---
part: "deploy"
parent: "data-map/scan-on-premises-sql-server-and-classify"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-OnPremisesSqlServerDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions a self-hosted integration runtime resource (and its auth key), registers an
    on-premises SQL Server instance as a Microsoft Purview Data Map source, and configures a
    credential-authenticated scan against it, optionally with a recurring trigger and/or an
    immediate run.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API (automation surface 4 per
    docs/automation-surface.md) to:
      1. Create or replace a SelfHosted integration runtime resource (-IntegrationRuntimeName).
      2. Regenerate/retrieve its primary auth key - this is the key an operator pastes into the
         self-hosted integration runtime (SHIR) installer's "Register Integration Runtime
         (Self-hosted)" screen. This script cannot install the SHIR software or paste the key for
         you - that is a manual, physical step on a Windows host with network access to the target
         SQL Server (see README.md Section 5 / design.md Section 8).
      3. Create or replace the SqlServerDatabase data source object.
      4. Create or replace a SqlServerDatabaseCredential scan object, referencing the integration
         runtime (connectedVia) and a pre-existing Purview credential object (-CredentialReferenceName)
         - there is no managed-identity authentication path for this source type at all.
      5. Optionally create or replace a recurring trigger (-RecurrenceFrequency).
      6. Optionally start an immediate scan run (-RunNow).

    Sibling of scenarios/data-map/scan-azure-sql-and-classify/,
    scan-azure-sql-managed-instance-and-classify/, and scan-azure-synapse-and-classify/ - same
    two-object model and the same create-or-replace idempotency contract, but on-premises SQL Server
    is a genuinely different Purview data source `kind` with its own registration/authentication
    story (see design.md):
      - No Azure resource backs an on-premises instance - resourceGroup/resourceName/subscriptionId/
        location are all omitted, matching Microsoft's own worked PowerShell example.
      - A self-hosted integration runtime is MANDATORY, not optional - Microsoft's own documentation
        states on-premises source types are "currently supported only via self-hosted IR-based scans."
      - There is no managed-identity scan kind for this source type. Authentication is always a
        stored credential (SQL Authentication or Windows Authentication), referenced by name.

    Idempotent by construction: every mutating call in this script is a REST PUT against a
    create-or-replace endpoint, or (for the auth key) a REST POST documented as safe to call
    repeatedly (it simply issues a new key value each time - see -SkipAuthKeyRegeneration if you
    want to reuse an already-registered SHIR without rotating its key). All REST operations were
    directly confirmed against Microsoft's own canonical REST reference during this build - see
    .NOTES.

    This script does NOT create the following out-of-band prerequisites:
      - The SHIR software installation and node registration on a Windows host (uses the auth key
        this script prints - a manual, physical step)
      - The SQL/Windows login and its db_datareader grant on the target SQL Server instance
      - The Key Vault secret holding that login's password
      - The Key Vault-to-Purview connection and the Purview credential object itself
        (-CredentialReferenceName must already exist). CORRECTED 2026-09-16: this script originally
        noted that no documented REST endpoint for credential-object creation existed. It does -
        PUT /scan/credentials/{credentialName} and PUT /scan/azureKeyVaults/{azureKeyVaultName},
        both documented operation groups at api-version 2023-09-01. Script them with
        scenarios/data-map/scan-credential-key-vault-backed/, then pass the resulting name here.
    All are documented in README.md Sections 3 and 5 - complete them before running this script
    with -RunNow, or the scan will register successfully but fail on its first run.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Nothing in this script runs a scan or creates a trigger unless you explicitly
    pass -RunNow or -RecurrenceFrequency.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account (used to build https://<name>.purview.azure.com).

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.
    Must hold the Data Source Administrator role on the target collection (docs/rbac-model.md Section 5).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER IntegrationRuntimeName
    Name for the self-hosted integration runtime resource this script creates (or reconciles).
    3-63 characters, letters/digits/hyphens only.

.PARAMETER SkipIntegrationRuntimeAuthKey
    If supplied, skips regenerating/printing the integration runtime's auth key - use this once a
    SHIR node is already registered and running, so re-running this script for routine reconciliation
    doesn't force an unnecessary key rotation (which would require re-registering every existing SHIR
    node with the new key).

