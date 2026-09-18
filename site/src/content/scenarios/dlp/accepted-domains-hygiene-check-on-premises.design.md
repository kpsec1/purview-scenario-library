---
part: "design"
parent: "dlp/accepted-domains-hygiene-check-on-premises"
---
## 1. Problem statement

`scenarios/dlp/accepted-domains-hygiene-check/design.md` §7 (Non-goals) disclosed a scope boundary
rather than silently assuming it away: that scenario authenticates to Exchange Online only
(`Connect-ExchangeOnline`), so a **hybrid** Exchange Online/on-premises tenant's on-premises accepted
domains, including the only place `DomainType ExternalRelay` is actually reachable (that scenario's
`design.md` §2), are entirely invisible to it. `PROGRESS.md` tracked this as a follow-up: *"Consider
an on-premises Exchange companion check for `accepted-domains-hygiene-check`, for a hybrid Exchange
Online/on-premises tenant whose on-premises accepted domains ... are invisible to the current
Exchange-Online-only script."* This scenario is that companion, a second, independent hygiene check
that runs the parent's same detection model against an **on-premises Exchange Management Shell**
session instead of Exchange Online PowerShell.

This is a companion, not a replacement: a hybrid buyer runs both scenarios, one against each
environment. See §3 for why they cannot safely run as one combined live session.

## 2. What's actually different on-premises (grounded this build)

Every cmdlet this scenario calls was independently re-verified against Microsoft's own reference
pages during this build (fetched via the canonical `MicrosoftDocs/office-docs-powershell` GitHub
source that Microsoft Learn itself renders from, and cited at `learn.microsoft.com` URLs throughout, 
`learn.microsoft.com` itself was unreachable from this build's network egress policy). Three concrete
differences from the parent scenario's Exchange Online-only model:

1. **`Get-AcceptedDomain` is the same cmdlet, same object shape, on both sides.** Applicable to
   Exchange Server 2010/2013/2016/2019/SE **and** Exchange Online (confirmed verbatim from Microsoft's
   reference page). The `-DomainController` parameter is on-premises-only (specifies which Active
   Directory domain controller to read from/write to, not supported on Edge Transport servers), this
   scenario's deploy script exposes it as an optional passthrough, since a multi-DC on-premises
   environment with AD replication lag is a realistic buyer scenario the cloud-only parent never needs
   to consider.
2. **`New-AcceptedDomain`/`Remove-AcceptedDomain` exist on-premises, closing part of the parent
   scenario's disclosed attribution gap.** The parent's `design.md` §5 states Exchange Online has *no*
   cmdlet to add or remove an accepted domain (confirmed: both cmdlets are on-premises-Exchange-only
   per their own applicability statements), so a domain-addition/removal event can never be attributed
   there via Exchange admin auditing. On-premises Exchange **does** have both cmdlets, meaning an
   on-premises admin audit trail genuinely *can* attribute a domain add/remove to a specific action, a
   capability the cloud side structurally lacks. §5 below builds this in.
3. **The on-premises audit-log surface is a different cmdlet with a different retention model, not
   `Search-UnifiedAuditLog`.** `Search-UnifiedAuditLog` (`docs/automation-surface.md` Surface 1) is an
   Exchange Online/Microsoft 365 unified-audit-log capability the parent scenario queries. On-premises
   Exchange has its own, older **administrator audit logging** feature (`Search-AdminAuditLog`,
   applicable to Exchange Server 2010-2019/SE only, confirmed **not** listed as applicable to Exchange
   Online on its own reference page, which separately confirms it is superseded there by unified audit
   logging). Key facts grounded this build via `Set-AdminAuditLogConfig`'s own reference page:
   - `-AdminAuditLogEnabled` defaults to `$true`, administrator audit logging is on by default on a
     fresh on-premises install, not an opt-in the buyer must remember to enable.
   - `-AdminAuditLogAgeLimit` defaults to **90 days**, sets this scenario's practical audit-lookback
     ceiling; a `-AuditLookbackDays` value beyond 90 will find nothing regardless of what actually
     happened, unless the buyer has widened this on their own server.
   - **VERIFY (pilot tenant or a future Microsoft Learn pass):** the exact *default* value of
     `-AdminAuditLogCmdlets` (which cmdlets are audited out of the box) was not stated with a
     confirmed default on the reference page this build fetched, only that `*` audits everything and
     that the parameter has no default explicitly documented in the fetched content. This scenario
     does **not** assume `Set-`/`New-`/`Remove-AcceptedDomain` are covered by a fresh install's default
     configuration; `README.md` §11 and the deploy script's `.NOTES` tell the buyer to confirm
     `Get-AdminAuditLogConfig | Select-Object AdminAuditLogCmdlets` includes them (or `*`) before
     relying on `-IncludeAuditAttribution`'s output for an incident investigation.

## 3. Why this is a separate live session, not one combined script

Both `Connect-ExchangeOnline` (parent scenario) and the on-premises remote-PowerShell pattern this
scenario uses (§4) work by **importing proxy functions for remote cmdlets into the caller's local
session**, `Connect-ExchangeOnline` does this implicitly; the on-premises pattern uses
`Import-PSSession` explicitly. Both import a cmdlet literally named `Get-AcceptedDomain`. Grounded
directly from Microsoft's own `Import-PSSession` reference this build: *"When you import commands
that have the same names as commands in the current session, the imported commands can hide ...
cmdlets in the session"*, whichever import runs second silently wins the unqualified `Get-AcceptedDomain`
name, and there is no way to safely tell which environment a bare `Get-AcceptedDomain` call in a mixed
script actually reached without extra bookkeeping. Microsoft's own mitigation for this exact class of
conflict is the `Import-PSSession -Prefix` parameter, confirmed from the same reference page, which
renames every imported command's noun (e.g. `-Prefix OnPrem` turns `Get-AcceptedDomain` into
`Get-OnPremAcceptedDomain`).

