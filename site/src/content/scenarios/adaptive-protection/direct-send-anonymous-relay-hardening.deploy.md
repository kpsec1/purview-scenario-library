---
part: "deploy"
parent: "adaptive-protection/direct-send-anonymous-relay-hardening"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-DirectSendHardening.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Deploys Direct Send detection (audit-mode transport rule), an inbound connector
    IP-authentication risk audit, the tenant-wide RejectDirectSend enforcement gate, and an
    optional certificate-based relay connector as a governed exception path.

.DESCRIPTION
    Deferred from scenarios/adaptive-protection/exchange-legacy-auth-block (reviews.md Red Team
    finding 3, design.md Section 8) because Direct Send and anonymous-relay-via-connector are a
    separate, unauthenticated abuse surface that scenario's SMTP AUTH block does not touch - closes
    that follow-up as its own standalone scenario.

    GROUNDING (design.md Sections 2-5): Direct Send is unauthenticated-by-design SMTP directly to
    the tenant's MX endpoint - no credential, certificate, or IP allowlist required. An
    IP-based InboundConnector authenticates a sender by source IP address alone, which Microsoft's
    own guidance says requires a static, UNSHARED IP - a range that is shared or too broad defeats
    the authentication model. Both are covered here as "unauthenticated by the strongest available
    definition," but remain independently controllable (Direct Send has no connector object at all).

    Four independent stages:
      1. ALWAYS RUNS (inert - audit only): create/reconcile the 'Direct Send Detection (Audit)'
         TransportRule at -Mode Audit. Tags matching messages with a header; never blocks or
         modifies mail. This is the substitute for a Direct Send usage report, which Microsoft does
         not document as existing (design.md Section 4).
      2. ALWAYS RUNS (read-only): enumerate every InboundConnector and flag (WARN) any connector
         with -RestrictDomainsToIPAddresses $true whose SenderIPAddresses CIDR range is wider than
         -MaxIpRangeCidrBits (default /24) - a disclosed heuristic, not a Microsoft-published
         threshold (design.md Section 5).
      3. -RejectDirectSendTenantWide (opt-in, live impact): Set-OrganizationConfig
         -RejectDirectSend $true tenant-wide.
      4. -CreateCertBasedRelayConnector (opt-in, exception path, independent of stage 3): creates a
         certificate-authenticated InboundConnector (-RestrictDomainsToCertificate $true) as the
         governed replacement for a Direct Send sender or a flagged IP-based relay connector.

    Idempotent throughout: every Get- read-back is compared against this run's desired state before
    any Set-/New- call; an already-matching object is reported and left untouched. -Force reconciles
    a drifted rule/connector to this run's parameters.

    Author-only reference code. This script never establishes its own connection to a tenant - run
    Connect-ExchangeOnline yourself first (see docs/automation-surface.md Section 3), then call this
    script.

.PARAMETER RuleName
    Name of the audit-mode detection TransportRule. Defaults to 'Direct Send Detection (Audit)'.

.PARAMETER MaxIpRangeCidrBits
    Connector risk heuristic threshold (design.md Section 5). An IP-based InboundConnector's
    SenderIPAddresses entry with a CIDR prefix SHORTER than this value (i.e. a wider range) is
    flagged WARN. Defaults to 24 (a /24, 256 addresses). Not a Microsoft-published threshold - a
    disclosed judgment call, parameterized so a buyer can tune it to their own network topology.

.PARAMETER RejectDirectSendTenantWide
    Live-impact stage. Sets Set-OrganizationConfig -RejectDirectSend $true tenant-wide. Off by
    default - this is this scenario's single highest-risk operational change (README.md Section 8);
    run README.md Section 2/3's audit window and evidence review first.

.PARAMETER CreateCertBasedRelayConnector
    Exception-path stage, independent of -RejectDirectSendTenantWide. Creates (or reconciles) a
    certificate-authenticated InboundConnector for a legitimate Direct Send/IP-relay sender that
    still needs to send mail without SMTP AUTH.

.PARAMETER RelayConnectorName
    Name of the certificate-based relay connector. Required with -CreateCertBasedRelayConnector.

.PARAMETER RelaySenderDomains
    SenderDomains for the relay connector (e.g. '*.contoso.com'). Required with
    -CreateCertBasedRelayConnector. Scope as narrowly as the sending application actually needs -
    design.md Section 9 flags that a certificate-based connector is NOT internal-recipient-only the
    way Direct Send was.