.PARAMETER ServerEndpoint
    The on-premises SQL Server instance's hostname, IP address, or "<host>\<namedInstance>" string -
    whatever value you'd type into SSMS's "Server name" box. Confirmed format via Microsoft's own
    worked PowerShell example (a bare IP address); this script passes the value through unmodified.

.PARAMETER DatabaseName
    Name of the database on the instance to scan. Omit to scan the entire instance (Microsoft's own
    documentation: "The whole SQL Server instance will be scanned if database name isn't provided") -
    this script requires it explicitly for predictable, scoped scans; pass '*' if you intend a
    whole-instance scan and want that intent to be explicit in your automation.

.PARAMETER CollectionReferenceName
    The Data Map collection's 5-character reference ID (NOT its friendly name) - read it from the
    collection's URL in the Purview portal, or the List Collections REST API. See README.md Section 6.

.PARAMETER CredentialReferenceName
    Name of a Purview credential object that already exists in this collection's domain, holding the
    SQL/Windows login's password (Key Vault-backed). This script does not create it - build it with
    scenarios/data-map/scan-credential-key-vault-backed/deploy/New-PurviewScanCredential.ps1 (its
    -CredentialName becomes this parameter's value), or see README.md Section 5 step 4 for the
    portal equivalent.

.PARAMETER CredentialType
    'SqlAuth' (default) or 'BasicAuth'. Microsoft's portal documents both "SQL Authentication" and
    "Windows Authentication" as supported methods for this source type, but the REST CredentialType
    enum has no value confirmed in this build to correspond specifically to Windows Authentication -
    'BasicAuth' is this script's best-effort mapping (Microsoft's generic credential taxonomy
    describes "Basic authentication" as username/password, the same shape Windows Authentication
    uses), flagged as an explicit VERIFY. 'SqlAuth' is the default because it is the credential type
    Microsoft's own worked PowerShell example for this exact scan kind uses. See README.md Section 11.

.PARAMETER DataSourceName
    Name for the registered data source object. Defaults to a sanitized form of -ServerEndpoint.

.PARAMETER ScanName
    Name for the scan object. Defaults to "<DataSourceName>-scan".

.PARAMETER ScanRulesetName
    Scan rule set to use. Defaults to 'SqlServerDatabase' - this repo's best-effort inference of
    the system default rule set's name for this source type (matching the "system ruleset name ==
    data source kind" pattern every sibling scenario confirmed via its own worked example), but NOT
    independently confirmed via a worked example for this specific source type. VERIFY before
    production use - see README.md Section 11. Pass a known-good custom rule set's name instead if
    you have one.

.PARAMETER ScanRulesetType
    'System' (default) or 'Custom'.

.PARAMETER ScanLevel
    'Full' or 'Incremental'. Used for the recurring trigger's default level and for -RunNow.
    Defaults to 'Full'.

.PARAMETER RecurrenceFrequency
    If supplied, creates a recurring trigger at this frequency: Hour, Day, Week, or Month.
    Omit to leave the scan without a schedule (register-only, or run only via -RunNow).

.PARAMETER RecurrenceInterval
    Interval multiplier for -RecurrenceFrequency (e.g. 1 with Week = every week). Defaults to 1.

.PARAMETER RecurrenceStartTime
    UTC start time for the recurring trigger. Defaults to (Get-Date).ToUniversalTime().

