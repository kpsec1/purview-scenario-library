---
part: "deploy"
parent: "insider-risk/security-policy-violations-by-risky-users"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `policy/security-policy-violations-risky-users-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Security Policy Violations by Risky Users",
  "policyTemplate": "Security policy violations by risky users",
  "templateStatus": "Microsoft-labeled PREVIEW as of this writing (same family-wide status as the base/departing-users/priority-users siblings) - re-verify GA status before a customer-facing commitment. README.md §1/§11.",
  "scope": {
    "users": "A plain Entra security group (or groups) resolved via ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 -MaxUsers 7500 (reused unmodified) - this template has no priority-user-group requirement, unlike the …by priority users sibling",
    "maxUsersInScope": 7500,
    "note": "Microsoft-fixed limit for this specific template - distinct from the base/priority-users siblings' 1,000 and the departing-users sibling's 15,000. Do not conflate the four. Cumulative tenant-wide across every policy built from this exact template."
  },
  "triggeringEvents": [
    {
      "type": "HR connector - job level change / performance review / performance improvement plan indicators",
      "source": "deploy/Send-HrRiskIndicatorRecord.ps1 uploading to a DEDICATED HR connector (own JobId, own app registration) - not the departing-employee-data-theft sibling's Resignation-scoped connector",
      "requiredEither": true,
      "note": "At least one of this trigger OR the Communication Compliance trigger below is required (Microsoft's prerequisite table states 'AND/OR', not both mandatory). Both together is also supported and recommended for broader coverage - README.md §5 Step 5."
    },
    {
      "type": "Communication Compliance risk-signal integration",
      "source": "Portal-only option selected in the IRM policy-creation workflow itself - auto-creates a dedicated 'Detect inappropriate text' Communication Compliance policy. No PowerShell surface exists for Communication Compliance policy creation/management (Microsoft Learn, explicit statement).",
      "requiredEither": true,
      "note": "Threat/Harassment/Discrimination trainable classifiers; 5+ risky messages in 24h brings a user in-scope; up to 48h latency. Microsoft's own documentation uses two different names for the auto-created policy in the same article ('Insider risk trigger - (date created)' in one paragraph, 'Risky user in messages - (date created)' in the next) - disclosed as an unresolved documentation inconsistency, not resolved by guessing which is correct. README.md §5 Step 6 / §11."
    }
  ],
  "indicators": {
    "microsoftDefenderForEndpointIndicators": {
      "category": "Microsoft Defender for Endpoint indicators (preview)",
      "note": "Same indicator category as every sibling in this template family - individual indicator names are not enumerated in Microsoft's own documentation as of this build. VERIFY the exact selectable indicator toggles against the live policy-creation workflow at deploy time. README.md §5 Step 7 / §11."
    },
    "communicationComplianceIndicators": "NOT selectable for this template per Microsoft's own indicator-category documentation - the CC integration option above is a TRIGGER mechanism only for this specific template, unlike the sibling 'Data leaks by risky users' template, which additionally lists CC content indicators as selectable scoring indicators. Do not conflate the two 'risky users' templates. design.md §2 goal 3."
  },
  "prerequisites": {
    "hrConnectorOrCommunicationCompliance": "At least one of: Microsoft 365 HR connector configured for risk indicators (Job level change / Performance review / Performance improvement plan), OR Communication Compliance integration with a dedicated risky-user policy. Both is supported. README.md §3.",
    "defenderForEndpointSubscription": "Active Microsoft Defender for Endpoint subscription (Plan not specified by Microsoft's own prerequisite table - same open Plan 1/Plan 2 VERIFY as every sibling). README.md §3.",
    "defenderForEndpointAdvancedFeature": "'Share endpoint alerts with Microsoft Compliance Center' toggled ON in the Microsoft Defender portal (Settings > Endpoints > Advanced features). Portal-only - no API. README.md §5 Step 3."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every sibling scenario."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```

#### `Send-HrRiskIndicatorRecord.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Uploads a job-level-change / performance-review / performance-improvement-plan CSV to a
    Microsoft Purview HR connector, feeding the "Security policy violations by risky users" (and
    "Data leaks by risky users") Insider Risk Management policy templates' HR-connector trigger.

