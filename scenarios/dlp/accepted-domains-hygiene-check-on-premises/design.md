# Design — On-Premises Accepted-Domains Hygiene Check (Hybrid Companion)

## 1. Problem statement

`scenarios/dlp/accepted-domains-hygiene-check/design.md` §7 (Non-goals) disclosed a scope boundary
rather than silently assuming it away: that scenario authenticates to Exchange Online only
(`Connect-ExchangeOnline`), so a **hybrid** Exchange Online/on-premises tenant's on-premises accepted
domains — including the only place `DomainType ExternalRelay` is actually reachable (that scenario's
`design.md` §2) — are entirely invisible to it. `PROGRESS.md` tracked this as a follow-up: *"Consider
an on-premises Exchange companion check for `accepted-domains-hygiene-check`, for a hybrid Exchange
Online/on-premises tenant whose on-premises accepted domains ... are invisible to the current
Exchange-Online-only script."* This scenario is that companion — a second, independent hygiene check
that runs the parent's same detection model against an **on-premises Exchange Management Shell**
session instead of Exchange Online PowerShell.

This is a companion, not a replacement: a hybrid buyer runs both scenarios, one against each
environment. See §3 for why they cannot safely run as one combined live session.

## 2. What's actually different on-premises (grounded this build)

Every cmdlet this scenario calls was independently re-verified against Microsoft's own reference
pages during this build (fetched via the canonical `MicrosoftDocs/office-docs-powershell` GitHub
source that Microsoft Learn itself renders from, and cited at `learn.microsoft.com` URLs throughout —
`learn.microsoft.com` itself was unreachable from this build's network egress policy). Three concrete
differences from the parent scenario's Exchange Online-only model:

1. **`Get-AcceptedDomain` is the same cmdlet, same object shape, on both sides.** Applicable to
   Exchange Server 2010/2013/2016/2019/SE **and** Exchange Online (confirmed verbatim from Microsoft's
   reference page). The `-DomainController` parameter is on-premises-only (specifies which Active
   Directory domain controller to read from/write to — not supported on Edge Transport servers) — this
   scenario's deploy script exposes it as an optional passthrough, since a multi-DC on-premises
   environment with AD replication lag is a realistic buyer scenario the cloud-only parent never needs
   to consider.
2. **`New-AcceptedDomain`/`Remove-AcceptedDomain` exist on-premises — closing part of the parent
   scenario's disclosed attribution gap.** The parent's `design.md` §5 states Exchange Online has *no*
   cmdlet to add or remove an accepted domain (confirmed: both cmdlets are on-premises-Exchange-only
   per their own applicability statements), so a domain-addition/removal event can never be attributed
   there via Exchange admin auditing. On-premises Exchange **does** have both cmdlets — meaning an
   on-premises admin audit trail genuinely *can* attribute a domain add/remove to a specific action, a
   capability the cloud side structurally lacks. §5 below builds this in.
3. **The on-premises audit-log surface is a different cmdlet with a different retention model, not
   `Search-UnifiedAuditLog`.** `Search-UnifiedAuditLog` (`docs/automation-surface.md` Surface 1) is an
   Exchange Online/Microsoft 365 unified-audit-log capability the parent scenario queries. On-premises
   Exchange has its own, older **administrator audit logging** feature (`Search-AdminAuditLog`,
   applicable to Exchange Server 2010–2019/SE only — confirmed **not** listed as applicable to Exchange
   Online on its own reference page, which separately confirms it is superseded there by unified audit
   logging). Key facts grounded this build via `Set-AdminAuditLogConfig`'s own reference page:
   - `-AdminAuditLogEnabled` defaults to `$true` — administrator audit logging is on by default on a
     fresh on-premises install, not an opt-in the buyer must remember to enable.
   - `-AdminAuditLogAgeLimit` defaults to **90 days** — sets this scenario's practical audit-lookback
     ceiling; a `-AuditLookbackDays` value beyond 90 will find nothing regardless of what actually
     happened, unless the buyer has widened this on their own server.
   - **VERIFY (pilot tenant or a future Microsoft Learn pass):** the exact *default* value of
     `-AdminAuditLogCmdlets` (which cmdlets are audited out of the box) was not stated with a
     confirmed default on the reference page this build fetched — only that `*` audits everything and
     that the parameter has no default explicitly documented in the fetched content. This scenario
     does **not** assume `Set-`/`New-`/`Remove-AcceptedDomain` are covered by a fresh install's default
     configuration; `README.md` §11 and the deploy script's `.NOTES` tell the buyer to confirm
     `Get-AdminAuditLogConfig | Select-Object AdminAuditLogCmdlets` includes them (or `*`) before
     relying on `-IncludeAuditAttribution`'s output for an incident investigation.

## 3. Why this is a separate live session, not one combined script

Both `Connect-ExchangeOnline` (parent scenario) and the on-premises remote-PowerShell pattern this
scenario uses (§4) work by **importing proxy functions for remote cmdlets into the caller's local
session** — `Connect-ExchangeOnline` does this implicitly; the on-premises pattern uses
`Import-PSSession` explicitly. Both import a cmdlet literally named `Get-AcceptedDomain`. Grounded
directly from Microsoft's own `Import-PSSession` reference this build: *"When you import commands
that have the same names as commands in the current session, the imported commands can hide ...
cmdlets in the session"* — whichever import runs second silently wins the unqualified `Get-AcceptedDomain`
name, and there is no way to safely tell which environment a bare `Get-AcceptedDomain` call in a mixed
script actually reached without extra bookkeeping. Microsoft's own mitigation for this exact class of
conflict is the `Import-PSSession -Prefix` parameter — confirmed from the same reference page — which
renames every imported command's noun (e.g. `-Prefix OnPrem` turns `Get-AcceptedDomain` into
`Get-OnPremAcceptedDomain`).

