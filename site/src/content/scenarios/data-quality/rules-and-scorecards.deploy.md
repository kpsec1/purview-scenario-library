---
part: "deploy"
parent: "data-quality/rules-and-scorecards"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-DataQualityRulesAndSchedule.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotently creates or updates Microsoft Purview Unified Catalog Data Quality rules for a
    governed data asset from a declarative JSON definition file, and schedules a one-time scan run.

.DESCRIPTION
    Calls the Microsoft Purview Data Quality REST API for Unified Catalog (Public Preview,
    automation surface 4 per docs/automation-surface.md) to:
      1. Read each rule in the definition file and reconcile it against the asset's existing
         rules (matched by name) - create a new rule if no name match exists, or update the
         existing rule in place (same ruleId) if one does.
      2. Optionally (-CreateSchedule, default on) create or update a one-time ("RunOnce") scan
         schedule scoped to the target data product/asset, so the rules just deployed actually run
         without a manual "Run quality scan" click in the portal.

    Idempotent by construction, matching this repo's established Data Map/Unified Catalog REST
    idiom: every rule is targeted at a specific ruleId (an existing rule's own ID when a name
    match is found via Get Rules, otherwise a newly generated GUID), and the same ruleId is always
    PUT to the Create Rules endpoint - so re-running this script with an unchanged definition file
    updates each rule in place rather than duplicating it, regardless of whether Create Rules'
    PUT is documented as strictly create-only or create-or-replace (this build's grounding pass did
    not find an explicit statement either way for this specific operation - see README.md Section 11
    VERIFY). The schedule follows the same pattern via Get Schedule/Create Schedule.

    This script does NOT create the governance domain, data product, data asset, or the Data
    Quality data-source connection (managed-identity credential + Azure SQL server/database) those
    rules run against - all four are prerequisites documented in README.md Section 3 and Section 5,
    following the product's own documented Data Quality lifecycle (register/scan the source in Data
    Map, add the asset to a data product, then set up the DQ connection) before rules can be
    authored against it at all.

    Author-only reference code. Never connects to a live tenant unless you supply real credentials
    and omit -WhatIf. Rules are created in 'Active' status by default (matching the portal's default
    for a newly created rule) - pass -RuleStatus Draft to land them without affecting live scores
    until reviewed.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API. Use
    'https://api.purview-service.microsoft.com' for tenants on the current Microsoft Purview
    portal, or 'https://<account>.purview.azure.com' for the classic portal - same distinction
    documented in scenarios/unified-catalog/curate-business-glossary/README.md Section 11.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of the service principal used to call the Data Quality REST API. Must
    hold the Data Quality Steward role on the target governance domain, which itself requires the
    Governance Domain Reader and Data Product Owner roles on that domain (docs/rbac-model.md
    Section 5 and README.md Section 3).

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString. Resolve from a vault at run time - never hard-code.

.PARAMETER RulesDefinitionPath
    Path to the rules definition JSON file. See deploy/rules/customer-master-data-quality-rules.json
    for the expected shape (businessDomainId/dataProductId/dataAssetId + a rules array). Each rule's
    typeProperties is passed through to the API unmodified - this script does not attempt to model
    or validate the shape of any specific rule type's typeProperties beyond what the definition
    file's author already knows is correct for that type (README.md Section 6).

.PARAMETER RuleStatus
    'Active' (default) or 'Draft'. Draft rules are created but do not contribute to the asset's
    global score and are not evaluated during a scan (README.md Section 6).

.PARAMETER CreateSchedule
    If supplied (default: $true), creates or updates a one-time scan schedule scoped to the data
    product/asset named in the definition file. Pass -CreateSchedule:$false to deploy rules only
    and trigger the scan separately (portal "Run quality scan", or a later run of this script).

.PARAMETER ScheduleId
    Identifier for the schedule object. Defaults to "<dataAssetId>-dq-scan".

.PARAMETER ScheduleName
    Display name for the schedule. Defaults to "Data quality scan - <assetDisplayName>".

