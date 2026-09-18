---
part: "validate"
parent: "dspm-for-ai/copilot-prompt-full-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CopilotPromptFullBlockRule.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Copilot-Block-SensitivePrompts-FullResponse" DLP rule is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy or rule state. Checks:
      1. The parent policy exists.
      2. The rule exists, is not Disabled, and has the expected priority.
      3. The rule's ContentContainsSensitiveInformation condition references the expected SITs.
      4. The rule's RestrictAccess setting/value pair matches this repo's deployed configuration
         (ExcludeContentProcessing/Block) - checked as [WARN], not [FAIL], because Microsoft has
         not published a worked example confirming this exact setting for this exact
         condition/action combination. See README.md Sec 5 and design.md Sec 5.
      5. The rule generates an alert (not silent).
    Exits with a non-zero code if any hard ([FAIL]) check fails. [WARN] checks never affect the
    exit code. Safe to re-run any number of times.

.PARAMETER PolicyName
    Name of the parent DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER SensitiveInformationTypeName
    Expected sensitive information type names for this rule.

.PARAMETER Priority
    Expected rule priority. Must match the -Priority used at deploy time (default 2).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-CopilotPromptFullBlockRule.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Copilot DLP - Sensitive Data Exposure Protection',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$SensitiveInformationTypeName = @('Canada physical addresses', 'EU debit card numbers'),

    [Parameter()]
    [ValidateRange(0, 10000)]
    [int]$Priority = 2
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
$ruleName = 'Copilot-Block-SensitivePrompts-FullResponse'

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

Write-Host "Validating rule '$ruleName' on policy '$PolicyName'..." -ForegroundColor Cyan

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Parent policy '$PolicyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - parent policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

# Filter by -Policy (rather than a bare -Identity lookup) so this check also confirms the rule
# actually belongs to the expected policy, not merely that a same-named rule exists somewhere.
$policyRules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$rule = $policyRules | Where-Object { $_.Name -eq $ruleName }
Test-Check -Description "Rule '$ruleName' exists on policy '$PolicyName'" -Condition ($null -ne $rule)
if (-not $rule) {
    Write-Host "`nCannot continue - rule not found on the expected policy. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description 'Rule is not Disabled' -Condition ($rule.Disabled -ne $true)

Test-Check -Description "Rule priority is $Priority (evaluated after the parent scenario's Rule 0/Rule 1)" `
    -Condition ($rule.Priority -eq $Priority) -Warn

foreach ($sitName in $SensitiveInformationTypeName) {
    $sitReferenced = ($rule.ContentContainsSensitiveInformation | Where-Object { $_.name -eq $sitName }).Count -gt 0
    Test-Check -Description "Rule includes SIT '$sitName'" -Condition $sitReferenced
}

Test-Check -Description 'Rule sets RestrictAccess ExcludeContentProcessing/Block (this repo''s best-grounded inference - VERIFY against a portal-created rule, see README.md Sec 5)' `
    -Condition (($rule.RestrictAccess | Where-Object { $_.setting -eq 'ExcludeContentProcessing' -and $_.value -eq 'Block' }).Count -gt 0) -Warn

Test-Check -Description 'Rule does not also set RestrictWebGrounding (would indicate the rule was accidentally deployed as a Rule-1-style web-grounding restriction instead of a full block)' `
    -Condition ($rule.RestrictWebGrounding -ne $true)

Test-Check -Description 'Rule generates an alert (not silent)' `
    -Condition ($null -ne $rule.GenerateAlert -and $rule.GenerateAlert.Count -gt 0)

Test-Check -Description 'Rule ReportSeverityLevel is High (this is the most severe of the three Copilot-location rules in this policy)' `
    -Condition ($rule.ReportSeverityLevel -eq 'High') -Warn

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
Write-Host 'Reminder: any [WARN] above on the RestrictAccess check means this repo''s scripted configuration has not been independently confirmed against a portal-created rule for this exact action - see README.md Sec 5 before production reliance.' -ForegroundColor Cyan

if ($script:failures -gt 0) { exit 1 }
```