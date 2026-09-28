---
part: "runbook"
parent: "data-lifecycle-management/adaptive-scope-auto-apply-label"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-AdaptiveScope / New-ComplianceTag / New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json -DryRun

# 2. Deploy the scope + label + policy + rule (after lab test + Records/Legal sign-off)
./deploy/New-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json

# 3. Validate (structure now; allow up to 5+7 days before coverage is meaningful)
./validate/Test-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json
```

### Portal reference

The scope is visible under **Settings** > **Roles and scopes** > **Adaptive scopes**; the label under
**Records Management** (or **Data Lifecycle Management**) > **File plan**; the policy under **Label
policies**. The portal's create-label-policy flow lets you
select an adaptive scope directly on its own **Choose adaptive policy scopes and locations** step, the
same documented flow the Keep-only sibling's page cites for plain retention policies
 - the PowerShell path used here does not expose an equivalent narrower-location
parameter. `-WhatIf` is non-functional in S&C PowerShell, so the deploy/remove
scripts ship a `-DryRun` instead.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Scope cmdlet | `New-AdaptiveScope` | Same shape as the Keep-only sibling; reused by name if it already exists |
| Label cmdlet | `New-ComplianceTag` | `-RetentionAction Keep -RetentionDuration 3650 -RetentionType CreationAgeInDays -IsRecordLabel $true` |
| `Regulatory` | `$false` (default) | `$true` creates the label but skips policy/rule creation entirely - auto-apply doesn't support regulatory records |
| Policy cmdlet | `New-RetentionCompliancePolicy -AdaptiveScopeLocation` | Same `AdaptiveScopeLocation` parameter set as the Keep-only sibling - no separate `-ExchangeLocation`/`-OneDriveLocation` toggle |
| Rule cmdlet | `New-RetentionComplianceRule -Policy -ApplyComplianceTag [-ContentMatchQuery]` | `ComplianceTag` parameter set - **no `-Name`** (documented mutually exclusive with `-ApplyComplianceTag`; why this matters, the design notes) |
| `ContentMatchQuery` | Empty by default | This scenario targets purely by adaptive scope (population), not a content signal - unlike the financial-records sibling |
| Adaptive scope population | Up to **5 days** | Daily query re-evaluation |
| Auto-apply distribution | Up to **7 days** | Backend batch process, independent of the scope's own delay |
| Membership inspection | `Get-AdaptiveScopeMembers -Identity <scope> -State Added` | Paged; don't use `-PageResultSize Unlimited` on large scopes |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** policy **DistributionStatus**; adaptive scope member count over time
(`Get-AdaptiveScopeMembers` or the portal's Scope details export); count of items labeled over time
(content search, or Data Lifecycle/Records Management reports); count of `Title` values that don't
map cleanly to "executive" (an upstream HR/Entra data-quality signal, same as the Keep-only sibling).
**Tuning:** review the `Title` value list periodically - the consequence of a stale query is now
record-strength, not just retention-strength, so treat this review as higher-priority than the
Keep-only sibling's equivalent task. Keep the auto-apply targeting scope-only (no content query) or,
if you add one, keep it narrow - precision matters more than recall once matches get locked as
records.

**Change management:** the scope's query, the label's settings, and the policy/rule are all
version-controlled in the config file - treat any change as deliberate and reviewed, never edited ad
hoc in the portal, and route label/policy changes through Records/Legal given the record-strength
consequence.

**Audit signal for scope or policy tampering:** the unified audit log
records adaptive-scope changes (`NewAdaptiveScope`, `SetAdaptiveScope`, `RemoveAdaptiveScope`,
`ApplicableAdaptiveScopeChange`) and retention-policy/rule changes
(`NewRetentionCompliancePolicy`/`SetRetentionCompliancePolicy`/`RemoveRetentionCompliancePolicy` and
the matching `*RetentionComplianceRule` operations) as distinct, named operations, the same set the
Keep-only sibling's page operations and tuning cites. Alert on `SetAdaptiveScope` against this
scenario's scope name outside a known change window - the same detection this scenario's scope-sharing design makes doubly important, since a tampered query now affects **two** scenarios' worth of
coverage (Keep-only retention and record-strength labeling) if both are deployed. The exact
`RecordType` value to pre-filter the same `Search-UnifiedAuditLog` query is not asserted here - VERIFY
before building a saved query, rather than guessing one, same disclosure as the Keep-only sibling.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1` **disables** the
policy by default (stops new content from being auto-labeled); `-Delete` removes the policy+rule
(future auto-apply stops; content already labeled as a record is **unchanged** - this is the key
difference from the Keep-only sibling, whose rollback genuinely releases retention);
`-Delete -TryRemoveScope` also attempts to remove the adaptive scope, but only if nothing else
references it (including the Keep-only sibling, if both share this scope name in your tenant). The
label definition and any already-labeled content are never touched by this script - unlocking or
removing an applied record label is a deliberate records-manager action, out of scope here.

## References

1. Declare records by using retention labels (record vs. regulatory record; removal requires records-manager privilege for a record, impossible for anyone for a regulatory record) - <https://learn.microsoft.com/purview/declare-records>
2. Automatically apply a retention label to retain or delete content (adaptive scopes explicitly documented as a supported, recommended input to a retention label policy; up to 7-day auto-apply latency; "isn't supported for regulatory records... require a published retention label policy") - <https://learn.microsoft.com/purview/apply-retention-labels-automatically>
3. Adaptive scopes - configuration, attributes, and up to 5-day population delay - <https://learn.microsoft.com/purview/purview-adaptive-scopes>
4. Adaptive scopes - portal location (Settings > Roles and scopes > Adaptive scopes) - <https://learn.microsoft.com/purview/purview-adaptive-scopes#how-to-configure-an-adaptive-scope>
5. Get started with records management in Microsoft 365 (File plan / Label policies portal location) - <https://learn.microsoft.com/purview/get-started-with-records-management>
6. New-ComplianceTag (retention label; -RetentionAction/-RetentionDuration/-RetentionType/-IsRecordLabel/-Regulatory) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
7. Microsoft Purview service description - records management / adaptive scopes licensing (E5) - this library's [Licensing matrix](/docs/licensing-matrix/), grounded from <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. New-RetentionComplianceRule (`-Name` documented mutually exclusive with `-ApplyComplianceTag`/`-PublishComplianceTag`; `ComplianceTag` parameter set) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
9. New-RetentionCompliancePolicy (`AdaptiveScopeLocation` parameter set) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
10. Audit log activities - retention policy and retention label activities - <https://learn.microsoft.com/purview/audit-log-activities#retention-policy-and-retention-label-activities>

> Re-verify all links, cmdlet parameters, and licensing against current Microsoft Learn before a
> customer-facing deployment - the location-granularity gap and the `-Name`/`-ApplyComplianceTag`
> correction in particular should be confirmed in a pilot tenant, not assumed.