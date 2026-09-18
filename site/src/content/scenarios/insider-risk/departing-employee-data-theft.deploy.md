---
part: "deploy"
parent: "insider-risk/departing-employee-data-theft"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-InsiderRiskAlerts.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Pulls Insider Risk Management alerts via the Microsoft Graph security API for export to a
    SIEM, ticketing system, or a flat file, rather than relying on manual review in the portal.

.DESCRIPTION
    Read-only. Never modifies alert state (no triage/assignment/resolution - see design.md §6
    for why that's explicitly out of scope for this scenario's automation).

    Uses Get-MgSecurityAlertV2 (Microsoft Graph PowerShell SDK, Microsoft.Graph.Security module)
    against the /security/alerts_v2 endpoint - Microsoft's documented integration path for
    bringing Insider Risk Management alert data into a SIEM or ticketing system (Microsoft
    Learn: irm-investigate-alerts-defender, "Integrate insider risk management data with
    Microsoft Graph security API").

    IMPORTANT - server-side filter limitation: the alerts_v2 List operation's $filter only
    supports the assignedTo, classification, determination, createdDateTime, lastUpdateDateTime,
    severity, serviceSource, and status properties (Microsoft Learn: security-list-alerts_v2).
    It does NOT support filtering by detectionSource - and detectionSource, not serviceSource,
    is the property whose documented enum includes the Insider Risk Management member
    (microsoftInsiderRiskManagement; see Microsoft Learn: security-detectionsource). serviceSource
    has no Insider-Risk-Management-specific member as of this writing. This script therefore
    pulls alerts using only server-supported $filter clauses (date range + severity, optionally)
    and filters the DetectionSource property CLIENT-SIDE in PowerShell - never assume a
    'detectionSource eq ...' server-side filter will work.

    Follows the app-only, certificate-based auth pattern that is the default for every script in
    this library (docs/automation-surface.md §3) - run Connect-MgGraph yourself first with a
    certificate-backed app registration holding the SecurityAlert.Read.All application
    permission, then call this script.

.PARAMETER SinceDateTime
    Only return alerts with createdDateTime at or after this value (UTC). Defaults to 7 days
    before now - the default review cadence recommended in README.md §8.

.PARAMETER Severity
    Optional server-side filter on alert severity (informational, low, medium, high). Omit to
    return all severities.

.PARAMETER OutputPath
    If specified, writes the filtered alerts as JSON to this path in addition to returning them
    on the pipeline. Useful for a scheduled export a SIEM connector polls from a file share.

.PARAMETER WhatIf
    This script makes no mutating calls, so -WhatIf has nothing destructive to preview - it is
    accepted for interface consistency with the rest of this repo's deploy/ scripts and simply
    prints the query plan (date range, severity filter, output path) without calling Graph.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Export-InsiderRiskAlerts.ps1 -WhatIf

    Dry run: shows the query plan, calls nothing.

.EXAMPLE
    ./Export-InsiderRiskAlerts.ps1 -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./irm-alerts.json

    Pulls the last 24 hours of Insider-Risk-Management-sourced alerts and writes them to JSON
    for a SIEM connector to pick up.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Integrate insider risk management data with Microsoft Graph security API (recommended
      integration path, Incidents/Alerts/Advanced hunting table):
      https://learn.microsoft.com/defender-xdr/irm-investigate-alerts-defender
    - List alerts_v2 (supported $filter properties):
      https://learn.microsoft.com/graph/api/security-list-alerts_v2
    - alert resource type (serviceSource vs. detectionSource properties):
      https://learn.microsoft.com/graph/api/resources/security-alert
    - detectionSource enum values (microsoftInsiderRiskManagement member):
      https://learn.microsoft.com/graph/api/resources/security-detectionsource
    - SecurityAlert.Read.All permission (least-privileged for this operation):
      https://learn.microsoft.com/graph/permissions-reference

    VERIFY before relying on this in production: the exact string Insider-Risk-Management-
    sourced alerts carry in productName (this script does not filter on productName - only on
    the documented detectionSource enum member - but productName is useful for a human-readable
    SIEM label; confirm its exact value against a pilot tenant's alert data).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [datetime]$SinceDateTime = (Get-Date).ToUniversalTime().AddDays(-7),

    [Parameter()]
    [ValidateSet('informational', 'low', 'medium', 'high')]
    [string]$Severity,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$detectionSourceFilter = 'microsoftInsiderRiskManagement'

function Assert-MgGraphSession {
    if (-not (Get-MgContext)) {
        throw 'No Microsoft Graph session found. Run Connect-MgGraph first (see docs/automation-surface.md §3 for the certificate app-only pattern).'
    }
}

$sinceIso = $SinceDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
$filterClauses = @("createdDateTime ge $sinceIso")
if ($Severity) { $filterClauses += "severity eq '$Severity'" }
$serverFilter = $filterClauses -join ' and '

Write-Host "Query plan: server-side `$filter = '$serverFilter'; client-side filter = DetectionSource -eq '$detectionSourceFilter'." -ForegroundColor Cyan
if ($OutputPath) { Write-Host "Output: $OutputPath" -ForegroundColor Cyan }

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Graph call made.' -ForegroundColor Yellow
    return
}

Assert-MgGraphSession

$allAlerts = Get-MgSecurityAlertV2 -Filter $serverFilter -All
$irmAlerts = $allAlerts | Where-Object { $_.DetectionSource -eq $detectionSourceFilter }

Write-Host "Retrieved $($allAlerts.Count) alert(s) matching the server-side filter; $($irmAlerts.Count) are Insider-Risk-Management-sourced." -ForegroundColor Green

$export = $irmAlerts | Select-Object Id, Title, Severity, Status, Classification, Determination, `
    CreatedDateTime, LastUpdateDateTime, DetectionSource, ServiceSource, IncidentId, IncidentWebUrl, `
    AssignedTo, Description

if ($OutputPath) {
    $export | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $OutputPath -Encoding utf8
    Write-Host "Wrote $($export.Count) alert(s) to '$OutputPath'." -ForegroundColor Cyan
}

$export
```

#### `policy/departing-employee-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Departing Employee Data Theft",
  "policyTemplate": "Data theft by departing users",
  "scope": {
    "users": "All users (org-wide)",
    "priorityUserGroup": null,
    "priorityUserGroupNote": "Not assigned by default - see README.md §8 for when/how to add one (e.g. Finance, Engineering-with-source-access, Executives)."
  },
  "triggeringEvents": [
    {
      "type": "HR connector - employee resignation",
      "source": "HR connector job configured per README.md §5 Prerequisites; fed by deploy/Send-HrTerminationRecord.ps1",
      "fields": ["UserPrincipalName", "ResignationDate", "LastWorkingDate"]
    },
    {
      "type": "User account deleted from Microsoft Entra ID",
      "source": "Built-in Entra signal - enable this option explicitly in the policy workflow as a fallback trigger",
      "note": "Do not rely on this as the primary trigger - it fires at account deletion, near the END of the risk window. See design.md §6."
    }
  ],
  "contentPriorities": {
    "sensitivityLabels": "VERIFY: map to the tenant's actual confidential/highly-confidential label names at deploy time - not hard-coded here",
    "sensitiveInfoTypes": []
  },
  "indicators": {
    "officeIndicators": [
      "Downloading content from SharePoint",
      "Syncing content from SharePoint",
      "Downloading content from OneDrive",
      "Syncing content from OneDrive",
      "Sharing SharePoint files with people outside the organization",
      "Sharing SharePoint folders with people outside the organization",
      "Sharing file links with people outside the organization in a Teams chat"
    ],
    "deviceIndicators": [
      "Creating or copying files to USB",
      "Using a browser to upload files to the web",
      "Printing files",
      "Creating or transferring files to a network share"
    ],
    "cloudIndicators": [
      "Box", "Dropbox", "Google Drive", "Amazon S3", "Azure"
    ],
    "note": "Device indicators require device onboarding (see scenarios/dlp/endpoint-dlp-usb-block/ for the same onboarding prerequisite). Cloud indicators for non-M365 destinations bill as Data Security processing units under PAYG - see docs/licensing-matrix.md §2 and README.md §10."
  },
  "detectionOptions": {
    "sequenceDetection": true,
    "cumulativeExfiltrationDetection": true,
    "note": "Apply Microsoft-provided default thresholds on first deployment (README.md §5 step 9); do not hand-tune thresholds until at least one full activation-window cycle of baseline data exists (README.md §8)."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. See reviews.md, CISO lens."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-03"
}
```

#### `Register-HrConnectorApp.ps1`

```powershell
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
```

#### `Remove-HrConnectorAppSecret.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Removes a superseded or expired client secret from the HR-connector Entra app registration
    that deploy/Register-HrConnectorApp.ps1 creates, closing the manual-cleanup gap that script's
    own .NOTES and README.md §11 flag: "-RotateSecret adds a secret, it doesn't replace one."

.DESCRIPTION
    Resolves a follow-up tracked in PROGRESS.md. Microsoft Entra applications support multiple
    concurrent client secrets by design, so Register-HrConnectorApp.ps1 -RotateSecret always adds
    a new one alongside any existing (even already-expired) ones rather than replacing it - a
    correct, documented Microsoft Graph behavior, not a bug in that script. Left alone, a
    superseded secret is a standing, unnecessary credential-leak surface until someone remembers
    to delete it by hand in the Microsoft Entra admin center. This script makes that cleanup a
    scripted, idempotent, -WhatIf-capable step instead.

    Two removal modes (mutually exclusive - see .PARAMETER RemoveExpired / .PARAMETER KeyId):

      -RemoveExpired (default, safe-by-construction): removes every password credential whose
      EndDateTime has already passed. An already-expired secret cannot authenticate
      Send-HrTerminationRecord.ps1 regardless of whether this script deletes it, so this mode
      never reduces the app's *working* secret count - it only deletes dead weight.

      -KeyId <guid>: removes one specific password credential by its KeyId (from
      Get-MgApplication's PasswordCredentials, or the value Register-HrConnectorApp.ps1's
      -RotateSecret run reported for the *previous* secret before rotation). Unlike
      -RemoveExpired, this can target a credential that has NOT yet expired - e.g. an operator
      who wants to force-retire a secret immediately after confirming the new one works, without
      waiting for the old one's natural expiry. Because this can remove a still-valid secret,
      the script refuses to proceed if doing so would leave the application with zero unexpired
      secrets, unless -Force is also passed - that combination would silently break
      Send-HrTerminationRecord.ps1's next scheduled run with no working credential left.

    Calls Microsoft Graph's application: removePassword action via Remove-MgApplicationPassword
    (Microsoft.Graph.Applications, v1.0 - confirmed current, non-beta, on this run against
    Microsoft Learn). -ApplicationId takes the application's OBJECT ID (aliased ObjectId in this
    cmdlet, same as Add-MgApplicationPassword in Register-HrConnectorApp.ps1) - not its AppId
    (client ID). This script always resolves and passes $app.Id, never $app.AppId.

    Idempotent: re-running with -RemoveExpired after there is nothing left to expire, or with a
    -KeyId that no longer exists on the application, reports "nothing to do" and exits cleanly
    rather than erroring.