.PARAMETER TriggerTimeUtc
    UTC timestamp the one-time scan should fire at. Defaults to five minutes from now. This
    scenario's schedule uses the API's confirmed 'RunOnce' trigger type only - see README.md
    Section 11 for why a recurring (daily/weekly/monthly) trigger type, while present in the
    portal's own scheduling UI, is not scripted here.

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview', confirmed current via
    a direct fetch of Microsoft's own REST reference at the time of this build.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every REST call that would be made without
    sending any mutating (PUT) request. Invoke-RestMethod has no native ShouldProcess integration,
    so this script wraps each mutating call in its own $PSCmdlet.ShouldProcess() check.

.EXAMPLE
    ./New-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath './rules/customer-master-data-quality-rules.json' -WhatIf

    Dry-run: shows exactly which REST calls would be made, changes nothing.

.EXAMPLE
    ./New-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath './rules/customer-master-data-quality-rules.json'

    Creates/updates the five rules in Active status and schedules a one-time scan five minutes out.

.EXAMPLE
    ./New-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath './rules/customer-master-data-quality-rules.json' -RuleStatus Draft -CreateSchedule:$false

    Lands the rules in Draft (no effect on live scores, no scan triggered) for review before
    activation - re-run without -RuleStatus Draft once approved.

