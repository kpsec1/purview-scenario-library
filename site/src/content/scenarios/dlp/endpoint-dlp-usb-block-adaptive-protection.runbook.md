---
part: "runbook"
parent: "dlp/endpoint-dlp-usb-block-adaptive-protection"
---
## Implementation steps

This scenario assumes the Exchange/Teams sibling scenario's Steps 1-3 (feeder IRM policy,
permissions, insider risk level definitions) are already complete - do those once; both policies
consume the same Adaptive Protection configuration.

### Step 1 - Onboard target devices (portal/MDM, not scriptable here)

Devices must already be onboarded to Microsoft Purview device management before this policy can
match any activity on them. See *Endpoint DLP: Block USB Removable Media Exfiltration* (the prerequisites and the implementation steps) for the
full onboarding procedure - not repeated here.

### Step 2 - Turn on Advanced classification scanning and protection (portal, not scriptable)

Purview portal → **Data loss prevention** → **Overview** → settings gear icon → **Endpoint DLP
settings** → **Advanced classification scanning and protection** → toggle **On**. Microsoft
documents this (or an explicit **File Type is** condition) as required for Adaptive Protection to
work on Devices at all; this scenario uses this path rather than a File Type
condition because the corresponding PowerShell parameter's value syntax is undocumented.

### Step 3 - Deploy the DLP policy (scripted, dry-run capable)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows exactly what would be created, changes nothing
./deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

