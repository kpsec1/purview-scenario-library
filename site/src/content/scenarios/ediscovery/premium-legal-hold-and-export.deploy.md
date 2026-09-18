---
part: "deploy"
parent: "ediscovery/premium-legal-hold-and-export"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-EdiscoveryAuditTrail.ps1`

```powershell
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
```

#### `Get-EdiscoveryExportPackage.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'MSAL.PS'; ModuleVersion = '4.61.3' }

<#
.SYNOPSIS
    Downloads an eDiscovery (Premium) review-set export package and its report files, once the
    export operation started by New-EdiscoverySearchReviewSetExport.ps1 has succeeded.

.DESCRIPTION
    Third-stage deploy script for the eDiscovery (Premium) legal-hold-and-export scenario.
    Implements the pattern Microsoft documents in "Use Microsoft Purview APIs for eDiscovery"
    (README.md section 12, reference 5): the export *package* is not downloaded through Microsoft
    Graph. It is downloaded through a separate Microsoft Purview eDiscovery API, authenticated
    with its own token (via MSAL.PS's Get-MsalToken, scope
    00001111-aaaa-2222-bbbb-3333cccc4444/.default -- this is Microsoft's own documented resource
    GUID for the MicrosoftPurviewEDiscovery first-party app, not invented here) -- separate from
    the Microsoft.Graph.Authentication token used to look up the export operation itself.

    This requires a *second* app registration step beyond the one used by the other two deploy
    scripts: registering (or reusing) the MicrosoftPurviewEDiscovery service principal in the
    tenant and granting the calling app the eDiscovery.Download.Read application permission
    against it. See README.md section 5 step 6 and reference 5 for the exact portal/PowerShell
    steps -- this script assumes that prerequisite is already in place and fails fast with a
    clear error if the download token request is rejected, rather than guessing at a remediation.

    Idempotent: skips any file already present locally with a matching byte size, so re-running
    this script after a partial download (or to pick up a second export from the same case) does
    not re-download files unnecessarily.

.PARAMETER CaseId
    The eDiscoveryCase id (from New-EdiscoveryPremiumLegalHold.ps1 / the Purview portal).