.NOTES
    VERIFY before production use (see README.md Section 11 for full detail):
    - The exact mechanism by which a 'TypeMatch' (Data type match) rule's typeProperties specifies
      *which* target type a column is checked against. Microsoft's conceptual documentation
      describes the behavior (the engine translates native types into its own type system) but the
      REST TypeProperties schema returned by this build's grounding pass exposes only `column`,
      `columns`, `condition`, `emptyCriteria`, `filterCriteria`, and `pattern` - no field named for
      an expected/target type. This script ships the TypeMatch rule with only `column` set, per the
      example in Microsoft's own Get Rules reference page; confirm against a pilot tenant whether a
      target type must be supplied some other way (e.g. inferred from the asset's imported schema)
      before relying on this rule catching real type mismatches.
    - Whether Create Rules' PUT is strictly create-only or create-or-replace when reused against an
      existing ruleId - this build's fetch of the operation's reference page did not state either
      way explicitly (unlike the Data Map Scans - Create Or Replace operation, which does). This
      script's idempotency does not depend on the answer (see .DESCRIPTION), but a production
      integration that calls Create Rules directly without this script's existence check first
      should confirm the behavior.
    - The Schedule object's Trigger `type` values beyond 'RunOnce' (i.e., a documented Recurrence
      type with frequency/interval fields, analogous to Data Map's Scans trigger). This build's
      grounding pass found only the 'RunOnce' shape in Microsoft's own REST examples for this
      operation; the portal's "Scheduled scans" wizard visibly supports daily/weekly/monthly
      recurrence, so a recurring type almost certainly exists, but its exact typeProperties were not
      independently confirmed. This script schedules a single RunOnce scan only - see README.md
      Section 8 for the portal-based recurring-schedule workaround until this is closed.

    Sources (Microsoft Learn, verify before production use):
    - Purview Data Quality REST operation groups (Create Rules, Get Rules, Create Schedule, Get
      Schedule, Get Asset Scores For Asset DQ):
      https://learn.microsoft.com/rest/api/purview/purviewdataquality/operation-groups?view=rest-purview-purviewdataquality-2026-01-12-preview
    - Data Quality API for Unified Catalog (Public Preview) - lifecycle and scope:
      https://learn.microsoft.com/rest/api/purview/unified-catalog-data-quality
    - Create data quality rules (rule types, dimensions, custom-rule expression language):
      https://learn.microsoft.com/purview/unified-catalog-data-quality-rules
    - Tutorial: Authenticate for Microsoft Purview data-plane APIs (token acquisition, roles):
      https://learn.microsoft.com/purview/data-gov-api-rest-data-plane
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RulesDefinitionPath,

    [Parameter()]
    [ValidateSet('Active', 'Draft')]
    [string]$RuleStatus = 'Active',

    [Parameter()]
    [bool]$CreateSchedule = $true,

    [Parameter()]
    [string]$ScheduleId,

    [Parameter()]
    [string]$ScheduleName,

    [Parameter()]
    [datetime]$TriggerTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(5),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'

$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][SecureString]$Secure)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-PurviewAccessToken {
    # v1 client-credentials flow against the shared Data Map / Unified Catalog / Data Quality
    # data-plane resource, per docs/automation-surface.md Section 3.
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

function Invoke-Dq {
    # Invoke-RestMethod has no native ShouldProcess integration, so every mutating call is wrapped
    # in its own $PSCmdlet.ShouldProcess() check. GET calls always execute, including under -WhatIf,
    # so the script can accurately report create vs. update for each rule/schedule.
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Put', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][hashtable]$Body,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][string]$Description = $Uri
    )
    if ($Method -eq 'Get') {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" }
    }
    if ($PSCmdlet.ShouldProcess($Description, "$Method $Uri")) {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            ContentType = 'application/json'
            Headers     = @{ Authorization = "Bearer $Token" }
        }
        if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }
        return Invoke-RestMethod @params
    }
    Write-Verbose "WhatIf: would $Method $Uri$(if ($Body) { " with body:`n$($Body | ConvertTo-Json -Depth 10)" })"
    return $null
}

function Get-ExistingRuleByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RulesListUri,
        [Parameter(Mandatory)][string]$Token
    )
    $existing = Invoke-Dq -Method Get -Uri "$RulesListUri?api-version=$ApiVersion" -Token $Token
    return ($existing | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
}

function Get-OrNewRule {
    param(
        [Parameter(Mandatory)][pscustomobject]$RuleDef,
        [Parameter(Mandatory)][string]$BusinessDomainId,
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$DataAssetId,
        [Parameter(Mandatory)][string]$RulesListUri,
        [Parameter(Mandatory)][string]$Token
    )
    $existing = Get-ExistingRuleByName -Name $RuleDef.name -RulesListUri $RulesListUri -Token $Token
    $ruleId = if ($existing) { $existing.id } else { [guid]::NewGuid().ToString() }

    $body = @{
        id             = $ruleId
        name           = $RuleDef.name
        description    = $RuleDef.description
        type           = $RuleDef.type
        status         = $RuleStatus
        dimension      = $RuleDef.dimension
        typeProperties = $RuleDef.typeProperties
        businessDomain = @{ referenceId = $BusinessDomainId; type = 'BusinessDomainReference' }
        dataProduct    = @{ referenceId = $DataProductId; type = 'DataProductReference' }
        dataAsset      = @{ referenceId = $DataAssetId; type = 'DataAssetReference' }
    }

    $uri = "$RulesListUri/$ruleId?api-version=$ApiVersion"
    $verb = if ($existing) { 'Update' } else { 'Create' }
    Invoke-Dq -Method Put -Uri $uri -Body $body -Token $Token `
        -Description "$verb rule '$($RuleDef.name)' on asset '$DataAssetId'" | Out-Null
    Write-Host "$verb`d rule '$($RuleDef.name)' (id: $ruleId, type: $($RuleDef.type), status: $RuleStatus)." -ForegroundColor Green
    return $ruleId
}

