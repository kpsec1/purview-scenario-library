---
part: "deploy"
parent: "data-security-investigations/post-breach-investigation-and-purge"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-DsiActivityAuditTrail.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Data Security Investigations (DSI) activity from the unified
    audit log - investigation creation/deletion, search/scope changes, AI analysis jobs, mitigation
    plan changes, and (most sensitive) purge jobs - for SIEM ingestion and post-incident evidence.

.DESCRIPTION
    Like this library's other portal-only-workflow scenarios (design.md Section 2), Data Security
    Investigations has no write API this repo's deploy scripts could target - investigation
    creation, search, AI analysis, and purge are all Microsoft Purview portal actions. The one part
    of DSI reachable through a documented, scriptable surface is its own footprint in the unified
    audit log: Microsoft's "Audit log activities" reference documents 28 distinct DSI Operations
    (design.md Section 4), retrievable via Search-UnifiedAuditLog (automation surface 1 per
    docs/automation-surface.md Section 1) using -Operations - the same surface, same pattern, as
    this library's other audit-trail scripts (e.g.
    communication-compliance/harassment-and-code-of-conduct/deploy/
    Export-CommunicationComplianceAuditTrail.ps1).

    This script queries by -Operations only, WITHOUT -RecordType: Microsoft's audit-log-activities
    reference lists the 28 DSI Operation names and friendly descriptions but does not state the
    RecordType enum value that carries them (VERIFY - README.md Section 11). Search-UnifiedAuditLog
    does not require -RecordType when -Operations is supplied, so this avoids inventing an
    unconfirmed RecordType value (AGENTS.md Section 4) while still returning every DSI record.

    Idempotency model: identical to Export-CommunicationComplianceAuditTrail.ps1 - accumulates a
    rolling history, merging newly-fetched records into an existing CSV and de-duplicating by a
    composite key of (CreationDate, Operations, UserIds, a stable hash of the AuditData JSON
    payload), so a scheduled run with an overlapping date window never produces duplicate rows
    (design.md Section 8).

    Author-only reference code. Never establishes its own tenant connection - run
    Connect-ExchangeOnline yourself first, then call this script. Read-only against the tenant: the
    only side effect is the CSV file this script writes, gated behind $PSCmdlet.ShouldProcess() so
    -WhatIf reports what would be merged without touching disk.

    This script does NOT read investigation content, mitigation-plan item details, or purge query
    results - Search-UnifiedAuditLog's AuditData JSON for these Operations is scoped to who did
    what to which investigation/job, not the sensitive data the investigation itself examined. See
    README.md Section 11.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Defaults to 7 days before -EndDate, suitable for a
    daily/weekly scheduled run with deliberate overlap (idempotent de-duplication makes overlap
    safe).

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    CreationDate.

