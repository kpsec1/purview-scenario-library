---
part: "validate"
parent: "data-map/bulk-grant-synapse-serverless-access"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-SynapseServerlessDatabaseAccess.ps1`

```powershell
#Requires -Version 7.0
#Requires -Modules SqlServer
<#
.SYNOPSIS
    Read-only verification that the login/user/db_datareader grants
    Grant-SynapseServerlessDatabaseAccess.ps1 applies are actually in place, across every target
    serverless database.

.DESCRIPTION
    Never modifies any object - runs only the SELECT-based catalog checks Microsoft documents for
    confirming an external-provider login/user/role assignment (see .NOTES). Checks:
      1. The login exists at the server (master-database) level (`sys.server_principals`).
      2. For each target database: the corresponding contained database user exists
         (`sys.database_principals`) AND is a member of `db_datareader`
         (`sys.database_role_members`), using the exact join Microsoft's own
         register-scan-synapse-workspace verification query demonstrates.
    Exits with a non-zero code if any hard check fails, so this script is safe to wire into a
    CI-style pre-flight or a post-deploy smoke test. Safe to re-run any number of times.

.PARAMETER ServerlessSqlEndpoint
    The workspace's built-in serverless SQL pool endpoint - same value passed to the deploy script.

.PARAMETER PrincipalName
    The Microsoft Entra-backed principal to check - same value passed to the deploy script.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal used to connect and run the read-only checks.
    Deliberately can be a LOWER-privileged identity than the deploy script's operator identity - this
    script only needs `CONNECT` and `VIEW DEFINITION`-level catalog visibility, not the Synapse
    Administrator privilege the deploy script's grants require - see README.md Section 3.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER Database
    Optional explicit list of database names to check. If omitted, enumerates every serverless
    database via `sys.databases` (excluding `master`), the same default the deploy script uses.

.PARAMETER ExcludeDatabase
    Optional list of database names to skip during enumeration. Ignored if -Database is supplied.

.EXAMPLE
    ./Test-SynapseServerlessDatabaseAccess.ps1 `
        -ServerlessSqlEndpoint 'ws-contoso-prod-ondemand.sql.azuresynapse.net' `
        -PrincipalName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

.NOTES
    Verification query modeled directly on Microsoft's own worked example in
    "Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview"
    (https://learn.microsoft.com/purview/register-scan-synapse-workspace), narrowed with a
    `WHERE p.name = ...` filter rather than returning every external principal in the database.
    Login-existence check modeled on the `sys.server_principals` query in "Troubleshoot serverless
    SQL pool in Azure Synapse Analytics"
    (https://learn.microsoft.com/azure/synapse-analytics/sql/resources-self-help-sql-on-demand).

    Untrusted input: -PrincipalName is validated and bracket/literal-escaped identically to the
    deploy script - see that script's own .NOTES.
#>
[CmdletBinding()]
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
    [string[]]$ExcludeDatabase = @()
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer -ErrorAction Stop
$script:failures = 0

function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    elseif ($Warn) {
        Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $script:failures++
    }
}

function ConvertTo-SqlStringLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Get-DatabaseAccessToken {
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

$escapedLiteral = ConvertTo-SqlStringLiteral -Value $PrincipalName
$token = Get-DatabaseAccessToken -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret

Write-Host "Validating access for '$PrincipalName' on '$ServerlessSqlEndpoint'..." -ForegroundColor Cyan

# --- Check 1: server-level login exists ---
$loginCheck = Invoke-Sqlcmd -ServerInstance $ServerlessSqlEndpoint -Database 'master' -AccessToken $token `
    -Query "SELECT COUNT(*) AS LoginExists FROM sys.server_principals WHERE name = N'$escapedLiteral' AND type IN ('E','X');"
Test-Check -Description "Server-level login '$PrincipalName' exists (sys.server_principals)" `
    -Condition ($loginCheck.LoginExists -gt 0)
if ($loginCheck.LoginExists -eq 0) {
    Write-Host "`nCannot continue - login not found. Run deploy/Grant-SynapseServerlessDatabaseAccess.ps1 first. $script:failures check(s) failed." -ForegroundColor Red
    exit 1
}

# --- Determine target databases ---
if ($Database) {
    $targetDatabases = $Database
}
else {
    $rows = Invoke-Sqlcmd -ServerInstance $ServerlessSqlEndpoint -Database 'master' -AccessToken $token `
        -Query "SELECT name FROM sys.databases WHERE name NOT IN ('master') ORDER BY name;"
    $targetDatabases = @($rows | ForEach-Object { $_.name }) | Where-Object { $ExcludeDatabase -notcontains $_ }
}

if (-not $targetDatabases -or $targetDatabases.Count -eq 0) {
    Write-Warning "No target databases found to validate."
    exit 0
}

# --- Check 2 (per database): user exists AND is a db_datareader member ---
foreach ($db in $targetDatabases) {
    try {
        $roleCheck = Invoke-Sqlcmd -ServerInstance $ServerlessSqlEndpoint -Database $db -AccessToken $token -Query @"
SELECT p.name AS UserName, r.name AS RoleName
FROM sys.database_principals p
LEFT JOIN sys.database_role_members rm ON p.principal_id = rm.member_principal_id
LEFT JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
WHERE p.name = N'$escapedLiteral';
"@
        $isMember = @($roleCheck | Where-Object { $_.RoleName -eq 'db_datareader' }).Count -gt 0
        Test-Check -Description "'$PrincipalName' has db_datareader in '$db'" -Condition $isMember
    }
    catch {
        Test-Check -Description "'$db' reachable and queryable ($($_.Exception.Message))" -Condition $false -Warn
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })

if ($script:failures -gt 0) { exit 1 }
```