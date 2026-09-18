---
part: "deploy"
parent: "insider-risk/data-leaks"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `policy/data-leaks-policy-manifest.json`

```json
{
  "_comment": "REFERENCE MANIFEST, NOT AN API PAYLOAD. Microsoft Purview Insider Risk Management has no documented PowerShell or Graph write API for policy authoring as of this writing (docs/automation-surface.md §6; design.md §4). No script in this scenario's deploy/ folder reads or applies this file - it is a structured, versioned source of truth for the person completing the portal steps in README.md §5, so the deployed policy can be diffed against intent during review instead of relying on institutional memory of what was clicked.",
  "policyName": "Data Leaks",
  "policyTemplate": "Data leaks",
  "templateStatus": "Not found to be labeled preview in this build's WebSearch-only grounding - re-verify GA/preview status against the live portal before a customer-facing commitment. README.md §1/§3.",
  "scope": {
    "users": "A plain Entra security group (or groups), resolved via ../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 (reused unmodified) - this template has no HR-connector, priority-user-group, or employment-stressor requirement (design.md §2 goal 1).",
    "maxUsersInScope": "VERIFY (portal or a direct Microsoft Learn fetch at deploy time) - this build's WebSearch-only grounding could not retrieve the base 'Data leaks' template's specific row from the Limits in Insider Risk Management page. DO NOT reuse the Security policy violations template's 1,000 or the risky/priority-users family's 7,500 - those are documented for DIFFERENT templates. design.md §2 goal 7; README.md §6.",
    "note": "Cumulative tenant-wide across every policy built from THIS exact template, per the same limit-tracking model every other template in this library documents."
  },
  "triggeringEvents": [
    {
      "type": "User matches a data loss prevention (DLP) policy",
      "primary": true,
      "source": "One or more EXISTING Purview DLP policies, checked for readiness by deploy/Test-DlpPolicyIrmTriggerReadiness.ps1 (new script, this fragment's own contribution) before being added via Purview portal -> Insider Risk Management -> Settings -> Policy indicators -> DLP alerts indicators -> Add DLP policies.",
      "requirements": "Policy must be scoped to Exchange Online, SharePoint Online, and/or OneDrive for Business (the only supported workloads for this indicator) and have at least one rule at ReportSeverityLevel = High. Up to 20 DLP policies may be assigned to one Data-leaks-template IRM policy.",
      "criticalGotcha": "DOUBLE-SCOPING REQUIREMENT (design.md §2 goal 3): a user's alert is only processed if that user is in scope of BOTH the DLP policy's own rule scope AND this IRM policy's own 'Users and groups' scope. Matching either alone is not sufficient - this is not automatically cross-checked by any tool; confirm manually per README.md §5 Step 3."
    },
    {
      "type": "User performs an exfiltration activity",
      "primary": false,
      "source": "Portal-only, built-in indicator thresholds (default or custom) - documented Microsoft-supported alternative, NOT given a full worked implementation in this fragment (design.md §3/§6/§7). Use if no qualifying DLP policy exists yet.",
      "requirements": "Select one or more built-in exfiltration indicators (SharePoint Online downloads, file/folder sharing, printing files, copying data to personal cloud messaging/storage services) and choose default or custom thresholds."
    }
  ],
  "indicators": {
    "officeIndicators": {
      "category": "Office indicators (built-in) - SharePoint Online downloads/syncing, sharing internal files/folders externally, printing files, copying data to personal cloud storage/messaging services",
      "selected": true,
      "note": "Primary scoring indicator category for this template. Requires no additional connector. README.md §5 Step 5/§6."
    },
    "cumulativeExfiltrationDetection": {
      "selected": true,
      "note": "ENABLED BY DEFAULT for this template per Microsoft Learn (already grounded in data-leaks-by-risky-users/README.md ref [6], which names this template explicitly) - confirm actually selected at policy creation rather than assumed."
    },
    "communicationComplianceScoringIndicators": {
      "category": "Optional - Sending financial regulatory text that might be risky / Sending inappropriate images / Sending inappropriate content / Sending messages that contain specific sensitive info types",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Documented as selectable for this template specifically (also Data theft, Data leaks by risky users, Data leaks by priority users) - a SCORING indicator, not a trigger; this scenario uses no Communication Compliance TRIGGER at all (design.md §2 goal 1)."
    },
    "generativeAiIndicators": {
      "category": "Optional - Prompt Shields, Protected material detection",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Documented as selectable for this template (also Data leaks by risky users, Data leaks by priority users, Risky AI usage)."
    },
    "cloudIndicators": {
      "category": "Optional - Cloud storage (Box, Dropbox, Google Drive) / Cloud service (Amazon S3, Azure)",
      "selected": "operator choice - not selected by default in this manifest",
      "note": "Microsoft's per-template description text names 'cloud indicators' explicitly for the base Data leaks template (unlike data-leaks-by-risky-users, where this remains an open VERIFY) - confirmed applicable here. Requires Defender for Cloud Apps connections + pay-as-you-go billing."
    }
  },
  "prerequisites": {
    "dlpPolicy": "At least one existing Purview DLP policy scoped to Exchange/SharePoint/OneDrive with a High-severity rule, IF using the DLP-policy triggering event. Checked by deploy/Test-DlpPolicyIrmTriggerReadiness.ps1.",
    "defenderForEndpoint": "NOT required for this template.",
    "hrConnectorOrCommunicationComplianceTrigger": "NOT required for this template - the defining simplification versus the risky/priority-users family (design.md §2 goal 1).",
    "payAsYouGoBilling": "Required ONLY if the optional cloud storage/cloud service indicator category is used."
  },
  "alertReview": {
    "pseudonymizeUserNames": true,
    "note": "Repo default - do not disable pseudonymization without an explicit, documented privacy/legal decision. Same as every IRM scenario in this library."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-15"
}
```

