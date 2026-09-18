---
part: "deploy"
parent: "communication-compliance/financial-regulatory-supervision"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-FinraSupervisionEvidence.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Communication Compliance policy matches, policy changes, and
    review-tag activity from the unified audit log, and derives a FINRA Rule 3110(b)(4)
    evidence-of-review log from the review-tag events.

.DESCRIPTION
    Communication Compliance has no write API this repo's other deploy scripts could target (see
    design.md Section 2) - policy creation, condition tuning, reviewer assignment, and population
    scoping are portal-only. This script targets the one thing about Communication Compliance that
    IS reachable through a documented API: its footprint in the Microsoft 365 unified audit log, via
    Search-UnifiedAuditLog (automation surface 1 per docs/automation-surface.md Section 1).

    This script issues the SAME three Search-UnifiedAuditLog query categories as the sibling
    scenario's Export-CommunicationComplianceAuditTrail.ps1 (scenarios/communication-compliance/
    harassment-and-code-of-conduct/) - these operations are Communication-Compliance-wide, not
    policy-specific, so re-deriving them per scenario would be pure duplication (design.md Section 2):

      1. Policy match   - Operations SupervisionRuleMatch
      2. Policy update   - RecordType Discovery, Operations SupervisionPolicyCreated /
         SupervisionPolicyUpdated / SupervisionPolicyDeleted
      3. Review tag       - RecordType AeD, Operations SupervisoryReviewTag

    WHAT THIS SCRIPT ADDS beyond the sibling: a second output file, the FINRA Rule 3110(b)(4)
    evidence-of-review log, derived entirely from the ReviewTag category's rows. FINRA Rule 3110(b)(4)
    requires that evidence of a supervisory review identify (a) the reviewer, (b) the correspondence/
    communication reviewed, (c) the review date, and (d) any action taken as a result. This script
    maps ReviewTag rows to those four fields as follows:
      (a) Reviewer     -> UserIds (the account that performed the review action)
      (b) Content ref   -> best-available identifier from AuditData (see VERIFY below - Communication
                           Compliance's audit trail does not expose the actual message content, only a
                           reference to the review action itself)
      (c) Review date   -> CreationDate
      (d) Action taken  -> parsed defensively from the AuditData JSON payload - see VERIFY below

    VERIFY (pilot tenant, README.md Section 11): this script could NOT confirm, without a direct
    Microsoft Learn fetch or a pilot tenant, the exact AuditData JSON property name Microsoft
    populates with the specific remediation action (Resolve/Tag as/Escalate/Notify/Remove) on a
    SupervisoryReviewTag event. Rather than guess a property name that might not exist (AGENTS.md
    Section 4's no-invented-fields rule), this script tries a short list of plausible candidate
    property names (see $actionPropertyCandidates below) and, if none match, falls back to surfacing
    the raw AuditData JSON string so no information is silently dropped. Confirm the real property
    name against a pilot tenant and update $actionPropertyCandidates accordingly.

    Idempotency model: identical rolling-history, merge-and-de-duplicate approach as the sibling
    script - both output files accumulate discrete events across potentially-overlapping date-range
    calls, de-duplicated by a composite key of (CreationDate, Operations, UserIds, a stable hash of
    the full AuditData JSON payload). See design.md Section 8.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only against the tenant: it never creates, modifies, or deletes any policy, alert, or
    message - the only side effects are the two CSV files this script writes, both gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports what would be merged without touching disk.

    This script does NOT capture actual message content - see README.md Section 11.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Defaults to 7 days before -EndDate, suitable for a
    daily scheduled run with deliberate overlap (idempotent de-duplication makes overlap safe).

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER AuditTrailCsvPath
    Path to the rolling audit-trail CSV (all three query categories, matching the sibling scenario's
    schema exactly). Created with a header row if it doesn't already exist; otherwise new,
    non-duplicate records are merged in.

.PARAMETER EvidenceOfReviewCsvPath
    Path to the rolling FINRA Rule 3110(b)(4) evidence-of-review CSV, derived from the ReviewTag
    category rows only. Created with a header row if it doesn't already exist.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size when not using -SessionCommand ReturnLargeSet.
    Defaults to 5000 (the cmdlet's documented per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The three Search-UnifiedAuditLog queries still execute
    (read-only; needed to report accurate would-be results), but neither CSV file is written - the
    script prints the count of new, non-duplicate records it would have merged into each.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-FinraSupervisionEvidence.ps1 -AuditTrailCsvPath './out/finra-audit-trail.csv' `
        -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv' -WhatIf

    Dry run: queries the last 7 days across all three categories and reports how many new records
    would be merged into each output file, writes nothing.

.EXAMPLE
    ./Export-FinraSupervisionEvidence.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -AuditTrailCsvPath './out/finra-audit-trail.csv' `
        -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv'

    A one-time backfill covering the full default Audit (Standard) retention window (README.md
    Section 11) before the first scheduled recurring run.

.NOTES
    VERIFY before relying on this for an examiner-facing evidence-of-review record beyond 180 days:
    default Audit (Standard) retention is 180 days for most workloads (one year for Entra ID/Exchange/
    OneDrive/SharePoint under an E5-tier license). Run this script on a recurring schedule (README.md
    Section 8) if the evidentiary window needed exceeds that retention.

    VERIFY (pilot tenant): the exact AuditData JSON property name for the remediation action taken on
    a SupervisoryReviewTag event - see the DESCRIPTION above and $actionPropertyCandidates below.

    Sources (WebSearch-corroborated; this build's network cannot directly fetch learn.microsoft.com -
    design.md Section 10, verify before production use):
    - Audit log activities - Communication compliance activities table:
      https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities
    - Use Communication Compliance reports and audits (Discovery/AeD RecordType + Operations worked
      examples this script's three queries are built from, matching the harassment sibling's script):
      https://learn.microsoft.com/purview/communication-compliance-reports-audits
    - Use Communication Compliance with SIEM solutions (SupervisionRuleMatch worked example):
      https://learn.microsoft.com/purview/communication-compliance-siem
    - Search-UnifiedAuditLog reference: https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - FINRA Rule 3110(b)(4) - the four evidence-of-review elements this script's derivation targets:
      https://www.finra.org/rules-guidance/rulebooks/finra-rules/3110
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter()]
    [datetime]$StartDate = ([datetime]::UtcNow.AddDays(-7)),

    [Parameter()]
    [datetime]$EndDate = ([datetime]::UtcNow),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EvidenceOfReviewCsvPath,

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

# Three query categories, identical to the harassment sibling's script (design.md Section 2) - these
# are Communication-Compliance-wide events, not specific to this scenario's policy.
$queryCategories = @(
    @{ Category = 'PolicyMatch'; RecordType = $null; Operations = @('SupervisionRuleMatch') }
    @{ Category = 'PolicyUpdate'; RecordType = 'Discovery'; Operations = @('SupervisionPolicyCreated', 'SupervisionPolicyUpdated', 'SupervisionPolicyDeleted') }
    @{ Category = 'ReviewTag'; RecordType = 'AeD'; Operations = @('SupervisoryReviewTag') }
)

# Candidate AuditData property names for the remediation action taken on a SupervisoryReviewTag
# event. UNCONFIRMED against a pilot tenant or a direct Microsoft Learn fetch (see .NOTES) - tried in
# order; the first one present on a given record's parsed AuditData is used. If none match, the raw
# AuditData JSON is surfaced instead of guessing, per AGENTS.md Section 4.
$actionPropertyCandidates = @('ReviewTag', 'Tag', 'Action', 'RemediationAction', 'Status')

function Get-StableStringHash {
    # Deterministic, cross-session-stable hash (unlike .NET's [string]::GetHashCode(), which is
    # randomized per process by default) - used only to fold a full AuditData JSON payload into a
    # fixed-width key component, never for anything security-sensitive.
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
    # De-duplication key for the rolling merge (design.md Section 8): CreationDate, Operations, and
    # UserIds are all confirmed top-level Search-UnifiedAuditLog output properties; a hash of the full
    # AuditData JSON payload (confirmed present on every record) is folded in as a fourth component
    # rather than assuming an always-present unique-ID property exists (AGENTS.md Section 4).
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

function Merge-CsvRows {
    # Shared merge-and-de-duplicate helper for both output files (design.md Section 8).
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$NewRows,
        [Parameter(Mandatory)][string]$Description
    )
    $existingRows = @()
    if (Test-Path -Path $Path -PathType Leaf) {
        $existingRows = @(Import-Csv -Path $Path)
    }
    $existingKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]($existingRows | ForEach-Object { $_.CompositeKey }))
    $rowsToAdd = @($NewRows | Where-Object { -not $existingKeys.Contains($_.CompositeKey) })

    Write-Host "$Description : $($rowsToAdd.Count) new, non-duplicate record(s) to merge (of $($NewRows.Count) fetched)." -ForegroundColor Cyan

    if ($rowsToAdd.Count -eq 0) {
        Write-Host "$Description : nothing to merge - CSV already up to date for this window." -ForegroundColor Yellow
        return
    }
    if ($PSCmdlet.ShouldProcess($Path, "Merge $($rowsToAdd.Count) new record(s) into '$Path'")) {
        $allRows = @($existingRows) + @($rowsToAdd)
        $allRows | Sort-Object CreationDate | Export-Csv -Path $Path -NoTypeInformation
        Write-Host "$Description : updated $Path ($($allRows.Count) total row(s))." -ForegroundColor Green
    }
    else {
        Write-Verbose "WhatIf: would merge $($rowsToAdd.Count) record(s) into '$Path'"
    }
}

