---
part: "deploy"
parent: "data-lifecycle-management/publish-labels-for-manual-application"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/publish-financial-records-label.sample.json`

```json
{
  "_comment": "Config for deploy/New-PublishRetentionLabelPolicy.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Publishes an EXISTING retention label to Exchange/SharePoint/OneDrive so finance and records users can manually apply it in Outlook/SharePoint/OneDrive. The label itself must already exist (create it first - e.g. scenarios/data-lifecycle-management/retention-labels-financial-records/). Read README.md Sections 2 and 11 before deploying.",
  "label": {
    "name": "Financial Records - 7yr Regulatory",
    "_labelNote": "Must be the Name of an existing retention label (New-ComplianceTag). This script never creates the label - it only publishes it. For a REGULATORY RECORD label, publishing is the ONLY supported distribution mechanism (auto-apply does not support regulatory records - README.md Section 2/11). For a plain record or standard label, publishing is a manual-apply complement to auto-apply, not a substitute."
  },
  "policy": {
    "name": "Publish Financial Records - Finance Locations",
    "comment": "Publishes the Financial Records regulatory label to finance locations so users can manually apply it to individual emails/documents.",
    "enabled": true,
    "sharePointLocation": ["https://contoso.sharepoint.com/sites/finance"],
    "exchangeLocation": ["Finance Team"],
    "oneDriveLocation": [],
    "modernGroupLocation": [],
    "_policyNote": "At least one location is required. exchangeLocation accepts a mailbox, mail-enabled security group, or distribution group name/email/GUID (e.g. a 'Finance Team' distribution group), or the literal value 'All'. modernGroupLocation publishes the label into a Microsoft 365 Group's connected SharePoint team site and Teams Files tab (not the group mailbox by email client - see README.md Section 11)."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-10"
}
```

#### `New-PublishRetentionLabelPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Publishes an EXISTING retention label to Exchange/SharePoint/OneDrive/Microsoft 365 Groups so
    admins and end users can manually apply it in Outlook, SharePoint, OneDrive, and Teams - using
    Security & Compliance PowerShell.

.DESCRIPTION
    Uses the Data Lifecycle Management / Records Management cmdlets in Security & Compliance
    PowerShell (automation surface 2 per docs/automation-surface.md):
      1. New-RetentionCompliancePolicy -> the label policy (locations)
      2. New-RetentionComplianceRule -PublishComplianceTag -> the rule that publishes the label

    This script never creates or edits the retention label itself (Get-ComplianceTag only) - the
    label must already exist. Create it first, e.g. via
    scenarios/data-lifecycle-management/retention-labels-financial-records/deploy/
    New-FinancialRecordsRetention.ps1.

    Why this scenario exists, and why it is not merely an "auto-apply alternative": Microsoft's
    auto-apply retention label policies (Set-/New-RetentionComplianceRule -ApplyComplianceTag) do
    NOT support labels that mark items as a REGULATORY RECORD - publishing is the only supported
    way to make a regulatory record label available to anyone. For a plain record or standard
    label, publishing is a manual-apply complement to auto-apply (precise, immediate, human-
    driven), not a substitute for it. See README.md Section 2 and the citations below.

    Idempotent: the policy and rule are located by name via Get-* before create; if present they
    are reported (not silently mutated - retention objects are high-consequence). Re-running is
    safe. -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements
    its own -DryRun that prints the intended cmdlets and runs none.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/publish-financial-records-label.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PublishRetentionLabelPolicy.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-PublishRetentionLabelPolicy.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-RetentionComplianceRule (-PublishComplianceTag; mandatory, mutually exclusive with
      -ApplyComplianceTag/-Name, no content-match condition):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - New-RetentionCompliancePolicy (locations: -ExchangeLocation/-SharePointLocation/
      -OneDriveLocation/-ModernGroupLocation; at least one required):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
    - Publish retention labels and apply them in apps (supported for ALL label configurations
      including regulatory records; publish timing; manual-apply UX per app):
      https://learn.microsoft.com/purview/create-apply-retention-labels
    - Automatically apply a retention label to retain or delete content ("This scenario isn't
      supported for regulatory records ... These scenarios require a published retention label
      policy."):
      https://learn.microsoft.com/purview/apply-retention-labels-automatically
    - Declare records by using retention labels ("... for labels that mark items as records (but
      not regulatory records), auto-apply those labels ..."):
      https://learn.microsoft.com/purview/declare-records
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/publish-financial-records-label.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue)) {
        throw "Retention cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}
function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'label', 'policy') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Publishing retention label '$($cfg.label.name)' via policy '$($cfg.policy.name)'." -ForegroundColor Cyan