.PARAMETER RunNow
    If supplied, starts an immediate scan run after the data source and scan objects are
    created/updated.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01', directly confirmed current for the
    Integration Runtimes (Create Or Replace, Regenerate Auth Key), Data Sources, and Scans REST
    operations this script calls via a direct fetch of each operation's own canonical Microsoft
    Learn REST reference page during this build - see .NOTES.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating request. Invoke-RestMethod has no native ShouldProcess integration, so this
    script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -IntegrationRuntimeName 'shir-onprem-sql' `
        -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
        -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -IntegrationRuntimeName 'shir-onprem-sql' `
        -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
        -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account'

    Registers the integration runtime resource (printing its auth key once), the data source, and
    the scan. Does not run anything yet.

.EXAMPLE
    ./New-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -IntegrationRuntimeName 'shir-onprem-sql' `
        -SkipIntegrationRuntimeAuthKey -ServerEndpoint 'sql01.contoso.local' -DatabaseName 'CustomerDB' `
        -CollectionReferenceName 'a1b2c' -CredentialReferenceName 'onprem-sql-svc-account' `
        -RecurrenceFrequency Week -RunNow

    Reconciles an already-registered SHIR without rotating its key, then adds a weekly trigger and
    kicks off an immediate full scan.

.NOTES
    Every mutating REST operation this script calls was directly fetched from Microsoft's own
    canonical REST reference during this build:
    - Integration Runtimes - Create Or Replace (confirmed SelfHostedIntegrationRuntime body shape,
      full worked HTTP example):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/integration-runtimes/create-or-replace
    - Integration Runtimes - Regenerate Auth Key (confirmed request/response shape, full worked HTTP
      example - this is the key the SHIR installer needs):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/integration-runtimes/regenerate-auth-key
    - Data Sources - Create Or Replace (confirmed SqlServerDatabaseDataSource/
      SqlServerDatabaseProperties body schema - no Azure resource fields):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/data-sources/create-or-replace
    - Scans - Create Or Replace (confirmed SqlServerDatabaseCredentialScan/
      SqlServerDatabaseCredentialScanProperties/ConnectedVia/CredentialReference body schema):
      https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace
    - New-AzPurviewSqlServerDatabaseDataSourceObject (Az.Purview module - worked example confirms
      resourceGroup/resourceName/subscriptionId/location are left unset for this source type):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasedatasourceobject
    - New-AzPurviewSqlServerDatabaseCredentialScanObject (Az.Purview module - worked example confirms
      every field this script's scan body sets, including CredentialType 'SqlAuth' and
      ConnectedViaReferenceName):
      https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasecredentialscanobject
    - Connect to and manage an on-premises SQL server instance in Microsoft Purview (registration,
      mandatory SHIR requirement, SQL/Windows authentication, credential creation, SQL Server 2005+
      supported / Express LocalDB not supported):
      https://learn.microsoft.com/purview/register-scan-on-premises-sql-server
    - Create and manage a self-hosted integration runtime (manual install/registration steps this
      script's printed auth key feeds into):
      https://learn.microsoft.com/purview/data-map-integration-runtime-self-hosted
    - Disaster recovery and migration best practices for Microsoft Purview data governance (classic)
      - independently corroborates that SHIR auth keys are retrievable via API/portal while the
      physical registration step "must be done manually inside the SHIRs' hosts," and that "there's
      no API to extract credentials":
      https://learn.microsoft.com/purview/data-gov-best-practices-disaster-recovery-migration

    VERIFY before production use (not resolved by guessing, per AGENTS.md Section 4 - see README.md
    Section 11 for the full writeup):
    - The literal system scan rule set name for SqlServerDatabase (-ScanRulesetName default) is
      inferred from the "system ruleset name == data source kind" pattern every sibling scenario
      confirmed for its own source type, not independently confirmed via a worked example for this
      one.
    - Which CredentialType enum value corresponds to "Windows Authentication" in the portal - this
      script's -CredentialType 'BasicAuth' default-alternative is a best-effort mapping, not a
      confirmed one.
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
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [ValidateLength(3, 63)]
    [string]$IntegrationRuntimeName,

    [Parameter()]
    [switch]$SkipIntegrationRuntimeAuthKey,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DatabaseName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9]{1,10}$')]
    [string]$CollectionReferenceName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CredentialReferenceName,

    [Parameter()]
    [ValidateSet('SqlAuth', 'BasicAuth')]
    [string]$CredentialType = 'SqlAuth',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$DataSourceName,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$')]
    [string]$ScanName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ScanRulesetName = 'SqlServerDatabase',

    [Parameter()]
    [ValidateSet('System', 'Custom')]
    [string]$ScanRulesetType = 'System',

    [Parameter()]
    [ValidateSet('Full', 'Incremental')]
    [string]$ScanLevel = 'Full',

    [Parameter()]
    [ValidateSet('Hour', 'Day', 'Week', 'Month')]
    [string]$RecurrenceFrequency,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$RecurrenceInterval = 1,

    [Parameter()]
    [datetime]$RecurrenceStartTime = (Get-Date).ToUniversalTime(),

    [Parameter()]
    [switch]$RunNow,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $DataSourceName) {
    $DataSourceName = ($ServerEndpoint -replace '[^A-Za-z0-9]+', '-').Trim('-')
}
if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }

$endpoint = "https://$PurviewAccountName.purview.azure.com"
$collectionRef = @{ referenceName = $CollectionReferenceName; type = 'CollectionReference' }

function Get-PurviewAccessToken {
    <#
        Client-credentials OAuth2 flow against the Data Map data-plane resource, per
        docs/automation-surface.md Section 3.
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

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: create or reconcile the self-hosted integration runtime resource ---
$irUri = "$endpoint/scan/integrationruntimes/$IntegrationRuntimeName?api-version=$ApiVersion"
$irBody = @{
    kind       = 'SelfHosted'
    properties = @{
        description = "Self-hosted IR for on-premises SQL Server scanning (provisioned by New-OnPremisesSqlServerDataMapScan.ps1)"
    }
}
Invoke-PurviewPut -Uri $irUri -Body $irBody -Token $token `
    -Description "Self-hosted integration runtime '$IntegrationRuntimeName'" | Out-Null
