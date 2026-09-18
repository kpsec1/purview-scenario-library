---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-JamfDeviceControlPolicyJson.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the locally generated JAMF device control policy JSON artifact matches its config -
    the JAMF-managed sibling of Test-MacDeviceControlUsbAllowlistPolicy.ps1.

.DESCRIPTION
    Read-only validation script - never modifies anything. Unlike the Intune sibling's validate
    script, there is no Microsoft Graph object to read back: JAMF's device control policy JSON
    lives inside a JAMF Pro custom-schema property with no documented API, so this script can only
    confirm the LOCAL ARTIFACT this scenario's deploy script produced is well-formed and matches
    -ConfigPath - it cannot confirm the JSON was actually pasted into JAMF Pro, that the profile is
    scoped/deployed, or that any Mac is enforcing it. See README.md Section 7 for the on-device
    (`mdatp health`) and functional checks this script cannot replace.

    Checks:
      1. -ArtifactPath exists and parses as valid JSON.
      2. groups: AllRemovableStorage (catch-all, scoped to removable_media_devices) and
         ApprovedBackupDrives (containing every serialNumber from -ConfigPath's approvedDevices)
         are both present.
      3. rules: Allow-ApprovedBackupDrives (allow + auditAllow, read/write/execute) and
         Deny-AllOtherRemovableStorage (deny + auditDeny, read/write/execute, excludes the approved
         group) are both present.
      4. settings: removableMedia enforcement enabled, defaultEnforcement = deny (fail-closed).
      5. If the mdatp CLI is available on this machine, also re-runs the Microsoft-documented local
         schema validator (`mdatp device-control policy validate --path <ArtifactPath>`) as a
         [WARN]-tier check (not [PASS]/[FAIL]) - this is a genuinely optional, best-effort check
         since a validation workstation is frequently not itself an onboarded Mac.

    Exits with a non-zero code if any hard ([FAIL]) check fails. Safe to re-run any number of times.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedDevices list).

.PARAMETER ArtifactPath
    Path to the generated device control policy JSON. Defaults to the deploy script's default
    output location, '../deploy/output/jamf-device-control-policy.json'.

.EXAMPLE
    ./Test-JamfDeviceControlPolicyJson.ps1 -ConfigPath ../deploy/config/my-tenant.json -ArtifactPath ../deploy/output/my-tenant-device-control-policy.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-device-control-usb-allowlist-jamf.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactPath = (Join-Path $PSScriptRoot '../deploy/output/jamf-device-control-policy.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
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

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Host "Validating local artifact for policy '$($cfg.policyDisplayName)'..." -ForegroundColor Cyan

Test-Check -Description "Artifact exists at '$ArtifactPath'" -Condition (Test-Path -LiteralPath $ArtifactPath)
if (-not (Test-Path -LiteralPath $ArtifactPath)) {
    Write-Host "`nCannot continue - run deploy/New-JamfDeviceControlPolicyJson.ps1 first. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$raw = Get-Content -LiteralPath $ArtifactPath -Raw
$dcPolicy = $null
try { $dcPolicy = $raw | ConvertFrom-Json } catch { }
Test-Check -Description 'Artifact parses as valid JSON' -Condition ($null -ne $dcPolicy)

if ($dcPolicy) {
    $catchAllGroup = $dcPolicy.groups | Where-Object { $_.name -eq 'AllRemovableStorage' }
    $approvedGroup = $dcPolicy.groups | Where-Object { $_.name -eq 'ApprovedBackupDrives' }
    Test-Check -Description 'AllRemovableStorage (catch-all) group present, scoped to removable_media_devices' `
        -Condition ($null -ne $catchAllGroup -and ($catchAllGroup.query.clauses | Where-Object { $_.'$type' -eq 'primaryId' -and $_.value -eq 'removable_media_devices' }))
    Test-Check -Description 'ApprovedBackupDrives group present' -Condition ($null -ne $approvedGroup)

    if ($approvedGroup) {
        foreach ($d in $cfg.approvedDevices) {
            Test-Check -Description "Approved group includes serialNumber '$($d.serialNumber)'" `
                -Condition ($null -ne ($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'serialNumber' -and $_.value -eq $d.serialNumber }))
        }
    }

    $allowRule = $dcPolicy.rules | Where-Object { $_.name -eq 'Allow-ApprovedBackupDrives' }
    $denyRule = $dcPolicy.rules | Where-Object { $_.name -eq 'Deny-AllOtherRemovableStorage' }
    Test-Check -Description 'Allow-ApprovedBackupDrives rule present' -Condition ($null -ne $allowRule)
    Test-Check -Description 'Deny-AllOtherRemovableStorage rule present' -Condition ($null -ne $denyRule)

    if ($allowRule) {
        Test-Check -Description 'Allow rule has an allow entry granting read/write/execute' `
            -Condition ($null -ne ($allowRule.entries | Where-Object { $_.enforcement.'$type' -eq 'allow' -and (Compare-Object $_.access @('read', 'write', 'execute') | Measure-Object).Count -eq 0 }))
        Test-Check -Description 'Allow rule also audits (auditAllow) - not a silent trust' `
            -Condition ($null -ne ($allowRule.entries | Where-Object { $_.enforcement.'$type' -eq 'auditAllow' }))
    }
    if ($denyRule) {
        Test-Check -Description 'Deny rule has a deny entry denying read/write/execute' `
            -Condition ($null -ne ($denyRule.entries | Where-Object { $_.enforcement.'$type' -eq 'deny' -and (Compare-Object $_.access @('read', 'write', 'execute') | Measure-Object).Count -eq 0 }))
        Test-Check -Description 'Deny rule excludes the approved group (mutually exclusive by construction)' `
            -Condition ($null -ne $denyRule.excludeGroups -and $denyRule.excludeGroups.Count -gt 0)
    }

    Test-Check -Description 'settings.features.removableMedia.disable = false (enforcement enabled)' `
        -Condition ($dcPolicy.settings.features.removableMedia.disable -eq $false)
    Test-Check -Description "settings.global.defaultEnforcement = 'deny' (fail-closed)" `
        -Condition ($dcPolicy.settings.global.defaultEnforcement -eq 'deny')
}

if (Get-Command mdatp -ErrorAction SilentlyContinue) {
    & mdatp device-control policy validate --path $ArtifactPath | Out-Null
    Test-Check -Description 'mdatp device-control policy validate --path (local schema validator) passed' -Condition ($LASTEXITCODE -eq 0) -Warn
}
else {
    Write-Host "  [WARN] mdatp CLI not found on this machine - schema validation not re-run here. Run on an onboarded Mac before pasting into JAMF Pro." -ForegroundColor Yellow
}

Write-Host "`nReminder: this script validates the LOCAL ARTIFACT only. It cannot confirm the JSON was pasted into JAMF Pro's 'Device Control Policy' property, that the profile is scoped/deployed, or that any Mac is enforcing it - see README.md Section 7 for the JAMF-console and on-device checks this script cannot replace." -ForegroundColor DarkCyan

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```