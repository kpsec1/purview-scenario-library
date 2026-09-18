---
part: "deploy"
parent: "dlp/defender-device-control-usb-allowlist-macos-jamf"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/mac-device-control-usb-allowlist-jamf.sample.json`

```json
{
  "policyDisplayName": "Device Control (macOS, JAMF) - USB Removable Media Default-Deny Allowlist",
  "policyDescription": "Denies all removable USB storage on JAMF-managed macOS endpoints by default; allows only IT-issued, identity-verified backup drives listed in approvedDevices (matched by serial number). Deployed by scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf. Owner: Security & Compliance team.",
  "approvedDevices": [
    {
      "label": "IT Data Custodians - encrypted backup drive #1",
      "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER"
    },
    {
      "label": "IT Data Custodians - encrypted backup drive #2",
      "serialNumber": "REPLACE_WITH_REAL_SERIAL_NUMBER_2"
    }
  ],
  "notificationUrl": "",
  "jamfComputerGroupName": "REPLACE_WITH_PILOT_JAMF_COMPUTER_GROUP_NAME"
}
```

#### `New-JamfDeviceControlPolicyJson.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Generates (and, optionally, locally schema-validates) the device control policy JSON artifact
    for JAMF-managed macOS endpoints - the "Device Control (macOS, JAMF) - USB Removable Media
    Default-Deny Allowlist" control.

.DESCRIPTION
    This is the JAMF-managed deployment path sibling of
    scenarios/dlp/defender-device-control-usb-allowlist-macos/ (Intune-managed). Both scenarios
    enforce the identical policy - one named allowlist group (ApprovedBackupDrives, matched by
    serialNumber) gets full read/write/execute; every other removable-storage device is denied,
    both paths audited - because macOS Device Control's groups/rules/settings JSON schema is the
    same regardless of which MDM delivers it. Only the delivery mechanism differs:

      - Intune sibling: the JSON is embedded inside a .mobileconfig payload and pushed via the
        Microsoft Graph macOSCustomConfiguration resource - a documented, API-automatable path.
      - This script (JAMF path): Microsoft's own JAMF procedure has NO documented API for setting
        the JAMF Pro "Device Control Policy" custom-schema property - it is a JAMF-console-only,
        copy/paste-the-JSON-into-a-text-box step (mac-device-control-jamf Step 4). No verified JAMF
        Pro REST API request body for populating a Custom-Schema-sourced Application & Custom
        Settings property was found during this build's grounding pass (developer.jamf.com was
        unreachable in this build environment). Rather than fabricate that API call, this script
        automates the two steps Microsoft DOES document as scriptable/CLI-driven (mac-device-
        control-jamf Steps 1-2: author the JSON, then validate it with the mdatp CLI) and leaves
        the JAMF-console paste step to the documented manual procedure in README.md Section 5.

    What this script does:
      1. Reads -ConfigPath (approvedDevices list) and generates the device control policy JSON -
         groups (AllRemovableStorage catch-all + ApprovedBackupDrives), rules (Allow-
         ApprovedBackupDrives / Deny-AllOtherRemovableStorage, both audited), and settings
         (removableMedia enforcement enabled, defaultEnforcement = deny). Byte-for-byte the same
         policy shape as the Intune sibling's embedded JSON (same fixed group/rule GUIDs too, so a
         hybrid Intune+JAMF fleet can run one identical policy identity across both MDM tools).
      2. Writes the JSON to -OutputPath as a plain, pretty-printed .json file - ready to copy/paste
         into the JAMF Pro "Device Control Policy" property (README.md Section 5, Step 4).
      3. With -ValidateWithMdatp, shells out to the Microsoft-documented local validator
         (`mdatp device-control policy validate --path <OutputPath>`) and surfaces its result. This
         requires running the script ON an already-onboarded Mac with the mdatp CLI available - it
         is not a remote/API check, and is skipped (not failed) with a warning if mdatp is not
         found, since this script is otherwise cross-platform PowerShell 7.

    Idempotent: re-running with an unchanged config produces byte-identical JSON; if -OutputPath
    already contains that exact content, the script reports no change and writes nothing. If the
    existing file's content differs, the script requires -Force to overwrite it (never silently
    clobbers a hand-edited or already-pasted-elsewhere file).

    PREREQUISITES this script does not perform (README.md Section 3, Section 5) - identical
    boundary to the Intune sibling, plus the JAMF-console steps this script's output feeds into:
      - Target Macs must already be onboarded to Microsoft Defender for Endpoint via JAMF, running
        Defender for Endpoint on macOS version 101.91.92 or later.
      - A Full Disk Access (PPPC) profile granting com.microsoft.dlp.daemon Full Disk Access must
        already be deployed via JAMF (fulldisk.mobileconfig / mac-jamfpro-policies Step 6) - device
        control cannot enforce without it.
      - The Defender for Endpoint preferences schema (schema.json) in the JAMF Pro "MDE Preferences"
        custom-schema profile must include the Device Control property set and the
        Data Loss Prevention (DLP) > Features > DC_in_dlp = enabled toggle - both configured through
        the JAMF Pro GUI, not by this script (README.md Section 5, Steps 3-4).
      - Pasting this script's output JSON into the JAMF Pro "Device Control Policy" property and
        scoping the profile to a pilot Computer Group - a manual JAMF-console step with no
        Microsoft-documented API (README.md Section 5, Step 4; design.md Section 3).

