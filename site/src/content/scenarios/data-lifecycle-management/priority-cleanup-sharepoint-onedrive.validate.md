---
part: "validate"
parent: "data-lifecycle-management/priority-cleanup-sharepoint-onedrive"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PriorityCleanupSharePointOneDrivePolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the SharePoint/OneDrive priority cleanup label, policy, and rule exist and are
    classified as priority cleanup objects, and reports the policy's current mode
    (simulation vs. enforced).

.DESCRIPTION
    Read-only - never modifies any object. Uses the official -PriorityCleanup filter switch on
    Get-ComplianceTag / Get-RetentionCompliancePolicy / Get-RetentionComplianceRule to confirm each
    object is classified as a priority cleanup object (rather than assuming an undocumented boolean
    property name on the returned object - Microsoft's reference does not publish one). Checks:
      1. The label exists in the -PriorityCleanup-filtered label list, with the expected
         RetentionAction.
      2. The policy exists in the -PriorityCleanup-filtered policy list, with the expected
         OneDriveLocation/SharePointLocation, and reports Enabled/Mode/DistributionStatus.
      3. The policy's rule exists in the -PriorityCleanup-filtered rule list and applies the
         expected label.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Unlike the Exchange sibling, a policy that reports Enabled=$false here is EXPECTED for most of
    this scenario's lifecycle - simulation is mandatory, so "In simulation" is the normal starting
    state, not a misconfiguration. This script prints the raw Mode value rather than treating
    Enabled=$false as a failure.

    This script CANNOT check pending-approval or disposed-item state - there is no documented
    PowerShell/Graph read API for the "Pending cleanups" queue. Use the portal (Data Lifecycle
    Management > Priority cleanup > Pending cleanups / Disposed items) or the auditing solution
    (search on the policy's Cleanup ID, or the PriorityCleanupTagApplied / PriorityCleanupFileRecycled
    operations) for that. See README.md Section 7/8.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention/priority
    cleanup configuration is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/priority-cleanup-sharepoint-onedrive.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-PriorityCleanupSharePointOneDrivePolicy.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/priority-cleanup-sharepoint-onedrive.sample.json')
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

Write-Host "Validating SharePoint/OneDrive priority cleanup ('$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Label - confirmed via the -PriorityCleanup filtered listing, not an assumed boolean property
$label = Get-ComplianceTag -PriorityCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cfg.label.name }
Test-Check -Description "Priority cleanup label '$($cfg.label.name)' exists (classified as priority cleanup)" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
    Test-Check -Description "  RetentionType is '$($cfg.label.retentionType)' (current: $($label.RetentionType))" `
        -Condition ("$($label.RetentionType)" -eq "$($cfg.label.retentionType)") -Warn
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
    Write-Host "    NOTE: Enabled=`$false / Mode 'In simulation' is the EXPECTED starting state for this workload - simulation is mandatory before enforcement, unlike the Exchange sibling scenario." -ForegroundColor DarkCyan
}

# Rule
$rule = Get-RetentionComplianceRule -PriorityCleanup -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Priority cleanup rule exists on the policy (classified as priority cleanup)" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "  Rule applies label '$($cfg.label.name)' (current: $($rule.ApplyComplianceTag))" `
        -Condition ("$($rule.ApplyComplianceTag)" -eq "$($cfg.label.name)")
}

Write-Host "`n  Note: this script cannot see pending-approval or disposed-item state (portal-only, no documented API)." -ForegroundColor Cyan
Write-Host "  Use auditing (search the policy's Cleanup ID; PriorityCleanupTagApplied / PriorityCleanupFileRecycled operations) to confirm actual Recycle Bin moves - see README.md Section 7." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```