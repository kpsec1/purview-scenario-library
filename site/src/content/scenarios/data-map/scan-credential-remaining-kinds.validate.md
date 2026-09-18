---
part: "validate"
parent: "data-map/scan-credential-remaining-kinds"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PurviewScanCredentialExtended.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only verification of a Purview Data Map scan credential of one of the five kinds
    deploy/New-PurviewScanCredentialExtended.ps1 creates: AccountKey, AmazonARN, ConsumerKeyAuth,
    DelegatedAuth, or ManagedIdentity.

.DESCRIPTION
    Same [PASS]/[WARN]/[FAIL] pattern and non-zero-on-FAIL exit code as the parent scenario's
    Test-PurviewScanCredential.ps1, extended with a per-kind completeness table instead of a single
    three-kind switch. Idempotent and safe to re-run: issues only GET requests against the Purview
    Scanning data-plane API and, optionally, metadata-only reads against Azure Key Vault. Never
    writes, never runs a scan, never reads a secret's value.

    Checks performed:
      1. The credential object exists.
      2. The credential's kind matches -ExpectedCredentialType (when supplied).
      3. Kind-specific field completeness (README.md Section 6):
           AccountKey       -> accountKey secret reference present
           AmazonARN        -> roleARN present and shaped like an AWS role ARN ([WARN] if not - a
                                format sanity check, not an AWS-side call)
           ConsumerKeyAuth  -> user, consumerKey present; consumerSecret AND password secret
                                references present (TWO independent references)
           DelegatedAuth    -> clientId, user present; password secret reference present
           ManagedIdentity  -> principalId, resourceId, tenantId all present; prints a [INFO]
                                Preview reminder
      4. For every KeyVaultSecret-shaped field the kind carries: the two discriminator literals
         (type / store.type) compared against -ExpectedSecretReferenceType /
         -ExpectedSecretStoreReferenceType. [WARN] only, never [FAIL] - same open VERIFY as the
         parent scenario.
      5. (-CheckKeyVaultSecret) every secret the kind carries (both, for ConsumerKeyAuth) resolved
         via Get-AzKeyVaultSecret without -AsPlainText. The Azure Key Vault name is derived the same
         authoritative way as the parent scenario's check 1 - a GET against the Key Vault connection
         object first, then reading the real vault name out of its baseUrl - not assumed to equal the
         Purview connection name (store.referenceName).

    WHAT THIS SCRIPT CANNOT CHECK:
      - For AmazonARN: whether the AWS-side IAM role trust policy is actually configured correctly.
        That is an AWS-console fact, not a Purview one.
      - For ManagedIdentity: whether the referenced user-assigned managed identity is actually
        attached to the Purview account or granted access at the target source - only that the
        credential object carries those three ID strings.
      - Everything the parent scenario's own script cannot check (no "test credential" API; no
        credential-to-scan reverse lookup). The only end-to-end proof for any kind remains a scan
        run reaching Succeeded.

    Author-only reference code.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Scanning REST API.
    Data Reader on the collection is sufficient for these read-only checks.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER CredentialName
    Name of the credential object to verify.

.PARAMETER ExpectedCredentialType
    Optional. Assert the credential's kind.

.PARAMETER ExpectedSecretReferenceType
    Expected KeyVaultSecret `type` literal for any secret-bearing field. Defaults to
    'AzureKeyVaultSecret'.

.PARAMETER ExpectedSecretStoreReferenceType
    Expected KeyVaultSecret `store.type` literal. Defaults to 'LinkedServiceReference'.

.PARAMETER CheckKeyVaultSecret
    Also confirm every secret this credential's kind references exists and is enabled in Azure Key
    Vault, using the Az.KeyVault module under your current Az context. Metadata only.

.PARAMETER ApiVersion
    Scanning data-plane REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 's3-role-arn' `
        -ExpectedCredentialType AmazonARN

    Structural verification of an AmazonARN credential, including its ARN's string shape.

.EXAMPLE
    ./Test-PurviewScanCredentialExtended.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'salesforce-consumer-key' `
        -ExpectedCredentialType ConsumerKeyAuth -CheckKeyVaultSecret

    Full verification of a ConsumerKeyAuth credential, including both of its Key Vault secrets.

.NOTES
    Sources (Microsoft Learn, direct-fetched for this build via the Microsoft Learn MCP tool):
    - Credential - Get / List (object shape per kind):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential
    - Credential - Create Or Replace (typeProperties definitions used to build the per-kind
      completeness checks below):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace
    - Key Vault Connections - Get (AzureKeyVault { id, name, properties.baseUrl }; same endpoint the
      parent scenario's Test-PurviewScanCredential.ps1 check 1 uses, reused here by
      Get-KeyVaultNameForConnection for the same authoritative vault-name derivation):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections
    - Get-AzKeyVaultSecret (metadata read; never -AsPlainText):
      https://learn.microsoft.com/powershell/module/az.keyvault/get-azkeyvaultsecret
