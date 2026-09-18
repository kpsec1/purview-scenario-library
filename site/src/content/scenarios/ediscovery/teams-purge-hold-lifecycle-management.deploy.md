---
part: "deploy"
parent: "ediscovery/teams-purge-hold-lifecycle-management"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Get-TeamsPurgeMailboxHoldState.ps1`

```powershell
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
```

#### `policy/teams-purge-hold-lifecycle-mailboxes.sample.json`

```json
{
  "_comment": "Reference definition for the eDiscovery Teams-purge hold lifecycle scenario. Consumed by Get-TeamsPurgeMailboxHoldState.ps1 / Remove-TeamsPurgeMailboxHolds.ps1 via -DefinitionPath. Schema-identical to search-and-purge-teams-messages/deploy/policy/teams-message-purge-search-definition.sample.json's search.targetMailboxes array -- in practice, point -DefinitionPath at that same incident config file so one file drives both scenarios (design.md Section 3 goal 1). Author-only reference for the buyer's own tenant -- replace every value below before use.",
  "case": {
    "displayName": "CONTOSO-TEAMS-2026-014",
    "externalId": "2026-014"
  },
  "search": {
    "targetMailboxes": [
      {
        "email": "payments-team@contoso.com",
        "sourceType": "StandardOrSharedChannel"
      },
      {
        "email": "alex.chen@contoso.com",
        "sourceType": "OneToOneChat"
      },
      {
        "email": "jordan.lee@contoso.com",
        "sourceType": "OneToOneChat"
      }
    ]
  }
}
```

#### `Remove-TeamsPurgeMailboxHolds.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }

<#
.SYNOPSIS
    Removes the scriptable subset of holds/retention policies blocking a Teams-message purge on a
    list of target mailboxes, and records exactly what it changed to a state file for later restore.

.DESCRIPTION
    Re-identifies each mailbox's hold state fresh (does not trust a prior
    Get-TeamsPurgeMailboxHoldState.ps1 report, which may be stale), then removes only the hold types
    this scenario documents as safely scriptable (design.md Section 2):

      Litigation Hold                 -> Set-Mailbox -LitigationHoldEnabled $false
      Mailbox-scoped retention policy -> Set-RetentionCompliancePolicy -RemoveExchangeLocation
                                          ("mbx"/"skp"-prefixed InPlaceHolds only -- Microsoft's own
                                          reference never documents this prefix pair on a group/team
                                          mailbox, and retention-settings.md confirms the Exchange-
                                          mailboxes location flatly rejects one, design.md Section 8)
      Mailbox-scoped Group-location   -> Set-RetentionCompliancePolicy -RemoveModernGroupLocation
      retention policy ("grp"-prefixed,  ("grp"-prefixed InPlaceHolds, not org-wide, on a confirmed
      not org-wide, on a group/team      group/team mailbox only -- the InPlaceHolds notation itself
      mailbox)                           is NOT explicitly confirmed by Microsoft for this specific,
                                          non-org-wide case; disclosed as a VERIFY, not guessed away)
      Organization-wide policy        -> Set-RetentionCompliancePolicy -AddExchangeLocationException
                                          (excludes this one mailbox -- does NOT edit the policy itself)
      Retention-label hold            -> OPT-IN ONLY via -IncludeComplianceTagHold. One-way; no
                                          documented cmdlet restores ComplianceTagHoldApplied to True.
      Pre-existing delay hold         -> Set-Mailbox -RemoveDelayHoldApplied/-RemoveDelayReleaseHoldApplied
                                          (requires the Legal Hold Exchange Online RBAC role)

    Deliberately NEVER removes (design.md Sections 6/7):
      - eDiscovery case holds (UniH-prefixed) -- identify-only; resolving/removing needs eDiscovery
        cmdlets in Security & Compliance PowerShell, the one documented app-only-unsupported
        exception in this repo (docs/automation-surface.md Section 3).
      - Legacy In-Place Holds -- Microsoft's own retirement guidance: not removable for an active
        mailbox.
      - Newer-location (*-AppRetentionCompliancePolicy) policies -- no documented per-mailbox
        applicability check exists.
      - A "grp"-prefixed, non-org-wide InPlaceHolds entry found on a mailbox that is NOT a group/team
        mailbox -- an anomaly no Microsoft Learn citation this scenario carries explains (design.md
        Section 8). Reported as UNRECOGNIZED and left untouched rather than guessed at.

    If ANY non-scriptable hold remains after this script runs (eDiscovery case hold, legacy In-Place
    Hold, or an unconfirmed newer-location policy), the purge will likely still be blocked -- this
    script says so explicitly per mailbox rather than implying success.

    -StatePath is REQUIRED: Restore-TeamsPurgeMailboxHolds.ps1 reads only this file, and only
    restores what this run actually changed (design.md Section 3 goal 3) -- never a wishlist.

    Connect first: Connect-ExchangeOnline AND Connect-IPPSSession (both certificate app-only --
    docs/automation-surface.md Section 3). This script does not open either session.

    Supports -WhatIf/-Confirm (SupportsShouldProcess) for every mutating call, independent of
    Set-RetentionCompliancePolicy's own lack of a functioning -WhatIf.

