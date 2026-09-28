---
part: "runbook"
parent: "dlp/exchange-pii-exfil-block"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Data loss prevention** → **Policies** → **+ Create policy** → **Custom** → **Custom policy**
   → **Next**.
2. Name: `PII DLP - Exchange External Send Control`.
3. **Choose locations**: select **Exchange email** only.
4. **Define policy settings** → **Create or customize advanced DLP rules** → **+ Create rule**.
5. Rule `PII-Exchange-Protect-External`: **Conditions** → **Content contains** → **Sensitive info
   types** → add **U.S. Social Security Number (SSN)** and **Credit Card Number**, minimum count
   **1** each, **Any of these** (OR). Add condition **Recipient is** → **outside my organization**
   (`AccessScope: NotInOrganization`). **Actions** → **Restrict access or
   encrypt the content in Microsoft 365 locations** → either **Block users from receiving email**
   (hard block) or **Encrypt email messages** and pick an RMS template (e.g. **Encrypt-Only**).
6. Rule `PII-Exchange-Audit-Internal`: same SIT conditions, **Recipient is** → **inside my
   organization**. **Actions**: alert + incident report only, no block.
7. (Optional) Rule `PII-Exchange-Override-External` (Block mode only, priority above the protect
   rule): same SIT conditions + **Sender is a member of** the nominated exception group, **Recipient
   is outside my organization**, **Block users from receiving email**, with **User can override
   the rule** → **With business justification**.
8. **Policy mode**: select **Run the policy in simulation mode** (do not select "turn it on
   automatically after 7 days" - same deliberate-enable standard as every other scenario in this
   library). **Submit** → **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-ExchangePiiDlpPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) - Block mode, with a business-exception group
./deploy/New-ExchangePiiDlpPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -ExceptionGroupEmail 'hr-benefits-ops@contoso.com'

# 3b. Or deploy in Encrypt mode instead of Block
./deploy/New-ExchangePiiDlpPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -Action Encrypt

# 4. After a review window, enforce
./deploy/New-ExchangePiiDlpPolicy.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-ExchangePiiDlpPolicy.ps1 -Action Block -ExceptionGroupEmail 'hr-benefits-ops@contoso.com'
```

The deploy script uses Security & Compliance PowerShell (`New-DlpCompliancePolicy`,
`New-DlpComplianceRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), the same
surface every other DLP scenario in this library uses.

## Configuration reference

| Setting | `PII-Exchange-Override-External` (Priority 0, Block mode + exception group only) | `PII-Exchange-Protect-External` (Priority 1) | `PII-Exchange-Audit-Internal` (Priority 2) |
|---|---|---|---|
| Sensitive info types | SSN, Credit Card Number - `mincount = 1` each, OR-combined | Same | Same |
| `AccessScope` | `NotInOrganization` | `NotInOrganization` | `InOrganization` |
| `FromMemberOf` / `ExceptIfFromMemberOf` | `FromMemberOf = <ExceptionGroupEmail>` | `ExceptIfFromMemberOf = <ExceptionGroupEmail>` when set | - |
| Action | `BlockAccess $true` + `NotifyAllowOverride WithJustification` | `-Action Block` → `BlockAccess $true`. `-Action Encrypt` → `EncryptRMSTemplate <EncryptTemplateName>` | `BlockAccess $false` |
| `StopPolicyProcessing` | `$true` | `$true` | (n/a, last rule) |
| `ReportSeverityLevel` | `High` | `High` | `Low` |

| Policy-level setting | Value |
|---|---|
| `Name` | `<PolicyName>` (default `PII DLP - Exchange External Send Control`) |
| `ExchangeLocation` | `All` |
| `Mode` | `TestWithNotifications` (deploy default) → `Enable` after review |

