#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }

<#
.SYNOPSIS
    Identifies every documented hold type on a list of target mailboxes -- the "Step 3/Step 4"
    identification work search-and-purge-teams-messages left manual. Read-only; makes no changes.

.DESCRIPTION
    Companion scenario to scenarios/ediscovery/search-and-purge-teams-messages/. Before that
    scenario's Invoke-TeamsMessagePurge.ps1 can succeed, every hold or retention policy on each
    target mailbox must be removed (Microsoft's own documented behavior: an active hold silently
    retains the content instead of just hiding it from the user, unlike the Exchange-mailbox sibling
    scenario). This script identifies what's actually on each mailbox, using the documented
    Get-Mailbox/Get-OrganizationConfig InPlaceHolds prefix convention (design.md Section 4):

      LitigationHoldEnabled            -> Litigation Hold
      InPlaceHolds "UniH..."           -> eDiscovery case hold (Unified Hold) -- identify-only, design.md Section 6
      InPlaceHolds "mbx<guid>:n"/"skp<guid>:n" -> mailbox-scoped OR org-wide retention policy
                                           (cross-checked against Get-OrganizationConfig)
      InPlaceHolds "-mbx<guid>"        -> this mailbox is excluded from an org-wide policy already
      InPlaceHolds <guid, no prefix>   -> legacy In-Place Hold -- identify-only, design.md Section 2
      ComplianceTagHoldApplied         -> retention-label hold
      DelayHoldApplied/DelayReleaseHoldApplied -> a delay hold from a prior, unrelated removal cycle

    Also lists every tenant-wide Get-AppRetentionCompliancePolicy policy (Teams chats, Teams private
    channel messages, Copilot, etc.) as INFORMATIONAL CONTEXT ONLY -- Microsoft's own docs state these
    newer-location policies "don't stamp directly on organization configuration or Exchange Online
    objects," so this script cannot confirm whether any one of them applies to a specific mailbox
    (design.md Section 7). Do not treat an empty per-mailbox report as proof no such policy applies.

    IMPORTANT -- "mbx"/"skp"/"grp" are NOT interchangeable for a mailbox-scoped (specific-location)
    retention policy. Microsoft's own "Identify Exchange mailbox hold types" reference documents ONLY
    "mbx"/"skp" for a Get-Mailbox-visible specific-location stamp; "grp" is documented ONLY under the
    separate Get-OrganizationConfig (org-wide) table, and Microsoft's retention-settings reference
    confirms a Microsoft 365 Group mailbox is flatly rejected ("RemoteGroupMailbox isn't a valid
    selection") from the Exchange-mailboxes location a "mbx"/"skp" stamp implies -- design.md Section 8.
    This script therefore classifies a "grp"-prefixed entry NOT found in Get-OrganizationConfig's own
    org-wide list as a distinct, undocumented case -- MailboxScopedGroupPolicyNames when the mailbox IS
    a group/team mailbox (the only mechanism that could plausibly have produced it,
    -AddModernGroupLocation), or UnrecognizedPolicyGuids when it is NOT (an anomaly no citation this
    scenario carries explains) -- rather than silently reusing the Exchange-location classification.

    Connect first: Connect-ExchangeOnline AND Connect-IPPSSession (both certificate app-only --
    docs/automation-surface.md Section 3). This script does not open either session.

.PARAMETER DefinitionPath
    Path to a JSON file with a .search.targetMailboxes[].email array -- schema-identical to
    search-and-purge-teams-messages/deploy/policy/teams-message-purge-search-definition.sample.json,
    so the same incident config file can drive both scenarios. Mutually exclusive with -Mailbox.

.PARAMETER Mailbox
    Explicit list of mailbox SMTP addresses. Mutually exclusive with -DefinitionPath.

.PARAMETER OutputPath
    Optional path to write the full per-mailbox report as JSON (consumed by nothing in this
    scenario directly -- Remove-TeamsPurgeMailboxHolds.ps1 re-identifies fresh rather than trusting a
    possibly-stale report; this is for incident-record/audit purposes).

.PARAMETER SkipAppRetentionPolicyListing
    Skip the informational Get-AppRetentionCompliancePolicy tenant-wide listing (design.md Section 7).

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Get-TeamsPurgeMailboxHoldState.ps1 -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json

.EXAMPLE
    ./Get-TeamsPurgeMailboxHoldState.ps1 -Mailbox 'payments-team@contoso.com','alex.chen@contoso.com' `
        -OutputPath ./hold-state-2026-014.json

.NOTES
    Grounded in Microsoft Learn -- see README.md Section 12 for the full citation list. Central
    references: "Identify Exchange mailbox hold types in eDiscovery" (InPlaceHolds prefix table,
    delay holds, ComplianceTagHoldApplied) and "PowerShell cmdlets for retention policies and
    retention labels" (Get-AppRetentionCompliancePolicy / newer-locations gap).

    Least-privileged roles: view-only access to Get-Mailbox/Get-OrganizationConfig (Exchange Online
    View-Only Recipients or broader) and Get-RetentionCompliancePolicy/Get-AppRetentionCompliancePolicy
    (View-Only Retention Management or broader) -- README.md Section 3.
#>
[CmdletBinding(DefaultParameterSetName = 'Definition')]
param(
    [Parameter(ParameterSetName = 'Definition')]
    [string]$DefinitionPath,

    [Parameter(Mandatory, ParameterSetName = 'Mailbox')]
    [string[]]$Mailbox,

    [string]$OutputPath,

    [switch]$SkipAppRetentionPolicyListing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ExoConnected {
    if (-not (Get-Command Get-Mailbox -ErrorAction SilentlyContinue)) {
        throw 'Exchange Online PowerShell cmdlets not found. Connect first: Connect-ExchangeOnline. See docs/automation-surface.md Section 3.'
    }
}
function Assert-SccConnected {
    if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw 'Security & Compliance PowerShell cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3.'
    }
}

function Get-TargetMailboxList {
    param([string]$DefinitionPath, [string[]]$Mailbox)
    if ($Mailbox) { return $Mailbox }
    if (-not $DefinitionPath) {
        throw 'Specify either -DefinitionPath or -Mailbox.'
    }
    if (-not (Test-Path -LiteralPath $DefinitionPath)) { throw "Definition file not found: $DefinitionPath" }
    $def = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json
    $emails = @($def.search.targetMailboxes | ForEach-Object { $_.email })
    if ($emails.Count -eq 0) { throw "No target mailboxes found under .search.targetMailboxes in $DefinitionPath." }
    return $emails
}

# GUID (without prefix/suffix) -> resolved retention-policy Name, cached to avoid repeat S&CC calls.
$script:PolicyNameCache = @{}
function Resolve-RetentionPolicyName {
    param([string]$Guid)
    if ($script:PolicyNameCache.ContainsKey($Guid)) { return $script:PolicyNameCache[$Guid] }
    $policy = Get-RetentionCompliancePolicy -Identity $Guid -DistributionDetail -ErrorAction SilentlyContinue
    $name = if ($policy) { $policy.Name } else { "<unresolved:$Guid>" }
    $script:PolicyNameCache[$Guid] = $name
    return $name
}

function ConvertTo-ParsedInPlaceHolds {
    # "mbx"/"skp" are the ONLY prefixes Microsoft documents for a Get-Mailbox-visible specific-location
    # (mailbox-scoped) retention policy stamp -- "grp" is documented only under the separate
    # Get-OrganizationConfig (org-wide) table (README.md Section 12 source 5). A "grp"-prefixed entry
    # not found in $OrgWideGroupGuids is therefore an undocumented case, kept in its own bucket rather
    # than merged into MailboxScopedPolicyNames and processed with an Exchange-location call that
    # Microsoft's retention-settings reference proves cannot ever have targeted a Group mailbox
    # (design.md Section 8).
    param([string[]]$InPlaceHolds, [string[]]$OrgWideExchangeGuids, [string[]]$OrgWideGroupGuids)

    $result = [ordered]@{
        EDiscoveryHoldGuids            = @()
        LegacyInPlaceHoldGuids         = @()
        MailboxScopedPolicyNames       = @()   # "mbx"/"skp" only
        MailboxScopedGroupPolicyNames  = @()   # "grp", not org-wide -- undocumented notation, disclosed
        OrgWidePolicyNamesOnMbx        = @()   # org-wide GUID that also happened to stamp this mailbox
        OrgWideExclusionPolicyNames    = @()
    }
    foreach ($h in @($InPlaceHolds)) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        if ($h -match '^UniH(.+)$') {
            $result.EDiscoveryHoldGuids += $Matches[1]
        }
        elseif ($h -match '^-mbx([0-9a-fA-F]{32})$') {
            $result.OrgWideExclusionPolicyNames += (Resolve-RetentionPolicyName -Guid $Matches[1])
        }
        elseif ($h -match '^(mbx|skp)([0-9a-fA-F]{32}):(\d)$') {
            $guid = $Matches[2]
            $name = Resolve-RetentionPolicyName -Guid $guid
            if ($OrgWideExchangeGuids -contains $guid) {
                $result.OrgWidePolicyNamesOnMbx += $name
            } else {
                $result.MailboxScopedPolicyNames += $name
            }
        }
        elseif ($h -match '^grp([0-9a-fA-F]{32}):(\d)$') {
            $guid = $Matches[1]
            $name = Resolve-RetentionPolicyName -Guid $guid
            if ($OrgWideGroupGuids -contains $guid) {
                $result.OrgWidePolicyNamesOnMbx += $name
            } else {
                $result.MailboxScopedGroupPolicyNames += $name
            }
        }
        else {
            # No recognized prefix -> legacy In-Place Hold (design.md Section 2).
            $result.LegacyInPlaceHoldGuids += $h
        }
    }
    return $result
}

# --- main ---

Assert-ExoConnected
Assert-SccConnected

$mailboxes = Get-TargetMailboxList -DefinitionPath $DefinitionPath -Mailbox $Mailbox
Write-Host "Identifying hold state for $($mailboxes.Count) target mailbox(es)..." -ForegroundColor Cyan

# Org-wide policies apply even when a mailbox's own InPlaceHolds is silent about them -- never skip
# this cross-check (design.md Section 4). "mbx"-prefixed org-wide policies apply to Exchange
# mailboxes (including 1xN Teams chats, stored in the participant's own mailbox); "grp"-prefixed
# org-wide policies apply to Microsoft 365 Group mailboxes (a standard/shared channel's PARENT TEAM
# mailbox) only, NOT to a regular user's mailbox -- these are two different policy types with two
# different exception mechanisms (-AddExchangeLocationException vs -AddModernGroupLocationException)
# per Microsoft's own InPlaceHolds prefix reference (README.md Section 12 source 5) -- design.md
# Section 4/8.
$orgConfig = Get-OrganizationConfig
$orgHoldEntries = @($orgConfig.InPlaceHolds)
$orgWideExchangeGuids = @($orgHoldEntries | ForEach-Object { if ($_ -match '^mbx([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })
$orgWideGroupGuids = @($orgHoldEntries | ForEach-Object { if ($_ -match '^grp([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })
$orgWideExchangePolicyNames = @($orgWideExchangeGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ })
$orgWideGroupPolicyNames = @($orgWideGroupGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ })

if ($orgWideExchangePolicyNames.Count -gt 0) {
    Write-Host "`n=== Organization-wide retention policies (Exchange mailboxes -- apply to ALL target mailboxes unless excluded) ===" -ForegroundColor Yellow
    $orgWideExchangePolicyNames | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "`nNo organization-wide Exchange-mailbox retention policies found."
}
if ($orgWideGroupPolicyNames.Count -gt 0) {
    Write-Host "`n=== Organization-wide retention policies (Microsoft 365 Group mailboxes -- apply ONLY to a group/team mailbox target, e.g. a standard/shared channel's parent team) ===" -ForegroundColor Yellow
    $orgWideGroupPolicyNames | ForEach-Object { Write-Host "  - $_" }
}

