---
part: "validate"
parent: "dlp/pci-teams-exfil-block"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PciTeamsDlpPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the "PCI DSS - Teams Card Data Exfiltration Block" DLP policy is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The policy exists and is scoped to TeamsLocation.
      2. All three rules exist with the expected priority order.
      3. Rule 0 (Card Ops override) is scoped to the correct group and allows justified override.
      4. Rule 1 (hard block) excludes the Card Ops group and does not allow override.
      5. Rule 2 (internal audit) does not block access.
      6. The policy Mode matches what was requested (warns, does not fail, if still in a Test* mode).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER PolicyName
    Name of the DLP policy to validate. Must match the -PolicyName used at deploy time.

.PARAMETER CardOpsGroupEmail
    Expected SMTP address of the Card Operations group, to confirm rule scoping matches intent.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-PciTeamsDlpPolicy.ps1 -CardOpsGroupEmail 'card-ops@contoso.com'
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$CardOpsGroupEmail
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

Test-Check -Description 'Policy is scoped to Teams locations' `
    -Condition ($policy.TeamsLocation -and $policy.TeamsLocation.Count -gt 0)

Test-Check -Description "Policy Mode is enforcing (Enable), not still in simulation" `
    -Condition ($policy.Mode -eq 'Enable') -Warn

$rules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue
$ruleOverride = $rules | Where-Object { $_.Name -eq 'PCI-CardOps-Override-External' }
$ruleBlock = $rules | Where-Object { $_.Name -eq 'PCI-Block-External-AllUsers' }
$ruleAudit = $rules | Where-Object { $_.Name -eq 'PCI-Audit-Internal-AllUsers' }

Test-Check -Description 'Rule PCI-CardOps-Override-External exists' -Condition ($null -ne $ruleOverride)
Test-Check -Description 'Rule PCI-Block-External-AllUsers exists' -Condition ($null -ne $ruleBlock)
Test-Check -Description 'Rule PCI-Audit-Internal-AllUsers exists' -Condition ($null -ne $ruleAudit)

if ($ruleOverride) {
    Test-Check -Description 'Override rule is scoped to Card Ops group' `
        -Condition ($ruleOverride.FromMemberOf -contains $CardOpsGroupEmail)
    Test-Check -Description 'Override rule blocks by default (BlockAccess = true)' `
        -Condition ($ruleOverride.BlockAccess -eq $true)
    Test-Check -Description 'Override rule allows justified override' `
        -Condition ($ruleOverride.NotifyAllowOverride -contains 'WithJustification')
    Test-Check -Description 'Override rule has priority 0 (evaluated first)' `
        -Condition ($ruleOverride.Priority -eq 0)
}

if ($ruleBlock) {
    Test-Check -Description 'Hard-block rule excludes the Card Ops group' `
        -Condition ($ruleBlock.ExceptIfFromMemberOf -contains $CardOpsGroupEmail)
    Test-Check -Description 'Hard-block rule blocks with no override configured' `
        -Condition ($ruleBlock.BlockAccess -eq $true -and (-not $ruleBlock.NotifyAllowOverride -or $ruleBlock.NotifyAllowOverride.Count -eq 0))
}

if ($ruleAudit) {
    Test-Check -Description 'Internal-audit rule does not block access' `
        -Condition ($ruleAudit.BlockAccess -ne $true)
    Test-Check -Description 'Internal-audit rule still generates an alert for visibility' `
        -Condition ($null -ne $ruleAudit.GenerateAlert -and $ruleAudit.GenerateAlert.Count -gt 0)
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```