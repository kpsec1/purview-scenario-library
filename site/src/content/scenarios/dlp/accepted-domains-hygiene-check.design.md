---
part: "design"
parent: "dlp/accepted-domains-hygiene-check"
---
## 1. Problem statement

`scenarios/dspm-for-ai/copilot-external-email-block/reviews.md` (Red Team finding 1) established
that the tenant's Exchange **accepted domains** configuration is the actual trust boundary behind
every DLP condition built on `FromScope`/`ExceptIfFromScope` (`UserScopeFrom`) — not just that one
scenario's rule. `PROGRESS.md` tracked the compensating control as a follow-up: *"an accepted-domains
hygiene check script that cross-references `Get-AcceptedDomain` against a known-partner-domains
allowlist and flags any legitimate partner domain missing accepted-domain status ... or, in the other
direction, any newly-added accepted domain that doesn't match a known-partner-domains allowlist."*
This scenario is that follow-up, built as a standalone, general-purpose control rather than bolted
onto any one DLP scenario — it protects every scenario in this repo (and any DLP/Conditional
Access/Copilot rule outside it) that relies on the internal/external sender or domain distinction.

## 2. Why "is the domain in `Get-AcceptedDomain`" is the wrong check

A naive hygiene check would just diff the set of domain names in `Get-AcceptedDomain` output against
an allowlist. That's insufficient, because accepted-domain status alone does not determine which side
of the `FromScope`/`UserScopeFrom` trust boundary a domain falls on — **`DomainType` does.** Confirmed
directly from Microsoft's `Set-AcceptedDomain`/`New-AcceptedDomain` references (fetched this build):

| `DomainType` | Microsoft's definition (verbatim) | Counts as "in organization" for `FromScope`? |
|---|---|---|
| `Authoritative` (default) | "Your organization is completely responsible for delivering email to recipients in the domain." | Yes |
| `InternalRelay` | Messages are relayed to a system "still under the authority of your company or IT department." | Yes — still your organization's own infrastructure |
| `ExternalRelay` | Messages are relayed to a system "outside your organization, which you don't control." | No — Microsoft's own accepted-domain type definition places this outside organizational control despite the domain being "accepted" |

A domain's mere presence in `Get-AcceptedDomain` therefore does **not** guarantee it's treated as
internal by every `FromScope`-consuming rule — a domain configured `ExternalRelay` is accepted (mail
for it is routed) but is, by Microsoft's own definition, not under the organization's control. This
scenario's checks are built around `DomainType`, not domain presence alone, closing the gap the
original Red Team finding actually pointed at.

**A genuinely new finding this build's grounding pass surfaced, not previously disclosed anywhere in
this repo:** `ExternalRelay` is **on-premises Exchange only**. Microsoft's `Set-AcceptedDomain`
reference states this explicitly: *"ExternalRelay: This is a type of non-authoritative domain that's
available only in on-premises Exchange organizations."* A pure Exchange Online tenant (the default
assumption for every other scenario in this repo — see `docs/automation-surface.md` §1) can never
have an `ExternalRelay` accepted domain; only `Authoritative` and `InternalRelay` are reachable there.
Practically, this means:
- For a pure-cloud tenant, **every** accepted domain counts as "in organization" for `FromScope`
  purposes — the `ExternalRelay`-is-external nuance `copilot-external-email-block/design.md` §4
  describes (citing the general `UserScopeFrom` predicate model) is a real mechanism, but not one a
  pure-cloud buyer's accepted-domains list can actually exercise.
- For a **hybrid** tenant (on-premises Exchange + Exchange Online, e.g. via Exchange Hybrid
  Configuration Wizard), an on-premises-configured `ExternalRelay` domain is a separate on-premises
  Active Directory object — this script, which authenticates to Exchange Online only (`Connect-
  ExchangeOnline`, `docs/automation-surface.md` §1), does not see it and cannot check it. Flagged as a
  scope boundary in §7 (non-goals) and `README.md` §11, not silently assumed away.
- If this script's live `Get-AcceptedDomain` call ever *does* observe `DomainType = ExternalRelay`
  against a cloud tenant, that is independently surprising per Microsoft's own documented scope for
  the value and is reported as a dedicated `[INFO]`-level finding worth investigating (hybrid
  Exchange Online/on-premises coexistence quirks are the most likely explanation), not silently
  merged into the ordinary "internal" bucket.

A follow-up to backport this `ExternalRelay`-is-on-premises-only correction into
`copilot-external-email-block/design.md` §4 (which currently states the general `UserScopeFrom`
mechanism without this cloud-vs-on-premises qualifier) is tracked in `PROGRESS.md` rather than made
here, per `AGENTS.md` §6's one-fragment-per-turn discipline — that scenario's own files are out of
scope for this fragment.

