---
part: "deploy"
parent: "communication-compliance/harassment-and-code-of-conduct"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-CommunicationComplianceAuditTrail.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Exports a rolling audit trail of Communication Compliance policy matches, policy changes, and
    review-tag activity from the unified audit log, for retention and drift detection beyond what
    the native Communication Compliance reports provide.

.DESCRIPTION
    Communication Compliance has no write API this repo's other deploy scripts could target (see
    design.md Section 2) - policy creation, condition tuning, and reviewer assignment are portal-
    only. This script targets the one thing about Communication Compliance that IS reachable
    through a documented API: its footprint in the Microsoft 365 unified audit log, via
    Search-UnifiedAuditLog (automation surface 1 per docs/automation-surface.md Section 1).

    Microsoft's audit-log-activities reference and its dedicated reports-audits/SIEM articles
    document three categories of Communication-Compliance-specific audit event, each requiring its
    own -RecordType/-Operations combination in Microsoft's own worked examples (design.md Section 4)
    - this script therefore issues three separate Search-UnifiedAuditLog queries rather than
    guessing that one unified call covers all five underlying Operation values:

      1. Policy match   - Operations SupervisionRuleMatch (a message matched a policy's conditions)
      2. Policy update   - RecordType Discovery, Operations SupervisionPolicyCreated /
         SupervisionPolicyUpdated / SupervisionPolicyDeleted (an admin changed a policy)
      3. Review tag       - RecordType AeD, Operations SupervisoryReviewTag (a reviewer tagged or
         resolved a message during investigation - the remediation-side signal)

    Idempotency model: like scenarios/compliance-manager/assess-against-iso27001's audit-trail
    script, this accumulates a ROLLING HISTORY of discrete events across potentially-overlapping
    date-range calls (e.g. a daily scheduled run whose window overlaps the prior run's tail). Every
    run merges newly-fetched records into the existing CSV, de-duplicating by a composite key of
    (CreationDate, Operations, UserIds, a stable hash of the full AuditData JSON payload) - so
    re-running with an overlapping or identical date range never produces duplicate rows. See
    design.md Section 8.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script. Read-only against the tenant: it never creates, modifies, or deletes any policy, alert,
    or message - the only side effect is the CSV file this script writes, which IS gated behind
    $PSCmdlet.ShouldProcess() so -WhatIf reports the records that would be merged without touching
    disk.

    This script does NOT capture message content, sender/recipient PII beyond what Search-
    UnifiedAuditLog's UserIds column already returns, or the specific classifier/keyword that
    matched - see README.md Section 11 for what it does and does not replace.

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
    Standard PowerShell ShouldProcess dry-run. The three Search-UnifiedAuditLog queries still
    execute (read-only; needed to report accurate would-be results), but the CSV file is not
    written - the script prints the count of new, non-duplicate records it would have merged.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-CommunicationComplianceAuditTrail.ps1 -OutputCsvPath './out/cc-audit-trail.csv' -WhatIf

    Dry run: queries the last 7 days across all three categories and reports how many new records
    would be merged, writes nothing.

.EXAMPLE
    ./Export-CommunicationComplianceAuditTrail.ps1 -OutputCsvPath './out/cc-audit-trail.csv'

    Merges the last 7 days of policy-match, policy-update, and review-tag events into the rolling
    CSV. Safe to schedule daily or weekly - overlapping windows never produce duplicate rows.

.EXAMPLE
    ./Export-CommunicationComplianceAuditTrail.ps1 -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
        -OutputCsvPath './out/cc-audit-trail.csv'

    A one-time backfill covering the full default Audit (Standard) retention window (README.md
    Section 11) before the first scheduled recurring run.

.NOTES
    VERIFY before relying on this for a compliance/HR investigation record beyond 180 days: default
    Audit (Standard) retention is 180 days for most workloads (one year for Entra ID/Exchange/
    OneDrive/SharePoint under an E5-tier license) - see README.md Section 11. Run this script on a
    recurring schedule (README.md Section 8) if the evidentiary window this scenario needs exceeds
    that retention, rather than relying on a single historical pull.

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

# Three query categories, each matching one of Microsoft's own documented worked examples verbatim
# (design.md Section 4) rather than a single guessed combined call.
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
    # De-duplication key for the rolling merge (design.md Section 8): a real audit event is
    # uniquely identified by when it happened, what happened, and who did it. CreationDate,
    # Operations, and UserIds are all confirmed top-level Search-UnifiedAuditLog output properties.
    # A flat, always-present unique-ID property is NOT confirmed as part of that output schema for
    # these operations - rather than assume one exists (AGENTS.md Section 4's no-invented-fields
    # rule), this key instead folds in a hash of the full AuditData JSON payload, which IS confirmed
    # to exist on every record, as the fourth uniqueness component.
    return '{0}|{1}|{2}|{3}' -f $Record.CreationDate, $Record.Operations, $Record.UserIds, (Get-StableStringHash -Value $Record.AuditData)
}

$allRecords = [System.Collections.Generic.List[object]]::new()

foreach ($query in $queryCategories) {
    Write-Host "Searching unified audit log: category '$($query.Category)' (RecordType=$($query.RecordType); Operations=$($query.Operations -join ',')) between $StartDate (UTC) and $EndDate (UTC)..." -ForegroundColor Cyan

    $sessionId = "cc-audit-trail-$($query.Category)-$([guid]::NewGuid())"
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
            # exported CSV can distinguish "a message matched a policy" from "a policy was edited"
            # from "a reviewer tagged/resolved a message" without re-deriving it from Operations.
            $record | Add-Member -NotePropertyName 'QueryCategory' -NotePropertyValue $query.Category -Force
        }
        if ($page.Count -gt 0) { $allRecords.AddRange($page) }
    } while ($page.Count -gt 0)
}

