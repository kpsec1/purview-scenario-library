---
part: "runbook"
parent: "dspm-for-ai/copilot-sensitive-data-exposure"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

**DLP policy:**

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
   prevention** → **Policies** → **Create policy**.
2. Category: **Custom** → template: **Custom policy** → **Next**. The **Microsoft 365 Copilot and
   Copilot Chat** location is **only available in the Custom template**.
3. Name: `Copilot DLP - Sensitive Data Exposure Protection`. Policies can't be renamed after
   creation - confirm before continuing.
4. **Choose locations**: turn **on** only **Microsoft 365 Copilot and Copilot Chat**. Selecting
   this location disables every other location for the same policy.
   **Admin units are not supported** for this location - it always applies tenant-wide.
5. **Define policy settings**: choose **Create or customize advanced DLP rules**.
6. Create rule **Copilot-Exclude-Labeled-Content** (priority 0):
   - Condition: **Content contains** → **Sensitivity labels** → select **Confidential** and
     **Highly Confidential**.
   - Action: **Prevent Copilot from processing content**. The item can still appear in the
     response's citations, but its content is not summarized or used.
7. Create rule **Copilot-Restrict-WebGrounding-SensitivePrompts** (priority 1):
   - Condition: **Content contains** → **Sensitive information types** → **U.S. Social Security
     Number (SSN)**, **Credit Card Number**. Microsoft's documentation is explicit that **you
     cannot combine a sensitivity-labels condition and a sensitive-information-types condition in
     the same rule** - this must be a second rule, not an added condition on rule 0.
   - Action: **Prevent Copilot from processing content** → **Performing Web Searches**.
8. **Policy mode**: choose **Run the policy in simulation mode** first. Follow the staged rollout
   in operations and tuning below.
9. **Submit**, then **Done**.

> **Now scripted as a separate, extending scenario:** Microsoft also offers a third Copilot-location
> action - **Prevent Copilot from processing content > Processing prompts**, which fully blocks a
> Copilot response when the prompt itself contains a chosen SIT (rather than only restricting
> web-search grounding). A dedicated re-grounding pass found Microsoft
> has since published a fuller worked use case for this action (still preview, still no worked
> PowerShell example for this exact condition/action combination) - see
> *Copilot Prompt Full-Response Block*, which adds this action as a third rule on this
> same policy, with the remaining PowerShell-grounding gap explicitly disclosed rather than resolved
> by guessing.

**DSPM for AI oversharing assessment (no activation needed, but review the results):**

10. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
    **DSPM for AI (classic)** → **Overview**. A weekly data risk assessment against the tenant's
    top 100 SharePoint sites by usage runs automatically, no setup required.
11. From **Reports**, review the SharePoint sites with the most unlabeled files referenced in
    Copilot prompts, and the sites with the broadest oversharing risk. Wait at least 24 hours after
    initial DSPM for AI activation for data to populate.
