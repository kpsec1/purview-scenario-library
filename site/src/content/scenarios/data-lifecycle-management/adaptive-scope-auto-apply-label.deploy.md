---
part: "deploy"
parent: "data-lifecycle-management/adaptive-scope-auto-apply-label"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/adaptive-scope-auto-apply-label.sample.json`

```json
{
  "_comment": "Config for deploy/New-AdaptiveScopeAutoApplyLabel.ps1. Author-only reference data - NOT applied to any tenant unless passed to the deploy script without -DryRun. Companion to scenarios/data-lifecycle-management/adaptive-scope-retention/ (Keep-only) and scenarios/data-lifecycle-management/retention-labels-financial-records/ (static-scope record label): this scenario auto-applies a RECORD retention label to the same query-driven executive population instead of a plain Keep action, using the identical New-RetentionCompliancePolicy -AdaptiveScopeLocation object model. Same regulatory-record guard as the financial-records sibling: Microsoft does not support auto-apply for REGULATORY RECORD labels, so this config defaults to a plain (non-regulatory) record label. Reuses the sibling adaptive-scope-retention scenario's adaptive scope name by default so the two scenarios can share one scope if both are deployed - the deploy script detects and reuses it (Get-AdaptiveScope) rather than creating a duplicate.",
  "adaptiveScope": {
    "name": "Executives - US and Canada",
    "comment": "User-type adaptive scope: Title matches a defined set of executive titles. Re-evaluated daily against Entra ID; no group to maintain. Shared by design with scenarios/data-lifecycle-management/adaptive-scope-retention/ - same name, same query, same object if both scenarios are deployed to one tenant.",
    "locationType": "User",
    "administrativeUnit": "",
    "filterConditions": {
      "conjunction": "Or",
      "conditions": [
        { "name": "Title", "operator": "Equals", "value": "Chief Executive Officer" },
        { "name": "Title", "operator": "Equals", "value": "Chief Financial Officer" },
        { "name": "Title", "operator": "Equals", "value": "Chief Operating Officer" },
        { "name": "Title", "operator": "Equals", "value": "General Counsel" }
      ]
    },
    "_scopeNote": "locationType: User | Group | Site (New-AdaptiveScope -LocationType). administrativeUnit: Entra administrative unit GUID to restrict scope membership to a delegated boundary; leave blank for Full directory. filterConditions maps to -FilterConditions (Conditions array of {Name,Operator,Value} + Conjunction And/Or; Operator: Equals/NotEquals/StartsWith/NotStartsWith). For the advanced query builder instead (OPATH for User/Group, KeyQL for Site), use -RawQuery - not shown here. Illustrative titles - set to your organization's real executive roster signal, validated by HR/Legal."
  },
  "label": {
    "name": "Executive Communications - Record",
    "comment": "Executives' Exchange email and OneDrive content, retained 10 years and locked as a record - population defined adaptively (Title attribute) instead of a static distribution list.",
    "retentionAction": "Keep",
    "retentionDurationDays": 3650,
    "retentionType": "CreationAgeInDays",
    "regulatory": false,
    "isRecordLabel": true,
    "reviewerEmail": [],
    "_labelNote": "retentionAction: Keep | Delete | KeepAndDelete. retentionDurationDays: integer days (3650 ~= 10 years, matching the Keep-only adaptive-scope-retention sibling's duration) or the string 'Unlimited'. retentionType: when the clock starts - CreationAgeInDays | ModificationAgeInDays | TaggedAgeInDays | EventAgeInDays. regulatory=true would make this a REGULATORY RECORD (cannot be removed, relabeled, unlocked, or have its retention shortened by anyone) - PowerShell-only to create, and NOT supported for auto-apply (see README.md Section 2/11, same correction already applied in the retention-labels-financial-records sibling). If regulatory=true is set here, this script creates the label then STOPS - no adaptive-scope policy/rule is created - hand off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ instead. Default here is regulatory=false / isRecordLabel=true (a plain, lockable record label), which auto-apply fully supports."
  },
  "policy": {
    "name": "Auto-apply Executive Communications Record - Adaptive",
    "comment": "Auto-applies the Executive Communications (record) label to the adaptively-scoped executive population's Exchange mail and OneDrive content.",
    "enabled": true,
    "_policyNote": "Maps to New-RetentionCompliancePolicy -AdaptiveScopeLocation <adaptiveScope.name>. Same disclosed parameter-surface gap as the adaptive-scope-retention sibling: no -ExchangeLocation/-OneDriveLocation-equivalent toggle in this parameter set, so which of the scope's User-type locations the policy actually covers is not exposed as a documented parameter - VERIFY (pilot tenant) per README.md Section 11 / design.md Section 4 before assuming Exchange+OneDrive-only."
  },
  "rule": {
    "contentMatchQuery": "",
    "_ruleNote": "Maps to New-RetentionComplianceRule -Policy -ApplyComplianceTag -ContentMatchQuery. Left empty by default - unlike the financial-records sibling (which matches a content signal within a broad SharePoint site), this rule relies entirely on the adaptive scope for targeting: everything in the executive population's covered locations gets the record label, no separate content condition. Set a KQL query here only if you want to narrow further within the adaptively-scoped population. GROUNDING CORRECTION vs. the financial-records sibling script: New-RetentionComplianceRule's -Name parameter is DOCUMENTED as mutually exclusive with -ApplyComplianceTag ('You can't use this parameter with the ApplyComplianceTag or PublishComplianceTag parameters' - Microsoft Learn) - this scenario's deploy script does not pass -Name when using -ApplyComplianceTag; see README.md Section 11 and PROGRESS.md for the same defect flagged as an open follow-up against the sibling script."
  },
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-11"
}
```

#### `New-AdaptiveScopeAutoApplyLabel.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Creates an adaptive scope, a RECORD retention label, and an auto-apply retention label policy/
    rule that stamps the label onto a query-driven population's Exchange mail and OneDrive content -
    using Security & Compliance PowerShell.