Write-Host "Integration runtime '$IntegrationRuntimeName' created/updated (kind: SelfHosted)." -ForegroundColor Green

# --- Step 2: retrieve (or skip) its auth key ---
if (-not $SkipIntegrationRuntimeAuthKey) {
    $authKeyUri = "$endpoint/scan/integrationruntimes/${IntegrationRuntimeName}:regenerateAuthKey?api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Integration runtime '$IntegrationRuntimeName'", "Regenerate auth key")) {
        $authKeyBody = @{ keyName = 'authKey1' } | ConvertTo-Json
        $authKeys = Invoke-RestMethod -Method Post -Uri $authKeyUri -Body $authKeyBody `
            -ContentType 'application/json' -Headers @{ Authorization = "Bearer $token" }
        Write-Host "`nSECURITY: the value below grants any host that presents it the ability to register as a trusted SHIR node for this Purview account. Do not run this in a pipeline that persists console output to logs, a chat/ticketing integration, or any other durable store - copy it interactively and discard it. Anyone who later reads a leaked copy of this key can stand up a rogue node that receives real scan jobs and can see the results this scenario classifies." -ForegroundColor Yellow
        Write-Host "Paste this into the SHIR installer's 'Register Integration Runtime (Self-hosted)' screen:" -ForegroundColor Yellow
        Write-Host "  $($authKeys.authKey1)" -ForegroundColor Yellow
        Write-Host "This key is shown once by this script and is not stored anywhere. If you lose it, re-run without -SkipIntegrationRuntimeAuthKey to issue a new one (this invalidates the old key for any node still using it) - use -SkipIntegrationRuntimeAuthKey on every subsequent reconciliation run once a node is registered, so routine re-runs of this script don't re-print or rotate it.`n" -ForegroundColor Yellow
    }
    else {
        Write-Verbose "WhatIf: would POST $authKeyUri to regenerate and print the auth key."
    }
}
else {
    Write-Host "Skipped auth key regeneration (-SkipIntegrationRuntimeAuthKey) - assuming a SHIR node is already registered." -ForegroundColor Cyan
}

