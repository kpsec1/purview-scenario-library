---
part: "deploy"
parent: "data-map/scan-credential-key-vault-backed"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-PurviewScanCredential.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles an Azure Key Vault connection and a Key Vault-backed Microsoft Purview
    Data Map scan credential object (SqlAuth, BasicAuth, or ServicePrincipal).

.DESCRIPTION
    Calls the Microsoft Purview Scanning data-plane REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Optionally create or replace the Azure Key Vault *connection* -
         PUT {endpoint}/scan/azureKeyVaults/{azureKeyVaultName}
         (only when -KeyVaultBaseUrl is supplied; otherwise the named connection is read back with
         a GET and the run fails fast if it doesn't exist).
      2. Create or replace the credential object -
         PUT {endpoint}/scan/credentials/{credentialName}

    The resulting credential is what a credential-authenticated scan references by name via its
    `properties.credential` = { credentialType, referenceName } block - for example the
    `AzureSqlDatabaseCredential` and `SqlServerDatabaseCredential` scan kinds used by
    scenarios/data-map/scan-azure-sql-and-classify/ and
    scenarios/data-map/scan-on-premises-sql-server-and-classify/ respectively.

    SECURITY MODEL - this script never handles the secret itself. A Purview credential object
    stores only a *reference* to an Azure Key Vault secret (vault connection name + secret name +
    optional secret version). The password / service-principal key must already exist as a secret
    in the Key Vault before this script runs, and Purview reads it at scan time using the Purview
    account's own managed identity. Consequently this script takes no plaintext or SecureString
    secret parameter for the target data source at all - only -AppId/-ClientSecret, which
    authenticate the *caller* to the Purview REST API. See README.md Sections 3 and 5.

    Idempotent by construction: both mutating calls are REST PUTs against documented
    create-or-replace endpoints ("Creates or replaces an instance of a credential." /
    "Creates or replaces a connection to Azure Key Vault."). Re-running this script with the same
    parameters reconciles both objects to the script's current definition rather than erroring or
    duplicating. Because a credential object holds no secret material, re-running it is also safe
    after a Key Vault secret rotation - rotate the secret in the vault, and (only if you pinned
    -SecretVersion) re-run this script with the new version.

    This script does NOT create:
      - The Azure Key Vault, or the secret inside it (Azure-side prerequisite - README.md Section 5).
      - The Key Vault access grant for the Purview account's managed identity (Get + List on
        secrets, or the Key Vault Secrets User role) - README.md Sections 3 and 5.
      - The database login / service principal the credential points at, or its db_datareader
        grant on the target database.
      - Any data source or scan object - see the sibling scenarios above for those.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account (used to build https://<name>.purview.azure.com).

.PARAMETER TenantId
    Microsoft Entra tenant ID of the tenant hosting the Purview account.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Scanning REST API.
    Must hold the Data Source Administrator role on the target collection (docs/rbac-model.md
    Section 5). This identity authenticates the caller only - it is never the identity the scan
    uses to read the target database.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER CredentialName
    Name for the Purview credential object. Referenced later as a scan's
    properties.credential.referenceName. Microsoft's REST reference constrains this to 3-63
    characters matching ^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$ - alphanumerics separated by single
    hyphens, no underscores, no leading/trailing hyphen.

.PARAMETER CredentialType
    Which credential kind to create:
      SqlAuth          - SQL authentication (login + password). The default, and the type used by
                         the AzureSqlDatabaseCredential / SqlServerDatabaseCredential scan kinds
                         for a SQL login.
      BasicAuth        - Username + password for sources whose documented method is basic auth.
                         Also this repo's best-effort mapping for the portal's "Windows
                         Authentication" option on on-premises SQL Server - see the VERIFY in
                         scenarios/data-map/scan-on-premises-sql-server-and-classify/.
      ServicePrincipal - Microsoft Entra service principal (app ID + tenant + client secret held
                         in Key Vault). Use when the target database is Entra-authenticated but
                         the Purview account's own SAMI cannot be used (for example, when the scan
                         runs over a self-hosted integration runtime, which does not support
                         managed-identity authentication).

.PARAMETER KeyVaultConnectionName
    Name of the Purview *Key Vault connection* object (not the Azure Key Vault resource name,
    though they are commonly the same). Same 3-63 character / hyphen-separated-alphanumeric
    constraint as -CredentialName.

