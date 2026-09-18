---
part: "validate"
parent: "ediscovery/teams-purge-hold-lifecycle-management"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-TeamsPurgeMailboxHoldLifecycle.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }

<#
.SYNOPSIS
    Validates this scenario's two use modes: (1) pre-purge readiness -- do any target mailboxes still
    have a scriptable-or-not blocking hold; or (2) post-restore -- did Restore-TeamsPurgeMailboxHolds.ps1
    actually put back everything Remove-TeamsPurgeMailboxHolds.ps1 removed. Read-only.

.DESCRIPTION
    Mode 1 (pre-purge readiness) -- pass -DefinitionPath or -Mailbox, no -StatePath:
      Re-identifies each mailbox's hold state (same logic as Get-TeamsPurgeMailboxHoldState.ps1) and
      reports [PASS] (no blocking hold identified) or [FAIL] (a blocking hold remains) per mailbox.
      [FAIL] here does not necessarily mean this scenario's own Remove script can fix it -- an
      eDiscovery case hold or legacy In-Place Hold FAILs here but is never scriptable (design.md
      Sections 2/6).

    Mode 2 (post-restore) -- pass -StatePath (the file Remove-TeamsPurgeMailboxHolds.ps1 wrote):
      For each mailbox entry, re-checks current state against what the state file recorded as
      removed, and reports [PASS] (restored), [FAIL] (still missing -- Restore script may not have
      run, or failed partway), or [WARN] for the two fields this scenario cannot restore
      (complianceTagHoldCleared, ediscoveryHoldsNotRemoved/legacyInPlaceHoldsNotRemoved -- reported
      for awareness, never scored as a failure since there is nothing this scenario claims to fix
      here).

    Exits non-zero on any [FAIL].

    Connect first: Connect-ExchangeOnline AND Connect-IPPSSession (both certificate app-only --
    docs/automation-surface.md Section 3).

.PARAMETER DefinitionPath
    Mode 1. Same schema as Get-TeamsPurgeMailboxHoldState.ps1. Mutually exclusive with -StatePath/-Mailbox.

.PARAMETER Mailbox
    Mode 1. Explicit mailbox list. Mutually exclusive with -StatePath/-DefinitionPath.

.PARAMETER StatePath
    Mode 2. The state file written by Remove-TeamsPurgeMailboxHolds.ps1.

.EXAMPLE
    ./Test-TeamsPurgeMailboxHoldLifecycle.ps1 -DefinitionPath ../deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json

.EXAMPLE
    ./Test-TeamsPurgeMailboxHoldLifecycle.ps1 -StatePath ./hold-removal-state-2026-014.json

.NOTES
    See README.md Section 12 for the shared Microsoft Learn citation list.
