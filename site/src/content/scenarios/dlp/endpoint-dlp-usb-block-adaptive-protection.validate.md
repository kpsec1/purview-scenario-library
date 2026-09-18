---
part: "validate"
parent: "dlp/endpoint-dlp-usb-block-adaptive-protection"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AdaptiveProtectionDevicesDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Adaptive Protection - Devices Endpoint DLP (Custom)" DLP policy is deployed
    correctly, and prints a manual checklist for the portal-only prerequisites and undocumented-
    shape actions this script cannot check via API.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Automated checks:
      1. The policy exists and is scoped to the Devices location.
      2. Both rules exist with the expected priority order.
      3. Rule 0 (Elevated) uses the correct -SharedByIRMUserRisk GUID and blocks all four
         restricted settings (RemovableMedia, CopyPaste, NetworkShare, Print).
      4. Rule 1 (Moderate/Minor) uses the correct GUIDs and audits (does not block) the same four
         settings.
      5. The policy Mode matches what was requested (warns, does not fail, if still in a Test* mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Then prints a manual checklist for everything this script has no API to query: device
    onboarding, Advanced classification scanning and protection, Adaptive Protection enablement,
    insider risk level definitions, the feeder IRM policy, and the two Quick-Setup actions
    (restricted apps, cloud/browser egress) this scenario's deploy script deliberately does not
    script because their -EndpointDlpRestrictions Setting/Value shape is undocumented (README.md
    Section 11). A policy that passes every automated check below can still silently match zero
    users, or match users with a narrower rule shape than Microsoft's own Quick Setup output, if
    these items aren't independently confirmed.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-AdaptiveProtectionDevicesDlpPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Adaptive Protection - Devices Endpoint DLP (Custom)'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

# Fixed, Microsoft-documented GUIDs for the three Adaptive Protection insider risk levels.
$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'
$riskLevelModerate = '797C4446-5C73-484F-8E58-0CCA08D6DF6C'
$riskLevelMinor = '75A4318B-94A2-4323-BA42-2CA6DB29AAFE'

$restrictedSettings = @('RemovableMedia', 'CopyPaste', 'NetworkShare', 'Print')

function Test-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [switch]$Warn
    )
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

function Test-RestrictionValues {
    param(
        [Parameter(Mandatory)] $Rule,
        [Parameter(Mandatory)] [string]$ExpectedValue,
        [Parameter(Mandatory)] [string]$RuleLabel
    )
    if (-not $Rule.EndpointDlpRestrictions) {
        Test-Check -Description "$RuleLabel has EndpointDlpRestrictions configured" -Condition $false
        return
    }
    foreach ($setting in $restrictedSettings) {
        $entry = $Rule.EndpointDlpRestrictions | Where-Object { $_.Setting -eq $setting }
        Test-Check -Description "$RuleLabel restricts '$setting' with Value='$ExpectedValue'" `
            -Condition ($null -ne $entry -and $entry.Value -eq $ExpectedValue)
    }
}

if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

Write-Host "Validating policy '$PolicyName'..." -ForegroundColor Cyan

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Policy '$PolicyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description 'Policy is scoped to the Devices (Endpoint DLP) location' `
    -Condition ($policy.EndpointDlpLocation -and $policy.EndpointDlpLocation.Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleBlock = $rules | Where-Object { $_.Name -eq 'AdaptiveProtection-Devices-Block-Elevated' }
$ruleAudit = $rules | Where-Object { $_.Name -eq 'AdaptiveProtection-Devices-Audit-ModerateMinor' }

Test-Check -Description 'Rule AdaptiveProtection-Devices-Block-Elevated exists' -Condition ($null -ne $ruleBlock)
Test-Check -Description 'Rule AdaptiveProtection-Devices-Audit-ModerateMinor exists' -Condition ($null -ne $ruleAudit)

if ($ruleBlock) {
    Test-Check -Description 'Elevated-block rule is scoped only to the Elevated risk-level GUID' `
        -Condition ($ruleBlock.SharedByIRMUserRisk -contains $riskLevelElevated -and $ruleBlock.SharedByIRMUserRisk.Count -eq 1)
    Test-Check -Description 'Elevated-block rule has priority 0 (evaluated first)' `
        -Condition ($ruleBlock.Priority -eq 0)
    Test-RestrictionValues -Rule $ruleBlock -ExpectedValue 'Block' -RuleLabel 'Elevated-block rule'
}

if ($ruleAudit) {
    Test-Check -Description 'Moderate/Minor-audit rule is scoped to exactly the Moderate and Minor GUIDs' `
        -Condition ($ruleAudit.SharedByIRMUserRisk -contains $riskLevelModerate -and $ruleAudit.SharedByIRMUserRisk -contains $riskLevelMinor -and $ruleAudit.SharedByIRMUserRisk.Count -eq 2)
    Test-Check -Description 'Moderate/Minor-audit rule still generates an alert for visibility' `
        -Condition ($null -ne $ruleAudit.GenerateAlert -and $ruleAudit.GenerateAlert.Count -gt 0)
    Test-RestrictionValues -Rule $ruleAudit -ExpectedValue 'Audit' -RuleLabel 'Moderate/Minor-audit rule'
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

Write-Host "`n--- Manual checklist (no API surface exists to check these) ---" -ForegroundColor Cyan
Write-Host '  [ ] Target devices are onboarded to Microsoft Purview device management (Settings > Device onboarding > Devices) and reporting into Activity explorer.'
Write-Host '  [ ] Advanced classification scanning and protection is turned ON (Purview portal > Data loss prevention > Endpoint DLP settings) - required for Adaptive Protection to work on Devices at all.'
Write-Host '  [ ] Adaptive Protection is turned ON (Purview portal > Insider Risk Management > Adaptive protection > Adaptive Protection settings).'
Write-Host '  [ ] Elevated/Moderate/Minor insider risk levels are defined (same definitions as the Exchange/Teams sibling scenario).'
Write-Host '  [ ] At least one Insider Risk Management policy is included in Adaptive Protection scope.'
Write-Host '  [ ] Purview portal > Insider Risk Management > Adaptive protection > Data Loss Prevention tab lists this policy.'
Write-Host '  [ ] At least 36 hours have passed since Adaptive Protection was enabled before concluding a pilot user was not correctly matched.'
Write-Host "  [ ] NOT scripted by this scenario (undocumented -EndpointDlpRestrictions shape - see README.md Section 11): 'Access by restricted apps' and 'Upload to a restricted cloud service domain or access from unallowed browsers.' If you need these two actions to fully match Microsoft's Quick Setup output, add them manually via the portal on both rules and confirm the resulting behavior there rather than assuming this script's four-setting subset is the complete Quick Setup rule shape."
Write-Host '  [ ] If scenarios/dlp/endpoint-dlp-usb-block is also deployed in this tenant, confirm the combined behavior for a user matched by both policies matches Microsoft''s documented "most restrictive policy wins" interaction rule (README.md Section 11) rather than assuming independent correctness.'
Write-Host '  [ ] End-to-end functional test (non-production device/account only): assign a test user a confirmed insider risk level, then have that account attempt to copy a file to a USB drive, network share, clipboard, or print it on an onboarded device. Confirm the expected rule (block for Elevated, audit for Moderate/Minor) fires and an alert appears in the DLP Alerts dashboard.'

if ($script:failures -gt 0) { exit 1 }
```