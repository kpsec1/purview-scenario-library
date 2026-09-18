---
part: "validate"
parent: "ediscovery/location-scoped-legal-hold"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EdiscoveryLocationHold.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Verifies a location-scoped eDiscovery hold policy built by New-EdiscoveryLocationHold.ps1:
    the case and hold policy exist, every declared userSource/siteSource is present and applied,
    and the policy itself reports no errors.

.DESCRIPTION
    Read-only. Requires only eDiscovery.Read.All (README.md section 3) -- never calls a mutating
    Graph endpoint. Exits non-zero on any hard [FAIL], so it's safe to use as a CI-style
    pre-flight or a scheduled drift check (README.md section 8), the same pattern
    scenarios/ediscovery/premium-legal-hold-and-export/validate/Test-EdiscoveryPremiumCaseSetup.ps1
    establishes.

    Checks:
      1. Case exists with the expected DisplayName.
      2. Hold policy exists with the expected DisplayName/contentQuery.
      3. Every userSource in the definition file exists and has holdStatus 'applied' (or
         'applying', reported WARN not FAIL -- see README.md section 11 on propagation timing).
      4. Every siteSource in the definition file exists (matched by title) and has holdStatus
         'applied'/'applying'.
      5. The policy's own `errors` collection is empty; a non-empty collection is reported FAIL
         with the raw error text, since Microsoft's error taxonomy (README.md section 12) maps
         directly to a remediation step.

.PARAMETER DefinitionPath
    Same JSON definition file used by New-EdiscoveryLocationHold.ps1.

.PARAMETER CaseId
.PARAMETER HoldId
    The eDiscoveryCase id and ediscoveryHoldPolicy id to validate.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy scripts. A read-only credential
    (eDiscovery.Read.All only) is sufficient and preferred for this script.

.EXAMPLE
    ./Test-EdiscoveryLocationHold.ps1 -DefinitionPath ../deploy/policy/location-hold-definition.json `
        -CaseId $caseId -HoldId $holdId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Manual verification checklist (no read API exists for these -- confirm in the Purview
    portal, Hold policies tab):
      - The hold policy's own portal-rendered state (Draft/On/In progress/Off/Pending deletion,
        README.md section 12) -- the per-source holdStatus this script reads is a finer-grained
        signal but is not documented as a 1:1 mapping to the portal's policy-level state label.
      - Whether any condition filters or KeyQL filters were added to the policy directly in the
        portal after this scenario's own deploy run -- this script and the deploy script only
        know about the single contentQuery property, not the portal's richer filter UI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$HoldId,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
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

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

# 1. Case
try {
    $case = Get-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId
} catch {
    Write-Check "Could not retrieve case $CaseId -- $($_.Exception.Message)" -Level FAIL
    exit 1
}
if ($case.DisplayName -eq $definition.case.displayName) {
    Write-Check "Case exists with expected DisplayName '$($case.DisplayName)'." -Level PASS
} else {
    Write-Check "Case $CaseId DisplayName is '$($case.DisplayName)', expected '$($definition.case.displayName)'." -Level WARN
}

# 2. Hold policy
$holdUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId"
try {
    $hold = Invoke-MgGraphRequest -Method GET -Uri $holdUri
} catch {
    Write-Check "Could not retrieve hold policy $HoldId -- $($_.Exception.Message)" -Level FAIL
    exit 1
}
if ($hold.displayName -eq $definition.hold.displayName) {
    Write-Check "Hold policy exists with expected DisplayName '$($hold.displayName)'." -Level PASS
} else {
    Write-Check "Hold policy $HoldId DisplayName is '$($hold.displayName)', expected '$($definition.hold.displayName)'." -Level WARN
}
if ($definition.hold.contentQuery -and $hold.contentQuery -ne $definition.hold.contentQuery) {
    Write-Check "Hold policy contentQuery differs from the definition file (portal edit since deploy?). Current: '$($hold.contentQuery)'" -Level WARN
} elseif (-not $hold.contentQuery) {
    Write-Check 'Hold policy has no contentQuery -- it holds ALL content in every location, not a filtered subset. Confirm this is intentional.' -Level WARN
}

# 5. Policy-level errors (checked early so 3/4's per-source detail has this context)
if ($hold.errors -and @($hold.errors).Count -gt 0) {
    foreach ($err in $hold.errors) {
        Write-Check "Hold policy reports an error: $err -- see 'Manage hold status errors' (README.md section 12) for the matching remediation, then re-run deploy/New-EdiscoveryLocationHold.ps1 -Retry." -Level FAIL
    }
} else {
    Write-Check 'Hold policy reports no errors.' -Level PASS
}

# 3. userSources
$actualUserSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdUri/userSources").value)
foreach ($userSourceDef in $definition.userSources) {
    $source = $actualUserSources | Where-Object { $_.email -eq $userSourceDef.email } | Select-Object -First 1
    if (-not $source) {
        Write-Check "userSource '$($userSourceDef.email)' not found on hold policy $HoldId." -Level FAIL
        continue
    }
    switch ($source.holdStatus) {
        'applied' { Write-Check "userSource '$($userSourceDef.email)' holdStatus is 'applied'." -Level PASS }
        'applying' { Write-Check "userSource '$($userSourceDef.email)' holdStatus is 'applying' -- still propagating; re-check before treating as a failure." -Level WARN }
        default { Write-Check "userSource '$($userSourceDef.email)' holdStatus is '$($source.holdStatus)' -- expected 'applied'." -Level FAIL }
    }
}

# 4. siteSources (matched by title, the closest available client-side key -- see
# deploy/New-EdiscoveryLocationHold.ps1's Confirm-SiteSource comment and README.md section 11)
$actualSiteSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdUri/siteSources").value)
foreach ($siteSourceDef in $definition.siteSources) {
    $siteTitle = ($siteSourceDef.site -split '/')[-1]
    $source = $actualSiteSources | Where-Object { $_.displayName -eq $siteTitle } | Select-Object -First 1
    if (-not $source) {
        Write-Check "siteSource for '$($siteSourceDef.site)' (matched by title '$siteTitle') not found on hold policy $HoldId." -Level FAIL
        continue
    }
    switch ($source.holdStatus) {
        'applied' { Write-Check "siteSource '$($siteSourceDef.site)' holdStatus is 'applied'." -Level PASS }
        'applying' { Write-Check "siteSource '$($siteSourceDef.site)' holdStatus is 'applying' -- still propagating; re-check before treating as a failure." -Level WARN }
        default { Write-Check "siteSource '$($siteSourceDef.site)' holdStatus is '$($source.holdStatus)' -- expected 'applied'." -Level FAIL }
    }
}

Write-Host ''
Write-Host "Summary: $script:FailCount FAIL, $script:WarnCount WARN."
if ($script:FailCount -gt 0) { exit 1 } else { exit 0 }
```