function Get-OrNewSchedule {
    param(
        [Parameter(Mandatory)][string]$BusinessDomainId,
        [Parameter(Mandatory)][string]$DataProductId,
        [Parameter(Mandatory)][string]$DataAssetId,
        [Parameter(Mandatory)][string]$ScheduleId,
        [Parameter(Mandatory)][string]$ScheduleName,
        [Parameter(Mandatory)][datetime]$TriggerTimeUtc,
        [Parameter(Mandatory)][string]$Token
    )
    $scheduleUri = "$endpoint/datagovernance/quality/business-domains/$BusinessDomainId/schedules/$ScheduleId?api-version=$ApiVersion"

    $existing = $null
    try { $existing = Invoke-Dq -Method Get -Uri $scheduleUri -Token $Token }
    catch {
        if (-not ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404)) { throw }
    }

    $body = @{
        id          = $ScheduleId
        name        = $ScheduleName
        description = "One-time data quality scan created by New-DataQualityRulesAndSchedule.ps1."
        trigger     = @{
            type           = 'RunOnce'
            typeProperties = @{
                timezone    = 'UTC'
                isScheduled = $true
                triggerTime = $TriggerTimeUtc.ToString('o')
            }
        }
        scope       = @{
            items = @(
                @{
                    dataProduct = @{ referenceId = $DataProductId; type = 'DataProductReference' }
                    dataAsset   = @{ referenceId = $DataAssetId; type = 'DataAssetReference' }
                }
            )
        }
        businessDomain = @{ referenceId = $BusinessDomainId; type = 'BusinessDomainReference' }
    }

    $verb = if ($existing) { 'Update' } else { 'Create' }
    Invoke-Dq -Method Put -Uri $scheduleUri -Body $body -Token $Token `
        -Description "$verb schedule '$ScheduleName'" | Out-Null
    Write-Host "$verb`d schedule '$ScheduleName' (id: $ScheduleId, fires: $($TriggerTimeUtc.ToString('u')))." -ForegroundColor Green
}

# --- Load and validate the definition file ---
$definition = Get-Content -Path $RulesDefinitionPath -Raw | ConvertFrom-Json
foreach ($required in 'businessDomainId', 'dataProductId', 'dataAssetId', 'rules') {
    if (-not $definition.$required) {
        throw "Definition file '$RulesDefinitionPath' is missing required field '$required'."
    }
}

if (-not $ScheduleId) { $ScheduleId = "$($definition.dataAssetId)-dq-scan" }
if (-not $ScheduleName) {
    $assetLabel = if ($definition.assetDisplayName) { $definition.assetDisplayName } else { $definition.dataAssetId }
    $ScheduleName = "Data quality scan - $assetLabel"
}

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Step 1: create/update each rule in the definition file ---
$rulesListUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)" +
"/data-products/$($definition.dataProductId)/data-assets/$($definition.dataAssetId)/rules"

$ruleIds = @{}
foreach ($ruleDef in $definition.rules) {
    $ruleIds[$ruleDef.name] = Get-OrNewRule -RuleDef $ruleDef `
        -BusinessDomainId $definition.businessDomainId -DataProductId $definition.dataProductId `
        -DataAssetId $definition.dataAssetId -RulesListUri $rulesListUri -Token $token
}

Write-Host "`n$($definition.rules.Count) rule(s) reconciled against asset '$($definition.assetDisplayName)'." -ForegroundColor Cyan

# --- Step 2 (optional): create/update a one-time scan schedule ---
if ($CreateSchedule) {
    Get-OrNewSchedule -BusinessDomainId $definition.businessDomainId -DataProductId $definition.dataProductId `
        -DataAssetId $definition.dataAssetId -ScheduleId $ScheduleId -ScheduleName $ScheduleName `
        -TriggerTimeUtc $TriggerTimeUtc -Token $token
    Write-Host "`nDone. The scan will fire once at $($TriggerTimeUtc.ToString('u')). Re-run this script (it will update the same schedule ID) to reschedule, or use the portal's Scheduled scans wizard for a recurring cadence - see README.md Section 8/11." -ForegroundColor Cyan
}
else {
    Write-Host "`nDone. -CreateSchedule:`$false was passed - no scan scheduled. Trigger one via the portal's 'Run quality scan', or re-run this script with -CreateSchedule:`$true." -ForegroundColor Cyan
}

Write-Host "Run validate/Test-DataQualityRulesAndScorecard.ps1 to verify the deployed rules, schedule, and (once a scan has run) the asset's score." -ForegroundColor Cyan
```

#### `Remove-DataQualityRulesAndSchedule.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the scan schedule created by New-DataQualityRulesAndSchedule.ps1, and optionally the
    data quality rules themselves.