.PARAMETER KeyVaultBaseUrl
    Base URL (DNS name) of the Azure Key Vault, e.g. https://kv-contoso-purview.vault.azure.net/.
    Supply this to create or reconcile the Key Vault connection. Omit it to require that
    -KeyVaultConnectionName already exists (the script GETs it and fails fast if it doesn't).

.PARAMETER KeyVaultConnectionDescription
    Optional description stamped on the Key Vault connection object.

.PARAMETER SecretName
    Name of the secret inside the Key Vault that holds the password (SqlAuth/BasicAuth) or the
    service principal client secret (ServicePrincipal). The secret must already exist.

.PARAMETER SecretVersion
    Optional specific secret version to pin. Omit to let Purview resolve the secret without a
    pinned version. VERIFY (see .NOTES): Microsoft's Purview reference documents the property but
    does not state the omitted-version behavior; the equivalent Azure Data Factory /Synapse
    AzureKeyVaultSecretReference property is documented as defaulting to the latest version.
    Pinning a version makes a rotation require re-running this script; omitting it does not.

.PARAMETER UserName
    Required for -CredentialType SqlAuth and BasicAuth. The SQL login or username the password
    belongs to. Ignored for ServicePrincipal.

.PARAMETER ServicePrincipalId
    Required for -CredentialType ServicePrincipal. Application (client) ID of the service
    principal the *scan* authenticates as against the target data source. This is a different
    principal from -AppId (which authenticates this script to the Purview API); do not reuse one
    for the other - see README.md Section 3 and design.md Section 4.

.PARAMETER ServicePrincipalTenantId
    Required for -CredentialType ServicePrincipal. Tenant the -ServicePrincipalId belongs to.
    Defaults to -TenantId when omitted.

.PARAMETER Description
    Optional description stamped on the credential object. Defaults to a generated string naming
    the credential type and secret.

.PARAMETER SecretReferenceType
    Literal value written to the credential's KeyVaultSecret `type` discriminator. Defaults to
    'AzureKeyVaultSecret'. Exposed as a parameter (rather than hard-coded) precisely because this
    is the one VERIFY in this script - see .NOTES - so a pilot-tenant read-back can correct it
    without a code edit.

.PARAMETER SecretStoreReferenceType
    Literal value written to the credential's KeyVaultSecret `store.type` discriminator. Defaults
    to 'LinkedServiceReference'. Same VERIFY rationale as -SecretReferenceType.

.PARAMETER ApiVersion
    Scanning data-plane REST API version to pin. Defaults to '2023-09-01', the version under which
    the Credential and Key Vault Connections operation groups' reference pages and worked examples
    were direct-fetched for this build.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT) request. Invoke-RestMethod has no native ShouldProcess integration,
    so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
        -KeyVaultConnectionName 'kv-contoso-purview' `
        -KeyVaultBaseUrl 'https://kv-contoso-purview.vault.azure.net/' `
        -SecretName 'onprem-sql-scan-password' -UserName 'purview_scanner' -WhatIf

    Dry-run: shows the Key Vault connection PUT and the SqlAuth credential PUT that would be made,
    changes nothing.

.EXAMPLE
    ./New-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'azuresql-scan-sp' `
        -CredentialType ServicePrincipal -KeyVaultConnectionName 'kv-contoso-purview' `
        -SecretName 'purview-scan-sp-secret' -ServicePrincipalId $ScanSpAppId

    Creates a service-principal credential against an already-registered Key Vault connection
    (no -KeyVaultBaseUrl, so the connection is verified rather than created). Suitable for an
    Azure SQL scan over a self-hosted integration runtime, where SAMI authentication is not
    supported.

