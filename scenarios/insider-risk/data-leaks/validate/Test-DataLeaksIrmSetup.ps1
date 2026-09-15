#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Data Leaks (base template) scenario and prints a
    manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId), and - if -GroupId and -MaxUsers
       are both supplied - the resulting enabled-user count is checked against the operator-
       confirmed cap. -MaxUsers has NO default: this template's specific cap could not be
       confirmed via this build's WebSearch-only grounding (design.md §2 goal 7) - if omitted,
       that one sub-check is skipped with an explicit message rather than silently reusing a
       different template's number.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (DLP-alerts indicator wiring, IRM policy existence/template/scope, indicator selection,
       the DLP-policy/IRM double-scoping cross-check, role groups) that has no Graph/PowerShell
       read API to verify programmatically as of this writing.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls. This script does NOT re-run the DLP-policy readiness checks - those live in
    ../deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 and should be run against Security & Compliance
    PowerShell separately; this script only covers the Graph-side scope check and the manual
    portal checklist.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated scope-sizing check - the same
    source group(s) used by
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1. If
    omitted, that check is skipped (with a message, not a failure) and only the Graph-session
    check runs.

.PARAMETER MaxUsers
    The template's actively-scored-user cap to check the resolved count against. NO DEFAULT -
    Microsoft's specific limit for the base 'Data leaks' template could not be confirmed via this
    build's WebSearch-only grounding (design.md §2 goal 7). Supply the number you confirmed from
    the live portal or a direct Microsoft Learn fetch; if omitted, the scope-sizing sub-check is
    skipped rather than silently checked against a wrong number.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.PARAMETER DlpTriggerConfigured
    Set if this deployment uses the DLP-policy triggering event (this scenario's primary,
    worked-example path) - adds the double-scoping cross-check reminder to the manual checklist.
    Omit if using only the exfiltration-activity triggering event instead.

.PARAMETER CloudIndicatorsEnabled
    Set if this deployment enabled the optional cloud storage/cloud service indicator category -
    adds the corresponding Defender for Cloud Apps connector-health item to the manual checklist.
    Omit (default) to skip that item entirely rather than print a checklist entry for a feature
    this deployment doesn't use.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DataLeaksIrmSetup.ps1 -GroupId $ScopeGroupId -MaxUsers 25000 -DlpTriggerConfigured

.NOTES
    Grounded in Microsoft Learn via WebSearch only in this build - see
    ../deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 .NOTES and
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1
    .NOTES for the Graph API references this script's automated check relies on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [Nullable[int]]$MaxUsers,

    [Parameter()]
    [string]$PolicyName = 'Data Leaks',

    [Parameter()]
    [switch]$DlpTriggerConfigured,

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

        if ($null -ne $MaxUsers) {
            Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the operator-confirmed $MaxUsers-user cap - NOTE: cumulative tenant-wide across every policy built from this exact template" `
                -Condition ($enabledCount -le $MaxUsers) -Warn
        }
        else {
            Write-Host "  [SKIP] -MaxUsers not supplied - this template's specific cap could not be confirmed via this build's WebSearch-only grounding (design.md §2 goal 7). Confirm the current limit from the portal or a direct Microsoft Learn fetch, then re-run with -MaxUsers to check the resolved count ($enabledCount) against it." -ForegroundColor Yellow
        }
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
    "Purview portal > Insider Risk Management > Settings > Policy indicators > DLP alerts indicators: the DLP-alerts indicator is enabled tenant-wide, and every DLP policy intended for THIS policy's triggering event (checked separately via ../deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 against Security & Compliance PowerShell) is actually added to the list - not merely readiness-checked."
    $(if ($DlpTriggerConfigured) { "Every DLP policy feeding this trigger has Mode = Enable, not TestWithNotifications/TestWithoutNotifications - whether a Test-mode policy still generates the alerts this indicator consumes is UNCONFIRMED (README.md §11); re-run ../deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 if any policy's Mode changed since it was last checked." })
    $(if ($DlpTriggerConfigured) { "DOUBLE-SCOPING CROSS-CHECK (design.md §2 goal 3): for each DLP policy feeding this trigger, confirm its own rule scope actually overlaps with this IRM policy's 'Users and groups' scope - a user missing from EITHER scope never has their alert processed, and there is no automated way to detect that silent gap." })
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the base 'Data leaks' template (NOT 'Data leaks by risky users' or 'Data leaks by priority users' - all three share overlapping naming in the template picker), and is in an active (not draft/disabled) state."
    "Policy's Indicators page has 'Office indicators' selected AND 'Cumulative exfiltration detection' selected (default-on for this template - confirm it wasn't inadvertently deselected)."
    "If optional Communication Compliance content indicators, generative-AI indicators, or cloud indicators are intended, confirm they are selected on the Indicators page - none is selected by default."
    $(if ($CloudIndicatorsEnabled) { "Microsoft Defender portal > Settings > Cloud Apps > App Connectors: the Box/Dropbox/Google Drive/Amazon S3/Azure connector(s) this policy's cloud indicators depend on show status 'Connected', and pay-as-you-go billing remains enabled in Purview billing." })
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm the actively-scored count against the cap you separately confirmed for this specific template (design.md §2 goal 7) - no API exists to check this automatically, and no other policy sharing this template's cumulative cap already exists that would push the combined count over the limit."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins' (docs/rbac-model.md §4)."
    "If using the alternative exfiltration-activity triggering event instead of (or in addition to) the DLP-policy trigger: confirm the selected built-in indicators and threshold mode (default vs. custom) match what was intended - portal-only, no read API."
    "Deployed configuration matches deploy/policy/data-leaks-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
) | Where-Object { $_ }
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
