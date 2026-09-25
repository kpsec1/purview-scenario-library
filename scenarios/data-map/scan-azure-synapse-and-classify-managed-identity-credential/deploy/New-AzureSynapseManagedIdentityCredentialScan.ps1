#Requires -Version 7.0
<#
.SYNOPSIS
    Reconciles the scan created by scan-azure-synapse-and-classify from Purview's system-assigned
    managed identity (SAMI) onto a user-assigned managed identity (UAMI) credential.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. GET the existing scan (created by scan-azure-synapse-and-classify/deploy/
         New-AzureSynapseDataMapScan.ps1) and confirm it is one of the two Azure Synapse workspace
         scan kinds this script knows how to reconcile (AzureSynapseWorkspaceMsi or
         AzureSynapseWorkspaceCredential - the latter allows re-running this script to point at a
         different UAMI credential).
      2. (best-effort precheck) GET the referenced credential object: warn (non-fatal) if it is
         missing - a 404 is ambiguous - but hard-stop (unless -Force) if it exists and is confirmed
         to be a kind other than ManagedIdentity, since that will deterministically fail at
         scan-run time.
      3. PUT the scan back with `kind` set to AzureSynapseWorkspaceCredential and
         `properties.credential` set to { credentialType: 'ManagedIdentity', referenceName:
         <-CredentialReferenceName> } - every other scan property (collection, scan rule set) copied
         forward from the existing object unchanged. Unlike the Azure SQL Database/Managed Instance
         siblings, this scan object carries no databaseName/serverEndpoint at all - both dedicated and
         serverless pool endpoints live on the DATA SOURCE object, which this script never touches.
      4. Optionally start an immediate scan run (-RunNow) to prove the new auth path works.

    Third sibling of scenarios/data-map/scan-azure-sql-and-classify-managed-identity-credential/ and
    scenarios/data-map/scan-azure-sql-managed-instance-and-classify-managed-identity-credential/ -
    same reconciliation pattern, but Azure Synapse Analytics is its own Purview scan `kind`
    (AzureSynapseWorkspaceCredential) with its own confirmed REST properties object
    (AzureSynapseWorkspaceCredentialScanProperties) - independently confirmed, not assumed identical
    to either sibling by naming convention. `ManagedIdentity` as a valid `credentialType` for THIS
    specific scan kind is confirmed by Microsoft's own worked JSON example on the canonical
    register-scan-synapse-workspace page (the same page scan-azure-synapse-and-classify's own build
    is grounded against) - see .NOTES. This is stronger grounding than either sibling had, both of
    which had to infer UAMI support for their specific scan kind from a separate, more generic
    "supported data sources for UAMI" list.

    This script does NOT create the UAMI itself, does NOT add it to the Purview account's Managed
    identities blade, and does NOT create the ManagedIdentity-kind credential object that references
    it - all three are prerequisites documented in README.md Section 3. Build the credential with
    scenarios/data-map/scan-credential-remaining-kinds/deploy/New-PurviewScanCredentialExtended.ps1
    -CredentialType ManagedIdentity first, then pass its name here as -CredentialReferenceName.

    Idempotent by construction: the mutating call is a REST PUT against a create-or-replace endpoint.
    Re-running this script with the same parameters reconciles the scan to the same UAMI credential
    reference rather than erroring or duplicating.

    This script does NOT create the out-of-band grants the UAMI-authenticated scan depends on:
      - Azure IAM "Reader" role for the UAMI (not the Purview account's SAMI) on the Synapse
        workspace resource (required for BOTH dedicated and serverless scanning)
      - Azure IAM "Storage blob data reader" role for the UAMI on the resource group/subscription
        holding the workspace's associated storage account (SERVERLESS ONLY)
      - Per-serverless-database enumeration login and per-database read grants, for the UAMI's exact
        managed-identity name (see README.md Section 5 for the full T-SQL, ported from the base
        scenario's SAMI grants with the UAMI's name substituted)
    All are one-time, ARM/SQL-side prerequisites documented in README.md Sections 3 and 5 - grant them
    before running this script, or the scan will reconcile successfully but fail on its first run
    under the new identity. This script does NOT re-verify the workspace firewall setting the base
    scenario already established - orthogonal to which Purview identity authenticates.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Nothing in this script runs a scan unless you explicitly pass -RunNow.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.
    Must hold the Data Source Administrator role on the scan's collection (docs/rbac-model.md
    Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER DataSourceName
    Name of the data source object the scan belongs to (matches the base scenario's -DataSourceName).

.PARAMETER ScanName
    Name of the scan object to reconcile. Defaults to "<DataSourceName>-scan" to match the base
    scenario's default.

.PARAMETER CredentialReferenceName
    Name of a Purview credential object, kind ManagedIdentity, that already exists in this
    collection's domain - built via scenarios/data-map/scan-credential-remaining-kinds/deploy/
    New-PurviewScanCredentialExtended.ps1 -CredentialType ManagedIdentity.

.PARAMETER SkipCredentialPrecheck
    Skip the best-effort GET against the referenced credential object before reconciling the scan.
    Does NOT suppress the hard stop below for a credential that is found but is the wrong kind.

.PARAMETER Force
    Reconcile the scan onto -CredentialReferenceName even if the precheck finds that credential
    object exists but is NOT kind ManagedIdentity. Has no effect on the 404/missing case.

.PARAMETER RunNow
    If supplied, starts an immediate scan run after the scan is reconciled.

.PARAMETER ScanLevel
    Scan level for -RunNow. Defaults to 'Full'.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', matching the base scenario.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT) request.

.EXAMPLE
    ./New-AzureSynapseManagedIdentityCredentialScan.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DataSourceName 'ws-contoso-prod' -CredentialReferenceName 'synapse-contoso-uami' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-AzureSynapseManagedIdentityCredentialScan.ps1 -PurviewAccountName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -DataSourceName 'ws-contoso-prod' -CredentialReferenceName 'synapse-contoso-uami' -RunNow

    Reconciles the scan onto the named UAMI credential and immediately runs a full scan.

.NOTES
    Sources (Microsoft Learn, direct-fetched for this build):
    - Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview - "Set up a scan
      by using an API" (Microsoft's own worked JSON body for a scan against this exact data source
      kind explicitly shows `"credentialType":"SqlAuth | ServicePrincipal | ManagedIdentity (if UAMI
      authentication)"` and `"kind":"AzureSynapseWorkspaceCredential | AzureSynapseWorkspaceMsi"` -
      the strongest direct confirmation of ManagedIdentity support for this specific scan kind of any
      of the three sibling scenarios):
      https://learn.microsoft.com/purview/register-scan-synapse-workspace#set-up-a-scan-by-using-an-api
    - Scans - Create Or Replace (API version 2023-09-01; confirmed
      AzureSynapseWorkspaceCredentialScanProperties field names: collection, scanRulesetName,
      scanRulesetType, credential:CredentialReference, resourceTypes - no databaseName/serverEndpoint,
      unlike the Database/Managed Instance siblings' scan properties):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
    - scan-azure-sql-and-classify-managed-identity-credential/ and scan-azure-sql-managed-instance-
      and-classify-managed-identity-credential/ - the two sibling scenarios this script mirrors the
      reconciliation pattern of.
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
    [ValidateNotNullOrEmpty()]
    [string]$DataSourceName,

    [Parameter()]
    [string]$ScanName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CredentialReferenceName,

    [Parameter()]
    [switch]$SkipCredentialPrecheck,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$RunNow,

    [Parameter()]
    [ValidateSet('Full', 'Incremental')]
    [string]$ScanLevel = 'Full',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }
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

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: GET the existing scan - this script reconciles, it never creates from scratch ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$existingScan = Get-PurviewObjectOrNull -Uri $scanUri -Token $token
if ($null -eq $existingScan) {
    throw "Scan '$ScanName' on data source '$DataSourceName' was not found. This scenario reconciles an EXISTING scan onto a UAMI credential - run scenarios/data-map/scan-azure-synapse-and-classify/deploy/New-AzureSynapseDataMapScan.ps1 first."
}
$compatibleScanKinds = @('AzureSynapseWorkspaceMsi', 'AzureSynapseWorkspaceCredential')
if ($existingScan.kind -notin $compatibleScanKinds) {
    throw "Scan '$ScanName' has kind '$($existingScan.kind)', not one of $($compatibleScanKinds -join '/'). This script only reconciles an Azure Synapse workspace scan - refusing to touch a mismatched scan (double-check -DataSourceName/-ScanName)."
}
if ($existingScan.kind -eq 'AzureSynapseWorkspaceCredential') {
    $priorType = $existingScan.properties.credential.credentialType
    $priorRef = $existingScan.properties.credential.referenceName
    Write-Host "Scan already authenticates via a credential (kind '$priorType', reference '$priorRef') - switching it to ManagedIdentity credential '$CredentialReferenceName'." -ForegroundColor Cyan
}
else {
    Write-Host "Scan currently authenticates via SAMI (kind AzureSynapseWorkspaceMsi) - switching it to ManagedIdentity credential '$CredentialReferenceName'." -ForegroundColor Cyan
}

# --- Step 2 (best-effort): confirm the referenced credential exists and is the right kind ---
if (-not $SkipCredentialPrecheck) {
    $credentialUri = "$endpoint/scan/credentials/$CredentialReferenceName`?api-version=$ApiVersion"
    $credential = Get-PurviewObjectOrNull -Uri $credentialUri -Token $token
    if ($null -eq $credential) {
        Write-Warning "Credential '$CredentialReferenceName' was not found (HTTP 404) - absent OR not visible to this identity (confirm -AppId's collection role, or pass -SkipCredentialPrecheck if the credential lives in a collection this identity cannot read). Proceeding, but the scan will fail at run time if the credential genuinely does not exist."
    }
    elseif ($credential.kind -ne 'ManagedIdentity') {
        # Deterministic, not ambiguous like the 404 case above: the object exists and its kind is
        # known, so this WILL fail at scan-run time. Hard stop unless the caller explicitly overrides.
        if (-not $Force) {
            throw "Credential '$CredentialReferenceName' exists but is kind '$($credential.kind)', not 'ManagedIdentity'. Reconciling this scan onto it would deterministically fail at run time. Fix -CredentialReferenceName, or pass -Force to proceed anyway."
        }
        Write-Warning "Credential '$CredentialReferenceName' exists but is kind '$($credential.kind)', not 'ManagedIdentity'. Proceeding anyway because -Force was supplied - Purview will reject the mismatch at run time."
    }
    else {
        Write-Host "Precheck: credential '$CredentialReferenceName' exists and is kind ManagedIdentity." -ForegroundColor Green
    }
}

# --- Step 3: reconcile the scan - copy every existing property forward, override kind + credential ---
# Note: unlike the Database/Managed Instance siblings, there is no databaseName/serverEndpoint to
# preserve here - both live on the data source object, which this script never touches. resourceTypes
# is deliberately not set, matching the base scenario's own choice (README.md Section 11).
$scanBody = @{
    kind       = 'AzureSynapseWorkspaceCredential'
    properties = @{
        collection      = $existingScan.properties.collection
        scanRulesetName = $existingScan.properties.scanRulesetName
        scanRulesetType = $existingScan.properties.scanRulesetType
        credential      = @{
            credentialType = 'ManagedIdentity'
            referenceName  = $CredentialReferenceName
        }
    }
}
Invoke-PurviewPut -Uri $scanUri -Body $scanBody -Token $token `
    -Description "Scan '$ScanName' - reconcile onto ManagedIdentity credential '$CredentialReferenceName'" | Out-Null
Write-Host "Scan '$ScanName' now authenticates via ManagedIdentity credential '$CredentialReferenceName' (kind: AzureSynapseWorkspaceCredential)." -ForegroundColor Green

# --- Step 4 (optional): run the scan immediately to prove the new auth path works ---
if ($RunNow) {
    $runId = [guid]::NewGuid().ToString()
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=$ScanLevel&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate $ScanLevel run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "Scan run started (runId: $runId). Poll validate/Test-AzureSynapseManagedIdentityCredentialScan.ps1 for status." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate $ScanLevel run."
    }
}

Write-Host "`nDone. Remember: this scan will fail at run time unless the workspace Reader grant, (serverless-only) Storage Blob Data Reader grant, and per-database enumeration/read grants for the UAMI (not the Purview account's SAMI) documented in README.md Sections 3 and 5 are already in place." -ForegroundColor Cyan
