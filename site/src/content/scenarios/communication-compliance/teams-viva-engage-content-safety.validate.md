---
part: "validate"
parent: "communication-compliance/teams-viva-engage-content-safety"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ContentSafetyAuditTrail.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV this scenario's deploy script produces, and prints a manual
    verification checklist for the policy and the Self-harm duty-of-care runbook, neither of which
    has a read API to check programmatically.

.DESCRIPTION
    Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - The CSV has the expected columns and at least the header (an empty file with zero data
         rows is not itself a failure - it means no matching audit events occurred in every window
         run so far, which is the expected common case immediately after deployment).
       - No duplicate CompositeKey rows - proof the deploy script's merge-and-de-duplicate design
         (design.md Section 7) is actually holding across re-runs.
       - Every row's Category value is one of the three documented query categories, and every
         row's Operation value is one of the five documented Communication Compliance operations
         (design.md Section 7).
       - Every row's ContentSafetyContext value is one of the six documented labels this script's
         Get-ContentSafetyContextLabel function can emit ('Hate', 'Sexual', 'Violence', 'SelfHarm',
         'Unknown', 'N/A') - 'Unknown' is expected and healthy (README.md Section 11 VERIFY), not
         itself a failure.
       - CreationDate values parse as valid timestamps and are monotonically non-decreasing after
         the deploy script's own Sort-Object.

    2. MANUAL (printed as a checklist, never fails the script) - the policy's existence, scope,
       classifiers, reviewers, privacy settings, and - the check unique to this scenario - whether
       the Self-harm duty-of-care escalation contact and runbook acknowledgment are actually
       confirmed, none of which have a documented read API (design.md Section 3).

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all for category 1.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-ContentSafetyAuditTrail.ps1.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - see
    design.md Section 3 for why no such call exists). Defaults to the name used throughout this
    scenario's docs and deploy/policy/content-safety-policy-manifest.json.

.EXAMPLE
    ./Test-ContentSafetyAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/content-safety-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy the first time this scenario is deployed in a
    quiet tenant, or immediately after deployment before the ~1 hour policy-activation window
    (README.md Section 11) has elapsed - it does not mean the deploy script is broken.

    A high proportion of 'Unknown' ContentSafetyContext values on PolicyMatch rows is expected until
    the underlying AuditData shape is independently confirmed against a real tenant (README.md
    Section 11 VERIFY) - this script deliberately treats it as informational, not a failure.

    THIS SCRIPT CANNOT VERIFY THE DUTY-OF-CARE RUNBOOK IS ACTUALLY STAFFED - that is a human,
    process-level fact with no technical signal this script (or Communication Compliance itself)
    can observe. The manual checklist below asks the operator to confirm it explicitly every run
    as a recurring nudge, not a one-time gate.

    Sources: see deploy/Export-ContentSafetyAuditTrail.ps1 .NOTES for the Microsoft Learn references
    this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter()]
    [string]$PolicyName = 'Teams and Viva Engage Content Safety Detection - All Users'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "=== AUTOMATED CHECKS: $AuditTrailCsvPath ===" -ForegroundColor Cyan

Test-Check -Description "File exists at -AuditTrailCsvPath" -Condition (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)
if (-not (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)) {
    Write-Host "`nCannot continue - file not found. Run deploy/Export-ContentSafetyAuditTrail.ps1 first." -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -Path $AuditTrailCsvPath)

$requiredColumns = 'CreationDate', 'Category', 'Operation', 'UserIds', 'RecordType', 'ContentSafetyContext', 'SeverityHint', 'AuditData', 'CompositeKey'
$actualColumns = if ($rows.Count -gt 0) {
    (Import-Csv -Path $AuditTrailCsvPath | Select-Object -First 1).PSObject.Properties.Name
} else {
    (Get-Content -Path $AuditTrailCsvPath -TotalCount 1) -split ','
}
foreach ($column in $requiredColumns) {
    Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
}