.DESCRIPTION
    This template's HR data requirement is materially different from the departing-employee-
    data-theft/…-by-departing-users siblings' single-scenario Resignation CSV
    (deploy/Send-HrTerminationRecord.ps1, reused unmodified by this repo elsewhere): Microsoft
    documents THREE separate HR scenario types for this template - Job level change, Performance
    review, and Performance improvement plan - any one of which alone, or in combination,
    satisfies the "HR connector configured for risk indicators" prerequisite (README.md §3;
    Microsoft Learn: import-hr-data, "Policy template" table). Reusing the resignation-only
    sibling script would silently misrepresent this template's actual HR data shape - this script
    exists because that generalization is genuinely new, not a copy of the sibling with a renamed
    parameter (design.md §2 goal 1).

    Wraps the same documented HR-connector ingestion pattern as
    ../../departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1 (Microsoft Learn:
    import-hr-data, "Step 4: Run the sample script to upload your HR data") - same OAuth 2.0
    client-credentials token acquisition, same fixed ingestion resource ID, same
    webhook.ingestion.office.com multipart/form-data upload, same 500-data-row-per-file chunking
    limit - generalized for a multi-scenario CSV instead of a single fixed schema. It does not call
    any Purview/Exchange/Graph PowerShell module cmdlet; the HR connector ingestion surface is a
    plain HTTPS webhook, not a PowerShell module.

    Flow:
      1. Validate the CSV has a scenario-identifier column (-ScenarioColumnName, default
         'HRScenario') plus 'UserPrincipalName' and 'EffectiveDate' - the three columns every one
         of Microsoft's three risk-indicator HR scenarios shares, per Microsoft's own worked
         multi-scenario CSV example (import-hr-data, "Configure a single CSV file for multiple HR
         data types"). Every other column (OldLevel/NewLevel for Job level change; Remarks/Rating
         for Performance review; the performance-improvement-plan columns - see .NOTES on a
         documentation inconsistency there) is optional per Microsoft's own per-scenario column
         tables and is passed through unvalidated.
      2. Warn (not fail) on any row whose scenario-identifier value isn't in -ValidScenarioValues.
         Microsoft's own documentation states scenario-identifier VALUES, like column NAMES, are
         examples mapped to Microsoft's fixed internal scenario types when the connector is
         created in the portal (import-hr-data, "Add the HRScenario column to a CSV file..." -
         "You also map the values used for the data type column when you set up the connector") -
         so an unrecognized value here is very likely an upstream typo worth flagging, but this
         script cannot know the actual tenant-configured mapping and must not hard-fail on it.
      3. Acquire an OAuth 2.0 client-credentials access token (identical resource ID and endpoint
         to the sibling script - this is a template-family-wide constant, not connector-specific).
      4. Split into chunks of at most 500 data rows (Microsoft's documented per-file ingestion
         limit) and POST each as multipart/form-data to the ingestion webhook, bearer-authenticated,
         over TLS 1.2.

    Idempotency note: identical, undocumented gap to the sibling script - Microsoft does not
    document re-ingestion/de-duplication behavior for an unchanged row re-uploaded on a later
    scheduled run. VERIFY in a pilot tenant before relying on repeat runs being a no-op. Re-running
    this script is always SAFE in the sense that it never deletes or mutates existing tenant state.

    This script never embeds a client secret. Pass it as a SecureString - never hard-code it or
    check it into source control.

    Author-only reference code. This script makes an outbound HTTPS call to
    webhook.ingestion.office.com whenever it runs WITHOUT -WhatIf. Always run with -WhatIf first.

.PARAMETER TenantId
    Microsoft Entra tenant ID (directory ID) - see docs/automation-surface.md for how to find it.

.PARAMETER AppId
    Application (client) ID of the Microsoft Entra app registered for THIS HR connector. Design
    decision (design.md §6): this scenario provisions its OWN app registration and its OWN HR
    connector object - distinct from the departing-employee-data-theft sibling's Resignation-scoped
    connector - rather than assuming an existing single-scenario connector can be edited in the
    portal to add these three new scenario types (Microsoft documents the Edit action as changing
    "the Azure App ID or the column header names," not as adding scenarios a connector wasn't
    created with - VERIFY at deploy time if reuse is preferred over provisioning a second
    connector). Reuse
    ../../departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1 unmodified with a
    different -DisplayName to create it - see README.md §5 Step 2.

