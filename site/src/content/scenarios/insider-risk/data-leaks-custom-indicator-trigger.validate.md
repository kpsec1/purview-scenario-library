---
part: "validate"
parent: "insider-risk/data-leaks-custom-indicator-trigger"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataLeaksCustomIndicatorTriggerSetup.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the scriptable parts of the Data Leaks (custom-indicator / third-party-connector
    trigger) scenario and prints a manual-verification checklist for the parts that have no API
    surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - re-runs
       deploy/Send-InsiderRiskIndicatorRecord.ps1's own CSV validation logic (schema, ISO 8601
       event-time parsing, threshold numeric-parsing, source-column value matching, duplicate
       UserColumn+EventTimeColumn detection) against a candidate CSV WITHOUT uploading anything, so
       an operator can check a file before scheduling it. If -GroupId is supplied, also checks a
       Microsoft Graph session and the resolved scope-candidate count against -MaxUsers, the same
       automated check both sibling scenarios' validation scripts already perform.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (connector creation, custom indicator creation and mapping, the policy's trigger/scoring
       selection and MANDATORY custom threshold, the 24-hour sync wait, the webhook firewall
       allowlist, role assignment, and connector log verification) that has no Graph/PowerShell
       read API to verify programmatically as of this writing.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls and uploads nothing.

.PARAMETER CsvPath
    Optional. Path to a candidate indicator-data CSV to validate (same file you'd pass to
    deploy/Send-InsiderRiskIndicatorRecord.ps1 -CsvPath). If omitted, the CSV-validation checks are
    skipped (with a message, not a failure).

.PARAMETER UserColumn
    Matches deploy/Send-InsiderRiskIndicatorRecord.ps1 -UserColumn. Defaults to 'UserPrincipalName'.

.PARAMETER EventTimeColumn
    Matches deploy/Send-InsiderRiskIndicatorRecord.ps1 -EventTimeColumn. Defaults to 'EventTime'.

.PARAMETER ThresholdColumn
    Matches deploy/Send-InsiderRiskIndicatorRecord.ps1 -ThresholdColumn. Optional.

.PARAMETER SourceColumn
    Matches deploy/Send-InsiderRiskIndicatorRecord.ps1 -SourceColumn. Optional; requires
    -RelatedValues.

.PARAMETER RelatedValues
    Matches deploy/Send-InsiderRiskIndicatorRecord.ps1 -RelatedValues. Required if -SourceColumn is
    specified.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated scope-sizing check - the same source
    group(s) used by ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1.
    If omitted, that check is skipped (with a message, not a failure).

.PARAMETER MaxUsers
    The template's actively-scored-user cap to check the resolved count against. Defaults to 15,000
    - the base 'Data leaks' template's own row in Microsoft's "Limits in Insider Risk Management"
    table. This cap is now shared cumulatively across THREE sibling scenarios if all are deployed in
    the same tenant (this one, ../../data-leaks/, and ../../data-leaks-exfiltration-activity-trigger/)
    - override this value accordingly.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only. Defaults to the name used throughout
    this scenario's docs.

.EXAMPLE
    ./Test-DataLeaksCustomIndicatorTriggerSetup.ps1 -CsvPath './third_party_alerts.csv' `
        -UserColumn 'User_Principal_Name' -EventTimeColumn 'Aggregation_Date' `
        -ThresholdColumn 'Alert_Count' -SourceColumn 'Source_Workload' -RelatedValues 'Salesforce','Dropbox'

    Validates a candidate CSV without uploading it, and prints the manual portal checklist.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DataLeaksCustomIndicatorTriggerSetup.ps1 -GroupId $ScopeGroupId

    Checks the resolved scope against the default 15,000-user cap; skips CSV validation.