$allRecords = [System.Collections.Generic.List[object]]::new()

foreach ($query in $queryCategories) {
    Write-Host "Searching unified audit log: category '$($query.Category)' (RecordType=$($query.RecordType); Operations=$($query.Operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

    $sessionId = "finra-evidence-$($query.Category)-$([guid]::NewGuid())"
    do {
        $searchParams = @{
            StartDate      = $StartDate
            EndDate        = $EndDate
            Operations     = $query.Operations
            ResultSize     = $ResultSize
            SessionId      = $sessionId
            SessionCommand = 'ReturnLargeSet'
        }
        if ($query.RecordType) { $searchParams['RecordType'] = $query.RecordType }

        # Wrapping in @() avoids PowerShell's single-object-vs-array ambiguity for a one-record page.
        $page = @(Search-UnifiedAuditLog @searchParams)
        foreach ($record in $page) {
            $record | Add-Member -NotePropertyName 'QueryCategory' -NotePropertyValue $query.Category -Force
        }
        if ($page.Count -gt 0) { $allRecords.AddRange($page) }
    } while ($page.Count -gt 0)
}

Write-Host "Found $($allRecords.Count) matching record(s) across all three categories in the search window." -ForegroundColor Green

# --- Output 1: the rolling audit-trail CSV (identical schema to the harassment sibling's script) ---
# Wrapped in @() so an empty $allRecords produces an empty array, not $null - Merge-CsvRows's
# -NewRows parameter is Mandatory and a bare $null would fail parameter binding.
$auditTrailRows = @(foreach ($record in $allRecords) {
    [pscustomobject]@{
        CreationDate = $record.CreationDate
        Category     = $record.QueryCategory
        Operation    = $record.Operations
        UserIds      = $record.UserIds
        RecordType   = $record.RecordType
        AuditData    = $record.AuditData
        CompositeKey = (Get-CompositeKey -Record $record)
    }
})
Merge-CsvRows -Path $AuditTrailCsvPath -NewRows $auditTrailRows -Description 'Audit trail'

