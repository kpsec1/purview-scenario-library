---
part: "deploy"
parent: "compliance-manager/hipaa-hitech-assessment"
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
    REUSED SCRIPT - NOT A DUPLICATE. This is the identical script shipped in
    scenarios/compliance-manager/assess-against-iso27001/deploy/Export-ComplianceManagerAuditTrail.ps1
    (also copied, byte-for-byte, into scenarios/compliance-manager/pci-dss-assessment/deploy/ and
    scenarios/compliance-manager/soc2-assessment/deploy/). It is copied into this scenario's deploy/
    folder so scenarios/compliance-manager/hipaa-hitech-assessment/ remains independently deployable,
    but the mechanism it targets is deliberately NOT assessment-scoped: Microsoft's audit-log-
    activities reference documents exactly three Compliance-Manager-specific operations, and all
    three are TENANT-WIDE events with no field that ties them to a single assessment (design.md
    Section 2 and Section 4). Concretely:
      - ComplianceManagerRolesChange           - an admin changed a user's Compliance Manager role.
      - ComplianceManagerAutomationLevelChange - an admin changed the org-wide automated-testing
        trust level across ALL improvement actions, in EVERY assessment.
      - ComplianceManagerAutomationChange      - an admin changed the automated-testing source
        setting for a specific improvement action, which may itself be shared across assessments.

    If this scenario AND any of scenarios/compliance-manager/assess-against-iso27001/,
    scenarios/compliance-manager/pci-dss-assessment/, and scenarios/compliance-manager/
    soc2-assessment/ are deployed in the same tenant, run only ONE instance of this script (any one
    of the copies - they are byte-for-byte identical) against a single shared -OutputCsvPath.
    Running multiple copies independently against separate CSV files produces fully-overlapping,
    redundant audit trails with no additional coverage - see README.md Section 5 and design.md
    Section 2 for why this scenario reuses rather than reinvents this script.

    None of the three operations cover assessment creation/deletion or improvement-action status
    changes - this script does not claim to detect those (the native Reports page's own history
    report already covers score-affecting changes; see README.md Section 11). What this script
    covers is the two categories of change that could quietly undermine trust in ANY Compliance
    Manager assessment's evidence: who can edit it, and whether automated testing's trust boundary
    was loosened.

    Idempotency model: this script accumulates a ROLLING HISTORY of discrete audit events across
    potentially-overlapping date-range calls (e.g. a daily scheduled run whose window overlaps the
    prior run's tail). Every run merges newly-fetched records into the existing CSV, de-duplicating
    by a composite key of (CreationDate, Operations, UserIds, a stable hash of the full AuditData
    JSON payload) - so re-running with an overlapping or identical date range never produces
    duplicate rows. The key deliberately does not assume a flat "ObjectId" property exists on the
    cmdlet's output (not confirmed in Microsoft's documented examples for this cmdlet); a
    best-effort ObjectId, parsed from inside AuditData where present, is still surfaced as its own
    output column for readability. See design.md Section 4 and README.md Section 11.

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
    CreationDate. If assess-against-iso27001, pci-dss-assessment, and/or soc2-assessment are also
    deployed in this tenant, point every copy at the SAME path (or run only one of the copies)
    rather than maintaining separate files.

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
    produce duplicate rows. Covers this HIPAA/HITECH assessment and any other Compliance Manager
    assessment in the tenant, since the underlying operations are tenant-wide (see .DESCRIPTION).

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
    retention, rather than relying on a single historical pull. This matters more here than for the
    ISO 27001/PCI DSS/SOC 2 siblings: HIPAA's own Security Rule requires retaining required
    documentation for SIX YEARS from creation or last-effective date (45 CFR Section 164.316(b)(2)(i))
    - far beyond even Audit Premium's typical retention configurations - so this script's own
    accumulated CSV, archived outside the tenant's audit-log retention window, is the durable record
    for years the underlying unified audit log itself will no longer have. See README.md Section 8.

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
    - 45 CFR Section 164.316(b)(2)(i) - HIPAA Security Rule six-year documentation retention
      requirement: https://www.ecfr.gov/current/title-45/section-164.316
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
    # De-duplication key for the rolling merge (design.md Section 4): a real audit event is
    # uniquely identified by when it happened, what happened, and who did it. CreationDate,
    # Operations, and UserIds are all confirmed top-level Search-UnifiedAuditLog output properties.
    # A flat "ObjectId" property is NOT confirmed as part of that output schema - rather than assume
    # one exists (AGENTS.md Section 4's no-invented-fields rule), this key instead folds in a hash
    # of the full AuditData JSON payload, which IS confirmed to exist on every record, as the fourth
    # uniqueness component.
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