**Decision:** this scenario's deploy script never establishes its own connection (same author-only
pattern as the parent, `README.md` §5) and is written to call the bare `Get-AcceptedDomain`/
`Search-AdminAuditLog` names, the caller is expected to run it in a session where **only** the
on-premises remote session has been imported (optionally via `Import-PSSession ... -Prefix OnPrem` if
the same session also needs the cloud parent's cmdlets side by side, in which case the caller renames
this script's own calls accordingly, documented, not silently assumed, in `README.md` §5). The two
scenarios' deploy scripts are never run as literally one combined script for this reason; §4's optional
cross-environment reconciliation reads the cloud parent's **already-written baseline file** instead of
holding a second live connection open, sidestepping the conflict entirely rather than working around it
with prefixes by default.

## 4. Cross-environment reconciliation, the actual hybrid-specific risk

Running the parent's checks twice, independently, in two environments is useful on its own (each
environment gets its own drift/baseline detection) but doesn't answer the question a hybrid buyer
actually cares about: **did the two sides go out of sync with each other without anyone noticing?**
A domain hand-configured differently on each side of a hybrid deployment is exactly the kind of
divergence neither side's own independent check can see.

**Decision:** an optional `-CloudBaselinePath` parameter on this scenario's deploy script, pointing at
the parent scenario's own `-BaselinePath` output file (a plain JSON read, no live cloud connection, 
§3). When supplied, the script adds a fourth check category, `CrossEnvironmentMismatch`: a domain
present in both the live on-premises state and the cloud baseline snapshot, with different `DomainType`
values, where neither side's type is `ExternalRelay` (expected to differ, `ExternalRelay` is
on-premises-only by definition, §2, so its mere presence on-premises with no cloud counterpart is not
itself a mismatch). Severity follows the parent's own trust-boundary-move rule (`design.md` §2 of the
parent scenario): `FAIL` if the two sides disagree on which side of the in-organization trust boundary
the domain falls on, `WARN` if both sides are in-organization types that simply differ
(`Authoritative` vs. `InternalRelay`).