#>
[CmdletBinding(DefaultParameterSetName = 'Definition')]
param(
    [Parameter(ParameterSetName = 'Definition')]
    [string]$DefinitionPath,

    [Parameter(Mandatory, ParameterSetName = 'Mailbox')]
    [string[]]$Mailbox,

    [Parameter(Mandatory, ParameterSetName = 'State')]
    [string]$StatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FailCount = 0
$script:WarnCount = 0
function Write-Check {
    param([string]$Message, [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Level)
    $prefix = "[$Level]"
    switch ($Level) {
        'PASS' { Write-Host "$prefix $Message" -ForegroundColor Green }
        'WARN' { Write-Host "$prefix $Message" -ForegroundColor Yellow; $script:WarnCount++ }
        'FAIL' { Write-Host "$prefix $Message" -ForegroundColor Red; $script:FailCount++ }
    }
}

if (-not (Get-Command Get-Mailbox -ErrorAction SilentlyContinue)) {
    throw 'Exchange Online PowerShell cmdlets not found. Connect first: Connect-ExchangeOnline. See docs/automation-surface.md Section 3.'
}
if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw 'Security & Compliance PowerShell cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3.'
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
    # kept in its own bucket rather than merged into MailboxScopedPolicyNames (design.md Section 8).
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

$orgConfig = Get-OrganizationConfig
# "mbx"-prefixed org-wide policies apply to all Exchange mailboxes; "grp"-prefixed apply ONLY to
# Microsoft 365 Group mailboxes -- never conflate the two (design.md Section 4/8).
$orgWideExchangeGuids = @(@($orgConfig.InPlaceHolds) | ForEach-Object { if ($_ -match '^mbx([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })
$orgWideGroupGuids = @(@($orgConfig.InPlaceHolds) | ForEach-Object { if ($_ -match '^grp([0-9a-fA-F]{32}):(\d)$') { $Matches[1] } } | Where-Object { $_ })

if ($PSCmdlet.ParameterSetName -eq 'State') {
    # --- Mode 2: post-restore validation ---
    if (-not (Test-Path -LiteralPath $StatePath)) { throw "State file not found: $StatePath" }
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json

    foreach ($entry in $state.mailboxes) {
        Write-Host "`n--- $($entry.mailbox) ---" -ForegroundColor Cyan
        $m = Get-Mailbox -Identity $entry.mailbox -ErrorAction SilentlyContinue
        if (-not $m) { Write-Check "Mailbox not found: $($entry.mailbox)" -Level FAIL; continue }
        $parsed = ConvertTo-ParsedInPlaceHolds -InPlaceHolds $m.InPlaceHolds -OrgWideExchangeGuids $orgWideExchangeGuids -OrgWideGroupGuids $orgWideGroupGuids

        if ($entry.litigationHoldRemoved) {
            if ($m.LitigationHoldEnabled) { Write-Check 'Litigation Hold restored.' -Level PASS }
            else { Write-Check 'Litigation Hold NOT restored (still disabled).' -Level FAIL }
        }
        foreach ($policyName in @($entry.mailboxScopedPoliciesRemoved)) {
            if ($parsed.MailboxScopedPolicyNames -contains $policyName -or $parsed.OrgWidePolicyNamesOnMbx -contains $policyName) {
                Write-Check "Mailbox-scoped retention policy '$policyName' restored." -Level PASS
            } else {
                Write-Check "Mailbox-scoped retention policy '$policyName' NOT restored." -Level FAIL
            }
        }
        foreach ($policyName in @($entry.mailboxScopedGroupPoliciesRemoved)) {
            if ($parsed.MailboxScopedGroupPolicyNames -contains $policyName -or $parsed.OrgWidePolicyNamesOnMbx -contains $policyName) {
                Write-Check "Mailbox-scoped Group-location retention policy '$policyName' restored." -Level PASS
            } else {
                Write-Check "Mailbox-scoped Group-location retention policy '$policyName' NOT restored." -Level FAIL
            }
        }
        if (@($entry.unrecognizedPolicyGuidsNotRemoved).Count -gt 0) {
            Write-Check "This mailbox had 'grp'-prefixed InPlaceHolds entry/entries this scenario never touched (design.md Section 8) -- confirm their state separately." -Level WARN
        }
        foreach ($exception in @($entry.orgWideExceptionsAdded)) {
            $policyName = $exception.name
            if ($exception.kind -eq 'Group') {
                # No confirmed InPlaceHolds notation for a Group-location exclusion was found during
                # this build's grounding pass -- cannot score PASS/FAIL, only confirm the restore
                # call ran (Restore-TeamsPurgeMailboxHolds.ps1's own output) -- README.md Section 11.
                Write-Check "Organization-wide Group policy exception for '$policyName' -- cannot verify from InPlaceHolds (design.md Section 4/8); confirm via Restore-TeamsPurgeMailboxHolds.ps1's own run output or the Purview portal." -Level WARN
            }
            elseif ($parsed.OrgWideExclusionPolicyNames -notcontains $policyName) {
                Write-Check "Organization-wide Exchange policy exception for '$policyName' removed (mailbox back under the policy)." -Level PASS
            } else {
                Write-Check "Organization-wide Exchange policy exception for '$policyName' still present -- mailbox NOT restored." -Level FAIL
            }
        }
        if ($entry.complianceTagHoldCleared) {
            Write-Check "ComplianceTagHoldApplied was cleared for this mailbox and cannot be restored by this scenario (design.md Section 5) -- not scored as a failure." -Level WARN
        }
        if (@($entry.ediscoveryHoldsNotRemoved).Count -gt 0 -or @($entry.legacyInPlaceHoldsNotRemoved).Count -gt 0) {
            Write-Check "This mailbox had non-scriptable holds this scenario never touched (eDiscovery case hold and/or legacy In-Place Hold) -- confirm their state separately." -Level WARN
        }
    }
} else {
    # --- Mode 1: pre-purge readiness ---
    if ($Mailbox) { $mailboxes = $Mailbox }
    else {
        if (-not $DefinitionPath) { throw 'Specify -DefinitionPath, -Mailbox, or -StatePath.' }
        if (-not (Test-Path -LiteralPath $DefinitionPath)) { throw "Definition file not found: $DefinitionPath" }
        $def = Get-Content -LiteralPath $DefinitionPath -Raw | ConvertFrom-Json
        $mailboxes = @($def.search.targetMailboxes | ForEach-Object { $_.email })
    }

    foreach ($mbx in $mailboxes) {
        Write-Host "`n--- $mbx ---" -ForegroundColor Cyan
        $m = Get-Mailbox -Identity $mbx -ErrorAction SilentlyContinue
        if (-not $m) { Write-Check "Mailbox not found: $mbx" -Level FAIL; continue }
        $parsed = ConvertTo-ParsedInPlaceHolds -InPlaceHolds $m.InPlaceHolds -OrgWideExchangeGuids $orgWideExchangeGuids -OrgWideGroupGuids $orgWideGroupGuids
        $isGroupMailbox = $m.RecipientTypeDetails -eq 'GroupMailbox'
        # Org-wide Exchange applicability is gated the same way org-wide Group applicability already is
        # -- the Exchange-mailboxes location (org-wide included) never covers a Microsoft 365 Group
        # mailbox (design.md Section 8).
        $applicableOrgWideExchange = if (-not $isGroupMailbox) {
            @($orgWideExchangeGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ } |
                Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
        } else { @() }
        $applicableOrgWideGroup = if ($isGroupMailbox) {
            @($orgWideGroupGuids | Select-Object -Unique | ForEach-Object { Resolve-RetentionPolicyName -Guid $_ } |
                Where-Object { $parsed.OrgWideExclusionPolicyNames -notcontains $_ })
        } else { @() }
        $applicableOrgWide = @($applicableOrgWideExchange + $applicableOrgWideGroup)
        $mailboxScopedGroup = if ($isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }
        $unrecognizedPolicyNames = if (-not $isGroupMailbox) { $parsed.MailboxScopedGroupPolicyNames } else { @() }

        $blockers = @()
        if ($m.LitigationHoldEnabled) { $blockers += 'Litigation Hold' }
        if ($parsed.EDiscoveryHoldGuids.Count -gt 0) { $blockers += "eDiscovery case hold(s): $($parsed.EDiscoveryHoldGuids -join ', ')" }
        if ($parsed.LegacyInPlaceHoldGuids.Count -gt 0) { $blockers += "legacy In-Place Hold(s): $($parsed.LegacyInPlaceHoldGuids -join ', ')" }
        if ($parsed.MailboxScopedPolicyNames.Count -gt 0) { $blockers += "mailbox-scoped polic(y/ies): $($parsed.MailboxScopedPolicyNames -join ', ')" }
        if ($mailboxScopedGroup.Count -gt 0) { $blockers += "mailbox-scoped Group-location polic(y/ies): $($mailboxScopedGroup -join ', ')" }
        if ($unrecognizedPolicyNames.Count -gt 0) { $blockers += "UNRECOGNIZED 'grp'-prefixed polic(y/ies) on a non-group mailbox: $($unrecognizedPolicyNames -join ', ')" }
        if ($parsed.OrgWidePolicyNamesOnMbx.Count -gt 0) { $blockers += "org-wide polic(y/ies) stamped on mailbox: $($parsed.OrgWidePolicyNamesOnMbx -join ', ')" }
        if ($applicableOrgWide.Count -gt 0) { $blockers += "applicable org-wide polic(y/ies): $($applicableOrgWide -join ', ')" }
        if ($m.ComplianceTagHoldApplied) { $blockers += 'retention-label hold (ComplianceTagHoldApplied)' }
        if ($m.DelayHoldApplied -or $m.DelayReleaseHoldApplied) { $blockers += 'delay hold' }

        if ($blockers.Count -eq 0) {
            Write-Check 'No blocking hold identified -- ready for the Teams purge as far as this scenario can confirm.' -Level PASS
        } else {
            Write-Check "Blocking hold(s) present: $($blockers -join '; ')" -Level FAIL
        }
    }
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
Write-Host 'Reminder: this script cannot see whether a newer-location (*-AppRetentionCompliancePolicy) policy applies to any mailbox above -- design.md Section 7. A [PASS]/no-blockers result is not a guarantee against that class of policy.'
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```