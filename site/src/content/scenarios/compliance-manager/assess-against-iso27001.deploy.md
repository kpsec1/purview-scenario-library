---
part: "deploy"
parent: "compliance-manager/assess-against-iso27001"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-ComplianceManagerAuditTrail.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of the three Compliance-Manager-specific operations Microsoft's
    unified audit log documents, for detecting configuration drift a native Compliance Manager
    report does not surface.

.DESCRIPTION
    Compliance Manager has no write API this repo's other deploy scripts could target (see
    design.md Section 2) - assessment creation and improvement-action updates are portal/Excel-
    wizard-only. This script targets the one thing about Compliance Manager that IS reachable
    through a documented API: its footprint in the Microsoft 365 unified audit log, via
    Search-UnifiedAuditLog (automation surface 1 per docs/automation-surface.md Section 1).

    Microsoft's audit-log-activities reference documents exactly three Compliance-Manager-specific
    operations (design.md Section 4):
      - ComplianceManagerRolesChange          - an admin changed a user's Compliance Manager role.
      - ComplianceManagerAutomationLevelChange - an admin changed the org-wide automated-testing
        trust level across all improvement actions.
      - ComplianceManagerAutomationChange      - an admin changed the automated-testing source
        setting for a specific improvement action.

    None of the three cover assessment creation/deletion or improvement-action status changes -
    this script does not claim to detect those (the native Reports page's own history report
    already covers score-affecting changes; see README.md Section 11). What this script covers is
    the two categories of change that could quietly undermine trust in this assessment's own
    evidence: who can edit it, and whether automated testing's trust boundary was loosened.

    Idempotency model: unlike this repo's policy-deploying scenarios (which skip an object that
    already exists) or its RunId-replace reporting scenarios (one fresh KPI snapshot per run), this
    script accumulates a ROLLING HISTORY of discrete audit events across potentially-overlapping
    date-range calls (e.g. a daily scheduled run whose window overlaps the prior run's tail). Every
    run merges newly-fetched records into the existing CSV, de-duplicating by a composite key of
    (CreationDate, Operations, UserIds, a stable hash of the full AuditData JSON payload) - so
    re-running with an overlapping or identical date range never produces duplicate rows. The key
    deliberately does not assume a flat "ObjectId" property exists on the cmdlet's output (that
    property is not confirmed in Microsoft's documented examples for this cmdlet - see the
    Get-CompositeKey function below and README.md Section 11); a best-effort ObjectId, parsed from
    inside AuditData where present, is still surfaced as its own output column for readability.
    See design.md Section 8.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call
    this script. Read-only: it never creates, modifies, or deletes any object - the only side
    effect is the CSV file this script writes, which IS gated behind $PSCmdlet.ShouldProcess() so
    -WhatIf reports the records that would be merged without touching disk.

.PARAMETER StartDate
    Start of the audit-log search window (UTC). Search-UnifiedAuditLog requires both -StartDate and
    -EndDate. Defaults to 7 days before -EndDate, suitable for a daily/weekly scheduled run with
    deliberate overlap (idempotent de-duplication makes overlap safe, and cheap insurance against a
    missed prior run).

.PARAMETER EndDate
    End of the audit-log search window (UTC). Defaults to the current time.

.PARAMETER OutputCsvPath
    Path to the rolling audit-trail CSV. Created with a header row if it doesn't already exist;
    otherwise new, non-duplicate records are merged in and the file is rewritten sorted by
    CreationDate.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size when not using -SessionCommand ReturnLargeSet.
    Defaults to 5000 (the cmdlet's documented per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The Search-UnifiedAuditLog query still executes
    (read-only; needed to report accurate would-be results), but the CSV file is not written - the
    script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv' -WhatIf

    Dry run: queries the last 7 days and reports how many new records would be merged, writes nothing.

.EXAMPLE
    ./Export-ComplianceManagerAuditTrail.ps1 -OutputCsvPath './out/compliance-manager-audit-trail.csv'

    Deploys (merges) the last 7 days of Compliance Manager role/automation-level/automation-source
    change events into the rolling CSV. Safe to schedule daily or weekly - overlapping windows never
    produce duplicate rows.

.EXAMPLE
    ./Export-ComplianceManagerAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/compliance-manager-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window (README.md
    Section 11) before the first scheduled recurring run.

.NOTES
    VERIFY before relying on this for a compliance audit trail beyond 180 days: default Audit
    (Standard) retention is 180 days for most workloads (one year for Entra ID/Exchange/OneDrive/
    SharePoint under an E5-tier license) - see README.md Section 11. Run this script on a recurring
    schedule (README.md Section 8) if the evidentiary window this scenario needs exceeds that
    retention, rather than relying on a single historical pull.

    Sources (Microsoft Learn, verify before production use):
    - Audit log activities - Compliance Manager activities table (the 3 operation names this script
      filters on): https://learn.microsoft.com/purview/audit-log-activities#compliance-manager-activities
    - Search-UnifiedAuditLog reference (-StartDate/-EndDate/-Operations/-ResultSize/-SessionCommand):
      https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/
      Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies):
      https://learn.microsoft.com/purview/audit-log-retention-policies
    - Exchange Online dependency for audit log search (View-Only Audit Logs / Audit Logs role) -
      docs/rbac-model.md Section 6, grounded from:
      https://learn.microsoft.com/purview/audit-log-search-deleted-mailbox-items#verify-administrator-permissions
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
    # Search-UnifiedAuditLog is only exported after a successful Connect-ExchangeOnline; its
    # absence means the caller never connected.
    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity also needs the View-Only Audit Logs or Audit Logs Exchange Online role - see rbac-model.md Section 6.'
    }
}