$report = @()
foreach ($mbx in $mailboxes) {
    $m = Get-Mailbox -Identity $mbx -ErrorAction SilentlyContinue
    if (-not $m) {
        Write-Warning "Mailbox not found: $mbx -- skipping."
        continue
    }
    $parsed = ConvertTo-ParsedInPlaceHolds -InPlaceHolds $m.InPlaceHolds -OrgWideExchangeGuids $orgWideExchangeGuids -OrgWideGroupGuids $orgWideGroupGuids
    $isGroupMailbox = $m.RecipientTypeDetails -eq 'GroupMailbox'

    # Org-wide Exchange policies apply to Exchange mailboxes, Exchange public folders, and 1xN Teams
    # chats (participant mailboxes) -- Microsoft's retention-settings reference confirms the Exchange-
    # mailboxes location as a whole (org-wide included) never covers a Microsoft 365 Group mailbox, so
    # this must be gated the same way the Group-policy applicability already is (design.md Section 8).
    $applicableOrgWideExchange = if (-not $isGroupMailbox) {
        @($orgWideExchangePolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    } else { @() }
    $applicableOrgWideGroup = if ($isGroupMailbox) {
        @($orgWideGroupPolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    } else { @() }
    $applicableOrgWide = @($applicableOrgWideExchange + $applicableOrgWideGroup)

    # A "grp"-prefixed, non-org-wide entry is only plausible on a group/team mailbox itself (the only
    # mechanism that could have produced it, -AddModernGroupLocation); on any other mailbox it's an
    # anomaly no citation this scenario carries explains -- never silently merged into either bucket.
    $mailboxScopedGroup = if ($isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }
    $unrecognizedPolicyNames = if (-not $isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }

    $blocksPurge = $m.LitigationHoldEnabled -or
        ($parsed.EDiscoveryHoldGuids.Count -gt 0) -or
        ($parsed.LegacyInPlaceHoldGuids.Count -gt 0) -or
        ($parsed.MailboxScopedPolicyNames.Count -gt 0) -or
        ($mailboxScopedGroup.Count -gt 0) -or
        ($unrecognizedPolicyNames.Count -gt 0) -or
        ($parsed.OrgWidePolicyNamesOnMbx.Count -gt 0) -or
        ($applicableOrgWide.Count -gt 0) -or
        [bool]$m.ComplianceTagHoldApplied -or
        [bool]$m.DelayHoldApplied -or
        [bool]$m.DelayReleaseHoldApplied

    $entry = [ordered]@{
        Mailbox                    = $mbx
        IsGroupMailbox             = $isGroupMailbox
        BlocksPurge                = $blocksPurge
        LitigationHoldEnabled      = [bool]$m.LitigationHoldEnabled
        EDiscoveryHoldGuids        = $parsed.EDiscoveryHoldGuids
        LegacyInPlaceHoldGuids     = $parsed.LegacyInPlaceHoldGuids
        MailboxScopedPolicyNames   = @($parsed.MailboxScopedPolicyNames + $parsed.OrgWidePolicyNamesOnMbx | Select-Object -Unique)
        MailboxScopedGroupPolicyNames = $mailboxScopedGroup
        UnrecognizedPolicyNames    = $unrecognizedPolicyNames
        ApplicableOrgWideExchangePolicyNames = $applicableOrgWideExchange
        ApplicableOrgWideGroupPolicyNames = $applicableOrgWideGroup
        OrgWideExclusionPolicyNames = $parsed.OrgWideExclusionPolicyNames
        ComplianceTagHoldApplied   = [bool]$m.ComplianceTagHoldApplied
        DelayHoldApplied           = [bool]$m.DelayHoldApplied
        DelayReleaseHoldApplied    = [bool]$m.DelayReleaseHoldApplied
    }
    $report += [pscustomobject]$entry

    Write-Host "`n--- $mbx $(if ($isGroupMailbox) { '[group/team mailbox]' }) ---" -ForegroundColor $(if ($blocksPurge) { 'Red' } else { 'Green' })
    Write-Host "  BlocksPurge: $blocksPurge"
    if ($m.LitigationHoldEnabled) { Write-Host '  - Litigation Hold: ENABLED' }
    if ($entry.EDiscoveryHoldGuids.Count -gt 0) { Write-Host "  - eDiscovery case hold(s) [identify-only, design.md Section 6]: $($entry.EDiscoveryHoldGuids -join ', ')" -ForegroundColor Yellow }
    if ($entry.LegacyInPlaceHoldGuids.Count -gt 0) { Write-Host "  - Legacy In-Place Hold(s) [identify-only, design.md Section 2]: $($entry.LegacyInPlaceHoldGuids -join ', ')" -ForegroundColor Yellow }
    if ($entry.MailboxScopedPolicyNames.Count -gt 0) { Write-Host "  - Retention polic(y/ies) stamped on this mailbox: $($entry.MailboxScopedPolicyNames -join ', ')" }
    if ($entry.MailboxScopedGroupPolicyNames.Count -gt 0) { Write-Host "  - Mailbox-scoped Group-location polic(y/ies) stamped on this group/team mailbox [undocumented InPlaceHolds notation -- design.md Section 8]: $($entry.MailboxScopedGroupPolicyNames -join ', ')" -ForegroundColor Yellow }
    if ($entry.UnrecognizedPolicyNames.Count -gt 0) { Write-Host "  - UNRECOGNIZED 'grp'-prefixed polic(y/ies) on a non-group mailbox [identify-only, no citation explains this case -- design.md Section 8]: $($entry.UnrecognizedPolicyNames -join ', ')" -ForegroundColor Yellow }
    if ($entry.ApplicableOrgWideExchangePolicyNames.Count -gt 0) { Write-Host "  - Organization-wide Exchange polic(y/ies) applicable (not excluded): $($entry.ApplicableOrgWideExchangePolicyNames -join ', ')" }
    if ($entry.ApplicableOrgWideGroupPolicyNames.Count -gt 0) { Write-Host "  - Organization-wide Group polic(y/ies) applicable (not excluded): $($entry.ApplicableOrgWideGroupPolicyNames -join ', ')" }
    if ($entry.ComplianceTagHoldApplied) { Write-Host '  - Retention-label hold (ComplianceTagHoldApplied): TRUE [one-way clear -- design.md Section 5]' -ForegroundColor Yellow }
    if ($entry.DelayHoldApplied -or $entry.DelayReleaseHoldApplied) { Write-Host "  - Delay hold present: DelayHoldApplied=$($entry.DelayHoldApplied) DelayReleaseHoldApplied=$($entry.DelayReleaseHoldApplied)" -ForegroundColor Yellow }
    if (-not $blocksPurge) { Write-Host '  No blocking hold identified by this scenario''s scriptable checks.' -ForegroundColor Green }
}

if (-not $SkipAppRetentionPolicyListing) {
    Write-Host "`n=== Newer-location retention policies (Teams chats/private channels/Copilot, etc.) -- INFORMATIONAL ONLY ===" -ForegroundColor DarkYellow
    Write-Host 'Cannot be matched to a specific mailbox (design.md Section 7). Use Policy Lookup in the Microsoft Purview portal to confirm applicability before assuming a mailbox is unaffected.' -ForegroundColor DarkYellow
    $appPolicies = @(Get-AppRetentionCompliancePolicy -ErrorAction SilentlyContinue)
    if ($appPolicies.Count -eq 0) {
        Write-Host '  (none found)'
    } else {
        $appPolicies | ForEach-Object { Write-Host "  - $($_.Name) [Applications: $($_.Applications -join ', ')]" }
    }
}

if ($OutputPath) {
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host "`nReport written to $OutputPath"
}

Write-Host "`nNext: for mailboxes with BlocksPurge=true, run ./Remove-TeamsPurgeMailboxHolds.ps1 before search-and-purge-teams-messages's Invoke-TeamsMessagePurge.ps1."
return $report