# --- 0. The label must already exist. This script never creates or edits it. ---
$label = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if (-not $label) {
    throw "Retention label '$($cfg.label.name)' does not exist. Create it first (e.g. scenarios/data-lifecycle-management/retention-labels-financial-records/deploy/New-FinancialRecordsRetention.ps1), then re-run this script. This script only publishes an existing label - it does not create one."
}
if ($label.Regulatory -or $label.IsRegulatory) {
    Write-Host "  [label] '$($cfg.label.name)' is a REGULATORY RECORD. Publishing is the ONLY supported way to make this label available - auto-apply does not support regulatory records. See README.md Section 2." -ForegroundColor Yellow
}
elseif ($label.IsRecordLabel) {
    Write-Host "  [label] '$($cfg.label.name)' marks items as a record. Publishing here complements (does not replace) any auto-apply policy already using this label." -ForegroundColor DarkGreen
}
else {
    Write-Host "  [label] '$($cfg.label.name)' is a standard retention label." -ForegroundColor DarkGreen
}

# --- 1. Label policy (New-RetentionCompliancePolicy) ---
$existingPolicy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    $polParams = @{ Name = $cfg.policy.name }
    if ($null -ne $cfg.policy.enabled) { $polParams.Enabled = [bool]$cfg.policy.enabled }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }
    if ($cfg.policy.sharePointLocation -and @($cfg.policy.sharePointLocation).Count -gt 0) { $polParams.SharePointLocation = @($cfg.policy.sharePointLocation) }
    if ($cfg.policy.exchangeLocation -and @($cfg.policy.exchangeLocation).Count -gt 0) { $polParams.ExchangeLocation = @($cfg.policy.exchangeLocation) }
    if ($cfg.policy.oneDriveLocation -and @($cfg.policy.oneDriveLocation).Count -gt 0) { $polParams.OneDriveLocation = @($cfg.policy.oneDriveLocation) }
    if ($cfg.policy.modernGroupLocation -and @($cfg.policy.modernGroupLocation).Count -gt 0) { $polParams.ModernGroupLocation = @($cfg.policy.modernGroupLocation) }
    if (-not ($polParams.SharePointLocation -or $polParams.ExchangeLocation -or $polParams.OneDriveLocation -or $polParams.ModernGroupLocation)) {
        throw "policy needs at least one location (sharePointLocation / exchangeLocation / oneDriveLocation / modernGroupLocation)."
    }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' (publish label policy, locations set)" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 2. Publish rule (New-RetentionComplianceRule -PublishComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    $ruleParams = @{
        Policy              = $cfg.policy.name
        PublishComplianceTag = $cfg.label.name
    }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -PublishComplianceTag '$($cfg.label.name)'" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (publishes '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Publishing typically takes under a day for SharePoint/OneDrive and up to 7 days for Exchange (mailbox needs >= 10 MB). Validate with validate/Test-PublishRetentionLabelPolicy.ps1 and confirm the label appears in Outlook/SharePoint/OneDrive's label picker." -ForegroundColor Yellow
```

#### `Remove-PublishRetentionLabelPolicy.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the publish label policy: disables (and optionally deletes) the policy/rule that
    makes the label available for manual application. The retention LABEL itself is never touched.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the publish policy (Set-RetentionCompliancePolicy -Enabled $false) so
                 admins/users stop seeing the label as an option to apply going forward.
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    This script NEVER touches the retention label (no Remove-ComplianceTag call at all - unlike
    the auto-apply sibling's rollback script, this one has no -TryRemoveLabel option, because
    unpublishing is never a reason to consider deleting a label other scenarios or policies may
    still depend on). Content already manually labeled by a user keeps its label and retention -
    unpublishing only stops new manual applications; it never removes an existing label from
    content. For a record or regulatory record label, removing an already-applied label is
    further restricted or impossible regardless (see rollback.md).

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements
    -DryRun. Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to
    'config/publish-financial-records-label.sample.json'. Only policy.name is read here.

.PARAMETER Delete
    Delete the publish policy and rule (not just disable).

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-PublishRetentionLabelPolicy.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy; "Updating retention labels
    and their policies" / "Locking the policy to prevent changes" sections of
    https://learn.microsoft.com/purview/create-apply-retention-labels
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/publish-financial-records-label.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.policy.name) { throw "policy.name is required." }

function Invoke-Scc {
    param([string]$Describe, [scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return }
    Write-Host "  $Describe" -ForegroundColor Green
    & $Action
}

$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($policy) {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false }
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops NEW manual applications)." -ForegroundColor Yellow
    if ($Delete) {
        Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)'" `
            -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false }
        Write-Host "  [delete] policy '$($cfg.policy.name)' removed (rule removed with it)." -ForegroundColor Red
    }
}
else { Write-Host "  [policy] '$($cfg.policy.name)' not found." -ForegroundColor DarkGray }

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Content already labeled by a user keeps its label and retention - disabling/deleting the publish policy only stops FUTURE manual applications. The retention label itself was never touched by this script. See rollback.md." -ForegroundColor Yellow
```