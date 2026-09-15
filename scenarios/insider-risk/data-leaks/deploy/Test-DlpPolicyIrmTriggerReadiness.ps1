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
         OneDriveLocation). Teams, Endpoint DLP, on-premises scanner, Power BI, and third-party
         app locations are NOT supported workloads for this indicator - a policy scoped ONLY to
         one of those generates DLP alerts that this Insider Risk Management template will never
         see, regardless of severity.
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
    Grounded in Microsoft Learn via WebSearch only in this build - direct fetch of
    learn.microsoft.com (and every other external URL attempted, not Microsoft-specific) returned
    EGRESS_BLOCKED from this session's network environment. Re-verify against a direct Learn fetch
    or the live portal before a customer-facing commitment:
    - Configure policy indicators in Insider Risk Management - "Data loss prevention (DLP) alerts
      indicators", supported workloads (Exchange Online, SharePoint Online, OneDrive for
      Business): https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#data-loss-prevention-alerts-indicators
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

    VERIFY (portal, at deploy time): whether a policy that ALSO includes an unsupported workload
    (e.g. TeamsLocation) alongside a supported one still has its supported-workload rules' High
    severity alerts processed correctly - not stated either way by Microsoft in this build's
    WebSearch-only grounding. This script WARNs on the presence of an unsupported workload rather
    than treating it as an automatic FAIL, since the supported-workload locations are still
    present and (per the documentation found) the restriction is described at the indicator/
    workload level, not stated as a whole-policy exclusion.

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
            HighSeverityRules   = @()
            Ready               = $false
        }
        continue
    }

    $supportedFound = @($supportedWorkloadProperties | Where-Object { $policy.$_ -and @($policy.$_).Count -gt 0 })
    $unsupportedFound = @($unsupportedWorkloadProperties | Where-Object { $policy.$_ -and @($policy.$_).Count -gt 0 })

    $rules = @(Get-DlpComplianceRule -Policy $name -ErrorAction SilentlyContinue)
    $matchingSeverityRules = @($rules | Where-Object { $_.ReportSeverityLevel -eq $RequiredSeverity })

    [PSCustomObject]@{
        PolicyName           = $name
        Found                = $true
        Mode                 = $policy.Mode
        SupportedWorkloads   = $supportedFound
        UnsupportedWorkloads = $unsupportedFound
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
        Write-Host "  [WARN] Also scoped to unsupported workload(s) $($r.UnsupportedWorkloads -join ', ') on the SAME policy - whether this affects the supported workload's own alert processing is unconfirmed (see .NOTES VERIFY)." -ForegroundColor Yellow
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