#>
[CmdletBinding()]
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
    [ValidateNotNullOrEmpty()]
    [string]$CredentialName,

    [Parameter()]
    [ValidateSet('AccountKey', 'AmazonARN', 'ConsumerKeyAuth', 'DelegatedAuth', 'ManagedIdentity')]
    [string]$ExpectedCredentialType,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedSecretReferenceType = 'AzureKeyVaultSecret',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedSecretStoreReferenceType = 'LinkedServiceReference',

    [Parameter()]
    [switch]$CheckKeyVaultSecret,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

$script:Failures = 0
$script:Warnings = 0

function Write-Check {
    param(
        [Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL', 'INFO')][string]$Result,
        [Parameter(Mandatory)][string]$Message
    )
    $color = switch ($Result) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'INFO' { 'Cyan' }
    }
    if ($Result -eq 'FAIL') { $script:Failures++ }
    if ($Result -eq 'WARN') { $script:Warnings++ }
    Write-Host ("[{0}] {1}" -f $Result, $Message) -ForegroundColor $color
}

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
        throw "GET $Uri failed with a non-404 error: $($_.Exception.Message)"
    }
}

# Purview connection name -> real Azure Key Vault name (or $null if it can't be derived), keyed so a
# ConsumerKeyAuth credential's two secret references - which commonly, but not necessarily, point at
# the same Key Vault connection - only trigger one GET each.
$script:KeyVaultConnectionCache = @{}

