---
part: "deploy"
parent: "ediscovery/teams-group-hold-resolution"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/teams-group-hold-resolution.sample.json`

```json
{
  "groups": [
    {
      "identity": "Payments Team",
      "resolveMembers": true
    },
    {
      "identity": "seniorleadershipteam@contoso.onmicrosoft.com",
      "resolveMembers": false
    }
  ]
}
```

#### `Resolve-TeamsGroupHoldLocations.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Resolves one or more Microsoft Teams / Microsoft 365 Groups into the userSource (group
    mailbox) + siteSource (group SharePoint site) pair that
    scenarios/ediscovery/location-scoped-legal-hold/'s hold scripts already accept, and optionally
    reconciles those locations directly onto an existing location-scoped hold policy.

.DESCRIPTION
    Closes the gap the sibling scenario's design.md Section 8 explicitly scoped out: "resolving
    *which* group/site pair to use from a Team name is a distinct, separately scoped lookup this
    fragment doesn't automate." This script is that lookup.

    Grounded directly in Microsoft's own "Preserve content in Microsoft Teams" / "Microsoft 365
    groups" guidance (README.md Section 12): a Team or Microsoft 365 Group's own preservable
    content lives in exactly two locations -- the group's mailbox (Teams channel conversations,
    cards, meeting/call summaries) and its SharePoint site (files shared in channels, the Teams
    Wiki) -- both discoverable from a single Get-UnifiedGroup call. Placing only those two
    locations on hold does **not** preserve individual members' 1:1/1:N chats or personal OneDrive
    files (README.md Section 11); resolving membership (-ResolveMembers) is offered as a
    reporting aid for that separate decision, never as an automatic hold-scope expansion.

    Two independent stages:
      1. Resolve (always runs, read-only). For each group identity in -DefinitionPath's `groups`
         array, calls Get-UnifiedGroup to read DisplayName/Alias/PrimarySmtpAddress/
         SharePointSiteUrl (Exchange Online PowerShell, automation surface 1 per
         docs/automation-surface.md Section 1 -- this script does not connect for you; run
         Connect-ExchangeOnline first, same convention as
         scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1).
         Writes a userSources[]/siteSources[] JSON fragment, in the exact shape
         scenarios/ediscovery/location-scoped-legal-hold/deploy/policy/location-hold-definition.json
         uses, to -OutputPath. With `resolveMembers: true` on a group entry (or -ResolveMembers),
         also calls Get-UnifiedGroupLinks -LinkType Members and writes a separate member-roster CSV
         -- informational only, never merged into the hold-definition fragment.
      2. Reconcile (-AddToHold only). Connects to Microsoft Graph (surface 3, self-connecting --
         same pattern as the sibling scenario's New-EdiscoveryLocationHold.ps1) and idempotently
         adds each resolved userSource/siteSource to the named -CaseId/-HoldId's hold policy, using
         the identical find-or-create Confirm-UserSource/Confirm-SiteSource logic the sibling
         scenario's deploy script uses -- duplicated here, not dot-sourced, per this repo's
         self-contained-deploy-tree convention (see scenarios/insider-risk/
         irm-case-escalation-to-ediscovery/deploy/Confirm-EdiscoveryEscalationLink.ps1 for
         precedent). $PSCmdlet.ShouldProcess() gates every write, so -WhatIf reports every add this
         run would make without calling a mutating Graph endpoint.

    Every run is idempotent: Stage 1 always re-resolves current group state and overwrites
    -OutputPath (a snapshot, not an accumulating log -- there is nothing to "already have" about a
    read); Stage 2 re-uses the sibling script's find-or-create-by-email/title matching, so
    re-running -AddToHold against a group already reconciled onto the hold reports it present and
    adds nothing new.

.PARAMETER DefinitionPath
    Path to a JSON file: { "groups": [ { "identity": "<name, alias, or SMTP address>",
    "resolveMembers": <bool, optional, default false> }, ... ] }. See
    deploy/config/teams-group-hold-resolution.sample.json.

.PARAMETER OutputPath
    Where to write the resolved userSources[]/siteSources[] JSON fragment. Defaults to
    'deploy/out/teams-group-hold-locations.resolved.json' (created if missing) -- the same
    gitignored-output-directory convention this library's other CSV/JSON-emitting scripts use
    (e.g. premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1's -OutputCsvPath
    examples), so a real run's resolved mailbox/site values are never accidentally committed
    alongside deploy/config/'s tracked sample file. Overwritten on every run (a snapshot of current
    state, not a log -- Section 1 above).

