---
part: "validate"
parent: "communication-compliance/copilot-interaction-detection"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CopilotInteractionAuditTrail.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV this scenario's deploy script produces, and prints a manual
    verification checklist for the policy itself, which has no read API to check programmatically.

.DESCRIPTION
    Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - read-only, no tenant connection
       needed:
       - The CSV has the expected columns and at least the header (an empty file with zero data
         rows is not itself a failure - it means no matching audit events occurred in every
         window run so far, which is the expected common case immediately after deployment).
       - No duplicate CompositeKey rows - proof the deploy script's merge-and-de-duplicate design
         (design.md Section 7) is actually holding across re-runs.
       - Every row's Category value is one of the three documented query categories, and every
         row's Operation value is one of the five documented Communication Compliance operations
         (design.md Section 7) - catches a scenario where the CSV was hand-edited or produced by a
         different script by mistake.
       - Every row's CopilotContext value is one of the four documented labels this script's
         Get-CopilotContextLabel function can emit ('PromptShields-PromptMatch',
         'ProtectedMaterial-ResponseMatch', 'Unknown', 'N/A') - 'Unknown' is expected and healthy
         (README.md Section 11 VERIFY), not itself a failure.
       - CreationDate values parse as valid timestamps and are monotonically non-decreasing after
         the deploy script's own Sort-Object.

    2. MANUAL (printed as a checklist, never fails the script) - the policy's existence, scope,
       classifiers, reviewers, and privacy settings, none of which have a documented read API
       (design.md Section 3). This is not a gap in this script - it is Communication Compliance's
       current product surface.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and needs no tenant connection at all for category 1.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-CopilotInteractionAuditTrail.ps1.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - see
    design.md Section 3 for why no such call exists). Defaults to the name used throughout this
    scenario's docs and deploy/policy/copilot-interaction-policy-manifest.json.

.EXAMPLE
    ./Test-CopilotInteractionAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/copilot-interaction-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy the first time this scenario is deployed in a
    quiet tenant, or immediately after deployment before the ~1 hour policy-activation window
    (README.md Section 11) has elapsed - it does not mean the deploy script is broken.

    A high proportion of 'Unknown' CopilotContext values on PolicyMatch rows is expected until the
    underlying AuditData shape is independently confirmed against a real tenant (README.md Section
    11 VERIFY) - this script deliberately treats it as informational, not a failure.

    Sources: see deploy/Export-CopilotInteractionAuditTrail.ps1 .NOTES for the Microsoft Learn
    references this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter()]
    [string]$PolicyName = 'Microsoft 365 Copilot Interaction Detection - All Users'
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
    Write-Host "`nCannot continue - file not found. Run deploy/Export-CopilotInteractionAuditTrail.ps1 first." -ForegroundColor Red
    exit 1
}

$rows = @(Import-Csv -Path $AuditTrailCsvPath)

$requiredColumns = 'CreationDate', 'Category', 'Operation', 'UserIds', 'RecordType', 'CopilotContext', 'AuditData', 'CompositeKey'
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

    $validCopilotContexts = 'PromptShields-PromptMatch', 'ProtectedMaterial-ResponseMatch', 'Unknown', 'N/A'
    $invalidContextRows = $rows | Where-Object { $_.CopilotContext -notin $validCopilotContexts }
    Test-Check -Description "Every row's CopilotContext is one of the 4 labels this script's parser can emit" -Condition ($invalidContextRows.Count -eq 0)

    $unknownContextCount = @($rows | Where-Object { $_.CopilotContext -eq 'Unknown' }).Count
    if ($unknownContextCount -gt 0) {
        Write-Host "  [WARN] $unknownContextCount PolicyMatch row(s) have an 'Unknown' CopilotContext - expected until the AuditData shape is confirmed against a real tenant (README.md Section 11 VERIFY), not itself a failure." -ForegroundColor Yellow
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
        Write-Host "  [WARN] $policyUpdateCount policy-change event(s) present in this file - review each per README.md Section 8 incident-response guidance, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }

    $promptShieldsCount = @($rows | Where-Object { $_.CopilotContext -eq 'PromptShields-PromptMatch' }).Count
    if ($promptShieldsCount -gt 0) {
        Write-Host "  [WARN] $promptShieldsCount possible Prompt Shields (jailbreak-attempt) match(es) present in this file - route to Security triage per README.md Section 8, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no read API exists to automate these - design.md Section 3) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Communication Compliance > Policies: a policy named '$PolicyName' exists, status Active (not Paused/Error), created from the 'Detect Microsoft 365 Copilot and Microsoft 365 Copilot Chat interactions' template."
    "Policy's location is scoped to Microsoft 365 Copilot and Microsoft 365 Copilot Chat only (not also Enterprise AI apps / Other AI apps, which require PAYG billing - README.md Section 3/10), matching deploy/policy/copilot-interaction-policy-manifest.json."
    "Policy's conditions are the unmodified template defaults: Prompt Shields and Protected material classifiers - no custom keyword dictionary was added (this scenario deliberately does not need one, unlike harassment-and-code-of-conduct)."
    "Policy's Reviewers list matches deploy/policy/copilot-interaction-policy-manifest.json's reviewers.placeholderMembers (replaced with the tenant's actual Security/Responsible-AI/Legal stakeholders) - not left at any default."
    "Settings > Roles and groups > Role groups: reviewers are members of Communication Compliance Investigators (full content access), not left only in Communication Compliance Analysts (metadata-only) - see README.md Section 3."
    "Settings > Communication Compliance > Privacy tab: 'Show anonymized versions of usernames' is enabled, per deploy/policy/copilot-interaction-policy-manifest.json's privacySettings (tenant-wide - may already be on from another policy)."
    "Policies page: the policy's storage-limit indicator is not approaching 80/90/95% of the 100 GB / 1,000,000-message per-policy limit (README.md Section 8/11) - a policy that silently auto-deactivates at the limit stops generating alerts with no in-band warning to anyone outside the Communication Compliance/Communication Compliance Admins role groups."
    "If this file shows 0 policy-update events but the policy's configuration looks different from deploy/policy/copilot-interaction-policy-manifest.json: the audit window may predate the change, or Audit (Standard)'s 180-day retention has already expired it (README.md Section 11) - do not assume 'no events in this file' means 'no changes ever happened.'"
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```