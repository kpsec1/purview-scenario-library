---
part: "validate"
parent: "ediscovery/roster-to-hold-locations"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-RosterHoldDefinitionMerge.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Verifies the output of Merge-RosterIntoHoldDefinition.ps1: every selected email is present
    exactly once in the merged definition file, each still traces back to a real roster row, and --
    if a hold is named -- each is actually present and applied on it.

.DESCRIPTION
    Read-only throughout: never writes a file and never calls a mutating Graph endpoint. Three
    check groups, the third only if -CaseId/-HoldId are supplied:

      1. Selection-to-roster traceability -- re-checks every -SelectionPath email still appears in
         -RosterPath (catches a roster/selection pair that has drifted apart since the merge ran).
      2. Selection-to-merged-definition completeness -- confirms every selected email appears
         exactly once in -MergedDefinitionPath's userSources[], each carrying a non-empty note (the
         audit-trail field Merge-RosterIntoHoldDefinition.ps1 always writes).
      3. Hold reconciliation (only with -CaseId/-HoldId) -- confirms each selected email is present
         as a userSource on the named hold policy with holdStatus applied/applying, the same check
         shape scenarios/ediscovery/location-scoped-legal-hold/validate/
         Test-EdiscoveryLocationHold.ps1 and teams-group-hold-resolution/validate/
         Test-TeamsGroupHoldLocations.ps1 both already perform, scoped to just this script's own
         selected emails.

    Exits non-zero on any hard FAIL -- safe for a scheduled or pre-production check, the same
    convention every validate/ script in this library follows.

.PARAMETER RosterPath
    Same roster CSV passed to Merge-RosterIntoHoldDefinition.ps1's -RosterPath.

.PARAMETER SelectionPath
    Same selection JSON passed to Merge-RosterIntoHoldDefinition.ps1's -SelectionPath.

.PARAMETER MergedDefinitionPath
    Path to the merged definition file Merge-RosterIntoHoldDefinition.ps1 wrote (its -OutputPath,
    or -DefinitionPath itself if that run used -InPlace).

.PARAMETER CaseId
.PARAMETER HoldId
    Optional. If supplied, also confirms each selected email's holdStatus on this hold policy.
    Requires -AppId/-TenantId/-CertificateThumbprint (or -Certificate).

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Microsoft Graph app-only authentication parameters, used only when -CaseId/-HoldId are
    supplied. A read-only credential (eDiscovery.Read.All) is sufficient and preferred.

