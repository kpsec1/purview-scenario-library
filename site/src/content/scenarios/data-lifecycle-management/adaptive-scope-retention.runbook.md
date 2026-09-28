---
part: "runbook"
parent: "data-lifecycle-management/adaptive-scope-retention"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-AdaptiveScope / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json -DryRun

# 2. Deploy the scope + policy + rule
./deploy/New-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json

# 3. Validate (structure now; allow up to 5 days before membership/distribution are meaningful)
./validate/Test-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json
```

### Portal reference

The scope is visible under **Settings** > **Roles and scopes** > **Adaptive scopes**; the policy
under **Data Lifecycle Management** > **Policies** > **Retention policies**. The portal's create-policy flow also lets you pick which
locations an adaptive-scope policy covers on a **Choose adaptive policy scopes and locations**
page - the PowerShell path used here does not expose an equivalent parameter. `-WhatIf` is non-functional in S&C PowerShell, so the deploy/remove scripts
ship a `-DryRun` instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scope cmdlet | `New-AdaptiveScope` | Adaptive scope |
| `LocationType` | `User` | Also `Group` (M365 Groups) or `Site` (SharePoint); each supports different attributes |
| `FilterConditions` | Hashtable: `Conditions` (`Name`/`Operator`/`Value`) + `Conjunction` | Simple-query-builder shape; `Operator`: `Equals`/`NotEquals`/`StartsWith`/`NotStartsWith`. `-RawQuery` (OPATH for User/Group, KeyQL for Site) is the advanced-query alternative - not used by default |
| Policy cmdlet | `New-RetentionCompliancePolicy -AdaptiveScopeLocation` | AdaptiveScopeLocation parameter set - no separate `-ExchangeLocation`/`-OneDriveLocation` toggles |
| Rule cmdlet | `New-RetentionComplianceRule` | `-RetentionDuration`/`-RetentionComplianceAction`/`-ExpirationDateOption`, no `-ApplyComplianceTag` (this is a plain retention rule, not a label) |
| `RetentionComplianceAction` | `Keep` | `Keep` / `Delete` / `KeepAndDelete` |
| `RetentionDuration` | `3650` (~10 years) | Illustrative litigation-readiness baseline; tune to your obligation |
| `ExpirationDateOption` | `CreationAgeInDays` | When the clock starts |
| Adaptive scope population | Up to **5 days** | Daily query re-evaluation; changes aren't immediate |
| Membership inspection | `Get-AdaptiveScopeMembers -Identity <scope> -State Added` | Paged; don't use `-PageResultSize Unlimited` on large scopes |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** policy **DistributionStatus**; adaptive scope member count over time (via the
portal's Scope details export, or `Get-AdaptiveScopeMembers`); count of `Title` values that don't
map cleanly to "executive" (a data-quality signal upstream in Entra/HR, not a Purview problem).
**Tuning:** review the `Title` value list periodically - job-title strings drift (new titles,
localized variants) and a scope query that isn't updated silently under-covers the intended
population; this is the adaptive-scope equivalent of "the distribution list went stale," just
quieter. Widening the query (`StartsWith` instead of exact `Equals`, or adding synonyms) trades
precision for recall - validate before widening.

**Change management:** the scope's query and the policy's retention settings are both
version-controlled in the config file - treat any change the same as any other retention-object
change: deliberate, reviewed, and re-deployed rather than edited ad hoc in the portal.

**Audit signal for scope tampering:** the unified audit log records
adaptive-scope and retention-policy configuration changes as distinct, named operations -
`NewAdaptiveScope`, `SetAdaptiveScope` ("Administrator changed the description or query for an
existing adaptive scope"), `RemoveAdaptiveScope`, and `ApplicableAdaptiveScopeChange` ("Users,
sites, or groups were added to or removed from the adaptive scope... Because the changes are
system-initiated, the reported user displays as a GUID rather than a user account"), alongside
`NewRetentionCompliancePolicy`/`SetRetentionCompliancePolicy`/`RemoveRetentionCompliancePolicy`
and the matching `*RetentionComplianceRule` operations. Alert on
`SetAdaptiveScope` against this scenario's scope name outside a known change window - a query
edit is the mechanism by which someone could narrow coverage (see the Red Team review finding
2). `Search-UnifiedAuditLog -Operations SetAdaptiveScope,RemoveAdaptiveScope` (add
`-UserIds`/date range as needed) surfaces these; the exact `RecordType` value to pre-filter the
same query is not asserted here - VERIFY against `Search-UnifiedAuditLog`'s supported record
types before building a saved query, rather than guessing one.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-AdaptiveScopeRetention.ps1` **disables** the
policy by default (stops new/changed content from being retained); `-Delete` removes the
policy+rule and - because this is `Keep`-only, not a record - genuinely **releases** the retention
already in force; `-Delete -TryRemoveScope` also attempts to remove the
adaptive scope itself, but only if nothing else references it (adaptive scopes are shared,
reusable objects across retention, Insider Risk Management, and Communication Compliance policies).