.DESCRIPTION
    Staged rollback (see ../rollback.md for the full procedure and what each stage does and does
    not undo):
      Stage 1 (default): delete the schedule only. The rules stay in place (still contributing to
        the asset's score whenever a scan does run - portal ad hoc, or a future re-run of the
        deploy script), but no further automatic scan is scheduled.
      Stage 2 (-RemoveRules): also delete every rule named in the definition file, from the asset.

    Idempotent: deleting an object that no longer exists (404) is treated as already-removed, not
    an error, so this script is safe to re-run.

.PARAMETER PurviewAccountEndpoint
    Base URL of the Purview Unified Catalog / Data Quality data-plane API.

.PARAMETER TenantId
    Microsoft Entra tenant ID.

.PARAMETER AppId
    Application (client) ID of a service principal holding the Data Quality Steward role on the
    target governance domain.

.PARAMETER ClientSecret
    Client secret for -AppId, as a SecureString.

.PARAMETER RulesDefinitionPath
    Path to the same rules definition JSON file passed to New-DataQualityRulesAndSchedule.ps1 -
    used to resolve the businessDomainId/dataProductId/dataAssetId and, with -RemoveRules, which
    rules (by name) to delete.

.PARAMETER ScheduleId
    Identifier of the schedule to delete. Defaults to "<dataAssetId>-dq-scan", matching the deploy
    script's default.

.PARAMETER RemoveRules
    If supplied, also deletes every rule in the definition file from the asset (Stage 2). Omit to
    remove only the schedule (Stage 1).

.PARAMETER ApiVersion
    Data Quality REST API version to pin. Defaults to '2026-01-12-preview', matching the deploy
    script.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    ./Remove-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath '../deploy/rules/customer-master-data-quality-rules.json' -WhatIf

    Dry-run of Stage 1 (schedule removal only).

.EXAMPLE
    ./Remove-DataQualityRulesAndSchedule.ps1 -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
        -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
        -RulesDefinitionPath '../deploy/rules/customer-master-data-quality-rules.json' -RemoveRules

    Stage 2: removes the schedule and every rule in the definition file.

.NOTES
    Sources: same as New-DataQualityRulesAndSchedule.ps1 - see that script's .NOTES.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PurviewAccountEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$RulesDefinitionPath,

    [Parameter()]
    [string]$ScheduleId,

    [Parameter()]
    [switch]$RemoveRules,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2026-01-12-preview'
)

$ErrorActionPreference = 'Stop'
$endpoint = $PurviewAccountEndpoint.TrimEnd('/')

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

function Remove-IfExists {
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
        Write-Host "Removed: $Description." -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Host "Already removed (404): $Description." -ForegroundColor Yellow
        }
        else { throw }
    }
}

$definition = Get-Content -Path $RulesDefinitionPath -Raw | ConvertFrom-Json
if (-not $ScheduleId) { $ScheduleId = "$($definition.dataAssetId)-dq-scan" }

$plainSecret = ConvertTo-PlainText -Secure $ClientSecret
try {
    $token = Get-PurviewAccessToken -TenantId $TenantId -AppId $AppId -PlainSecret $plainSecret
}
finally {
    $plainSecret = $null
}

# --- Stage 1: remove the schedule ---
$scheduleUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)/schedules/$ScheduleId?api-version=$ApiVersion"
Remove-IfExists -Uri $scheduleUri -Token $token -Description "schedule '$ScheduleId'"

