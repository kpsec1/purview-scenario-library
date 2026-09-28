---
part: "runbook"
parent: "data-map/scan-on-premises-sql-server-and-classify-pii-ruleset"
---
## Implementation steps

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **SQL Server** as the source type, name the ruleset (e.g. `SqlServerDatabase-PiiOnly`),
   and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected - deselect every one except the classifications you want to retain (U.S. Social Security
   Number, Credit Card Number, or whatever your program's driver requires). There is no documented
   "select none, then add back" toggle; for ~200 entries the portal path is significantly more
   tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local'
```

`-DataSourceName` must match the data source name the base scenario registered - defaults to a
sanitized form of the SQL Server instance's `-ServerEndpoint` in that scenario (e.g.
`sql01-contoso-local` for `sql01.contoso.local`); pass the exact value you used there.

## Configuration reference

See the design notes for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy, and exactly what is
confirmed vs. still `VERIFY` about the name-vs-kind relationship for this source type).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `SqlServerDatabase-PiiOnly` | Account-wide object name - reusable across every on-premises SQL Server scan that wants this scope (the design notes goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded - same default pair as every sibling Data Map PII-ruleset scenario in this library |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only - see the known limitations) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset - fails immediately if the SHIR node isn't registered/running |
| `-ApiVersion` | `2023-09-01` | Pinned; matches the base scenario and every sibling PII-ruleset scenario |

## Operations and tuning

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against the
  prior System-default run - a narrower classification set should measurably reduce per-column
  comparison time.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes (e.g. a new regulatory scope adds a data category), `-RetainedSystemClassifications` must be
  updated and the script re-run - there is no automatic sync between a program's stated scope and
  this ruleset's contents. Review the retained list at the same cadence as the licensing matrix
  review.
- **New system classifications Microsoft adds.** Because the exclusion list is derived live at deploy
  time, a classification Microsoft adds after this ruleset was last applied is
  automatically excluded on the *next* run of `New-PiiOnlyScanRuleset.ps1` - but not retroactively on
  the existing ruleset object until that script is re-run. Re-run it periodically (e.g. quarterly)
  rather than treating "deployed once" as "current forever."
- **Every scan rule set change is audit-logged, so treat the change itself as security-relevant.**
  Narrowing a scan's classification scope is a monitoring-coverage decision, not just a performance
  tweak - a scan under this ruleset will never surface a credential, key, or out-of-program data
  category that the System default would have caught. This is a genuinely elevated concern for this
  specific source type: on-premises SQL Server instances are the estate most likely to hold an
  undocumented sensitive column the System default's ~200-classification sweep would have caught.
  Pull **Scan rule set: Create / Update / Delete** Management-category audit events (via the
  `PurviewDataMapOperation` Microsoft Graph security audit log record type) into the same
  SIEM/Sentinel pipeline that already ingests this library's other Purview audit activity, and correlate
  a ruleset-narrowing event with the SHIR node's own health signal - a narrower ruleset on a scan that
  is *also* silently failing at the SHIR layer compounds two independent coverage gaps into one blind
  spot that neither Purview's own UI nor a naive "scan succeeded" check would surface on its own.
- **SHIR-specific operational risks are unchanged by this scenario** - see the base scenario's
  operations and tuning for the full on-premises incident-response list (SHIR node down, credential password
  rotated without the Purview credential object being updated, network/firewall change, SHIR software
  expiration). This scenario does not add or remove any of those risks; it only changes what a
  *successful* scan run classifies.

## Rollback and decommission

See the rollback runbook for the full staged sequence (revert the scan to System default; optionally delete
the custom ruleset object).

## References

1. New-AzPurviewSqlServerDatabaseScanRulesetObject (Az.Purview PowerShell module - confirms the
   Custom `SqlServerDatabaseScanRuleset` object shape and the `Kind: "SqlServerDatabase"` value,
   direct fetch from `learn.microsoft.com` in this build's environment) -
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasescanrulesetobject>
2. Scan Rulesets - Get / Create Or Replace REST API reference (API version 2023-09-01; confirms the
   `SqlServerDatabaseScanRuleset` object definition and `kind` literal alongside every sibling source
   type's own analogous object; generic call shape shared across source types; direct fetch this
   build) -
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
3. SqlServerDatabaseScanRuleset / SqlServerDatabaseSystemScanRuleset interfaces
   (`@azure-rest/purview-scanning` JavaScript SDK - confirms `kind: "SqlServerDatabase"` for BOTH the
   Custom and System ruleset variants of this source type, direct fetch this build) -
   <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/sqlserverdatabasescanruleset>
   <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/sqlserverdatabasesystemscanruleset>
4. New-AzPurviewSqlServerDatabaseCredentialScanObject (Az.Purview PowerShell module - confirms the
   scan object's field names via a worked example; that example uses an arbitrary custom ruleset
   name `'SqlServer'`, not the System default, which is why reference 1/2/3's `kind` confirmation
   does not also close the System ruleset's literal `name` - see the known limitations) -
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasecredentialscanobject>
5. Type - List REST API reference (Types API; confirms `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape - tenant-wide, source-type-agnostic; reused unchanged
   from the Azure SQL Database sibling's own direct fetch) -
   <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
6. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace.") - <https://learn.microsoft.com/purview/data-map-classification-custom>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary -
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) -
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Connect to and manage an on-premises SQL server instance in Microsoft Purview (base scenario's
   registration/scan reference this scenario extends; confirms the mandatory SHIR requirement and
   the stored-credential-only authentication story this scenario's reconcile step preserves) -
   <https://learn.microsoft.com/purview/register-scan-on-premises-sql-server>
9. Data Map classification supported list (confirmed to list classifications by human-readable
   name/description only, with no exact `MICROSOFT.*` identifier strings) -
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
10. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module - corroborates the scan rule set
    delete operation and its 204 response) -
    <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) -
    <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. *Scan On-Premises SQL Server and Classify Sensitive Columns* (base scenario this fragment
    extends; confirms `SqlServerDatabaseCredential` as the only compatible scan kind, and discloses
    the System-ruleset-name VERIFY this scenario inherits unresolved) - this library.
13. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) -
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
14. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API - the SIEM-consumable record type for Data Map
    Management-category events, including scan rule set changes) -
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>
15. *PII-Only Scan Rule Set for Azure SQL Database*,
    *PII-Only Scan Rule Set for Azure Synapse Analytics*, and
    *PII-Only Scan Rule Set for Azure SQL Managed Instance* (sibling
    scenarios this fragment mirrors - pattern precedent for the live-Types-API exclusion-list
    design, the reconcile-not-reconstruct scan update, and the name-vs-kind independent-verification
    discipline) - this library.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. One VERIFY remains open in the known limitations (the System default scan rule set's
> literal resource `name` for this source type, inherited unresolved from the base scenario) and
> should be closed against a pilot tenant or the Purview portal's own Scan rule sets → System tab
> before production use.