#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Creates (or reuses) the single-purpose Microsoft Entra app registration the HR connector
    needs, instead of leaving it a manual Microsoft Entra admin center task.

.DESCRIPTION
    Resolves a follow-up tracked in PROGRESS.md: Microsoft's own HR-connector guide
    (import-hr-data, "Step 2: Create an app in Microsoft Entra ID") walks through app
    registration as a manual portal task and cites only the generic "Register an application
    with the Microsoft identity platform" quickstart - it does not name a connector-specific
    cmdlet. There isn't one, because none is needed: Step 2's own requirement is a plain app
    registration with an application ID, a client secret, and nothing else (no API permissions,
    no redirect URI, no special manifest) - a generic Microsoft.Graph.Applications sequence
    covers it completely without inventing anything HR-connector-specific.

    Sequence (mirrors what the Microsoft Entra admin center's "New registration" wizard does
    for you automatically - each step is scripted here explicitly because the Graph API does
    NOT chain them the way the portal UI does):
      1. Get-MgApplication -Filter "displayName eq '...'" - idempotency check. If an app with
         this exact display name already exists, reuse it instead of creating a duplicate.
      2. New-MgApplication -DisplayName ... -SignInAudience AzureADMyOrg - creates the
         application object (single-tenant; this app has no reason to accept sign-ins from
         other tenants or personal Microsoft accounts).
      3. New-MgServicePrincipal -AppId ... - creating an Application object via Graph does
         NOT automatically create the corresponding Service Principal (unlike registering
         through the portal, which does both in one step) - this step closes that gap.
      4. Add-MgApplicationPassword -ApplicationId <objectId> -PasswordCredential @{...} -
         issues a client secret with an explicit, bounded expiration. NOTE: -ApplicationId
         here is aliased ObjectId in the Microsoft.Graph.Applications module - it takes the
         application's OBJECT ID (the Id property), not its AppId (client ID). Passing AppId
         here is a common mistake this script guards against by always using $app.Id.

    Deliberately DOES NOT grant this app registration any Microsoft Graph API permission (no
    RequiredResourceAccess, no Update-MgApplication -Api call). README.md §3's hygiene callout
    requires this app to stay single-purpose - it authenticates only against the HR-connector
    ingestion webhook's own OAuth resource (a fixed, non-Graph resource ID hard-coded in
    Send-HrTerminationRecord.ps1), never Microsoft Graph itself. Leaving RequiredResourceAccess
    empty is what bounds a leaked secret's blast radius to "can submit HR resignation records."
    validate/Test-HrConnectorAppRegistration.ps1 checks this stays true on every run.

    Idempotent: re-running with the same -DisplayName reuses the existing app and service
    principal rather than creating duplicates. It does NOT issue a new secret on a plain
    re-run - pass -RotateSecret explicitly to add one (see .PARAMETER RotateSecret). The
    secret's plaintext value is only ever held in memory long enough to wrap it in a
    SecureString for the caller; this script never writes it to disk or the console.

    This is a one-time (or rarely-run, for rotation) bootstrap task performed by a human
    administrator, not a scheduled unattended job - it therefore uses interactive delegated
    auth (Connect-MgGraph -Scopes 'Application.ReadWrite.All'), not this repo's usual app-only
    certificate pattern (docs/automation-surface.md §3). A standing app-only credential with
    the power to create other app registrations and mint their secrets would itself be a much
    higher-value target than the one-time interactive session this task actually needs.

.PARAMETER DisplayName
    Display name for the app registration. Defaults to a name that makes its single purpose
    obvious in the Microsoft Entra admin center's "App registrations" list.

.PARAMETER SecretValidityMonths
    How many months until the issued client secret expires. Defaults to 3 (~90 days), matching
    README.md §3/§11's recommended rotation cadence for this credential. Microsoft caps any
    client secret at 24 months regardless of this value.

