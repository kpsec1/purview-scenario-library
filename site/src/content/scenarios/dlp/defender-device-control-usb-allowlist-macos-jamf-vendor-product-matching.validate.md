---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-JamfVendorProductDeviceAllowlistPolicyJson.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the locally generated JAMF device control policy JSON artifact (serialNumber +
    vendorId/productId compound matching) matches its config - the vendor/product-matching sibling
    of Test-JamfDeviceControlPolicyJson.ps1.

.DESCRIPTION
    Read-only validation script - never modifies anything. Like the base JAMF scenario's validate
    script, there is no Microsoft Graph object or JAMF Pro API to read back: this script can only
    confirm the LOCAL ARTIFACT this scenario's deploy script produced is well-formed and matches
    -ConfigPath - it cannot confirm the JSON was actually pasted into JAMF Pro, that the profile is
    scoped/deployed, or that any Mac is enforcing it. See README.md Section 7 for the on-device
    (`mdatp health`) and functional checks this script cannot replace.

    Checks:
      1. -ArtifactPath exists and parses as valid JSON.
      2. groups: AllRemovableStorage (catch-all, scoped to removable_media_devices) is present; one
         "VendorProductMatch-<label>" AND sub-group (primaryId=removable_media_devices, matching
         vendorId, matching productId) exists for every -ConfigPath vendorProductDevices entry, at
         its expected deterministic id; ApprovedBackupDrives is present and contains every
         serialNumber from approvedDevices AND every vendorProductDevices sub-group's id as a groupId
         clause.
      3. Ordering: every vendorProductDevices sub-group appears in the groups array BEFORE
         ApprovedBackupDrives (Microsoft's documented "group must be defined within the policy before
         the clause" requirement for groupId).
      4. No orphaned "VendorProductMatch-" groups - every group with that name prefix in the artifact
         corresponds to a current -ConfigPath vendorProductDevices entry; none left over from a
         removed device (this script fully regenerates the artifact from config each run, so an
         orphan here would mean the artifact was hand-edited, or generated from a stale config).
      5. rules: Allow-ApprovedBackupDrives (allow + auditAllow, read/write/execute) and
         Deny-AllOtherRemovableStorage (deny + auditDeny, read/write/execute, excludes the approved
         group) are both present, unchanged from the base scenario.
      6. settings: removableMedia enforcement enabled, defaultEnforcement = deny (fail-closed).
      7. If the mdatp CLI is available on this machine, also re-runs the Microsoft-documented local
         schema validator (`mdatp device-control policy validate --path <ArtifactPath>`) as a
         [WARN]-tier check (not [PASS]/[FAIL]).

    Exits with a non-zero code if any hard ([FAIL]) check fails. Safe to re-run any number of times.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedDevices[] and/or
    vendorProductDevices[]).

.PARAMETER ArtifactPath
    Path to the generated device control policy JSON. Defaults to the deploy script's default output
    location, '../deploy/output/jamf-device-control-policy.json'.

