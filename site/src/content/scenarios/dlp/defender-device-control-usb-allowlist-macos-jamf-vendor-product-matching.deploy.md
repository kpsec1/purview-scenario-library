---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/mac-jamf-vendor-product-device-allowlist.sample.json`

```json
{
  "policyDisplayName": "Device Control (macOS, JAMF) - USB Removable Media Default-Deny Allowlist",
  "policyDescription": "Denies all removable USB storage on JAMF-managed macOS endpoints by default; allows only IT-issued, identity-verified backup drives matched by serial number (approvedDevices) and/or by vendorId+productId (vendorProductDevices, for drives with no readable serial number). Deployed by scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching - supersedes the base scenario's own output once vendor/product matching is needed. Owner: Security & Compliance team.",
  "approvedDevices": [
    {
      "label": "IT Data Custodians - encrypted backup drive #1",
      "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER"
    }
  ],
  "vendorProductDevices": [
    {
      "label": "IT Imaging Team - bulk-imaged dock (no readable serial number)",
      "vendorId": "0951",
      "productId": "1666"
    }
  ],
  "notificationUrl": "",
  "jamfComputerGroupName": "REPLACE_WITH_PILOT_JAMF_COMPUTER_GROUP_NAME"
}
```

#### `New-JamfVendorProductDeviceAllowlistPolicyJson.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Generates (and, optionally, locally schema-validates) a device control policy JSON artifact for
    JAMF-managed macOS endpoints that matches approved removable-storage devices by serialNumber
    AND/OR by vendorId+productId compound matching - the JAMF-managed sibling of
    scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching (Intune).