.PARAMETER NdjsonOutDir
    Optional. When supplied, every new (non-duplicate) record merged this run is ALSO written as
    newline-delimited JSON to '<NdjsonOutDir>/DSI-Activity-<runStamp>.ndjson' - one file per run,
    the same per-run-file convention scenarios/audit/streaming-to-sentinel-or-management-api's
    Invoke-ManagementActivityPoll.ps1 already uses for its own Path B '<contentType>-<runStamp>.ndjson'
    exports (README.md Section 6/Section 8). Point this at that scenario's own -OutDir (e.g. './out')
    to land DSI activity in the same directory a downstream forwarder is already watching, without
    building a second forwarder. 'DSI-Activity' (hyphenated) is this repo's own label, NOT a real
    Office 365 Management Activity API content type - Data Security Investigations audit records
    never pass through that API (they come from Search-UnifiedAuditLog directly); see README.md
    Section 8 and design.md Section 6. Omit this parameter to keep using this script exactly as
    before - the CSV output alone is unaffected either way.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size. Defaults to 5000 (the cmdlet's documented
    per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Search-UnifiedAuditLog query still executes
    (read-only; needed to report accurate would-be results), but the CSV file is not written.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-DsiActivityAuditTrail.ps1 -OutputCsvPath './out/dsi-audit-trail.csv' -WhatIf

    Dry run: queries the last 7 days of DSI activity and reports how many new records would be
    merged, writes nothing.

.EXAMPLE
    ./Export-DsiActivityAuditTrail.ps1 -OutputCsvPath './out/dsi-audit-trail.csv'

    Merges the last 7 days of DSI activity into the rolling CSV. Safe to schedule daily.

.EXAMPLE
    ./Export-DsiActivityAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/dsi-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window before the
    first scheduled recurring run (README.md Section 11).

.EXAMPLE
    ./Export-DsiActivityAuditTrail.ps1 -OutputCsvPath './out/dsi-audit-trail.csv' -NdjsonOutDir '../../../audit/streaming-to-sentinel-or-management-api/out'

    Merges the rolling CSV as usual, AND writes this run's new records as NDJSON into the audit
    streaming scenario's own Path B output directory - README.md Section 8.

.NOTES
    Every DSIPurgeStarted record is flagged with a console warning as this script runs - see
    README.md Section 8 for why purge starts are this scenario's single highest-priority Blue Team
    signal (it is the one DSI action that can permanently and irreversibly delete tenant data).

    VERIFY - the RecordType enum value for DSI records is not stated in Microsoft's own reference
    (see .DESCRIPTION); this script relies on -Operations alone. If a future Microsoft Learn
    revision documents the RecordType, add it as an additional filter for defense in depth.

    -NdjsonOutDir writes the exact same fields as the CSV (CreationDate/Operation/UserIds/
    RecordType/AuditData), just re-shaped: AuditData is parsed from its JSON string into a nested
    object (falling back to the raw string if parsing fails) so the NDJSON record is full-fidelity
    JSON rather than a CSV cell holding escaped JSON text - the same shape
    Invoke-ManagementActivityPoll.ps1 already produces for its own content-blob records. Only
    $rowsToAdd (already de-duplicated against the CSV) is ever written, so a scheduled run with an
    overlapping date window never produces duplicate NDJSON records either.

    Sources (Microsoft Learn, verify before production use):
    - Audit log activities - Data Security Investigations activities table (the 28 Operation values
      this script's -Operations list is built from verbatim):
      https://learn.microsoft.com/purview/audit-log-activities#data-security-investigations-activities
    - Learn about Data Security Investigations - Unified audit log integration (activity logging
      is automatic, no opt-in/configuration step):
      https://learn.microsoft.com/purview/data-security-investigations#integration-with-other-microsoft-platforms-and-solutions
    - Search-UnifiedAuditLog reference (-StartDate/-EndDate/-Operations/-ResultSize/
      -SessionCommand):
      https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Manage audit log retention policies (180-day Standard default, 1-year E5 default for
      Entra/Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies):
      https://learn.microsoft.com/purview/audit-log-retention-policies
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [datetime]$StartDate = ([datetime]::UtcNow.AddDays(-7)),

    [Parameter()]
    [datetime]$EndDate = ([datetime]::UtcNow),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputCsvPath,

    [Parameter()]
    [string]$NdjsonOutDir,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int]$ResultSize = 5000
)

$ErrorActionPreference = 'Stop'

function Assert-ExoSession {
    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - see rbac-model.md Section 6.'
    }
}

Assert-ExoSession

