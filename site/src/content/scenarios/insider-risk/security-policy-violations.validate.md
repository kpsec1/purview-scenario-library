---
part: "validate"
parent: "insider-risk/security-policy-violations"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-SecurityPolicyViolationsIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Security Policy Violations (base template) scenario and
    prints a manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId, the same dependency
       Get-SecurityPolicyViolationsScopeCandidates.ps1 has), and - if -GroupId resolves - that the
       resulting enabled-user count is within -MaxUsers.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (policy, Defender for Endpoint advanced feature, role groups, whether any OTHER
       "Security policy violations" base-template policy already exists elsewhere in the tenant)
       that has no Graph/PowerShell read API to verify programmatically as of this writing - see
       design.md §4.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls.

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated scope-sizing check. If omitted, that
    one automated check is skipped (with a message, not a failure) and only the Graph-session check
    runs.

.PARAMETER MaxUsers
    The cap to check the resolved group(s)' enabled-user count against. Defaults to 1000 -
    Microsoft's documented limit for this template. See README.md §6.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-SecurityPolicyViolationsIrmSetup.ps1 -GroupId $PrivilegedUsersGroupId

.NOTES
    Grounded in Microsoft Learn - see deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1
    .NOTES for the Graph API references this script's automated checks rely on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxUsers = 1000,

    [Parameter()]
    [string]$PolicyName = 'Security Policy Violations'
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
        Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the $MaxUsers-user template cap - NOTE: this does not account for other policies sharing this template's cap; see .NOTES" `
            -Condition ($enabledCount -le $MaxUsers) -Warn
    }
    catch {
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}
elseif ($graphContext) {
    Write-Host "  [SKIP] No -GroupId supplied - scope-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these - design.md §4) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Security policy violations' template (the base template, not the departing-users/priority-users/risky-users siblings), and is in an active (not draft/disabled) state."
    "Microsoft Defender portal > Settings > Endpoints > Advanced features: 'Share endpoint alerts with Microsoft Compliance Center' is ON (README.md §5 Step 2)."
    "Policy's Indicators page has the 'Microsoft Defender for Endpoint indicators (preview)' category selected."
    "Policy's 'Users and groups' scope is the deliberately-chosen group(s)/users from Get-SecurityPolicyViolationsScopeCandidates.ps1 - NOT 'All users and groups' (README.md §5 Step 4)."
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm no OTHER 'Security policy violations' (base template) policy already exists in the tenant that would push the CUMULATIVE template-wide count over 1,000 - no API exists to check this automatically (README.md §5 Step 3, §10; design.md §2 goal 5)."
    "Purview portal > Insider Risk Management > Policies: no 'Your organization doesn't have a Microsoft Defender for Endpoint subscription' or 'Microsoft Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal' policy-health warning is showing (README.md §8)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins'."
    "Deployed configuration matches deploy/policy/security-policy-violations-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```