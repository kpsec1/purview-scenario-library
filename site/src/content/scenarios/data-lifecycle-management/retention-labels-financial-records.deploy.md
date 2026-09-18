---
part: "deploy"
parent: "data-lifecycle-management/retention-labels-financial-records"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/financial-records-retention.sample.json`

```json
{
  "_comment": "Config for deploy/New-FinancialRecordsRetention.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. CORRECTED (see README.md Section 2/11): Microsoft does not support auto-apply for REGULATORY RECORD labels, so this default config creates a plain RECORD label (locked, not regulatory-immutable) and auto-applies it. For a true regulatory record, use the '_regulatoryVariant' shape shown in README.md Section 5 instead - that variant makes this script stop after label creation, and hands off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to actually distribute the label.",
  "label": {
    "name": "Financial Records - 7yr Record",
    "comment": "Broker-dealer financial books-and-records retained 7 years, first 2 years accessible, as a locked record (SEC 17a-4(b)/(f)).",
    "retentionAction": "Keep",
    "retentionDurationDays": 2555,
    "retentionType": "CreationAgeInDays",
    "regulatory": false,
    "isRecordLabel": true,
    "reviewerEmail": [],
    "_labelNote": "retentionAction: Keep | Delete | KeepAndDelete. retentionDurationDays: integer days (2555 ~= 7 years) or the string 'Unlimited'. retentionType: when the clock starts - CreationAgeInDays | ModificationAgeInDays | TaggedAgeInDays | EventAgeInDays. regulatory=true would make this a REGULATORY RECORD (strongest immutability: cannot be removed, relabeled, unlocked, or its retention shortened; content cannot be edited/deleted) - this option is only creatable in PowerShell, not the portal by default (README.md Section 5). CORRECTED default: this config uses regulatory=false / isRecordLabel=true (a plain, lockable record label) because Microsoft does NOT support auto-apply for regulatory records - see README.md Section 2/11. If regulatory=true is set instead, this script creates the label then REFUSES to auto-apply it (stops before policy/rule creation) - hand off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to actually distribute a regulatory label."
  },
  "policy": {
    "name": "Auto-apply Financial Records - Finance sites",
    "comment": "Auto-applies the Financial Records (record) label to finance content.",
    "enabled": true,
    "sharePointLocation": ["https://contoso.sharepoint.com/sites/finance"],
    "exchangeLocation": [],
    "oneDriveLocation": [],
    "_policyNote": "At least one location is required. Use adaptive scopes for large/dynamic estates (out of scope here - see README.md Section 11). Static-scope SharePoint site URL(s) shown."
  },
  "rule": {
    "contentMatchQuery": "SensitiveType:\"Credit Card Number\" OR \"invoice\" OR \"general ledger\" OR \"trial balance\"",
    "_ruleNote": "KQL for auto-apply matching (-ContentMatchQuery). Narrow this to your real financial-record signals - an over-broad query locks non-records as records (only a records manager can unlock/remove the label - see rollback.md). Alternatively match sensitive information types via a -ContentContainsSensitiveInformation hashtable (not shown; see New-RetentionComplianceRule reference). Auto-apply can take up to 7 days to take effect."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-03"
}
```

#### `New-FinancialRecordsRetention.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a retention label for financial records (SEC 17a-4-style immutability) and an auto-apply
    retention label policy that stamps it onto finance content - using Security & Compliance
    PowerShell.

.DESCRIPTION
    Uses the Data Lifecycle Management / Records Management cmdlets in Security & Compliance
    PowerShell (automation surface 2 per docs/automation-surface.md):
      1. New-ComplianceTag             -> the retention label (Keep N days; record or regulatory record)
      2. New-RetentionCompliancePolicy -> the auto-apply label policy (locations)
      3. New-RetentionComplianceRule   -> the rule binding the label to the policy with a match query

    CORRECTED (see README.md Section 6/11 and reviews.md's correction addenda): the auto-apply rule
    call omits -Name. New-RetentionComplianceRule's -Name parameter is documented mutually exclusive
    with -ApplyComplianceTag ("You can't use this parameter with the ApplyComplianceTag or
    PublishComplianceTag parameters" - Microsoft Learn); the ComplianceTag parameter set -ApplyComplianceTag
    belongs to does not list -Name at all. The existing idempotency check (Get-RetentionComplianceRule
    -Policy) already locates the rule by policy, not by name, so nothing depends on an explicit name.

    CORRECTED (see README.md Section 2/11 and reviews.md's correction addendum): Microsoft's
    auto-apply retention label policies do NOT support labels that mark items as a REGULATORY
    RECORD - publishing is the only supported distribution mechanism for those. This script
    therefore creates the label regardless of the `regulatory` config flag (New-ComplianceTag
    -Regulatory $true is a valid, standalone call), but SKIPS auto-apply policy/rule creation with a
    clear warning when `label.regulatory` is true, instead of building an unsupported configuration.
    Hand off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to
    actually distribute a regulatory label. The sample config defaults to a plain RECORD label
    (`isRecordLabel: true`, `regulatory: false`), which auto-apply DOES support - see the
    `-Regulatory` note in .NOTES for the record vs. regulatory record distinction.

    Why PowerShell: a REGULATORY RECORD label (`-Regulatory $true`) can only be created in
    PowerShell (the portal hides the option by default), regardless of how it's later distributed.
    That makes label creation genuinely PowerShell-first even though this script's own auto-apply
    step only ever applies to non-regulatory labels.

    Idempotent: each object is located by name via Get-* before create; if present it is reported
    (labels/policies are not silently mutated - retention objects are high-consequence). Re-running is
    safe. -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements its
    own -DryRun that prints the intended cmdlets and runs none.

    !!! IRREVERSIBLE !!! Once a record (or regulatory record) label is APPLIED to content, the label
    cannot be removed without records-manager privilege (record) or at all (regulatory record) -
    retention can't be shortened either way. TEST IN A LAB TENANT FIRST, review with -DryRun, and
    get Legal/Records sign-off before running for real. See README.md Sections 2/11.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/financial-records-retention.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FinancialRecordsRetention.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-FinancialRecordsRetention.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-ComplianceTag (retention label; -RetentionAction/-RetentionDuration/-RetentionType/
      -IsRecordLabel/-Regulatory): https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-RetentionCompliancePolicy / New-RetentionComplianceRule (-ApplyComplianceTag; -Name
      documented mutually exclusive with -ApplyComplianceTag/-PublishComplianceTag - the source of the
      -Name omission correction above):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Declare records / regulatory records:
      https://learn.microsoft.com/purview/records-management
      https://learn.microsoft.com/purview/declare-records
    - Automatically apply a retention label ("isn't supported for regulatory records... require a
      published retention label policy" - the source of this script's regulatory-record guard):
      https://learn.microsoft.com/purview/apply-retention-labels-automatically
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/financial-records-retention.sample.json'),

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
foreach ($k in 'label', 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Deploying financial-records retention: label '$($cfg.label.name)'$(if (-not $cfg.label.regulatory) { " + auto-apply policy '$($cfg.policy.name)'" })." -ForegroundColor Cyan
if ($cfg.label.regulatory) {
    Write-Host "WARNING: this creates a REGULATORY RECORD label - IRREVERSIBLE once applied (retention can't be shortened, label can't be removed). Test in a lab and get Legal/Records sign-off. See README.md Sections 2/11." -ForegroundColor Red
    Write-Host "NOTE: Microsoft does not support auto-apply for regulatory records - this run will create the label ONLY and SKIP the auto-apply policy/rule. Use scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to distribute it. See README.md Section 2." -ForegroundColor Yellow
}

# --- 1. Retention label (New-ComplianceTag) ---
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - retention labels are high-consequence; edit deliberately)." -ForegroundColor DarkGreen
}
else {
    $dur = if ("$($cfg.label.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.label.retentionDurationDays }
    $tagParams = @{
        Name            = $cfg.label.name
        RetentionAction = $cfg.label.retentionAction
        RetentionType   = $cfg.label.retentionType
        RetentionDuration = $dur
    }
    if ($cfg.label.comment) { $tagParams.Comment = $cfg.label.comment }
    if ($cfg.label.regulatory) { $tagParams.Regulatory = $true }
    elseif ($cfg.label.isRecordLabel) { $tagParams.IsRecordLabel = $true }
    if ($cfg.label.reviewerEmail -and @($cfg.label.reviewerEmail).Count -gt 0) { $tagParams.ReviewerEmail = @($cfg.label.reviewerEmail) }

    $desc = "New-ComplianceTag -Name '$($cfg.label.name)' -RetentionAction $($cfg.label.retentionAction) -RetentionDuration $dur -RetentionType $($cfg.label.retentionType)$(if ($cfg.label.regulatory) { ' -Regulatory $true' } elseif ($cfg.label.isRecordLabel) { ' -IsRecordLabel $true' })"
    Invoke-Scc -Describe $desc -Action { New-ComplianceTag @tagParams -Confirm:$false } | Out-Null
    Write-Host "  [label] created '$($cfg.label.name)'" -ForegroundColor Green
}

if ($cfg.label.regulatory) {
    Write-Host "`n[skip] Auto-apply policy/rule NOT created: Microsoft does not support auto-apply for regulatory records (see README.md Section 2/11)." -ForegroundColor Yellow
    Write-Host "       Next step: scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to publish '$($cfg.label.name)' for manual application." -ForegroundColor Yellow
    Write-Host "`nDone (label only)." -ForegroundColor Cyan
    return
}

# --- 2. Auto-apply label policy (New-RetentionCompliancePolicy) ---
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
    if (-not ($polParams.SharePointLocation -or $polParams.ExchangeLocation -or $polParams.OneDriveLocation)) {
        throw "policy needs at least one location (sharePointLocation / exchangeLocation / oneDriveLocation)."
    }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' (auto-apply label policy, locations set)" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 3. Auto-apply rule (New-RetentionComplianceRule -ApplyComplianceTag) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    # -Name is documented mutually exclusive with -ApplyComplianceTag (ComplianceTag parameter set) -
    # see .NOTES and README.md Section 6/11. Omitted here; the existing idempotency check above
    # locates the rule by -Policy, not by name.
    $ruleParams = @{
        Policy            = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
    }
    if (-not [string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { $ruleParams.ContentMatchQuery = $cfg.rule.contentMatchQuery }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)' -ContentMatchQuery <query>" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (auto-apply '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Auto-apply can take up to 7 days to take effect. Validate with validate/Test-FinancialRecordsRetention.ps1 and confirm labeling in the portal (Records Management / Data Lifecycle Management)." -ForegroundColor Yellow
```

#### `Remove-FinancialRecordsRetention.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the financial-records retention deployment: disables (and optionally deletes) the
    auto-apply policy/rule. The retention LABEL itself is intentionally not force-removed.

.DESCRIPTION
    Uses Security & Compliance PowerShell. Staged:
      Default    Disable the auto-apply policy (Set-RetentionCompliancePolicy -Enabled $false) so it
                 stops stamping the label on NEW content. Content already labeled keeps its label and
                 retention (records/regulatory records are immutable or near-immutable by design).
      -Delete    Additionally delete the policy (Remove-RetentionCompliancePolicy) and its rule.

    Only applicable if an auto-apply policy/rule exists at all: this scenario's deploy script does
    NOT create an auto-apply policy/rule for a label configured as a REGULATORY RECORD (Microsoft
    doesn't support that combination - see README.md Section 2/11) - there's nothing here to roll
    back for that case; see scenarios/data-lifecycle-management/publish-labels-for-manual-application/
    rollback.md instead.

    The retention LABEL is NOT deleted by this script. A record label that has been applied to
    content can only be removed by an admin for the container (SharePoint/OneDrive) or with
    write-access (Exchange), and a regulatory record label CANNOT be deleted at all once applied -
    its retention can't be shortened either way. Removing the policy stops future auto-labeling; it
    does NOT release existing records. This is by design, not a limitation to work around.

    -WhatIf is non-functional in Security & Compliance PowerShell, so this script implements -DryRun.
    Connect first with Connect-IPPSSession.

.PARAMETER ConfigPath
    Path to the same JSON config used to deploy. Defaults to 'config/financial-records-retention.sample.json'.
    Only policy.name (and, with -TryRemoveLabel, label.name) are read here.

.PARAMETER Delete
    Delete the auto-apply policy and rule (not just disable).

.PARAMETER TryRemoveLabel
    Attempt to remove the retention label too (Remove-ComplianceTag). This SUCCEEDS only if the label
    was never applied and isn't a published/regulatory record in use; otherwise the service refuses,
    which this script reports rather than forcing.

.PARAMETER DryRun
    Print the intended cmdlets and run none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-FinancialRecordsRetention.ps1 -DryRun

.NOTES
    Grounded in Microsoft Learn: Set-/Remove-RetentionCompliancePolicy, Remove-ComplianceTag; records
    management immutability. https://learn.microsoft.com/purview/records-management
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/financial-records-retention.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$TryRemoveLabel,

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
    Write-Host "  [disable] policy '$($cfg.policy.name)' disabled (stops NEW auto-labeling)." -ForegroundColor Yellow
    if ($Delete) {
        Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)'" `
            -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false }
        Write-Host "  [delete] policy '$($cfg.policy.name)' removed (rule removed with it)." -ForegroundColor Red
    }
}
else { Write-Host "  [policy] '$($cfg.policy.name)' not found." -ForegroundColor DarkGray }

if ($TryRemoveLabel -and $cfg.label.name) {
    if ($DryRun) {
        Write-Host "  DRYRUN would run: Remove-ComplianceTag -Identity '$($cfg.label.name)'" -ForegroundColor DarkYellow
    }
    else {
        try {
            Remove-ComplianceTag -Identity $cfg.label.name -Confirm:$false
            Write-Host "  [delete] label '$($cfg.label.name)' removed (was not in use)." -ForegroundColor Red
        }
        catch {
            Write-Warning "  Could not remove label '$($cfg.label.name)': $($_.Exception.Message). This is expected for a record or regulatory record label that has been applied to content - such labels cannot be deleted while records exist (a regulatory record label never can, even if never applied). See rollback.md."
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Existing labeled content keeps its retention (regulatory records are immutable) - disabling/deleting the policy only stops FUTURE auto-labeling. See rollback.md." -ForegroundColor Yellow
```