.PARAMETER RelayCertificateSubjectDomain
    Accepted domain expected in the Subject/SAN of the sending device's TLS certificate (e.g.
    'contoso.com'). Required with -CreateCertBasedRelayConnector.

.PARAMETER Force
    Reconcile an existing rule or connector's shape to this script's definition if it has drifted,
    instead of leaving a drifted object untouched.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run. Reports every create/update this run would make
    without calling any mutating cmdlet.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./New-DirectSendHardening.ps1 -WhatIf

    Dry run of stages 1-2 only (audit rule + connector audit - no live impact regardless of -WhatIf).

.EXAMPLE
    ./New-DirectSendHardening.ps1

.EXAMPLE
    # Stage 4: migrate a scan-to-email device family to certificate-based relay.
    ./New-DirectSendHardening.ps1 -CreateCertBasedRelayConnector `
        -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' `
        -RelaySenderDomains '*.contoso.com' -RelayCertificateSubjectDomain 'contoso.com'

.EXAMPLE
    # Stage 3: enforce, after confirming Step 3's evidence review found no unmigrated senders.
    ./New-DirectSendHardening.ps1 -RejectDirectSendTenantWide

.NOTES
    Sources (Microsoft Learn, verified via Microsoft Docs MCP during this build - README.md
    Section 12):
    - How to set up a multifunction device or application to send email using Microsoft 365 or
      Office 365 (Direct Send and SMTP relay sections):
      https://learn.microsoft.com/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365
    - Set-OrganizationConfig / Get-OrganizationConfig (-RejectDirectSend):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps
      https://learn.microsoft.com/powershell/module/exchangepowershell/get-organizationconfig?view=exchange-ps
    - New-InboundConnector / Get-InboundConnector (-RestrictDomainsToCertificate,
      -RestrictDomainsToIPAddresses, -SenderIPAddresses, -TlsSenderCertificateName):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-inboundconnector?view=exchange-ps
    - New-TransportRule / Get-TransportRule (-Mode, -HeaderContainsMessageHeader,
      -HeaderContainsWords, -SentToScope, -SetHeaderName, -SetHeaderValue):
      https://learn.microsoft.com/powershell/module/exchangepowershell/new-transportrule?view=exchange-ps
    - Header firewall (X-MS-Exchange-Organization-AuthAs values):
      https://learn.microsoft.com/exchange/header-firewall-exchange-2013-help

    VERIFY (README.md Section 11): the exact default value and full behavioral description of
    -RejectDirectSend are not documented beyond the parameter's existence/type on its own reference
    page - re-verify against a pilot tenant before production reliance.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RuleName = 'Direct Send Detection (Audit)',

    [Parameter()]
    [ValidateRange(0, 32)]
    [int]$MaxIpRangeCidrBits = 24,

    [Parameter()]
    [switch]$RejectDirectSendTenantWide,

    [Parameter()]
    [switch]$CreateCertBasedRelayConnector,

    [Parameter()]
    [string]$RelayConnectorName,

    [Parameter()]
    [string[]]$RelaySenderDomains,

    [Parameter()]
    [string]$RelayCertificateSubjectDomain,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Assert-ExoSession {
    if (-not (Get-Command Get-TransportRule -ErrorAction SilentlyContinue)) {
        throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first (see docs/automation-surface.md). The connecting identity (or the automation app''s service principal) also needs the Organization Management Exchange Online role group - see README.md Section 3.'
    }
}

