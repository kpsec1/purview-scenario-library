#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Reconciles Microsoft Purview audit log retention policies against a version-controlled JSON
    config, using Security & Compliance PowerShell.

.DESCRIPTION
    For each named policy in the config file, this script:
      1. Validates the entry (name/description length limits, RetentionDuration enum,
         Operations-requires-exactly-one-RecordTypes rule, Priority range).
      2. Checks the Priority against every OTHER live policy in the tenant and every other entry
         in this config, and refuses to proceed on any collision (Priority must be tenant-wide
         unique, per Microsoft's documentation).
      3. Checks the total policy count (existing + net-new) against the tenant's 50-policy cap.
      4. For each entry: if a policy with that Name already exists, compares live settings to the
         config and calls Set-UnifiedAuditLogRetentionPolicy only if they differ (full-replace
         semantics); otherwise calls New-UnifiedAuditLogRetentionPolicy.

    All validation happens before any write - a single invalid or colliding entry stops the whole
    run rather than partially applying the config. See design.md Section 4 for the reconciliation
    flow and Section 2/5 for why this script cannot create the five portal-only durations
    (7 Days / 30 Days / 3 Years / 5 Years / 7 Years).

.PARAMETER ConfigPath
    Path to a JSON config file shaped like deploy/config/audit-retention-policies.sample.json.

.PARAMETER WhatIf
    Reports every create/update this run would perform. Makes no changes.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./deploy/New-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json -WhatIf

.EXAMPLE
    ./deploy/New-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json

.NOTES
    Grounded against (all fetched during this build, 2026-09-04):
    - New-UnifiedAuditLogRetentionPolicy / Set-UnifiedAuditLogRetentionPolicy / Remove-
      UnifiedAuditLogRetentionPolicy / Get-UnifiedAuditLogRetentionPolicy reference pages
      (learn.microsoft.com/powershell/module/exchangepowershell/...) - full parameter sets,
      RetentionDuration accepted values (ThreeMonths, SixMonths, NineMonths, TwelveMonths,
      TenYears - confirmed identical on both New- and Set-), the Operations/RecordTypes mutual-
      exclusivity rule, and the worked examples this sample config's three entries are adapted
      from.
    - "Manage audit log retention policies" (learn.microsoft.com/purview/audit-log-retention-
      policies) - the 50-policy cap, the 1-10000 Priority range with 1 = highest, the "no two
      policies can share a Priority" rule, the Name (64 char) / Description (256 char) limits,
      the Organization Configuration role requirement, and the portal's wider duration list
      (7 Days / 30 Days / 6 Months / 9 Months / 1 Year / 3 Years / 5 Years / 7 Years / 10 Years)
      used here only to document the gap vs. the narrower PowerShell enum - never as a value this
      script accepts.
    VERIFY (pilot tenant, before production reliance): whether editing a live policy's
    RetentionDuration changes the expiration of audit records already committed under the old
    duration, or only affects records committed after the edit - Microsoft's own conceptual page
    states both "changes... change the expiration time of the audit data after updating" and that
    such changes "don't update any previously committed items" without reconciling the two
    statements. See README.md Section 11 and design.md Section 6.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ValidDurations = @('ThreeMonths', 'SixMonths', 'NineMonths', 'TwelveMonths', 'TenYears')

function Get-NormalizedArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object)
}

function Test-ArraysEqual {
    param([string[]]$Left, [string[]]$Right)
    $l = Get-NormalizedArray $Left
    $r = Get-NormalizedArray $Right
    if ($l.Count -ne $r.Count) { return $false }
    for ($i = 0; $i -lt $l.Count; $i++) {
        if ($l[$i] -ne $r[$i]) { return $false }
    }
    return $true
}

# --- Load and validate config -------------------------------------------------------------
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
if (-not $config.policies -or $config.policies.Count -eq 0) {
    throw "Config at '$ConfigPath' has no 'policies' entries."
}

Write-Verbose "Loaded $($config.policies.Count) policy definition(s) from '$ConfigPath'."

$seenNames = @{}
$seenPriorities = @{}
foreach ($p in $config.policies) {
    if ([string]::IsNullOrWhiteSpace($p.name)) {
        throw "Every policy entry must have a non-empty 'name'."
    }
    if ($p.name.Length -gt 64) {
        throw "Policy '$($p.name)': Name exceeds Microsoft's documented 64-character limit."
    }
    if ($p.description -and $p.description.Length -gt 256) {
        throw "Policy '$($p.name)': Description exceeds Microsoft's documented 256-character limit."
    }
    if ($seenNames.ContainsKey($p.name)) {
        throw "Duplicate policy name '$($p.name)' within the config file."
    }
    $seenNames[$p.name] = $true

    if ($p.retentionDuration -notin $ValidDurations) {
        throw "Policy '$($p.name)': retentionDuration '$($p.retentionDuration)' is not one of the " +
            "PowerShell-supported values ($($ValidDurations -join ', ')). The portal supports " +
            "additional durations (7 Days/30 Days/3 Years/5 Years/7 Years) that no PowerShell " +
            "cmdlet can create or edit - see README.md Section 11."
    }

    $recordTypes = Get-NormalizedArray $p.recordTypes
    $operations = Get-NormalizedArray $p.operations
    if ($operations.Count -gt 0 -and $recordTypes.Count -ne 1) {
        throw "Policy '$($p.name)': 'operations' requires exactly one 'recordTypes' entry " +
            "(Microsoft's documented constraint on -Operations/-RecordTypes) - found $($recordTypes.Count)."
    }

    if ($null -eq $p.priority -or $p.priority -lt 1 -or $p.priority -gt 10000) {
        throw "Policy '$($p.name)': priority must be an integer between 1 and 10000."
    }
    if ($seenPriorities.ContainsKey([int]$p.priority)) {
        throw "Policy '$($p.name)': priority $($p.priority) collides with policy " +
            "'$($seenPriorities[[int]$p.priority])' elsewhere in this config file - " +
            "priority must be tenant-wide unique."
    }
    $seenPriorities[[int]$p.priority] = $p.name
}

