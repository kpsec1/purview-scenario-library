---
part: "deploy"
parent: "dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-ExchangePiiEncryptModeAuditCompanion.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Adds the "PII-Exchange-Audit-Encrypt-Exception" audit rule to an existing
    scenarios/dlp/exchange-pii-exfil-block/ policy.

.DESCRIPTION
    Closes the Red-Team-flagged gap in exchange-pii-exfil-block/README.md §11: when that scenario
    runs -Action Encrypt with a non-empty -ExceptionGroupEmail, members of that group are silently
    excluded from the encrypt rule (ExceptIfFromMemberOf) with no override concept for a
    non-halting action - their matching external mail is delivered in cleartext with zero alert,
    incident report, or override record.

    This script adds ONE additional, low-severity, non-blocking rule to the PARENT scenario's
    EXISTING policy, scoped to exactly that population (FromMemberOf the exception group,
    AccessScope NotInOrganization, same SIT conditions):
      - BlockAccess = $false (never restricts delivery - see design.md §5, non-goals)
      - GenerateAlert / GenerateIncidentReport at Low severity

    This does NOT create a policy, and it does NOT modify any of the parent scenario's own three
    rules. It requires the parent policy to already exist and fails clearly if it does not.

    Idempotent: if the rule already exists, reports its current state and takes no action unless
    -Force is passed, which reconciles the rule's properties (including -Priority) to this
    script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant. Run
    Connect-IPPSSession yourself first (see docs/automation-surface.md §3), then call this script.

.PARAMETER PolicyName
    Name of the PARENT scenario's existing DLP policy. Must match the -PolicyName used when
    scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 was run.

.PARAMETER ExceptionGroupEmail
    SMTP address of the same business-exception group configured on the parent scenario via its
    own -ExceptionGroupEmail. Mandatory here (unlike the parent scenario, where it is optional) -
    this companion has no purpose without one.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive the alert and incident report. Should
    normally match the parent scenario's own -AdminNotificationEmail so this event lands in the
    same triage queue.

.PARAMETER Priority
    Optional explicit rule priority. If omitted, the script computes one greater than the highest
    Priority currently present among the target policy's rules (see design.md §4) rather than
    relying on portal/creation-order defaults, so repeated deploys are idempotent.

.PARAMETER ReportSeverityLevel
    Severity recorded on this rule's alert/incident report (Low, Medium, or High -
    New-DlpComplianceRule's -ReportSeverityLevel parameter). Defaults to 'Low', matching this
    policy's PII-Exchange-Audit-Internal convention (expected, approved-exception traffic, not a
    novel threat signal). Raise to 'High' if the nominated exception group includes privileged or
    high-risk mailboxes where a compromised account sending this traffic should not be triaged at
    the same priority as routine internal audit noise - see README.md §11 (Blue Team finding).

.PARAMETER Force
    If the rule already exists, update it (including re-computing -Priority) to match this
    script's definition instead of skipping.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-DlpComplianceRule call that
    would be made without calling any mutating cmdlet.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-ExchangePiiEncryptModeAuditCompanion.ps1 `
        -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-ExchangePiiEncryptModeAuditCompanion.ps1 `
        -ExceptionGroupEmail 'hr-benefits-ops@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com'

    Adds the audit rule to the default parent policy at the default Low severity.