## References

1. Learn about retention policies and retention labels - adaptive-scope "executives" example - <https://learn.microsoft.com/purview/retention#adaptive-or-static-policy-scopes-for-retention>
2. Adaptive scopes - up to 5 days for queries to populate/reflect changes - <https://learn.microsoft.com/purview/purview-adaptive-scopes#how-to-configure-an-adaptive-scope>
3. Microsoft Purview service description - Data Lifecycle Management adaptive scopes/auto-apply licensing (E5/IP&G) - this library's [Licensing matrix](/docs/licensing-matrix/), grounded from <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
4. Adaptive scopes - scope types and supported attributes/properties table - <https://learn.microsoft.com/purview/purview-adaptive-scopes#configure-adaptive-scopes>
5. Adaptive scopes - portal location (Settings > Roles and scopes > Adaptive scopes) - <https://learn.microsoft.com/purview/purview-adaptive-scopes#how-to-configure-an-adaptive-scope>
6. Create and configure retention policies - adaptive policy scope/location selection in the portal - <https://learn.microsoft.com/purview/create-retention-policies#create-and-configure-a-retention-policy>
7. New-AdaptiveScope (-Name/-LocationType/-FilterConditions/-RawQuery) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-adaptivescope>
8. New-RetentionCompliancePolicy (AdaptiveScopeLocation parameter set) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
9. New-RetentionComplianceRule (-RetentionDuration/-RetentionComplianceAction/-ExpirationDateOption) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
10. Get-AdaptiveScopeMembers (-Identity/-State/-PageResultSize; paging, don't use Unlimited on large scopes; result-metadata property names `TotalMemberCount`/`CurrentPageMemberCount`/`IsLastPage`/`Watermark` confirmed in the page's own worked paging examples) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-adaptivescopemembers>
11. Adaptive scopes - validating advanced queries via PowerShell (Get-Recipient/Get-Mailbox/Get-User with -Filter) - <https://learn.microsoft.com/purview/purview-adaptive-scopes#to-run-a-query-by-using-powershell>
12. Remove-RetentionComplianceRule ("causes the release of all Exchange mailbox and SharePoint site retentions that are associated with the rule") - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancerule>
13. Learn about retention policies and retention labels - Skype for Business / Exchange public folders don't support adaptive scopes - <https://learn.microsoft.com/purview/retention#adaptive-or-static-policy-scopes-for-retention>
14. Audit log activities - retention policy and retention label activities, incl. `SetAdaptiveScope`/`ApplicableAdaptiveScopeChange`/`NewAdaptiveScope`/`RemoveAdaptiveScope` - <https://learn.microsoft.com/purview/audit-log-activities#retention-policy-and-retention-label-activities>

> Re-verify all links, cmdlet parameters, and licensing against current Microsoft Learn before a
> customer-facing deployment - the AdaptiveScopeLocation location-granularity gap in particular
> should be confirmed in a pilot tenant, not assumed.