**Decision:** this scenario's deploy script never establishes its own connection (same author-only
pattern as the parent, `README.md` §5) and is written to call the bare `Get-AcceptedDomain`/
`Search-AdminAuditLog` names — the caller is expected to run it in a session where **only** the
on-premises remote session has been imported (optionally via `Import-PSSession ... -Prefix OnPrem` if
the same session also needs the cloud parent's cmdlets side by side, in which case the caller renames
this script's own calls accordingly — documented, not silently assumed, in `README.md` §5). The two
scenarios' deploy scripts are never run as literally one combined script for this reason; §4's optional
cross-environment reconciliation reads the cloud parent's **already-written baseline file** instead of
holding a second live connection open, sidestepping the conflict entirely rather than working around it
with prefixes by default.

## 4. Cross-environment reconciliation — the actual hybrid-specific risk

Running the parent's checks twice, independently, in two environments is useful on its own (each
environment gets its own drift/baseline detection) but doesn't answer the question a hybrid buyer
actually cares about: **did the two sides go out of sync with each other without anyone noticing?**
A domain hand-configured differently on each side of a hybrid deployment is exactly the kind of
divergence neither side's own independent check can see.

**Decision:** an optional `-CloudBaselinePath` parameter on this scenario's deploy script, pointing at
the parent scenario's own `-BaselinePath` output file (a plain JSON read, no live cloud connection —
§3). When supplied, the script adds a fourth check category, `CrossEnvironmentMismatch`: a domain
present in both the live on-premises state and the cloud baseline snapshot, with different `DomainType`
values, where neither side's type is `ExternalRelay` (expected to differ — `ExternalRelay` is
on-premises-only by definition, §2, so its mere presence on-premises with no cloud counterpart is not
itself a mismatch). Severity follows the parent's own trust-boundary-move rule (`design.md` §2 of the
parent scenario): `FAIL` if the two sides disagree on which side of the in-organization trust boundary
the domain falls on, `WARN` if both sides are in-organization types that simply differ
(`Authoritative` vs. `InternalRelay`).

**A genuinely open design question this build could not resolve with a single correct answer:**
Microsoft's own guidance on which `DomainType` a **shared-namespace** hybrid domain (one with Remote
Mailbox objects representing cloud-hosted recipients) should carry **differs by scenario** — community
and Microsoft Q&A guidance found this build (not an authoritative Microsoft Learn conceptual page,
which was unreachable — `learn.microsoft.com` blocked, §1) indicates a shared-namespace domain with
Remote Mailbox objects present is commonly left `Authoritative` on **both** sides to support Directory
Based Edge Blocking, while `InternalRelay` remains appropriate specifically when not all recipients for
that domain are known to one side (e.g. a domain still mid-migration). This directly contradicts the
parent scenario's own `deploy/KnownDomains.sample.json` sample entry, which models a
`hybrid.contoso.com` domain as `expectedDomainType: InternalRelay` "on-premises Exchange hybrid
coexistence domain" without this nuance. **This scenario does not resolve or silently correct that
sample** (a `PROGRESS.md` follow-up tracks reviewing it against a primary, authoritative Microsoft
Learn source once `learn.microsoft.com` is reachable, or a pilot tenant, rather than guessing which of
several plausible hybrid topologies the sample was meant to represent) — but it does mean
`CrossEnvironmentMismatch` findings must not be read as automatically wrong. A `WARN` (not `FAIL`) on
an `Authoritative`-vs-`InternalRelay` split is the deliberately conservative choice: both are
in-organization, and which one is "correct" for a given domain depends on that domain's actual
migration/coexistence state, which only the buyer's own change-management record (the known-domains
config's `owner` field) can settle. `README.md` §11 states this plainly.

## 5. Audit attribution — a real improvement over the parent's disclosed gap

