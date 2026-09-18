---
part: "deploy"
parent: "insider-risk/security-policy-violations-by-priority-users"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Get-PriorityUserGroupScopeCandidates.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Resolves an Entra security group's transitive user membership into a correctly-sized,
    correctly-formatted candidate list for the Insider Risk Management "priority user group"
    bulk-membership upload, and checks it against BOTH of this template family's documented caps.

.DESCRIPTION
    Read-only. Never creates, modifies, or deletes anything in Microsoft Entra ID or the Purview
    portal - it only reads group membership and reports. It does NOT create the priority user
    group or upload members to it - no documented Graph/PowerShell write API for priority user
    groups was found during this build (design.md §2 goal 2/6). This script prepares the input to
    the manual portal workflow (README.md §5 Step 4), it does not perform that workflow.

    For each -GroupId supplied, this script calls Get-MgGroupTransitiveMemberAsUser (the
    microsoft.graph.user OData cast on /groups/{id}/transitiveMembers, so nested groups resolve
    correctly), dedupes the combined membership by user Id across all supplied groups, filters to
    AccountEnabled -eq $true, and checks the resulting count against TWO independently-documented
    caps:

      1. -MaxGroupMembers (default 10000) - Microsoft's documented ceiling on a single priority
         user group's own membership.
      2. -MaxActivelyScored (default 1000) - Microsoft's documented ceiling on how many users can
         be actively scored under the "Security policy violations by priority users" template,
         CUMULATIVE across every policy built from it tenant-wide (the same cap, and the same
         cumulative scoping rule, as the sibling "Security policy violations" base template).

    IMPORTANT - no Microsoft Learn page found during this build states what happens when a
    priority user group LARGER than the 1,000-actively-scored cap is assigned to a policy built
    from this template. This script does not guess: it reports against both caps independently
    and flags whichever is smaller as the effective planning ceiling, rather than assuming the
    10,000-member cap is the only one that matters. See design.md §3 and README.md §6/§11 for the
    full disclosure - VERIFY this interaction in a pilot tenant before relying on full coverage
    for a priority user group sized between the two caps.

    This script also flags candidates with no populated `mail` attribute in Microsoft Graph as a
    [WARN] - Microsoft's own priority-user-group workflow describes members as "mail-enabled
    users," but a populated `mail` attribute is an APPROXIMATION for mail-enablement, not a
    guarantee (a null Graph `mail` property reliably indicates NOT mail-enabled; a populated one
    does not, by itself, confirm the Exchange-side state the portal's own search/select or CSV
    upload step will actually accept). See README.md §11.

    Follows the app-only, certificate-based auth pattern that is the default for every script in
    this library (docs/automation-surface.md §3) - run Connect-MgGraph yourself first, then call
    this script.

.PARAMETER GroupId
    One or more Entra group object IDs (GUIDs) whose transitive user membership should be resolved
    as priority-user-group candidates. Membership across multiple groups is deduped by user Id, not
    summed - a user in two supplied groups counts once.

.PARAMETER MaxGroupMembers
    The priority user group's own membership cap to check the resolved, deduped, enabled-account
    count against. Defaults to 10000 - Microsoft's documented limit for a single priority user
    group. Override only if Microsoft changes the published limit; do not raise it to make a
    warning disappear.

.PARAMETER MaxActivelyScored
    The "Security policy violations by priority users" template's actively-scored-user cap to
    separately check the same count against. Defaults to 1000 - Microsoft's documented limit,
    cumulative tenant-wide across every policy built from this exact template. Override only if
    Microsoft changes the published limit.

.PARAMETER OutputPath
    If specified, writes the resolved candidate list as a `user principal name`-headed CSV to this
    path, ready for the priority user group's bulk-upload dialog (README.md §5 Step 4) - VERIFY the
    exact expected column-header casing and file format against the live upload dialog at deploy
    time before relying on this file without adjustment (README.md §11).

.PARAMETER WhatIf
    This script makes no mutating calls, so -WhatIf has nothing destructive to preview - accepted
    for interface consistency with the rest of this repo's deploy/ scripts; prints the query plan
    without calling Graph.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Get-PriorityUserGroupScopeCandidates.ps1 -GroupId $ExecutivesGroupId -WhatIf

    Dry run: shows the query plan, calls nothing.

