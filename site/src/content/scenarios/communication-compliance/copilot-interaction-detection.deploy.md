---
part: "deploy"
parent: "communication-compliance/copilot-interaction-detection"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-CopilotInteractionAuditTrail.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Communication Compliance policy matches, policy changes, and
    review-tag activity for the Microsoft 365 Copilot Interaction Detection policy, from the
    unified audit log, for retention and drift detection beyond Communication Compliance's native
    reporting window.

.DESCRIPTION
    Communication Compliance has no write API this repo's other deploy scripts could target (see
    design.md Section 3) - policy creation from a template, condition tuning, and reviewer
    assignment are portal-only, even for a template-based policy. This script targets the one thing
    about Communication Compliance that IS reachable through a documented API: its footprint in the
    Microsoft 365 unified audit log, via Search-UnifiedAuditLog (automation surface 1 per
    docs/automation-surface.md Section 1).

    This script reuses the identical three-query shape already grounded and shipped in
    scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/
    Export-CommunicationComplianceAuditTrail.ps1, because Communication Compliance records its
    audit footprint identically regardless of which policy, template, or location produced the
    event (design.md Section 7) - reusing a grounded surface rather than inventing a
    Copilot-specific one that doesn't exist:

      1. Policy match    - Operations SupervisionRuleMatch (a prompt or response matched a policy's
         conditions - Prompt Shields or Protected material, in this scenario's case)
      2. Policy update    - RecordType Discovery, Operations SupervisionPolicyCreated /
         SupervisionPolicyUpdated / SupervisionPolicyDeleted (an admin changed a policy)
      3. Review tag       - RecordType AeD, Operations SupervisoryReviewTag (a reviewer tagged or
         resolved an interaction during investigation - the remediation-side signal)

    Two things are genuinely new in this script, not copied verbatim (design.md Section 7):

      - -PolicyNameFilter: Search-UnifiedAuditLog has no documented -PolicyName parameter, so this
        script fetches all matching records for the query categories above, then filters
        client-side on a best-effort parse of the policy name out of each record's AuditData JSON.
        Defaults to this scenario's own policy name so a tenant running both this scenario and
        harassment-and-code-of-conduct side by side gets two separate, correctly-attributed rolling
        CSVs instead of one merged file. Pass -PolicyNameFilter '' (empty string) to disable
        filtering and capture every Communication Compliance policy's events in one file.
      - CopilotContext column: a best-effort, NEVER-BLOCKING parse of AuditData looking for a
        classifier-name field to distinguish a Prompt Shields (prompt-side) match from a Protected
        material (response-side) match without a human having to open the raw JSON. The exact
        AuditData shape for this specific classifier pairing was not independently confirmed
        against a worked example during this scenario's grounding pass (README.md Section 11
        VERIFY) - a parse miss populates 'Unknown', never an error, and never drops the row.

    Idempotency model: identical rolling-history pattern to the harassment scenario's script - every
    run merges newly-fetched records into the existing CSV, de-duplicating by a composite key of
    (CreationDate, Operations, UserIds, a stable hash of the full AuditData JSON payload) - so
    re-running with an overlapping or identical date range never produces duplicate rows.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only against the tenant: it never creates, modifies, or deletes any policy, alert,
    prompt, or response - the only side effect is the CSV file this script writes, which IS gated
    behind $PSCmdlet.ShouldProcess() so -WhatIf reports the records that would be merged without
    touching disk.

    This script does NOT capture the actual prompt/response text, sender/recipient PII beyond what
    Search-UnifiedAuditLog's UserIds column already returns, or a confirmed classifier ID (see
    CopilotContext caveat above and README.md Section 11).

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
    ('Microsoft 365 Copilot Interaction Detection - All Users'). Pass an empty string to disable
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
    ./Export-CopilotInteractionAuditTrail.ps1 -OutputCsvPath './out/copilot-interaction-audit-trail.csv' -WhatIf

    Dry run: queries the last 7 days across all three categories, filters to this scenario's policy
    name, and reports how many new records would be merged, writes nothing.

.EXAMPLE
    ./Export-CopilotInteractionAuditTrail.ps1 -OutputCsvPath './out/copilot-interaction-audit-trail.csv'

    Merges the last 7 days of policy-match, policy-update, and review-tag events into the rolling
    CSV. Safe to schedule daily or weekly - overlapping windows never produce duplicate rows.

.EXAMPLE
    ./Export-CopilotInteractionAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/copilot-interaction-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window (README.md
    Section 11) before the first scheduled recurring run.

