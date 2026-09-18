---
part: "deploy"
parent: "dlp/accepted-domains-hygiene-check"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-AcceptedDomainsHygieneReport.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Cross-references the tenant's live Exchange accepted-domains configuration against a buyer-
    curated known-domains allowlist and the previous run's recorded state, flagging both directions
    of hygiene risk this scenario was built to close: a legitimate domain silently excluded from
    trust, and an unreviewed domain silently granted it.

.DESCRIPTION
    Every Microsoft Purview/Exchange DLP condition built on FromScope/ExceptIfFromScope
    (UserScopeFrom) - including scenarios/dspm-for-ai/copilot-external-email-block's Rule 3 this
    scenario was scoped from - treats a sender as "in organization" based entirely on the tenant's
    Get-AcceptedDomain configuration and, specifically, each domain's DomainType (design.md Sec 2):
    Authoritative and InternalRelay count as in-organization; ExternalRelay does not, and (a finding
    this scenario's own grounding pass surfaced, not previously documented anywhere in this repo) is
    only reachable on an on-premises Exchange organization in the first place - see design.md Sec 2.

    This script computes four categories of finding, entirely from read-only Get-AcceptedDomain (and,
    optionally, Search-UnifiedAuditLog) calls:
      1. MissingExpectedDomain  - a known-domains config entry marked Required is absent from the
         live accepted-domains list. False-positive-exclusion risk: that domain's mail is silently
         treated as external by every FromScope-consuming rule.
      2. DomainTypeMismatch     - a known domain is present but its live DomainType differs from the
         config's ExpectedDomainType. May or may not change the trust boundary (Authoritative vs.
         InternalRelay both count as in-organization) but is always a configuration-drift signal.
      3. UnexpectedTrustedDomain - a live accepted domain has a trust-conferring DomainType
         (Authoritative/InternalRelay) but is not present in the known-domains config at all. The
         higher-severity direction: this domain has been silently granted in-organization trust for
         every FromScope-consuming rule in the tenant with no review recorded anywhere in Purview.
      4. ExternalRelayObserved  - any live accepted domain reports DomainType ExternalRelay. Always
         reported, regardless of known-domains config membership, because Microsoft documents this
         value as on-premises-Exchange-only (design.md Sec 2) - seeing it in a cloud tenant is itself
         worth investigating, most likely a hybrid Exchange coexistence artifact this script (which
         only authenticates to Exchange Online) cannot independently explain.

    Baseline/drift model (design.md Sec 4): every run overwrites a single JSON baseline snapshot,
    and every run after the first also diffs the current state against that PREVIOUS run's snapshot
    to detect Added/Removed/DomainTypeChanged/DefaultChanged/MatchSubDomainsChanged events since the
    last check - the concrete "newly-added accepted domain" signal the originating Red Team finding
    (scenarios/dspm-for-ai/copilot-external-email-block/reviews.md, Red Team finding 1) asked for.
    MatchSubDomains is checked independently of DomainType: a domain flipped to MatchSubDomains=$true
    silently extends in-organization trust to every subdomain without changing DomainType at all -
    this scenario's own reviews.md (Red Team finding 1) caught the first draft missing this check.
    These drift events are appended to a separate CSV log (replace-by-RunId on re-run, matching
    scenarios/data-estate-insights/classification-coverage-report's idempotency model).

    Creates, modifies, or deletes NO Purview or Exchange object. The only side effects are the three
    local files this script writes (baseline JSON, drift-log CSV, per-run findings JSON) - all three
    are gated behind $PSCmdlet.ShouldProcess(), so -WhatIf computes and prints every finding without
    touching disk. See rollback.md.

    Exit code: non-zero if any MissingExpectedDomain or UnexpectedTrustedDomain finding is present in
    this run (the two directions the originating Red Team finding treats as real risk, not just
    drift) - safe to wire into a scheduled task/CI job that should fail loudly on either. A
    DomainTypeMismatch or ExternalRelayObserved finding alone does not affect the exit code (see
    README.md Sec 8 for the operational reasoning).

    Author-only reference code. This script never establishes its own connection to a tenant. Run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Sec 3 - this is Exchange
    Online PowerShell, Surface 1, not Security & Compliance PowerShell), then call this script.