$policyUpdateRows = @($auditTrailRows | Where-Object { $_.Category -eq 'PolicyUpdate' })
foreach ($row in $policyUpdateRows) {
    Write-Warning "Policy change detected: $($row.Operation) by $($row.UserIds) at $($row.CreationDate). Confirm this matches an intended, documented change and that the firm's WSPs still describe the policy accurately - see README.md Section 5 step 11 and Section 8."
}

# --- Output 2: the FINRA Rule 3110(b)(4) evidence-of-review CSV, derived from ReviewTag rows only ---
$reviewTagRecords = @($allRecords | Where-Object { $_.QueryCategory -eq 'ReviewTag' })

$evidenceRows = @(foreach ($record in $reviewTagRecords) {
    $actionTaken = $null
    $parsedAuditData = $null
    try {
        $parsedAuditData = $record.AuditData | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not parse AuditData as JSON for a ReviewTag record at $($record.CreationDate) - carrying the raw value forward unparsed."
    }
    if ($parsedAuditData) {
        foreach ($candidate in $actionPropertyCandidates) {
            if ($parsedAuditData.PSObject.Properties.Name -contains $candidate) {
                $actionTaken = $parsedAuditData.$candidate
                break
            }
        }
    }
    if (-not $actionTaken) {
        # None of the candidate property names matched. Point at the AuditData column already on
        # this same row rather than re-embedding the full raw JSON a second time here - duplicating
        # a potentially large payload across two columns of the same row bloats every unconfirmed
        # row for no benefit and complicates downstream SIEM ingestion (reviews.md Blue Team finding).
        $actionTaken = 'UNCONFIRMED - no recognized action property found; see this row''s own AuditData column for the raw payload'
    }

    [pscustomobject]@{
        Reviewer         = $record.UserIds
        ReviewDate       = $record.CreationDate
        ContentReference = "SupervisoryReviewTag event at $($record.CreationDate) - see AuditData for the full payload; Communication Compliance's audit trail does not expose the reviewed message's own content, only a reference to the review action (README.md Section 11)"
        ActionTaken      = $actionTaken
        AuditData        = $record.AuditData
        CompositeKey     = (Get-CompositeKey -Record $record)
    }
})
Merge-CsvRows -Path $EvidenceOfReviewCsvPath -NewRows $evidenceRows -Description 'FINRA 3110(b)(4) evidence-of-review'

