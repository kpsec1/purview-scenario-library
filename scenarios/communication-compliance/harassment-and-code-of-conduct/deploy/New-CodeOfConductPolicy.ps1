#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or reconciles the SCRIPTABLE SUBSET of a Microsoft Purview Communication Compliance
    code-of-conduct policy: a supervisory-review policy plus a keyword/phrase (lexicon) rule scoped
    to reviewees and message direction, with a sampling rate and assigned reviewers.

.DESCRIPTION
    Uses the Security & Compliance PowerShell SupervisoryReview cmdlets
    (New-/Set-/Get-SupervisoryReviewPolicyV2, New-/Set-/Get-SupervisoryReviewRule) - automation
    surface 1 per docs/automation-surface.md - to deploy the keyword-detection and workflow shell of
    a workplace-conduct communication supervision policy.

    IMPORTANT SCOPE BOUNDARY. Microsoft states that PowerShell "isn't supported for creating and
    managing Communication Compliance policies" (the portal is the supported surface), and the
    trainable classifiers that do the real work of harassment detection - Targeted harassment,
    Threat, Discrimination - are NOT exposed as parameters of the documented SupervisoryReview
    cmdlets. This script therefore deploys only what the cmdlet surface genuinely supports:
      - the policy object and its reviewers,
      - a rule whose Condition matches your code-of-conduct KEYWORD LEXICON, scoped to the reviewee
        group(s) and communication direction(s), at a sampling rate.
    You MUST still add the trainable classifiers (and location selection: Exchange/Teams/Viva
    Engage) in the portal - see README.md Sections 5 and 11 and
    deploy/policy/inappropriate-text-portal-reference.json. Treat this script as the keyword/workflow
    half of a two-part deployment, not the whole control.

    Idempotent: the policy and rule are located by name via Get-* first; if present they are updated
    with Set-*, otherwise created with New-*. Re-running reconciles to the config file.

    -WhatIf is deliberately NOT used: Microsoft documents that "The WhatIf switch doesn't work in
    Security & Compliance PowerShell." This script implements its own -DryRun that prints every
    mutating cmdlet it would run and invokes none.

    Author-only reference code. Connect first with Connect-IPPSSession (certificate app-only
    preferred - see docs/automation-surface.md Section 3); this script does not open the session.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/code-of-conduct.sample.json'. See that
    file for the schema (policyName, reviewers, reviewees, directions, samplingRate, keywordLexicon).

.PARAMETER DryRun
    Print every mutating cmdlet that would run and invoke none. Use this to review the exact
    policy/rule/condition before touching the tenant (the working substitute for -WhatIf here).

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-CodeOfConductPolicy.ps1 -DryRun

    Dry-run: shows the policy, reviewers, and the keyword rule Condition that would be created.

.EXAMPLE
    Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
    ./New-CodeOfConductPolicy.ps1 -ConfigPath ./config/code-of-conduct.json

    Reconciles the policy and its keyword rule to the config file. Add classifiers in the portal.

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - New-/Set-/Get-/Remove-SupervisoryReviewPolicyV2, New-/Set-/Get-SupervisoryReviewRule (SCC PowerShell):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-supervisoryreviewpolicyv2
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-supervisoryreviewrule
    - Create and manage Communication Compliance policies (PowerShell not supported for CC policy
      management; 'Detect inappropriate text' template; classifiers; roles):
      https://learn.microsoft.com/purview/communication-compliance-policies
    - Get started / configure (locations, reviewers, review percentage):
      https://learn.microsoft.com/purview/communication-compliance-configure

    VERIFY (README.md Section 11): whether a modern portal-created CC policy is fully equivalent to a
    SupervisoryReviewPolicyV2 created here; whether -ContentSources sets locations (Exchange/Teams/
    Viva Engage); and whether -AdvancedRule can express trainable classifiers (undocumented). Prefer
    the portal for the classifier half of this control.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/code-of-conduct.sample.json'),

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Assert-SccConnected {
    if (-not (Get-Command Get-SupervisoryReviewPolicyV2 -ErrorAction SilentlyContinue)) {
        throw "SupervisoryReview cmdlets not found. Connect first: Connect-IPPSSession (Security & Compliance PowerShell). See docs/automation-surface.md Section 3."
    }
}

