---
part: "deploy"
parent: "insider-risk/security-policy-violations"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Get-SecurityPolicyViolationsScopeCandidates.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Resolves the candidate user population for the Insider Risk Management "Security policy
    violations" base template's policy scope, and checks it against Microsoft's fixed 1,000-user
    template-wide limit.

.DESCRIPTION
    Read-only. Never creates, modifies, or deletes anything in Microsoft Entra ID or the Purview
    portal - it only reads group membership and reports.

    This template has no HR connector and no priority-user-group requirement (unlike its
    departing-users and priority-users siblings), so the population added to the IRM policy's
    "Users and groups" step at deploy time is the ONLY control keeping the actively-scored
    population within Microsoft's fixed 1,000-user cap for this specific template - see
    design.md §3 for why "all users and groups" is not a viable scope for this template in any
    tenant above roughly that headcount.

    For each -GroupId supplied, this script calls Get-MgGroupTransitiveMemberAsUser (the
    microsoft.graph.user OData cast on /groups/{id}/transitiveMembers, so nested groups resolve
    correctly), dedupes the combined membership by user Id across all supplied groups, filters to
    AccountEnabled -eq $true, and compares the resulting count against -MaxUsers (default 1000,
    Microsoft's documented limit for this template).

    IMPORTANT - this check is a PRE-FLIGHT ESTIMATE, not a guarantee:
    - It cannot see users already in scope of OTHER "Security policy violations" (base template)
      policies elsewhere in the tenant, because Microsoft's 1,000-user limit is cumulative across
      ALL policies built from this exact template, and no documented Graph/REST API exists to
      query current template-wide usage. Confirm no other base-template policy already exists via
      the portal's Policies tab before relying on this script's count alone (README.md §5 Step 3,
      §10).
    - It reports enabled accounts only - a disabled account re-enabled after this script runs
      would not be reflected until the script is re-run.

    Follows the app-only, certificate-based auth pattern that is the default for every script in
    this library (docs/automation-surface.md §3) - run Connect-MgGraph yourself first, then call
    this script.

.PARAMETER GroupId
    One or more Entra group object IDs (GUIDs) whose transitive user membership should be resolved
    as policy-scope candidates. Membership across multiple groups is deduped by user Id, not
    summed - a user in two supplied groups counts once.

.PARAMETER MaxUsers
    The cap to check the resolved, deduped, enabled-account count against. Defaults to 1000 -
    Microsoft's documented limit for the "Security policy violations" base template. Override only
    if Microsoft changes the published limit; do not raise it to make a warning disappear.

.PARAMETER OutputPath
    If specified, writes the resolved candidate list (Id, DisplayName, UserPrincipalName,
    AccountEnabled, SourceGroupIds) as CSV to this path in addition to returning it on the
    pipeline - suitable as a hand-off artifact for whoever completes the portal policy-creation
    step (README.md §5 Step 4).

.PARAMETER WhatIf
    This script makes no mutating calls, so -WhatIf has nothing destructive to preview - accepted
    for interface consistency with the rest of this repo's deploy/ scripts; prints the query plan
    without calling Graph.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Get-SecurityPolicyViolationsScopeCandidates.ps1 -GroupId $PrivilegedUsersGroupId -WhatIf

    Dry run: shows the query plan, calls nothing.

.EXAMPLE
    ./Get-SecurityPolicyViolationsScopeCandidates.ps1 -GroupId $PrivilegedUsersGroupId, $ContractorsGroupId -OutputPath ./scope-candidates.csv

    Resolves both groups' transitive user membership, dedupes across them, filters to enabled
    accounts, checks the combined count against the 1,000-user cap, and writes the candidate list
    to CSV.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - List group transitive members (OData cast, required ConsistencyLevel: eventual header,
      GroupMember.Read.All among the higher-privileged application permissions):
      https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0
    - Get-MgGroupTransitiveMemberAsUser (Microsoft.Graph.Groups module, output type
      IMicrosoftGraphUser):
      https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggrouptransitivememberasuser
    - Limits in Insider Risk Management - maximum users in scope for the "Security policy
      violations" template (1,000):
      https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template
    - GroupMember.Read.All permission:
      https://learn.microsoft.com/graph/permissions-reference

    VERIFY before relying on this in production: this script cannot account for users already in
    scope of other "Security policy violations" (base template) policies elsewhere in the tenant -
    no Graph/REST API to query current template-wide usage was found during this build. See
    README.md §5 Step 3 and §10, design.md §2 goal 5.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxUsers = 1000,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Assert-MgGraphSession {
    if (-not (Get-MgContext)) {
        throw 'No Microsoft Graph session found. Run Connect-MgGraph first (see docs/automation-surface.md §3 for the certificate app-only pattern).'
    }
}

Write-Host "Query plan: resolve transitive user membership (microsoft.graph.user OData cast) of $($GroupId.Count) group(s) [$($GroupId -join ', ')]; dedupe by Id; filter to AccountEnabled -eq `$true; compare combined count against MaxUsers=$MaxUsers." -ForegroundColor Cyan
if ($OutputPath) { Write-Host "Output: $OutputPath" -ForegroundColor Cyan }

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Graph call made.' -ForegroundColor Yellow
    return
}

Assert-MgGraphSession

# Keyed by user Id so membership across multiple supplied groups is deduped, not summed.
$candidatesById = @{}