if (@($evidenceRows).Count -gt 0) {
    Write-Host "$(@($evidenceRows).Count) evidence-of-review record(s) processed this run - confirm each shows a reviewer who holds an appropriate FINRA registration (design.md Section 6; Purview cannot verify this for you)." -ForegroundColor Cyan
}
```

#### `policy/financial-regulatory-supervision-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Communication Compliance has no documented REST, Graph, or PowerShell write API for policy creation or management as of this writing - see design.md Section 2. No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed policy can be diffed against intent during review. Follows the same precedent set by scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/policy/communication-compliance-policy-manifest.json for this module's portal-only surface.",
  "policyType": "custom",
  "policyName": "Financial Regulatory Compliance Supervision - Registered Representatives",
  "policyNameNote": "Policy names cannot be changed after creation. Confirm before creating.",
  "locations": [
    "Exchange Online",
    "Microsoft Teams"
  ],
  "locationsNote": "Viva Engage is optional - add only if the firm's registered representatives actually conduct business communication there. Third-party financial messaging platforms (Bloomberg Message/Mail, ICE Chat, Reuters Eikon Messenger, Symphony, and the other Microsoft-documented native data connectors) are explicitly out of scope for this scenario - see design.md Section 7. A firm relying on those platforms for trading-floor communication must supervise them through their own dedicated connector setup, not assume this policy covers them.",
  "direction": [
    "Inbound",
    "Outbound",
    "Internal"
  ],
  "directionNote": "Internal is deliberately included - desk-to-desk internal chat is exactly where collusion/stock-manipulation language is most likely to appear, unlike external customer correspondence alone.",
  "usersInScope": {
    "option": "group",
    "note": "The firm's FINRA-registered/supervised-person population, sourced from its own broker-dealer registration or HR system and reflected in an Entra ID group or adaptive scope - NOT 'All users'. See design.md Section 3 for why this scenario deliberately departs from the harassment-and-code-of-conduct sibling's all-users scoping. This scenario does not derive or reconcile this population automatically - see design.md Section 7 (Non-goals).",
    "placeholderGroupName": "FINRA-Registered-Representatives"
  },
  "excludedUsersAndGroups": [],
  "reviewers": {
    "roleGroup": "Communication Compliance Investigators",
    "note": "Investigators (not Analysts) because a substantive Rule 3110(b)(4) supervisory judgment requires full message content, not metadata-only access (README.md Section 3, design.md Section 6). GATING REQUIREMENT beyond Purview's own RBAC: every named reviewer below must separately hold an appropriate FINRA registration (e.g. a Series 24 principal, or a documented delegated-review designee under the firm's written supervisory procedures) - Communication Compliance has no native concept of FINRA registration status and will not enforce this for you.",
    "placeholderMembers": [
      "compliance-principal-1@contoso.example",
      "compliance-principal-2@contoso.example"
    ]
  },
  "conditions": {
    "trainableClassifiers": [
      { "name": "Corporate sabotage", "note": "Deliberate destruction/damage to corporate assets or property - part of the Regulatory compliance classifier family this scenario draws from, though Microsoft frames its primary use case around sector regulation like NERC CIP rather than broker-dealer supervision specifically." },
      { "name": "Customer complaints", "note": "Maps to FINRA Rule 4530 customer-complaint reporting and CFPB-style complaint-detection obligations." },
      { "name": "Gifts & entertainment", "note": "Maps to FINRA Rule 3220 (Influencing or Rewarding Employees of Others) and firm gifts/entertainment policies." },
      { "name": "Money laundering", "note": "Signs of concealing/disguising the origin or destination of proceeds." },
      { "name": "[Workplace/Regulatory] collusion", "note": "NAMING VERIFY (design.md Section 5, README.md Section 11): this build found this classifier referred to as both 'Regulatory collusion' and 'Workplace collusion' across independent secondary sources, and could not directly fetch Microsoft's canonical classifier-definitions page to resolve which is the current portal-UI label. Confirm at deploy time. Detects price fixing, trade-secret sharing, coordinated buying strategies, and secretive/concealing behavior." },
      { "name": "Stock manipulation", "note": "Recommendations to buy/sell/hold stock to manipulate price - the core classifier for FINRA/SEC market-manipulation supervision." },
      { "name": "Unauthorized disclosure", "note": "Sharing of explicitly confidential/internal-only information - most directly relevant to insider-trading/MNPI-leakage supervision." }
    ],
    "customKeywordDictionary": {
      "file": "finra-supervision-evasion-phrases.txt",
      "purpose": "Concealment/evasion phrasing only (e.g. 'let's discuss offline') - the exact phrasing regulators cite in off-channel-communications enforcement actions as evidence traders knew to route sensitive discussion around a monitored channel. NEVER add restricted-list ticker symbols, issuer names, or deal codenames to this file or its production equivalent - the restricted list is itself confidential supervisory information and a keyword dictionary that reveals what the firm is watching for is a liability. See design.md Section 5 and reviews.md Red Team."
    },
    "conditionCombination": "OR (Content matches any of these classifiers) OR (Message/Attachment contains any of these words, from the custom keyword dictionary)"
  },
  "reviewPercentage": 100,
  "reviewPercentageNote": "Shipped as this scenario's default because an UNREVIEWED match under a FINRA-registered-person population is a documented Rule 3110(b)(4) supervisory-review gap, not merely a missed alert (design.md Section 8) - a materially different risk posture from the harassment sibling's alert-fatigue framing. Regulators do not mandate a fixed sampling percentage; lowering this below 100% is the firm's own written-supervisory-procedures decision requiring Compliance/Legal sign-off, not a default this scenario recommends. Record any deviation here.",
  "filterEmailBlasts": true,
  "ocrEnabled": true,
  "privacySettings": {
    "usernamePseudonymization": true,
    "note": "Settings > Communication Compliance > Privacy tab > 'Show anonymized versions of usernames' - portal-only, tenant-wide setting, not per-policy."
  },
  "noticeTemplate": {
    "create": true,
    "name": "Regulatory Supervision Notice",
    "note": "Only needed if the firm's escalation path uses the 'Notify' remediation action (README.md Section 5, step 10)."
  },
  "wspAlignment": {
    "required": true,
    "note": "README.md Section 5, step 11: the firm's own written supervisory procedures (WSPs) must document the review percentage, escalation path, and registered-principal assignments this policy actually implements. A correctly configured policy that the WSPs don't describe is still an examination finding waiting to happen."
  },
  "outOfScope": {
    "thirdPartyConnectors": "Bloomberg Message/Mail, ICE Chat, Reuters Eikon Messenger, Symphony, and other Microsoft-documented native data connectors - design.md Section 7, a candidate follow-up fragment.",
    "retentionOfCommunications": "SEC 17a-4 / FINRA 4511 books-and-records retention of the underlying communications is handled by scenarios/data-lifecycle-management/retention-labels-financial-records/, not this scenario - design.md Section 7/Section 8.",
    "registeredRepresentativePopulationDerivation": "This scenario assumes usersInScope.placeholderGroupName already exists and is kept current by the firm's own registration/HR process - design.md Section 7."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-10"
}
```

#### `policy/finra-supervision-evasion-phrases.txt`

```
# Custom keyword dictionary - CONCEALMENT/EVASION PHRASES ONLY.
#
# Purpose: catch language indicating someone knows a conversation is being monitored and is
# deliberately routing sensitive discussion around it - the exact pattern regulators cite in
# off-channel-communications enforcement actions as evidence of intent (README.md Section 2,
# design.md Section 5). This list does NOT duplicate the Corporate sabotage / Customer complaints /
# Gifts & entertainment / Money laundering / [Workplace/Regulatory] collusion / Stock manipulation /
# Unauthorized disclosure trainable classifiers, which already cover explicit regulatory-violation
# language far more robustly than a static word list could.
#
# NEVER add restricted-list ticker symbols, issuer names, deal codenames, or any other firm-specific
# confidential supervisory information to this file or its production equivalent - see README.md
# Section 11 and reviews.md Red Team. A keyword dictionary that reveals what the firm is watching for
# is a liability, not a control.
let's discuss offline
let's take this offline
call me instead
don't put that in an email
don't put that in writing
don't send that in writing
keep this between us
keep this off the record
off the record
this conversation didn't happen
delete this after reading
delete after you read this
use my personal phone
text me instead
let's talk in person about this
not over email
not over teams
better discussed in person
```