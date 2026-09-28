---
part: "runbook"
parent: "data-quality/connection-and-scorecard-alerts"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Connection:** **Health management** → **Data quality** → select the governance domain →
   **Manage** → **Connections** → **New**. Choose **Data Map** or enter the Azure SQL server/
   database directly, test the connection, and **Submit**. Grant the Purview
   managed identity `db_datareader` on the source database.
2. **(Managed-VNet only)** Before step 1, provision the region under **Settings** → **Unified
   Catalog** → **Virtual network**, then select **Enable managed V-Net** during connection setup
   and complete the private-endpoint approval flow on the storage/SQL resource's **Networking**
   blade.
3. **Alerts:** same governance domain → **Manage** → **Alerts** → **New**. Enter a display name,
   choose **Score less than** or **Score decreased by more than** and a threshold, add a
   **Recipient**, define the **Scope** (data products/assets), and **Submit**.
4. Confirm both objects independently: **Manage** → **Connections** shows the connection's status;
   **Manage** → **Alerts** lists the alert with its **Notifications** toggle.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connection - dry run first (reports the exact REST call, changes nothing)
./deploy/New-DataQualityConnection.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ConnectionDefinitionPath './deploy/connection/customer-sql-connection.json' `
    -WhatIf

# 2. Connection - deploy for real (non-VNet, managed-identity, public-endpoint path)
./deploy/New-DataQualityConnection.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ConnectionDefinitionPath './deploy/connection/customer-sql-connection.json'

# 3. Alerts - deploy both asset-level example alerts (score threshold + score regression)
./deploy/New-DataQualityAlert.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json'

# 3b. (Optional) Alerts - deploy the product-level companion example instead of/alongside 3
#     One alert covers every asset in the 'Customer 360' data product (dataAssetId omitted) -
#     see the Configuration reference (Section 6) and Section 11 for the scope trade-off.
./deploy/New-DataQualityAlert.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -AlertDefinitionPath './deploy/alerts/customer-360-product-score-alert.json'

# 4. Validate (connection + alerts together, or pass only one -*DefinitionPath to check just that half)
./validate/Test-DataQualityConnectionAndAlerts.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ConnectionDefinitionPath './deploy/connection/customer-sql-connection.json' `
    -AlertDefinitionPath './deploy/alerts/customer-master-score-alerts.json'
