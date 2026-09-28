---
part: "runbook"
parent: "records-management/file-plan-bulk-import"
---
## Implementation steps

```powershell
# --- Path A: documented CSV import (portal upload) ---
# 1. Offline validation - no tenant connection needed
./deploy/New-FilePlanImportCsv.ps1 -InputPath ./deploy/config/file-plan-schedule.sample.csv

# 2. (Recommended) also check LabelName-uniqueness and EventType-exists against your tenant
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/New-FilePlanImportCsv.ps1 -TenantChecks -OutputPath ./deploy/config/file-plan-import-ready.csv

# 3. Upload file-plan-import-ready.csv via the portal:
#    Purview portal > Records Management > File plan > Import > Download a blank template (once, to
#    confirm current column order) > Upload a file > select file-plan-import-ready.csv

# --- Path B: fully scripted, no portal step ---
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/New-FilePlanBulkLabels.ps1 -DryRun          # prints every cmdlet, creates nothing
./deploy/New-FilePlanBulkLabels.ps1                  # creates descriptors + labels, idempotent

# --- Either path: validate ---
./validate/Test-FilePlanBulkImport.ps1
```

### Portal reference

File plan lives in the [Microsoft Purview portal](https://purview.microsoft.com) under **Records
Management → File plan**; the **Import** button is on that page, and file-plan descriptor picklists
(Department/Category/etc.) can also be managed there directly. `-WhatIf` is
non-functional in S&C PowerShell, so `New-FilePlanBulkLabels.ps1` ships a `-DryRun` instead.

## Configuration reference

The source CSV's columns are Microsoft's own documented file-plan-import property names
 - both automation paths read the identical file:

| Column | Required | Notes |
|---|---|---|
| `LabelName` | Yes | ≤64 chars; only `a-z A-Z 0-9 - ` (space); unique in tenant; **immutable after save** |
| `Comment` / `Notes` | No | ≤1024 chars each (admin-only / user-facing description) |
| `IsRecordLabel` | No* | `TRUE`/`FALSE`; group-required with the retention trio below once set |
| `RetentionAction` | No* | `Delete` \| `Keep` \| `KeepAndDelete`; required once Duration/Type/ReviewerEmail are set |
| `RetentionDuration` | No* | `Unlimited` or 1-36525 (days); required once Action/Type are set |
| `RetentionType` | No* | `CreationAgeInDays` \| `EventAgeInDays` \| `TaggedAgeInDays` \| `ModificationAgeInDays` |
| `ReviewerEmail` | No | Requires `RetentionAction=KeepAndDelete`; **semicolon**-separated in the CSV, array/comma in the cmdlet |
| `ReferenceId` / `DepartmentName` / `Category` / `SubCategory` / `AuthorityType` | No | Free-text file-plan descriptors; out-of-box picklist values or your own |
| `CitationName` / `CitationUrl` / `CitationJurisdiction` | No | The **Provision/citation** descriptor (name/URL/jurisdiction) |
| `Regulatory` | No | `TRUE` requires `IsRecordLabel=TRUE` **and** the tenant configured to display the regulatory option, or import validation fails |
| `EventType` | Cond. | Required iff `RetentionType=EventAgeInDays`; **must already exist** in the tenant before import/deploy |
| `IsRecordUnlockedAsDefault` | No | `TRUE` requires `IsRecordLabel=TRUE` and `Regulatory≠TRUE` |
| `ComplianceTagForNextStage` | No | Replacement label at end of retention; not allowed with `Regulatory=TRUE` |

\* "No" per Microsoft's table, but each becomes required the moment any one of the group is set -
see `FilePlanRow.Validate.ps1` for the exact group-dependency logic, reproduced from.

| Path B cmdlet | Purpose |
|---|---|
| `New-FilePlanPropertyDepartment` / `-Category` / `-SubCategory -ParentId` / `-Citation` / `-ReferenceId` / `-Authority` | Create-or-report the six descriptor picklist objects |
| `New-ComplianceTag -FilePlanProperty <json>` | The label itself; `-FilePlanProperty` takes a `PSCustomObject{Settings=@(@{Key;Value})}` converted to JSON - the exact syntax Microsoft documents |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** file-plan row count vs. schedule row count (drift = someone edited the tenant
outside this pipeline); validation failure rate on each CI run of `New-FilePlanImportCsv.ps1`
(rising failures usually mean the schedule source - an HR/Legal spreadsheet - is drifting from the
CSV's required format); count of labels created without a disposition reviewer (an auto-delete
`KeepAndDelete` label with no review is a `[WARN]` from both scripts - track it as a records-hygiene
metric). **Tuning:** treat the CSV as the single source of truth for the schedule - resist portal
edits that the file doesn't reflect, or the next validation run will report false drift. Batch new
record classes into the same file rather than one-off portal creations, so every class stays
reviewable in one diff.

**Change management:** `LabelName` and its core retention settings can't be changed once saved
 - a correction is a **new row/label**, never an in-place edit of the CSV for an
existing name. Treat every schedule change as a Records/Legal-reviewed pull request against the CSV.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-FilePlanBulkLabels.ps1` **attempts**
`Remove-ComplianceTag` for every row's label and **reports** (never forces) failures for labels
already applied, published, regulatory, or event-based. Descriptor objects
(Department/Category/etc.) are **not** removed - they're shared, tenant-wide picklist values other
labels may reference. The portal CSV-import path has no bulk-delete equivalent at all; labels it
creates are removed the same way, one at a time.

## References

1. New-ComplianceTag (`-FilePlanProperty` PSCustomObject→JSON shape; `-RetentionAction`/
   `-RetentionDuration`/`-RetentionType`/`-ReviewerEmail`/`-IsRecordLabel`/`-Regulatory`/
   `-IsRecordUnlockedAsDefault`/`-ComplianceTagForNextStage`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag>
2. Get-ComplianceRetentionEventType / Get-ComplianceTag (live EventType/LabelName checks) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-complianceretentioneventtype>
3. Use file plan to create and manage retention labels (import property table, group dependencies,
   max lengths, LabelName charset, roles, delete constraints, "not supported for import: multi-stage
   disposition review") - <https://learn.microsoft.com/purview/file-plan-manager>
4. New-FilePlanPropertyDepartment / -Category / -SubCategory (`-ParentId`) / -Citation /
   -ReferenceId / -Authority - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-fileplanpropertydepartment>
5. Get-FilePlanPropertyAuthority / -Category / -Citation / -Department / -ReferenceId /
   -SubCategory (the six `Get-*` cmdlets `-FilePlanProperty`'s values must resolve against) -
   referenced in New-ComplianceTag's own `-FilePlanProperty` documentation
6. Learn about records management - <https://learn.microsoft.com/purview/records-management>
7. Microsoft Purview service description - Records Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. Declare records by using retention labels - audit log activities for labeling - <https://learn.microsoft.com/purview/declare-records>
9. Audit log activities - Retention policy and retention label activities (`NewComplianceTag` /
   "Created retention label") - <https://learn.microsoft.com/purview/audit-log-activities#retention-policy-and-retention-label-activities>
10. Office 365 Management Activity API schema - Common schema (`RecordType` 38 `DataGovernance`) - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#common-schema>

> Re-verify all links, cmdlet parameters, licensing, and the portal template's exact column order
> against current Microsoft Learn (and a live template download) before a customer-facing
> deployment. `LabelName` and core retention settings are immutable once saved - validate thoroughly
> before either deploy path touches a production tenant.