.PARAMETER DisplayName
    Display name of the app registration to clean up. Must match the -DisplayName used with
    deploy/Register-HrConnectorApp.ps1 (defaults to the same value).

.PARAMETER RemoveExpired
    Remove every password credential that has already expired (EndDateTime in the past). Safe by
    construction - see .DESCRIPTION. This is the default, lower-risk mode.

.PARAMETER KeyId
    Remove one specific password credential by its KeyId, regardless of whether it has expired
    yet. Mutually exclusive with -RemoveExpired. Requires -Force if the targeted credential has
    not yet expired and removing it would leave zero unexpired secrets on the application.

.PARAMETER Force
    Required in addition to -KeyId when the targeted credential is still unexpired AND removing
    it would leave the application with no working secret. Never required for -RemoveExpired,
    which by definition only removes already-dead credentials.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports which credential(s) would be removed
    without calling Microsoft Graph to change anything.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -RemoveExpired -WhatIf

    Dry run: lists which already-expired secrets would be deleted, calls nothing.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -RemoveExpired

    Routine cleanup: deletes every already-expired secret on the app. Safe to run on a schedule
    or immediately after confirming a -RotateSecret run's new secret works in production.

.EXAMPLE
    Connect-MgGraph -Scopes 'Application.ReadWrite.All'
    ./Remove-HrConnectorAppSecret.ps1 -KeyId '5b1a1e3e-8f21-4a6c-9d3b-1a2b3c4d5e6f' -Force

    Force-retires one specific still-valid secret immediately (e.g. suspected exposure) even
    though it has not expired yet, accepting that this may leave the app with fewer working
    secrets - only needed if that secret is also the last unexpired one.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-MgApplicationPassword (Microsoft.Graph.Applications, v1.0 - confirmed current, not
      the beta-only Remove-MgBetaApplicationPassword; -ApplicationId is aliased ObjectId and
      takes the application's object ID; -KeyId's own documented parameter type is
      System.String, not System.Guid, despite the underlying Graph resource property's Edm type
      being Guid - this script's own -KeyId parameter is typed [string] with a GUID-format
      ValidatePattern to match the cmdlet's actual signature exactly, rather than declaring
      [guid] and risking an unnecessary type-conversion mismatch against what
      Get-MgApplication's PasswordCredentials.KeyId returns at runtime):
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/remove-mgapplicationpassword
    - application: removePassword (the underlying Graph REST action - `POST /applications/{id}/
      removePassword` with a `{"keyId": "<guid>"}` body; the REST reference documents addressing
      by the object ID path segment only, so this script always resolves and passes $app.Id, the
      same object ID Register-HrConnectorApp.ps1's Add-MgApplicationPassword call already uses):
      https://learn.microsoft.com/graph/api/application-removepassword
    - passwordCredential resource type (keyId's Edm type is Guid at the REST layer; endDateTime
      is the expiry this script's -RemoveExpired mode filters on):
      https://learn.microsoft.com/graph/api/resources/passwordcredential
    - Get-MgApplication / Add-MgApplicationPassword: see deploy/Register-HrConnectorApp.ps1
      .NOTES for these references (unchanged by this script).

    This script never prints or logs a secret's plaintext value - it only ever handles KeyId
    (a non-secret Guid identifier) and EndDateTime, never SecretText.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Expired')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Purview HR Connector - Insider Risk Management (single-purpose)',

    [Parameter(ParameterSetName = 'Expired')]
    [switch]$RemoveExpired,

    [Parameter(Mandatory, ParameterSetName = 'Specific')]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$KeyId,

    [Parameter(ParameterSetName = 'Specific')]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Expired' -and -not $RemoveExpired) {
    throw 'Specify -RemoveExpired to delete all already-expired secrets, or -KeyId <guid> to remove one specific secret.'
}

$graphContext = Get-MgContext
if (-not $graphContext) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'Application.ReadWrite.All' first."
}
if ($graphContext.Scopes -notcontains 'Application.ReadWrite.All') {
    Write-Warning "Current Graph session does not list 'Application.ReadWrite.All' in its granted scopes - the call below will fail if it wasn't actually consented. Reconnect with Connect-MgGraph -Scopes 'Application.ReadWrite.All' if so."
}

$app = Get-MgApplication -Filter "displayName eq '$DisplayName'" `
    -Property Id, DisplayName, AppId, PasswordCredentials
if (-not $app) {
    throw "No application named '$DisplayName' found - nothing to clean up. Has deploy/Register-HrConnectorApp.ps1 been run yet?"
}
if ($app -is [array]) {
    throw "Multiple applications named '$DisplayName' exist (ObjectIds: $($app.Id -join ', ')) - resolve the duplicate manually before re-running this script."
}

$now = Get-Date
$credentials = @($app.PasswordCredentials)
$validCredentials = @($credentials | Where-Object { $_.EndDateTime -gt $now })

if ($PSCmdlet.ParameterSetName -eq 'Expired') {
    $targets = @($credentials | Where-Object { $_.EndDateTime -le $now })
    if ($targets.Count -eq 0) {
        Write-Host "No expired secrets found on '$DisplayName' ($($credentials.Count) total, all unexpired). Nothing to do." -ForegroundColor Green
        return
    }
}
else {
    $target = $credentials | Where-Object { $_.KeyId -eq $KeyId }
    if (-not $target) {
        Write-Host "No secret with KeyId '$KeyId' found on '$DisplayName'. Nothing to do (already removed, or wrong KeyId)." -ForegroundColor Green
        return
    }
    $isTargetValid = $target.EndDateTime -gt $now
    $wouldOrphanApp = $isTargetValid -and $validCredentials.Count -le 1
    if ($wouldOrphanApp -and -not $Force) {
        throw "KeyId '$KeyId' is the application's only unexpired secret - removing it would leave Send-HrTerminationRecord.ps1 with no working credential. Re-run with -Force if this is intentional (e.g. suspected secret exposure), after confirming a replacement secret is already deployed."
    }
    $targets = @($target)
}

foreach ($cred in $targets) {
    $label = if ($cred.DisplayName) { $cred.DisplayName } else { '(no label)' }
    $status = if ($cred.EndDateTime -le $now) { "expired $($cred.EndDateTime.ToString('u'))" } else { "VALID until $($cred.EndDateTime.ToString('u'))" }

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Would remove secret KeyId=$($cred.KeyId) ('$label', $status) from '$DisplayName'." -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess("$DisplayName (KeyId=$($cred.KeyId), $status)", 'Remove client secret')) {
        continue
    }

    Write-Host "Removing secret KeyId=$($cred.KeyId) ('$label', $status)..." -NoNewline
    # -ApplicationId takes the object ID (aliased ObjectId), matching Register-HrConnectorApp.ps1's
    # Add-MgApplicationPassword usage - never $app.AppId.
    Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $cred.KeyId | Out-Null
    Write-Host ' done.' -ForegroundColor Green
}

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Microsoft Graph write call made.' -ForegroundColor Yellow
    return
}

$remaining = @((Get-MgApplication -ApplicationId $app.Id -Property PasswordCredentials).PasswordCredentials)
$remainingValid = @($remaining | Where-Object { $_.EndDateTime -gt $now })
Write-Host "`n$($targets.Count) secret(s) removed. $($remainingValid.Count) unexpired secret(s) remain on '$DisplayName'." -ForegroundColor Cyan
if ($remainingValid.Count -eq 0) {
    Write-Warning "No unexpired secrets remain on '$DisplayName' - Send-HrTerminationRecord.ps1's next scheduled run will fail authentication until Register-HrConnectorApp.ps1 -RotateSecret issues a new one."
}
```

#### `Send-HrTerminationRecord.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Uploads an employee-resignation CSV to a Microsoft Purview HR connector, feeding the
    "Data theft by departing users" Insider Risk Management policy's triggering event.

.DESCRIPTION
    Wraps Microsoft's own documented HR-connector ingestion pattern (Microsoft Learn:
    import-hr-data, "Step 4: Run the sample script to upload your HR data") as a parameterized,
    -WhatIf-capable, chunking-aware PowerShell function instead of a one-off script edited
    in place. It does not call any Purview/Exchange/Graph PowerShell module cmdlet - the HR
    connector ingestion surface is a plain HTTPS webhook, not a PowerShell module, and this
    script talks to it directly with Invoke-RestMethod / HttpClient-equivalent calls.

    Flow (matches the documented sample script's behavior):
      1. Acquire an OAuth 2.0 client-credentials access token from
         https://login.windows.net/<TenantId>/oauth2/token against the fixed HR-connector
         ingestion resource ID.
      2. Split the input CSV into chunks of at most 500 data rows (the documented per-file
         ingestion limit; see README.md References) - a header row is added to every chunk.
      3. POST each chunk as multipart/form-data (field name "file") to
         https://webhook.ingestion.office.com/api/signals?jobid=<JobId>, bearer-authenticated
         with the token from step 1, over TLS 1.2.

    Idempotency note: the HR connector's own re-ingestion/de-duplication behavior for a
    resignation record with the same UserPrincipalName uploaded twice is NOT documented by
    Microsoft as of this writing (VERIFY in a pilot tenant before relying on daily re-uploads
    of an unchanged CSV to be a no-op). Re-running this script is always SAFE in the sense
    that it never deletes or mutates existing tenant state - at worst it re-submits already-
    ingested rows.

    This script never embeds a client secret. Pass it as a SecureString (interactively, from
    a secrets vault, or from a CI secret) - never hard-code it or check it into source control.

    Author-only reference code. This script makes an outbound HTTPS call to
    webhook.ingestion.office.com whenever it runs WITHOUT -WhatIf - there is no "connect first,
    then run" separation like the Security & Compliance PowerShell scenarios in this repo,
    because this surface has no session concept. Always run with -WhatIf first.

.PARAMETER TenantId
    Microsoft Entra tenant ID (directory ID) - see docs/automation-surface.md for how to find it.

.PARAMETER AppId
    Application (client) ID of the Microsoft Entra app registered for this HR connector
    (Microsoft Learn: import-hr-data, Step 2). This script does not create the app registration
    - see README.md Prerequisites.

.PARAMETER AppSecret
    Client secret for the app above, as a SecureString. Never pass in plaintext; never store
    in this repo or in an unencrypted file.

.PARAMETER JobId
    The HR connector's Job ID, generated when the connector is created in the Purview portal
    (Microsoft Learn: import-hr-data, Step 3).

.PARAMETER CsvPath
    Path to the resignation CSV. Required columns: UserPrincipalName, ResignationDate,
    LastWorkingDate (ISO 8601 date-time format) - see README.md Configuration reference for the
    exact schema this scenario uses.

.PARAMETER ChunkSize
    Maximum data rows per uploaded chunk. Defaults to 500, the documented per-file ingestion
    limit. Lower this only if you have evidence a given tenant needs a smaller chunk.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Validates the CSV schema, computes the chunk
    plan, and reports exactly what would be uploaded (chunk count, row counts, target JobId) -
    acquires no token and makes no HTTP call to the ingestion endpoint.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'HR connector app secret'
    ./Send-HrTerminationRecord.ps1 -TenantId $TenantId -AppId $AppId -AppSecret $secret `
        -JobId $JobId -CsvPath './employee_resignations.csv' -WhatIf

    Dry run: validates the CSV and reports the upload plan, sends nothing.

.EXAMPLE
    ./Send-HrTerminationRecord.ps1 -TenantId $TenantId -AppId $AppId -AppSecret $secret `
        -JobId $JobId -CsvPath './employee_resignations.csv'

    Uploads the CSV to the HR connector, chunked at 500 rows per call.

.NOTES
    Grounded in Microsoft Learn (verify before production use - Microsoft describes the
    underlying sample script as provided AS IS, unsupported under any standard support
    program):
    - Set up a connector to import HR data (CSV schema, Steps 1-4, webhook domain,
      client-credentials auth, 500-row-per-file limit, GitHub sample script location):
      https://learn.microsoft.com/purview/import-hr-data
    - Sample script source (reference only - this script is an independent, parameterized
      reimplementation, not a copy):
      https://github.com/microsoft/m365-compliance-connector-sample-scripts

    VERIFY before go-live: confirm re-ingestion/de-duplication behavior for an unchanged CSV
    re-uploaded on a subsequent scheduled run, in a pilot tenant - not documented by Microsoft
    as of this writing (see design.md §6 and README.md §11).

    Requires PowerShell 7.0+: this script uses Invoke-RestMethod's -Form parameter for
    multipart/form-data upload, which is not available in Windows PowerShell 5.1's
    Invoke-RestMethod (5.1 lacks -Form entirely). This is the one script in this repo that
    departs from the "5.1 or 7+" flexibility of the EXO/S&C-based scenarios, because this
    surface is a plain REST endpoint with no PowerShell-module alternative to fall back to.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [System.Security.SecureString]$AppSecret,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$JobId,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$ChunkSize = 500
)