.PARAMETER AppSecret
    Client secret for the app above, as a SecureString. Never pass in plaintext; never store in
    this repo or in an unencrypted file.

.PARAMETER JobId
    This connector's Job ID, generated when the connector is created in the Purview portal
    (Microsoft Learn: import-hr-data, Step 3). Not the departing-employee-data-theft sibling's
    JobId - see .PARAMETER AppId.

.PARAMETER CsvPath
    Path to the risk-indicator CSV. Required columns: UserPrincipalName, EffectiveDate, and the
    scenario-identifier column named by -ScenarioColumnName (default 'HRScenario'). See
    README.md §6 for the full per-scenario column reference and the multi-scenario worked example.

.PARAMETER ScenarioColumnName
    Name of the column identifying which HR scenario each row represents. Defaults to 'HRScenario'
    (Microsoft's own example name) - override if this connector was mapped to a different column
    name in the portal (Microsoft documents the name itself as arbitrary/operator-chosen).

.PARAMETER ValidScenarioValues
    The set of scenario-identifier values this script warns against if a row's value falls outside
    it. Defaults to Microsoft's own three worked-example values for this template ('Job level
    change', 'Performance review', 'Performance improvement plan'). Override if this connector was
    mapped to different literal values in the portal - see .DESCRIPTION step 2.

.PARAMETER ChunkSize
    Maximum data rows per uploaded chunk. Defaults to 500, the documented per-file ingestion limit.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Validates the CSV schema, computes the chunk plan,
    reports per-scenario row counts and any unrecognized scenario values, and reports exactly what
    would be uploaded - acquires no token and makes no HTTP call to the ingestion endpoint.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'HR connector app secret'
    ./Send-HrRiskIndicatorRecord.ps1 -TenantId $TenantId -AppId $AppId -AppSecret $secret `
        -JobId $JobId -CsvPath './risk_indicators.csv' -WhatIf

    Dry run: validates the CSV, reports per-scenario row counts and the upload plan, sends nothing.

.EXAMPLE
    ./Send-HrRiskIndicatorRecord.ps1 -TenantId $TenantId -AppId $AppId -AppSecret $secret `
        -JobId $JobId -CsvPath './risk_indicators.csv'

    Uploads the CSV to the HR connector, chunked at 500 rows per call.

.NOTES
    Grounded in Microsoft Learn (verify before production use - Microsoft describes the underlying
    sample script as provided AS IS, unsupported under any standard support program):
    - Set up a connector to import HR data (three risk-indicator CSV schemas, the HRScenario
      multi-scenario pattern, webhook domain, client-credentials auth, 500-row-per-file limit):
      https://learn.microsoft.com/purview/import-hr-data
    - Learn about Insider Risk Management policy templates - "Security policy violations by risky
      users" prerequisites (HR connector risk indicators AND/OR Communication Compliance
      integration, AND active Defender for Endpoint subscription):
      https://learn.microsoft.com/purview/insider-risk-management-policy-templates#security-policy-violations-by-risky-users
    - Sample script source (reference only - this script is an independent, parameterized
      reimplementation for a different, multi-scenario schema, not a copy):
      https://github.com/microsoft/m365-compliance-connector-sample-scripts

    DOCUMENTATION INCONSISTENCY, disclosed rather than silently resolved: Microsoft's own
    "CSV file for performance improvement plan data" section shows a worked example with the
    header `UserPrincipalName,EffectiveDate,ImprovementRemarks,PerformanceRating`, but the column
    description table immediately below it labels the same two optional columns "Remarks" and
    "Rating" (identical wording to the separate Performance review section above it, apparently
    not updated for this section). Microsoft's own text states column names are "not required
    parameters, but only examples" and are mapped to data types when the connector is created in
    the portal - so this inconsistency does not block this script (it validates only
    UserPrincipalName/EffectiveDate/the scenario column, and passes every other column through
    unvalidated), but confirm the actual expected column names against the live portal's file-
    mapping step at connector-creation time rather than assuming either worked example is
    authoritative. See README.md §11.

    VERIFY before go-live: (1) re-ingestion/de-duplication behavior for an unchanged row re-
    uploaded on a subsequent scheduled run - not documented by Microsoft as of this writing; (2)
    whether an existing single-scenario HR connector can be edited in the portal to add these three
    scenario types, versus requiring a new connector object as this script assumes - see .PARAMETER
    AppId and design.md §6.

    Requires PowerShell 7.0+: uses Invoke-RestMethod's -Form parameter for multipart/form-data
    upload, unavailable in Windows PowerShell 5.1.
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
    [string]$ScenarioColumnName = 'HRScenario',

    [Parameter()]
    [string[]]$ValidScenarioValues = @('Job level change', 'Performance review', 'Performance improvement plan'),

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$ChunkSize = 500
)

