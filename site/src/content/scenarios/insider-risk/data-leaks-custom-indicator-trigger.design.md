---
part: "design"
parent: "insider-risk/data-leaks-custom-indicator-trigger"
---
## 1. Problem statement

`scenarios/insider-risk/data-leaks/` and `scenarios/insider-risk/data-leaks-exfiltration-activity-trigger/`
build the base **Data leaks** template's two Microsoft-native triggering-event options: a DLP-policy
match, and a built-in exfiltration indicator. Both are bounded to what Insider Risk Management can see
natively — Exchange Online/SharePoint Online/OneDrive activity, plus (if Defender for Cloud Apps is
connected and pay-as-you-go billing is enabled) a fixed list of cloud-storage/cloud-service apps (Box,
Dropbox, Google Drive, Amazon S3, Azure). Neither sibling scenario can bring in a detection from a
non-Microsoft workload that isn't on that fixed cloud-indicator list — a third-party CASB, a SaaS app
with no native Microsoft connector (Salesforce is Microsoft's own worked example), or a SIEM's own
correlation output (Microsoft Sentinel, Splunk).

`PROGRESS.md`'s own follow-up backlog, recorded while building the exfiltration-activity-trigger
sibling, named this gap directly as a non-goal of that fragment: "Consider a companion scenario or
script using the **Insider Risk Indicators (preview)** connector to bring a non-Microsoft-workload
detection... in as a custom trigger for this same base `Data leaks` template — explicitly out of scope
for this fragment... a materially different building block (a new data connector) from either existing
worked example." This fragment is that companion — the **third** trigger mechanism this library builds
for the same base `Data leaks` template.

## 2. Design goals

1. **Ground the actual three-step process end to end, not just the connector-creation step.**
   Microsoft's own documentation frames this as three sequential, cross-referenced articles: (1) create
   the **Insider Risk Indicators (preview)** connector (`import-insider-risk-indicators`), (2) create a
   **custom indicator** from it (`insider-risk-management-settings-policy-indicators#custom-indicators`),
   (3) use the custom indicator as a trigger and/or scoring indicator with a threshold in the policy
   workflow (`insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy`).
   All three were fetched directly from Microsoft Learn during this build (not WebSearch snippets) and
   are reflected as three distinct README §5 steps, not collapsed into one.
2. **The CSV schema for this connector is genuinely, documentedly flexible — column names are not fixed
   the way the HR-connector sibling's schema is.** Microsoft states this explicitly: "The column names
   described in the following sections are examples, not required parameters. You can use any column
   names in your CSV files." Only two roles are mandatory regardless of name: a Microsoft 365 user
   email/UPN column, and an event-time column in ISO 8601 format (`yyyy-mm-ddThh:mm:ss.nnnnnn+|-hh:mm`).
   A third role — a column used as a threshold value — is optional but, if used, must be a *Number*
   data type. This is a materially different validation problem from
   `departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`'s fixed three-column schema
   check, so this fragment's own upload script (`deploy/Send-InsiderRiskIndicatorRecord.ps1`) takes the
   column names as parameters rather than hard-coding them — see §5.
3. **Document, and defensively check for, two real silent-data-loss/failure modes Microsoft's own
   documentation discloses, rather than only the happy path.**
   - **Duplicate UPN + event-time combinations are silently dropped, not rejected with an error**:
     "Make sure that all combinations of UPN and timestamp to be imported are unique. If any record in
     the uploaded CSV file contains the same timestamp and UPN as other records in the file, the record
     is dropped." A security-relevant data-import pipeline that silently drops rows with no error is a
     real operational risk if unmonitored — `deploy/Send-InsiderRiskIndicatorRecord.ps1` checks for this
     client-side before upload and fails closed by default (§5, §6).
   - **The `Source column` values in the CSV must exactly match the values entered in the connector's
     own `Related values in source column` field, or the connector fails**: "Make sure that the values
     you enter in the Related values in source column field match the values in the Source column list.
     The connector fails if the column values don't match." This fragment's upload script also checks
     this client-side when a source column is configured (§5).
4. **Reuse this template's already-grounded facts unmodified — same discipline as the exfiltration-
   activity-trigger sibling's own design goal 1.** The 15,000-actively-scored-user cap, the plain-Entra-
   group population mechanism, the reused scope-candidate script, and the reused alert-export script all
   apply identically here and are cross-referenced, not re-derived. The cap is now **shared cumulatively
   across three sibling policies** if all three Data-leaks-template scenarios in this library are
   deployed in the same tenant — a sizing point sharper here than in either prior sibling, since this is
   now the third policy drawing from the same 15,000-user pool.
5. **Ground the ingestion webhook mechanics by independently confirming they're identical to the
   already-grounded HR-connector sibling's own mechanics — don't assume, verify.** Microsoft's
   `import-insider-risk-indicators` article names the same underlying sample script family
   (`https://github.com/microsoft/m365-compliance-connector-sample-scripts`) this repo's HR-connector
   scenario (`departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`) already grounded, but
   points at the family's generic `sample_script.ps1` rather than the HR-specific
   `upload_termination_records.ps1`. This build fetched `sample_script.ps1` directly from GitHub and
   confirmed it uses the **identical** OAuth token endpoint template
   (`https://login.windows.net/{tenantId}/oauth2/token`), the **identical** fixed resource ID
   (`https://microsoft.onmicrosoft.com/86dfdabb-5089-4a0c-880a-cfa5a790c5b1`), and the **identical**
   webhook upload URL (`https://webhook.ingestion.office.com/api/signals`) as the already-grounded HR
   connector script — confirming this is one shared, generic M365 compliance-connector ingestion
   surface, not a coincidental resemblance. The one confirmed difference: `sample_script.ps1`'s own
   default chunk size is **5,000** records per call (`RecordsPerCall`, configurable), not the
   HR-connector page's own documented 500-row-per-file limit — `deploy/Send-InsiderRiskIndicatorRecord.ps1`
   defaults to 5,000 for this reason, sourced to the direct GitHub fetch, not silently copied from the
   HR sibling's own different, page-documented figure.
6. **The Entra app registration step is generic and identical in shape to the HR-connector sibling's own
   Step 1 — reuse the existing script, don't fork it.** Microsoft's `import-insider-risk-indicators`
   Step 1 asks for the same three artifacts (app ID, app secret, tenant ID) with no API permissions
   named, the same shape `departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1` already
   scripts generically (no HR-specific logic in that script beyond its default `-DisplayName`). This
   fragment reuses that script and its matching validation script
   (`departing-employee-data-theft/validate/Test-HrConnectorAppRegistration.ps1`) unmodified, called
   with a new `-DisplayName`, instead of writing a near-duplicate.
7. **Ground which policy templates actually support custom indicators, without overstating Microsoft's
   own imprecise wording.** The custom-indicators section states plainly: "add the custom indicator to
   an insider risk policy in any *Data theft* or *Data leaks* policies." This is looser than the named
   policy-template list elsewhere in the same documentation set (`Data theft by departing users`,
   `Data leaks`, `Data leaks by priority users`, `Data leaks by risky users`) — it is not clear from this
   wording alone whether "Data theft" here means only `Data theft by departing users` or is shorthand for
   a template family, nor whether "Data leaks" covers all three named Data-leaks templates or only the
   base one. This fragment scopes itself to the base `Data leaks` template only — the scope
   `PROGRESS.md`'s own follow-up item named — and states the broader-template-applicability question as
   an open, unresolved reading of Microsoft's own wording rather than guessing either direction
   (`README.md` §11).
8. **Do not fabricate a threshold-recommendation mechanism for custom indicators.** Microsoft states
   plainly elsewhere in the same settings article: "Insider Risk Management doesn't provide recommended
   thresholds for custom indicators." Real-time analytics (preview) explicitly does not cover them
   either. This fragment's docs and manifest require **custom** thresholds for any custom indicator used
   as a trigger, consistent with the documented rule: "After selecting your custom trigger or indicator,
   make sure to set a custom threshold (don't use the default thresholds)."

## 3. Why this is its own scenario folder, not an edit to a sibling's files

Same precedent already established twice for this exact template family
(`data-leaks-by-priority-users`, `data-leaks-by-risky-users`, and most directly
`data-leaks-exfiltration-activity-trigger`): a materially different triggering-event mechanism — here, a
wholly new building block (a data connector importing external, non-Microsoft-workload data) rather than
a different combination of built-in indicators — warrants its own scenario folder.
`data-leaks-exfiltration-activity-trigger/design.md` §7 explicitly named this connector as future,
separately-scoped work, not something to fold into that fragment.

## 4. Policy architecture (what's deployed where)

| Component | Mechanism | Scriptable? |
|---|---|---|
| Entra app registration for the connector | **Reused unmodified**: `../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1 -DisplayName '<this connector's name>'` | **Yes** — reused, no connector-specific logic needed (§2 goal 6) |
| Insider Risk Indicators (preview) connector (Authentication, Sample file, Data mapping pages) | Purview portal → Settings → Data connectors → My connectors → Add connector | No — portal-only; `deploy/policy/data-leaks-custom-indicator-trigger-policy-manifest.json` is a reference, not an API payload |
| Indicator-data CSV preparation, client-side schema/dedup/source-value validation, and chunked upload | `deploy/Send-InsiderRiskIndicatorRecord.ps1` (new — this fragment's own contribution) | **Yes** — talks directly to the documented ingestion webhook, the same surface the HR-connector sibling already uses (§2 goal 5) |
| Custom indicator creation (Settings → Policy indicators → Custom Indicators tab) | Purview portal | No — portal-only; recorded in the manifest |
| Scope-candidate resolution | `../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` (reused unmodified, `-MaxUsers 15000`) | **Yes** — reused, identical population mechanism (§2 goal 4) |
| IRM policy (template, custom-indicator trigger/scoring selection + threshold, scope) | Purview portal → Insider Risk Management → Policies → Create policy | No — portal-only; recorded in the manifest |
| Alert export | `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` (reused unmodified) | **Yes** — reused, no Defender for Endpoint signal to join against |
| App-registration hygiene validation | **Reused unmodified**: `../departing-employee-data-theft/validate/Test-HrConnectorAppRegistration.ps1 -DisplayName '<this connector's app>'` | **Yes** — reused |
| Connector/indicator/policy configuration validation | `validate/Test-DataLeaksCustomIndicatorTriggerSetup.ps1` (new) | **Yes** — automated CSV-schema/Graph-session checks + manual portal checklist |

## 5. Data flow

A third-party CASB, DLP tool, or SIEM (Microsoft's own worked examples: Salesforce and Dropbox activity,
aggregated by Microsoft Sentinel or Splunk) produces **pre-aggregated** detection records — Microsoft is
explicit that raw signals cannot be imported, only aggregations. An operator (or a scheduled export job
on the third-party side) writes those aggregations to a CSV with, at minimum, a user-identifier column
and an ISO-8601 event-time column, plus optionally a `Source` column (to route different aggregation
types to different custom indicators from one CSV, Microsoft's own multi-indicator worked example) and a
`Number`-typed column to serve as a threshold value.

`deploy/Send-InsiderRiskIndicatorRecord.ps1` validates that CSV against a **caller-specified** column
mapping (not a fixed schema, §2 goal 2) — mandatory user/event-time columns present and well-formed,
optional threshold column numeric-parseable for every row, optional source-column values matching a
caller-specified allow-list exactly (§2 goal 3, second bullet) — and checks for duplicate
user+event-time combinations, which the connector would otherwise silently drop (§2 goal 3, first
bullet). It then acquires an OAuth client-credentials token and uploads the validated CSV in chunks to
the same `webhook.ingestion.office.com/api/signals` endpoint the HR-connector sibling already uses,
confirmed identical by a direct GitHub source fetch (§2 goal 5).

Once data has flowed at least once, the operator creates one custom indicator per distinct `Source`
value (or one indicator for a single-source CSV) in Insider Risk Management settings, pointing it at the
connector and, if a threshold column was mapped, that column. The custom indicator is then selected on
the base `Data leaks` policy's **Triggers** page (to bring a user into scope) and/or **Indicators** page
(to score an already-in-scope user), each with its own **mandatory custom threshold** — Microsoft
provides no default/recommended threshold for a custom indicator (§2 goal 8).

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Worked example | Microsoft's own documented Example 2 shape: Salesforce + Dropbox aggregated alerts routed via a `Source` column into two custom indicators from one connector/CSV | Reuses Microsoft's own worked, grounded example rather than inventing a fictitious third-party tool's export format (`AGENTS.md` §4) |
| CSV column-name handling | Caller-specified via script parameters (`-UserColumn`, `-EventTimeColumn`, `-ThresholdColumn`, `-SourceColumn`, `-RelatedValues`), not hard-coded | Microsoft explicitly documents column names as non-fixed for this connector — a fixed-schema check (the HR-connector sibling's own approach) would misrepresent this connector's actual flexibility (§2 goal 2) |
| Duplicate UPN+event-time handling | Hard error on a real (non-`-WhatIf`) run unless `-AllowDuplicateRecords` is explicitly passed; always reported (count and offending rows) even under `-WhatIf` | Microsoft documents this as a **silent** drop with no error from the service itself — the one place in this pipeline this repo can catch a real, undisclosed-at-runtime data-loss mode before it happens, so it defaults to fail-closed rather than a soft warning (§2 goal 3) |
| Source-column value validation | Hard error if any row's source-column value isn't in the caller-supplied `-RelatedValues` list, before any upload attempt | Microsoft documents a hard connector-side failure ("The connector fails if the column values don't match") for this exact mismatch — failing the same way client-side, before spending an upload attempt, is strictly better than discovering it in the connector's log after the fact |
| Chunk size default | 5,000 records per call | Confirmed via a direct GitHub fetch of the actual `sample_script.ps1` this Microsoft Learn article references — not copied from the HR-connector sibling's own different, page-documented 500-row limit (§2 goal 5) |
| App registration | Reuse `Register-HrConnectorApp.ps1`/`Test-HrConnectorAppRegistration.ps1` unmodified, new `-DisplayName` | Confirmed generic (no connector-specific logic) and confirmed the underlying OAuth resource is identical across both connectors (§2 goals 5–6) |
| Template scope | Base `Data leaks` template only | The exact scope `PROGRESS.md`'s follow-up item named; Microsoft's own "Data theft or Data leaks policies" wording for which templates support custom indicators is not precise enough to safely extend further in this fragment (§2 goal 7) |
| Threshold policy | Custom thresholds only, both in this scenario's own docs and enforced as a checklist item in `validate/` | Microsoft provides no default/recommended threshold for a custom indicator, and disallows setting any trigger threshold at all if "Use only as a triggering event without any thresholds" is selected (§2 goal 8) |
| Max-users cap | 15,000, shared cumulatively across every `Data leaks`-template policy in the tenant — now a **three-way** shared pool if every sibling in this library is deployed | Same Microsoft Learn "Limits in Insider Risk Management" table already cited by both sibling scenarios (§2 goal 4) |

## 7. Non-goals

- **Does not build the DLP-policy trigger or the built-in-exfiltration-indicator trigger** — those are
  `data-leaks/` and `data-leaks-exfiltration-activity-trigger/` respectively.
- **Does not perform the third-party detection or aggregation itself.** This scenario starts from an
  already-aggregated CSV — building a Salesforce/Dropbox/CASB export pipeline, a Sentinel/Splunk
  correlation rule, or any other upstream aggregation job is explicitly out of scope; those systems and
  their own licensing are the buyer's existing tooling, not something this library provisions.
- **Does not attempt to resolve which exact named policy templates beyond the base `Data leaks`
  template support custom indicators** — flagged as an open reading of Microsoft's own imprecise wording
  (§2 goal 7, `README.md` §11), not guessed in either direction.
- **Does not build a Power Automate-based upload trigger** (Microsoft's own optional Step 7 in
  `import-insider-risk-indicators`) — the scheduled-script pattern this library already uses for the HR
  connector (Windows Task Scheduler, `README.md` §8) is reused instead for consistency across this
  repo's connector-based scenarios; a Power Automate variant is a candidate future fragment, not built
  here.
- **Does not configure Adaptive Protection** — same non-goal as every other base Insider Risk Management
  scenario in this library.
- **Does not attempt cross-policy alert disambiguation** — same disclosed `AlertPolicyId` gap as every
  Insider Risk Management scenario in this library, sharper here with three Data-leaks-template siblings
  potentially coexisting.
- **Does not fabricate a case-sensitivity rule for source-column value matching.** Microsoft's own
  wording ("make sure that the values... match") does not state whether the comparison is
  case-sensitive; `deploy/Send-InsiderRiskIndicatorRecord.ps1` treats it as case-sensitive (the stricter,
  fail-safer assumption) and this is flagged as an open VERIFY, not asserted as confirmed Microsoft
  behavior (`README.md` §11).