.PARAMETER ConfigPath
    Path to the JSON config (approvedDevices list). Defaults to the sibling
    'config/mac-device-control-usb-allowlist-jamf.sample.json' - copy and edit it, do not deploy
    the sample values as-is. jamfComputerGroupName is informational only (documents which JAMF
    Computer Group the operator scopes the profile to by hand) - this script never calls the JAMF
    Pro API, so it has no effect on the generated JSON.

.PARAMETER OutputPath
    Where to write the generated device control policy JSON. Defaults to
    'output/jamf-device-control-policy.json' next to this script.

.PARAMETER ValidateWithMdatp
    After writing the file, run `mdatp device-control policy validate --path <OutputPath>` (the
    Microsoft-documented local schema validator). Requires running this script on an onboarded Mac
    with the mdatp CLI present; skipped with a warning (not a hard failure) if mdatp is not found,
    since a policy-authoring workstation is frequently not itself an onboarded endpoint.

.PARAMETER Force
    If -OutputPath already exists with different content, overwrite it. Without -Force, an existing
    file with different content is left untouched and the script exits non-zero.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports what would be written (and, with
    -ValidateWithMdatp, what would be validated) without writing or shelling out to mdatp.

.EXAMPLE
    ./New-JamfDeviceControlPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -WhatIf

    Dry-run: shows exactly what would be written, changes nothing.

.EXAMPLE
    ./New-JamfDeviceControlPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -OutputPath ./output/my-tenant-device-control-policy.json

    Generates the JSON artifact ready to paste into JAMF Pro (README.md Section 5, Step 4).

.EXAMPLE
    # Run on an onboarded Mac's Terminal, from a pwsh session:
    ./New-JamfDeviceControlPolicyJson.ps1 -ConfigPath ./config/my-tenant.json -ValidateWithMdatp

    Generates the JSON, then locally schema-validates it with the mdatp CLI before you paste it
    into JAMF Pro.