.EXAMPLE
    ./Get-PriorityUserGroupScopeCandidates.ps1 -GroupId $ExecutivesGroupId, $PrivilegedAdminsGroupId -OutputPath ./priority-user-group-candidates.csv

    Resolves both groups' transitive user membership, dedupes across them, filters to enabled
    accounts, checks the combined count against both documented caps, and writes a bulk-upload-
    ready CSV.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Prioritize user groups for Insider Risk Management policies (priority user group creation
      workflow, 10,000-member cap, `user principal name` CSV bulk-upload column, "mail-enabled
      users" wording):
      https://learn.microsoft.com/purview/insider-risk-management-settings-priority-user-groups
    - Limits in Insider Risk Management - maximum users in scope for "Security policy violations
      by priority users" (1,000, identical to and cumulative with the base template):
      https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template
    - List group transitive members (OData cast, required ConsistencyLevel: eventual header,
      GroupMember.Read.All among the higher-privileged application permissions):
      https://learn.microsoft.com/graph/api/group-list-transitivemembers?view=graph-rest-1.0
    - Get-MgGroupTransitiveMemberAsUser (Microsoft.Graph.Groups module, output type
      IMicrosoftGraphUser):
      https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggrouptransitivememberasuser
    - GroupMember.Read.All permission:
      https://learn.microsoft.com/graph/permissions-reference

    VERIFY before relying on this in production:
    - What happens when a priority user group larger than the 1,000-actively-scored cap is
      assigned to a policy built from this template - not documented either way. design.md §3.
    - The exact `user principal name` CSV column-header casing and accepted file format for the
      live bulk-upload dialog - this build's network access could not fetch the Microsoft Learn
      page directly to extract a verbatim quote; the value used here is corroborated by multiple
      independent secondary sources describing the same Microsoft documentation, not a
      first-party verbatim confirmation. README.md §11.
    - This script cannot account for users already actively scored under OTHER policies sharing
      this template's cumulative 1,000-user cap (including the base template) - no Graph/REST API
      to query current template-wide usage was found during this build. README.md §6/§11.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string[]]$GroupId,

    [Parameter()]
    [int]$MaxGroupMembers = 10000,

    [Parameter()]
    [int]$MaxActivelyScored = 1000,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Assert-MgGraphSession {
    if (-not (Get-MgContext)) {
        throw 'No Microsoft Graph session found. Run Connect-MgGraph first (see docs/automation-surface.md §3 for the certificate app-only pattern).'
    }
}

Write-Host "Query plan: resolve transitive user membership (microsoft.graph.user OData cast) of $($GroupId.Count) group(s) [$($GroupId -join ', ')]; dedupe by Id; filter to AccountEnabled -eq `$true; compare combined count against MaxGroupMembers=$MaxGroupMembers (priority-group cap) and MaxActivelyScored=$MaxActivelyScored (template cap - cumulative w/ base template, see .NOTES)." -ForegroundColor Cyan
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
        -Property 'id,displayName,userPrincipalName,accountEnabled,mail' `
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
            Mail              = $member.Mail
            SourceGroupIds    = [System.Collections.Generic.List[string]]::new()
        }
        $candidatesById[$member.Id].SourceGroupIds.Add($gid)
    }
}

# @(...) forces array semantics even when the filtered set has zero or exactly one element -
# PowerShell would otherwise assign $null or a bare scalar, breaking every .Count reference below
# and producing a JSON/CSV scalar instead of a collection on export. Same gotcha class documented
# throughout this repo's other scope-resolution and export scripts.
$enabledCandidates = @($candidatesById.Values | Where-Object { $_.AccountEnabled -eq $true } | Sort-Object UserPrincipalName)
$disabledCount = $candidatesById.Count - $enabledCandidates.Count
$noMailCount = @($enabledCandidates | Where-Object { [string]::IsNullOrEmpty($_.Mail) }).Count

Write-Host "Resolved $($candidatesById.Count) unique user(s) across $($GroupId.Count) group(s): $($enabledCandidates.Count) enabled (priority-group candidates), $disabledCount disabled (excluded)." -ForegroundColor Green

if ($noMailCount -gt 0) {
    Write-Host "[WARN] $noMailCount of $($enabledCandidates.Count) candidate(s) have no populated Microsoft Graph 'mail' attribute. Microsoft's priority-user-group workflow describes members as 'mail-enabled users' - confirm these candidates resolve correctly in the portal's own member-search step before assuming the CSV upload will accept them (README.md §11 - this is an approximation, not a guarantee)." -ForegroundColor Yellow
}

$effectiveCap = [Math]::Min($MaxGroupMembers, $MaxActivelyScored)
if ($enabledCandidates.Count -gt $MaxGroupMembers) {
    Write-Host "[FAIL] $($enabledCandidates.Count) enabled candidate(s) EXCEEDS the $MaxGroupMembers-member priority-user-group cap. Narrow the source group(s) before creating the priority user group - see README.md §5 Step 3/4." -ForegroundColor Red
}
elseif ($enabledCandidates.Count -gt $MaxActivelyScored) {
    Write-Host "[WARN] $($enabledCandidates.Count) enabled candidate(s) is within the $MaxGroupMembers-member priority-group cap but EXCEEDS the $MaxActivelyScored-user template actively-scored cap. What happens to members beyond the template cap is UNDOCUMENTED by Microsoft (design.md §3) - VERIFY in a pilot tenant before assuming full coverage for this population." -ForegroundColor Yellow
}
elseif ($enabledCandidates.Count -gt ($effectiveCap * 0.8)) {
    Write-Host "[WARN] $($enabledCandidates.Count) enabled candidate(s) is within 20% of the effective $effectiveCap-user ceiling (the smaller of the two documented caps). Leave headroom for growth, and remember the $MaxActivelyScored-user template cap is shared with any OTHER policy built from this same template in the tenant, including the base 'Security policy violations' template - see .NOTES." -ForegroundColor Yellow
}
else {
    Write-Host "[PASS] $($enabledCandidates.Count) enabled candidate(s) is within both documented caps (this group set alone - see .NOTES on other policies sharing the actively-scored cap)." -ForegroundColor Green
}

if ($OutputPath) {
    # Single-column CSV, header text per README.md §5 Step 4/§11 - VERIFY exact casing against the
    # live upload dialog before relying on this file without adjustment.
    $enabledCandidates | ForEach-Object {
        [PSCustomObject]@{ 'user principal name' = $_.UserPrincipalName }
    } | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
    Write-Host "Wrote $($enabledCandidates.Count) candidate(s) to '$OutputPath' (single 'user principal name' column for the portal bulk-upload dialog)." -ForegroundColor Cyan
}

$enabledCandidates
```