.PARAMETER RotateSecret
    If the app registration already exists, issue an additional client secret instead of just
    reporting the existing app's identifiers untouched. Does not revoke the prior secret -
    remove the old one from Certificates & secrets once the new one is confirmed working
    (rollback.md's "what rollback does not undo" section covers why this script won't guess at
    that timing for you).

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports the plan (create vs. reuse, secret
    issuance) without calling Microsoft Graph to create, modify, or query anything.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Register-HrConnectorApp.ps1 -WhatIf

    Dry run: shows whether a new app would be created or an existing one reused, calls nothing.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    $result = ./Register-HrConnectorApp.ps1
    $result.AppId        # -> Send-HrTerminationRecord.ps1 -AppId
    $result.TenantId     # -> Send-HrTerminationRecord.ps1 -TenantId
    $result.ClientSecret # SecureString -> Send-HrTerminationRecord.ps1 -AppSecret

    First run: creates the app, service principal, and a 3-month secret; returns everything
    Step 3 (create the HR connector) and Step 4 (Send-HrTerminationRecord.ps1) need.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Register-HrConnectorApp.ps1 -RotateSecret

    Subsequent run at the ~90-day rotation point: reuses the existing app/service principal,
    issues a new secret, and reminds you to remove the superseded one once the new secret is
    confirmed working in Send-HrTerminationRecord.ps1's scheduled task.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Set up a connector to import HR data, Step 2 (what the app registration needs - and does
      not need - for this specific flow):
      https://learn.microsoft.com/purview/import-hr-data
    - Register an application with the Microsoft identity platform (the generic quickstart
      Microsoft's own HR-connector guide points to for Step 2):
      https://learn.microsoft.com/entra/identity-platform/quickstart-register-app
    - New-MgApplication / Get-MgApplication (Microsoft.Graph.Applications):
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgapplication
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/get-mgapplication
    - New-MgServicePrincipal (creating the Application object does not auto-create this - a
      documented, separate step):
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgserviceprincipal
    - Add-MgApplicationPassword (-ApplicationId takes the object ID, aliased ObjectId; the
      returned SecretText is shown only once):
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/add-mgapplicationpassword
    - Delegate app registration permissions in Microsoft Entra ID (by default ALL member users
      can register applications - no special role is needed unless the tenant has set "Users
      can register applications" to No, in which case the operator running this script needs
      the Application Developer role; docs/rbac-model.md §11):
      https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles

    VERIFY before go-live: this script's -RotateSecret path adds a second secret rather than
    replacing the first, matching Add-MgApplicationPassword's own documented behavior (multiple
    concurrent password credentials are supported) - remove the superseded secret manually
    (Entra admin center or Remove-MgApplicationPassword) once the new one is confirmed working.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Purview HR Connector - Insider Risk Management (single-purpose)',

    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$SecretValidityMonths = 3,

    [Parameter()]
    [switch]$RotateSecret
)

$ErrorActionPreference = 'Stop'

$graphContext = Get-MgContext
if (-not $graphContext) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'Application.ReadWrite.All' first."
}
if ($graphContext.Scopes -notcontains 'Application.ReadWrite.All') {
    Write-Warning "Current Graph session does not list 'Application.ReadWrite.All' in its granted scopes - the calls below will fail if it wasn't actually consented. Reconnect with Connect-MgGraph -Scopes 'Application.ReadWrite.All' if so."
}

# --- Idempotency check: does an app with this display name already exist? ---
$existingApp = Get-MgApplication -Filter "displayName eq '$DisplayName'"
if ($existingApp -is [array] -and $existingApp.Count -gt 1) {
    throw "Multiple applications named '$DisplayName' already exist (ObjectIds: $($existingApp.Id -join ', ')) - resolve the duplicate manually before re-running this script."
}

$willCreateApp = -not $existingApp
$willIssueSecret = $willCreateApp -or $RotateSecret

