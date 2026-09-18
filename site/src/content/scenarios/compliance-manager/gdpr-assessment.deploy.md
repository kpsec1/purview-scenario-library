---
part: "deploy"
parent: "compliance-manager/gdpr-assessment"
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
    (also copied, byte-for-byte, into scenarios/compliance-manager/pci-dss-assessment/deploy/,
    scenarios/compliance-manager/soc2-assessment/deploy/, and scenarios/compliance-manager/
    hipaa-hitech-assessment/deploy/). It is copied into this scenario's deploy/ folder so
    scenarios/compliance-manager/gdpr-assessment/ remains independently deployable, but the
    mechanism it targets is deliberately NOT assessment-scoped: Microsoft's audit-log-activities
    reference documents exactly three Compliance-Manager-specific operations, and all three are
    TENANT-WIDE events with no field that ties them to a single assessment (design.md Section 2
    and Section 4). Concretely:
      - ComplianceManagerRolesChange           - an admin changed a user's Compliance Manager role.
      - ComplianceManagerAutomationLevelChange - an admin changed the org-wide automated-testing
        trust level across ALL improvement actions, in EVERY assessment.
      - ComplianceManagerAutomationChange      - an admin changed the automated-testing source
        setting for a specific improvement action, which may itself be shared across assessments.

    If this scenario AND any of scenarios/compliance-manager/assess-against-iso27001/,
    scenarios/compliance-manager/pci-dss-assessment/, scenarios/compliance-manager/soc2-assessment/,
    and scenarios/compliance-manager/hipaa-hitech-assessment/ are deployed in the same tenant, run
    only ONE instance of this script (any one of the copies - they are byte-for-byte identical)
    against a single shared -OutputCsvPath. Running multiple copies independently against separate
    CSV files produces fully-overlapping, redundant audit trails with no additional coverage - see
    README.md Section 5 and design.md Section 2 for why this scenario reuses rather than reinvents
    this script.

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
    produce duplicate rows. Covers this EU GDPR assessment and any other Compliance Manager
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
    retention, rather than relying on a single historical pull. Unlike the HIPAA/HITECH sibling
    (which cites a specific 45 CFR six-year documentation-retention figure), GDPR's own Article 5(2)
    accountability principle requires being able to DEMONSTRATE compliance but does not itself state
    a fixed retention period for that evidence - do not invent a specific number here. Align the
    archived CSV's retention with the organization's own documented record-retention policy (which
    Article 5(1)(e)'s storage-limitation principle requires it to have) rather than assuming Audit
    (Standard)'s native window is sufficient. See README.md Section 8.

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
    - GDPR Article 5(2) (accountability principle) and Article 5(1)(e) (storage limitation):
      https://learn.microsoft.com/compliance/regulatory/gdpr#gdpr-faqs
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

#### `policy/gdpr-assessment-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Compliance Manager has no documented REST, Graph, or PowerShell write API for assessment creation, control mapping, or improvement-action status/evidence updates as of this writing (docs/automation-surface.md has no routing-table row for Compliance Manager; see design.md Section 2 - identical grounding to scenarios/compliance-manager/assess-against-iso27001/, scenarios/compliance-manager/pci-dss-assessment/, scenarios/compliance-manager/soc2-assessment/, and scenarios/compliance-manager/hipaa-hitech-assessment/). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed assessment can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "regulation": "EU GDPR (General Data Protection Regulation)",
  "regulationTier": "Premium template - counts against the tenant's purchased or A5/E5/G5 3-free-premium-template allotment. See README.md Section 3.",
  "regulationVersionNote": "Compliance Manager's regulation catalog lists 'EU GDPR (General Data Protection Regulation)' as a single premium template under the Europe, Middle East, and Africa (EMEA) category. It has no versioned sibling the way ISO/IEC 27001 (:2013 vs :2022) or PCI DSS (v3.2.1 vs v4.0) do. The catalog's EMEA section also separately lists a 'UK Data Protection Act' template (the UK's post-Brexit implementing statute, which itself incorporates 'UK GDPR') - a materially different jurisdiction/regulator (the UK Information Commissioner's Office, not an EU/EEA Data Protection Authority) from the EU GDPR template this scenario deploys. Not the same near-identical-name trap as HIPAA/HITECH-vs-HITRUST (the names are not easily confused), but an organization with both EU and UK obligations should not assume this single assessment covers the UK template too. See README.md Section 11.",
  "licensingHistoryNote": "GDPR was one of a small, fixed set of regulatory templates (alongside NIST 800-53 and ISO/IEC 27001) included by default in Compliance Manager BEFORE Microsoft's December 2022 licensing change. Since that change, continued use of GDPR counts against the same 3-free-premium-template allotment every other premium template (including this library's ISO 27001/PCI DSS/SOC 2/HIPAA-HITECH siblings) draws from - there is no longer a separate 'free GDPR' entitlement. An organization that adopted this template before December 2022 should confirm its current regulation-license count reflects this, rather than assuming legacy free access continues. See README.md Section 3/Section 10.",
  "assessmentName": "EU GDPR - Microsoft 365 Estate",
  "assessmentNameNote": "Assessment names must be unique tenant-wide (Microsoft Learn: compliance-manager-assessments). Cannot be changed after creation without deleting and recreating.",
  "group": {
    "strategy": "joinExistingIfPresent",
    "name": "Security & Compliance Assessments",
    "note": "If scenarios/compliance-manager/assess-against-iso27001/, scenarios/compliance-manager/pci-dss-assessment/, scenarios/compliance-manager/soc2-assessment/, and/or scenarios/compliance-manager/hipaa-hitech-assessment/ are already deployed in this tenant using this same group name, ADD this GDPR assessment to that existing group rather than creating a new one. If this is the tenant's first Compliance Manager assessment, create a new group with this name so future assessments join it. See design.md Section 6 for exactly what group membership does and does not buy you - the benefit is narrower than 'shared credit for every control.'",
    "groupingRule": "Microsoft documents that a group can contain multiple assessments for the SAME product only if each one is for a DIFFERENT regulation (compliance-manager-assessments, 'Groups for assessments'). ISO/IEC 27001:2022 + PCI DSS v4.0 + SOC 2 + HIPAA/HITECH + EU GDPR in one group is five different regulations against the same Microsoft 365 product - an explicitly supported combination, not a new edge case introduced by adding a fifth."
  },
  "servicesInScope": [
    "Microsoft 365"
  ],
  "servicesInScopeNote": "Multicloud (AWS/GCP/Azure via Defender for Cloud) scoping is out of scope for this scenario, matching every sibling scenario's identical non-goal and this library's tenant-only scope (AGENTS.md Section 5), even though Microsoft explicitly documents that a single EU GDPR assessment CAN span Microsoft 365, Azure, AWS, and GCP together (compliance-manager-multicloud) - a genuinely available option this scenario deliberately does not exercise.",
  "roleAssignments": {
    "note": "Identical Compliance Manager role model to every other assessment in this library - assign the narrowest role that does the job. See README.md Section 3. NOTE: unlike HIPAA's blanket Privacy/Security Officer designation requirement, GDPR's Article 37 Data Protection Officer (DPO) designation is CONDITIONAL - required only where core activities involve large-scale systematic monitoring, large-scale special-category/criminal-conviction data processing, or public-authority processing. Determine applicability before assuming a DPO must be named; where one is required or voluntarily appointed, that designation is a GDPR Article 37 obligation, not a Compliance Manager RBAC role, and is not satisfied merely by assigning someone Compliance Manager Administration.",
    "recommendedStarter": [
      { "role": "Compliance Manager Administration", "assignTo": "The person creating and owning this assessment (1-2 people, not the whole security team) - ideally the organization's Data Protection Officer if one is designated, or a delegate from Legal/Privacy" },
      { "role": "Compliance Manager Assessor", "assignTo": "Control owners across IT/Security/Legal/Privacy (GDPR's data-subject-rights, breach-notification, and DPIA obligations span legal and privacy stakeholders, not just IT) who will test and update improvement actions but should not create new assessments" },
      { "role": "Compliance Manager Reader", "assignTo": "Internal auditors, the organization's Data Protection Officer if not already a Contributor, and leadership who need visibility without edit rights" }
    ]
  },
  "recommendedDeploymentOrder": [
    "scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/ (+ the on-premises SQL Server and Synapse siblings) (discovering and classifying where EU personal data actually resides - the prerequisite for both Data Subject Request fulfillment and a meaningful Data Protection Impact Assessment)",
    "scenarios/data-estate-insights/sensitivity-label-coverage-report/ and .../classification-coverage-report/ (measuring how completely that discovered personal data is labeled/classified across the estate - Article 5(1)(f) integrity and confidentiality, and DPIA input)",
    "scenarios/information-protection/auto-label-confidential-sharepoint/ and .../auto-label-confidential-exchange/ (labeling/encrypting documents likely to contain EU personal data at rest and in transit - Article 5(1)(f), Article 32 security of processing)",
    "scenarios/dlp/exchange-pii-exfil-block/ (+ Part 2) (blocking unauthorized transmission of personal-data identifiers over email - Article 5(1)(f), Article 32)",
    "scenarios/data-lifecycle-management/event-based-retention-and-disposition/ (or another retention/disposition scenario) (enforcing the storage-limitation principle - Article 5(1)(e): personal data retained no longer than necessary)",
    "scenarios/unified-catalog/governance-domain-hierarchy/ and .../manage-data-products/ (a data inventory/ownership structure that is a genuine, if partial, technical building block toward an Article 30 Record of Processing Activities - see design.md Section 7 for the honest scope of this)",
    "scenarios/audit/premium-audit-investigation/ and .../compromised-account-incident-response/ (audit trail and incident response feeding the Article 33 72-hour breach-notification risk assessment)",
    "THEN create this assessment - built-in automation (design.md Section 4) picks up signals from controls already in place, reducing the manual-testing backlog a Contributor/Assessor faces on day one."
  ],
  "controlCrosswalk": {
    "_comment": "This is THIS LIBRARY'S OWN correlation of its scenarios to GDPR's own published structure (the three compliance areas Microsoft's own gdpr overview groups the regulation into - Data Subject Requests, Breach Notification, Data Protection Impact Assessment - plus the Article 5 processing principles, Article 46 cross-border transfer safeguards, and Article 30/37 accountability-and-governance obligations that sit alongside them) - it is NOT a reproduction of Microsoft's proprietary per-improvement-action automation mapping (which isn't published in a form this scenario can fetch and cite - see design.md Section 7, same constraint every sibling scenario's design.md documents for its own regulation). Use it to decide deployment order and to brief the organization's Data Protection Officer (if designated) or privacy lead on what this tenant's Microsoft 365 controls contribute - do not present it to a Data Protection Authority (in the event of a regulatory inquiry) or a data-subject complaint process as Microsoft's own control mapping, and do not present it as proof the organization's own Article 30 Records of Processing Activities or Article 35 DPIA obligations are complete (those are the organization's own legal obligations - see README.md Section 2/Section 11).",
    "categories": [
      { "category": "Data Subject Rights (DSR)", "articleCitation": "GDPR Articles 12-23 (access, rectification, erasure, restriction, portability, objection)", "coverage": "scenarios/ediscovery/gdpr-dsr-fulfillment/ - a purpose-built DSR-intake case-management scenario (per-request Article 12(3) SLA tracking, a data-subject-scoped eDiscovery case/custodian/search) that hands off to scenarios/ediscovery/premium-legal-hold-and-export/ (Access/Portability export) and scenarios/ediscovery/search-and-purge-data-spillage/ (Erasure) for fulfillment - the same underlying Exchange/SharePoint/OneDrive discovery capability Microsoft's own gdpr-dsr-office365 guidance points to. Rectification, Restriction, and Objection are tracked (ledger + SLA + a Discovery-stage search) but not technically fulfilled - no Purview-native control exists for any of the three (that scenario's design.md Section 6)." },
      { "category": "Data Processing Principles", "articleCitation": "GDPR Article 5 (lawfulness/fairness/transparency, purpose limitation, data minimization, accuracy, storage limitation, integrity and confidentiality)", "coverage": "scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/ (+ siblings) and scenarios/data-estate-insights/classification-coverage-report/ (knowing what personal data exists, supporting minimization and accuracy), scenarios/data-lifecycle-management/event-based-retention-and-disposition/ (storage limitation, Article 5(1)(e)), scenarios/information-protection/auto-label-confidential-sharepoint/, .../auto-label-confidential-exchange/, and scenarios/dlp/exchange-pii-exfil-block/ (+ Part 2) (integrity and confidentiality, Article 5(1)(f)). Lawfulness of processing itself (identifying a valid Article 6 legal basis for each processing activity) is an organizational/legal determination this library does not automate." },
      { "category": "Breach Notification", "articleCitation": "GDPR Articles 33-34 (72-hour notification to the supervisory Data Protection Authority; notification to affected data subjects without undue delay for high-risk breaches)", "coverage": "scenarios/audit/compromised-account-incident-response/ (post-compromise response feeding the required breach risk assessment), scenarios/audit/premium-audit-investigation/ (forensic investigation and log review supporting that risk assessment and the required breach documentation). This library does not script the notification obligations themselves (notifying the Data Protection Authority within 72 hours, or notifying affected individuals), which are organizational/legal processes, not a Purview policy - identical non-goal to the HIPAA/HITECH sibling's Breach Notification Rule treatment." },
      { "category": "Data Protection Impact Assessment (DPIA)", "articleCitation": "GDPR Article 35 (required for processing 'likely to result in a high risk to the rights and freedoms of natural persons')", "coverage": "Little to no direct technical automation from this Microsoft 365/Purview-only library - a DPIA is an organizational risk-assessment document, not a control this library configures. The genuine, partial technical input: scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/ and scenarios/data-estate-insights/sensitivity-label-coverage-report/ can supply the 'what personal data exists, where, and how is it currently protected' factual inputs a DPIA needs, but neither performs the required necessity/proportionality/risk analysis or produces a DPIA document itself." },
      { "category": "Cross-Border Data Transfers", "articleCitation": "GDPR Chapter V, Article 46 (transfers outside the EU/EEA require appropriate safeguards, e.g. Standard Contractual Clauses)", "coverage": "Out of scope for direct technical automation from this Microsoft 365/Purview-only library. Cross-border transfer safeguards (Standard Contractual Clauses, adequacy decisions, the EU-U.S. Data Privacy Framework) are contractual/legal instruments between the organization and Microsoft (or another processor), not a Purview policy this scenario configures - Microsoft's own published position (README.md Section 11, reference 6). No scenario in this library scopes multi-geo data residency for GDPR purposes as of this writing; tracked as a PROGRESS.md follow-up." },
      { "category": "Accountability & Governance", "articleCitation": "GDPR Article 5(2) (accountability principle), Article 24 (responsibility of the controller), Article 30 (records of processing activities), Article 37 (DPO designation, where applicable)", "coverage": "scenarios/unified-catalog/governance-domain-hierarchy/ and .../manage-data-products/ are a genuine, if partial, technical building block toward an Article 30 Record of Processing Activities - Purview's catalog documents data assets/products and their ownership/domain, not GDPR's specific Article 30(1) schema (processing purposes, categories of recipients, retention periods, and transfer safeguards per processing activity) - a real, disclosed gap, not a reproduction of an Article 30 register. scenarios/audit/premium-audit-investigation/ supports ongoing oversight. Article 37 DPO designation itself is an organizational/legal determination and appointment this library does not automate - see roleAssignments.note above." }
    ],
    "principlesNote": "Unlike HIPAA/HITECH's 'addressable is not optional' Security Rule distinction (which has no analog here), GDPR's own structural trap this crosswalk guards against is different: treating a high Compliance Manager score, or completion of the improvement actions Microsoft's automation surfaces, as equivalent to having a documented Article 6 lawful basis for every processing activity and a complete Article 30 record of processing. Neither is something Compliance Manager (or this scenario) can verify - see README.md Section 11."
  },
  "auditMonitoring": {
    "operations": [
      "ComplianceManagerRolesChange",
      "ComplianceManagerAutomationLevelChange",
      "ComplianceManagerAutomationChange"
    ],
    "note": "These 3 operations are TENANT-WIDE Compliance Manager events, not scoped to a single assessment. This scenario deliberately REUSES scenarios/compliance-manager/assess-against-iso27001/deploy/Export-ComplianceManagerAuditTrail.ps1 (also copied into scenarios/compliance-manager/pci-dss-assessment/deploy/, scenarios/compliance-manager/soc2-assessment/deploy/, and scenarios/compliance-manager/hipaa-hitech-assessment/deploy/) rather than shipping a fifth, functionally-identical copy - run ONE instance against a shared CSV path if more than one of these scenarios is deployed. See design.md Section 2 and README.md Section 5."
  },
  "notAValidGdprCertification": "A Compliance Manager assessment - however complete - is an internal readiness-tracking and evidence tool. GDPR Article 42 does describe a certification mechanism (and Article 43 describes accredited certification bodies) - a genuine difference from HIPAA, where no HHS-approved certification exists for anyone - but current practice is fragmented across individual national supervisory authorities and accredited certification bodies rather than a single unified EU-wide seal (README.md Section 11, reference 8). This Compliance Manager assessment is not, and does not progress toward, any Article 42/43 certification, and must never be presented as 'GDPR certified.' It also does not substitute for the organization's own legally required Article 30 Records of Processing Activities, Article 35 Data Protection Impact Assessments, or its Article 28 processor-agreement obligations with Microsoft. See README.md Section 2/Section 11.",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-16"
}
```