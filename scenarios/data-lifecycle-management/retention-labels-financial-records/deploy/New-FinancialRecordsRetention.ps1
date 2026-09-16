#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a retention label for financial records (SEC 17a-4-style immutability) and an auto-apply
    retention label policy that stamps it onto finance content - using Security & Compliance
    PowerShell.

.DESCRIPTION
    Uses the Data Lifecycle Management / Records Management cmdlets in Security & Compliance
    PowerShell (automation surface 2 per docs/automation-surface.md):
      1. New-ComplianceTag             -> the retention label (Keep N days; record or regulatory record)
      2. New-RetentionCompliancePolicy -> the auto-apply label policy (locations)
      3. New-RetentionComplianceRule   -> the rule binding the label to the policy with a match query

    CORRECTED (see README.md Section 6/11 and reviews.md's correction addenda): the auto-apply rule
    call omits -Name. New-RetentionComplianceRule's -Name parameter is documented mutually exclusive
    with -ApplyComplianceTag ("You can't use this parameter with the ApplyComplianceTag or
    PublishComplianceTag parameters" - Microsoft Learn); the ComplianceTag parameter set -ApplyComplianceTag
    belongs to does not list -Name at all. The existing idempotency check (Get-RetentionComplianceRule
    -Policy) already locates the rule by policy, not by name, so nothing depends on an explicit name.

    CORRECTED (see README.md Section 2/11 and reviews.md's correction addendum): Microsoft's
    auto-apply retention label policies do NOT support labels that mark items as a REGULATORY
    RECORD - publishing is the only supported distribution mechanism for those. This script
    therefore creates the label regardless of the `regulatory` config flag (New-ComplianceTag
    -Regulatory $true is a valid, standalone call), but SKIPS auto-apply policy/rule creation with a
    clear warning when `label.regulatory` is true, instead of building an unsupported configuration.
    Hand off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to
    actually distribute a regulatory label. The sample config defaults to a plain RECORD label
    (`isRecordLabel: true`, `regulatory: false`), which auto-apply DOES support - see the
    `-Regulatory` note in .NOTES for the record vs. regulatory record distinction.

    Why PowerShell: a REGULATORY RECORD label (`-Regulatory $true`) can only be created in
    PowerShell (the portal hides the option by default), regardless of how it's later distributed.
    That makes label creation genuinely PowerShell-first even though this script's own auto-apply
    step only ever applies to non-regulatory labels.

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (labels/policies are not silently mutated - retention objects are high-consequence). Re-running is
    safe. -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its
    own -DryRun that prints the intended cmdlets and runs none.

    !!! IRREVERSIBLE !!! Once a record (or regulatory record) label is APPLIED to content, the label
    cannot be removed without records-manager privilege (record) or at all (regulatory record) -
    retention can't be shortened either way. TEST IN A LAB TENANT FIRST, review with -DryRun, and
    get Legal/Records sign-off before running for real. See README.md Sections 2/11.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/financial-records-retention.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FinancialRecordsRetention.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FinancialRecordsRetention.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag (retention label; -RetentionAction/-RetentionDuration/-RetentionType/
      -IsRecordLabel/-Regulatory): https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-RetentionCompliancePolicy / New-RetentionComplianceRule (-ApplyComplianceTag; -Name
      documented mutually exclusive with -ApplyComplianceTag/-PublishComplianceTag - the source of the
      -Name omission correction above):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Declare records / regulatory records:
      https://learn.microsoft.com/purview/records-management
      https://learn.microsoft.com/purview/declare-records
    - Automatically apply a retention label ("isn't supported for regulatory records... require a
      published retention label policy" - the source of this script's regulatory-record guard):
      https://learn.microsoft.com/purview/apply-retention-labels-automatically
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/financial-records-retention.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'label', 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Deploying financial-records retention: label '$($cfg.label.name)'$(if (-not $cfg.label.regulatory) { " + auto-apply policy '$($cfg.policy.name)'" })." -ForegroundColor Cyan
if ($cfg.label.regulatory) {
    Write-Host "WARNING: this creates a REGULATORY RECORD label - IRREVERSIBLE once applied (retention can't be shortened, label can't be removed). Test in a lab and get Legal/Records sign-off. See README.md Sections 2/11." -ForegroundColor Red
    Write-Host "NOTE: Microsoft does not support auto-apply for regulatory records - this run will create the label ONLY and SKIP the auto-apply policy/rule. Use scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to distribute it. See README.md Section 2." -ForegroundColor Yellow
}

# --- 1. Retention label (New-ComplianceTag) ---
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - retention labels are high-consequence; edit deliberately)." -ForegroundColor DarkGreen
}
else {
    $dur = if ("$($cfg.label.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.label.retentionDurationDays }
    $tagParams = @{
        Name            = $cfg.label.name
        RetentionAction = $cfg.label.retentionAction
        RetentionType   = $cfg.label.retentionType
        RetentionDuration = $dur
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }
    if ($cfg.label.regulatory) { $tagParams.Regulatory = $true }
    elseif ($cfg.label.isRecordLabel) { $tagParams.IsRecordLabel = $true }
    if ($cfg.label.reviewerEmail -and @($cfg.label.reviewerEmail).Count -gt 0) { $tagParams.ReviewerEmail = @($cfg.label.reviewerEmail) }

    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionDuration $dur -RetentionType $($cfg.label.retentionType)$(if ($cfg.label.regulatory) { ' -Regulatory $true' } elseif ($cfg.label.isRecordLabel) { ' -IsRecordLabel $true' })"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)'" -ForegroundColor Green
}

if ($cfg.label.regulatory) {
    Write-Host "`n[skip] Auto-apply policy/rule NOT created: Microsoft does not support auto-apply for regulatory records (see README.md Section 2/11)." -ForegroundColor Yellow
    Write-Host "       Next step: scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to publish '$($cfg.label.name)' for manual application." -ForegroundColor Yellow
    Write-Host "`nDone (label only)." -ForegroundColor Cyan
    return
}

# --- 2. Auto-apply label policy (New-RetentionCompliancePolicy) ---
$existingPolicy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    $polParams = @{ Name = $cfg.policy.name }
    if ($null -ne $cfg.policy.enabled) { $polParams.Enabled = [bool]$cfg.policy.enabled }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }
    if ($cfg.policy.sharePointLocation -and @($cfg.policy.sharePointLocation).Count -gt 0) { $polParams.SharePointLocation = @($cfg.policy.sharePointLocation) }
    if ($cfg.policy.exchangeLocation -and @($cfg.policy.exchangeLocation).Count -gt 0) { $polParams.ExchangeLocation = @($cfg.policy.exchangeLocation) }
    if ($cfg.policy.oneDriveLocation -and @($cfg.policy.oneDriveLocation).Count -gt 0) { $polParams.OneDriveLocation = @($cfg.policy.oneDriveLocation) }
    if (-not ($polParams.SharePointLocation -or $polParams.ExchangeLocation -or $polParams.OneDriveLocation)) {
        throw "policy needs at least one location (sharePointLocation / exchangeLocation / oneDriveLocation)."
    }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' (auto-apply label policy, locations set)" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 3. Auto-apply rule (New-RetentionComplianceRule -ApplyComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    # -Name is documented mutually exclusive with -ApplyComplianceTag (ComplianceTag parameter set) -
    # see .NOTES and README.md Section 6/11. Omitted here; the existing idempotency check above
    # locates the rule by -Policy, not by name.
    $ruleParams = @{
        Policy            = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
    }
    if (-not [string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { $ruleParams.ContentMatchQuery = $cfg.rule.contentMatchQuery }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)' -ContentMatchQuery <query>" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (auto-apply '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Auto-apply can take up to 7 days to take effect. Validate with validate/Test-FinancialRecordsRetention.ps1 and confirm labeling in the portal (Records Management / Data Lifecycle Management)." -ForegroundColor Yellow
