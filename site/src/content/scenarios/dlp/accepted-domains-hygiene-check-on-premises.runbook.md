---
part: "runbook"
parent: "dlp/accepted-domains-hygiene-check-on-premises"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. On the on-premises Exchange server (or a management workstation with the Exchange admin tools),
   open the Exchange admin center or run `Get-AcceptedDomain | Format-Table Name, DomainName,
   DomainType, Default` in the on-premises Exchange Management Shell to see the equivalent data this
   scenario automates.
2. Cross-reference each domain against the same `KnownDomains.json` review the parent scenario's implementation steps step 2 describes - this is one shared review process across both environments, not a separate on-premises-specific one.
3. There is no portal equivalent for this scenario's baseline-diff, unreviewed-trust, or
   cross-environment detection - those require the script path below.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect to the on-premises Exchange organization via remote PowerShell (the design notes Sec 3/8).
# Run this on a domain-joined machine with network line-of-sight to the CAS/Mailbox server.
$OnPremCred = Get-Credential
$OnPremSession = New-PSSession -ConfigurationName Microsoft.Exchange `
    -ConnectionUri "http://$OnPremServerFqdn/PowerShell/" -Authentication Kerberos -Credential $OnPremCred
Import-PSSession $OnPremSession -DisableNameChecking
# Do NOT also import a Connect-ExchangeOnline session into this same process unless you re-import
# one of the two with -Prefix (the design notes Sec 3) - both export a cmdlet named Get-AcceptedDomain.

# 2. Reuse the SAME known-domains config the parent scenario uses - do not create a second copy.
# (If you haven't set up the parent scenario yet, copy and edit its sample first - parent this page Sec 5.)

# 3. Dry run - reports every on-premises finding, writes nothing
./deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1 `
    -KnownDomainsConfigPath '../accepted-domains-hygiene-check/deploy/KnownDomains.json' `
    -BaselinePath './deploy/out/onprem-accepted-domains-baseline.json' `
    -DriftLogPath './deploy/out/onprem-accepted-domains-drift-log.csv' `
    -WhatIf

# 4. First real run - establishes the on-premises baseline
./deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1 `
    -KnownDomainsConfigPath '../accepted-domains-hygiene-check/deploy/KnownDomains.json' `
    -BaselinePath './deploy/out/onprem-accepted-domains-baseline.json' `
    -DriftLogPath './deploy/out/onprem-accepted-domains-drift-log.csv'

# 5. (Optional, recommended for a hybrid organization) Re-run with cross-environment reconciliation, once
# the parent scenario has produced at least one baseline of its own:
./deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1 `
    -KnownDomainsConfigPath '../accepted-domains-hygiene-check/deploy/KnownDomains.json' `
    -BaselinePath './deploy/out/onprem-accepted-domains-baseline.json' `
    -DriftLogPath './deploy/out/onprem-accepted-domains-drift-log.csv' `
    -CloudBaselinePath '../accepted-domains-hygiene-check/deploy/out/accepted-domains-baseline.json' `
    -IncludeAuditAttribution

# 6. Validate the report files (add -CloudBaselinePath to also verify CrossEnvironmentMismatch
# findings against a live comparison, once the cloud baseline exists)
./validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1 `
    -BaselinePath './deploy/out/onprem-accepted-domains-baseline.json' `
    -DriftLogPath './deploy/out/onprem-accepted-domains-drift-log.csv' `
    -KnownDomainsConfigPath '../accepted-domains-hygiene-check/deploy/KnownDomains.json' -CheckLive `
    -CloudBaselinePath '../accepted-domains-hygiene-check/deploy/out/accepted-domains-baseline.json'

# 7. Schedule step 4/5 on a recurring cadence, independently of the parent scenario's own schedule
# (the design notes Sec 6 - separate files, no contention). This scenario ships no scheduler-specific
# code; wire it into a Windows Task Scheduler task or Azure Automation hybrid runbook worker with
# network access to the on-premises server - see Sec 3's Kerberos/network-reachability note.
```

Every finding category, its severity model, and the baseline/drift mechanics are fully documented in
the design notes and the deploy script's own `.DESCRIPTION`/`.NOTES` blocks.

## Configuration reference

