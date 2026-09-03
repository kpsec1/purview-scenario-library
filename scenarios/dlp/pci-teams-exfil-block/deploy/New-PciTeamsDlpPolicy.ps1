#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys the "PCI DSS - Teams Card Data Exfiltration Block" DLP policy and its three rules.

.DESCRIPTION
    Creates (or, if already present, leaves untouched and reports) one Microsoft Purview DLP
    policy scoped to Microsoft Teams chat and channel messages, with three rules:
      0. PCI-CardOps-Override-External  - Card Operations group, external share, block-with-justification-override
      1. PCI-Block-External-AllUsers    - everyone else, external share, hard block
      2. PCI-Audit-Internal-AllUsers    - everyone, internal share, audit only

    Idempotent: if a policy with the same -PolicyName already exists, the script reports its
    current state and takes no action, rather than erroring or creating a duplicate. Re-run with
    -Force to update rule properties on an existing policy to match this script's definition.

    Author-only reference code. This script never establishes its own connection to a tenant and
    never targets a live tenant by default (-Mode defaults to TestWithNotifications, a
    non-blocking simulation mode). Run Connect-IPPSSession yourself first (see
    docs/automation-surface.md §3 for the certificate app-only pattern), then call this script.

.PARAMETER PolicyName
    Name of the DLP policy. Policy names cannot be changed after creation (Microsoft Learn:
    dlp-create-policy-powerbi-cc-numbers) - choose deliberately.

.PARAMETER CardOpsGroupEmail
    SMTP address of the mail-enabled security group (or Microsoft 365 group) whose members get
    the block-with-justification-override path for external card-number shares. Must already
    exist in the tenant - this script does not create it.

.PARAMETER AdminNotificationEmail
    One or more admin/SOC mailbox addresses to receive incident reports and alerts.

.PARAMETER Mode
    DLP policy mode: Enable, Disable, TestWithNotifications, or TestWithoutNotifications
    (Set-DlpCompliancePolicy -Mode; Microsoft Learn: set-dlpcompliancepolicy). Defaults to
    TestWithNotifications so a first run never blocks live traffic.

.PARAMETER Force
    If the policy already exists, update its rules to match this script's definition instead of
    skipping. Rule updates go through Set-DlpComplianceRule -WhatIf when -WhatIf is passed.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every New-/Set-Dlp* call that would be
    made without calling any mutating cmdlet. Passed through to the underlying New-DlpCompliancePolicy
    / New-DlpComplianceRule calls as well, so no policy or rule object is created during a
    -WhatIf run.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./New-PciTeamsDlpPolicy.ps1 -CardOpsGroupEmail 'card-ops@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -WhatIf

    Dry-run: shows exactly what would be created, changes nothing.

.EXAMPLE
    ./New-PciTeamsDlpPolicy.ps1 -CardOpsGroupEmail 'card-ops@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications

    Deploys in simulation mode: policy tips and notifications fire, nothing is blocked yet.

