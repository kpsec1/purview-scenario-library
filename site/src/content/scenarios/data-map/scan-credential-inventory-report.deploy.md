---
part: "deploy"
parent: "data-map/scan-credential-inventory-report"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-CredentialInventoryReport.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Exports a normalized, historical inventory of every Microsoft Purview Data Map scan credential
    (GET /scan/credentials, all eight documented CredentialType kinds) and flags any credential
    whose secret reference or identity fields no longer match a checked-in expected-state file -
    the estate-wide detective control the "silent credential re-point" gap in
    scenarios/data-map/scan-credential-key-vault-backed/README.md Section 11 (Red Team finding)
    currently has none of.

.DESCRIPTION
    Calls the Microsoft Purview Scanning data-plane Credential - List REST API (automation surface
    4 per docs/automation-surface.md, api-version 2023-09-01) to enumerate every credential object
    in the account, paging via the response's own 'nextLink' field until it is null.

    Purview credential objects are a discriminated union on 'kind' with eight documented shapes
    (AccountKey, ServicePrincipal, BasicAuth, SqlAuth, AmazonARN, ConsumerKeyAuth, DelegatedAuth,
    ManagedIdentity) - see README.md Section 6. This script normalizes every kind's 'typeProperties'
    into a flat set of named fields (a "fingerprint") using a per-kind extraction table, so one
    generic comparison engine can diff any credential against a checked-in expected-state JSON file
    (deploy/policy/expected-credential-inventory.json is a worked example) regardless of kind. No
    field extracted or written by this script is ever the secret VALUE - every field is either a
    plaintext identity property (user, servicePrincipalId, tenant, roleARN, clientId, principalId,
    resourceId, tenantId) or a Key Vault SECRET REFERENCE (secretName, store.referenceName,
    secretVersion) - never a password, key, or token. This matches the "credential stores a
    reference, never the secret itself" property scan-credential-key-vault-backed's design.md
    Section 3 establishes for credential creation; this script preserves it for credential reading.

    This generalizes scan-credential-key-vault-backed/validate/Test-PurviewScanCredential.ps1's
    per-credential -Expected* parameters into an estate-wide, checked-in-file-driven control -
    see PROGRESS.md's "Follow-ups discovered while building the Key Vault-backed scan credential
    scenario" for the item this scenario closes.

    Idempotency model: matches scenarios/data-estate-insights/classification-coverage-report's own
    pattern - re-running for the same -RunId (default: current UTC date, 'yyyy-MM-dd') REPLACES
    that RunId's rows in the trend log rather than appending duplicates. See design.md Section 5.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Read-only throughout - this script creates, modifies, and deletes nothing in
    Purview; its only side effect is writing the trend-log CSV and per-run drift-report JSON.

