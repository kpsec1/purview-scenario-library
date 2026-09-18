---
part: "deploy"
parent: "dlp/accepted-domains-hygiene-check-on-premises"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Export-OnPremisesAcceptedDomainsHygieneReport.ps1`

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    On-premises Exchange companion to scenarios/dlp/accepted-domains-hygiene-check: runs the same
    known-domains hygiene and baseline-drift checks against an on-premises Exchange Management Shell
    session, and optionally cross-references the cloud scenario's last recorded baseline to detect
    hybrid-specific drift between the two environments.

.DESCRIPTION
    scenarios/dlp/accepted-domains-hygiene-check authenticates to Exchange Online only, so a hybrid
    tenant's on-premises accepted domains - including the only place DomainType ExternalRelay is
    actually reachable (design.md Sec 2) - are entirely invisible to it (that scenario's design.md
    Sec 7, disclosed non-goal). This script is the companion that closes that gap by running an
    equivalent check against on-premises Get-AcceptedDomain instead.

    Computes the same four core finding categories as the parent scenario (design.md Sec 2/6 there),
    entirely from read-only Get-AcceptedDomain (and, optionally, Search-AdminAuditLog) calls against
    an ALREADY-ESTABLISHED on-premises Exchange remote PowerShell session (this script never connects
    itself - see README.md Sec 5 and design.md Sec 3 for why):
      1. MissingExpectedDomain   - a known-domains config entry marked Required is absent from the
         on-premises Get-AcceptedDomain output.
      2. DomainTypeMismatch      - a known domain is present on-premises but its live DomainType
         differs from the config's ExpectedDomainType.
      3. UnexpectedTrustedDomain - an on-premises accepted domain has a trust-conferring DomainType
         (Authoritative/InternalRelay) but is not present in the known-domains config at all.
      4. ExternalRelayObserved   - reported as INFO here, not WARN as in the parent - ExternalRelay is
         EXPECTED and normal on-premises (design.md Sec 2), unlike the parent's cloud-only context
         where it is inherently surprising.

    Plus three finding categories unique to this companion (design.md Sec 4), only computed when
    -CloudBaselinePath is supplied - one per independently-checked field, the same per-field-category
    convention the baseline-diff block below already uses for DomainTypeChangedSincePreviousRun/
    DefaultChangedSincePreviousRun/MatchSubDomainsChangedSincePreviousRun, chosen deliberately (over a
    single overloaded category) so the drift log's (RunId, Category, DomainName) row key stays unique
    even when one domain diverges on more than one field in the same run:
      5. CrossEnvironmentMismatch              - DomainType differs where neither side is ExternalRelay
         (an on-premises-only value never expected to have a cloud counterpart). FAIL if the two sides
         disagree on the in-organization trust boundary, WARN if both are in-organization types that
         simply differ.
      6. CrossEnvironmentMatchSubDomainsMismatch - MatchSubDomains differs where neither side's
         DomainType is ExternalRelay. FAIL if either side has it set to $true (one environment silently
         accepts mail for every subdomain of this domain while the other does not - an asymmetric
         attack surface), WARN otherwise.
      7. CrossEnvironmentDefaultMismatch         - Default differs where neither side's DomainType is
         ExternalRelay. Always WARN - each environment computes its own default accepted domain
         independently in a hybrid deployment (two separate organizations), so a difference alone is
         not a misconfiguration, but is unreviewed drift worth a human confirming.

    Baseline/drift model: identical shape and replace-by-RunId idempotency to the parent scenario
    (parent design.md Sec 4), but written to entirely separate -BaselinePath/-DriftLogPath files -
    never the parent's own files (design.md Sec 6). -CloudBaselinePath is read-only input, never
    written to.

    Creates, modifies, or deletes NO Exchange or Purview object. The only side effects are the three
    local files this script writes (baseline JSON, drift-log CSV, per-run findings JSON) - all three
    are gated behind $PSCmdlet.ShouldProcess(), so -WhatIf computes and prints every finding without
    touching disk. See rollback.md.

    Author-only reference code. This script never establishes its own connection to a tenant or
    server. Run the on-premises remote PowerShell connection pattern yourself first (README.md Sec 5,
    design.md Sec 3/8 - New-PSSession -ConfigurationName Microsoft.Exchange plus Import-PSSession),
    then call this script. Do NOT also have a Connect-ExchangeOnline session imported into the same
    PowerShell process unless you have re-imported one of the two sessions with -Prefix - both sessions
    export a proxy cmdlet literally named Get-AcceptedDomain and the second import silently wins the
    unqualified name (design.md Sec 3).

    Exit code: non-zero if any MissingExpectedDomain, UnexpectedTrustedDomain, or (when
    -CloudBaselinePath is supplied) trust-boundary-crossing CrossEnvironmentMismatch finding is present
    in this run - same alerting contract as the parent scenario's deploy script.

.PARAMETER KnownDomainsConfigPath
    Path to the SAME buyer-curated known-domains JSON config the parent scenario uses (schema:
    ../accepted-domains-hygiene-check/deploy/KnownDomains.sample.json). Reused, not duplicated -
    design.md Sec 7: a domain's reviewed status is a business decision independent of which Exchange
    environment currently hosts its mail.

.PARAMETER BaselinePath
    Path to this scenario's OWN single-snapshot JSON baseline file (on-premises state), read (if it
    exists) and overwritten each successful run. Must not point at the parent scenario's baseline file
    - keep the two environments' baselines separate (design.md Sec 6).

.PARAMETER DriftLogPath
    Path to this scenario's OWN append/replace-by-RunId CSV drift log (on-premises state). Same shape
    as the parent scenario's drift log, but a separate file.

.PARAMETER CloudBaselinePath
    Optional. Path to the PARENT scenario's own -BaselinePath output file (a plain, read-only JSON
    read - no live Exchange Online connection is opened by this script, design.md Sec 3). When
    supplied, additionally computes CrossEnvironmentMismatch findings (design.md Sec 4). Omit to run
    the on-premises-only checks (1-4) without cross-environment reconciliation.

.PARAMETER RunId
    Identifier for this report run. Defaults to the current UTC date ('yyyy-MM-dd'). Same
    replace-by-RunId semantics as the parent scenario.

.PARAMETER DomainControllerFqdn
    Optional. Passed through to Get-AcceptedDomain -DomainController - an on-premises-only parameter
    (design.md Sec 2) specifying which Active Directory domain controller to read from. Useful in a
    multi-DC environment with known replication lag; omit to let Exchange pick automatically.

.PARAMETER IncludeAuditAttribution
    If set, additionally queries Search-AdminAuditLog -Cmdlets 'Set-AcceptedDomain',
    'New-AcceptedDomain','Remove-AcceptedDomain' over the -AuditLookbackDays window (capped in
    practice by the on-premises organization's own -AdminAuditLogAgeLimit, 90 days by default -
    design.md Sec 2) and includes matching events in the findings report, best-effort. Unlike the
    parent scenario's -IncludeAuditAttribution, this DOES cover domain Added/Removed events - both
    New-AcceptedDomain and Remove-AcceptedDomain are real, on-premises-auditable cmdlets (design.md
    Sec 5), a genuine capability gap the on-premises side closes relative to cloud.
    VERIFY (pilot tenant, or a future Microsoft Learn pass, before production reliance): the exact
    DEFAULT value of -AdminAuditLogCmdlets (which cmdlets a fresh install audits out of the box) was
    not confirmed by this build's grounding pass - see design.md Sec 2 and README.md Sec 11. Run
    `Get-AdminAuditLogConfig | Select-Object AdminAuditLogCmdlets` first and confirm it includes
    Set-AcceptedDomain/New-AcceptedDomain/Remove-AcceptedDomain (or '*') before relying on this
    switch's output for an incident investigation.

.PARAMETER AuditLookbackDays
    -IncludeAuditAttribution only: how many days back to query Search-AdminAuditLog. Defaults to 7.
    Values beyond the on-premises organization's own -AdminAuditLogAgeLimit (90 days by default) will
    silently find nothing older than that limit, regardless of what actually happened - design.md Sec 2.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. All read-only Get-AcceptedDomain (and, if requested,
    Search-AdminAuditLog) calls still execute and every finding is printed, but none of the three
    output files is written.

.EXAMPLE
    # On the machine/session with the on-premises Exchange remote session imported (README.md Sec 5):
    ./Export-OnPremisesAcceptedDomainsHygieneReport.ps1 `
        -KnownDomainsConfigPath '../../accepted-domains-hygiene-check/deploy/KnownDomains.json' `
        -BaselinePath './out/onprem-accepted-domains-baseline.json' `
        -DriftLogPath './out/onprem-accepted-domains-drift-log.csv' `
        -WhatIf

    Dry run against on-premises state only: computes and prints every finding, writes nothing to disk.

.EXAMPLE
    ./Export-OnPremisesAcceptedDomainsHygieneReport.ps1 `
        -KnownDomainsConfigPath '../../accepted-domains-hygiene-check/deploy/KnownDomains.json' `
        -BaselinePath './out/onprem-accepted-domains-baseline.json' `
        -DriftLogPath './out/onprem-accepted-domains-drift-log.csv' `
        -CloudBaselinePath '../../accepted-domains-hygiene-check/deploy/out/accepted-domains-baseline.json' `
        -IncludeAuditAttribution

    Full run: on-premises findings, cross-environment reconciliation against the cloud scenario's most
    recent baseline (file read only, no live cloud connection), best-effort Search-AdminAuditLog
    attribution for Set-/New-/Remove-AcceptedDomain over the last 7 days, overwrites the on-premises
    baseline, and appends/replaces today's drift-log rows.