# --- Stage 2 (optional): remove every rule in the definition file ---
if ($RemoveRules) {
    $rulesBaseUri = "$endpoint/datagovernance/quality/business-domains/$($definition.businessDomainId)" +
    "/data-products/$($definition.dataProductId)/data-assets/$($definition.dataAssetId)/rules"
    $existingRules = Invoke-RestMethod -Method Get -Uri "$rulesBaseUri?api-version=$ApiVersion" -Headers @{ Authorization = "Bearer $token" }

    foreach ($ruleDef in $definition.rules) {
        $match = $existingRules | Where-Object { $_.name -eq $ruleDef.name } | Select-Object -First 1
        if (-not $match) {
            Write-Host "Rule '$($ruleDef.name)' not found - already removed or never created." -ForegroundColor Yellow
            continue
        }
        $ruleUri = "$rulesBaseUri/$($match.id)?api-version=$ApiVersion"
        Remove-IfExists -Uri $ruleUri -Token $token -Description "rule '$($ruleDef.name)' (id: $($match.id))"
    }
}
else {
    Write-Host "`nRules were left in place (score history and rule definitions still exist). Pass -RemoveRules to also delete them." -ForegroundColor Cyan
}
```

#### `rules/customer-master-data-quality-rules.json`

```json
{
  "_comment": "Example values below. businessDomainId/dataProductId/dataAssetId must be replaced with the real GUIDs of a governance domain, data product, and data asset that already exist in Unified Catalog (see README.md Section 3 - this scenario does not create them). This example targets the 'Customer' data asset used elsewhere in this repo: the Azure SQL customerdb.dbo.Customers table registered by scenarios/data-map/scan-azure-sql-and-classify/ and modeled as a glossary term in scenarios/unified-catalog/curate-business-glossary/, inside the same 'Customer Experience' governance domain.",
  "businessDomainId": "76be16f9-5cb3-4839-83d6-4e3829a8ab0c",
  "dataProductId": "2a1d2087-09e2-4ecf-817d-1f5bfcbc31bf",
  "dataAssetId": "fadb55b6-aa10-47d5-82c4-5e2723ba7869",
  "assetDisplayName": "Customer (customerdb.dbo.Customers)",
  "rules": [
    {
      "name": "Emptyblank_fields_CustomerId",
      "description": "CustomerId must never be null or blank - it is the primary key every downstream system joins on.",
      "type": "NotNull",
      "dimension": "Completeness",
      "typeProperties": {
        "column": { "type": "Column", "value": "CustomerId" }
      }
    },
    {
      "name": "Unique_values_CustomerId",
      "description": "CustomerId must be unique - a duplicate primary key indicates an upstream ingestion or key-generation defect.",
      "type": "Unique",
      "dimension": "Uniqueness",
      "typeProperties": {
        "column": { "type": "Column", "value": "CustomerId" }
      }
    },
    {
      "name": "Data_type_match_SignupDate",
      "description": "SignupDate must be a valid date - a value the scan engine cannot cast to the expected type is treated as a miscast row for scoring. See README.md Section 11 (VERIFY) for how the target type itself is selected via this rule's typeProperties.",
      "type": "TypeMatch",
      "dimension": "Conformity",
      "typeProperties": {
        "column": { "type": "Column", "value": "SignupDate" }
      }
    },
    {
      "name": "Duplicate_rows_FirstName_LastName_Email",
      "description": "The combination of FirstName, LastName, and Email should be unique per row - catches the same person entered as two different CustomerId records (a common MDM defect this rule is designed to surface, distinct from the CustomerId-uniqueness rule above).",
      "type": "Duplicate",
      "dimension": "Accuracy",
      "typeProperties": {
        "columns": [
          { "type": "Column", "value": "FirstName" },
          { "type": "Column", "value": "LastName" },
          { "type": "Column", "value": "Email" }
        ]
      }
    },
    {
      "name": "Custom_Email_format_valid",
      "description": "Email must match a basic local-part@domain shape. A stricter production regex should be substituted per the organization's actual email-validation standard - this is a starter pattern, not an RFC 5322-complete validator.",
      "type": "CustomTruth",
      "dimension": "Accuracy",
      "typeProperties": {
        "condition": "regexMatch(toString(Email), '^[^@\\\\s]+@[^@\\\\s]+\\\\.[^@\\\\s]+$')",
        "emptyCriteria": "Email IS NULL",
        "columns": [
          { "type": "Column", "value": "Email" }
        ]
      }
    }
  ]
}
```