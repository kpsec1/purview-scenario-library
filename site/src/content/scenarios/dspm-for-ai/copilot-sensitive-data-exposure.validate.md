---
part: "validate"
parent: "dspm-for-ai/copilot-sensitive-data-exposure"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CopilotSensitiveDataProtectionPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Copilot DLP - Sensitive Data Exposure Protection" DLP policy is deployed
    correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The policy exists.
      2. Both rules exist with the expected priority order.
      3. Rule 0 (label exclusion) has the ExcludeContentProcessing/Block RestrictAccess setting.
      4. Rule 1 (web-grounding restriction) has RestrictWebGrounding = $true and the expected SITs.
      5. The policy Mode matches what was requested (warns, does not fail, if still in a Test* mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Does NOT check the policy's Locations/EnforcementPlanes output property directly - Microsoft's
    cmdlet reference does not document the exact Get-DlpCompliancePolicy output property name for
    a policy created via the generic -Locations/-EnforcementPlanes parameter pair (unlike the
    strongly-typed -TeamsLocation/-SharePointLocation properties this repo's other DLP validate
    scripts check directly). See deploy/New-CopilotSensitiveDataProtectionPolicy.ps1 .NOTES.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER SensitivityLabelName
    Expected sensitivity label display names for Rule 0, to confirm the AdvancedRule condition
    references the expected label GUIDs.

.PARAMETER SensitiveInformationTypeName
    Expected sensitive information type names for Rule 1.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-CopilotSensitiveDataProtectionPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitivityLabelName = @('Confidential', 'Highly Confidential'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInformationTypeName = @('U.S. Social Security Number (SSN)', 'Credit Card Number')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

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

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleLabel = $rules | Where-Object { $_.Name -eq 'Copilot-Exclude-Labeled-Content' }
$ruleWeb = $rules | Where-Object { $_.Name -eq 'Copilot-Restrict-WebGrounding-SensitivePrompts' }

Test-Check -Description 'Rule Copilot-Exclude-Labeled-Content exists' -Condition ($null -ne $ruleLabel)
Test-Check -Description 'Rule Copilot-Restrict-WebGrounding-SensitivePrompts exists' -Condition ($null -ne $ruleWeb)

if ($ruleLabel) {
    Test-Check -Description 'Label-exclusion rule has priority 0 (evaluated first)' `
        -Condition ($ruleLabel.Priority -eq 0)
    Test-Check -Description 'Label-exclusion rule carries an AdvancedRule condition' `
        -Condition (-not [string]::IsNullOrWhiteSpace($ruleLabel.AdvancedRule))
    if (-not [string]::IsNullOrWhiteSpace($ruleLabel.AdvancedRule)) {
        foreach ($labelName in $SensitivityLabelName) {
            $label = Get-Label -Identity $labelName -ErrorAction SilentlyContinue
            $labelReferenced = $label -and ($ruleLabel.AdvancedRule -match [regex]::Escape($label.Guid))
            Test-Check -Description "AdvancedRule references the '$labelName' label GUID" -Condition $labelReferenced
        }
    }
    Test-Check -Description 'Label-exclusion rule sets RestrictAccess ExcludeContentProcessing/Block' `
        -Condition (($ruleLabel.RestrictAccess | Where-Object { $_.setting -eq 'ExcludeContentProcessing' -and $_.value -eq 'Block' }).Count -gt 0)
    Test-Check -Description 'Label-exclusion rule generates an alert (not silent)' `
        -Condition ($null -ne $ruleLabel.GenerateAlert -and $ruleLabel.GenerateAlert.Count -gt 0)
}

if ($ruleWeb) {
    Test-Check -Description 'Web-grounding-restriction rule has priority 1' `
        -Condition ($ruleWeb.Priority -eq 1)
    Test-Check -Description 'Web-grounding-restriction rule sets RestrictWebGrounding = $true' `
        -Condition ($ruleWeb.RestrictWebGrounding -eq $true)
    foreach ($sitName in $SensitiveInformationTypeName) {
        $sitReferenced = ($ruleWeb.ContentContainsSensitiveInformation | Where-Object { $_.name -eq $sitName }).Count -gt 0
        Test-Check -Description "Web-grounding-restriction rule includes SIT '$sitName'" -Condition $sitReferenced
    }
    Test-Check -Description 'Web-grounding-restriction rule generates an alert (not silent)' `
        -Condition ($null -ne $ruleWeb.GenerateAlert -and $ruleWeb.GenerateAlert.Count -gt 0)
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
Write-Host 'Reminder: this policy protects LABELED content only. Separately review the DSPM for AI oversharing data risk assessment (README.md §7 step 6, §8) for unlabeled exposure this policy cannot see.' -ForegroundColor Cyan

if ($script:failures -gt 0) { exit 1 }
```