## 3. Two-directional hygiene model

Matching the original Red Team finding's own framing, this scenario checks in both directions:

1. **False-positive-exclusion risk** — a domain the buyer expects to be treated as internal (listed
   in the known-domains config with `required: true`) is missing from `Get-AcceptedDomain`, or present
   but with a `DomainType` that doesn't match what the buyer configured as expected. A legitimate
   partner or subsidiary domain in this state is silently treated as external by every
   `FromScope`-consuming rule — `copilot-external-email-block`'s Rule 3 among them — with no error
   surfaced anywhere in Purview.
2. **Silent-bypass risk** — a domain appears in `Get-AcceptedDomain` with a trust-conferring
   `DomainType` (`Authoritative`/`InternalRelay`) that is **not** in the known-domains config at all.
   Whether caused by a misconfiguration, an unreviewed change, or (the Red Team framing this follow-up
   was scoped from) an attacker who has gained enough access to add an accepted domain, this state
   grants that domain "internal" trust for every `FromScope`-consuming rule in the tenant without any
   review having happened. This is the higher-severity direction — see `reviews.md`.

## 4. Baseline/drift model, not a one-shot allowlist diff

A single allowlist-diff run only tells the buyer today's state, not whether something *changed*.
This scenario borrows the trend-log pattern already established by `scenarios/data-estate-insights/
classification-coverage-report` (`design.md` §5 there): each run writes a timestamped snapshot to a
JSON baseline file, and every run after the first diffs the **current** `Get-AcceptedDomain` output
against the **previous run's recorded snapshot** (not just against the static known-domains config) to
surface `Added`/`Removed`/`DomainTypeChanged`/`DefaultChanged` events since the last check — the
concrete "newly-added accepted domain" signal the original Red Team finding asked for. The static
known-domains config remains the source of truth for whether a given state is *expected*; the baseline
file is what makes a *change* to that state detectable and dated, not just a compliant-or-not snapshot.

Idempotency: like `classification-coverage-report`, each run is identified by a `-RunId` (default:
current UTC date). Re-running for the same `RunId` replaces that `RunId`'s rows in the drift log
rather than duplicating them; the baseline file itself always holds only the most recent snapshot
(overwritten each successful run, not appended), since only the most recent prior state is needed to
compute the next run's diff.

## 5. Audit-log attribution — a real, disclosed limit

The original Red Team finding's "newly-added accepted domain" framing implies an admin can find out
*who* added it and *when*. This build's grounding pass found that attribution is only partially
achievable from Exchange Online PowerShell:

- **`Set-AcceptedDomain`** (changing `DomainType`, `Default`, `MatchSubDomains`, etc. on an *existing*
  accepted domain) is available in Exchange Online (Microsoft's applicability statement: *"This
  cmdlet is available in on-premises Exchange and in the cloud-based service"*) and is a Set- cmdlet
  of the kind Exchange Online's unified admin audit logging generally records under `RecordType
  ExchangeAdmin`, `Operations` matching the cmdlet name (`docs/rbac-model.md` §6's own established
  pattern for Exchange admin actions). This script's `-IncludeAuditAttribution` switch queries
  `Search-UnifiedAuditLog -RecordType ExchangeAdmin -Operations 'Set-AcceptedDomain'` for this reason.
  **VERIFY (pilot tenant):** no Microsoft-published worked example independently confirms
  `Set-AcceptedDomain` specifically appears under this `RecordType`/`Operations` pair (as opposed to
  being logged at all, which is the general documented default) — flagged in `README.md` §11 and the
  script's own `.NOTES` rather than assumed.
- **`New-AcceptedDomain`/`Remove-AcceptedDomain`** — the two cmdlets that would add or remove a domain
  outright — are **on-premises Exchange only** per Microsoft's own applicability statements on both
  reference pages (fetched directly this build). **Exchange Online has no cmdlet for adding or
  removing an accepted domain at all** — a cloud tenant's accepted domains are managed exclusively
  through the Microsoft 365 admin center's domain-verification/removal flow (adding a custom domain,
  or removing one). This means an `Added`/`Removed` event this script's baseline diff detects (§4)
  **cannot** be attributed via `ExchangeAdmin`-RecordType `Search-UnifiedAuditLog` queries — there is
  no `New-AcceptedDomain`/`Remove-AcceptedDomain` Exchange admin event to find in a cloud tenant,
  because the underlying action never went through Exchange PowerShell.
- The more likely attribution source for an added/removed domain is Microsoft Entra ID's own directory
  audit activities — `Add verified domain`/`Remove verified domain`/`Add unverified domain`/`Remove
  unverified domain` (category `DirectoryManagement`, confirmed present in Microsoft's audit-activity
  reference, fetched this build). **VERIFY (pilot tenant or a future Microsoft Learn pass):** whether
  these specific activity names surface through `Search-UnifiedAuditLog -RecordType
  AzureActiveDirectory` with an `Operations` value that matches verbatim (Entra audit's own portal
  typically shows a human-readable "Activity" column that is not always identical to the
  `Search-UnifiedAuditLog Operations` string for the same underlying event) — this build's grounding
  pass confirmed the activity names exist in Microsoft's Entra audit-activity reference, but found no
  worked `Search-UnifiedAuditLog` example querying them by name. Not built into this script's
  `-IncludeAuditAttribution` switch for that reason; documented as a known gap in `README.md` §11
  rather than guessed at.

**Net effect, stated plainly for a buyer:** this script reliably **detects** that a domain was added,
removed, or had its `DomainType`/`Default` changed (§4's baseline diff, which needs no audit log at
all — it's a direct state comparison). It can **sometimes attribute** a `DomainType`/`Default` change
to an admin and timestamp via the Exchange admin audit trail (VERIFY above). It **cannot currently**
attribute a domain addition or removal to a specific admin action from this script alone — that
requires a separate Entra ID directory-audit query this build could not fully ground, tracked as a
follow-up in `PROGRESS.md`.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Module placement | `scenarios/dlp/` | The control exists to protect `FromScope`-consuming DLP rules (Exchange, Teams, Copilot); cross-linked from `copilot-external-email-block/README.md`'s originating Red Team finding rather than nested under `dspm-for-ai`, since the risk applies to any `FromScope` rule in the tenant, not just the Copilot one. |
| Deploy-script shape | A read-only reporting/checking script (`Export-AcceptedDomainsHygieneReport.ps1`), not a policy-deploying script | Same archetype as `scenarios/data-estate-insights/classification-coverage-report` — this scenario creates no Purview or Exchange object; its only side effect is the files it writes. `rollback.md` follows that scenario's "nothing to undo in the tenant" model. |
| Trust boundary rule | `DomainType` (`Authoritative`/`InternalRelay` = in-organization; `ExternalRelay` = not, and unreachable on a pure-cloud tenant per §2) | Directly grounded in Microsoft's own accepted-domain-type definitions, not an assumption. |
| Known-domains source of truth | A buyer-edited JSON config (`deploy/KnownDomains.sample.json`), not an attempt to auto-derive "expected" domains from any Purview/Exchange signal | No Microsoft-documented source distinguishes a "reviewed and approved" partner domain from any other accepted domain — this has to be a human-curated list, the same limitation any allowlist-based hygiene control has. |
| Baseline storage | A single JSON file, overwritten each run (not a history) | Only the immediately-prior state is needed to compute drift; the separate drift log (CSV, replace-by-RunId) is the historical record — see §4. |
| Audit attribution | Best-effort, `-IncludeAuditAttribution` opt-in switch, `ExchangeAdmin` `Set-AcceptedDomain` only | The honest subset of §5's findings this script can grounded-ly implement; domain add/remove attribution is disclosed as unbuilt, not guessed at. |

## 7. Non-goals

- Does not manage, create, or remove any accepted domain, DLP rule, or any other Purview/Exchange
  object — purely a read-only detection control. See `rollback.md`.
- Does not check on-premises Exchange accepted domains in a hybrid deployment — this script
  authenticates to Exchange Online only (§2). **Built as a companion scenario, not in this fragment:**
  `scenarios/dlp/accepted-domains-hygiene-check-on-premises/`, which reuses this scenario's own
  `KnownDomains.json` and baseline file rather than duplicating them (that scenario's `design.md`
  §3/§7 explains why the two run as separate live sessions, not one combined script).
- Does not attempt to attribute a domain **addition or removal** to a specific admin action — see
  §5's disclosed gap.
- Does not replace `copilot-external-email-block`'s own `README.md` §3 prerequisite that the
  accepted-domains list be correctly configured before that scenario is deployed — this scenario is
  the ongoing, post-deployment monitoring control for that same prerequisite, not a one-time gate.
- Does not evaluate DNS-level domain ownership/verification status (SPF/DKIM/DMARC, domain
  verification TXT records) — strictly an `Get-AcceptedDomain`-object-model check.

## 8. References

Full citation list with URLs: `README.md` §12.