$ErrorActionPreference = 'Stop'

# Fixed per Microsoft's documented HR connector ingestion flow (import-hr-data) - a template-
# family-wide constant, not connector- or scenario-specific, so not exposed as a parameter.
# Identical values to ../../departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1.
$tokenEndpointTemplate = 'https://login.windows.net/{0}/oauth2/token?api-version=1.0'
$ingestionResource = 'https://microsoft.onmicrosoft.com/86dfdabb-5089-4a0c-880a-cfa5a790c5b1'
$webhookBaseUrl = 'https://webhook.ingestion.office.com/api/signals'

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
$requiredColumns = @('UserPrincipalName', 'EffectiveDate', $ScenarioColumnName)
$missingColumns = $requiredColumns | Where-Object { $_ -notin $actualColumns }
if ($missingColumns) {
    throw "CsvPath '$CsvPath' is missing required column(s): $($missingColumns -join ', '). Required: $($requiredColumns -join ', ')."
}

# --- Per-scenario row counts and unrecognized-value warning (non-fatal - see .NOTES) ---
$scenarioGroups = $rows | Group-Object -Property $ScenarioColumnName
foreach ($group in $scenarioGroups) {
    $recognized = $group.Name -in $ValidScenarioValues
    $marker = if ($recognized) { '' } else { ' [UNRECOGNIZED - confirm this maps correctly in the portal-configured connector, or pass -ValidScenarioValues to silence this warning if it is intentional]' }
    $color = if ($recognized) { 'Cyan' } else { 'Yellow' }
    Write-Host "  $($group.Count) row(s) with $ScenarioColumnName = '$($group.Name)'$marker" -ForegroundColor $color
}

# --- Compute the chunk plan (data rows only; header is re-added per chunk on upload) ---
$chunks = @(for ($i = 0; $i -lt $rows.Count; $i += $ChunkSize) {
    , $rows[$i..([Math]::Min($i + $ChunkSize - 1, $rows.Count - 1))]
})
Write-Host "CSV '$CsvPath': $($rows.Count) risk-indicator record(s), $($chunks.Count) chunk(s) of up to $ChunkSize row(s), target JobId '$JobId'." -ForegroundColor Cyan

if ($WhatIfPreference) {
    for ($c = 0; $c -lt $chunks.Count; $c++) {
        Write-Host "  [WhatIf] Chunk $($c + 1)/$($chunks.Count): $($chunks[$c].Count) row(s) -> POST $webhookBaseUrl`?jobid=$JobId" -ForegroundColor Yellow
    }
    Write-Host 'WhatIf: no token acquired, no HTTP call made.' -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess("HR connector JobId '$JobId'", "Upload $($rows.Count) risk-indicator record(s) in $($chunks.Count) chunk(s)")) {
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

Write-Host "`nUpload complete: $($rows.Count) risk-indicator record(s) submitted to JobId '$JobId' in $($chunks.Count) chunk(s)." -ForegroundColor Cyan
Write-Host 'Verify ingestion in the Purview portal: Settings > Data connectors > (this HR connector) > Download log.' -ForegroundColor Cyan
```