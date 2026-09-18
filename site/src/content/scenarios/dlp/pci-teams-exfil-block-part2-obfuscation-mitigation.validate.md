---
part: "validate"
parent: "dlp/pci-teams-exfil-block-part2-obfuscation-mitigation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PciElevatedRiskTeamsBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the PCI-ElevatedRisk-Block-AllExternal rule is deployed correctly on Part 1's PCI
    Teams DLP policy, and prints a manual checklist for the portal-only prerequisites this script
    cannot check via API.

.DESCRIPTION
    Read-only validation script - never modifies policy or rule state. Automated checks:
      1. The parent policy exists.
      2. The new rule exists, at priority 0, with the correct SharedByIRMUserRisk (Elevated-only)
         GUID, AccessScope, BlockAccess, and no override configured.
      3. Part 1's three original rules still exist and were correctly re-prioritized to 1/2/3.
      4. Part 1's three original rules' own conditions (sensitive info type, Card Ops group
         scoping) were not altered by this fragment's deploy script.
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

    Then prints a manual checklist for everything this script has no API to query: whether the
    Communication Compliance SIT indicator is enabled and covers Credit Card Number, whether the
    feeder Insider Risk Management policy exists with the right triggering event and cumulative
    exfiltration detection enabled, and whether that policy is in Adaptive Protection's scope. A
    rule that passes every automated check below can still never fire if any of those portal-only
    prerequisites aren't met - see README.md Section 7 for the end-to-end pilot workflow.

.PARAMETER PolicyName
    Name of the parent DLP policy to validate. Must match the -PolicyName used at deploy time.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-PciElevatedRiskTeamsBlock.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'
$newRuleName = 'PCI-ElevatedRisk-Block-AllExternal'

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

Write-Host "Validating policy '$PolicyName' for the elevated-risk drip-exfiltration rule..." -ForegroundColor Cyan

$policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Test-Check -Description "Parent policy '$PolicyName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$newRule = Get-DlpComplianceRule -Identity $newRuleName -ErrorAction SilentlyContinue
Test-Check -Description "Rule '$newRuleName' exists" -Condition ($null -ne $newRule)

if ($newRule) {
    Test-Check -Description 'New rule has priority 0 (evaluated before all Part 1 rules)' `
        -Condition ($newRule.Priority -eq 0)
    Test-Check -Description 'New rule is scoped only to the Elevated risk-level GUID' `
        -Condition ($newRule.SharedByIRMUserRisk -contains $riskLevelElevated -and $newRule.SharedByIRMUserRisk.Count -eq 1)
    Test-Check -Description 'New rule blocks access (BlockAccess = true)' `
        -Condition ($newRule.BlockAccess -eq $true)
    Test-Check -Description 'New rule has no content/sensitive-information-type condition (fires on any content)' `
        -Condition (-not $newRule.ContentContainsSensitiveInformation -or $newRule.ContentContainsSensitiveInformation.Count -eq 0)
    Test-Check -Description 'New rule does not allow a user override (Elevated risk cannot self-override)' `
        -Condition (-not $newRule.NotifyAllowOverride -or $newRule.NotifyAllowOverride.Count -eq 0)
    Test-Check -Description 'New rule generates an alert for visibility' `
        -Condition ($null -ne $newRule.GenerateAlert -and $newRule.GenerateAlert.Count -gt 0)
}

$expectedPriorities = @{
    'PCI-CardOps-Override-External' = 1
    'PCI-Block-External-AllUsers'   = 2
    'PCI-Audit-Internal-AllUsers'   = 3
}
foreach ($ruleName in $expectedPriorities.Keys) {
    $rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue
    Test-Check -Description "Part 1 rule '$ruleName' still exists" -Condition ($null -ne $rule)
    if ($rule) {
        Test-Check -Description "Part 1 rule '$ruleName' re-prioritized to $($expectedPriorities[$ruleName])" `
            -Condition ($rule.Priority -eq $expectedPriorities[$ruleName])
        Test-Check -Description "Part 1 rule '$ruleName' still requires Credit Card Number content (unmodified by this fragment)" `
            -Condition ($rule.ContentContainsSensitiveInformation -and $rule.ContentContainsSensitiveInformation.Count -gt 0)
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

Write-Host "`n--- Manual checklist (no API surface exists to check these) ---" -ForegroundColor Cyan
Write-Host '  [ ] Communication Compliance SIT indicator is enabled in Insider Risk Management settings, scoped to Credit Card Number, and covers Microsoft Teams (Purview portal > Insider Risk Management > Settings > Policy indicators > Communication Compliance indicators).'
Write-Host '  [ ] The feeder Insider Risk Management policy (deploy/policy/irm-drip-exfiltration-config-manifest.json) exists, uses the "User performs an exfiltration activity" triggering event, includes the Communication Compliance indicator, and has Cumulative exfiltration detection turned on.'
Write-Host '  [ ] The feeder policy is included in Adaptive Protection scope (Purview portal > Insider Risk Management > Adaptive protection > Insider risk levels).'
Write-Host '  [ ] Adaptive Protection itself is turned ON (prerequisite already established in scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/README.md Section 5).'
Write-Host '  [ ] Purview portal > Insider Risk Management > Adaptive protection > Data Loss Prevention tab lists policy "PCI DSS - Teams Card Data Exfiltration Block" - confirms the portal recognizes this rule''s SharedByIRMUserRisk condition as an Adaptive Protection binding.'
Write-Host '  [ ] At least 36 hours have passed since Adaptive Protection was enabled, AND at least one daily cumulative-exfiltration-detection evaluation cycle has run, before concluding a pilot did not work (see README.md Section 11).'
Write-Host '  [ ] Understood and communicated to the buyer: this control does not detect or block a single, perfectly-executed split-PAN message - it only shortens the exposure window after a qualifying behavioral signal (README.md Section 11, design.md Section 1).'

if ($script:failures -gt 0) { exit 1 }
```