.PARAMETER KnownDomainsConfigPath
    Path to the buyer-curated known-domains JSON config (schema: deploy/KnownDomains.sample.json).
    No Microsoft-documented source can auto-derive this list (design.md Sec 6) - it must be
    maintained by hand, the same limitation any allowlist-based hygiene control has.

.PARAMETER BaselinePath
    Path to the single-snapshot JSON baseline file this script reads (if it exists) and overwrites
    each successful run. Omit an existing file for the first-ever run - the script reports every
    live domain as "no prior baseline to compare" rather than treating it as newly Added.

.PARAMETER DriftLogPath
    Path to the append/replace-by-RunId CSV drift log. Created with a header row if it doesn't
    already exist. One row is written per finding (all four categories, plus Added/Removed/Changed
    baseline-drift events) for this RunId.

.PARAMETER RunId
    Identifier for this report run, used both as a drift-log column and to make re-runs replace
    rather than duplicate. Defaults to the current UTC date ('yyyy-MM-dd').

.PARAMETER IncludeAuditAttribution
    If set, additionally queries Search-UnifiedAuditLog -RecordType ExchangeAdmin -Operations
    'Set-AcceptedDomain' over the -AuditLookbackDays window and includes matching events in the
    findings report, best-effort. Does NOT attribute a domain Added/Removed drift event - Exchange
    Online has no New-/Remove-AcceptedDomain cmdlet to audit (design.md Sec 5); only DomainType/
    Default changes on an already-existing accepted domain are in scope for this switch. VERIFY
    (pilot tenant): whether Set-AcceptedDomain is independently confirmed to appear under this
    RecordType/Operations pair - see design.md Sec 5 and README.md Sec 11.

.PARAMETER AuditLookbackDays
    -IncludeAuditAttribution only: how many days back to query Search-UnifiedAuditLog. Defaults to 7.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. All read-only Get-AcceptedDomain (and, if requested,
    Search-UnifiedAuditLog) calls still execute and every finding is printed, but none of the three
    output files is written.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain
    ./Export-AcceptedDomainsHygieneReport.ps1 -KnownDomainsConfigPath './KnownDomains.json' `
        -BaselinePath './out/accepted-domains-baseline.json' `
        -DriftLogPath './out/accepted-domains-drift-log.csv' -WhatIf

    Dry run: computes and prints every finding against live data, writes nothing to disk.

.EXAMPLE
    ./Export-AcceptedDomainsHygieneReport.ps1 -KnownDomainsConfigPath './KnownDomains.json' `
        -BaselinePath './out/accepted-domains-baseline.json' `
        -DriftLogPath './out/accepted-domains-drift-log.csv' -IncludeAuditAttribution

    Full run: computes findings, includes best-effort Set-AcceptedDomain audit-log attribution for
    the last 7 days, overwrites the baseline, and appends/replaces today's drift-log rows.

