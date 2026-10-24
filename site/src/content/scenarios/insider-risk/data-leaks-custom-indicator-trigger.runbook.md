---
part: "runbook"
parent: "insider-risk/data-leaks-custom-indicator-trigger"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management Admins**
(Purview role group) and holds the **Data Connector Admin** role (included by default in both groups).

### Step 2 - Register the Entra app for the connector (scripted, reused unmodified)

Same generic, permission-free app-registration requirement as the HR-connector sibling - no
connector-specific cmdlet exists, and none is needed (the design notes goal 6).

```powershell
Connect-MgGraph -Scopes 'Application.ReadWrite.All'

../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1 `
    -DisplayName 'Purview Insider Risk Indicators Connector (single-purpose)' -WhatIf

$irmConnectorApp = ../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1 `
    -DisplayName 'Purview Insider Risk Indicators Connector (single-purpose)'
```

Record `$irmConnectorApp.AppId`/`.TenantId`; store `.ClientSecret` in a vault immediately. Validate its
hygiene the same way the HR-connector scenario does:

```powershell
../departing-employee-data-theft/validate/Test-HrConnectorAppRegistration.ps1 `
    -DisplayName 'Purview Insider Risk Indicators Connector (single-purpose)'
```

### Step 3 - Prepare a sample CSV of your third-party detections

Build (or export directly from your CASB/DLP/SIEM tool) a small sample CSV matching the shape you intend
to use in production. Microsoft's own worked example - reused here rather than an invented format
 - routes two detection types from one CSV via a `Source` column:

```text
User_Principal_Name,Display_Name,Alert_Severity,Alert_Count,Aggregation_Date,Source_Workload
sarad@contoso.com,Salesforce - Sensitive report downloaded and emailed externally,High,10,2026-09-10T05:52:56.962686Z,Salesforce
bradh@contoso.com,Salesforce - Excessive modifications to sensitive reports,Medium,3,2026-09-10T05:52:56.962686Z,Salesforce
sarad@contoso.com,Dropbox - Sensitive files saved to personal Dropbox,High,14,2026-09-10T05:52:56.962686Z,Dropbox
bradh@contoso.com,Dropbox - Anomalous file copy activity,Medium,5,2026-09-10T05:52:56.962686Z,Dropbox
```

Only `User_Principal_Name` and `Aggregation_Date` (ISO 8601) are mandatory roles - the column *names*
are not fixed by Microsoft; use whatever your export tool actually produces and pass the matching names
to every script below via `-UserColumn`/`-EventTimeColumn`. `Alert_Count` is this example's threshold
field (must be Number-typed); `Source_Workload` is the multi-indicator routing column.

### Step 4 - Create the Insider Risk Indicators (preview) connector (portal, not scriptable)

Purview portal → **Settings** → **Data connectors** → **My connectors** → **Add connector** → select
**Insider Risk Indicators (preview)** → accept the terms of service:

1. **Authentication** page: name the connector, paste `$irmConnectorApp.AppId` from Step 2.
2. **Sample file** page: upload the CSV from Step 3. If routing multiple indicators from one CSV, set
   **Source column** to `Source_Workload` and enter the exact, comma-separated (no spaces) values in
   **Related values in source column** - e.g. `Salesforce,Dropbox`. Otherwise select **None (Single
   source)**. In **Verify sample data and data type**, confirm `Alert_Count` (or your own threshold
   column) is assigned a **Number** data type.
3. **Data mapping** page: map **Event time (UTC time)** to `Aggregation_Date` and **Microsoft 365 user
   email address** to `User_Principal_Name` (both mandatory), then select any other columns to carry
   through as supporting context.
4. **Finish**: review and submit. **Copy the Job ID** - required for Step 5.

Use `deploy/policy/data-leaks-custom-indicator-trigger-policy-manifest.json` as the checklist/reference
while completing this workflow - it is not consumed by any API, and is the durable record of the exact
mapping selected, since none of it can be read back via Graph or PowerShell.

### Step 5 - Validate and upload your indicator data (scripted, idempotent-safe, dry-run first)

```powershell
$secret = Read-Host -AsSecureString -Prompt 'Insider Risk Indicators connector app secret'

