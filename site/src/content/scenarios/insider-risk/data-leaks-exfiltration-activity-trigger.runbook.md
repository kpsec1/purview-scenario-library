---
part: "runbook"
parent: "insider-risk/data-leaks-exfiltration-activity-trigger"
---
## Implementation steps

### Step 1 - Assign permissions

Confirm the operator is a member of **Insider Risk Management** or **Insider Risk Management
Admins** (Purview role group). No HR/Communication Compliance/Defender-for-Endpoint/DLP role is
needed anywhere in this scenario - a materially shorter prerequisite list than either data-leaks
sibling.

### Step 2 - Turn on the built-in indicators this policy will use (portal, one-time, tenant-wide)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Built-in
Indicators**: confirm the specific exfiltration indicators you intend to use - as a trigger, a
scoring indicator, or both - are turned on. An indicator that isn't enabled here can't be selected
later in the policy-creation workflow (the workflow's own **Turn on indicators** prompt links back
to this same settings page).

### Step 3 - Resolve and size the policy-scope candidate list (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $ScopeGroupId -MaxUsers 15000 -WhatIf

# Resolve, dedupe, filter to enabled accounts, check against the confirmed cap
../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 `
    -GroupId $ScopeGroupId -MaxUsers 15000 -OutputPath ./data-leaks-exfil-trigger-scope-candidates.csv
```

**`-MaxUsers` is 15,000** - the same base `Data leaks` template row in Microsoft's "Limits in
Insider Risk Management" table *Data Leaks (base template)* (the configuration reference and the references) already confirms via a direct
Microsoft Learn fetch. This cap is **shared cumulatively with the DLP-trigger sibling** (and any
other policy built from this exact template) - it is a per-template limit, not a per-trigger-event
limit. Pass a lower value if another `Data leaks`-template policy already consumes part of it.

### Step 4 - Create the Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy**:

1. Template: **Data leaks**. Confirm this is the base template and not `Data leaks by risky users`
   or `Data leaks by priority users` - all three share overlapping naming in the template picker.
2. Name: `Data Leaks - Exfiltration Activity Trigger` (distinct from the DLP-trigger sibling's own
   `Data Leaks` policy name, so both can coexist in the same tenant as two separate policies - a
   single policy cannot use both trigger types at once, see the configuration reference and the known limitations). The template and name can't
   be changed after policy creation - confirm before continuing.
3. **Users and groups**: assign the scope resolved in Step 3. If you intend to use **real-time
   analytics (preview)** threshold recommendations (optional), scope to **Include all users and
   groups** instead - that feature requires it.
4. **Triggers for this policy**: select **User performs an exfiltration activity**, then choose one
   or more of the listed built-in indicators as the trigger (only indicators turned on in Step 2
   are selectable).
5. **Trigger threshold** (sub-step 5 of this same policy-creation workflow - not a separate
   top-level step in this page): choose **Use default thresholds (Recommended)**, or **Use
   custom thresholds for the triggering events** and set a level per selected trigger indicator.
   Microsoft does not publish the specific numeric values behind the default option for any
   indicator - if default behavior needs to be documented precisely for a customer commitment, use
   custom thresholds instead so the exact values are explicit and recorded in the configuration
   manifest referenced below. See the configuration reference's worked example for how a custom threshold level maps to
   daily event counts.
6. **Policy indicators** (sub-step 6 - a separate page, a separate decision from sub-step 5's
   trigger threshold above): select **Office indicators** (SharePoint Online downloads/syncing,
   sharing internal files/folders externally, printing files, copying data to personal cloud
   storage/messaging services) - this template's primary, built-in scoring category. Optionally
   add Communication Compliance content indicators, generative AI app indicators, and/or cloud
   storage/cloud service indicators (requires those apps connected in Microsoft Defender for Cloud
   Apps and pay-as-you-go billing).
7. Select **Cumulative exfiltration detection** (enabled by default for this template - confirm it
   is actually selected).
8. **Decide whether to use default or custom indicator thresholds** for the **scoring** indicators
   selected in sub-step 6 above - this is Microsoft's own separate workflow page from sub-step 5's
   trigger threshold, not the same setting reused. Choose **Use default thresholds for all
   indicators** or **Specify custom thresholds**, independently of whatever was chosen for the
   trigger.
9. **Review and submit.**

Use `deploy/policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json` as the checklist/
reference while completing this workflow - it is not consumed by any API, and is the durable record
of exactly which indicators and threshold mode were selected at each of the two independent
decision points above (sub-steps 5 and 8), since neither can be read back via Graph or PowerShell.

### Step 5 - Export correlated alerts for SIEM/ticketing integration (scripted, read-only, reused)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1 `
    -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./data-leaks-exfil-trigger-alerts.json
