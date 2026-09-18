---
part: "deploy"
parent: "communication-compliance/teams-viva-engage-content-safety"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-ContentSafetyAuditTrail.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Communication Compliance policy matches, policy changes, and
    review-tag activity for the Teams and Viva Engage Content Safety Detection policy, from the
    unified audit log, for retention and drift detection beyond Communication Compliance's native
    reporting window.

.DESCRIPTION
    Communication Compliance has no write API this repo's other deploy scripts could target (see
    design.md Section 3) - policy creation from a template, condition tuning, and reviewer
    assignment are portal-only, even for a template-based policy. This script targets the one thing
    about Communication Compliance that IS reachable through a documented API: its footprint in the
    Microsoft 365 unified audit log, via Search-UnifiedAuditLog (automation surface 1 per
    docs/automation-surface.md Section 1).

    This script reuses the identical three-query shape already grounded and shipped in both sibling
    Communication Compliance scenarios in this repo (harassment-and-code-of-conduct,
    copilot-interaction-detection), because Communication Compliance records its audit footprint
    identically regardless of which policy, template, or location produced the event (design.md
    Section 7) - reusing a grounded surface rather than inventing a new one:

      1. Policy match    - Operations SupervisionRuleMatch (a message matched one of this policy's
         four classifiers: Hate, Sexual, Violence, or Self-harm)
      2. Policy update    - RecordType Discovery, Operations SupervisionPolicyCreated /
         SupervisionPolicyUpdated / SupervisionPolicyDeleted (an admin changed the policy)
      3. Review tag       - RecordType AeD, Operations SupervisoryReviewTag (a reviewer tagged or
         resolved a match during investigation)

    Two things are genuinely new in this script, not copied from either sibling (design.md Section 7):

      - ContentSafetyContext / SeverityHint columns: best-effort, NEVER-BLOCKING parses of AuditData
        that try to identify which of the four classifiers a PolicyMatch row corresponds to, and the
        raw severity value if present. This is the first Communication Compliance scenario in this
        repo whose classifier family populates a Severity column at all - the exact AuditData shape
        for this pairing was not independently confirmed against a worked example during this
        scenario's grounding pass (README.md Section 11 VERIFY); a parse miss populates 'Unknown' /
        empty, never an error, and never drops the row.
      - A distinct, louder Write-Warning specifically for any newly-merged row whose
        ContentSafetyContext resolves to 'SelfHarm' - because a Self-harm match is the one outcome
        this scenario's entire operational design (README.md Section 8, design.md Section 6) is
        built around not missing. This is a delayed, schedule-dependent safety net, NOT a substitute
        for the immediate, in-portal duty-of-care escalation the runbook requires - see README.md
        Section 8 and this script's own console output.

    Idempotency model: identical rolling-history pattern to both sibling scripts - every run merges
    newly-fetched records into the existing CSV, de-duplicating by a composite key of
    (CreationDate, Operations, UserIds, a stable hash of the full AuditData JSON payload) - so
    re-running with an overlapping or identical date range never produces duplicate rows.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only against the tenant: it never creates, modifies, or deletes any policy, alert,
    or message - the only side effect is the CSV file this script writes, which IS gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports the records that would be merged without touching
    disk.

    This script does NOT capture the actual message text, sender/recipient PII beyond what
    Search-UnifiedAuditLog's UserIds column already returns, or a confirmed classifier/severity ID
    (see ContentSafetyContext/SeverityHint caveats above and README.md Section 11). It is NOT a
    substitute for the immediate, in-portal duty-of-care escalation README.md Section 8 requires for
    a Self-harm match - it is a secondary, after-the-fact record.

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

.PARAMETER PolicyNameFilter
    Client-side filter applied after fetching: only records whose parsed AuditData policy name
    equals this value are kept. Defaults to this scenario's own policy name
    ('Teams and Viva Engage Content Safety Detection - All Users'). Pass an empty string to disable
    filtering and capture every Communication Compliance policy's matching events.

