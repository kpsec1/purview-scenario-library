---
part: "validate"
parent: "data-lifecycle-management/event-based-retention-and-disposition"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EventBasedRetentionAndDisposition.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the retention event type, event-based retention label, and publish policy/rule exist
    and are configured as expected.

.DESCRIPTION
    Read-only - never modifies any object. Uses Security & Compliance PowerShell Get-* cmdlets to
    check, against the config file:
      1. The retention event type exists.
      2. The retention label exists, is bound to that event type, with the expected RetentionAction/
         Duration/RetentionType and record/disposition-review settings.
      3. The publish policy exists and is enabled, with at least one location.
      4. The policy's rule publishes the expected label.
    Exits non-zero on any hard failure (safe for a CI-style pre-flight). Safe to re-run.

    Connect first with Connect-IPPSSession. A View-Only role that can read retention configuration
    is sufficient.

.PARAMETER ConfigPath
    Path to the config to validate against. Defaults to
    '../deploy/config/employee-departure-retention.sample.json'.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Test-EventBasedRetentionAndDisposition.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/employee-departure-retention.sample.json')
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

Write-Host "Validating event-based retention ('$($cfg.eventType.name)' / '$($cfg.label.name)' / '$($cfg.policy.name)')..." -ForegroundColor Cyan

# Event type
$eventType = Get-ComplianceRetentionEventType -Identity $cfg.eventType.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention event type '$($cfg.eventType.name)' exists" -Condition ($null -ne $eventType)

# Label
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
Test-Check -Description "Retention label '$($cfg.label.name)' exists" -Condition ($null -ne $label)
if ($label) {
    Test-Check -Description "  RetentionAction is '$($cfg.label.retentionAction)' (current: $($label.RetentionAction))" `
        -Condition ("$($label.RetentionAction)" -eq "$($cfg.label.retentionAction)")
    Test-Check -Description "  RetentionType is EventAgeInDays (current: $($label.RetentionType))" `
        -Condition ("$($label.RetentionType)" -eq 'EventAgeInDays')
    Test-Check -Description "  RetentionDuration is $($cfg.label.retentionDurationDays) days (current: $($label.RetentionDuration))" `
        -Condition ("$($label.RetentionDuration)" -eq "$($cfg.label.retentionDurationDays)") -Warn
    Test-Check -Description "  Label's EventType is bound to '$($cfg.eventType.name)' (current: $($label.EventType))" `
        -Condition ("$($label.EventType)" -like "*$($cfg.eventType.name)*") -Warn
    if ($cfg.label.isRecordLabel) {
        Test-Check -Description "  Label is a record label" -Condition ([bool]$label.IsRecordLabel) -Warn
    }
    $hasReview = $label.ReviewerEmail -or $label.MultiStageReviewProperty
    Test-Check -Description "  Label has a disposition-review reviewer/stage configuration (undocumented read-back property name; best-effort)" `
        -Condition ($null -ne $hasReview) -Warn
}

# Policy
$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
Test-Check -Description "Publish policy '$($cfg.policy.name)' exists" -Condition ($null -ne $policy)
if ($policy) {
    Test-Check -Description "  Policy is enabled" -Condition ([bool]$policy.Enabled) -Warn
    $hasLoc = (@($policy.SharePointLocation).Count -gt 0) -or (@($policy.ExchangeLocation).Count -gt 0)
    Test-Check -Description "  Policy has at least one location" -Condition $hasLoc
    if ($policy.DistributionStatus) { Write-Host "    Distribution status: $($policy.DistributionStatus)" -ForegroundColor Cyan }
}

# Rule
$rule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
Test-Check -Description "Publish rule exists on the policy" -Condition ($null -ne $rule)
if ($rule) {
    Test-Check -Description "  Rule publishes label '$($cfg.label.name)' (current: $($rule.PublishComplianceTag))" `
        -Condition ("$($rule.PublishComplianceTag)" -eq "$($cfg.label.name)")
}

Write-Host "`n  Note: this checks the POLICY, not whether any individual employee's records have had a" -ForegroundColor Cyan
Write-Host "  retention event fired for them. Use Get-ComplianceRetentionEvent to inspect fired events." -ForegroundColor Cyan
Write-Host "$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```