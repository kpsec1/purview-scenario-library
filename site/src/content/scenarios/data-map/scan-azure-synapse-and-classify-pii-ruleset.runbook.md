---
part: "runbook"
parent: "data-map/scan-azure-synapse-and-classify-pii-ruleset"
---
## Implementation steps

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **Azure Synapse Analytics** as the source type, name the ruleset (e.g.
   `AzureSynapseWorkspace-PiiOnly`), and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected - deselect every one except the classifications you want to retain (U.S. Social
   Security Number, Credit Card Number, or whatever your program's driver requires). There is no
   documented "select none, then add back" toggle; for ~200 entries the portal path is
   significantly more tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default (`AzureSynapseSQL`)** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod'
```

## Configuration reference

See the design notes for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy, and the
system-ruleset-name-vs-kind naming nuance specific to this source type).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `AzureSynapseWorkspace-PiiOnly` | Account-wide object name - reusable across every Azure Synapse Analytics scan that wants this scope (the design notes goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded - same default pair as every sibling Data Map PII-ruleset scenario in this library |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only - see the known limitations) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset |
| `-ApiVersion` | `2023-09-01` | Pinned; matches the base scenario and the Azure SQL Database sibling |

## Operations and tuning

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against
  the prior System-default run - a narrower classification set should measurably reduce
  per-column comparison time, a more visible effect on a nontrivial dedicated pool than on a small
  database given how long the base scenario's own page already documents Synapse scans can run.
  Track this as a rough sanity check that the ruleset actually took effect, not a performance
  metric.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes, `-RetainedSystemClassifications` must be updated and the script re-run - there is no
  automatic sync between a program's stated scope and this ruleset's contents. Review the retained
  list at the same cadence as the licensing matrix review.
- **New system classifications Microsoft adds.** Because the exclusion list is derived live at
  deploy time, a classification Microsoft adds after this ruleset was last applied
  is automatically excluded on the *next* run of `New-PiiOnlyScanRuleset.ps1` - but not
  retroactively on the existing ruleset object until that script is re-run. Re-run it periodically
  (e.g. quarterly) rather than treating "deployed once" as "current forever."
- **Every scan rule set change is audit-logged, so treat the change itself as security-relevant.**
  Narrowing a scan's classification scope is a monitoring-coverage decision, not just a
  performance tweak - a scan under this ruleset will never surface a credential, key, or
  out-of-program data category that the System default would have caught. Microsoft's own audit
  event catalog lists **Scan rule set: Create / Update / Delete** under the Management category;
  pull these events into the same SIEM/Sentinel pipeline that already ingests this library's other
  Purview audit activity via `PurviewDataMapOperation` (Microsoft Graph security audit log record
  type) so a ruleset narrowing on the Synapse workspace scan is reviewed with the same rigor as a
  DLP policy exception - see references 12-13.

## Rollback and decommission

See the rollback runbook for the full staged sequence (revert the scan to the `AzureSynapseSQL` System
ruleset; optionally delete the custom ruleset object).

## References

1. New-AzPurviewAzureSynapseWorkspaceScanRulesetObject (Az.Purview PowerShell module - confirms the
   Custom `AzureSynapseWorkspaceScanRuleset` object shape and the `Kind: AzureSynapseWorkspace`
   value via a worked example, direct-fetched from GitHub raw source after `learn.microsoft.com`
   returned `EGRESS_BLOCKED` in this build environment) -
   <https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSynapseWorkspaceScanRulesetObject.md>
2. New-AzPurviewAzureSynapseWorkspaceCredentialScanObject (Az.Purview PowerShell module - confirms
   `Kind: AzureSynapseWorkspaceCredential` for the credential-authenticated scan variant, and
   confirms `ScanRulesetName: AzureSynapseSQL`/`ScanRulesetType: System` as the shared System
   default for both Msi- and Credential-authenticated Synapse scans, via a worked example) -
   <https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSynapseWorkspaceCredentialScanObject.md>
3. New-AzPurviewAzureSynapseWorkspaceMsiScanObject (Az.Purview PowerShell module - confirms `Kind:
   AzureSynapseWorkspaceMsi`, reused unchanged from the base scenario's own citation) -
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacemsiscanobject>
4. Scan Rulesets - Create Or Replace / - Get REST API reference (API version 2023-09-01; generic
   call shape confirmed by direct fetch during the Azure SQL Database sibling scenario's build, and
   reused unchanged here - only the request body's `kind` value differs per source type) -
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
5. Type - List REST API reference (Types API; confirmed `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape - tenant-wide, source-type-agnostic; reused unchanged
   from the Azure SQL Database sibling's own direct fetch) -
   <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
6. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace.") - <https://learn.microsoft.com/purview/data-map-classification-custom>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary -
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) -
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Data Map classification supported list (confirmed to list classifications by human-readable
   name/description only, with no exact `MICROSOFT.*` identifier strings) -
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
9. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module - corroborates the scan rule set
   delete operation and its 204 response) - <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
10. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (base scenario's
    registration/scan reference this scenario extends; confirms `AzureSynapseSQL` as the System
    default scan rule set name) - <https://learn.microsoft.com/purview/register-scan-synapse-workspace>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) - <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) -
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
13. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API) -
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>
14. *PII-Only Scan Rule Set for Azure SQL Database* (sibling scenario this fragment
    mirrors - pattern precedent for the live-Types-API exclusion-list design and the reconcile-not-reconstruct scan update) - this library.
15. *Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* (base scenario this fragment extends) -
    this library.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. The Synapse-specific REST body shape VERIFY is now resolved (the known limitations,
> 2026-09-25, confirmed directly against the REST reference page). One VERIFY remains open in the known limitations
> (Types API pagination behavior at scale) and should be closed against a pilot tenant.