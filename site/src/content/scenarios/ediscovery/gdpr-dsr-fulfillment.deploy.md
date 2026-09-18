---
part: "deploy"
parent: "ediscovery/gdpr-dsr-fulfillment"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-DsrRequest.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Intakes a GDPR Data Subject Request (DSR): creates (or reconciles) a single-custodian
    eDiscovery case scoped to the data subject's own mailbox and OneDrive/SharePoint site, and
    upserts a ledger entry tracking the request's GDPR Article 12(3) response-SLA dates.

.DESCRIPTION
    Idempotent, parameterized deploy script for the case-management layer this repo's
    search-and-purge-data-spillage sibling explicitly does not provide (README.md Section 1;
    design.md Section 2). Uses Microsoft Graph (automation surface 3 per docs/automation-surface.md)
    -- the same reason and object model as this repo's premium-legal-hold-and-export and
    search-and-purge-data-spillage siblings: app-only authentication for eDiscovery cmdlets in
    Security & Compliance PowerShell is explicitly unsupported by Microsoft.

    Stages, each individually idempotent (re-running this script is always safe):
      1. Find-or-create the eDiscoveryCase by DisplayName.
      2. Find-or-create the data subject as a single custodian (by email) -- NOT held. A DSR does
         not need, and should not imply, a litigation hold on the requester (design.md Section 3).
      3. Find-or-create that custodian's userSource (mailbox + OneDrive/SharePoint site).
      4. Find-or-create the search, scoped to dataSourceScopes 'allCaseCustodians' (this one
         person's own sources only -- design.md Section 3's blast-radius rationale) with the
         definition file's contentQuery (empty by default -- README.md Section 6).
      4b. (Optional, -IncludeParticipantSearch) Find-or-create a SECOND, tenant-wide search for
          messages where the data subject is a participant (sender/recipient/cc) but the message
          lives in someone ELSE's mailbox -- content a custodian-scoped search cannot see, since it
          only reaches the data subject's own mailbox/site. Off by default: this is a genuine
          Article 15 completeness gap (reviews.md Red Team finding 1), but the fix is a
          dataSourceScopes 'allTenantMailboxes' sweep with the same blast-radius profile this
          repo's search-and-purge-data-spillage sibling already flagged -- an explicit opt-in, not
          a silent default.
      5. Compute the GDPR Article 12(3) SLA dates from receivedDate (one month; a further two
         months if extended) and upsert a ledger entry (JSON array file) recording them alongside
         the case/custodian/search IDs and a free-text Status field this scenario's scripts never
         infer on their own.

    Every mutating Graph cmdlet used here (New-MgSecurityCaseEdiscoveryCase,
    New-MgSecurityCaseEdiscoveryCaseCustodian, New-MgSecurityCaseEdiscoveryCaseCustodianUserSource,
    New-MgSecurityCaseEdiscoveryCaseSearch) natively implements ShouldProcess, so -WhatIf on this
    script fans out to a true dry run on every Graph call. The ledger write is also gated behind
    -WhatIf via an explicit ShouldProcess check, since it is this scenario's own state, not
    Microsoft's, and is not itself idempotent-by-Graph-object-identity.

    This script never exports, purges, or otherwise fulfills the request -- see README.md Section 5
    for the request-type-specific hand-off to this repo's already-built export/purge scripts, and
    Section 6 for why Rectification/Restriction/Objection have no technical fulfillment step here at
    all.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/dsr-request-definition.sample.json's shape.

.PARAMETER LedgerPath
    Path to the ledger JSON file (a simple JSON array of request records). Created if it doesn't
    exist. Defaults to ./dsr-ledger.json alongside this script. Treat this file as confidential --
    it accumulates every request's data-subject email/name and SLA dates (README.md Section 11).

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store, used
    for certificate-based app-only authentication (docs/automation-surface.md Section 3). Mutually
    exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object (for example, resolved from Key Vault at run time) to use
    instead of -CertificateThumbprint. Mutually exclusive with -CertificateThumbprint.