Assert-ExoSession

$complianceManagerOperations = @(
    'ComplianceManagerRolesChange',
    'ComplianceManagerAutomationLevelChange',
    'ComplianceManagerAutomationChange'
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
    # De-duplication key for the rolling merge (design.md Section 8): a real audit event is
    # uniquely identified by when it happened, what happened, and who did it. CreationDate,
    # Operations, and UserIds are all confirmed top-level Search-UnifiedAuditLog output properties
    # (grounded via the cited Best Practices and audit-log-export-records examples in this script's
    # .NOTES). A flat "ObjectId" property is NOT confirmed as part of that output schema - rather
    # than assume one exists (AGENTS.md Section 4's no-invented-fields rule), this key instead
    # folds in a hash of the full AuditData JSON payload, which IS confirmed to exist on every
    # record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

function Get-BestEffortTargetObjectId {
    # Best-effort only, for a human-readable column - never used in the composite key. Microsoft's
    # audit-log-activities reference documents the 3 operation names this script filters on but not
    # the internal shape of their AuditData JSON payload, so this may legitimately return $null.
    # See README.md Section 11.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$AuditDataJson)
    try {
        $parsed = $AuditDataJson | ConvertFrom-Json -ErrorAction Stop
        return $parsed.ObjectId
    }
    catch {
        return $null
    }
}

Write-Host "Searching unified audit log for Compliance Manager operations between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

# Page through results with SessionCommand ReturnLargeSet, per Search-UnifiedAuditLog's documented
# pagination pattern (repeated calls with the same SessionId until a call returns zero records).
$sessionId = "compliance-manager-audit-trail-$([guid]::NewGuid())"
$allRecords = [System.Collections.Generic.List[object]]::new()
do {
    # Deliberately NOT using -Formatted: some cited Microsoft examples use it for a more readable
    # console table, but its effect on the raw AuditData JSON string isn't documented, and this
    # script's best-effort ObjectId parsing (Get-BestEffortTargetObjectId) depends on AuditData
    # staying valid JSON. Omitting it keeps every field in its plain, undocumented-transform state.
    $page = @(Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate `
        -Operations $complianceManagerOperations -ResultSize $ResultSize `
        -SessionId $sessionId -SessionCommand ReturnLargeSet)
    # Wrapping in @() up front avoids PowerShell's single-object-vs-array ambiguity: a page that
    # returns exactly one record would otherwise come back as a scalar with no .Count property,
    # which would make the loop-continuation check below silently misbehave.
    if ($page.Count -gt 0) { $allRecords.AddRange($page) }
} while ($page.Count -gt 0)

Write-Host "Found $($allRecords.Count) matching record(s) in the search window." -ForegroundColor Green

$newRows = foreach ($record in $allRecords) {
    [pscustomobject]@{
        CreationDate         = $record.CreationDate
        Operation            = $record.Operations
        UserIds              = $record.UserIds
        RecordType           = $record.RecordType
        AuditDataObjectId    = (Get-BestEffortTargetObjectId -AuditDataJson $record.AuditData)
        AuditData            = $record.AuditData
        CompositeKey         = (Get-CompositeKey -Record $record)
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

    foreach ($row in $rowsToAdd) {
        if ($row.Operation -match 'AutomationLevel|AutomationChange') {
            Write-Warning "Automation-trust change detected: $($row.Operation) by $($row.UserIds) at $($row.CreationDate). Review whether this weakens automated testing for this assessment's improvement actions - see README.md Section 8 incident-response guidance."
        }
        elseif ($row.Operation -eq 'ComplianceManagerRolesChange') {
            Write-Warning "Compliance Manager role change detected: by $($row.UserIds) at $($row.CreationDate). Confirm this matches an expected onboarding/offboarding/role-adjustment event - see README.md Section 8."
        }
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
```

#### `policy/iso27001-assessment-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Compliance Manager has no documented REST, Graph, or PowerShell write API for assessment creation, control mapping, or improvement-action status/evidence updates as of this writing (docs/automation-surface.md has no routing-table row for Compliance Manager; see design.md Section 2). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed assessment can be diffed against intent during review instead of relying on institutional memory of what was clicked. This follows the identical precedent set by scenarios/insider-risk/departing-employee-data-theft/deploy/policy/departing-employee-policy-manifest.json for another portal-only Purview surface.",
  "regulation": "ISO/IEC 27001:2022",
  "regulationNote": "Compliance Manager's Regulations page lists ISO/IEC 27001:2013 and ISO/IEC 27001:2022 as two separate premium templates (compliance-manager-regulations-list, re-fetched 2026-09-10). This manifest targets :2022 because the industry-wide IAF MD 26 transition period ended October 31, 2025 - all ISO/IEC 27001:2013 certificates must have expired or been reissued against :2022 by that date, and certification bodies stopped conducting initial/recertification audits to :2013 after April 30, 2024. See README.md Section 2/Section 11 and design.md Section 5b.",
  "regulationTier": "Premium template - counts against the tenant's purchased or A5/E5/G5 3-free-premium-template allotment. See README.md Section 3.",
  "assessmentName": "ISO/IEC 27001:2022 - Microsoft 365 Estate",
  "assessmentNameNote": "Assessment names must be unique tenant-wide (Microsoft Learn: compliance-manager-assessments). Confirm before creating - like a DLP policy name elsewhere in this repo, it cannot be changed by renaming after creation without deleting and recreating.",
  "group": {
    "strategy": "createNew",
    "name": "Security & Compliance Assessments",
    "note": "Groups can't be deleted and an assessment's group can't be changed after creation (README.md Section 12) - decide this before clicking through the wizard. If the tenant also runs scenarios/compliance-manager/pci-dss-assessment/ (or any other Compliance Manager assessment), consider adding it to this same group - but only NONTECHNICAL improvement actions (documentation/operational) sync within a shared group; TECHNICAL improvement actions already sync tenant-wide regardless of group. See pci-dss-assessment/design.md Section 6 for the precise, Microsoft-documented distinction (this note was corrected during that scenario's build to stop implying broader sharing than the product actually provides)."
  },
  "servicesInScope": [
    "Microsoft 365"
  ],
  "servicesInScopeNote": "Multicloud (AWS/GCP/Azure via Defender for Cloud) scoping is explicitly out of scope for this scenario - see design.md Section 7. A buyer with a multicloud estate can add services later by editing the assessment.",
  "roleAssignments": {
    "note": "Assign the narrowest Compliance Manager role that does the job, per README.md Section 3's role table. Do not default everyone assessing this template to Administration.",
    "recommendedStarter": [
      { "role": "Compliance Manager Administration", "assignTo": "The person creating and owning this assessment (1-2 people, not the whole security team)" },
      { "role": "Compliance Manager Assessor", "assignTo": "Control owners across IT/Security/HR/Legal who will test and update improvement actions but should not create new assessments" },
      { "role": "Compliance Manager Reader", "assignTo": "Auditors, GRC analysts, and leadership who need visibility without edit rights" }
    ]
  },
  "recommendedDeploymentOrder": [
    "scenarios/dlp/pci-teams-exfil-block/ (if Teams/chat exfiltration is in the estate's threat model)",
    "scenarios/information-protection/auto-label-confidential-sharepoint/",
    "scenarios/dlp/endpoint-dlp-usb-block/",
    "scenarios/insider-risk/departing-employee-data-theft/",
    "THEN create this assessment - built-in automation (design.md Section 6) picks up signals from controls already in place, reducing the manual-testing backlog a Contributor/Assessor faces on day one."
  ],
  "auditMonitoring": {
    "operations": [
      "ComplianceManagerRolesChange",
      "ComplianceManagerAutomationLevelChange",
      "ComplianceManagerAutomationChange"
    ],
    "note": "The only three Compliance-Manager-specific operations documented in Microsoft's audit-log-activities reference as of this build (design.md Section 4). Monitored on a recurring schedule by deploy/Export-ComplianceManagerAuditTrail.ps1 - see README.md Section 5."
  },
  "schemaVersion": "1.1",
  "lastUpdated": "2026-09-10"
}
```