```

Same reuse rationale as the DLP-trigger sibling: no Microsoft Defender for Endpoint signal to join
against.

**Caveat carried over from every IRM scenario in this library:** if more than one Insider Risk
Management policy is deployed in the tenant - including this scenario's own DLP-trigger sibling, if
both are deployed - this export cannot tell which policy produced a given alert; `AlertPolicyId`
has no documented way to map back to a named Purview policy.

### Step 6 - Validate

```powershell
./validate/Test-DataLeaksExfiltrationActivityTriggerSetup.ps1 -GroupId $ScopeGroupId
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy template | `Data leaks` | Same template as the DLP-trigger sibling - not found labeled preview in this build's grounding; re-verify at deploy time. Cannot be changed after creation |
| Triggering event (this scenario's worked example) | **User performs an exfiltration activity** - one or more built-in indicators, default/custom/anomalous-activity thresholds | The DLP-trigger sibling's own documented alternative (*Data Leaks (base template)* (the configuration reference)) - this scenario is that alternative's full worked example |
| Trigger-indicator threshold mode | Operator choice: **Use default thresholds (Recommended)** or **Use custom thresholds for the triggering events** | Microsoft's exact default numeric values are unpublished for any indicator - **VERIFY (portal)** before stating a specific default figure to a customer |
| Worked threshold example (Microsoft-published, illustrative only) | SharePoint-download custom thresholds: **10+/day → low** impact, **20+/day → medium** impact, **30+/day → high** impact on risk score/alert severity | Sourced directly from "Configure policy indicators in Insider Risk Management" - Microsoft's own words: "For example, suppose you decide..." - not a stated universal default for this or any other indicator |
| Anomalous-activity trigger option | **"Activity is above user's usual activity for the day"** - available for indicators that support it (not all); dynamically computed per user rather than a fixed daily count | Selectable in place of a fixed threshold where offered; if not listed for a given indicator, it isn't available and must be enabled first in Insider risk settings if merely unselectable |
| Real-time analytics (preview) threshold recommendations | Optional; requires insider risk analytics enabled and this policy scoped to **Include all users and groups** | Gives data-driven recommendations based on the previous 10 days of activity; not usable for custom indicators or indicator variants |
| Scoring-indicator threshold mode (separate decision from the trigger's) | Operator choice: **Use default thresholds for all indicators** or **Specify custom thresholds** | A distinct page/decision in the same policy-creation workflow - the design notes goal 2/section 5 |
| Primary scoring indicator category | **Office indicators** (built-in) - SharePoint Online downloads/syncs, external file/folder sharing, printing files, copying to personal cloud storage/messaging services | Identical to the DLP-trigger sibling; no additional connector required |
| Cumulative exfiltration detection | **Enabled by default** for this template | Confirm selected at policy creation, not assumed |
| Optional scoring indicators | Communication Compliance content indicators; generative AI app indicators (Prompt Shields, Protected material detection) | Both documented as selectable for this template - identical to the DLP-trigger sibling |
| Optional cloud indicators | Cloud storage (Box, Dropbox, Google Drive) / cloud service (Amazon S3, Azure) indicators | Confirmed applicable to this template (*Data Leaks (base template)* (the configuration reference)); requires Defender for Cloud Apps + pay-as-you-go billing |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | No HR-connector, Communication-Compliance-trigger, or priority-user-group requirement |
| Maximum actively-scored users for this template | **15,000** - same row as the DLP-trigger sibling, **shared cumulatively** across every policy built from this exact template regardless of which trigger event a given policy uses | Per-template limit, not per-trigger-event |
| DLP policy dependency | **None** | The defining difference from the sibling scenario |
| Defender for Endpoint dependency | **None** | |
| User-identity privacy | Pseudonymized (Microsoft default) | Not disabled by this scenario |
| Alert export mechanism | Reused: `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, unmodified | The plain, non-MDE-joining variant |
| Whether both triggering-event types can be combined on one policy | **Resolved: no** - one triggering-event configuration per policy, set to either mechanism, not both | the design notes goal 6/section 6; the known limitations |
| Cross-policy disambiguation | Not attempted - same disclosed gap as every IRM scenario in this library | `AlertPolicyId` has no documented policy-name mapping |

## Operations and tuning

- **Two independent threshold decisions, not one - re-tune both deliberately, not just the one you
  remember configuring.** A common operational mistake this scenario's own review surfaced:
  treating "the threshold" as a single setting. Lowering the trigger-indicator threshold brings
  more users into scope sooner; lowering a scoring-indicator threshold raises alert severity sooner
  for users already in scope. Confirm which one actually needs adjustment before changing either.
- **If real-time analytics (preview) is used, re-run it periodically as organizational activity
  norms shift** - its recommendations are based on a rolling 10-day window, not a one-time
  calculation; a threshold tuned for a prior activity baseline can under- or over-alert as normal
  usage patterns change.
- **Coordinate policy naming and trigger choice explicitly if deploying this scenario alongside the
  DLP-trigger sibling in the same tenant** - a single policy cannot use both trigger mechanisms, so deploy them as two separate, distinctly-named policies (as this scenario's own step 4 of the implementation steps already directs) rather than assuming either can absorb the other's trigger mechanism.
- **Re-scope on group-membership change**, same reasoning as every group-scoped IRM template in
  this library - *Security Policy Violations (base template)* (operations and tuning), not repeated here in full.
- **Cumulative exfiltration detection depends on Microsoft Entra data sharing** for peer-group
  accuracy - same disclosed dependency as *Data Leaks (base template)* (operations and tuning).
- **If cloud-app indicators are enabled, monitor Defender for Cloud Apps connector health
  independently** - a disconnected connector silently stops contributing to this policy's scoring.
- **Pair with the HR-connector-triggered siblings for defense in depth, not as a replacement** -
  same framing *Data Leaks (base template)* (operations and tuning) already establishes for the DLP-trigger sibling, applies
  identically here.
- **Confirm at deployment sign-off which specific indicators were selected as the trigger versus as
  a scoring indicator** - the two lists can differ, and a reviewer assuming they're identical could
  misjudge what actually brings a user into this policy's scope.
- **Re-check tenant-wide indicator enablement (Settings → Policy indicators) whenever another team
  changes it, not just at initial deployment.** Because a trigger indicator must first be turned on
  tenant-wide before it's selectable in this policy, another administrator disabling
  that same indicator later - for an unrelated reason, e.g. reducing noise on a different policy -
  silently removes it from this policy's trigger set too, with no error or notification. This is
  the same class of shared-tenant-wide-setting risk *Data Leaks (base template)* (operations and tuning) documents for its own
  global DLP-alerts indicator, applied here to built-in indicator enablement instead.

## Rollback and decommission

See the rollback runbook. Quick reference: narrowing policy scope, changing a trigger or scoring threshold,
or turning off an optional indicator is reversible in seconds; deleting the policy or revoking an
app registration's certificate is not.

## References

1. Get started with Insider Risk Management - Step 6 "Create an Insider Risk Management policy,"
   sub-steps 12/14/15: the "User matches a data loss prevention (DLP) policy" vs. "User performs an
   exfiltration activity" triggering-event choice, phrased as alternative "if you select X... if
   you select Y..." branches; the trigger-indicator default-vs-custom-vs-anomalous threshold choice
   (a separate decision from the later policy/scoring-indicator threshold page, sub-step 17) -
   confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
2. Learn about Insider Risk Management policy templates - Data leaks template description and the
   "Policy template prerequisites and triggering events" table: "Data leak policy activity that
   creates a High severity alert **or** built-in exfiltration event triggers," prerequisite "DLP
   policy configured for High severity alerts... **OR** Customized triggering indicators" -
   confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#data-leaks>
3. Configure policy indicators in Insider Risk Management - "Indicator level settings": the fully
   worked SharePoint-download custom-threshold example (10+/20+/30+ events per day → low/medium/
   high impact on risk score and alert severity), explicitly framed as an illustrative example, not
   a stated default; the "Activity is above user's usual activity for the day" anomalous-activity
   trigger option; "Use real-time analytics recommendations to set thresholds" (preview, requires
   insider risk analytics enabled and "Include all users and groups" scope, 10-day activity
   window); "you can only modify triggering events for policies created from the Data leaks or
   Data leaks by priority users templates" - confirmed via a direct Microsoft Learn fetch -
   <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#indicator-level-settings>,
   <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#use-real-time-analytics-recommendations-to-set-thresholds>
4. Limits in Insider Risk Management - "Maximum number of users in scope for a policy template":
   Data leaks = **15,000**, a per-template (not per-trigger-event) limit - already confirmed via a
   direct Microsoft Learn fetch for the DLP-trigger sibling scenario, reused here unmodified -
   <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>
5. *Data Leaks (base template)* and the design notes - this scenario's direct sibling and template source,
   whose own already-grounded facts (max-users cap, population mechanism, cumulative exfiltration
   detection default, optional indicator applicability) this scenario reuses and cross-references
   rather than re-verifying independently. `security-policy-violations/deploy/
   Get-SecurityPolicyViolationsScopeCandidates.ps1` and `departing-employee-data-theft/deploy/
   Export-InsiderRiskAlerts.ps1` - reused unmodified.
6. alert resource type - `AlertPolicyId`, `DetectionSource` properties -
   <https://learn.microsoft.com/graph/api/resources/security-alert>
7. List group transitive members (OData cast, required `ConsistencyLevel: eventual` header,
   `GroupMember.Read.All` among the higher-privileged application permissions) -
   <https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0>
8. Microsoft Graph permissions reference (`GroupMember.Read.All`, `SecurityAlert.Read.All`) -
   <https://learn.microsoft.com/graph/permissions-reference>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale. This scenario's citations were grounded via a direct
> Microsoft Learn MCP fetch of the URLs above, from a session whose network environment did not
> block direct fetches (a materially stronger grounding posture than the DLP-trigger sibling
> scenario's original WebSearch-only build). Remaining facts that could not be corroborated with
> reasonable confidence are still explicitly flagged `VERIFY` above and in the design notes rather than
> asserted.