#### `Test-DlpPolicyIrmTriggerReadiness.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Checks whether one or more EXISTING Microsoft Purview DLP policies qualify as a triggering
    event for an Insider Risk Management "Data leaks" (base template) policy, before the operator
    wires them up in the portal.

.DESCRIPTION
    Read-only. Never creates, modifies, or deletes any DLP policy or rule - this script only
    reads and reports. The DLP policy/policies this scenario points at are assumed to already
    exist, independently owned and tuned elsewhere in the tenant (or by another scenario in this
    library, e.g. scenarios/dlp/exchange-pii-exfil-block) - design.md §2 goal 5/§7.

    For each -DlpPolicyName supplied, this script checks:
      1. The policy exists.
      2. The policy is scoped to at least one of the three workloads the "Data loss prevention
         (DLP) alerts" Insider Risk Management indicator actually supports - Exchange Online,
         SharePoint Online, or OneDrive for Business (ExchangeLocation / SharePointLocation /
         OneDriveLocation). Teams, Endpoint DLP, on-premises scanner, Power BI, third-party
         app locations, and Microsoft 365 Copilot are NOT supported workloads for this
         indicator - a policy scoped ONLY to one of those generates DLP alerts that this Insider
         Risk Management template will never see, regardless of severity. Confirmed directly
         against Microsoft Learn during this fragment's grounding pass - see .NOTES; the
         Copilot exclusion is checked separately (step 2a) since Copilot-scoped policies use the
         EnforcementPlanes property, not one of the *Location array properties the other
         unsupported workloads use.
      2a. (WARN, not FAIL) The policy's EnforcementPlanes does not include 'CopilotExperiences' -
          a policy scoped to the Microsoft 365 Copilot location uses a materially different
          scoping mechanism (-Locations plus -EnforcementPlanes CopilotExperiences, not a
          Microsoft365CopilotLocation-style array parameter) and is explicitly excluded from this
          indicator regardless of any other workload also scoped on the same policy - see .NOTES.
      3. At least one rule on the policy has ReportSeverityLevel = High - this template's own
         triggering event is explicitly "a DLP policy configured for High severity alerts"; a
         policy with only Low/Medium-severity rules never fires this trigger at all.
      4. (Across all policies supplied) the combined count does not exceed Microsoft's documented
         ceiling of 20 DLP policies assignable as a triggering event on one Data-leaks-template
         IRM policy.
      5. (WARN, not FAIL) The policy's Mode is 'Enable', not a Test mode. Whether a policy left in
         TestWithNotifications/TestWithoutNotifications mode still generates the High-severity
         alerts this indicator consumes is UNCONFIRMED in this build's grounding - see .NOTES.

    WHAT THIS SCRIPT CANNOT CHECK (disclosed, not silently skipped - see README.md §5 Step 3/§6/
    §11 and design.md §2 goal 3): Microsoft documents that a user's DLP-policy-triggered alert is
    only processed by this template if that user is in scope of BOTH the DLP policy's own rule
    scope AND the separate Insider Risk Management policy's own "Users and groups" scope - neither
    alone is sufficient. This script reports each policy's own location/rule scope so the operator
    can manually cross-reference it against the IRM policy's scope (resolved separately via
    ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1) - no
    Graph/PowerShell surface exists to compare the two scopes programmatically, and this script
    does not attempt to fabricate one.

    Follows the app-only, certificate-based auth pattern that is the default for every script in
    this library (docs/automation-surface.md §3) - run Connect-IPPSSession yourself first, then
    call this script.

