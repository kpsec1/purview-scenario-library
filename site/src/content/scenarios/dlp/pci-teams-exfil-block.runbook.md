---
part: "runbook"
parent: "dlp/pci-teams-exfil-block"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
   prevention** → **Policies** → **Create policy**.
2. Category: **Custom** → template: **Custom policy** → **Next**.
3. Name: `PCI DSS - Teams Card Data Exfiltration Block`. **Policies can't be renamed after
   creation** - confirm the name before continuing.
4. **Assign admin units**: accept **Full directory** (unless the tenant uses administrative
   units - see [RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive)).
5. **Choose locations**: select **Teams chat and channel messages** only; deselect all other
   locations.
6. **Define policy settings**: choose **Create or customize advanced DLP rules**.
7. Create rule **PCI-CardOps-Override-External** (priority 0):
   - Conditions: **Content contains** → **Sensitive info types** → **Credit Card Number**; add
     group **Sender is a member of** → the Card Operations group; **Content is shared from
     Microsoft 365** → **with people outside my organization**.
   - Actions: **Restrict access or encrypt the content in Microsoft 365 locations** → for Teams
     this is the only supported action family; enable **user overrides** with
     **require a business justification**.
   - Notifications: policy tip on, custom text explaining the override path.
   - Incident reports: alert **High** severity, send to the SOC/admin mailbox.
8. Create rule **PCI-Block-External-AllUsers** (priority 1): same conditions as rule 0 but
   **excluding** the Card Operations group, and **no** override allowed.
9. Create rule **PCI-Audit-Internal-AllUsers** (priority 2): condition is **Content contains
   Credit Card Number** only (no external-sharing condition); action is **audit only** - do not
   add a restrict/block action; alert **Low** severity.
10. **Policy mode**: choose **Run the policy in simulation mode** first (or
    **...and show policy tips**) - do not turn it on immediately. Follow the staged rollout in
    operations and tuning below.
11. **Submit**, then **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-PciTeamsDlpPolicy.ps1 `
    -CardOpsGroupEmail 'card-ops@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real traffic first
./deploy/New-PciTeamsDlpPolicy.ps1 `
    -CardOpsGroupEmail 'card-ops@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. After a tuning window, enforce
./deploy/New-PciTeamsDlpPolicy.ps1 `
    -CardOpsGroupEmail 'card-ops@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-PciTeamsDlpPolicy.ps1 -CardOpsGroupEmail 'card-ops@contoso.com'
```