.PARAMETER IncludeParticipantSearch
    Also create a second, tenant-wide search (dataSourceScopes 'allTenantMailboxes', contentQuery
    'participants:<email>') for messages where the data subject is a sender/recipient/cc but the
    message lives in someone else's mailbox -- content the primary custodian-scoped search cannot
    see. Off by default because it carries the same tenant-wide blast-radius profile this repo's
    search-and-purge-data-spillage sibling already flags for allTenantMailboxes sweeps (README.md
    Section 11; reviews.md Red Team finding 1) -- opt in deliberately for an Access/Portability
    request where completeness matters more than the broader estimate/review surface.

.PARAMETER Status
    Update the ledger entry's Status field on this run (for example 'Reviewing', 'Fulfilled',
    'Closed'). This scenario never sets Status itself beyond the initial 'Discovery' -- it's a
    manual case-management field the operator drives.

.PARAMETER ApplyExtension
    Record that the Article 12(3) two-further-months extension has been invoked for this request
    (sets ExtensionApplied = $true and ExtensionAppliedDate = today in the ledger). This script does
    NOT notify the data subject -- Article 12(3) requires that notification, with reasons, within
    the original one-month period; sending it is the operator's own action (README.md Section 6).

.PARAMETER ExtensionReason
    Free-text reason recorded alongside -ApplyExtension, for the organization's own accountability
    record (Article 5(2)).

.EXAMPLE
    ./New-DsrRequest.ps1 -DefinitionPath ./policy/dsr-request-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/custodian/userSource/search/ledger action this run would take, without
    calling any mutating Graph endpoint or writing the ledger file.

.EXAMPLE
    ./New-DsrRequest.ps1 -DefinitionPath ./policy/dsr-request-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case/custodian/userSource/search (if they don't already exist) and writes/updates
    the ledger entry with the computed SLA dates.

.EXAMPLE
    ./New-DsrRequest.ps1 -DefinitionPath ./policy/dsr-request-definition.sample.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint `
        -Status Fulfilled

    Re-runs the reconciliation (a no-op against Graph, since everything already exists) and updates
    the ledger entry's Status to 'Fulfilled'.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md Section 12 for the full citation list. Cmdlet names and request
    shapes used here:
      - New-MgSecurityCaseEdiscoveryCase                    (POST /security/cases/ediscoveryCases)
      - New-MgSecurityCaseEdiscoveryCaseCustodian            (POST .../custodians)
      - New-MgSecurityCaseEdiscoveryCaseCustodianUserSource  (POST .../custodians/{id}/userSources)
      - New-MgSecurityCaseEdiscoveryCaseSearch               (POST .../searches, dataSourceScopes
                                                                'allCaseCustodians')

    A Graph-created case is an eDiscovery (Premium)-configured case -- see README.md Section 3 for
    the licensing implication, the same finding this repo's search-and-purge-data-spillage sibling
    already made for its own Graph-created case.

    The ledger is this scenario's own bookkeeping, not a Microsoft Purview object -- there is no
    Graph/PowerShell API for "GDPR request SLA tracking." Store it somewhere access-controlled and
    backed up; it is the only record of the Article 12(3) due dates once you close this terminal.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [string]$LedgerPath = (Join-Path $PSScriptRoot 'dsr-ledger.json'),

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [ValidateSet('Discovery', 'Reviewing', 'Fulfilled', 'Closed')]
    [string]$Status,

    [switch]$ApplyExtension,
    [string]$ExtensionReason,

    [switch]$IncludeParticipantSearch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ValidRequestTypes = @('Access', 'Portability', 'Erasure', 'Rectification', 'Restriction', 'Objection')

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)
    if (Get-MgContext) { Write-Verbose 'Reusing existing Microsoft Graph connection.'; return }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

function Get-OrNewDsrCase {
    param($Definition)

    $existing = Get-MgSecurityCaseEdiscoveryCase -All |
        Where-Object { $_.DisplayName -eq $Definition.caseDisplayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Case '$($Definition.caseDisplayName)' already exists (id=$($existing.Id))."
        return $existing
    }

    $body = @{
        displayName = $Definition.caseDisplayName
        description = "GDPR DSR $($Definition.requestId) ($($Definition.requestType))"
        externalId  = $Definition.requestId
    }
    if ($PSCmdlet.ShouldProcess($Definition.caseDisplayName, 'Create eDiscovery case')) {
        $created = New-MgSecurityCaseEdiscoveryCase -BodyParameter $body
        Write-Host "Created case '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<case-id-pending>'; DisplayName = $Definition.caseDisplayName }
}

function Get-OrNewSubjectCustodian {
    param($CaseId, $Email)

    $existing = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.Email -eq $Email } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Custodian '$Email' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add data subject as custodian to case $CaseId (NOT held)")) {
        $created = New-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -Email $Email
        Write-Host "Added custodian '$($created.Email)' (id=$($created.Id)). No hold applied -- a DSR does not require or imply one (design.md Section 3)."
        return $created
    }
    return [pscustomobject]@{ Id = '<custodian-id-pending>'; Email = $Email }
}

function Confirm-SubjectUserSource {
    param($CaseId, $CustodianId, $Email)

    $existingSources = @()
    try {
        $existingSources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource `
            -EdiscoveryCaseId $CaseId -EdiscoveryCustodianId $CustodianId -All
    } catch {
        Write-Verbose "Could not list existing userSources for custodian $CustodianId (expected under -WhatIf on a not-yet-created custodian)."
    }
    if ($existingSources | Where-Object { $_.Email -eq $Email }) {
        Write-Verbose "userSource for '$Email' already exists on custodian $CustodianId."
        return
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add mailbox + OneDrive/SharePoint site userSource to custodian $CustodianId")) {
        # includedSources 'mailbox, site' -- same combined-string form this repo's
        # premium-legal-hold-and-export sibling uses; README.md Section 11 carries forward that
        # sibling's own VERIFY on whether the v1.0 endpoint accepts this combined form or only a
        # single value at a time.
        New-MgSecurityCaseEdiscoveryCaseCustodianUserSource -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $CustodianId -Email $Email -IncludedSources 'mailbox, site' | Out-Null
        Write-Host "Added userSource (mailbox, site) for '$Email'."
    }
}

