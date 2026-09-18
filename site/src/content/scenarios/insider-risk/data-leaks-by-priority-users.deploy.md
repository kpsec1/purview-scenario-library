---
part: "deploy"
parent: "insider-risk/data-leaks-by-priority-users"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `policy/data-leaks-priority-users-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring or priority-user-group management as of this writing (docs/automation-surface.md §6; design.md §2 goal 7). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy and priority user group can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Data Leaks by Priority Users",
  "policyTemplate": "Data leaks by priority users",
  "templateStatus": "Not found to be labeled preview in this build's grounding - re-verify GA/preview status against the live portal before a customer-facing commitment. README.md §1/§6.",
  "priorityUserGroup": {
    "createdInSettings": "Purview portal > Settings > Insider Risk Management > Priority user groups > Create priority user group. README.md §5 Step 4. REQUIRED for this template, not optional.",
    "maxMembers": 10000,
    "membershipSource": "../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1 output CSV (bulk upload) and/or portal search/select - NOT a live-synced Entra group. README.md §5 Step 3/4.",
    "reviewPermissions": "Assign one or more of Insider Risk Management / Insider Risk Management Analysts / Insider Risk Management Investigators role groups, or specific individual users, as reviewers for this group's data. README.md §8.",
    "note": "A priority user group is a standalone, template-agnostic object - reuse an existing one if this population is already used by a Security policy violations by priority users policy, rather than creating a duplicate."
  },
  "scope": {
    "mechanism": "'Add or edit priority user groups' option on the Users and groups page - a distinct UI path confirmed by Microsoft to appear ONLY for this template, not the plain 'Include specific users and groups' option. README.md §5 Step 5, design.md §1.",
    "maxActivelyScoredUsers": 1000,
    "note": "This template's OWN, independently-documented cap - cumulative ONLY across policies built from THIS exact template. NOT shared with Security policy violations by priority users (numerically identical, separate cap), Data leaks (15,000), or Data leaks by risky users (7,500). design.md §3, README.md §6.",
    "adminUnitRestriction": "NOT supported for this template. Only an unrestricted administrator can create a policy from this template - a restricted/scoped administrator cannot create it at all. README.md §3/§5 Step 1."
  },
  "triggeringEvents": [
    {
      "type": "User matches a data loss prevention (DLP) policy",
      "optional": true,
      "note": "Identical to the base Data leaks template's own primary trigger - up to 20 policies, Exchange Online/SharePoint Online/OneDrive for Business only. Checked by ../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 (reused). README.md §5 Step 2/5."
    },
    {
      "type": "User performs an exfiltration activity",
      "optional": true,
      "note": "Documented Microsoft-supported alternative - built-in indicators, default or custom thresholds. NOT given a full worked implementation in this fragment, matching the base Data leaks scenario's own scope. README.md §5 Step 5/§11."
    }
  ],
  "indicators": {
    "officeIndicators": {
      "category": "Office indicators (built-in) - per Microsoft's current description: SharePoint sites, Microsoft Teams, and email messaging",
      "selected": true
    },
    "cumulativeExfiltrationDetection": {
      "selected": true,
      "note": "ENABLED BY DEFAULT for this template - confirm actually selected at policy creation rather than assumed. README.md §5 Step 5/§6."
    },
    "riskScoreBoosters": {
      "userIsMemberOfPriorityUserGroup": {
        "selected": true,
        "critical": "MUST be explicitly selected under Risk score boosters for priority-group membership to actually increase alert likelihood/severity - this is NOT an automatic consequence of the scope assignment above. This is this fragment's single most operationally significant grounded finding. README.md §5 Step 5/§8/§11, design.md §2 goal 4."
      }
    },
    "communicationComplianceScoringIndicators": {
      "category": "Optional - Sending financial regulatory text that might be risky / Sending inappropriate images / Sending inappropriate content / Sending messages that contain specific sensitive info types",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Explicitly confirmed selectable for this template. README.md §5 Step 5/§6, reference 11."
    },
    "generativeAiIndicators": {
      "category": "Optional - Prompt Shields, Protected material detection",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Explicitly confirmed selectable for this template. README.md §5 Step 5/§6, reference 11."
    },
    "cloudIndicators": {
      "category": "Optional - Cloud storage (Box, Dropbox, Google Drive) / Cloud service (Amazon S3, Azure)",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "NOT confirmed applicable to this specific template - Microsoft's per-template description text does not name 'cloud indicators' for this template the way it does for the base Data leaks template. VERIFY against the live workflow at deploy time. README.md §5 Step 5/§6/§11."
    }
  },
  "prerequisites": {
    "dlpPolicy": "Optional - required only if using the DLP-policy triggering event. Checked by ../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 (reused).",
    "priorityUserGroup": "REQUIRED for this template - not optional. README.md §3.",
    "defenderForEndpoint": "NOT required for this template.",
    "hrConnectorOrCommunicationComplianceTrigger": "NOT required for this template.",
    "payAsYouGoBilling": "Required ONLY if the (unconfirmed-applicable) optional cloud indicator category is used and confirmed available."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every IRM scenario in this library.",
    "reviewerScoping": "Optionally restricted at the priority-user-group level - see priorityUserGroup.reviewPermissions above."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-15"
}
```