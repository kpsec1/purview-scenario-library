#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the Purview Data Map scan credential object created by New-PurviewScanCredential.ps1,
    and optionally the Azure Key Vault connection it referenced.

.DESCRIPTION
    Calls the Microsoft Purview Scanning data-plane REST API to delete, in order:
      1. The credential object   - DELETE {endpoint}/scan/credentials/{credentialName}
      2. (only with -RemoveKeyVaultConnection) the Key Vault connection -
         DELETE {endpoint}/scan/azureKeyVaults/{azureKeyVaultName}

    Both documented deletes return 204 No Content on success.

    ORDER MATTERS, and this script enforces it. A Key Vault connection can be referenced by many
    credentials; deleting the connection out from under a credential that still references it
    leaves that credential resolvable as metadata but broken at scan time. By default this script
    therefore refuses -RemoveKeyVaultConnection while any *other* credential still references the
    same connection, listing the offenders. Override with -Force only when you have confirmed
    those credentials are also being retired.

    Deleting a credential does NOT delete, disable, or modify:
      - The Azure Key Vault secret it pointed at (the secret is untouched - a credential holds only
        a reference, never the material).
      - Any scan object that references the credential by name. Such a scan is left in place and
        will start failing at its next run with an authentication error. Remove or re-point those
        scans first - see rollback.md Stage 1.
      - Catalog assets or classifications produced by prior successful scan runs.

    Idempotent: deleting an object that doesn't exist (already removed) is treated as success, not
    an error, so this script is safe to re-run.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Scanning REST API.
    Must hold the Data Source Administrator role on the target collection.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER CredentialName
    Name of the credential object to delete (matches -CredentialName used at deploy time).

.PARAMETER KeyVaultConnectionName
    Name of the Key Vault connection. Required only with -RemoveKeyVaultConnection.

.PARAMETER RemoveKeyVaultConnection
    Also delete the Key Vault connection object named by -KeyVaultConnectionName, after the
    reference check described above passes (or is overridden with -Force).

.PARAMETER Force
    Skip the "other credentials still reference this Key Vault connection" safety check. Has no
    effect without -RemoveKeyVaultConnection.

.PARAMETER ApiVersion
    Scanning data-plane REST API version to pin. Defaults to '2023-09-01'.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every DELETE that would be issued without
    sending it. The read-only reference check still runs under -WhatIf, so a dry run tells you
    whether the Key Vault deletion would have been blocked.

.EXAMPLE
    ./Remove-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' -WhatIf

    Dry-run: shows the credential DELETE that would be issued, changes nothing.

.EXAMPLE
    ./Remove-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
        -KeyVaultConnectionName 'kv-contoso-purview' -RemoveKeyVaultConnection

    Full teardown of this scenario's two objects, refusing to drop the Key Vault connection if any
    other credential still references it.

.NOTES
    Sources (Microsoft Learn, direct-fetched for this build):
    - Credential - Delete (DELETE /scan/credentials/{credentialName} -> 204):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/delete
    - Credential - List (GET /scan/credentials -> { count, nextLink, value[] }; used by the
      reference check below):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list
    - Key Vault Connections - Delete / Get:
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections

    LIMITATION (disclosed, not worked around): the reference check inspects only *credentials*. The
    Scanning API exposes no documented reverse-lookup of "which scans reference credential X", so
    this script cannot warn you that a live scan object still points at the credential being
    deleted. Enumerate scans per data source first if that matters - see rollback.md Stage 1 and
    README.md Section 11.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$CredentialName,

    [Parameter()]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$KeyVaultConnectionName,

    [Parameter()]
    [switch]$RemoveKeyVaultConnection,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if ($RemoveKeyVaultConnection -and -not $KeyVaultConnectionName) {
    throw "-KeyVaultConnectionName is required when -RemoveKeyVaultConnection is specified."
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"

function Get-PurviewAccessToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][SecureString]$ClientSecret
    )
    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret))
    try {
        $body = @{
            client_id     = $AppId
            client_secret = $plainSecret
            grant_type    = 'client_credentials'
            resource      = 'https://purview.azure.net'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }
    finally {
        $plainSecret = $null
    }
}

