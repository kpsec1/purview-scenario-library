#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Idempotently reconciles membership of the three dedicated Data Security Investigations (DSI)
    role groups - Admins, Investigators, Reviewers - against a declarative JSON config.

.DESCRIPTION
    Data Security Investigations has no write API for the workflow itself (investigation creation,
    search, AI analysis, mitigation, purge are all Microsoft Purview portal-only - see design.md
    Section 2). The one part of standing DSI up that IS reachable through a documented automation
    surface is role-group membership: the three dedicated role groups this script manages are
    ordinary Security & Compliance PowerShell role groups, provisioned the same way as any other
    Purview role group (Add-RoleGroupMember/Remove-RoleGroupMember/Get-RoleGroupMember - "Manage
    role groups in Exchange Online").

    This script does NOT create the role groups (they are Microsoft-managed, built into every
    tenant once Data Security Investigations is available - see README.md Section 3) and does NOT
    touch the four role groups that carry DSI access implicitly (Compliance Administrator,
    Organization Management, Data Security Management, Insider Risk Management) - reconciling
    those would risk unintended side effects on unrelated Purview solutions those role groups also
    govern. Only the three DSI-specific role groups are in scope.

    Idempotency model: for each role group in the config, compares the current membership
    (Get-RoleGroupMember) against the desired list. Members present in the desired list but missing
    from the role group are added (Add-RoleGroupMember). Members present in the role group but
    absent from the desired list are left alone by default - pass -RemoveExtraMembers to also
    remove them (Remove-RoleGroupMember), for full declarative reconciliation. A re-run with an
    unchanged config and no drift makes zero calls beyond the read-only Get-RoleGroupMember checks.

    Author-only reference code. Never connects to a tenant itself - run Connect-IPPSSession
    yourself first (Security & Compliance PowerShell - automation surface 2 per
    docs/automation-surface.md Section 1), then call this script. The connecting identity needs
    the Role Management role (held by Organization Management / Data Security Investigations
    Admins) to modify role group membership - see README.md Section 3 and docs/rbac-model.md
    Section 13.

.PARAMETER ConfigPath
    Path to the role-assignment JSON config. Defaults to
    './policy/dsi-role-assignments.sample.json' relative to this script - copy and edit that file
    with real identities before running against a real tenant; never commit real identities into
    the sample file itself.

.PARAMETER RemoveExtraMembers
    Also remove members present in a role group but absent from that role group's list in the
    config (full declarative reconciliation). Without this switch, the script is additive-only -
    it never removes a member you didn't explicitly ask it to remove, which is the safer default
    for a role group governing purge (destructive-action) permissions.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Every Add-RoleGroupMember/Remove-RoleGroupMember
    call is gated behind $PSCmdlet.ShouldProcess() - Get-RoleGroupMember reads still execute (they
    are read-only and needed to compute the diff), but no membership changes are made.

.EXAMPLE
    Connect-IPPSSession -UserPrincipalName admin@contoso.com
    ./New-DsiRoleGroupAssignments.ps1 -ConfigPath ./policy/dsi-role-assignments.json -WhatIf

    Dry run: reports exactly which Add-RoleGroupMember (and, with -RemoveExtraMembers,
    Remove-RoleGroupMember) calls would be made, without changing anything.

.EXAMPLE
    ./New-DsiRoleGroupAssignments.ps1 -ConfigPath ./policy/dsi-role-assignments.json

    Additive reconciliation: adds any missing members from the config to each of the three role
    groups; never removes an existing member.

.EXAMPLE
    ./New-DsiRoleGroupAssignments.ps1 -ConfigPath ./policy/dsi-role-assignments.json -RemoveExtraMembers

    Full reconciliation: role-group membership after this run matches the config exactly.

.NOTES
    VERIFY (pilot tenant): role group permission changes can take up to 30 minutes to propagate to
    assigned users, per Microsoft's own documented caveat - the validate/ script re-checking
    immediately after this script runs will correctly show the new membership (Get-RoleGroupMember
    reflects the change immediately), but the *user's* access in the Purview portal may lag behind
    that read by up to 30 minutes. Don't treat a portal access failure in that window as this
    script having failed.

    Sources (Microsoft Learn, verify before production use):
    - Assign permissions in Data Security Investigations (the three role group names verbatim, the
      role-group-vs-role distinction, the four role groups with implicit DSI access, the "up to 30
      minutes to propagate" caveat, and the Role Management/Data Security Investigations Admins
      prerequisite to modify role groups from the portal):
      https://learn.microsoft.com/purview/data-security-investigations-permissions
    - Manage role groups in Exchange Online (Add-RoleGroupMember/Remove-RoleGroupMember/
      Update-RoleGroupMember/Get-RoleGroupMember syntax and semantics - the same cmdlets, reached
      via Connect-IPPSSession instead of Connect-ExchangeOnline, manage Security & Compliance
      role groups such as these):
      https://learn.microsoft.com/exchange/permissions-exo/role-groups
    - Learn about Data Security Investigations (role-based access controls as a named safety
      component - Admins/Investigators/Reviewers separation of duties):
      https://learn.microsoft.com/purview/data-security-investigations-application-card
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'policy/dsi-role-assignments.sample.json'),

    [Parameter()]
    [switch]$RemoveExtraMembers
)