.NOTES
    See deploy/Send-InsiderRiskIndicatorRecord.ps1 .NOTES for the full grounding citations this
    script's CSV-validation logic relies on (import-insider-risk-indicators,
    insider-risk-management-settings-policy-indicators#custom-indicators, and the direct GitHub fetch
    confirming the shared ingestion webhook mechanics). See
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 .NOTES for
    the Graph API references the scope-sizing check relies on. Also run
    ../../departing-employee-data-theft/validate/Test-HrConnectorAppRegistration.ps1 -DisplayName
    '<this connector's app>' separately (reused unmodified) to validate the Entra app registration's
    hygiene - not duplicated here.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [string]$UserColumn = 'UserPrincipalName',

    [Parameter()]
    [string]$EventTimeColumn = 'EventTime',

    [Parameter()]
    [string]$ThresholdColumn,

    [Parameter()]
    [string]$SourceColumn,

    [Parameter()]
    [string[]]$RelatedValues,

    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxUsers = 15000,

    [Parameter()]
    [string]$PolicyName = 'Data Leaks - Custom Indicator (Third-Party Connector) Trigger'
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

Write-Host "=== AUTOMATED CHECKS ===" -ForegroundColor Cyan

if ($SourceColumn -and -not $RelatedValues) {
    Test-Check -Description '-SourceColumn was specified without -RelatedValues (both required together)' -Condition $false
}

