---
part: "validate"
parent: "data-lifecycle-management/adaptive-protection-deleted-content-preservation"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AdaptiveProtectionDlmPreservation.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Checks whether Adaptive Protection's Data Lifecycle Management deleted-content preservation
    control has visibly fired within a lookback window, and reports the result as evidence found /
    not found -- never as a definitive enabled/disabled status.

.DESCRIPTION
    Read-only. No Get-/New-/Set- cmdlet exists for the underlying opt-in toggle or its
    auto-created retention label/policy (design.md Section 2, item 1) -- there is nothing this
    script can query to directly answer "is the control on." What it CAN check is whether the
    two audit friendly names Microsoft documents for this control -- Retained file proactively
    (SharePointDataProactivelyPreserved) and Retained email item proactively
    (ExchangeDataProactivelyPreserved) -- appear in the unified audit log within the lookback
    window (design.md Section 2, item 2).

    This is deliberately reported as [PASS]/[INCONCLUSIVE], never [PASS]/[FAIL], for the "evidence
    found" check: a zero-row result is equally consistent with (a) the control being off, (b) the
    control being on but no Elevated-risk user has deleted anything in the window, or (c) the
    36-hour propagation delay after a first-time enable (design.md Section 5) not having elapsed
    yet. Asserting [FAIL] on a zero-row result would overclaim certainty this script cannot have --
    see README.md Section 7/11.

    Safe to re-run; safe to schedule (README.md Section 8 recommends daily, alongside deploy/
    Export-AdaptiveProtectionPreservationEvidence.ps1). Exits non-zero only on a hard
    infrastructure failure (no Exchange Online session) -- never on a zero-evidence window, which
    is expected, common, and not itself a failure.

.PARAMETER LookbackDays
    How many days back to search for preservation evidence. Defaults to 30 -- long enough to
    smooth over an infrequent Elevated-risk-user population without requiring daily manual
    review, short enough to stay well inside the 180-day Standard Audit retention default (see
    deploy/Export-AdaptiveProtectionPreservationEvidence.ps1's own .NOTES).

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-AdaptiveProtectionDlmPreservation.ps1

.EXAMPLE
    ./Test-AdaptiveProtectionDlmPreservation.ps1 -LookbackDays 120

    Widens the check to the control's own full 120-day preservation window -- useful right after
    first enabling the toggle, or when triaging whether a specific past incident would have been
    caught.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$LookbackDays = 30
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Inconclusive)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Inconclusive) { Write-Host "  [INCONCLUSIVE] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - see rbac-model.md Section 6.'
}

$startDate = ([datetime]::UtcNow.AddDays(-$LookbackDays))
$endDate = ([datetime]::UtcNow)
$operations = @('SharePointDataProactivelyPreserved', 'ExchangeDataProactivelyPreserved')

Write-Host "Checking for Adaptive Protection deleted-content preservation evidence in the unified audit log, last $LookbackDays day(s) ($startDate to $endDate, UTC)..." -ForegroundColor Cyan

$records = @(Search-UnifiedAuditLog -StartDate $startDate -EndDate $endDate -Operations $operations -ResultSize 100)

$sharePointCount = @($records | Where-Object { $_.Operations -eq 'SharePointDataProactivelyPreserved' }).Count
$exchangeCount = @($records | Where-Object { $_.Operations -eq 'ExchangeDataProactivelyPreserved' }).Count

Write-Host "Found $($records.Count) total preservation event(s): $sharePointCount SharePoint/OneDrive (Retained file proactively), $exchangeCount Exchange (Retained email item proactively)." -ForegroundColor Cyan

if ($records.Count -gt 0) {
    Test-Check -Description "Preservation evidence found in the last $LookbackDays day(s) - the control has visibly fired at least once" -Condition $true
    $mostRecent = $records | Sort-Object CreationDate -Descending | Select-Object -First 1
    Write-Host "  Most recent event: $($mostRecent.CreationDate) UTC, user=$($mostRecent.UserIds), operation=$($mostRecent.Operations)" -ForegroundColor Cyan
}
else {
    Test-Check -Description "No preservation evidence found in the last $LookbackDays day(s)" -Condition $false -Inconclusive
    Write-Host '  This does NOT confirm the control is off. No status cmdlet exists (design.md Section 2, item 4) - a zero-row result is equally consistent with the control being on and simply not yet triggered (no Elevated-risk user has deleted content in this window), or with the up-to-36-hour propagation delay after first enabling it. Confirm the portal toggle state directly: Purview portal -> Solutions -> Settings -> Solution settings -> Data lifecycle management -> Adaptive protection (README.md Section 5).' -ForegroundColor Yellow
}

Write-Host "`nResult: $($script:failures) hard failure(s)." -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```