.DESCRIPTION
    scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/deploy/
    New-JamfDeviceControlPolicyJson.ps1 (the base JAMF scenario) matches approved devices by
    serialNumber only, deliberately deferring vendorId/productId compound matching for the same
    reason the Intune sibling's own parent scenario deferred it: macOS's device-control JSON schema
    keeps vendorId and productId as two separate clause types that can only be AND-combined via a
    per-device sub-group referenced by a "groupId" clause - a materially more complex, per-device
    dynamic-GUID model the base fragment's four-fixed-GUID design never needed (this scenario's own
    design.md Section 3). This script closes that gap for JAMF-managed fleets, for a buyer whose
    approved drives have no readable serial number (e.g. bulk-imaged imaging docks, or third-party
    hardware whose serialNumber clause macOS reports empty).

    UNLIKE THE INTUNE SIBLING, THIS SCRIPT DOES NOT PATCH A LIVE OBJECT. JAMF's device control
    policy has no documented API (the same gap the base JAMF scenario's own design.md Section 3
    discloses) - every JAMF deployment is "regenerate the complete artifact locally, then paste the
    whole thing into the JAMF Pro console by hand." This script is therefore a SUPERSET GENERATOR,
    not an incremental patcher: it reads ONE config file containing both approvedDevices
    (serialNumber-based) and vendorProductDevices (vendorId/productId-based), and produces the
    COMPLETE policy JSON containing both matching mechanisms in one ApprovedBackupDrives group - the
    same final policy shape the Intune sibling's Add-MacVendorProductDeviceAllowlist.ps1 produces via
    an incremental Graph PATCH, just generated as a single artifact instead. Run THIS script instead
    of (not in addition to) the base scenario's New-JamfDeviceControlPolicyJson.ps1 once you need
    vendor/product matching too - see design.md Section 3 for why JAMF has no "extend the live
    policy" equivalent to the Intune sibling's PATCH flow.

    What this script does:
      1. Reads -ConfigPath (approvedDevices[] and/or vendorProductDevices[] - at least one entry
         across both lists is required) and generates the device control policy JSON:
           - groups: AllRemovableStorage (catch-all), one "VendorProductMatch-<label>" per-device
             AND sub-group per vendorProductDevices entry, and ApprovedBackupDrives (an "any"/OR
             group whose clauses are every approvedDevices serialNumber clause PLUS one groupId
             clause per vendorProductDevices sub-group).
           - rules: Allow-ApprovedBackupDrives / Deny-AllOtherRemovableStorage, unchanged from the
             base scenario - both already key off ApprovedBackupDrives' group id directly, so no new
             rule is needed to cover the vendor/product-matched devices (design.md Section 2 goal 2).
           - settings: removableMedia enforcement enabled, defaultEnforcement = deny.
         Every fixed GUID (AllRemovableStorage, ApprovedBackupDrives, both rules) is byte-identical
         to the base JAMF scenario's and the Intune vendor-product-matching sibling's own constants,
         and every per-device sub-group id is derived with the SAME deterministic RFC 4122 Section
         4.3 version-5 (SHA-1, name-based) UUID scheme and namespace constant the Intune sibling
         uses - so a hybrid Intune+JAMF fleet approving the identical vendorId+productId pair on both
         deployment paths gets the identical sub-group id on both (design.md Section 4).
         If vendorProductDevices is empty, this script's output is byte-identical to the base
         scenario's own output for the same approvedDevices list - this script is a strict superset,
         not a divergent reimplementation.
      2. Writes the JSON to -OutputPath as a plain, pretty-printed .json file - ready to copy/paste
         into the JAMF Pro "Device Control Policy" property, the same manual step the base scenario's
         README.md Section 5 documents (Steps 3-4 there apply unchanged to this script's output).
      3. With -ValidateWithMdatp, shells out to the Microsoft-documented local validator
         (`mdatp device-control policy validate --path <OutputPath>`) and surfaces its result. This
         requires running the script ON an already-onboarded Mac with the mdatp CLI available - it
         is not a remote/API check, and is skipped (not failed) with a warning if mdatp is not found.

    Idempotent: re-running with an unchanged config produces byte-identical JSON; if -OutputPath
    already contains that exact content, the script reports no change and writes nothing. If the
    existing file's content differs, the script requires -Force to overwrite it (never silently
    clobbers a hand-edited or already-pasted-elsewhere file) - identical discipline to the base
    scenario's own script.

    PREREQUISITES this script does not perform (README.md Section 3, Section 5) - identical boundary
    to the base JAMF scenario:
      - Target Macs must already be onboarded to Microsoft Defender for Endpoint via JAMF, running
        Defender for Endpoint on macOS version 101.91.92 or later.
      - A Full Disk Access (PPPC) profile granting com.microsoft.dlp.daemon Full Disk Access must
        already be deployed via JAMF - device control cannot enforce without it.
      - The Defender for Endpoint preferences schema (schema.json) in the JAMF Pro "MDE Preferences"
        custom-schema profile must include the Device Control property set and
        Data Loss Prevention (DLP) > Features > DC_in_dlp = enabled - configured through the JAMF Pro
        GUI, not by this script.
      - Pasting this script's output JSON into the JAMF Pro "Device Control Policy" property and
        scoping the profile to a pilot Computer Group - a manual JAMF-console step with no
        Microsoft-documented API (README.md Section 5; design.md Section 3).

.PARAMETER ConfigPath
    Path to the JSON config (approvedDevices[] and/or vendorProductDevices[] - at least one entry
    across both lists total). Defaults to the sibling
    'config/mac-jamf-vendor-product-device-allowlist.sample.json' - copy and edit it, do not deploy
    the sample values as-is. jamfComputerGroupName is informational only (this script never calls the
    JAMF Pro API, so it has no effect on the generated JSON).

.PARAMETER OutputPath
    Where to write the generated device control policy JSON. Defaults to
    'output/jamf-device-control-policy.json' next to this script - deliberately the SAME default
    filename the base scenario's script uses, since this script's output is meant to supersede it,
    not live alongside it as a second artifact.

.PARAMETER ValidateWithMdatp
    After writing the file, run `mdatp device-control policy validate --path <OutputPath>` (the
    Microsoft-documented local schema validator). Requires running this script on an onboarded Mac
    with the mdatp CLI present; skipped with a warning (not a hard failure) if mdatp is not found.

.PARAMETER Force
    If -OutputPath already exists with different content, overwrite it. Without -Force, an existing
    file with different content is left untouched and the script exits non-zero.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports what would be written (and, with
    -ValidateWithMdatp, what would be validated) without writing or shelling out to mdatp.