# Dry run - validates schema, ISO 8601 parsing, threshold numeric parsing, source-value matching,
# and duplicate (UPN, EventTime) detection. Makes no network call.
./deploy/Send-InsiderRiskIndicatorRecord.ps1 `
    -TenantId $irmConnectorApp.TenantId -AppId $irmConnectorApp.AppId -AppSecret $secret `
    -JobId $JobId -CsvPath './third_party_alerts.csv' `
    -UserColumn 'User_Principal_Name' -EventTimeColumn 'Aggregation_Date' `
    -ThresholdColumn 'Alert_Count' -SourceColumn 'Source_Workload' `
    -RelatedValues 'Salesforce','Dropbox' -WhatIf

# Real upload
./deploy/Send-InsiderRiskIndicatorRecord.ps1 `
    -TenantId $irmConnectorApp.TenantId -AppId $irmConnectorApp.AppId -AppSecret $secret `
    -JobId $JobId -CsvPath './third_party_alerts.csv' `
    -UserColumn 'User_Principal_Name' -EventTimeColumn 'Aggregation_Date' `
    -ThresholdColumn 'Alert_Count' -SourceColumn 'Source_Workload' `
    -RelatedValues 'Salesforce','Dropbox'
```

The script **fails closed** (throws before any network call) on a duplicate `(User_Principal_Name,
Aggregation_Date)` combination unless `-AllowDuplicateRecords` is passed - Microsoft documents this
exact combination as **silently dropped**, not rejected with an error, by the connector itself
(the design notes goal 3). It also fails closed on any source-column value not in `-RelatedValues`,
matching Microsoft's own documented connector-side failure for that mismatch.

Verify the upload in the portal: **Settings** → **Data connectors** → this connector → **Download
log** → confirm `RecordsSaved` matches the row count uploaded.

### Step 6 - Create the custom indicator(s) (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Custom
Indicators** tab → **Add custom indicator**, once per entry in the manifest's `customIndicators[]`:

1. Enter a name and optional description.
2. **Data connector**: select the connector created in Step 4.
3. If the connector used a Source column, select the specific value (`Salesforce` or `Dropbox` in this
   worked example) this indicator represents.
4. **Data from mapping file**: select the Number-typed threshold column (`Alert_Count`), **or** select
   **Use only as a triggering event without any thresholds** - these are mutually exclusive; the latter
   means this indicator can never be given a trigger threshold later.
5. **Add indicator**.

### Step 7 - Resolve and size the policy-scope candidate list (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $ScopeGroupId -MaxUsers 15000 -OutputPath ./data-leaks-custom-indicator-scope-candidates.csv
```

**`-MaxUsers` is 15,000**, identical to and shared cumulatively with **both** sibling scenarios - a
three-way shared pool if all three Data-leaks-template policies are deployed in this tenant. Pass a
lower value if either sibling's policy already consumes part of it.

### Step 8 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data leaks** (base template - not a sibling Data-leaks-family template). Name:
   `Data Leaks - Custom Indicator (Third-Party Connector) Trigger`.
2. **Users and groups**: assign the scope resolved in Step 7.
3. **Triggers for this policy**: select the custom indicator(s) created in Step 6. Set a **custom
   threshold** for each - Microsoft provides no default/recommended threshold for a custom indicator, so
   there is no "Use default thresholds" option to fall back on here, unlike either sibling scenario's
   built-in-indicator triggers.
4. **Policy indicators**: select **Office indicators** and confirm **Cumulative exfiltration detection**
   is selected. Optionally also select the same custom indicator(s) here to additionally score
   already-in-scope users, with their own independently-configured custom threshold.
5. **Review and submit.**

Wait **24 hours** after this step (or any later change to the custom indicators or this policy) before
running Step 5's upload script for the first time - Microsoft documents this sync window explicitly;
uploading during it can leave data unscored.

### Step 9 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

```powershell
../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./data-leaks-custom-indicator-alerts.json
```

### Step 10 - Schedule the upload script and validate