function Get-OrNewSubjectSearch {
    param($CaseId, $Definition)

    $searchDisplayName = "$($Definition.requestId) - all custodian sources"
    $existing = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.DisplayName -eq $searchDisplayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Search '$searchDisplayName' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($searchDisplayName, "Create eDiscovery search in case $CaseId (dataSourceScopes=allCaseCustodians)")) {
        $created = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId `
            -DisplayName $searchDisplayName `
            -Description "Discovery search for GDPR DSR $($Definition.requestId) -- scoped to the data subject's own custodian sources only." `
            -ContentQuery $Definition.contentQuery `
            -DataSourceScopes 'allCaseCustodians'
        Write-Host "Created search '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<search-id-pending>'; DisplayName = $searchDisplayName }
}

function Get-OrNewParticipantSearch {
    param($CaseId, $Definition)

    $searchDisplayName = "$($Definition.requestId) - participant mentions (tenant-wide)"
    $existing = Get-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.DisplayName -eq $searchDisplayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Search '$searchDisplayName' already exists (id=$($existing.Id))."
        return $existing
    }

    # participants: expands to an Entra ID identity lookup (SMTP/alias/display name) across
    # From/To/Cc/Bcc/Recipients -- README.md Section 12 reference 4-adjacent KQL grounding.
    # dataSourceScopes allTenantMailboxes is the SAME blast-radius tradeoff
    # search-and-purge-data-spillage already made and disclosed -- not a new, unreviewed risk.
    $query = "participants:$($Definition.dataSubject.email)"
    if ($PSCmdlet.ShouldProcess($searchDisplayName, "Create tenant-wide participant search in case $CaseId (dataSourceScopes=allTenantMailboxes)")) {
        $created = New-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $CaseId `
            -DisplayName $searchDisplayName `
            -Description "Tenant-wide participant search for GDPR DSR $($Definition.requestId) -- catches messages about the data subject stored in OTHER mailboxes, which the custodian-scoped search cannot reach." `
            -ContentQuery $query `
            -DataSourceScopes 'allTenantMailboxes'
        Write-Host "Created search '$($created.DisplayName)' (id=$($created.Id)). Review its estimate before treating results as safe to export/purge -- tenant-wide scope (README.md Section 11)."
        return $created
    }
    return [pscustomobject]@{ Id = '<participant-search-id-pending>'; DisplayName = $searchDisplayName }
}