# All 28 DSI Operations documented in Microsoft's audit-log-activities reference (design.md
# Section 4), reproduced verbatim rather than a guessed subset.
$dsiOperations = @(
    'CreatedDSIInvestigation'
    'DeletedDSIInvestigation'
    'UpdatedDSIInvestigation'
    'GetDSIInvestigation'
    'DSIInvestigationListViewed'
    'DSIInvestigationSettingsViewed'
    'DSIInvestigationSettingsUpdated'
    'DSIInvestigationSettingsDefaultViewed'
    'DSIInvestigationMembersUpdated'
    'DSIInvestigationCreatedFromXDR'
    'DSIInvestigationCreatedFromIRM'
    'DSIPurviewSearchAdded'
    'DSIPurviewSearchUpdated'
    'GetSearchDSIInvestigation'
    'DSIPurviewSearchUploadFile'
    'DSIPurviewSearchAddToEvidenceSetJobSubmitted'
    'DSIPurviewSearchSampleJobSubmitted'
    'DSISampleResultsViewed'
    'DSISampleStatusViewed'
    'DSISampleViewCancelled'
    'DSIPurviewSearchStatisticsJobSubmitted'
    'DSIStatisticsResultsViewed'
    'DSIStatisticsViewCancelled'
    'DSIEvidenceSetViewed'
    'DSIEvidenceSetDocumentViewed'
    'DSIInvestigationVectorizationJobSubmitted'
    'DSIVectorSearchStarted'
    'DSIInvestigationCategorizationJobSubmitted'
    'DSIProbeJobSubmitted'
    'DSIProbeJobResultsViewed'
    'DSIActivitiesViewed'
    'DSISingleActivityViewed'
    'DSIItemAddedToMitigation'
    'DSIItemRemovedFromMitigation'
    'DSIItemViewedFromMitigation'
    'DSIMitigationPlanListViewed'
    'DSIMitigationItemStatusUpdated'
    'DSIPurgeStarted'
    'DSIAIFeedbackProvided'
    'DSICapacityViewed'
    'DSICapacityUpdated'
    'DSICapacityDeleted'
)

function Get-StableStringHash {
    # A deterministic, cross-session-stable hash (unlike .NET's [string]::GetHashCode(), which is
    # randomized per process) - folds a full AuditData JSON payload into a fixed-width key
    # component for de-duplication. Never used for anything security-sensitive.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $hashBytes = $md5.ComputeHash($bytes)
    }
    finally {
        $md5.Dispose()
    }
    return [System.BitConverter]::ToString($hashBytes).Replace('-', '')
}

