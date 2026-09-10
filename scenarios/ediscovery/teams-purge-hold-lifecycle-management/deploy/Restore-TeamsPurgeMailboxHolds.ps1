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
      orgWideExceptionsAdded       -> Set-RetentionCompliancePolicy -RemoveExchangeLocationException (per policy)

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
    # documents only Name/Workload/Enabled/Mode as default-displayed properties).
    param($Mailbox)
    $scoped = @()
    $excluded = @()
    foreach ($h in @($Mailbox.InPlaceHolds)) {
        if ($h -match '^-mbx([0-9a-fA-F]{32})$') { $excluded += (Resolve-RetentionPolicyName -Guid $Matches[1]) }
        elseif ($h -match '^(mbx|skp)([0-9a-fA-F]{32}):(\d)$') { $scoped += (Resolve-RetentionPolicyName -Guid $Matches[2]) }
    }
    return [pscustomobject]@{ ScopedPolicyNames = $scoped; ExcludedPolicyNames = $excluded }
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
}

Write-Host "`nRestore pass complete. Confirm with ./validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1 -StatePath $StatePath." -ForegroundColor Cyan