.EXAMPLE
    ./New-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
        -KeyVaultConnectionName 'kv-contoso-purview' -SecretName 'onprem-sql-scan-password' `
        -SecretVersion 'b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6' -UserName 'purview_scanner'

    Re-runs after a secret rotation, pinning the new secret version. Because the credential object
    holds only a reference, this is a metadata-only update - no secret passes through this script.

.NOTES
    CLOSES the long-standing "no documented REST endpoint for Purview credential-object creation"
    gap recorded in PROGRESS.md and referenced in:
      - scenarios/data-map/scan-azure-sql-and-classify/design.md Section 7 (Non-goals)
      - scenarios/data-map/scan-on-premises-sql-server-and-classify/deploy/
        New-OnPremisesSqlServerDataMapScan.ps1 .NOTES
    Both of those builds concluded credential creation was portal-only. It is not: the Scanning
    data-plane REST API's Credential and Key Vault Connections operation groups are fully
    documented at api-version 2023-09-01 and were direct-fetched in full for this build. Those two
    scenarios' notes are corrected in place by this fragment.

    VERIFY (pilot tenant, before production reliance) - one genuine gap, deliberately not guessed
    away. Microsoft's Purview Credential reference defines KeyVaultSecret as
    { secretName, secretVersion, store: { referenceName, type }, type } but types both `type`
    fields as an open `string` with no enumerated values, and its only worked request example is a
    BasicAuth credential carrying `description` alone - no typeProperties, so no secret reference
    is shown end-to-end anywhere in the Purview documentation set. The @azure-rest/purview-scanning
    JS SDK types them as plain `string` too, and Az.Purview ships no credential-object cmdlet at
    all (only scan objects), so there is no Purview-specific source that pins the literals.
    This script's defaults - 'AzureKeyVaultSecret' for -SecretReferenceType and
    'LinkedServiceReference' for -SecretStoreReferenceType - come from two converging indirect
    sources:
      (a) Azure Data Factory / Synapse Artifacts model an identically-shaped
          AzureKeyVaultSecretReference as { type: 'AzureKeyVaultSecret' (required literal),
          store: LinkedServiceReference, secretName, secretVersion }; and
      (b) Purview's own Key Vault Connections - Create Or Replace worked *response* returns an `id`
          ending in `/linkedservices/AzureKeyVault1`, i.e. Purview does model a Key Vault
          connection as a linked service internally, which is what makes the
          'LinkedServiceReference' store discriminator coherent here.
    That is strong structural corroboration, not a Purview-specific worked example. Both literals
    are therefore parameters, not constants: confirm them with a portal-created credential read
    back through Credential - Get on a pilot tenant, and override if they differ. Also unconfirmed
    for Purview specifically: whether omitting secretVersion resolves to the latest version (the
    documented Data Factory behavior). See README.md Section 11.

    Sources (Microsoft Learn, direct-fetched for this build unless noted):
    - Credential - Create Or Replace (PUT /scan/credentials/{credentialName}, credential kinds,
      KeyVaultSecret/Store/UserPassCredentialProperties/
      KeyVaultSecretServicePrinipalCredentialTypeProperties definitions, name pattern):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace
    - Credential - List / Delete (list envelope { count, nextLink, value[] }; DELETE -> 204):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/delete
    - Key Vault Connections - Create Or Replace (PUT /scan/azureKeyVaults/{name},
      AzureKeyVaultProperties { baseUrl, description }, worked example):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections/create-or-replace
    - Scanning Data Plane operation-group index (confirms Credential + Key Vault Connections are
      first-class documented operation groups at 2023-09-01):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/operation-groups
    - Credentials for source authentication in Microsoft Purview Data Map (supported credential
      types; Key Vault connection prerequisite; Purview MSI needs Get + List on secrets, or the
      Key Vault Secrets User role):
      https://learn.microsoft.com/purview/data-map-data-scan-credentials
    - AzureKeyVaultSecretReference (Data Factory model - structural analog behind the two VERIFY
      literal defaults above; `type` is a required 'AzureKeyVaultSecret' literal, `store` is a
      LinkedServiceReference, secretVersion defaults to the latest version):
      https://learn.microsoft.com/azure/templates/microsoft.datafactory/2017-09-01-preview/factories/linkedservices
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, roles):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    # Microsoft's documented constraint for both credentialName and azureKeyVaultName:
    # minLength 3, maxLength 63, pattern ^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$
    [Parameter(Mandatory)]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$CredentialName,

    [Parameter()]
    [ValidateSet('SqlAuth', 'BasicAuth', 'ServicePrincipal')]
    [string]$CredentialType = 'SqlAuth',

    [Parameter(Mandatory)]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$KeyVaultConnectionName,

    [Parameter()]
    [ValidatePattern('^https://[A-Za-z0-9._-]+/?$')]
    [string]$KeyVaultBaseUrl,

    [Parameter()]
    [string]$KeyVaultConnectionDescription,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SecretName,

    [Parameter()]
    [string]$SecretVersion,

    [Parameter()]
    [string]$UserName,

    [Parameter()]
    [string]$ServicePrincipalId,

    [Parameter()]
    [string]$ServicePrincipalTenantId,

    [Parameter()]
    [string]$Description,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SecretReferenceType = 'AzureKeyVaultSecret',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SecretStoreReferenceType = 'LinkedServiceReference',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

# --- Parameter-combination validation (done here rather than with parameter sets so that the
#     three credential types share one obvious call shape in the docs) ---
switch ($CredentialType) {
    { $_ -in 'SqlAuth', 'BasicAuth' } {
        if (-not $UserName) {
            throw "-UserName is required for -CredentialType $CredentialType (it is the SQL login or username the Key Vault secret's password belongs to)."
        }
        if ($ServicePrincipalId) {
            Write-Warning "-ServicePrincipalId is ignored for -CredentialType $CredentialType."
        }
    }
    'ServicePrincipal' {
        if (-not $ServicePrincipalId) {
            throw "-ServicePrincipalId is required for -CredentialType ServicePrincipal."
        }
        if ($UserName) {
            Write-Warning "-UserName is ignored for -CredentialType ServicePrincipal."
        }
        if (-not $ServicePrincipalTenantId) {
            $ServicePrincipalTenantId = $TenantId
            Write-Verbose "-ServicePrincipalTenantId not supplied; defaulting to -TenantId ($TenantId)."
        }
        if ($ServicePrincipalId -eq $AppId) {
            Write-Warning "-ServicePrincipalId matches -AppId. The identity that calls the Purview API and the identity a scan authenticates to the data source as are different roles; reusing one principal for both widens its blast radius. See design.md Section 4."
        }
    }
}

if (-not $Description) {
    $Description = "$CredentialType credential referencing Key Vault secret '$SecretName' via connection '$KeyVaultConnectionName'. Managed by scenarios/data-map/scan-credential-key-vault-backed."
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"

function Get-PurviewAccessToken {
    <#
        Client-credentials OAuth2 flow against the Data Map data-plane resource, per
        docs/automation-surface.md Section 3 and README.md reference 7 (data-gov-api-rest-data-plane).
    #>
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

function Invoke-PurviewPut {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if ($PSCmdlet.ShouldProcess($Description, "PUT $Uri")) {
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method Put -Uri $Uri -Body $json -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" }
    }
    Write-Verbose "WhatIf: would PUT $Uri with body:`n$($Body | ConvertTo-Json -Depth 10)"
    return $null
}

