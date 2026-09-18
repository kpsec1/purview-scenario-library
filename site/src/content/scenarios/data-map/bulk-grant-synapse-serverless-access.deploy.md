---
part: "deploy"
parent: "data-map/bulk-grant-synapse-serverless-access"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Grant-SynapseServerlessDatabaseAccess.ps1`

```powershell
#Requires -Version 7.0
#Requires -Modules SqlServer
<#
.SYNOPSIS
    Bulk-applies the per-serverless-database CREATE LOGIN / CREATE USER / db_datareader grants an
    Azure Synapse Analytics workspace's built-in serverless SQL pool needs, across every serverless
    database in the workspace (or an explicit subset), instead of running the T-SQL by hand once per
    database in Synapse Studio.

.DESCRIPTION
    Closes the CISO-flagged prerequisite-cost-scaling gap in
    scenarios/data-map/scan-azure-synapse-and-classify/ (README.md Section 3): that scenario's own
    per-database enumeration login and db_datareader grants are a FIXED, one-time cost per database,
    but a workspace with dozens of serverless databases turns into dozens of manual Synapse Studio
    SQL-script operations before the parent scenario's scan can classify any of them. This script
    automates that loop.

    Connects directly to the workspace's built-in serverless SQL pool endpoint (T-SQL, NOT the
    Purview Data Map REST API the parent scenario's own deploy script uses - see design.md Section 3
    for why this is a materially different automation surface, not an extension of that script) and:

      1. Enumerates the workspace's serverless databases via `SELECT name FROM sys.databases` against
         the built-in pool's `master` database (Microsoft's own documented query for listing databases
         visible to a serverless SQL pool - see .NOTES), unless -Database is supplied to target an
         explicit list instead.
      2. Creates the Microsoft Entra-backed login named by -PrincipalName with
         `CREATE LOGIN [...] FROM EXTERNAL PROVIDER;` EXACTLY ONCE, against `master` - a SERVER-scoped
         statement, not a per-database one. This corrects a framing question the parent scenario's own
         README/design left unresolved (it documented Microsoft's per-database portal walkthrough
         literally, which repeats the same step in each database's own Synapse Studio "New SQL script"
         context) - see .NOTES and design.md Section 4 for the grounding that settled it.
      3. For every enumerated (or explicitly listed) database: creates the corresponding contained
         database user (`CREATE USER [...] FOR LOGIN [...];`) and adds it to the `db_datareader` role
         (`ALTER ROLE db_datareader ADD MEMBER [...];`) - skipping either statement if that database
         already has the user/membership in place, so a re-run against a workspace with some databases
         already granted only touches the ones still missing it.

    Idempotent by construction: every login/user/role-membership check queries the live catalog
    (`sys.server_principals`, `sys.database_principals`, `sys.database_role_members`) before issuing
    the matching CREATE/ALTER statement, and skips it if already satisfied. Continues past a single
    database's failure (e.g. a read-only database replicated from a Spark/Lake database - Microsoft
    documents these as not accepting the same grants, see .NOTES) rather than aborting the whole batch,
    and reports a per-database result table plus a non-zero exit code if any database hard-failed.

    This script does NOT:
      - Create or configure the Purview Data Map scan itself - see
        scenarios/data-map/scan-azure-synapse-and-classify/deploy/New-AzureSynapseDataMapScan.ps1.
      - Grant the *dedicated* SQL pool's equivalent access - dedicated pools have a materially
        different (non-login-based) CREATE USER ... FROM EXTERNAL PROVIDER + sp_addrolemember pattern,
        and a workspace typically has only one dedicated pool (no bulk-scaling problem to solve) -
        see design.md Section 6 (non-goals).
      - Grant the Synapse Administrator / SQL Active Directory Admin role this script's own OPERATOR
        identity needs in order to run - that is a prerequisite, documented in README.md Section 3, not
        a deliverable of this script.
      - Auto-detect which databases are read-only replicas of a Spark/Lake database - no documented
        catalog signal for this was found; use -ExcludeDatabase to skip known ones. See README.md
        Section 11.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf.

.PARAMETER ServerlessSqlEndpoint
    The workspace's built-in serverless SQL pool endpoint, e.g.
    "ws-contoso-prod-ondemand.sql.azuresynapse.net" (same value used by the parent scenario's
    -ServerlessSqlEndpoint parameter).

