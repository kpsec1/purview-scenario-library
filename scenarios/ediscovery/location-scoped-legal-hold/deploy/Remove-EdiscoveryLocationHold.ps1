#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Staged rollback for the eDiscovery location-scoped-legal-hold scenario: remove one or more
    named locations (userSources/siteSources) from a hold policy, or delete the entire hold
    policy outright.

.DESCRIPTION
    Mirrors the staged approach in rollback.md. Unlike the sibling
    premium-legal-hold-and-export scenario's custodian release (a reversible "release, re-apply
    later" action with its own release endpoint), the v1.0 Graph API exposes no "turn off and
    keep for later" action for an ediscoveryHoldPolicy -- enablePolicy/disablePolicy exist only
    in the beta namespace (design.md section 4). On v1.0 there are exactly two ways to stop a
    location-scoped hold from preserving content:
      1. Delete one userSource or siteSource (releases that single location; the policy and its
         other locations are untouched).
      2. Delete the entire ediscoveryHoldPolicy (-DeleteHold) -- releases every location in it at
         once. There is no partial, reversible "pause" in between on v1.0.

    Both actions carry the same Microsoft-documented warning, quoted directly rather than
    softened: "Turning off a hold policy might result in the permanent deletion of any content
    currently being preserved" / "When you delete a hold policy ... This action might result in
    permanent deletion of any content currently being preserved" (README.md section 12). This
    script never deletes mailbox/SharePoint content itself -- it only removes the eDiscovery
    hold that was preserving it; whatever normal retention/deletion processing already applies
    (or doesn't) to that location resumes once the hold is gone, per rollback.md "What rollback
    does not undo."

.PARAMETER CaseId
    The eDiscoveryCase id to act on.

.PARAMETER HoldId
    The ediscoveryHoldPolicy id to act on.

.PARAMETER UserSourceEmail
    One or more userSource email addresses to remove from the hold. If omitted (and
    -SiteSourceUrl is also omitted), every userSource and siteSource currently on the hold is
    removed -- functionally equivalent to (but not the same API call as) deleting the policy;
    prefer -DeleteHold for that case, since it also clears the policy object itself.

.PARAMETER SiteSourceUrl
    One or more SharePoint site URLs to remove from the hold.

.PARAMETER DeleteHold
    Permanently delete the entire hold policy object (all its sources with it) rather than
    removing sources individually. Not reversible -- re-establishing the hold means re-running
    deploy/New-EdiscoveryLocationHold.ps1 against a new hold policy.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy script.

.EXAMPLE
    ./Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
        -UserSourceEmail 'payments-compliance-dl@contoso.com' `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports that this run would remove one named location, without removing anything.

.EXAMPLE
    ./Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId -DeleteHold `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Permanently deletes the entire hold policy after the loud confirmation prompt (or
    unattended, if -Confirm:$false is also supplied by the caller).

.NOTES
    Grounded in Microsoft Learn: Delete userSource / Delete siteSource
    (DELETE .../legalHolds/{id}/userSources/{id} and .../siteSources/{id}) and Delete
    ediscoveryHoldPolicy (DELETE .../legalHolds/{id}), all v1.0. No typed cmdlet exists for any
    of these three operations (design.md section 4) -- Invoke-MgGraphRequest is used throughout,
    matching New-EdiscoveryLocationHold.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$HoldId,

    [string[]]$UserSourceEmail,
    [string[]]$SiteSourceUrl,

    [switch]$DeleteHold,

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

$script:GraphBase = 'https://graph.microsoft.com/v1.0'
$holdBaseUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId"

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

if ($DeleteHold) {
    Write-Warning "Deleting hold policy $HoldId releases every location in it at once. Microsoft's own documentation: 'When you delete a hold policy, you remove all associated holds and release all sites and mailboxes. This action might result in permanent deletion of any content currently being preserved.' Confirm the preservation duty for every location in this policy has actually lapsed before continuing (rollback.md)."
    if ($PSCmdlet.ShouldProcess($HoldId, 'PERMANENTLY DELETE eDiscovery location-scoped hold policy')) {
        Invoke-MgGraphRequest -Method DELETE -Uri $holdBaseUri | Out-Null
        Write-Host "Deleted hold policy $HoldId. This cannot be undone -- see rollback.md."
    }
    Write-Host 'Done.'
    return
}

$userSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdBaseUri/userSources").value)
$siteSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdBaseUri/siteSources").value)

$userTargets = if ($UserSourceEmail) {
    $userSources | Where-Object { $_.email -in $UserSourceEmail }
} elseif (-not $SiteSourceUrl) {
    $userSources
} else {
    @()
}

$siteTargets = if ($SiteSourceUrl) {
    $siteTitles = $SiteSourceUrl | ForEach-Object { ($_ -split '/')[-1] }
    $siteSources | Where-Object { $_.displayName -in $siteTitles }
} elseif (-not $UserSourceEmail) {
    $siteSources
} else {
    @()
}

if (-not $userTargets -and -not $siteTargets) {
    Write-Host 'No matching userSources/siteSources found -- nothing to release.'
} else {
    foreach ($source in $userTargets) {
        if ($PSCmdlet.ShouldProcess($source.email, "Remove userSource from hold policy $HoldId")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$holdBaseUri/userSources/$($source.id)" | Out-Null
            Write-Host "Removed userSource '$($source.email)' from hold policy $HoldId."
        }
    }
    foreach ($source in $siteTargets) {
        if ($PSCmdlet.ShouldProcess($source.displayName, "Remove siteSource from hold policy $HoldId")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$holdBaseUri/siteSources/$($source.id)" | Out-Null
            Write-Host "Removed siteSource '$($source.displayName)' from hold policy $HoldId."
        }
    }
}

Write-Host 'Done. The hold policy object itself still exists -- pass -DeleteHold to remove it entirely, or re-run deploy/New-EdiscoveryLocationHold.ps1 to add locations back.'