function Invoke-Scc {
    <#
        Runs $Action, or - under -DryRun - prints $Describe and runs nothing. This is the manual
        stand-in for -WhatIf, which is non-functional in Security & Compliance PowerShell.
    #>
    param(
        [Parameter(Mandatory)][string]$Describe,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($DryRun) {
        Write-Host "  DRYRUN would run: $Describe" -ForegroundColor DarkYellow
        return $null
    }
    Write-Host "  $Describe" -ForegroundColor Green
    return & $Action
}

function New-ConductCondition {
    <#
        Builds the -Condition filter string per Microsoft's documented supervisory-review syntax:
        reviewees and directions and keyword/phrase matches, each type OR-joined internally and the
        types AND-joined, wrapped in an outer parenthesis. Phrases (with spaces) are inserted bare,
        matching Microsoft's own example: "((trade) -OR (insider trading))".
    #>
    param(
        [Parameter(Mandatory)][string[]]$Reviewees,
        [Parameter(Mandatory)][string[]]$Directions,
        [Parameter(Mandatory)][string[]]$Keywords
    )
    $rev = '(' + (($Reviewees | ForEach-Object { "(Reviewee:$_)" }) -join ' -OR ') + ')'
    $dir = '(' + (($Directions | ForEach-Object { "(Direction:$_)" }) -join ' -OR ') + ')'
    $kw = '(' + (($Keywords | ForEach-Object { "($_)" }) -join ' -OR ') + ')'
    return "($rev -AND $dir -AND $kw)"
}

# --- Load config ---
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($req in 'policyName', 'reviewers', 'reviewees', 'directions', 'keywordLexicon') {
    if (-not $cfg.$req -or @($cfg.$req).Count -eq 0) { throw "Config is missing required field '$req'." }
}
$keywords = @($cfg.keywordLexicon | Where-Object { $_ -notmatch '^PLACEHOLDER' })
if ($keywords.Count -eq 0) { throw "keywordLexicon contains only PLACEHOLDER entries - replace them with your organization's terms before deploying." }
$samplingRate = if ($null -ne $cfg.samplingRate) { [int]$cfg.samplingRate } else { 100 }
$enabled = if ($null -ne $cfg.enabled) { [bool]$cfg.enabled } else { $true }
$policyName = $cfg.policyName
$ruleName = "$policyName - Keyword Rule"

Assert-SccConnected

Write-Host "Deploying Communication Compliance code-of-conduct policy '$policyName' (keyword/workflow subset)." -ForegroundColor Cyan
Write-Host "NOTE: trainable classifiers (Targeted harassment / Threat / Discrimination) and location selection are portal-only - see README.md Sections 5 and 11." -ForegroundColor Yellow

# --- Policy: create or reconcile ---
$existingPolicy = Get-SupervisoryReviewPolicyV2 -Identity $policyName -ErrorAction SilentlyContinue
if ($existingPolicy) {
    Invoke-Scc -Describe "Set-SupervisoryReviewPolicyV2 -Identity '$policyName' -Reviewers $($cfg.reviewers -join ',') -Enabled `$$enabled" -Action {
        Set-SupervisoryReviewPolicyV2 -Identity $policyName -Reviewers @($cfg.reviewers) -Enabled $enabled -Confirm:$false
    } | Out-Null
}
else {
    Invoke-Scc -Describe "New-SupervisoryReviewPolicyV2 -Name '$policyName' -Reviewers $($cfg.reviewers -join ',') -Enabled `$$enabled" -Action {
        New-SupervisoryReviewPolicyV2 -Name $policyName -Reviewers @($cfg.reviewers) -Enabled $enabled -Confirm:$false
    } | Out-Null
}

# --- Rule: create or reconcile (keyword lexicon, reviewees, directions, sampling) ---
$condition = New-ConductCondition -Reviewees @($cfg.reviewees) -Directions @($cfg.directions) -Keywords $keywords
Write-Host "  Condition: $condition" -ForegroundColor DarkGray

$existingRule = Get-SupervisoryReviewRule -Policy $policyName -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $ruleName } | Select-Object -First 1
if ($existingRule) {
    Invoke-Scc -Describe "Set-SupervisoryReviewRule -Identity '$($existingRule.Identity)' -Condition <built> -SamplingRate $samplingRate" -Action {
        Set-SupervisoryReviewRule -Identity $existingRule.Identity -Condition $condition -SamplingRate $samplingRate -Confirm:$false
    } | Out-Null
}
else {
    Invoke-Scc -Describe "New-SupervisoryReviewRule -Name '$ruleName' -Policy '$policyName' -Condition <built> -SamplingRate $samplingRate" -Action {
        New-SupervisoryReviewRule -Name $ruleName -Policy $policyName -Condition $condition -SamplingRate $samplingRate -Confirm:$false
    } | Out-Null
}

Write-Host "`nDone (keyword/workflow subset)." -ForegroundColor Cyan
Write-Host "Next, in the Microsoft Purview portal, open the '$policyName' policy and add the trainable classifiers and locations from deploy/policy/inappropriate-text-portal-reference.json. Then run validate/Test-CodeOfConductPolicy.ps1." -ForegroundColor Yellow