function Invoke-PurviewDelete {
    <#
        DELETE that treats 404 (already gone) as success, so re-running this script is idempotent.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if ($PSCmdlet.ShouldProcess($Description, "DELETE $Uri")) {
        try {
            Invoke-RestMethod -Method Delete -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } | Out-Null
            Write-Host "Removed: $Description" -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
                Write-Host "Already absent (404), nothing to do: $Description" -ForegroundColor DarkGray
            }
            else { throw }
        }
    }
    else {
        Write-Verbose "WhatIf: would DELETE $Uri ($Description)"
    }
}

function Get-PurviewCredentialList {
    <#
        GET /scan/credentials, following nextLink. Returns every credential object in the account.
    #>
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$ApiVersion
    )
    $all = @()
    $uri = "$Endpoint/scan/credentials`?api-version=$ApiVersion"
    while ($uri) {
        $page = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $Token" }
        if ($page.value) { $all += $page.value }
        $uri = $page.nextLink
    }
    return $all
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: delete the credential object ---
$credentialUri = "$endpoint/scan/credentials/$CredentialName`?api-version=$ApiVersion"
Invoke-PurviewDelete -Uri $credentialUri -Token $token `
    -Description "Credential '$CredentialName'"

# --- Step 2 (optional): delete the Key Vault connection ---
if ($RemoveKeyVaultConnection) {

    if (-not $Force) {
        # Safety check: is any OTHER credential still referencing this Key Vault connection?
        # A credential's store reference lives at properties.typeProperties.<secretProp>.store.referenceName,
        # where <secretProp> differs per kind (password / servicePrincipalKey / accountKey /
        # consumerSecret). Rather than enumerate kinds, walk every KeyVaultSecret-shaped child.
        Write-Verbose "Checking whether other credentials still reference Key Vault connection '$KeyVaultConnectionName'..."
        $others = @()
        foreach ($cred in Get-PurviewCredentialList -Endpoint $endpoint -Token $token -ApiVersion $ApiVersion) {
            if ($cred.name -eq $CredentialName) { continue }  # the one we just deleted
            $tp = $cred.properties.typeProperties
            if (-not $tp) { continue }
            foreach ($prop in $tp.PSObject.Properties) {
                $storeRef = $prop.Value.store.referenceName
                if ($storeRef -and $storeRef -eq $KeyVaultConnectionName) {
                    $others += $cred.name
                    break
                }
            }
        }

        if ($others.Count -gt 0) {
            $otherList = $others -join ', '
            throw "Refusing to delete Key Vault connection '$KeyVaultConnectionName': $($others.Count) other credential(s) still reference it ($otherList). Delete or re-point those credentials first, or re-run with -Force if they are also being retired. Deleting the connection while they reference it leaves them resolvable as metadata but broken at scan time."
        }
        Write-Verbose "No other credentials reference '$KeyVaultConnectionName'. Proceeding."
    }
    else {
        Write-Warning "-Force specified: skipping the 'other credentials still reference this connection' check."
    }

    $kvUri = "$endpoint/scan/azureKeyVaults/$KeyVaultConnectionName`?api-version=$ApiVersion"
    Invoke-PurviewDelete -Uri $kvUri -Token $token `
        -Description "Key Vault connection '$KeyVaultConnectionName'"
}

Write-Host @"

Done. Not removed by this script (by design):
  - The Azure Key Vault secret itself - a Purview credential stores only a reference, so the
    secret is untouched. Delete or disable it in Key Vault separately if this is a full teardown.
  - The Purview managed identity's access grant on that Key Vault (access policy entry, or the
    Key Vault Secrets User role assignment).
  - The database login / service principal the credential pointed at, and its db_datareader grant.
  - Any scan object that referenced this credential by name - it remains configured and will fail
    at its next run with an authentication error. See rollback.md Stage 1.

Confirm removal with validate/Test-PurviewScanCredential.ps1 (expect it to report the credential
as absent).
"@ -ForegroundColor Cyan