function Get-KeyVaultNameForConnection {
    <#
        Authoritative vault-name derivation, matching the parent scenario's Test-PurviewScanCredential.ps1
        check 1 exactly: GET the Key Vault connection object and read the real Azure Key Vault name out
        of its baseUrl (https://<vault>.vault.azure.net/), rather than assuming the Purview connection
        name and the Azure vault name are the same string.
    #>
    param(
        [Parameter(Mandatory)][string]$ConnectionName,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$ApiVersion
    )
    if ($script:KeyVaultConnectionCache.ContainsKey($ConnectionName)) {
        return $script:KeyVaultConnectionCache[$ConnectionName]
    }
    $kvUri = "$Endpoint/scan/azureKeyVaults/$ConnectionName`?api-version=$ApiVersion"
    $kv = Get-PurviewObjectOrNull -Uri $kvUri -Token $Token
    $vaultName = $null
    if ($kv -and $kv.properties.baseUrl) {
        $vaultName = ([uri]$kv.properties.baseUrl).Host.Split('.')[0]
    }
    $script:KeyVaultConnectionCache[$ConnectionName] = $vaultName
    return $vaultName
}

function Test-KeyVaultSecretReference {
    <#
        Runs checks 4 (discriminator literals) and, optionally, 5 (live secret existence) against
        one named KeyVaultSecret-shaped field. Returns nothing; writes checks directly so multiple
        references (ConsumerKeyAuth) can be checked in sequence with distinct labels.
    #>
    param(
        [Parameter(Mandatory)][string]$FieldLabel,
        [Parameter(Mandatory)]$SecretRef,
        [Parameter(Mandatory)][string]$ExpectedSecretReferenceType,
        [Parameter(Mandatory)][string]$ExpectedSecretStoreReferenceType,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$ApiVersion,
        [switch]$CheckKeyVaultSecret
    )
    if ($null -eq $SecretRef -or -not $SecretRef.secretName) {
        Write-Check FAIL "$FieldLabel is missing or carries no secretName."
        return
    }
    Write-Check PASS "$FieldLabel references secret '$($SecretRef.secretName)' via connection '$($SecretRef.store.referenceName)'."

    if ($SecretRef.secretVersion) {
        Write-Check INFO "$FieldLabel secret version pinned to '$($SecretRef.secretVersion)'."
    }
    else {
        Write-Check INFO "$FieldLabel has no secret version pinned (expected to resolve to the latest version - open VERIFY, see parent scenario's README.md Section 11)."
    }

    foreach ($pair in @(
            @{ Label = 'type'; Observed = $SecretRef.type; Expected = $ExpectedSecretReferenceType },
            @{ Label = 'store.type'; Observed = $SecretRef.store.type; Expected = $ExpectedSecretStoreReferenceType }
        )) {
        if ($pair.Observed -eq $pair.Expected) {
            Write-Check PASS "$FieldLabel $($pair.Label) = '$($pair.Observed)' (matches expected default)."
        }
        else {
            Write-Check WARN "$FieldLabel $($pair.Label) = '$($pair.Observed)', expected '$($pair.Expected)'. Not a failure - this is the open discriminator-literal VERIFY inherited from the parent scenario."
        }
    }

    if ($CheckKeyVaultSecret) {
        if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
            Write-Check WARN "$FieldLabel -CheckKeyVaultSecret skipped: the Az.KeyVault module is not installed."
            return
        }
        # Authoritative vault-name derivation (matches the parent scenario's check 1): GET the Key
        # Vault connection object named by store.referenceName and read the real Azure Key Vault name
        # out of its baseUrl, rather than assuming the Purview connection name equals the vault name.
        $vaultName = Get-KeyVaultNameForConnection -ConnectionName $SecretRef.store.referenceName `
            -Endpoint $Endpoint -Token $Token -ApiVersion $ApiVersion
        if (-not $vaultName) {
            Write-Check WARN "$FieldLabel -CheckKeyVaultSecret skipped: Key Vault connection '$($SecretRef.store.referenceName)' was not found or reports no baseUrl, so the Azure Key Vault name cannot be derived."
            return
        }
        try {
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $SecretRef.secretName -ErrorAction Stop
            if ($null -eq $secret) {
                Write-Check FAIL "$FieldLabel secret '$($SecretRef.secretName)' was not found in Key Vault '$vaultName'."
            }
            elseif ($secret.Enabled -eq $false) {
                Write-Check FAIL "$FieldLabel secret '$($SecretRef.secretName)' exists in Key Vault '$vaultName' but is DISABLED."
            }
            else {
                Write-Check PASS "$FieldLabel secret '$($SecretRef.secretName)' exists and is enabled in Key Vault '$vaultName'."
                if ($secret.Expires -and $secret.Expires -lt (Get-Date)) {
                    Write-Check WARN "$FieldLabel secret '$($SecretRef.secretName)' has an expiry date in the past ($($secret.Expires.ToString('u')))."
                }
                elseif ($secret.Expires -and $secret.Expires -lt (Get-Date).AddDays(30)) {
                    Write-Check WARN "$FieldLabel secret '$($SecretRef.secretName)' expires within 30 days ($($secret.Expires.ToString('u')))."
                }
            }
        }
        catch {
            Write-Check WARN "$FieldLabel - could not read secret metadata from Key Vault '$vaultName': $($_.Exception.Message). This may mean YOUR identity lacks Get on the vault's secrets - it does not by itself prove the Purview managed identity cannot read it."
        }
    }
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

Write-Host "`n=== Purview scan credential verification: '$CredentialName' on '$PurviewAccountName' ===`n" -ForegroundColor White

# --- Check 1: credential exists ---
$credentialUri = "$endpoint/scan/credentials/$CredentialName`?api-version=$ApiVersion"
$cred = Get-PurviewObjectOrNull -Uri $credentialUri -Token $token
if ($null -eq $cred) {
    Write-Check FAIL "Credential '$CredentialName' not found (HTTP 404) - absent OR not visible to this identity; confirm -AppId's collection role before concluding it is missing."
    Write-Host "`nSummary: $script:Failures failed, $script:Warnings warning(s)." -ForegroundColor White
    exit 1
}
Write-Check PASS "Credential '$CredentialName' exists (kind: $($cred.kind))."

# --- Check 2: credential kind ---
if ($ExpectedCredentialType) {
    if ($cred.kind -eq $ExpectedCredentialType) {
        Write-Check PASS "Credential kind matches expected '$ExpectedCredentialType'."
    }
    else {
        Write-Check FAIL "Credential kind is '$($cred.kind)' but '$ExpectedCredentialType' was expected."
    }
}

$tp = $cred.properties.typeProperties
if (-not $tp) {
    Write-Check FAIL "Credential '$CredentialName' carries no properties.typeProperties at all - it was likely created with a description only and cannot authenticate a scan."
    Write-Host "`nSummary: $script:Failures failed, $script:Warnings warning(s)." -ForegroundColor White
    if ($script:Failures -gt 0) { exit 1 }
    exit 0
}

# --- Check 3+4(+5): kind-specific completeness and secret-reference checks ---
switch ($cred.kind) {
    'AccountKey' {
        Test-KeyVaultSecretReference -FieldLabel 'typeProperties.accountKey' -SecretRef $tp.accountKey `
            -ExpectedSecretReferenceType $ExpectedSecretReferenceType -ExpectedSecretStoreReferenceType $ExpectedSecretStoreReferenceType `
            -Endpoint $endpoint -Token $token -ApiVersion $ApiVersion -CheckKeyVaultSecret:$CheckKeyVaultSecret
    }
    'AmazonARN' {
        if (-not $tp.roleARN) {
            Write-Check FAIL "typeProperties.roleARN is missing - an AmazonARN credential needs the AWS IAM role's ARN."
        }
        elseif ($tp.roleARN -notmatch '^arn:aws:iam::\d{12}:role/.+$') {
            Write-Check WARN "typeProperties.roleARN = '$($tp.roleARN)' does not match the expected AWS role ARN shape (arn:aws:iam::<12-digit-account-id>:role/<name>). This is a format sanity check only - it does not call AWS."
        }
        else {
            Write-Check PASS "typeProperties.roleARN is set and shaped like a valid AWS role ARN ('$($tp.roleARN)')."
        }
        Write-Check INFO "This script cannot confirm the AWS-side IAM role trust policy is configured correctly - that is an AWS-console fact. See README.md Section 7."
    }
    'ConsumerKeyAuth' {
        if ($tp.user) { Write-Check PASS "typeProperties.user is set ('$($tp.user)')." }
        else { Write-Check FAIL "typeProperties.user is missing." }

        if ($tp.consumerKey) { Write-Check PASS "typeProperties.consumerKey is set (plain text, not a secret reference)." }
        else { Write-Check FAIL "typeProperties.consumerKey is missing." }

        Test-KeyVaultSecretReference -FieldLabel 'typeProperties.consumerSecret' -SecretRef $tp.consumerSecret `
            -ExpectedSecretReferenceType $ExpectedSecretReferenceType -ExpectedSecretStoreReferenceType $ExpectedSecretStoreReferenceType `
            -Endpoint $endpoint -Token $token -ApiVersion $ApiVersion -CheckKeyVaultSecret:$CheckKeyVaultSecret
        Test-KeyVaultSecretReference -FieldLabel 'typeProperties.password' -SecretRef $tp.password `
            -ExpectedSecretReferenceType $ExpectedSecretReferenceType -ExpectedSecretStoreReferenceType $ExpectedSecretStoreReferenceType `
            -Endpoint $endpoint -Token $token -ApiVersion $ApiVersion -CheckKeyVaultSecret:$CheckKeyVaultSecret
    }
    'DelegatedAuth' {
        if ($tp.clientId) { Write-Check PASS "typeProperties.clientId is set ('$($tp.clientId)')." }
        else { Write-Check FAIL "typeProperties.clientId is missing." }
        if ($tp.user) { Write-Check PASS "typeProperties.user is set ('$($tp.user)')." }
        else { Write-Check FAIL "typeProperties.user is missing." }

        Test-KeyVaultSecretReference -FieldLabel 'typeProperties.password' -SecretRef $tp.password `
            -ExpectedSecretReferenceType $ExpectedSecretReferenceType -ExpectedSecretStoreReferenceType $ExpectedSecretStoreReferenceType `
            -Endpoint $endpoint -Token $token -ApiVersion $ApiVersion -CheckKeyVaultSecret:$CheckKeyVaultSecret
    }
    'ManagedIdentity' {
        if ($tp.principalId) { Write-Check PASS "typeProperties.principalId is set ('$($tp.principalId)')." }
        else { Write-Check FAIL "typeProperties.principalId is missing." }
        if ($tp.resourceId) { Write-Check PASS "typeProperties.resourceId is set ('$($tp.resourceId)')." }
        else { Write-Check FAIL "typeProperties.resourceId is missing." }
        if ($tp.tenantId) { Write-Check PASS "typeProperties.tenantId is set ('$($tp.tenantId)')." }
        else { Write-Check FAIL "typeProperties.tenantId is missing." }
        Write-Check INFO "ManagedIdentity (user-assigned) is a Microsoft-labeled Preview capability - see README.md Section 11. This script cannot confirm the referenced identity is attached to the Purview account or granted access at the target source."
    }
    default {
        Write-Check INFO "Credential kind '$($cred.kind)' is outside this scenario's five scripted kinds (and the parent scenario's three) - completeness checks skipped."
    }
}

Write-Host ""
Write-Check INFO "Structural verification only. No Purview API tests a credential end-to-end; the sole proof is a scan run reaching Succeeded. See README.md Section 7."
Write-Host "`nSummary: $script:Failures failed, $script:Warnings warning(s)." -ForegroundColor White

if ($script:Failures -gt 0) { exit 1 }
exit 0
```