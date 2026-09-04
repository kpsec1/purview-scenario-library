#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of eDiscovery case-lifecycle and hold-policy-lifecycle events
    from the unified audit log, closing the independent-actor-visibility gap this scenario's own
    Graph objects (case, custodian) don't provide - see README.md Section 8 and reviews.md's
    original Red Team finding 1.

.DESCRIPTION
    None of this scenario's own Graph objects retain a full history of who released a hold or
    closed/deleted a case - the case exposes only a single lastModifiedBy/closedBy snapshot. This
    script routes around that gap through the Microsoft 365 unified audit log (Search-
    UnifiedAuditLog, automation surface 1 per docs/automation-surface.md Section 1), the same
    pattern this repo's other no-independent-audit-trail scenarios already use
    (scenarios/compliance-manager/assess-against-iso27001/,
    scenarios/communication-compliance/harassment-and-code-of-conduct/).

    Two query categories, both confirmed directly against Microsoft's own "Audit log activities"
    eDiscovery activity reference (design note below) rather than guessed by analogy:

      1. CaseLifecycle  - RecordType Discovery, Operations CaseAdded / CaseUpdated / CaseClosed /
         CaseReopened / CaseRemoved. Directly answers the case-close/case-delete half of this
         script's original ask.
      2. HoldPolicyLifecycle - RecordType Discovery, Operations HoldCreated / HoldUpdated /
         HoldRemoved / HoldRetryDistributionSync.

    IMPORTANT GROUNDING CAVEAT - read before treating this as a complete answer to "who
    applied/released THIS scenario's custodian holds": this scenario's own deploy scripts
    (New-/Remove-EdiscoveryPremiumLegalHold.ps1) call the CUSTODIAN-scoped Graph actions
    (ediscoveryCustodian: applyHold / release) - a different object model from the case-level
    ediscoveryHoldPolicy ("Hold policies" tab) object that Microsoft's Audit log activities
    reference documents HoldCreated/HoldUpdated/HoldRemoved/HoldRetryDistributionSync against, and
    that the sibling scenarios/ediscovery/location-scoped-legal-hold/ scenario's
    New-EdiscoveryLocationHold.ps1 calls directly. Two facts pull in opposite directions on
    whether the HoldPolicyLifecycle category below also captures this scenario's own custodian
    apply/release calls:
      - FOR: Microsoft's "Manage holds in eDiscovery (Premium)" article states that when a
        custodian is placed on hold, "the user and their selected data sources are automatically
        added to a custodian hold policy" (a "CustodianHold(HoldId)" object) - i.e. custodian holds
        are internally modeled as a hold policy too.
      - AGAINST: that specific article, and the only Microsoft Learn page found describing
        per-custodian audit-activity search ("View custodian audit activity"), both carry
        Microsoft's own caution banner: "Microsoft retired all classic eDiscovery experiences on
        August 31, 2025 ... The guidance in this article only applies to organizations hosted in
        Microsoft 365 operated by 21Vianet (China)." Neither is confirmed to describe the current,
        non-legacy eDiscovery experience this scenario's deploy scripts target for commercial
        (non-21Vianet) tenants.

    Rather than assert the HoldPolicyLifecycle category captures custodian apply/release events (or
    that it doesn't), this script queries for it anyway - the best-documented signal available, and
    a run that finds zero HoldPolicyLifecycle rows for a tenant that has actually only ever placed
    custodian holds (never used the ediscoveryHoldPolicy/"Hold policies" object directly) is itself
    informative, not a bug. See README.md Section 8 and the VERIFY item this build added to
    PROGRESS.md for the pilot-tenant confirmation step that would resolve this either way.

    Idempotency model: identical to
    scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/
    Export-CommunicationComplianceAuditTrail.ps1 - a rolling history accumulated across
    potentially-overlapping date-range calls, de-duplicated by a composite key of (CreationDate,
    Operations, UserIds, a stable hash of the full AuditData JSON payload).

    -CaseName (optional) post-filters both categories client-side by the AuditData JSON's own
    CaseName property, since Search-UnifiedAuditLog has no -CaseId/-CaseName parameter of its own.
    Useful once a tenant has more than one eDiscovery matter generating audit noise; omit it to
    keep the rolling trail tenant-wide across every case (matches this repo's other two
    audit-trail scripts' tenant-wide default).

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only against the tenant: it never creates, modifies, or deletes any case, hold, or
    custodian - the only side effect is the CSV file this script writes, which IS gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports the records that would be merged without touching
    disk.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Search-UnifiedAuditLog requires both -StartDate and
    -EndDate. Defaults to 7 days before -EndDate, suitable for a weekly scheduled run per
    README.md Section 8's review-cadence recommendation, with deliberate overlap (idempotent
    de-duplication makes overlap safe).

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER CaseName
    Optional client-side filter (exact match, case-insensitive) on the AuditData JSON's CaseName
    property. Omit to keep the trail tenant-wide across every eDiscovery case.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    CreationDate.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size when not using -SessionCommand ReturnLargeSet.
    Defaults to 5000 (the cmdlet's documented per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Both Search-UnifiedAuditLog queries still execute
    (read-only; needed to report accurate would-be results), but the CSV file is not written - the
    script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-EdiscoveryAuditTrail.ps1 -OutputCsvPath './out/edisc-audit-trail.csv' -CaseName 'CONTOSO-LIT-2026-014' -WhatIf

    Dry run scoped to one matter: queries the last 7 days across both categories and reports how
    many new records would be merged, writes nothing.

.EXAMPLE
    ./Export-EdiscoveryAuditTrail.ps1 -OutputCsvPath './out/edisc-audit-trail.csv'

    Merges the last 7 days of case-lifecycle and hold-policy-lifecycle events, tenant-wide, into
    the rolling CSV. Safe to schedule weekly alongside
    validate/Test-EdiscoveryPremiumCaseSetup.ps1 per README.md Section 8's review cadence -
    overlapping windows never produce duplicate rows.

.EXAMPLE
    ./Export-EdiscoveryAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/edisc-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window before the
    first scheduled recurring run - see .NOTES.

.NOTES
    VERIFY before relying on this for a matter beyond 180 days of history: default Audit
    (Standard) retention is 180 days for most workloads (one year for Entra ID/Exchange/OneDrive/
    SharePoint under an E5-tier license). Run this script on a recurring schedule if the
    evidentiary window a matter needs exceeds that retention, rather than relying on a single
    historical pull. See scenarios/audit/premium-audit-investigation/README.md Section 11 for this
    library's fuller treatment of retention-tier limits, and consider Audit Premium retention
    policies (up to 10 years) for a matter with a long evidentiary horizon.

    VERIFY (pilot tenant, before treating a zero-row HoldPolicyLifecycle result as "no hold
    activity happened"): whether HoldCreated/HoldUpdated/HoldRemoved/HoldRetryDistributionSync fire
    for this scenario's own ediscoveryCustodian: applyHold/release actions - see the .DESCRIPTION
    caveat above. Tracked in PROGRESS.md.

    Sources (Microsoft Learn, verify before production use):
    - Audit log activities - eDiscovery activity reference (the exact Operation names/descriptions
      this script's two categories are built from verbatim, both confirmed current with no
      legacy-experience caution banner on the page itself):
      https://learn.microsoft.com/purview/audit-log-activities#ediscovery-activities
    - Office 365 Management Activity API schema - Common schema AuditLogRecordType table (record
      type 24, "Discovery": "Events for eDiscovery activities performed by running content
      searches and managing eDiscovery cases in the Microsoft Purview portal"):
      https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#common-schema
    - Search for eDiscovery activities in the audit log (confirms PowerShell, not just the portal
      Audit solution, is a supported path to these same records; also documents the
      ClientApplication=EMC / IP-address distinction between new- and classic-experience entries):
      https://learn.microsoft.com/purview/edisc-ref-audit-log
    - Manage holds in eDiscovery (Premium) (the "custodian hold policy" corroborating claim; carries
      Microsoft's classic-experience/21Vianet-China-only caution banner - see .DESCRIPTION):
      https://learn.microsoft.com/purview/ediscovery-managing-holds
    - View custodian audit activity (the one per-custodian audit UI Microsoft documents; also
      carries the classic-experience/21Vianet-China-only caution banner):
      https://learn.microsoft.com/purview/ediscovery-view-custodian-activity
    - Search-UnifiedAuditLog reference (-StartDate/-EndDate/-Operations/-RecordType/-ResultSize/
      -SessionCommand): https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/
      Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies):
      https://learn.microsoft.com/purview/audit-log-retention-policies
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [datetime]$StartDate = ([datetime]::UtcNow.AddDays(-7)),

    [Parameter()]
    [datetime]$EndDate = ([datetime]::UtcNow),

    [Parameter()]
    [string]$CaseName,

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

# Two query categories, each matching Microsoft's own "Audit log activities" eDiscovery activity
# reference verbatim (see .NOTES) rather than a single guessed combined call.
$queryCategories = @(
    @{
        Category   = 'CaseLifecycle'
        RecordType = 'Discovery'
        Operations = @('CaseAdded', 'CaseUpdated', 'CaseClosed', 'CaseReopened', 'CaseRemoved')
    }
    @{
        Category   = 'HoldPolicyLifecycle'
        RecordType = 'Discovery'
        Operations = @('HoldCreated', 'HoldUpdated', 'HoldRemoved', 'HoldRetryDistributionSync')
    }
)

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
    # unique-ID property is NOT confirmed as part of that output schema for these operations -
    # rather than assume one exists (AGENTS.md Section 4's no-invented-fields rule), this key
    # instead folds in a hash of the full AuditData JSON payload, which IS confirmed to exist on
    # every record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

$allRecords = [System.Collections.Generic.List[object]]::new()

foreach ($query in $queryCategories) {
    Write-Host "Searching unified audit log: category '$($query.Category)' (RecordType=$($query.RecordType); Operations=$($query.Operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

    $sessionId = "edisc-audit-trail-$($query.Category)-$([guid]::NewGuid())"
    do {
        $searchParams = @{
            StartDate      = $StartDate
            EndDate        = $EndDate
            RecordType     = $query.RecordType
            Operations     = $query.Operations
            ResultSize     = $ResultSize
            SessionId      = $sessionId
            SessionCommand = 'ReturnLargeSet'
        }

        # Wrapping in @() up front avoids PowerShell's single-object-vs-array ambiguity: a page
        # that returns exactly one record would otherwise come back as a scalar with no .Count
        # property, which would make the loop-continuation check below silently misbehave.
        $page = @(Search-UnifiedAuditLog @searchParams)
        foreach ($record in $page) {
            # Tag each record with its query category before merging the two result sets, so the
            # exported CSV can distinguish "a case changed" from "a hold policy changed" without
            # re-deriving it from Operations.
            $record | Add-Member -NotePropertyName 'QueryCategory' -NotePropertyValue $query.Category -Force
        }
        if ($page.Count -gt 0) { $allRecords.AddRange($page) }
    } while ($page.Count -gt 0)
}

Write-Host "Found $($allRecords.Count) matching record(s) across both categories in the search window." -ForegroundColor Green

# Parse each record's AuditData JSON once, up front, so both the -CaseName filter and the
# extracted CaseId/CaseName/ObjectType/ObjectName/ResultStatus columns below share one parse pass
# instead of re-parsing per use.
$parsedRecords = foreach ($record in $allRecords) {
    $auditData = $null
    try {
        $auditData = $record.AuditData | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Record with CreationDate=$($record.CreationDate) Operations=$($record.Operations) has AuditData that failed to parse as JSON - CaseId/CaseName/ObjectType/ObjectName/ResultStatus columns will be blank for this row, but the raw AuditData is still preserved."
    }
    [pscustomobject]@{
        Record    = $record
        AuditData = $auditData
    }
}

if ($CaseName) {
    $before = $parsedRecords.Count
    $parsedRecords = @($parsedRecords | Where-Object { $_.AuditData -and $_.AuditData.CaseName -and $_.AuditData.CaseName -eq $CaseName })
    Write-Host "Filtered to CaseName '$CaseName': $($parsedRecords.Count) of $before record(s) matched." -ForegroundColor Cyan
}

$newRows = foreach ($item in $parsedRecords) {
    $record = $item.Record
    $auditData = $item.AuditData
    [pscustomobject]@{
        CreationDate = $record.CreationDate
        Category     = $record.QueryCategory
        Operation    = $record.Operations
        RecordType   = $record.RecordType
        CaseId       = $auditData.CaseId
        CaseName     = $auditData.CaseName
        ObjectType   = $auditData.ObjectType
        ObjectName   = $auditData.ObjectName
        ResultStatus = $auditData.ResultStatus
        UserIds      = $record.UserIds
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

    $caseDeletedRows = @($rowsToAdd | Where-Object { $_.Operation -eq 'CaseRemoved' })
    foreach ($row in $caseDeletedRows) {
        Write-Warning "eDiscovery case deleted: '$($row.CaseName)' (CaseId=$($row.CaseId)) by $($row.UserIds) at $($row.CreationDate). Case deletion is permanent and turns off every hold in the case - confirm this matches an intended, documented action per rollback.md Stage 4, not an unexpected deletion."
    }

    $holdRemovedRows = @($rowsToAdd | Where-Object { $_.Operation -eq 'HoldRemoved' })
    foreach ($row in $holdRemovedRows) {
        Write-Warning "Hold policy deleted: '$($row.ObjectName)' in case '$($row.CaseName)' by $($row.UserIds) at $($row.CreationDate). Deleting a hold policy releases every content location in it - confirm counsel has actually confirmed the preservation duty has lapsed per README.md Section 3's gating prerequisite, and see the .NOTES VERIFY on whether this Operation also captures this scenario's own custodian-scoped hold releases."
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