.PARAMETER PrincipalName
    The Microsoft Entra-backed principal to grant db_datareader on every target database - typically
    the Microsoft Purview account's own display name (matching the parent scenario's SAMI-authenticated
    scan default), but any Entra user/group/service-principal display name or UPN Azure Synapse accepts
    in `CREATE LOGIN [...] FROM EXTERNAL PROVIDER` works. Validated against a conservative character
    allow-list and bracket-escaped before use in generated T-SQL (see .NOTES) - never pass untrusted
    input to this parameter.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to connect to the serverless SQL pool and
    run the grants. This is an OPERATOR identity with sufficient Synapse SQL privilege to create logins
    and users (Microsoft documents this as the workspace's Synapse Administrator / SQL Active Directory
    Admin role - see README.md Section 3) - it is intentionally NOT the same identity as -PrincipalName
    in the common case (-PrincipalName is typically the lower-privileged Purview MSI being granted
    read-only access, not the admin identity granting it).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER Database
    Optional explicit list of serverless database names to target, skipping live enumeration entirely.
    Use this to scope a run to specific databases, or when `sys.databases` enumeration itself is not
    desired for a given run.

.PARAMETER ExcludeDatabase
    Optional list of database names to skip even if returned by enumeration - e.g. databases you know
    are read-only replicas of a Spark/Lake database (Microsoft documents these as not accepting the
    same login-based grants; see .NOTES), or databases deliberately not in scope for scanning. Ignored
    if -Database is supplied.

.PARAMETER SkipLoginCreation
    If supplied, skips step 2 (the one-time CREATE LOGIN at the master-database level) entirely and
    goes straight to the per-database CREATE USER/ALTER ROLE loop - use this if the login was already
    confirmed to exist (e.g. created via the portal walkthrough, or by a prior run of this script).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every CREATE LOGIN/CREATE USER/ALTER ROLE
    statement that would be run, and every read-only catalog query that would be executed to decide
    that, without changing anything. Invoke-Sqlcmd has no native ShouldProcess integration, so this
    script wraps each mutating statement in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./Grant-SynapseServerlessDatabaseAccess.ps1 `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -PrincipalName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -WhatIf

    Dry run: enumerates every serverless database in the workspace and reports exactly which
    CREATE LOGIN/CREATE USER/ALTER ROLE statements would run, without changing anything.

.EXAMPLE
    ./Grant-SynapseServerlessDatabaseAccess.ps1 `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -PrincipalName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -ExcludeDatabase 'spark_replica_db'

    Grants access across every serverless database except the named exclusion, creating the login
    once (if it does not already exist) and reconciling each database's user/role membership.