#### `policy/hipaa-hitech-assessment-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Compliance Manager has no documented REST, Graph, or PowerShell write API for assessment creation, control mapping, or improvement-action status/evidence updates as of this writing (docs/automation-surface.md has no routing-table row for Compliance Manager; see design.md Section 2 - identical grounding to scenarios/compliance-manager/assess-against-iso27001/, scenarios/compliance-manager/pci-dss-assessment/, and scenarios/compliance-manager/soc2-assessment/). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed assessment can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "regulation": "HIPAA/HITECH",
  "regulationTier": "Premium template - counts against the tenant's purchased or A5/E5/G5 3-free-premium-template allotment. See README.md Section 3.",
  "regulationVersionNote": "Compliance Manager's regulation catalog lists 'HIPAA/HITECH' as a single premium template under the US Government category. It does NOT have a versioned sibling the way ISO/IEC 27001 (:2013 vs :2022) or PCI DSS (v3.2.1 vs v4.0) do, but it DOES have a separately-listed, easy-to-confuse-with-it template in the same catalog: 'HITRUST' (the HITRUST CSF - a separate, independently governed certifiable framework maintained by the HITRUST Alliance that harmonizes many standards INCLUDING HIPAA, but is not the same thing as a HIPAA/HITECH assessment and has its own separate certification path). Select 'HIPAA/HITECH', not 'HITRUST', when the goal is a HIPAA/HITECH-specific readiness view. See README.md Section 11.",
  "assessmentName": "HIPAA/HITECH - Microsoft 365 Estate",
  "assessmentNameNote": "Assessment names must be unique tenant-wide (Microsoft Learn: compliance-manager-assessments). Cannot be changed after creation without deleting and recreating.",
  "group": {
    "strategy": "joinExistingIfPresent",
    "name": "Security & Compliance Assessments",
    "note": "If scenarios/compliance-manager/assess-against-iso27001/, scenarios/compliance-manager/pci-dss-assessment/, and/or scenarios/compliance-manager/soc2-assessment/ are already deployed in this tenant using this same group name, ADD this HIPAA/HITECH assessment to that existing group rather than creating a new one. If this is the tenant's first Compliance Manager assessment, create a new group with this name so future assessments join it. See design.md Section 6 for exactly what group membership does and does not buy you - the benefit is narrower than 'shared credit for every control.'",
    "groupingRule": "Microsoft documents that a group can contain multiple assessments for the SAME product only if each one is for a DIFFERENT regulation (compliance-manager-assessments, 'Groups for assessments'). ISO/IEC 27001:2022 + PCI DSS v4.0 + SOC 2 + HIPAA/HITECH in one group is four different regulations against the same Microsoft 365 product - an explicitly supported combination, not an edge case."
  },
  "servicesInScope": [
    "Microsoft 365"
  ],
  "servicesInScopeNote": "Multicloud (AWS/GCP/Azure via Defender for Cloud) scoping is out of scope for this scenario, matching scenarios/compliance-manager/assess-against-iso27001/design.md Section 7, scenarios/compliance-manager/pci-dss-assessment/design.md Section 8, and scenarios/compliance-manager/soc2-assessment/design.md Section 8's identical non-goal, and this library's tenant-only scope (AGENTS.md Section 5).",
  "roleAssignments": {
    "note": "Identical Compliance Manager role model to every other assessment in this library - assign the narrowest role that does the job. See README.md Section 3. NOTE: HIPAA itself separately requires the covered entity/business associate to formally DESIGNATE a Privacy Officer (45 CFR Section 164.530(a)(1)) and a Security Officer (45 CFR Section 164.308(a)(2)) - these are HIPAA-mandated organizational roles, not Compliance Manager RBAC roles, and are not satisfied merely by assigning someone Compliance Manager Administration.",
    "recommendedStarter": [
      { "role": "Compliance Manager Administration", "assignTo": "The person creating and owning this assessment (1-2 people, not the whole security team) - ideally the organization's designated HIPAA Security Officer or a delegate" },
      { "role": "Compliance Manager Assessor", "assignTo": "Control owners across IT/Security/Compliance/Privacy (HIPAA's Privacy Rule, Security Rule, and Breach Notification Rule span legal, clinical-operations, and technical stakeholders, not just IT) who will test and update improvement actions but should not create new assessments" },
      { "role": "Compliance Manager Reader", "assignTo": "Internal auditors, the organization's designated Privacy Officer/Security Officer if not already a Contributor, and leadership who need visibility without edit rights" }
    ]
  },
  "recommendedDeploymentOrder": [
    "scenarios/information-protection/auto-label-confidential-sharepoint/ and .../auto-label-confidential-exchange/ (labeling/encrypting documents likely to contain ePHI at rest and in transit - Technical Safeguards Section 164.312(a)/(e))",
    "scenarios/dlp/exchange-pii-exfil-block/ (+ Part 2) (blocking unauthorized transmission of ePHI-adjacent identifiers over email - Technical Safeguards Section 164.312(e), Transmission Security)",
    "scenarios/dlp/endpoint-dlp-usb-block/ (+ Adaptive Protection variant) (controlling removable media that could carry ePHI off-network - Physical Safeguards Section 164.310(d), Device and Media Controls)",
    "scenarios/adaptive-protection/block-legacy-authentication/ and .../exchange-legacy-auth-block/ (access control and person/entity authentication - Technical Safeguards Section 164.312(a)/(d); Administrative Safeguards Section 164.308(a)(4), Access Authorization)",
    "scenarios/insider-risk/departing-employee-data-theft/ (workforce security and termination procedures - Administrative Safeguards Section 164.308(a)(3))",
    "scenarios/audit/premium-audit-investigation/ (information system activity review and audit controls - Administrative Safeguards Section 164.308(a)(1)(ii)(D); Technical Safeguards Section 164.312(b))",
    "scenarios/audit/compromised-account-incident-response/ (incident response feeding the required breach risk assessment - Breach Notification Rule, 45 CFR Sections 164.400-414)",
    "THEN create this assessment - built-in automation (design.md Section 4) picks up signals from controls already in place, reducing the manual-testing backlog a Contributor/Assessor faces on day one."
  ],
  "controlCrosswalk": {
    "_comment": "This is THIS LIBRARY'S OWN correlation of its scenarios to HIPAA/HITECH's own published rule structure (Privacy Rule, Security Rule's three safeguard categories, Breach Notification Rule - 45 CFR Part 160 and Part 164) - it is NOT a reproduction of Microsoft's proprietary per-improvement-action automation mapping (which isn't published in a form this scenario can fetch and cite - see design.md Section 7, same constraint scenarios/compliance-manager/assess-against-iso27001/design.md Section 6, scenarios/compliance-manager/pci-dss-assessment/design.md Section 7, and scenarios/compliance-manager/soc2-assessment/design.md Section 7 document for their own regulations). Use it to decide deployment order and to brief the organization's designated Privacy/Security Officer on what this tenant's Microsoft 365 controls contribute - do not present it to HHS OCR (in the event of an investigation) or a business-partner auditor as Microsoft's own control mapping, and do not present it as proof the organization's own required Security Risk Analysis (45 CFR Section 164.308(a)(1)(ii)(A)) is complete (that analysis is the organization's own legal obligation - see README.md Section 2/Section 11).",
    "categories": [
      { "category": "Privacy Rule", "cfrCitation": "45 CFR Part 164, Subpart E", "hasAddressableSpecifications": false, "coverage": "Out of scope for direct technical automation from this Microsoft 365/Purview-only library - minimum-necessary use/disclosure restrictions and patient right-of-access request handling are organizational/legal processes this library does not script. The closest existing technical building block is PHI identification itself: Microsoft Purview ships a built-in 'U.S. Health Insurance Act (HIPAA) Enhanced' DLP policy template (SSN + DEA Number + U.S. Physical Addresses + All Full Names sensitive information types AND ICD-9-CM/ICD-10-CM keyword terms AND the Healthcare/Health-Medical-Forms trainable classifiers) that this library has not yet wrapped in a dedicated scenario - see PROGRESS.md follow-up." },
      { "category": "Administrative Safeguards", "cfrCitation": "45 CFR Section 164.308", "hasAddressableSpecifications": true, "coverage": "scenarios/insider-risk/departing-employee-data-theft/ (Section 164.308(a)(3) - workforce security/termination procedures), scenarios/audit/premium-audit-investigation/ (Section 164.308(a)(1)(ii)(D) - information system activity review), scenarios/adaptive-protection/block-legacy-authentication/ and .../exchange-legacy-auth-block/ (Section 164.308(a)(4) - access authorization procedures)." },
      { "category": "Physical Safeguards", "cfrCitation": "45 CFR Section 164.310", "hasAddressableSpecifications": true, "coverage": "Largely out of scope for this Microsoft 365/Purview-only library - facility access controls and workstation physical security are an Azure-datacenter/physical-office concern, not a Purview one. Partial coverage only: scenarios/dlp/endpoint-dlp-usb-block/ (+ the Defender for Endpoint device-control family) addresses Section 164.310(d), Device and Media Controls, for the subset of that standard concerned with removable electronic media leaving the network with ePHI on it - disposal, accountability, and media re-use of physical devices themselves are not addressed." },
      { "category": "Technical Safeguards", "cfrCitation": "45 CFR Section 164.312", "hasAddressableSpecifications": true, "coverage": "scenarios/adaptive-protection/block-legacy-authentication/, .../exchange-legacy-auth-block/ (Section 164.312(a)/(d) - access control, person/entity authentication), scenarios/audit/premium-audit-investigation/ (Section 164.312(b) - audit controls), scenarios/information-protection/auto-label-confidential-sharepoint/, .../auto-label-confidential-exchange/ (Section 164.312(a)/(e) - encryption supporting access control and transmission security), scenarios/dlp/exchange-pii-exfil-block/ (+ Part 2) (Section 164.312(e) - transmission security)." },
      { "category": "Breach Notification Rule", "cfrCitation": "45 CFR Sections 164.400-414", "hasAddressableSpecifications": false, "coverage": "scenarios/audit/compromised-account-incident-response/ (post-compromise response feeding the required breach risk assessment), scenarios/audit/premium-audit-investigation/ (forensic investigation and log review supporting that risk assessment). This library does not script the notification obligations themselves (notifying affected individuals, HHS, and - for breaches affecting 500+ residents of a state or jurisdiction - the media), which are organizational/legal processes, not a Purview policy." }
    ],
    "addressableNotOptionalNote": "For the three Security Rule safeguard categories (Administrative, Physical, Technical), HIPAA's own rule text distinguishes 'required' from 'addressable' implementation specifications - but 'addressable' does NOT mean optional. An organization must implement every addressable specification as written, OR document why it is not reasonable/appropriate and implement an equivalent alternative measure, OR document why no safeguard is needed. See README.md Section 11 - this is the single most common HIPAA Security Rule misunderstanding this scenario has found grounded documentation for, and the manifest-structural check in validate/Test-ComplianceManagerAuditTrail.ps1 confirms each Security Rule category still carries this flag rather than letting it be silently dropped in a future edit."
  },
  "auditMonitoring": {
    "operations": [
      "ComplianceManagerRolesChange",
      "ComplianceManagerAutomationLevelChange",
      "ComplianceManagerAutomationChange"
    ],
    "note": "These 3 operations are TENANT-WIDE Compliance Manager events, not scoped to a single assessment. This scenario deliberately REUSES scenarios/compliance-manager/assess-against-iso27001/deploy/Export-ComplianceManagerAuditTrail.ps1 (also copied into scenarios/compliance-manager/pci-dss-assessment/deploy/ and scenarios/compliance-manager/soc2-assessment/deploy/) rather than shipping a fourth, functionally-identical copy - run ONE instance against a shared CSV path if more than one of these scenarios is deployed. See design.md Section 2 and README.md Section 5."
  },
  "notAValidHipaaCertification": "A Compliance Manager assessment - however complete - is an internal readiness-tracking and evidence tool. There is currently no certification standard that the U.S. Department of Health and Human Services approves to demonstrate HIPAA/HITECH compliance by a business associate (Microsoft's own published position, cited in README.md Section 2/Section 11) - this assessment does not create one, and must never be presented as 'HIPAA certified.' It also does not substitute for the organization's own legally required Security Risk Analysis (45 CFR Section 164.308(a)(1)(ii)(A)) or for a signed Business Associate Agreement between the organization and Microsoft (and any subcontractor that creates, receives, maintains, or transmits PHI). See README.md Section 2/Section 11.",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-16"
}
```