function Confirm-AuditRule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )
    $desired = @{
        HeaderContainsMessageHeader = 'X-MS-Exchange-Organization-AuthAs'
        HeaderContainsWords         = 'Anonymous'
        SentToScope                 = 'InOrganization'
        SetHeaderName               = 'X-DirectSendHardening-Detected'
        SetHeaderValue              = 'True'
        Mode                        = 'Audit'
    }
    $existing = Get-TransportRule -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        $drifted = ($existing.Mode -ne $desired.Mode) -or
        ($existing.SentToScope -ne $desired.SentToScope) -or
        ($existing.HeaderContainsMessageHeader -ne $desired.HeaderContainsMessageHeader)
        if (-not $drifted) {
            Write-Host "  [coverage] Rule '$Name' already exists in the desired audit shape - not modified." -ForegroundColor Yellow
            return $existing
        }
        Write-Host "  [drift] Rule '$Name' exists but has drifted from the desired audit shape." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host '    Not modified - pass -Force to reconcile.' -ForegroundColor Yellow
            return $existing
        }
        if ($PSCmdlet.ShouldProcess($Name, 'Set-TransportRule (reconcile to audit shape)')) {
            Set-TransportRule -Identity $Name @desired | Out-Null
            Write-Host "  [reconciled] '$Name' reset to the desired audit shape." -ForegroundColor Green
        }
        return Get-TransportRule -Identity $Name
    }
    if ($PSCmdlet.ShouldProcess($Name, 'New-TransportRule (Mode = Audit - never blocks mail)')) {
        New-TransportRule -Name $Name @desired | Out-Null
        Write-Host "  [created] Audit rule '$Name' created (Mode = Audit - inert, tags matches only)." -ForegroundColor Green
        return Get-TransportRule -Identity $Name
    }
    return $null
}

function Get-ConnectorCidrRiskFindings {
    param([Parameter(Mandatory)][int]$MaxCidrBits)
    $findings = @()
    $connectors = Get-InboundConnector -ErrorAction SilentlyContinue
    foreach ($c in $connectors) {
        if ($c.RestrictDomainsToIPAddresses -ne $true) { continue }
        foreach ($entry in @($c.SenderIPAddresses)) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            if ($entry -match '/(\d+)$') {
                $prefixBits = [int]$Matches[1]
                if ($prefixBits -lt $MaxCidrBits) {
                    $findings += [pscustomobject]@{
                        Connector = $c.Name
                        Entry     = $entry
                        PrefixBits = $prefixBits
                        Reason    = "CIDR /$prefixBits is wider than the -MaxIpRangeCidrBits threshold (/$MaxCidrBits) - $([math]::Pow(2, 32 - $prefixBits)) possible source addresses."
                    }
                }
            }
            elseif ($entry -match '-') {
                $findings += [pscustomobject]@{
                    Connector  = $c.Name
                    Entry      = $entry
                    PrefixBits = $null
                    Reason     = 'IP range (start-end) syntax - this script does not compute its width; review manually.'
                }
            }
        }
    }
    return $findings
}

function Confirm-CertBasedRelayConnector {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$SenderDomains,
        [Parameter(Mandatory)][string]$CertificateSubjectDomain,
        [switch]$Force
    )
    $existing = Get-InboundConnector -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        $matches = ($existing.RestrictDomainsToCertificate -eq $true) -and
        ($existing.TlsSenderCertificateName -eq $CertificateSubjectDomain)
        if ($matches) {
            Write-Host "  [coverage] Relay connector '$Name' already exists in the desired certificate-based shape - not modified." -ForegroundColor Yellow
            return $existing
        }
        Write-Host "  [drift] Relay connector '$Name' exists but has drifted." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host '    Not modified - pass -Force to reconcile.' -ForegroundColor Yellow
            return $existing
        }
        if ($PSCmdlet.ShouldProcess($Name, 'Set-InboundConnector (reconcile to certificate-based shape)')) {
            Set-InboundConnector -Identity $Name -SenderDomains $SenderDomains `
                -RestrictDomainsToCertificate $true -TlsSenderCertificateName $CertificateSubjectDomain `
                -RequireTls $true | Out-Null
            Write-Host "  [reconciled] '$Name' reset to certificate-based." -ForegroundColor Green
        }
        return Get-InboundConnector -Identity $Name
    }
    if ($PSCmdlet.ShouldProcess($Name, 'New-InboundConnector (certificate-based - RestrictDomainsToCertificate)')) {
        New-InboundConnector -Name $Name -SenderDomains $SenderDomains `
            -RestrictDomainsToCertificate $true -TlsSenderCertificateName $CertificateSubjectDomain `
            -RequireTls $true -Enabled $true | Out-Null
        Write-Host "  [created] Certificate-based relay connector '$Name' created." -ForegroundColor Green
        return Get-InboundConnector -Identity $Name
    }
    return $null
}

Assert-ExoSession

Write-Host "Direct Send / anonymous relay hardening: reconciling audit rule '$RuleName'." -ForegroundColor Cyan
Confirm-AuditRule -Name $RuleName -Force:$Force | Out-Null