.PARAMETER ExportOperationId
    The caseOperation id for the completed export (printed by
    New-EdiscoverySearchReviewSetExport.ps1, or read from the case's Exports tab -> "Copy support
    information" in the portal).

.PARAMETER OutputDirectory
    Local directory to download the export package and report files into. Created if it doesn't
    exist. Treat this directory as containing case-sensitive/privileged litigation content --
    apply the same access controls and retention discipline your organization applies to any
    outside-counsel production set.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for both the Graph token and the
    separate download token.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for app-only auth (both tokens). Mutually exclusive with -Certificate.

.PARAMETER Certificate
    In-memory X509Certificate2 for app-only auth. Mutually exclusive with -CertificateThumbprint.

.EXAMPLE
    ./Get-EdiscoveryExportPackage.ps1 -CaseId $caseId -ExportOperationId $opId `
        -OutputDirectory ./exports/CONTOSO-LIT-2026-014-export1 `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Lists every file the export contains and its size, without downloading anything.

.EXAMPLE
    ./Get-EdiscoveryExportPackage.ps1 -CaseId $caseId -ExportOperationId $opId `
        -OutputDirectory ./exports/CONTOSO-LIT-2026-014-export1 `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Grounded in Microsoft Learn: "Use Microsoft Purview APIs for eDiscovery" (README.md section
    12, reference 5) -- this script is a parameterized, idempotent adaptation of Microsoft's own
    published DownloadExportUsingAppCert.ps1 reference script from that page, changed to: accept
    an already-established Graph connection or connect via the shared connect pattern used by
    this repo's other deploy scripts; skip files that already exist locally with a matching size;
    and support -WhatIf. The MSAL.PS scope GUID (00001111-aaaa-2222-bbbb-3333cccc4444) and the
    exportFileMetadata.downloadUrl / X-AllowWithAADToken header pattern are copied verbatim from
    that Microsoft-published example, not independently re-derived.

    Export packages must be downloaded within 30 days of the export operation completing --
    Microsoft's own guidance states export processes are retained for the life of the case, but
    the *content* is deleted 30 days after completion (README.md section 11, reference 6).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$ExportOperationId,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Microsoft's own documented resource scope for the separate eDiscovery export-download token --
# see .NOTES. Not a tenant-specific value; do not treat as a secret.
$DownloadTokenScope = '00001111-aaaa-2222-bbbb-3333cccc4444/.default'

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$operationUri = "/v1.0/security/cases/ediscoveryCases/$CaseId/operations/$ExportOperationId"
$operation = Invoke-MgGraphRequest -Method GET -Uri $operationUri
if (-not $operation) {
    throw "No operation found at $operationUri -- confirm -CaseId/-ExportOperationId are correct."
}
if ($operation.status -ne 'succeeded') {
    Write-Warning "Export operation status is '$($operation.status)', not 'succeeded'. Files listed below (if any) may be incomplete. Re-run after the export finishes -- see New-EdiscoverySearchReviewSetExport.ps1's poll loop or the portal's Exports tab."
}

$files = $operation.exportFileMetadata
if (-not $files -or $files.Count -eq 0) {
    Write-Warning 'No exportFileMetadata entries returned for this operation -- nothing to download yet.'
    return
}

if (-not (Test-Path $OutputDirectory)) {
    if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create output directory')) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
}

# Acquire the separate download token -- a client-secret or certificate credential object built
# the same way the ExchangeOnlineManagement/Graph connections in this repo's other scripts are.
$tokenParams = @{ ClientId = $AppId; TenantId = $TenantId; Scopes = $DownloadTokenScope }
if ($Certificate) {
    $tokenParams['ClientCertificate'] = $Certificate
} elseif ($CertificateThumbprint) {
    $tokenParams['ClientCertificate'] = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint"
} else {
    throw 'Either -Certificate or -CertificateThumbprint is required to acquire the download token.'
}
$downloadToken = Get-MsalToken @tokenParams

foreach ($file in $files) {
    $destination = Join-Path $OutputDirectory $file.fileName
    if ((Test-Path $destination) -and (Get-Item $destination).Length -eq $file.size) {
        Write-Verbose "Skipping '$($file.fileName)' -- already downloaded with matching size ($($file.size) bytes)."
        continue
    }

    if ($PSCmdlet.ShouldProcess($file.fileName, "Download $($file.size) bytes to $destination")) {
        Invoke-WebRequest -Uri $file.downloadUrl -OutFile $destination -Headers @{
            'Authorization'        = "Bearer $($downloadToken.AccessToken)"
            'X-AllowWithAADToken'  = 'true'
        }
        Write-Host "Downloaded '$($file.fileName)' ($($file.size) bytes) to $destination."
    } else {
        Write-Host "[WhatIf] Would download '$($file.fileName)' ($($file.size) bytes) to $destination."
    }
}

Write-Host "Done. $($files.Count) file(s) processed for operation $ExportOperationId."
```

#### `New-EdiscoveryPremiumLegalHold.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or reconciles) a Microsoft Purview eDiscovery (Premium) case, adds one or more
    custodians, and places a legal hold on each custodian's Exchange mailbox and OneDrive site.

