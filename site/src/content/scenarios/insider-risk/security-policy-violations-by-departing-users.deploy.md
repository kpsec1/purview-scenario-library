---
part: "deploy"
parent: "insider-risk/security-policy-violations-by-departing-users"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-SecurityViolationInsiderRiskAlerts.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
<#
.SYNOPSIS
    Pulls Insider Risk Management alerts from the "Security policy violations by departing users"
    template via the Microsoft Graph security API, joined - best effort - to the underlying
    Microsoft Defender for Endpoint alert that triggered them.

.DESCRIPTION
    Read-only. Never modifies alert state (no triage/assignment/resolution - same grounded
    boundary as scenarios/insider-risk/departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1).

    This template's distinguishing feature versus the sibling Data theft template is that its
    triggering/scoring signal is itself a Graph Security API alert - a Microsoft Defender for
    Endpoint alert (detectionSource = microsoftDefenderForEndpoint) - which Microsoft's Defender
    XDR alert-correlation engine CAN group into the same incident as the resulting Insider Risk
    Management alert (detectionSource = microsoftInsiderRiskManagement). See design.md §2 goal 4/5
    and README.md §11 for the full grounding discussion. Where a Defender for Endpoint alert
    shares an IncidentId with an Insider-Risk-Management-sourced alert in the pulled batch, this
    script attaches that Defender alert's Title/Categories/MitreTechniques/Determination to the
    exported record as RelatedDefenderAlerts, giving an investigator the specific security
    violation (which malware, which disabled control) without a second portal lookup.

    IMPORTANT - this join is BEST EFFORT, not guaranteed:
    - Microsoft documents that alerts are aggregated into a shared incident "with the same attack
      techniques or the same attacker," and separately documents that Insider Risk Management
      alert data reaches the same Defender XDR unified alert queue - but no worked example
      confirming this SPECIFIC pairing (a Defender for Endpoint alert and the Insider-Risk-
      Management-generated alert it triggered sharing one IncidentId) was found during this
      build. VERIFY in a pilot tenant before relying on RelatedDefenderAlerts being populated.
      When no correlated alert is found, the IRM alert is still exported (with an empty
      RelatedDefenderAlerts array) - this script never drops an IRM alert for lack of a join.
    - The server-side alerts_v2 $filter does not support detectionSource or incidentId
      (Microsoft Learn: security-list-alerts_v2) - both the detectionSource split and the
      IncidentId join happen CLIENT-SIDE in PowerShell after a broader date/severity-scoped pull,
      the same pattern the sibling scenario's export script already uses for detectionSource
      alone.
    - This script CANNOT tell which specific "Security policy violations..." template (this one,
      the base template, ...by priority users, or ...by risky users) produced a given exported
      IRM alert if more than one is deployed in the same tenant. The alert resource's
      AlertPolicyId field is populated "when there's a specific policy that generated the alert,"
      but Microsoft doesn't document a way to map that GUID back to a named Purview policy via
      any API. AlertPolicyId is included in the export as raw, unmapped data for the operator's
      own manual cross-reference - see README.md §11.

    Follows the app-only, certificate-based auth pattern that is the default for every script in
    this library (docs/automation-surface.md §3) - run Connect-MgGraph yourself first, then call
    this script.

.PARAMETER SinceDateTime
    Only return alerts with createdDateTime at or after this value (UTC). Defaults to 7 days
    before now.

.PARAMETER Severity
    Optional server-side filter on alert severity (informational, low, medium, high). Omit to
    return all severities. Applies to the initial broad pull only - both detectionSource values
    are always pulled together so the IncidentId join has candidate Defender for Endpoint alerts
    to match against.

.PARAMETER OutputPath
    If specified, writes the joined export as JSON to this path in addition to returning it on
    the pipeline.

.PARAMETER WhatIf
    This script makes no mutating calls, so -WhatIf has nothing destructive to preview - accepted
    for interface consistency with the rest of this repo's deploy/ scripts; prints the query plan
    without calling Graph.

.EXAMPLE
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
    ./Export-SecurityViolationInsiderRiskAlerts.ps1 -WhatIf

    Dry run: shows the query plan, calls nothing.