```

Both deploy scripts use the **Microsoft Purview Data Quality REST API for Unified Catalog** (Public
Preview) - automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), same surface as
*Configure Rules and Review Scorecards for a Governed Data Asset*. Token acquisition follows the same client-credentials pattern.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Connection type | `AzureSqlDatabase`, `ManagedServiceIdentity` credential, `Sql` scope | Matches the sibling scenario's Azure SQL "Customer" asset; managed identity is the only supported authentication for Microsoft-native sources |
| `isVNetEnabled` default | `false` | The scripted default targets the common, non-VNet case - see the known limitations and the design notes for why `computeId` is not required here |
| Managed-VNet opt-in | `-EnableManagedVNet -ComputeId <pre-provisioned id>` | Never provisions the compute location itself - portal/Governance Domain Administrator-only, see the known limitations |
| Alert `condition` functions | `score_threshold(GLOBAL_SCORE)`, `score_variance(GLOBAL_SCORE)` | The only two functions confirmed in Microsoft's own REST worked examples - the design notes |
| Alert `receivers` value | Microsoft Entra object ID (GUID) of a user or mail-enabled security group | Every REST worked example uses a GUID, never a raw SMTP address/UPN - see the known limitations VERIFY |
| Alert `enabledForFailedJobs` | `true` (example definition file default) | Also notifies receivers when the scan job itself fails (distinct from "scan succeeded, score is low") - matches the portal's "Turn on notifications for failed quality scan" option |
| Alert scope granularity | Asset-level (`customer-master-score-alerts.json`, both `dataProductId` + `dataAssetId`) **or** product-level (`customer-360-product-score-alert.json`, `dataProductId` only) | Same `New-DataQualityAlert.ps1` script deploys either shape - product-level scope is built automatically whenever `dataAssetId` is absent from a definition-file entry; see the known limitations for the grounding status of the product-only shape and the operational trade-off |
| API version pinned by both scripts | `2026-01-12-preview` | Confirmed current via direct fetch of Microsoft's REST reference at build time; **Public Preview** |

Full REST-body grounding: each deploy/validate script's inline comments and `.NOTES` block cite the
exact Microsoft Learn reference pages.

## Operations and tuning

**Choosing asset-level vs. product-level alert scope:** deploy `customer-master-score-alerts.json`
(asset-level) when an operator needs to know *which* asset regressed without an extra lookup step;
deploy `customer-360-product-score-alert.json` (product-level) when the data product has too many
assets for one alert each to stay manageable, and a first-triage "something in this product
regressed" notification is enough to start an investigation. The two are not mutually exclusive -
run both, or scope several product-level alerts to different asset subsets, per the known limitations's grounding
caveat and trade-off note.

**KPIs to watch (first 30 days):**
- **Alert fire rate.** Zero fires in 30 days on a freshly deployed alert is ambiguous - it could
  mean the data is genuinely healthy, or that the threshold is set too loosely, or that no scan has
  run at all (check *Configure Rules and Review Scorecards for a Governed Data Asset*' own schedule health first). A monthly review of "has
  this alert ever fired since deployment" is a minimum sanity check.
- **Connection health.** A Data Quality scan failure most commonly traces back to the connection
  (revoked managed-identity grant, source firewall change, or an expired/rotated credential on the
  source side) - *Configure Rules and Review Scorecards for a Governed Data Asset* (operations and tuning)'s incident-response runbook item (a) is this
  scenario's connection, made concrete.
- **Receivers list drift - accidental or adversarial.** This scenario's alert `receivers` are
  static Entra object IDs in a definition file - a person who leaves the data-product-owner role
  stops receiving alerts silently unless the definition file (and a re-run of
  `New-DataQualityAlert.ps1`) is updated. The same mechanism is also a stealth bypass: because
  **Data Quality Steward** is domain-wide, anyone holding it can call `Update Alert` directly
  and repoint `receivers` away from the real distribution list without deleting the alert - it
  still exists, still shows `Enabled`, and still passes a naive "does the alert exist" check.
  **Do not treat a one-time post-deploy validate run as sufficient.** Wire
  `validate/Test-DataQualityConnectionAndAlerts.ps1` into a recurring pipeline (daily or per
  change), diffed against the source-controlled definition file under normal PR review - the same
  "declarative file, reviewed like any other policy change" discipline this library already applies to
  DLP rules and label policies - so an out-of-band `receivers` change is caught as a validation
  failure, not discovered only when nobody was notified of a real regression.

**Alert routing:** route the alert's notification email into existing incident tooling (a shared
mailbox monitored by the data governance team, or a rule forwarding into a ticketing system) rather
than an individual's inbox - the same guidance *Configure Rules and Review Scorecards for a Governed Data Asset* (operations and tuning) already gives.

**Incident-response runbook (connection failure, distinct from "the alert fired because the score
is genuinely low"):**
1. **Triage** - check the connection's status under **Manage** → **Connections**, or via
   `Get Data Source`; a scan failure's error detail (portal **Monitoring** tab, or
   *Configure Rules and Review Scorecards for a Governed Data Asset*' `Get Run Status`) usually names the specific cause.
2. **Classify the cause**, in order of likelihood: (a) the managed-identity read grant on the source
   was revoked or the source firewall/network rule changed; (b) for the managed-VNet path, the
   private endpoint's approval was revoked or the region's compute location was deleted (deleting a
   region removes every connection linked to it -); (c) the source schema
   changed and needs **Import schema** re-run (same as *Configure Rules and Review Scorecards for a Governed Data Asset* (operations and tuning) item
   (b)); (d) **someone recently ran this scenario's own rollback** (the rollback runbook Stage 2) and the
   sibling scenario's schedule wasn't repointed or paused first - ask whether a teardown happened
   recently before spending time on (a)-(c). **This has to stay a human question, not a query, for
   now** - a dedicated grounding pass confirmed no programmatic audit trail exists yet for
   this action.
3. **Remediate** - re-apply the grant, re-approve the private endpoint, or re-import the schema,
   then re-run `validate/Test-DataQualityConnectionAndAlerts.ps1` before assuming the fix worked.
4. **Escalate** if failures recur after confirming the connection, grant, and (if applicable)
   private-endpoint state are all healthy.

**Review cadence:** review alert thresholds and receivers quarterly alongside the sibling
scenario's rule pass/fail/miscast review - a threshold set once at deployment and never revisited
tends to drift from what "acceptable" actually means for the asset as its data volume and use
change.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-DataQualityConnectionAndAlerts.ps1` removes the alerts only by default; add
`-RemoveConnection` (with `-ConnectionDefinitionPath`) to also delete the data-source connection.