.DESCRIPTION
    Idempotent, parameterized deploy script for the first stage of the eDiscovery (Premium)
    legal-hold-and-export scenario. Uses Microsoft Graph (automation surface 3 per
    docs/automation-surface.md) because app-only authentication for eDiscovery cmdlets in
    Security & Compliance PowerShell is explicitly unsupported by Microsoft -- see
    docs/automation-surface.md section 3 and README.md section 5.

    Stages, each individually idempotent (re-running this script after a partial failure is safe):
      1. Find-or-create the eDiscoveryCase by DisplayName.
      2. Find-or-create each custodian by email.
      3. Find-or-create each custodian's userSource (mailbox + OneDrive site).
      4. Apply hold to every custodian whose HoldStatus isn't already 'success'.

    Every mutating Graph cmdlet used here (New-MgSecurityCaseEdiscoveryCase,
    New-MgSecurityCaseEdiscoveryCaseCustodian, New-MgSecurityCaseEdiscoveryCaseCustodianUserSource,
    Add-MgSecurityCaseEdiscoveryCaseCustodianHold) natively implements ShouldProcess, so -WhatIf
    on this script fans out to a true dry run on every Graph call -- no writes occur.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/ediscovery-case-definition.json's shape (case,
    custodians[]). Keeps the case/custodian list out of the script body.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store,
    used for certificate-based app-only authentication (docs/automation-surface.md section 3).
    Mutually exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object (for example, resolved from Key Vault at run time) to
    use instead of -CertificateThumbprint. Prefer this in a CI/CD pipeline so the private key is
    never written to disk. Mutually exclusive with -CertificateThumbprint.

.EXAMPLE
    ./New-EdiscoveryPremiumLegalHold.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/custodian/userSource/hold action this run would take, without calling any
    mutating Graph endpoint.

.EXAMPLE
    ./New-EdiscoveryPremiumLegalHold.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case (if it doesn't already exist), adds any missing custodians and userSources,
    and applies hold to every custodian not already on hold.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12 for the full citation list. Cmdlet names and request
    shapes used here:
      - New-MgSecurityCaseEdiscoveryCase                    (POST /security/cases/ediscoveryCases)
      - New-MgSecurityCaseEdiscoveryCaseCustodian            (POST .../custodians)
      - New-MgSecurityCaseEdiscoveryCaseCustodianUserSource  (POST .../custodians/{id}/userSources)
      - Add-MgSecurityCaseEdiscoveryCaseCustodianHold        (POST .../custodians/{id}/applyHold)

    VERIFY before relying on this in production: Microsoft's own hold-creation guidance states a
    newly applied eDiscovery hold can take up to 24 hours to take effect (README.md section 11,
    reference 8) -- this script's -WaitForHold switch polls HoldStatus but does not itself wait
    out that propagation window; a 'success' HoldStatus reflects Graph's own state, not confirmed
    end-to-end preservation, which Microsoft does not expose an API to confirm directly.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    # Poll HoldStatus after applying hold until it leaves 'notStarted'/'running', instead of
    # firing-and-forgetting the applyHold call. Off by default -- hold application is
    # asynchronous and this script is meant to be safe to re-run rather than to block.
    [switch]$WaitForHold,

    [int]$HoldPollTimeoutSeconds = 300,
    [int]$HoldPollIntervalSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)

    if (Get-MgContext) {
        Write-Verbose 'Reusing existing Microsoft Graph connection.'
        return
    }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) {
        $connectParams['Certificate'] = $Certificate
    } else {
        $connectParams['CertificateThumbprint'] = $CertificateThumbprint
    }
    Connect-MgGraph @connectParams
}