.EXAMPLE
    ./Test-JamfVendorProductDeviceAllowlistPolicyJson.ps1 -ConfigPath ../deploy/config/my-tenant.json -ArtifactPath ../deploy/output/my-tenant-device-control-policy.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-jamf-vendor-product-device-allowlist.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactPath = (Join-Path $PSScriptRoot '../deploy/output/jamf-device-control-policy.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
$script:NamePrefix = 'VendorProductMatch-'
# Byte-identical to the deploy script's own constant and to the Intune sibling's - see
# deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1's .NOTES.
$script:SubGroupNamespaceHex = '8f3a2b108f2e4c4a9b8b2f1a6c9d7e10'

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

function Get-DeterministicSubGroupId {
    param(
        [Parameter(Mandatory)][string]$NamespaceHex,
        [Parameter(Mandatory)][string]$Name
    )
    $nsBytes = [byte[]](0..15 | ForEach-Object { [Convert]::ToByte($NamespaceHex.Substring($_ * 2, 2), 16) })
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)
    $toHash = [byte[]]($nsBytes + $nameBytes)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash($toHash)
    }
    finally {
        $sha1.Dispose()
    }

    $b = [byte[]]$hash[0..15]
    $b[6] = [byte](($b[6] -band 0x0F) -bor 0x50)
    $b[8] = [byte](($b[8] -band 0x3F) -bor 0x80)

    $hex = -join ($b | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$approvedDevices = @($cfg.approvedDevices | Where-Object { $_ })
$vendorProductDevices = @($cfg.vendorProductDevices | Where-Object { $_ })

Write-Host "Validating local artifact for policy '$($cfg.policyDisplayName)'..." -ForegroundColor Cyan

Test-Check -Description "Artifact exists at '$ArtifactPath'" -Condition (Test-Path -LiteralPath $ArtifactPath)
if (-not (Test-Path -LiteralPath $ArtifactPath)) {
    Write-Host "`nCannot continue - run deploy/New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 first. $script:failures check(s) failed." -ForegroundColor Red
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
        foreach ($d in $approvedDevices) {
            Test-Check -Description "Approved group includes serialNumber clause '$($d.serialNumber)'" `
                -Condition ($null -ne ($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'serialNumber' -and $_.value -eq $d.serialNumber }))
        }
    }

    # --- vendorId/productId compound-matching checks ---
    $ownedSubGroups = @($dcPolicy.groups | Where-Object { $_.name -like "$($script:NamePrefix)*" })
    $expectedGroupIds = @{}
    foreach ($d in $vendorProductDevices) {
        $vendorNorm = ([string]$d.vendorId).ToLowerInvariant()
        $productNorm = ([string]$d.productId).ToLowerInvariant()
        $expectedId = Get-DeterministicSubGroupId -NamespaceHex $script:SubGroupNamespaceHex -Name "mac-vendor-product-match/v1/$vendorNorm`:$productNorm"
        $expectedGroupIds[$expectedId] = $d.label
        $expectedName = "$script:NamePrefix$($d.label)"
        $subGroup = $dcPolicy.groups | Where-Object { $_.id -eq $expectedId }

        Test-Check -Description "vendorId/productId sub-group '$expectedName' present at its deterministic id" -Condition ($null -ne $subGroup)
        if ($subGroup) {
            $clauses = $subGroup.query.clauses
            Test-Check -Description "  '$expectedName' is an AND group over primaryId+vendorId+productId" `
                -Condition ($subGroup.query.'$type' -eq 'and' -and
                            ($clauses | Where-Object { $_.'$type' -eq 'primaryId' -and $_.value -eq 'removable_media_devices' }) -and
                            ($clauses | Where-Object { $_.'$type' -eq 'vendorId' -and $_.value -eq $vendorNorm }) -and
                            ($clauses | Where-Object { $_.'$type' -eq 'productId' -and $_.value -eq $productNorm }))
        }
        if ($approvedGroup) {
            Test-Check -Description "ApprovedBackupDrives references '$expectedName' via a groupId clause" `
                -Condition ($null -ne ($approvedGroup.query.clauses | Where-Object { $_.'$type' -eq 'groupId' -and $_.value -eq $expectedId }))
        }

        if ($subGroup -and $approvedGroup) {
            $subGroupIndex = [array]::IndexOf(@($dcPolicy.groups.id), $expectedId)
            $approvedGroupIndex = [array]::IndexOf(@($dcPolicy.groups.id), $approvedGroup.id)
            Test-Check -Description "  '$expectedName' appears before ApprovedBackupDrives in the groups array (groupId ordering requirement)" `
                -Condition ($subGroupIndex -ge 0 -and $approvedGroupIndex -ge 0 -and $subGroupIndex -lt $approvedGroupIndex)
        }
    }

    $orphans = @($ownedSubGroups | Where-Object { -not $expectedGroupIds.ContainsKey($_.id) })
    Test-Check -Description 'No orphaned VendorProductMatch- sub-groups (every owned group matches a current config entry)' `
        -Condition ($orphans.Count -eq 0)
    foreach ($orphan in $orphans) {
        Write-Host "    Orphan: '$($orphan.name)' (id $($orphan.id)) has no corresponding vendorProductDevices entry in -ConfigPath." -ForegroundColor Red
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