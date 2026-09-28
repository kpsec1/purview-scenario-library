---
part: "runbook"
parent: "dlp/accepted-domains-hygiene-check"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the Exchange admin center (`admin.exchange.microsoft.com`) → **Mail flow** → **Accepted
   domains**, or run `Get-AcceptedDomain | Format-Table Name, DomainName, DomainType, Default` in
   Exchange Online PowerShell to see the equivalent data this scenario automates.
2. For each accepted domain shown, confirm with the domain's business owner whether it's expected and
   correctly typed (`Authoritative` for a domain your organization fully owns mail delivery for,
   `InternalRelay` for a domain still under your organization's authority but relayed elsewhere - see
   the design notes). Record the outcome - this manual review is exactly what the configuration reference's `KnownDomains.json`
   config formalizes and makes repeatable.
3. There is no portal equivalent for this scenario's baseline-diff or unreviewed-trust detection -
   those require the script path below.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only, Exchange Online PowerShell - see docs/automation-surface.md Sec 3)
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Copy and edit the known-domains config for your tenant
Copy-Item ./deploy/KnownDomains.sample.json ./deploy/KnownDomains.json
# ... edit ./deploy/KnownDomains.json with your reviewed domains and their expected DomainType ...

# 3. Dry run - reports every finding, writes nothing
./deploy/Export-AcceptedDomainsHygieneReport.ps1 `
    -KnownDomainsConfigPath ./deploy/KnownDomains.json `
    -BaselinePath ./deploy/out/accepted-domains-baseline.json `
    -DriftLogPath ./deploy/out/accepted-domains-drift-log.csv `
    -WhatIf

# 4. First real run - establishes the baseline (no Added/Removed/Changed drift is possible yet)
./deploy/Export-AcceptedDomainsHygieneReport.ps1 `
    -KnownDomainsConfigPath ./deploy/KnownDomains.json `
    -BaselinePath ./deploy/out/accepted-domains-baseline.json `
    -DriftLogPath ./deploy/out/accepted-domains-drift-log.csv

# 5. Validate the report files
./validate/Test-AcceptedDomainsHygieneReport.ps1 `
    -BaselinePath ./deploy/out/accepted-domains-baseline.json `
    -DriftLogPath ./deploy/out/accepted-domains-drift-log.csv `
    -KnownDomainsConfigPath ./deploy/KnownDomains.json -CheckLive