.PARAMETER DefinitionPath
    Same schema as Get-TeamsPurgeMailboxHoldState.ps1. Mutually exclusive with -Mailbox.

.PARAMETER Mailbox
    Explicit list of mailbox SMTP addresses. Mutually exclusive with -DefinitionPath.

.PARAMETER StatePath
    REQUIRED. Path to write the JSON state file recording exactly what was removed per mailbox.
    Pass this same path to Restore-TeamsPurgeMailboxHolds.ps1 after the purge.

.PARAMETER IncludeComplianceTagHold
    Opt-in: also clear ComplianceTagHoldApplied via -RemoveComplianceTagHoldApplied -ProvideConsent.
    Default is to LEAVE this hold type alone and report it as a blocker requiring a manual decision,
    because clearing it cannot be reversed by this scenario (design.md Section 5).

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-TeamsPurgeMailboxHolds.ps1 -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json `
        -StatePath ./hold-removal-state-2026-014.json -WhatIf

.EXAMPLE
    ./Remove-TeamsPurgeMailboxHolds.ps1 -Mailbox 'payments-team@contoso.com' `
        -StatePath ./hold-removal-state-2026-014.json

.NOTES
    Grounded in Microsoft Learn -- README.md Section 12. Cmdlet shapes confirmed against:
      Set-Mailbox (-LitigationHoldEnabled, -RemoveComplianceTagHoldApplied -ProvideConsent,
        -RemoveDelayHoldApplied, -RemoveDelayReleaseHoldApplied)
      Set-RetentionCompliancePolicy (-RemoveExchangeLocation, -RemoveModernGroupLocation,
        -AddExchangeLocationException)

    VERIFY (pilot tenant or a future Microsoft Learn pass): Microsoft's "Identify Exchange mailbox hold
    types in eDiscovery" reference documents the InPlaceHolds notation for a specific-location
    (mailbox-scoped) retention policy as "mbx"/"skp" only (via Get-Mailbox); it never states what, if
    anything, a specific-location policy scoped to a Microsoft 365 Group mailbox via
    -AddModernGroupLocation stamps on that mailbox's own InPlaceHolds. This script treats a "grp"-
    prefixed, non-org-wide entry found on a confirmed group/team mailbox as exactly that case (the only
    mechanism that could plausibly have produced it, since Exchange-location provably rejects group
    mailboxes -- README.md Section 11) and removes it via -RemoveModernGroupLocation, but the notation
    itself is not explicitly confirmed by Microsoft for this non-org-wide combination.

    Set-RetentionCompliancePolicy causes "a full synchronization across your organization" per
    Microsoft's own reference -- this script calls it once per (policy, mailbox) pair, sequentially;
    for a large target-mailbox list against the same policy, expect this step to be the slowest part
    of the run. Removing a delay hold requires the Legal Hold Exchange Online RBAC role -- README.md
    Section 3.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Definition')]
