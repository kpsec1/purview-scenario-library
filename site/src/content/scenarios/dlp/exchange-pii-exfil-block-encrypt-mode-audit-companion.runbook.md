---
part: "runbook"
parent: "dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Data loss prevention** → **Policies** → open the parent scenario's existing policy (`PII DLP -
   Exchange External Send Control`) → **Edit policy** → **Create or customize advanced DLP rules**
   → **+ Create rule**.
2. Rule name: `PII-Exchange-Audit-Encrypt-Exception`. **Conditions**: **Content contains** →
   **Sensitive info types** → **U.S. Social Security Number (SSN)** and **Credit Card Number**,
   minimum count **1** each, **Any of these** (OR) - identical SIT conditions to every other rule in
   this policy. Add **Sender is a member of** → the same nominated business-exception group used at
   parent-scenario deploy time (`-ExceptionGroupEmail`). Add **Recipient is** → **outside my
   organization**.
3. **Actions**: no restriction/encryption action - **Generate an incident report and send it to**
   the same SOC/admin distribution list the parent scenario notifies, with severity **Low**
   (matching `PII-Exchange-Audit-Internal`'s severity convention - this event is informational, not
   an enforcement failure; the exception is intentional and approved, only its *visibility* was
   missing).
4. Leave **Priority** unset if this is the first rule created after the parent policy's existing
   three - the portal auto-assigns the next available slot for a rule added to an Exchange-scoped
   policy. If reconciling via script, see the configuration reference for the explicit `-Priority` this
   scenario's deploy script requires.
5. **Save**. No change to the policy's overall `Mode` is needed - this rule inherits whatever mode
   (`TestWithNotifications` or `Enable`) the parent policy is already running in; being audit-only,
   it behaves identically in both.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports the change, makes none
./deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1 `
    -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Deploy
./deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1 `
    -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. Validate
./validate/Test-ExchangePiiEncryptModeAuditCompanion.ps1 -ExceptionGroupEmail 'hr-benefits-ops@contoso.com'
```

