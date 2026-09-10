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

.NOTES
    Every DSIPurgeStarted record is flagged with a console warning as this script runs - see
    README.md Section 8 for why purge starts are this scenario's single highest-priority Blue Team
    signal (it is the one DSI action that can permanently and irreversibly delete tenant data).

    VERIFY - the RecordType enum value for DSI records is not stated in Microsoft's own reference
    (see .DESCRIPTION); this script relies on -Operations alone. If a future Microsoft Learn
    revision documents the RecordType, add it as an additional filter for defense in depth.

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

$mergeDescription = "Merge $($rowsToAdd.Count) new record(s) into '$OutputCsvPath'"
if ($rowsToAdd.Count -eq 0) {
    Write-Host "Nothing to merge - CSV already up to date for this window." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object CreationDate | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Audit trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green

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