.NOTES
    VERIFY before production reliance (full detail: README.md Sec 11, design.md Sec 2/4):
    - The default value of -AdminAuditLogCmdlets (whether a fresh on-premises install audits
      Set-/New-/Remove-AcceptedDomain without explicit configuration) was not confirmed by this
      build's grounding pass.
    - Which DomainType (Authoritative vs. InternalRelay) is "correct" for a shared-namespace hybrid
      domain depends on that domain's actual migration/coexistence state and is not resolved to a
      single rule by this script - a CrossEnvironmentMismatch WARN is not automatically a misconfig.
    - Set-AcceptedDomain's own reference documents -MakeDefault as "specifies whether the accepted
      domain is the default domain" but never states outright that only one accepted domain can be
      Default at a time in a given organization - this script's Default cross-environment check (added
      in a later build, design.md Sec 4/9) treats each environment's Default flag as independently
      computed rather than asserting a single-default invariant it could not confirm.

    Sources (Microsoft Learn, fetched via the canonical MicrosoftDocs GitHub source this build - see
    README.md Sec 12 for full citations; verify against learn.microsoft.com before production use):
    - Get-AcceptedDomain reference (on-premises + cloud applicability, -DomainController):
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-accepteddomain
    - Set-AcceptedDomain reference (-MatchSubDomains: "enables mail to be sent by and received from
      users on any subdomain of this accepted domain," default $false; -MakeDefault: "specifies whether
      the accepted domain is the default domain"), fetched directly from the canonical MicrosoftDocs
      GitHub source in the build that added the MatchSubDomains/Default cross-environment checks:
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-accepteddomain
    - New-AcceptedDomain / Remove-AcceptedDomain references (on-premises-only applicability):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-accepteddomain
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-accepteddomain
    - Search-AdminAuditLog reference (on-premises-only applicability, -Cmdlets parameter):
      https://learn.microsoft.com/powershell/module/exchangepowershell/search-adminauditlog
    - Set-AdminAuditLogConfig reference (-AdminAuditLogEnabled default $true, -AdminAuditLogAgeLimit
      default 90 days): https://learn.microsoft.com/powershell/module/exchangepowershell/set-adminauditlogconfig
    - Connect to Exchange servers using remote PowerShell (New-PSSession/Import-PSSession pattern):
      https://learn.microsoft.com/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    - Import-PSSession reference (-Prefix, name-collision behavior):
      https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/import-pssession
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
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CloudBaselinePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunId = ([datetime]::UtcNow.ToString('yyyy-MM-dd')),

    [Parameter()]
    [string]$DomainControllerFqdn,

    [Parameter()]
    [switch]$IncludeAuditAttribution,

    [Parameter()]
    [ValidateRange(1, 90)]
    [int]$AuditLookbackDays = 7
)

