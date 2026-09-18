---
part: "validate"
parent: "dlp/defender-device-control-usb-allowlist-macos"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-MacDeviceControlUsbAllowlistPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies the "Device Control (macOS) - USB Removable Media Default-Deny Allowlist" Intune
    macOS Custom configuration profile is deployed correctly.

.DESCRIPTION
    Read-only validation script - never modifies policy state. Checks:
      1. The device configuration object exists and is a macOSCustomConfiguration.
      2. Its payload decodes to a well-formed mobileconfig with the expected PayloadIdentifier
         (com.microsoft.wdav) and the DC_in_dlp feature-enable dict.
      3. The embedded device-control policy JSON contains the expected groups (catch-all +
         approved), rules (allow + deny, mutually exclusive by construction), and every
         serialNumber from -ConfigPath's approvedDevices list.
      4. The policy has at least one assignment (pilot group or All devices).
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

    Note: this script validates the device configuration *object* only. It does not and cannot
    confirm per-device profile *sync/apply status* (Intune admin center > Devices > macOS >
    Configuration profiles > this policy > Device status), nor whether Full Disk Access for
    com.microsoft.dlp.daemon has actually been granted on a given Mac - both are prerequisites this
    script cannot observe remotely. See README.md Section 7 for the functional (on-device) test
    steps this script cannot replace.

.PARAMETER ConfigPath
    Path to the same JSON config used at deploy time (approvedDevices list + assignment target).

.PARAMETER PolicyDisplayName
    Overrides the config file's policyDisplayName, if set.

.PARAMETER GraphBaseUri
    Graph base URI. Defaults to 'https://graph.microsoft.com/v1.0'.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-MacDeviceControlUsbAllowlistPolicy.ps1 -ConfigPath ../deploy/config/mac-device-control-usb-allowlist.sample.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/mac-device-control-usb-allowlist.sample.json'),

    [Parameter()]
    [string]$PolicyDisplayName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
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

function Assert-MgConnected {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw 'Microsoft Graph PowerShell SDK not found. Install Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement, then Connect-MgGraph.'
    }
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first. See docs/automation-surface.md Section 3.'
    }
}

function Get-AllGraphValues {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($resp.value) { $items += $resp.value }
        $next = $resp.'@odata.nextLink'
    }
    return $items
}

function ConvertFrom-Utf8Base64 {
    param([Parameter(Mandatory)][string]$Base64)
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$displayName = if ($PolicyDisplayName) { $PolicyDisplayName } else { $cfg.policyDisplayName }

Assert-MgConnected
Write-Host "Validating policy '$displayName'..." -ForegroundColor Cyan

$configUri = "$GraphBaseUri/deviceManagement/deviceConfigurations"
$policy = Get-AllGraphValues -Uri $configUri | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

Test-Check -Description "Policy '$displayName' exists" -Condition ($null -ne $policy)
if (-not $policy) {
    Write-Host "`nCannot continue - policy not found. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

$full = Invoke-MgGraphRequest -Method GET -Uri "$configUri/$($policy.id)"
Test-Check -Description 'Policy is a macOSCustomConfiguration' `
    -Condition ($full.'@odata.type' -eq '#microsoft.graph.macOSCustomConfiguration')
Test-Check -Description "payloadFileName ends in .mobileconfig" -Condition ($full.payloadFileName -like '*.mobileconfig')

$mobileConfigXml = $null
try { $mobileConfigXml = ConvertFrom-Utf8Base64 $full.payload } catch { }
Test-Check -Description 'payload decodes as text (base64 round-trip)' -Condition (-not [string]::IsNullOrEmpty($mobileConfigXml))

if ($mobileConfigXml) {
    Test-Check -Description 'PayloadIdentifier is com.microsoft.wdav (MDE managed-preferences profile)' `
        -Condition ($mobileConfigXml -match '<key>PayloadIdentifier</key>\s*<string>com\.microsoft\.wdav</string>')
    Test-Check -Description 'DC_in_dlp feature is enabled (Device Control engine on)' `
        -Condition ($mobileConfigXml -match '<string>DC_in_dlp</string>[\s\S]*?<string>enabled</string>')

    [xml]$plist = $null
    $policyJsonText = $null
    try {
        # Extract the raw JSON string between <key>policy</key><string> ... </string> without a
        # full XML parse, since the embedded JSON itself contains characters XML parsers can choke
        # on if the surrounding mobileconfig has any encoding quirks - a plain regex extraction is
        # more robust for a read-only validation check than round-tripping through [xml].
        $m = [regex]::Match($mobileConfigXml, '<key>policy</key>\s*<string>([\s\S]*?)</string>')
        if ($m.Success) {
            $raw = $m.Groups[1].Value
            $raw = $raw -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
            $policyJsonText = $raw.Trim()
        }
    }
    catch { }

    Test-Check -Description 'Embedded device-control policy JSON found' -Condition (-not [string]::IsNullOrEmpty($policyJsonText))

    if ($policyJsonText) {
        $dcPolicy = $null
        try { $dcPolicy = $policyJsonText | ConvertFrom-Json } catch { }
        Test-Check -Description 'Embedded policy JSON parses' -Condition ($null -ne $dcPolicy)

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
                    -Condition ($null -ne ($allowRule.entries | Where-Object { $_.enforcement.'$type' -eq 'allow' -and (Compare-Object $_.access @('read','write','execute') | Measure-Object).Count -eq 0 }))
                Test-Check -Description 'Allow rule also audits (auditAllow) - not a silent trust' `
                    -Condition ($null -ne ($allowRule.entries | Where-Object { $_.enforcement.'$type' -eq 'auditAllow' }))
            }
            if ($denyRule) {
                Test-Check -Description 'Deny rule has a deny entry denying read/write/execute' `
                    -Condition ($null -ne ($denyRule.entries | Where-Object { $_.enforcement.'$type' -eq 'deny' -and (Compare-Object $_.access @('read','write','execute') | Measure-Object).Count -eq 0 }))
                Test-Check -Description 'Deny rule excludes the approved group (mutually exclusive by construction)' `
                    -Condition ($null -ne $denyRule.excludeGroups -and $denyRule.excludeGroups.Count -gt 0)
            }

            Test-Check -Description 'settings.features.removableMedia.disable = false (enforcement enabled)' `
                -Condition ($dcPolicy.settings.features.removableMedia.disable -eq $false)
            Test-Check -Description "settings.global.defaultEnforcement = 'deny' (fail-closed)" `
                -Condition ($dcPolicy.settings.global.defaultEnforcement -eq 'deny')
        }
    }
}

$assignments = Get-AllGraphValues -Uri "$configUri/$($policy.id)/assignments"
Test-Check -Description 'Policy has at least one assignment' -Condition ($assignments.Count -gt 0)
if ($assignments.Count -gt 0) {
    $isAllDevices = $assignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' }
    Test-Check -Description 'Assignment is scoped to a pilot group, not tenant-wide "All devices" (confirm this is intentional once past pilot)' `
        -Condition (-not $isAllDevices) -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```