.PARAMETER MemberRosterPath
    Where to write the member-roster CSV for any group with resolveMembers true. Defaults to
    'deploy/out/teams-group-hold-members.roster.csv' (same rationale as -OutputPath -- this file
    contains member display names and SMTP addresses, matter-related personal data that shouldn't
    land in version control by default). Only written if at least one group requests member
    resolution.

.PARAMETER ResolveMembers
    Force member resolution for every group in -DefinitionPath, regardless of each entry's own
    resolveMembers value. Off by default -- member enumeration needs the View-Only Recipients role
    (same as Get-UnifiedGroup itself) and, for a large group, is the slower of this script's two
    Exchange Online calls.

.PARAMETER AddToHold
    After resolving, reconcile every group's userSource/siteSource onto an existing
    location-scoped-legal-hold hold policy via Microsoft Graph. Requires -CaseId and -HoldId. Off
    by default -- the resolve-only path is the safer default for a first run (inspect the JSON
    fragment, merge it into location-hold-definition.json by hand or feed it to
    scenarios/ediscovery/location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1's own
    -DefinitionPath yourself) before this script starts writing to a live hold policy.

.PARAMETER CaseId
.PARAMETER HoldId
    The eDiscoveryCase id and ediscoveryHoldPolicy id to reconcile onto. Required with -AddToHold.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Microsoft Graph app-only authentication parameters, used only for the -AddToHold path -- same
    shape as scenarios/ediscovery/location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1.
    Not required for the resolve-only path (Exchange Online PowerShell connection is assumed
    already established -- see .DESCRIPTION).

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Resolve-TeamsGroupHoldLocations.ps1 -DefinitionPath ./config/teams-group-hold-resolution.sample.json

    Resolves every declared group's mailbox/site and writes the JSON fragment. Makes no change to
    any hold -- inspect the output, then merge it into location-hold-definition.json by hand.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Resolve-TeamsGroupHoldLocations.ps1 -DefinitionPath ./config/teams-group-hold-resolution.sample.json `
        -AddToHold -CaseId $caseId -HoldId $holdId `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Dry run: resolves every group and reports every userSource/siteSource add this run would make
    against the named hold, without calling a mutating Graph endpoint.

.NOTES
    Grounded in Microsoft Learn (README.md Section 12): "Create holds in eDiscovery" -- "Preserve
    content in Microsoft Teams" / "Microsoft 365 groups" section, the exact Get-UnifiedGroup /
    Get-UnifiedGroupLinks commands and output shape quoted directly (including the View-Only
    Recipients role requirement); "Manage holds in eDiscovery" -- "Place a hold on Microsoft Teams
    and Microsoft 365 groups" (same guidance, hold-management context); the Get-UnifiedGroup /
    Get-UnifiedGroupLinks Exchange PowerShell module references (parameter/syntax confirmation).

    VERIFY before relying on this for a group created immediately before this script runs: this
    script warns (does not fail) when SharePointSiteUrl comes back blank on Get-UnifiedGroup,
    since a Microsoft 365 group's SharePoint site is provisioned asynchronously at group creation
    (Microsoft Graph: "Microsoft 365 Group behaviors and provisioning options" -- the
    ProvisionSiteOnDemand resourceBehaviorOptions value exists specifically to defer that
    provisioning) and a community-reported, non-canonical timeframe puts the delay at "a few
    minutes to up to 24 hours." No canonical Microsoft Learn page states an exact SLA for
    SharePointSiteUrl becoming populated on Get-UnifiedGroup after group creation -- re-run this
    script rather than treating one blank result as a permanent failure.

    Re-grounded 2026-09-04 (cross-referenced against scenarios/ediscovery/location-scoped-legal-hold/'s
    own VERIFY, full analysis in that scenario's design.md Section 3): Microsoft's current "Create
    holds in eDiscovery" page states group-as-data-source expansion (any supported group type,
    including Microsoft 365 groups) is "limited to a maximum of 100 members" in the portal's own
    interactive data-source picker -- a smaller, more specific figure than the ">1,000 email
    addresses" "Distribution group has too many members" hold-application error the current "Manage
    holds in eDiscovery" page documents. Direct re-fetch of both pages confirmed neither is a stale
    or superseded reference; Microsoft's text doesn't state whether the two figures describe the same
    limit surfaced at two different pipeline steps (portal picker vs. post-apply error) or two
    independent limits. This script's own output (one userSource per group -- the group's own
    mailbox, never an expansion of individual members) is not itself subject to either cap; the cap
    only matters if a human, using this script's -ResolveMembers roster output, chooses to add
    individual members as their own userSources -- treat 100 members as the conservative planning
    threshold there. Kept as an open, dual-cited VERIFY rather than resolved by guessing which
    figure governs, per AGENTS.md Section 4.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [string]$OutputPath,

    [string]$MemberRosterPath,

    [switch]$ResolveMembers,

    [switch]$AddToHold,

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

