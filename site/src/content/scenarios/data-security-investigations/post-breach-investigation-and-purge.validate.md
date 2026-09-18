---
part: "validate"
parent: "data-security-investigations/post-breach-investigation-and-purge"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DsiRoleGroupAssignments.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Read-only readiness check: confirms the three dedicated Data Security Investigations (DSI)
    role groups exist, that their membership matches a config, that at least one user has
    administrative access, and that unified audit logging is enabled (a prerequisite for
    Export-DsiActivityAuditTrail.ps1).

.DESCRIPTION
    Never modifies tenant state. Checks:
      1. Each of the three DSI role groups (Admins/Investigators/Reviewers) is readable via
         Get-RoleGroupMember - a failure here means DSI setup (README.md Section 5, Step 2) has
         not been completed in this tenant, not that the role group was deleted (these are
         Microsoft-managed role groups; this script never creates or deletes them).
      2. Every member listed in the config for a role group is actually a current member
         (catches New-DsiRoleGroupAssignments.ps1 drift, or a manual portal change that diverged
         from the declared config).
      3. The Admins role group has at least one member - Microsoft explicitly warns against a
         "zero administrator" state (README.md Section 3).
      4. Unified audit logging is enabled for the org (Get-AdminAuditLogConfig
         -UnifiedAuditLogIngestionEnabled) - without it, Export-DsiActivityAuditTrail.ps1 (and the
         DSI activity logging Microsoft documents as automatic) has nothing to read.

    This does NOT validate anything about DSI itself - whether billing/AI capacity is configured,
    whether an investigation exists, or whether purge is functioning - because none of those has a
    documented API this library found to check against (README.md Section 7/Section 11). Those are
    portal-only checks: the Purview portal's Data Security Investigations > Overview page shows
    setup-task completion status directly.

.PARAMETER ConfigPath
    Path to the role-assignment JSON config to validate against. Defaults to
    '../deploy/policy/dsi-role-assignments.sample.json'.

.EXAMPLE
    Connect-IPPSSession -UserPrincipalName admin@contoso.com
    Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
    ./Test-DsiRoleGroupAssignments.ps1 -ConfigPath ../deploy/policy/dsi-role-assignments.json

.NOTES
    Requires both a Security & Compliance PowerShell session (Connect-IPPSSession, for
    Get-RoleGroupMember against these role groups) and an Exchange Online PowerShell session
    (Connect-ExchangeOnline, for Get-AdminAuditLogConfig) - see docs/automation-surface.md
    Section 1. Both cmdlets ship in the same ExchangeOnlineManagement module; only the connection
    endpoint differs.

    Sources (Microsoft Learn, verify before production use):
    - Assign permissions in Data Security Investigations (the three role group names, the "always
      have at least one Admins member" guidance):
      https://learn.microsoft.com/purview/data-security-investigations-permissions
    - Turn auditing on or off (Get-AdminAuditLogConfig, UnifiedAuditLogIngestionEnabled):
      https://learn.microsoft.com/purview/audit-log-enable-disable
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/policy/dsi-role-assignments.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

$dsiRoleGroups = @(
    'Data Security Investigations Admins'
    'Data Security Investigations Investigators'
    'Data Security Investigations Reviewers'
)

Test-Check -Description "Config file exists ($ConfigPath)" -Condition (Test-Path -LiteralPath $ConfigPath)
if (-not (Test-Path -LiteralPath $ConfigPath)) { Write-Host "`nCannot continue without a config file." -ForegroundColor Red; exit 1 }
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

# --- 1-3. Role group readability, membership drift, zero-admin check ---
if (-not (Get-Command Get-RoleGroupMember -ErrorAction SilentlyContinue)) {
    Write-Host "`nNo Security & Compliance PowerShell session found - run Connect-IPPSSession first." -ForegroundColor Red
    exit 1
}

foreach ($groupName in $dsiRoleGroups) {
    $desiredMembers = @()
    if ($config.roleGroups.PSObject.Properties.Name -contains $groupName) {
        $desiredMembers = @($config.roleGroups.$groupName)
    }

    try {
        $existing = @(Get-RoleGroupMember -Identity $groupName -ErrorAction Stop)
        Test-Check -Description "Role group '$groupName' is readable" -Condition $true
    }
    catch {
        Test-Check -Description "Role group '$groupName' is readable (error: $($_.Exception.Message))" -Condition $false
        continue
    }

    $existingNames = @($existing | ForEach-Object { $_.Name })
    $missing = @($desiredMembers | Where-Object { $_ -notin $existingNames })
    Test-Check -Description "'$groupName' membership matches config ($($existingNames.Count) current, $($desiredMembers.Count) desired)" -Condition ($missing.Count -eq 0)
    foreach ($m in $missing) {
        Write-Host "    missing: $m (run New-DsiRoleGroupAssignments.ps1 to reconcile)" -ForegroundColor Yellow
    }

    if ($groupName -eq 'Data Security Investigations Admins') {
        Test-Check -Description "'$groupName' has at least one member (avoids a 'zero administrator' state)" -Condition ($existingNames.Count -gt 0)
    }
}

# --- 4. Unified audit logging enabled (prerequisite for Export-DsiActivityAuditTrail.ps1) ---
if (Get-Command Get-AdminAuditLogConfig -ErrorAction SilentlyContinue) {
    try {
        $auditConfig = Get-AdminAuditLogConfig
        Test-Check -Description "Unified audit logging is enabled (required for Export-DsiActivityAuditTrail.ps1 and DSI's own activity logging)" -Condition ([bool]$auditConfig.UnifiedAuditLogIngestionEnabled)
    }
    catch {
        Test-Check -Description "Read unified audit logging config (error: $($_.Exception.Message))" -Condition $false
    }
}
else {
    Test-Check -Description "Exchange Online PowerShell session available to check unified audit logging (run Connect-ExchangeOnline)" -Condition $false -Warn
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
Write-Host "Reminder: this script cannot validate DSI billing/AI-capacity setup, investigation state, or purge outcomes - no documented API exists for those (README.md Section 7/Section 11). Confirm those in the Purview portal's Data Security Investigations > Overview and Usage dashboard pages." -ForegroundColor DarkGray
if ($script:failures -gt 0) { exit 1 }
```