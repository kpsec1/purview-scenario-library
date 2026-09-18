---
part: "deploy"
parent: "records-management/disposition-proof-export"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-DispositionProofEvidence.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Builds a rolling, scriptable proof-of-disposition audit trail -- disposition review actions
    (added reviewer, approved disposal, extended retention, relabeled) and record deletions --
    complementing the Records Management "Disposition" page's manual, portal-only CSV export.

.DESCRIPTION
    The Microsoft Purview portal's Records Management > Disposition page lets a reviewer or
    administrator filter the Pending disposition / Disposed items tabs for one retention label and
    Export the result as a one-off .csv (README.md Section 5; design.md Section 2) -- the primary,
    Microsoft-documented way to produce proof of disposition. That export has no documented
    PowerShell/Graph equivalent: it is a portal button, not a cmdlet or REST call (design.md
    Section 2, item 4). This script does not attempt to reproduce it. What it scripts instead is
    the one thing Microsoft DOES document a stable automation surface for: the audit trail every
    disposition action and record deletion emits, which is the evidentiary record underneath the
    portal export.

    Three groups of Operations, matched verbatim against Microsoft's own "Audit log activities"
    reference (design.md Section 2, items 1-2):
      - Disposition review activities: AddReviewer, ApproveDisposal, ExtendRetention, RelabelItem
        -- one event per reviewer action on an item nearing or past the end of its retention
        period, including autoapproval (Microsoft states autoapproval reuses the same
        ApproveDisposal event rather than emitting a new one -- README.md Section 11).
      - File and page activities: RecordDelete ("Deleted file marked as a record") -- fires when a
        document or email marked as a record is deleted, whether via a reviewed disposition or an
        automatic regulatory-record delete with no review stage at all (the two cases the portal's
        own Disposition page distinguishes by "Type": review-based disposal vs. "Records Disposed"
        -- design.md Section 3).
      - File and page activities (context, not disposition per se): LockRecord ("Changed record
        status to locked") and UnlockRecord ("Changed record status to unlocked") -- added after
        this scenario's four-lens review (reviews.md, Red Team finding 2) flagged that a record
        must be UNLOCKED before it can be modified or deleted by a user with at least contributor
        permission. A RecordDelete with no preceding UnlockRecord in this same trail is the
        expected, in-process shape; an UnlockRecord shortly before a RecordDelete that has no
        corresponding final-stage ApproveDisposal is a pattern worth an analyst's attention
        (README.md Section 8) -- this script surfaces the raw events so that reconciliation is
        possible; it does not itself compute or alert on the pattern.

    No -RecordType filter is applied, matching this repo's existing precedent in
    scenarios/data-lifecycle-management/adaptive-protection-deleted-content-preservation/deploy/
    Export-AdaptiveProtectionPreservationEvidence.ps1 for the identical class of gap: Microsoft's
    Graph auditLogRecordType enum confirms a RecordsManagement member and a MultiStageDisposition
    member (design.md Section 2, item 3) whose names strongly suggest they cover these events, but
    no worked Search-UnifiedAuditLog example pairs either value with these specific Operations, and
    RecordDelete's own documentation says it applies to "documents and emails" while being listed
    under a SharePoint-oriented activities table -- guessing a RecordType risks silently
    under-matching real disposition evidence (AGENTS.md Section 4). Filtering by -Operations alone
    is the conservative choice.

    Idempotency model: identical to the AdaptiveProtection preservation-evidence script and to
    scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1 -- a
    rolling history accumulated across potentially-overlapping date-range calls, de-duplicated by a
    composite key of (CreationDate, Operations, UserIds, a stable hash of the full AuditData JSON
    payload). Safe to schedule daily or weekly; safe to re-run the same window twice.

    -RetentionLabelName (optional) post-filters client-side, matching on the AuditData JSON's own
    label-related properties (best-effort -- see .NOTES) so a single scheduled tenant-wide run can
    still produce a label-scoped evidence bundle for one records schedule (e.g. the "Contract
    Expiration - 7yr" label scenarios/records-management/regulatory-records-disposition/ deploys)
    without a second query.

    Author-only reference code. This script never establishes its own connection to a tenant -- run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call
    this script. Read-only against the tenant: it never creates, modifies, or deletes any content,
    label, or policy -- the only side effect is the CSV file this script writes, gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports the records that would be merged without touching
    disk.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Search-UnifiedAuditLog requires both -StartDate
    and -EndDate. Defaults to 7 days before -EndDate, suitable for a daily or weekly scheduled run
    (README.md Section 8); deliberate overlap is safe because de-duplication is idempotent.

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER RetentionLabelName
    Optional client-side filter (case-insensitive substring match against the parsed AuditData
    JSON's best-effort label-name properties -- see .NOTES). Scopes the export to one records
    schedule's evidence. Omit to keep the trail tenant-wide across every retention label.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    CreationDate.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size when not using -SessionCommand ReturnLargeSet.
    Defaults to 5000 (the cmdlet's documented per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Search-UnifiedAuditLog query still executes
    (read-only; needed to report accurate would-be results), but the CSV file is not written -- the
    script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-DispositionProofEvidence.ps1 -OutputCsvPath './out/disposition-proof.csv' -WhatIf

    Dry run: queries the last 7 days tenant-wide and reports how many new records would be merged,
    writes nothing.

.EXAMPLE
    ./Export-DispositionProofEvidence.ps1 -OutputCsvPath './out/disposition-proof.csv'

    Merges the last 7 days of disposition-review and record-deletion events, tenant-wide, into the
    rolling CSV. Safe to schedule alongside validate/Test-DispositionProofExport.ps1 per
    README.md Section 8's recommended daily or weekly cadence.

.EXAMPLE
    ./Export-DispositionProofEvidence.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -RetentionLabelName 'Contract Expiration - 7yr' -OutputCsvPath './out/contract-expiration-audit.csv'

    A targeted, 180-day (full Audit Standard retention window) pull scoped to one records schedule,
    for an examiner or auditor request against
    scenarios/records-management/regulatory-records-disposition/'s own label (README.md Section 9).

.NOTES
    VERIFY (pilot tenant): the exact AuditData JSON property name(s) that carry the retention
    label's display name for AddReviewer/ApproveDisposal/ExtendRetention/RelabelItem/RecordDelete --
    no worked Microsoft example was found during this build's grounding pass. This script inspects
    every top-level string property of the parsed AuditData object for -RetentionLabelName rather
    than asserting one property name (README.md Section 11); the raw AuditData JSON is always
    preserved in the output CSV regardless of whether the filter matches.

    VERIFY (pilot tenant): whether RecordType RecordsManagement or MultiStageDisposition (both
    confirmed members of Microsoft Graph's auditLogRecordType enum -- design.md Section 2, item 3)
    is the correct, narrower RecordType for the four Disposition review activities Operations. If
    confirmed, add -RecordType to this script's search for defense-in-depth (Operations alone
    already fully scopes the query; a confirmed RecordType would only guard against an
    Operation-name collision from an unrelated workload, which this build found no evidence of).

    VERIFY (pilot tenant): whether the ApproveDisposal record's AuditData JSON exposes a field
    that distinguishes manual approval from autoapproval. Microsoft's own documentation states only
    that "there's no new auditing event for autoapproval -- instead, use the details in the
    existing Approved disposal auditing event" without naming the field (README.md Section 11).
    This script preserves the full AuditData JSON so that field, once identified, can be extracted
    from already-collected evidence without a re-query.

    Sources (Microsoft Learn, verify before production use) -- see design.md Section References
    for the full citation list this script's design decisions are grounded in.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [datetime]$StartDate = ([datetime]::UtcNow.AddDays(-7)),

    [Parameter()]
    [datetime]$EndDate = ([datetime]::UtcNow),

    [Parameter()]
    [string]$RetentionLabelName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputCsvPath,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int]$ResultSize = 5000
)

$ErrorActionPreference = 'Stop'

function Assert-ExoSession {
    # Search-UnifiedAuditLog is only exported after a successful Connect-ExchangeOnline; its
    # absence means the caller never connected.
    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - this is a DIFFERENT role than Disposition Management, which only governs the portal Disposition page (README.md Section 3, rbac-model.md Section 6).'
    }
}

Assert-ExoSession

# All Operations documented verbatim by Microsoft's "Audit log activities" reference (design.md
# Section 2, items 1-2) - no RecordType filter (design.md Section 2, item 3 and Section 6; .NOTES
# above). LockRecord/UnlockRecord added per reviews.md Red Team finding 2 - context for a
# RecordDelete that was preceded by an unlock, not itself a disposition event.
$operations = @('AddReviewer', 'ApproveDisposal', 'ExtendRetention', 'RelabelItem', 'RecordDelete', 'LockRecord', 'UnlockRecord')

function Get-StableStringHash {
    # A deterministic, cross-session-stable hash (unlike .NET's [string]::GetHashCode(), which is
    # randomized per process by default and would silently break de-duplication across separate
    # script runs). Used only to fold a full AuditData JSON payload into a fixed-width key
    # component - never used for anything security-sensitive.
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
    # De-duplication key for the rolling merge: a real audit event is uniquely identified by when
    # it happened, what happened, and who did it. CreationDate, Operations, and UserIds are all
    # confirmed top-level Search-UnifiedAuditLog output properties. A flat, always-present
    # unique-ID property is NOT confirmed as part of that output schema for these seven Operations
    # specifically - rather than assume one exists (AGENTS.md Section 4's no-invented-fields
    # rule), this key instead folds in a hash of the full AuditData JSON payload, which IS
    # confirmed to exist on every record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

function Test-RetentionLabelMatch {
    # Best-effort, property-name-agnostic label match (see .NOTES: no confirmed property name
    # exists for the label on these Operations). Scans every top-level string value on the parsed
    # AuditData object for a case-insensitive substring match rather than asserting a schema.
    param(
        [Parameter(Mandatory)][string]$LabelName,
        [Parameter()]$AuditData
    )
    if (-not $AuditData) { return $false }
    foreach ($property in $AuditData.PSObject.Properties) {
        if ($property.Value -is [string] -and $property.Value -like "*$LabelName*") {
            return $true
        }
    }
    return $false
}

Write-Host "Searching unified audit log for disposition-review and record-deletion events (Operations=$($operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

$allRecords = [System.Collections.Generic.List[object]]::new()
$sessionId = "disposition-proof-export-$([guid]::NewGuid())"
do {
    $searchParams = @{
        StartDate      = $StartDate
        EndDate        = $EndDate
        Operations     = $operations
        ResultSize     = $ResultSize
        SessionId      = $sessionId
        SessionCommand = 'ReturnLargeSet'
    }
    # Wrapping in @() up front avoids PowerShell's single-object-vs-array ambiguity: a page that
    # returns exactly one record would otherwise come back as a scalar with no .Count property,
    # which would make the loop-continuation check below silently misbehave.
    $page = @(Search-UnifiedAuditLog @searchParams)
    if ($page.Count -gt 0) { $allRecords.AddRange($page) }
} while ($page.Count -gt 0)

Write-Host "Found $($allRecords.Count) matching record(s) in the search window." -ForegroundColor Green

# Parse each record's AuditData JSON once, up front. Only fields the general Search-UnifiedAuditLog
# audit-data schema documents as common across workloads (Workload, ObjectId, UserId) are extracted
# into their own columns - none of these are confirmed specifically for these seven Operations by a
# worked Microsoft example, so they are populated best-effort ($null if absent) rather than assumed
# mandatory. The raw AuditData JSON is always preserved in full regardless.
$parsedRecords = foreach ($record in $allRecords) {
    $auditData = $null
    try {
        $auditData = $record.AuditData | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Record with CreationDate=$($record.CreationDate) Operations=$($record.Operations) has AuditData that failed to parse as JSON - Workload/ObjectId columns will be blank for this row, but the raw AuditData is still preserved."
    }
    [pscustomobject]@{
        Record    = $record
        AuditData = $auditData
    }
}

if ($RetentionLabelName) {
    $before = $parsedRecords.Count
    $parsedRecords = @($parsedRecords | Where-Object { Test-RetentionLabelMatch -LabelName $RetentionLabelName -AuditData $_.AuditData })
    Write-Host "Filtered to RetentionLabelName '$RetentionLabelName' (best-effort AuditData scan - see .NOTES): $($parsedRecords.Count) of $before record(s) matched." -ForegroundColor Cyan
}

$newRows = foreach ($item in $parsedRecords) {
    $record = $item.Record
    $auditData = $item.AuditData
    [pscustomobject]@{
        CreationDate = $record.CreationDate
        Operation    = $record.Operations
        Workload     = $auditData.Workload
        UserIds      = $record.UserIds
        ObjectId     = $auditData.ObjectId
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
    Write-Host 'Nothing to merge in this window.' -ForegroundColor Yellow
    Write-Host 'A zero-row result is NOT proof no disposition activity occurred - see .NOTES and README.md Section 7/11: it is equally consistent with no reviewer action having been due yet, or with a gap in audit coverage. Cross-check against the portal Disposition page (Section 5) before concluding nothing happened.' -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object CreationDate | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Proof-of-disposition evidence trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green
    Write-Host 'Reminder: this CSV is a complement to, not a replacement for, the portal Disposition page Filter+Export workflow (README.md Section 5) - it cannot be scripted end-to-end because no PowerShell/Graph equivalent of that export is documented (README.md Section 11).' -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
```