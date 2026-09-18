---
part: "validate"
parent: "ediscovery/teams-group-hold-resolution"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-TeamsGroupHoldLocations.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Verifies the output of Resolve-TeamsGroupHoldLocations.ps1: every declared group still
    resolves to the same mailbox/site, the resolved JSON fragment matches current group state, and
    -- if a hold is named -- every resolved location is actually present and applied on it.

.DESCRIPTION
    Read-only throughout: never calls a mutating Exchange Online or Graph endpoint. Two check
    groups, the second only if -CaseId/-HoldId are supplied:

      1. Group drift -- re-runs Get-UnifiedGroup for each declared group and compares
         PrimarySmtpAddress/SharePointSiteUrl against -ResolvedPath's userSources/siteSources.
         A mismatch here means the group's mailbox address or site URL changed since the last
         Resolve-TeamsGroupHoldLocations.ps1 run (a UPN/site-rename event, README.md Section 11)
         and the resolved fragment (or a hold already built from it) is stale.
      2. Hold reconciliation (only with -CaseId/-HoldId) -- confirms each resolved userSource/
         siteSource is present on the named hold policy with holdStatus applied/applying, the same
         checks scenarios/ediscovery/location-scoped-legal-hold/validate/
         Test-EdiscoveryLocationHold.ps1 already performs, scoped to just this script's own
         resolved groups rather than every source on the hold.

    Exits non-zero on any hard FAIL -- safe for a scheduled drift check (README.md Section 8),
    the same convention every validate/ script in this library follows.

.PARAMETER DefinitionPath
    Same JSON definition file used by Resolve-TeamsGroupHoldLocations.ps1.