function Get-PurviewObjectOrNull {
    <#
        GET that treats 404 as "does not exist" (returns $null) and rethrows anything else, so a
        genuine authorization or transport failure is never silently reported as "not found".
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token
    )
    try {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: the Azure Key Vault connection ---
# A credential can only reference a Key Vault that is already registered as a connection on the
# Purview account (Microsoft Learn: "Before you can create a Credential, first associate one or
# more of your existing Azure Key Vault instances with your Microsoft Purview account").
$kvUri = "$endpoint/scan/azureKeyVaults/$KeyVaultConnectionName`?api-version=$ApiVersion"

if ($KeyVaultBaseUrl) {
    $kvProperties = @{ baseUrl = $KeyVaultBaseUrl }
    if ($KeyVaultConnectionDescription) { $kvProperties['description'] = $KeyVaultConnectionDescription }

    Invoke-PurviewPut -Uri $kvUri -Body @{ properties = $kvProperties } -Token $token `
        -Description "Key Vault connection '$KeyVaultConnectionName' ($KeyVaultBaseUrl)" | Out-Null
    Write-Host "Key Vault connection '$KeyVaultConnectionName' created/updated -> $KeyVaultBaseUrl" -ForegroundColor Green
}
else {
    # No base URL supplied: require that the connection already exists rather than silently
    # creating a credential whose store reference dangles.
    $existingKv = Get-PurviewObjectOrNull -Uri $kvUri -Token $token
    if ($null -eq $existingKv) {
        throw "Key Vault connection '$KeyVaultConnectionName' was not found on Purview account '$PurviewAccountName' (HTTP 404). Note that a 404 here means 'absent OR not visible to this identity' - the Scanning API is not documented to distinguish a missing object from one the caller lacks the collection role to read, so confirm -AppId holds Data Source Administrator (or at least Data Reader) on the target collection before assuming the object is genuinely missing. If it is missing, re-run with -KeyVaultBaseUrl to create it, or correct the name. A credential referencing a non-existent Key Vault connection would be accepted as metadata but fail at scan time."
    }
    Write-Host "Key Vault connection '$KeyVaultConnectionName' already exists -> $($existingKv.properties.baseUrl)" -ForegroundColor Green
}

# --- Step 2: the credential object ---
# The secret reference. `type` and `store.type` are the two VERIFY literals - see .NOTES.
$secretReference = @{
    type  = $SecretReferenceType
    store = @{
        referenceName = $KeyVaultConnectionName
        type          = $SecretStoreReferenceType
    }
    secretName = $SecretName
}
if ($SecretVersion) { $secretReference['secretVersion'] = $SecretVersion }

# Each credential kind carries a different typeProperties shape (Credential - Create Or Replace):
#   SqlAuth / BasicAuth -> UserPassCredentialProperties           -> { user, password }
#   ServicePrincipal    -> ServicePrincipalAzureKeyVaultCredential -> { servicePrincipalId,
#                                                                      servicePrincipalKey, tenant }
$typeProperties = switch ($CredentialType) {
    { $_ -in 'SqlAuth', 'BasicAuth' } {
        @{
            user     = $UserName
            password = $secretReference
        }
    }
    'ServicePrincipal' {
        @{
            servicePrincipalId  = $ServicePrincipalId
            servicePrincipalKey = $secretReference
            tenant              = $ServicePrincipalTenantId
        }
    }
}

$credentialUri = "$endpoint/scan/credentials/$CredentialName`?api-version=$ApiVersion"
$credentialBody = @{
    kind       = $CredentialType
    properties = @{
        description    = $Description
        typeProperties = $typeProperties
    }
}

Invoke-PurviewPut -Uri $credentialUri -Body $credentialBody -Token $token `
    -Description "Credential '$CredentialName' (kind: $CredentialType, secret: $SecretName)" | Out-Null

$versionLabel = if ($SecretVersion) { "version '$SecretVersion'" } else { 'latest version (no version pinned)' }
Write-Host "Credential '$CredentialName' created/updated (kind: $CredentialType, secret: '$SecretName', $versionLabel)." -ForegroundColor Green

Write-Host @"

Done. Reference this credential from a scan object's properties.credential block:

    credential = @{ credentialType = '$CredentialType'; referenceName = '$CredentialName' }

  - Azure SQL over a self-hosted IR / non-SAMI path : scan kind 'AzureSqlDatabaseCredential'
  - On-premises SQL Server                          : scan kind 'SqlServerDatabaseCredential'
    (see scenarios/data-map/scan-on-premises-sql-server-and-classify/deploy/)

The scan will still fail at run time unless all three out-of-band prerequisites are already in
place (README.md Sections 3 and 5):
  1. The secret '$SecretName' exists in the Key Vault behind connection '$KeyVaultConnectionName'.
  2. The Purview account's managed identity has Get + List on that vault's secrets (access policy),
     or the Key Vault Secrets User role (Azure RBAC permission model).
  3. The login/service principal the credential points at has db_datareader on the target database.

Run validate/Test-PurviewScanCredential.ps1 to confirm 1-2 and the object shape before scanning.
"@ -ForegroundColor Cyan
```

#### `policy/scan-credential-definitions.json`

```json
{
  "$comment": [
    "Reference request bodies for the Microsoft Purview Scanning data-plane REST API objects this",
    "scenario creates. These are the exact shapes deploy/New-PurviewScanCredential.ps1 builds, kept",
    "here as a readable artifact for review, diffing, and hand-curl testing. This file is NOT read",
    "by the deploy script - it is documentation-as-data, matching this repo's deploy/policy/",
    "convention.",
    "",
    "All values in angle brackets are placeholders. No secret material appears in any of these",
    "bodies by design: a Purview credential stores a REFERENCE to a Key Vault secret, never the",
    "secret itself.",
    "",
    "API version 2023-09-01. Grounding and the one open VERIFY are documented in",
    "../New-PurviewScanCredential.ps1 .NOTES and ../../README.md Sections 6 and 11."
  ],

  "keyVaultConnection": {
    "$comment": [
      "PUT {endpoint}/scan/azureKeyVaults/{azureKeyVaultName}?api-version=2023-09-01",
      "azureKeyVaultName: 3-63 chars, ^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$",
      "Shape confirmed verbatim against Microsoft's KeyVaultConnections_CreateOrReplace worked",
      "example. Both properties are optional per the AzureKeyVaultProperties definition; baseUrl is",
      "the one that actually matters."
    ],
    "properties": {
      "baseUrl": "https://<key-vault-name>.vault.azure.net/",
      "description": "Key Vault holding scan credentials for Purview Data Map"
    }
  },

  "credentialSqlAuth": {
    "$comment": [
      "PUT {endpoint}/scan/credentials/{credentialName}?api-version=2023-09-01",
      "kind 'SqlAuth' -> properties typed as UserPassCredentialProperties -> typeProperties is",
      "KeyVaultSecretUserPassCredentialTypeProperties { user, password: KeyVaultSecret }.",
      "Use for a SQL login on Azure SQL Database, Azure SQL Managed Instance, or on-premises SQL",
      "Server. Referenced by an AzureSqlDatabaseCredential / SqlServerDatabaseCredential scan.",
      "",
      "VERIFY: password.type ('AzureKeyVaultSecret') and password.store.type",
      "('LinkedServiceReference') are the two literals Microsoft's Purview reference types as open",
      "strings without enumerating values, and no Purview worked example shows a populated secret",
      "reference. Defaults derive from the identically-shaped Data Factory AzureKeyVaultSecretReference",
      "plus Purview's own Key Vault connection response id ending in '/linkedservices/...'.",
      "Overridable via -SecretReferenceType / -SecretStoreReferenceType."
    ],
    "kind": "SqlAuth",
    "properties": {
      "description": "SQL authentication credential for Data Map scanning",
      "typeProperties": {
        "user": "<sql-login-name>",
        "password": {
          "type": "AzureKeyVaultSecret",
          "store": {
            "referenceName": "<key-vault-connection-name>",
            "type": "LinkedServiceReference"
          },
          "secretName": "<secret-name-in-key-vault>"
        }
      }
    }
  },

  "credentialBasicAuth": {
    "$comment": [
      "kind 'BasicAuth' -> identical UserPassCredentialProperties shape as SqlAuth.",
      "This repo's best-effort mapping for the portal's 'Windows Authentication' option on",
      "on-premises SQL Server - that mapping is itself an open VERIFY carried from",
      "scenarios/data-map/scan-on-premises-sql-server-and-classify/."
    ],
    "kind": "BasicAuth",
    "properties": {
      "description": "Basic authentication credential for Data Map scanning",
      "typeProperties": {
        "user": "<domain\\username-or-username>",
        "password": {
          "type": "AzureKeyVaultSecret",
          "store": {
            "referenceName": "<key-vault-connection-name>",
            "type": "LinkedServiceReference"
          },
          "secretName": "<secret-name-in-key-vault>"
        }
      }
    }
  },

  "credentialServicePrincipal": {
    "$comment": [
      "kind 'ServicePrincipal' -> properties typed as",
      "ServicePrincipalAzureKeyVaultCredentialProperties -> typeProperties is",
      "KeyVaultSecretServicePrinipalCredentialTypeProperties (Microsoft's own spelling - note the",
      "missing 'c' in 'Prinipal' in the definition name; the wire property names below are correct)",
      "{ servicePrincipalId, servicePrincipalKey: KeyVaultSecret, tenant }.",
      "Use when the target is Entra-authenticated but the Purview account's system-assigned managed",
      "identity cannot be used - notably when the scan runs over a self-hosted integration runtime,",
      "which does not support managed-identity authentication."
    ],
    "kind": "ServicePrincipal",
    "properties": {
      "description": "Service principal credential for Data Map scanning",
      "typeProperties": {
        "servicePrincipalId": "<scan-service-principal-app-id>",
        "tenant": "<tenant-id>",
        "servicePrincipalKey": {
          "type": "AzureKeyVaultSecret",
          "store": {
            "referenceName": "<key-vault-connection-name>",
            "type": "LinkedServiceReference"
          },
          "secretName": "<secret-name-in-key-vault>",
          "secretVersion": "<optional-pinned-version>"
        }
      }
    }
  },

  "scanCredentialReference": {
    "$comment": [
      "NOT created by this scenario - shown so the hand-off is unambiguous. This is the block a",
      "credential-authenticated scan object carries at properties.credential, referencing the",
      "credential created above by name. credentialType must match the credential object's kind.",
      "See scenarios/data-map/scan-on-premises-sql-server-and-classify/deploy/ for the full scan body."
    ],
    "credential": {
      "credentialType": "SqlAuth",
      "referenceName": "<credential-name>"
    }
  }
}
```

#### `Remove-PurviewScanCredential.ps1`

```powershell
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
```