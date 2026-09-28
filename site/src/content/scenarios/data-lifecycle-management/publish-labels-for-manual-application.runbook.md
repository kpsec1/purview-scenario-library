---
part: "runbook"
parent: "data-lifecycle-management/publish-labels-for-manual-application"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - Automation surface, section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 0. Prerequisite: the label must already exist (see retention-labels-financial-records)
Get-ComplianceTag -Identity 'Financial Records - 7yr Regulatory'

# 1. Dry run - prints the exact New-RetentionCompliancePolicy / -Rule cmdlets
./deploy/New-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json -DryRun

# 2. Deploy the publish policy + rule
./deploy/New-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json

# 3. Validate
./validate/Test-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json
```

### Portal reference

The policy is visible in the [Microsoft Purview portal](https://purview.microsoft.com) under
**Records Management** (or **Data Lifecycle Management**) → **Policies** → **Label policies**, listed
with policy type **Publish**. `-WhatIf` is non-functional in S&C PowerShell, so
the deploy/remove scripts ship a `-DryRun` instead.

### How users actually apply the published label

Once published, users select the label themselves - this scenario doesn't (and can't) force
application:

- **Outlook / Outlook on the web:** select the item → **Assign Policy** (ribbon or right-click) →
  choose the label.
- **SharePoint / OneDrive:** select the item → details pane → **Apply label** (new experience only,
  not classic).
- **Teams group-connected sites:** **Files** tab, same experience as SharePoint, once the label is
  published to the **Microsoft 365 Groups** location.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Label | Read-only prerequisite (`Get-ComplianceTag`) | This scenario never runs `New-/Set-ComplianceTag` |
| Policy cmdlet | `New-RetentionCompliancePolicy` | Publish label policy; needs ≥1 location |
| Locations | `SharePointLocation`, `ExchangeLocation` | Also `OneDriveLocation`, `ModernGroupLocation` |
| Rule cmdlet | `New-RetentionComplianceRule -PublishComplianceTag` | One rule per policy; **no** `-ContentMatchQuery`/`-ContentContainsSensitiveInformation` - those parameters belong to the `-ApplyComplianceTag` parameter set only |
| Retry stuck distribution | `Set-RetentionCompliancePolicy -RetryDistribution` | If the policy status shows Off (Error) |
| Supported for regulatory records | **Yes - the only supported path** | Contrast: auto-apply explicitly does **not** support regulatory records |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** policy **DistributionStatus** (should reach a healthy state); count of items
manually labeled over time (content search / activity explorer) as a coverage signal against how
much *should* be labeled. **Tuning:** publishing has no query to tune - the lever here is **user
awareness**, not policy configuration. Pair this with clear guidance to the target audience (what
the label means, when to apply it) and, where the label isn't a regulatory record, an auto-apply
policy for the content people forget to label.

**Change management:** adding/removing locations is a straightforward, low-risk change (unlike the
sibling's irreversible auto-apply of a regulatory label) - publishing doesn't retroactively affect
already-labeled content and unpublishing doesn't recall it either.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-PublishRetentionLabelPolicy.ps1` **disables**
the publish policy (stops offering the label to *new* selections); `-Delete` removes the policy +
rule. The retention **label itself is never touched** by this scenario's scripts - there's no
`-TryRemoveLabel`-equivalent here at all, unlike the sibling. Removing the policy never un-labels
content a user already labeled.

## References

1. Publish retention labels and apply them in apps (publish steps; timing; manual-apply UX per app; supported for all label configurations incl. regulatory records) - <https://learn.microsoft.com/purview/create-apply-retention-labels>
2. New-RetentionCompliancePolicy (locations; ≥1 location required; policy not valid until a rule is added) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
3. New-RetentionComplianceRule (`-PublishComplianceTag` parameter set: mandatory, mutually exclusive with `-ApplyComplianceTag`/`-Name`, no content-match parameters) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
4. Automatically apply a retention label to retain or delete content ("isn't supported for regulatory records... require a published retention label policy"; `Set-RetentionCompliancePolicy -RetryDistribution`) - <https://learn.microsoft.com/purview/apply-retention-labels-automatically>
5. Declare records by using retention labels ("...for labels that mark items as records (but not regulatory records), auto-apply those labels...") - <https://learn.microsoft.com/purview/declare-records>
6. Get-RetentionComplianceRule (documented default-display properties: Name, Disabled, Mode, Comment) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-retentioncompliancerule>
7. Learn about retention policies and retention labels ("a single retention label can be included in multiple retention label policies"; "Will a label be overridden?" table - auto-apply is "Not applicable" for regulatory records) - <https://learn.microsoft.com/purview/retention>
8. PowerShell cmdlets for retention policies and retention labels - <https://learn.microsoft.com/purview/retention-cmdlets>
9. Microsoft Purview service description - Records Management / Data Lifecycle Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>

> Re-verify all links, cmdlet parameters, and licensing against current Microsoft Learn before a
> customer-facing deployment. This scenario deliberately never creates or edits a retention label -
> confirm the target label already exists before running the deploy script.