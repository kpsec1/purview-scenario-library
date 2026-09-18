---
part: "validate"
parent: "compliance-manager/soc2-assessment"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-ComplianceManagerAuditTrail.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the audit-trail CSV this scenario's (reused) deploy script produces, structurally
    validates this scenario's own control-crosswalk manifest, and prints a manual verification
    checklist for the assessment itself, which has no read API to check programmatically.

.DESCRIPTION
    Three categories of check, clearly separated in the output:

    1. AUTOMATED - AUDIT TRAIL (hard pass/fail, contributes to exit code) - read-only, no tenant
       connection needed. Identical checks to scenarios/compliance-manager/assess-against-
       iso27001/validate/Test-ComplianceManagerAuditTrail.ps1 and scenarios/compliance-manager/
       pci-dss-assessment/validate/Test-ComplianceManagerAuditTrail.ps1, because the CSV shape and
       the operations it monitors are identical - the underlying script is reused, not reinvented
       (see ../design.md Section 2):
       - The CSV has the expected columns.
       - No duplicate CompositeKey rows.
       - Every row's Operation value is one of the three documented Compliance Manager operations.
       - CreationDate values parse as valid timestamps and are monotonically non-decreasing.

    2. AUTOMATED - CROSSWALK MANIFEST (hard pass/fail, contributes to exit code) - THIS scenario's
       own addition, structured differently from its PCI DSS sibling because SOC 2 is organized by
       Trust Services Criteria (TSC) category, not numbered goals: structurally validates
       deploy/policy/soc2-assessment-manifest.json's controlCrosswalk array (all 5 AICPA 2017 TSC
       categories present exactly once, each with an aicpaCode and a coverage string, and the
       mandatory Security category flagged as such) and confirms every scenario path referenced
       anywhere in the manifest (recommendedDeploymentOrder and controlCrosswalk.coverage) that
       looks like a scenarios/... path actually exists in this repository - catching a stale
       cross-link before a buyer follows it into a 404.

    3. MANUAL (printed as a checklist, never fails the script) - the assessment's existence, scope,
       group, and role assignments, none of which have a documented read API (design.md Section 2).

    Exits non-zero only if an AUTOMATED check (category 1 or 2) hard-fails. Safe to re-run any
    number of times; makes no mutating calls and needs no tenant connection at all.

.PARAMETER AuditTrailCsvPath
    Path to the CSV produced by deploy/Export-ComplianceManagerAuditTrail.ps1 (or one of the reused
    copies in scenarios/compliance-manager/assess-against-iso27001/deploy/ or scenarios/compliance-
    manager/pci-dss-assessment/deploy/, if that's the one actually run - see design.md Section 2).

.PARAMETER CrosswalkManifestPath
    Path to deploy/policy/soc2-assessment-manifest.json. Defaults to the sibling copy in this
    scenario's own deploy/policy/ folder.

.PARAMETER RepoRoot
    Path to the repository root, used to resolve and confirm scenarios/... paths referenced inside
    the crosswalk manifest actually exist on disk. Defaults to three levels up from this script's
    location (validate/ -> soc2-assessment/ -> compliance-manager/ -> scenarios/ -> repo root),
    matching this repository's own scenario folder depth.

.PARAMETER AssessmentName
    Display name used for the manual-checklist output only (no API call is made against it - see
    design.md Section 2 for why no such call exists). Defaults to the name used throughout this
    scenario's docs and deploy/policy/soc2-assessment-manifest.json.

.EXAMPLE
    ./Test-ComplianceManagerAuditTrail.ps1 -AuditTrailCsvPath '../deploy/out/compliance-manager-audit-trail.csv'

.NOTES
    A CSV with zero data rows is expected and healthy the first time this scenario is deployed in a
    quiet tenant. Re-run deploy/Export-ComplianceManagerAuditTrail.ps1 with a wider -StartDate to
    confirm the query itself works if this is unexpected.

    Sources: see deploy/Export-ComplianceManagerAuditTrail.ps1 .NOTES for the Microsoft Learn
    references this scenario's grounding rests on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AuditTrailCsvPath,

    [Parameter()]
    [string]$CrosswalkManifestPath = (Join-Path $PSScriptRoot '../deploy/policy/soc2-assessment-manifest.json'),

    [Parameter()]
    [string]$RepoRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter()]
    [string]$AssessmentName = 'SOC 2 - Microsoft 365 Estate'
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

Write-Host "=== AUTOMATED CHECKS (1/2): audit trail - $AuditTrailCsvPath ===" -ForegroundColor Cyan

