---
part: "validate"
parent: "insider-risk/security-policy-violations-by-priority-users"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PriorityUserGroupIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Security Policy Violations by Priority Users scenario
    and prints a manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId, the same dependency
       Get-PriorityUserGroupScopeCandidates.ps1 has), and - if -GroupId resolves - that the
       resulting enabled-user count is checked against both documented caps.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (priority user group existence/membership/reviewer-permission scoping, policy, Defender for
       Endpoint advanced feature, role groups, the open dual-cap-interaction question) that has no
       Graph/PowerShell read API to verify programmatically as of this writing - see design.md §2
       goal 6.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated candidate-sizing check - the same
    source group(s) used to build the priority-user-group candidate CSV. If omitted, that one
    automated check is skipped (with a message, not a failure) and only the Graph-session check
    runs.

.PARAMETER MaxGroupMembers
    The priority user group's own membership cap to check the resolved count against. Defaults to
    10000 - Microsoft's documented limit. See README.md §6.

.PARAMETER MaxActivelyScored
    The template's actively-scored-user cap to separately check the same count against. Defaults
    to 1000 - Microsoft's documented limit, cumulative tenant-wide across every policy built from
    this exact template (shared with the base template). See README.md §6.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-PriorityUserGroupIrmSetup.ps1 -GroupId $ExecutivesGroupId

.NOTES
    Grounded in Microsoft Learn - see deploy/Get-PriorityUserGroupScopeCandidates.ps1 .NOTES for
    the Graph API references this script's automated checks rely on.
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
    [string]$PolicyName = 'Security Policy Violations by Priority Users'
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
        Test-Check -Description "Combined enabled-member count ($enabledCount) is within the $MaxActivelyScored-user template actively-scored cap - NOTE: this cap is shared with the base template and any other policy built from this exact template; see .NOTES on the undocumented behavior above this cap" `
            -Condition ($enabledCount -le $MaxActivelyScored) -Warn
    }
    catch {
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}
elseif ($graphContext) {
    Write-Host "  [SKIP] No -GroupId supplied - candidate-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these - design.md §2 goal 6) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Settings > Insider Risk Management > Priority user groups: the priority user group exists, its membership matches the intended candidate list, and reviewer permissions are deliberately scoped (not left at a broader default) if this is a sensitive population (README.md §3/§5 Step 4/§8)."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Security policy violations by priority users' template (not the base/departing-users/risky-users siblings), and is in an active (not draft/disabled) state."
    "Policy's 'Users and groups' scope is the priority user group created above - NOT a plain Entra group or 'All users and groups' (README.md §5 Step 5)."
    "Microsoft Defender portal > Settings > Endpoints > Advanced features: 'Share endpoint alerts with Microsoft Compliance Center' is ON (README.md §5 Step 2)."
    "Policy's Indicators page has the 'Microsoft Defender for Endpoint indicators (preview)' category selected."
    "If the priority user group's membership is at or near the $MaxActivelyScored-user template cap: confirm what the live portal actually shows or warns (or doesn't) about active scoring beyond that cap - UNDOCUMENTED by Microsoft as of this build (README.md §6/§11, design.md §3). Record the observed behavior for this tenant rather than assuming it."
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm no OTHER policy sharing this template's cumulative 1,000-user cap (including a base-template policy) already exists that would push the CUMULATIVE template-wide count over the limit - no API exists to check this automatically."
    "Purview portal > Insider Risk Management > Policies: no 'Your organization doesn't have a Microsoft Defender for Endpoint subscription' or 'Microsoft Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal' policy-health warning is showing (README.md §8)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins'."
    "Deployed configuration matches deploy/policy/security-policy-violations-priority-users-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```