.EXAMPLE
    ./Test-RosterHoldDefinitionMerge.ps1 `
        -RosterPath ../deploy/config/teams-group-hold-members.roster.sample.csv `
        -SelectionPath ../deploy/config/roster-selection.sample.json `
        -MergedDefinitionPath ../deploy/out/location-hold-definition.merged.json

    Selection-to-roster and selection-to-merged-definition checks only.

.EXAMPLE
    ./Test-RosterHoldDefinitionMerge.ps1 `
        -RosterPath ../deploy/config/teams-group-hold-members.roster.sample.csv `
        -SelectionPath ../deploy/config/roster-selection.sample.json `
        -MergedDefinitionPath ../deploy/out/location-hold-definition.merged.json `
        -CaseId $caseId -HoldId $holdId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Adds the hold-reconciliation check.

.NOTES
    Does not re-check current group membership (no Exchange Online call) -- by design, matching
    Merge-RosterIntoHoldDefinition.ps1's own .NOTES: the roster is treated as the point-in-time
    audit record the human's selection was based on, not something this script re-validates live.
    If you need to confirm a selected member is still a current group member, run
    teams-group-hold-resolution/validate/Test-TeamsGroupHoldLocations.ps1's group-drift check
    against the same group separately.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RosterPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SelectionPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$MergedDefinitionPath,

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

$rosterRows = @(Import-Csv -Path $RosterPath)
$rosterEmails = @($rosterRows | ForEach-Object { $_.MemberPrimarySmtpAddress.ToLowerInvariant() })

$selection = Get-Content -Path $SelectionPath -Raw | ConvertFrom-Json
# Property-presence check first -- Set-StrictMode -Version Latest throws on PSCustomObject
# dot-access to a key that doesn't exist at all (same gotcha the deploy script's own .NOTES and
# teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1 already document).
$hasSelectedEmails = $selection.PSObject.Properties.Name -contains 'selectedEmails'
if (-not $hasSelectedEmails -or @($selection.selectedEmails).Count -eq 0) {
    Write-Check "'$SelectionPath' declares no entries under 'selectedEmails'." -Level FAIL
    exit 1
}
$selectedEmails = @($selection.selectedEmails | Select-Object -Unique)

$definition = Get-Content -Path $MergedDefinitionPath -Raw | ConvertFrom-Json
$mergedUserSources = if ($definition.PSObject.Properties.Name -contains 'userSources') { @($definition.userSources) } else { @() }

# 1. Selection-to-roster traceability
foreach ($email in $selectedEmails) {
    if ($rosterEmails -contains $email.ToLowerInvariant()) {
        Write-Check "'$email' traces back to a roster row in '$RosterPath'." -Level PASS
    } else {
        Write-Check "'$email' is in '$SelectionPath' but NOT found in '$RosterPath' -- the roster and selection files have drifted apart since the last merge." -Level FAIL
    }
}

# 2. Selection-to-merged-definition completeness
foreach ($email in $selectedEmails) {
    $matches = @($mergedUserSources | Where-Object { $_.email.ToLowerInvariant() -eq $email.ToLowerInvariant() })
    if ($matches.Count -eq 0) {
        Write-Check "'$email' is selected but NOT present in '$MergedDefinitionPath' userSources[] -- run Merge-RosterIntoHoldDefinition.ps1." -Level FAIL
    } elseif ($matches.Count -gt 1) {
        Write-Check "'$email' appears $($matches.Count) times in '$MergedDefinitionPath' userSources[] -- expected exactly once (duplicate entry, likely from a manual edit outside this script)." -Level FAIL
    } elseif (($matches[0].PSObject.Properties.Name -notcontains 'note') -or -not $matches[0].note) {
        Write-Check "'$email' is present in '$MergedDefinitionPath' but its userSource entry has no 'note' -- unexpected for an entry Merge-RosterIntoHoldDefinition.ps1 wrote; may have been added by hand." -Level WARN
    } else {
        Write-Check "'$email' is present in '$MergedDefinitionPath' userSources[] with an audit-trail note." -Level PASS
    }
}

# 3. Hold reconciliation (optional)
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
        } catch {
            Write-Check "Could not retrieve hold policy $HoldId in case $CaseId -- $($_.Exception.Message)" -Level FAIL
            $actualUserSources = @()
        }

        foreach ($email in $selectedEmails) {
            $userSource = $actualUserSources | Where-Object { $_.email -eq $email } | Select-Object -First 1
            if (-not $userSource) {
                Write-Check "'$email' not found as a userSource on hold policy $HoldId -- run Merge-RosterIntoHoldDefinition.ps1 -AddToHold." -Level FAIL
            } elseif ($userSource.holdStatus -eq 'applied') {
                Write-Check "'$email' userSource holdStatus is 'applied' on hold policy $HoldId." -Level PASS
            } elseif ($userSource.holdStatus -eq 'applying') {
                Write-Check "'$email' userSource holdStatus is 'applying' on hold policy $HoldId -- still propagating." -Level WARN
            } else {
                Write-Check "'$email' userSource holdStatus is '$($userSource.holdStatus)' on hold policy $HoldId -- expected 'applied'." -Level FAIL
            }
        }
    }
} else {
    Write-Check '-CaseId/-HoldId not supplied -- skipped hold-reconciliation checks.' -Level WARN
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```