---
part: "validate"
parent: "data-lifecycle-management/priority-cleanup-permanent-deletion"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PriorityCleanupPermanentDeletionPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the shared priority-cleanup label, policy, and rule exist and are classified as
    priority cleanup objects. CANNOT confirm the policy is actually configured for permanent
    deletion (vs. the default Recycle-Bin outcome) - no PowerShell/Graph property is confirmed to
    expose that state. Use audit search (this script's guidance below) for post-hoc confirmation.

.DESCRIPTION
    Read-only - never modifies any object. Uses the official -PriorityCleanup filter switch on
    Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule, identical
    mechanism to the priority-cleanup-sharepoint-onedrive sibling's validate script. Checks:
      1. The label exists in the -PriorityCleanup-filtered label list, with the expected
         RetentionAction.
      2. The policy exists in the -PriorityCleanup-filtered policy list, with the expected
         OneDriveLocation/SharePointLocation, and reports Enabled/Mode/DistributionStatus.
      3. The policy's rule exists in the -PriorityCleanup-filtered rule list and applies the
         expected label.

    WHAT THIS SCRIPT CANNOT CHECK: whether the portal-only "Delete data permanently" selection has
    been made on this policy. No documented Get-RetentionCompliancePolicy/Get-ComplianceTag property
    is confirmed to expose content-disposition mode (README.md Section 11, design.md Section 4) -
    this is a genuine platform read-back gap, not an oversight of this script. The only reliable,
    scriptable confirmation that permanent deletion actually occurred is post-hoc: search the audit
    log for the 'PriorityCleanupFileDeleted' operation under this policy's Cleanup ID. A
    'PriorityCleanupFileRecycled' event instead means the item went to the second-stage Recycle
    Bin - i.e. the portal step was NOT completed (or the underlying object was misconfigured), not a
    permanent deletion. This script cannot query the audit log itself (a separate
    Search-UnifiedAuditLog permission/session scope); see README.md Section 7 for the exact query.

    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention/priority
    cleanup configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/priority-cleanup-permanent-deletion.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-PriorityCleanupPermanentDeletionPolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/priority-cleanup-permanent-deletion.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating priority cleanup permanent-deletion base objects ('$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Label
$label = Get-ComplianceTag -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.label.name }
Test-Check -Description "Priority cleanup label '$($cfg.label.name)' exists (classified as priority cleanup)" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
}

# Policy
$policy = Get-RetentionCompliancePolicy -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.policy.name }
Test-Check -Description "Priority cleanup policy '$($cfg.policy.name)' exists (classified as priority cleanup)" -Condition ($null -ne $policy)
if ($policy) {
    $expectedOneDrive = @($cfg.policy.oneDriveLocation)
    $actualOneDrive = @($policy.OneDriveLocation)
    $oneDriveOk = ($expectedOneDrive.Count -eq 0) -or (-not ($expectedOneDrive | Where-Object { $_ -notin $actualOneDrive -and $actualOneDrive -notcontains 'All' }))
    Test-Check -Description "  OneDriveLocation covers the expected location(s)" -Condition $oneDriveOk -Warn

    $expectedSharePoint = @($cfg.policy.sharePointLocation)
    $actualSharePoint = @($policy.SharePointLocation)
    $sharePointOk = ($expectedSharePoint.Count -eq 0) -or (-not ($expectedSharePoint | Where-Object { $_ -notin $actualSharePoint -and $actualSharePoint -notcontains 'All' }))
    Test-Check -Description "  SharePointLocation covers the expected site(s)" -Condition $sharePointOk -Warn

    Write-Host "    Enabled: $($policy.Enabled) | Mode: $($policy.Mode) | DistributionStatus: $($policy.DistributionStatus)" -ForegroundColor Cyan
    Write-Host "    NOTE: Enabled=`$false / Mode 'In simulation' is the EXPECTED starting state - simulation is mandatory before enforcement." -ForegroundColor DarkCyan
}

# Rule
$rule = Get-RetentionComplianceRule -PriorityCleanup -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Priority cleanup rule exists on the policy (classified as priority cleanup)" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "  Rule applies label '$($cfg.label.name)' (current: $($rule.ApplyComplianceTag))" `
        -Condition ("$($rule.ApplyComplianceTag)" -eq "$($cfg.label.name)")
}

Write-Host "`n  *** This script CANNOT confirm permanent-deletion mode is active - no documented read-back property exists. ***" -ForegroundColor Red
Write-Host "  Confirm the portal-only 'Delete data permanently' selection manually (Data Lifecycle Management > Priority cleanup > open policy)." -ForegroundColor Yellow
Write-Host "  For post-hoc, scriptable confirmation, search the audit log (policy's Cleanup ID as keyword) for:" -ForegroundColor Cyan
Write-Host "    - 'PriorityCleanupFileDeleted'  => permanent deletion occurred (this scenario's intended outcome)" -ForegroundColor Cyan
Write-Host "    - 'PriorityCleanupFileRecycled' => item moved to the Recycle Bin instead - the manual step was likely NOT completed" -ForegroundColor Cyan
Write-Host "  See README.md Section 7." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed (base objects only - see note above).' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```