# 6. Schedule step 4 to run on a recurring cadence (daily recommended - see Sec 8).
#    This scenario ships no scheduler-specific code; wire it into your own Azure Automation
#    runbook, Azure Function timer trigger, or equivalent (docs/automation-surface.md Sec 6).
```

Every finding category, its severity model, and the baseline/drift mechanics are fully documented in
the design notes and the deploy script's own `.DESCRIPTION`/`.NOTES` blocks.

## Configuration reference

**`KnownDomains.json` schema** (`deploy/KnownDomains.sample.json`):

| Field | Type | Meaning |
|---|---|---|
| `domainName` | string | The accepted-domain name to check, exactly as it appears in `Get-AcceptedDomain`'s `DomainName`. |
| `expectedDomainType` | string | One of `Authoritative`, `InternalRelay`, `ExternalRelay` - what this domain's `DomainType` is expected to be. |
| `required` | bool | `true` if this domain's absence from `Get-AcceptedDomain` should be a `FAIL`-severity finding; `false` for a `WARN`-severity one (e.g. a domain that's expected but not yet business-critical). |
| `owner` | string | Free-text business owner/justification, surfaced in finding details for triage - not validated by the script. |

**Finding categories** (deploy script's `Add-Finding` calls, the design notes):

| Category | Default severity | Meaning |
|---|---|---|
| `MissingExpectedDomain` | `FAIL` if `required: true`, else `WARN` | A known-domains entry is absent from live `Get-AcceptedDomain`. |
| `DomainTypeMismatch` | `FAIL` if the trust boundary changes, else `WARN` | A known domain's live `DomainType` differs from `expectedDomainType`. |
| `UnexpectedTrustedDomain` | `FAIL` | A live accepted domain with `DomainType` `Authoritative`/`InternalRelay` is not in the known-domains config at all. |
| `ExternalRelayObserved` | `WARN` | Any live accepted domain reports `DomainType ExternalRelay` - surprising on a cloud-only tenant, see the known limitations. |
| `DomainAddedSincePreviousRun` | `FAIL` (trust-conferring type) or `WARN` | A domain present now but absent from the last-recorded baseline. |
| `DomainRemovedSincePreviousRun` | `WARN` | A domain present in the last-recorded baseline but absent now. |
| `DomainTypeChangedSincePreviousRun` | `WARN` | A domain's `DomainType` differs from the last-recorded baseline. |
| `DefaultChangedSincePreviousRun` | `INFO` | The tenant's default-domain flag changed on this domain since the last baseline. |
| `MatchSubDomainsChangedSincePreviousRun` | `FAIL` if flipped to `$true` on an in-organization domain, else `WARN` | A domain's `MatchSubDomains` flag changed since the last baseline. A flip to `$true` silently extends in-organization trust to every subdomain of that domain for `FromScope`-consuming rules, independent of any `DomainType` change - see the known limitations. |

Exit code: `deploy/Export-AcceptedDomainsHygieneReport.ps1` exits `1` if any `FAIL`-severity finding is
present in the current run (`MissingExpectedDomain`/`DomainTypeMismatch`/`UnexpectedTrustedDomain`/
`DomainAddedSincePreviousRun` can each reach `FAIL`) - safe to wire directly into a scheduled job's own
failure/alerting path. `WARN`/`INFO`-only findings exit `0`.

## Operations and tuning

**Recommended cadence:** daily. Accepted-domains changes are infrequent, deliberate administrative
actions in a healthy tenant - a daily run gives same-day detection without meaningful cost. `RunId`
defaults to the current UTC date, so a daily schedule naturally produces one row per finding per day
in the drift log with no duplicate-row risk from an occasional re-run on the same day. This is a
**detective**, not preventive, control - a domain added between scheduled runs holds unreviewed trust
for up to one full cadence interval before this scenario surfaces it. A higher-assurance environment
(e.g. one already running *Copilot External Email Block* in production `Enable` mode) should shorten
the interval - pass an explicit `-RunId` (e.g. an hourly timestamp instead of the UTC-date default) on
a sub-daily schedule; the replace-by-RunId idempotency model supports any cadence,
not just daily, as long as `-RunId` is set to match it.

**KPIs to watch:**
- **`UnexpectedTrustedDomain` count, trending to zero.** This is the control's headline signal - every
  occurrence means a domain currently holds in-organization trust for every `FromScope`-consuming rule
  in the tenant with no reviewed record. Triage each one: either add it to `KnownDomains.json` (if
  legitimate, after review) or investigate how it was added (see the known limitations's audit-attribution limits).
- **`MissingExpectedDomain` with `required: true`, trending to zero.** Each occurrence is a live gap in
  a `FromScope`-consuming rule's intended coverage - a partner or subsidiary being treated as external
  when it shouldn't be.
- **`DomainAddedSincePreviousRun`/`DomainRemovedSincePreviousRun` volume, as a change-frequency
  baseline.** A sudden spike deserves the same scrutiny any unusual configuration-change volume does.

**Review cadence:** any `FAIL`-severity finding should be triaged same-day, given the daily recommended
run cadence - this is a same-day-actionable signal, not a periodic report to batch-review.

**Incident-response runbook (`UnexpectedTrustedDomain` finding):**
1. **Confirm intent** - check with the domain's likely business owner (a recent partner onboarding, a
   new subsidiary) before assuming malice; most occurrences are legitimate changes missing from
   `KnownDomains.json`, not an attack.
2. **If legitimate** - add the domain to `KnownDomains.json` with the correct `expectedDomainType` and
   an `owner` note, closing the finding on the next run.
3. **If not legitimate or intent cannot be confirmed** - this is a credential-compromise or
   insider-action indicator. Attempt attribution via `-IncludeAuditAttribution` (covers `DomainType`/
   `Default` changes on an already-accepted domain only - see the known limitations's limit on attributing the
   domain-addition event itself) and, for the actual addition/removal event, the **Microsoft Entra
   audit log** directly (Entra admin center or Graph `auditLogs/directoryAudits`) filtered to the
   `DirectoryManagement` category's `Add verified domain`/`Add unverified domain`/`Remove verified
   domain`/`Remove unverified domain` activities - **not** `Search-UnifiedAuditLog`, which does not
   expose those events. Escalate to the identity/security team; consider revoking
   recently-issued admin credentials with domain-management rights pending investigation.
4. **Document** - the findings JSON and drift-log CSV are the evidentiary record for both directions of
   this workflow.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: this scenario creates no Exchange or
Purview object, so rollback is limited to stopping the schedule, removing the automation identity's
Exchange Online role assignment, and deciding what to do with the already-produced report files -
nothing tenant-side to undo.

## References

1. Get-AcceptedDomain reference - full parameter syntax (`-Identity`, `-DomainController`,
   `-ResultSize`; no `-DomainType` filter parameter exists, it is an output-object property only) -
   <https://learn.microsoft.com/powershell/module/exchangepowershell/get-accepteddomain>
2. Set-AcceptedDomain reference - `-DomainType` parameter and its three valid values with Microsoft's
   own verbatim definitions (Authoritative/InternalRelay/ExternalRelay), the explicit statement that
   `ExternalRelay` is "available only in on-premises Exchange organizations," `-MatchSubDomains`,
   `-MakeDefault`, `-AddressBookEnabled`, cloud/on-premises applicability statement ("available in
   on-premises Exchange and in the cloud-based service") - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-accepteddomain>
3. New-AcceptedDomain reference - `-DomainType` definitions (independent phrasing corroborating
   source 2) and the explicit "This cmdlet is available only in on-premises Exchange" applicability
   statement - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-accepteddomain>
4. Remove-AcceptedDomain reference - confirms this cmdlet is also on-premises-Exchange-only, the
   basis for the known limitations's "no cloud cmdlet to add or remove an accepted domain" finding - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-accepteddomain>
5. Data loss prevention Exchange conditions and actions reference - confirms the portal condition
   "Sender scope" maps to the PowerShell condition `FromScope`/`ExceptIfFromScope`, property type
   `UserScopeFrom` - the trust-boundary mechanism this entire scenario protects - <https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions>
6. Search-UnifiedAuditLog reference (`-RecordType`, `-Operations`, `-StartDate`/`-EndDate` parameters
   used by `-IncludeAuditAttribution`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
6a. Audit log activities reference (Microsoft Purview), "Exchange admin activities" section - the
    verbatim default-logging rule (all Exchange Online PowerShell changes except `Get-`/`Search-`/
    `Test-`-prefixed cmdlets and unnamed internal Microsoft-maintenance cmdlets) `Set-AcceptedDomain`
    is measured against to close the known limitations audit-attribution VERIFY - <https://learn.microsoft.com/purview/audit-log-activities#exchange-admin-activities>
7. Audit activity reference (Microsoft Entra ID) - confirms `Add verified domain`/`Remove verified
   domain`/`Add unverified domain`/`Remove unverified domain`/`Update domain` exist as named
   `DirectoryManagement`-category audit activities in the **Microsoft Entra audit log** specifically
   (not the Microsoft 365 unified audit log - see source 9) - <https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities>
8. *Copilot External Email Block* - the originating scenario whose Red Team
   review (the review notes, finding 1) scoped this follow-up.
9. Audit log activities reference (Microsoft Purview) - "Directory administration activities" table
   confirms the Microsoft 365 unified audit log's actual `RecordType AzureActiveDirectory`
   `Operations` strings for domain events (`Add domain to company.`/`Remove domain from
   company.`/`Verify domain.`), independently different from and not a superset of source 7's
   Entra-native activity names - the basis for the known limitations's confirmed (not guessed) conclusion that those
   names aren't `Search-UnifiedAuditLog`-queryable - <https://learn.microsoft.com/purview/audit-log-activities#directory-administration-activities>
8. *Copilot External Email Block* - the originating scenario whose Red Team
   review (the review notes, finding 1) scoped this follow-up.
9. *Exportable, Historical Classification Coverage Report* - the sibling read-only reporting
   scenario this fragment's baseline/drift-log/idempotency model and the rollback runbook structure follow.
10. [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap) - Exchange Online RBAC dependency, and section 14's citation convention this
    scenario's the prerequisites follows.

> Verify current cmdlet availability (especially the on-premises-vs-cloud applicability statements in
> sources 2-4, which are load-bearing for this scenario's entire design) against current Microsoft
> Learn before a customer-facing deployment.