function Get-OrNewEdiscoveryCase {
    param($Definition, [switch]$WhatIfPreference)

    $existing = Get-MgSecurityCaseEdiscoveryCase -All |
        Where-Object { $_.DisplayName -eq $Definition.displayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Case '$($Definition.displayName)' already exists (id=$($existing.Id))."
        return $existing
    }

    $body = @{
        displayName = $Definition.displayName
        description = $Definition.description
        externalId  = $Definition.externalId
    }
    if ($PSCmdlet.ShouldProcess($Definition.displayName, 'Create eDiscovery (Premium) case')) {
        $created = New-MgSecurityCaseEdiscoveryCase -BodyParameter $body
        Write-Host "Created case '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    # -WhatIf path: nothing was created, return a placeholder so downstream -WhatIf reporting
    # can still describe what it *would* do against this case.
    return [pscustomobject]@{ Id = '<case-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OrNewCustodian {
    param($CaseId, $CustodianDef)

    $existing = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.Email -eq $CustodianDef.email } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Custodian '$($CustodianDef.email)' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($CustodianDef.email, "Add custodian to case $CaseId")) {
        $created = New-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId `
            -Email $CustodianDef.email
        Write-Host "Added custodian '$($created.Email)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<custodian-id-pending>'; Email = $CustodianDef.email; HoldStatus = $null }
}

function Confirm-CustodianUserSource {
    param($CaseId, $CustodianId, $Email)

    $existingSources = @()
    try {
        $existingSources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource `
            -EdiscoveryCaseId $CaseId -EdiscoveryCustodianId $CustodianId -All
    } catch {
        # A pending (-WhatIf) custodian has no real ID to query against yet -- treat as empty.
        Write-Verbose "Could not list existing userSources for custodian $CustodianId (expected under -WhatIf on a not-yet-created custodian)."
    }
    if ($existingSources | Where-Object { $_.Email -eq $Email }) {
        Write-Verbose "userSource for '$Email' already exists on custodian $CustodianId."
        return
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add mailbox + OneDrive userSource to custodian $CustodianId")) {
        # includedSources covers both the custodian's mailbox and OneDrive/SharePoint site --
        # see README.md section 12 reference 11 (Create custodian userSource, v1.0).
        New-MgSecurityCaseEdiscoveryCaseCustodianUserSource -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $CustodianId -Email $Email -IncludedSources 'mailbox, site' | Out-Null
        Write-Host "Added userSource (mailbox, site) for '$Email'."
    }
}

