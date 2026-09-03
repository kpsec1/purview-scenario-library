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