Test-Check -Description "File exists at -AuditTrailCsvPath" -Condition (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)
if (-not (Test-Path -Path $AuditTrailCsvPath -PathType Leaf)) {
    Write-Host "`nCannot continue audit-trail checks - file not found. Run deploy/Export-ComplianceManagerAuditTrail.ps1 first (or a reused copy in assess-against-iso27001/deploy/ or pci-dss-assessment/deploy/ - see design.md Section 2)." -ForegroundColor Red
}
else {
    $rows = @(Import-Csv -Path $AuditTrailCsvPath)

    $requiredColumns = 'CreationDate', 'Operation', 'UserIds', 'RecordType', 'AuditDataObjectId', 'AuditData', 'CompositeKey'
    $actualColumns = if ($rows.Count -gt 0) {
        (Import-Csv -Path $AuditTrailCsvPath | Select-Object -First 1).PSObject.Properties.Name
    } else {
        (Get-Content -Path $AuditTrailCsvPath -TotalCount 1) -split ','
    }
    foreach ($column in $requiredColumns) {
        Test-Check -Description "Column '$column' present" -Condition ($actualColumns -contains $column)
    }

    if ($rows.Count -eq 0) {
        Write-Host "  [PASS] File contains a header with no data rows - healthy if no Compliance Manager role/automation-level changes occurred in the queried window(s) so far." -ForegroundColor Green
    }
    else {
        $duplicateKeys = $rows | Group-Object CompositeKey | Where-Object { $_.Count -gt 1 }
        Test-Check -Description "No duplicate CompositeKey rows (de-duplication merge is holding)" -Condition ($duplicateKeys.Count -eq 0)
        if ($duplicateKeys.Count -gt 0) {
            Write-Host "         Duplicate keys: $($duplicateKeys.Name -join '; ')" -ForegroundColor Yellow
        }

        $validOperations = 'ComplianceManagerRolesChange', 'ComplianceManagerAutomationLevelChange', 'ComplianceManagerAutomationChange'
        $invalidOperationRows = $rows | Where-Object { $_.Operation -notin $validOperations }
        Test-Check -Description "Every row's Operation is one of the 3 documented Compliance Manager operations" -Condition ($invalidOperationRows.Count -eq 0)
        if ($invalidOperationRows.Count -gt 0) {
            Write-Host "         Unexpected operation value(s): $(($invalidOperationRows.Operation | Select-Object -Unique) -join ', ')" -ForegroundColor Yellow
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

        $automationChanges = @($rows | Where-Object { $_.Operation -match 'AutomationLevel|AutomationChange' })
        if ($automationChanges.Count -gt 0) {
            Write-Host "  [WARN] $($automationChanges.Count) automation-trust change event(s) present in this file - review each per README.md Section 8 incident-response guidance, do not treat their mere presence as a failure of this script." -ForegroundColor Yellow
        }
    }
}

Write-Host "`n=== AUTOMATED CHECKS (2/2): control crosswalk manifest - $CrosswalkManifestPath ===" -ForegroundColor Cyan

Test-Check -Description "Manifest file exists at -CrosswalkManifestPath" -Condition (Test-Path -Path $CrosswalkManifestPath -PathType Leaf)
if (-not (Test-Path -Path $CrosswalkManifestPath -PathType Leaf)) {
    Write-Host "`nCannot continue manifest checks - file not found." -ForegroundColor Red
}
else {
    $manifest = $null
    try {
        $manifest = Get-Content -Path $CrosswalkManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        Test-Check -Description "Manifest parses as valid JSON" -Condition $true
    }
    catch {
        Test-Check -Description "Manifest parses as valid JSON" -Condition $false
        Write-Host "         Parse error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($manifest) {
        Test-Check -Description "regulation is 'System and Organization Controls (SOC) 2' (not the SOC 1 sibling template - README.md Section 11)" -Condition ($manifest.regulation -eq 'System and Organization Controls (SOC) 2')

        $categories = @($manifest.controlCrosswalk.categories)
        $expectedCategories = 'Security', 'Availability', 'Processing Integrity', 'Confidentiality', 'Privacy'
        Test-Check -Description "controlCrosswalk.categories contains exactly 5 entries (the AICPA 2017 Trust Services Criteria categories)" -Condition ($categories.Count -eq 5)

        $categoryNames = @($categories | ForEach-Object { $_.category })
        $missingCategories = @($expectedCategories | Where-Object { $_ -notin $categoryNames })
        Test-Check -Description "All 5 TSC categories are present exactly once" -Condition (($missingCategories.Count -eq 0) -and ($categoryNames.Count -eq ($categoryNames | Select-Object -Unique).Count))
        if ($missingCategories.Count -gt 0) {
            Write-Host "         Missing categor(y/ies): $($missingCategories -join ', ')" -ForegroundColor Yellow
        }

        $incompleteCategories = @($categories | Where-Object { -not $_.category -or -not $_.aicpaCode -or -not $_.coverage })
        Test-Check -Description "Every category entry has a category name, an aicpaCode, and a coverage string" -Condition ($incompleteCategories.Count -eq 0)

        $securityCategory = $categories | Where-Object { $_.category -eq 'Security' } | Select-Object -First 1
        Test-Check -Description "The 'Security' category is flagged mandatory:true (it is the only TSC category present in every SOC 2 report)" -Condition ($null -ne $securityCategory -and $securityCategory.mandatory -eq $true)

        # Collect every scenarios/... path mentioned anywhere in the manifest (recommendedDeploymentOrder
        # entries and controlCrosswalk.coverage strings) and confirm each one resolves to a real
        # directory under the repo's scenarios/ tree - catches a stale cross-link before a buyer
        # follows it into a 404, per this script's own .DESCRIPTION.
        $scenarioPathPattern = 'scenarios/[a-z0-9\-]+/[a-z0-9\-]+/'
        $textToScan = @($manifest.recommendedDeploymentOrder) + @($categories | ForEach-Object { $_.coverage })
        $referencedPaths = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($text in $textToScan) {
            if (-not $text) { continue }
            foreach ($match in [regex]::Matches($text, $scenarioPathPattern)) {
                [void]$referencedPaths.Add($match.Value.TrimEnd('/'))
            }
        }

        $resolvedRepoRoot = (Resolve-Path -Path $RepoRoot -ErrorAction SilentlyContinue)
        if (-not $resolvedRepoRoot) {
            Test-Check -Description "Repo root resolves (-RepoRoot '$RepoRoot')" -Condition $false -Warn
            Write-Host "         Skipping scenario cross-link existence checks - pass -RepoRoot explicitly if this script was moved." -ForegroundColor Yellow
        }
        else {
            $missingPaths = [System.Collections.Generic.List[string]]::new()
            foreach ($relativePath in $referencedPaths) {
                $fullPath = Join-Path $resolvedRepoRoot.Path $relativePath
                if (-not (Test-Path -Path $fullPath -PathType Container)) {
                    $missingPaths.Add($relativePath)
                }
            }
            Test-Check -Description "All $($referencedPaths.Count) scenarios/... path(s) referenced in the manifest exist in the repo" -Condition ($missingPaths.Count -eq 0)
            if ($missingPaths.Count -gt 0) {
                Write-Host "         Missing/stale path(s): $($missingPaths -join '; ')" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no read API exists to automate these - design.md Section 2) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Compliance Manager > Assessments: an assessment named '$AssessmentName' exists, based on the 'System and Organization Controls (SOC) 2' regulation (NOT the separately-listed SOC 1 template - README.md Section 11), with status other than blank/None."
    "Assessment's Services tab shows Microsoft 365 in scope, matching deploy/policy/soc2-assessment-manifest.json's servicesInScope."
    "Assessment's group matches deploy/policy/soc2-assessment-manifest.json's group.name - if assess-against-iso27001 and/or pci-dss-assessment are also deployed, confirm this assessment was ADDED to that same group (design.md Section 6), not created in a separate one."
    "Compliance Manager > Settings > User access (or the assessment's own Manage user access pane): role assignments match deploy/policy/soc2-assessment-manifest.json's roleAssignments."
    "Compliance Manager > Improvement actions, filtered to this assessment: spot-check that at least some actions show a 'Passed'/tested status sourced from built-in automation, confirming already-deployed Information Protection/DLP/Adaptive Protection/Insider Risk/Audit scenarios (deploy/policy/soc2-assessment-manifest.json's recommendedDeploymentOrder) are actually feeding this assessment."
    "If the same nontechnical improvement action (e.g. a documented information security policy) appears in both this assessment and the ISO 27001 and/or PCI DSS assessments: confirm updating it in one is reflected in the others (design.md Section 6's group-sharing claim) - this is the concrete, checkable proof the group-placement decision is paying off."
    "Confirm with whoever owns this tenant's SOC 2 program that this assessment is being used as an internal readiness-tracking tool, and NOT presented anywhere as a substitute for an actual SOC 2 report (Type I or Type II) issued by an independent AICPA-accredited CPA firm - README.md Section 2/Section 11."
    "If a SOC 2 Type II audit period of performance is underway or planned: confirm the audit-trail CSV's collection window (README.md Section 8) covers the full period, since Audit (Standard)'s 180-day default retention is shorter than a typical 6-12 month Type II period - see deploy/Export-ComplianceManagerAuditTrail.ps1's .NOTES."
    "If this file shows 0 automation-trust-change events but Compliance Manager > Settings shows an unexpected automation level: the audit window may predate the change, or Audit (Standard)'s 180-day retention has already expired it (README.md Section 11) - do not assume 'no events in this file' means 'no changes ever happened.'"
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```