$ErrorActionPreference = 'Stop'
$inOrganizationTypes = @('Authoritative', 'InternalRelay')

function Assert-OnPremisesExchangeSession {
    # Get-AcceptedDomain is only exported after a successful on-premises remote PowerShell import
    # (New-PSSession -ConfigurationName Microsoft.Exchange + Import-PSSession, design.md Sec 3/8).
    # Its absence means the caller never imported the session (or is holding a Connect-ExchangeOnline
    # session instead - that also exports a cmdlet with this exact name).
    $commands = @(Get-Command Get-AcceptedDomain -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        throw 'No on-premises Exchange remote PowerShell session found. Run New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://<ServerFQDN>/PowerShell/ -Authentication Kerberos, then Import-PSSession, first (see README.md Sec 5) - this scenario needs an on-premises Exchange Management Shell session, not Connect-ExchangeOnline.'
    }
    # -All surfaces every loaded command with this name across every module/session-state, not just
    # the one PowerShell would resolve unqualified - the one reliable way to detect the exact
    # collision design.md Sec 3 documents (a Connect-ExchangeOnline session and an on-premises
    # Import-PSSession session both export a proxy cmdlet literally named Get-AcceptedDomain). Added
    # after this build's own Red Team review flagged that the earlier version of this check could
    # silently query the WRONG environment and report a clean, false-negative result (reviews.md).
    if ($commands.Count -gt 1) {
        Write-Warning "Multiple 'Get-AcceptedDomain' commands are loaded in this session ($($commands.Count) found, from module(s): $(($commands | ForEach-Object { $_.ModuleName }) -join ', ')) - this is the exact Import-PSSession/Connect-ExchangeOnline name collision documented in design.md Sec 3. This run will use whichever one PowerShell resolves for an unqualified call, which may silently be Exchange Online rather than on-premises Exchange - a false-negative risk for every finding this script computes. Re-import one session with -Prefix (e.g. Import-PSSession `$OnPremSession -Prefix OnPrem) and re-run using the disambiguated cmdlet name, or close the other session, before trusting this run's results."
    }
}