.EXAMPLE
    ./New-ExchangePiiEncryptModeAuditCompanion.ps1 `
        -ExceptionGroupEmail 'exec-assistants@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -ReportSeverityLevel High

    Same, but for an exception group considered high-risk enough that a match shouldn't be
    triaged at routine-audit priority.

.NOTES
    VERIFY before relying on this in production: run the functional test in README.md §7 to
    confirm the deployed rule generates an alert/incident report for exception-group traffic in
    your tenant - every individual parameter is grounded from official Microsoft Learn references,
    but no worked example combines them for this exact narrow population.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpComplianceRule / Get-DlpComplianceRule / Set-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancerule
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule
    - Data Loss Prevention policy reference (rule priority / multi-rule-match behavior):
      https://learn.microsoft.com/purview/dlp-policy-reference#rules
    - Credit Card Number SIT definition: https://learn.microsoft.com/purview/sit-defn-credit-card-number
    - U.S. Social Security Number (SSN) SIT definition: https://learn.microsoft.com/purview/sit-defn-us-social-security-number
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PII DLP - Exchange External Send Control',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$ExceptionGroupEmail,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [Nullable[int]]$Priority,

    [Parameter()]
    [ValidateSet('Low', 'Medium', 'High')]
    [string]$ReportSeverityLevel = 'Low',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-IppsSession {
    # Get-DlpCompliancePolicy is only exported after a successful Connect-IPPSSession; its absence means the caller never connected.
    if (-not (Get-Command Get-DlpCompliancePolicy -ErrorAction SilentlyContinue)) {
        throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
    }
}

Assert-IppsSession

$ruleName = 'PII-Exchange-Audit-Encrypt-Exception'
$protectRuleName = 'PII-Exchange-Protect-External'
$piiSits = @(
    @{ name = 'U.S. Social Security Number (SSN)'; mincount = '1' },
    @{ name = 'Credit Card Number'; mincount = '1' }
)

$parentPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
if (-not $parentPolicy) {
    throw "Parent policy '$PolicyName' was not found. This companion requires scenarios/dlp/exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1 to have already been run with a matching -PolicyName."
}

$parentRules = Get-DlpComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue

# Drift check (warn only - see design.md §4): confirm the parent's Protect rule already excludes
# this same exception group, which is the precondition for this companion's target population
# (Encrypt-mode, exception-group, external-recipient) to be otherwise-unmatched by any other rule.
$protectRule = $parentRules | Where-Object { $_.Name -eq $protectRuleName }
if (-not $protectRule) {
    Write-Warning "Parent rule '$protectRuleName' was not found on policy '$PolicyName'. This companion's target population may not actually be excluded from another rule - confirm the parent scenario's own configuration before relying on this companion's alerts as the only signal for exception-group traffic."
}
elseif ($protectRule.ExceptIfFromMemberOf -notcontains $ExceptionGroupEmail) {
    Write-Warning "Parent rule '$protectRuleName' does not currently exclude '$ExceptionGroupEmail' via ExceptIfFromMemberOf. Either the parent scenario was deployed with a different -ExceptionGroupEmail, or it is running -Action Block (where the exclusion lives on a different rule). Confirm -ExceptionGroupEmail here matches the parent scenario's live configuration before deploying."
}

# Compute an explicit, deterministic priority (design.md §4) unless the caller supplied one.
if ($null -eq $Priority) {
    $otherRules = $parentRules | Where-Object { $_.Name -ne $ruleName }
    $highestPriority = if ($otherRules) { ($otherRules | Measure-Object -Property Priority -Maximum).Maximum } else { -1 }
    $Priority = $highestPriority + 1
}
else {
    $collision = $parentRules | Where-Object { $_.Name -ne $ruleName -and $_.Priority -eq $Priority }
    if ($collision) {
        throw "Explicit -Priority $Priority collides with existing rule '$($collision.Name)' on policy '$PolicyName'. Pass a different -Priority or omit it to let this script compute a safe one."
    }
}

$ruleParams = @{
    Name                                 = $ruleName
    Policy                               = $PolicyName
    Priority                             = $Priority
    FromMemberOf                         = $ExceptionGroupEmail
    AccessScope                          = 'NotInOrganization'
    ContentContainsSensitiveInformation  = $piiSits
    BlockAccess                          = $false
    GenerateAlert                        = $AdminNotificationEmail
    GenerateIncidentReport               = $AdminNotificationEmail
    ReportSeverityLevel                  = $ReportSeverityLevel
    Comment                              = "Visibility-only companion to $PolicyName's Encrypt-mode exception-group exclusion. Deployed by scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion. Never blocks or encrypts - see that scenario's README.md §11."
}

$existingRule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue

if (-not $existingRule) {
    if ($PSCmdlet.ShouldProcess($ruleName, "New-DlpComplianceRule (Policy: $PolicyName, Priority: $Priority)")) {
        New-DlpComplianceRule @ruleParams -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleName' on policy '$PolicyName' (Priority: $Priority)." -ForegroundColor Green
}
elseif ($Force) {
    $ruleParams.Remove('Policy') | Out-Null
    $ruleParams.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleName, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleName @ruleParams -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleName' on policy '$PolicyName' (Priority: $Priority)." -ForegroundColor Green
}
else {
    Write-Host "Rule '$ruleName' already exists on policy '$PolicyName' (Priority: $($existingRule.Priority)). No changes made. Pass -Force to reconcile." -ForegroundColor Yellow
}

Write-Host "`nDone. Run validate/Test-ExchangePiiEncryptModeAuditCompanion.ps1 to verify the deployed configuration." -ForegroundColor Cyan
```

#### `Remove-ExchangePiiEncryptModeAuditCompanion.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Removes the "PII-Exchange-Audit-Encrypt-Exception" rule added by
    New-ExchangePiiEncryptModeAuditCompanion.ps1.

.DESCRIPTION
    Deletes only this companion's own rule via Remove-DlpComplianceRule. Never touches the parent
    scenario's policy or its own three rules (PII-Exchange-Override-External,
    PII-Exchange-Protect-External, PII-Exchange-Audit-Internal).

    Idempotent: if the rule does not exist, reports that and exits cleanly rather than erroring.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run - reports the removal that would happen without
    calling Remove-DlpComplianceRule.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Remove-ExchangePiiEncryptModeAuditCompanion.ps1 -WhatIf

.EXAMPLE
    ./Remove-ExchangePiiEncryptModeAuditCompanion.ps1
    # Permanently removes the rule. There is no "disable" state for a single rule (unlike a
    # policy's Mode) - see rollback.md.

.NOTES
    Sources: https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = 'Stop'

$ruleName = 'PII-Exchange-Audit-Encrypt-Exception'

if (-not (Get-Command Get-DlpComplianceRule -ErrorAction SilentlyContinue)) {
    throw 'No Security & Compliance PowerShell session found. Run Connect-IPPSSession first (see docs/automation-surface.md).'
}

$rule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue

if (-not $rule) {
    Write-Host "Rule '$ruleName' does not exist. Nothing to roll back." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($ruleName, 'Remove-DlpComplianceRule (permanent - this rule has no disabled state)')) {
    Remove-DlpComplianceRule -Identity $ruleName -Confirm:$false -WhatIf:$WhatIfPreference
}
Write-Host "Removed rule '$ruleName'. The parent policy and its other rules are unaffected." -ForegroundColor Green
```