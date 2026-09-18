---
part: "validate"
parent: "data-map/scan-credential-key-vault-backed"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-PurviewScanCredential.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only verification that a Purview Data Map scan credential and its Azure Key Vault
    connection exist, are wired to each other correctly, and that the referenced Key Vault secret
    is actually reachable.

.DESCRIPTION
    Runs a graded set of checks and prints a [PASS]/[WARN]/[FAIL] line for each, then exits 0 if
    no check FAILed and 1 otherwise (so it can gate a pipeline). Idempotent and safe to re-run: it
    issues only GET requests against the Purview Scanning data-plane API and, optionally, a
    metadata-only read against Azure Key Vault. It never writes, never runs a scan, and never
    reads a secret's value.

    Checks performed:
      1. The Key Vault connection object exists and exposes a baseUrl.
      2. The credential object exists.
      3. The credential's kind matches -ExpectedCredentialType (when supplied).
      4. The credential's secret reference points at the expected Key Vault connection
         (store.referenceName) and secret (secretName).
      5. The secret reference's two discriminator literals (type / store.type) match what
         deploy/New-PurviewScanCredential.ps1 wrote. Reported as [WARN], never [FAIL] - these are
         this scenario's one open VERIFY (see README.md Section 11). A mismatch here read back from
         a portal-created credential is exactly the evidence needed to close that VERIFY, so the
         script prints the observed values rather than just complaining.
      6. Kind-specific completeness: user present for SqlAuth/BasicAuth; servicePrincipalId and
         tenant present for ServicePrincipal.
      7. (-CheckKeyVaultSecret, requires the Az.KeyVault module and an Az login) the referenced
         secret exists in the vault and is enabled. This is the single most common cause of a
         credential that validates structurally but fails at scan time.

    WHAT THIS SCRIPT CANNOT CHECK, and why - stated rather than silently omitted:
      - Whether the Purview account's managed identity can actually read the secret. Purview
        exposes no "test credential" API, and the Key Vault access grant is an Azure-side object
        this script's caller may not be able to read. -CheckKeyVaultSecret proves the secret
        exists from *your* identity's perspective, which is necessary but not sufficient.
      - Whether the stored password/key is currently valid at the data source.
      - Which scan objects reference this credential (no documented reverse lookup - see
        README.md Section 11).
    The only end-to-end proof remains a scan run that reaches Succeeded.

    Author-only reference code.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Scanning REST API.
    Data Reader on the collection is sufficient for the read-only checks here, per
    docs/rbac-model.md Section 5.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER CredentialName
    Name of the credential object to verify.

.PARAMETER KeyVaultConnectionName
    Name of the Key Vault connection the credential is expected to reference.

.PARAMETER ExpectedSecretName
    Optional. Assert that the credential's secret reference names this secret.

.PARAMETER ExpectedCredentialType
    Optional. Assert the credential's kind: SqlAuth, BasicAuth, or ServicePrincipal.

.PARAMETER ExpectedSecretReferenceType
    Expected KeyVaultSecret `type` literal. Defaults to 'AzureKeyVaultSecret' (see check 5).

.PARAMETER ExpectedSecretStoreReferenceType
    Expected KeyVaultSecret `store.type` literal. Defaults to 'LinkedServiceReference'.

.PARAMETER CheckKeyVaultSecret
    Also confirm the referenced secret exists and is enabled in the Azure Key Vault, using the
    Az.KeyVault module under your current Az context. Reads metadata only (Get-AzKeyVaultSecret
    without -AsPlainText), never the secret value.

.PARAMETER ApiVersion
    Scanning data-plane REST API version to pin. Defaults to '2023-09-01'.

.EXAMPLE
    ./Test-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
        -KeyVaultConnectionName 'kv-contoso-purview'

    Structural verification only.

.EXAMPLE
    ./Test-PurviewScanCredential.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -CredentialName 'onprem-sql-svc-account' `
        -KeyVaultConnectionName 'kv-contoso-purview' -ExpectedSecretName 'onprem-sql-scan-password' `
        -ExpectedCredentialType SqlAuth -CheckKeyVaultSecret

    Full verification including the Key Vault secret's existence and enabled state.

.NOTES
    Sources (Microsoft Learn, direct-fetched for this build):
    - Credential - Get / List (object shape: name, kind, properties.description,
      properties.typeProperties):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential
    - Key Vault Connections - Get (AzureKeyVault { id, name, properties.baseUrl }):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections
    - Credentials for source authentication in Microsoft Purview Data Map (Purview MSI needs Get +
      List on the vault's secrets, or the Key Vault Secrets User role):
      https://learn.microsoft.com/purview/data-map-data-scan-credentials
    - Get-AzKeyVaultSecret (metadata read; the value is only returned with -AsPlainText, which this
      script never passes):
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

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultConnectionName,

    [Parameter()]
    [string]$ExpectedSecretName,

    [Parameter()]
    [ValidateSet('SqlAuth', 'BasicAuth', 'ServicePrincipal')]
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
        # Anything other than a clean 404 is a real problem (auth, network, throttling) and must
        # not be reported as "the object doesn't exist" - rethrow with context.
        throw "GET $Uri failed with a non-404 error: $($_.Exception.Message)"
    }
}

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

