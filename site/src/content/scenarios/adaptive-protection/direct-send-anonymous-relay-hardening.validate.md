---
part: "validate"
parent: "adaptive-protection/direct-send-anonymous-relay-hardening"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-DirectSendHardening.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Validates Direct Send / anonymous relay hardening: the audit rule's shape, the tenant-wide
    RejectDirectSend gate, the InboundConnector IP-authentication risk audit, and expected
    certificate-based relay connector coverage.

.DESCRIPTION
    Read-only. Makes no changes. Four checks:
      1. Audit rule exists with the expected shape (Mode = Audit, condition, action).
      2. Tenant-wide RejectDirectSend, if expected to be set.
      3. InboundConnector IP-authentication risk heuristic (same logic as deploy script) - every
         flagged connector is reported as WARN, never FAIL (design.md Section 5 - this is a
         disclosed heuristic, not a hard requirement).
      4. Each -ExpectedRelayConnectors entry: exists with RestrictDomainsToCertificate = $true.

.PARAMETER RuleName
    Must match deploy time. Defaults to 'Direct Send Detection (Audit)'.

.PARAMETER MaxIpRangeCidrBits
    Must match deploy time for a consistent re-audit. Defaults to 24.

.PARAMETER ExpectRejectDirectSend
    If set, FAILs when Get-OrganizationConfig's RejectDirectSend is not $true. If not set, only
    reports the current value as INFO.

.PARAMETER ExpectedRelayConnectors
    Names of certificate-based relay connectors that should exist. Each one missing, or present but
    not RestrictDomainsToCertificate = $true, is a FAIL.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Test-DirectSendHardening.ps1 -ExpectRejectDirectSend `
        -ExpectedRelayConnectors 'Contoso Scan-to-Email (Certificate)'

.NOTES
    Sources: same as deploy/New-DirectSendHardening.ps1's .NOTES block.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RuleName = 'Direct Send Detection (Audit)',

    [Parameter()]
    [ValidateRange(0, 32)]
    [int]$MaxIpRangeCidrBits = 24,

    [Parameter()]
    [switch]$ExpectRejectDirectSend,

    [Parameter()]
    [string[]]$ExpectedRelayConnectors = @()
)

$ErrorActionPreference = 'Stop'
$script:FailCount = 0
$script:WarnCount = 0

function Write-Check {
    param([ValidateSet('PASS', 'FAIL', 'WARN', 'INFO')][string]$Status, [string]$Message)
    $color = switch ($Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'INFO' { 'Cyan' } }
    Write-Host "  [$Status] $Message" -ForegroundColor $color
    if ($Status -eq 'FAIL') { $script:FailCount++ }
    if ($Status -eq 'WARN') { $script:WarnCount++ }
}

if (-not (Get-Command Get-TransportRule -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first.'
}

Write-Host 'Validating Direct Send / anonymous relay hardening...' -ForegroundColor Cyan
Write-Host '--- Check 1: audit rule shape ---' -ForegroundColor Cyan

$rule = Get-TransportRule -Identity $RuleName -ErrorAction SilentlyContinue
if (-not $rule) {
    Write-Check FAIL "Audit rule '$RuleName' does not exist."
}
else {
    $shapeOk = ($rule.Mode -eq 'Audit') -and
    ($rule.SentToScope -eq 'InOrganization') -and
    ($rule.HeaderContainsMessageHeader -eq 'X-MS-Exchange-Organization-AuthAs')
    if ($shapeOk) {
        Write-Check PASS "Audit rule '$RuleName' exists with the expected shape (Mode = Audit, SentToScope = InOrganization, AuthAs condition)."
    }
    else {
        Write-Check FAIL "Audit rule '$RuleName' exists but has drifted (Mode='$($rule.Mode)', SentToScope='$($rule.SentToScope)')."
    }
    if ($rule.Mode -ne 'Audit') {
        Write-Check WARN "Rule Mode is '$($rule.Mode)', not 'Audit' - if this was changed to Enforce, confirm that was intentional (this scenario's own deploy script only ever creates it as Audit)."
    }
}

Write-Host "`n--- Check 2: tenant-wide RejectDirectSend ---" -ForegroundColor Cyan
$orgConfig = Get-OrganizationConfig
if ($orgConfig.RejectDirectSend -eq $true) {
    Write-Check PASS 'RejectDirectSend = $true tenant-wide.'
}
elseif ($ExpectRejectDirectSend) {
    Write-Check FAIL "RejectDirectSend = $($orgConfig.RejectDirectSend), expected `$true."
}
else {
    Write-Check INFO "RejectDirectSend = $($orgConfig.RejectDirectSend) (not asserted - pass -ExpectRejectDirectSend to require `$true)."
}