function Get-DsrSlaDates {
    param([datetime]$ReceivedDate)
    # GDPR Article 12(3): one month, extendable by two further months where necessary --
    # README.md Section 4/References. Calendar-month arithmetic (AddMonths), not a fixed 30/90-day
    # count -- matches how Article 12(3) itself is phrased ("within one month of receipt").
    [pscustomobject]@{
        DueDate            = $ReceivedDate.AddMonths(1)
        MaxExtendedDueDate = $ReceivedDate.AddMonths(3)
    }
}

function Read-DsrLedger {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Save-DsrLedger {
    param([string]$Path, [array]$Ledger)
    if ($PSCmdlet.ShouldProcess($Path, 'Write DSR ledger')) {
        $Ledger | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding utf8
        Write-Host "Ledger written to $Path ($($Ledger.Count) request(s))."
    } else {
        Write-Host "(-WhatIf) Would write ledger to $Path ($($Ledger.Count) request(s))."
    }
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

if ($definition.requestType -notin $ValidRequestTypes) {
    throw "Definition file requestType '$($definition.requestType)' is not one of: $($ValidRequestTypes -join ', ')."
}
$receivedDate = [datetime]::ParseExact($definition.receivedDate, 'yyyy-MM-dd', $null)

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-OrNewDsrCase -Definition $definition
$custodian = Get-OrNewSubjectCustodian -CaseId $case.Id -Email $definition.dataSubject.email
Confirm-SubjectUserSource -CaseId $case.Id -CustodianId $custodian.Id -Email $definition.dataSubject.email
$search = Get-OrNewSubjectSearch -CaseId $case.Id -Definition $definition

$participantSearchId = $null
if ($IncludeParticipantSearch) {
    $participantSearch = Get-OrNewParticipantSearch -CaseId $case.Id -Definition $definition
    $participantSearchId = $participantSearch.Id
}

$sla = Get-DsrSlaDates -ReceivedDate $receivedDate

$ledger = Read-DsrLedger -Path $LedgerPath
$entry = $ledger | Where-Object { $_.requestId -eq $definition.requestId } | Select-Object -First 1

if ($entry) {
    Write-Verbose "Ledger already has an entry for $($definition.requestId) -- updating in place."
    if ($Status) { $entry.status = $Status }
    if ($ApplyExtension) {
        $entry.extensionApplied = $true
        $entry.extensionAppliedDate = (Get-Date).ToString('yyyy-MM-dd')
        $entry.extensionReason = $ExtensionReason
    }
    $entry.caseId = $case.Id
    $entry.custodianId = $custodian.Id
    $entry.searchId = $search.Id
    if ($participantSearchId) { $entry.participantSearchId = $participantSearchId }
    $entry.lastUpdated = (Get-Date).ToString('s')
} else {
    $entry = [pscustomobject]@{
        requestId            = $definition.requestId
        requestType          = $definition.requestType
        dataSubjectEmail     = $definition.dataSubject.email
        dataSubjectDisplayName = $definition.dataSubject.displayName
        receivedDate         = $definition.receivedDate
        dueDate              = $sla.DueDate.ToString('yyyy-MM-dd')
        maxExtendedDueDate   = $sla.MaxExtendedDueDate.ToString('yyyy-MM-dd')
        extensionApplied     = [bool]$ApplyExtension
        extensionAppliedDate = $(if ($ApplyExtension) { (Get-Date).ToString('yyyy-MM-dd') } else { $null })
        extensionReason      = $(if ($ApplyExtension) { $ExtensionReason } else { $null })
        status               = $(if ($Status) { $Status } else { 'Discovery' })
        caseId               = $case.Id
        custodianId          = $custodian.Id
        searchId             = $search.Id
        participantSearchId  = $participantSearchId
        lastUpdated          = (Get-Date).ToString('s')
    }
    $ledger = @($ledger) + $entry
}

Save-DsrLedger -Path $LedgerPath -Ledger $ledger

Write-Host ''
Write-Host "=== GDPR DSR $($definition.requestId) ($($definition.requestType)) ==="
Write-Host "  Case:               '$($case.DisplayName)' (id=$($case.Id))"
Write-Host "  Data subject:       $($definition.dataSubject.email)"
Write-Host "  Received:           $($definition.receivedDate)"
Write-Host "  Due (Art. 12(3)):   $($entry.dueDate)  (extend to $($entry.maxExtendedDueDate) if invoked -- notify the data subject within the first month, with reasons)"
Write-Host "  Status:             $($entry.status)"
if ($participantSearchId) {
    Write-Host "  Participant search: $participantSearchId (tenant-wide -- review its estimate separately before including its results in an Access/Portability export or an Erasure purge)."
}
Write-Host ''
switch ($definition.requestType) {
    { $_ -in @('Access', 'Portability') } {
        Write-Host 'Next (Access/Portability -- README.md Section 5): review this search''s estimate, then hand off to premium-legal-hold-and-export''s review-set/export scripts, pointed at this case/search:'
        Write-Host "  ../premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1 -CaseId $($case.Id) -SearchId $($search.Id) -AppId `$AppId -TenantId `$TenantId -CertificateThumbprint `$Thumbprint -WhatIf"
        if ($definition.requestType -eq 'Portability') {
            Write-Host '  NOTE: confirm the export format satisfies Article 20''s "structured, commonly used, machine-readable format" requirement before delivering it -- README.md Section 11.'
        }
    }
    'Erasure' {
        Write-Host 'Next (Erasure -- README.md Section 5): review this search''s estimate, then hand off to search-and-purge-data-spillage''s purge script, pointed at this case/search:'
        Write-Host "  ../search-and-purge-data-spillage/deploy/Invoke-DataSpillagePurge.ps1 -CaseId $($case.Id) -SearchId $($search.Id) -PurgeType Recoverable -AppId `$AppId -TenantId `$TenantId -CertificateThumbprint `$Thumbprint -WhatIf"
        Write-Host '  If any located content is under a litigation hold, purge will not remove it -- see that sibling''s hand-off to priority-cleanup-exchange-data-spillage (README.md Section 5).'
    }
    default {
        Write-Host "Next ($($definition.requestType) -- README.md Section 6): this scenario's technical scope ends at Discovery. Fulfillment is a manual/process action outside Purview's technical surface -- review the search results to identify affected records, then complete the change in the system of record."
    }
}
```

#### `policy/dsr-request-definition.sample.json`

```json
{
  "_comment": "Illustrative values only -- replace before use. This file identifies a real data subject (email, display name) and, once New-DsrRequest.ps1 runs, becomes the definition behind a live eDiscovery case and ledger entry. Treat it and the ledger file (dsr-ledger.json) as confidential for the life of the request -- same discipline this repo's search-and-purge-data-spillage/deploy/policy/data-spillage-search-definition.sample.json applies to its own sensitive query text.",
  "requestId": "DSR-2026-0001",
  "requestType": "Access",
  "_requestTypeComment": "One of: Access, Portability, Erasure, Rectification, Restriction, Objection. See README.md Section 6 for what this scenario's scripts do (and don't do) for each value.",
  "dataSubject": {
    "email": "ada.lovelace@contoso.com",
    "displayName": "Ada Lovelace"
  },
  "receivedDate": "2026-09-16",
  "_receivedDateComment": "The date the organization received the request (not the date this script runs) -- New-DsrRequest.ps1 computes the GDPR Article 12(3) one-month/three-month SLA dates from this value. Format: yyyy-MM-dd.",
  "caseDisplayName": "DSR-2026-0001 - Access",
  "_caseDisplayNameComment": "Avoid putting the data subject's name or email directly in the case DisplayName if your organization's case-naming convention is itself visible to a broader audience than the request warrants (e.g. a shared case list) -- the requestId alone is enough for this scenario's scripts to reconcile the case.",
  "contentQuery": "",
  "_contentQueryComment": "KQL (optional -- Microsoft's Create searches reference documents contentQuery as optional). Empty string returns everything in the custodian's mailbox + OneDrive/SharePoint site (README.md Section 6) -- the right default for an Access/Portability/Erasure request, which is about ALL of the person's data, not a keyword subset. Narrow this only for a Rectification/Restriction/Objection request scoped to specific, already-identified records.",
  "notes": "Optional free-text context: intake channel, identity-verification method used, or other case-management detail not otherwise captured."
}
```