.EXAMPLE
    ./Export-SecurityViolationInsiderRiskAlerts.ps1 -SinceDateTime (Get-Date).AddDays(-1) -OutputPath ./security-violation-alerts.json

    Pulls the last 24 hours of Insider-Risk-Management-sourced alerts, joined where possible to
    their correlated Defender for Endpoint alert, and writes them to JSON for a SIEM connector.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - alert resource type (AlertPolicyId, IncidentId, DetectionSource properties):
      https://learn.microsoft.com/graph/api/resources/security-alert
    - detectionSource enum values (microsoftInsiderRiskManagement, microsoftDefenderForEndpoint):
      https://learn.microsoft.com/graph/api/resources/security-detectionsource
    - List alerts_v2 (supported $filter properties - detectionSource/incidentId NOT among them):
      https://learn.microsoft.com/graph/api/security-list-alerts_v2
    - Integrate insider risk management data with Microsoft Graph security API (alerts
      aggregated by attack technique/attacker into a shared incident):
      https://learn.microsoft.com/defender-xdr/irm-investigate-alerts-defender
    - SecurityAlert.Read.All permission:
      https://learn.microsoft.com/graph/permissions-reference

    VERIFY before relying on this in production: whether a Defender for Endpoint alert and the
    Insider Risk Management alert it triggers under this template actually share one IncidentId -
    not confirmed by a worked example in Microsoft Learn during this build. See README.md §11 and
    design.md §2 goal 5 / §5.
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
$irmSource = 'microsoftInsiderRiskManagement'
$mdeSource = 'microsoftDefenderForEndpoint'

function Assert-MgGraphSession {
    if (-not (Get-MgContext)) {
        throw 'No Microsoft Graph session found. Run Connect-MgGraph first (see docs/automation-surface.md §3 for the certificate app-only pattern).'
    }
}

$sinceIso = $SinceDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
$filterClauses = @("createdDateTime ge $sinceIso")
if ($Severity) { $filterClauses += "severity eq '$Severity'" }
$serverFilter = $filterClauses -join ' and '

Write-Host "Query plan: server-side `$filter = '$serverFilter'; client-side split on DetectionSource ('$irmSource' / '$mdeSource'); best-effort join by IncidentId (VERIFY - see .NOTES)." -ForegroundColor Cyan
if ($OutputPath) { Write-Host "Output: $OutputPath" -ForegroundColor Cyan }

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Graph call made.' -ForegroundColor Yellow
    return
}

Assert-MgGraphSession

$allAlerts = Get-MgSecurityAlertV2 -Filter $serverFilter -All
# @(...) on both: Where-Object unwraps a single-match result to a bare scalar (no .Count
# property), which would break every .Count reference against these two variables below.
$irmAlerts = @($allAlerts | Where-Object { $_.DetectionSource -eq $irmSource })
$mdeAlerts = @($allAlerts | Where-Object { $_.DetectionSource -eq $mdeSource })

Write-Host "Retrieved $($allAlerts.Count) alert(s) matching the server-side filter; $($irmAlerts.Count) Insider-Risk-Management-sourced, $($mdeAlerts.Count) Defender-for-Endpoint-sourced (join candidates)." -ForegroundColor Green

# Group the MDE alerts pulled in this same batch by IncidentId for an O(1) lookup during the join.
# A Defender for Endpoint alert whose correlating IRM alert falls outside this run's -SinceDateTime
# window (e.g. the MDE alert is older than the daily IRM-import lag) will not be found here - this
# is a known, disclosed limitation of a stateless, single-window export, not a bug.
$mdeByIncident = @{}
foreach ($mdeAlert in $mdeAlerts) {
    if ([string]::IsNullOrEmpty($mdeAlert.IncidentId)) { continue }
    if (-not $mdeByIncident.ContainsKey($mdeAlert.IncidentId)) {
        $mdeByIncident[$mdeAlert.IncidentId] = [System.Collections.Generic.List[object]]::new()
    }
    $mdeByIncident[$mdeAlert.IncidentId].Add($mdeAlert)
}