function Confirm-CustodianHold {
    param($CaseId, $Custodian)

    if ($Custodian.HoldStatus -eq 'success') {
        Write-Verbose "Custodian $($Custodian.Email) is already on hold (HoldStatus=success)."
        return
    }

    if ($PSCmdlet.ShouldProcess($Custodian.Email, "Apply eDiscovery hold (case $CaseId)")) {
        Add-MgSecurityCaseEdiscoveryCaseCustodianHold -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $Custodian.Id | Out-Null
        Write-Host "Requested hold for custodian '$($Custodian.Email)'. This is asynchronous -- Microsoft documents up to a 24-hour propagation window before the hold is fully in effect (README.md section 11)."

        if ($WaitForHold) {
            $elapsed = 0
            do {
                Start-Sleep -Seconds $HoldPollIntervalSeconds
                $elapsed += $HoldPollIntervalSeconds
                $refreshed = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId `
                    -EdiscoveryCustodianId $Custodian.Id
                Write-Verbose "  HoldStatus for $($Custodian.Email): $($refreshed.HoldStatus) (elapsed ${elapsed}s)"
            } while ($refreshed.HoldStatus -in @('notStarted', 'running', $null) -and $elapsed -lt $HoldPollTimeoutSeconds)

            if ($refreshed.HoldStatus -ne 'success') {
                Write-Warning "Custodian $($Custodian.Email) HoldStatus is '$($refreshed.HoldStatus)' after ${elapsed}s -- this does not necessarily indicate failure (hold application can legitimately take longer than this poll window); re-check via validate/Test-EdiscoveryPremiumCaseSetup.ps1 later rather than treating this as an error."
            }
        }
    }
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-OrNewEdiscoveryCase -Definition $definition.case

foreach ($custodianDef in $definition.custodians) {
    $custodian = Get-OrNewCustodian -CaseId $case.Id -CustodianDef $custodianDef
    Confirm-CustodianUserSource -CaseId $case.Id -CustodianId $custodian.Id -Email $custodianDef.email
    Confirm-CustodianHold -CaseId $case.Id -Custodian $custodian
}

Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)) has $($definition.custodians.Count) custodian(s) reconciled."
Write-Host 'Next: ./New-EdiscoverySearchReviewSetExport.ps1 to search, collect into a review set, and export.'
```

#### `New-EdiscoverySearchReviewSetExport.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or reconciles) an eDiscovery search scoped to a case's custodians, commits the
    search results to a review set, and starts an export from that review set.

.DESCRIPTION
    Second-stage deploy script for the eDiscovery (Premium) legal-hold-and-export scenario. Runs
    after New-EdiscoveryPremiumLegalHold.ps1 has created the case and placed custodians on hold.

    Stages, each individually idempotent:
      1. Find-or-create the eDiscoverySearch (dataSourceScopes=allCaseCustodians, scoped to the
         KQL contentQuery in the definition file).
      2. Find-or-create the eDiscoveryReviewSet.
      3. Start an addToReviewSet operation committing the search into the review set, unless an
         addToReviewSet operation for that search/review-set pair has already succeeded.
      4. Start an export operation from the review set, unless an export with the same
         outputName has already succeeded.

    addToReviewSet and export are both long-running, asynchronous caseOperations (Graph returns
    202 Accepted with a Location header pointing at the operation). This script polls each
    operation's status via Get-MgSecurityCaseEdiscoveryCaseOperation and reports the final state
    rather than assuming synchronous completion, per docs/automation-surface.md section 5's
    guidance for asynchronous Purview operations.

.PARAMETER DefinitionPath
    Path to the same JSON file used by New-EdiscoveryPremiumLegalHold.ps1 (case, search,
    reviewSet, export).

.PARAMETER CaseId
    The eDiscoveryCase id returned by New-EdiscoveryPremiumLegalHold.ps1. Required rather than
    re-resolved by DisplayName here, so this script can't accidentally act against a
    same-named case created outside this scenario's control.

.PARAMETER SkipAddToReviewSet
    Create/confirm the search and review set but don't start (or re-check) an addToReviewSet
    operation. Useful for reviewing/tuning the search's estimated hit count in the portal before
    committing data into the review set's Azure Storage location.

.PARAMETER SkipExport
    Create/confirm the search and review set, and run addToReviewSet, but don't start an export.
    Use this to pause for human review-set triage (tagging, culling) before producing an export
    package for outside counsel.

.PARAMETER ForceAddToReviewSet
    Start a new addToReviewSet operation even if one has already succeeded in this case. Use
    this for a deliberate second commit (for example, after custodian data sources changed) --
    see the addToReviewSet idempotency VERIFY note below before relying on this by default.

.EXAMPLE
    ./New-EdiscoverySearchReviewSetExport.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

.EXAMPLE
    ./New-EdiscoverySearchReviewSetExport.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint `
        -SkipExport

    Runs the search and commits it to the review set, but stops short of exporting -- so a
    reviewer can tag/cull in the portal before an export package is produced.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12. Cmdlets used:
      - New-MgSecurityCaseEdiscoveryCaseSearch              (POST .../searches)
      - New-MgSecurityCaseEdiscoveryCaseReviewSet            (POST .../reviewSets)
      - Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet (POST .../reviewSets/{id}/addToReviewSet)
      - Export-MgSecurityCaseEdiscoveryCaseReviewSet         (POST .../reviewSets/{id}/export)
      - Get-MgSecurityCaseEdiscoveryCaseOperation             (GET .../operations/{id})

    caseOperationStatus values used in the poll loop (notStarted, submissionFailed, running,
    succeeded, partiallySucceeded, failed, unknownFutureValue) are the exact v1.0 enum from the
    caseOperation resource type reference -- not guessed or carried over from the beta namespace,
    which uses a different casing/shape in places (README.md section 11).

    VERIFY: the addToReviewSet/export idempotency checks below key off DisplayName/outputName
    text match via Get-...-All | Where-Object, since neither operation type exposes a documented
    "does an equivalent operation already exist" query filter. A prior run's search/review-set/
    export with a *different* DisplayName/outputName than the current definition file will not be
    found and will result in a duplicate -- keep definition-file names stable across re-runs of
    the same matter's collection.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [switch]$SkipAddToReviewSet,
    [switch]$SkipExport,
    [switch]$ForceAddToReviewSet,

    [int]$OperationPollTimeoutSeconds = 1800,
    [int]$OperationPollIntervalSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)
    if (Get-MgContext) { Write-Verbose 'Reusing existing Microsoft Graph connection.'; return }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

function Wait-CaseOperation {
    param($CaseId, $OperationId, [string]$Label)

    $elapsed = 0
    do {
        $op = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId
        Write-Verbose "  [$Label] status=$($op.Status) progress=$($op.PercentProgress)% (elapsed ${elapsed}s)"
        if ($op.Status -in @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
            break
        }
        Start-Sleep -Seconds $OperationPollIntervalSeconds
        $elapsed += $OperationPollIntervalSeconds
    } while ($elapsed -lt $OperationPollTimeoutSeconds)

    if ($op.Status -notin @('succeeded', 'partiallySucceeded', 'failed', 'submissionFailed')) {
        Write-Warning "[$Label] operation $OperationId did not reach a terminal state within ${OperationPollTimeoutSeconds}s (last status: $($op.Status)). It may still be running -- re-check with Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -CaseOperationId $OperationId later rather than assuming failure."
    } elseif ($op.Status -eq 'failed' -or $op.Status -eq 'submissionFailed') {
        Write-Warning "[$Label] operation $OperationId ended with status '$($op.Status)'. ResultInfo: $($op.ResultInfo | ConvertTo-Json -Compress -Depth 5)"
    } else {
        Write-Host "[$Label] operation $OperationId completed with status '$($op.Status)'."
    }
    return $op
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

# 1. Find-or-create the search.
$search = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.search.displayName } |
    Select-Object -First 1
if (-not $search) {
    if ($PSCmdlet.ShouldProcess($definition.search.displayName, "Create eDiscovery search in case $CaseId")) {
        $search = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId `
            -DisplayName $definition.search.displayName `
            -Description $definition.search.description `
            -ContentQuery $definition.search.contentQuery `
            -DataSourceScopes $definition.search.dataSourceScopes
        Write-Host "Created search '$($search.DisplayName)' (id=$($search.Id))."
    } else {
        $search = [pscustomobject]@{ Id = '<search-id-pending>'; DisplayName = $definition.search.displayName }
    }
} else {
    Write-Verbose "Search '$($definition.search.displayName)' already exists (id=$($search.Id))."
}

# 2. Find-or-create the review set.
$reviewSet = Get-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId -All |
    Where-Object { $_.DisplayName -eq $definition.reviewSet.displayName } |
    Select-Object -First 1
if (-not $reviewSet) {
    if ($PSCmdlet.ShouldProcess($definition.reviewSet.displayName, "Create review set in case $CaseId")) {
        $reviewSet = New-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId `
            -DisplayName $definition.reviewSet.displayName
        Write-Host "Created review set '$($reviewSet.DisplayName)' (id=$($reviewSet.Id))."
    } else {
        $reviewSet = [pscustomobject]@{ Id = '<reviewset-id-pending>'; DisplayName = $definition.reviewSet.displayName }
    }
} else {
    Write-Verbose "Review set '$($definition.reviewSet.displayName)' already exists (id=$($reviewSet.Id))."
}

# 3. Commit the search into the review set (addToReviewSet), unless already done for this pair.
if (-not $SkipAddToReviewSet) {
    $priorAddOps = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryAddToReviewSetOperation' -and
            $_.Status -eq 'succeeded'
        }
    # Note: caseOperation doesn't expose which review set/search a completed addToReviewSet
    # operation targeted without a follow-up Get on the operation's expanded properties -- this
    # check is therefore best-effort (counts *any* succeeded addToReviewSet operation in the
    # case) rather than an exact per-search/per-review-set match. See .NOTES VERIFY above.
    if ($priorAddOps -and -not $ForceAddToReviewSet) {
        Write-Verbose "At least one addToReviewSet operation has already succeeded in this case; skipping. Pass -ForceAddToReviewSet is not implemented -- re-run manually via Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet if a second commit is intentional."
    } else {
        if ($PSCmdlet.ShouldProcess("$($search.DisplayName) -> $($reviewSet.DisplayName)", 'Add search results to review set')) {
            $addBody = @{
                search              = @{ id = $search.Id }
                additionalDataOptions = 'linkedFiles'
                itemsToInclude      = 'searchHits'
                documentVersion     = 'latest'
                cloudAttachmentVersion = 'latest'
            }
            $responseHeaders = $null
            Add-MgSecurityCaseEdiscoveryCaseReviewSetToReviewSet -EdiscoveryCaseId $CaseId `
                -EdiscoveryReviewSetId $reviewSet.Id -BodyParameter $addBody `
                -ResponseHeadersVariable responseHeaders | Out-Null
            $opLocation = $responseHeaders['Location']
            $opId = ($opLocation -split '/')[-1]
            Write-Host "Started addToReviewSet operation $opId."
            Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'addToReviewSet' | Out-Null
        }
    }
}

# 4. Export from the review set, unless an export with the same outputName already succeeded.
if (-not $SkipExport) {
    $priorExportOps = Get-MgSecurityCaseEdiscoveryCaseOperation -EdiscoveryCaseId $CaseId -All |
        Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.security.ediscoveryExportOperation' -and
            $_.AdditionalProperties['outputName'] -eq $definition.export.outputName
        }
    $alreadySucceeded = $priorExportOps | Where-Object { $_.Status -eq 'succeeded' }
    if ($alreadySucceeded) {
        Write-Verbose "Export '$($definition.export.outputName)' already succeeded (operation $($alreadySucceeded[0].Id)); skipping. Export packages must be downloaded within 30 days of completion (README.md section 11) -- if that window has passed, delete the existing export in the portal and re-run this script to start a fresh one."
    } else {
        if ($PSCmdlet.ShouldProcess($definition.export.outputName, "Export review set '$($reviewSet.DisplayName)'")) {
            $exportBody = @{
                outputName      = $definition.export.outputName
                description     = $definition.export.description
                exportOptions   = $definition.export.exportOptions
                exportStructure = $definition.export.exportStructure
            }
            $responseHeaders = $null
            Export-MgSecurityCaseEdiscoveryCaseReviewSet -EdiscoveryCaseId $CaseId `
                -EdiscoveryReviewSetId $reviewSet.Id -BodyParameter $exportBody `
                -ResponseHeadersVariable responseHeaders | Out-Null
            $opLocation = $responseHeaders['Location']
            $opId = ($opLocation -split '/')[-1]
            Write-Host "Started export operation $opId ('$($definition.export.outputName)')."
            $finalOp = Wait-CaseOperation -CaseId $CaseId -OperationId $opId -Label 'export'
            if ($finalOp.Status -eq 'succeeded') {
                Write-Host "Export succeeded. Case id: $CaseId, operation id: $opId -- pass these to Get-EdiscoveryExportPackage.ps1 to download the package."
            }
        }
    }
}