.EXAMPLE
    ./Grant-SynapseServerlessDatabaseAccess.ps1 `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -PrincipalName 'contoso-purview' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -Database 'sales_db', 'hr_db' -SkipLoginCreation

    Targets exactly two named databases and skips the login-creation step (already confirmed to exist).

.NOTES
    Grounding (Microsoft Learn, fetched directly during this build):

    - Invoke-Sqlcmd -AccessToken client-credentials example (confirms the exact
      Invoke-RestMethod-against-login.microsoftonline.com-then-Invoke-Sqlcmd-AccessToken pattern this
      script uses, resource https://database.windows.net/ for a service principal):
      https://learn.microsoft.com/powershell/module/sqlserver/invoke-sqlcmd
    - Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (confirms the
      per-database CREATE USER [...] FOR LOGIN [...]; ALTER ROLE db_datareader ADD MEMBER [...]; T-SQL
      for serverless databases, and the sys.database_principals/sys.database_role_members verification
      query this script's checks are modeled on):
      https://learn.microsoft.com/purview/register-scan-synapse-workspace
    - Access lake databases using serverless SQL pool (confirms `SELECT * FROM sys.databases;` as
      Microsoft's own documented way to enumerate databases visible to a serverless SQL pool, and the
      "Create workspace-level data reader" example that runs `CREATE LOGIN [...] FROM EXTERNAL
      PROVIDER` exactly once, with no per-database repetition):
      https://learn.microsoft.com/azure/synapse-analytics/metadata/database
    - Troubleshoot serverless SQL pool in Azure Synapse Analytics (confirms `CREATE LOGIN` runs
      against `use master` and is explicitly documented as a server-level, not per-database,
      statement; also the sys.server_principals login-existence check this script's login check is
      modeled on): https://learn.microsoft.com/azure/synapse-analytics/sql/resources-self-help-sql-on-demand
    - Azure Synapse workspace access control overview (confirms "Synapse Administrators are granted
      db_owner (DBO) permissions on the serverless SQL pool, Built-in. To grant other users access to
      the serverless SQL pool, Synapse administrators need to run SQL scripts on the serverless pool" -
      the basis for this script's -AppId prerequisite documented in README.md Section 3):
      https://learn.microsoft.com/azure/synapse-analytics/security/synapse-workspace-access-control-overview
    - SQL Authentication in Azure Synapse Analytics (confirms `CREATE LOGIN [name@domain] FROM
      EXTERNAL PROVIDER` / `CREATE USER [name] FROM EXTERNAL PROVIDER` bracket-quoted syntax forms):
      https://learn.microsoft.com/azure/synapse-analytics/sql/sql-authentication

    CORRECTION to scenarios/data-map/scan-azure-synapse-and-classify: that scenario's README.md
    Section 5 step 3c and design.md Section 4 describe the serverless CREATE LOGIN step as something
    to "repeat for every serverless database to be scanned," following Microsoft's own portal
    walkthrough literally (each database's own Synapse Studio "New SQL script" context). This build's
    grounding pass found two independent, directly-fetched Microsoft Learn sources stating plainly
    that CREATE LOGIN and other login-level grants "should be executed on master database, as these
    are all server-level permissions" - i.e. once per workspace, not once per database. This script
    implements the corrected (once-per-workspace) behavior. The parent scenario's own README/design
    wording is not edited by this fragment (see AGENTS.md Section 6 - one fragment per turn); a
    follow-up to reconcile its wording is recorded in PROGRESS.md.

    Untrusted input: -PrincipalName is validated against a conservative allow-list pattern and its `]`
    characters are doubled before being spliced into a bracket-quoted T-SQL identifier (the standard
    T-SQL bracket-escaping rule); it is never passed to Invoke-Sqlcmd's -Query as unescaped free text.
    Do not relax the validation pattern to accept arbitrary strings.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerlessSqlEndpoint,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,127}$')]
    [string]$PrincipalName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter()]
    [string[]]$Database,

    [Parameter()]
    [string[]]$ExcludeDatabase = @(),

    [Parameter()]
    [switch]$SkipLoginCreation
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer -ErrorAction Stop

function ConvertTo-SqlBracketIdentifier {
    <# Escapes a name for use inside T-SQL [ ... ] bracket-quoted identifier syntax. #>
    param([Parameter(Mandatory)][string]$Name)
    return $Name.Replace(']', ']]')
}

function ConvertTo-SqlStringLiteral {
    <# Escapes a value for use inside a T-SQL N'...' string literal. #>
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Get-DatabaseAccessToken {
    <#
        Client-credentials OAuth2 flow against the Azure SQL/Synapse data-plane resource
        (https://database.windows.net/) - the exact pattern in Invoke-Sqlcmd's own "Example 12:
        Connect to Azure SQL Database (or Managed Instance) using a Service Principal" reference.
        Deliberately a DIFFERENT resource/audience than the Purview Data Map REST API's own
        https://purview.azure.net token (see design.md Section 3) - this script never talks to the
        Purview control plane at all.
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
            resource      = 'https://database.windows.net/'
        }
        $response = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body
        return $response.access_token
    }
    finally {
        $plainSecret = $null
    }
}

function Invoke-SynapseServerlessQuery {
    param(
        [Parameter(Mandatory)][string]$DatabaseName,
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string]$AccessToken
    )
    return Invoke-Sqlcmd -ServerInstance $ServerlessSqlEndpoint -Database $DatabaseName `
        -AccessToken $AccessToken -Query $Query -ErrorAction Stop
}

