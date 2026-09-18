---
part: "validate"
parent: "information-protection/auto-label-eu-personal-data-exchange"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EuPersonalDataAutoLabelExchangePolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Confidentiality - Auto-Label EU Personal Data in Exchange Email" auto-labeling
    policy is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The target label exists and resolves via Get-Label.
      2. The policy exists and is scoped to the Exchange location.
      3. The rule exists, targets the Exchange workload, and references the expected SIT
         conditions (checked individually against -SensitiveInfoTypeName, not just "at least
         one").
      4. The policy Mode matches what was requested (warns, does not fail, if still in a Test*
         mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    This script does NOT verify that the label's scope includes "Emails", or that it is not a
    parent label (README.md §3/§11) - those require inspecting label-taxonomy fields this
    script's author could not confirm with certainty from Get-Label output; verify those manually
    in the Purview portal label list before deploying.

    IMPORTANT - config validation is not match validation, and Exchange has NO "Labeled items"
    dashboard the way SharePoint/OneDrive does. A fully green run here proves the policy and rule
    are shaped correctly, NOT that any email has actually been labeled. Use Activity Explorer
    (filter: Sensitivity label applied, 60-90 minute delay) for real confirmation - see
    README.md §7.

.PARAMETER PolicyName
    Name of the auto-labeling policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER LabelName
    Expected label name (or GUID) the policy should apply.

.PARAMETER SensitiveInfoTypeName
    Expected sensitive information type names the rule's condition list should contain. Must
    match the -SensitiveInfoTypeName used at deploy time (defaults to the same EU-wide bundle set
    the deploy script defaults to).

.PARAMETER IncludeTravelDocumentSits
    Pass this if the policy was deployed with -IncludeTravelDocumentSits, so this script checks
    for 'EU passport number' and "EU driver's license number" in addition to whatever
    -SensitiveInfoTypeName set is in effect - mirrors the deploy script's own switch instead of
    requiring the caller to retype the full expanded list. See README.md §6, design.md §5.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential'

.EXAMPLE
    ./Test-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential' -IncludeTravelDocumentSits

    Validates a policy deployed with the opt-in passport/driver's-license bundle enabled.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Confidentiality - Auto-Label EU Personal Data in Exchange Email',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'Confidential',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInfoTypeName = @(
        'EU national identification number',
        'EU Social Security Number (SSN) or Equivalent ID',
        'EU debit card number'
    ),

    [Parameter()]
    [switch]$IncludeTravelDocumentSits
)

if ($IncludeTravelDocumentSits) {
    $SensitiveInfoTypeName = @($SensitiveInfoTypeName + @('EU passport number', "EU driver's license number")) | Select-Object -Unique
}

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

Test-Check -Description 'Policy is scoped to the Exchange location' `
    -Condition ($policy.ExchangeLocation -and $policy.ExchangeLocation.Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rule = Get-AutoSensitivityLabelRule -Policy $PolicyName -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'AutoLabel-EuPersonalData-Exchange' }

Test-Check -Description 'Rule AutoLabel-EuPersonalData-Exchange exists' -Condition ($null -ne $rule)

if ($rule) {
    Test-Check -Description 'Rule targets the Exchange workload' `
        -Condition ($rule.Workload -contains 'Exchange')

    # Get-AutoSensitivityLabelRule's read-back shape for ContentContainsSensitiveInformation isn't
    # documented with the same certainty as the New-/Set- write shape (lowercase 'name'/'mincount'
    # keys, confirmed via New-DlpComplianceRule's own reference examples) - checking both 'name'
    # and 'Name' defensively rather than assuming one, per the casing VERIFY in README.md §11.
    $conditionNames = @($rule.ContentContainsSensitiveInformation | ForEach-Object {
        if ($_.PSObject.Properties['name']) { $_.name } elseif ($_.PSObject.Properties['Name']) { $_.Name }
    })
    Test-Check -Description 'Rule references at least one sensitive information type condition' `
        -Condition ($conditionNames.Count -gt 0)

    foreach ($expected in $SensitiveInfoTypeName) {
        Test-Check -Description "Rule includes SIT condition '$expected'" `
            -Condition ($conditionNames -contains $expected)
    }
}

Write-Host "`nManual checks not automated by this script (see README.md §3/§11):" -ForegroundColor Cyan
Write-Host "  - Confirm '$LabelName' label scope includes 'Emails'."
Write-Host "  - Confirm '$LabelName' is not a parent label (has no sublabels) in the Purview portal label list."
Write-Host "  - Confirm real labeling via Activity Explorer (Sensitivity label applied), not this script - there is no Labeled items dashboard for Exchange."

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```