12. Work the **Recommendations** page: in particular, **Protect your data from potential
    oversharing risks** (data risk assessment results) and **Protect items with sensitivity labels
    from Microsoft 365 Copilot and agent processing** (the one-click equivalent of the DLP policy
    this scenario deploys by named script instead - see the design notesa for why this scenario uses
    a separately named, script-managed policy rather than the one-click default).

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real Copilot traffic first
./deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. After a tuning window (allow up to 4 hours for propagation before testing), enforce
./deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-CopilotSensitiveDataProtectionPolicy.ps1
```

The deploy script uses Security & Compliance PowerShell (`New-DlpCompliancePolicy`,
`New-DlpComplianceRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). The
label-exclusion rule uses the `-AdvancedRule` JSON form (there is no simple
`-ContentContainsSensitiveInformation`-style parameter for a sensitivity-label condition combined
with the Copilot location's `-RestrictAccess` action); the web-grounding-restriction rule uses the
standard `-ContentContainsSensitiveInformation` parameter plus the `-RestrictWebGrounding` boolean
parameter. Both patterns are taken directly from Microsoft's own `New-DlpCompliancePolicy` /
`New-DlpComplianceRule` PowerShell reference examples - see the script's `.NOTES` block for exact
citations.

## Configuration reference

| Setting | Rule 0: `Copilot-Exclude-Labeled-Content` | Rule 1: `Copilot-Restrict-WebGrounding-SensitivePrompts` |
|---|---|---|
| Priority | 0 | 1 |
| Condition | `AdvancedRule` - content contains sensitivity label (Confidential, Highly Confidential, by GUID) | `ContentContainsSensitiveInformation` = U.S. Social Security Number (SSN), Credit Card Number |
| Action | `RestrictAccess` = `@{setting='ExcludeContentProcessing'; value='Block'}` | `RestrictWebGrounding` = `$true` |
| What it stops | Copilot from using the item's content in a response summary (item may still appear as a citation link) | Copilot from using external web search as a grounding source for that prompt; internal M365 grounding is unaffected |
| What it does **not** stop | Access to the item outside Copilot (open/download); it is not a permissions control | Copilot from answering using internal (already-accessible) Microsoft 365 content, even unlabeled overshared content |
| `GenerateAlert` / `GenerateIncidentReport` | Admin/SOC mailbox | Admin/SOC mailbox |
| `ReportSeverityLevel` | High | Medium |
| Policy location | `Locations` = Copilot Applications location GUID `470f2276-e011-4e9d-a6ec-20768be3a4b0`, `EnforcementPlanes` = `CopilotExperiences` (both rules share the one policy) | |
| Policy `Mode` | `TestWithNotifications` (deploy default) → `Enable` after tuning | |

Full cmdlet parameter grounding: `deploy/New-CopilotSensitiveDataProtectionPolicy.ps1` inline
comments and its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence:** Off → Run in simulation mode → Run in simulation mode + show policy tips
(pilot group, where supported for this location) → Turn it on. The deploy script's default `-Mode
TestWithNotifications` corresponds to the simulation stage; pass `-Mode Enable` deliberately once
tuning is complete. Allow the documented **up to four hours** for a policy change to reach the
Copilot experience before drawing conclusions from a test - longer than this
repo's Teams/Exchange DLP scenarios (~1 hour), plan test windows accordingly.

**KPIs to watch (first 30 days):**
- **Rule 0 (label exclusion) match count** - trend by SharePoint site. A concentration of matches
  on a small number of sites usually indicates a site whose sensitivity-label coverage or
  permissions need attention beyond this DLP policy - cross-reference against the DSPM for AI
  oversharing assessment for that site.
- **Rule 1 (web-grounding restriction) match count** - a sustained high rate can indicate users
  routinely including real sensitive data in prompts as a matter of habit (e.g., pasting a customer
  record to ask Copilot to reformat it) - a training/process signal, not necessarily malicious.
- **DSPM for AI oversharing assessment trend** - this is the primary metric this scenario exists to
  move: falling site-count and file-count in the weekly oversharing assessment over time is the
  evidence that permissions remediation (not this DLP policy, which is a content-level backstop)
  is working. Review monthly at minimum during an active Copilot rollout.
- **Unlabeled-file-in-Copilot-prompt volume** (DSPM for AI Reports) - files referenced in Copilot
  prompts that carry **no** sensitivity label at all are invisible to Rule 0 by definition; a high
  and rising trend here is the strongest available signal that label coverage (not this DLP policy)
  needs expansion - see the design notes and Known Limitations below.

**Ownership note:** assign an accountable owner for the DSPM for AI oversharing-assessment trend
who is **not** solely the DLP/Security team - permissions remediation (removing stale "Anyone"
links, tightening inherited SharePoint permissions) is typically a SharePoint admin / data
governance responsibility. A program that only tunes this DLP policy while nobody owns the
underlying permissions backlog will show declining Rule 0 match *rates* (fewer labeled items get
touched as usage patterns shift) without the oversharing assessment's site/file counts actually
improving - a misleading signal for a board-level report. Name the owner before reporting this
control as "in place."

**Alert routing:** both rules generate alerts and incident reports to the SOC/admin mailbox
parameter. Route into the SIEM (Microsoft Sentinel connector or Microsoft Defender XDR incident
queue export) per [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task).

**Review cadence:** quarterly at minimum for the DLP policy configuration (re-run
`validate/Test-CopilotSensitiveDataProtectionPolicy.ps1` to catch drift); **monthly** for the DSPM
for AI oversharing assessment trend during an active Copilot rollout, dropping to quarterly once
the oversharing backlog is under control.

**Incident-response runbook (Rule 0 / Rule 1 alert):**
1. **Triage** - open the alert in the DLP Alerts dashboard or Microsoft Defender portal incident
   queue; confirm which rule matched and the sending user.
2. **Classify** - Rule 0 match: expected, routine behavior (a user asked about something they can
   technically access but is labeled confidential) unless the volume or specific site is anomalous
   for that user - escalate anomalies to the DSPM for AI **Activity explorer** user-risk view (for
   analysts with Insider Risk Management Analyst/Investigator access) rather than treating every
   match as an incident. Rule 1 match: check whether the prompt content resembles a real customer
   record (possible legitimate but risky workflow needing process guidance) or looks like probing/
   test behavior.
3. **Document** - retain alert records; do not delete or edit them. They are the evidence trail for
   the pre-rollout security review this scenario exists to support.
4. **Escalate to permissions remediation, not just DLP tuning** - if Rule 0 matches cluster on a
   specific SharePoint site, that site is a candidate for the DSPM for AI oversharing
   recommendation workflow (tighten sharing links, review site permissions) - closing the loop back
   to operations and tuning's primary KPI, not just suppressing the DLP alert.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-CopilotSensitiveDataProtectionPolicy.ps1` disables (reversible); add `-Purge` to
permanently delete the policy and its rules. The DSPM for AI oversharing assessment is not deployed
by this scenario (portal-only, automatic) and has nothing to roll back.

## References

1. Learn about Data Security Posture Management for AI (classic) - automatic weekly top-100
   SharePoint site oversharing assessment, Reports, Activity explorer - <https://learn.microsoft.com/purview/dspm-for-ai>
2. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
   365 Copilot and Copilot Chat (locations, conditions/actions table, licensing, permissions,
   four-hour propagation, file-open enforcement timing, uploaded-file scanning limitation) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about>
3. Configure a secure and governed foundation for Microsoft Copilot (pre-rollout oversharing
   guardrails, DLP-for-Copilot as the sensitivity-label enforcement step) - <https://learn.microsoft.com/microsoft-365/copilot/configure-secure-governed-data-foundation-microsoft-365-copilot>
4. Microsoft Purview service description - DLP for Microsoft Copilot licensing table (label-based
   restriction requires E5-tier; prompt-safeguard DLP available at all tiers) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-dlp-for-microsoft-copilot>
5. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
   365 Copilot and Copilot Chat - Permissions section (Copilot-location-specific role list) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#permissions>
6. Permissions for Data Security Posture Management for AI (classic) - <https://learn.microsoft.com/purview/ai-microsoft-purview-permissions>
7. Learn about Data Security Posture Management for AI (classic) - Microsoft Purview Audit
   prerequisite for Copilot activity insights - <https://learn.microsoft.com/purview/dspm-for-ai#how-to-use-data-security-posture-management-for-ai>
8. New-DlpCompliancePolicy reference - Example 4 (Copilot location JSON, `-EnforcementPlanes
   CopilotExperiences`, `-AdvancedRule` label-condition JSON, `-RestrictAccess
   ExcludeContentProcessing`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
9. New-DlpComplianceRule reference (`-RestrictAccess`, `-RestrictWebGrounding`,
   `-ContentContainsSensitiveInformation` parameters) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
10. Set-DlpCompliancePolicy reference (`-Mode` values) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>
11. Remove-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
12. Learn about the default data loss prevention policy for Microsoft 365 Copilot location (the
    one-click `Default DLP policy - Protect sensitive M365 Copilot interactions`, ships in
    simulation mode by default) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-default-policy>
13. Considerations for DSPM for AI to manage data security and compliance protections for AI
    interactions (classic) - one-click policies including **DSPM for AI - Protect sensitive data
    from Copilot processing** - <https://learn.microsoft.com/purview/dspm-for-ai-considerations>
14. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>

> Re-verify all links, preview/GA status, and licensing tier citations against current Microsoft
> Learn before a customer-facing assessment or sale - Copilot-related Purview capabilities are
> changing faster than this library's other, more mature DLP surfaces (Teams/Exchange/Endpoint).