Assert-OnPremisesExchangeSession

# --- Load the buyer-curated known-domains config - SAME file the parent scenario uses (design.md Sec 7) ---
$knownConfig = Get-Content -Path $KnownDomainsConfigPath -Raw | ConvertFrom-Json
$knownByDomain = @{}
foreach ($entry in $knownConfig.knownDomains) {
    $knownByDomain[$entry.domainName.ToLowerInvariant()] = $entry
}

# --- Live on-premises accepted-domains state ---
$getAcceptedDomainParams = @{ ResultSize = 'Unlimited' }
if ($DomainControllerFqdn) { $getAcceptedDomainParams['DomainController'] = $DomainControllerFqdn }
$liveDomains = @(Get-AcceptedDomain @getAcceptedDomainParams)
$liveByDomain = @{}
foreach ($domain in $liveDomains) {
    $liveByDomain[$domain.DomainName.ToLowerInvariant()] = $domain
}

Write-Host "Loaded $($knownByDomain.Count) known-domain config entr$(if ($knownByDomain.Count -eq 1) { 'y' } else { 'ies' }) and $($liveDomains.Count) live on-premises accepted domain(s)." -ForegroundColor Cyan

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

# --- 1 & 2: known-domains config vs. live on-premises state ---
Write-Host "`nChecking known-domains config against live on-premises accepted domains..." -ForegroundColor Cyan
foreach ($known in $knownConfig.knownDomains) {
    $key = $known.domainName.ToLowerInvariant()
    $live = $liveByDomain[$key]

    if (-not $live) {
        if ($known.required) {
            Add-Finding -Category 'MissingExpectedDomain' -Severity 'FAIL' -DomainName $known.domainName `
                -Detail "Required known domain is absent from on-premises Get-AcceptedDomain. Owner on file: $($known.owner). Note: absence here alone is not necessarily wrong for a domain that's cloud-only (e.g. *.onmicrosoft.com) - confirm this domain is actually expected to exist on-premises before treating this as an incident."
        }
        else {
            Add-Finding -Category 'MissingExpectedDomain' -Severity 'WARN' -DomainName $known.domainName `
                -Detail "Non-required known domain is absent from on-premises Get-AcceptedDomain. Owner on file: $($known.owner)."
        }
        continue
    }

    if ($live.DomainType -ne $known.expectedDomainType) {
        $wasInOrg = $inOrganizationTypes -contains $known.expectedDomainType
        $isInOrg = $inOrganizationTypes -contains $live.DomainType
        $boundaryChanged = $wasInOrg -ne $isInOrg
        Add-Finding -Category 'DomainTypeMismatch' -Severity $(if ($boundaryChanged) { 'FAIL' } else { 'WARN' }) -DomainName $known.domainName `
            -Detail "Live on-premises DomainType '$($live.DomainType)' differs from expected '$($known.expectedDomainType)'.$(if ($boundaryChanged) { ' This changes which side of the in-organization trust boundary the domain falls on.' } else { ' Both types count as in-organization, so the trust boundary is unaffected, but this is unreviewed configuration drift.' })"
    }
}

# --- 3: live on-premises domains with trust-conferring DomainType not present in the known-domains config ---
Write-Host "`nChecking for unreviewed trusted domains (on-premises)..." -ForegroundColor Cyan
foreach ($live in $liveDomains) {
    $key = $live.DomainName.ToLowerInvariant()
    if ($knownByDomain.ContainsKey($key)) { continue }
    if ($inOrganizationTypes -contains $live.DomainType) {
        Add-Finding -Category 'UnexpectedTrustedDomain' -Severity 'FAIL' -DomainName $live.DomainName `
            -Detail "On-premises accepted domain has trust-conferring DomainType '$($live.DomainType)' but is not present in the known-domains config. Since New-AcceptedDomain is a real, auditable on-premises cmdlet (design.md Sec 5), -IncludeAuditAttribution has a real chance of identifying who added it - unlike the parent cloud scenario's equivalent finding."
    }
}

# --- 4: ExternalRelay observed (expected and normal on-premises - INFO, not WARN as in the parent) ---
foreach ($live in $liveDomains) {
    if ($live.DomainType -eq 'ExternalRelay') {
        Add-Finding -Category 'ExternalRelayObserved' -Severity 'INFO' -DomainName $live.DomainName `
            -Detail 'DomainType is ExternalRelay. Expected and normal on an on-premises Exchange organization (design.md Sec 2) - unlike the parent cloud scenario, this is not a surprising finding here. Confirm the relay target is still correct as part of routine review.'
    }
}

# --- Baseline diff: Added / Removed / DomainTypeChanged / DefaultChanged / MatchSubDomainsChanged ---
Write-Host "`nComparing against the previous on-premises baseline (if any)..." -ForegroundColor Cyan
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
                -Detail "Not present in the on-premises baseline recorded on $($previous.runId) ($($previous.runTimestampUtc)). DomainType: $($live.DomainType)."
            continue
        }
        if ($prior.DomainType -ne $live.DomainType) {
            Add-Finding -Category 'DomainTypeChangedSincePreviousRun' -Severity 'WARN' -DomainName $live.DomainName `
                -Detail "DomainType changed from '$($prior.DomainType)' (baseline: $($previous.runId)) to '$($live.DomainType)' (this run)."
        }
        if ($prior.Default -ne $live.Default) {
            Add-Finding -Category 'DefaultChangedSincePreviousRun' -Severity 'INFO' -DomainName $live.DomainName `
                -Detail "Default flag changed from '$($prior.Default)' (baseline: $($previous.runId)) to '$($live.Default)' (this run)."
        }
        if ($prior.MatchSubDomains -ne $live.MatchSubDomains) {
            $severity = if ($live.MatchSubDomains -eq $true -and ($inOrganizationTypes -contains $live.DomainType)) { 'FAIL' } else { 'WARN' }
            Add-Finding -Category 'MatchSubDomainsChangedSincePreviousRun' -Severity $severity -DomainName $live.DomainName `
                -Detail "MatchSubDomains changed from '$($prior.MatchSubDomains)' (baseline: $($previous.runId)) to '$($live.MatchSubDomains)' (this run).$(if ($live.MatchSubDomains -eq $true) { ' This silently extends in-organization trust to every subdomain of this domain.' })"
        }
    }
    foreach ($priorKey in $previousByDomain.Keys) {
        if (-not $liveByDomain.ContainsKey($priorKey)) {
            $priorEntry = $previousByDomain[$priorKey]
            Add-Finding -Category 'DomainRemovedSincePreviousRun' -Severity 'WARN' -DomainName $priorEntry.DomainName `
                -Detail "Present in the on-premises baseline recorded on $($previous.runId) (DomainType: $($priorEntry.DomainType)) but absent from this run's Get-AcceptedDomain output."
        }
    }
}
else {
    Write-Host "  No prior on-premises baseline found at '$BaselinePath' - this is treated as the first run. Nothing is reported as Added/Removed/Changed until a baseline exists." -ForegroundColor Yellow
}

