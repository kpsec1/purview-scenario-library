#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Reports'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of direct (non-PIM) Microsoft Entra ID role-assignment changes
    for the four Entra roles that grant Compliance Manager Administration-equivalent access
    implicitly, closing the blind spot Search-UnifiedAuditLog cannot see (design.md Section 2).

.DESCRIPTION
    scenarios/compliance-manager/assess-against-iso27001's own Red Team review found a gap: its
    Export-ComplianceManagerAuditTrail.ps1 only catches an EXPLICIT, Compliance-Manager-scoped
    ComplianceManagerRolesChange event. A user who instead holds Global Administrator, Compliance
    Administrator, Compliance Data Administrator, or Security Administrator gets Administration-
    equivalent Compliance Manager access IMPLICITLY through that Entra ID role - and per Microsoft's
    own documentation, doesn't even appear on the Compliance Manager User access settings page (see
    that scenario's README.md Section 11 and this scenario's design.md Section 2). This script closes
    that specific gap by monitoring the Entra directory audit log directly for changes to those four
    roles - not just for Compliance Manager, but for every other module in this library whose
    rbac-model.md Section 3 mapping lists the same four roles as carrying implicit Purview access.

    Surface: Microsoft Graph PowerShell SDK (automation surface 3 per docs/automation-surface.md
    Section 1), via Get-MgAuditLogDirectoryAudit against /auditLogs/directoryAudits - Microsoft
    Entra ID's OWN audit log, a genuinely separate log from the Microsoft 365 unified audit log
    Search-UnifiedAuditLog reads (see design.md Section 2 for why these are two different systems
    with two different retention models).

    Scope (grounded, not guessed - design.md Section 3): this script queries the Core Directory
    RoleManagement category's six DIRECT-ASSIGNMENT activities - "Add member to role"/"Remove
    member from role" and their two scoped variants each (Administrative-Unit-restricted, and the
    separately-named "scoped member" form) - filtered client-side to targetResources entries of
    type "Role" whose displayName matches one of the four monitored role names
    (-PrivilegedRoleDisplayNames, parameterized, defaults to the four roles rbac-model.md Section 3
    documents). It ALSO monitors the PIM-service RoleManagement activity "Add member to role
    outside of PIM (permanent)" - Microsoft's own canonical audit-activities reference lists this as
    a distinct, separately-named activity from plain "Add member to role" (2026-09-27 grounding,
    design.md Section 4a; formerly an open VERIFY). It does NOT cover the rest of Privileged
    Identity Management (PIM)'s eligible/time-bound activation family, which logs under a different,
    much larger set of activity names (e.g. "Add member to role in PIM completed
    (permanent/timebound)") - see design.md Section 3 Non-goals and README.md Section 11 for why that
    family is out of scope for this fragment rather than guessed at.

    Idempotency model: unlike Export-ComplianceManagerAuditTrail.ps1 (which has no confirmed stable
    unique-ID field on its Search-UnifiedAuditLog output and falls back to a composite hash), the
    Microsoft Graph directoryAudit resource DOES document a stable "id" property ("Indicates the
    unique ID for the activity. This is a GUID.") - so this script de-duplicates on that Id directly
    on every merge into the rolling CSV. See design.md Section 6 for this contrast.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-MgGraph yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only: it never creates, modifies, or deletes any Entra object - the only side
    effect is the CSV file this script writes, gated behind $PSCmdlet.ShouldProcess() so -WhatIf
    reports the records that would be merged without touching disk.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Defaults to 24 hours before -EndDate. Unlike
    Export-ComplianceManagerAuditTrail.ps1's 7-day default, this script defaults to a 1-day window
    because the underlying Entra audit log's own retention is dramatically shorter than Audit
    (Standard)'s 180 days - as little as 7 days on Microsoft Entra ID Free (README.md Section 11) -
    so a DAILY scheduled run (not weekly) is the safe minimum cadence for this script specifically.

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER PrivilegedRoleDisplayNames
    The Entra built-in role display names to monitor. Defaults to the four roles rbac-model.md
    Section 3 documents as carrying implicit Compliance Manager Administration-equivalent access:
    Global Administrator, Compliance Administrator, Compliance Data Administrator, Security
    Administrator. Parameterized (not hard-coded) so an organization can extend this to any other role this
    library's rbac-model.md maps to implicit Purview access for a different module - see README.md
    Section 6.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    ActivityDateTime.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Get-MgAuditLogDirectoryAudit query still executes
    (read-only; needed to report accurate would-be results), but the CSV file is not written - the
    script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Export-EntraPrivilegedRoleAuditTrail.ps1 -OutputCsvPath './out/entra-privileged-role-audit-trail.csv' -WhatIf

    Dry run: queries the last 24 hours and reports how many new records would be merged, writes nothing.

.EXAMPLE
    ./Export-EntraPrivilegedRoleAuditTrail.ps1 -OutputCsvPath './out/entra-privileged-role-audit-trail.csv'

    Deploys (merges) the last 24 hours of privileged-role assignment/removal events into the rolling
    CSV. Safe to schedule daily - overlapping windows never produce duplicate rows (Id-based
    de-duplication).

.EXAMPLE
    ./Export-EntraPrivilegedRoleAuditTrail.ps1 -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) `
        -OutputCsvPath './out/entra-privileged-role-audit-trail.csv'

    A one-time backfill covering the full Microsoft Entra ID P1/P2 default retention window
    (README.md Section 11) before the first scheduled recurring run. On Microsoft Entra ID Free,
    the real backfill ceiling is 7 days regardless of what -StartDate requests - the query simply
    returns nothing for the unavailable portion.

.NOTES
    VERIFY before relying on this beyond the tenant's actual Entra audit-log retention: 7 days on
    Microsoft Entra ID Free, 30 days on P1/P2 (README.md Section 11) - run this script daily from
    day one if the evidentiary window this scenario needs exceeds that retention, rather than
    relying on a single historical pull. A tenant with Microsoft Purview Audit (Premium) can
    alternatively rely on that product's own 1-year default retention for the AzureActiveDirectory
    workload (README.md Section 10) instead of this script's own CSV accumulation, but Purview
    Audit does not expose these events through Search-UnifiedAuditLog with a documented Entra-
    specific -RecordType/-Operations filter as clean as this script's Graph-native one - see
    design.md Section 2.

    VERIFY (pilot tenant): the exact targetResources array shape for "Add member to role"/"Remove
    member from role" events - Microsoft's targetResource resource-type reference documents type
    can be "Role" or "User" with a displayName property on each, but no worked JSON example for
    this specific activity confirms array ordering or that both entries are always present. This
    script does not assume ordering - it filters the full array by .Type at each step - but does
    assume at least one "Role"-typed entry exists on a matching row (README.md Section 11).

    RESOLVED 2026-09-27 (Microsoft Learn pass): Microsoft's own "Security operations for privileged
    accounts" guidance recommends detecting roles assigned outside PIM by filtering the audit log to
    Service=PIM, Category=Role management, Activity type="Add member to role (permanent)". A direct
    fetch of Microsoft's canonical "Microsoft Entra audit log categories and activities" reference
    confirms this is shorthand for that page's own "Add member to role outside of PIM (permanent)"
    activity, listed under the Privileged Identity Management (PIM) service's RoleManagement
    category - a separately-named, separately-documented activity from the plain "Add member to
    role" this script otherwise filters on, which is listed only under the Core Directory service's
    own RoleManagement category. They are confirmed to be two genuinely distinct audit activities,
    not one event under two display conventions, so $monitoredActivities below now includes both.
    See design.md Section 4a (updated in place; the "two readings" discrepancy this section
    previously carried as open is resolved to reading (b) - a genuinely distinct event) and README.md
    Section 11.

    THROTTLING: Get-MgAuditLogDirectoryAudit is a Microsoft Graph PowerShell SDK cmdlet, which
    implements automatic retry with exponential backoff honoring the Retry-After header for
    non-batched requests (docs/automation-surface.md Section 5) - this script does not implement its
    own 429-handling because it never drops to a raw Invoke-MgGraphRequest call.

    Sources (Microsoft Learn, verify before production use):
    - directoryAudit resource type (activityDisplayName, category, id, targetResources, initiatedBy
      properties): https://learn.microsoft.com/graph/api/resources/directoryaudit
    - targetResource resource type (type/displayName/id on each target,
      including "Role"): https://learn.microsoft.com/graph/api/resources/targetresource
    - List directoryAudits (permissions AuditLog.Read.All least-privileged; $filter eq/ge/le/startswith):
      https://learn.microsoft.com/graph/api/directoryaudit-list
    - Get-MgAuditLogDirectoryAudit reference (-Filter/-All/-PageSize parameters, Microsoft.Graph.Reports module):
      https://learn.microsoft.com/powershell/module/microsoft.graph.reports/get-mgauditlogdirectoryaudit
    - Microsoft Entra audit log categories and activities (Core Directory RoleManagement: 6 direct-
      assignment activities headed by "Add member to role" / "Remove member from role"; PIM
      RoleManagement: "Add member to role outside of PIM (permanent)", confirmed by direct fetch
      2026-09-27 to be listed separately from the Core Directory activities above): https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities
    - Microsoft Entra data retention (7 days Free / 30 days P1-P2 for audit logs):
      https://learn.microsoft.com/entra/identity/monitoring-health/reference-reports-data-retention
    - A worked example combining `eq` and `ge` with `and` directly against /auditLogs/directoryAudits
      (grounds this script's -Filter composition): https://learn.microsoft.com/entra/identity/monitoring-health/scenario-health-conditional-access-block-policy
    - Security operations for privileged accounts in Microsoft Entra ID ("Roles assigned out of PIM"
      detection guidance citing "Add member to role (permanent)", Service=PIM - grounded above as the
      same activity as "Add member to role outside of PIM (permanent)"):
      https://learn.microsoft.com/entra/architecture/security-operations-privileged-accounts
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [datetime]$StartDate = ([datetime]::UtcNow.AddDays(-1)),

    [Parameter()]
    [datetime]$EndDate = ([datetime]::UtcNow),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$PrivilegedRoleDisplayNames = @(
        'Global Administrator',
        'Compliance Administrator',
        'Compliance Data Administrator',
        'Security Administrator'
    ),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputCsvPath
)

$ErrorActionPreference = 'Stop'

function Assert-GraphSession {
    # Get-MgAuditLogDirectoryAudit is only exported after a successful Connect-MgGraph with the
    # Microsoft.Graph.Reports submodule loaded; its absence means the caller never connected.
    if (-not (Get-Command Get-MgAuditLogDirectoryAudit -ErrorAction SilentlyContinue)) {
        throw 'No Microsoft Graph PowerShell SDK session found (Microsoft.Graph.Reports module). Run Connect-MgGraph first (see docs/automation-surface.md). The connecting identity/app needs the AuditLog.Read.All Graph application permission - see README.md Section 3.'
    }
}

Assert-GraphSession

# The first 6 are documented Core Directory / RoleManagement activities for a DIRECT (non-PIM) role
# membership change - the plain tenant-wide form plus its two scoped variants (Administrative-Unit-
# restricted assignment, and the separately-named "scoped member" form). The 7th, "Add member to
# role outside of PIM (permanent)", is a PIM-service RoleManagement activity confirmed (2026-09-27,
# see .NOTES) to be a genuinely distinct event from plain "Add member to role" - it is Microsoft's
# own detection signal for a role assigned permanently while bypassing PIM's eligible/active
# workflow in a PIM-enabled tenant; see README.md Section 11 and design.md Section 4a.
$monitoredActivities = @(
    'Add member to role',
    'Add member to role scoped over Restricted Management Administrative Unit',
    'Add scoped member to role',
    'Add member to role outside of PIM (permanent)',
    'Remove member from role',
    'Remove member from role scoped over Restricted Management Administrative Unit',
    'Remove scoped member from role'
)

function Get-RoleDisplayNameFromTargetResources {
    # Best-effort extraction of the "Role" target's displayName - the property this script filters
    # on. Not used for de-duplication (that's the record's own documented Id) - see .NOTES.
    param([Parameter(Mandatory)][AllowNull()]$TargetResources)
    $roleTarget = @($TargetResources) | Where-Object { $_.Type -eq 'Role' } | Select-Object -First 1
    return $roleTarget.DisplayName
}

function Get-PrincipalDisplayNameFromTargetResources {
    # Best-effort: the "User" target on an "Add/Remove member to/from role" event is the affected
    # principal. Falls back to $null (surfaced as an empty column) rather than assuming presence -
    # AGENTS.md Section 4's no-invented-fields rule; see README.md Section 11.
    param([Parameter(Mandatory)][AllowNull()]$TargetResources)
    $userTarget = @($TargetResources) | Where-Object { $_.Type -eq 'User' } | Select-Object -First 1
    if ($userTarget) {
        if ($userTarget.UserPrincipalName) { return $userTarget.UserPrincipalName }
        return $userTarget.DisplayName
    }
    return $null
}

function Get-InitiatorDisplayName {
    # InitiatedBy is either a user (interactive/delegated change) or an app (automation/PIM
    # completion) - both documented on auditActivityInitiator. Surfaces whichever is present.
    param([Parameter(Mandatory)][AllowNull()]$InitiatedBy)
    if ($InitiatedBy.User.UserPrincipalName) { return $InitiatedBy.User.UserPrincipalName }
    if ($InitiatedBy.App.DisplayName) { return "$($InitiatedBy.App.DisplayName) (app)" }
    return $null
}

$startIso = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$endIso = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
# Filters server-side on category + date range only (grounded combination - .NOTES source 7); the
# activityDisplayName/target-role narrowing happens client-side below rather than assuming a wider
# compound $filter (multiple eq clauses joined by 'or') is supported for this specific resource.
$filter = "category eq 'RoleManagement' and activityDateTime ge $startIso and activityDateTime le $endIso"

Write-Host "Searching Entra directory audit log for RoleManagement category events between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan
$candidateRecords = @(Get-MgAuditLogDirectoryAudit -Filter $filter -All)
Write-Host "Found $($candidateRecords.Count) RoleManagement-category record(s) in the search window; narrowing to monitored activities/roles..." -ForegroundColor Cyan

$matchedRecords = @($candidateRecords | Where-Object {
    $_.ActivityDisplayName -in $monitoredActivities -and
    (Get-RoleDisplayNameFromTargetResources -TargetResources $_.TargetResources) -in $PrivilegedRoleDisplayNames
})

Write-Host "$($matchedRecords.Count) matching privileged-role-assignment record(s)." -ForegroundColor Green

$newRows = foreach ($record in $matchedRecords) {
    [pscustomobject]@{
        Id                    = $record.Id
        ActivityDateTime      = $record.ActivityDateTime
        ActivityDisplayName   = $record.ActivityDisplayName
        RoleDisplayName       = (Get-RoleDisplayNameFromTargetResources -TargetResources $record.TargetResources)
        PrincipalDisplayName  = (Get-PrincipalDisplayNameFromTargetResources -TargetResources $record.TargetResources)
        InitiatedBy           = (Get-InitiatorDisplayName -InitiatedBy $record.InitiatedBy)
        Result                = $record.Result
        ResultReason          = $record.ResultReason
        CorrelationId         = $record.CorrelationId
    }
}

# --- Merge into the existing CSV, de-duplicating by the record's own documented Id ---
$existingRows = @()
if (Test-Path -Path $OutputCsvPath -PathType Leaf) {
    $existingRows = @(Import-Csv -Path $OutputCsvPath)
}

$existingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($existingRows | ForEach-Object { $_.Id }))
$rowsToAdd = @($newRows | Where-Object { -not $existingIds.Contains($_.Id) })

Write-Host "$($rowsToAdd.Count) new, non-duplicate record(s) to merge (of $($newRows.Count) matched)." -ForegroundColor Cyan

$mergeDescription = "Merge $($rowsToAdd.Count) new record(s) into '$OutputCsvPath'"
if ($rowsToAdd.Count -eq 0) {
    Write-Host "Nothing to merge - CSV already up to date for this window." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object ActivityDateTime | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Audit trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green

    foreach ($row in $rowsToAdd) {
        if ($row.RoleDisplayName -eq 'Global Administrator') {
            Write-Warning "GLOBAL ADMINISTRATOR role change detected: $($row.ActivityDisplayName) for $($row.PrincipalDisplayName), initiated by $($row.InitiatedBy) at $($row.ActivityDateTime). Treat as a near-zero-tolerance signal - see README.md Section 8 incident-response guidance."
        }
        else {
            Write-Warning "Privileged role change detected: $($row.ActivityDisplayName) '$($row.RoleDisplayName)' for $($row.PrincipalDisplayName), initiated by $($row.InitiatedBy) at $($row.ActivityDateTime). Confirm this matches an expected onboarding/offboarding/role-adjustment event - see README.md Section 8."
        }
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
