#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'MSAL.PS'; ModuleVersion = '4.61.3' }

<#
.SYNOPSIS
    Downloads an eDiscovery (Premium) review-set export package and its report files, once the
    export operation started by New-EdiscoverySearchReviewSetExport.ps1 has succeeded.

.DESCRIPTION
    Third-stage deploy script for the eDiscovery (Premium) legal-hold-and-export scenario.
    Implements the pattern Microsoft documents in "Use Microsoft Purview APIs for eDiscovery"
    (README.md section 12, reference 5): the export *package* is not downloaded through Microsoft
    Graph. It is downloaded through a separate Microsoft Purview eDiscovery API, authenticated
    with its own token (via MSAL.PS's Get-MsalToken, scope
    00001111-aaaa-2222-bbbb-3333cccc4444/.default -- this is Microsoft's own documented resource
    GUID for the MicrosoftPurviewEDiscovery first-party app, not invented here) -- separate from
    the Microsoft.Graph.Authentication token used to look up the export operation itself.

    This requires a *second* app registration step beyond the one used by the other two deploy
    scripts: registering (or reusing) the MicrosoftPurviewEDiscovery service principal in the
    tenant and granting the calling app the eDiscovery.Download.Read application permission
    against it. See README.md section 5 step 6 and reference 5 for the exact portal/PowerShell
    steps -- this script assumes that prerequisite is already in place and fails fast with a
    clear error if the download token request is rejected, rather than guessing at a remediation.

    Idempotent: skips any file already present locally with a matching byte size, so re-running
    this script after a partial download (or to pick up a second export from the same case) does
    not re-download files unnecessarily.

.PARAMETER CaseId
    The eDiscoveryCase id (from New-EdiscoveryPremiumLegalHold.ps1 / the Purview portal).

.PARAMETER ExportOperationId
    The caseOperation id for the completed export (printed by
    New-EdiscoverySearchReviewSetExport.ps1, or read from the case's Exports tab -> "Copy support
    information" in the portal).

.PARAMETER OutputDirectory
    Local directory to download the export package and report files into. Created if it doesn't
    exist. Treat this directory as containing case-sensitive/privileged litigation content --
    apply the same access controls and retention discipline your organization applies to any
    outside-counsel production set.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for both the Graph token and the
    separate download token.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for app-only auth (both tokens). Mutually exclusive with -Certificate.

.PARAMETER Certificate
    In-memory X509Certificate2 for app-only auth. Mutually exclusive with -CertificateThumbprint.

.EXAMPLE
    ./Get-EdiscoveryExportPackage.ps1 -CaseId $caseId -ExportOperationId $opId `
        -OutputDirectory ./exports/CONTOSO-LIT-2026-014-export1 `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Lists every file the export contains and its size, without downloading anything.

.EXAMPLE
    ./Get-EdiscoveryExportPackage.ps1 -CaseId $caseId -ExportOperationId $opId `
        -OutputDirectory ./exports/CONTOSO-LIT-2026-014-export1 `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Grounded in Microsoft Learn: "Use Microsoft Purview APIs for eDiscovery" (README.md section
    12, reference 5) -- this script is a parameterized, idempotent adaptation of Microsoft's own
    published DownloadExportUsingAppCert.ps1 reference script from that page, changed to: accept
    an already-established Graph connection or connect via the shared connect pattern used by
    this repo's other deploy scripts; skip files that already exist locally with a matching size;
    and support -WhatIf. The MSAL.PS scope GUID (00001111-aaaa-2222-bbbb-3333cccc4444) and the
    exportFileMetadata.downloadUrl / X-AllowWithAADToken header pattern are copied verbatim from
    that Microsoft-published example, not independently re-derived.

    Export packages must be downloaded within 30 days of the export operation completing --
    Microsoft's own guidance states export processes are retained for the life of the case, but
    the *content* is deleted 30 days after completion (README.md section 11, reference 6).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$ExportOperationId,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

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

# Microsoft's own documented resource scope for the separate eDiscovery export-download token --
# see .NOTES. Not a tenant-specific value; do not treat as a secret.
$DownloadTokenScope = '00001111-aaaa-2222-bbbb-3333cccc4444/.default'

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

$operationUri = "/v1.0/security/cases/ediscoveryCases/$CaseId/operations/$ExportOperationId"
$operation = Invoke-MgGraphRequest -Method GET -Uri $operationUri
if (-not $operation) {
    throw "No operation found at $operationUri -- confirm -CaseId/-ExportOperationId are correct."
}
if ($operation.status -ne 'succeeded') {
    Write-Warning "Export operation status is '$($operation.status)', not 'succeeded'. Files listed below (if any) may be incomplete. Re-run after the export finishes -- see New-EdiscoverySearchReviewSetExport.ps1's poll loop or the portal's Exports tab."
}

$files = $operation.exportFileMetadata
if (-not $files -or $files.Count -eq 0) {
    Write-Warning 'No exportFileMetadata entries returned for this operation -- nothing to download yet.'
    return
}

if (-not (Test-Path $OutputDirectory)) {
    if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create output directory')) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
}

# Acquire the separate download token -- a client-secret or certificate credential object built
# the same way the ExchangeOnlineManagement/Graph connections in this repo's other scripts are.
$tokenParams = @{ ClientId = $AppId; TenantId = $TenantId; Scopes = $DownloadTokenScope }
if ($Certificate) {
    $tokenParams['ClientCertificate'] = $Certificate
} elseif ($CertificateThumbprint) {
    $tokenParams['ClientCertificate'] = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint"
} else {
    throw 'Either -Certificate or -CertificateThumbprint is required to acquire the download token.'
}
$downloadToken = Get-MsalToken @tokenParams

foreach ($file in $files) {
    $destination = Join-Path $OutputDirectory $file.fileName
    if ((Test-Path $destination) -and (Get-Item $destination).Length -eq $file.size) {
        Write-Verbose "Skipping '$($file.fileName)' -- already downloaded with matching size ($($file.size) bytes)."
        continue
    }

    if ($PSCmdlet.ShouldProcess($file.fileName, "Download $($file.size) bytes to $destination")) {
        Invoke-WebRequest -Uri $file.downloadUrl -OutFile $destination -Headers @{
            'Authorization'        = "Bearer $($downloadToken.AccessToken)"
            'X-AllowWithAADToken'  = 'true'
        }
        Write-Host "Downloaded '$($file.fileName)' ($($file.size) bytes) to $destination."
    } else {
        Write-Host "[WhatIf] Would download '$($file.fileName)' ($($file.size) bytes) to $destination."
    }
}

Write-Host "Done. $($files.Count) file(s) processed for operation $ExportOperationId."