function Get-CompositeKey {
    param([Parameter(Mandatory)]$Record)
    # CreationDate + Operations + UserIds are confirmed top-level Search-UnifiedAuditLog output
    # properties; no flat unique-ID property is confirmed present on every DSI record, so a hash of
    # the full AuditData JSON is folded in as the fourth uniqueness component (same approach as
    # Export-CommunicationComplianceAuditTrail.ps1 - AGENTS.md Section 4's no-invented-fields rule).
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

Write-Host "Searching unified audit log for $($dsiOperations.Count) Data Security Investigations Operations between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

$allRecords = [System.Collections.Generic.List[object]]::new()
$sessionId = "dsi-audit-trail-$([guid]::NewGuid())"
do {
    $page = @(Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate -Operations $dsiOperations `
            -ResultSize $ResultSize -SessionId $sessionId -SessionCommand ReturnLargeSet)
    if ($page.Count -gt 0) { $allRecords.AddRange($page) }
} while ($page.Count -gt 0)

Write-Host "Found $($allRecords.Count) matching record(s)." -ForegroundColor Green

$newRows = foreach ($record in $allRecords) {
    [pscustomobject]@{
        CreationDate = $record.CreationDate
        Operation    = $record.Operations
        UserIds      = $record.UserIds
        RecordType   = $record.RecordType
        AuditData    = $record.AuditData
        CompositeKey = (Get-CompositeKey -Record $record)
    }
}

# --- Merge into the existing CSV, de-duplicating by CompositeKey ---
$existingRows = @()
if (Test-Path -Path $OutputCsvPath -PathType Leaf) {
    $existingRows = @(Import-Csv -Path $OutputCsvPath)
}

$existingKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]($existingRows | ForEach-Object { $_.CompositeKey }))
$rowsToAdd = @($newRows | Where-Object { -not $existingKeys.Contains($_.CompositeKey) })

Write-Host "$($rowsToAdd.Count) new, non-duplicate record(s) to merge (of $($newRows.Count) fetched)." -ForegroundColor Cyan

$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$mergeDescription = "Merge $($rowsToAdd.Count) new record(s) into '$OutputCsvPath'"
if ($NdjsonOutDir) {
    $mergeDescription += " and write them as NDJSON to '$NdjsonOutDir'"
}

if ($rowsToAdd.Count -eq 0) {
    Write-Host "Nothing to merge - CSV already up to date for this window." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object CreationDate | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Audit trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green

    if ($NdjsonOutDir) {
        if (-not (Test-Path -LiteralPath $NdjsonOutDir)) { New-Item -ItemType Directory -Path $NdjsonOutDir -Force | Out-Null }
        $ndjsonFile = Join-Path $NdjsonOutDir "DSI-Activity-$runStamp.ndjson"
        foreach ($row in $rowsToAdd) {
            $auditDataObj = $row.AuditData
            try { $auditDataObj = $row.AuditData | ConvertFrom-Json -ErrorAction Stop } catch { }
            [pscustomobject]@{
                CreationDate = $row.CreationDate
                Operation    = $row.Operation
                UserIds      = $row.UserIds
                RecordType   = $row.RecordType
                AuditData    = $auditDataObj
            } | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $ndjsonFile -Encoding utf8
        }
        Write-Host "NDJSON companion feed written: $ndjsonFile ($($rowsToAdd.Count) record(s)) - see scenarios/audit/streaming-to-sentinel-or-management-api/README.md Section 8." -ForegroundColor Green
    }

    $purgeRows = @($rowsToAdd | Where-Object { $_.Operation -eq 'DSIPurgeStarted' })
    foreach ($row in $purgeRows) {
        Write-Warning "PURGE STARTED: $($row.UserIds) at $($row.CreationDate) - review this event immediately. Purge can permanently and irreversibly delete tenant data (README.md Section 6/Section 8/Section 11)."
    }

    $investigationCreatedRows = @($rowsToAdd | Where-Object { $_.Operation -in @('CreatedDSIInvestigation', 'DSIInvestigationCreatedFromXDR', 'DSIInvestigationCreatedFromIRM') })
    if ($investigationCreatedRows.Count -gt 0) {
        Write-Host "$($investigationCreatedRows.Count) new investigation(s) created this run - confirm each is a recognized, in-progress incident (README.md Section 8)." -ForegroundColor Cyan
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
```

#### `New-DsiRoleGroupAssignments.ps1`

```powershell
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
```

#### `policy/dsi-role-assignments.sample.json`

```json
{
  "$schema": "https://learn.microsoft.com/purview/data-security-investigations-permissions",
  "_comment": "Desired-state membership for the three dedicated Data Security Investigations role groups. Replace every placeholder UPN with real, mail-enabled user or mail-enabled security group identities from the buyer's tenant before running New-DsiRoleGroupAssignments.ps1. Never commit real identities into this file - copy it out of source control first. Role group names, capabilities, and the four auto-included role groups (Compliance Administrator, Organization Management, Data Security Management, Insider Risk Management) are documented in README.md Section 3 and Section 6 - do not rename these three role group strings, they must match the exact Purview role group names.",
  "roleGroups": {
    "Data Security Investigations Admins": [
      "dsi-admin-1@contoso.example"
    ],
    "Data Security Investigations Investigators": [
      "dsi-investigator-1@contoso.example",
      "dsi-investigator-2@contoso.example"
    ],
    "Data Security Investigations Reviewers": [
      "dsi-reviewer-1@contoso.example"
    ]
  }
}
```

#### `policy/empty-role-assignments.json`

```json
{
  "_comment": "Used with New-DsiRoleGroupAssignments.ps1 -RemoveExtraMembers to reconcile every dedicated DSI role group to empty membership - see rollback.md Section 1. Edit the arrays to leave specific members in place instead of removing everyone.",
  "roleGroups": {
    "Data Security Investigations Admins": [],
    "Data Security Investigations Investigators": [],
    "Data Security Investigations Reviewers": []
  }
}
```