$script:GraphBase = 'https://graph.microsoft.com/v1.0'

function Assert-ExchangeOnlineSession {
    # Get-UnifiedGroup is only exported after a successful Connect-ExchangeOnline; its absence
    # means the caller never connected. Same pattern as
    # scenarios/dlp/endpoint-dlp-usb-block/deploy/New-EndpointDlpUsbBlockPolicy.ps1's
    # Assert-IppsSession.
    if (-not (Get-Command Get-UnifiedGroup -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md Section 3) -- this script does not connect for you.'
    }
}

function Resolve-GroupLocation {
    param([string]$Identity, [bool]$WantMembers)

    $group = Get-UnifiedGroup -Identity $Identity -ErrorAction Stop |
        Select-Object DisplayName, Alias, PrimarySmtpAddress, SharePointSiteUrl

    if (-not $group.SharePointSiteUrl) {
        Write-Warning "Group '$($group.DisplayName)' ($($group.PrimarySmtpAddress)) returned no SharePointSiteUrl -- its site may still be provisioning (see this script's .NOTES), or provisioning was deferred (ProvisionSiteOnDemand). Only the mailbox will be included in this run's output for this group; re-run once the site exists."
    }

    $members = @()
    if ($WantMembers) {
        Write-Verbose "Resolving membership for '$($group.DisplayName)' (Get-UnifiedGroupLinks -LinkType Members)."
        $members = @(Get-UnifiedGroupLinks -Identity $Identity -LinkType Members -ErrorAction Stop |
            Select-Object DisplayName, PrimarySmtpAddress)
        Write-Host "  '$($group.DisplayName)': $($members.Count) current member(s) -- point-in-time snapshot, not itself placed on hold by this script (README.md Section 11)."
    }

    [pscustomobject]@{
        DisplayName        = $group.DisplayName
        Alias              = $group.Alias
        PrimarySmtpAddress = $group.PrimarySmtpAddress
        SharePointSiteUrl  = $group.SharePointSiteUrl
        Members            = $members
    }
}

function Confirm-UserSourceOnHold {
    # Duplicated from scenarios/ediscovery/location-scoped-legal-hold/deploy/
    # New-EdiscoveryLocationHold.ps1's Confirm-UserSource -- not dot-sourced, per this repo's
    # self-contained-deploy-tree convention.
    param($CaseId, $HoldId, [string]$Email)

    $listUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId/userSources"
    $existingSources = @()
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $listUri
        $existingSources = @($response.value)
    } catch {
        Write-Verbose "Could not list existing userSources for hold $HoldId (expected under -WhatIf on a not-yet-created hold)."
    }
    if ($existingSources | Where-Object { $_.email -eq $Email }) {
        Write-Verbose "userSource for '$Email' already exists on hold $HoldId."
        return
    }

    $body = @{ email = $Email; includedSources = 'mailbox' }
    if ($PSCmdlet.ShouldProcess($Email, "Add group mailbox as userSource on hold policy $HoldId")) {
        Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json) | Out-Null
        Write-Host "Added userSource '$Email' to hold policy $HoldId."
    }
}

function Confirm-SiteSourceOnHold {
    # Duplicated from New-EdiscoveryLocationHold.ps1's Confirm-SiteSource -- see note above.
    param($CaseId, $HoldId, [string]$SiteUrl)

    $listUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId/siteSources"
    $existingSources = @()
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $listUri
        $existingSources = @($response.value)
    } catch {
        Write-Verbose "Could not list existing siteSources for hold $HoldId (expected under -WhatIf on a not-yet-created hold)."
    }
    $siteTitle = ($SiteUrl -split '/')[-1]
    if ($existingSources | Where-Object { $_.displayName -eq $siteTitle }) {
        Write-Verbose "siteSource for '$SiteUrl' already appears present on hold $HoldId (matched by title '$siteTitle')."
        return
    }

    $body = @{ site = @{ webUrl = $SiteUrl } }
    if ($PSCmdlet.ShouldProcess($SiteUrl, "Add group SharePoint site as siteSource on hold policy $HoldId")) {
        Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Added siteSource '$SiteUrl' to hold policy $HoldId."
    }
}

# --- main ---

if ($AddToHold -and (-not $CaseId -or -not $HoldId)) {
    throw '-AddToHold requires both -CaseId and -HoldId.'
}
if ($AddToHold -and (-not $AppId -or -not $TenantId -or (-not $CertificateThumbprint -and -not $Certificate))) {
    throw '-AddToHold requires Microsoft Graph app-only auth parameters: -AppId, -TenantId, and either -CertificateThumbprint or -Certificate.'
}

Assert-ExchangeOnlineSession

