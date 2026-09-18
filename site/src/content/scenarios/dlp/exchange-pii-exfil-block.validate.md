---
part: "validate"
parent: "dlp/exchange-pii-exfil-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ExchangePiiDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "PII DLP - Exchange External Send Control" DLP policy is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The policy exists and is scoped to ExchangeLocation.
      2. Rule PII-Exchange-Protect-External exists with the expected recipient scope and action
         (BlockAccess for -Action Block, EncryptRMSTemplate for -Action Encrypt).
      3. Rule PII-Exchange-Audit-Internal exists, scoped to internal recipients, and does not
         block access.
      4. If -ExceptionGroupEmail is supplied and -Action is Block, rule
         PII-Exchange-Override-External exists, is scoped to that group, and allows justified
         override; the protect rule excludes the same group.
      5. The policy Mode matches what was requested (warns, does not fail, if still in a Test*
         mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER Action
    Expected action mode ('Block' or 'Encrypt'). Must match the -Action used at deploy time.

.PARAMETER ExceptionGroupEmail
    Expected SMTP address of the business-exception group, if one was configured at deploy time.
    Omit if the scenario was deployed without an exception group.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-ExchangePiiDlpPolicy.ps1 -Action Block -ExceptionGroupEmail 'hr-benefits-ops@contoso.com'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter()]
    [ValidateSet('Block', 'Encrypt')]
    [string]$Action = 'Block',

    [Parameter()]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ExceptionGroupEmail
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

Test-Check -Description 'Policy is scoped to Exchange locations' `
    -Condition ($policy.ExchangeLocation -and $policy.ExchangeLocation.Count -gt 0)

Test-Check -Description "Policy Mode is enforcing (Enable), not still in simulation" `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleOverride = $rules | Where-Object { $_.Name -eq 'PII-Exchange-Override-External' }
$ruleProtect = $rules | Where-Object { $_.Name -eq 'PII-Exchange-Protect-External' }
$ruleAudit = $rules | Where-Object { $_.Name -eq 'PII-Exchange-Audit-Internal' }

Test-Check -Description 'Rule PII-Exchange-Protect-External exists' -Condition ($null -ne $ruleProtect)
Test-Check -Description 'Rule PII-Exchange-Audit-Internal exists' -Condition ($null -ne $ruleAudit)

if ($ruleProtect) {
    Test-Check -Description 'Protect rule scopes to external recipients (AccessScope = NotInOrganization)' `
        -Condition ($ruleProtect.AccessScope -eq 'NotInOrganization')

    if ($Action -eq 'Block') {
        Test-Check -Description 'Protect rule blocks access (BlockAccess = true)' `
            -Condition ($ruleProtect.BlockAccess -eq $true)
        Test-Check -Description 'Protect rule does not also carry an RMS template (Action=Block)' `
            -Condition (-not $ruleProtect.EncryptRMSTemplate) -Warn
    }
    else {
        Test-Check -Description 'Protect rule applies an RMS template (EncryptRMSTemplate set)' `
            -Condition ($null -ne $ruleProtect.EncryptRMSTemplate)
        Test-Check -Description 'Protect rule does not also hard-block (Action=Encrypt is non-halting)' `
            -Condition ($ruleProtect.BlockAccess -ne $true)
    }

    if ($ExceptionGroupEmail) {
        Test-Check -Description 'Protect rule excludes the business-exception group' `
            -Condition ($ruleProtect.ExceptIfFromMemberOf -contains $ExceptionGroupEmail)
    }
}

if ($ruleAudit) {
    Test-Check -Description 'Audit rule scopes to internal recipients (AccessScope = InOrganization)' `
        -Condition ($ruleAudit.AccessScope -eq 'InOrganization')
    Test-Check -Description 'Internal-audit rule does not block access' `
        -Condition ($ruleAudit.BlockAccess -ne $true)
    Test-Check -Description 'Internal-audit rule still generates an alert for visibility' `
        -Condition ($null -ne $ruleAudit.GenerateAlert -and $ruleAudit.GenerateAlert.Count -gt 0)
}

if ($Action -eq 'Block' -and $ExceptionGroupEmail) {
    Test-Check -Description 'Rule PII-Exchange-Override-External exists' -Condition ($null -ne $ruleOverride)
    if ($ruleOverride) {
        Test-Check -Description 'Override rule is scoped to the business-exception group' `
            -Condition ($ruleOverride.FromMemberOf -contains $ExceptionGroupEmail)
        Test-Check -Description 'Override rule blocks by default (BlockAccess = true)' `
            -Condition ($ruleOverride.BlockAccess -eq $true)
        Test-Check -Description 'Override rule allows justified override' `
            -Condition ($ruleOverride.NotifyAllowOverride -contains 'WithJustification')
        Test-Check -Description 'Override rule has priority 0 (evaluated first)' `
            -Condition ($ruleOverride.Priority -eq 0)
    }
}
else {
    Test-Check -Description 'No stale override rule present (Action=Encrypt or no exception group configured)' `
        -Condition ($null -eq $ruleOverride) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```