if ($WhatIfPreference) {
    if ($willCreateApp) {
        Write-Host "[WhatIf] Would create application '$DisplayName' (SignInAudience: AzureADMyOrg), its service principal, and a $SecretValidityMonths-month client secret." -ForegroundColor Yellow
    }
    else {
        Write-Host "[WhatIf] Application '$DisplayName' already exists (ObjectId: $($existingApp.Id), AppId: $($existingApp.AppId))." -ForegroundColor Yellow
        if ($RotateSecret) {
            Write-Host "[WhatIf] Would issue an additional $SecretValidityMonths-month client secret (-RotateSecret)." -ForegroundColor Yellow
        }
        else {
            Write-Host '[WhatIf] Would reuse the existing app as-is (pass -RotateSecret to issue a new secret).' -ForegroundColor Yellow
        }
    }
    Write-Host 'WhatIf: no Microsoft Graph write call made.' -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess($DisplayName, $(if ($willCreateApp) { 'Create app registration + service principal + client secret' } elseif ($RotateSecret) { 'Issue additional client secret' } else { 'Reuse existing app registration (no change)' }))) {
    return
}

if ($willCreateApp) {
    Write-Host "Creating application '$DisplayName' (SignInAudience: AzureADMyOrg)..." -NoNewline
    # Single-tenant only (AzureADMyOrg) - this app never needs to accept sign-ins from other
    # tenants or personal Microsoft accounts. Deliberately no -RequiredResourceAccess: see
    # .DESCRIPTION for why this app stays permission-free.
    $app = New-MgApplication -DisplayName $DisplayName -SignInAudience 'AzureADMyOrg'
    Write-Host ' done.' -ForegroundColor Green

    Write-Host 'Creating the matching service principal (Graph does not do this automatically for an application it creates)...' -NoNewline
    $sp = New-MgServicePrincipal -AppId $app.AppId
    Write-Host ' done.' -ForegroundColor Green
}
else {
    $app = $existingApp
    Write-Host "Reusing existing application '$DisplayName' (ObjectId: $($app.Id), AppId: $($app.AppId))." -ForegroundColor Cyan
    $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'"
    if (-not $sp) {
        Write-Warning 'No service principal found for this application - creating one now (this should not normally happen for an app this script created).'
        $sp = New-MgServicePrincipal -AppId $app.AppId
    }
}

$clientSecret = $null
if ($willIssueSecret) {
    $secretLabel = "Register-HrConnectorApp.ps1 - $(Get-Date -Format 'yyyy-MM-dd')"
    Write-Host "Issuing a $SecretValidityMonths-month client secret ('$secretLabel')..." -NoNewline
    # -ApplicationId is aliased ObjectId in this cmdlet - it takes $app.Id (the object ID),
    # NOT $app.AppId (the client ID). Passing AppId here is the single most common mistake
    # with this cmdlet - see .NOTES.
    $passwordCredential = @{
        displayName = $secretLabel
        endDateTime = (Get-Date).AddMonths($SecretValidityMonths)
    }
    $secretResult = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential $passwordCredential
    Write-Host ' done.' -ForegroundColor Green

    # Immediately wrap the one-time plaintext secret value in a SecureString - this script
    # never writes the plaintext secret to disk or the console at any point.
    $clientSecret = ConvertTo-SecureString -String $secretResult.SecretText -AsPlainText -Force
}
else {
    Write-Host 'No new secret issued (pass -RotateSecret to add one to an existing app). Existing secrets are unaffected.' -ForegroundColor DarkGray
}

Write-Host "`nApplication (client) ID : $($app.AppId)" -ForegroundColor Cyan
Write-Host "Object ID               : $($app.Id)" -ForegroundColor Cyan
Write-Host "Tenant ID               : $($graphContext.TenantId)" -ForegroundColor Cyan
Write-Host "Service principal ID    : $($sp.Id)" -ForegroundColor Cyan
if ($clientSecret) {
    Write-Host 'Client secret           : (returned as a SecureString on the pipeline output - not printed here; store it in a vault immediately, it cannot be retrieved again)' -ForegroundColor Yellow
}
Write-Host "`nNext: README.md Step 3 (create the HR connector, using the Application ID above) - or, for a rotation run, update the HR-connector app secret wherever Send-HrTerminationRecord.ps1's scheduled task reads it from." -ForegroundColor Cyan

[PSCustomObject]@{
    AppId          = $app.AppId
    ObjectId       = $app.Id
    TenantId       = $graphContext.TenantId
    ServicePrincipalId = $sp.Id
    ClientSecret   = $clientSecret
    SecretIssued   = $willIssueSecret
}