.PARAMETER ResultSize
    Passed to Search-UnifiedAuditLog's page size when not using -SessionCommand ReturnLargeSet.
    Defaults to 5000 (the cmdlet's documented per-call maximum without paging).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The three Search-UnifiedAuditLog queries still
    execute (read-only; needed to report accurate would-be results), but the CSV file is not
    written - the script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-ContentSafetyAuditTrail.ps1 -OutputCsvPath './out/content-safety-audit-trail.csv' -WhatIf

    Dry run: queries the last 7 days across all three categories, filters to this scenario's policy
    name, and reports how many new records would be merged, writes nothing.

.EXAMPLE
    ./Export-ContentSafetyAuditTrail.ps1 -OutputCsvPath './out/content-safety-audit-trail.csv'

    Merges the last 7 days of policy-match, policy-update, and review-tag events into the rolling
    CSV. Safe to schedule daily or weekly - overlapping windows never produce duplicate rows.

.EXAMPLE
    ./Export-ContentSafetyAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/content-safety-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window (README.md
    Section 11) before the first scheduled recurring run.

.NOTES
    VERIFY before relying on this for a duty-of-care or Legal investigation record beyond 180 days:
    default Audit (Standard) retention is 180 days for most workloads (one year for Entra ID/
    Exchange/OneDrive/SharePoint under an E5-tier license) - see README.md Section 11. Run this
    script on a recurring schedule (README.md Section 8) if the evidentiary window this scenario
    needs exceeds that retention.

    VERIFY: the ContentSafetyContext/SeverityHint columns' parse is best-effort and not confirmed
    against a real tenant's AuditData shape for this classifier pairing - see README.md Section 11.

    This script's Self-harm warning is a secondary, schedule-dependent safety net - it does NOT
    replace the immediate, in-portal duty-of-care escalation README.md Section 8 requires.

    Sources (Microsoft Learn, verify before production use):
    - Audit log activities - Communication compliance activities table:
      https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities
    - Use Communication Compliance reports and audits (Discovery/AeD RecordType + Operations worked
      examples this script's three queries are built from verbatim):
      https://learn.microsoft.com/purview/communication-compliance-reports-audits
    - Use Communication Compliance with SIEM solutions (the SupervisionRuleMatch worked example):
      https://learn.microsoft.com/purview/communication-compliance-siem
    - Search-UnifiedAuditLog reference: https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Manage audit log retention policies: https://learn.microsoft.com/purview/audit-log-retention-policies
    - Harm categories in Azure AI Content Safety - severity levels, the basis for this script's
      SeverityHint best-effort label: https://learn.microsoft.com/azure/ai-services/content-safety/concepts/harm-categories
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
    [AllowEmptyString()]
    [string]$PolicyNameFilter = 'Teams and Viva Engage Content Safety Detection - All Users',

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

# Three query categories, each matching one of Microsoft's own documented worked examples verbatim
# (design.md Section 7) rather than a single guessed combined call.
$queryCategories = @(
    @{ Category = 'PolicyMatch'; RecordType = $null; Operations = @('SupervisionRuleMatch') }
    @{ Category = 'PolicyUpdate'; RecordType = 'Discovery'; Operations = @('SupervisionPolicyCreated', 'SupervisionPolicyUpdated', 'SupervisionPolicyDeleted') }
    @{ Category = 'ReviewTag'; RecordType = 'AeD'; Operations = @('SupervisoryReviewTag') }
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
    # De-duplication key for the rolling merge (design.md Section 7): a real audit event is
    # uniquely identified by when it happened, what happened, and who did it. CreationDate,
    # Operations, and UserIds are all confirmed top-level Search-UnifiedAuditLog output properties.
    # A flat, always-present unique-ID property is NOT confirmed as part of that output schema for
    # these operations - rather than assume one exists (AGENTS.md Section 4's no-invented-fields
    # rule), this key instead folds in a hash of the full AuditData JSON payload, which IS confirmed
    # to exist on every record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

function Get-ParsedAuditData {
    # Best-effort JSON parse - AuditData is documented as the "main data source" for every
    # Communication Compliance audit record, but its exact per-field schema for this specific
    # classifier pairing was not independently confirmed against a worked example (README.md
    # Section 11 VERIFY). Never throws: a parse failure returns $null so callers can degrade
    # gracefully instead of dropping the row.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$AuditDataJson)
    if ([string]::IsNullOrWhiteSpace($AuditDataJson)) { return $null }
    try {
        return $AuditDataJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-PolicyNameFromParsedAuditData {
    # Same candidate-property-name pattern as this repo's other Communication Compliance
    # audit-trail scripts (README.md Section 11) - checked in order, first present non-empty value
    # wins. Returns $null (never throws) if none match - the row is still kept, just not
    # attributable to a specific policy by this filter.
    param([Parameter(Mandatory)][AllowNull()]$Parsed)
    if ($null -eq $Parsed) { return $null }
    foreach ($property in 'PolicyName', 'Name', 'ObjectId') {
        $value = $Parsed.PSObject.Properties[$property]
        if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value.Value)) {
            return [string]$value.Value
        }
    }
    return $null
}

function Get-ContentSafetyContextLabel {
    # Best-effort, NEVER-BLOCKING classification of a policy-match record against this policy's
    # four classifiers. design.md Section 7 / README.md Section 11 both flag this as unconfirmed
    # against a real worked example for this classifier pairing - 'Unknown' is a normal, expected,
    # non-error outcome, not a bug.
    param([Parameter(Mandatory)]$Category, [Parameter(Mandatory)][AllowNull()]$Parsed)
    if ($Category -ne 'PolicyMatch' -or $null -eq $Parsed) { return 'N/A' }
    $candidateText = ($Parsed | ConvertTo-Json -Depth 6 -Compress)
    if ($candidateText -match 'Self[\s-]?[Hh]arm') { return 'SelfHarm' }
    if ($candidateText -match '\bHate\b') { return 'Hate' }
    if ($candidateText -match '\bSexual\b') { return 'Sexual' }
    if ($candidateText -match '\bViolence\b') { return 'Violence' }
    return 'Unknown'
}

function Get-SeverityHint {
    # Best-effort, NEVER-BLOCKING extraction of a raw severity value if the parsed AuditData
    # happens to carry a recognizably-named field. Not confirmed against a worked example
    # (README.md Section 11) - an empty string is the expected, non-error default.
    param([Parameter(Mandatory)][AllowNull()]$Parsed)
    if ($null -eq $Parsed) { return '' }
    foreach ($property in 'Severity', 'severity', 'SeverityLevel') {
        $value = $Parsed.PSObject.Properties[$property]
        if ($value -and -not [string]::IsNullOrWhiteSpace([string]$value.Value)) {
            return [string]$value.Value
        }
    }
    return ''
}

$allRecords = [System.Collections.Generic.List[object]]::new()

foreach ($query in $queryCategories) {
    Write-Host "Searching unified audit log: category '$($query.Category)' (RecordType=$($query.RecordType); Operations=$($query.Operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

    $sessionId = "content-safety-audit-$($query.Category)-$([guid]::NewGuid())"
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

        # Wrapping in @() up front avoids PowerShell's single-object-vs-array ambiguity: a page
        # that returns exactly one record would otherwise come back as a scalar with no .Count
        # property, which would make the loop-continuation check below silently misbehave.
        $page = @(Search-UnifiedAuditLog @searchParams)
        foreach ($record in $page) {
            $record | Add-Member -NotePropertyName 'QueryCategory' -NotePropertyValue $query.Category -Force
        }
        if ($page.Count -gt 0) { $allRecords.AddRange($page) }
    } while ($page.Count -gt 0)
}

Write-Host "Found $($allRecords.Count) matching record(s) across all three categories in the search window." -ForegroundColor Green

$filteredRecords = if ([string]::IsNullOrEmpty($PolicyNameFilter)) {
    $allRecords
}
else {
    $kept = [System.Collections.Generic.List[object]]::new()
    $unattributed = 0
    foreach ($record in $allRecords) {
        $parsed = Get-ParsedAuditData -AuditDataJson $record.AuditData
        $policyName = Get-PolicyNameFromParsedAuditData -Parsed $parsed
        if ($null -eq $policyName) {
            # Can't attribute this record to any policy by name - keep it rather than silently drop
            # a possibly-relevant event; README.md Section 11 documents this as a known, disclosed
            # limitation of client-side filtering, not a reason to lose data.
            $kept.Add($record)
            $unattributed++
        }
        elseif ($policyName -eq $PolicyNameFilter) {
            $kept.Add($record)
        }
    }
    if ($unattributed -gt 0) {
        Write-Verbose "$unattributed record(s) had no parsable policy name and were kept rather than dropped (see .NOTES on best-effort AuditData parsing)."
    }
    $kept
}

Write-Host "$($filteredRecords.Count) record(s) remain after applying -PolicyNameFilter '$PolicyNameFilter' (of $($allRecords.Count) fetched)." -ForegroundColor Cyan

$newRows = foreach ($record in $filteredRecords) {
    $parsed = Get-ParsedAuditData -AuditDataJson $record.AuditData
    [pscustomobject]@{
        CreationDate         = $record.CreationDate
        Category             = $record.QueryCategory
        Operation            = $record.Operations
        UserIds              = $record.UserIds
        RecordType           = $record.RecordType
        ContentSafetyContext = Get-ContentSafetyContextLabel -Category $record.QueryCategory -Parsed $parsed
        SeverityHint         = Get-SeverityHint -Parsed $parsed
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

Write-Host "$($rowsToAdd.Count) new, non-duplicate record(s) to merge (of $($newRows.Count) fetched after filtering)." -ForegroundColor Cyan

$mergeDescription = "Merge $($rowsToAdd.Count) new record(s) into '$OutputCsvPath'"
if ($rowsToAdd.Count -eq 0) {
    Write-Host "Nothing to merge - CSV already up to date for this window." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($OutputCsvPath, $mergeDescription)) {
    $allRows = @($existingRows) + @($rowsToAdd)
    $allRows | Sort-Object CreationDate | Export-Csv -Path $OutputCsvPath -NoTypeInformation
    Write-Host "Audit trail updated: $OutputCsvPath ($($allRows.Count) total row(s))." -ForegroundColor Green

    $policyUpdateRows = @($rowsToAdd | Where-Object { $_.Category -eq 'PolicyUpdate' })
    foreach ($row in $policyUpdateRows) {
        Write-Warning "Policy change detected: $($row.Operation) by $($row.UserIds) at $($row.CreationDate). Confirm this matches an intended, documented change - see README.md Section 8 incident-response guidance."
    }

    $selfHarmRows = @($rowsToAdd | Where-Object { $_.ContentSafetyContext -eq 'SelfHarm' })
    if ($selfHarmRows.Count -gt 0) {
        Write-Warning "*** $($selfHarmRows.Count) possible Self-harm classifier match(es) recorded this run. *** This is a SECONDARY, schedule-dependent record - it does NOT substitute for the immediate, in-portal duty-of-care escalation README.md Section 8 requires. If this run's schedule means significant time has passed since the underlying message was sent, confirm the escalation runbook was already followed at the time of the original alert; do not treat discovering it here as the first response."
    }

    $reviewTagCount = @($rowsToAdd | Where-Object { $_.Category -eq 'ReviewTag' }).Count
    if ($reviewTagCount -gt 0) {
        Write-Host "$reviewTagCount review-tag/resolution event(s) recorded this run - see README.md Section 8 for the recommended reviewer-workload cadence check." -ForegroundColor Cyan
    }
}
else {
    Write-Verbose "WhatIf: would $mergeDescription"
}
```

#### `policy/content-safety-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Communication Compliance has no documented REST, Graph, or PowerShell write API for policy creation or management as of this writing - including policies created from a built-in template. Microsoft's own communication-compliance-policies article states explicitly: 'PowerShell isn't supported for creating and managing Communication Compliance policies. To create and manage these policies, use the policy management controls in the Communication Compliance solution.' No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed policy (and the duty-of-care escalation prerequisite) can be diffed against intent during review. Follows the identical precedent set by scenarios/communication-compliance/harassment-and-code-of-conduct/ and scenarios/communication-compliance/copilot-interaction-detection/ for the same no-write-API Purview surface.",
  "policyType": "template",
  "policyTemplate": "Detect inappropriate content",
  "policyName": "Teams and Viva Engage Content Safety Detection - All Users",
  "policyNameNote": "Policy names cannot be changed after creation (Microsoft Learn: communication-compliance-policies). Confirm before creating.",
  "locations": [
    "Microsoft Teams",
    "Viva Engage"
  ],
  "locationsNote": "Template-fixed locations. Does NOT include Exchange (unsupported by this classifier family) or Microsoft Copilot experiences (supported by the classifiers in general, but not part of this template's fixed location list) - see README.md Section 8 for the documented, optional edit to add Copilot as a location to this or another policy.",
  "direction": [
    "Inbound",
    "Outbound",
    "Internal"
  ],
  "usersInScope": {
    "option": "allUsers",
    "note": "Deliberately not piloted on a subset - README.md Section 8 explains why narrowing scope here means narrowing self-harm-risk coverage, a materially different trade-off than narrowing a general conduct-monitoring policy's blast radius."
  },
  "excludedUsersAndGroups": [],
  "reviewers": {
    "roleGroup": "Communication Compliance Investigators",
    "note": "Deliberately the SAME reviewer pool as scenarios/communication-compliance/harassment-and-code-of-conduct/ - one trained HR/Legal team handling both policies' overlapping risk categories rather than a duplicated pool (design.md Section 5). Populate with the same named stakeholders already assigned to that policy, plus confirm each has completed the duty-of-care runbook acknowledgment below.",
    "placeholderMembers": [
      "hr-compliance-lead@contoso.example",
      "legal-employment-counsel@contoso.example"
    ]
  },
  "dutyOfCareEscalationContact": {
    "_comment": "THIS IS THIS SCENARIO'S CENTRAL GO-LIVE PRECONDITION, NOT AN OPTIONAL FIELD. Communication Compliance has no product capability to route a Self-harm-classifier match differently from a Hate/Sexual/Violence match (design.md Section 6) - this contact and the acknowledgment below are a process control this scenario's own runbook depends on entirely.",
    "contactRole": "Employee Assistance Program (EAP) / HR duty-of-care contact - REPLACE with a named, reachable individual or team, not a generic mailbox with unmonitored response time",
    "contactMethod": "REPLACE with the organization's actual escalation channel (phone, paging system, dedicated email with an SLA)",
    "afterHoursCoverageConfirmed": false,
    "afterHoursCoverageNote": "Set to true only once weekend/after-hours reachability is explicitly confirmed, not assumed. A business-hours-only contact means a Friday-evening message could go unaddressed until Monday - see README.md Section 8. If true after-hours coverage isn't available, document that as an accepted residual risk rather than leaving this implied.",
    "runbookAcknowledged": false,
    "runbookAcknowledgedNote": "Set to true only once the named contact and the full HR/Legal reviewer pool above have completed the README.md Section 7 tabletop drill and confirmed they understand the README.md Section 8 escalation runbook. Do NOT create the policy in the portal (README.md Section 5, step 10) until this is true."
  },
  "conditions": {
    "template": {
      "note": "The template's fixed classifier set is used unmodified - no custom keyword dictionary or additional classifier is added. See design.md Section 2.",
      "classifiers": [
        { "name": "Hate", "technology": "Azure AI Content Safety LLM classifier (preview)", "overlapsWith": "Discrimination/Harassment trainable classifiers in harassment-and-code-of-conduct - complementary, not redundant (design.md Section 4)" },
        { "name": "Sexual", "technology": "Azure AI Content Safety LLM classifier (preview)", "overlapsWith": "No trainable-classifier equivalent for text - new coverage (design.md Section 4)" },
        { "name": "Violence", "technology": "Azure AI Content Safety LLM classifier (preview)", "overlapsWith": "Threat trainable classifier in harassment-and-code-of-conduct - complementary, not redundant (design.md Section 4)" },
        { "name": "Self-harm", "technology": "Azure AI Content Safety LLM classifier (preview)", "overlapsWith": "No trainable-classifier equivalent - new coverage; the primary reason this scenario exists (design.md Section 1)" }
      ]
    }
  },
  "reviewPercentage": 100,
  "reviewPercentageNote": "Template default. Do not lower this silently - see README.md Section 8; a self-harm/violence risk control is a poor candidate for sampling below 100%.",
  "severityThreshold": {
    "value": 4,
    "scale": "Azure AI Content Safety 0-7 scale, trimmed to 0/2/4/6 in the Communication Compliance Severity column",
    "note": "A match below severity 4 does not populate the Severity column or necessarily surface as a standalone alert - see README.md Section 6/11 for the documented word-count-threshold inconsistency that also affects whether a short message is evaluated at all."
  },
  "filterEmailBlasts": {
    "applicable": false,
    "note": "Email-blast filtering is an Exchange-mailbox-scoped setting; this policy's locations (Teams, Viva Engage) have no email-blast concept."
  },
  "ocrEnabled": {
    "applicable": false,
    "note": "This classifier family does not evaluate OCR images or attachments (README.md Section 11)."
  },
  "privacySettings": {
    "usernamePseudonymization": true,
    "note": "Settings > Communication Compliance > Privacy tab > 'Show anonymized versions of usernames' - portal-only, tenant-wide setting, not per-policy. Skip this step if already enabled by harassment-and-code-of-conduct or copilot-interaction-detection."
  },
  "payg": {
    "required": false,
    "note": "No PAYG requirement documented for this scenario's scope (Teams, Viva Engage) during this build's grounding pass - distinct from the Enterprise AI apps/Other AI apps generative-AI locations. Confirm against the Product Terms before a sales commitment (README.md Section 3/10)."
  },
  "relatedPolicies": {
    "harassmentAndCodeOfConduct": "Deliberately separate, complementary policy - see design.md Section 4 for the full overlap analysis (Threat vs. Violence, Discrimination/Harassment vs. Hate). Not merged into one custom policy.",
    "copilotInteractionDetection": "Unrelated risk categories (jailbreak/IP exposure vs. this policy's conduct/welfare categories) - different reviewer pool, no overlap expected.",
    "addCopilotLocationOption": "Documented, optional edit (README.md Section 8) to extend this policy's classifiers to the Microsoft Copilot experiences location - not part of this manifest's default configuration."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-15"
}
```