Write-Host "`nAuditing InboundConnectors for the IP-authentication risk heuristic (threshold: /$MaxIpRangeCidrBits)..." -ForegroundColor Cyan
$connectorFindings = Get-ConnectorCidrRiskFindings -MaxCidrBits $MaxIpRangeCidrBits
if ($connectorFindings.Count -eq 0) {
    Write-Host '  [ok] No InboundConnector flagged by the risk heuristic.' -ForegroundColor Green
}
else {
    foreach ($f in $connectorFindings) {
        Write-Host "  [WARN] Connector '$($f.Connector)': $($f.Entry) - $($f.Reason)" -ForegroundColor Yellow
    }
    Write-Host '  Review each WARN against README.md Section 5 Step 2''s inventory. This heuristic is disclosed, not a Microsoft-published threshold (design.md Section 5).' -ForegroundColor Yellow
}

if ($CreateCertBasedRelayConnector) {
    Write-Host "`nStage (-CreateCertBasedRelayConnector): reconciling certificate-based relay connector." -ForegroundColor Cyan
    if (-not $RelayConnectorName -or -not $RelaySenderDomains -or -not $RelayCertificateSubjectDomain) {
        throw '-CreateCertBasedRelayConnector requires -RelayConnectorName, -RelaySenderDomains, and -RelayCertificateSubjectDomain.'
    }
    Confirm-CertBasedRelayConnector -Name $RelayConnectorName -SenderDomains $RelaySenderDomains `
        -CertificateSubjectDomain $RelayCertificateSubjectDomain -Force:$Force | Out-Null
    Write-Host '  Reminder: a certificate-based relay connector is NOT internal-recipient-only the way Direct Send was - scope -RelaySenderDomains narrowly (design.md Section 9).' -ForegroundColor Yellow
}

if ($RejectDirectSendTenantWide) {
    Write-Host "`nStage (-RejectDirectSendTenantWide): rejecting unauthenticated Direct Send tenant-wide." -ForegroundColor Cyan
    $orgConfig = Get-OrganizationConfig
    if ($orgConfig.RejectDirectSend -eq $true) {
        Write-Host '  [coverage] RejectDirectSend is already $true tenant-wide - not modified.' -ForegroundColor Yellow
    }
    else {
        if ($PSCmdlet.ShouldProcess('Organization', 'Set-OrganizationConfig -RejectDirectSend $true')) {
            Set-OrganizationConfig -RejectDirectSend $true
            Write-Host '  [set] RejectDirectSend = $true tenant-wide.' -ForegroundColor Green
        }
    }
    Write-Host '  Reminder: any device/app still depending on unmigrated Direct Send will start failing now - confirm README.md Section 3''s evidence review found none, or migrate it via -CreateCertBasedRelayConnector first.' -ForegroundColor Yellow
}
else {
    Write-Host "`nEnforcement stage skipped (-RejectDirectSendTenantWide not passed) - Direct Send is unchanged by this run; only the audit rule and connector inventory were reconciled." -ForegroundColor DarkYellow
}

Write-Host "`nDone. Run validate/Test-DirectSendHardening.ps1 to verify." -ForegroundColor Cyan
```

#### `Remove-DirectSendHardening.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.2.0' }
<#
.SYNOPSIS
    Staged rollback for Direct Send / anonymous relay hardening: disable tenant-wide rejection,
    remove the audit-mode detection rule, and/or remove a certificate-based relay connector.

.DESCRIPTION
    Mirrors deploy/New-DirectSendHardening.ps1's independent stages. Each switch below undoes
    exactly one stage; combine as needed. See rollback.md for the recommended sequence and what
    rollback does NOT undo.

.PARAMETER UnsetRejectDirectSend
    Sets Set-OrganizationConfig -RejectDirectSend $false tenant-wide - immediate, reversible.

.PARAMETER RuleName
    Name of the audit-mode detection TransportRule to remove. Only used with -RemoveAuditRule.
    Defaults to 'Direct Send Detection (Audit)'.

.PARAMETER RemoveAuditRule
    Removes the audit-mode TransportRule via Remove-TransportRule. Stops evidence-gathering; does
    not affect enforcement (RejectDirectSend is independent).

.PARAMETER RelayConnectorName
    Name of a certificate-based relay connector to remove. Only used with -RemoveRelayConnector.