$ErrorActionPreference = 'Stop'

# The three dedicated DSI role groups this script is scoped to (README.md Section 3). Any other
# key in the config's roleGroups object is rejected rather than silently touched, since the four
# implicitly-granted role groups (Compliance Administrator, Organization Management, Data Security
# Management, Insider Risk Management) are intentionally out of scope (see .DESCRIPTION).
$dsiRoleGroups = @(
    'Data Security Investigations Admins'
    'Data Security Investigations Investigators'
    'Data Security Investigations Reviewers'
)

function Assert-IppsSession {
    if (-not (Get-Command Get-RoleGroupMember -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (docs/automation-surface.md Section 1, surface 2). The connecting identity also needs the Role Management role to modify role group membership - see README.md Section 3.'
    }
}

Assert-IppsSession

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath"
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if (-not $config.roleGroups) {
    throw "Config at '$ConfigPath' has no 'roleGroups' object."
}

$configuredGroups = @($config.roleGroups.PSObject.Properties.Name)
$unknownGroups = @($configuredGroups | Where-Object { $_ -notin $dsiRoleGroups })
if ($unknownGroups.Count -gt 0) {
    throw "Config references role group(s) outside this script's scope: $($unknownGroups -join ', '). This script only manages: $($dsiRoleGroups -join ', ')."
}

$totalAdded = 0
$totalRemoved = 0

foreach ($groupName in $dsiRoleGroups) {
    $desiredMembers = @()
    if ($config.roleGroups.PSObject.Properties.Name -contains $groupName) {
        $desiredMembers = @($config.roleGroups.$groupName)
    }

    Write-Host "Reconciling role group '$groupName' ($($desiredMembers.Count) desired member(s))..." -ForegroundColor Cyan

    try {
        $existing = @(Get-RoleGroupMember -Identity $groupName -ErrorAction Stop)
    }
    catch {
        Write-Warning "Could not read role group '$groupName' - it may not exist in this tenant, or Data Security Investigations may not yet be set up (README.md Section 5, Step 2). Skipping. Error: $($_.Exception.Message)"
        continue
    }

    $existingNames = @($existing | ForEach-Object { $_.Name })
    $toAdd = @($desiredMembers | Where-Object { $_ -notin $existingNames })
    $toRemove = if ($RemoveExtraMembers) { @($existingNames | Where-Object { $_ -notin $desiredMembers }) } else { @() }

    foreach ($member in $toAdd) {
        $desc = "Add-RoleGroupMember -Identity '$groupName' -Member '$member'"
        if ($PSCmdlet.ShouldProcess($groupName, "Add member '$member'")) {
            Add-RoleGroupMember -Identity $groupName -Member $member
            Write-Host "  + Added '$member'" -ForegroundColor Green
            $totalAdded++
        }
        else {
            Write-Verbose "WhatIf: would run $desc"
        }
    }

    foreach ($member in $toRemove) {
        if ($PSCmdlet.ShouldProcess($groupName, "Remove member '$member'")) {
            Remove-RoleGroupMember -Identity $groupName -Member $member -Confirm:$false
            Write-Host "  - Removed '$member'" -ForegroundColor Yellow
            $totalRemoved++
        }
        else {
            Write-Verbose "WhatIf: would run Remove-RoleGroupMember -Identity '$groupName' -Member '$member'"
        }
    }

    if ($toAdd.Count -eq 0 -and $toRemove.Count -eq 0) {
        Write-Host "  Already reconciled - no changes." -ForegroundColor DarkGray
    }
}

Write-Host "`nDone. $totalAdded member(s) added, $totalRemoved member(s) removed." -ForegroundColor Cyan
if (-not $RemoveExtraMembers) {
    Write-Host "Ran in additive-only mode (default) - existing members outside the config were left in place. Use -RemoveExtraMembers for full reconciliation." -ForegroundColor DarkGray
}
Write-Host "Allow up to 30 minutes for permission changes to propagate to users (see .NOTES)." -ForegroundColor DarkGray
