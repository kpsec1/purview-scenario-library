---
part: "validate"
parent: "insider-risk/security-policy-violations-by-risky-users"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-RiskyUsersIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Security Policy Violations by Risky Users scenario and
    prints a manual-verification checklist for the parts that have no API surface.

.DESCRIPTION
    Read-only. Two categories of check, clearly separated in the output:

    1. AUTOMATED (hard pass/fail, contributes to exit code) - a Microsoft Graph session is active
       with the GroupMember.Read.All permission (probed with a minimal
       Get-MgGroupTransitiveMemberAsUser call against -GroupId, the same dependency
       ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 has),
       and - if -GroupId resolves - that the resulting enabled-user count is checked against this
       template's 7,500-user cap.

    2. MANUAL (printed as a checklist, never fails the script) - the portal-only configuration
       (dedicated HR connector existence/scenario mapping, Communication Compliance dedicated
       policy existence, IRM policy, Defender for Endpoint advanced feature, role groups, the
       AND/OR trigger-health question) that has no Graph/PowerShell read API to verify
       programmatically as of this writing - see design.md §2 goal 6/7.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls. This script does NOT validate HR connector ingestion status (no read API
    exists for that either - see the manual checklist).

.PARAMETER GroupId
    One or more Entra group object IDs used for the automated scope-sizing check - the same
    source group(s) used by
    ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1. If
    omitted, that one automated check is skipped (with a message, not a failure) and only the
    Graph-session check runs.

.PARAMETER MaxUsers
    The template's actively-scored-user cap to check the resolved count against. Defaults to 7500
    - Microsoft's documented limit for this template, cumulative tenant-wide across every policy
    built from this exact template. See README.md §6.

.PARAMETER PolicyName
    Display name used for the manual-checklist output only (no API call is made against it - there
    is nothing to query). Defaults to the name used throughout this scenario's docs.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-RiskyUsersIrmSetup.ps1 -GroupId $SecurityRelevantUsersGroupId

.NOTES
    Grounded in Microsoft Learn - see
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1
    .NOTES for the Graph API references this script's automated check relies on.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxUsers = 7500,

    [Parameter()]
    [string]$PolicyName = 'Security Policy Violations by Risky Users'
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
        Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the $MaxUsers-user template cap - NOTE: this cap is shared across every policy built from this exact template tenant-wide" `
            -Condition ($enabledCount -le $MaxUsers) -Warn
    }
    catch {
        Test-Check -Description "Get-MgGroupTransitiveMemberAsUser call succeeds - FAILED: $($_.Exception.Message)" -Condition $false
    }
}
elseif ($graphContext) {
    Write-Host "  [SKIP] No -GroupId supplied - scope-sizing check not run." -ForegroundColor Yellow
}

Write-Host "`n=== MANUAL VERIFICATION CHECKLIST (no API surface exists to automate these - design.md §2 goal 7) ===" -ForegroundColor Cyan
$manualChecklist = @(
    "Purview portal > Settings > Data connectors > My connectors: a DEDICATED HR connector (not the departing-employee-data-theft sibling's Resignation-scoped one) exists, mapped to Job level change / Performance review / Performance improvement plan, with a recent successful import log entry (README.md §5 Step 2/§8)."
    "If Communication Compliance integration is enabled: Communication Compliance > Policies: the auto-created dedicated 'Detect inappropriate text' policy (name per README.md §11's disclosed naming inconsistency) exists, is active, and its scope/classifiers haven't been unintentionally narrowed (README.md §5 Step 6/§8)."
    "AT LEAST ONE of the two trigger paths above is confirmed actually producing signal - a policy with neither is silently non-functional despite appearing correctly configured (README.md §8/§11, design.md §2 goal 6). Do not treat 'the policy exists' as evidence either path is live."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Security policy violations by risky users' template (not the base/departing-users/priority-users siblings), and is in an active (not draft/disabled) state."
    "Policy's Indicators page has the 'Microsoft Defender for Endpoint indicators (preview)' category selected - NOT Communication Compliance content indicators, which are not documented as selectable for this specific template (README.md §5 Step 7)."
    "Microsoft Defender portal > Settings > Endpoints > Advanced features: 'Share endpoint alerts with Microsoft Compliance Center' is ON (README.md §5 Step 3)."
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm no OTHER policy sharing this template's cumulative 7,500-user cap already exists that would push the CUMULATIVE template-wide count over the limit - no API exists to check this automatically."
    "Purview portal > Insider Risk Management > Policies: no 'Your organization doesn't have a Microsoft Defender for Endpoint subscription' or 'Microsoft Defender for Endpoint alerts aren't being shared with the Microsoft Purview portal' policy-health warning is showing (README.md §8)."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins', and (if the Communication Compliance review-page path is needed) the relevant IRM investigators have been manually added to 'Communication Compliance Investigators' (README.md §5 Step 6)."
    "Deployed configuration matches deploy/policy/security-policy-violations-risky-users-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
)
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```