$ErrorActionPreference = 'Stop'

# Fixed per Microsoft's documented HR connector ingestion flow (import-hr-data) - not a
# tenant-specific value, so not exposed as a parameter.
$tokenEndpointTemplate = 'https://login.windows.net/{0}/oauth2/token?api-version=1.0'
$ingestionResource = 'https://microsoft.onmicrosoft.com/86dfdabb-5089-4a0c-880a-cfa5a790c5b1'
$webhookBaseUrl = 'https://webhook.ingestion.office.com/api/signals'
$requiredColumns = @('UserPrincipalName', 'ResignationDate', 'LastWorkingDate')

function ConvertFrom-SecureStringPlain {
    param([Parameter(Mandatory)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# --- Validate CSV schema before doing anything else ---
$rows = Import-Csv -LiteralPath $CsvPath
if ($rows.Count -eq 0) {
    throw "CsvPath '$CsvPath' contains no data rows."
}
$actualColumns = $rows[0].PSObject.Properties.Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns }
if ($missingColumns) {
    throw "CsvPath '$CsvPath' is missing required column(s): $($missingColumns -join ', '). Required: $($requiredColumns -join ', ')."
}

# --- Compute the chunk plan (data rows only; header is re-added per chunk on upload) ---
# @(...) forces array-of-chunks even when there's exactly one chunk (PowerShell would
# otherwise unwrap a single-item for-loop result to a bare array of rows, not an array
# containing one chunk).
$chunks = @(for ($i = 0; $i -lt $rows.Count; $i += $ChunkSize) {
    , $rows[$i..([Math]::Min($i + $ChunkSize - 1, $rows.Count - 1))]
})
Write-Host "CSV '$CsvPath': $($rows.Count) resignation record(s), $($chunks.Count) chunk(s) of up to $ChunkSize row(s), target JobId '$JobId'." -ForegroundColor Cyan

if ($WhatIfPreference) {
    for ($c = 0; $c -lt $chunks.Count; $c++) {
        Write-Host "  [WhatIf] Chunk $($c + 1)/$($chunks.Count): $($chunks[$c].Count) row(s) -> POST $webhookBaseUrl`?jobid=$JobId" -ForegroundColor Yellow
    }
    Write-Host 'WhatIf: no token acquired, no HTTP call made.' -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess("HR connector JobId '$JobId'", "Upload $($rows.Count) resignation record(s) in $($chunks.Count) chunk(s)")) {
    return
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# --- Acquire an OAuth 2.0 client-credentials token (Microsoft Learn: import-hr-data Step 4) ---
$plainSecret = ConvertFrom-SecureStringPlain -Secure $AppSecret
try {
    $tokenBody = @{
        client_id     = $AppId
        client_secret = $plainSecret
        grant_type    = 'client_credentials'
        resource      = $ingestionResource
    }
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri ($tokenEndpointTemplate -f $TenantId) `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $tokenBody
}
finally {
    $plainSecret = $null
}
$accessToken = $tokenResponse.access_token
if (-not $accessToken) {
    throw 'Token acquisition succeeded but returned no access_token - check AppId/AppSecret/TenantId.'
}

# --- Upload each chunk as multipart/form-data ---
$uploadUri = "$webhookBaseUrl`?jobid=$JobId"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "hr-connector-upload-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    for ($c = 0; $c -lt $chunks.Count; $c++) {
        $chunkPath = Join-Path $tempDir "chunk-$($c + 1).csv"
        $chunks[$c] | Export-Csv -LiteralPath $chunkPath -NoTypeInformation

        $form = @{ file = Get-Item -LiteralPath $chunkPath }
        $headers = @{ Authorization = "Bearer $accessToken" }

        Write-Host "Uploading chunk $($c + 1)/$($chunks.Count) ($($chunks[$c].Count) row(s))..." -NoNewline
        $null = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers -Form $form -TimeoutSec 400
        Write-Host ' done.' -ForegroundColor Green
    }
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nUpload complete: $($rows.Count) resignation record(s) submitted to JobId '$JobId' in $($chunks.Count) chunk(s)." -ForegroundColor Cyan
Write-Host 'Verify ingestion in the Purview portal: Settings > Data connectors > (this HR connector) > Download log.' -ForegroundColor Cyan
```