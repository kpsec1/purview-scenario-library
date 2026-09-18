---
part: "validate"
parent: "audit/compromised-account-incident-response"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-CompromisedAccountResponse.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only readiness/state check for the compromised-account containment scenario: confirms both
    Graph and Exchange Online connections, validates the config, resolves the target account/mailbox,
    and reports current containment state (useful both before and after a run).

.DESCRIPTION
    Never modifies tenant state. Checks:
      1. Microsoft Graph is connected with the required scopes.
      2. Exchange Online PowerShell is connected.
      3. The config file is well-formed and names a resolvable target account/mailbox.
      4. Reports current state: accountEnabled, forwarding, Inbox rule count (incl. hidden),
         FullAccess/SendAs delegate grant count - the same detection the deploy script performs.
    Exits non-zero on any hard failure. Safe to re-run before AND after
    deploy/Invoke-CompromisedAccountResponse.ps1 - after a run, a clean state (disabled, no
    forwarding, no rules, no non-owner grants) confirms containment succeeded.

.PARAMETER ConfigPath
    Path to the config to validate. Defaults to '../deploy/config/compromised-account-response.sample.json'.

.EXAMPLE
    Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All'
    Connect-ExchangeOnline
    ./Test-CompromisedAccountResponse.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../deploy/config/compromised-account-response.sample.json')
)

$ErrorActionPreference = 'Stop'
$script:failures = 0
function Test-Check {
    param([string]$Description, [bool]$Condition, [switch]$Warn)
    if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
    elseif ($Warn) { Write-Host "  [WARN] $Description" -ForegroundColor Yellow }
    else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $script:failures++ }
}

# --- Graph connectivity ---
$ctx = Get-MgContext -ErrorAction SilentlyContinue
Test-Check -Description "Connected to Microsoft Graph" -Condition ($null -ne $ctx)
if ($ctx) {
    $requiredScopes = 'User.EnableDisableAccount.All', 'User.RevokeSessions.All', 'User-PasswordProfile.ReadWrite.All'
    foreach ($scope in $requiredScopes) {
        $has = @($ctx.Scopes) -contains $scope
        Test-Check -Description "Graph token has scope '$scope'" -Condition $has -Warn
    }
}
else {
    Write-Host "`nRun Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All' first." -ForegroundColor Red
}

# --- Exchange Online connectivity ---
$exoConnected = [bool](Get-Command Get-Mailbox -ErrorAction SilentlyContinue)
Test-Check -Description "Exchange Online PowerShell cmdlets available (Connect-ExchangeOnline run)" -Condition $exoConnected
if (-not $exoConnected) { Write-Host "`nRun Connect-ExchangeOnline first." -ForegroundColor Red }

# --- Config validation ---
Test-Check -Description "Config file exists" -Condition (Test-Path -LiteralPath $ConfigPath)
$cfg = $null
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    Test-Check -Description "Config has targetUserPrincipalName" -Condition (-not [string]::IsNullOrWhiteSpace($cfg.targetUserPrincipalName))
    Test-Check -Description "inboxRules.mode is 'All' or 'ByIdentity'" -Condition (@('All', 'ByIdentity') -contains $cfg.inboxRules.mode)
}

# --- Resolve target and report current state ---
if ($ctx -and $exoConnected -and $cfg -and -not [string]::IsNullOrWhiteSpace($cfg.targetUserPrincipalName)) {
    $upn = $cfg.targetUserPrincipalName
    try {
        $user = Get-MgUser -UserId $upn -Property Id, AccountEnabled, SignInSessionsValidFromDateTime -ErrorAction Stop
        Test-Check -Description "Target Entra ID account resolves ($upn)" -Condition ($null -ne $user)
        Write-Host "    accountEnabled: $($user.AccountEnabled)" -ForegroundColor DarkGray
        Write-Host "    signInSessionsValidFromDateTime: $($user.SignInSessionsValidFromDateTime)" -ForegroundColor DarkGray
    }
    catch {
        Test-Check -Description "Target Entra ID account resolves ($upn)" -Condition $false
    }
    try {
        $mailbox = Get-Mailbox -Identity $upn -ErrorAction Stop
        Test-Check -Description "Target mailbox resolves ($upn)" -Condition ($null -ne $mailbox)
        $rules = @(Get-InboxRule -Mailbox $upn -IncludeHidden)
        $fa = @(Get-MailboxPermission -Identity $upn | Where-Object { $_.AccessRights -contains 'FullAccess' -and -not $_.IsInherited -and $_.User -notlike '*\SELF' })
        $sa = @(Get-RecipientPermission -Identity $upn | Where-Object { $_.Trustee -notlike 'NT AUTHORITY\SELF' })
        Write-Host "    forwarding: ForwardingAddress=$($mailbox.ForwardingAddress) ForwardingSmtpAddress=$($mailbox.ForwardingSmtpAddress)" -ForegroundColor DarkGray
        Write-Host "    inbox rules (incl. hidden): $($rules.Count)" -ForegroundColor DarkGray
        Write-Host "    FullAccess grants: $($fa.Count)   SendAs grants: $($sa.Count)" -ForegroundColor DarkGray
        $clean = (-not $mailbox.ForwardingAddress) -and (-not $mailbox.ForwardingSmtpAddress) -and ($rules.Count -eq 0) -and ($fa.Count -eq 0) -and ($sa.Count -eq 0) -and ($user.AccountEnabled -eq $false)
        Test-Check -Description "Mailbox/account state is fully contained (post-run check)" -Condition $clean -Warn
    }
    catch {
        Test-Check -Description "Target mailbox resolves ($upn)" -Condition $false
    }
}

Write-Host "`n$(if ($script:failures -eq 0) { 'All hard checks passed.' } else { "$script:failures hard check(s) failed." })" `
    -ForegroundColor $(if ($script:failures -eq 0) { 'Green' } else { 'Red' })
if ($script:failures -gt 0) { exit 1 }
```