Write-Host 'Done.'
```

#### `policy/ediscovery-case-definition.json`

```json
{
  "_comment": "Reference definition for the eDiscovery (Premium) legal-hold-and-export scenario. Consumed by New-EdiscoveryPremiumLegalHold.ps1 and New-EdiscoverySearchReviewSetExport.ps1 via -DefinitionPath. Author-only reference for the buyer's own tenant -- replace every value below before use. No secrets belong in this file.",
  "case": {
    "displayName": "CONTOSO-LIT-2026-014",
    "description": "Wrongful-termination litigation -- Regional Sales team. Outside counsel: Example & Example LLP.",
    "externalId": "2026-014"
  },
  "custodians": [
    { "email": "dana.chen@contoso.com", "displayName": "Dana Chen (Regional Sales Director)" },
    { "email": "miguel.ortiz@contoso.com", "displayName": "Miguel Ortiz (Sales Ops Manager)" }
  ],
  "search": {
    "displayName": "CONTOSO-LIT-2026-014 - All custodian content",
    "description": "All custodian mailbox/OneDrive content matching the case keyword set and date range, per the litigation hold notice date range agreed with outside counsel.",
    "contentQuery": "(severance OR termination OR \"reduction in force\" OR RIF) AND date>=2025-01-01",
    "dataSourceScopes": "allCaseCustodians"
  },
  "reviewSet": {
    "displayName": "CONTOSO-LIT-2026-014 - Review Set 1"
  },
  "export": {
    "outputName": "CONTOSO-LIT-2026-014 - Export 1 - outside counsel production",
    "description": "First production export for outside counsel review",
    "exportOptions": "originalFiles,tags",
    "exportStructure": "pst"
  }
}
```

#### `Remove-EdiscoveryPremiumLegalHold.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Staged rollback for the eDiscovery (Premium) legal-hold-and-export scenario: release the
    hold on one or more custodians, and optionally close or delete the case.