Full cmdlet parameter grounding: `deploy/New-ExchangePiiDlpPolicy.ps1` inline comments and its
`.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence**: Off → simulation mode → review for at least a business cycle (7+ days,
with representative test/real traffic during the window) → Enable. Same deliberate-enable
standard as every other DLP scenario in this library.

**KPIs to watch (first 30-60 days):**
- **DLP Alerts / incident-report volume** for the `PII-Exchange-Protect-External` rule, split by
  Block vs. override (if an exception group is configured) - a sudden spike in overrides is the
  earliest signal the exception group's approved workflow has changed or is being misused.
- **`PII-Exchange-Audit-Internal` volume**, watched for the same truncated-digit-string
  false-positive pattern documented for *PCI Teams Card-Data Exfiltration Block* (help-desk staff quoting partial
  card numbers, etc.) - tune before this becomes noise that gets ignored.
- **Bounce/NDR-related help-desk tickets** in Block mode, which are the practical detection signal
  for a sender who didn't understand why their external mail didn't arrive.

**Alert routing:** lands in the DLP Alerts dashboard / Microsoft Defender portal, same as every
other DLP scenario in this library; see [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) for building a custom
SIEM pipeline (out of scope for this scenario's deliverable).

**Runbook - an external message containing PII wasn't blocked/encrypted as expected:**
1. Confirm the policy `Mode` is `Enable`, not still `TestWithNotifications`.
2. Confirm the message wasn't sent by a member of the exception group (Block mode) - that traffic
   is expected to go through the override path, not the hard block, by design.
3. Confirm the recipient really is external - `AccessScope: NotInOrganization` is evaluated
   against the actual recipient domain, not a display name; a shared-domain guest or a
   federated-partner mailbox may not evaluate the way an operator expects. Corroborate with a
   controlled test to a domain you know is external.
4. If the message had both internal and external recipients, confirm you're checking the correct
   **fork** - bifurcation means each recipient's copy is evaluated (and reported) independently; an internal recipient's copy being delivered normally is expected, not a
   sign the external copy also went through.
5. If none of the above explains it, check for a rule-load failure the same way this library's
   Exchange auto-labeling scenario documents - re-run the automated config check; if it reports a
   rule missing or malformed, recreate it via `-Force`.

**Runbook - investigating a historical `PII-Exchange-Protect-External` alert or incident
report:**
1. The alert/incident report itself does not record which `-Action` (Block or Encrypt) was
   active at match time - that context lives only in the rule's *current* configuration, which
   may have changed since. Run the automated config check to see the **current**
   action mode; do not assume it matches what fired historically if `-Action` was ever switched
   (the rollback plan, "Switching -Action") without also checking change history (e.g., the audit log entry for
   the `Set-DlpComplianceRule` call that made the switch).
2. Identify which **fork** of a bifurcated message the alert refers to (section 8, main runbook, step 4)
   before concluding anything about recipients not named in that specific alert.

**Review cadence:** monthly for the first quarter, quarterly thereafter - align with the review
cadence already established for *Auto-Label Confidential PII in Exchange Email* if both scenarios are deployed
against the same tenant, since they cover overlapping content but are operationally independent.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-ExchangePiiDlpPolicy.ps1` disables (reversible); add `-Purge` to
permanently delete the policy and its rules.

## References

1. New-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
2. New-DlpComplianceRule reference - full parameter syntax, confirms `AccessScope`,
   `EncryptRMSTemplate`, `BlockAccess`, `FromMemberOf`/`ExceptIfFromMemberOf` - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
3. New-DlpComplianceRule reference - `-AccessScope` parameter: "InOrganization: ... a recipient
   inside the organization. NotInOrganization: ... a recipient outside the organization." - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule#-accessscope>
4. Set-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
5. Remove-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
6. Bifurcation (Exchange reference) - per-recipient forking, independent DLP rule evaluation and
   incident reporting per fork - <https://learn.microsoft.com/exchange/reference/bifurcation#why-bifurcation>
7. Message encryption FAQ - subscription requirements (Office 365/Microsoft 365 E3 and E5 include
   Microsoft Purview Message Encryption at no extra cost) - <https://learn.microsoft.com/purview/ome-faq#what-subscriptions-do-i-need-to-use-microsoft-purview-message-encryption->
8. Microsoft Purview service description - Information Protection Message Encryption feature
   availability (E3/E5 tiers) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-information-protection-message-encryption>
9. Set up Message Encryption - verifying Azure Rights Management activation
   (`Get-IRMConfiguration`, `AzureRMSLicensingEnabled`) - <https://learn.microsoft.com/purview/set-up-new-message-encryption-capabilities#verify-that-azure-rights-management-is-active>
10. Data Loss Prevention policy reference - Exchange action table; "Restrict access or encrypt the
    content in Microsoft 365 locations (Block Everyone, Block only people outside your
    organization)" is halting, the Encrypt Email Messages sub-option is non-halting - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
11. Data loss prevention Exchange conditions and actions reference - condition/action-to-
    PowerShell-parameter mapping table (`BlockAccess`, recipient conditions) - <https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions>
12. How to disable the Encrypt-Only feature in Outlook - confirms **Encrypt-Only** is an
    automatically-added ad-hoc template once Message Encryption is enabled - <https://learn.microsoft.com/troubleshoot/microsoft-365/purview/office-message-encryption/disable-encrypt-only>
13. Get-RMSTemplate reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-rmstemplate>
14. Credit Card Number SIT definition - <https://learn.microsoft.com/purview/sit-defn-credit-card-number>
15. U.S. Social Security Number (SSN) SIT definition - <https://learn.microsoft.com/purview/sit-defn-us-social-security-number>
16. *Auto-Label Confidential PII in Exchange Email* (the known limitations) - the
    documented gap this scenario closes.
17. *PCI Teams Card-Data Exfiltration Block* - the sibling scenario this one's rule pattern (override
    group, `AccessScope`, `StopPolicyProcessing`) directly reuses.

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - DLP action/condition surfaces have changed more than once in this feature's history, same
> caveat as every other scenario in this library.