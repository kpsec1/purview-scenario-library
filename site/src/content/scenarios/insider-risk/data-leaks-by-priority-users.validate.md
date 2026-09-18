---
part: "validate"
parent: "insider-risk/data-leaks-by-priority-users"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataLeaksPriorityUsersIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Data Leaks by Priority Users scenario and prints a
    manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. This scenario reuses two already-built scripts unmodified
    (../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 and
    ../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1)
    rather than forking either a third/second time (design.md §2 goals 1-2) - this script does NOT
    re-implement either one. It covers only:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId), and - if -GroupId resolves - that
       the resulting enabled-user count is checked against BOTH this template's own documented
       caps: the 10,000-member priority-user-group cap and the 1,000-actively-scored template cap
       (independently confirmed for THIS exact template - design.md §3 - not borrowed from a
       sibling template by analogy).

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (priority user group existence/membership/reviewer-permission scoping, the "Add or edit
       priority user groups" scope step, the separately-selectable "User is a member of a
       priority user group" risk score booster, policy existence/template/state, the DLP
       double-scoping cross-check if the DLP trigger is used) that has no Graph/PowerShell read
       API to verify programmatically as of this writing - see design.md §2 goal 7.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls. Run ../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 separately
    against Security & Compliance PowerShell if using the DLP-policy trigger - this script does not
    re-run it.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated candidate-sizing check - the same
    source group(s) used to build the priority-user-group candidate CSV via
    ../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1.
    If omitted, that one automated check is skipped (with a message, not a failure) and only the
    Graph-session check runs.

.PARAMETER MaxGroupMembers
    The priority user group's own membership cap to check the resolved count against. Defaults to
    10000 - Microsoft's documented, tenant-wide limit (not per-template). See README.md §6.

.PARAMETER MaxActivelyScored
    This template's own actively-scored-user cap to separately check the same count against.
    Defaults to 1000 - Microsoft's documented limit for THIS exact template, cumulative only across
    policies built from it (NOT shared with any other template - design.md §3). See README.md §6.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.PARAMETER DlpTriggerConfigured
    Set if this deployment uses the DLP-policy triggering event - adds the double-scoping
    cross-check reminder to the manual checklist. Omit if using only the exfiltration-activity
    triggering event instead.

.PARAMETER CloudIndicatorsEnabled
    Set if this deployment enabled the optional cloud storage/cloud service indicator category
    (whose applicability to this specific template is itself an open VERIFY - README.md §11) - adds
    the corresponding Defender for Cloud Apps connector-health item to the manual checklist. Omit
    (default) to skip that item entirely.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DataLeaksPriorityUsersIrmSetup.ps1 -GroupId $PriorityPopulationGroupId -DlpTriggerConfigured

.NOTES
    Grounded in Microsoft Learn via direct MCP fetch/search (not WebSearch-only) - see README.md
    §12 for full citations, and
    ../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1
    .NOTES for the underlying Graph API references this script's automated check relies on.

    VERIFY (pilot tenant): what happens when a priority user group larger than 1,000 members is
    assigned to a policy built from THIS specific template - not documented either way by
    Microsoft. design.md §3.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxGroupMembers = 10000,

    [Parameter()]
    [int]$MaxActivelyScored = 1000,

    [Parameter()]
    [string]$PolicyName = 'Data Leaks by Priority Users',

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
        Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the $MaxGroupMembers-member priority-user-group cap" `
            -Condition ($enabledCount -le $MaxGroupMembers) -Warn
        Test-Check -Description "Combined enabled-member count ($enabledCount) is within the $MaxActivelyScored-user template actively-scored cap - this template's OWN cap, not shared with Security policy violations by priority users, Data leaks, or Data leaks by risky users (design.md §3)" `
            -Condition ($enabledCount -le $MaxActivelyScored) -Warn
    }
    catch {
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}
elseif ($graphContext) {
    Write-Host "  [SKIP] No -GroupId supplied - candidate-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Settings > Insider Risk Management > Priority user groups: the priority user group exists, its membership matches the intended candidate list, and reviewer permissions are deliberately scoped (not left at a broader default) if this is a sensitive population (README.md §3/§5 Step 4/§8)."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Data leaks by priority users' template (NOT 'Data leaks'/'Data leaks by risky users', and NOT 'Security policy violations by priority users' - all four share overlapping naming in the template picker), and is in an active (not draft/disabled) state."
    "Policy's 'Users and groups' page used the 'Add or edit priority user groups' option (NOT 'Include specific users and groups') and the correct priority user group is assigned (README.md §5 Step 5)."
    "CRITICAL: Policy's Indicators page has 'User is a member of a priority user group' explicitly selected under Risk score boosters - this is a SEPARATE checkbox from the scope assignment above, and priority-group members receive NO likelihood/severity boost without it (README.md §5 Step 5/§8/§11, design.md §2 goal 4)."
    "Policy's Indicators page has 'Office indicators' selected AND 'Cumulative exfiltration detection' selected (default-on for this template - confirm it wasn't inadvertently deselected)."
    $(if ($DlpTriggerConfigured) { "Purview portal > Insider Risk Management > Settings > Policy indicators > DLP alerts indicators: every DLP policy feeding this trigger (checked separately via ../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1) is actually added to the global list - not merely readiness-checked (README.md §5 Step 2/6)." })
    $(if ($DlpTriggerConfigured) { "Every DLP policy feeding this trigger has Mode = Enable, not TestWithNotifications/TestWithoutNotifications - re-run ../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 if any policy's Mode changed since it was last checked (README.md §11)." })
    $(if ($DlpTriggerConfigured) { "DOUBLE-SCOPING CROSS-CHECK: each DLP policy feeding this trigger has its own rule scope overlapping with this policy's priority-user-group population - a user missing from EITHER scope never has an alert processed, and there is no automated way to detect that silent gap (README.md §8)." })
    "If optional Communication Compliance content indicators or generative-AI indicators are intended, confirm they are selected on the Indicators page - none is selected by default."
    $(if ($CloudIndicatorsEnabled) { "Microsoft Defender portal > Settings > Cloud Apps > App Connectors: the relevant connector(s) show status 'Connected', and pay-as-you-go billing remains enabled - also confirm the cloud-indicator category was actually offered for THIS template at policy-creation time (README.md §11 open VERIFY)." })
    "Confirm the operator who created this policy is an UNRESTRICTED administrator - admin units are not supported for this template, and a restricted/scoped administrator cannot create it at all (README.md §3/§5 Step 1)."
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm the actively-scored count against the $MaxActivelyScored-user cap (this template's OWN pool - do not net it against a Security policy violations by priority users policy's own usage) - no API exists to check this automatically."
    "If the priority user group's membership is at or near the $MaxActivelyScored-user cap: confirm what the live portal actually shows or warns about active scoring beyond that cap - UNDOCUMENTED by Microsoft for this specific template (README.md §6/§11, design.md §3)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins'."
    "Deployed configuration matches deploy/policy/data-leaks-priority-users-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
) | Where-Object { $_ }
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```