# --- Step 3: register (or reconcile) the data source ---
$dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
$dataSourceBody = @{
    kind       = 'SqlServerDatabase'
    properties = @{
        serverEndpoint = $ServerEndpoint
        collection     = $collectionRef
    }
}
Invoke-PurviewPut -Uri $dataSourceUri -Body $dataSourceBody -Token $token `
    -Description "Data source '$DataSourceName' ($ServerEndpoint)" | Out-Null
Write-Host "Data source '$DataSourceName' created/updated." -ForegroundColor Green

# --- Step 4: create (or reconcile) the scan, authenticating via the stored credential ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
$scanBody = @{
    kind       = 'SqlServerDatabaseCredential'
    properties = @{
        databaseName    = $DatabaseName
        serverEndpoint  = $ServerEndpoint
        collection      = $collectionRef
        connectedVia    = @{
            integrationRuntimeType = 'SelfHosted'
            referenceName          = $IntegrationRuntimeName
        }
        credential      = @{
            credentialType = $CredentialType
            referenceName  = $CredentialReferenceName
        }
        scanRulesetName = $ScanRulesetName
        scanRulesetType = $ScanRulesetType
    }
}
Invoke-PurviewPut -Uri $scanUri -Body $scanBody -Token $token `
    -Description "Scan '$ScanName' on data source '$DataSourceName'" | Out-Null
Write-Host "Scan '$ScanName' created/updated (kind: SqlServerDatabaseCredential, IR: $IntegrationRuntimeName, credential: $CredentialReferenceName, ruleset: $ScanRulesetName [$ScanRulesetType])." -ForegroundColor Green