.NOTES
    VERIFY before relying on this for a Responsible-AI/Legal investigation record beyond 180 days:
    default Audit (Standard) retention is 180 days for most workloads (one year for Entra ID/
    Exchange/OneDrive/SharePoint under an E5-tier license) - see README.md Section 11. Run this
    script on a recurring schedule (README.md Section 8) if the evidentiary window this scenario
    needs exceeds that retention, rather than relying on a single historical pull.

    VERIFY: the CopilotContext column's classifier-name parse is best-effort and not confirmed
    against a real tenant's AuditData shape for this classifier pairing - see README.md Section 11.

    Sources (Microsoft Learn, verify before production use):
    - Audit log activities - Communication compliance activities table (the friendly-name groupings
      this script's three categories mirror):
      https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities
    - Use Communication Compliance reports and audits (the Discovery/AeD RecordType + Operations
      worked examples this script's three queries are built from verbatim):
      https://learn.microsoft.com/purview/communication-compliance-reports-audits
    - Use Communication Compliance with SIEM solutions (the SupervisionRuleMatch Operations/
      RecordType worked example):
      https://learn.microsoft.com/purview/communication-compliance-siem
    - Search-UnifiedAuditLog reference (-StartDate/-EndDate/-Operations/-RecordType/-ResultSize/
      -SessionCommand): https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/
      Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies):
      https://learn.microsoft.com/purview/audit-log-retention-policies
    - Trainable classifiers definitions - Prompt Shields / Protected material scope (prompts-only /
      responses-only), the basis for this script's CopilotContext best-effort label:
      https://learn.microsoft.com/purview/trainable-classifiers-definitions#prompt-shields
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
    [string]$PolicyNameFilter = 'Microsoft 365 Copilot Interaction Detection - All Users',

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
    # Communication Compliance's AuditData JSON has been observed (not independently confirmed on a
    # worked example for this exact classifier pairing, README.md Section 11) to carry the policy
    # name under one of these candidate property names depending on Operations/RecordType. Checked
    # in order; the first present, non-empty value wins. Returns $null (never throws) if none match
    # - the row is still kept, just not attributable to a specific policy by this filter.
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

function Get-CopilotContextLabel {
    # Best-effort, NEVER-BLOCKING classification of a policy-match record as prompt-side (Prompt
    # Shields) vs. response-side (Protected material) vs. unknown, by looking for a classifier-name
    # field in the parsed AuditData. Design.md Section 7 / README.md Section 11 both flag this as
    # unconfirmed against a real worked example for this classifier pairing - 'Unknown' is a normal,
    # expected, non-error outcome, not a bug.
    param([Parameter(Mandatory)]$Category, [Parameter(Mandatory)][AllowNull()]$Parsed)
    if ($Category -ne 'PolicyMatch' -or $null -eq $Parsed) { return 'N/A' }
    $candidateText = ($Parsed | ConvertTo-Json -Depth 6 -Compress)
    if ($candidateText -match 'Prompt\s*Shield') { return 'PromptShields-PromptMatch' }
    if ($candidateText -match 'Protected\s*[Mm]aterial') { return 'ProtectedMaterial-ResponseMatch' }
    return 'Unknown'
}

$allRecords = [System.Collections.Generic.List[object]]::new()

foreach ($query in $queryCategories) {
    Write-Host "Searching unified audit log: category '$($query.Category)' (RecordType=$($query.RecordType); Operations=$($query.Operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

    $sessionId = "copilot-interaction-audit-$($query.Category)-$([guid]::NewGuid())"
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
            # Tag each record with its query category before merging the three result sets, so the
            # exported CSV can distinguish "an interaction matched a policy" from "a policy was
            # edited" from "a reviewer tagged/resolved an interaction" without re-deriving it from
            # Operations.
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
        CreationDate    = $record.CreationDate
        Category        = $record.QueryCategory
        Operation       = $record.Operations
        UserIds         = $record.UserIds
        RecordType      = $record.RecordType
        CopilotContext  = Get-CopilotContextLabel -Category $record.QueryCategory -Parsed $parsed
        AuditData       = $record.AuditData
        CompositeKey    = (Get-CompositeKey -Record $record)
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

    $promptShieldsCount = @($rowsToAdd | Where-Object { $_.CopilotContext -eq 'PromptShields-PromptMatch' }).Count
    if ($promptShieldsCount -gt 0) {
        Write-Warning "$promptShieldsCount possible Prompt Shields (jailbreak-attempt) match(es) recorded this run - see README.md Section 8 incident-response guidance, step 1 (route to Security first)."
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

#### `policy/copilot-interaction-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Communication Compliance has no documented REST, Graph, or PowerShell write API for policy creation or management as of this writing - including policies created from a built-in template. Microsoft's own communication-compliance-policies and communication-compliance-configure articles both state explicitly: 'PowerShell isn't supported for creating and managing Communication Compliance policies. To create and manage these policies, use the policy management controls in the Communication Compliance solution.' (docs/automation-surface.md has no routing-table row for Communication Compliance for the same reason.) No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked. This follows the identical precedent set by scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/policy/communication-compliance-policy-manifest.json for the same no-write-API Purview surface.",
  "policyType": "template",
  "policyTemplate": "Detect Microsoft 365 Copilot and Microsoft 365 Copilot Chat interactions",
  "policyName": "Microsoft 365 Copilot Interaction Detection - All Users",
  "policyNameNote": "Policy names cannot be changed after creation (Microsoft Learn: communication-compliance-policies). Confirm before creating.",
  "locations": [
    "Microsoft 365 Copilot and Microsoft 365 Copilot Chat"
  ],
  "locationsNote": "Template-fixed location. Does NOT include Enterprise AI apps or Other AI apps - both require enabling pay-as-you-go billing, which this scenario deliberately keeps out of scope (design.md Section 8, README.md Section 3/10). Extending to those locations is a documented, separate follow-up (README.md Section 8, 'Add a generative AI app as a location for an existing policy').",
  "direction": [
    "Inbound",
    "Outbound",
    "Internal"
  ],
  "usersInScope": {
    "option": "allUsers",
    "note": "This scenario's default, matching the template's intent of reviewing all Copilot usage. Consider a time-boxed pilot scoped to Select users (the tenant's Copilot pilot cohort) before expanding to All users if this is the tenant's first Communication Compliance policy targeting Copilot - see README.md Section 8. Record any such exception here, don't let a 'temporary' pilot scope quietly become permanent."
  },
  "excludedUsersAndGroups": [],
  "reviewers": {
    "roleGroup": "Communication Compliance Investigators",
    "note": "Investigators (not Analysts) because a credible jailbreak/protected-material assessment needs full prompt/response text, not metadata-only access (README.md Section 3, design.md Section 6, docs/rbac-model.md Section 4). This scenario's default reviewer pool is Security/Responsible-AI/Legal, not HR/Legal (the harassment-and-code-of-conduct scenario's pool) - populate with named stakeholders per README.md Section 5 step 2.",
    "placeholderMembers": [
      "responsible-ai-lead@contoso.example",
      "security-operations@contoso.example"
    ]
  },
  "conditions": {
    "template": {
      "note": "The template's fixed classifier pair is used unmodified - no custom keyword dictionary or additional classifier is added, unlike harassment-and-code-of-conduct's custom policy. See design.md Section 2 for why the template is the correct choice here rather than rebuilding the same configuration as a custom policy.",
      "classifiers": [
        {
          "name": "Prompt Shields",
          "evaluates": "Prompts only",
          "detects": "User prompt-injection / jailbreak attempts",
          "language": "English only"
        },
        {
          "name": "Protected material",
          "evaluates": "Responses only",
          "detects": "Known copyrighted or branded text content reproduced by Copilot",
          "language": "English only"
        }
      ]
    }
  },
  "reviewPercentage": 100,
  "reviewPercentageNote": "Template default. Lowering this is a documented alert-volume lever (README.md Section 8) - do not lower it silently without recording the decision here.",
  "filterEmailBlasts": {
    "applicable": false,
    "note": "Email-blast filtering is an Exchange-mailbox-scoped setting; this policy's sole location is Microsoft 365 Copilot and Microsoft 365 Copilot Chat, which has no email-blast concept."
  },
  "ocrEnabled": {
    "applicable": false,
    "note": "OCR scans image attachments in Exchange/Teams; Copilot prompt/response body content is text, not an attachment-bearing location."
  },
  "privacySettings": {
    "usernamePseudonymization": true,
    "note": "Settings > Communication Compliance > Privacy tab > 'Show anonymized versions of usernames' - portal-only, tenant-wide setting, not per-policy. Shared with any other Communication Compliance policy in the tenant; skip this step if already enabled by harassment-and-code-of-conduct or another policy."
  },
  "payg": {
    "required": false,
    "note": "Microsoft 365 Copilot detection has no PAYG requirement. PAYG applies only to Enterprise AI apps / Other AI apps locations, which this manifest's locations list deliberately excludes (README.md Section 3/10)."
  },
  "relatedPolicies": {
    "note": "Optional alternative/complement: adding 'Microsoft Copilot experiences' as a location to an existing Communication Compliance policy (e.g. harassment-and-code-of-conduct) applies THAT policy's own classifiers to Copilot too - a different condition set (Threat/Harassment/Discrimination/Profanity, not Prompt Shields/Protected material) achieved via a documented edit rather than this template. This scenario deploys a separate, dedicated policy instead - see design.md Section 8 for why the two are not merged.",
    "irmIntegration": "Prompt Shields and Protected material detection can optionally feed Insider Risk Management's Risky AI usage (or Data leaks / Data leaks by risky/priority users) policy templates via the Policy indicators setting - a standalone IRM scenario this repo doesn't yet build (tracked in PROGRESS.md), not configured by this manifest."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-11"
}
```