**`KnownDomains.json`** - same schema as the parent scenario (`../accepted-domains-hygiene-check/
the configuration reference); not repeated here. `expectedDomainType` already supports `ExternalRelay`, which is
fully reachable (and expected, the architecture and the known limitations) on the on-premises side.

**Finding categories** (deploy script's `Add-Finding` calls, the design notes):

| Category | Default severity | Meaning |
|---|---|---|
| `MissingExpectedDomain` | `FAIL` if `required: true`, else `WARN` | A known-domains entry is absent from on-premises `Get-AcceptedDomain`. |
| `DomainTypeMismatch` | `FAIL` if the trust boundary changes, else `WARN` | A known domain's live on-premises `DomainType` differs from `expectedDomainType`. |
| `UnexpectedTrustedDomain` | `FAIL` | An on-premises accepted domain with `DomainType` `Authoritative`/`InternalRelay` is not in the known-domains config. |
| `ExternalRelayObserved` | `INFO` (differs from the parent's `WARN` - expected here, the architecture) | Any on-premises accepted domain reports `DomainType ExternalRelay`. |
| `DomainAddedSincePreviousRun` | `FAIL` (trust-conferring type) or `WARN` | A domain present now but absent from the on-premises baseline. |
| `DomainRemovedSincePreviousRun` | `WARN` | A domain present in the on-premises baseline but absent now. |
| `DomainTypeChangedSincePreviousRun` | `WARN` | A domain's `DomainType` differs from the on-premises baseline. |
| `DefaultChangedSincePreviousRun` | `INFO` | The default-domain flag changed on this domain since the on-premises baseline. |
| `MatchSubDomainsChangedSincePreviousRun` | `FAIL` if flipped to `$true` on an in-organization domain, else `WARN` | A domain's `MatchSubDomains` flag changed since the on-premises baseline. |
| `CrossEnvironmentMismatch` (only with `-CloudBaselinePath`) | `FAIL` if the trust boundary disagrees between environments, else `WARN` | A domain's on-premises `DomainType` differs from the cloud baseline's recorded `DomainType` for the same domain, and neither is `ExternalRelay` - the design notes. |
| `CrossEnvironmentMatchSubDomainsMismatch` (only with `-CloudBaselinePath`) | `FAIL` if either side has `MatchSubDomains` `$true`, else `WARN` | A domain's on-premises `MatchSubDomains` differs from the cloud baseline's recorded value, and neither side's `DomainType` is `ExternalRelay` - the design notes. One environment silently accepting mail for every subdomain while the other does not is an asymmetric attack surface. |
| `CrossEnvironmentDefaultMismatch` (only with `-CloudBaselinePath`) | `WARN` | A domain's on-premises `Default` flag differs from the cloud baseline's recorded value, and neither side's `DomainType` is `ExternalRelay` - the design notes. Each environment computes its own default accepted domain independently in a hybrid deployment, so this is unreviewed drift, not automatically a misconfiguration. |

**Why three separate categories, not one `CrossEnvironmentMismatch` covering all three fields:** the
drift-log CSV's uniqueness key is `(RunId, Category, DomainName)` - the same replace-by-`RunId` model
the parent scenario uses. A domain that diverges on more than one field in the same run (e.g. both
`MatchSubDomains` and `Default`) needs one row per divergence, and one row per divergence needs a
distinct category to stay unique under that key - the same reason this scenario's own baseline-diff
block already uses three separate per-field categories (`DomainTypeChangedSincePreviousRun`/
`DefaultChangedSincePreviousRun`/`MatchSubDomainsChangedSincePreviousRun`) rather than one overloaded
`ChangedSincePreviousRun` category. Confirmed by this build's own functional test (the validation steps below), which
caught the row-collision this design avoids before it shipped.

Exit code: exits `1` if any `FAIL`-severity finding is present in the current run - same contract as
the parent scenario. `WARN`/`INFO`-only findings exit `0`.

## Operations and tuning

**Recommended cadence:** daily, run independently of the parent scenario's own schedule (the design notes - separate files, no contention risk). If both scenarios run daily, schedule the on-premises run
to complete before the cross-environment reconciliation step reads the cloud scenario's baseline, or
accept that `-CloudBaselinePath` may reflect the cloud side's *previous* day's state on some runs -
either is acceptable for a detective control at this cadence; state which convention your scheduler
uses in your own runbook documentation.

**KPIs to watch** (in addition to the parent scenario's own KPIs, operations and tuning there, which apply
independently to the on-premises side):
- **`CrossEnvironmentMismatch` count, trending to zero (or to a stable, understood, non-zero baseline
  for domains genuinely mid-migration).** This is this scenario's headline, hybrid-specific signal.
  Unlike the parent's `UnexpectedTrustedDomain`, a non-zero count here is not automatically an
  incident - triage against the known-domains config's `owner` field and the domain's actual
  migration state before escalating.
- **`CrossEnvironmentMatchSubDomainsMismatch` count, especially any `FAIL`-severity row, trending to
  zero.** A `FAIL` here means one environment accepts mail for every subdomain of the domain while the
  other does not - treat this with the same urgency as `UnexpectedTrustedDomain`, since it is an
  asymmetric attack surface, not merely stylistic drift.
- **`CrossEnvironmentDefaultMismatch` count** - lower urgency than the other two (always `WARN`), but
  worth a periodic review to confirm each side's default accepted domain is still the one the deploying organization
  intends new recipients' primary SMTP address to be generated against.
- **`UnexpectedTrustedDomain` count on the on-premises side, trending to zero** - same interpretation
  as the parent scenario, now covering the environment the parent cannot see.

**Incident-response runbook (`UnexpectedTrustedDomain`, `CrossEnvironmentMismatch`,
`CrossEnvironmentMatchSubDomainsMismatch`, or `CrossEnvironmentDefaultMismatch` finding):**
1. **Confirm intent** - same first step as the parent scenario's runbook (operations and tuning there).
2. **If legitimate** - add/correct the domain's entry in the shared `KnownDomains.json`, closing the
   finding on the next run of whichever scenario(s) it affects.
3. **If not legitimate, or intent cannot be confirmed, for an on-premises `UnexpectedTrustedDomain`
   finding** - run with `-IncludeAuditAttribution` (after confirming `-AdminAuditLogCmdlets` coverage,
   the known limitations) to attempt attribution via `Search-AdminAuditLog` - a real chance of success here, unlike the
   parent's equivalent finding. Escalate to the identity/security team.
4. **For a `CrossEnvironmentMismatch`/`CrossEnvironmentMatchSubDomainsMismatch` finding that turns out
   to be a genuine misconfiguration** - correct the disagreeing side's `DomainType`/`MatchSubDomains`
   via `Set-AcceptedDomain` on whichever environment is wrong, informed by the known-domains config's
   intended value; re-run both scenarios' deploy scripts to confirm the finding clears.
5. **For a `CrossEnvironmentDefaultMismatch` finding** - confirm with the messaging/identity team which
   domain each environment's default accepted domain is *supposed* to be; if one side is wrong, correct
   it with `Set-AcceptedDomain -MakeDefault $true` on the intended domain. VERIFY (pilot tenant, before
   assuming this is a one-step fix): Microsoft's own `-MakeDefault` reference states it "specifies
   whether the accepted domain is the default domain" but never states outright that setting it `$true`
   on one domain automatically clears the flag from whichever domain previously held it - confirm the
   old default domain's `Default` flag actually flips before treating the finding as closed.
6. **Document** - the on-premises findings JSON and drift-log CSV are the evidentiary record.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: this scenario creates no Exchange or
Purview object, so rollback is limited to closing the on-premises remote PowerShell session, stopping
the schedule, removing the automation identity's on-premises Exchange role assignment, and deciding
what to do with the already-produced report files - nothing tenant-side to undo, same archetype as
the parent scenario.

## References

1. Get-AcceptedDomain reference - on-premises (Exchange Server 2010/2013/2016/2019/SE) **and**
   Exchange Online applicability, `-DomainController` (on-premises-only parameter) -
   <https://learn.microsoft.com/powershell/module/exchangepowershell/get-accepteddomain>
2. New-AcceptedDomain reference - on-premises-only applicability, confirmed independently this build
   - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-accepteddomain>
3. Remove-AcceptedDomain reference - on-premises-only applicability -
   <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-accepteddomain>
4. Set-AcceptedDomain reference - `-DomainType` values and definitions (`ExternalRelay` "available
   only in on-premises Exchange organizations"); also `-MatchSubDomains` ("enables mail to be sent by
   and received from users on any subdomain of this accepted domain," default `$false`) and
   `-MakeDefault` ("specifies whether the accepted domain is the default domain") - the two fields the
   `CrossEnvironmentMatchSubDomainsMismatch`/`CrossEnvironmentDefaultMismatch` checks reconcile
   across environments, fetched directly from the canonical MicrosoftDocs GitHub source in the later
   build that added those two checks - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-accepteddomain>
5. Search-AdminAuditLog reference - applicable to Exchange Server 2010/2013/2016/2019/SE only (not
   listed for Exchange Online, which uses `Search-UnifiedAuditLog` instead), `-Cmdlets`,
   `-StartDate`/`-EndDate` parameters - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-adminauditlog>
6. Set-AdminAuditLogConfig reference - `-AdminAuditLogEnabled` default `$true`,
   `-AdminAuditLogAgeLimit` default 90 days, `-AdminAuditLogCmdlets` default `None` (confirmed
   2026-09-27, the known limitations) -
   <https://learn.microsoft.com/powershell/module/exchangepowershell/set-adminauditlogconfig>
7. Administrator audit log structure reference - `Caller`, `CmdletName`, `Succeeded`,
   `ObjectModified`, `RunDate` output properties this scenario's findings JSON surfaces -
   <https://learn.microsoft.com/exchange/policy-and-compliance/admin-audit-logging/admin-audit-logging>
8. Connect to Exchange servers using remote PowerShell - the `New-PSSession -ConfigurationName
   Microsoft.Exchange -ConnectionUri http://<ServerFQDN>/PowerShell/ -Authentication Kerberos` /
   `Import-PSSession` pattern this scenario's Prerequisites and Step-by-step sections use verbatim,
   including the documented reason the URI uses `http` not `https` (Kerberos-encrypted payload) -
   <https://learn.microsoft.com/powershell/exchange/connect-to-exchange-servers-using-remote-powershell>
9. Import-PSSession reference - the documented command-name-collision behavior and `-Prefix`
   mitigation this scenario's the prerequisites and the known limitations and the design notes are built around -
   <https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/import-pssession>
10. *Accepted-Domains Hygiene Check* - the parent scenario this fragment is a
    companion to; shares its `KnownDomains.json` config and baseline/drift-log/idempotency model.
11. [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - the five all-cloud automation surfaces this scenario's
    on-premises connection method deliberately sits outside of.
12. Accepted domains (conceptual) - defines `InternalRelay` as the shared-namespace case (domain
    shared with a third-party system, or between Exchange organizations in different AD forests) -
    <https://learn.microsoft.com/exchange/mail-flow/accepted-domains/accepted-domains>
13. Manage accepted domains in Exchange Online - the shared-namespace `InternalRelay` procedure and
    the "remains configured as internal relay rather than authoritative" migration guidance -
    <https://learn.microsoft.com/exchange/mail-flow-best-practices/manage-accepted-domains/manage-accepted-domains>
14. Use Directory-Based Edge Blocking to reject messages sent to invalid recipients - confirms
    `Authoritative`+DBEB is reached only after all recipients are added to Exchange Online and
    replicated, resolving the design notes's now-closed open question -
    <https://learn.microsoft.com/exchange/mail-flow-best-practices/use-directory-based-edge-blocking>

> **Grounding note for this fragment:** `learn.microsoft.com` was unreachable from this build's
> network egress policy. Every citation above was independently verified this build via the
> canonical `MicrosoftDocs` GitHub source repositories that Microsoft Learn itself renders from
> (`office-docs-powershell`, `OfficeDocs-Exchange`) rather than a search-engine summary alone, except
> references 12-14, added in a later build once the original hybrid `Authoritative`-vs-`InternalRelay`
> open question (previously sourced from secondary community/Q&A content only) was resolved via
> `WebSearch` result summaries citing those three Microsoft Learn conceptual pages by name and URL -
> direct `WebFetch` to `learn.microsoft.com` was blocked again in that build's environment, the same
> recurring restriction, not a one-off. Re-verify all citations against live `learn.microsoft.com`
> pages before a customer-facing deployment.