.PARAMETER DlpPolicyName
    One or more existing DLP policy names (Identity) to check. Order does not matter; the
    20-policy ceiling check is applied to the combined count.

.PARAMETER RequiredSeverity
    The severity level this template's DLP-alerts trigger requires at least one rule to carry.
    Defaults to 'High' - Microsoft's own documented requirement for this triggering event. Do not
    lower this to make a warning disappear; lowering it does not change what the live product
    actually requires.

.PARAMETER WhatIf
    This script makes no mutating calls, so -WhatIf has nothing destructive to preview - accepted
    for interface consistency with the rest of this repo's deploy/ scripts; prints the query plan
    without calling Security & Compliance PowerShell.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control' -WhatIf

    Dry run: shows the query plan, calls nothing.

.EXAMPLE
    ./Test-DlpPolicyIrmTriggerReadiness.ps1 -DlpPolicyName 'PII DLP - Exchange External Send Control', 'SharePoint PII Guardrail'

    Checks both named policies against the supported-workload, High-severity-rule, and
    combined-20-policy-ceiling requirements, and prints each policy's own scope for the operator
    to cross-reference against the IRM policy's own "Users and groups" scope.

.NOTES
    Originally grounded in Microsoft Learn via WebSearch only (direct fetch of learn.microsoft.com
    returned EGRESS_BLOCKED from that build's network environment). A follow-up fragment
    re-confirmed the facts below via a direct Microsoft Learn MCP fetch (this session's network
    environment did not block it):
    - Configure policy indicators in Insider Risk Management - "Supported DLP workloads": the
      High Severity DLP Alert indicator supports only Exchange Online, SharePoint Online, and
      OneDrive for Business. Endpoint DLP, Microsoft Teams, Microsoft 365 Copilot, on-premises
      repositories, and Power BI are explicitly listed as NOT currently supported -
      https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#supported-dlp-workloads
    - The same article, immediately following the unsupported-workload list, states verbatim:
      "If your DLP policy spans multiple workloads (for example, Exchange + Endpoint), only the
      alerts from the supported workloads (Exchange Online, SharePoint Online, and OneDrive for
      Business) are processed" - CONFIRMED, resolving the mixed-workload VERIFY this script
      previously carried (see the removed VERIFY immediately below this note in prior revisions):
      a policy scoped to both a supported and an unsupported workload still has its
      supported-workload rules' alerts processed correctly. The WARN this script prints for that
      combination is now purely informational (confirmed-safe), not an open question.
    - Learn about Insider Risk Management policy templates - Data leaks template: "configure at
      least one Microsoft Purview Data Loss Prevention (DLP) policy... to receive insider risk
      alerts for High Severity DLP policy alerts", up to 20 DLP policies assignable, and the
      dual-scope requirement ("Only users included in Insider Risk Management policies using the
      Data leaks template have high severity DLP policy alerts processed, and only users included
      in a rule for a high severity DLP alert are analyzed by the Insider Risk Management policy
      for consideration"): https://learn.microsoft.com/purview/insider-risk-management-policy-templates
    - Get started with Insider Risk Management - Step 6, "Triggers for this policy" ("User matches
      a data loss prevention (DLP) policy" vs. "User performs an exfiltration activity"):
      https://learn.microsoft.com/purview/insider-risk-management-configure
    - New-DlpCompliancePolicy / Set-DlpCompliancePolicy reference - `-EnforcementPlanes`
      (MultiValuedProperty) and `-Locations` (generic JSON string keyed by a location GUID) are
      the parameters Microsoft's own worked example uses to scope a DLP policy to the Microsoft
      365 Copilot location (`-EnforcementPlanes @('CopilotExperiences')`) - there is no
      Microsoft365CopilotLocation-style array parameter analogous to ExchangeLocation/
      TeamsLocation/etc.:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy,
      https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about

    VERIFY (pilot tenant, at deploy time): whether Get-DlpCompliancePolicy's returned object
    actually exposes EnforcementPlanes as a readable property with the same values New-/
    Set-DlpCompliancePolicy accept for it - this fragment's grounding confirmed EnforcementPlanes
    as a New-/Set- (write) parameter but did not find a dedicated Get-DlpCompliancePolicy
    reference page confirming its exact shape on read. Step 2a below is a WARN, not a FAIL, for
    this reason: if the property is absent or empty on a genuinely Copilot-scoped policy, this
    script's Copilot check silently no-ops rather than falsely passing a policy it could not
    actually classify.

    VERIFY (pilot tenant, before relying on a Test-mode policy as this trigger's source): whether
    a DLP policy in Mode = TestWithNotifications or TestWithoutNotifications still generates the
    High-severity alerts the "Data loss prevention (DLP) alerts" IRM indicator consumes, or
    whether Mode must be Enable for those alerts to reach Insider Risk Management at all. This
    build's WebSearch-only grounding found no Microsoft statement either way on this specific
    interaction. Found during this scenario's own four-lens review (reviews.md, Red Team/Blue Team
    findings) - flagged here as a WARN rather than a FAIL because test-mode DLP policies are
    documented to still generate incident reports/alerts for their own purpose (previewing policy
    impact before enforcement), which is suggestive but not a confirmed answer for THIS specific
    indicator's behavior.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$DlpPolicyName,

    [Parameter()]
    [ValidateSet('Low', 'Medium', 'High')]
    [string]$RequiredSeverity = 'High'
)

$ErrorActionPreference = 'Stop'
$maxDlpPoliciesPerIrmPolicy = 20
$supportedWorkloadProperties = @('ExchangeLocation', 'SharePointLocation', 'OneDriveLocation')
$unsupportedWorkloadProperties = @('TeamsLocation', 'EndpointDlpLocation', 'OnPremisesScannerDlpLocation', 'ThirdPartyAppDlpLocation', 'PowerBIDlpLocation')
$copilotEnforcementPlaneValue = 'CopilotExperiences'

function Assert-IppsSession {
    if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md §3).'
    }
}