**Re-grounded in a later build, resolved, not still open.** The original build could not reach
`learn.microsoft.com` at all and relied on community/Microsoft Q&A guidance alone. A later build's
`WebSearch` pass (direct `WebFetch` to `learn.microsoft.com` was blocked again in that build's
environment, the same recurring egress restriction, not a one-off) returned result summaries citing
three authoritative Microsoft Learn **conceptual** pages by name and URL rather than secondary
blogs/Q&A threads, and they resolve the question:

- **"Accepted domains" (`exchange/mail-flow/accepted-domains/accepted-domains`)**, defines
  `InternalRelay` precisely as the shared-namespace case: *"Some of the recipients in the internal
  relay domain don't exist in the Exchange organization,"* citing as its own worked examples sharing
  the domain "between the Exchange organization and a third-party messaging system" or "between
  Exchange organizations in different Active Directory forests", a hybrid Exchange
  Online/on-premises coexistence deployment is exactly this shape (two separate directories/mail
  systems sharing one SMTP namespace while migration is in progress).
- **"Manage accepted domains in Exchange Online"
  (`exchange/mail-flow-best-practices/manage-accepted-domains/manage-accepted-domains`)**, states
  the shared-namespace procedure directly: create the accepted domain "with the type set to Internal
  Relay," and for an in-progress migration, *"confirm that the accepted domain remains configured as
  internal relay rather than authoritative because if the organization is authoritative for a domain,
  unknown recipients will not be forwarded,"* which would cause mail loops/NDRs for the
  not-yet-migrated recipients.
- **"Use Directory-Based Edge Blocking..."
  (`exchange/mail-flow-best-practices/use-directory-based-edge-blocking`)**, confirms the
  `Authoritative`+DBEB combination the original community guidance described is a **different,
  later** state than an active hybrid-coexistence domain: DBEB requires `Authoritative`, but *"until
  all valid recipients have been added to Exchange Online and replicated,"* the domain "should be
  left configured as Internal relay." A domain only becomes a good `Authoritative`+DBEB candidate
  once migration is complete (or, for a domain fully cut over to Exchange Online, once on-premises no
  longer holds any live recipients for it), not while it's still an active coexistence domain with
  Remote Mailbox objects on both sides.

**Extended in a later build to cover `MatchSubDomains` and `Default`, not just `DomainType`** (closing
the non-goal §9 originally deferred, once a concrete buyer need surfaced as a `PROGRESS.md`
follow-up). Two new finding categories, `CrossEnvironmentMatchSubDomainsMismatch` and
`CrossEnvironmentDefaultMismatch`, deliberately **separate categories**, not additional rows under the
existing `CrossEnvironmentMismatch` name, mirroring this scenario's own baseline-diff block (§6), which
already uses three distinct per-field categories (`DomainTypeChangedSincePreviousRun`/
`DefaultChangedSincePreviousRun`/`MatchSubDomainsChangedSincePreviousRun`) rather than one overloaded
category, for the identical structural reason: the drift-log CSV's uniqueness key is
`(RunId, Category, DomainName)`, and a domain that diverges on two fields in the same run needs two
distinct rows to stay unique under that key. **This is not a hypothetical concern**, the first draft of
this extension used a single shared `CrossEnvironmentMismatch` category for all three fields, and this
build's own functional test (a mocked-`Get-AcceptedDomain` run with a domain deliberately diverging on
both `MatchSubDomains` and `Default`) caught the resulting `(RunId, Category, DomainName)` collision as
a `[FAIL]` in `validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`'s existing duplicate-row check
before the design shipped, the three-category split was adopted specifically to fix that, not chosen
speculatively.

