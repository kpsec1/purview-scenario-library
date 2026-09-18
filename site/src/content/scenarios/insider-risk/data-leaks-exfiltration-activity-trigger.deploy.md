---
part: "deploy"
parent: "insider-risk/data-leaks-exfiltration-activity-trigger"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, recording BOTH independent threshold decisions (trigger and scoring) this trigger path involves, since neither can be read back via any API.",
  "policyName": "Data Leaks - Exfiltration Activity Trigger",
  "policyTemplate": "Data leaks",
  "templateStatus": "Same base template as scenarios/insider-risk/data-leaks/ - not found labeled preview in this build's grounding. Re-verify GA/preview status against the live portal before a customer-facing commitment.",
  "scope": {
    "users": "A plain Entra security group (or groups), resolved via ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 (reused unmodified) - no HR-connector, priority-user-group, or employment-stressor requirement.",
    "maxUsersInScope": 15000,
    "note": "Confirmed via a direct Microsoft Learn fetch (README.md §12 ref 4). This is a PER-TEMPLATE cap, shared cumulatively with the DLP-trigger sibling scenario (scenarios/insider-risk/data-leaks/) and any other policy built from this exact template - NOT a per-trigger-event cap.",
    "realTimeAnalyticsScopeRequirement": "If real-time analytics (preview) threshold recommendations are used, this policy must be scoped to 'Include all users and groups' instead of a specific group - README.md §6/§11."
  },
  "triggeringEvent": {
    "type": "User performs an exfiltration activity",
    "alternativeNotUsedHere": "User matches a data loss prevention (DLP) policy - see scenarios/insider-risk/data-leaks/ for that worked example. design.md §2 goal 6/README.md §11: whether both can be combined on one policy is NOT confirmed - this manifest assumes a single-select choice.",
    "triggerIndicators": {
      "selected": "OPERATOR CHOICE - list the specific built-in indicator(s) selected as the trigger here, e.g. ['Downloading content from SharePoint', 'Sharing SharePoint files/folders with people outside the organization']. Must be enabled first in Insider Risk Management > Settings > Policy indicators > Built-in Indicators (README.md §5 Step 2).",
      "thresholdMode": "OPERATOR CHOICE - 'Use default thresholds (Recommended)' OR 'Use custom thresholds for the triggering events'. Microsoft does NOT publish the numeric values behind the default option for any indicator - README.md §6/§11 recommends custom thresholds whenever exact trigger sensitivity must be documented for a customer commitment.",
      "customThresholdValues": "OPERATOR CHOICE, only if thresholdMode = custom - record the per-indicator low/medium/high (or anomalous-activity) values actually selected here, e.g. per README.md §6's worked SharePoint-download example: {\"low\": \"10+/day\", \"medium\": \"20+/day\", \"high\": \"30+/day\"}. That specific example is Microsoft's own illustration, not this scenario's default.",
      "anomalousActivityOption": "OPERATOR CHOICE, where offered per indicator - 'Activity is above user's usual activity for the day' - dynamically computed per user rather than a fixed daily count. Only available for indicators that support it."
    }
  },
  "scoringIndicators": {
    "_note": "A SEPARATE decision page/threshold mode from the triggeringEvent.triggerIndicators above - design.md §2 goal 2/§5. The indicator lists may overlap or differ; do not assume they match.",
    "officeIndicators": {
      "category": "Office indicators (built-in) - SharePoint Online downloads/syncing, sharing internal files/folders externally, printing files, copying data to personal cloud storage/messaging services",
      "selected": true,
      "note": "Primary scoring indicator category for this template, identical to the DLP-trigger sibling."
    },
    "cumulativeExfiltrationDetection": {
      "selected": true,
      "note": "ENABLED BY DEFAULT for this template - confirm actually selected at policy creation rather than assumed."
    },
    "communicationComplianceScoringIndicators": {
      "category": "Optional - Sending financial regulatory text that might be risky / Sending inappropriate images / Sending inappropriate content / Sending messages that contain specific sensitive info types",
      "selected": "operator choice - not selected by default in this manifest"
    },
    "generativeAiIndicators": {
      "category": "Optional - Prompt Shields, Protected material detection",
      "selected": "operator choice - not selected by default in this manifest"
    },
    "cloudIndicators": {
      "category": "Optional - Cloud storage (Box, Dropbox, Google Drive) / Cloud service (Amazon S3, Azure)",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Confirmed applicable to this template (data-leaks/README.md §6). Requires Defender for Cloud Apps connections + pay-as-you-go billing."
    },
    "thresholdMode": "OPERATOR CHOICE - 'Use default thresholds for all indicators' OR 'Specify custom thresholds' - independent of whatever was chosen for triggeringEvent.triggerIndicators.thresholdMode above."
  },
  "prerequisites": {
    "dlpPolicy": "NOT required for this trigger path - the defining difference from the sibling scenario.",
    "defenderForEndpoint": "NOT required for this template.",
    "hrConnectorOrCommunicationComplianceTrigger": "NOT required for this template.",
    "payAsYouGoBilling": "Required ONLY if the optional cloud storage/cloud service scoring indicator category is used.",
    "realTimeAnalytics": "Optional - requires Insider risk analytics enabled (Get started Step 3) and this policy scoped to 'Include all users and groups' if used."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every IRM scenario in this library."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-16"
}
```