param(
    [Parameter(ParameterSetName = 'Definition')]
    [string]$DefinitionPath,

    [Parameter(Mandatory, ParameterSetName = 'Mailbox')]
    [string[]]$Mailbox,

    [Parameter(Mandatory)]
    [string]$StatePath,

    [switch]$IncludeComplianceTagHold
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
    if (-not $DefinitionPath) { throw 'Specify either -DefinitionPath or -Mailbox.' }
    if (-not (Test-Path -LiteralPath $DefinitionPath)) { throw "Definition file not found: $DefinitionPath" }
    $def = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json
    $emails = @($def.search.targetMailboxes | ForEach-Object { $_.email })
    if ($emails.Count -eq 0) { throw "No target mailboxes found under .search.targetMailboxes in $DefinitionPath." }
    return $emails
}

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
    # Get-OrganizationConfig (org-wide) table. A "grp"-prefixed entry not found in $OrgWideGroupGuids is
    # kept in its own bucket rather than merged into MailboxScopedPolicyNames and removed with an
    # Exchange-location call that can never have targeted a Group mailbox (design.md Section 8).
    param([string[]]$InPlaceHolds, [string[]]$OrgWideExchangeGuids, [string[]]$OrgWideGroupGuids)
    $result = [ordered]@{
        EDiscoveryHoldGuids            = @()
        LegacyInPlaceHoldGuids         = @()
        MailboxScopedPolicyNames       = @()   # "mbx"/"skp" only
        MailboxScopedGroupPolicyNames  = @()   # "grp", not org-wide -- undocumented notation, disclosed
        OrgWidePolicyNamesOnMbx        = @()
        OrgWideExclusionPolicyNames    = @()
    }
    foreach ($h in @($InPlaceHolds)) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        if ($h -match '^UniH(.+)$') { $result.EDiscoveryHoldGuids += $Matches[1] }
        elseif ($h -match '^-mbx([0-9a-fA-F]{32})$') { $result.OrgWideExclusionPolicyNames += (Resolve-RetentionPolicyName -Guid $Matches[1]) }
        elseif ($h -match '^(mbx|skp)([0-9a-fA-F]{32}):(\d)$') {
            $guid = $Matches[2]
            $name = Resolve-RetentionPolicyName -Guid $guid
            if ($OrgWideExchangeGuids -contains $guid) { $result.OrgWidePolicyNamesOnMbx += $name }
            else { $result.MailboxScopedPolicyNames += $name }
        }
        elseif ($h -match '^grp([0-9a-fA-F]{32}):(\d)$') {
            $guid = $Matches[1]
            $name = Resolve-RetentionPolicyName -Guid $guid
            if ($OrgWideGroupGuids -contains $guid) { $result.OrgWidePolicyNamesOnMbx += $name }
            else { $result.MailboxScopedGroupPolicyNames += $name }
        }
        else { $result.LegacyInPlaceHoldGuids += $h }
    }
    return $result
}

# --- main ---

Assert-ExoConnected
Assert-SccConnected