.NOTES
    VERIFY before production reliance (full detail: README.md Sec 11, design.md Sec 5):
    - Set-AcceptedDomain's appearance under RecordType ExchangeAdmin / Operations
      'Set-AcceptedDomain' in Search-UnifiedAuditLog is the general documented default for Exchange
      admin cmdlets, not independently confirmed for this specific cmdlet by a Microsoft-published
      worked example.
    - Domain Added/Removed drift events cannot be attributed to an admin/timestamp by this script -
      Exchange Online has no New-/Remove-AcceptedDomain cmdlet (both are on-premises-Exchange-only
      per Microsoft's own applicability statements); the likely attribution source (Microsoft Entra
      ID's "Add verified domain"/"Remove verified domain" DirectoryManagement audit activities) was
      confirmed to exist by name but not confirmed queryable via Search-UnifiedAuditLog's Operations
      filter by this build - not implemented for that reason, see design.md Sec 5.

    Sources (Microsoft Learn, verify before production use):
    - Get-AcceptedDomain reference: https://learn.microsoft.com/powershell/module/exchangepowershell/get-accepteddomain
    - Set-AcceptedDomain reference (-DomainType, -MatchSubDomains, -MakeDefault, cloud/on-premises
      applicability statement): https://learn.microsoft.com/powershell/module/exchangepowershell/set-accepteddomain
    - New-AcceptedDomain reference (-DomainType definitions, on-premises-only applicability):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-accepteddomain
    - Data loss prevention Exchange conditions and actions reference (FromScope/ExceptIfFromScope,
      UserScopeFrom): https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions
    - Search-UnifiedAuditLog reference: https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
    - Audit activity reference (Microsoft Entra ID DirectoryManagement domain activities):
      https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$KnownDomainsConfigPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DriftLogPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunId = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),

    [Parameter()]
    [switch]$IncludeAuditAttribution,

    [Parameter()]
    [ValidateRange(1, 90)]
    [int]$AuditLookbackDays = 7
)

$ErrorActionPreference = 'Stop'
$inOrganizationTypes = @('Authoritative', 'InternalRelay')

function Assert-ExchangeOnlineSession {
    # Get-AcceptedDomain is only exported after a successful Connect-ExchangeOnline; its absence
    # means the caller never connected (or connected to Security & Compliance PowerShell instead -
    # this scenario needs Exchange Online PowerShell, docs/automation-surface.md Surface 1).
    if (-not (Get-Command Get-AcceptedDomain -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md Sec 3) - this scenario is Surface 1 (Exchange Online), not Connect-IPPSSession.'
    }
}

Assert-ExchangeOnlineSession

# --- Load the buyer-curated known-domains config (design.md Sec 6: no auto-derivable source) ---
$knownConfig = Get-Content -Path $KnownDomainsConfigPath -Raw | ConvertFrom-Json
$knownByDomain = @{}
foreach ($entry in $knownConfig.knownDomains) {
    $knownByDomain[$entry.domainName.ToLowerInvariant()] = $entry
}

# --- Live accepted-domains state ---
$liveDomains = @(Get-AcceptedDomain -ResultSize Unlimited)
$liveByDomain = @{}
foreach ($domain in $liveDomains) {
    $liveByDomain[$domain.DomainName.ToLowerInvariant()] = $domain
}

Write-Host "Loaded $($knownByDomain.Count) known-domain config entr$(if ($knownByDomain.Count -eq 1) { 'y' } else { 'ies' }) and $($liveDomains.Count) live accepted domain(s)." -ForegroundColor Cyan

$findings = [System.Collections.Generic.List[pscustomobject]]::new()
function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'FAIL')][string]$Severity,
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$Detail
    )
    $findings.Add([pscustomobject]@{
        RunId      = $RunId
        Category   = $Category
        Severity   = $Severity
        DomainName = $DomainName
        Detail     = $Detail
    })
    $color = switch ($Severity) { 'FAIL' { 'Red' }; 'WARN' { 'Yellow' }; default { 'Gray' } }
    Write-Host "  [$Severity] $Category ($DomainName): $Detail" -ForegroundColor $color
}