# --- Snapshot the live tenant and check cross-tenant constraints -------------------------
Write-Verbose 'Fetching live audit log retention policies for pre-flight checks...'
$livePolicies = @(Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop)
Write-Verbose "Tenant currently has $($livePolicies.Count) custom audit log retention polic(y/ies) " +
    '(the default policy is not included in this count or list - Get-UnifiedAuditLogRetentionPolicy ' +
    'never returns it).'

foreach ($p in $config.policies) {
    $collision = $livePolicies | Where-Object {
        $_.Priority -eq [int]$p.priority -and $_.Name -ne $p.name
    }
    if ($collision) {
        throw "Policy '$($p.name)': priority $($p.priority) is already used by live policy " +
            "'$($collision.Name)'. No two audit log retention policies may share a priority. " +
            "Choose a different value or update the colliding policy's priority first."
    }
}

$toCreateCount = ($config.policies | Where-Object { $_.name -notin $livePolicies.Name }).Count
$projectedTotal = $livePolicies.Count + $toCreateCount
if ($projectedTotal -gt 50) {
    throw "This run would create $toCreateCount new polic(y/ies), bringing the tenant total to " +
        "$projectedTotal - over Microsoft's documented 50-policy-per-organization cap. " +
        "$($livePolicies.Count) polic(y/ies) already exist."
}

# --- Reconcile each policy -----------------------------------------------------------------
foreach ($p in $config.policies) {
    $live = $livePolicies | Where-Object { $_.Name -eq $p.name } | Select-Object -First 1
    $recordTypes = Get-NormalizedArray $p.recordTypes
    $operations = Get-NormalizedArray $p.operations
    $userIds = Get-NormalizedArray $p.userIds

    # RecordTypes/Operations/UserIds are always passed explicitly, using $null (not an empty
    # array) when the config leaves them blank - matching Microsoft's own documented example of
    # clearing a MultiValuedProperty ("-UserIds $null ... removes all values from the UserId
    # property so the policy applies to all users"), so an update that removes a prior
    # scoping value actually clears it on both New- (first-time default) and Set- (overwrite).
    # NOTE: Microsoft's worked $null-clearing example covers -UserIds specifically; applying the
    # same $null convention to -RecordTypes/-Operations here is this script's own extrapolation
    # by analogy (same MultiValuedProperty type, same "blank = applies to all" documented
    # default), not independently confirmed for those two parameters - see README.md Section 11.
    $cmdletParams = @{
        RetentionDuration = $p.retentionDuration
        Description       = if ($p.description) { $p.description } else { $null }
        RecordTypes       = if ($recordTypes.Count -gt 0) { $recordTypes } else { $null }
        Operations        = if ($operations.Count -gt 0) { $operations } else { $null }
        UserIds           = if ($userIds.Count -gt 0) { $userIds } else { $null }
        Priority          = [int]$p.priority
    }

    if (-not $live) {
        if ($PSCmdlet.ShouldProcess($p.name, 'New-UnifiedAuditLogRetentionPolicy')) {
            New-UnifiedAuditLogRetentionPolicy -Name $p.name @cmdletParams | Out-Null
            Write-Host "[CREATED] '$($p.name)' (priority $($p.priority), $($p.retentionDuration))"
        }
        continue
    }

    # Named $isMatch, not $matches - $matches is PowerShell's automatic variable populated by
    # the -match operator, and clobbering it here would be confusing to anyone extending this
    # script later.
    $isMatch = (
        $live.RetentionDuration -eq $p.retentionDuration -and
        $live.Priority -eq [int]$p.priority -and
        [string]$live.Description -eq [string]$p.description -and
        (Test-ArraysEqual -Left $live.RecordTypes -Right $recordTypes) -and
        (Test-ArraysEqual -Left $live.Operations -Right $operations) -and
        (Test-ArraysEqual -Left $live.UserIds -Right $userIds)
    )

    if ($isMatch) {
        Write-Host "[UNCHANGED] '$($p.name)' already matches the config."
        continue
    }

    if ($PSCmdlet.ShouldProcess($p.name, 'Set-UnifiedAuditLogRetentionPolicy')) {
        Set-UnifiedAuditLogRetentionPolicy -Identity $p.name @cmdletParams | Out-Null
        Write-Host "[UPDATED] '$($p.name)' (priority $($p.priority), $($p.retentionDuration))"
    }
}

if ($config.policies.retentionDuration -contains 'TenYears') {
    Write-Warning ('One or more policies use TenYears retention. This script cannot verify the ' +
        '10-Year Audit Log Retention add-on license is assigned to every user the policy covers - ' +
        'confirm that manually before relying on it. See README.md Section 3.')
}