The deploy script uses Security & Compliance PowerShell (`New-DlpCompliancePolicy`,
`New-DlpComplianceRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), because DLP
policy/rule objects have no Graph authoring equivalent today.

## Configuration reference

| Setting | Rule 0: `PCI-CardOps-Override-External` | Rule 1: `PCI-Block-External-AllUsers` | Rule 2: `PCI-Audit-Internal-AllUsers` |
|---|---|---|---|
| Priority | 0 | 1 | 2 |
| Sender scope | `FromMemberOf` = Card Ops group | `ExceptIfFromMemberOf` = Card Ops group | (all senders) |
| Share-target condition | `AccessScope = NotInOrganization` | `AccessScope = NotInOrganization` | (none - reached only for non-external traffic, see the design notes) |
| Sensitive info type | Credit Card Number (built-in SIT, Luhn-validated) | Credit Card Number | Credit Card Number |
| `BlockAccess` | `$true` | `$true` | `$false` |
| `NotifyAllowOverride` | `WithJustification` | (none) | n/a |
| `ReportSeverityLevel` | High | High | Low |
| `GenerateAlert` / `GenerateIncidentReport` | Admin + SOC mailbox | Admin + SOC mailbox | Admin + SOC mailbox |
| `StopPolicyProcessing` | `$true` | `$true` | `$false` |
| Policy location | `TeamsLocation = "All"` (all three rules share the one policy) | | |
| Policy `Mode` | `TestWithNotifications` (deploy default) → `Enable` after tuning | | |

Full cmdlet parameter grounding: `deploy/New-PciTeamsDlpPolicy.ps1` inline comments and its
`.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence** (Microsoft's documented staged rollout): Off → Run in
simulation mode → Run in simulation mode + show policy tips (pilot group) → Turn it on. The deploy
script's default `-Mode TestWithNotifications` corresponds to stage 2; pass `-Mode Enable`
deliberately once tuning is complete.

**KPIs to watch (first 30 days):**
- **Rule 1 (hard block) match count** - a sudden spike after enabling usually means a legitimate
  business process was missed by the Card Ops exception, not a wave of attempted exfiltration.
  Investigate before assuming malice.
- **Rule 0 (override) usage rate** - track how often Card Ops actually overrides. A rate near
  100% suggests the "audit only, confirm last 4 digits" workflow the group is meant to do is
  routinely hitting the full-PAN block instead - a training or process gap, not a policy bug.
- **Rule 2 (internal audit) volume** - this is your baseline for how much internal PAN sharing
  exists before you consider tightening it to a block. Trend it weekly; a flat or rising trend
  after a security-awareness push is a signal the control needs to move from audit to block.
- **False-positive rate** - sensitive info type false positives (test data, truncated/partial
  numbers that still pass the Luhn check) show up as override requests or user complaints; tune
  by adjusting the SIT's confidence level or count thresholds only after confirming the pattern in
  Activity Explorer, not from a single report.

**Alert routing:** all three rules generate alerts and incident reports to the SOC/admin mailbox
parameter. Route the DLP alert source into the SIEM (Microsoft Sentinel connector, or the
Microsoft Defender XDR incident queue export) so it lands in existing on-call rotation rather than
living only in the Purview portal - see [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) for the Audit Search /
Graph pull pattern if building a custom pipeline instead.

**Review cadence:** quarterly at minimum (PCI DSS expects documented, periodic review of security
controls) for the overall control; re-run `validate/Test-PciTeamsDlpPolicy.ps1` as part of that
review to catch configuration drift (e.g., someone editing the policy directly in the portal
without updating this library's script parameters). Review **Rule 0 override usage** on a **weekly**
cadence, not quarterly - a compromised or coerced Card Ops account is the one path in this design
that can move a live PAN externally with a single click, and a weekly Advanced Hunting query
against DLP alert data (per-user override count, [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) audit-search
routing) catches abuse long before a quarterly review would.

**Incident-response runbook (Rule 1 / Rule 0 block or override alert):**
1. **Triage** - open the alert in the DLP Alerts dashboard or Microsoft Defender portal incident
   queue; confirm which rule matched, the sender, and (for Teams) that the "Sensitive info types"
   tab shows an actual PAN-shaped match rather than a false positive (test data, a truncated
   number that still passes the Luhn check, an unrelated 16-digit identifier).
2. **Classify** - true positive vs. false positive. False positive: no further action beyond
   noting the pattern for a future SIT confidence-threshold tuning pass (see KPI notes above).
3. **True positive, Rule 1 (hard block, non-Card-Ops sender)** - the message never left the
   tenant; contact the sender's manager and initiate the org's standard data-handling incident
   process. Determine whether the sender needs to be added to a legitimate workflow (Card Ops
   membership) or needs security-awareness follow-up.
4. **True positive, Rule 0 (Card Ops override used)** - pull the business-justification text from
   the audit log `ExceptionInfo` value. If the justification is legitimate and
   consistent with the group's known workflow, close as expected behavior. If not, escalate as a
   potential insider-risk event and consider a temporary removal from the Card Ops group pending
   investigation.
5. **Document** - every true positive and every override closure is retained as PCI DSS
   Requirement 10 evidence; do not delete or edit alert records.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-PciTeamsDlpPolicy.ps1` disables (reversible); add `-Purge` to
permanently delete the policy and its rules.

## References

1. DLP licensing and scope of protection for Microsoft Teams - <https://learn.microsoft.com/purview/dlp-microsoft-teams>
2. Create and deploy data loss prevention policies (staged rollout, ~1 hour sync) - <https://learn.microsoft.com/purview/dlp-create-deploy-policy>
3. Microsoft Purview service description - DLP for Teams (Microsoft Communications DLP service) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-dlp-for-teams>
4. Learn about the default DLP policy in Microsoft Teams (naming, DLP Compliance Management permission) - <https://learn.microsoft.com/purview/dlp-teams-default-policy>
5. Data loss prevention and Microsoft Teams (blocking behavior, policy tips, no email notification, override/business-justification logging) - <https://learn.microsoft.com/purview/dlp-microsoft-teams>
6. PCI DSS Requirement 4.2 - never send unprotected PANs by end-user messaging technologies - <https://learn.microsoft.com/azure/aks/pci-data#protect-cardholder-data> (Microsoft's mapping of PCI DSS 4.0.1 Requirement 4.2; cross-check sub-clause numbering (4.2.1/4.2.2) against the current PCI SSC PCI DSS v4.0.1 standard at <https://docs-prv.pcisecuritystandards.org/PCI%20DSS/Standard/PCI-DSS-v4_0_1.pdf> before an assessment)
7. Payment Card Industry (PCI) Data Security Standard (DSS) - Compliance Manager premium template - <https://learn.microsoft.com/compliance/regulatory/offering-pci-dss>
8. New-DlpCompliancePolicy reference (TeamsLocation, Mode) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
9. New-DlpComplianceRule reference (AccessScope, BlockAccess, NotifyAllowOverride, StopPolicyProcessing, ReportSeverityLevel) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
10. Set-DlpCompliancePolicy reference (Mode: Enable/Disable/TestWithNotifications/TestWithoutNotifications) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>
11. Remove-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
12. Credit Card Number sensitive information type definition (Luhn checksum, format) - <https://learn.microsoft.com/purview/sit-defn-credit-card-number>
13. Data Loss Prevention policy reference (supported actions per location, user overrides, business-justification X-header) - <https://learn.microsoft.com/purview/dlp-policy-reference>
14. Learn about investigating data loss prevention alerts (alert lifecycle, DLP Alerts dashboard 30-day retention, Defender portal 6-month retention) - <https://learn.microsoft.com/purview/dlp-alert-investigation-learn>
15. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>

> Re-verify all links and sub-clause citations against current Microsoft Learn and the PCI SSC
> standard before a customer-facing assessment or sale - both product behavior and the PCI DSS
> standard revision in force change over time.