$joinedCount = 0
# @(...) around the whole loop forces array semantics for $export even when $irmAlerts has zero
# or exactly one element - PowerShell would otherwise assign $null (zero iterations) or a bare
# scalar (one iteration) instead of an array, breaking the $export.Count reference below and
# producing a JSON scalar/null instead of a JSON array on export.
$export = @(foreach ($irmAlert in $irmAlerts) {
    # Guard the lookup BEFORE piping: piping a $null hashtable-miss into ForEach-Object still
    # runs the block once with $_ = $null (PowerShell treats a single $null as one pipeline
    # object, not zero), which would otherwise produce one spurious all-null "related" entry.
    # The @(...) wrap around the ForEach-Object result separately guards the .Count check just
    # below it - PowerShell unwraps a single-object pipeline result to a bare scalar, which has
    # no .Count property and would make that check silently evaluate to $false either way. Same
    # class of gotcha the sibling scenario's chunk-building code documents.
    $related = @()
    if (-not [string]::IsNullOrEmpty($irmAlert.IncidentId) -and $mdeByIncident.ContainsKey($irmAlert.IncidentId)) {
        $related = @($mdeByIncident[$irmAlert.IncidentId] | ForEach-Object {
            [PSCustomObject]@{
                Id               = $_.Id
                Title            = $_.Title
                Categories       = $_.Categories
                MitreTechniques  = $_.MitreTechniques
                Determination    = $_.Determination
                Severity         = $_.Severity
                CreatedDateTime  = $_.CreatedDateTime
            }
        })
        if ($related.Count -gt 0) { $joinedCount++ }
    }

    [PSCustomObject]@{
        Id                    = $irmAlert.Id
        Title                 = $irmAlert.Title
        Severity              = $irmAlert.Severity
        Status                = $irmAlert.Status
        Classification        = $irmAlert.Classification
        Determination         = $irmAlert.Determination
        CreatedDateTime       = $irmAlert.CreatedDateTime
        LastUpdateDateTime    = $irmAlert.LastUpdateDateTime
        DetectionSource       = $irmAlert.DetectionSource
        ServiceSource         = $irmAlert.ServiceSource
        IncidentId            = $irmAlert.IncidentId
        IncidentWebUrl        = $irmAlert.IncidentWebUrl
        AlertPolicyId         = $irmAlert.AlertPolicyId
        AssignedTo            = $irmAlert.AssignedTo
        Description           = $irmAlert.Description
        RelatedDefenderAlerts = @($related)
    }
})

Write-Host "Joined $joinedCount of $($irmAlerts.Count) Insider-Risk-Management alert(s) to at least one correlated Defender for Endpoint alert by IncidentId. Unjoined alerts are still exported - see .NOTES on why a join can legitimately miss." -ForegroundColor $(if ($joinedCount -eq $irmAlerts.Count -or $irmAlerts.Count -eq 0) { 'Green' } else { 'Yellow' })

if ($OutputPath) {
    $export | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $OutputPath -Encoding utf8
    Write-Host "Wrote $($export.Count) alert(s) to '$OutputPath'." -ForegroundColor Cyan
}

$export
```

#### `policy/security-policy-violations-departing-users-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Security Policy Violations by Departing Users",
  "policyTemplate": "Security policy violations by departing users",
  "templateStatus": "Microsoft-labeled PREVIEW as of this writing - re-verify GA status before a customer-facing commitment. README.md §1/§11.",
  "scope": {
    "users": "Same population as departing-employee-data-theft's policy, or a subset",
    "maxUsersInScope": 15000,
    "note": "Microsoft-fixed limit for this specific template - distinct from, and larger than, the sibling Data theft template's 20,000-user limit. Do not conflate the two."
  },
  "triggeringEvents": [
    {
      "type": "HR connector - employee resignation",
      "source": "REUSED from ../../departing-employee-data-theft/deploy/policy/departing-employee-policy-manifest.json's HR connector - not a second connector object",
      "optional": true,
      "fields": ["UserPrincipalName", "ResignationDate", "LastWorkingDate"]
    },
    {
      "type": "User account deleted from Microsoft Entra ID",
      "source": "Built-in Entra signal - enable explicitly in the policy workflow",
      "optional": true,
      "note": "Unlike the sibling Data theft template, Microsoft's own prerequisite table lists BOTH triggers as optional for this template, without naming either as the documented primary. README.md §5 Step 5 / §6."
    }
  ],
  "indicators": {
    "microsoftDefenderForEndpointIndicators": {
      "category": "Microsoft Defender for Endpoint indicators (preview)",
      "note": "Individual indicator names are not enumerated in Microsoft's own documentation as of this build (only the category-level description: 'unapproved or malicious software installation or bypassing security controls'). VERIFY the exact selectable indicator toggles against the live policy-creation workflow at deploy time. README.md §5 Step 5 / §11."
    },
    "otherIndicatorCategoriesSelectable": "VERIFY: whether Office/Device/Cumulative-exfiltration indicator categories are also selectable for this specific template in the live portal - not confirmed by Microsoft Learn during this build. Do not assume either way."
  },
  "prerequisites": {
    "defenderForEndpointSubscription": "Active Microsoft Defender for Endpoint subscription (Plan not specified by Microsoft's own prerequisite table - VERIFY Plan 1 vs Plan 2 sufficiency for this template's specific indicators). README.md §3.",
    "defenderForEndpointAdvancedFeature": "'Share endpoint alerts with Microsoft Compliance Center' toggled ON in the Microsoft Defender portal (Settings > Endpoints > Advanced features). Portal-only - no API. README.md §5 Step 2.",
    "intelligentDetectionsTriageStatuses": "At least one Defender for Endpoint alert triage status (Unknown/New/In progress/Resolved) selected in Purview Settings > Insider Risk Management > Intelligent detections. Portal-only - no API. README.md §5 Step 3."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as the sibling scenario."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-09"
}
```