.EXAMPLE
    ./New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

    Dry-run: shows exactly what would be written, changes nothing.

.EXAMPLE
    ./New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -Force

    Regenerates the JSON artifact (overwriting a prior version, e.g. the base scenario's
    serialNumber-only output) ready to paste into JAMF Pro.

.EXAMPLE
    # Run on an onboarded Mac's Terminal, from a pwsh session:
    ./New-JamfVendorProductDeviceAllowlistPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -ValidateWithMdatp

.NOTES
    SCOPE: limited to the "removable_media_devices" primaryId family, the same family the base JAMF
    scenario's serialNumber-based ApprovedBackupDrives group already covers. Does not extend
    vendorId/productId matching to the Apple, Portable, or Bluetooth families - those are each
    separate sibling fragments' own scope, matching the Intune vendor-product-matching sibling's own
    stated non-goals (its design.md Section 8).

    vendorId/productId identify a DEVICE MODEL, not a unique physical unit - the same disclosed
    limitation as the Intune sibling and the Bluetooth allowlist sibling. See README.md Section 11.

    No directly-confirmed Microsoft worked example pairs a "groupId" clause with more than one
    sibling sub-group inside one "any" query - inherited unresolved from the Intune sibling (its own
    design.md Section 3 / .NOTES). The groupId clause TYPE itself, its "match if a device is a member
    of another group" semantics, and the "group must be defined within the policy before the clause"
    ordering requirement are directly confirmed from Microsoft's own Clause reference table (Sources
    below); the N-sub-groups-in-one-OR-query composition is this repository's own application of that
    documented primitive. Flagged as VERIFY in README.md Section 11.

    The RFC 4122 Section 4.3 version-5 UUID derivation this script implements
    (Get-DeterministicSubGroupId below) is byte-for-byte the same function, namespace constant, and
    hash-input format ("mac-vendor-product-match/v1/<vendorId>:<productId>") as the Intune sibling's
    Add-MacVendorProductDeviceAllowlist.ps1 - deliberately, so the same vendorId+productId pair
    produces the SAME sub-group id whether deployed via Intune or JAMF (design.md Section 4). It was
    independently verified during the Intune sibling's build against Python's standard-library
    uuid.uuid5() reference implementation for the same namespace+name input; reused verbatim here, not
    re-derived.

    Sources (Microsoft Learn, verify before production use):
    - Device Control for macOS (Clause reference table - groupId "Match if a device is a member of
      another group. The value represents the UUID of the group to match against. The group must be
      defined within the policy before the clause."; vendorId/productId "Four digit hexadecimal
      string"; query $type any/or = OR semantics):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Deploy and manage Device Control using JAMF (Steps 1-4: author JSON, validate with mdatp, update
      the Defender for Endpoint preferences schema, add the Device Control Policy property; no
      documented API for the property itself):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf
    - Device control policies in Microsoft Defender for Endpoint (shared groups/rules/entries
      concepts; "the rules and policies are combined into a single JSON and configured by using JAMF
      as the device control policy"):
      https://learn.microsoft.com/defender-endpoint/device-control-policies
    - Sample macOS device control policies (deny_all_bluetooth_devices_except_samsung.json - the
      vendorId+productId AND-clause exception-group shape this script generalizes to N devices and to
      the removable_media_devices family):
      https://github.com/microsoft/mdatp-devicecontrol/blob/main/macOS/policy/samples/deny_all_bluetooth_devices_except_samsung.json
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/deploy/
      New-JamfDeviceControlPolicyJson.ps1 - the base JAMF scenario this script supersedes; same fixed
      group/rule GUIDs.
    - scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/deploy/
      Add-MacVendorProductDeviceAllowlist.ps1 - the Intune sibling this script's group-generation
      logic and deterministic-UUID scheme are ported from.
    - RFC 4122, Section 4.3 (name-based UUID, algorithm for creating a version-5 UUID):
      https://www.rfc-editor.org/rfc/rfc4122#section-4.3
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-jamf-vendor-product-device-allowlist.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output/jamf-device-control-policy.json'),

    [Parameter()]
    [switch]$ValidateWithMdatp,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Fixed, source-controlled GUIDs - byte-identical to the base JAMF scenario's and the Intune sibling's
# own constants, so a hybrid Intune+JAMF fleet (or an upgrade from the base scenario's serialNumber-
# only output to this superset) shares one policy identity.
$script:AllRemovableGroupId = '11111111-aaaa-4bbb-8ccc-111111111111'
$script:ApprovedGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'
$script:AllowRuleId = '33333333-cccc-4ddd-8eee-333333333333'
$script:DenyRuleId = '44444444-dddd-4eee-8fff-444444444444'

# This fragment's own fixed namespace constant for RFC 4122 Section 4.3 version-5 UUID derivation -
# byte-identical to the Intune sibling's own constant (never reused for any other purpose in this
# repo) so the same vendorId+productId pair yields the same sub-group id on either deployment path.
$script:SubGroupNamespaceHex = '8f3a2b108f2e4c4a9b8b2f1a6c9d7e10'
$script:NamePrefix = 'VendorProductMatch-'

function Test-FourDigitHex {
    param([string]$Value, [string]$FieldName, [string]$Label)
    if ($Value -notmatch '^[0-9A-Fa-f]{4}$') {
        throw "Device '$Label': $FieldName must be a four-digit hexadecimal string (e.g. '0951'), got '$Value'."
    }
}

function Get-DeterministicSubGroupId {
    <#
        RFC 4122 Section 4.3 version-5 (name-based, SHA-1) UUID derivation, worked entirely in raw
        hex-string/byte-array form (never round-tripped through [guid]'s byte-array constructor,
        which reorders bytes for .NET's mixed-endian internal representation) - avoids the classic
        UUID-v5-in-.NET endianness bug. Byte-for-byte the same implementation as the Intune sibling's
        Add-MacVendorProductDeviceAllowlist.ps1, verified there against Python's uuid.uuid5().
    #>
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
    $b[6] = [byte](($b[6] -band 0x0F) -bor 0x50)   # version 5
    $b[8] = [byte](($b[8] -band 0x3F) -bor 0x80)   # variant RFC 4122

    $hex = -join ($b | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

function Get-DeviceControlPolicyJson {
    param([Parameter(Mandatory)]$Config)

    # Where-Object filters out $null - PowerShell's @($Config.x) evaluates to a 1-element array
    # containing $null (not an empty array) when the JSON key is omitted entirely.
    $approvedDevices = @($Config.approvedDevices | Where-Object { $_ })
    $vendorProductDevices = @($Config.vendorProductDevices | Where-Object { $_ })

    if ($approvedDevices.Count -eq 0 -and $vendorProductDevices.Count -eq 0) {
        throw "At least one entry across approvedDevices and vendorProductDevices combined is required."
    }

    $serialClauses = foreach ($d in $approvedDevices) {
        if (-not $d.serialNumber) { throw "Every approvedDevices entry requires serialNumber (label: '$($d.label)')." }
        [ordered]@{ '$type' = 'serialNumber'; value = $d.serialNumber }
    }

    $seenLabels = @{}
    $seenPairs = @{}
    $vendorProductSubGroups = foreach ($d in $vendorProductDevices) {
        if (-not $d.label) { throw "Every vendorProductDevices entry requires a 'label'." }
        if ($seenLabels.ContainsKey($d.label)) { throw "Duplicate vendorProductDevices label '$($d.label)' - labels must be unique within one config file." }
        $seenLabels[$d.label] = $true
        Test-FourDigitHex -Value $d.vendorId -FieldName 'vendorId' -Label $d.label
        Test-FourDigitHex -Value $d.productId -FieldName 'productId' -Label $d.label
        $vendorNorm = $d.vendorId.ToLowerInvariant()
        $productNorm = $d.productId.ToLowerInvariant()
        $pairKey = "$vendorNorm`:$productNorm"
        if ($seenPairs.ContainsKey($pairKey)) {
            throw "Duplicate vendorId+productId pair '$pairKey' on entries '$($seenPairs[$pairKey])' and '$($d.label)' - each device's vendorId+productId pair determines its group id and must be unique within one config file, even if labels differ."
        }
        $seenPairs[$pairKey] = $d.label

        [pscustomobject]@{
            Label     = $d.label
            VendorId  = $vendorNorm
            ProductId = $productNorm
            GroupId   = Get-DeterministicSubGroupId -NamespaceHex $script:SubGroupNamespaceHex -Name "mac-vendor-product-match/v1/$vendorNorm`:$productNorm"
        }
    }

    $groups = New-Object System.Collections.Generic.List[object]
    $groups.Add([ordered]@{
        '$type' = 'device'
        id      = $script:AllRemovableGroupId
        name    = 'AllRemovableStorage'
        query   = [ordered]@{
            '$type' = 'all'
            clauses = @([ordered]@{ '$type' = 'primaryId'; value = 'removable_media_devices' })
        }
    })
    foreach ($vp in $vendorProductSubGroups) {
        $groups.Add([ordered]@{
            '$type' = 'device'
            id      = $vp.GroupId
            name    = "$script:NamePrefix$($vp.Label)"
            query   = [ordered]@{
                '$type' = 'and'
                clauses = @(
                    [ordered]@{ '$type' = 'primaryId'; value = 'removable_media_devices' }
                    [ordered]@{ '$type' = 'vendorId'; value = $vp.VendorId }
                    [ordered]@{ '$type' = 'productId'; value = $vp.ProductId }
                )
            }
        })
    }
    $approvedClauses = @($serialClauses) + @($vendorProductSubGroups | ForEach-Object { [ordered]@{ '$type' = 'groupId'; value = $_.GroupId } })
    $groups.Add([ordered]@{
        '$type' = 'device'
        id      = $script:ApprovedGroupId
        name    = 'ApprovedBackupDrives'
        query   = [ordered]@{
            '$type' = 'any'
            clauses = $approvedClauses
        }
    })

    $policy = [ordered]@{
        groups   = @($groups)
        rules    = @(
            [ordered]@{
                id            = $script:AllowRuleId
                name          = 'Allow-ApprovedBackupDrives'
                includeGroups = @($script:ApprovedGroupId)
                entries       = @(
                    [ordered]@{
                        '$type'     = 'removableMedia'
                        id          = '77777777-0001-4001-8001-000000000001'
                        enforcement = [ordered]@{ '$type' = 'allow' }
                        access      = @('read', 'write', 'execute')
                    }
                    [ordered]@{
                        '$type'     = 'removableMedia'
                        id          = '77777777-0002-4002-8002-000000000002'
                        enforcement = [ordered]@{ '$type' = 'auditAllow'; options = @('send_event') }
                        access      = @('read', 'write', 'execute')
                    }
                )
            }
            [ordered]@{
                id            = $script:DenyRuleId
                name          = 'Deny-AllOtherRemovableStorage'
                includeGroups = @($script:AllRemovableGroupId)
                excludeGroups = @($script:ApprovedGroupId)
                entries       = @(
                    [ordered]@{
                        '$type'     = 'removableMedia'
                        id          = '77777777-0003-4003-8003-000000000003'
                        enforcement = [ordered]@{ '$type' = 'deny' }
                        access      = @('read', 'write', 'execute')
                    }
                    [ordered]@{
                        '$type'     = 'removableMedia'
                        id          = '77777777-0004-4004-8004-000000000004'
                        enforcement = [ordered]@{ '$type' = 'auditDeny'; options = @('send_event', 'show_notification') }
                        access      = @('read', 'write', 'execute')
                    }
                )
            }
        )
        settings = [ordered]@{
            features = [ordered]@{ removableMedia = [ordered]@{ disable = $false } }
            global   = [ordered]@{ defaultEnforcement = 'deny' }
        }
    }
    if ($Config.notificationUrl) {
        $policy.settings.ux = [ordered]@{ navigationTarget = $Config.notificationUrl }
    }

    foreach ($vp in $vendorProductSubGroups) {
        Write-Host "  [plan] Approving device '$($vp.Label)' by vendorId=$($vp.VendorId), productId=$($vp.ProductId) (sub-group id $($vp.GroupId))." -ForegroundColor DarkCyan
    }

    ($policy | ConvertTo-Json -Depth 10) + "`n"
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyDisplayName) { throw "policyDisplayName is required in the config file (used for console output/traceability only - it is not written into the JSON artifact)." }

Write-Host "JAMF-managed macOS device control USB allowlist (serialNumber + vendorId/productId): policy '$($cfg.policyDisplayName)'." -ForegroundColor Cyan
if ($cfg.jamfComputerGroupName -and $cfg.jamfComputerGroupName -ne 'REPLACE_WITH_PILOT_JAMF_COMPUTER_GROUP_NAME') {
    Write-Host "  Reminder: scope the JAMF Pro profile to Computer Group '$($cfg.jamfComputerGroupName)' by hand (README.md Section 5) - this script cannot do that for you (design.md Section 3)." -ForegroundColor DarkYellow
}
else {
    Write-Host "  Reminder: jamfComputerGroupName is not set - scope the JAMF Pro profile to a pilot group by hand before assigning (never 'All Computers' on a first rollout)." -ForegroundColor DarkYellow
}

$newJson = Get-DeviceControlPolicyJson -Config $cfg

# --- Write (idempotent) ---
$existingJson = if (Test-Path -LiteralPath $OutputPath) { Get-Content -LiteralPath $OutputPath -Raw } else { $null }

if ($existingJson -eq $newJson) {
    Write-Host "  [artifact] '$OutputPath' already matches this config - no change." -ForegroundColor Yellow
}
elseif ($existingJson -and -not $Force) {
    Write-Host "  [artifact] '$OutputPath' exists with different content - not overwritten. Pass -Force to reconcile it to this config (this is expected the first time you switch from the base scenario's serialNumber-only output to this superset)." -ForegroundColor Red
    exit 1
}
else {
    $isOverwrite = [bool]$existingJson
    $action = if ($isOverwrite) { 'reconcile (overwrite)' } else { 'create' }
    if ($PSCmdlet.ShouldProcess($OutputPath, "$action device control policy JSON")) {
        $outDir = Split-Path -Parent $OutputPath
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        Set-Content -LiteralPath $OutputPath -Value $newJson -NoNewline -Encoding utf8
        $verbPast = if ($isOverwrite) { 'reconciled (overwritten)' } else { 'created' }
        Write-Host "  [artifact] $verbPast '$OutputPath'" -ForegroundColor Green
    }
    else {
        Write-Host "  [artifact] WhatIf - would $action '$OutputPath'" -ForegroundColor DarkYellow
    }
}

# --- Optional local schema validation via mdatp CLI ---
if ($ValidateWithMdatp) {
    if (-not (Get-Command mdatp -ErrorAction SilentlyContinue)) {
        Write-Warning "mdatp CLI not found - skipping local schema validation. Run this on an already-onboarded Mac's Terminal to validate before pasting into JAMF Pro."
    }
    elseif (-not (Test-Path -LiteralPath $OutputPath)) {
        Write-Warning "Nothing to validate - '$OutputPath' was not written this run (WhatIf, or unchanged)."
    }
    elseif ($PSCmdlet.ShouldProcess($OutputPath, 'mdatp device-control policy validate --path')) {
        Write-Host "`n  [mdatp] Validating schema: mdatp device-control policy validate --path $OutputPath" -ForegroundColor Cyan
        & mdatp device-control policy validate --path $OutputPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [mdatp] Schema validation reported a non-zero exit code ($LASTEXITCODE) - fix the JSON before pasting it into JAMF Pro." -ForegroundColor Red
            exit 1
        }
        Write-Host "  [mdatp] Schema validation passed." -ForegroundColor Green
    }
}

Write-Host "`nDone. This artifact is not yet enforcing anything - it must still be pasted into the JAMF Pro 'Device Control Policy' property and scoped to a pilot Computer Group by hand (base scenario's README.md Section 5, Steps 3-4; no Microsoft-documented API performs this step). Run validate/Test-JamfVendorProductDeviceAllowlistPolicyJson.ps1 to re-check the local artifact's structure at any time." -ForegroundColor Cyan
```