foreach ($gid in $GroupId) {
    Write-Host "Resolving transitive user members of group '$gid'..." -ForegroundColor Cyan
    # ConsistencyLevel: eventual is REQUIRED by the Graph API whenever an OData cast query
    # parameter is used (List group transitive members - Request headers) - this is the
    # microsoft.graph.user cast, so the header is mandatory here, not optional hardening.
    $members = Get-MgGroupTransitiveMemberAsUser -GroupId $gid `
        -Property 'id,displayName,userPrincipalName,accountEnabled' `
        -ConsistencyLevel eventual -All

    foreach ($member in $members) {
        if ($candidatesById.ContainsKey($member.Id)) {
            $candidatesById[$member.Id].SourceGroupIds.Add($gid)
            continue
        }
        $candidatesById[$member.Id] = [PSCustomObject]@{
            Id                = $member.Id
            DisplayName       = $member.DisplayName
            UserPrincipalName = $member.UserPrincipalName
            AccountEnabled    = $member.AccountEnabled
            SourceGroupIds    = [System.Collections.Generic.List[string]]::new()
        }
        $candidatesById[$member.Id].SourceGroupIds.Add($gid)
    }
}

# @(...) forces array semantics even when the filtered set has zero or exactly one element -
# PowerShell would otherwise assign $null or a bare scalar, breaking every .Count reference below
# and producing a JSON/CSV scalar instead of a collection on export. Same gotcha class documented
# in the sibling scenario's Export-SecurityViolationInsiderRiskAlerts.ps1.
$enabledCandidates = @($candidatesById.Values | Where-Object { $_.AccountEnabled -eq $true } | Sort-Object UserPrincipalName)
$disabledCount = $candidatesById.Count - $enabledCandidates.Count

Write-Host "Resolved $($candidatesById.Count) unique user(s) across $($GroupId.Count) group(s): $($enabledCandidates.Count) enabled (policy-scope candidates), $disabledCount disabled (excluded)." -ForegroundColor Green

if ($enabledCandidates.Count -gt $MaxUsers) {
    Write-Host "[FAIL] $($enabledCandidates.Count) enabled candidate(s) EXCEEDS the $MaxUsers-user template cap. Narrow the source group(s) before policy creation - see README.md §5 Step 3." -ForegroundColor Red
}
elseif ($enabledCandidates.Count -gt ($MaxUsers * 0.8)) {
    Write-Host "[WARN] $($enabledCandidates.Count) enabled candidate(s) is within 20% of the $MaxUsers-user template cap. Leave headroom for growth, and remember this cap is shared with any OTHER 'Security policy violations' (base template) policy in the tenant - see .NOTES." -ForegroundColor Yellow
}
else {
    Write-Host "[PASS] $($enabledCandidates.Count) enabled candidate(s) is within the $MaxUsers-user template cap (this group set alone - see .NOTES on other policies sharing the same cap)." -ForegroundColor Green
}

if ($OutputPath) {
    $enabledCandidates | ForEach-Object {
        [PSCustomObject]@{
            Id                = $_.Id
            DisplayName       = $_.DisplayName
            UserPrincipalName = $_.UserPrincipalName
            SourceGroupIds    = ($_.SourceGroupIds -join ';')
        }
    } | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
    Write-Host "Wrote $($enabledCandidates.Count) candidate(s) to '$OutputPath'." -ForegroundColor Cyan
}

$enabledCandidates
```

#### `policy/security-policy-violations-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Security Policy Violations",
  "policyTemplate": "Security policy violations",
  "templateStatus": "Microsoft-labeled PREVIEW as of this writing (same family as the departing-users sibling) - re-verify GA status before a customer-facing commitment. README.md §1/§11.",
  "scope": {
    "users": "Operator-chosen Entra security group(s), resolved and sized by deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 - NOT 'All users and groups'. README.md §5 Step 3.",
    "maxUsersInScope": 1000,
    "note": "Microsoft-fixed limit for this specific template, cumulative across ALL policies built from it tenant-wide - smaller than the departing-users sibling's 15,000 and the risky-users sibling's 7,500, identical to the priority-users sibling's own cap. Do not conflate the four. design.md §3."
  },
  "triggeringEvents": [
    {
      "type": "Microsoft Defender for Endpoint security alert (defense evasion of security controls or unwanted software)",
      "optional": false,
      "note": "This IS the template's only triggering event - there is no HR connector or Entra-account-deletion toggle on this template's policy-creation workflow, unlike the departing-users sibling. README.md §5 Step 4 / §6."
    }
  ],
  "indicators": {
    "microsoftDefenderForEndpointIndicators": {
      "category": "Microsoft Defender for Endpoint indicators (preview)",
      "note": "Individual indicator names are not enumerated in Microsoft's own documentation as of this build. VERIFY the exact selectable indicator toggles against the live policy-creation workflow at deploy time. README.md §5 Step 4 / §11."
    },
    "otherIndicatorCategoriesSelectable": "VERIFY: whether Office/Device/Cumulative-exfiltration indicator categories are also selectable for this specific template in the live portal - not confirmed by Microsoft Learn during this build. Do not assume either way."
  },
  "prerequisites": {
    "defenderForEndpointSubscription": "Active Microsoft Defender for Endpoint subscription (Plan not specified by Microsoft's own prerequisite table - same open VERIFY the departing-users sibling carries). README.md §3.",
    "defenderForEndpointAdvancedFeature": "'Share endpoint alerts with Microsoft Compliance Center' toggled ON in the Microsoft Defender portal (Settings > Endpoints > Advanced features). Tenant-wide, shared with any other 'Security policy violations...' family policy. Portal-only - no API. README.md §5 Step 2.",
    "hrConnector": "NOT REQUIRED for this template - unlike the departing-users, priority-users, and risky-users siblings.",
    "priorityUserGroup": "NOT REQUIRED for this template - unlike the priority-users sibling."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every other Insider Risk Management scenario in this library."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```