Schedule Step 5's script to run on a recurring cadence (e.g. daily, matching your third-party tool's own
aggregation-export schedule) - the same Windows Task Scheduler pattern
`../departing-employee-data-theft/operations and tuning already documents for the HR connector, reused here
without modification.

```powershell
./validate/Test-DataLeaksCustomIndicatorTriggerSetup.ps1 `
    -CsvPath './third_party_alerts.csv' `
    -UserColumn 'User_Principal_Name' -EventTimeColumn 'Aggregation_Date' `
    -ThresholdColumn 'Alert_Count' -SourceColumn 'Source_Workload' -RelatedValues 'Salesforce','Dropbox' `
    -GroupId $ScopeGroupId
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data leaks` | Same template as both siblings. Confirmed that `Data leaks by priority users` also supports a custom indicator as its triggering event and `Data leaks by risky users` does not; this scenario scopes itself to the base template only |
| Triggering mechanism | Custom indicator(s), imported via the Insider Risk Indicators (preview) connector | The third and final documented Data-leaks-template trigger mechanism this library builds |
| Mandatory CSV column roles | A user-identifier column (any name) + an ISO 8601 event-time column (any name) | Column *names* are not fixed by Microsoft for this connector - a real difference from the HR-connector sibling's fixed 3-column schema |
| Optional CSV column roles | A Number-typed threshold column; a Source column (with an exact-match `-RelatedValues` list) for multi-indicator-from-one-CSV | `deploy/Send-InsiderRiskIndicatorRecord.ps1` `-ThresholdColumn`/`-SourceColumn`/`-RelatedValues` |
| Documented silent-drop condition | Duplicate (user, event-time) combination in the uploaded CSV | Microsoft: "the record is dropped" - no error surfaced by the service; this scenario's upload script fails closed on this by default |
| Documented hard-failure condition | Source-column values not matching the connector's configured "Related values" exactly | Microsoft: "The connector fails if the column values don't match" - checked client-side before upload |
| Custom indicator threshold mode | **Custom only - no default exists** | Microsoft: "Insider Risk Management doesn't provide recommended thresholds for custom indicators." A "Use only as a triggering event without any thresholds" option exists as an alternative to any threshold at all |
| Ingestion webhook mechanics | Identical to the HR-connector sibling's own script: same OAuth token endpoint template, same fixed resource ID, same webhook URL | Confirmed via a direct GitHub fetch of the generic `sample_script.ps1`, not assumed from documentation prose alone - the design notes goal 5 |
| Chunk size default | 5,000 records per upload call | `sample_script.ps1`'s own `RecordsPerCall` default - different from the HR-connector Learn page's own documented 500-row limit |
| Post-configuration-change sync wait | 24 hours | Microsoft's own documented minimum before uploading data after a custom-indicator or policy change |
| Scoring-indicator selection | Office indicators (primary) + Cumulative exfiltration detection (default-on); optionally the same custom indicator(s) also used as scoring indicators | Identical to both sibling scenarios for the built-in portion |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | No HR-connector, Communication-Compliance-trigger, or priority-user-group requirement |
| Maximum actively-scored users for this template | **15,000** - shared cumulatively across **all three** Data-leaks-template scenarios in this library if all are deployed | Per-template limit, not per-trigger-mechanism |
| DLP policy / built-in-exfiltration-indicator dependency | **None** | The defining difference from both sibling scenarios |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, unmodified | |
| Cross-policy disambiguation | Not attempted - same disclosed gap as every IRM scenario in this library | `AlertPolicyId` has no documented policy-name mapping |

## Operations and tuning

- **The threshold decision for a custom indicator has no "default" fallback - treat it as a
  first-class tuning lever from day one, not something to defer.** Unlike either sibling scenario's
  built-in indicators, there is no "Use default thresholds (Recommended)" option for a custom indicator
  - every custom indicator used as a trigger or scoring indicator needs a deliberately chosen numeric
  value from the start.
- **Monitor the upload pipeline's own health independently - a failed scheduled upload produces no
  native Microsoft alert.** Unlike a native Microsoft connector whose health is visible to Microsoft
  itself, this pipeline's only failure signal is the connector's own **Download log** (a manual pull) or
  whatever exit-code/logging your task scheduler captures from
  `deploy/Send-InsiderRiskIndicatorRecord.ps1`. Wire the scheduled task's exit code into existing
  infrastructure monitoring rather than relying on someone remembering to check the portal log.
- **Re-verify the third-party source's own detection coverage and tuning independently - this
  scenario inherits whatever gaps and false-positive/negative rates the upstream CASB/DLP/SIEM
  aggregation already has.** Insider Risk Management scores what it's given; it cannot compensate for a
  third-party tool that under- or over-detects.
- **Coordinate policy naming explicitly if deploying alongside either sibling scenario** - same
  reasoning both siblings already document for each other, now a three-way coordination point.
- **Re-scope on group-membership change**, same reasoning as every group-scoped IRM template in this
  library - *Security Policy Violations (base template)* (operations and tuning), not repeated in full here.
- **Track the 15,000-user cap across all three Data-leaks-template siblings deliberately** - there is no
  Graph/REST usage-count API to check current cumulative usage; maintain the sizing math manually if
  more than one is deployed.
- **Re-run the 24-hour sync wait after every custom-indicator or policy edit, not just the first
  deployment** - the same wait applies to any subsequent change, not only initial setup.
- **Restrict write access to the CSV export path and the scheduled-task host as a security control
  input, not just an operational convenience** - the known limitations discloses this pipeline validates shape, not
  provenance; treat that file path and host with the same access discipline as any other input that can
  influence a security alerting pipeline's output.

## Rollback and decommission

See the rollback runbook. Quick reference: pausing the scheduled upload script, narrowing policy scope, or
raising a threshold is reversible in seconds; deleting the connector, a custom indicator, the policy, or
revoking the app registration's certificate is not.

## References

1. Set up a connector to import third-party insider risk detections (preview) - the full three-step
   process, CSV column-name flexibility ("not required parameters"), mandatory UPN/event-time roles,
   Number-typed threshold-column requirement, Source-column multi-indicator worked example and its exact
   documented failure mode, the UPN+timestamp uniqueness/silent-drop requirement, the 24-hour post-update
   sync wait, the `webhook.ingestion.office.com` firewall allowlist requirement, and the **Data Connector
   Admin** role requirement - confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/import-insider-risk-indicators>
2. Configure policy indicators in Insider Risk Management - "Built-in indicators vs. custom indicators"
   and "Custom indicators" sections: the three-step create-and-use flow, the custom-threshold-only rule
   ("don't use the default thresholds"), the "Use only as a triggering event without any thresholds"
   option, and "Insider Risk Management doesn't provide recommended thresholds for custom indicators" -
   confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#custom-indicators>
3. Get started with Insider Risk Management - "Configure Insider Risk Indicator (preview) connector"
   (Step 4) and Step 6's note pointing custom-trigger/indicator configuration at the Custom indicators
   article - confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-configure#configure-insider-risk-indicator-preview-connector>
4. Learn about Insider Risk Management policy templates - confirms custom indicators apply to "any
   *Data theft* or *Data leaks* policies" (imprecise wording flagged in section 11) and the base `Data leaks`
   template's own triggering-event/prerequisite table, reused unmodified from both sibling scenarios -
   confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-policy-templates>
5. Sample script source for the generic M365 compliance connector ingestion family - fetched directly
   from GitHub during this build; confirmed identical OAuth token endpoint template, fixed resource ID,
   and webhook URL to the already-grounded HR-connector sibling script, and confirmed a different
   default chunk size (5,000 via `RecordsPerCall`) from the HR-connector Learn page's own documented
   500-row limit -
   <https://github.com/microsoft/m365-compliance-connector-sample-scripts/blob/main/sample_script.ps1>
6. Limits in Insider Risk Management - "Maximum number of users in scope for a policy template": Data
   leaks = **15,000**, reused unmodified from both sibling scenarios' own already-grounded citation -
   <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
7. *Data Leaks (base template)*, *Data Leaks (exfiltration-activity trigger)*, and
   *Departing Employee Data Theft*/the design notes - this scenario's direct siblings, whose own
   already-grounded facts (max-users cap, population mechanism, the HR-connector app-registration and
   ingestion-webhook pattern this scenario reuses/adapts) are cross-referenced rather than re-verified
   independently. `security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1`,
   `departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1`,
   `departing-employee-data-theft/validate/Test-HrConnectorAppRegistration.ps1`, and
   `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` - reused unmodified.
8. alert resource type - `AlertPolicyId`, `DetectionSource` properties -
   <https://learn.microsoft.com/graph/api/resources/security-alert>
9. List group transitive members (OData cast, required `ConsistencyLevel: eventual` header,
   `GroupMember.Read.All` among the higher-privileged application permissions) -
   <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
10. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) -
    <https://learn.microsoft.com/graph/permissions-reference>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn before a
> customer-facing assessment or sale. This scenario's citations were grounded via a direct Microsoft
> Learn MCP fetch of the URLs above, plus a direct GitHub source fetch of the generic ingestion sample
> script (ref 5) - a materially stronger grounding posture than a WebSearch-snippets-only build.
> Remaining facts that could not be corroborated with reasonable confidence are explicitly flagged
> `VERIFY` above and in the design notes rather than asserted.