function Invoke-SynapseServerlessStatement {
    <# Runs a mutating T-SQL statement gated by $PSCmdlet.ShouldProcess. #>
    param(
        [Parameter(Mandatory)][string]$DatabaseName,
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$Description
    )
    if ($PSCmdlet.ShouldProcess($Description, "Run T-SQL against database '$DatabaseName'")) {
        Invoke-Sqlcmd -ServerInstance $ServerlessSqlEndpoint -Database $DatabaseName `
            -AccessToken $AccessToken -Query $Query -ErrorAction Stop | Out-Null
        return $true
    }
    Write-Verbose "WhatIf: would run against '$DatabaseName': $Query"
    return $false
}

$escapedIdentifier = ConvertTo-SqlBracketIdentifier -Name $PrincipalName
$escapedLiteral = ConvertTo-SqlStringLiteral -Value $PrincipalName

$token = Get-DatabaseAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

# --- Step 1: enumerate target databases ---
if ($Database) {
    $targetDatabases = $Database
    Write-Host "Using explicit database list ($($targetDatabases.Count) database(s))." -ForegroundColor Cyan
}
else {
    Write-Host "Enumerating serverless databases via sys.databases on '$ServerlessSqlEndpoint'..." -ForegroundColor Cyan
    $rows = Invoke-SynapseServerlessQuery -DatabaseName 'master' -AccessToken $token `
        -Query "SELECT name FROM sys.databases WHERE name NOT IN ('master') ORDER BY name;"
    $targetDatabases = @($rows | ForEach-Object { $_.name }) | Where-Object { $ExcludeDatabase -notcontains $_ }
    Write-Host "Found $($targetDatabases.Count) database(s) after applying -ExcludeDatabase." -ForegroundColor Cyan
}

if (-not $targetDatabases -or $targetDatabases.Count -eq 0) {
    Write-Warning "No target databases to process. Nothing to do."
    exit 0
}

# --- Step 2: create the login exactly once, at the master-database (server) level ---
if (-not $SkipLoginCreation) {
    $loginCheck = Invoke-SynapseServerlessQuery -DatabaseName 'master' -AccessToken $token `
        -Query "SELECT COUNT(*) AS LoginExists FROM sys.server_principals WHERE name = N'$escapedLiteral' AND type IN ('E','X');"
    if ($loginCheck.LoginExists -gt 0) {
        Write-Host "Login '$PrincipalName' already exists at the server (master) level - skipping CREATE LOGIN." -ForegroundColor Green
    }
    else {
        $ran = Invoke-SynapseServerlessStatement -DatabaseName 'master' `
            -Query "CREATE LOGIN [$escapedIdentifier] FROM EXTERNAL PROVIDER;" -AccessToken $token `
            -Description "Server-level login '$PrincipalName' (run once, not per database)"
        if ($ran) { Write-Host "Login '$PrincipalName' created at the server (master) level." -ForegroundColor Green }
    }
}
else {
    Write-Host "Skipping login creation (-SkipLoginCreation)." -ForegroundColor Yellow
}

# --- Step 3: reconcile CREATE USER + db_datareader membership per database ---
$results = New-Object System.Collections.Generic.List[pscustomobject]
foreach ($db in $targetDatabases) {
    $status = 'Unknown'
    $detail = ''
    try {
        $userCheck = Invoke-SynapseServerlessQuery -DatabaseName $db -AccessToken $token `
            -Query "SELECT COUNT(*) AS UserExists FROM sys.database_principals WHERE name = N'$escapedLiteral';"
        $userExists = $userCheck.UserExists -gt 0

        if (-not $userExists) {
            $ran = Invoke-SynapseServerlessStatement -DatabaseName $db `
                -Query "CREATE USER [$escapedIdentifier] FOR LOGIN [$escapedIdentifier];" -AccessToken $token `
                -Description "Database user '$PrincipalName' in '$db'"
            $status = if ($ran) { 'UserCreated' } else { 'WouldCreateUser (WhatIf)' }
        }

        $roleCheck = Invoke-SynapseServerlessQuery -DatabaseName $db -AccessToken $token -Query @"
SELECT COUNT(*) AS IsMember
FROM sys.database_principals p
JOIN sys.database_role_members rm ON p.principal_id = rm.member_principal_id
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
WHERE p.name = N'$escapedLiteral' AND r.name = 'db_datareader';
"@
        if ($roleCheck.IsMember -gt 0) {
            $status = if ($status -eq 'Unknown') { 'AlreadyGranted' } else { $status }
            $detail = 'db_datareader membership already present'
        }
        else {
            $ran = Invoke-SynapseServerlessStatement -DatabaseName $db `
                -Query "ALTER ROLE db_datareader ADD MEMBER [$escapedIdentifier];" -AccessToken $token `
                -Description "db_datareader membership for '$PrincipalName' in '$db'"
            $status = if ($ran) {
                if ($status -eq 'UserCreated') { 'UserCreated+RoleGranted' } else { 'RoleGranted' }
            }
            else {
                'WouldGrantRole (WhatIf)'
            }
        }
    }
    catch {
        $status = 'Error'
        $detail = $_.Exception.Message
    }
    $results.Add([pscustomobject]@{ Database = $db; Status = $status; Detail = $detail })
}

Write-Host "`nResults:" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host

$errorCount = @($results | Where-Object { $_.Status -eq 'Error' }).Count
if ($errorCount -gt 0) {
    Write-Warning "$errorCount of $($results.Count) database(s) failed - see Detail column above. Common cause: a database that is a read-only replica of a Spark/Lake database (see README.md Section 11); add it to -ExcludeDatabase once confirmed."
    exit 1
}

Write-Host "`nDone. $($results.Count) database(s) processed, 0 error(s)." -ForegroundColor Green
```