.PARAMETER PurviewAccountName
    The Purview account name (not the full URL). The scanning endpoint is derived as
    'https://<PurviewAccountName>.purview.azure.com' - the same endpoint shape
    scan-credential-key-vault-backed's own scripts use for this data plane.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Credential - List API. Must
    hold at minimum the Data Reader role on the collection(s) whose credentials should be visible -
    Credential is a Scanning-plane object alongside data sources and scans, and this script is a
    read-only consumer of it. See README.md Section 3 for the same by-analogy role caveat
    scan-credential-key-vault-backed/README.md Section 3 already carries for Data Source
    Administrator on the write path.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER ExpectedStatePath
    Path to a checked-in JSON file describing the expected credential inventory (name, kind, and a
    flat map of expected fingerprint fields per credential) - see
    deploy/policy/expected-credential-inventory.json for the worked shape. Optional: omit to produce
    an inventory-only report (every credential's normalized fingerprint, no drift comparison).

.PARAMETER TrendLogPath
    Path to the append/replace-by-RunId CSV trend log (one row per RunId x CredentialName). Created
    with a header row if it doesn't already exist.

.PARAMETER DriftReportDirectory
    Directory to write this run's full drift-report JSON
    ('<RunId>-credential-inventory-drift.json') - the complete per-credential fingerprint plus any
    field-level mismatches against -ExpectedStatePath. Created if it doesn't already exist.

.PARAMETER RunId
    Identifier for this report run, used both as a trend-log column and to make re-runs replace
    rather than duplicate. Defaults to the current UTC date ('yyyy-MM-dd').

.PARAMETER ApiVersion
    Purview Scanning data-plane REST API version to pin. Defaults to '2023-09-01', the version
    scan-credential-key-vault-backed's own scripts were grounded against and confirmed current via
    a direct fetch of the Credential - List REST reference page.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. The read-only Credential - List calls still execute
    (needed to report accurate would-be numbers), but neither the trend-log CSV nor the drift-report
    file is written - the script prints a summary instead.

.EXAMPLE
    ./Export-CredentialInventoryReport.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -TrendLogPath './out/credential-inventory-trend.csv' `
        -DriftReportDirectory './out/drift-reports' -WhatIf

    Dry run: lists every credential, computes fingerprints, prints a per-credential summary, writes
    nothing to disk.

.EXAMPLE
    ./Export-CredentialInventoryReport.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ExpectedStatePath './policy/expected-credential-inventory.json' `
        -TrendLogPath './out/credential-inventory-trend.csv' `
        -DriftReportDirectory './out/drift-reports'

    Full run with drift detection: appends/replaces today's trend-log row(s) and writes a drift
    report flagging any credential that is new, missing, or whose fingerprint no longer matches the
    checked-in expected state.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - This script treats the Credential - List response's 'nextLink' as a directly-callable,
      fully-qualified URL and pages until it is null. Microsoft's Credential - List reference
      documents the field only as "The link to the next page of results, if any remaining results
      exist" with no worked multi-page example populating it (its one worked example returns 2
      credentials, count 2, nextLink null) - this is the standard Azure REST list-pagination
      convention used elsewhere in this repo (e.g. Discovery - Query's continuationToken-based
      paging follows the same "call what the server gives you" pattern), not a Purview-specific
      confirmed example for THIS field on THIS endpoint.
    - AmazonARN (RoleARNCredential) and ManagedIdentity credentials carry no Key Vault secret
      reference at all in their typeProperties - roleARN and principalId/resourceId/tenantId are
      plain strings, not KeyVaultSecret objects. This script's fingerprint extraction reflects that
      structural difference rather than forcing every kind through the same secret-reference shape.

    Sources (Microsoft Learn, verify before production use):
    - Credential - List REST reference (API version 2023-09-01) - response envelope, worked
      2-credential example, all eight kind-specific properties/typeProperties definitions:
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list
    - Credential - Create Or Replace REST reference - the same eight kind definitions from the
      write side, cross-checked for consistency:
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace
    - Tutorial: Use REST APIs to authenticate for Microsoft Purview data-plane APIs:
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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

    [Parameter()]
    [string]$ExpectedStatePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TrendLogPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DriftReportDirectory,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunId = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'
$endpoint = "https://$PurviewAccountName.purview.azure.com"

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$PlainSecret
    )
    $body = @{
        client_id     = $AppId
        client_secret = $PlainSecret
        grant_type    = 'client_credentials'
        resource      = 'https://purview.azure.net'
    }
    $response = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
    return $response.access_token
}

function Get-KeyVaultSecretFields {
    # Flattens a KeyVaultSecret sub-object { secretName, secretVersion, store: { referenceName, type }, type }
    # into a prefixed, flat field set. Never touches the secret VALUE - the API itself never returns it.
    param([Parameter(Mandatory)][string]$Prefix, $KeyVaultSecret)
    $fields = [ordered]@{}
    $fields["$Prefix.SecretName"] = $KeyVaultSecret.secretName
    $fields["$Prefix.SecretVersion"] = if ($KeyVaultSecret.secretVersion) { $KeyVaultSecret.secretVersion } else { '(latest - unpinned)' }
    $fields["$Prefix.KeyVaultConnectionName"] = $KeyVaultSecret.store.referenceName
    return $fields
}

function Get-CredentialFingerprint {
    # Per-kind extraction table. Every kind's typeProperties shape is grounded against the
    # Credential - List / Create Or Replace REST references (README.md Section 6 / .NOTES above).
    # Returns an ordered hashtable of named fields - the "fingerprint" this scenario diffs.
    param([Parameter(Mandatory)]$Credential)

    $tp = $Credential.properties.typeProperties
    $fields = [ordered]@{}

    switch ($Credential.kind) {
        { $_ -in 'SqlAuth', 'BasicAuth' } {
            # UserPassCredentialProperties -> { user, password: KeyVaultSecret }
            $fields['User'] = $tp.user
            (Get-KeyVaultSecretFields -Prefix 'Password' -KeyVaultSecret $tp.password).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
        }
        'ServicePrincipal' {
            # KeyVaultSecretServicePrinipalCredentialTypeProperties -> { servicePrincipalId, servicePrincipalKey: KeyVaultSecret, tenant }
            $fields['ServicePrincipalId'] = $tp.servicePrincipalId
            $fields['Tenant'] = $tp.tenant
            (Get-KeyVaultSecretFields -Prefix 'ServicePrincipalKey' -KeyVaultSecret $tp.servicePrincipalKey).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
        }
        'AccountKey' {
            # KeyVaultSecretAccountKeyCredentialTypeProperties -> { accountKey: KeyVaultSecret }
            (Get-KeyVaultSecretFields -Prefix 'AccountKey' -KeyVaultSecret $tp.accountKey).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
        }
        'AmazonARN' {
            # RoleARNCredentialTypeProperties -> { roleARN } - a plain string, NOT a KeyVaultSecret.
            # This kind authenticates via AWS role assumption, not a Purview-held secret at all.
            $fields['RoleARN'] = $tp.roleARN
        }
        'ConsumerKeyAuth' {
            # KeyVaultSecretConsumerKeyCredentialTypeProperties -> { consumerKey, consumerSecret: KeyVaultSecret, password: KeyVaultSecret, user }
            $fields['User'] = $tp.user
            $fields['ConsumerKey'] = $tp.consumerKey
            (Get-KeyVaultSecretFields -Prefix 'ConsumerSecret' -KeyVaultSecret $tp.consumerSecret).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
            (Get-KeyVaultSecretFields -Prefix 'Password' -KeyVaultSecret $tp.password).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
        }
        'DelegatedAuth' {
            # KeyVaultSecretDelegatedAuthCredentialTypeProperties -> { clientId, password: KeyVaultSecret, user }
            $fields['ClientId'] = $tp.clientId
            $fields['User'] = $tp.user
            (Get-KeyVaultSecretFields -Prefix 'Password' -KeyVaultSecret $tp.password).GetEnumerator() | ForEach-Object { $fields[$_.Key] = $_.Value }
        }
        'ManagedIdentity' {
            # KeyVaultSecretManagedIdentityAzureKeyVaultCredentialTypeProperties -> { principalId, resourceId, tenantId }
            # No Key Vault reference at all - a user-assigned managed identity has no stored secret.
            $fields['PrincipalId'] = $tp.principalId
            $fields['ResourceId'] = $tp.resourceId
            $fields['TenantId'] = $tp.tenantId
        }
        default {
            Write-Warning "Credential '$($Credential.name)': unrecognized kind '$($Credential.kind)' - Microsoft's documented CredentialType enum is AccountKey/ServicePrincipal/BasicAuth/SqlAuth/AmazonARN/ConsumerKeyAuth/DelegatedAuth/ManagedIdentity. Recording no fingerprint fields for this credential; investigate before trusting this run's drift report for it."
        }
    }
    return $fields
}

function Compare-Fingerprint {
    # Generic, kind-agnostic diff: every field named in $Expected must match $Actual exactly.
    # An expected field absent from $Actual (e.g. expected state written for the wrong kind) is
    # itself reported as a mismatch, not silently skipped.
    param([Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Actual, [hashtable]$Expected)
    $mismatches = @()
    if (-not $Expected) { return $mismatches }
    foreach ($key in $Expected.Keys) {
        $expectedValue = [string]$Expected[$key]
        $actualValue = if ($Actual.Contains($key)) { [string]$Actual[$key] } else { $null }
        if ($actualValue -ne $expectedValue) {
            $mismatches += [pscustomobject]@{
                Field    = $key
                Expected = $expectedValue
                Actual   = ($actualValue ?? '(field not present on this credential)')
            }
        }
    }
    return $mismatches
}

# --- Authenticate ---
$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Page through GET /scan/credentials until nextLink is null (see .NOTES) ---
$credentials = @()
$uri = "$endpoint/scan/credentials?api-version=$ApiVersion"
do {
    Write-Verbose "GET $uri"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $token" }
    $credentials += @($response.value)
    $uri = $response.nextLink
} while ($uri)

if ($credentials.Count -ne [int]$response.count -and $response.PSObject.Properties.Name -contains 'count') {
    Write-Warning ("Paged {0} credential(s) but the API's own 'count' field reported {1}. Microsoft's " +
        "reference does not document this as an error condition - investigate before trusting this " +
        "run's inventory as complete." -f $credentials.Count, [int]$response.count)
}

# --- Load expected state (optional) ---
$expectedByName = @{}
if ($ExpectedStatePath) {
    if (-not (Test-Path -Path $ExpectedStatePath -PathType Leaf)) {
        throw "ExpectedStatePath '$ExpectedStatePath' was supplied but does not exist."
    }
    $expectedDefinitions = Get-Content -Path $ExpectedStatePath -Raw | ConvertFrom-Json -Depth 10
    foreach ($def in $expectedDefinitions.credentials) {
        $expectedByName[$def.name] = $def
    }
}

# --- Build the per-credential report ---
$results = foreach ($credential in $credentials) {
    $fingerprint = Get-CredentialFingerprint -Credential $credential
    $expected = $expectedByName[$credential.name]
    $mismatches = @()
    $status = 'NotTracked'

    if ($expected) {
        $expectedFieldsHashtable = @{}
        $expected.expectedFields.PSObject.Properties | ForEach-Object { $expectedFieldsHashtable[$_.Name] = $_.Value }
        if ($expected.kind -ne $credential.kind) {
            $mismatches += [pscustomobject]@{ Field = 'kind'; Expected = $expected.kind; Actual = $credential.kind }
        }
        $mismatches += Compare-Fingerprint -Actual $fingerprint -Expected $expectedFieldsHashtable
        $status = if ($mismatches.Count -eq 0) { 'Match' } else { 'Drift' }
    }

    [pscustomobject]@{
        RunId           = $RunId
        RunTimestampUtc = [datetime]::UtcNow.ToString('o')
        Name            = $credential.name
        Kind            = $credential.kind
        Status          = $status
        MismatchCount   = $mismatches.Count
        Mismatches      = $mismatches
        Fingerprint     = $fingerprint
    }
}

# --- Credentials expected but absent from the live tenant (deleted, or never deployed) ---
$missingNames = $expectedByName.Keys | Where-Object { $_ -notin $results.Name }
foreach ($missingName in $missingNames) {
    $results += [pscustomobject]@{
        RunId           = $RunId
        RunTimestampUtc = [datetime]::UtcNow.ToString('o')
        Name            = $missingName
        Kind            = $expectedByName[$missingName].kind
        Status          = 'Missing'
        MismatchCount   = 1
        Mismatches      = @([pscustomobject]@{ Field = '(entire credential)'; Expected = 'present'; Actual = 'not found in GET /scan/credentials' })
        Fingerprint     = [ordered]@{}
    }
}

# --- Console summary (printed regardless of -WhatIf, so a dry run still shows the numbers) ---
Write-Host "Credential inventory for '$PurviewAccountName' (RunId '$RunId'): $($credentials.Count) credential(s) found." -ForegroundColor Cyan
foreach ($row in ($results | Sort-Object Name)) {
    $color = switch ($row.Status) {
        'Drift'      { 'Red' }
        'Missing'    { 'Red' }
        'Match'      { 'Green' }
        default      { 'Yellow' }
    }
    Write-Host ("  [{0}] {1} (kind: {2}){3}" -f $row.Status, $row.Name, $row.Kind, `
        (if ($row.MismatchCount -gt 0) { " - $($row.MismatchCount) mismatch(es): $(($row.Mismatches | ForEach-Object { $_.Field }) -join ', ')" } else { '' })) -ForegroundColor $color
}
$driftCount = @($results | Where-Object { $_.Status -in 'Drift', 'Missing' }).Count
if ($driftCount -gt 0) {
    Write-Warning "$driftCount credential(s) drifted from or are missing against the expected state in '$ExpectedStatePath'. Review the drift-report JSON before assuming this is benign - see README.md Section 8's runbook."
}

