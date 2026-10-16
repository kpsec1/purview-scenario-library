---
part: "runbook"
parent: "data-map/scan-azure-sql-and-classify-pii-ruleset"
---
## Implementation steps

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **Azure SQL Database** as the source type, name the ruleset (e.g.
   `AzureSqlDatabase-PiiOnly`), and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected - deselect every one except the classifications you want to retain (U.S. Social
   Security Number, Credit Card Number, or whatever your program's driver requires). There is no
   documented "select none, then add back" toggle; for ~200 entries the portal path is
   significantly more tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb'
```

## Configuration reference

See the design notes for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `AzureSqlDatabase-PiiOnly` | Account-wide object name - reusable across every Azure SQL Database scan that wants this scope (the design notes goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only - see the known limitations) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset |
| `-ApiVersion` | `2023-09-01` | Pinned; confirmed current for the Scan Rulesets and Types endpoints as of this build |

## Operations and tuning

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against
  the prior System-default run - a narrower classification set should measurably reduce
  per-column comparison time on a nontrivial database. Track this as a rough sanity check that the
  ruleset actually took effect, not just as a performance metric.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes (e.g. a new regulatory scope adds a data category), `-RetainedSystemClassifications`
  must be updated and the script re-run - there is no automatic sync between a program's stated
  scope and this ruleset's contents. Review the retained list at the same cadence as the licensing
  matrix review.
- **New system classifications Microsoft adds.** Because the exclusion list is derived live at
  deploy time, a classification Microsoft adds after this ruleset was last applied
  is automatically excluded on the *next* run of `New-PiiOnlyScanRuleset.ps1` - but not
  retroactively on the existing ruleset object until that script is re-run. Re-run it periodically
  (e.g. quarterly) rather than treating "deployed once" as "current forever."
- **Every scan rule set change is audit-logged, so treat the change itself as security-relevant.**
  Narrowing a scan's classification scope is a monitoring-coverage decision, not just a
  performance tweak - a scan under this ruleset will never surface a credential, key, or
  out-of-program data category that the System default would have caught. Microsoft's own audit
  event catalog lists **Scan rule set: Create / Update / Delete** under the Management category
  ([RBAC model, section 14](/docs/rbac-model/)'s "how scenarios should cite RBAC" pattern applies equally to audit
  citations); pull these events into the same SIEM/Sentinel pipeline that already ingests this
  repo's other Purview audit activity via `PurviewDataMapOperation` (Microsoft Graph security
  audit log record type) so a ruleset narrowing is reviewed with the same rigor as a DLP policy
  exception - see references 12-13.

## Rollback and decommission

See the rollback runbook for the full staged sequence (revert the scan to System default; optionally
delete the custom ruleset object).

## References

1. Scan Rulesets - Create Or Replace REST API reference (API version 2023-09-01, confirmed
   `AzureSqlDatabaseScanRuleset`/`AzureSqlDatabaseScanRulesetProperties` body schema - direct
   fetch, this build) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
2. New-AzPurviewAzureSqlDatabaseScanRulesetObject (Az.Purview PowerShell module - confirms the
   `-ExcludedSystemClassification` exclusion model with a worked
   `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` example) - <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasescanrulesetobject>
3. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace. An example is `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`.") -
   <https://learn.microsoft.com/purview/data-map-classification-custom>
4. Type - List REST API reference (Types API; confirmed `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape, worked example `MICROSOFT.GOVERNMENT.CHILE.CDI_NUMBER` -
   direct fetch, this build) - <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
5. Scan Rulesets - Get REST API reference (API version 2023-09-01, direct fetch, this build) -
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
6. Data classification in Data Map ("System classifications: 200+ system classifications... formal
   names... prefixed by *MICROSOFT*.") - <https://learn.microsoft.com/purview/data-map-classification>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary -
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) -
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Data Map classification supported list (fetched in full during this build; confirmed to list
   classifications by human-readable name/description only, with no exact `MICROSOFT.*`
   identifier strings - the finding behind the known limitations's second limitation) -
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
9. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module - corroborates the scan rule set
   delete operation and its 204 response) - <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
10. Discover and govern Azure SQL Database (base scenario's scan/source registration this
    scenario extends) - <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) -
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
13. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API - the SIEM-consumable record type for Data Map
    Management-category events, including scan rule set changes) -
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. One VERIFY remains open in the known limitations (Types API pagination behavior at
> scale) and should be closed against a pilot tenant first.