.NOTES
    SCOPE: matches approved devices by serialNumber only, not vendorId/productId - same rationale
    and same deferred follow-up as the Intune sibling (design.md Section 5 there, restated in this
    scenario's own design.md Section 4).

    Sources (Microsoft Learn, verify before production use):
    - Deploy and manage Device Control using JAMF (Steps 1-4: author JSON, validate with mdatp,
      update the Defender for Endpoint preferences schema, add the Device Control Policy property):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-jamf
    - Device Control for macOS (policy model: settings/groups/rules/entries, query/clause schema;
      "Prepare your endpoints" - Full Disk Access for com.microsoft.dlp.daemon, DC_in_dlp via
      Data Loss Prevention (DLP) > Features, minimum product version 101.91.92; `mdatp version`):
      https://learn.microsoft.com/defender-endpoint/mac-device-control-overview
    - Device control policies in Microsoft Defender for Endpoint (shared groups/rules/entries
      concepts across Windows and macOS; the Mac JSON policy tab):
      https://learn.microsoft.com/defender-endpoint/device-control-policies
    - Set up the Microsoft Defender for Endpoint on macOS policies in Jamf Pro (Step 3b: Preference
      Domain must be exactly com.microsoft.wdav; Step 6: Full Disk Access PPPC profile procedure):
      https://learn.microsoft.com/defender-endpoint/mac-jamfpro-policies
    - Onboard and offboard macOS devices into Purview solutions using Jamf Pro for Microsoft
      Defender for Endpoint customers (fulldisk.mobileconfig / schema.json update procedure via the
      JAMF Pro console):
      https://learn.microsoft.com/purview/device-onboarding-offboarding-macos-jamfpro-mde
    - scenarios/dlp/defender-device-control-usb-allowlist-macos/ - the Intune sibling this policy
      JSON is generated identically to (same groups/rules/settings shape, same fixed GUIDs).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/mac-device-control-usb-allowlist-jamf.sample.json'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output/jamf-device-control-policy.json'),

    [Parameter()]
    [switch]$ValidateWithMdatp,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Fixed, source-controlled GUIDs - identical to the Intune sibling's constants (design.md Section
# 4) so a hybrid Intune+JAMF Mac fleet can run one identical policy identity across both MDM tools.
$script:AllRemovableGroupId = '11111111-aaaa-4bbb-8ccc-111111111111'
$script:ApprovedGroupId = '22222222-bbbb-4ccc-8ddd-222222222222'
$script:AllowRuleId = '33333333-cccc-4ddd-8eee-333333333333'
$script:DenyRuleId = '44444444-dddd-4eee-8fff-444444444444'

function Get-DeviceControlPolicyJson {
    param([Parameter(Mandatory)]$Config)

    if (-not $Config.approvedDevices -or @($Config.approvedDevices).Count -eq 0) {
        throw "approvedDevices must contain at least one entry with a serialNumber."
    }
    $serialClauses = foreach ($d in $Config.approvedDevices) {
        if (-not $d.serialNumber) { throw "Every approvedDevices entry requires serialNumber (label: '$($d.label)')." }
        [ordered]@{ '$type' = 'serialNumber'; value = $d.serialNumber }
    }

    $policy = [ordered]@{
        groups = @(
            [ordered]@{
                '$type' = 'device'
                id      = $script:AllRemovableGroupId
                name    = 'AllRemovableStorage'
                query   = [ordered]@{
                    '$type' = 'all'
                    clauses = @([ordered]@{ '$type' = 'primaryId'; value = 'removable_media_devices' })
                }
            }
            [ordered]@{
                '$type' = 'device'
                id      = $script:ApprovedGroupId
                name    = 'ApprovedBackupDrives'
                query   = [ordered]@{
                    '$type' = 'any'
                    clauses = @($serialClauses)
                }
            }
        )
        rules = @(
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

    ($policy | ConvertTo-Json -Depth 10) + "`n"
}

# --- Load and validate config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policyDisplayName) { throw "policyDisplayName is required in the config file (used for console output/traceability only - it is not written into the JSON artifact)." }

Write-Host "JAMF-managed macOS device control USB allowlist: policy '$($cfg.policyDisplayName)'." -ForegroundColor Cyan
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
    Write-Host "  [artifact] '$OutputPath' exists with different content - not overwritten. Pass -Force to reconcile it to this config." -ForegroundColor Red
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
        Write-Warning "mdatp CLI not found - skipping local schema validation. Run this on an already-onboarded Mac's Terminal to validate before pasting into JAMF Pro (README.md Section 5, Step 2)."
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

Write-Host "`nDone. This artifact is not yet enforcing anything - it must still be pasted into the JAMF Pro 'Device Control Policy' property and scoped to a pilot Computer Group by hand (README.md Section 5, Steps 3-4; no Microsoft-documented API performs this step). Run validate/Test-JamfDeviceControlPolicyJson.ps1 to re-check the local artifact's structure at any time." -ForegroundColor Cyan
```