## References

1. Microsoft Purview billing models / Data governance billing (DGPU) - <https://learn.microsoft.com/purview/purview-billing-models> and <https://learn.microsoft.com/purview/data-governance-billing>
2. Data governance roles and permissions in Microsoft Purview - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
3. Data Quality API for Unified Catalog (Public Preview) - scope, GA-only coverage, lifecycle - <https://learn.microsoft.com/rest/api/purview/unified-catalog-data-quality>
4. Set up data source connection for data quality in Unified Catalog - <https://learn.microsoft.com/purview/unified-catalog-data-quality-supported-sources-connection>
5. Set up managed virtual networks for data quality scans in virtual network storage (compute provisioning, Governance Domain Administrator role, region-deletion cascade) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-managed-virtual-networks>
6. Set up data quality alerts (portal workflow, Score less than / Score decreased by more than, required role, recipient/threshold concepts) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-alerts>
7. Purview Data Quality REST reference - Create Data Source, Get Data Source, Update Data Source - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/create-data-source/create-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-data-source/get-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-data-source/update-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview>
8. Purview Data Quality REST reference - Update Alert, Get Alert, Get Alerts, Update Alert Status, Delete Alert - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-alert/update-alert?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-alert/get-alert?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-alerts/get-alerts?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/update-alert-status/update-alert-status?view=rest-purview-purviewdataquality-2026-01-12-preview>, <https://learn.microsoft.com/rest/api/purview/purviewdataquality/delete-alert/delete-alert?view=rest-purview-purviewdataquality-2026-01-12-preview>
9. Purview Data Quality REST operation-groups index (2026-01-12-preview) - confirms no Get/List Compute operation exists - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/operation-groups?view=rest-purview-purviewdataquality-2026-01-12-preview>
10. Purview Data Quality REST reference - Delete Data Source - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/delete-data-source/delete-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview>
11. Audit log activities (Microsoft Purview's confirmed `RecordType`/`Operations` reference; no Unified Catalog/Data Quality/governance-domain section - Purview coverage is `PurviewDataMapOperation`, the classic Data Map API's own record type) - <https://learn.microsoft.com/purview/audit-log-activities>
12. Audit - Query - REST API (Azure Purview) - the classic Data Map's own data-plane audit-history endpoint (`category`/`operationType`, e.g. `Asset`/`EntityUpdated`), covering Atlas-model Data Map entities, not Unified Catalog governance-domain objects - <https://learn.microsoft.com/rest/api/purview/datamapdataplane/audit/query>
13. "Microsoft Purview Unified Catalog Needs Audit Logs. Here's Why." (independent third-party analysis, March 2026; corroborates references 11/12 rather than standing alone) - <https://medium.com/@marcoOesterlin/microsoft-purview-unified-catalog-needs-audit-logs-heres-why-b208e83e1b94>

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment - this entire feature is **Public Preview**, and the VERIFY items in
> section 11 should be closed against a pilot tenant first. References 11-12 could not be directly
> fetched in this build's execution environment (`learn.microsoft.com` egress was blocked) - see
> the VERIFY callout in the known limitations before treating the audit-coverage finding as pilot-tenant-confirmed.