---
part: "validate"
parent: "insider-risk/data-leaks-exfiltration-activity-trigger"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataLeaksExfiltrationActivityTriggerSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Data Leaks (exfiltration-activity trigger) scenario and
    prints a manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId), and - if -GroupId is supplied -
       the resulting enabled-user count is checked against -MaxUsers (defaults to 15,000, the base
       'Data leaks' template's own Microsoft-documented cap - the SAME per-template cap the
       ../../data-leaks/ DLP-trigger sibling scenario uses, since this is the same policy template
       with a different triggering event, not a different template).

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (which built-in indicators are turned on tenant-wide, the trigger-indicator selection and
       threshold mode, the SEPARATE scoring-indicator selection and threshold mode, IRM policy
       existence/template/scope, role groups) that has no Graph/PowerShell read API to verify
       programmatically as of this writing.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls. Unlike ../../data-leaks/validate/Test-DataLeaksIrmSetup.ps1, this script has
    no DLP-policy-readiness dependency to reference - this trigger path uses no DLP policy at all.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated scope-sizing check - the same
    source group(s) used by
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1. If
    omitted, that check is skipped (with a message, not a failure) and only the Graph-session
    check runs.

.PARAMETER MaxUsers
    The template's actively-scored-user cap to check the resolved count against. Defaults to
    15,000 - the base 'Data leaks' template's own row in Microsoft's "Limits in Insider Risk
    Management" table (README.md §12 ref 4). This cap is cumulative across every policy built from
    this exact template tenant-wide - INCLUDING the DLP-trigger sibling scenario, if both are
    deployed in the same tenant - so override this value if another Data-leaks-template policy
    already consumes part of it.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.PARAMETER CustomThresholdsUsed
    Set if this deployment uses custom (not default) thresholds for the trigger indicators - adds
    a reminder to confirm the recorded values in deploy/policy/
    data-leaks-exfiltration-activity-trigger-policy-manifest.json match what was actually entered
    in the portal. Omit if using Microsoft's default thresholds (whose exact values are unpublished
    - README.md §11).

.PARAMETER CloudIndicatorsEnabled
    Set if this deployment enabled the optional cloud storage/cloud service scoring indicator
    category - adds the corresponding Defender for Cloud Apps connector-health item to the manual
    checklist. Omit (default) to skip that item entirely rather than print a checklist entry for a
    feature this deployment doesn't use.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DataLeaksExfiltrationActivityTriggerSetup.ps1 -GroupId $ScopeGroupId -CustomThresholdsUsed

    Checks the resolved scope against the default 15,000-user cap and reminds the operator to
    confirm the recorded custom threshold values.

.EXAMPLE
    ./Test-DataLeaksExfiltrationActivityTriggerSetup.ps1 -GroupId $ScopeGroupId -MaxUsers 10000

    Overrides the default to check against a reduced cap, e.g. because the DLP-trigger sibling
    scenario's own policy already consumes part of the shared 15,000-user limit.

.NOTES
    Limits in Insider Risk Management - "Maximum number of users in scope for a policy template":
    Data leaks = 15,000 (confirmed via a direct Microsoft Learn fetch, reused from
    ../../data-leaks/README.md §12 ref 4) -
    https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template.
    See ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1
    .NOTES for the remaining Graph API references this script's automated check relies on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxUsers = 15000,

    [Parameter()]
    [string]$PolicyName = 'Data Leaks - Exfiltration Activity Trigger',

    [Parameter()]
    [switch]$CustomThresholdsUsed,

    [Parameter()]
    [switch]$CloudIndicatorsEnabled
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

$graphContext = Get-MgContext
Test-Check -Description 'Microsoft Graph session is active' -Condition ($null -ne $graphContext)

if ($graphContext -and $GroupId) {
    try {
        $enabledCount = 0
        foreach ($gid in $GroupId) {
            $members = Get-MgGroupTransitiveMemberAsUser -GroupId $gid `
                -Property 'id,accountEnabled' -ConsistencyLevel eventual -All
            $enabledCount += @($members | Where-Object { $_.AccountEnabled -eq $true }).Count
        }
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds against $($GroupId.Count) supplied group(s) (permission is actually granted, not just requested)" -Condition $true

        Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the $MaxUsers-user cap - NOTE: shared cumulatively with the DLP-trigger sibling scenario and every other policy built from this exact template" `
            -Condition ($enabledCount -le $MaxUsers) -Warn
    }
    catch {
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}
elseif ($graphContext) {
    Write-Host "  [SKIP] No -GroupId supplied - scope-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Insider Risk Management > Settings > Policy indicators > Built-in Indicators: every indicator intended as a TRIGGER and/or a SCORING indicator for this policy is turned on tenant-wide - an indicator not enabled here cannot be selected in the policy workflow (README.md §5 Step 2)."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the base 'Data leaks' template (NOT 'Data leaks by risky users' or 'Data leaks by priority users' - all three share overlapping naming in the template picker), and is in an active (not draft/disabled) state."
    "Policy's Triggers page has 'User performs an exfiltration activity' selected (NOT 'User matches a data loss prevention (DLP) policy' - confirm this deployment didn't accidentally pick the sibling scenario's trigger), with the intended trigger indicator(s) selected."
    "Trigger threshold mode matches deploy/policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json's triggeringEvent.triggerIndicators.thresholdMode - default, custom, or anomalous-activity per indicator."
    $(if ($CustomThresholdsUsed) { "CUSTOM TRIGGER THRESHOLDS: the specific low/medium/high (or anomalous-activity) values actually entered in the portal match the values recorded in the manifest's triggeringEvent.triggerIndicators.customThresholdValues - there is no read API to diff this automatically." })
    "Policy's Indicators page (a SEPARATE page/decision from the Triggers page above - design.md §2 goal 2/§5) has 'Office indicators' selected AND 'Cumulative exfiltration detection' selected (default-on for this template - confirm it wasn't inadvertently deselected)."
    "Scoring-indicator threshold mode (the 'Decide whether to use default or custom indicator thresholds' page) matches the manifest's scoringIndicators.thresholdMode - confirm this was set independently and wasn't assumed to match the trigger's own threshold mode."
    "If optional Communication Compliance content indicators, generative-AI indicators, or cloud indicators are intended as SCORING indicators, confirm they are selected on the Indicators page - none is selected by default."
    $(if ($CloudIndicatorsEnabled) { "Microsoft Defender portal > Settings > Cloud Apps > App Connectors: the Box/Dropbox/Google Drive/Amazon S3/Azure connector(s) this policy's cloud indicators depend on show status 'Connected', and pay-as-you-go billing remains enabled in Purview billing." })
    "If real-time analytics (preview) threshold recommendations were used: confirm this policy is scoped to 'Include all users and groups' (required for that feature) rather than the narrower group this script's -GroupId check assumes - if so, the automated scope-count check above does not apply to this deployment."
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm the actively-scored count against the 15,000-user cap for this template (shared cumulatively with the ../../data-leaks/ DLP-trigger sibling scenario, if also deployed) - no API exists to check this automatically."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins' (docs/rbac-model.md §4)."
    "If the DLP-trigger sibling scenario (../../data-leaks/) is ALSO deployed in this tenant: confirm the two policies use distinct names and, pending README.md §11's open combinability question, are not assumed to share or merge trigger behavior."
    "Deployed configuration matches deploy/policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
) | Where-Object { $_ }
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```