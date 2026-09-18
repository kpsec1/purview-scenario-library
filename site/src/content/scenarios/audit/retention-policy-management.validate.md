---
part: "validate"
parent: "audit/retention-policy-management"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-AuditRetentionPolicy.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Confirms the live tenant's audit log retention policies match a config file, and that the
    tenant-wide constraints (unique priority, 50-policy cap) still hold. Read-only.

.DESCRIPTION
    For each policy in the config:
      - Confirms it exists live.
      - Confirms RetentionDuration, Priority, Description, RecordTypes, Operations, and UserIds
        all match.
    Then, across the whole tenant (not just config entries):
      - Confirms no two live policies share a Priority.
      - Warns if the live policy count is within 5 of the documented 50-policy cap.

    Exits non-zero on any hard failure (safe for a CI-style pre-flight/drift check).

.PARAMETER ConfigPath
    Path to the same JSON config New-AuditRetentionPolicy.ps1 used.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./validate/Test-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json

.NOTES
    Grounded against Get-UnifiedAuditLogRetentionPolicy (the cmdlet never returns the tenant's
    default policy - confirmed in "Manage audit log retention policies",
    learn.microsoft.com/purview/audit-log-retention-policies) and the same New-/Set-
    UnifiedAuditLogRetentionPolicy references cited in deploy/New-AuditRetentionPolicy.ps1's
    .NOTES, fetched during this build, 2026-09-04.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$failures = 0
$warnings = 0

function Get-NormalizedArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object)
}

function Test-ArraysEqual {
    param([string[]]$Left, [string[]]$Right)
    $l = Get-NormalizedArray $Left
    $r = Get-NormalizedArray $Right
    if ($l.Count -ne $r.Count) { return $false }
    for ($i = 0; $i -lt $l.Count; $i++) {
        if ($l[$i] -ne $r[$i]) { return $false }
    }
    return $true
}

try {
    $livePolicies = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop)
}
catch {
    Write-Error "Get-UnifiedAuditLogRetentionPolicy failed - confirm Security & Compliance " +
        "PowerShell is connected (Connect-IPPSSession) and the account holds the Organization " +
        "Configuration role (e.g. via the Compliance Data Administrator role group). $_"
    exit 1
}
Write-Host "[INFO] Tenant has $($livePolicies.Count) custom audit log retention polic(y/ies) " +
    "(default policy excluded from this count)."

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

foreach ($p in $config.policies) {
    $live = $livePolicies | Where-Object { $_.Name -eq $p.name } | Select-Object -First 1
    if (-not $live) {
        Write-Host "[FAIL] '$($p.name)' does not exist in the tenant."
        $failures++
        continue
    }

    $mismatches = @()
    if ($live.RetentionDuration -ne $p.retentionDuration) {
        $mismatches += "RetentionDuration: live='$($live.RetentionDuration)' expected='$($p.retentionDuration)'"
    }
    if ($live.Priority -ne [int]$p.priority) {
        $mismatches += "Priority: live=$($live.Priority) expected=$($p.priority)"
    }
    if ([string]$live.Description -ne [string]$p.description) {
        $mismatches += "Description differs"
    }
    if (-not (Test-ArraysEqual -Left $live.RecordTypes -Right (Get-NormalizedArray $p.recordTypes))) {
        $mismatches += "RecordTypes: live=[$($live.RecordTypes -join ', ')] expected=[$($p.recordTypes -join ', ')]"
    }
    if (-not (Test-ArraysEqual -Left $live.Operations -Right (Get-NormalizedArray $p.operations))) {
        $mismatches += "Operations: live=[$($live.Operations -join ', ')] expected=[$($p.operations -join ', ')]"
    }
    if (-not (Test-ArraysEqual -Left $live.UserIds -Right (Get-NormalizedArray $p.userIds))) {
        $mismatches += "UserIds: live=[$($live.UserIds -join ', ')] expected=[$($p.userIds -join ', ')]"
    }

    if ($mismatches.Count -eq 0) {
        Write-Host "[PASS] '$($p.name)' matches config."
    }
    else {
        Write-Host "[FAIL] '$($p.name)' drifted from config: $($mismatches -join '; ')"
        $failures++
    }
}

# Tenant-wide priority-uniqueness check (across ALL live policies, not just config entries)
$priorityGroups = $livePolicies | Group-Object -Property Priority | Where-Object { $_.Count -gt 1 }
if ($priorityGroups) {
    foreach ($group in $priorityGroups) {
        $names = ($group.Group | Select-Object -ExpandProperty Name) -join ', '
        Write-Host "[FAIL] Priority $($group.Name) is shared by multiple live policies: $names"
        $failures++
    }
}
else {
    Write-Host "[PASS] No priority collisions among $($livePolicies.Count) live polic(y/ies)."
}

# Cap headroom warning
$remaining = 50 - $livePolicies.Count
if ($remaining -le 5) {
    Write-Host "[WARN] Only $remaining polic(y/ies) of headroom remain before the documented 50-policy cap."
    $warnings++
}
else {
    Write-Host "[PASS] $remaining polic(y/ies) of headroom remain before the 50-policy cap."
}

Write-Host ''
Write-Host "Summary: $failures failure(s), $warnings warning(s)."
if ($failures -gt 0) { exit 1 }
exit 0
```