.EXAMPLE
    ./New-PciTeamsDlpPolicy.ps1 -CardOpsGroupEmail 'card-ops@contoso.com' `
        -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force

    Deploys (or updates) the policy in full enforcement mode.

.NOTES
    VERIFY before enforcing in production: run the functional tests in README.md §7 to confirm
    -BlockAccess $true fully blocks message delivery for a TeamsLocation-scoped rule in this
    tenant. Microsoft's DLP policy reference documents "Restrict access or encrypt the content in
    Microsoft 365 locations" as the one supported action category for Teams, and BlockAccess is
    the same underlying flag used for that category on Exchange/SharePoint/OneDrive/Teams, but no
    Teams-specific worked example is published as of this writing.

    Sources (Microsoft Learn, verify before production use):
    - New-DlpCompliancePolicy / New-DlpComplianceRule reference:
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule
    - Set-DlpCompliancePolicy -Mode values: https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy
    - DLP and Microsoft Teams (locations, licensing, scoping): https://learn.microsoft.com/purview/dlp-microsoft-teams
    - Credit Card Number SIT definition: https://learn.microsoft.com/purview/sit-defn-credit-card-number
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyName = 'PCI DSS - Teams Card Data Exfiltration Block',

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$CardOpsGroupEmail,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdminNotificationEmail,

    [Parameter()]
    [ValidateSet('Enable', 'Disable', 'TestWithNotifications', 'TestWithoutNotifications')]
    [string]$Mode = 'TestWithNotifications',

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

$ruleNameOverride = 'PCI-CardOps-Override-External'
$ruleNameBlockExternal = 'PCI-Block-External-AllUsers'
$ruleNameAuditInternal = 'PCI-Audit-Internal-AllUsers'
$creditCardSit = @{ Name = 'Credit Card Number' }

$existingPolicy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy -and -not $Force) {
    Write-Host "Policy '$PolicyName' already exists (Mode: $($existingPolicy.Mode)). No changes made. Pass -Force to reconcile rules to this script's definition." -ForegroundColor Yellow
    return
}

if (-not $existingPolicy) {
    if ($PSCmdlet.ShouldProcess($PolicyName, 'New-DlpCompliancePolicy (TeamsLocation All)')) {
        New-DlpCompliancePolicy -Name $PolicyName `
            -TeamsLocation 'All' `
            -Mode $Mode `
            -Comment 'PCI-DSS control: blocks/audits Credit Card Number SIT in Teams chat and channel messages. Deployed by scenarios/dlp/pci-teams-exfil-block. Owner: Security & Compliance team.' `
            -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created DLP policy '$PolicyName' (Mode: $Mode)." -ForegroundColor Green
}
else {
    Write-Host "Policy '$PolicyName' exists - reconciling rules (-Force)." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($PolicyName, "Set-DlpCompliancePolicy -Mode $Mode")) {
        Set-DlpCompliancePolicy -Identity $PolicyName -Mode $Mode -WhatIf:$WhatIfPreference
    }
}

# --- Rule 0: Card Operations override path (external share, block-with-justification) ---
$rule0 = Get-DlpComplianceRule -Identity $ruleNameOverride -ErrorAction SilentlyContinue
$rule0Params = @{
    Name                            = $ruleNameOverride
    Policy                          = $PolicyName
    Priority                        = 0
    FromMemberOf                    = $CardOpsGroupEmail
    AccessScope                     = 'NotInOrganization'
    ContentContainsSensitiveInformation = @($creditCardSit)
    BlockAccess                     = $true
    NotifyAllowOverride             = @('WithJustification')
    NotifyUser                      = @('LastModifier') + $AdminNotificationEmail
    NotifyPolicyTipCustomText       = 'This message contains a full card number and is going to someone outside the organization. As Card Operations, you may override with a documented business justification; all overrides are logged and reviewed.'
    GenerateAlert                   = $AdminNotificationEmail
    GenerateIncidentReport          = $AdminNotificationEmail
    ReportSeverityLevel             = 'High'
    StopPolicyProcessing            = $true
}
if (-not $rule0) {
    if ($PSCmdlet.ShouldProcess($ruleNameOverride, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule0Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameOverride'." -ForegroundColor Green
}
elseif ($Force) {
    $rule0Params.Remove('Policy') | Out-Null
    $rule0Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameOverride, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameOverride @rule0Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameOverride'." -ForegroundColor Green
}

# --- Rule 1: hard block for everyone else sharing externally ---
$rule1 = Get-DlpComplianceRule -Identity $ruleNameBlockExternal -ErrorAction SilentlyContinue
$rule1Params = @{
    Name                            = $ruleNameBlockExternal
    Policy                          = $PolicyName
    Priority                        = 1
    ExceptIfFromMemberOf            = $CardOpsGroupEmail
    AccessScope                     = 'NotInOrganization'
    ContentContainsSensitiveInformation = @($creditCardSit)
    BlockAccess                     = $true
    NotifyUser                      = @('LastModifier') + $AdminNotificationEmail
    NotifyPolicyTipCustomText       = 'This message was blocked because it contains a full card number and was addressed to someone outside the organization. This is a PCI-DSS control - contact the Security team if you have a legitimate business need.'
    GenerateAlert                   = $AdminNotificationEmail
    GenerateIncidentReport          = $AdminNotificationEmail
    ReportSeverityLevel             = 'High'
    StopPolicyProcessing            = $true
}
if (-not $rule1) {
    if ($PSCmdlet.ShouldProcess($ruleNameBlockExternal, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule1Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameBlockExternal'." -ForegroundColor Green
}
elseif ($Force) {
    $rule1Params.Remove('Policy') | Out-Null
    $rule1Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameBlockExternal, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameBlockExternal @rule1Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameBlockExternal'." -ForegroundColor Green
}

# --- Rule 2: audit-only for internal card-number shares (anything rules 0/1 didn't stop-process) ---
$rule2 = Get-DlpComplianceRule -Identity $ruleNameAuditInternal -ErrorAction SilentlyContinue
$rule2Params = @{
    Name                            = $ruleNameAuditInternal
    Policy                          = $PolicyName
    Priority                        = 2
    ContentContainsSensitiveInformation = @($creditCardSit)
    BlockAccess                     = $false
    GenerateAlert                   = $AdminNotificationEmail
    GenerateIncidentReport          = $AdminNotificationEmail
    ReportSeverityLevel             = 'Low'
}
if (-not $rule2) {
    if ($PSCmdlet.ShouldProcess($ruleNameAuditInternal, 'New-DlpComplianceRule')) {
        New-DlpComplianceRule @rule2Params -WhatIf:$WhatIfPreference | Out-Null
    }
    Write-Host "Created rule '$ruleNameAuditInternal'." -ForegroundColor Green
}
elseif ($Force) {
    $rule2Params.Remove('Policy') | Out-Null
    $rule2Params.Remove('Name') | Out-Null
    if ($PSCmdlet.ShouldProcess($ruleNameAuditInternal, 'Set-DlpComplianceRule')) {
        Set-DlpComplianceRule -Identity $ruleNameAuditInternal @rule2Params -WhatIf:$WhatIfPreference
    }
    Write-Host "Updated rule '$ruleNameAuditInternal'." -ForegroundColor Green
}

Write-Host "`nDone. Policy sync to the Teams service can take up to ~1 hour (Microsoft Learn: dlp-microsoft-teams). Run validate/Test-PciTeamsDlpPolicy.ps1 to verify the deployed configuration." -ForegroundColor Cyan