$mailboxes = Get-TargetMailboxList -DefinitionPath $DefinitionPath -Mailbox $Mailbox
$orgConfig = Get-OrganizationConfig
# "mbx"-prefixed org-wide policies apply to Exchange mailboxes (all mailbox types, incl. 1xN Teams
# chats); "grp"-prefixed org-wide policies apply ONLY to Microsoft 365 Group mailboxes and use a
# different exception parameter (-AddModernGroupLocationException, not -AddExchangeLocationException)
# -- design.md Section 4/8. Never conflate the two.
$orgWideExchangeGuids = @(@($orgConfig.InPlaceHolds) | ForEach-Object { if ($_ -match '^mbx([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })
$orgWideGroupGuids = @(@($orgConfig.InPlaceHolds) | ForEach-Object { if ($_ -match '^grp([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })
$orgWideExchangePolicyNames = @($orgWideExchangeGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ })
$orgWideGroupPolicyNames = @($orgWideGroupGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ })

$state = @{
    generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    mailboxes    = @()
}
$anyUnresolvedBlockers = $false

foreach ($mbx in $mailboxes) {
    Write-Host "`n=== $mbx ===" -ForegroundColor Cyan
    $m = Get-Mailbox -Identity $mbx -ErrorAction SilentlyContinue
    if (-not $m) { Write-Warning "Mailbox not found: $mbx -- skipping."; continue }

    $parsed = ConvertTo-ParsedInPlaceHolds -InPlaceHolds $m.InPlaceHolds -OrgWideExchangeGuids $orgWideExchangeGuids -OrgWideGroupGuids $orgWideGroupGuids
    $isGroupMailbox = $m.RecipientTypeDetails -eq 'GroupMailbox'
    # Org-wide Exchange applicability is gated the same way org-wide Group applicability already is --
    # the Exchange-mailboxes location (org-wide included) never covers a Microsoft 365 Group mailbox
    # (design.md Section 8).
    $applicableOrgWideExchange = if (-not $isGroupMailbox) {
        @($orgWideExchangePolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    } else { @() }
    $applicableOrgWideGroup = if ($isGroupMailbox) {
        @($orgWideGroupPolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    } else { @() }
    $mailboxScoped = @($parsed.MailboxScopedPolicyNames + $parsed.OrgWidePolicyNamesOnMbx | Select-Object -Unique)
    # A "grp"-prefixed, non-org-wide entry is only plausible on a group/team mailbox itself; on any
    # other mailbox it's an unexplained anomaly -- never routed through either removal mechanism.
    $mailboxScopedGroup = if ($isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }
    $unrecognizedPolicyNames = if (-not $isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }

    $entry = [ordered]@{
        mailbox                     = $mbx
        litigationHoldRemoved       = $false
        mailboxScopedPoliciesRemoved = @()
        mailboxScopedGroupPoliciesRemoved = @()
        orgWideExceptionsAdded      = @()   # array of { name, kind: 'Exchange'|'Group' }
        complianceTagHoldCleared    = $false
        delayHoldsCleared           = @()
        ediscoveryHoldsNotRemoved   = $parsed.EDiscoveryHoldGuids
        legacyInPlaceHoldsNotRemoved = $parsed.LegacyInPlaceHoldGuids
        unrecognizedPolicyGuidsNotRemoved = $unrecognizedPolicyNames
        complianceTagHoldSkipped    = $false
    }

    if ($m.LitigationHoldEnabled) {
        if ($PSCmdlet.ShouldProcess($mbx, 'Set-Mailbox -LitigationHoldEnabled $false')) {
            Set-Mailbox -Identity $mbx -LitigationHoldEnabled $false -Confirm:$false
            $entry.litigationHoldRemoved = $true
            Write-Host '  [removed] Litigation Hold'
        }
    }

    foreach ($policyName in $mailboxScoped) {
        if ($policyName -like '<unresolved:*') { Write-Warning "  Could not resolve policy name for a mailbox-scoped hold on $mbx ($policyName) -- not removed."; $anyUnresolvedBlockers = $true; continue }
        if ($PSCmdlet.ShouldProcess($mbx, "Set-RetentionCompliancePolicy -Identity '$policyName' -RemoveExchangeLocation")) {
            Set-RetentionCompliancePolicy -Identity $policyName -RemoveExchangeLocation $mbx -Confirm:$false | Out-Null
            $entry.mailboxScopedPoliciesRemoved += $policyName
            Write-Host "  [removed] mailbox-scoped retention policy '$policyName'"
        }
    }

    foreach ($policyName in $mailboxScopedGroup) {
        if ($policyName -like '<unresolved:*') { Write-Warning "  Could not resolve policy name for a mailbox-scoped Group-location hold on $mbx ($policyName) -- not removed."; $anyUnresolvedBlockers = $true; continue }
        Write-Warning "  $mbx has a mailbox-scoped Group-location retention policy ('$policyName') -- the InPlaceHolds notation for this non-org-wide case isn't explicitly confirmed by Microsoft (README.md Section 11); removing via -RemoveModernGroupLocation as the only plausible mechanism, not a guess by analogy."
        if ($PSCmdlet.ShouldProcess($mbx, "Set-RetentionCompliancePolicy -Identity '$policyName' -RemoveModernGroupLocation")) {
            Set-RetentionCompliancePolicy -Identity $policyName -RemoveModernGroupLocation $mbx -Confirm:$false | Out-Null
            $entry.mailboxScopedGroupPoliciesRemoved += $policyName
            Write-Host "  [removed] mailbox-scoped Group-location retention policy '$policyName'"
        }
    }

    if ($unrecognizedPolicyNames.Count -gt 0) {
        Write-Warning "  $mbx has 'grp'-prefixed InPlaceHolds entry/entries NOT removed by this script because this mailbox is not a group/team mailbox -- no citation this scenario carries explains this case (design.md Section 8): $($unrecognizedPolicyNames -join ', ')"
        $anyUnresolvedBlockers = $true
    }

    foreach ($policyName in $applicableOrgWideExchange) {
        if ($policyName -like '<unresolved:*') { Write-Warning "  Could not resolve org-wide Exchange policy name for $mbx ($policyName) -- exception not added."; $anyUnresolvedBlockers = $true; continue }
        if ($PSCmdlet.ShouldProcess($mbx, "Set-RetentionCompliancePolicy -Identity '$policyName' -AddExchangeLocationException")) {
            Set-RetentionCompliancePolicy -Identity $policyName -AddExchangeLocationException $mbx -Confirm:$false | Out-Null
            $entry.orgWideExceptionsAdded += [pscustomobject]@{ name = $policyName; kind = 'Exchange' }
            Write-Host "  [excepted] organization-wide Exchange retention policy '$policyName'"
        }
    }
    foreach ($policyName in $applicableOrgWideGroup) {
        if ($policyName -like '<unresolved:*') { Write-Warning "  Could not resolve org-wide Group policy name for $mbx ($policyName) -- exception not added."; $anyUnresolvedBlockers = $true; continue }
        if ($PSCmdlet.ShouldProcess($mbx, "Set-RetentionCompliancePolicy -Identity '$policyName' -AddModernGroupLocationException")) {
            Set-RetentionCompliancePolicy -Identity $policyName -AddModernGroupLocationException $mbx -Confirm:$false | Out-Null
            $entry.orgWideExceptionsAdded += [pscustomobject]@{ name = $policyName; kind = 'Group' }
            Write-Host "  [excepted] organization-wide Group retention policy '$policyName' (group/team mailbox)"
        }
    }

    if ($m.ComplianceTagHoldApplied) {
        if ($IncludeComplianceTagHold) {
            Write-Warning "  ComplianceTagHoldApplied clear on $mbx is ONE-WAY -- no documented cmdlet restores it (design.md Section 5)."
            if ($PSCmdlet.ShouldProcess($mbx, 'Set-Mailbox -RemoveComplianceTagHoldApplied -ProvideConsent (IRREVERSIBLE)')) {
                Set-Mailbox -Identity $mbx -RemoveComplianceTagHoldApplied -ProvideConsent -Confirm:$false
                $entry.complianceTagHoldCleared = $true
                Write-Host '  [cleared, IRREVERSIBLE] retention-label hold (ComplianceTagHoldApplied)'
            }
        } else {
            Write-Warning "  $mbx has ComplianceTagHoldApplied=true (retention-label hold) -- NOT cleared (pass -IncludeComplianceTagHold to opt in; this is a one-way action, design.md Section 5). Purge will likely remain blocked for this mailbox."
            $entry.complianceTagHoldSkipped = $true
            $anyUnresolvedBlockers = $true
        }
    }

    if ($m.DelayHoldApplied) {
        if ($PSCmdlet.ShouldProcess($mbx, 'Set-Mailbox -RemoveDelayHoldApplied')) {
            Set-Mailbox -Identity $mbx -RemoveDelayHoldApplied -Confirm:$false
            $entry.delayHoldsCleared += 'DelayHoldApplied'
            Write-Host '  [cleared] pre-existing delay hold (DelayHoldApplied)'
        }
    }
    if ($m.DelayReleaseHoldApplied) {
        if ($PSCmdlet.ShouldProcess($mbx, 'Set-Mailbox -RemoveDelayReleaseHoldApplied')) {
            Set-Mailbox -Identity $mbx -RemoveDelayReleaseHoldApplied -Confirm:$false
            $entry.delayHoldsCleared += 'DelayReleaseHoldApplied'
            Write-Host '  [cleared] pre-existing delay hold (DelayReleaseHoldApplied)'
        }
    }

    if ($parsed.EDiscoveryHoldGuids.Count -gt 0) {
        Write-Warning "  $mbx has eDiscovery case hold(s) NOT removed by this script: $($parsed.EDiscoveryHoldGuids -join ', '). Resolve/turn off manually (README.md Section 5) -- design.md Section 6."
        $anyUnresolvedBlockers = $true
    }
    if ($parsed.LegacyInPlaceHoldGuids.Count -gt 0) {
        Write-Warning "  $mbx has legacy In-Place Hold(s) NOT removable by this script: $($parsed.LegacyInPlaceHoldGuids -join ', ') -- design.md Section 2."
        $anyUnresolvedBlockers = $true
    }

    $state.mailboxes += [pscustomobject]$entry
}

$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding utf8
Write-Host "`nState written to $StatePath -- pass this same path to Restore-TeamsPurgeMailboxHolds.ps1 after the purge." -ForegroundColor Cyan

if ($anyUnresolvedBlockers) {
    Write-Warning 'At least one mailbox still has a hold this script cannot remove (eDiscovery case hold, legacy In-Place Hold, an unresolved policy name, or a skipped retention-label hold). Re-run ./Get-TeamsPurgeMailboxHoldState.ps1 to confirm BlocksPurge before proceeding to the purge step.'
}
```

#### `Restore-TeamsPurgeMailboxHolds.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }

<#
.SYNOPSIS
    Reapplies exactly the holds/retention policies that Remove-TeamsPurgeMailboxHolds.ps1 removed,
    reading only its state file -- never a fresh identify pass, so a partial removal restores exactly
    what actually changed.

.DESCRIPTION
    Reverses, per mailbox, each field Remove-TeamsPurgeMailboxHolds.ps1 recorded as true/non-empty:

      litigationHoldRemoved        -> Set-Mailbox -LitigationHoldEnabled $true
      mailboxScopedPoliciesRemoved -> Set-RetentionCompliancePolicy -AddExchangeLocation (per policy)
      mailboxScopedGroupPoliciesRemoved -> Set-RetentionCompliancePolicy -AddModernGroupLocation (per
                                            policy -- "grp"-prefixed, not org-wide, group/team mailbox
                                            only; design.md Section 8)
      orgWideExceptionsAdded       -> Set-RetentionCompliancePolicy -RemoveExchangeLocationException (per policy)

    unrecognizedPolicyGuidsNotRemoved was never removed by this scenario (a "grp"-prefixed InPlaceHolds
    entry on a non-group mailbox no citation explains -- design.md Section 8), so there is nothing to
    restore for it -- printed as a reminder only.

    Before each Add/Remove call, checks the mailbox's current InPlaceHolds state and skips (with a
    message, not silently) if it's already in the target state -- Set-RetentionCompliancePolicy causes
    "a full synchronization across your organization" per Microsoft's own reference, so this script
    avoids redundant calls where it can confirm one isn't needed.

    complianceTagHoldCleared and delayHoldsCleared are reported but NEVER acted on:
      - complianceTagHoldCleared: no documented cmdlet sets ComplianceTagHoldApplied back to True
        (design.md Section 5) -- this script prints a reminder, nothing more.
      - delayHoldsCleared: delay holds are system-managed (the Managed Folder Assistant re-applies
        one automatically if it detects the underlying hold is back and content is still pending
        removal) -- nothing to script.

    ediscoveryHoldsNotRemoved / legacyInPlaceHoldsNotRemoved were never removed by this scenario, so
    there is nothing to restore for them -- printed as a reminder only, in case the operator separately
    turned an eDiscovery case hold off via the portal and needs to remember to turn it back on.

    Connect first: Connect-ExchangeOnline AND Connect-IPPSSession (both certificate app-only --
    docs/automation-surface.md Section 3). This script does not open either session.

    Supports -WhatIf/-Confirm (SupportsShouldProcess).

.PARAMETER StatePath
    REQUIRED. The state file written by Remove-TeamsPurgeMailboxHolds.ps1.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Restore-TeamsPurgeMailboxHolds.ps1 -StatePath ./hold-removal-state-2026-014.json -WhatIf

.EXAMPLE
    ./Restore-TeamsPurgeMailboxHolds.ps1 -StatePath ./hold-removal-state-2026-014.json

.NOTES
    Grounded in Microsoft Learn -- README.md Section 12. Run this as soon as the purge is validated
    (validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1) -- Microsoft notes that reapplying a hold
    within 24 hours of a Teams purge can still preserve the mailbox's compliance copy from background
    deletion, a reason to treat this step as time-sensitive, not a background chore
    (search-and-purge-teams-messages/README.md Section 6).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$StatePath
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

$script:PolicyNameCache = @{}
function Resolve-RetentionPolicyName {
    # Same resolution logic as Get-/Remove-TeamsPurgeMailboxHolds.ps1, needed here to interpret the
    # mailbox's CURRENT InPlaceHolds state before deciding whether a restore call is redundant.
    param([string]$Guid)
    if ($script:PolicyNameCache.ContainsKey($Guid)) { return $script:PolicyNameCache[$Guid] }
    $policy = Get-RetentionCompliancePolicy -Identity $Guid -DistributionDetail -ErrorAction SilentlyContinue
    $name = if ($policy) { $policy.Name } else { "<unresolved:$Guid>" }
    $script:PolicyNameCache[$Guid] = $name
    return $name
}

function Get-CurrentPolicyMembership {
    # Parses a mailbox's live InPlaceHolds into policy-name sets, the same prefix convention used by
    # Get-/Remove-TeamsPurgeMailboxHolds.ps1 (design.md Section 4) -- deliberately NOT relying on an
    # unconfirmed .Guid property on Get-RetentionCompliancePolicy's output (Microsoft's own reference
    # documents only Name/Workload/Enabled/Mode as default-displayed properties). "mbx"/"skp" (Exchange-
    # location) and "grp" (Group-location) are tracked in separate sets -- never merged, matching the
    # same distinction Get-/Remove- already draw (design.md Section 8).
    param($Mailbox)
    $scoped = @()
    $scopedGroup = @()
    $excluded = @()
    foreach ($h in @($Mailbox.InPlaceHolds)) {
        if ($h -match '^-mbx([0-9a-fA-F]{32})$') { $excluded += (Resolve-RetentionPolicyName -Guid $Matches[1]) }
        elseif ($h -match '^(mbx|skp)([0-9a-fA-F]{32}):(\d)$') { $scoped += (Resolve-RetentionPolicyName -Guid $Matches[2]) }
        elseif ($h -match '^grp([0-9a-fA-F]{32}):(\d)$') { $scopedGroup += (Resolve-RetentionPolicyName -Guid $Matches[1]) }
    }
    return [pscustomobject]@{ ScopedPolicyNames = $scoped; ScopedGroupPolicyNames = $scopedGroup; ExcludedPolicyNames = $excluded }
}

# --- main ---

Assert-ExoConnected
Assert-SccConnected

if (-not (Test-Path -LiteralPath $StatePath)) { throw "State file not found: $StatePath" }
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json

if (@($state.mailboxes).Count -eq 0) {
    Write-Host 'State file has no mailbox entries -- nothing to restore.'
    return
}

foreach ($entry in $state.mailboxes) {
    Write-Host "`n=== $($entry.mailbox) ===" -ForegroundColor Cyan
    $m = Get-Mailbox -Identity $entry.mailbox -ErrorAction SilentlyContinue
    if (-not $m) { Write-Warning "Mailbox not found: $($entry.mailbox) -- skipping restore for this entry."; continue }

    if ($entry.litigationHoldRemoved) {
        if ($m.LitigationHoldEnabled) {
            Write-Host '  Litigation Hold already enabled -- skipping.'
        }
        elseif ($PSCmdlet.ShouldProcess($entry.mailbox, 'Set-Mailbox -LitigationHoldEnabled $true')) {
            Set-Mailbox -Identity $entry.mailbox -LitigationHoldEnabled $true -Confirm:$false
            Write-Host '  [restored] Litigation Hold'
        }
    }

    $current = Get-CurrentPolicyMembership -Mailbox $m

    foreach ($policyName in @($entry.mailboxScopedPoliciesRemoved)) {
        if ($current.ScopedPolicyNames -contains $policyName) {
            Write-Host "  Mailbox already back in '$policyName' -- skipping."
        }
        elseif ($PSCmdlet.ShouldProcess($entry.mailbox, "Set-RetentionCompliancePolicy -Identity '$policyName' -AddExchangeLocation")) {
            Set-RetentionCompliancePolicy -Identity $policyName -AddExchangeLocation $entry.mailbox -Confirm:$false | Out-Null
            Write-Host "  [restored] mailbox-scoped retention policy '$policyName'"
        }
    }

    foreach ($policyName in @($entry.mailboxScopedGroupPoliciesRemoved)) {
        if ($current.ScopedGroupPolicyNames -contains $policyName) {
            Write-Host "  Mailbox already back in Group-location policy '$policyName' -- skipping."
        }
        elseif ($PSCmdlet.ShouldProcess($entry.mailbox, "Set-RetentionCompliancePolicy -Identity '$policyName' -AddModernGroupLocation")) {
            Set-RetentionCompliancePolicy -Identity $policyName -AddModernGroupLocation $entry.mailbox -Confirm:$false | Out-Null
            Write-Host "  [restored] mailbox-scoped Group-location retention policy '$policyName'"
        }
    }

    foreach ($exception in @($entry.orgWideExceptionsAdded)) {
        # Remove-TeamsPurgeMailboxHolds.ps1 records { name, kind: 'Exchange'|'Group' } -- 'grp'-prefixed
        # org-wide Group policies use -RemoveModernGroupLocationException, not the Exchange-location
        # parameter (design.md Section 4/8). Never conflate the two.
        $policyName = $exception.name
        if ($exception.kind -eq 'Group') {
            # No confirmed InPlaceHolds notation for a Group-location exclusion was found during this
            # build's grounding pass (README.md Section 11) -- always attempt the restore call rather
            # than guess a skip-check pattern that could silently leave a real exception in place.
            if ($PSCmdlet.ShouldProcess($entry.mailbox, "Set-RetentionCompliancePolicy -Identity '$policyName' -RemoveModernGroupLocationException")) {
                Set-RetentionCompliancePolicy -Identity $policyName -RemoveModernGroupLocationException $entry.mailbox -Confirm:$false | Out-Null
                Write-Host "  [restored] removed Group exception from organization-wide policy '$policyName'"
            }
        }
        elseif ($current.ExcludedPolicyNames -notcontains $policyName) {
            Write-Host "  Mailbox already back under '$policyName' (no exception present) -- skipping."
        }
        elseif ($PSCmdlet.ShouldProcess($entry.mailbox, "Set-RetentionCompliancePolicy -Identity '$policyName' -RemoveExchangeLocationException")) {
            Set-RetentionCompliancePolicy -Identity $policyName -RemoveExchangeLocationException $entry.mailbox -Confirm:$false | Out-Null
            Write-Host "  [restored] removed Exchange exception from organization-wide policy '$policyName'"
        }
    }

    if ($entry.complianceTagHoldCleared) {
        Write-Warning "  $($entry.mailbox): ComplianceTagHoldApplied was cleared and CANNOT be restored by this script -- no documented cmdlet exists (design.md Section 5). It will be re-set automatically only if a retention label is newly applied to a folder/item in this mailbox."
    }
    if (@($entry.delayHoldsCleared).Count -gt 0) {
        Write-Host "  $($entry.mailbox): a pre-existing delay hold ($($entry.delayHoldsCleared -join ', ')) was cleared earlier -- system-managed, nothing to restore."
    }
    if (@($entry.ediscoveryHoldsNotRemoved).Count -gt 0) {
        Write-Host "  $($entry.mailbox): eDiscovery case hold(s) were never removed by this scenario ($($entry.ediscoveryHoldsNotRemoved -join ', ')) -- if you separately turned one off in the portal, remember to turn it back on there." -ForegroundColor Yellow
    }
    if (@($entry.unrecognizedPolicyGuidsNotRemoved).Count -gt 0) {
        Write-Host "  $($entry.mailbox): unrecognized 'grp'-prefixed polic(y/ies) were never removed by this scenario ($($entry.unrecognizedPolicyGuidsNotRemoved -join ', ')) -- design.md Section 8; nothing to restore." -ForegroundColor Yellow
    }
}

Write-Host "`nRestore pass complete. Confirm with ./validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1 -StatePath $StatePath." -ForegroundColor Cyan
```