# --- 1 & 2: known-domains config vs. live state ---
Write-Host "`nChecking known-domains config against live accepted domains..." -ForegroundColor Cyan
foreach ($known in $knownConfig.knownDomains) {
    $key = $known.domainName.ToLowerInvariant()
    $live = $liveByDomain[$key]

    if (-not $live) {
        if ($known.required) {
            Add-Finding -Category 'MissingExpectedDomain' -Severity 'FAIL' -DomainName $known.domainName `
                -Detail "Required known domain is absent from Get-AcceptedDomain. Mail from this domain is treated as external by every FromScope-consuming rule until this is corrected. Owner on file: $($known.owner)."
        }
        else {
            Add-Finding -Category 'MissingExpectedDomain' -Severity 'WARN' -DomainName $known.domainName `
                -Detail "Non-required known domain is absent from Get-AcceptedDomain. Owner on file: $($known.owner)."
        }
        continue
    }

    if ($live.DomainType -ne $known.expectedDomainType) {
        $wasInOrg = $inOrganizationTypes -contains $known.expectedDomainType
        $isInOrg = $inOrganizationTypes -contains $live.DomainType
        $boundaryChanged = $wasInOrg -ne $isInOrg
        Add-Finding -Category 'DomainTypeMismatch' -Severity $(if ($boundaryChanged) { 'FAIL' } else { 'WARN' }) -DomainName $known.domainName `
            -Detail "Live DomainType '$($live.DomainType)' differs from expected '$($known.expectedDomainType)'.$(if ($boundaryChanged) { ' This changes which side of the in-organization trust boundary the domain falls on for FromScope-consuming rules.' } else { ' Both types count as in-organization for FromScope purposes, so the trust boundary is unaffected, but this is unreviewed configuration drift.' })"
    }
}

# --- 3: live domains with trust-conferring DomainType not present in the known-domains config ---
Write-Host "`nChecking for unreviewed trusted domains..." -ForegroundColor Cyan
foreach ($live in $liveDomains) {
    $key = $live.DomainName.ToLowerInvariant()
    if ($knownByDomain.ContainsKey($key)) { continue }
    if ($inOrganizationTypes -contains $live.DomainType) {
        Add-Finding -Category 'UnexpectedTrustedDomain' -Severity 'FAIL' -DomainName $live.DomainName `
            -Detail "Accepted domain has trust-conferring DomainType '$($live.DomainType)' but is not present in the known-domains config. This domain is currently granted in-organization trust by every FromScope-consuming rule in the tenant with no reviewed record of why."
    }
}

# --- 4: ExternalRelay observed at all (on-premises-only value - surprising on a cloud tenant) ---
foreach ($live in $liveDomains) {
    if ($live.DomainType -eq 'ExternalRelay') {
        Add-Finding -Category 'ExternalRelayObserved' -Severity 'WARN' -DomainName $live.DomainName `
            -Detail 'DomainType is ExternalRelay, which Microsoft documents as available only in on-premises Exchange organizations (design.md Sec 2). Unexpected on an Exchange Online-only tenant - most likely explained by a hybrid Exchange coexistence configuration this script cannot independently see (it authenticates to Exchange Online only).'
    }
}

# --- Baseline diff: Added / Removed / DomainTypeChanged / DefaultChanged since the last run ---
Write-Host "`nComparing against the previous baseline (if any)..." -ForegroundColor Cyan
if (Test-Path -Path $BaselinePath -PathType Leaf) {
    $previous = Get-Content -Path $BaselinePath -Raw | ConvertFrom-Json
    $previousByDomain = @{}
    foreach ($entry in $previous.domains) { $previousByDomain[$entry.DomainName.ToLowerInvariant()] = $entry }

    foreach ($live in $liveDomains) {
        $key = $live.DomainName.ToLowerInvariant()
        $prior = $previousByDomain[$key]
        if (-not $prior) {
            $severity = if ($inOrganizationTypes -contains $live.DomainType) { 'FAIL' } else { 'WARN' }
            Add-Finding -Category 'DomainAddedSincePreviousRun' -Severity $severity -DomainName $live.DomainName `
                -Detail "Not present in the baseline recorded on $($previous.runId) ($($previous.runTimestampUtc)). DomainType: $($live.DomainType)."
            continue
        }
        # Independent checks, not elseif: a single run can legitimately change more than one of
        # DomainType/Default/MatchSubDomains on the same domain, and each is a distinct signal worth
        # its own finding rather than only the first one detected (reviews.md Red Team finding 1).
        if ($prior.DomainType -ne $live.DomainType) {
            Add-Finding -Category 'DomainTypeChangedSincePreviousRun' -Severity 'WARN' -DomainName $live.DomainName `
                -Detail "DomainType changed from '$($prior.DomainType)' (baseline: $($previous.runId)) to '$($live.DomainType)' (this run)."
        }
        if ($prior.Default -ne $live.Default) {
            Add-Finding -Category 'DefaultChangedSincePreviousRun' -Severity 'INFO' -DomainName $live.DomainName `
                -Detail "Default flag changed from '$($prior.Default)' (baseline: $($previous.runId)) to '$($live.Default)' (this run)."
        }
        if ($prior.MatchSubDomains -ne $live.MatchSubDomains) {
            # A flip to $true silently extends this domain's trust to every subdomain for every
            # FromScope-consuming rule - a real trust-boundary expansion, not cosmetic drift, even
            # though DomainType itself hasn't changed. Not covered by the DomainTypeChanged check
            # above (reviews.md Red Team finding 1).
            $severity = if ($live.MatchSubDomains -eq $true -and ($inOrganizationTypes -contains $live.DomainType)) { 'FAIL' } else { 'WARN' }
            Add-Finding -Category 'MatchSubDomainsChangedSincePreviousRun' -Severity $severity -DomainName $live.DomainName `
                -Detail "MatchSubDomains changed from '$($prior.MatchSubDomains)' (baseline: $($previous.runId)) to '$($live.MatchSubDomains)' (this run).$(if ($live.MatchSubDomains -eq $true) { ' This silently extends in-organization trust to every subdomain of this domain for FromScope-consuming rules.' })"
        }
    }
    foreach ($priorKey in $previousByDomain.Keys) {
        if (-not $liveByDomain.ContainsKey($priorKey)) {
            $priorEntry = $previousByDomain[$priorKey]
            Add-Finding -Category 'DomainRemovedSincePreviousRun' -Severity 'WARN' -DomainName $priorEntry.DomainName `
                -Detail "Present in the baseline recorded on $($previous.runId) (DomainType: $($priorEntry.DomainType)) but absent from this run's Get-AcceptedDomain output."
        }
    }
}
else {
    Write-Host "  No prior baseline found at '$BaselinePath' - this is treated as the first run. Nothing is reported as Added/Removed/Changed until a baseline exists." -ForegroundColor Yellow
}

# --- Optional best-effort audit attribution for Set-AcceptedDomain (design.md Sec 5) ---
$auditEvents = @()
if ($IncludeAuditAttribution) {
    Write-Host "`nQuerying Search-UnifiedAuditLog for Set-AcceptedDomain events (last $AuditLookbackDays day(s))..." -ForegroundColor Cyan
    Write-Warning 'VERIFY (pilot tenant): Set-AcceptedDomain is not independently confirmed to appear under RecordType ExchangeAdmin / Operations ''Set-AcceptedDomain'' by a Microsoft-published worked example - see README.md Sec 11 and design.md Sec 5. This does not attribute Added/Removed domain events - Exchange Online has no New-/Remove-AcceptedDomain cmdlet to audit.'
    $auditEvents = @(Search-UnifiedAuditLog -RecordType ExchangeAdmin -Operations 'Set-AcceptedDomain' `
        -StartDate ([datetime]::UtcNow.AddDays(-$AuditLookbackDays)) -EndDate ([datetime]::UtcNow))
    Write-Host "  Found $($auditEvents.Count) matching audit record(s)." -ForegroundColor $(if ($auditEvents.Count -gt 0) { 'Yellow' } else { 'Gray' })
}

# --- Summary ---
$failCount = @($findings | Where-Object Severity -eq 'FAIL').Count
$warnCount = @($findings | Where-Object Severity -eq 'WARN').Count
Write-Host "`nSummary: $($findings.Count) finding(s) - $failCount FAIL, $warnCount WARN, $($findings.Count - $failCount - $warnCount) INFO." `
    -ForegroundColor $(if ($failCount -gt 0) { 'Red' } elseif ($warnCount -gt 0) { 'Yellow' } else { 'Green' })

# --- Write output files (baseline overwrite, drift-log replace-by-RunId, per-run findings JSON) ---
$writeDescription = "Write/replace RunId '$RunId' row(s) in drift log '$DriftLogPath', overwrite baseline '$BaselinePath', and write this run's findings JSON"
if ($PSCmdlet.ShouldProcess($writeDescription, 'Write report files')) {
    $existingRows = @()
    if (Test-Path -Path $DriftLogPath -PathType Leaf) {
        $existingRows = @(Import-Csv -Path $DriftLogPath | Where-Object { $_.RunId -ne $RunId })
    }
    $newRows = $findings | Select-Object RunId, Category, Severity, DomainName, Detail
    ($existingRows + $newRows) | Sort-Object RunId, Category, DomainName | Export-Csv -Path $DriftLogPath -NoTypeInformation

    $baseline = [pscustomobject]@{
        runId           = $RunId
        runTimestampUtc = [datetime]::UtcNow.ToString('o')
        domains         = $liveDomains | Select-Object DomainName, DomainType, Default, MatchSubDomains
    }
    $baseline | ConvertTo-Json -Depth 10 | Set-Content -Path $BaselinePath -Encoding utf8

    $findingsPath = Join-Path (Split-Path -Path $DriftLogPath -Parent) "$RunId-accepted-domains-findings.json"
    [pscustomobject]@{
        runId       = $RunId
        findings    = $findings
        auditEvents = $auditEvents | Select-Object CreationDate, UserIds, Operations, RecordType
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $findingsPath -Encoding utf8

    Write-Host "`nBaseline updated: $BaselinePath" -ForegroundColor Cyan
    Write-Host "Drift log updated: $DriftLogPath" -ForegroundColor Cyan
    Write-Host "Findings written: $findingsPath" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $writeDescription"
}

if ($failCount -gt 0) { exit 1 }
```

#### `KnownDomains.sample.json`

```json
{
  "_comment": "Sample known-domains hygiene config. Copy to KnownDomains.json and edit for your tenant before running deploy/Export-AcceptedDomainsHygieneReport.ps1 - see README.md Sec 5/6. No Microsoft-documented source can auto-derive this list (design.md Sec 6): every entry is a human decision about which domains this tenant's admins have reviewed and expect to see as accepted, and with what DomainType.",
  "knownDomains": [
    {
      "domainName": "contoso.com",
      "expectedDomainType": "Authoritative",
      "required": true,
      "owner": "IT - primary tenant domain"
    },
    {
      "domainName": "contoso.onmicrosoft.com",
      "expectedDomainType": "Authoritative",
      "required": true,
      "owner": "IT - default tenant domain, always accepted, do not remove"
    },
    {
      "domainName": "eu.contoso.com",
      "expectedDomainType": "Authoritative",
      "required": true,
      "owner": "IT - EU subsidiary, multi-geo data residency scope"
    },
    {
      "domainName": "hybrid.contoso.com",
      "expectedDomainType": "InternalRelay",
      "required": true,
      "owner": "IT - on-premises Exchange hybrid coexistence domain, still under this organization's authority per Microsoft's InternalRelay definition (design.md Sec 2). Confirmed correct for an active (not-yet-fully-migrated) coexistence domain - see accepted-domains-hygiene-check-on-premises/design.md Sec 4; revisit to Authoritative only once all recipients for this domain exist in Exchange Online."
    }
  ]
}
```