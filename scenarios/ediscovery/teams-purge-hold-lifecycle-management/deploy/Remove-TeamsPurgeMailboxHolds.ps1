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
      Set-RetentionCompliancePolicy (-RemoveExchangeLocation, -AddExchangeLocationException)

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
    param([string[]]$InPlaceHolds, [string[]]$OrgWideGuids)
    $result = [ordered]@{
        EDiscoveryHoldGuids         = @()
        LegacyInPlaceHoldGuids      = @()
        MailboxScopedPolicyNames    = @()
        OrgWidePolicyNamesOnMbx     = @()
        OrgWideExclusionPolicyNames = @()
    }
    foreach ($h in @($InPlaceHolds)) {
        if ([string]::IsNullOrWhiteSpace($h)) { continue }
        if ($h -match '^UniH(.+)$') { $result.EDiscoveryHoldGuids += $Matches[1] }
        elseif ($h -match '^-mbx([0-9a-fA-F]{32})$') { $result.OrgWideExclusionPolicyNames += (Resolve-RetentionPolicyName -Guid $Matches[1]) }
        elseif ($h -match '^(mbx|skp|grp)([0-9a-fA-F]{32}):(\d)$') {
            $guid = $Matches[2]
            $name = Resolve-RetentionPolicyName -Guid $guid
            if ($OrgWideGuids -contains $guid) { $result.OrgWidePolicyNamesOnMbx += $name }
            else { $result.MailboxScopedPolicyNames += $name }
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
$orgWideGuids = @($orgWideExchangeGuids + $orgWideGroupGuids)
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

    $parsed = ConvertTo-ParsedInPlaceHolds -InPlaceHolds $m.InPlaceHolds -OrgWideGuids $orgWideGuids
    $isGroupMailbox = $m.RecipientTypeDetails -eq 'GroupMailbox'
    $applicableOrgWideExchange = @($orgWideExchangePolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    $applicableOrgWideGroup = if ($isGroupMailbox) {
        @($orgWideGroupPolicyNames | Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
    } else { @() }
    $mailboxScoped = @($parsed.MailboxScopedPolicyNames + $parsed.OrgWidePolicyNamesOnMbx | Select-Object -Unique)

    $entry = [ordered]@{
        mailbox                     = $mbx
        litigationHoldRemoved       = $false
        mailboxScopedPoliciesRemoved = @()
        orgWideExceptionsAdded      = @()   # array of { name, kind: 'Exchange'|'Group' }
        complianceTagHoldCleared    = $false
        delayHoldsCleared           = @()
        ediscoveryHoldsNotRemoved   = $parsed.EDiscoveryHoldGuids
        legacyInPlaceHoldsNotRemoved = $parsed.LegacyInPlaceHoldGuids
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
