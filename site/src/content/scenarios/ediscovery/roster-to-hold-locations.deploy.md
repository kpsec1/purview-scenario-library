---
part: "deploy"
parent: "ediscovery/roster-to-hold-locations"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/roster-selection.sample.json`

```json
{
  "_comment": "Human-authored decision record for scenarios/ediscovery/roster-to-hold-locations/. Every email in selectedEmails must appear in the -RosterPath CSV's MemberPrimarySmtpAddress column (teams-group-hold-resolution's Resolve-TeamsGroupHoldLocations.ps1 -ResolveMembers output) -- Merge-RosterIntoHoldDefinition.ps1 fails fast on any that don't, rather than accepting an address it cannot verify against the roster. Author-only reference for the buyer's own tenant -- replace every value below before use. No secrets belong in this file.",
  "reason": "CID 2026-009 (see location-scoped-legal-hold/deploy/policy/location-hold-definition.json) names two individually-identified custodians within the Payments Team roster as direct subjects of the inquiry -- outside counsel (Example & Example LLP) confirmed 2026-09-04 their individual mailboxes need preservation beyond the group mailbox/site already on hold.",
  "selectedEmails": [
    "alex.chen@contoso.com",
    "jordan.patel@contoso.com"
  ]
}
```

#### `config/teams-group-hold-members.roster.sample.csv`

```
"Group","MemberDisplayName","MemberPrimarySmtpAddress"
"Payments Team","Alex Chen","alex.chen@contoso.com"
"Payments Team","Jordan Patel","jordan.patel@contoso.com"
"Payments Team","Sam Osei","sam.osei@contoso.com"
```

#### `Merge-RosterIntoHoldDefinition.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Merges a human-selected subset of a Microsoft Teams / Microsoft 365 Group member roster (as
    produced by scenarios/ediscovery/teams-group-hold-resolution/'s -ResolveMembers roster CSV)
    into scenarios/ediscovery/location-scoped-legal-hold/'s location-hold-definition.json shape as
    new userSources[] entries, and optionally reconciles them directly onto an existing hold policy.

.DESCRIPTION
    Closes the hand-off scenarios/ediscovery/teams-group-hold-resolution/design.md Section 7 left
    manual: "Once a human uses -ResolveMembers's roster output to decide individual members also
    need preservation, feeding those resolved mailbox addresses into the sibling scenario's own
    userSources[] array is currently a manual step." This script is that hand-off, not a decision
    engine -- it never selects members itself. Per teams-group-hold-resolution/design.md Section 2,
    "a human decision, not this script's to make": which roster members actually need individual
    preservation is supplied by the caller as -SelectionPath, a small JSON file recording the exact
    email addresses chosen and the reason (a matter/counsel decision), never inferred from group
    membership size, role, or any other heuristic.

    Two independent stages, mirroring the pattern this repo already established in
    Resolve-TeamsGroupHoldLocations.ps1:

      1. Merge (always runs). Reads -RosterPath (the roster CSV) and -SelectionPath (the human's
         chosen subset). Every email in -SelectionPath must appear in -RosterPath's
         MemberPrimarySmtpAddress column -- an email that doesn't is treated as a hard error (a
         typo, or a stale selection file referencing a member no longer in the roster), never
         silently accepted, since accepting an unverified address would defeat the roster's purpose
         as this decision's own audit trail. Reads -DefinitionPath (an existing
         location-hold-definition.json-shaped file) and appends one new userSources[] entry per
         selected email not already present (matched case-insensitively against existing
         userSources[].email), each carrying a note recording which group roster it came from and
         the selection file's own stated reason. Writes the merged result to -OutputPath (default:
         a gitignored deploy/out/ location, never the tracked -DefinitionPath itself) unless
         -InPlace is set, in which case -DefinitionPath is overwritten directly -- after this script
         first copies the pre-merge file to a timestamped .bak alongside it, so an -InPlace run is
         still recoverable without relying on git history.
      2. Reconcile (-AddToHold only). Connects to Microsoft Graph (surface 3) and idempotently adds
         every *selected* member's email (not just the ones new to the definition file this run --
         find-or-create means an already-merged-but-never-reconciled email still gets added) as a
         userSource on the named -CaseId/-HoldId, using the identical find-or-create
         Confirm-UserSourceOnHold logic
         Resolve-TeamsGroupHoldLocations.ps1 and location-scoped-legal-hold/deploy/
         New-EdiscoveryLocationHold.ps1 both already use -- duplicated here, not dot-sourced, per
         this repo's self-contained-deploy-tree convention. $PSCmdlet.ShouldProcess() gates every
         write, so -WhatIf reports every merge/add this run would make without touching a file or
         calling a mutating Graph endpoint.

    Idempotent on every run: re-running the same -SelectionPath against an already-merged
    -DefinitionPath finds every selected email already present and adds nothing new; re-running
    -AddToHold against a hold policy where a member was already reconciled reports it present.