Write-Host "Query plan: check $($DlpPolicyName.Count) DLP polic$(if ($DlpPolicyName.Count -eq 1) { 'y' } else { 'ies' }) [$($DlpPolicyName -join ', ')] for supported-workload scope, at least one rule with ReportSeverityLevel=$RequiredSeverity, and the combined $maxDlpPoliciesPerIrmPolicy-policy ceiling." -ForegroundColor Cyan

if ($WhatIfPreference) {
    Write-Host 'WhatIf: no Security & Compliance PowerShell call made.' -ForegroundColor Yellow
    return
}

Assert-IppsSession

$results = foreach ($name in $DlpPolicyName) {
    $policy = Get-DlpCompliancePolicy -Identity $name -ErrorAction SilentlyContinue
    if (-not $policy) {
        [PSCustomObject]@{
            PolicyName          = $name
            Found               = $false
            Mode                = $null
            SupportedWorkloads  = @()
            UnsupportedWorkloads = @()
            CopilotScoped       = $false
            HighSeverityRules   = @()
            Ready               = $false
        }
        continue
    }

    $supportedFound = @($supportedWorkloadProperties | Where-Object { $policy.$_ -and @($policy.$_).Count -gt 0 })
    $unsupportedFound = @($unsupportedWorkloadProperties | Where-Object { $policy.$_ -and @($policy.$_).Count -gt 0 })
    $copilotScoped = @($policy.EnforcementPlanes) -contains $copilotEnforcementPlaneValue

    $rules = @(Get-DlpComplianceRule -Policy $name -ErrorAction SilentlyContinue)
    $matchingSeverityRules = @($rules | Where-Object { $_.ReportSeverityLevel -eq $RequiredSeverity })

    [PSCustomObject]@{
        PolicyName           = $name
        Found                = $true
        Mode                 = $policy.Mode
        SupportedWorkloads   = $supportedFound
        UnsupportedWorkloads = $unsupportedFound
        CopilotScoped        = $copilotScoped
        # @(...) forces array semantics even when exactly one or zero rules match - PowerShell
        # would otherwise unwrap a single-element result to a bare string or $null, breaking the
        # .Count check below (same gotcha documented in
        # ../../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1).
        HighSeverityRules     = @($matchingSeverityRules.Name)
        Ready                 = ($supportedFound.Count -gt 0 -and $matchingSeverityRules.Count -gt 0)
    }
}