if ($rows.Count -eq 0) {
    Write-Host "  [PASS] File contains a header with no data rows - healthy if no policy matches, policy changes, or review-tag actions occurred in the queried window(s) so far." -ForegroundColor Green
}
else {
    $duplicateKeys = $rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }
    Test-Check -Description "No duplicate CompositeKey rows (de-duplication merge is holding)" -Condition ($duplicateKeys.Count -eq 0)
    if ($duplicateKeys.Count -gt 0) {
        Write-Host "         Duplicate keys: $($duplicateKeys.Name -join '; ')" -ForegroundColor Yellow
    }

    $validCategories = 'PolicyMatch', 'PolicyUpdate', 'ReviewTag'
    $invalidCategoryRows = $rows | Where-Object { $_.Category -notin $validCategories }
    Test-Check -Description "Every row's Category is one of the 3 documented query categories" -Condition ($invalidCategoryRows.Count -eq 0)

    $validOperations = 'SupervisionRuleMatch', 'SupervisionPolicyCreated', 'SupervisionPolicyUpdated', 'SupervisionPolicyDeleted', 'SupervisoryReviewTag'
    $invalidOperationRows = $rows | Where-Object { $_.Operation -notin $validOperations }
    Test-Check -Description "Every row's Operation is one of the 5 documented Communication Compliance operations" -Condition ($invalidOperationRows.Count -eq 0)
    if ($invalidOperationRows.Count -gt 0) {
        Write-Host "         Unexpected operation value(s): $(($invalidOperationRows.Operation | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
    }

    $validContexts = 'Hate', 'Sexual', 'Violence', 'SelfHarm', 'Unknown', 'N/A'
    $invalidContextRows = $rows | Where-Object { $_.ContentSafetyContext -notin $validContexts }
    Test-Check -Description "Every row's ContentSafetyContext is one of the 6 labels this script's parser can emit" -Condition ($invalidContextRows.Count -eq 0)

    $unknownContextCount = @($rows | Where-Object { $_.ContentSafetyContext -eq 'Unknown' }).Count
    if ($unknownContextCount -gt 0) {
        Write-Host "  [WARN] $unknownContextCount PolicyMatch row(s) have an 'Unknown' ContentSafetyContext - expected until the AuditData shape is confirmed against a real tenant (README.md Section 11 VERIFY), not itself a failure." -ForegroundColor Yellow
    }

    $parsedDates = foreach ($row in $rows) {
        $parsed = $null
        $ok = [datetime]::TryParse($row.CreationDate, [ref]$parsed)
        [pscustomobject]@{ Raw = $row.CreationDate; Parsed = $parsed; Ok = $ok }
    }
    Test-Check -Description "Every CreationDate value parses as a valid timestamp" -Condition (($parsedDates | Where-Object { -not $_.Ok }).Count -eq 0)

    $sortedCheck = $true
    for ($i = 1; $i -lt $parsedDates.Count; $i++) {
        if ($parsedDates[$i].Parsed -lt $parsedDates[$i - 1].Parsed) { $sortedCheck = $false; break }
    }
    Test-Check -Description "CreationDate values are non-decreasing (file wasn't reordered/corrupted after the deploy script's own sort)" -Condition $sortedCheck

    $policyUpdateCount = @($rows | Where-Object { $_.Category -eq 'PolicyUpdate' }).Count
    if ($policyUpdateCount -gt 0) {
        Write-Host "  [WARN] $policyUpdateCount policy-change event(s) present in this file - review each per README.md Section 8, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }

    $selfHarmCount = @($rows | Where-Object { $_.ContentSafetyContext -eq 'SelfHarm' }).Count
    if ($selfHarmCount -gt 0) {
        Write-Host "  [WARN] *** $selfHarmCount possible Self-harm classifier match(es) present in this file. *** Confirm the README.md Section 8 duty-of-care escalation runbook was followed at the time each underlying alert was generated - do not treat discovering it in this file as the first response." -ForegroundColor Red
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no read API exists to automate these - design.md Section 3) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Communication Compliance > Policies: a policy named '$PolicyName' exists, status Active (not Paused/Error), created from the 'Detect inappropriate content' template."
    "Policy's locations are scoped to Microsoft Teams and Viva Engage only (not Exchange, which this classifier family doesn't support), matching deploy/policy/content-safety-policy-manifest.json."
    "Policy's conditions are the unmodified template defaults: Hate, Violence, Sexual, and Self-harm classifiers - no custom keyword dictionary was added."
    "Policy's Reviewers list matches deploy/policy/content-safety-policy-manifest.json's reviewers.placeholderMembers (replaced with the tenant's actual HR/Legal stakeholders) - ideally the SAME team already reviewing harassment-and-code-of-conduct, per design.md Section 5."
    "Settings > Roles and groups > Role groups: reviewers are members of Communication Compliance Investigators (full content access), not left only in Communication Compliance Analysts (metadata-only)."
    "Settings > Communication Compliance > Privacy tab: 'Show anonymized versions of usernames' is enabled (tenant-wide - may already be on from another policy)."
    "*** THE SELF-HARM DUTY-OF-CARE ESCALATION CONTACT IS NAMED, REACHABLE, AND HAS ACKNOWLEDGED THE README.md SECTION 8 RUNBOOK. *** This is this scenario's central go-live precondition (design.md Section 6) - Communication Compliance has no technical control that enforces this; confirm it explicitly, every run, not just once at deployment."
    "The full HR/Legal reviewer pool has completed the README.md Section 7 tabletop drill within the last quarter (README.md Section 8 recommends a quarterly cadence, not a one-time drill)."
    "Policies page: the policy's storage-limit indicator is not approaching 80/90/95% of the 100 GB / 1,000,000-message per-policy limit - a policy that silently auto-deactivates at the limit stops generating alerts with no in-band warning, and the consequence here includes losing self-harm-risk detection coverage."
    "If this file shows 0 policy-update events but the policy's configuration looks different from deploy/policy/content-safety-policy-manifest.json: the audit window may predate the change, or Audit (Standard)'s 180-day retention has already expired it - do not assume 'no events in this file' means 'no changes ever happened.'"
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```