The parent scenario's `-IncludeAuditAttribution` switch cannot attribute a domain
Added/Removed event at all (Exchange Online has no cmdlet for the underlying action — parent
`design.md` §5). On-premises, `New-AcceptedDomain`/`Remove-AcceptedDomain` **are** real, auditable
cmdlets (§2), so this scenario's own `-IncludeAuditAttribution` switch queries
`Search-AdminAuditLog -Cmdlets 'Set-AcceptedDomain','New-AcceptedDomain','Remove-AcceptedDomain'` —
all three, not just `Set-`. This is a genuine capability gap the on-premises side closes relative to
cloud, stated as such rather than treated as a routine mirror of the parent's switch. The 90-day
default retention ceiling (§2) and the unconfirmed default `-AdminAuditLogCmdlets` coverage (§2,
VERIFY) are the two honest limits carried forward.

## 6. Baseline/drift model — same shape, separate files, same idempotency rule

Reuses the parent's baseline/drift-log/`-RunId` idempotency model verbatim (parent `design.md` §4) —
same JSON baseline shape, same replace-by-`RunId` CSV drift log — but against entirely separate output
files (`-BaselinePath`/`-DriftLogPath` point at on-premises-specific paths the caller chooses; never
the parent's own files, which the optional `-CloudBaselinePath` in §4 only *reads*, never writes to).
Keeping the two environments' baselines as separate files, never merged into one, is deliberate: an
on-premises run must never overwrite or be blocked by the cloud run's own baseline, and the two
scenarios can be scheduled entirely independently (different cadences, different operators, even
different owning teams) without file contention.

## 7. Known-domains config reuse, not duplication

This scenario reads the **same** `KnownDomains.json` file/schema the parent scenario uses (parent
`README.md` §6) — not a second, on-premises-specific config. A domain's "reviewed and expected" status
is a property of the buyer's actual business relationship with that domain, not of which Exchange
environment happens to host its mailboxes; maintaining two separate known-domains files for the same
tenant would immediately drift against each other, the exact failure mode this whole control exists to
catch. The existing `expectedDomainType` field already supports all three `DomainType` values
including `ExternalRelay` (parent `README.md` §6), so no schema change was needed to reuse it as-is.

## 8. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Module placement | `scenarios/dlp/`, sibling to the parent scenario | Same control family, same module, extends rather than duplicates — matches this repo's established sibling-scenario pattern (e.g. `defender-device-control-usb-allowlist` → `-macos` → `-macos-jamf`). |
| Connection surface | On-premises Exchange Management Shell via remote PowerShell (`New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://<ServerFQDN>/PowerShell/ -Authentication Kerberos`), **not** one of `docs/automation-surface.md`'s five surfaces | That doc's five surfaces are deliberately all-cloud (§1 there); on-premises Exchange Management Shell is a sixth, narrower connection method this one scenario needs and documents itself rather than widening that cross-cutting doc's scope for a single-scenario need. |
| Live combined session | Not supported by default (§3) | Real PowerShell proxy-function name collision between two remoting-imported `Get-AcceptedDomain` cmdlets; sidestepped via separate processes/sessions plus an optional file-based cross-check (§4), not a runtime guard this script could not itself enforce. |
| Cross-environment check | Optional `-CloudBaselinePath`, reads the parent's last-written baseline file only | Answers the hybrid-specific "did the two sides diverge" question without a second live connection (§3, §4). |
| Known-domains config | Reused verbatim from the parent, no schema change | §7 — a domain's reviewed status isn't environment-specific. |
| Audit attribution | `Search-AdminAuditLog`, all three of `Set-`/`New-`/`Remove-AcceptedDomain` | §5 — a real capability the parent structurally cannot offer for `New-`/`Remove-`. |
| `DomainController` passthrough | Optional `-DomainControllerFqdn` parameter | An on-premises-only concern (multi-DC replication lag) the cloud-only parent never faces (§2). |

## 9. Non-goals

- Does not establish its own remote PowerShell session — the caller runs `New-PSSession`/
  `Import-PSSession` first (§3, `README.md` §5), the same author-only pattern the parent scenario uses
  for `Connect-ExchangeOnline`.
- Does not attempt to run simultaneously with the parent scenario's live cloud session in one process
  by default — §3.
- Does not resolve the open `hybrid.contoso.com` `InternalRelay`-vs-`Authoritative` sample-config
  question (§4) — tracked as a `PROGRESS.md` follow-up, not guessed at here.
- Does not manage, create, or remove any accepted domain, DLP rule, or any other Exchange/Purview
  object — purely a read-only detection control, same as the parent (`rollback.md`).
- Does not attempt to reconcile `MatchSubDomains`/`Default` flags across environments — only
  `DomainType` (§4). A future follow-up could extend `CrossEnvironmentMismatch` to cover those fields
  too, once a concrete buyer need surfaces one (matching this repo's incremental-scoping discipline).

## 10. References

Full citation list with URLs: `README.md` §12.