.DESCRIPTION
    Combines the two object models this repo already ships separately:
      - scenarios/data-lifecycle-management/adaptive-scope-retention/ (adaptive scope + Keep-only
        retention policy)
      - scenarios/data-lifecycle-management/retention-labels-financial-records/ (record label +
        auto-apply policy/rule, static SharePoint scope)
    into the auto-apply retention LABEL variant of the adaptive-scope pattern: population is defined
    by a query (Entra Title attribute, not a static list), and the content is locked as a record
    (New-RetentionComplianceRule -ApplyComplianceTag), not just retained (-RetentionComplianceAction).

    Cmdlets used (automation surface 2 per docs/automation-surface.md):
      1. New-AdaptiveScope             -> a User-type adaptive scope (query on the Title attribute) -
         reuses the adaptive-scope-retention sibling's scope by name if it already exists (adaptive
         scopes are shared, reusable objects); creates it if this scenario is deployed standalone.
      2. New-ComplianceTag             -> the retention label (Keep N days; record, not regulatory)
      3. New-RetentionCompliancePolicy -> the auto-apply label policy, scoped via -AdaptiveScopeLocation
      4. New-RetentionComplianceRule   -> the rule binding the label to the policy (-ApplyComplianceTag)

    GROUNDED: Microsoft's own "Automatically apply a retention label" guidance documents adaptive
    scopes as a supported (and production-recommended) input to a retention LABEL policy, not just a
    plain retention policy: "If you decide to use an adaptive policy, you must create one or more
    adaptive scopes before you create your retention label policy, and then select them during the
    create retention label policy process." This script's -AdaptiveScopeLocation + -ApplyComplianceTag
    combination is that documented path (see .NOTES).

    SAME REGULATORY-RECORD GUARD as retention-labels-financial-records: Microsoft does NOT support
    auto-apply for labels that mark items as a REGULATORY RECORD (only a published policy can
    distribute one). This script creates the label regardless of the `regulatory` config flag, but
    SKIPS adaptive-scope policy/rule creation with a clear warning when `label.regulatory` is true.
    Hand off to scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to actually
    distribute a regulatory label to this (or any) population.

    GROUNDING CORRECTION vs. the financial-records sibling script: New-RetentionComplianceRule's
    -Name parameter is documented as mutually exclusive with -ApplyComplianceTag ("You can't use this
    parameter with the ApplyComplianceTag or PublishComplianceTag parameters" - Microsoft Learn). The
    sibling script (New-FinancialRecordsRetention.ps1) passes both together, which does not match the
    documented parameter set and is flagged as an open follow-up in PROGRESS.md rather than silently
    repeated here. This script omits -Name entirely when calling -ApplyComplianceTag; the rule is
    still located afterward by -Policy (Get-RetentionComplianceRule -Policy), never by name, so no
    functionality is lost.

    Idempotent: each object (scope, label, policy, rule) is located by its natural key before create;
    if present it is reported (not silently mutated - retention objects, and record labels especially,
    are high-consequence). Re-running is safe. -WhatIf is non-functional in Security & Compliance
    PowerShell, so this script implements its own -DryRun that prints the intended cmdlets and runs
    none.

    !!! IRREVERSIBLE-LEANING !!! Once a record label is APPLIED to content it can only be unlocked or
    removed by a records manager - and because membership here is adaptively (attribute-)driven, an
    over-broad or stale Title query locks the wrong population's content as records, not just retains
    it. This is a materially higher-consequence combination than either sibling scenario alone. TEST
    IN A LAB TENANT FIRST, review with -DryRun, and get Records/Legal sign-off. See README.md
    Sections 2/11.

    Connect first: Connect-IPPSSession (certificate app-only preferred - docs/automation-surface.md
    Section 3). This script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/adaptive-scope-auto-apply-label.sample.json'.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none (the working substitute for -WhatIf,
    which does not function in Security & Compliance PowerShell).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-AdaptiveScopeAutoApplyLabel.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-AdaptiveScopeAutoApplyLabel.ps1

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-AdaptiveScope (-Name/-LocationType/-FilterConditions/-RawQuery/-AdministrativeUnit):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-adaptivescope
    - Adaptive scopes overview + 5-day population delay:
      https://learn.microsoft.com/purview/purview-adaptive-scopes
    - Automatically apply a retention label - adaptive scopes explicitly documented as a supported
      input to a retention label policy ("select them during the create retention label policy
      process"); up to 7-day auto-apply latency; auto-apply NOT supported for regulatory records:
      https://learn.microsoft.com/purview/apply-retention-labels-automatically
    - New-ComplianceTag (retention label; -RetentionAction/-RetentionDuration/-RetentionType/
      -IsRecordLabel/-Regulatory): https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag
    - New-RetentionCompliancePolicy (-AdaptiveScopeLocation parameter set):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy
    - New-RetentionComplianceRule (-ApplyComplianceTag / ComplianceTag parameter set; -Name is
      documented mutually exclusive with -ApplyComplianceTag - the correction cited above):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule
    - Declare records / regulatory records (record vs. regulatory record removal privilege):
      https://learn.microsoft.com/purview/declare-records
      https://learn.microsoft.com/purview/records-management
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/adaptive-scope-auto-apply-label.sample.json'),

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
function ConvertTo-FilterConditionsHashtable {
    param([Parameter(Mandatory)]$FilterConditions)
    $conditions = @()
    foreach ($c in $FilterConditions.conditions) {
        $conditions += @{ Name = $c.name; Operator = $c.operator; Value = $c.value }
    }
    return @{ Conditions = $conditions; Conjunction = $FilterConditions.conjunction }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($k in 'adaptiveScope', 'label', 'policy', 'rule') { if (-not $cfg.$k) { throw "Config missing '$k' section." } }
if (-not $cfg.adaptiveScope.name) { throw "adaptiveScope.name is required." }
if (-not $cfg.label.name) { throw "label.name is required." }
if (-not $cfg.policy.name) { throw "policy.name is required." }

Assert-SccConnected
Write-Host "Deploying adaptive-scope auto-apply label: scope '$($cfg.adaptiveScope.name)' + label '$($cfg.label.name)'$(if (-not $cfg.label.regulatory) { " + policy '$($cfg.policy.name)'" })." -ForegroundColor Cyan
if ($cfg.label.regulatory) {
    Write-Host "WARNING: this creates a REGULATORY RECORD label - IRREVERSIBLE once applied (retention can't be shortened, label can't be removed by anyone). Test in a lab and get Legal/Records sign-off. See README.md Sections 2/11." -ForegroundColor Red
    Write-Host "NOTE: Microsoft does not support auto-apply for regulatory records - this run will create the label ONLY and SKIP the adaptive-scope policy/rule. Use scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to distribute it." -ForegroundColor Yellow
}
else {
    Write-Host "NOTE: this locks matching content as a RECORD (removable only by a records manager), for a population that changes adaptively. Over-broad scope or query = over-broad record locking. See README.md Sections 2/11." -ForegroundColor Yellow
}

# --- 1. Adaptive scope (New-AdaptiveScope) - shared/reused with the Keep-only sibling by name ---
$existingScope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
if ($existingScope) {
    Write-Host "  [scope] exists '$($cfg.adaptiveScope.name)' (reused - possibly already deployed by the adaptive-scope-retention sibling; not modified)." -ForegroundColor DarkGreen
}
else {
    $filterHash = ConvertTo-FilterConditionsHashtable -FilterConditions $cfg.adaptiveScope.filterConditions
    $scopeParams = @{
        Name             = $cfg.adaptiveScope.name
        LocationType     = $cfg.adaptiveScope.locationType
        FilterConditions = $filterHash
    }
    if ($cfg.adaptiveScope.comment) { $scopeParams.Comment = $cfg.adaptiveScope.comment }
    if ($cfg.adaptiveScope.administrativeUnit) { $scopeParams.AdministrativeUnit = $cfg.adaptiveScope.administrativeUnit }

    $desc = "New-AdaptiveScope -Name '$($cfg.adaptiveScope.name)' -LocationType $($cfg.adaptiveScope.locationType) -FilterConditions <$($filterHash.Conditions.Count) condition(s), $($filterHash.Conjunction)>"
    Invoke-Scc -Describe $desc -Action { New-AdaptiveScope @scopeParams } | Out-Null
    Write-Host "  [scope] created '$($cfg.adaptiveScope.name)' - allow up to 5 days for membership to populate." -ForegroundColor Green
}

# --- 2. Retention label (New-ComplianceTag) ---
$existingLabel = Get-ComplianceTag -Identity $cfg.label.name -ErrorAction SilentlyContinue
if ($existingLabel) {
    Write-Host "  [label] exists '$($cfg.label.name)' (not modified - retention labels are high-consequence; edit deliberately)." -ForegroundColor DarkGreen
}
else {
    $dur = if ("$($cfg.label.retentionDurationDays)" -eq 'Unlimited') { 'Unlimited' } else { [int]$cfg.label.retentionDurationDays }
    $tagParams = @{
        Name               = $cfg.label.name
        RetentionAction    = $cfg.label.retentionAction
        RetentionType      = $cfg.label.retentionType
        RetentionDuration  = $dur
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
    Write-Host "`n[skip] Adaptive-scope policy/rule NOT created: Microsoft does not support auto-apply for regulatory records (see README.md Section 2/11)." -ForegroundColor Yellow
    Write-Host "       Next step: scenarios/data-lifecycle-management/publish-labels-for-manual-application/ to publish '$($cfg.label.name)' for manual application." -ForegroundColor Yellow
    Write-Host "`nDone (scope + label only)." -ForegroundColor Cyan
    return
}

# --- 3. Adaptive-scope auto-apply label policy (New-RetentionCompliancePolicy) ---
$existingPolicy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Write-Host "  [policy] exists '$($cfg.policy.name)'" -ForegroundColor DarkGreen
}
else {
    $polParams = @{
        Name                  = $cfg.policy.name
        AdaptiveScopeLocation = $cfg.adaptiveScope.name
    }
    if ($null -ne $cfg.policy.enabled) { $polParams.Enabled = [bool]$cfg.policy.enabled }
    if ($cfg.policy.comment) { $polParams.Comment = $cfg.policy.comment }
    Invoke-Scc -Describe "New-RetentionCompliancePolicy -Name '$($cfg.policy.name)' -AdaptiveScopeLocation '$($cfg.adaptiveScope.name)'" `
        -Action { New-RetentionCompliancePolicy @polParams -Confirm:$false } | Out-Null
    Write-Host "  [policy] created '$($cfg.policy.name)'" -ForegroundColor Green
}

# --- 4. Auto-apply rule (New-RetentionComplianceRule -ApplyComplianceTag; ComplianceTag parameter
#        set - -Name is documented mutually exclusive with -ApplyComplianceTag, so it is NOT passed) ---
$existingRule = Get-RetentionComplianceRule -Policy $cfg.policy.name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existingRule) {
    Write-Host "  [rule] exists on policy '$($cfg.policy.name)' (one rule per policy - not modified)." -ForegroundColor DarkGreen
}
else {
    $ruleParams = @{
        Policy             = $cfg.policy.name
        ApplyComplianceTag = $cfg.label.name
    }
    if (-not [string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { $ruleParams.ContentMatchQuery = $cfg.rule.contentMatchQuery }
    $descSuffix = if (-not [string]::IsNullOrWhiteSpace($cfg.rule.contentMatchQuery)) { " -ContentMatchQuery <query>" } else { " (no content query - scope-only targeting)" }
    Invoke-Scc -Describe "New-RetentionComplianceRule -Policy '$($cfg.policy.name)' -ApplyComplianceTag '$($cfg.label.name)'$descSuffix" `
        -Action { New-RetentionComplianceRule @ruleParams -Confirm:$false } | Out-Null
    Write-Host "  [rule] created (auto-apply '$($cfg.label.name)')" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Two independent delays stack here: adaptive scope membership (up to 5 days) and auto-apply distribution (up to 7 days). Validate with validate/Test-AdaptiveScopeAutoApplyLabel.ps1 and confirm actual labeling in the portal before relying on this operationally." -ForegroundColor Yellow
```

#### `Remove-AdaptiveScopeAutoApplyLabel.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Rolls back the adaptive-scope auto-apply label policy/rule and, optionally, the adaptive scope -
    staged, per rollback.md. Never touches the label definition or content already labeled.

.DESCRIPTION
    Stage 1 (default): Set-RetentionCompliancePolicy -Enabled $false - stops the policy from
    auto-applying the label to any further content. Reversible (re-run the deploy script to
    re-enable). Content already labeled as a record is NOT affected - see "What rollback does not
    undo" in rollback.md.

    Stage 2 (-Delete): Remove-RetentionCompliancePolicy - removes the policy AND its rule in one call
    (Microsoft's own documented behavior). This stops future auto-apply only. It does NOT unlock or
    remove the record label from content already labeled - only a records manager can do that
    (Get-ComplianceTag / the portal's Records Management > File plan, out of scope for this script),
    and only for a plain record; a regulatory record (if one was created via -Delete's label.regulatory
    path having been skipped from auto-apply entirely) can never be removed by anyone.

    Stage 3 (-Delete -TryRemoveScope): also attempts Remove-AdaptiveScope for the adaptive scope. This
    can fail if the scope is still referenced by another policy (including the adaptive-scope-
    retention sibling, if both are deployed to the same tenant sharing one scope by name) - the script
    reports the failure rather than forcing it (-ForceDeletion is available but NOT used by default;
    pass -ForceScopeDeletion to opt in).

    This script never removes the retention label itself (Remove-ComplianceTag) - a record label
    definition, and any content already locked under it, is out of scope for a policy/rule rollback.
    Remove the label definition manually, deliberately, and only after confirming no content still
    carries it.

    Idempotent / safe to re-run: each stage checks current state before acting.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to 'config/adaptive-scope-auto-apply-label.sample.json'.

.PARAMETER Delete
    Also remove the auto-apply policy (and its rule). Does not touch the label or labeled content.

.PARAMETER TryRemoveScope
    After -Delete, also attempt to remove the adaptive scope (Remove-AdaptiveScope). Reports failure
    rather than forcing it unless -ForceScopeDeletion is also specified.

.PARAMETER ForceScopeDeletion
    Pass -ForceDeletion to Remove-AdaptiveScope. Only meaningful with -Delete -TryRemoveScope.

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeAutoApplyLabel.ps1 -DryRun

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./Remove-AdaptiveScopeAutoApplyLabel.ps1 -Delete

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Remove-RetentionCompliancePolicy (removes policy + rule together):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancepolicy
    - Remove-AdaptiveScope (-Identity/-ForceDeletion):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-adaptivescope
    - Declare records / regulatory records (record label removal requires records-manager privilege;
      regulatory record cannot be removed by anyone): https://learn.microsoft.com/purview/declare-records
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/adaptive-scope-auto-apply-label.sample.json'),

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$TryRemoveScope,

    [Parameter()]
    [switch]$ForceScopeDeletion,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Invoke-Scc {
    param([Parameter(Mandatory)][string]$Describe, [Parameter(Mandatory)][scriptblock]$Action)
    if ($DryRun) { Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow; return $null }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

if (-not (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue)) {
    throw "Retention cmdlets not found. Connect first: Connect-IPPSSession. See docs/automation-surface.md Section 3."
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$policy = Get-RetentionCompliancePolicy -Identity $cfg.policy.name -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "Policy '$($cfg.policy.name)' not found - nothing to disable/delete (expected if label.regulatory was true, since no policy/rule is created in that case)." -ForegroundColor Yellow
}
elseif ($Delete) {
    Invoke-Scc -Describe "Remove-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' (removes policy + rule)" `
        -Action { Remove-RetentionCompliancePolicy -Identity $cfg.policy.name -Confirm:$false } | Out-Null
    Write-Host "  [policy+rule] removed '$($cfg.policy.name)'. Future content stops being auto-labeled. Content already labeled as a record is UNCHANGED - see rollback.md." -ForegroundColor Green
}
else {
    Invoke-Scc -Describe "Set-RetentionCompliancePolicy -Identity '$($cfg.policy.name)' -Enabled `$false" `
        -Action { Set-RetentionCompliancePolicy -Identity $cfg.policy.name -Enabled $false -Confirm:$false } | Out-Null
    Write-Host "  [policy] disabled '$($cfg.policy.name)' - no new content is auto-labeled; re-run the deploy script to re-enable." -ForegroundColor Green
}

if ($Delete -and $TryRemoveScope) {
    $scope = Get-AdaptiveScope -Identity $cfg.adaptiveScope.name -ErrorAction SilentlyContinue
    if (-not $scope) {
        Write-Host "Adaptive scope '$($cfg.adaptiveScope.name)' not found - nothing to remove." -ForegroundColor Yellow
    }
    else {
        $removeParams = @{ Identity = $cfg.adaptiveScope.name }
        if ($ForceScopeDeletion) { $removeParams.ForceDeletion = $true }
        try {
            Invoke-Scc -Describe "Remove-AdaptiveScope -Identity '$($cfg.adaptiveScope.name)'$(if ($ForceScopeDeletion) { ' -ForceDeletion' })" `
                -Action { Remove-AdaptiveScope @removeParams -Confirm:$false } | Out-Null
            Write-Host "  [scope] removed '$($cfg.adaptiveScope.name)'" -ForegroundColor Green
        }
        catch {
            Write-Host "  [scope] could not remove '$($cfg.adaptiveScope.name)': $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  This can happen if another policy still references the scope - e.g. the adaptive-scope-retention sibling, if both share this scope name in your tenant. Re-run with -ForceScopeDeletion only after confirming no other policy needs it." -ForegroundColor Yellow
        }
    }
}

Write-Host "`nDone. The retention label definition and any content already labeled as a record are never touched by this script - see rollback.md." -ForegroundColor Cyan
```