#### `policy/security-policy-violations-priority-users-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring or priority-user-group management as of this writing (docs/automation-surface.md §6; design.md §2 goal 6). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy and priority user group can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Security Policy Violations by Priority Users",
  "policyTemplate": "Security policy violations by priority users",
  "templateStatus": "Microsoft-labeled PREVIEW as of this writing (same family as the base and departing-users siblings) - re-verify GA status before a customer-facing commitment. README.md §1/§11.",
  "priorityUserGroup": {
    "createdInSettings": "Purview portal > Settings > Insider Risk Management > Priority user groups > Create priority user group. README.md §5 Step 4.",
    "maxMembers": 10000,
    "membershipSource": "deploy/Get-PriorityUserGroupScopeCandidates.ps1 output CSV (bulk upload) and/or portal search/select - NOT a live-synced Entra group. README.md §5 Step 3/4, §11.",
    "reviewPermissions": "Assign one or more of Insider Risk Management / Insider Risk Management Analysts / Insider Risk Management Investigators role groups, or specific individual users, as reviewers for this group's data. README.md §3/§8.",
    "note": "This is a distinct, Microsoft-managed object - NOT the same thing as a plain Entra security group assigned to the sibling base template's policy. design.md §2 goal 1."
  },
  "scope": {
    "users": "The priority user group above, assigned at policy creation - this template does not accept a plain Entra group or individual users directly.",
    "maxActivelyScoredUsers": 1000,
    "note": "Microsoft-fixed limit for this specific template, cumulative across ALL policies built from it tenant-wide - IDENTICAL to the base 'Security policy violations' template's own cap (shared cumulative ceiling, not two separate 1,000-user allowances), smaller than the departing-users sibling's 15,000 and the risky-users sibling's 7,500. Interaction with the priority user group's own 10,000-member cap is UNDOCUMENTED by Microsoft - see design.md §3, README.md §6/§11. Do not conflate any of these four caps."
  },
  "triggeringEvents": [
    {
      "type": "Microsoft Defender for Endpoint security alert (defense evasion of security controls or unwanted software)",
      "optional": false,
      "note": "This IS the template's only triggering event - identical to the base template, there is no HR connector or Entra-account-deletion toggle on this template's policy-creation workflow. README.md §5 Step 5 / §6."
    }
  ],
  "indicators": {
    "microsoftDefenderForEndpointIndicators": {
      "category": "Microsoft Defender for Endpoint indicators (preview)",
      "note": "Individual indicator names are not enumerated in Microsoft's own documentation as of this build. VERIFY the exact selectable indicator toggles against the live policy-creation workflow at deploy time. README.md §5 Step 5 / §11."
    },
    "otherIndicatorCategoriesSelectable": "VERIFY: whether Office/Device/Cumulative-exfiltration indicator categories are also selectable for this specific template in the live portal - not confirmed by Microsoft Learn during this build. Do not assume either way."
  },
  "scoringBehavior": {
    "priorityGroupBoost": "Membership in the priority user group increases both the LIKELIHOOD and SEVERITY of resulting alerts for the same underlying activity, versus a non-priority user. README.md §5/§6/design.md §5."
  },
  "prerequisites": {
    "defenderForEndpointSubscription": "Active Microsoft Defender for Endpoint subscription (Plan not specified by Microsoft's own prerequisite table - same open VERIFY the base and departing-users siblings carry). README.md §3.",
    "defenderForEndpointAdvancedFeature": "'Share endpoint alerts with Microsoft Compliance Center' toggled ON in the Microsoft Defender portal (Settings > Endpoints > Advanced features). Tenant-wide, shared with any other 'Security policy violations...' family policy. Portal-only - no API. README.md §5 Step 2.",
    "hrConnector": "NOT REQUIRED for this template - unlike the departing-users and risky-users siblings.",
    "priorityUserGroup": "REQUIRED for this template - the distinguishing prerequisite versus the base template. README.md §3/§5 Step 4."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every other Insider Risk Management scenario in this library.",
    "reviewerScoping": "Optionally restricted at the priority-user-group level (see priorityUserGroup.reviewPermissions above) - a capability the base template's plain-group mechanism does not offer."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```