Write-Host "`n=== Purview scan credential verification: '$CredentialName' on '$PurviewAccountName' ===`n" -ForegroundColor White

# --- Check 1: Key Vault connection exists ---
$kvUri = "$endpoint/scan/azureKeyVaults/$KeyVaultConnectionName`?api-version=$ApiVersion"
$kv = Get-PurviewObjectOrNull -Uri $kvUri -Token $token
if ($null -eq $kv) {
    Write-Check FAIL "Key Vault connection '$KeyVaultConnectionName' not found (HTTP 404) - i.e. absent OR not visible to this identity. Confirm -AppId holds at least Data Reader on the target collection before concluding the object is missing."
}
elseif (-not $kv.properties.baseUrl) {
    Write-Check WARN "Key Vault connection '$KeyVaultConnectionName' exists but reports no baseUrl."
}
else {
    Write-Check PASS "Key Vault connection '$KeyVaultConnectionName' exists -> $($kv.properties.baseUrl)"
}

# --- Check 2: credential exists ---
$credentialUri = "$endpoint/scan/credentials/$CredentialName`?api-version=$ApiVersion"
$cred = Get-PurviewObjectOrNull -Uri $credentialUri -Token $token
if ($null -eq $cred) {
    Write-Check FAIL "Credential '$CredentialName' not found (HTTP 404) - absent OR not visible to this identity; confirm -AppId's collection role before concluding it is missing. (If you just ran Remove-PurviewScanCredential.ps1, this FAIL is the expected, intended result - see rollback.md.)"
    Write-Host "`nSummary: $script:Failures failed, $script:Warnings warning(s)." -ForegroundColor White
    exit 1
}
Write-Check PASS "Credential '$CredentialName' exists (kind: $($cred.kind))."

# --- Check 3: credential kind ---
if ($ExpectedCredentialType) {
    if ($cred.kind -eq $ExpectedCredentialType) {
        Write-Check PASS "Credential kind matches expected '$ExpectedCredentialType'."
    }
    else {
        Write-Check FAIL "Credential kind is '$($cred.kind)' but '$ExpectedCredentialType' was expected. A scan referencing it with the wrong credentialType will fail."
    }
}

# --- Locate the KeyVaultSecret-shaped child of typeProperties, whichever property holds it ---
# SqlAuth/BasicAuth -> password; ServicePrincipal -> servicePrincipalKey; other kinds ->
# accountKey / consumerSecret. Walking the object is kind-agnostic and survives future kinds.
$tp = $cred.properties.typeProperties
$secretRef = $null
$secretRefProperty = $null
if ($tp) {
    foreach ($prop in $tp.PSObject.Properties) {
        if ($prop.Value -and $prop.Value.PSObject.Properties.Name -contains 'secretName') {
            $secretRef = $prop.Value
            $secretRefProperty = $prop.Name
            break
        }
    }
}

if ($null -eq $secretRef) {
    Write-Check FAIL "Credential '$CredentialName' carries no Key Vault secret reference under properties.typeProperties. It was likely created with a description only (Microsoft's own worked example does exactly that) and cannot authenticate a scan."
}
else {
    Write-Check INFO "Secret reference found at typeProperties.$secretRefProperty"

    # --- Check 4: secret reference wiring ---
    $storeRef = $secretRef.store.referenceName
    if ($storeRef -eq $KeyVaultConnectionName) {
        Write-Check PASS "Secret reference points at Key Vault connection '$KeyVaultConnectionName'."
    }
    else {
        Write-Check FAIL "Secret reference points at Key Vault connection '$storeRef', not '$KeyVaultConnectionName'."
    }

    if ($ExpectedSecretName) {
        if ($secretRef.secretName -eq $ExpectedSecretName) {
            Write-Check PASS "Secret name matches expected '$ExpectedSecretName'."
        }
        else {
            Write-Check FAIL "Secret name is '$($secretRef.secretName)' but '$ExpectedSecretName' was expected."
        }
    }
    else {
        Write-Check INFO "Secret name: '$($secretRef.secretName)' (no -ExpectedSecretName supplied to assert against)."
    }

    if ($secretRef.secretVersion) {
        Write-Check INFO "Secret version pinned to '$($secretRef.secretVersion)'. A Key Vault rotation will NOT take effect until this credential is re-deployed with the new version."
    }
    else {
        Write-Check INFO "No secret version pinned (expected to resolve to the latest version - itself an open VERIFY, see README.md Section 11)."
    }

    # --- Check 5: the two VERIFY discriminator literals (WARN only, never FAIL) ---
    foreach ($pair in @(
            @{ Label = 'type'; Observed = $secretRef.type; Expected = $ExpectedSecretReferenceType },
            @{ Label = 'store.type'; Observed = $secretRef.store.type; Expected = $ExpectedSecretStoreReferenceType }
        )) {
        if ($pair.Observed -eq $pair.Expected) {
            Write-Check PASS "Secret reference $($pair.Label) = '$($pair.Observed)' (matches this scenario's default)."
        }
        else {
            Write-Check WARN "Secret reference $($pair.Label) = '$($pair.Observed)', expected '$($pair.Expected)'. Not a failure: these two literals are this scenario's open VERIFY (README.md Section 11). If this credential was created in the PORTAL, the observed value is authoritative - record it and re-deploy with -SecretReferenceType/-SecretStoreReferenceType to match."
        }
    }
}