Write-Host ''
foreach ($r in $results) {
    if (-not $r.Found) {
        Write-Host "[FAIL] '$($r.PolicyName)' - policy not found." -ForegroundColor Red
        continue
    }

    if ($r.SupportedWorkloads.Count -eq 0) {
        Write-Host "[FAIL] '$($r.PolicyName)' - no supported workload (ExchangeLocation/SharePointLocation/OneDriveLocation) is scoped. This policy's DLP alerts will never be seen by the Data-leaks DLP-alerts indicator." -ForegroundColor Red
    }
    else {
        Write-Host "[PASS] '$($r.PolicyName)' - supported workload(s): $($r.SupportedWorkloads -join ', ')." -ForegroundColor Green
    }

    if ($r.UnsupportedWorkloads.Count -gt 0) {
        Write-Host "  [WARN] Also scoped to unsupported workload(s) $($r.UnsupportedWorkloads -join ', ') on the SAME policy - CONFIRMED safe: Microsoft documents that only the supported-workload rules' alerts are processed by this indicator when a policy spans both (see .NOTES)." -ForegroundColor Yellow
    }

    if ($r.CopilotScoped) {
        Write-Host "  [WARN] Policy is also scoped to the Microsoft 365 Copilot location (EnforcementPlanes contains 'CopilotExperiences') - Copilot is explicitly NOT a supported workload for this indicator; this policy's supported-workload rules are still processed, but any rule that ONLY covers Copilot interactions will never trigger this indicator (see .NOTES)." -ForegroundColor Yellow
    }

    if ($r.Mode -ne 'Enable') {
        Write-Host "  [WARN] Policy Mode is '$($r.Mode)', not 'Enable' - whether a DLP policy running in TestWithNotifications/TestWithoutNotifications mode still generates the High-severity alerts this indicator consumes is UNCONFIRMED in this build's grounding (see .NOTES VERIFY). This library's own DLP scenarios commonly default new policies to TestWithNotifications for a first, safe rollout - a policy left in test mode indefinitely may silently produce no IRM trigger signal even though every other check here passes." -ForegroundColor Yellow
    }

    if ($r.HighSeverityRules.Count -eq 0) {
        Write-Host "  [FAIL] No rule on this policy has ReportSeverityLevel=$RequiredSeverity - the DLP-policy triggering event requires at least one." -ForegroundColor Red
    }
    else {
        Write-Host "  [PASS] $($r.HighSeverityRules.Count) rule(s) at $RequiredSeverity severity: $($r.HighSeverityRules -join ', ')." -ForegroundColor Green
    }

    Write-Host "  Cross-reference reminder: confirm this policy's own scope overlaps with the IRM policy's 'Users and groups' scope - both must include a given user for that user's alerts to be processed (design.md §2 goal 3)." -ForegroundColor Cyan
}

$foundCount = @($results | Where-Object { $_.Found }).Count
if ($foundCount -gt $maxDlpPoliciesPerIrmPolicy) {
    Write-Host "`n[FAIL] $foundCount polic$(if ($foundCount -eq 1) { 'y' } else { 'ies' }) supplied EXCEEDS Microsoft's documented $maxDlpPoliciesPerIrmPolicy-policy ceiling for a single Data-leaks-template IRM policy's triggering event." -ForegroundColor Red
}
else {
    Write-Host "`n$foundCount of $maxDlpPoliciesPerIrmPolicy allowed DLP polic$(if ($foundCount -eq 1) { 'y' } else { 'ies' }) used." -ForegroundColor Cyan
}

$readyCount = @($results | Where-Object { $_.Ready }).Count
Write-Host "$readyCount of $($DlpPolicyName.Count) polic$(if ($DlpPolicyName.Count -eq 1) { 'y' } else { 'ies' }) ready to use as a Data-leaks triggering event." -ForegroundColor $(if ($readyCount -eq $DlpPolicyName.Count) { 'Green' } else { 'Yellow' })

$results
```