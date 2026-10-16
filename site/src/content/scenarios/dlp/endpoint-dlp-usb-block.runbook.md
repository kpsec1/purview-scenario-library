---
part: "runbook"
parent: "dlp/endpoint-dlp-usb-block"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Onboard devices first** (one-time, not part of this scenario's deploy script). Sign in to the
   [Microsoft Purview portal](https://purview.microsoft.com) → **Settings** → **Device
   onboarding** → **Devices** → **Turn on device onboarding** → **Onboarding**, choose a
   deployment method (local script, Group Policy, Configuration Manager, or Intune), and deploy
   the downloaded package to target endpoints. If devices are already onboarded to Microsoft
   Defender for Endpoint, they already appear in this list - only **Turn on device monitoring** is
   needed.
2. Go to **Data loss prevention** → **Policies** → **Create policy**.
3. Category: **Custom** → template: **Custom policy** → **Next**.
4. Name: `Endpoint DLP - Block USB Removable Media Exfiltration`. **Policies can't be renamed
   after creation** - confirm the name before continuing.
5. **Assign admin units**: accept **Full directory** (unless the tenant uses administrative units
   - see [RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive)).
6. **Choose locations**: select **Devices** only; deselect all other locations.
7. **Define policy settings**: choose **Create or customize advanced DLP rules**.
8. Create rule **USB-Block-Sensitive-AllUsers** (priority 0):
   - Conditions: **Content contains** → **Sensitive info types** → **U.S. Social Security Number
     (SSN)** OR **Credit Card Number** (min count 1 each); add **Sender is a member of** with
     **Except if** toggled → the IT Data Custodians group.
   - Actions: **Audit or restrict activities on devices** → **File activities for all apps** →
     **Apply restrictions to specific activity** → set **Copy to a removable USB device** =
     **Block**.
   - Incident reports: alert **High** severity, send to the SOC/admin mailbox.
9. Create rule **USB-Audit-ITDataCustodians** (priority 1): same content condition, scoped
   (**not** excepted) to the IT Data Custodians group; same activity restriction but set **Copy to
   a removable USB device** = **Audit only**; alert **Low** severity.
10. **Policy mode**: choose **Run the policy in simulation mode** first. Do not turn it on
    immediately - follow the staged rollout in operations and tuning below.
11. **Submit**, then **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real activity first
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. After a tuning window and a pilot-tenant functional test, enforce
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com'

# Optional: justification-gate the IT Data Custodians path instead of silently logging it
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -ITExceptionAction Warn -Mode Enable -Force
./validate/Test-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -ExpectedITExceptionAction Warn
```

The deploy script uses Security & Compliance PowerShell (`New-DlpCompliancePolicy`,
`New-DlpComplianceRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Device
onboarding itself has no equivalent PowerShell/Graph cmdlet documented as of this writing and must
be performed as in the implementation steps step 1 above, once, before this policy has any effect.

## Configuration reference

| Setting | Rule 0: `USB-Block-Sensitive-AllUsers` | Rule 1: `USB-Audit-ITDataCustodians` |
|---|---|---|
| Priority | 0 | 1 |
| Sender scope | `ExceptIfFromMemberOf` = IT Data Custodians group | `FromMemberOf` = IT Data Custodians group |
| Sensitive content | SSN OR Credit Card Number (min count 1 each) | SSN OR Credit Card Number (min count 1 each) |
| `EndpointDlpRestrictions` | `@{Setting='RemovableMedia'; Value='Block'}` - confirmed, see the known limitations | `@{Setting='RemovableMedia'; Value=$ITExceptionAction}` - `Audit` (default) or `Warn`, confirmed, see the known limitations |
| `ReportSeverityLevel` | High | Low |
| `GenerateAlert` / `GenerateIncidentReport` | Admin + SOC mailbox | Admin + SOC mailbox |
| `StopPolicyProcessing` | `$true` | `$false` |
| Policy location | `EndpointDlpLocation = "All"` (both rules share the one policy) | |
| Policy `Mode` | `TestWithNotifications` (deploy default) → `Enable` after tuning | |

Full cmdlet parameter grounding: `deploy/New-EndpointDlpUsbBlockPolicy.ps1` inline comments and
its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence** (mirrors Microsoft's documented staged rollout used across every DLP
scenario in this library): Off → Run in simulation mode → Run in simulation mode + show policy tips
(pilot group) → Turn it on. The deploy script's default `-Mode TestWithNotifications` corresponds
to the simulation stage; pass `-Mode Enable` deliberately once tuning and the validation steps functional tests
are complete.

**KPIs to watch (first 30 days):**
- **Rule 0 (all-users block) match count** - a sudden spike after enabling usually means a
  legitimate business process was missed by the IT Data Custodians exception, not a wave of
  attempted exfiltration. Investigate before assuming malice.
- **Rule 1 (IT Data Custodians audit) volume and per-user distribution** - this is the baseline of
  how much sensitive content the custodian team actually copies to removable media as part of its
  job. An unusually high volume from a single custodian account relative to peers is the signal
  worth investigating first.
- **False-positive rate** - SIT false positives (test data, employee IDs that happen to be
  9 digits) show up as user complaints; tune by adjusting the SIT's confidence level or minimum
  count only after confirming the pattern in Activity explorer, not from a single report.

**Alert routing:** both rules generate alerts and incident reports to the SOC/admin mailbox
parameter. Route the DLP alert source into the SIEM (Microsoft Sentinel connector, or the
Microsoft Defender XDR incident queue export) so it lands in existing on-call rotation rather than
living only in the Purview portal - see [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task).

**Review cadence:** quarterly at minimum for the overall control; re-run
`validate/Test-EndpointDlpUsbBlockPolicy.ps1` as part of that review to catch configuration drift.
Review **Rule 1 (IT Data Custodians) audit volume** on a **weekly** cadence, not quarterly - this
audit-only group is the one path in this design that can move real regulated data onto removable
media with no block at all, so it is the highest-value target for a compromised or malicious
insider and deserves the same weekly-review discipline as the Card Operations override in
*PCI Teams Card-Data Exfiltration Block*.

**Incident-response runbook (Rule 0 block alert, or a Rule 1 audit event that looks anomalous):**
1. **Triage** - open the alert in the DLP Alerts dashboard or Microsoft Defender portal incident
   queue; confirm which rule matched, the user, the device, and that the "Sensitive info types"
   tab shows an actual SSN/PAN-shaped match rather than a false positive.
2. **Classify** - true positive vs. false positive. False positive: no further action beyond
   noting the pattern for a future SIT confidence-threshold tuning pass.
3. **True positive, Rule 0 (block, non-Custodian user)** - the copy never completed; contact the
   user's manager and initiate the org's standard data-handling incident process. Determine
   whether the user needs a legitimate exception path or security-awareness follow-up.
4. **True positive, Rule 1 (IT Data Custodian audit)** - the copy already completed. Confirm the
   activity matches the custodian's known backup/imaging schedule and device. If it doesn't
   (unscheduled, unusual volume, unfamiliar device), escalate as a potential insider-risk event
   and consider temporary removal from the IT Data Custodians group pending investigation.
5. **Document** - every true positive and every custodian audit-event review is retained as
   incident-response evidence; do not delete or edit alert records.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-EndpointDlpUsbBlockPolicy.ps1` disables (reversible); add `-Purge` to
permanently delete the policy and its rules.

## References

1. Microsoft Purview service description - Endpoint Data Loss Prevention (DLP) licensing table - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-data-loss-prevention-endpoint-data-loss-protection-dlp>
2. Onboard Windows devices into Microsoft 365 overview (onboarding methods, supported OS builds, permissions - device management supports only Entra roles) - <https://learn.microsoft.com/purview/device-onboarding-overview>
3. Learn about the default DLP policy in Microsoft Teams (naming behavior applies to all DLP policies: cannot be renamed after creation) - <https://learn.microsoft.com/purview/dlp-teams-default-policy>
4. Data Loss Prevention policy reference (Audit or restrict activities on devices; Allow/Audit only/Block with override/Block action semantics; Copy to a removable device activity) - <https://learn.microsoft.com/purview/dlp-policy-reference>
5. Troubleshooting endpoint data loss prevention configuration and policy sync - <https://learn.microsoft.com/purview/dlp-edlp-tshoot-sync>
6. Help protect files that Endpoint Data Loss Prevention doesn't scan - <https://learn.microsoft.com/purview/dlp-create-policy-files-edlp-doesnt-scan>
7. Configure endpoint data loss prevention settings (Removable USB device groups, restricted-activity actions) - <https://learn.microsoft.com/purview/dlp-configure-endpoint-settings>
8. New-DlpCompliancePolicy reference (EndpointDlpLocation, Mode) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
9. New-DlpComplianceRule reference (EndpointDlpRestrictions - confirmed Setting names Print/CopyPaste/ScreenCapture/RemovableMedia/NetworkShare/UnallowedApps and Value enum Audit/Block/Ignore/Warn, plus the NotifyUser requirement for Block/Warn; also ContentContainsSensitiveInformation, FromMemberOf/ExceptIfFromMemberOf, StopPolicyProcessing, ReportSeverityLevel) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
10. Set-DlpComplianceRule reference (EndpointDlpRestrictions - identical Setting/Value enumeration and NotifyUser requirement, confirmed independently) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
11. Set-DlpCompliancePolicy reference (Mode: Enable/Disable/TestWithNotifications/TestWithoutNotifications) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>
12. Remove-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
13. Get started with Endpoint data loss prevention - <https://learn.microsoft.com/purview/endpoint-dlp-getting-started>
14. Learn about Endpoint data loss prevention (local evaluation, file classification triggers) - <https://learn.microsoft.com/purview/endpoint-dlp-learn-about>
15. Device control in Microsoft Defender for Endpoint (content-blind device-level USB control, complementary to Endpoint DLP) - <https://learn.microsoft.com/defender-endpoint/device-control-overview>
16. Creating Endpoint DLP Rules using PowerShell - Part 1 (Microsoft Security Blog, Tech Community - secondary/corroborating EndpointDlpRestrictions Setting/Value hashtable example for RemovableMedia and Print, superseded as primary citation by items 9-10) - <https://techcommunity.microsoft.com/blog/microsoft-security-blog/creating-endpoint-dlp-rules-using-powershell---part-1/4286999>
17. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
18. U.S. Social Security Number (SSN) / Credit Card Number sensitive information types - reused from *Auto-Label Confidential PII in SharePoint & OneDrive* (see that scenario's own references for SIT definition citations).
19. Configure endpoint DLP settings (Removable USB device groups - creation workflow, Vendor ID/Product ID/Instance ID device identification, per-device alias) - <https://learn.microsoft.com/purview/dlp-configure-endpoint-settings>
20. Configuring USB hardware ID exceptions in Microsoft Purview endpoint DLP (Microsoft Q&A - confirms the rule-level workflow: create the device group in Endpoint DLP settings, then add an exclusion for it under the rule's actions/exceptions) - <https://learn.microsoft.com/answers/questions/5942592/configuring-usb-hardware-id-exceptions-in-microsof>
21. Set-PolicyConfig reference (`-DlpRemovableMediaGroups`/`-DlpPrinterGroups`/`-DlpNetworkShareGroups`/`-DlpAppGroups`/`-DlpExtensionGroups` - confirmed to exist as `PswsHashtable`/`PswsHashtable[]` parameters; description text and the cmdlet's EXAMPLES section are unpublished placeholder content as of this pass) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-policyconfig>

> Re-verify all links against current Microsoft Learn and a pilot tenant before a customer-facing
> assessment or sale. The `EndpointDlpRestrictions` `Setting`/`Value` shape is now grounded in
> items 9-10 (official Microsoft Learn cmdlet reference pages, fetched and confirmed directly);
> item 16's community walkthrough is kept only as a secondary, corroborating source. The `Warn`
> value's mapping to the portal's "Block with override" option remains a well-corroborated
> inference, not a literal Microsoft citation - confirm the on-screen behavior in a pilot tenant
> before relying on that framing with a customer.