.PARAMETER RosterPath
    Path to the member-roster CSV produced by teams-group-hold-resolution's
    Resolve-TeamsGroupHoldLocations.ps1 -ResolveMembers (columns: Group, MemberDisplayName,
    MemberPrimarySmtpAddress).

.PARAMETER SelectionPath
    Path to a JSON file recording the human decision: { "reason": "<why these members>",
    "selectedEmails": [ "<email>", ... ] }. Every email must appear in -RosterPath. See
    deploy/config/roster-selection.sample.json.

.PARAMETER DefinitionPath
    Path to the existing location-hold-definition.json-shaped file to merge into (e.g.
    location-scoped-legal-hold/deploy/policy/location-hold-definition.json, or a matter-specific
    copy of it). Read only unless -InPlace is set.

.PARAMETER OutputPath
    Where to write the merged definition file. Defaults to
    'deploy/out/<DefinitionPath base name>.merged.json' -- a gitignored location, so a real merge's
    output (which may embed a case-specific -SelectionPath reason) is never accidentally committed.
    Ignored if -InPlace is set.

.PARAMETER InPlace
    Overwrite -DefinitionPath directly instead of writing to -OutputPath. Off by default -- the
    safer default is to inspect the merged file at -OutputPath before it replaces anything tracked
    in version control. When set, this script first copies -DefinitionPath to
    '<DefinitionPath>.bak-<yyyyMMddHHmmss>' in the same directory before overwriting it (skipped
    under -WhatIf).

.PARAMETER AddToHold
    After merging, reconcile every selected member's email onto an existing
    location-scoped-legal-hold hold policy via Microsoft Graph (idempotent find-or-create, so this
    covers a member already present in the definition file from an earlier run too). Requires
    -CaseId and -HoldId. Off
    by default -- inspect the merged file first, or hand it to
    location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1's own -DefinitionPath yourself,
    before this script starts writing to a live hold policy.

.PARAMETER CaseId
.PARAMETER HoldId
    The eDiscoveryCase id and ediscoveryHoldPolicy id to reconcile onto. Required with -AddToHold.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Microsoft Graph app-only authentication parameters, used only for the -AddToHold path -- same
    shape as location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1 and
    teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1.

