---
part: "runbook"
parent: "data-quality/rules-and-scorecards"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the target asset is already in Unified Catalog: **Data Map** → source registered and
   scanned; then **Unified Catalog** → the asset added to a **data product** inside a **governance
   domain**.
2. Assign the automation identity's *human* counterpart (or, for this walkthrough, yourself) the
   **Data Quality Steward** role: in the governance domain, select **Roles** → add the user under
   **Data Quality Steward**. This role requires **Governance Domain Reader** and
   **Data Product Owner** to already be held on the same domain - assign those first if not already
   present.
3. Set up the **Data Quality connection**: **Health management** → **Data quality** → select the
   governance domain → **Manage** → **Connections** → **New**. Choose **Data Map** as the source type
   (simplest - reuses the already-scanned Data Map registration), test the connection, and **Submit**. Grant the Purview managed identity the source-appropriate read role (e.g.
   `db_datareader` for Azure SQL - the same grant *Scan Azure SQL Database and Classify Sensitive Columns*
   already documents).
4. Navigate to the asset's **Data quality** page (**Health management** → **Data quality** → domain →
   data product → asset) and select **Rules** → **New rule** to author each rule interactively - this
   is the portal equivalent of what the script in the implementation steps's script path does in bulk from a JSON file.
5. Select **Run quality scan** for an immediate ad hoc run, or **Manage** → **Scheduled scans** → **New**
   for a recurring cadence (the portal supports daily/weekly/monthly recurrence - see the known limitations for why this
   scenario's script only schedules a one-time run).
6. After the scan completes, review the score on the asset's **Overview** tab, and the roll-up report
   at **Health management** → **Reports** → **Data quality** for the product/domain view.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Deploy (dry run first - reports every REST call that would be made, changes nothing)
./deploy/New-DataQualityRulesAndSchedule.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json' `
    -WhatIf

# 2. Deploy for real - rules land Active, a one-time scan is scheduled 5 minutes out
./deploy/New-DataQualityRulesAndSchedule.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json'

# 3. Land rules in Draft for review first, without triggering a scan
./deploy/New-DataQualityRulesAndSchedule.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json' `
    -RuleStatus Draft -CreateSchedule:$false

# 4. Validate (after the scheduled scan has had time to complete)
./validate/Test-DataQualityRulesAndScorecard.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json'
```

The deploy script uses the **Microsoft Purview Data Quality REST API for Unified Catalog** (Public
Preview) - automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - because rule and schedule
objects have no Security & Compliance PowerShell or Graph equivalent. Token acquisition follows the
same client-credentials pattern already used by this library's other surface-4 scripts.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Rule types deployed | `NotNull`, `Unique`, `TypeMatch`, `Duplicate`, `CustomTruth` | Confirmed API `type` values, taken directly from Microsoft's own Get Rules / Create Rules reference examples |
| Rule dimensions | Completeness, Uniqueness, Conformity, Accuracy (×2) | Matches the six-dimension model (Accuracy/Completeness/Conformity/Consistency/Timeliness/Uniqueness) Microsoft documents for Data Quality reporting - this scenario deliberately omits **Freshness**, which isn't supported for Azure SQL sources |
| Rule `status` on create | `Active` (default), or `Draft` via `-RuleStatus` | Draft rules don't run during a scan and don't contribute to the global score - a safe landing state for review |
| Rule cap per asset | 200 active rules | Product-enforced; a scan fails outright above this - see the known limitations |
| Schedule trigger type | `RunOnce` only | The only trigger type this build's grounding confirmed in the REST schema - see the known limitations |
| Scan authentication | Managed identity only (Microsoft-native sources) | Portal-configured DQ connection prerequisite - not scripted, see the known limitations |
| API version pinned by this script | `2026-01-12-preview` | Confirmed current via direct fetch of Microsoft's REST reference at build time; **Public Preview** - covers GA Data Quality features only, not alerting/schema-import/preview features |

Full REST-body grounding: `deploy/New-DataQualityRulesAndSchedule.ps1` inline comments and its
`.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Asset/data-product/domain global score trend** - a steady score near 100% with sudden drops
  flags an upstream data-pipeline regression faster than a downstream report catching the symptom.
- **Passed vs. failed vs. miscast vs. empty row counts per rule** (from `Get Runs For Asset`/the
  portal's rule-level **History** tab) - a rule with a persistently high **miscast** count usually
  means the rule's target type or format doesn't match the real data shape and needs tuning, not that
  the data itself is bad.
- **Scan failure rate** - a Data Quality scan failure (distinct from a low *score*, which means the
  scan succeeded and found bad data) usually points at the DQ connection, not the rules - see the
  runbook below.

**Alert routing:** configure score-threshold alerts (**Score less than X%**, or **Score decreased by
more than X%**) per governance domain via **Manage** → **Alerts** in the portal - this is a
**Data Quality Steward**-only action with no independently confirmed REST endpoint in this build's
grounding pass (`Update Alert`/`Get Alerts` operation groups exist per the REST index, but were not
independently fetched and verified for this fragment; see the known limitations). Alerts email a
configured recipient/distribution list on every scan, not just failures - route that mailbox into
existing incident tooling rather than leaving it as an unmonitored inbox.

**Do not treat this scenario as "monitored" until at least one alert is configured.** This
scenario's deploy script creates rules and a schedule but - per the VERIFY above - does **not**
configure alerting. Without it, a score regression (or a rule silently left in `Draft` after a
review that never happened - see the known limitations) produces **no notification at all**; the only way to notice
is someone manually opening the portal or re-running `validate/Test-DataQualityRulesAndScorecard.ps1`.
Treat portal alert configuration as a go-live gate for this scenario, not an optional enhancement,
and additionally wire `validate/Test-DataQualityRulesAndScorecard.ps1` (with `-ExpectedRuleStatus
Active`) into an existing CI/ops pipeline on a recurring cadence so an unintentional Draft/removed
rule is caught even if the portal alert channel is missed or muted.

**Incident-response runbook (a scan fails outright, distinct from "the score is just low"):**
1. **Triage** - check the run status in **Health management** → **Data quality** → **Monitoring**
   for the specific error, or via `Get Run Status`/`Get Runs For Asset`.
2. **Classify the cause**, in order of likelihood: (a) the DQ connection's managed-identity grant on
   the source was revoked or the source's firewall changed (same failure class as the Data Map
   scenario's runbook - see *Scan Azure SQL Database and Classify Sensitive Columns* (operations and tuning)); (b) the
   source schema changed and needs **Import schema** re-run before the next scan;
   (c) more than 200 active rules are on the asset (product-enforced cap - see the known limitations);
   (d) a transient Spark/service-side issue - safe to let the next scheduled run retry.
3. **Remediate** - re-apply the specific broken grant, re-import the schema, or deactivate the
   lowest-priority rules to get under the 200-rule cap, then re-run
   `validate/Test-DataQualityRulesAndScorecard.ps1` before assuming the fix worked.
4. **Escalate** if failures recur after confirming the connection, schema, and rule count are all
   healthy - a Purview-service-side issue worth a support case.

**Review cadence:** review rule pass/fail/miscast trends monthly with the data product owner; a rule
that has passed 100% for months may be a candidate to retire (or tighten) rather than keep running at
cost, and a rule with a persistent miscast rate needs its `typeProperties` corrected, not more scans.

## Rollback and decommission

See the rollback runbook for the full staged procedure (remove schedule → optionally remove rules). Quick
reference: `./deploy/Remove-DataQualityRulesAndSchedule.ps1` removes the schedule only by default; add
`-RemoveRules` to also delete the rules from the asset.

## References

1. Overview of data quality in Microsoft Purview Unified Catalog - <https://learn.microsoft.com/purview/unified-catalog-data-quality>
2. Microsoft Purview billing models / Data governance billing (DGPU) - <https://learn.microsoft.com/purview/purview-billing-models> and <https://learn.microsoft.com/purview/data-governance-billing>
3. Data governance roles and permissions in Microsoft Purview - governance domain role table (Data Quality Steward, Data Quality Reader, Data Quality Metadata Reader, Data Profile Steward/Reader) - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
4. Set up data source connection for data quality in Unified Catalog (managed-identity-only authentication for Microsoft-native sources, required read grants) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-supported-sources-connection>
5. Data Quality API for Unified Catalog (Public Preview) - scope, GA-only coverage, lifecycle - <https://learn.microsoft.com/rest/api/purview/unified-catalog-data-quality>
6. Get started with Microsoft Purview data governance - data quality action steps - <https://learn.microsoft.com/purview/data-governance-get-started#improve-data-quality-and-remove-data-issues>
7. Create data quality rules (rule types, dimensions, custom-rule expression language, 200-rule cap, required-roles note) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-rules>
8. Configure a data quality scan for a data product (schedule wizard, schema import, prerequisites) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-scan>
9. Review data quality scores of data assets (score formula, 50-run trend history, Power BI report) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-scores>
10. Purview Data Quality REST reference - Create Rules and Get Rules operations (confirmed `type` values NotNull/Unique/TypeMatch/Duplicate/CustomTruth) - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/create-rules/create-rules?view=rest-purview-purviewdataquality-2026-01-12-preview> and <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-rules/get-rules?view=rest-purview-purviewdataquality-2026-01-12-preview>
11. Understand the quality report in Unified Catalog (six-dimension model) - <https://learn.microsoft.com/purview/unified-catalog-reports-data-quality-health>
12. Purview Data Quality REST operation groups index (2026-01-12-preview) - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/operation-groups?view=rest-purview-purviewdataquality-2026-01-12-preview>
13. Monitor data quality jobs in Unified Catalog - <https://learn.microsoft.com/purview/unified-catalog-data-quality-job-monitor>
14. Review data quality scores of data assets - rule-level pass/fail/miscast/empty detail and history - <https://learn.microsoft.com/purview/unified-catalog-data-quality-scores#rule-details-and-history>
15. Set up data quality alerts (score-threshold configuration, required role) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-alerts>
16. Configure an incremental data quality scan (time-based filtering, cost/performance rationale) - <https://learn.microsoft.com/purview/unified-catalog-data-quality-scan-incremental>
17. Purview Data Quality REST reference - Create Schedule and Get Schedule operations (confirmed `RunOnce` trigger shape) - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/create-schedule/create-schedule?view=rest-purview-purviewdataquality-2026-01-12-preview> and <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-schedule/get-schedule?view=rest-purview-purviewdataquality-2026-01-12-preview>
18. Purview Data Quality REST reference - Get Asset Scores For Asset DQ and Create Data Source operations - <https://learn.microsoft.com/rest/api/purview/purviewdataquality/get-asset-scores-for-asset-dq/get-asset-scores-for-asset-dq?view=rest-purview-purviewdataquality-2026-01-12-preview> and <https://learn.microsoft.com/rest/api/purview/purviewdataquality/create-data-source/create-data-source?view=rest-purview-purviewdataquality-2026-01-12-preview>

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment - this entire feature is **Public Preview**, and the four VERIFY items in
> section 11 should be closed against a pilot tenant first.