.PARAMETER RemoveRelayConnector
    Removes the named certificate-based InboundConnector via Remove-InboundConnector. Any
    device/app still relying on it for mail flow will stop being able to relay once this runs -
    confirm no legitimate sender still depends on it first.

.PARAMETER Force
    Required in addition to -RemoveAuditRule/-RemoveRelayConnector to actually remove an object -
    a deliberate double-opt-in for a non-reversible action, the same pattern this library's other
    -Purge-style rollback scripts use.

.PARAMETER WhatIf
    Standard PowerShell ShouldProcess dry-run.

.EXAMPLE
    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
    ./Remove-DirectSendHardening.ps1 -UnsetRejectDirectSend

.EXAMPLE
    ./Remove-DirectSendHardening.ps1 -RemoveAuditRule -RemoveRelayConnector `
        -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' -Force

.NOTES
    Sources: same as deploy/New-DirectSendHardening.ps1's .NOTES block.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$UnsetRejectDirectSend,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RuleName = 'Direct Send Detection (Audit)',

    [Parameter()]
    [switch]$RemoveAuditRule,

    [Parameter()]
    [string]$RelayConnectorName,

    [Parameter()]
    [switch]$RemoveRelayConnector,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Get-TransportRule -ErrorAction SilentlyContinue)) {
    throw 'No Exchange Online PowerShell session found. Run Connect-ExchangeOnline first.'
}

if ($UnsetRejectDirectSend) {
    Write-Host 'Re-enabling unauthenticated Direct Send tenant-wide (RejectDirectSend = $false)...' -ForegroundColor Cyan
    $orgConfig = Get-OrganizationConfig
    if ($orgConfig.RejectDirectSend -eq $false) {
        Write-Host '  [coverage] RejectDirectSend is already $false - not modified.' -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess('Organization', 'Set-OrganizationConfig -RejectDirectSend $false')) {
        Set-OrganizationConfig -RejectDirectSend $false
        Write-Host '  [set] RejectDirectSend = $false tenant-wide.' -ForegroundColor Green
    }
}

if ($RemoveAuditRule) {
    Write-Host "`nRemoving audit rule '$RuleName'..." -ForegroundColor Cyan
    $rule = Get-TransportRule -Identity $RuleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        Write-Host "  [coverage] Rule '$RuleName' does not exist - nothing to remove." -ForegroundColor Yellow
    }
    elseif (-not $Force) {
        Write-Warning "  Rule '$RuleName' exists but -Force was not passed - not removed. Pass -Force to confirm."
    }
    elseif ($PSCmdlet.ShouldProcess($RuleName, 'Remove-TransportRule')) {
        Remove-TransportRule -Identity $RuleName -Confirm:$false
        Write-Host "  [removed] '$RuleName'." -ForegroundColor Green
    }
}

if ($RemoveRelayConnector) {
    if (-not $RelayConnectorName) {
        throw '-RemoveRelayConnector requires -RelayConnectorName.'
    }
    Write-Host "`nRemoving relay connector '$RelayConnectorName'..." -ForegroundColor Cyan
    $connector = Get-InboundConnector -Identity $RelayConnectorName -ErrorAction SilentlyContinue
    if (-not $connector) {
        Write-Host "  [coverage] Connector '$RelayConnectorName' does not exist - nothing to remove." -ForegroundColor Yellow
    }
    elseif (-not $Force) {
        Write-Warning "  Connector '$RelayConnectorName' exists but -Force was not passed - not removed. Pass -Force to confirm. Any device/app still sending through it will lose mail flow once removed."
    }
    elseif ($PSCmdlet.ShouldProcess($RelayConnectorName, 'Remove-InboundConnector')) {
        Remove-InboundConnector -Identity $RelayConnectorName -Confirm:$false
        Write-Host "  [removed] '$RelayConnectorName'." -ForegroundColor Green
    }
}

if (-not ($UnsetRejectDirectSend -or $RemoveAuditRule -or $RemoveRelayConnector)) {
    Write-Warning 'No rollback switch passed - nothing to do. Pass -UnsetRejectDirectSend, -RemoveAuditRule, and/or -RemoveRelayConnector (with -Force for removals).'
}

Write-Host "`nDone. Run validate/Test-DirectSendHardening.ps1 to confirm the resulting state." -ForegroundColor Cyan
```