$definitionDir = Split-Path -Path (Resolve-Path $DefinitionPath) -Parent
$defaultOutDir = Join-Path (Split-Path -Path $definitionDir -Parent) 'out'
if (-not $OutputPath) { $OutputPath = Join-Path $defaultOutDir 'teams-group-hold-locations.resolved.json' }
if (-not $MemberRosterPath) { $MemberRosterPath = Join-Path $defaultOutDir 'teams-group-hold-members.roster.csv' }
foreach ($path in @($OutputPath, $MemberRosterPath)) {
    $dir = Split-Path -Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
if (-not $definition.groups -or @($definition.groups).Count -eq 0) {
    throw "'$DefinitionPath' declares no groups under its 'groups' array."
}

$resolved = @()
foreach ($groupDef in $definition.groups) {
    # ($groupDef.resolveMembers) directly would throw under Set-StrictMode -Version Latest when a
    # group entry omits the (documented-optional) resolveMembers key entirely -- PSCustomObject
    # property access on a missing key is a hard error under strict mode, not a $null. Check for
    # the property's presence first.
    $entryWantsMembers = ($groupDef.PSObject.Properties.Name -contains 'resolveMembers') -and $groupDef.resolveMembers
    $wantMembers = $ResolveMembers -or [bool]$entryWantsMembers
    Write-Verbose "Resolving '$($groupDef.identity)'..."
    $resolved += Resolve-GroupLocation -Identity $groupDef.identity -WantMembers $wantMembers
}

$userSources = @($resolved | ForEach-Object { @{ email = $_.PrimarySmtpAddress } })
$siteSources = @($resolved | Where-Object { $_.SharePointSiteUrl } | ForEach-Object { @{ site = $_.SharePointSiteUrl } })
$fragment = @{ userSources = $userSources; siteSources = $siteSources }

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write resolved userSources/siteSources JSON fragment')) {
    $fragment | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding utf8
    Write-Host "Wrote $($userSources.Count) userSource(s), $($siteSources.Count) siteSource(s) to '$OutputPath'."
}

$missingSite = @($resolved | Where-Object { -not $_.SharePointSiteUrl })
if ($missingSite.Count -gt 0) {
    # Rolled up here, not just the per-group Write-Warning in Resolve-GroupLocation, so this gap
    # is visible even to a caller only watching Write-Host output (e.g. a non-interactive
    # scheduled run where -WarningAction/-WarningVariable weren't captured) -- Red Team finding,
    # reviews.md.
    Write-Warning "$($missingSite.Count) of $($resolved.Count) group(s) resolved with NO SharePointSiteUrl -- their site was excluded from this run's output entirely: $(($missingSite | ForEach-Object { $_.DisplayName }) -join ', '). See README.md Section 11 before treating this run's siteSources list as complete."
}

$rosterRows = @($resolved | Where-Object { $_.Members.Count -gt 0 } | ForEach-Object {
    $group = $_
    $group.Members | ForEach-Object { [pscustomobject]@{ Group = $group.DisplayName; MemberDisplayName = $_.DisplayName; MemberPrimarySmtpAddress = $_.PrimarySmtpAddress } }
})
if ($rosterRows.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($MemberRosterPath, "Write $($rosterRows.Count)-row member roster CSV")) {
        $rosterRows | Export-Csv -Path $MemberRosterPath -NoTypeInformation -Encoding utf8
        Write-Host "Wrote $($rosterRows.Count) member-roster row(s) to '$MemberRosterPath' (informational -- not added to any hold by this script)."
    }
}

if ($AddToHold) {
    if (Get-MgContext) {
        Write-Verbose 'Reusing existing Microsoft Graph connection.'
    } else {
        $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
        if ($Certificate) { $connectParams['Certificate'] = $Certificate }
        else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
        Connect-MgGraph @connectParams
    }

    foreach ($group in $resolved) {
        Confirm-UserSourceOnHold -CaseId $CaseId -HoldId $HoldId -Email $group.PrimarySmtpAddress
        if ($group.SharePointSiteUrl) {
            Confirm-SiteSourceOnHold -CaseId $CaseId -HoldId $HoldId -SiteUrl $group.SharePointSiteUrl
        }
    }
    Write-Host "Done. Reconciled $($resolved.Count) group(s) onto hold policy $HoldId (case $CaseId)."
    Write-Host "Next: ../location-scoped-legal-hold/validate/Test-EdiscoveryLocationHold.ps1 to confirm hold status, or ./../validate/Test-TeamsGroupHoldLocations.ps1 for this scenario's own checks."
} else {
    Write-Host "Resolve-only run complete. Merge '$OutputPath' into a location-hold-definition.json by hand, or re-run with -AddToHold -CaseId -HoldId to reconcile directly."
}
```