.EXAMPLE
    ./Merge-RosterIntoHoldDefinition.ps1 `
        -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
        -SelectionPath ./config/roster-selection.sample.json `
        -DefinitionPath ../location-scoped-legal-hold/deploy/policy/location-hold-definition.json `
        -WhatIf

    Dry run: reports which selected members would be appended as new userSources, and where the
    merged file would be written. Touches no file.

.EXAMPLE
    ./Merge-RosterIntoHoldDefinition.ps1 `
        -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
        -SelectionPath ./config/roster-selection.sample.json `
        -DefinitionPath ../location-scoped-legal-hold/deploy/policy/location-hold-definition.json `
        -AddToHold -CaseId $caseId -HoldId $holdId `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Merges to deploy/out/location-hold-definition.merged.json AND reconciles every selected
    member directly onto the named hold policy.

.NOTES
    Grounded in Microsoft Learn (README.md Section 12, inherited unchanged from the two sibling
    scenarios this fragment connects -- no new product fact is introduced here): the userSources[]
    shape and Create userSource v1.0 Graph endpoint are identical to
    location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1's own grounding; the roster
    CSV shape is identical to teams-group-hold-resolution/deploy/
    Resolve-TeamsGroupHoldLocations.ps1's own output.

    This script never re-validates roster freshness against current group membership (no
    Get-UnifiedGroupLinks call) -- the roster's own point-in-time-snapshot nature is
    teams-group-hold-resolution's documented behavior (its own README.md Section 11), not something
    this hand-off script re-implements. If a selected member has since left the group, this script
    still merges them (the roster is the audit record of who the human's decision was based on, not
    a live membership check) -- confirm current membership out-of-band before relying on a roster
    older than a few days.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RosterPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SelectionPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [string]$OutputPath,

    [switch]$InPlace,

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

function Confirm-UserSourceOnHold {
    # Duplicated from location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1's
    # Confirm-UserSource / teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1's
    # Confirm-UserSourceOnHold -- not dot-sourced, per this repo's self-contained-deploy-tree
    # convention.
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
    if ($PSCmdlet.ShouldProcess($Email, "Add member mailbox as userSource on hold policy $HoldId")) {
        Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json) | Out-Null
        Write-Host "Added userSource '$Email' to hold policy $HoldId."
    }
}

# --- validate parameter combinations up front ---

if ($AddToHold -and (-not $CaseId -or -not $HoldId)) {
    throw '-AddToHold requires both -CaseId and -HoldId.'
}
if ($AddToHold -and (-not $AppId -or -not $TenantId -or (-not $CertificateThumbprint -and -not $Certificate))) {
    throw '-AddToHold requires Microsoft Graph app-only auth parameters: -AppId, -TenantId, and either -CertificateThumbprint or -Certificate.'
}
if ($InPlace -and $OutputPath) {
    Write-Warning "-InPlace was specified together with -OutputPath -- -OutputPath ('$OutputPath') is ignored; the merged result is written to -DefinitionPath ('$DefinitionPath') instead."
}

# --- load and cross-validate the roster + selection ---

$rosterRows = @(Import-Csv -Path $RosterPath)
if ($rosterRows.Count -eq 0) {
    throw "'$RosterPath' contains no rows -- nothing to select from."
}
$rosterByEmail = @{}
foreach ($row in $rosterRows) {
    $rosterByEmail[$row.MemberPrimarySmtpAddress.ToLowerInvariant()] = $row
}

$selection = Get-Content -Path $SelectionPath -Raw | ConvertFrom-Json
# Property-presence check first, not direct access -- Set-StrictMode -Version Latest throws on
# PSCustomObject dot-access to a key that doesn't exist at all (same gotcha
# teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1 already hit and fixed for
# its own optional 'resolveMembers' key; here 'selectedEmails' is documented as required, but a
# malformed selection file omitting the key entirely must still fail with this script's own clear
# error message, not an unhandled PropertyNotFoundException).
$hasSelectedEmails = $selection.PSObject.Properties.Name -contains 'selectedEmails'
if (-not $hasSelectedEmails -or @($selection.selectedEmails).Count -eq 0) {
    throw "'$SelectionPath' declares no entries under 'selectedEmails'."
}
$reason = if ($selection.PSObject.Properties.Name -contains 'reason') { $selection.reason } else { '(no reason recorded in selection file)' }

# Case-insensitive de-duplication (preserves first-seen casing) -- Select-Object -Unique alone is
# case-sensitive and would treat 'Alex@contoso.com' and 'alex@contoso.com' as two entries.
$seenEmails = New-Object System.Collections.Generic.HashSet[string]
$selectedEmails = @($selection.selectedEmails | Where-Object { $seenEmails.Add($_.ToLowerInvariant()) })
$unresolvedSelections = @($selectedEmails | Where-Object { -not $rosterByEmail.ContainsKey($_.ToLowerInvariant()) })
if ($unresolvedSelections.Count -gt 0) {
    throw "The following selectedEmails in '$SelectionPath' do not appear in '$RosterPath''s MemberPrimarySmtpAddress column: $($unresolvedSelections -join ', '). Fix the selection file or re-run Resolve-TeamsGroupHoldLocations.ps1 -ResolveMembers to refresh the roster -- this script never adds an email it cannot verify against a roster row."
}

# --- load the definition file to merge into ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json
$existingUserSources = if ($definition.PSObject.Properties.Name -contains 'userSources') { @($definition.userSources) } else { @() }
$existingEmails = @($existingUserSources | ForEach-Object { $_.email.ToLowerInvariant() })

$toAdd = @()
$alreadyPresent = @()
foreach ($email in $selectedEmails) {
    if ($existingEmails -contains $email.ToLowerInvariant()) {
        $alreadyPresent += $email
        continue
    }
    $rosterRow = $rosterByEmail[$email.ToLowerInvariant()]
    $toAdd += [pscustomobject]@{
        email = $email
        note  = "Individual member of '$($rosterRow.Group)' ($($rosterRow.MemberDisplayName)) added via roster-to-hold-locations/deploy/Merge-RosterIntoHoldDefinition.ps1. Reason: $reason"
    }
}

Write-Host "Selection: $($selectedEmails.Count) email(s) -- $($toAdd.Count) new, $($alreadyPresent.Count) already present in '$DefinitionPath'."
if ($alreadyPresent.Count -gt 0) {
    Write-Verbose "Already present, skipped: $($alreadyPresent -join ', ')"
}

# --- resolve output path ---

if ($InPlace) {
    $OutputPath = $DefinitionPath
} elseif (-not $OutputPath) {
    # Anchored to this script's own deploy/out/, not -DefinitionPath's directory -- DefinitionPath
    # points at a foreign scenario's tracked policy file (e.g.
    # ../location-scoped-legal-hold/deploy/policy/), and this scenario's own gitignored out/ is the
    # right default landing spot for a merge result that may embed a case-specific -SelectionPath
    # reason, consistent with every other out/-writing script in this library.
    $defaultOutDir = Join-Path $PSScriptRoot 'out'
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($DefinitionPath)
    $OutputPath = Join-Path $defaultOutDir "$baseName.merged.json"
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# --- write merged definition (Stage 1) ---

if ($toAdd.Count -eq 0) {
    Write-Host 'Nothing new to merge -- every selected email is already present in the definition file.'
} else {
    $mergedUserSources = @($existingUserSources) + @($toAdd)
    $merged = $definition | Select-Object *
    $merged | Add-Member -NotePropertyName userSources -NotePropertyValue $mergedUserSources -Force

    if ($InPlace -and (Test-Path $DefinitionPath)) {
        $backupPath = "$DefinitionPath.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
        if ($PSCmdlet.ShouldProcess($backupPath, 'Back up definition file before in-place overwrite')) {
            Copy-Item -Path $DefinitionPath -Destination $backupPath
            Write-Host "Backed up pre-merge definition file to '$backupPath'."
        }
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, "Write merged definition file with $($toAdd.Count) new userSource(s)")) {
        $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding utf8
        Write-Host "Wrote merged definition to '$OutputPath' ($($toAdd.Count) new userSource(s) added)."
    }
}

# --- reconcile onto a live hold (Stage 2, optional) ---

if ($AddToHold) {
    # Reconciles every *selected* email, not just $toAdd (the ones new to the file this run) --
    # Confirm-UserSourceOnHold is its own idempotent find-or-create, so an email that was already
    # present in the definition file (e.g. merged into it by an earlier run) but never actually
    # reconciled onto the live hold still needs this pass to add it. Scoping Stage 2 to only
    # $toAdd would silently skip that case -- a real gap caught during this scenario's own
    # four-lens review (reviews.md, Red Team).
    if (Get-MgContext) {
        Write-Verbose 'Reusing existing Microsoft Graph connection.'
    } else {
        $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
        if ($Certificate) { $connectParams['Certificate'] = $Certificate }
        else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
        Connect-MgGraph @connectParams
    }

    foreach ($email in $selectedEmails) {
        Confirm-UserSourceOnHold -CaseId $CaseId -HoldId $HoldId -Email $email
    }
    Write-Host "Done. Reconciled $($selectedEmails.Count) selected member(s) onto hold policy $HoldId (case $CaseId)."
    Write-Host '../location-scoped-legal-hold/validate/Test-EdiscoveryLocationHold.ps1 to confirm hold status, or ./../validate/Test-RosterHoldDefinitionMerge.ps1 for this scenario''s own checks.'
} else {
    Write-Host "Merge-only run complete. Inspect '$OutputPath', then feed it to location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1 -DefinitionPath yourself, or re-run this script with -AddToHold -CaseId -HoldId to reconcile directly."
}
```