# --- Step 5 (optional): create a recurring trigger ---
if ($RecurrenceFrequency) {
    $triggerUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/triggers/default?api-version=$ApiVersion"
    $triggerBody = @{
        properties = @{
            scanLevel  = $ScanLevel
            recurrence = @{
                frequency = $RecurrenceFrequency
                interval  = $RecurrenceInterval
                startTime = $RecurrenceStartTime.ToString('o')
            }
        }
    }
    Invoke-PurviewPut -Uri $triggerUri -Body $triggerBody -Token $token `
        -Description "Recurring trigger for scan '$ScanName' (every $RecurrenceInterval $RecurrenceFrequency)" | Out-Null
    Write-Host "Recurring trigger created/updated: every $RecurrenceInterval $RecurrenceFrequency, level $ScanLevel, starting $($RecurrenceStartTime.ToString('u'))." -ForegroundColor Green
}

# --- Step 6 (optional): run the scan immediately ---
if ($RunNow) {
    $runId = [guid]::NewGuid().ToString()
    # Action-style POST with a colon suffix and runId as a query parameter - the shape
    # scan-azure-sql-managed-instance-and-classify's own build directly confirmed against
    # Microsoft's REST reference (see that scenario's design.md Section 5).
    $runUri = "$endpoint/scan/datasources/$DataSourceName/scans/${ScanName}:run?runId=$runId&scanLevel=$ScanLevel&api-version=$ApiVersion"
    if ($PSCmdlet.ShouldProcess("Scan '$ScanName'", "Start immediate $ScanLevel run (runId $runId)")) {
        Invoke-RestMethod -Method Post -Uri $runUri -Headers @{ Authorization = "Bearer $token" } | Out-Null
        Write-Host "Scan run started (runId: $runId). Poll validate/Test-OnPremisesSqlServerDataMapScan.ps1 for status - a first full scan of a nontrivial instance can take from minutes to hours, and will fail immediately if the SHIR node isn't registered/running yet." -ForegroundColor Cyan
    }
    else {
        Write-Verbose "WhatIf: would POST $runUri to start an immediate $ScanLevel run."
    }
}

Write-Host "`nDone. Remember: the scan will fail at run time unless (1) a SHIR node has been installed and registered with the printed auth key and shows 'Running' in the portal, and (2) the credential object '$CredentialReferenceName' already exists and points at a login with db_datareader on '$DatabaseName' - see README.md Sections 3 and 5." -ForegroundColor Cyan
```

#### `Remove-OnPremisesSqlServerDataMapScan.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan (and its trigger, if any) created by New-OnPremisesSqlServerDataMapScan.ps1,
    and optionally the data source registration and/or the integration runtime resource itself.

.DESCRIPTION
    Calls the Microsoft Purview Data Map / Scanning REST API to delete, in order:
      1. The recurring trigger (if present) - DELETE .../scans/{scanName}/triggers/default
      2. The scan object - DELETE .../datasources/{dataSourceName}/scans/{scanName}
      3. (only with -RemoveDataSource) the data source registration itself -
         DELETE .../datasources/{dataSourceName}
      4. (only with -RemoveIntegrationRuntime) the self-hosted integration runtime resource -
         DELETE .../integrationruntimes/{integrationRuntimeName}

    Deleting a scan or data source does NOT delete assets already ingested into the catalog from
    previous scan runs (Microsoft Learn: register-scan-on-premises-sql-server - "Deleting your scan
    does not delete catalog assets created from previous scans"). This script only removes the
    scanning configuration; it never deletes catalog data.

    Deleting the integration runtime RESOURCE in Purview does not uninstall the SHIR SOFTWARE from
    whatever host it's running on, and does not stop that host's Integration Runtime Windows service
    - it only removes Purview's registration of it. If other scans still reference the same
    integration runtime, do not pass -RemoveIntegrationRuntime.

    Idempotent: deleting an object that doesn't exist (already removed) is treated as success, not
    an error, so this script is safe to re-run.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER PurviewAccountName
    Name of the Microsoft Purview account.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Purview Data Map REST API.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER DataSourceName
    Name of the data source object (matches -DataSourceName used at deploy time, or a sanitized form
    of -ServerEndpoint if it was left to default).

.PARAMETER ScanName
    Name of the scan object. Defaults to "<DataSourceName>-scan" to match the deploy script's default.

.PARAMETER RemoveDataSource
    If supplied, also deletes the data source registration after the scan is removed.

.PARAMETER IntegrationRuntimeName
    Name of the self-hosted integration runtime resource. Required only if -RemoveIntegrationRuntime
    is supplied.

.PARAMETER RemoveIntegrationRuntime
    If supplied, also deletes the integration runtime resource. Do not pass this if any other scan
    (for this or another data source) still references the same integration runtime.

.PARAMETER ApiVersion
    Data Map REST API version to pin. Defaults to '2023-09-01' to match the deploy script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (DELETE) request.

.EXAMPLE
    ./Remove-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql01-contoso-local' -WhatIf

    Dry-run: shows exactly which DELETE calls would be made, changes nothing.

.EXAMPLE
    ./Remove-OnPremisesSqlServerDataMapScan.ps1 -PurviewAccountName 'contoso-purview' -TenantId $TenantId `
        -AppId $AppId -ClientSecret $ClientSecret -DataSourceName 'sql01-contoso-local' `
        -RemoveDataSource -IntegrationRuntimeName 'shir-onprem-sql' -RemoveIntegrationRuntime

    Full teardown: removes the trigger, the scan, the data source registration, and the integration
    runtime resource. Does not touch the SHIR software/service on its host - see README.md/rollback.md.

.NOTES
    All four DELETE calls follow the same path pattern confirmed by direct fetch of the matching
    Create Or Replace REST reference pages (see New-OnPremisesSqlServerDataMapScan.ps1's .NOTES) -
    Microsoft's REST APIs consistently pair a resource's Create Or Replace and Delete operations on
    the same URI.

    Sources (Microsoft Learn, verify before production use):
    - Connect to and manage an on-premises SQL server instance in Microsoft Purview - "Manage your
      scans" (deleting a scan does not delete catalog assets):
      https://learn.microsoft.com/purview/register-scan-on-premises-sql-server
    - Create and manage a self-hosted integration runtime - "Manage a self-hosted integration
      runtime" (deleting the IR resource vs. the software/service on its host):
      https://learn.microsoft.com/purview/data-map-integration-runtime-self-hosted
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
    [ValidateNotNullOrEmpty()]
    [string]$DataSourceName,

    [Parameter()]
    [string]$ScanName,

    [Parameter()]
    [switch]$RemoveDataSource,

    [Parameter()]
    [string]$IntegrationRuntimeName,

    [Parameter()]
    [switch]$RemoveIntegrationRuntime,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2023-09-01'
)

$ErrorActionPreference = 'Stop'

if (-not $ScanName) { $ScanName = "$DataSourceName-scan" }
if ($RemoveIntegrationRuntime -and -not $IntegrationRuntimeName) {
    throw "-IntegrationRuntimeName is required when -RemoveIntegrationRuntime is supplied."
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
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Description
    )
    if (-not $PSCmdlet.ShouldProcess($Description, "DELETE $Uri")) {
        Write-Verbose "WhatIf: would DELETE $Uri"
        return
    }
    try {
        Invoke-RestMethod -Method Delete -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } | Out-Null
        Write-Host "Removed: $Description" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Already absent (no-op): $Description" -ForegroundColor Yellow
        }
        else {
            throw
        }
    }
}

