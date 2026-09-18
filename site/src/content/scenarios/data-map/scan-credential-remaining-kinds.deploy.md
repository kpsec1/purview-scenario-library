---
part: "deploy"
parent: "data-map/scan-credential-remaining-kinds"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-PurviewScanCredentialExtended.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles a Microsoft Purview Data Map scan credential of one of the five kinds the
    parent scenario (scan-credential-key-vault-backed) does not script: AccountKey, AmazonARN,
    ConsumerKeyAuth, DelegatedAuth, or ManagedIdentity (user-assigned).

.DESCRIPTION
    Calls the Microsoft Purview Scanning data-plane REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. For AccountKey / ConsumerKeyAuth / DelegatedAuth only: optionally create or replace the
         Azure Key Vault *connection* - PUT {endpoint}/scan/azureKeyVaults/{azureKeyVaultName} -
         when -KeyVaultBaseUrl is supplied; otherwise the named connection is read back with a GET
         and the run fails fast if it doesn't exist. Identical semantics to the parent scenario's
         deploy script.
         AmazonARN and ManagedIdentity carry no Key Vault reference at all in their typeProperties
         (see README.md Section 6) - this script THROWS if -KeyVaultConnectionName/-KeyVaultBaseUrl
         are supplied for either kind, rather than silently ignoring them.
      2. Create or replace the credential object - PUT {endpoint}/scan/credentials/{credentialName}
         - with a body shape that is entirely different per -CredentialType (README.md Section 6):
           AccountKey       -> { accountKey: KeyVaultSecret }
           AmazonARN        -> { roleARN: <plain string> }
           ConsumerKeyAuth  -> { user, consumerKey: <plain string>, consumerSecret: KeyVaultSecret,
                                  password: KeyVaultSecret }                  (TWO secret references)
           DelegatedAuth    -> { clientId, user, password: KeyVaultSecret }
           ManagedIdentity  -> { principalId, resourceId, tenantId }         (all plain strings)

    SECURITY MODEL - identical to the parent scenario for the three secret-bearing kinds here
    (AccountKey, ConsumerKeyAuth, DelegatedAuth): this script never receives or handles the secret
    value itself, only Key Vault coordinates (connection + secret name (+ version)). For AmazonARN
    and ManagedIdentity there is no secret at all to protect - both kinds authenticate via an
    out-of-band trust relationship (an AWS IAM role's trust policy; an Azure user-assigned managed
    identity already granted access at the source) that this script references by ID but never
    creates or grants access for.

    Idempotent by construction: the credential PUT is a documented create-or-replace endpoint.
    Re-running this script with the same parameters reconciles the object to the script's current
    definition.

    This script does NOT create:
      - The Azure Key Vault, or the secret inside it (AccountKey/ConsumerKeyAuth/DelegatedAuth).
      - The Key Vault access grant for the Purview account's managed identity.
      - The AWS IAM role an AmazonARN credential references, or configure its trust policy. Per
        README.md Section 3, the Microsoft account ID / external ID needed to configure that trust
        policy are surfaced only in the Purview PORTAL's "New credential" pane - this script cannot
        supply them because no REST endpoint returning them was found during this build's grounding
        pass (README.md Section 11).
      - The user-assigned managed identity a ManagedIdentity credential references, or add it to the
        Purview account (an Azure portal / Managed identities blade action).
      - Any data source or scan object.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account (used to build https://<name>.purview.azure.com).

.PARAMETER TenantId
    Microsoft Entra tenant ID of the tenant hosting the Purview account.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Scanning REST API.
    Must hold the Data Source Administrator role on the target collection (docs/rbac-model.md
    Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER CredentialName
    Name for the Purview credential object. 3-63 characters matching
    ^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$ - same constraint as the parent scenario.

.PARAMETER CredentialType
    Which of the five kinds to create: AccountKey, AmazonARN, ConsumerKeyAuth, DelegatedAuth, or
    ManagedIdentity. See README.md Section 6 for the exact typeProperties shape of each and Section
    3 for prerequisites. ManagedIdentity is a Microsoft-labeled Preview capability - README.md
    Section 11.

.PARAMETER KeyVaultConnectionName
    Name of the Purview Key Vault connection object. Required for -CredentialType AccountKey,
    ConsumerKeyAuth, or DelegatedAuth. Throws if supplied for AmazonARN or ManagedIdentity, which
    reference no Key Vault connection at all.

.PARAMETER KeyVaultBaseUrl
    Base URL of the Azure Key Vault. Supply to create/reconcile the Key Vault connection; omit to
    require that -KeyVaultConnectionName already exists. Ignored (and must be omitted) for
    AmazonARN/ManagedIdentity.

.PARAMETER KeyVaultConnectionDescription
    Optional description stamped on the Key Vault connection object, if one is created.

.PARAMETER SecretName
    Name of the Key Vault secret holding: the storage/Cosmos DB account key (AccountKey), the
    Salesforce user's password (ConsumerKeyAuth), or the Fabric/Power BI admin's password
    (DelegatedAuth). Required for those three kinds; ignored for AmazonARN/ManagedIdentity.

.PARAMETER SecretVersion
    Optional specific version of -SecretName to pin. Omit to let Purview resolve the secret without
    a pinned version - same open VERIFY as the parent scenario (README.md Section 11 there).

.PARAMETER ConsumerSecretName
    ConsumerKeyAuth only. Name of the Key Vault secret holding the Salesforce Connected App's
    consumer secret - a SECOND, independent secret reference from -SecretName (the password). See
    README.md Section 6.

.PARAMETER ConsumerSecretVersion
    Optional specific version of -ConsumerSecretName to pin.

.PARAMETER UserName
    Required for -CredentialType ConsumerKeyAuth (the Salesforce username) and DelegatedAuth (the
    Fabric/Power BI administrator's username). Ignored for other kinds.

.PARAMETER ConsumerKey
    Required for -CredentialType ConsumerKeyAuth. The Salesforce Connected App's Consumer Key
    (client ID). Written as a PLAIN STRING into the credential object's metadata - Microsoft's
    schema types this field as a string, not a KeyVaultSecret (README.md Section 11). Do not pass
    the Consumer *Secret* here; that is -ConsumerSecretName, stored in Key Vault.

.PARAMETER ClientId
    Required for -CredentialType DelegatedAuth. The Application (client) ID of the app registration
    used for the Fabric/Power BI delegated-authentication flow. Plain string, not a secret.

.PARAMETER RoleArn
    Required for -CredentialType AmazonARN. The AWS IAM role's ARN, e.g.
    arn:aws:iam::181328463391:role/PurviewS3ScanRole. The role must already exist and trust the
    Microsoft account ID / external ID Purview's portal displays - see README.md Section 3. This
    script does not validate the ARN against AWS; -WhatIf and the validate/ script only check its
    string shape.

.PARAMETER PrincipalId
    Required for -CredentialType ManagedIdentity. The principal (object) ID of an existing
    user-assigned managed identity already added to the Purview account. See README.md Section 3.

.PARAMETER ResourceId
    Required for -CredentialType ManagedIdentity. The Azure resource ID of that same user-assigned
    managed identity (/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/
    userAssignedIdentities/...).

.PARAMETER ManagedIdentityTenantId
    Optional for -CredentialType ManagedIdentity. Tenant the user-assigned managed identity belongs
    to. Defaults to -TenantId.

.PARAMETER Description
    Optional description stamped on the credential object. Defaults to a generated string naming the
    credential type.

.PARAMETER SecretReferenceType
    Literal value written to any KeyVaultSecret's `type` discriminator this credential kind uses.
    Defaults to 'AzureKeyVaultSecret' - same open VERIFY and same override mechanism as the parent
    scenario. Ignored for AmazonARN/ManagedIdentity (no KeyVaultSecret in either).

.PARAMETER SecretStoreReferenceType
    Literal value written to any KeyVaultSecret's `store.type` discriminator. Defaults to
    'LinkedServiceReference'. Same rationale as -SecretReferenceType.

.PARAMETER ApiVersion
    Scanning data-plane REST API version to pin. Defaults to '2023-09-01', matching the parent
    scenario and this fragment's own grounding pass.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT) request.

.EXAMPLE
    ./New-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'adls-account-key' `
        -CredentialType AccountKey -KeyVaultConnectionName 'kv-contoso-purview' `
        -SecretName 'adls-storage-account-key' -WhatIf

    Dry-run: shows the AccountKey credential PUT that would be made against an existing Key Vault
    connection.

.EXAMPLE
    ./New-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 's3-role-arn' `
        -CredentialType AmazonARN -RoleArn 'arn:aws:iam::181328463391:role/PurviewS3ScanRole'

    Creates a Role ARN credential for Amazon S3 scanning. No Key Vault parameters accepted for this
    kind. The AWS role must already exist and trust Microsoft - README.md Section 3.

.EXAMPLE
    ./New-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'salesforce-consumer-key' `
        -CredentialType ConsumerKeyAuth -KeyVaultConnectionName 'kv-contoso-purview' `
        -UserName 'purview-integration@contoso.com' -ConsumerKey '3MVG9...' `
        -ConsumerSecretName 'salesforce-consumer-secret' -SecretName 'salesforce-password'

    Creates a Consumer Key credential for Salesforce scanning, with two independent Key Vault
    secrets (consumer secret and password) and a plain-text consumer key.

.EXAMPLE
    ./New-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'adls-uami' `
        -CredentialType ManagedIdentity -PrincipalId $UamiPrincipalId -ResourceId $UamiResourceId

    Creates a ManagedIdentity credential referencing an existing user-assigned managed identity.
    PREVIEW capability - README.md Section 11.

.NOTES
    CLOSES the "five credential kinds are out of scope" follow-up recorded against
    scan-credential-key-vault-backed/README.md Section 11 and PROGRESS.md.

    Sources (Microsoft Learn, direct-fetched for this build via the Microsoft Learn MCP tool):
    - Credential - Create Or Replace (all eight CredentialType kinds and their typeProperties
      definitions, including the five this script creates):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace
    - Credentials for source authentication in Microsoft Purview Data Map (the enumerated
      credential-type list, User-assigned managed identity (preview), UAMI creation procedure and
      its six supported source types):
      https://learn.microsoft.com/purview/data-map-data-scan-credentials
    - Amazon S3 Multicloud Scanning Connector for Microsoft Purview (Role ARN as the only auth
      method for S3; the portal-displayed Microsoft account ID / external ID that have no confirmed
      REST source - see README.md Section 11):
      https://learn.microsoft.com/purview/register-scan-amazon-s3
    - Connect to your Microsoft Fabric tenant in the same tenant as Microsoft Purview (Delegated
      Auth worked example: Client ID, User name, Password):
      https://learn.microsoft.com/purview/register-scan-fabric-tenant
    - Data governance best practices for security (credential priority order: Purview managed
      identity -> user-assigned managed identity -> service principal -> account key/SQL auth/other):
      https://learn.microsoft.com/purview/data-gov-classic-security-best-practices

    VERIFY (pilot tenant) - carried from the parent scenario, unchanged for the secret-bearing kinds
    here: the KeyVaultSecret `type`/`store.type` discriminator literals, and omitted-secretVersion
    semantics. See README.md Section 11 for the two VERIFYs specific to this fragment (the AmazonARN
    account ID/external ID source, and ManagedIdentity's current preview status).
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

    [Parameter(Mandatory)]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$CredentialName,

    [Parameter(Mandatory)]
    [ValidateSet('AccountKey', 'AmazonARN', 'ConsumerKeyAuth', 'DelegatedAuth', 'ManagedIdentity')]
    [string]$CredentialType,

    [Parameter()]
    [ValidateLength(3, 63)]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$KeyVaultConnectionName,

    [Parameter()]
    [ValidatePattern('^https://[A-Za-z0-9._-]+/?$')]
    [string]$KeyVaultBaseUrl,

    [Parameter()]
    [string]$KeyVaultConnectionDescription,

    [Parameter()]
    [string]$SecretName,

    [Parameter()]
    [string]$SecretVersion,

    [Parameter()]
    [string]$ConsumerSecretName,

    [Parameter()]
    [string]$ConsumerSecretVersion,

    [Parameter()]
    [string]$UserName,

    [Parameter()]
    [string]$ConsumerKey,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [ValidatePattern('^arn:aws:iam::\d{12}:role/.+$')]
    [string]$RoleArn,

    [Parameter()]
    [string]$PrincipalId,

    [Parameter()]
    [string]$ResourceId,

    [Parameter()]
    [string]$ManagedIdentityTenantId,

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

# --- Kinds that carry a KeyVaultSecret reference, vs. kinds that carry none at all ---
$keyVaultBackedKinds = @('AccountKey', 'ConsumerKeyAuth', 'DelegatedAuth')
$usesKeyVault = $CredentialType -in $keyVaultBackedKinds

# --- Parameter-combination validation, per kind ---
if ($usesKeyVault) {
    if (-not $KeyVaultConnectionName) {
        throw "-KeyVaultConnectionName is required for -CredentialType $CredentialType."
    }
}
else {
    if ($KeyVaultConnectionName -or $KeyVaultBaseUrl -or $KeyVaultConnectionDescription) {
        throw "-KeyVaultConnectionName/-KeyVaultBaseUrl/-KeyVaultConnectionDescription do not apply to -CredentialType $CredentialType - this kind's typeProperties carries no KeyVaultSecret reference at all (README.md Section 6). Omit them."
    }
}

switch ($CredentialType) {
    'AccountKey' {
        if (-not $SecretName) { throw "-SecretName is required for -CredentialType AccountKey (the Key Vault secret holding the storage/Cosmos DB account key)." }
        foreach ($p in 'ConsumerSecretName', 'UserName', 'ConsumerKey', 'ClientId', 'RoleArn', 'PrincipalId', 'ResourceId') {
            if ($PSBoundParameters.ContainsKey($p)) { Write-Warning "-$p is ignored for -CredentialType AccountKey." }
        }
    }
    'AmazonARN' {
        if (-not $RoleArn) { throw "-RoleArn is required for -CredentialType AmazonARN." }
        foreach ($p in 'SecretName', 'ConsumerSecretName', 'UserName', 'ConsumerKey', 'ClientId', 'PrincipalId', 'ResourceId') {
            if ($PSBoundParameters.ContainsKey($p)) { Write-Warning "-$p is ignored for -CredentialType AmazonARN." }
        }
    }
    'ConsumerKeyAuth' {
        if (-not $UserName) { throw "-UserName is required for -CredentialType ConsumerKeyAuth." }
        if (-not $ConsumerKey) { throw "-ConsumerKey is required for -CredentialType ConsumerKeyAuth (the Salesforce Connected App's Consumer Key - plain text, not a secret)." }
        if (-not $ConsumerSecretName) { throw "-ConsumerSecretName is required for -CredentialType ConsumerKeyAuth (the Key Vault secret holding the Consumer Secret)." }
        if (-not $SecretName) { throw "-SecretName is required for -CredentialType ConsumerKeyAuth (the Key Vault secret holding the Salesforce user's password)." }
        foreach ($p in 'ClientId', 'RoleArn', 'PrincipalId', 'ResourceId') {
            if ($PSBoundParameters.ContainsKey($p)) { Write-Warning "-$p is ignored for -CredentialType ConsumerKeyAuth." }
        }
    }
    'DelegatedAuth' {
        if (-not $ClientId) { throw "-ClientId is required for -CredentialType DelegatedAuth (the scanning app registration's Application (client) ID)." }
        if (-not $UserName) { throw "-UserName is required for -CredentialType DelegatedAuth." }
        if (-not $SecretName) { throw "-SecretName is required for -CredentialType DelegatedAuth (the Key Vault secret holding the admin account's password)." }
        foreach ($p in 'ConsumerSecretName', 'ConsumerKey', 'RoleArn', 'PrincipalId', 'ResourceId') {
            if ($PSBoundParameters.ContainsKey($p)) { Write-Warning "-$p is ignored for -CredentialType DelegatedAuth." }
        }
    }
    'ManagedIdentity' {
        if (-not $PrincipalId) { throw "-PrincipalId is required for -CredentialType ManagedIdentity." }
        if (-not $ResourceId) { throw "-ResourceId is required for -CredentialType ManagedIdentity." }
        if (-not $ManagedIdentityTenantId) {
            $ManagedIdentityTenantId = $TenantId
            Write-Verbose "-ManagedIdentityTenantId not supplied; defaulting to -TenantId ($TenantId)."
        }
        foreach ($p in 'SecretName', 'ConsumerSecretName', 'UserName', 'ConsumerKey', 'ClientId', 'RoleArn') {
            if ($PSBoundParameters.ContainsKey($p)) { Write-Warning "-$p is ignored for -CredentialType ManagedIdentity." }
        }
        Write-Warning "ManagedIdentity (user-assigned) is a Microsoft-labeled Preview capability as of this fragment's grounding pass. See README.md Sections 3 and 11 before relying on it in production. This script does not verify the referenced identity is actually attached to the Purview account or granted access at the target source - see validate/Test-PurviewScanCredentialExtended.ps1."
    }
}

if (-not $Description) {
    $Description = "$CredentialType credential. Managed by scenarios/data-map/scan-credential-remaining-kinds."
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

function Invoke-PurviewPut {
    <#
        -LogBody, if supplied, is what the -WhatIf verbose preview prints instead of -Body. Needed
        because ConsumerKeyAuth's typeProperties.consumerKey is a PLAIN STRING (not a KeyVaultSecret
        reference) baked directly into the request body - unlike every field the parent scenario's
        equivalent function ever logs, which are names/references, never a value worth protecting.
        Without this, a -WhatIf -Verbose dry run would print a Salesforce Consumer Key to the
        console/log even though it makes no REST call at all. See reviews.md (Red Team finding 2).
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description,
        [hashtable]$LogBody
    )
    if ($PSCmdlet.ShouldProcess($Description, "PUT $Uri")) {
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method Put -Uri $Uri -Body $json -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $Token" }
    }
    $bodyToLog = if ($LogBody) { $LogBody } else { $Body }
    Write-Verbose "WhatIf: would PUT $Uri with body:`n$($bodyToLog | ConvertTo-Json -Depth 10)"
    return $null
}

function Get-PurviewObjectOrNull {
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

function New-KeyVaultSecretReference {
    <#
        Builds one KeyVaultSecret sub-object. Shared across AccountKey/ConsumerKeyAuth(x2)/
        DelegatedAuth so the two VERIFY discriminator literals are set from one place.
    #>
    param(
        [Parameter(Mandatory)][string]$SecretName,
        [string]$SecretVersion,
        [Parameter(Mandatory)][string]$KeyVaultConnectionName,
        [Parameter(Mandatory)][string]$SecretReferenceType,
        [Parameter(Mandatory)][string]$SecretStoreReferenceType
    )
    $ref = @{
        type       = $SecretReferenceType
        store      = @{
            referenceName = $KeyVaultConnectionName
            type          = $SecretStoreReferenceType
        }
        secretName = $SecretName
    }
    if ($SecretVersion) { $ref['secretVersion'] = $SecretVersion }
    return $ref
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: the Azure Key Vault connection (only for AccountKey/ConsumerKeyAuth/DelegatedAuth) ---
if ($usesKeyVault) {
    $kvUri = "$endpoint/scan/azureKeyVaults/$KeyVaultConnectionName`?api-version=$ApiVersion"

    if ($KeyVaultBaseUrl) {
        $kvProperties = @{ baseUrl = $KeyVaultBaseUrl }
        if ($KeyVaultConnectionDescription) { $kvProperties['description'] = $KeyVaultConnectionDescription }

        Invoke-PurviewPut -Uri $kvUri -Body @{ properties = $kvProperties } -Token $token `
            -Description "Key Vault connection '$KeyVaultConnectionName' ($KeyVaultBaseUrl)" | Out-Null
        Write-Host "Key Vault connection '$KeyVaultConnectionName' created/updated -> $KeyVaultBaseUrl" -ForegroundColor Green
    }
    else {
        $existingKv = Get-PurviewObjectOrNull -Uri $kvUri -Token $token
        if ($null -eq $existingKv) {
            throw "Key Vault connection '$KeyVaultConnectionName' was not found on Purview account '$PurviewAccountName' (HTTP 404 - absent OR not visible to this identity; confirm -AppId holds at least Data Reader on the target collection before assuming it is missing). Re-run with -KeyVaultBaseUrl to create it, or correct the name."
        }
        Write-Host "Key Vault connection '$KeyVaultConnectionName' already exists -> $($existingKv.properties.baseUrl)" -ForegroundColor Green
    }
}

# --- Step 2: the credential object, body shape entirely dependent on kind ---
$typeProperties = switch ($CredentialType) {
    'AccountKey' {
        @{
            accountKey = New-KeyVaultSecretReference -SecretName $SecretName -SecretVersion $SecretVersion `
                -KeyVaultConnectionName $KeyVaultConnectionName -SecretReferenceType $SecretReferenceType `
                -SecretStoreReferenceType $SecretStoreReferenceType
        }
    }
    'AmazonARN' {
        @{ roleARN = $RoleArn }
    }
    'ConsumerKeyAuth' {
        @{
            user           = $UserName
            consumerKey    = $ConsumerKey
            consumerSecret = New-KeyVaultSecretReference -SecretName $ConsumerSecretName -SecretVersion $ConsumerSecretVersion `
                -KeyVaultConnectionName $KeyVaultConnectionName -SecretReferenceType $SecretReferenceType `
                -SecretStoreReferenceType $SecretStoreReferenceType
            password       = New-KeyVaultSecretReference -SecretName $SecretName -SecretVersion $SecretVersion `
                -KeyVaultConnectionName $KeyVaultConnectionName -SecretReferenceType $SecretReferenceType `
                -SecretStoreReferenceType $SecretStoreReferenceType
        }
    }
    'DelegatedAuth' {
        @{
            clientId = $ClientId
            user     = $UserName
            password = New-KeyVaultSecretReference -SecretName $SecretName -SecretVersion $SecretVersion `
                -KeyVaultConnectionName $KeyVaultConnectionName -SecretReferenceType $SecretReferenceType `
                -SecretStoreReferenceType $SecretStoreReferenceType
        }
    }
    'ManagedIdentity' {
        @{
            principalId = $PrincipalId
            resourceId  = $ResourceId
            tenantId    = $ManagedIdentityTenantId
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

# ConsumerKeyAuth's consumerKey is a plain string, not a Key Vault reference - redact it from the
# -WhatIf -Verbose preview so a dry run never prints it (reviews.md, Red Team finding 2).
$logBody = $null
if ($CredentialType -eq 'ConsumerKeyAuth') {
    $logBody = @{
        kind       = $credentialBody.kind
        properties = @{
            description    = $credentialBody.properties.description
            typeProperties = @{
                user           = $typeProperties.user
                consumerKey    = '<redacted - plain-text field, not logged even under -WhatIf -Verbose>'
                consumerSecret = $typeProperties.consumerSecret
                password       = $typeProperties.password
            }
        }
    }
}

Invoke-PurviewPut -Uri $credentialUri -Body $credentialBody -LogBody $logBody -Token $token `
    -Description "Credential '$CredentialName' (kind: $CredentialType)" | Out-Null

Write-Host "Credential '$CredentialName' created/updated (kind: $CredentialType)." -ForegroundColor Green

Write-Host @"

Done. Reference this credential from a scan object's properties.credential block:

    credential = @{ credentialType = '$CredentialType'; referenceName = '$CredentialName' }

No scenario in this library currently consumes a $CredentialType credential in a scan object - see
README.md Section 6 for the source types Microsoft documents this kind against, and design.md
Section 7 for the natural follow-up fragments that would consume it.

Run validate/Test-PurviewScanCredentialExtended.ps1 to confirm the object's shape before scanning.
"@ -ForegroundColor Cyan
```

#### `policy/scan-credential-extended-definitions.json`

```json
{
  "$comment": [
    "Reference request bodies for the five Microsoft Purview Scanning data-plane credential kinds",
    "this scenario creates, matching what deploy/New-PurviewScanCredentialExtended.ps1 builds. Kept",
    "here as a readable artifact for review/diffing, per this repo's deploy/policy/ convention. NOT",
    "read by the deploy script.",
    "",
    "All values in angle brackets are placeholders. AccountKey/ConsumerKeyAuth/DelegatedAuth carry a",
    "secret REFERENCE only, never secret material. AmazonARN and ManagedIdentity carry no secret",
    "reference at all - see README.md Section 6.",
    "",
    "API version 2023-09-01. Grounding: ../New-PurviewScanCredentialExtended.ps1 .NOTES and",
    "../../README.md Sections 6, 11, and 12."
  ],

  "credentialAccountKey": {
    "$comment": [
      "PUT {endpoint}/scan/credentials/{credentialName}?api-version=2023-09-01",
      "kind 'AccountKey' -> AccountKeyCredentialProperties -> typeProperties is",
      "KeyVaultSecretAccountKeyCredentialTypeProperties { accountKey: KeyVaultSecret }.",
      "Use for Azure Blob Storage, ADLS Gen1/Gen2, Azure Files, or Azure Cosmos DB (SQL API) -",
      "README.md Section 6 references 2-5."
    ],
    "kind": "AccountKey",
    "properties": {
      "description": "Account key credential for Data Map scanning",
      "typeProperties": {
        "accountKey": {
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

  "credentialAmazonARN": {
    "$comment": [
      "kind 'AmazonARN' -> RoleARNCredentialProperties -> typeProperties is",
      "RoleARNCredentialTypeProperties { roleARN: <plain string> }. NO KeyVaultSecret anywhere in",
      "this kind - Amazon S3 is the only documented source (README.md Section 6, reference 6).",
      "",
      "The AWS IAM role this ARN names must already trust the Microsoft account ID + external ID",
      "shown in the Purview PORTAL's New credential pane - no REST endpoint returning those two",
      "values was found during this build's grounding pass (README.md Section 11 - VERIFY)."
    ],
    "kind": "AmazonARN",
    "properties": {
      "description": "Role ARN credential for Amazon S3 Data Map scanning",
      "typeProperties": {
        "roleARN": "arn:aws:iam::<aws-account-id>:role/<role-name>"
      }
    }
  },

  "credentialConsumerKeyAuth": {
    "$comment": [
      "kind 'ConsumerKeyAuth' -> ConsumerKeyCredentialProperties -> typeProperties is",
      "KeyVaultSecretConsumerKeyCredentialTypeProperties { user, consumerKey: <plain string>,",
      "consumerSecret: KeyVaultSecret, password: KeyVaultSecret }. TWO independent KeyVaultSecret",
      "references. consumerKey itself is a plain string, NOT a secret reference - confirmed directly",
      "from the schema (README.md Section 11). Salesforce is the only documented source",
      "(README.md Section 6, reference 7)."
    ],
    "kind": "ConsumerKeyAuth",
    "properties": {
      "description": "Consumer Key credential for Salesforce Data Map scanning",
      "typeProperties": {
        "user": "<salesforce-username>",
        "consumerKey": "<salesforce-connected-app-consumer-key>",
        "consumerSecret": {
          "type": "AzureKeyVaultSecret",
          "store": {
            "referenceName": "<key-vault-connection-name>",
            "type": "LinkedServiceReference"
          },
          "secretName": "<consumer-secret-name-in-key-vault>"
        },
        "password": {
          "type": "AzureKeyVaultSecret",
          "store": {
            "referenceName": "<key-vault-connection-name>",
            "type": "LinkedServiceReference"
          },
          "secretName": "<password-secret-name-in-key-vault>"
        }
      }
    }
  },

  "credentialDelegatedAuth": {
    "$comment": [
      "kind 'DelegatedAuth' -> DelegatedAuthCredentialProperties -> typeProperties is",
      "KeyVaultSecretDelegatedAuthCredentialTypeProperties { clientId, password: KeyVaultSecret,",
      "user }. Confirmed against Microsoft Fabric / Power BI worked examples (README.md Section 6,",
      "references 9-10): Client ID = the scanning app registration's Application (client) ID,",
      "User name = a Fabric Administrator / Power BI admin account, Password = that account's",
      "password stored in Key Vault."
    ],
    "kind": "DelegatedAuth",
    "properties": {
      "description": "Delegated auth credential for Microsoft Fabric / Power BI Data Map scanning",
      "typeProperties": {
        "clientId": "<app-registration-client-id>",
        "user": "<fabric-or-power-bi-admin-username>",
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

  "credentialManagedIdentity": {
    "$comment": [
      "kind 'ManagedIdentity' -> ManagedIdentityAzureKeyVaultCredentialProperties -> typeProperties",
      "is KeyVaultSecretManagedIdentityAzureKeyVaultCredentialTypeProperties { principalId,",
      "resourceId, tenantId }. NO KeyVaultSecret anywhere in this kind - a user-assigned managed",
      "identity has no stored secret at all. PREVIEW capability per Microsoft's own",
      "'Credentials for source authentication' page as of this build (README.md Section 11).",
      "The referenced identity must already be added to the Purview account (Azure portal ->",
      "Managed identities blade) and granted access at the target source - this scenario does not",
      "create either."
    ],
    "kind": "ManagedIdentity",
    "properties": {
      "description": "User-assigned managed identity credential for Data Map scanning (Preview)",
      "typeProperties": {
        "principalId": "<uami-principal-object-id>",
        "resourceId": "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<uami-name>",
        "tenantId": "<tenant-id>"
      }
    }
  }
}
```