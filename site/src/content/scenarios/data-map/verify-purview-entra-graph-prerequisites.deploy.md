---
part: "deploy"
parent: "data-map/verify-purview-entra-graph-prerequisites"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Confirm-DirectoryReadersMembership.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Confirms that every Azure SQL Managed Instance backing a Microsoft Purview Data Map source
    still has its system-assigned managed identity as a current member of the Microsoft Entra ID
    Directory Readers role, and flags any other, unexpected member of that same tenant-wide role
    as drift.

.DESCRIPTION
    scenarios/data-map/scan-azure-sql-managed-instance-and-classify/reviews.md (Blue Team finding
    1) flagged a gap: that scenario's own validate/Test-AzureSqlManagedInstanceDataMapScan.ps1
    authenticates against the Purview Data Map data-plane resource (https://purview.azure.net)
    with a Data Reader-scoped Purview role, which has no reason to also hold a directory-read
    Microsoft Graph permission - so it cannot check the one Microsoft Entra prerequisite
    (Directory Readers membership for the instance's managed identity) that scenario's own README
    Section 3 documents as required before Microsoft Entra authentication works AT ALL for that
    instance. Without it, a newly registered instance's Purview scan authenticates successfully in
    testing (if Directory Readers was granted manually during setup) but then fails silently,
    tenant-wide, for every Entra-authenticated connection to that instance - not just this scan -
    if the grant is later revoked (e.g. during an unrelated identity security review that didn't
    know this scan depended on it). This script closes that gap with a SEPARATE, purpose-built
    Microsoft Graph-permissioned checker, for every Managed-Instance-backed Purview data source in
    an inventory file, not just one.

    Surface: Microsoft Graph PowerShell SDK (automation surface 3 per docs/automation-surface.md
    Section 1), via Get-MgDirectoryRole + Get-MgDirectoryRoleMember against
    /directoryRoles and /directoryRoles/{id}/members - a genuinely different auth surface and
    permission (RoleManagement.Read.Directory) than the Purview Data Map REST API the sibling
    scenario's own scripts use.

    Two things are checked, per row of -ManagedInstanceInventoryPath:
    1. EXPECTED PRESENT: is the row's PrincipalObjectId currently a Directory Readers member?
       Missing = FAIL (the scan for that instance is at risk of failing Entra authentication).
    2. UNEXPECTED EXTRA (computed once, reported alongside every row): which current Directory
       Readers members are NOT any inventory row's PrincipalObjectId? Reported as WARN drift -
       Directory Readers is a tenant-wide-flavored role various other workloads may legitimately
       also need (README.md Section 11), so an extra member is not automatically wrong, but this
       scenario's own scan-azure-sql-managed-instance-and-classify/reviews.md flagged that nothing
       previously detected such drift at all.

    Idempotency: this script performs zero mutating Graph calls under any parameter combination -
    it only reads role/member state. The one side effect (writing -ReportPath) is gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports the same PASS/FAIL/WARN findings to the console
    without touching disk - see README.md Section 5 and AGENTS.md Section 4's dry-run requirement.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-MgGraph yourself first (see docs/automation-surface.md Section 3), then call this
    script. It never grants, revokes, or otherwise modifies Directory Readers membership - fixing
    a FAIL is a deliberate, separate, higher-privilege action left to a human Privileged Role
    Administrator (design.md Section 10 Non-goals), consistent with this repo's convention of not
    automating rare, high-privilege, one-time directory grants.

.PARAMETER ManagedInstanceInventoryPath
    Path to a CSV inventory with (at minimum) InstanceName and PrincipalObjectId columns - one row
    per Azure SQL Managed Instance that a Microsoft Purview Data Map source scans via
    scan-azure-sql-managed-instance-and-classify. Optional ResourceGroupName and
    PurviewDataSourceName columns are carried through into the report for readability only; they
    are never used to look anything up. PrincipalObjectId is the instance's managed identity
    object ID in Microsoft Entra ID - obtain it with
    (Get-AzSqlInstance -ResourceGroupName <rg> -Name <instance>).Identity.PrincipalId (see
    README.md Section 5) - this script deliberately does not call Get-AzSqlInstance itself, to
    keep its own auth surface limited to Microsoft Graph alone (design.md Section 4).

.PARAMETER ReportPath
    Optional path to write a JSON report (PASS/FAIL/WARN per row, plus the drift list) alongside
    the console output. If omitted, findings are printed to the console only and nothing is
    written to disk.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Directory Readers role/member lookup still runs
    (read-only; needed to report accurate findings), but -ReportPath is not written - the script
    prints what it would have written instead.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Confirm-DirectoryReadersMembership.ps1 -ManagedInstanceInventoryPath './managed-instances.csv' -WhatIf

    Dry run: reports every instance's PASS/FAIL and any drift, writes nothing to disk.

.EXAMPLE
    ./Confirm-DirectoryReadersMembership.ps1 -ManagedInstanceInventoryPath './managed-instances.csv' `
        -ReportPath './out/directory-readers-membership-report.json'

    Runs the check and writes the JSON report. Exits non-zero if any inventoried instance's
    managed identity is missing from Directory Readers - safe as a CI-style pre-flight gate before
    (re)enabling a recurring Data Map scan trigger for that instance.

.NOTES
    VERIFY (pilot tenant): this script assumes the Directory Readers built-in role has already
    been activated at least once in the tenant (i.e. Get-MgDirectoryRole finds it). Microsoft's own
    "List directoryRoles" reference states that operation "lists the directory roles that are
    activated in the tenant" and "only returns roles that have been activated" - a tenant that has
    NEVER granted Directory Readers to anyone (e.g. a brand-new Managed Instance registration
    before its first grant) may return zero roles matching the filter even though the role
    definition exists tenant-wide. This script treats that case as a hard FAIL for every inventory
    row with remediation text pointing at README.md Section 5, rather than silently reporting
    "0 members, nothing to check."

    VERIFY (pilot tenant): Get-MgDirectoryRoleMember returns only directoryObject IDs and
    @odata.type - resolving a "drift" member's display name calls Get-MgServicePrincipal,
    Get-MgUser, or Get-MgGroup depending on that type. A member whose underlying object was since
    deleted (a stale reference) will fail all three lookups; this script catches that and reports
    the raw ID with a "(could not resolve - possibly deleted)" label rather than throwing.

    THROTTLING: both cmdlets are Microsoft Graph PowerShell SDK cmdlets, which implement automatic
    retry with exponential backoff honoring the Retry-After header for non-batched requests
    (docs/automation-surface.md Section 5) - this script does not implement its own 429-handling.

    Sources (Microsoft Learn, verify before production use):
    - Get-MgDirectoryRole reference (Microsoft.Graph.Identity.DirectoryManagement module, -Filter
      parameter): https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgdirectoryrole
    - Get-MgDirectoryRoleMember reference (-DirectoryRoleId, -All parameters; permissions
      RoleManagement.Read.Directory least-privileged): https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgdirectoryrolemember
    - List directoryRoles (Microsoft Graph REST reference - "activated roles only" behavior this
      script's role-not-found handling relies on): https://learn.microsoft.com/graph/api/directoryrole-list
    - List members of a directory role (Microsoft Graph REST reference, RoleManagement.Read.Directory
      least-privileged permission): https://learn.microsoft.com/graph/api/directoryrole-list-members
    - Directory Readers role in Microsoft Entra ID for Azure SQL (why Managed Instance needs it):
      https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-directory-readers-role
    - Assign Directory Readers role to a Microsoft Entra group and manage role assignments
      (Managed-Instance-specific grant tutorial, cited by the sibling scenario's own README.md
      Section 12 reference 3): https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-directory-readers-role-tutorial
    - directoryRole resource type (id, displayName, roleTemplateId properties):
      https://learn.microsoft.com/graph/api/resources/directoryrole
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagedInstanceInventoryPath,

    [Parameter()]
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

function Assert-GraphSession {
    # Get-MgDirectoryRole is only exported after a successful Connect-MgGraph with the
    # Microsoft.Graph.Identity.DirectoryManagement submodule loaded; its absence means the caller
    # never connected.
    if (-not (Get-Command Get-MgDirectoryRole -ErrorAction SilentlyContinue)) {
        throw 'No Microsoft Graph PowerShell SDK session found (Microsoft.Graph.Identity.DirectoryManagement module). Run Connect-MgGraph first (see docs/automation-surface.md). The connecting identity/app needs the RoleManagement.Read.Directory Graph application permission - see README.md Section 3.'
    }
}

function Resolve-DirectoryObjectDisplayName {
    # Best-effort friendly-name resolution for a directoryObject ID of unknown type - used only for
    # the drift report, never for the pass/fail comparison itself (which is Id-based). Falls back
    # to a "(could not resolve)" label rather than throwing - see .NOTES.
    param(
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][AllowNull()][string]$ODataType
    )
    try {
        switch -Wildcard ($ODataType) {
            '*servicePrincipal' { return (Get-MgServicePrincipal -ServicePrincipalId $ObjectId -ErrorAction Stop).DisplayName }
            '*user'             { return (Get-MgUser -UserId $ObjectId -ErrorAction Stop).UserPrincipalName }
            '*group'            { return (Get-MgGroup -GroupId $ObjectId -ErrorAction Stop).DisplayName }
            default             { return "(unresolved type '$ODataType')" }
        }
    }
    catch {
        return '(could not resolve - possibly deleted)'
    }
}

Assert-GraphSession

if (-not (Test-Path -Path $ManagedInstanceInventoryPath -PathType Leaf)) {
    throw "Inventory file not found: $ManagedInstanceInventoryPath"
}

$inventory = @(Import-Csv -Path $ManagedInstanceInventoryPath)
if ($inventory.Count -eq 0) {
    throw "Inventory file '$ManagedInstanceInventoryPath' contains no data rows."
}
foreach ($requiredColumn in 'InstanceName', 'PrincipalObjectId') {
    if (-not ($inventory[0].PSObject.Properties.Name -contains $requiredColumn)) {
        throw "Inventory file is missing required column '$requiredColumn'. See README.md Section 6 for the expected CSV shape."
    }
}

Write-Host "Looking up the Directory Readers role definition..." -ForegroundColor Cyan
# List directoryRoles only returns roles ACTIVATED at least once in this tenant (Microsoft Learn
# reference cited in .NOTES) - a $null result here means Directory Readers has never been granted
# to anyone yet, not that it has zero current members. Treated as a hard failure below, not a
# silent "0 members" pass.
$directoryReadersRole = Get-MgDirectoryRole -Filter "displayName eq 'Directory Readers'"

$currentMemberIds = [System.Collections.Generic.HashSet[string]]::new()
$currentMembersById = @{}
if ($directoryReadersRole) {
    Write-Host "Found Directory Readers role (Id: $($directoryReadersRole.Id)). Listing current members..." -ForegroundColor Cyan
    $members = @(Get-MgDirectoryRoleMember -DirectoryRoleId $directoryReadersRole.Id -All)
    foreach ($member in $members) {
        [void]$currentMemberIds.Add($member.Id)
        $currentMembersById[$member.Id] = $member
    }
    Write-Host "$($members.Count) current Directory Readers member(s)." -ForegroundColor Green
}
else {
    Write-Warning "Directory Readers role has never been activated in this tenant (Get-MgDirectoryRole found no match). Every inventoried instance below is treated as FAIL - see README.md Section 5 for how to grant it the first time."
}

$results = foreach ($row in $inventory) {
    $isMember = $directoryReadersRole -and $currentMemberIds.Contains($row.PrincipalObjectId)
    [pscustomobject]@{
        InstanceName          = $row.InstanceName
        ResourceGroupName     = $row.ResourceGroupName
        PurviewDataSourceName = $row.PurviewDataSourceName
        PrincipalObjectId     = $row.PrincipalObjectId
        DirectoryReadersRoleActivated = [bool]$directoryReadersRole
        IsCurrentMember       = $isMember
        Status                = if ($isMember) { 'PASS' } else { 'FAIL' }
    }
}

Write-Host "`n=== Per-instance Directory Readers membership ===" -ForegroundColor Cyan
foreach ($result in $results) {
    $label = if ($result.ResourceGroupName) { "$($result.InstanceName) (rg: $($result.ResourceGroupName))" } else { $result.InstanceName }
    if ($result.Status -eq 'PASS') {
        Write-Host "  [PASS] $label - managed identity $($result.PrincipalObjectId) is a current Directory Readers member." -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $label - managed identity $($result.PrincipalObjectId) is NOT a current Directory Readers member. Microsoft Entra authentication to this instance - including its Purview scan - will fail. Remediate per README.md Section 5." -ForegroundColor Red
    }
}

# Drift: any current member not claimed by any inventory row. Computed once (not per-row) since
# Directory Readers is a single, shared, tenant-wide role.
$inventoryIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($inventory | ForEach-Object { $_.PrincipalObjectId }))
$driftMembers = @($currentMembersById.Values | Where-Object { -not $inventoryIds.Contains($_.Id) })

Write-Host "`n=== Membership drift (Directory Readers members not in this inventory) ===" -ForegroundColor Cyan
if ($driftMembers.Count -eq 0) {
    Write-Host "  [PASS] No unexpected Directory Readers members - current membership matches this inventory exactly." -ForegroundColor Green
}
else {
    foreach ($driftMember in $driftMembers) {
        $oDataType = $driftMember.AdditionalProperties['@odata.type']
        $displayName = Resolve-DirectoryObjectDisplayName -ObjectId $driftMember.Id -ODataType $oDataType
        Write-Host "  [WARN] Unexpected member: $displayName (Id: $($driftMember.Id), type: $oDataType). Confirm this is an authorized workload/identity that independently needs Directory Readers - see README.md Section 11." -ForegroundColor Yellow
    }
}

if ($ReportPath) {
    $report = [pscustomobject]@{
        GeneratedUtc                  = (Get-Date).ToUniversalTime().ToString('o')
        DirectoryReadersRoleActivated = [bool]$directoryReadersRole
        Instances                     = $results
        DriftMemberCount              = $driftMembers.Count
        DriftMembers                  = @($driftMembers | ForEach-Object {
            [pscustomobject]@{
                Id          = $_.Id
                ODataType   = $_.AdditionalProperties['@odata.type']
                DisplayName = Resolve-DirectoryObjectDisplayName -ObjectId $_.Id -ODataType $_.AdditionalProperties['@odata.type']
            }
        })
    }
    $reportDescription = "Write Directory Readers membership report to '$ReportPath'"
    if ($PSCmdlet.ShouldProcess($ReportPath, $reportDescription)) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportPath -Encoding utf8
        Write-Host "`nReport written: $ReportPath" -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would $reportDescription"
    }
}

$failCount = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
Write-Host "`n$failCount of $($results.Count) inventoried instance(s) FAILED the Directory Readers membership check. $($driftMembers.Count) unexpected member(s) found (drift, non-fatal)." `
    -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })

if ($failCount -gt 0) { exit 1 }
```