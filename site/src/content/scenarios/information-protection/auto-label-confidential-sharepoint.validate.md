---
part: "validate"
parent: "information-protection/auto-label-confidential-sharepoint"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ConfidentialAutoLabelPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Confidentiality - Auto-Label PII in SharePoint and OneDrive" auto-labeling
    policy is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The target label exists and resolves via Get-Label.
      2. The policy exists and is scoped to SharePoint and OneDrive locations.
      3. Both rules exist, target the correct workload, and reference the same SIT conditions.
      4. The policy Mode matches what was requested (warns, does not fail, if still in a Test*
         mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    This script does NOT verify the "not a parent label" or "label scope includes Files & other
    data assets" prerequisites (README.md §11) - those require inspecting label-taxonomy fields
    this script's author could not confirm with certainty from Get-Label output; verify those
    manually in the Purview portal label list before deploying.

    IMPORTANT - config validation is not match validation: a fully green run here proves the
    policy and rules are shaped correctly, NOT that the policy is actually labeling any files
    (e.g. a wrong region, or EnableAIPIntegration never turned on, would still pass every check
    below). Always cross-check the Overview / Labeled items dashboard in the Purview portal for
    non-zero match volume before treating a green run as end-to-end proof (see README.md §7, §11).

.PARAMETER PolicyName
    Name of the auto-labeling policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER LabelName
    Expected label name (or GUID) the policy should apply.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-ConfidentialAutoLabelPolicy.ps1 -LabelName 'Confidential'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label PII in SharePoint and OneDrive',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'Confidential'
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

if (-not (Get-Command Get-AutoSensitivityLabelPolicy -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

Write-Host "Validating auto-labeling policy '$PolicyName'..." -ForegroundColor Cyan

$label = Get-Label -Identity $LabelName -ErrorAction SilentlyContinue
Test-Check -Description "Label '$LabelName' exists and resolves via Get-Label" -Condition ($null -ne $label)

$policy = Get-AutoSensitivityLabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Policy '$PolicyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description 'Policy applies the expected label' `
    -Condition ($policy.ApplySensitivityLabel -eq $LabelName -or $policy.ApplySensitivityLabel -eq $label.ImmutableId)

Test-Check -Description 'Policy is scoped to SharePoint locations' `
    -Condition ($policy.SharePointLocation -and $policy.SharePointLocation.Count -gt 0)

Test-Check -Description 'Policy is scoped to OneDrive locations' `
    -Condition ($policy.OneDriveLocation -and $policy.OneDriveLocation.Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-AutoSensitivityLabelRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleSharePoint = $rules | Where-Object { $_.Name -eq 'AutoLabel-Confidential-PII-SharePoint' }
$ruleOneDrive = $rules | Where-Object { $_.Name -eq 'AutoLabel-Confidential-PII-OneDrive' }

Test-Check -Description 'Rule AutoLabel-Confidential-PII-SharePoint exists' -Condition ($null -ne $ruleSharePoint)
Test-Check -Description 'Rule AutoLabel-Confidential-PII-OneDrive exists' -Condition ($null -ne $ruleOneDrive)

if ($ruleSharePoint) {
    Test-Check -Description 'SharePoint rule targets the SharePoint workload' `
        -Condition ($ruleSharePoint.Workload -contains 'SharePoint')
    Test-Check -Description 'SharePoint rule references at least one sensitive information type condition' `
        -Condition ($null -ne $ruleSharePoint.ContentContainsSensitiveInformation -and $ruleSharePoint.ContentContainsSensitiveInformation.Count -gt 0)
}

if ($ruleOneDrive) {
    Test-Check -Description 'OneDrive rule targets the OneDriveForBusiness workload' `
        -Condition ($ruleOneDrive.Workload -contains 'OneDriveForBusiness')
    Test-Check -Description 'OneDrive rule references at least one sensitive information type condition' `
        -Condition ($null -ne $ruleOneDrive.ContentContainsSensitiveInformation -and $ruleOneDrive.ContentContainsSensitiveInformation.Count -gt 0)
}

Write-Host "`nManual checks not automated by this script (see README.md §11):" -ForegroundColor Cyan
Write-Host "  - Confirm '$LabelName' is not a parent label (has no sublabels) in the Purview portal label list."
Write-Host "  - Confirm '$LabelName' label scope includes 'Files & other data assets'."
Write-Host "  - Confirm (Get-SPOTenant).EnableAIPIntegration is `$true (requires SharePoint Online Management Shell)."

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```