# --- Write the trend-log CSV (replace-by-RunId) and this run's full drift-report JSON ---
$writeDescription = "Write/replace RunId '$RunId' row(s) in trend log '$TrendLogPath' and drift-report JSON in '$DriftReportDirectory'"
if ($PSCmdlet.ShouldProcess($writeDescription, 'Write report files')) {
    $existingRows = @()
    if (Test-Path -Path $TrendLogPath -PathType Leaf) {
        $existingRows = @(Import-Csv -Path $TrendLogPath | Where-Object { $_.RunId -ne $RunId })
    }
    $trendRows = $existingRows + ($results | Select-Object RunId, RunTimestampUtc, Name, Kind, Status, MismatchCount)
    $trendRows | Sort-Object RunId, Name | Export-Csv -Path $TrendLogPath -NoTypeInformation

    New-Item -Path $DriftReportDirectory -ItemType Directory -Force | Out-Null
    $reportPath = Join-Path $DriftReportDirectory "$RunId-credential-inventory-drift.json"
    $results | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding utf8

    Write-Host "`nTrend log updated: $TrendLogPath" -ForegroundColor Cyan
    Write-Host "Drift report written to: $reportPath" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $writeDescription"
}
```

#### `policy/expected-credential-inventory.json`

```json
{
  "$comment": [
    "Worked example of a checked-in expected-state file for",
    "deploy/Export-CredentialInventoryReport.ps1's -ExpectedStatePath parameter. This file is NOT",
    "read automatically - it is a starting point to copy, rename, and fill in with your tenant's",
    "own credential inventory (README.md Section 5/6).",
    "",
    "Each entry's 'expectedFields' map uses the same flat field names",
    "Get-CredentialFingerprint (deploy/Export-CredentialInventoryReport.ps1) produces for that kind -",
    "see README.md Section 6's fingerprint-field table for the full per-kind list. Only include the",
    "fields you want tracked; any field named here that the live credential doesn't match (or",
    "doesn't have) is reported as a drift/mismatch. No field here is ever a secret VALUE - only",
    "identity properties and Key Vault SECRET REFERENCES (name/version/connection), matching the",
    "same 'reference only, never the secret' boundary scan-credential-key-vault-backed/design.md",
    "Section 3 establishes for credential creation.",
    "",
    "The two entries below correspond to the two credentials",
    "scan-credential-key-vault-backed/deploy/policy/scan-credential-definitions.json creates -",
    "this file is this scenario's natural expected-state starting point when both scenarios are",
    "deployed together."
  ],

  "credentials": [
    {
      "name": "onprem-sql-svc-account",
      "kind": "SqlAuth",
      "expectedFields": {
        "User": "purview_scanner",
        "Password.SecretName": "onprem-sql-scan-password",
        "Password.KeyVaultConnectionName": "kv-contoso-purview",
        "Password.SecretVersion": "(latest - unpinned)"
      }
    },
    {
      "name": "azuresql-scan-sp",
      "kind": "ServicePrincipal",
      "expectedFields": {
        "ServicePrincipalId": "<scan-service-principal-app-id>",
        "Tenant": "<tenant-id>",
        "ServicePrincipalKey.SecretName": "purview-scan-sp-secret",
        "ServicePrincipalKey.KeyVaultConnectionName": "kv-contoso-purview"
      }
    }
  ]
}
```