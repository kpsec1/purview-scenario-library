---
part: "validate"
parent: "dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ExchangePiiElevatedRiskBlock.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Verifies the PII-Exchange-ElevatedRisk-Block-AllExternal rule is deployed correctly on the
    parent Exchange PII DLP policy, and prints a manual checklist for the portal-only
    prerequisites this script cannot check via API.

.DESCRIPTION
    Read-only validation script - never modifies policy or rule state. Automated checks:
      1. The parent policy exists.
      2. The new rule exists, at priority 0, with the correct SharedByIRMUserRisk (Elevated-only)
         GUID, AccessScope, BlockAccess, and no override configured.
      3. Every other rule on the policy has a unique, contiguous priority starting at 1 (the
         compaction New-ExchangePiiElevatedRiskBlock.ps1 performs - see design.md §6). This check
         is deliberately name-agnostic: it does not assume exactly three rules exist, since the
         parent scenario's own -ExceptionGroupEmail rule and the separate Encrypt-mode audit
         companion rule are both optional.
      4. Each other rule still has a content/sensitive-information-type condition (i.e., this
         fragment's deploy script did not accidentally strip one while compacting priorities).
    Exits with a non-zero code if any hard check fails. Safe to re-run any number of times.

    Then prints a manual checklist for everything this script has no API to query: whether the
    Exchange DLP-alerts indicator is enabled and pointed at the parent policy, whether the feeder
    Insider Risk Management policy exists with the right triggering event and cumulative
    exfiltration detection enabled, and whether that policy is in Adaptive Protection's scope. A
    rule that passes every automated check below can still never fire if any of those portal-only
    prerequisites aren't met - see README.md §7 for the end-to-end pilot workflow.

.PARAMETER PolicyName
    Name of the parent DLP policy to validate. Must match the -PolicyName used at deploy time.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-ExchangePiiElevatedRiskBlock.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

$riskLevelElevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'
$newRuleName = 'PII-Exchange-ElevatedRisk-Block-AllExternal'

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
    Test-Check -Description 'New rule has priority 0 (evaluated before every other rule)' `
        -Condition ($newRule.Priority -eq 0)
    Test-Check -Description 'New rule is scoped only to the Elevated risk-level GUID' `
        -Condition ($newRule.SharedByIRMUserRisk -contains $riskLevelElevated -and $newRule.SharedByIRMUserRisk.Count -eq 1)
    Test-Check -Description 'New rule is scoped to external recipients only (AccessScope = NotInOrganization)' `
        -Condition ($newRule.AccessScope -eq 'NotInOrganization')
    Test-Check -Description 'New rule blocks access (BlockAccess = true)' `
        -Condition ($newRule.BlockAccess -eq $true)
    Test-Check -Description 'New rule has no content/sensitive-information-type condition (fires on any content)' `
        -Condition (-not $newRule.ContentContainsSensitiveInformation -or $newRule.ContentContainsSensitiveInformation.Count -eq 0)
    Test-Check -Description 'New rule does not allow a user override (Elevated risk cannot self-override)' `
        -Condition (-not $newRule.NotifyAllowOverride -or $newRule.NotifyAllowOverride.Count -eq 0)
    Test-Check -Description 'New rule generates an alert for visibility' `
        -Condition ($null -ne $newRule.GenerateAlert -and $newRule.GenerateAlert.Count -gt 0)
    Test-Check -Description 'New rule is marked High severity' `
        -Condition ($newRule.ReportSeverityLevel -eq 'High')
}

# --- Name-agnostic compaction check (design.md §6): every OTHER rule must occupy a unique,
#     contiguous priority starting at 1 - regardless of how many such rules exist or what they're
#     named (the parent scenario's own optional override rule, and the separate Encrypt-mode audit
#     companion rule, are both allowed to be present or absent). -->
$otherRules = @(Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $newRuleName })
Test-Check -Description 'At least one other rule exists on the policy besides the new rule' `
    -Condition ($otherRules.Count -gt 0)

if ($otherRules.Count -gt 0) {
    $sortedPriorities = $otherRules | Select-Object -ExpandProperty Priority | Sort-Object
    $expectedPriorities = 1..($otherRules.Count)
    $prioritiesMatch = @(Compare-Object -ReferenceObject $expectedPriorities -DifferenceObject $sortedPriorities -SyncWindow 0).Count -eq 0
    Test-Check -Description "All $($otherRules.Count) other rule(s) occupy unique, contiguous priorities starting at 1 (found: $($sortedPriorities -join ', '))" `
        -Condition $prioritiesMatch

    foreach ($rule in $otherRules) {
        Test-Check -Description "Rule '$($rule.Name)' (priority $($rule.Priority)) still has its own content/sensitive-information-type condition (unmodified by this fragment's compaction)" `
            -Condition ($rule.ContentContainsSensitiveInformation -and $rule.ContentContainsSensitiveInformation.Count -gt 0) `
            -Warn
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

Write-Host "`n--- Manual checklist (no API surface exists to check these) ---" -ForegroundColor Cyan
Write-Host '  [ ] The Exchange DLP-alerts indicator is enabled in Insider Risk Management global settings, pointed at policy "PII DLP - Exchange External Send Control", with "Generating alerts from selected DLP policies" checked and saved (Purview portal > Insider Risk Management > Settings > Policy indicators > Built-in Indicators > Data loss prevention (DLP) indicators).'
Write-Host '  [ ] The feeder Insider Risk Management policy (deploy/policy/irm-exchange-drip-exfiltration-config-manifest.json) exists, uses the "User matches a data loss prevention (DLP) policy" triggering event pointed at the same DLP policy, and has Cumulative exfiltration detection turned on.'
Write-Host '  [ ] The feeder policy is included in Adaptive Protection scope (Purview portal > Insider Risk Management > Adaptive protection > Insider risk levels).'
Write-Host '  [ ] Adaptive Protection itself is turned ON (prerequisite already established in scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/README.md Section 5).'
Write-Host '  [ ] Purview portal > Insider Risk Management > Adaptive protection > Data Loss Prevention tab lists policy "PII DLP - Exchange External Send Control" - confirms the portal recognizes this rule''s SharedByIRMUserRisk condition as an Adaptive Protection binding.'
Write-Host '  [ ] At least 36 hours have passed since Adaptive Protection was enabled before concluding a pilot did not work (see README.md Section 11).'
Write-Host '  [ ] Understood and communicated to the buyer: this control does not detect or block a single, perfectly-executed split-SSN/PAN message - it only shortens the exposure window after a qualifying behavioral signal (README.md Section 11, design.md Section 1).'

if ($script:failures -gt 0) { exit 1 }
```