if ($CsvPath) {
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        Test-Check -Description "CsvPath '$CsvPath' exists" -Condition $false
    }
    else {
        $rows = Import-Csv -LiteralPath $CsvPath
        Test-Check -Description "CsvPath '$CsvPath' contains at least one data row (found $($rows.Count))" -Condition ($rows.Count -gt 0)

        if ($rows.Count -gt 0) {
            $actualColumns = $rows[0].PSObject.Properties.Name
            $requiredColumns = @($UserColumn, $EventTimeColumn)
            if ($ThresholdColumn) { $requiredColumns += $ThresholdColumn }
            if ($SourceColumn) { $requiredColumns += $SourceColumn }
            $missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns } | Select-Object -Unique
            Test-Check -Description "Required column(s) present: $($requiredColumns -join ', ')" -Condition (-not $missingColumns)

            if (-not $missingColumns) {
                $badUser = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.$UserColumn) }).Count
                Test-Check -Description "'$UserColumn' is non-empty in every row (found $badUser empty)" -Condition ($badUser -eq 0)

                $badTime = 0
                foreach ($row in $rows) {
                    $parsedTime = [datetimeoffset]::MinValue
                    if (-not [datetimeoffset]::TryParse($row.$EventTimeColumn, [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedTime)) {
                        $badTime++
                    }
                }
                Test-Check -Description "'$EventTimeColumn' parses as ISO 8601 in every row (found $badTime unparseable)" -Condition ($badTime -eq 0)

                if ($ThresholdColumn) {
                    $badNumber = 0
                    foreach ($row in $rows) {
                        $parsedNumber = 0.0
                        if (-not [double]::TryParse($row.$ThresholdColumn, [System.Globalization.NumberStyles]::Number,
                                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedNumber)) {
                            $badNumber++
                        }
                    }
                    Test-Check -Description "'$ThresholdColumn' is numeric in every row (found $badNumber non-numeric)" -Condition ($badNumber -eq 0)
                }

                if ($SourceColumn -and $RelatedValues) {
                    $badSource = @($rows | Where-Object { $_.$SourceColumn -cnotin $RelatedValues }).Count
                    Test-Check -Description "'$SourceColumn' values all match -RelatedValues ($($RelatedValues -join ', ')) exactly (found $badSource mismatch(es))" -Condition ($badSource -eq 0)
                }

                $duplicateGroups = $rows | Group-Object -Property { "$($_.$UserColumn)|$($_.$EventTimeColumn)" } |
                    Where-Object { $_.Count -gt 1 }
                Test-Check -Description "No duplicate ($UserColumn, $EventTimeColumn) combinations (found $($duplicateGroups.Count) duplicate group(s)) - Microsoft silently drops these on ingestion" `
                    -Condition (-not $duplicateGroups) -Warn
            }
        }
    }
}
else {
    Write-Host "  [SKIP] No -CsvPath supplied - CSV validation not run." -ForegroundColor Yellow
}

$graphContext = Get-MgContext
if ($GroupId) {
    Test-Check -Description 'Microsoft Graph session is active' -Condition ($null -ne $graphContext)
    if ($graphContext) {
        try {
            $enabledCount = 0
            foreach ($gid in $GroupId) {
                $members = Get-MgGroupTransitiveMemberAsUser -GroupId $gid `
                    -Property 'id,accountEnabled' -ConsistencyLevel eventual -All
                $enabledCount += @($members | Where-Object { $_.AccountEnabled -eq $true }).Count
            }
            Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds against $($GroupId.Count) supplied group(s)" -Condition $true
            Test-Check -Description "Combined enabled-member count ($enabledCount) is within the $MaxUsers-user cap - NOTE: shared cumulatively with BOTH Data-leaks-template sibling scenarios" `
                -Condition ($enabledCount -le $MaxUsers) -Warn
        }
        catch {
            Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
        }
    }
}
else {
    Write-Host "  [SKIP] No -GroupId supplied - scope-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Settings > Data connectors > My connectors: the Insider Risk Indicators (preview) connector exists, its Authentication page's app ID matches the Entra app ../../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1 created, and its Sample file/Data mapping configuration matches deploy/policy/data-leaks-custom-indicator-trigger-policy-manifest.json."
    "The operator who created the connector held the Data Connector Admin role (docs/rbac-model.md §4/§11) at creation time."
    "Purview portal > Settings > Data connectors > (this connector) > Download log: the most recent run's RecordsSaved count matches the row count of the CSV actually uploaded."
    "Insider Risk Management > Settings > Policy indicators > Custom Indicators tab: one custom indicator exists per manifest customIndicators[] entry, each pointed at this connector, with the correct Source column value and threshold-field mapping (or the 'Use only as a triggering event without any thresholds' option, if that was chosen instead)."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the base 'Data leaks' template (not a sibling Data-leaks-family template), and is in an active (not draft/disabled) state."
    "Policy's Triggers page has the intended custom indicator(s) selected, each with a CUSTOM threshold set (not left as a default - Microsoft provides no recommended/default threshold for a custom indicator) and NOT using the 'Use only as a triggering event without any thresholds' option unless that was the deliberate choice."
    "Policy's Indicators page (a SEPARATE page/decision from Triggers) has 'Office indicators' and 'Cumulative exfiltration detection' selected, and - if the manifest's customIndicatorsAlsoUsedForScoring lists any - those same custom indicators also selected here with their own independently-configured custom threshold."
    "At least 24 hours elapsed between the last custom indicator/policy configuration change and the first (or most recent post-change) run of deploy/Send-InsiderRiskIndicatorRecord.ps1 - Microsoft: uploading while updates are syncing can leave some data unscored."
    "webhook.ingestion.office.com is allowlisted on the firewall of whatever host runs deploy/Send-InsiderRiskIndicatorRecord.ps1 on a schedule."
    "If deploy/Send-InsiderRiskIndicatorRecord.ps1 is scheduled to run automatically (recommended - same Windows Task Scheduler pattern as the HR-connector sibling, README.md §8): confirm the schedule exists and its last run succeeded, since a failed scheduled upload produces no native Microsoft alert."
    "If EITHER sibling Data-leaks-template scenario (../../data-leaks/ or ../../data-leaks-exfiltration-activity-trigger/) is ALSO deployed in this tenant: confirm all three use distinct policy names, and that the 15,000-user cap sizing accounts for all three (README.md §6/§10)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins' (docs/rbac-model.md §4)."
    "Deployed configuration matches deploy/policy/data-leaks-custom-indicator-trigger-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
) | Where-Object { $_ }
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```