Same `ExternalRelay` exclusion as the `DomainType` check applies to both new checks (a domain that's
`ExternalRelay` on either side is skipped entirely). Severity rules, grounded against
`Set-AcceptedDomain`'s reference page (fetched directly from the canonical MicrosoftDocs GitHub source
in this build, `README.md` §12):
- **`MatchSubDomains`** ("enables mail to be sent by and received from users on any subdomain of this
  accepted domain," default `$false`): `FAIL` if either side has it `$true`, one environment silently
  accepting mail for every subdomain while the other does not is a real asymmetric attack surface (an
  attacker-registered subdomain is in-organization mail on one side only), the same severity logic the
  same-environment `MatchSubDomainsChangedSincePreviousRun` check already applies (§6) to a `$true`
  value on an in-organization domain.
- **`Default`** ("specifies whether the accepted domain is the default domain," via `-MakeDefault`, 
  Microsoft's reference does not explicitly state only one domain can hold this flag per organization,
  though the surrounding documentation implies a singular default): always `WARN`, never `FAIL`. Each
  environment computes and enforces its own default accepted domain independently, a hybrid deployment
  is two separate organizations sharing a namespace, not one organization with one default, so a
  difference here is expected, unreviewed drift, not a trust-boundary violation the way `DomainType`/
  `MatchSubDomains` divergence is.

**Conclusion:** the parent scenario's `deploy/KnownDomains.sample.json` sample entry, 
`hybrid.contoso.com` as `expectedDomainType: InternalRelay`, labeled "on-premises Exchange hybrid
coexistence domain", is correct as written, precisely because it models an *active coexistence*
domain, not a fully-migrated one. The original community guidance about `Authoritative`+DBEB was not
wrong, it describes a domain in a different migration state than the sample's own label already says
it's in. No code or sample change was needed; the ambiguity was in this design doc's framing of the
open question, not in the sample. `CrossEnvironmentMismatch` findings on an
`Authoritative`-vs-`InternalRelay` split remain `WARN`, not `FAIL` (both are in-organization types),
because a live tenant could legitimately be mid-migration on one side and not the other, but the
default expectation for an still-coexisting shared-namespace domain is now `InternalRelay` on both
sides, not an open question. `README.md` §11/§12 record the citations; re-verify against a live
`learn.microsoft.com` fetch before a customer-facing deployment, since this build's grounding was
`WebSearch`-summary-only, not a direct primary-source page fetch (§1/§12).

## 5. Audit attribution, a real improvement over the parent's disclosed gap

The parent scenario's `-IncludeAuditAttribution` switch cannot attribute a domain
Added/Removed event at all (Exchange Online has no cmdlet for the underlying action, parent
`design.md` §5). On-premises, `New-AcceptedDomain`/`Remove-AcceptedDomain` **are** real, auditable
cmdlets (§2), so this scenario's own `-IncludeAuditAttribution` switch queries
`Search-AdminAuditLog -Cmdlets 'Set-AcceptedDomain','New-AcceptedDomain','Remove-AcceptedDomain'`, 
all three, not just `Set-`. This is a genuine capability gap the on-premises side closes relative to
cloud, stated as such rather than treated as a routine mirror of the parent's switch. The 90-day
default retention ceiling (§2) and the unconfirmed default `-AdminAuditLogCmdlets` coverage (§2,
VERIFY) are the two honest limits carried forward.

## 6. Baseline/drift model, same shape, separate files, same idempotency rule

Reuses the parent's baseline/drift-log/`-RunId` idempotency model verbatim (parent `design.md` §4), 
same JSON baseline shape, same replace-by-`RunId` CSV drift log, but against entirely separate output
files (`-BaselinePath`/`-DriftLogPath` point at on-premises-specific paths the caller chooses; never
the parent's own files, which the optional `-CloudBaselinePath` in §4 only *reads*, never writes to).
Keeping the two environments' baselines as separate files, never merged into one, is deliberate: an
on-premises run must never overwrite or be blocked by the cloud run's own baseline, and the two
scenarios can be scheduled entirely independently (different cadences, different operators, even
different owning teams) without file contention.

## 7. Known-domains config reuse, not duplication

This scenario reads the **same** `KnownDomains.json` file/schema the parent scenario uses (parent
`README.md` §6), not a second, on-premises-specific config. A domain's "reviewed and expected" status
is a property of the buyer's actual business relationship with that domain, not of which Exchange
environment happens to host its mailboxes; maintaining two separate known-domains files for the same
tenant would immediately drift against each other, the exact failure mode this whole control exists to
catch. The existing `expectedDomainType` field already supports all three `DomainType` values
including `ExternalRelay` (parent `README.md` §6), so no schema change was needed to reuse it as-is.

## 8. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Module placement | `scenarios/dlp/`, sibling to the parent scenario | Same control family, same module, extends rather than duplicates, matches this repo's established sibling-scenario pattern (e.g. `defender-device-control-usb-allowlist` → `-macos` → `-macos-jamf`). |
| Connection surface | On-premises Exchange Management Shell via remote PowerShell (`New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://<ServerFQDN>/PowerShell/ -Authentication Kerberos`), **not** one of `docs/automation-surface.md`'s five surfaces | That doc's five surfaces are deliberately all-cloud (§1 there); on-premises Exchange Management Shell is a sixth, narrower connection method this one scenario needs and documents itself rather than widening that cross-cutting doc's scope for a single-scenario need. |
| Live combined session | Not supported by default (§3) | Real PowerShell proxy-function name collision between two remoting-imported `Get-AcceptedDomain` cmdlets; sidestepped via separate processes/sessions plus an optional file-based cross-check (§4), not a runtime guard this script could not itself enforce. |
| Cross-environment check | Optional `-CloudBaselinePath`, reads the parent's last-written baseline file only | Answers the hybrid-specific "did the two sides diverge" question without a second live connection (§3, §4). |
| Cross-environment check scope | `DomainType`, `MatchSubDomains`, `Default`, three fields, three separate finding categories | §4, mirrors the baseline-diff block's own per-field category pattern (§6) and avoids a `(RunId, Category, DomainName)` collision when a domain diverges on more than one field in the same run, a real bug this build's own functional test caught in a single-category draft. |
| Known-domains config | Reused verbatim from the parent, no schema change | §7, a domain's reviewed status isn't environment-specific. |
| Audit attribution | `Search-AdminAuditLog`, all three of `Set-`/`New-`/`Remove-AcceptedDomain` | §5, a real capability the parent structurally cannot offer for `New-`/`Remove-`. |
| `DomainController` passthrough | Optional `-DomainControllerFqdn` parameter | An on-premises-only concern (multi-DC replication lag) the cloud-only parent never faces (§2). |

## 9. Non-goals

- Does not establish its own remote PowerShell session, the caller runs `New-PSSession`/
  `Import-PSSession` first (§3, `README.md` §5), the same author-only pattern the parent scenario uses
  for `Connect-ExchangeOnline`.
- Does not attempt to run simultaneously with the parent scenario's live cloud session in one process
  by default, §3.
- Does not resolve the open `hybrid.contoso.com` `InternalRelay`-vs-`Authoritative` sample-config
  question (§4), tracked as a `PROGRESS.md` follow-up, not guessed at here.
- Does not manage, create, or remove any accepted domain, DLP rule, or any other Exchange/Purview
  object, purely a read-only detection control, same as the parent (`rollback.md`).
- **Resolved (later build), no longer a non-goal:** cross-environment reconciliation of `MatchSubDomains`/
  `Default`, once a concrete buyer need surfaced as a `PROGRESS.md` follow-up, see §4 for the design
  and §8 for the key decision. Kept here as a record of the original scoping call, per this repo's
  incremental-scoping discipline.

## 10. References

Full citation list with URLs: `README.md` §12.