.PARAMETER ResolvedPath
    Path to the resolved userSources/siteSources JSON fragment Resolve-TeamsGroupHoldLocations.ps1
    wrote. Defaults to 'deploy/out/teams-group-hold-locations.resolved.json' (sibling of
    -DefinitionPath's own deploy/ tree), the same default the deploy script uses.

.PARAMETER CaseId
.PARAMETER HoldId
    Optional. If supplied, also confirms each resolved location's holdStatus on this hold policy.
    Requires -AppId/-TenantId/-CertificateThumbprint (or -Certificate).

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Microsoft Graph app-only authentication parameters, used only when -CaseId/-HoldId are
    supplied. A read-only credential (eDiscovery.Read.All) is sufficient and preferred. This
    script does not connect to Exchange Online for you -- run Connect-ExchangeOnline first, same
    convention as the deploy script.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Test-TeamsGroupHoldLocations.ps1 -DefinitionPath ../deploy/config/teams-group-hold-resolution.sample.json

    Group-drift check only.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Test-TeamsGroupHoldLocations.ps1 -DefinitionPath ../deploy/config/teams-group-hold-resolution.sample.json `
        -CaseId $caseId -HoldId $holdId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Group-drift check plus hold-reconciliation check.

.NOTES
    Manual verification checklist (no read API/cmdlet exists for these -- confirm by hand):
      - Whether a group flagged WARN for a blank SharePointSiteUrl has since finished site
        provisioning (README.md Section 11) -- re-run both this script and the deploy script once
        confirmed, rather than treating the WARN as permanent.
      - Individual member mailboxes/OneDrive accounts are never checked here, by design -- this
        scenario resolves the group's own mailbox/site only (README.md Section 2); a legal team
        that also added individual members' mailboxes to the hold should validate those through
        the sibling scenario's own Test-EdiscoveryLocationHold.ps1 against the full definition
        file, not through this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [string]$ResolvedPath,

    [string]$CaseId,

    [string]$HoldId,

    [string]$AppId,

    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FailCount = 0
$script:WarnCount = 0
$script:GraphBase = 'https://graph.microsoft.com/v1.0'

function Write-Check {
    param([string]$Message, [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Level)
    $prefix = "[$Level]"
    switch ($Level) {
        'PASS' { Write-Host "$prefix $Message" -ForegroundColor Green }
        'WARN' { Write-Host "$prefix $Message" -ForegroundColor Yellow; $script:WarnCount++ }
        'FAIL' { Write-Host "$prefix $Message" -ForegroundColor Red; $script:FailCount++ }
    }
}

if (-not (Get-Command Get-UnifiedGroup -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md Section 3).'
}

$definitionDir = Split-Path -Path (Resolve-Path $DefinitionPath) -Parent
if (-not $ResolvedPath) {
    $defaultOutDir = Join-Path (Split-Path -Path $definitionDir -Parent) 'out'
    $ResolvedPath = Join-Path $defaultOutDir 'teams-group-hold-locations.resolved.json'
}

if (-not (Test-Path $ResolvedPath -PathType Leaf)) {
    Write-Check "Resolved fragment '$ResolvedPath' not found -- run Resolve-TeamsGroupHoldLocations.ps1 first." -Level FAIL
    exit 1
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
$resolvedFragment = Get-Content -Path $ResolvedPath -Raw | ConvertFrom-Json
$resolvedEmails = @($resolvedFragment.userSources | ForEach-Object { $_.email })
$resolvedSites = @($resolvedFragment.siteSources | ForEach-Object { $_.site })

# 1. Group drift
$currentGroups = @()
foreach ($groupDef in $definition.groups) {
    try {
        $group = Get-UnifiedGroup -Identity $groupDef.identity -ErrorAction Stop |
            Select-Object DisplayName, PrimarySmtpAddress, SharePointSiteUrl
    } catch {
        Write-Check "Group '$($groupDef.identity)' could not be resolved -- $($_.Exception.Message)" -Level FAIL
        continue
    }
    $currentGroups += $group

    if ($resolvedEmails -contains $group.PrimarySmtpAddress) {
        Write-Check "Group '$($group.DisplayName)' PrimarySmtpAddress '$($group.PrimarySmtpAddress)' matches the resolved fragment." -Level PASS
    } else {
        Write-Check "Group '$($group.DisplayName)' PrimarySmtpAddress '$($group.PrimarySmtpAddress)' is NOT present in '$ResolvedPath' -- re-run Resolve-TeamsGroupHoldLocations.ps1 (identity change or fragment is stale)." -Level FAIL
    }

    if (-not $group.SharePointSiteUrl) {
        Write-Check "Group '$($group.DisplayName)' has no SharePointSiteUrl -- site may still be provisioning or was deferred (see this script's .NOTES and README.md Section 11)." -Level WARN
    } elseif ($resolvedSites -contains $group.SharePointSiteUrl) {
        Write-Check "Group '$($group.DisplayName)' SharePointSiteUrl matches the resolved fragment." -Level PASS
    } else {
        Write-Check "Group '$($group.DisplayName)' SharePointSiteUrl '$($group.SharePointSiteUrl)' is NOT present in '$ResolvedPath' -- re-run Resolve-TeamsGroupHoldLocations.ps1." -Level FAIL
    }
}

# 2. Hold reconciliation (optional)
if ($CaseId -and $HoldId) {
    if (-not $AppId -or -not $TenantId -or (-not $CertificateThumbprint -and -not $Certificate)) {
        Write-Check '-CaseId/-HoldId supplied but Graph auth parameters (-AppId/-TenantId/-CertificateThumbprint or -Certificate) are missing -- skipping hold-reconciliation checks.' -Level WARN
    } else {
        if (Get-MgContext) {
            Write-Verbose 'Reusing existing Microsoft Graph connection.'
        } else {
            $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
            if ($Certificate) { $connectParams['Certificate'] = $Certificate }
            else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
            Connect-MgGraph @connectParams
        }

        $holdUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId"
        try {
            $actualUserSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdUri/userSources").value)
            $actualSiteSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdUri/siteSources").value)
        } catch {
            Write-Check "Could not retrieve hold policy $HoldId in case $CaseId -- $($_.Exception.Message)" -Level FAIL
            $actualUserSources = @(); $actualSiteSources = @()
        }

        foreach ($group in $currentGroups) {
            $userSource = $actualUserSources | Where-Object { $_.email -eq $group.PrimarySmtpAddress } | Select-Object -First 1
            if (-not $userSource) {
                Write-Check "Group '$($group.DisplayName)' mailbox '$($group.PrimarySmtpAddress)' not found as a userSource on hold policy $HoldId -- run Resolve-TeamsGroupHoldLocations.ps1 -AddToHold." -Level FAIL
            } elseif ($userSource.holdStatus -eq 'applied') {
                Write-Check "Group '$($group.DisplayName)' mailbox userSource holdStatus is 'applied'." -Level PASS
            } elseif ($userSource.holdStatus -eq 'applying') {
                Write-Check "Group '$($group.DisplayName)' mailbox userSource holdStatus is 'applying' -- still propagating." -Level WARN
            } else {
                Write-Check "Group '$($group.DisplayName)' mailbox userSource holdStatus is '$($userSource.holdStatus)' -- expected 'applied'." -Level FAIL
            }

            if ($group.SharePointSiteUrl) {
                $siteTitle = ($group.SharePointSiteUrl -split '/')[-1]
                $siteSource = $actualSiteSources | Where-Object { $_.displayName -eq $siteTitle } | Select-Object -First 1
                if (-not $siteSource) {
                    Write-Check "Group '$($group.DisplayName)' site (matched by title '$siteTitle') not found as a siteSource on hold policy $HoldId -- run Resolve-TeamsGroupHoldLocations.ps1 -AddToHold." -Level FAIL
                } elseif ($siteSource.holdStatus -eq 'applied') {
                    Write-Check "Group '$($group.DisplayName)' site siteSource holdStatus is 'applied'." -Level PASS
                } elseif ($siteSource.holdStatus -eq 'applying') {
                    Write-Check "Group '$($group.DisplayName)' site siteSource holdStatus is 'applying' -- still propagating." -Level WARN
                } else {
                    Write-Check "Group '$($group.DisplayName)' site siteSource holdStatus is '$($siteSource.holdStatus)' -- expected 'applied'." -Level FAIL
                }
            }
        }
    }
} else {
    Write-Check '-CaseId/-HoldId not supplied -- skipped hold-reconciliation checks (group-drift checks only).' -Level WARN
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```