# Deploy in simulation mode (Microsoft's own Quick Setup default posture)
./deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications
```

This creates one Endpoint DLP policy scoped to the Devices location, with two rules keyed off the
`SharedByIRMUserRisk` condition and the four confirmed `EndpointDlpRestrictions` settings.

### Step 4 - Pilot, then enforce

Same guidance as the Exchange/Teams sibling scenario: confirm the feeder IRM policy has completed
at least one full baseline/tuning cycle before promoting to enforcement. Pilot on non-production
test accounts/devices while the policy is in `TestWithNotifications` mode. Once satisfied:

```powershell
./deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force
```

### Step 5 - Validate

```powershell
./validate/Test-AdaptiveProtectionDevicesDlpPolicy.ps1
```

### Step 6 - (Optional) Complete the remaining two Quick Setup actions manually

Microsoft's own Quick Setup Devices rule also includes **Access by restricted apps** and
**Upload to a restricted cloud service domain or access from unallowed browsers**. This scenario's script does not create either action because no documented
`-EndpointDlpRestrictions` Setting/Value shape exists for them at the rule level. If an organization wants full parity with Microsoft's Quick Setup output, add both actions to
**both** rules manually via the portal (Purview portal → **Data loss prevention** → open this
policy → edit each rule's **Audit or restrict activities on devices** action) rather than assuming
this script's four-setting subset is the complete picture.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| DLP policy name | `Adaptive Protection - Devices Endpoint DLP (Custom)` | Deliberately distinct from Microsoft's Quick-Setup-generated name (`Adaptive Protection policy for Endpoint DLP`) - see the known limitations |
| Policy location | Devices (`-EndpointDlpLocation All`) | Endpoint DLP only - Exchange/Teams covered by the sibling scenario |
| Rule 0: `AdaptiveProtection-Devices-Block-Elevated` | `SharedByIRMUserRisk = FCB9FA93-6269-4ACF-A756-832E79B36A2A` (Elevated) → `EndpointDlpRestrictions`: `RemovableMedia`/`CopyPaste`/`NetworkShare`/`Print` all set to `Block` | Reproduces 4 of Microsoft's documented 6 Quick Setup actions for this rule - see the known limitations for the 2 not scripted |
| Rule 1: `AdaptiveProtection-Devices-Audit-ModerateMinor` | `SharedByIRMUserRisk = 797C4446-5C73-484F-8E58-0CCA08D6DF6C, 75A4318B-94A2-4323-BA42-2CA6DB29AAFE` (Moderate, Minor) → same 4 settings, all `Audit` | Same 2-action gap as Rule 0 |
| `NotifyUser` (Rule 0 only) | `@('LastModifier')` | Required by Microsoft's documented cmdlet reference for a Block value - in tension with Quick Setup's own displayed "User Notification: Off" for this rule; disclosed, not silently resolved - see the known limitations |
| Initial policy mode | `TestWithNotifications` (simulation) | Matches Microsoft's own Quick Setup default |
| Incident report severity | `Low` for both rules | Matches Microsoft's documented values |
| User override | Not enabled (default off) | Matches Microsoft's documented values |
| `ScreenCapture` | Not configured | Not part of Microsoft's documented Devices Quick Setup rule table for this policy - see the design notes |
| Advanced classification scanning and protection | Must be ON (portal, step 2 of the implementation steps) | Devices-specific Adaptive Protection prerequisite, distinct from the Exchange/Teams sibling's prerequisites |
| File Type condition | Not added - rule applies to **any** file type | Microsoft's own Quick Setup rule scopes its version of this rule to Word processing/Spreadsheet/Presentation/Archive/Mail via a "File Type is" condition; this scenario instead satisfies the same prerequisite via Advanced classification scanning and protection (above), so no File Type condition is added. Net effect: **broader** file-type coverage than Quick Setup, **narrower** activity coverage (4 of 6 actions) - see section 11 |

## Operations and tuning

Same KPI framework, tuning guidance, and incident-response runbook shape as the Exchange/Teams
sibling scenario (*Dynamic Risk-Based DLP Enforcement* (operations and tuning)) - not repeated in full here. Two
Devices-specific additions:

- **Track the split between the two policies.** Because Elevated-risk enforcement now spans two
  independent DLP policies (Exchange/Teams and Devices), review both policies' incident volume
  together, not in isolation - a user blocked on one channel and immediately active on the other
  is a signal the combined control is working as intended (contained on the attempted channel),
  not that one policy "missed" something the other caught.
- **Watch for interaction with *Endpoint DLP: Block USB Removable Media Exfiltration*, if also deployed.**
  Microsoft's documented "most restrictive policy wins" rule means a user matched by both
  this policy and that one gets the stricter of the two outcomes automatically - but confirm this
  composes as expected for your specific rule configurations in a pilot tenant rather than
  assuming it always resolves the way you'd want.
- **Coordinate with HR/Legal before broad enforcement-mode rollout** - identical residual
  consideration to the Exchange/Teams sibling scenario (an Elevated-risk block is driven by an
  opaque ML-computed risk score, not a human decision); see that scenario's operations and tuning and
  the CISO review.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent removal).
Quick reference: `./deploy/Remove-AdaptiveProtectionDevicesDlpPolicy.ps1` disables the policy
(reversible in seconds); `-Purge` permanently deletes it. Rolling back this scenario has no effect
on the Exchange/Teams sibling policy, Adaptive Protection itself, device onboarding, or Advanced
classification scanning and protection - each is independently owned.

## References

1. Learn about Adaptive Protection in Data Loss Prevention (documented Devices Quick Setup rule
   table - six-activity action list including the two this scenario doesn't script; Advanced
   classification/File Type prerequisite; "most restrictive policy" interaction rule) - <https://learn.microsoft.com/purview/dlp-adaptive-protection-learn>
2. Permissions for Adaptive Protection - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection#permissions-for-adaptive-protection>
3. Help dynamically mitigate risks with Adaptive Protection (36-hour propagation delay) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
4. New-DlpComplianceRule reference (`-EndpointDlpRestrictions`, `-SharedByIRMUserRisk`,
   `-ContentFileTypeMatches` placeholder text, `NotifyUser` requirement) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
5. Set-DlpComplianceRule reference (identical text, confirmed independently) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
6. New-DlpCompliancePolicy reference (`-EndpointDlpLocation` parameter) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
7. Set-DlpCompliancePolicy / Remove-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>, <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
8. Configure endpoint data loss prevention settings (Advanced classification scanning and
   protection, Restricted apps and app groups, Browser and domain restrictions) - <https://learn.microsoft.com/purview/dlp-configure-endpoint-settings>
9. Set-PolicyConfig reference (`-EndpointDlpGlobalSettings` - documented tenant-wide list
   mechanism, distinct from this scenario's per-rule action gap; see the design notes) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-policyconfig>
10. [Licensing matrix, section 2](/docs/licensing-matrix/#2-master-capability--license-matrix) - Adaptive Protection and Endpoint DLP rows.
11. *Dynamic Risk-Based DLP Enforcement* - the Exchange/Teams sibling
    scenario this one complements.
12. *Endpoint DLP: Block USB Removable Media Exfiltration* - the always-on Devices DLP policy this scenario's
    the known limitations documents an interaction with.

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - Adaptive Protection and Endpoint DLP are both
> comparatively fast-moving areas of the Purview portfolio.