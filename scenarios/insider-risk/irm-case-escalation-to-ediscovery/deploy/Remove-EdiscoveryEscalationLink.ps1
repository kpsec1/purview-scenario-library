#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Undoes what Confirm-EdiscoveryEscalationLink.ps1 added: the provenance block it stamped onto
    the eDiscovery case description, and (opt-in) the custodian hold it applied.

.DESCRIPTION
    Deliberately narrow, staged rollback -- see rollback.md for the full procedure and why each
    stage is separately gated:
      1. Default (no switches): removes only the delimited "IRM ESCALATION PROVENANCE" block from
         the case description, leaving any other description text an investigator wrote untouched.
         Safe, reversible (re-run Confirm-EdiscoveryEscalationLink.ps1 to re-stamp it), and never
         touches the custodian/hold or the case itself.
      2. -ReleaseHold: additionally calls the custodian 'release' action (the same
         Invoke-MgGraphRequest POST .../custodians/{id}/release pattern as the sibling scenario's
         own Remove-EdiscoveryPremiumLegalHold.ps1) for the custodian named in the definition file.
         Releasing a hold this scenario placed for an active IRM investigation can itself be a
         preservation failure -- this switch exists for the case actually resolves as benign, not
         as a routine cleanup step. See rollback.md's counsel-confirmation gate.

    This script never closes or deletes the eDiscoveryCase itself, and never touches the source
    Insider Risk Management case (no Graph/PowerShell write API exists for either IRM case
    resolution or, per design.md section 1, the escalation relationship). Closing/deleting the
    case is scenarios/ediscovery/premium-legal-hold-and-export/deploy/Remove-EdiscoveryPremiumLegalHold.ps1's
    job -- deliberately not duplicated here, since it operates on the same case object this
    scenario only adds a custodian/provenance block to.

.PARAMETER DefinitionPath
    Path to the same JSON file passed to Confirm-EdiscoveryEscalationLink.ps1.

.PARAMETER ReleaseHold
    Also release the eDiscovery hold on the custodian named in the definition file. Requires
    written confirmation that the IRM case resolved in a way that ends the preservation duty --
    see rollback.md and the counsel-confirmation gate this scenario inherits from the sibling
    eDiscovery scenario.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as Confirm-EdiscoveryEscalationLink.ps1.

.EXAMPLE
    ./Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports what would be removed, makes no change.

.EXAMPLE
    ./Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -ReleaseHold -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Strips the provenance block AND releases the custodian's hold. Only run this after counsel
    has confirmed the preservation duty for this matter has lapsed (rollback.md).

.NOTES
    Grounded in Microsoft Learn -- same citation set as Confirm-EdiscoveryEscalationLink.ps1 and
    scenarios/ediscovery/premium-legal-hold-and-export/deploy/Remove-EdiscoveryPremiumLegalHold.ps1
    (README.md section 12). The custodian 'release' action has no typed Graph SDK cmdlet as of this
    build (same finding the sibling scenario already recorded) -- both scripts call it via
    Invoke-MgGraphRequest against the documented v1.0 REST action instead of a fabricated cmdlet
    name.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [switch]$ReleaseHold,

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

$ProvenanceMarkerStart = '--- IRM ESCALATION PROVENANCE (managed by irm-case-escalation-to-ediscovery; do not hand-edit between the markers) ---'
$ProvenanceMarkerEnd = '--- END IRM ESCALATION PROVENANCE ---'

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)

    if (Get-MgContext) {
        Write-Verbose 'Reusing existing Microsoft Graph connection.'
        return
    }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) {
        $connectParams['Certificate'] = $Certificate
    } else {
        $connectParams['CertificateThumbprint'] = $CertificateThumbprint
    }
    Connect-MgGraph @connectParams
}

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-MgSecurityCaseEdiscoveryCase -All |
    Where-Object { $_.DisplayName -eq $definition.ediscoveryCase.displayName } |
    Select-Object -First 1

if (-not $case) {
    Write-Warning "No eDiscovery case named '$($definition.ediscoveryCase.displayName)' was found -- nothing to roll back."
} else {
    $description = if ($case.Description) { $case.Description } else { '' }
    if ($description -like "*$ProvenanceMarkerStart*") {
        $pattern = [regex]::Escape($ProvenanceMarkerStart) + '.*?' + [regex]::Escape($ProvenanceMarkerEnd)
        $stripped = [regex]::Replace($description, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline).Trim()

        if ($PSCmdlet.ShouldProcess($case.DisplayName, 'Remove IRM escalation provenance block from case description')) {
            Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $case.Id -BodyParameter @{ description = $stripped } | Out-Null
            Write-Host "Removed provenance block from case '$($case.DisplayName)'."
        }
    } else {
        Write-Verbose "No provenance block found on case '$($case.DisplayName)' -- description left untouched."
    }

    if ($ReleaseHold) {
        $custodian = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $case.Id -All |
            Where-Object { $_.Email -eq $definition.irmCase.userPrincipalName } |
            Select-Object -First 1

        if (-not $custodian) {
            Write-Warning "No custodian '$($definition.irmCase.userPrincipalName)' found on case '$($case.DisplayName)' -- nothing to release."
        } elseif ($custodian.HoldStatus -ne 'success') {
            Write-Verbose "Custodian '$($custodian.Email)' HoldStatus is '$($custodian.HoldStatus)', not 'success' -- skipping release."
        } elseif ($PSCmdlet.ShouldProcess($custodian.Email, "RELEASE eDiscovery hold (case $($case.Id)) -- confirm the preservation duty has lapsed; see rollback.md")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "/v1.0/security/cases/ediscoveryCases/$($case.Id)/custodians/$($custodian.Id)/release" | Out-Null
            Write-Host "Released hold for custodian '$($custodian.Email)'."
        }
    }
}

Write-Host 'Done. This script never closes/deletes the eDiscovery case or touches the source Insider Risk Management case -- see rollback.md for those separate, more destructive stages.'