# --- 5 (optional): cross-environment reconciliation against the cloud scenario's own baseline (design.md Sec 4) ---
if ($CloudBaselinePath) {
    Write-Host "`nCross-referencing against the cloud scenario's baseline: $CloudBaselinePath..." -ForegroundColor Cyan
    $cloud = Get-Content -Path $CloudBaselinePath -Raw | ConvertFrom-Json
    $cloudByDomain = @{}
    foreach ($entry in $cloud.domains) { $cloudByDomain[$entry.DomainName.ToLowerInvariant()] = $entry }

    foreach ($live in $liveDomains) {
        $key = $live.DomainName.ToLowerInvariant()
        $cloudEntry = $cloudByDomain[$key]
        if (-not $cloudEntry) { continue }
        if ($live.DomainType -eq 'ExternalRelay' -or $cloudEntry.DomainType -eq 'ExternalRelay') { continue }

        if ($live.DomainType -ne $cloudEntry.DomainType) {
            $onPremInOrg = $inOrganizationTypes -contains $live.DomainType
            $cloudInOrg = $inOrganizationTypes -contains $cloudEntry.DomainType
            $boundaryDisagreement = $onPremInOrg -ne $cloudInOrg
            Add-Finding -Category 'CrossEnvironmentMismatch' -Severity $(if ($boundaryDisagreement) { 'FAIL' } else { 'WARN' }) -DomainName $live.DomainName `
                -Detail "On-premises DomainType '$($live.DomainType)' differs from the cloud baseline's recorded DomainType '$($cloudEntry.DomainType)' (cloud baseline: $($cloud.runId)).$(if ($boundaryDisagreement) { ' The two environments disagree on which side of the in-organization trust boundary this domain falls on - FromScope-consuming DLP rules in Exchange Online only ever see the CLOUD side of this disagreement.' } else { " Both sides are in-organization types that simply differ - not automatically a misconfiguration (design.md Sec 4); confirm against this domain's actual migration/coexistence state and the known-domains config's owner field." })"
        }

        # design.md Sec 4/Sec 9: adds two sibling categories to CrossEnvironmentMismatch, once a
        # concrete buyer need surfaced (PROGRESS.md follow-up) - separate categories, not additional
        # findings under the same 'CrossEnvironmentMismatch' name, so a domain that diverges on more
        # than one field never collides on the drift log's (RunId, Category, DomainName) row key. Same
        # ExternalRelay exclusion above applies to both new checks.
        if ($live.MatchSubDomains -ne $cloudEntry.MatchSubDomains) {
            $eitherExtendsSubdomainTrust = ($live.MatchSubDomains -eq $true) -or ($cloudEntry.MatchSubDomains -eq $true)
            Add-Finding -Category 'CrossEnvironmentMatchSubDomainsMismatch' -Severity $(if ($eitherExtendsSubdomainTrust) { 'FAIL' } else { 'WARN' }) -DomainName $live.DomainName `
                -Detail "On-premises MatchSubDomains '$($live.MatchSubDomains)' differs from the cloud baseline's recorded MatchSubDomains '$($cloudEntry.MatchSubDomains)' (cloud baseline: $($cloud.runId)).$(if ($eitherExtendsSubdomainTrust) { ' One environment silently accepts mail for every subdomain of this domain (Set-AcceptedDomain -MatchSubDomains reference) while the other does not - an attacker-registered subdomain would be treated as in-organization only on the side with MatchSubDomains=$true, an asymmetric attack surface the FromScope-consuming side cannot see if it is the more restrictive one.' } else { ' Both sides report the same effective non-extension of subdomain trust; this branch should be unreachable in practice but is evaluated defensively.' })"
        }

        if ($live.Default -ne $cloudEntry.Default) {
            Add-Finding -Category 'CrossEnvironmentDefaultMismatch' -Severity 'WARN' -DomainName $live.DomainName `
                -Detail "On-premises Default flag '$($live.Default)' differs from the cloud baseline's recorded Default flag '$($cloudEntry.Default)' (cloud baseline: $($cloud.runId)). Each environment computes its own default accepted domain independently (Set-AcceptedDomain -MakeDefault reference) - a hybrid deployment legitimately runs two separate organizations, each with its own default, so this alone is not a misconfiguration. Confirm which domain each side's new-recipient primary SMTP address generation actually targets is intentional before closing this finding."
        }
    }
    Write-Host "  Cross-environment reconciliation complete (cloud baseline recorded $($cloud.runId), $($cloud.domains.Count) domain(s))." -ForegroundColor Cyan
}
else {
    Write-Host "`nSkipping cross-environment reconciliation - pass -CloudBaselinePath (pointing at the parent scenario's own -BaselinePath output) to enable it." -ForegroundColor Yellow
}

# --- Optional best-effort audit attribution (design.md Sec 5 - genuinely closes part of the parent's gap) ---
$auditEvents = @()
if ($IncludeAuditAttribution) {
    Write-Host "`nQuerying Search-AdminAuditLog for Set-/New-/Remove-AcceptedDomain events (last $AuditLookbackDays day(s))..." -ForegroundColor Cyan
    if (-not (Get-Command Search-AdminAuditLog -ErrorAction SilentlyContinue)) {
        Write-Warning 'Search-AdminAuditLog is not available in this session. It is on-premises-Exchange-only (design.md Sec 2) - confirm the imported session is the on-premises Exchange remote session, not Connect-ExchangeOnline. Skipping audit attribution for this run.'
    }
    else {
        Write-Warning 'VERIFY (pilot tenant): the DEFAULT value of -AdminAuditLogCmdlets (whether a fresh install audits these three cmdlets without explicit configuration) was not confirmed by this build - see README.md Sec 11 and design.md Sec 2. Run Get-AdminAuditLogConfig | Select-Object AdminAuditLogCmdlets to confirm coverage before relying on this output for an investigation. Also note the 90-day default -AdminAuditLogAgeLimit caps how far back this query can ever see, regardless of -AuditLookbackDays.'
        $auditEvents = @(Search-AdminAuditLog -Cmdlets 'Set-AcceptedDomain', 'New-AcceptedDomain', 'Remove-AcceptedDomain' `
            -StartDate ([datetime]::UtcNow.AddDays(-$AuditLookbackDays)) -EndDate ([datetime]::UtcNow))
        Write-Host "  Found $($auditEvents.Count) matching admin audit log record(s)." -ForegroundColor $(if ($auditEvents.Count -gt 0) { 'Yellow' } else { 'Gray' })
    }
}

# --- Summary ---
$failCount = @($findings | Where-Object Severity -eq 'FAIL').Count
$warnCount = @($findings | Where-Object Severity -eq 'WARN').Count
Write-Host "`nSummary: $($findings.Count) finding(s) - $failCount FAIL, $warnCount WARN, $($findings.Count - $failCount - $warnCount) INFO." `
    -ForegroundColor $(if ($failCount -gt 0) { 'Red' } elseif ($warnCount -gt 0) { 'Yellow' } else { 'Green' })

# --- Write output files (on-premises baseline overwrite, drift-log replace-by-RunId, findings JSON) ---
$writeDescription = "Write/replace RunId '$RunId' row(s) in on-premises drift log '$DriftLogPath', overwrite on-premises baseline '$BaselinePath', and write this run's findings JSON"
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
        environment     = 'on-premises'
        domains         = $liveDomains | Select-Object DomainName, DomainType, Default, MatchSubDomains
    }
    $baseline | ConvertTo-Json -Depth 10 | Set-Content -Path $BaselinePath -Encoding utf8

    $findingsPath = Join-Path (Split-Path -Path $DriftLogPath -Parent) "$RunId-onprem-accepted-domains-findings.json"
    [pscustomobject]@{
        runId       = $RunId
        findings    = $findings
        auditEvents = $auditEvents | Select-Object RunDate, Caller, CmdletName, Succeeded, ObjectModified
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $findingsPath -Encoding utf8

    Write-Host "`nOn-premises baseline updated: $BaselinePath" -ForegroundColor Cyan
    Write-Host "On-premises drift log updated: $DriftLogPath" -ForegroundColor Cyan
    Write-Host "Findings written: $findingsPath" -ForegroundColor Cyan
}
else {
    Write-Verbose "WhatIf: would $writeDescription"
}

if ($failCount -gt 0) { exit 1 }
```