The deploy script uses the same Security & Compliance PowerShell surface as the parent scenario
(`New-DlpComplianceRule` against the parent's **existing** `-PolicyName`) - automation surface 2 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). It does not call `New-DlpCompliancePolicy` - this fragment never
creates a policy of its own; see the design notes.

## Configuration reference

| Setting | `PII-Exchange-Audit-Encrypt-Exception` |
|---|---|
| Sensitive info types | SSN, Credit Card Number - `mincount = 1` each, OR-combined (identical to every other rule in the policy) |
| `FromMemberOf` | `<ExceptionGroupEmail>` (must match the parent scenario's own `-ExceptionGroupEmail` exactly) |
| `AccessScope` | `NotInOrganization` |
| `BlockAccess` | `$false` (non-halting - this rule never restricts delivery) |
| `GenerateAlert` / `GenerateIncidentReport` | `<AdminNotificationEmail>` |
| `ReportSeverityLevel` | `<ReportSeverityLevel>` (default `Low`; raise to `High` for a higher-risk exception group - see the design notes and the Blue Team finding in the review notes) |
| `Priority` | Explicit, deploy-script-computed - defaults to one past the highest existing rule priority in the target policy; the script fails clearly rather than silently colliding with an existing rule's priority. See the design notes. |
| `StopPolicyProcessing` | Not set (`$false`/default) - there is nothing after it to stop; see the design notes. |

| Policy-level setting | Value |
|---|---|
| Target policy | `<PolicyName>` (default `PII DLP - Exchange External Send Control` - must match the parent scenario's `-PolicyName`) |
| `Mode` | Not touched by this script - inherits the parent policy's current mode |

Full cmdlet parameter grounding: `deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1` inline
comments and its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence:** no separate simulation stage - this rule is audit-only by construction, so
there is no "enforcement" phase to stage into. Deploy it directly once the parent scenario is
confirmed running in Encrypt mode with an exception group configured.

**KPIs to watch:**
- **Volume of `PII-Exchange-Audit-Encrypt-Exception` alerts.** This is expected to be low - it only
  fires for a nominated, presumably small exception group. A sustained or growing volume is a signal
  worth investigating on its own terms (is the exception group's approved use case actually this
  frequent, or has group membership drifted beyond its original intent?), independent of whether the
  underlying Encrypt action is "working as designed."
- **Severity is a policy decision, not a fixed default.** This rule's default `ReportSeverityLevel`
  is `Low` to match the internal-audit convention, but if the nominated exception group includes
  privileged or otherwise high-risk mailboxes, deploy with `-ReportSeverityLevel High` instead so a
  compromised account isn't triaged at the same priority as routine audit noise - see the design notes.
- **Correlate against the exception group's membership review cadence.** Since this rule's entire
  purpose is visibility into a population that was deliberately excluded from a stronger control,
  its alert volume is a natural input to the same group-membership review this library recommends
  for the parent scenario's Block-mode override path (*Exchange PII Exfiltration Block (Block or Encrypt)* (operations and tuning)).

**Alert routing:** lands in the same DLP Alerts dashboard / Microsoft Defender portal as every other
rule in the parent policy - no separate pipeline. An analyst triaging that dashboard should
recognize this rule by name (`PII-Exchange-Audit-Encrypt-Exception`) as "expected exception traffic,
now visible" rather than "a new attack pattern."

**Runbook - confirming this companion is still doing its job:**
1. Run `./validate/Test-ExchangePiiEncryptModeAuditCompanion.ps1` - confirms the rule still exists
   and is still correctly scoped.
2. Confirm the parent policy is still running `-Action Encrypt` with the same `-ExceptionGroupEmail`
   - if either changed without re-running this companion's deploy script, the two can drift out of
   sync.
3. If the parent scenario's `-ExceptionGroupEmail` changes (a different group is nominated), re-run
   `deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1 -Force` with the new group email - this
   script does not watch for that change automatically.

**Review cadence:** align with the parent scenario's own review cadence (*Exchange PII Exfiltration Block (Block or Encrypt)* (operations and tuning)) - monthly for the first quarter, quarterly thereafter. There is no independent
cadence for this companion; it is not a standalone control with its own lifecycle.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference:
`./deploy/Remove-ExchangePiiEncryptModeAuditCompanion.ps1` removes only this rule - the parent
policy and its other rules are untouched.

## References

1. New-DlpComplianceRule reference - full parameter syntax, confirms `FromMemberOf`, `AccessScope`,
   `BlockAccess`, `GenerateAlert`, `GenerateIncidentReport`, `ReportSeverityLevel`, `Priority` - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
2. Set-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
3. Remove-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
4. Get-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancerule>
5. New-DlpComplianceRule reference - `-AccessScope` parameter: "InOrganization: ... a recipient
   inside the organization. NotInOrganization: ... a recipient outside the organization." - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule#-accessscope>
6. New-DlpComplianceRule reference - `-FromMemberOf` parameter (sender is a member of the specified
   distribution group, mail-enabled security group, or Microsoft 365 group) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule#-frommemberof>
7. Data Loss Prevention policy reference - rule priority: "For the hosted service locations, like
   Exchange, SharePoint, and OneDrive, each rule is assigned a priority in the order in which it's
   created," and multi-rule-match behavior: "If content matches multiple rules, the first rule
   evaluated that has the most restrictive action is enforced... matches for all of the rules are
   recorded in the audit logs and shown in the DLP reports, even though only the most restrictive
   rule is applied." - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
8. Credit Card Number SIT definition - <https://learn.microsoft.com/purview/sit-defn-credit-card-number>
9. U.S. Social Security Number (SSN) SIT definition - <https://learn.microsoft.com/purview/sit-defn-us-social-security-number>
10. *Exchange PII Exfiltration Block (Block or Encrypt)* (the known limitations) - the documented gap this companion
    closes (visibility, not prevention).
11. *Exchange PII Exfiltration Block (Block or Encrypt)* (the configuration reference) - the original design decision explaining
    why Encrypt mode has no override concept to log against, which is the root cause this companion
    works around rather than reverses.

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - same caveat as every other scenario in this library.