.DESCRIPTION
    Mirrors the staged approach in rollback.md: releasing a hold is reversible (a released
    custodian can be re-held with New-EdiscoveryPremiumLegalHold.ps1), while closing or deleting
    the case is progressively more destructive. Default behavior only releases holds -- closing
    or deleting the case requires an explicit switch, because Microsoft's own documentation warns
    that closing or deleting a case turns off *every* hold in it and releases any content that
    was preserved only by that hold (README.md section 9 / rollback.md).

    This script never deletes mailbox/OneDrive content itself -- it only removes the eDiscovery
    hold that was preserving it. Whether content becomes eligible for normal deletion/retention
    processing after the hold is released depends on whatever other retention policies (if any)
    independently apply to that mailbox or site -- see rollback.md "What rollback does not undo".

.PARAMETER CaseId
    The eDiscoveryCase id to act on.

.PARAMETER CustodianEmail
    One or more custodian email addresses to release from hold. If omitted, every custodian
    currently on hold in the case is released.

.PARAMETER CloseCase
    After releasing holds, close the case (Microsoft Purview portal equivalent of Actions ->
    Close case). Closing turns off all holds in the case, including any not covered by
    -CustodianEmail -- confirm every custodian's hold is intended to end before passing this.

.PARAMETER DeleteCase
    Permanently delete the case. Implies -CloseCase. Not reversible -- re-establishing the case
    means re-running New-EdiscoveryPremiumLegalHold.ps1 / New-EdiscoverySearchReviewSetExport.ps1
    from scratch against a new case id.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the other deploy/ scripts.

