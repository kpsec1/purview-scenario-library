---
part: "deploy"
parent: "insider-risk/data-leaks-by-risky-users"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `policy/data-leaks-risky-users-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Data Leaks by Risky Users",
  "policyTemplate": "Data leaks by risky users",
  "templateStatus": "NOT Microsoft-labeled preview as of this writing, unlike its Security policy violations by risky users cousin (whose template family carries an explicit preview label) - re-verify GA/preview status before a customer-facing commitment. README.md §1/§3.",
  "scope": {
    "users": "A plain Entra security group (or groups) resolved via ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 -MaxUsers 7500 (reused unmodified) - this template has no priority-user-group requirement",
    "maxUsersInScope": 7500,
    "note": "Numerically identical to the Security policy violations by risky users cousin's own cap, but a SEPARATE cumulative cap - do not conflate the two templates' usage counts. Cumulative tenant-wide across every policy built from THIS exact template."
  },
  "triggeringEvents": [
    {
      "type": "HR connector - job level change / performance review / performance improvement plan indicators",
      "source": "../security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1 (reused unmodified) uploading to a THIRD, dedicated HR connector (own JobId, own app registration) - not the departing-employee-data-theft sibling's Resignation-scoped connector, and not the security-policy-violations-by-risky-users sibling's own dedicated risk-indicator connector",
      "requiredEither": true,
      "note": "At least one of this trigger OR the Communication Compliance trigger below is required (Microsoft's prerequisite table states 'AND/OR', not both mandatory). Both together is also supported and recommended for broader coverage - README.md §5 Step 4."
    },
    {
      "type": "Communication Compliance risk-signal integration (TRIGGER role)",
      "source": "Portal-only option selected in the IRM policy-creation workflow itself - auto-creates a dedicated 'Detect inappropriate text' Communication Compliance policy. No PowerShell surface exists for Communication Compliance policy creation/management (Microsoft Learn, explicit statement).",
      "requiredEither": true,
      "note": "Threat/Harassment/Discrimination trainable classifiers; 5+ risky messages in 24h brings a user in-scope; up to 48h latency. Microsoft's own documentation uses two different names for the auto-created policy in the same article ('Insider risk trigger - (date created)' in one paragraph, 'Risky user in messages - (date created)' in the next) - disclosed as an unresolved documentation inconsistency. README.md §5 Step 5 / §11. NOTE: this is a DIFFERENT role for Communication Compliance than the optional SCORING indicators below - the same product, selected independently, in two different places in this one policy."
    }
  ],
  "indicators": {
    "officeIndicators": {
      "category": "Office indicators (built-in)",
      "selected": true,
      "note": "Primary scoring indicator category for this template - SharePoint Online downloads/syncing, sharing internal files/folders externally, copying data to personal cloud storage/messaging services. Requires no additional connector. README.md §5 Step 6/§6."
    },
    "cumulativeExfiltrationDetection": {
      "selected": true,
      "note": "ENABLED BY DEFAULT for this template per Microsoft Learn - confirm actually selected at policy creation rather than assumed. Depends on Microsoft Entra hierarchy/job-title/SharePoint-access data for peer-group accuracy. README.md §5 Step 6/§8."
    },
    "communicationComplianceScoringIndicators": {
      "category": "Optional - Sending financial regulatory text that might be risky / Sending inappropriate images / Sending inappropriate content / Sending messages that contain specific sensitive info types",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "SCORING indicators, documented as selectable for this template specifically (also Data theft, Data leaks, Data leaks by priority users) - distinct from the Communication Compliance TRIGGER integration above. design.md §2 goal 4."
    },
    "generativeAiIndicators": {
      "category": "Optional - Prompt Shields, Protected material detection (Azure AI Content Safety classifiers)",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Documented as selectable for this template (also Data leaks, Data leaks by priority users, Risky AI usage). README.md §5 Step 6."
    },
    "cloudIndicators": {
      "category": "Optional - Cloud storage (Box, Dropbox, Google Drive) / Cloud service (Amazon S3, Azure)",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Requires Defender for Cloud Apps app connections + pay-as-you-go billing. WHETHER THIS CATEGORY IS ACTUALLY OFFERED FOR THIS SPECIFIC TEMPLATE IN THE LIVE POLICY-CREATION WORKFLOW IS UNCONFIRMED - Microsoft's per-template text names it for Data theft by departing users and the base Data leaks template, not explicitly for this one. VERIFY at deploy time. README.md §5 Step 6/§11, design.md §2 goal 5."
    }
  },
  "prerequisites": {
    "hrConnectorOrCommunicationCompliance": "At least one of: Microsoft 365 HR connector configured for disgruntlement/risk indicators (Job level change / Performance review / Performance improvement plan), OR Communication Compliance integration with a dedicated policy. Both is supported. README.md §3.",
    "defenderForEndpoint": "NOT required for this template - the defining licensing/deployment difference from the Security policy violations by risky users cousin. README.md §3/§10.",
    "payAsYouGoBilling": "Required ONLY if the optional cloud storage/cloud service indicator category is used. Not required for the template's core Office indicators. README.md §3/§10."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every IRM scenario in this library."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-15"
}
```