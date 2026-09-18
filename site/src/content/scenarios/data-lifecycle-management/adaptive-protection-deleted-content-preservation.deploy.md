---
part: "deploy"
parent: "data-lifecycle-management/adaptive-protection-deleted-content-preservation"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-AdaptiveProtectionPreservationEvidence.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Adaptive Protection's Data Lifecycle Management deleted-
    content preservation events, and optionally scopes it to one user to build the evidence
    bundle a Microsoft Support restore request needs.

.DESCRIPTION
    Adaptive Protection can auto-create a single, tenant-wide, org-invisible retention label +
    auto-apply policy that preserves any SharePoint, OneDrive, or Exchange Online content deleted
    by a user Insider Risk Management has assigned the Elevated risk level, for 120 days
    (design.md Section 1/4). Microsoft states explicitly that "you don't need to create or manage
    the retention label or auto-labeling retention policy" and that it "aren't visible in the
    Microsoft Purview portal" -- there is no Get-/New-/Set- cmdlet and no Graph resource for it
    (design.md Section 2, item 1; README.md Section 5). This script does not attempt to create,
    enable, or query that policy directly -- it can't be done from PowerShell. What it scripts
    instead is the one thing Microsoft DOES document a surface for: the audit trail the control
    emits every time it fires.

    Two Operations, matched verbatim against Microsoft's own "Audit log activities" reference
    (design.md Section 2, item 2) -- no RecordType filter, since that reference does not document
    one specifically for these two Operations and guessing one risks silently under-matching real
    events (design.md Section 6):
      - SharePointDataProactivelyPreserved ("Retained file proactively") -- SharePoint/OneDrive
      - ExchangeDataProactivelyPreserved ("Retained email item proactively") -- Exchange

    Idempotency model: identical to scenarios/ediscovery/premium-legal-hold-and-export/deploy/
    Export-EdiscoveryAuditTrail.ps1 -- a rolling history accumulated across potentially-overlapping
    date-range calls, de-duplicated by a composite key of (CreationDate, Operations, UserIds, a
    stable hash of the full AuditData JSON payload). Safe to schedule daily or weekly; safe to
    re-run the same window twice.

    -UserPrincipalName (optional) post-filters client-side on the record's own UserIds property --
    Search-UnifiedAuditLog has a -UserIds parameter, but this script deliberately queries tenant-
    wide and filters after the fact, so a single scheduled run keeps building one complete rolling
    trail (matching this repo's other audit-trail scripts) while still supporting an ad hoc,
    narrowly-scoped pull for one support ticket via the same CSV output.

    A ZERO-ROW RESULT IS NOT PROOF THE CONTROL IS OFF. No status cmdlet exists for the underlying
    toggle (design.md Section 2, item 4) -- these events only fire when an Elevated-risk user
    actually deletes content. Absence of evidence in a given window is consistent with the control
    being on and simply not yet triggered, or with it never having been turned on at all; this
    script cannot tell the two apart. See README.md Section 7/11 and validate/
    Test-AdaptiveProtectionDlmPreservation.ps1, which reports this explicitly rather than as PASS/
    FAIL.

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

.PARAMETER UserPrincipalName
    Optional client-side filter (exact match, case-insensitive) on the record's UserIds property --
    scopes the export to one user's preserved deletions, for a Microsoft Support restore-request
    evidence bundle. Omit to keep the trail tenant-wide across every Elevated-risk user.

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
    ./Export-AdaptiveProtectionPreservationEvidence.ps1 -OutputCsvPath './out/ap-dlm-preservation.csv' -WhatIf

    Dry run: queries the last 7 days tenant-wide and reports how many new records would be
    merged, writes nothing.

.EXAMPLE
    ./Export-AdaptiveProtectionPreservationEvidence.ps1 -OutputCsvPath './out/ap-dlm-preservation.csv'

    Merges the last 7 days of proactive-preservation events, tenant-wide, into the rolling CSV.
    Safe to schedule alongside validate/Test-AdaptiveProtectionDlmPreservation.ps1 per
    README.md Section 8's recommended daily cadence.

.EXAMPLE
    ./Export-AdaptiveProtectionPreservationEvidence.ps1 -StartDate (Get-Date).AddDays(-120) -EndDate (Get-Date) `
        -UserPrincipalName 'alex.rivera@contoso.com' -OutputCsvPath './out/contoso-support-ticket-evidence.csv'

    A targeted, 120-day pull (matching the control's own retention window) for one user under
    investigation, to attach to the Microsoft Support restore request (README.md Section 9).

.NOTES
    VERIFY before relying on this for a matter beyond 180 days of history: default Audit
    (Standard) retention is 180 days for most workloads (one year for Entra ID/Exchange/OneDrive/
    SharePoint under an E5-tier license). Run this script on a recurring schedule if the
    evidentiary window a matter needs exceeds that retention -- see
    scenarios/audit/premium-audit-investigation/README.md Section 11 for this library's fuller
    treatment of retention-tier limits, and consider Audit Premium retention policies (up to 10
    years) for a matter with a long evidentiary horizon. This matters more here than for most
    audit-trail scripts in this library: the content itself is only preserved for 120 days, so an
    evidence pull that needs to span the full preservation window is well within the 180-day
    Standard default, but a Support restore request made near the end of that window should not
    also assume the AUDIT record survives past 180 days on a Standard-tier tenant.

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
    [string]$UserPrincipalName,

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
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - see rbac-model.md Section 6.'
    }
}

Assert-ExoSession

# Both Operations documented verbatim by Microsoft's "Audit log activities" reference under
# "Retention policy and retention label activities" for this control specifically (design.md
# Section 2, item 2) - no RecordType filter (design.md Section 6).
$operations = @('SharePointDataProactivelyPreserved', 'ExchangeDataProactivelyPreserved')

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
    # unique-ID property is NOT confirmed as part of that output schema for these two Operations
    # specifically - rather than assume one exists (AGENTS.md Section 4's no-invented-fields
    # rule), this key instead folds in a hash of the full AuditData JSON payload, which IS
    # confirmed to exist on every record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

Write-Host "Searching unified audit log for Adaptive Protection deleted-content preservation events (Operations=$($operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

$allRecords = [System.Collections.Generic.List[object]]::new()
$sessionId = "ap-dlm-preservation-$([guid]::NewGuid())"
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
# audit-data schema documents as common across workloads (Workload, ObjectId, UserId,
# SourceFileName) are extracted - none of these are confirmed specifically for
# SharePointDataProactivelyPreserved/ExchangeDataProactivelyPreserved by a worked Microsoft
# example, so they are populated best-effort ($null if absent) rather than assumed mandatory. The
# raw AuditData JSON is always preserved in full regardless.
$parsedRecords = foreach ($record in $allRecords) {
    $auditData = $null
    try {
        $auditData = $record.AuditData | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Record with CreationDate=$($record.CreationDate) Operations=$($record.Operations) has AuditData that failed to parse as JSON - Workload/ObjectId/SourceFileName columns will be blank for this row, but the raw AuditData is still preserved."
    }
    [pscustomobject]@{
        Record    = $record
        AuditData = $auditData
    }
}

if ($UserPrincipalName) {
    $before = $parsedRecords.Count
    $parsedRecords = @($parsedRecords | Where-Object { $_.Record.UserIds -and ($_.Record.UserIds -eq $UserPrincipalName) })
    Write-Host "Filtered to UserPrincipalName '$UserPrincipalName': $($parsedRecords.Count) of $before record(s) matched." -ForegroundColor Cyan
}

$newRows = foreach ($item in $parsedRecords) {
    $record = $item.Record
    $auditData = $item.AuditData
    [pscustomobject]@{
        CreationDate   = $record.CreationDate
        Operation      = $record.Operations
        Workload       = $auditData.Workload
        UserIds        = $record.UserIds
        ObjectId       = $auditData.ObjectId
        SourceFileName = $auditData.SourceFileName
        AuditData      = $record.AuditData
        CompositeKey   = (Get-CompositeKey -Record $record)
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
    Write-Host 'A zero-row result is NOT proof the control is off - see .NOTES and README.md Section 7/11: these events only fire when an Elevated-risk user deletes content. Use validate/Test-AdaptiveProtectionDlmPreservation.ps1 for the same caveat framed as a health check.' -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object CreationDate | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Evidence trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green
    Write-Host 'Reminder: this control has no self-service restore. To recover preserved content, contact Microsoft Support and attach the relevant rows from this CSV as evidence (README.md Section 9).' -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
```