.EXAMPLE
    ./Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports which custodians would be released, without releasing anything.

.EXAMPLE
    ./Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId -CustodianEmail 'dana.chen@contoso.com' `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Releases the hold on a single named custodian; the case and its other custodians (if any)
    are untouched.

.NOTES
    Grounded in Microsoft Learn: ediscoveryCustodian: release (POST .../custodians/{id}/release,
    README.md section 12) and the case-close/delete warning in "Create and manage cases in
    eDiscovery" (README.md section 12). -DeleteCase uses Remove-MgSecurityCaseEdiscoveryCase.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [string[]]$CustodianEmail,

    [switch]$CloseCase,
    [switch]$DeleteCase,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($DeleteCase) { $CloseCase = $true }

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$allCustodians = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All
$targets = if ($CustodianEmail) {
    $allCustodians | Where-Object { $_.Email -in $CustodianEmail }
} else {
    $allCustodians | Where-Object { $_.HoldStatus -eq 'success' }
}

if (-not $targets) {
    Write-Host 'No matching custodians on hold -- nothing to release.'
} else {
    foreach ($custodian in $targets) {
        if ($PSCmdlet.ShouldProcess($custodian.Email, "Release eDiscovery hold (case $CaseId)")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "/v1.0/security/cases/ediscoveryCases/$CaseId/custodians/$($custodian.Id)/release" | Out-Null
            Write-Host "Released hold for custodian '$($custodian.Email)'."
        }
    }
}

if ($CloseCase) {
    Write-Warning 'Closing the case turns off every hold in it, including any custodian not passed via -CustodianEmail. Confirm this is intended before continuing (rollback.md).'
    if ($PSCmdlet.ShouldProcess($CaseId, 'Close eDiscovery case')) {
        Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId -Status 'closed'
        Write-Host "Closed case $CaseId."
    }
}

if ($DeleteCase) {
    if ($PSCmdlet.ShouldProcess($CaseId, 'PERMANENTLY DELETE eDiscovery case')) {
        Remove-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId
        Write-Host "Deleted case $CaseId. This cannot be undone -- see rollback.md."
    }
}

Write-Host 'Done.'
```