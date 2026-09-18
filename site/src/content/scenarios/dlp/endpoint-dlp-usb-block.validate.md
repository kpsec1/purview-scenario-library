---
part: "validate"
parent: "dlp/endpoint-dlp-usb-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EndpointDlpUsbBlockPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "Endpoint DLP - Block USB Removable Media Exfiltration" DLP policy is deployed
    correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The policy exists and is scoped to EndpointDlpLocation (Devices).
      2. Both rules exist with the expected priority order.
      3. Rule 0 (all-users block) excludes the IT Data Custodians group and blocks removable media.
      4. Rule 1 (IT Data Custodians) is scoped to the group and audits (does not block).
      5. The policy Mode matches enforcement expectations (warns, does not fail, if still in a
         Test* mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Note: this script validates the DLP policy *configuration* only. It does not and cannot
    confirm per-device *policy sync status* (Settings > Device onboarding > Devices) - a
    correctly configured policy can still be unenforced on a specific endpoint that hasn't
    synced yet. See README.md §7 for the functional (on-device) test steps this script cannot
    replace.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER ITCustodiansGroupEmail
    Expected SMTP address of the IT Data Custodians group, to confirm rule scoping matches intent.

.PARAMETER ExpectedITExceptionAction
    The -ITExceptionAction value the policy was deployed with ('Audit' or 'Warn' - see
    deploy/New-EndpointDlpUsbBlockPolicy.ps1). Defaults to 'Audit'. Both are officially documented
    -EndpointDlpRestrictions -Value strings (Microsoft Learn: New-DlpComplianceRule /
    Set-DlpComplianceRule).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'Endpoint DLP - Block USB Removable Media Exfiltration',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ITCustodiansGroupEmail,

    [Parameter()]
    [ValidateSet('Audit', 'Warn')]
    [string]$ExpectedITExceptionAction = 'Audit'
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

Test-Check -Description 'Policy is scoped to Endpoint DLP (Devices) locations' `
    -Condition ($policy.EndpointDlpLocation -and $policy.EndpointDlpLocation.Count -gt 0)

Test-Check -Description 'Policy Mode is enforcing (Enable), not still in simulation' `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleBlock = $rules | Where-Object { $_.Name -eq 'USB-Block-Sensitive-AllUsers' }
$ruleAudit = $rules | Where-Object { $_.Name -eq 'USB-Audit-ITDataCustodians' }

Test-Check -Description 'Rule USB-Block-Sensitive-AllUsers exists' -Condition ($null -ne $ruleBlock)
Test-Check -Description 'Rule USB-Audit-ITDataCustodians exists' -Condition ($null -ne $ruleAudit)

if ($ruleBlock) {
    Test-Check -Description 'Block rule excludes the IT Data Custodians group' `
        -Condition ($ruleBlock.ExceptIfFromMemberOf -contains $ITCustodiansGroupEmail)
    Test-Check -Description 'Block rule has priority 0 (evaluated first)' `
        -Condition ($ruleBlock.Priority -eq 0)
    Test-Check -Description 'Block rule restricts removable-media copy activity' `
        -Condition ($ruleBlock.EndpointDlpRestrictions -and ($ruleBlock.EndpointDlpRestrictions | Out-String) -match 'RemovableMedia')
    Test-Check -Description 'Block rule restriction value is Block, not Audit' `
        -Condition (($ruleBlock.EndpointDlpRestrictions | Out-String) -match 'Block')
}

if ($ruleAudit) {
    Test-Check -Description 'Audit rule is scoped to the IT Data Custodians group' `
        -Condition ($ruleAudit.FromMemberOf -contains $ITCustodiansGroupEmail)
    Test-Check -Description 'Audit rule restricts removable-media copy activity' `
        -Condition ($ruleAudit.EndpointDlpRestrictions -and ($ruleAudit.EndpointDlpRestrictions | Out-String) -match 'RemovableMedia')
    Test-Check -Description "Audit rule restriction value matches -ExpectedITExceptionAction ('$ExpectedITExceptionAction'), not Block" `
        -Condition (($ruleAudit.EndpointDlpRestrictions | Out-String) -match $ExpectedITExceptionAction -and ($ruleAudit.EndpointDlpRestrictions | Out-String) -notmatch 'Block')
    Test-Check -Description 'Audit rule still generates an alert for visibility' `
        -Condition ($null -ne $ruleAudit.GenerateAlert -and $ruleAudit.GenerateAlert.Count -gt 0)
    if ($ExpectedITExceptionAction -eq 'Warn') {
        Test-Check -Description 'Warn action has -NotifyUser configured (Microsoft Learn: Block/Warn require NotifyUser)' `
            -Condition ($null -ne $ruleAudit.NotifyUser -and $ruleAudit.NotifyUser.Count -gt 0)
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```