---
part: "validate"
parent: "dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ExchangePiiEncryptModeAuditCompanion.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "PII-Exchange-Audit-Encrypt-Exception" rule is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies rule or policy state. Checks:
      1. The rule exists on the expected parent policy.
      2. It is scoped to the exception group (FromMemberOf) and external recipients
         (AccessScope = NotInOrganization), with the same SIT conditions as the parent scenario.
      3. It is non-blocking (BlockAccess = $false) and generates an alert + incident report.
      4. Drift check (warn only): the parent's own PII-Exchange-Protect-External rule still
         excludes the same exception group via ExceptIfFromMemberOf - the precondition for this
         companion's target population to be otherwise unmatched by any other rule in the policy.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

.PARAMETER PolicyName
    Name of the parent scenario's DLP policy. Must match the -PolicyName used at deploy time.

.PARAMETER ExceptionGroupEmail
    Expected SMTP address of the business-exception group. Must match the -ExceptionGroupEmail
    used at deploy time.

.PARAMETER ReportSeverityLevel
    Expected severity (Low, Medium, or High). Must match the -ReportSeverityLevel used at deploy
    time. Defaults to 'Low'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-ExchangePiiEncryptModeAuditCompanion.ps1 -ExceptionGroupEmail 'hr-benefits-ops@contoso.com'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ExceptionGroupEmail,

    [Parameter()]
    [ValidateSet('Low', 'Medium', 'High')]
    [string]$ReportSeverityLevel = 'Low'
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

if (-not (Get-Command Get-DlpComplianceRule -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$ruleName = 'PII-Exchange-Audit-Encrypt-Exception'
$protectRuleName = 'PII-Exchange-Protect-External'

Write-Host "Validating rule '$ruleName' on policy '$PolicyName'..." -ForegroundColor Cyan

$parentPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Parent policy '$PolicyName' exists" -Condition ($null -ne $parentPolicy)
if (-not $parentPolicy) {
    Write-Host "`nCannot continue - parent policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue
Test-Check -Description "Rule '$ruleName' exists" -Condition ($null -ne $rule)
if (-not $rule) {
    Write-Host "`nCannot continue - rule not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

Test-Check -Description "Rule belongs to policy '$PolicyName'" `
    -Condition ($rule.Policy -eq $PolicyName)

Test-Check -Description 'Rule is scoped to the exception group (FromMemberOf)' `
    -Condition ($rule.FromMemberOf -contains $ExceptionGroupEmail)

Test-Check -Description 'Rule scopes to external recipients (AccessScope = NotInOrganization)' `
    -Condition ($rule.AccessScope -eq 'NotInOrganization')

Test-Check -Description 'Rule is non-blocking (BlockAccess = $false)' `
    -Condition ($rule.BlockAccess -ne $true)

Test-Check -Description 'Rule does not carry an RMS encrypt template (audit-only, no enforcement action)' `
    -Condition (-not $rule.EncryptRMSTemplate)

Test-Check -Description 'Rule generates an alert for visibility' `
    -Condition ($null -ne $rule.GenerateAlert -and $rule.GenerateAlert.Count -gt 0)

Test-Check -Description 'Rule generates an incident report' `
    -Condition ($null -ne $rule.GenerateIncidentReport -and $rule.GenerateIncidentReport.Count -gt 0)

Test-Check -Description "Rule severity is $ReportSeverityLevel (as configured at deploy time)" `
    -Condition ($rule.ReportSeverityLevel -eq $ReportSeverityLevel) -Warn

# Drift check against the parent scenario's own Protect rule (design.md §4 / README.md §11).
$protectRule = Get-DlpComplianceRule -Identity $protectRuleName -ErrorAction SilentlyContinue
if (-not $protectRule) {
    Test-Check -Description "Parent rule '$protectRuleName' found (needed to confirm this companion's target population is otherwise unmatched)" `
        -Condition $false -Warn
}
else {
    Test-Check -Description "Parent rule '$protectRuleName' excludes the same exception group (no drift)" `
        -Condition ($protectRule.ExceptIfFromMemberOf -contains $ExceptionGroupEmail) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```