Write-Host "`n--- Check 3: InboundConnector IP-authentication risk audit (threshold: /$MaxIpRangeCidrBits) ---" -ForegroundColor Cyan
$connectors = Get-InboundConnector -ErrorAction SilentlyContinue
$anyFlagged = $false
foreach ($c in $connectors) {
    if ($c.RestrictDomainsToIPAddresses -ne $true) { continue }
    foreach ($entry in @($c.SenderIPAddresses)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ($entry -match '/(\d+)$') {
            $prefixBits = [int]$Matches[1]
            if ($prefixBits -lt $MaxIpRangeCidrBits) {
                $anyFlagged = $true
                Write-Check WARN "Connector '$($c.Name)': $entry is a /$prefixBits range (wider than /$MaxIpRangeCidrBits) - review for migration to a certificate-based connector."
            }
        }
        elseif ($entry -match '-') {
            $anyFlagged = $true
            Write-Check WARN "Connector '$($c.Name)': $entry is an IP range - this script does not compute its width; review manually."
        }
    }
}
if (-not $anyFlagged) {
    Write-Check PASS 'No InboundConnector flagged by the risk heuristic.'
}

if ($ExpectedRelayConnectors.Count -gt 0) {
    Write-Host "`n--- Check 4: expected certificate-based relay connector coverage ---" -ForegroundColor Cyan
    foreach ($name in $ExpectedRelayConnectors) {
        $c = Get-InboundConnector -Identity $name -ErrorAction SilentlyContinue
        if (-not $c) {
            Write-Check FAIL "Relay connector '$name' does not exist."
        }
        elseif ($c.RestrictDomainsToCertificate -eq $true) {
            Write-Check PASS "Relay connector '$name' exists and is certificate-based."
        }
        else {
            Write-Check FAIL "Relay connector '$name' exists but RestrictDomainsToCertificate is not `$true."
        }
    }
}

Write-Host "`n--- Manual checklist (no cmdlet exists for these) ---" -ForegroundColor Cyan
Write-Host '  [ ] README.md Section 2/3''s audit-window evidence (message trace / rule report) was reviewed before enforcing.' -ForegroundColor White
Write-Host '  [ ] Every WARN-flagged connector above was reviewed and either accepted or migrated.' -ForegroundColor White
Write-Host '  [ ] Every certificate-based relay connector was end-to-end tested with its sending device/app, not just config-checked.' -ForegroundColor White
Write-Host '  [ ] Aware that Microsoft''s own Direct Send guidance states it is "working on an option to disable Direct Send by default" - re-check current behavior against Microsoft Learn periodically (README.md Section 11).' -ForegroundColor White

Write-Host "`nSummary: $script:FailCount FAIL, $script:WarnCount WARN." -ForegroundColor Cyan
if ($script:FailCount -gt 0) {
    Write-Host 'Result: FAIL' -ForegroundColor Red
    exit 1
}
else {
    Write-Host 'Result: PASS (automated checks only - complete the manual checklist above before relying on this in production).' -ForegroundColor Green
    exit 0
}
```