Write-Host "Found $($allRecords.Count) matching record(s) across all three categories in the search window." -ForegroundColor Green

$newRows = foreach ($record in $allRecords) {
    [pscustomobject]@{
        CreationDate  = $record.CreationDate
        Category      = $record.QueryCategory
        Operation     = $record.Operations
        UserIds       = $record.UserIds
        RecordType    = $record.RecordType
        AuditData     = $record.AuditData
        CompositeKey  = (Get-CompositeKey -Record $record)
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

    $policyUpdateRows = @($rowsToAdd | Where-Object { $_.Category -eq 'PolicyUpdate' })
    foreach ($row in $policyUpdateRows) {
        Write-Warning "Policy change detected: $($row.Operation) by $($row.UserIds) at $($row.CreationDate). Confirm this matches an intended, documented change - see README.md Section 8 incident-response guidance."
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

#### `policy/code-of-conduct-evasion-phrases.txt`

```
don't tell HR
don't tell hr
keep this between us
off the record
delete this after reading
delete this message
what happens here stays here
not for HR
don't put this in writing
don't report this
just between you and me
this never happened
don't tell legal
```

#### `policy/communication-compliance-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Communication Compliance has no documented REST, Graph, or PowerShell write API for policy creation or management as of this writing - Microsoft's own communication-compliance-policies and communication-compliance-configure articles both state explicitly: 'PowerShell isn't supported for creating and managing Communication Compliance policies. To create and manage these policies, use the policy management controls in the Communication Compliance solution.' (docs/automation-surface.md has no routing-table row for Communication Compliance for the same reason.) No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal wizard in README.md Section 5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked. This follows the identical precedent set by scenarios/insider-risk/departing-employee-data-theft/deploy/policy/departing-employee-policy-manifest.json and scenarios/compliance-manager/assess-against-iso27001/deploy/policy/iso27001-assessment-manifest.json for other portal-only Purview surfaces.",
  "policyType": "custom",
  "policyName": "Workplace Harassment and Code of Conduct - All Users",
  "policyNameNote": "Policy names cannot be changed after creation (Microsoft Learn: communication-compliance-policies). Confirm before creating.",
  "locations": [
    "Exchange Online",
    "Microsoft Teams",
    "Viva Engage"
  ],
  "locationsNote": "Matches the built-in 'Detect inappropriate text' template's location set exactly, but built as a custom policy (not from the template) so the classifier set and custom keyword dictionary below can be combined - see design.md Section 3. Third-party sources (e.g. Instant Bloomberg) require a connector configured separately and are out of scope here.",
  "direction": [
    "Inbound",
    "Outbound",
    "Internal"
  ],
  "usersInScope": {
    "option": "allUsers",
    "note": "Microsoft's own planning guidance recommends including all users for policies optimized for harassment or discrimination detection (communication-compliance-plan). Do not scope this to a subset unless the tenant has a documented reason (e.g. a phased pilot rollout - see README.md Section 8)."
  },
  "excludedUsersAndGroups": [],
  "reviewers": {
    "roleGroup": "Communication Compliance Investigators",
    "note": "Investigators (not Analysts) because HR/Legal need full message content access, not metadata-only, to credibly assess a harassment complaint (README.md Section 3, docs/rbac-model.md Section 4). Populate with named HR and Legal stakeholders per README.md Section 5 step 3 - do not leave this at the auto-assigned Communication Compliance Admins/Global Admin fallback (see userReportedMessagesPolicy below for why that fallback matters).",
    "placeholderMembers": [
      "hr-compliance-lead@contoso.example",
      "employment-legal-counsel@contoso.example"
    ]
  },
  "conditions": {
    "trainableClassifiers": [
      { "name": "Discrimination", "expectedVolume": "Low" },
      { "name": "Harassment", "expectedVolume": "Low", "note": "Microsoft's UI and some docs pages label this classifier 'Targeted harassment' - see README.md Section 11 for the documented naming inconsistency. Same underlying classifier." },
      { "name": "Profanity", "expectedVolume": "Medium" },
      { "name": "Threat", "expectedVolume": "Low" }
    ],
    "customKeywordDictionary": {
      "file": "code-of-conduct-evasion-phrases.txt",
      "purpose": "Catches organization-specific concealment/evasion phrasing the trainable classifiers are not designed to detect (e.g. 'don't tell HR', 'off the record') - NOT a duplicate slur/profanity list, since the Profanity/Harassment/Discrimination classifiers already cover that ground more robustly than a static keyword list could. See design.md Section 4."
    },
    "conditionCombination": "OR (Content matches any of these classifiers) OR (Message/Attachment contains any of these words, from the custom keyword dictionary)"
  },
  "reviewPercentage": 100,
  "reviewPercentageNote": "Microsoft's planning guidance recommends 100% for policies where catching every match matters (communication-compliance-plan). Lowering this is a documented alert-volume lever (README.md Section 8) - do not lower it silently without recording the decision here.",
  "filterEmailBlasts": true,
  "ocrEnabled": true,
  "ocrNote": "Catches screenshotted harassing content (memes, chat screenshots) shared as an image attachment - Communication Compliance's own built-in OCR, not the separate OCR (preview) setting used by DLP/IRM (see README.md Section 11).",
  "privacySettings": {
    "usernamePseudonymization": true,
    "note": "Settings > Communication Compliance > Privacy tab > 'Show anonymized versions of usernames' - portal-only, tenant-wide setting, not per-policy. Enable before Investigators begin triage so identity is revealed only when a case genuinely requires it (README.md Section 11, reviews.md CISO lens)."
  },
  "noticeTemplate": {
    "create": true,
    "name": "Code of Conduct Reminder Notice",
    "note": "Settings > Communication Compliance > Notice templates. Used by Investigators when the 'Notify' remediation action is the appropriate response to a lower-severity match (README.md Section 8)."
  },
  "userReportedMessagesPolicy": {
    "action": "reassignReviewers",
    "note": "This system policy is auto-created by the tenant's Communication Compliance license (up to 30 days after purchase) and its initial reviewers/creator default to the Communication Compliance Admins role group or, if that group is empty, a randomly selected Global Administrator (Microsoft Learn: communication-compliance-policies, 'User-reported messages policy'). Microsoft's own guidance is to immediately assign custom reviewers such as HR/Legal instead of leaving this default in place. Reassign to the same reviewers as policyName above.",
    "supportedChannels": ["Microsoft Teams (chat/channel messages)", "Viva Engage (conversations, preview)"]
  },
  "complianceBoundaryStep": {
    "required": false,
    "note": "Only needed if the tenant has eDiscovery compliance boundaries configured (README.md Section 5, Step 0). If so, run New-ComplianceSecurityFilter once (per-tenant, not per-policy) to grant Investigators/Admins access to the SupervisoryReview{*} scoped mailboxes - see Microsoft Learn: communication-compliance-configure#step-6-optional-update-compliance-boundaries-for-communication-compliance-policies."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-04"
}
```