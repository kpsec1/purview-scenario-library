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