# --- Check 6: kind-specific completeness ---
switch ($cred.kind) {
    { $_ -in 'SqlAuth', 'BasicAuth' } {
        if ($tp.user) { Write-Check PASS "typeProperties.user is set ('$($tp.user)')." }
        else { Write-Check FAIL "typeProperties.user is missing - a $($cred.kind) credential needs the login the secret's password belongs to." }
    }
    'ServicePrincipal' {
        if ($tp.servicePrincipalId) { Write-Check PASS "typeProperties.servicePrincipalId is set ('$($tp.servicePrincipalId)')." }
        else { Write-Check FAIL "typeProperties.servicePrincipalId is missing." }
        if ($tp.tenant) { Write-Check PASS "typeProperties.tenant is set ('$($tp.tenant)')." }
        else { Write-Check FAIL "typeProperties.tenant is missing." }
        if ($tp.servicePrincipalId -and $tp.servicePrincipalId -eq $AppId) {
            Write-Check WARN "The scan's service principal is the same app registration used to call the Purview API (-AppId). These are different roles; reusing one principal widens its blast radius. See design.md Section 4."
        }
    }
    default {
        Write-Check INFO "Credential kind '$($cred.kind)' is outside this scenario's three scripted kinds - completeness checks skipped."
    }
}

# --- Check 7 (optional): the Key Vault secret itself ---
if ($CheckKeyVaultSecret) {
    if ($null -eq $secretRef) {
        Write-Check WARN "-CheckKeyVaultSecret skipped: no secret reference to resolve."
    }
    elseif (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        Write-Check WARN "-CheckKeyVaultSecret skipped: the Az.KeyVault module is not installed. Install-Module Az.KeyVault, then Connect-AzAccount."
    }
    elseif (-not $kv -or -not $kv.properties.baseUrl) {
        Write-Check WARN "-CheckKeyVaultSecret skipped: the Key Vault connection's baseUrl is unknown, so the vault name cannot be derived."
    }
    else {
        # Derive the vault name from the connection's baseUrl (https://<vault>.vault.azure.net/).
        $vaultName = ([uri]$kv.properties.baseUrl).Host.Split('.')[0]
        try {
            # Metadata only - no -AsPlainText, so the secret value is never retrieved.
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretRef.secretName -ErrorAction Stop
            if ($null -eq $secret) {
                Write-Check FAIL "Secret '$($secretRef.secretName)' was not found in Key Vault '$vaultName'. The credential will fail at scan time."
            }
            elseif ($secret.Enabled -eq $false) {
                Write-Check FAIL "Secret '$($secretRef.secretName)' exists in Key Vault '$vaultName' but is DISABLED."
            }
            else {
                Write-Check PASS "Secret '$($secretRef.secretName)' exists and is enabled in Key Vault '$vaultName'."
                if ($secret.Expires -and $secret.Expires -lt (Get-Date)) {
                    Write-Check WARN "Secret '$($secretRef.secretName)' has an expiry date in the past ($($secret.Expires.ToString('u')))."
                }
                elseif ($secret.Expires -and $secret.Expires -lt (Get-Date).AddDays(30)) {
                    Write-Check WARN "Secret '$($secretRef.secretName)' expires within 30 days ($($secret.Expires.ToString('u'))). Plan the rotation."
                }
            }
        }
        catch {
            Write-Check WARN "Could not read secret metadata from Key Vault '$vaultName': $($_.Exception.Message). This may mean YOUR identity lacks Get on the vault's secrets - it does not by itself prove the Purview managed identity cannot read it."
        }
    }
}

Write-Host ""
Write-Check INFO "Structural verification only. No Purview API tests a credential end-to-end; the sole proof is a scan run reaching Succeeded. See README.md Section 7."
Write-Host "`nSummary: $script:Failures failed, $script:Warnings warning(s)." -ForegroundColor White

if ($script:Failures -gt 0) { exit 1 }
exit 0
```