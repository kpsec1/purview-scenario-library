#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Identity.Governance'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Reports'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Closes the role-assignable-group blind spot disclosed in Export-EntraPrivilegedRoleAuditTrail.ps1
    (design.md Section 4b, reviews.md Red Team finding 1): discovers which role-assignable groups
    currently hold one of the four monitored roles, then exports a rolling audit trail of
    membership changes (Add/Remove member to/from group) for exactly that discovered group set.

.DESCRIPTION
    Export-EntraPrivilegedRoleAuditTrail.ps1's category eq 'RoleManagement' filter is structurally
    blind to a legitimate, Microsoft-recommended pattern: assigning Global Administrator/Compliance
    Administrator/Compliance Data Administrator/Security Administrator to an Entra ID P1/P2
    role-assignable group instead of to individual users. Adding a member to such a group grants the
    role but is logged as a GroupManagement-category "Add member to group" event - a completely
    different category, invisible to the sibling script's filter (see this scenario's design.md
    Section 4b and README.md Section 11 for the full disclosure).

    This script closes that gap in two phases, run together on every invocation (no cached state, so
    the monitored group set is always current - a group added or removed from a monitored role
    between runs is picked up automatically):

    PHASE 1 - Discovery (read-only, always re-run, never assumed from a prior run):
      1. List every role-assignable group in the tenant: Get-MgGroup -Filter "isAssignableToRole eq
         true" -All. This exact eq-operator filter is Microsoft's own documented worked example for
         this property and works WITHOUT the ConsistencyLevel:eventual/$count advanced-query headers
         (Microsoft's "Advanced query capabilities" guidance states eq filters work by default,
         unlike ne/not/endswith on this resource - see .NOTES source 8).
      2. For each of the four monitored role display names, resolve its role definition Id
         (Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq '<role>'") and list its
         active role assignments (Get-MgRoleManagementDirectoryRoleAssignment -Filter
         "roleDefinitionId eq '<id>'" -All) - both documented, worked-example filter shapes (.NOTES
         source 4/5).
      3. Cross-reference (client-side): any role-assignable group whose Id appears as a PrincipalId
         in one of those role assignments is a "monitored group" for Phase 2.

    PHASE 2 - Audit export (the same rolling-CSV pattern as the sibling script):
      For the monitored group set discovered in Phase 1, query the Entra directory audit log
      (Get-MgAuditLogDirectoryAudit) for GroupManagement-category events in the search window, using
      the SAME grounded category+date-range server-side filter shape the sibling script already uses
      (design.md Section 4 there). Narrows client-side to "Add member to group"/"Remove member from
      group" events (plus the two bulk-import/remove variants - see below) whose targetResources
      array contains a Group-typed entry matching one of the monitored group Ids - a shape directly
      confirmed by Microsoft's own worked Get-EntraAuditDirectoryLog example (.NOTES source 6) for
      the two single-member activities, which is also the first confirmation in this scenario that a
      GroupManagement targetResources entry carries a stable "id" (not just displayName) - a
      materially stronger match key than the sibling script had available for its own Role-typed
      targets.

      As of this revision, $monitoredActivities also includes "Bulk import group members - finished
      (bulk)" and "Bulk remove group members - finished (bulk)" - confirmed as real, distinct
      GroupManagement-category activity names by a direct fetch of Microsoft's own
      reference-audit-activities source page (.NOTES source 7/12), closing the "not monitored at
      all" half of reviews.md round 2 Red Team finding 3. Whether these two activities' records carry
      the same Group-typed-plus-User-typed targetResources shape as the confirmed single-member
      activities is NOT independently confirmed by a Microsoft worked example - the extraction
      functions below fail soft (skip the record) rather than assume, so this remains a disclosed,
      not-yet-pilot-tenant-verified residual gap rather than a silently-guessed fix (README.md
      Section 11, AGENTS.md Section 4).

    Each output row carries the discovered RoleDisplayName the group held AT DISCOVERY TIME (this
    run), so the CSV is self-documenting about why each group was in scope - not just that a
    membership change happened. PrincipalDisplayName may contain more than one semicolon-separated
    name on a single row for a bulk import/remove event that affects multiple members at once (see
    Get-PrincipalDisplayNameFromTargetResources) - a single-member Add/Remove event always yields
    exactly one name, unchanged from before this revision.

    Idempotency: de-duplicates on the record's own documented Id (GUID), identical to the sibling
    script (design.md Section 5) - the same API, same documented stable-Id guarantee.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-MgGraph yourself first, then call this script. Read-only: it never creates, modifies, or
    deletes any Entra object (group, role assignment, or otherwise) - the only side effect is the CSV
    file this script writes, gated behind $PSCmdlet.ShouldProcess() so -WhatIf reports the records
    that would be merged (and the discovered group set) without touching disk.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Defaults to 24 hours before -EndDate - same
    reasoning as the sibling script: the underlying Entra directory audit log's own retention is as
    short as 7 days on Microsoft Entra ID Free, so a daily run is the safe minimum cadence.

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER PrivilegedRoleDisplayNames
    The Entra built-in role display names whose role-assignable-group holders are discovered and
    monitored. Defaults to the same four roles as the sibling script (rbac-model.md Section 3):
    Global Administrator, Compliance Administrator, Compliance Data Administrator, Security
    Administrator. Keep this in sync with -PrivilegedRoleDisplayNames on
    Export-EntraPrivilegedRoleAuditTrail.ps1 if you customize it there.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    ActivityDateTime.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Discovery (Phase 1) and the audit-log query (Phase 2)
    still execute (read-only; needed to report accurate would-be results), but the CSV file is not
    written - the script prints the discovered monitored-group set and the count of new,
    non-duplicate records it would have merged.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Export-RoleAssignableGroupMembershipAuditTrail.ps1 -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv' -WhatIf

    Dry run: discovers the current monitored group set, queries the last 24 hours, and reports how
    many new records would be merged. Writes nothing.

.EXAMPLE
    ./Export-RoleAssignableGroupMembershipAuditTrail.ps1 -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv'

    Deploys (merges) the last 24 hours of monitored-group membership-change events into the rolling
    CSV. Safe to schedule daily alongside Export-EntraPrivilegedRoleAuditTrail.ps1 - overlapping
    windows never produce duplicate rows (Id-based de-duplication).

.EXAMPLE
    ./Export-RoleAssignableGroupMembershipAuditTrail.ps1 -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) `
        -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv'

    A one-time backfill covering the full Microsoft Entra ID P1/P2 default retention window. On
    Microsoft Entra ID Free, the real backfill ceiling is 7 days regardless of what -StartDate
    requests.

.NOTES
    If Phase 1 discovers zero role-assignable groups holding any of the four monitored roles, that is
    the healthy, expected state for most tenants (role-assignable groups are an opt-in pattern) - the
    script still runs Phase 2 with an empty group set (which trivially yields zero matched records)
    rather than skipping it, so a tenant that starts using this pattern later is picked up on the very
    next scheduled run with no configuration change needed.

    VERIFY (pilot tenant): this script cross-references ACTIVE role assignments
    (unifiedRoleAssignment, i.e. Get-MgRoleManagementDirectoryRoleAssignment's output) against
    role-assignable groups - it does not distinguish a tenant-wide assignment from one scoped to an
    administrative unit (directoryScopeId), and does not separately handle a role-assignable group
    that itself holds the role only through Privileged Identity Management (PIM) group-eligibility
    (activated-but-time-bound access) rather than a permanent assignment - unifiedRoleAssignment
    reflects currently-active assignments by either mechanism, so a PIM-activated group assignment IS
    included in Phase 1's discovery for as long as it's active, but this script does not alert
    separately when that activation starts or ends (that's PIM's own audit trail, out of scope here
    per the sibling script's design.md Section 9 Non-goals, which this companion inherits).

    VERIFY (pilot tenant or a future Microsoft Learn pass): whether a "Remove member from group"
    event's targetResources array is guaranteed to carry the same Group/User-typed entry pair
    Microsoft's own worked example confirms for "Add member to group" specifically (source 6 below) -
    this script assumes symmetry (both activities use the same targetResources shape) but no worked
    example for the Remove variant specifically was found during this build. The extraction function
    fails soft (empty column) rather than assuming, consistent with the sibling script's own handling
    of its unconfirmed Role-target array position.

    VERIFY (pilot tenant or a future Microsoft Learn pass): whether "Bulk import group members -
    finished (bulk)"/"Bulk remove group members - finished (bulk)" records carry a Group-typed
    targetResources entry (this script's match key) at all, and if so whether they carry one
    User-typed entry per affected member or some other shape (e.g. a count-only summary with no
    per-member detail). Source 12 below (direct fetch of Microsoft's reference-audit-activities.md)
    confirms both activity names and their GroupManagement category, but the source page does not
    document targetResources contents for these two specifically, and source 6's worked example
    covers only the singular "Add member to group" activity. Until confirmed, a bulk import/remove
    that doesn't match this script's Group-typed-entry assumption is silently skipped (fails soft,
    per Get-GroupTargetFromTargetResources above) rather than raising a false record - meaning a
    bulk-added privileged-group member could still go undetected by this script even after this
    revision, if the real shape turns out to differ. README.md Section 11 discloses this explicitly
    rather than claiming the gap is fully closed.

    THROTTLING: all three Graph resources this script calls (groups, roleManagement/directory, and
    auditLogs/directoryAudits) are called through Microsoft Graph PowerShell SDK cmdlets, which
    implement automatic retry with exponential backoff honoring the Retry-After header - no custom
    429-handling needed, consistent with the sibling script.

    Sources (Microsoft Learn, verify before production use):
    1. Use Microsoft Entra groups to manage role assignments (role-assignable groups; membership
       governance is expected at the group level): https://learn.microsoft.com/entra/identity/role-based-access-control/groups-concept
    2. IMicrosoftGraphGroup.IsAssignableToRole property (confirms $filter support: eq, ne, not):
       https://learn.microsoft.com/dotnet/api/microsoft.azure.powershell.cmdlets.resources.msgraph.models.apiv10.imicrosoftgraphgroup.isassignabletorole
    3. List Microsoft Entra role assignments (worked PowerShell example: Get-MgRoleManagementDirectoryRoleAssignment
       -Filter "PrincipalId eq '<group id>'" to list role assignments for a group; and
       Get-MgRoleManagementDirectoryRoleDefinition + "roleDefinitionId eq" to list by role):
       https://learn.microsoft.com/entra/identity/role-based-access-control/view-assignments
    4. Get-MgRoleManagementDirectoryRoleAssignment reference (Application permissions, least to most
       privileged: RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory,
       RoleManagement.Read.All, Directory.ReadWrite.All, Directory.Read.All):
       https://learn.microsoft.com/powershell/module/microsoft.graph.identity.governance/get-mgrolemanagementdirectoryroleassignment
    5. List unifiedRoleAssignments (worked filter examples: roleDefinitionId eq, principalId eq):
       https://learn.microsoft.com/graph/api/rbacapplication-list-roleassignments
    6. Get-EntraAuditDirectoryLog reference, Example 9 (worked -Filter combining activityDisplayName
       eq 'Add member to group' with targetResources/any(r:r/type eq 'User') and
       targetResources/any(r:r/id eq '<groupId>' and r/type eq 'Group') - confirms the Group-typed
       targetResources entry carries a stable id property):
       https://learn.microsoft.com/powershell/module/microsoft.entra.reports/get-entraauditdirectorylog
    7. Microsoft Entra audit log categories and activities (Core Directory GroupManagement category:
       "Add member to group" / "Remove member from group"):
       https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities
    8. Advanced query capabilities on Microsoft Entra ID objects (eq filters work by default without
       ConsistencyLevel/$count; ne/not/endswith require them):
       https://learn.microsoft.com/graph/aad-advanced-queries
    9. Use the $filter query parameter (worked example: ~/groups?$filter=isAssignableToRole eq true):
       https://learn.microsoft.com/graph/filter-query-parameter
    10. Get-MgGroup reference (Application permissions table lists Group.Read.All directly - the
        cmdlet this script actually calls, not just the underlying REST resource):
        https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggroup
    11. directoryAudit resource type / targetResource resource type (shared with the sibling script):
        https://learn.microsoft.com/graph/api/resources/directoryaudit
        https://learn.microsoft.com/graph/api/resources/targetresource
    12. Microsoft Entra audit log activity reference - GroupManagement category, Microsoft Entra
        (AAD) Management UX audit source (confirms "Bulk import group members - finished (bulk)" and
        "Bulk remove group members - finished (bulk)" as distinct, real activity names; does not
        document their targetResources shape - see the VERIFY note above). Fetched directly from the
        docs source (learn.microsoft.com returned EGRESS_BLOCKED in this build environment) at
        https://raw.githubusercontent.com/MicrosoftDocs/entra-docs/main/docs/identity/monitoring-health/reference-audit-activities.md
        - rendered page: https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities
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
    if (-not (Get-Command Get-MgAuditLogDirectoryAudit -ErrorAction SilentlyContinue)) {
        throw 'No Microsoft Graph PowerShell SDK session found. Run Connect-MgGraph first. The connecting identity/app needs the AuditLog.Read.All, Group.Read.All, and RoleManagement.Read.Directory Graph application permissions - see README.md Section 3.'
    }
}

Assert-GraphSession

# ============================================================================
# PHASE 1 - Discovery: which role-assignable groups currently hold one of the
# monitored roles? Always re-run, never cached, so a group added to or removed
# from a monitored role between runs is picked up automatically (design.md
# Section 4b / this script's own new design section).
# ============================================================================

Write-Host "Phase 1: discovering role-assignable groups..." -ForegroundColor Cyan
# eq filter on isAssignableToRole works by default - no ConsistencyLevel/$count needed (.NOTES
# source 8/9). -All pages through the full result set (max 500 role-assignable groups per tenant).
$roleAssignableGroups = @(Get-MgGroup -Filter "isAssignableToRole eq true" -All -Property Id, DisplayName)
Write-Host "Found $($roleAssignableGroups.Count) role-assignable group(s) in the tenant." -ForegroundColor Cyan

$monitoredGroups = @{}   # GroupId -> [pscustomobject]@{ GroupId; GroupDisplayName; RoleDisplayName }

if ($roleAssignableGroups.Count -gt 0) {
    $roleAssignableGroupIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($roleAssignableGroups.Id))

    foreach ($roleName in $PrivilegedRoleDisplayNames) {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq '$roleName'" | Select-Object -First 1
        if (-not $roleDefinition) {
            Write-Warning "No role definition found for '$roleName' - skipping (check the role display name is spelled exactly as it appears in the Entra admin center)."
            continue
        }

        $assignments = @(Get-MgRoleManagementDirectoryRoleAssignment -Filter "roleDefinitionId eq '$($roleDefinition.Id)'" -All)
        foreach ($assignment in $assignments) {
            if ($roleAssignableGroupIds.Contains($assignment.PrincipalId)) {
                $group = $roleAssignableGroups | Where-Object { $_.Id -eq $assignment.PrincipalId } | Select-Object -First 1
                if (-not $monitoredGroups.ContainsKey($group.Id)) {
                    $monitoredGroups[$group.Id] = [pscustomobject]@{
                        GroupId         = $group.Id
                        GroupDisplayName = $group.DisplayName
                        RoleDisplayName = $roleName
                    }
                    Write-Warning "Monitored group discovered: '$($group.DisplayName)' ($($group.Id)) holds '$roleName' via role-assignable-group assignment. Its own membership changes are now in scope for this run."
                }
            }
        }
    }
}

Write-Host "Phase 1 complete: $($monitoredGroups.Count) group(s) in scope for this run." -ForegroundColor Green

# ============================================================================
# PHASE 2 - Audit export: GroupManagement-category membership-change events
# for exactly the monitored group set discovered above.
# ============================================================================

$monitoredActivities = @(
    'Add member to group',
    'Remove member from group',
    # Confirmed as real, distinct GroupManagement-category activity names via a direct fetch of
    # Microsoft's own reference-audit-activities source (.NOTES source 7/12) - NOT the same
    # activity as the two single-member ones above (closes reviews.md round 2 Red Team finding 3's
    # "not monitored at all" gap). The targetResources shape for these two specifically (does a
    # Group-typed entry plus one-or-more User-typed entries appear, matching the singular events'
    # confirmed shape?) is still not confirmed by a Microsoft worked example - see the VERIFY note
    # below and README.md Section 11. Included here rather than left out entirely: the fail-soft
    # extraction functions below skip any record that doesn't carry a matching Group-typed target,
    # so adding these names can only gain coverage, never fabricate a false match.
    'Bulk import group members - finished (bulk)',
    'Bulk remove group members - finished (bulk)'
)

function Get-GroupTargetFromTargetResources {
    # Group-typed target's Id/DisplayName - confirmed present on "Add member to group" events by
    # Microsoft's own worked Get-EntraAuditDirectoryLog example (.NOTES source 6). Filters by .Type
    # rather than assuming array position, consistent with the sibling script's own approach. Not
    # independently confirmed for the two bulk activities above - fails soft ($null) rather than
    # assuming if no Group-typed entry is present, so an unconfirmed/different bulk shape is safely
    # skipped (disclosed residual gap) instead of silently mismatched.
    param([Parameter(Mandatory)][AllowNull()]$TargetResources)
    return @($TargetResources) | Where-Object { $_.Type -eq 'Group' } | Select-Object -First 1
}

function Get-PrincipalDisplayNameFromTargetResources {
    # The User-typed target(s) on a membership-change event are the affected member(s). Collects
    # EVERY User-typed entry (not just the first) and joins them, rather than assuming exactly one -
    # a single-member "Add/Remove member to/from group" event has exactly one, so this is unchanged
    # for that case, but a "Bulk import/remove group members" event may legitimately carry more than
    # one User-typed target per record (unconfirmed either way - no Microsoft worked example was
    # found for the bulk activities' record shape). Falls back to $null (empty CSV column) rather
    # than assuming presence - README.md Section 11.
    param([Parameter(Mandatory)][AllowNull()]$TargetResources)
    $userTargets = @($TargetResources) | Where-Object { $_.Type -eq 'User' }
    if ($userTargets.Count -gt 0) {
        $names = $userTargets | ForEach-Object { if ($_.UserPrincipalName) { $_.UserPrincipalName } else { $_.DisplayName } }
        return ($names -join '; ')
    }
    return $null
}

function Get-InitiatorDisplayName {
    param([Parameter(Mandatory)][AllowNull()]$InitiatedBy)
    if ($InitiatedBy.User.UserPrincipalName) { return $InitiatedBy.User.UserPrincipalName }
    if ($InitiatedBy.App.DisplayName) { return "$($InitiatedBy.App.DisplayName) (app)" }
    return $null
}

$newRows = @()

if ($monitoredGroups.Count -gt 0) {
    $startIso = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $endIso = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    # Same grounded server-side filter shape as the sibling script: category + date range only
    # (design.md Section 4 there). activityDisplayName and the specific group match happen
    # client-side below, same discipline.
    $filter = "category eq 'GroupManagement' and activityDateTime ge $startIso and activityDateTime le $endIso"

    Write-Host "Phase 2: searching Entra directory audit log for GroupManagement category events between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan
    $candidateRecords = @(Get-MgAuditLogDirectoryAudit -Filter $filter -All)
    Write-Host "Found $($candidateRecords.Count) GroupManagement-category record(s) in the search window; narrowing to monitored groups..." -ForegroundColor Cyan

    $matchedRecords = @($candidateRecords | Where-Object {
        if ($_.ActivityDisplayName -notin $monitoredActivities) { return $false }
        # Fails soft (no match) rather than throwing if a record's targetResources has no
        # Group-typed entry at all - defensive against a malformed/unexpected record shape,
        # consistent with the sibling script's own fail-soft extraction functions.
        $groupTarget = Get-GroupTargetFromTargetResources -TargetResources $_.TargetResources
        return ($null -ne $groupTarget) -and $monitoredGroups.ContainsKey($groupTarget.Id)
    })

    Write-Host "$($matchedRecords.Count) matching monitored-group membership-change record(s)." -ForegroundColor Green

    $newRows = foreach ($record in $matchedRecords) {
        $groupTarget = Get-GroupTargetFromTargetResources -TargetResources $record.TargetResources
        $monitored = $monitoredGroups[$groupTarget.Id]
        [pscustomobject]@{
            Id                    = $record.Id
            ActivityDateTime      = $record.ActivityDateTime
            ActivityDisplayName   = $record.ActivityDisplayName
            GroupId               = $groupTarget.Id
            GroupDisplayName      = $monitored.GroupDisplayName
            RoleDisplayName       = $monitored.RoleDisplayName
            PrincipalDisplayName  = (Get-PrincipalDisplayNameFromTargetResources -TargetResources $record.TargetResources)
            InitiatedBy           = (Get-InitiatorDisplayName -InitiatedBy $record.InitiatedBy)
            Result                = $record.Result
            ResultReason          = $record.ResultReason
            CorrelationId         = $record.CorrelationId
        }
    }
}
else {
    Write-Host "Phase 2 skipped: no role-assignable group currently holds a monitored role - nothing to query." -ForegroundColor Yellow
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
        Write-Warning "Monitored-group membership change detected: $($row.ActivityDisplayName) '$($row.PrincipalDisplayName)' on group '$($row.GroupDisplayName)' (holds '$($row.RoleDisplayName)'), initiated by $($row.InitiatedBy) at $($row.ActivityDateTime). Confirm this matches an expected onboarding/offboarding/access-review event - see README.md Section 8."
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
