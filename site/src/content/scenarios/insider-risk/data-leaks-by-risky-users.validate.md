---
part: "validate"
parent: "insider-risk/data-leaks-by-risky-users"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DataLeaksRiskyUsersIrmSetup.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Validates the scriptable parts of the Data Leaks by Risky Users scenario and prints a
    manual-verification checklist for the parts that have no API surface.

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
       trigger policy existence, IRM policy, Office/cumulative-exfiltration indicator selection,
       optional CC/generative-AI/cloud indicators, role groups, the AND/OR trigger-health
       question) that has no Graph/PowerShell read API to verify programmatically as of this
       writing - see design.md §2 goal 7 / README.md §7.

    Exits non-zero only if an AUTOMATED check hard-fails. Safe to re-run any number of times; makes
    no mutating calls. This script does NOT validate HR connector ingestion status or Defender for
    Cloud Apps connector health (no read API exists for either - see the manual checklist).

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

.PARAMETER CloudIndicatorsEnabled
    Set if this deployment enabled the optional cloud storage/cloud service indicator category -
    adds the corresponding Defender for Cloud Apps connector-health item to the manual checklist.
    Omit (default) to skip that item entirely rather than print a checklist entry for a feature
    this deployment doesn't use.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Test-DataLeaksRiskyUsersIrmSetup.ps1 -GroupId $RiskyUsersGroupId

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
    [string]$PolicyName = 'Data Leaks by Risky Users',

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
        Test-Check -Description "Combined enabled-member count across supplied group(s) ($enabledCount) is within the $MaxUsers-user template cap - NOTE: this cap is shared across every policy built from this exact template tenant-wide, AND is numerically identical to (but a separate cap from) the Security policy violations by risky users cousin's own cap" `
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
    "Purview portal > Settings > Data connectors > My connectors: a THIRD, dedicated HR connector (not the departing-employee-data-theft sibling's Resignation-scoped one, and not the security-policy-violations-by-risky-users sibling's own dedicated risk-indicator connector) exists, mapped to Job level change / Performance review / Performance improvement plan, with a recent successful import log entry (README.md §5 Step 2/§8)."
    "Any SCHEDULED (non-interactive) invocation of Send-HrRiskIndicatorRecord.ps1 for this scenario passes -JobId/-AppId matching THIS scenario's own connector, not a sibling's - three near-identical connectors now exist in this library using the same script and calling convention, and a wrong JobId uploads silently with no error (README.md §8/§11)."
    "If Communication Compliance TRIGGER integration is enabled: Communication Compliance > Policies: the auto-created dedicated 'Detect inappropriate text' policy (name per README.md §11's disclosed naming inconsistency) exists, is active, and its scope/classifiers haven't been unintentionally narrowed (README.md §5 Step 5/§8)."
    "AT LEAST ONE of the two trigger paths above is confirmed actually producing signal - a policy with neither is silently non-functional despite appearing correctly configured (README.md §8/§11, design.md §2 goal 8). Do not treat 'the policy exists' as evidence either path is live."
    "Purview portal > Insider Risk Management > Policies: policy '$PolicyName' exists, uses the 'Data leaks by risky users' template (not the base Data leaks/…by priority users siblings, and not the differently-scored Security policy violations by risky users cousin), and is in an active (not draft/disabled) state."
    "Policy's Indicators page has 'Office indicators' selected AND 'Cumulative exfiltration detection' selected (this template's default-on indicator, per README.md §6 - confirm it wasn't inadvertently deselected)."
    "If optional Communication Compliance content indicators or generative-AI indicators are intended as SCORING indicators (distinct from the trigger integration above), confirm they are selected on the Indicators page, not only the trigger option (README.md §5 Step 6/§6 - the same product plays two independent roles in this one policy)."
    $(if ($CloudIndicatorsEnabled) { "Microsoft Defender portal > Settings > Cloud Apps > App Connectors: the Box/Dropbox/Google Drive/Amazon S3/Azure connector(s) this policy's cloud indicators depend on show status 'Connected', and pay-as-you-go billing remains enabled in Purview billing (README.md §5 Step 6/§10)." })
    "Purview portal > Insider Risk Management > Policies > this policy's 'Users in scope' column: confirm no OTHER policy sharing this template's cumulative 7,500-user cap already exists that would push the CUMULATIVE template-wide count over the limit - no API exists to check this automatically."
    "Purview portal > Settings > Roles and groups: at least one user is a member of 'Insider Risk Management' or 'Insider Risk Management Admins', and (if the Communication Compliance review-page path is needed) the relevant IRM investigators have been manually added to 'Communication Compliance Investigators' (README.md §5 Step 5)."
    "Deployed configuration matches deploy/policy/data-leaks-risky-users-policy-manifest.json (diff manually - the manifest is a reference, not a live query)."
) | Where-Object { $_ }
$manualChecklist | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor Yellow }

Write-Host "`n$(if ($script:failures -eq 0) { 'All automated checks passed.' } else { "$script:failures automated check(s) failed." }) Manual checklist above still requires a human to confirm in the portal." `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```