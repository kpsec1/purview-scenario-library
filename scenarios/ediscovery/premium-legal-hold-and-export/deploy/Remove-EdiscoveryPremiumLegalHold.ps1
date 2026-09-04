#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Staged rollback for the eDiscovery (Premium) legal-hold-and-export scenario: release the
    hold on one or more custodians, and optionally close or delete the case.

.DESCRIPTION
    Mirrors the staged approach in rollback.md: releasing a hold is reversible (a released
    custodian can be re-held with New-EdiscoveryPremiumLegalHold.ps1), while closing or deleting
    the case is progressively more destructive. Default behavior only releases holds -- closing
    or deleting the case requires an explicit switch, because Microsoft's own documentation warns
    that closing or deleting a case turns off *every* hold in it and releases any content that
    was preserved only by that hold (README.md section 9 / rollback.md).

    This script never deletes mailbox/OneDrive content itself -- it only removes the eDiscovery
    hold that was preserving it. Whether content becomes eligible for normal deletion/retention
    processing after the hold is released depends on whatever other retention policies (if any)
    independently apply to that mailbox or site -- see rollback.md "What rollback does not undo".

.PARAMETER CaseId
    The eDiscoveryCase id to act on.

.PARAMETER CustodianEmail
    One or more custodian email addresses to release from hold. If omitted, every custodian
    currently on hold in the case is released.

.PARAMETER CloseCase
    After releasing holds, close the case (Microsoft Purview portal equivalent of Actions ->
    Close case). Closing turns off all holds in the case, including any not covered by
    -CustodianEmail -- confirm every custodian's hold is intended to end before passing this.

.PARAMETER DeleteCase
    Permanently delete the case. Implies -CloseCase. Not reversible -- re-establishing the case
    means re-running New-EdiscoveryPremiumLegalHold.ps1 / New-EdiscoverySearchReviewSetExport.ps1
    from scratch against a new case id.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the other deploy/ scripts.

.EXAMPLE
    ./Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports which custodians would be released, without releasing anything.

.EXAMPLE
    ./Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId -CustodianEmail 'dana.chen@contoso.com' `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Releases the hold on a single named custodian; the case and its other custodians (if any)
    are untouched.

.NOTES
    Grounded in Microsoft Learn: ediscoveryCustodian: release (POST .../custodians/{id}/release,
    README.md section 12) and the case-close/delete warning in "Create and manage cases in
    eDiscovery" (README.md section 12). -DeleteCase uses Remove-MgSecurityCaseEdiscoveryCase.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [string[]]$CustodianEmail,

    [switch]$CloseCase,
    [switch]$DeleteCase,

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

if ($DeleteCase) { $CloseCase = $true }

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$allCustodians = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All
$targets = if ($CustodianEmail) {
    $allCustodians | Where-Object { $_.Email -in $CustodianEmail }
} else {
    $allCustodians | Where-Object { $_.HoldStatus -eq 'success' }
}

if (-not $targets) {
    Write-Host 'No matching custodians on hold -- nothing to release.'
} else {
    foreach ($custodian in $targets) {
        if ($PSCmdlet.ShouldProcess($custodian.Email, "Release eDiscovery hold (case $CaseId)")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "/v1.0/security/cases/ediscoveryCases/$CaseId/custodians/$($custodian.Id)/release" | Out-Null
            Write-Host "Released hold for custodian '$($custodian.Email)'."
        }
    }
}

if ($CloseCase) {
    Write-Warning 'Closing the case turns off every hold in it, including any custodian not passed via -CustodianEmail. Confirm this is intended before continuing (rollback.md).'
    if ($PSCmdlet.ShouldProcess($CaseId, 'Close eDiscovery case')) {
        Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId -Status 'closed'
        Write-Host "Closed case $CaseId."
    }
}

if ($DeleteCase) {
    if ($PSCmdlet.ShouldProcess($CaseId, 'PERMANENTLY DELETE eDiscovery case')) {
        Remove-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $CaseId
        Write-Host "Deleted case $CaseId. This cannot be undone -- see rollback.md."
    }
}

Write-Host 'Done.'