$token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: remove the recurring trigger, if any ---
$triggerUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName/triggers/default?api-version=$ApiVersion"
Invoke-PurviewDelete -Uri $triggerUri -Token $token -Description "Trigger on scan '$ScanName'"

# --- Step 2: remove the scan ---
$scanUri = "$endpoint/scan/datasources/$DataSourceName/scans/$ScanName?api-version=$ApiVersion"
Invoke-PurviewDelete -Uri $scanUri -Token $token -Description "Scan '$ScanName' on data source '$DataSourceName'"

# --- Step 3 (optional): remove the data source registration ---
if ($RemoveDataSource) {
    $dataSourceUri = "$endpoint/scan/datasources/$DataSourceName?api-version=$ApiVersion"
    Invoke-PurviewDelete -Uri $dataSourceUri -Token $token -Description "Data source '$DataSourceName'"
}
else {
    Write-Host "Data source '$DataSourceName' left registered (pass -RemoveDataSource to remove it too)." -ForegroundColor Yellow
}

# --- Step 4 (optional): remove the integration runtime resource ---
if ($RemoveIntegrationRuntime) {
    $irUri = "$endpoint/scan/integrationruntimes/$IntegrationRuntimeName?api-version=$ApiVersion"
    Invoke-PurviewDelete -Uri $irUri -Token $token -Description "Integration runtime '$IntegrationRuntimeName'"
    Write-Host "Note: this removed Purview's registration of the integration runtime only. If a SHIR node is still running on a host with this key, stop/uninstall it separately - see rollback.md." -ForegroundColor Yellow
}
elseif ($IntegrationRuntimeName) {
    Write-Host "Integration runtime '$IntegrationRuntimeName' left registered (pass -RemoveIntegrationRuntime to remove it too)." -ForegroundColor Yellow
}

Write-Host "`nDone. Catalog assets already ingested from prior scan runs are not deleted by this script - see rollback.md." -ForegroundColor Cyan
```