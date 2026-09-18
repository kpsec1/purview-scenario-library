---
part: "deploy"
parent: "audit/compromised-account-incident-response"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `config/compromised-account-response.sample.json`

```json
{
  "_comment": "Config for deploy/Invoke-CompromisedAccountResponse.ps1. Author-only reference data. Drives the mutating containment response to a CONFIRMED compromised mailbox: disable account, revoke sessions, reset password, clear forwarding, remove Inbox rules, remove delegate grants. Do not point this at an account until compromise is confirmed - see README.md Section 8.",
  "targetUserPrincipalName": "jdoe@contoso.example",
  "actions": {
    "disableAccount": true,
    "revokeSessions": true,
    "resetPassword": true,
    "clearForwarding": true
  },
  "_actionsNote": "Each action is independently toggleable and idempotent - set to false to skip a step this run (e.g. if another team already handled it). Every action maps to a step in Microsoft's compromised-account playbook (README.md Section 5/12 ref 1) except the delegate-permission cleanup below, which is this scenario's own extension (design.md Section 5).",
  "newPassword": null,
  "_newPasswordNote": "Leave null to have the script generate a random strong password. The password is printed ONCE to the console and never written to the backup file or any other artifact - relay it to the user out-of-band, never through the mailbox you just locked down.",
  "inboxRules": {
    "mode": "All",
    "identities": []
  },
  "_inboxRulesNote": "'All' removes every Inbox rule found (including hidden ones) - the recommended default for a confirmed compromise (design.md Section 4). Use 'ByIdentity' with the 'identities' array (exact Get-InboxRule Identity values) for a surgical response once the investigation has pinpointed the specific malicious rule(s).",
  "delegatePermissions": {
    "fullAccess": "All",
    "sendAs": "All"
  },
  "_delegatePermissionsNote": "'All' removes every non-owner FullAccess and SendAs grant found. Use 'None' to skip, or an array of trustee identities (e.g. UPNs) for a surgical response. This scenario's own extension beyond Microsoft's documented Step 6 - see design.md Section 5.",
  "backupDir": "./out",
  "_backupDirNote": "Every run writes a timestamped JSON snapshot of pre-removal state here BEFORE making any change - the evidence record and the only practical rollback input (rollback.md). Treat as sensitive: it lists every Inbox rule and delegate grant found, but never the reset password.",
  "schemaVersion": "1.0",
  "lastUpdated": "2026-09-16"
}
```

#### `Invoke-CompromisedAccountResponse.ps1`

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Contains a CONFIRMED compromised mailbox: disables the Entra ID account, revokes active sessions,
    resets the password, clears mailbox forwarding, removes Inbox rules (incl. hidden), and removes
    non-owner mailbox delegate grants (FullAccess/SendAs) - backing up pre-removal state first.

.DESCRIPTION
    Automates Microsoft's own documented containment playbook (Steps 1, 2, and 6 of "Respond to a
    compromised cloud email account" - see README.md Section 12 ref 1), plus a delegate-permission
    cleanup this scenario adds on top (design.md Section 5). Two automation surfaces are required and
    must already be connected - this script opens neither session:
      - Microsoft Graph (surface 3): Microsoft.Graph.Users / Microsoft.Graph.Users.Actions
        (Update-MgUser, Revoke-MgUserSignInSession)
      - Exchange Online PowerShell (surface 1): ExchangeOnlineManagement
        (Get-Mailbox/Set-Mailbox, Get-InboxRule/Remove-InboxRule,
         Get-MailboxPermission/Remove-MailboxPermission, Get-RecipientPermission/Remove-RecipientPermission)

    Every mutating action:
      1. Reads current state first (idempotent - skips what's already applied).
      2. Is captured in a pre-removal JSON backup BEFORE the corresponding Remove-*/Set-Mailbox call.
      3. Is gated by -WhatIf/-Confirm (SupportsShouldProcess).

    This scenario is DESTRUCTIVE BY DESIGN once run for real. Do not point it at an account until
    compromise is confirmed - see README.md Section 8. Always -WhatIf first.

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the sibling 'config/compromised-account-response.sample.json'.

.PARAMETER BackupDir
    Directory for the pre-removal JSON backup. Overrides config.backupDir when supplied.

.EXAMPLE
    Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All'
    Connect-ExchangeOnline
    ./Invoke-CompromisedAccountResponse.ps1 -WhatIf

    Preview every containment action for the configured account; change nothing.

.EXAMPLE
    Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All'
    Connect-ExchangeOnline
    ./Invoke-CompromisedAccountResponse.ps1 -ConfigPath ./config/compromise-jdoe.json -BackupDir ./out/jdoe

.NOTES
    Grounded in Microsoft Learn (verify before production use):
    - Respond to a compromised cloud email account (Steps 1/2/6):
      https://learn.microsoft.com/defender-office-365/responding-to-a-compromised-email-account
    - Update user (accountEnabled, passwordProfile):
      https://learn.microsoft.com/graph/api/user-update?view=graph-rest-1.0
    - revokeSignInSessions action (Revoke-MgUserSignInSession):
      https://learn.microsoft.com/graph/api/user-revokesigninsessions?view=graph-rest-1.0
    - Set-Mailbox (ForwardingAddress/ForwardingSmtpAddress/DeliverToMailboxAndForward):
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailbox?view=exchange-ps
    - Remove-InboxRule / Get-InboxRule -IncludeHidden:
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-inboxrule?view=exchange-ps
    - Manage permissions for recipients (Add/Remove-MailboxPermission):
      https://learn.microsoft.com/exchange/recipients-in-exchange-online/manage-permissions-for-recipients
    - Remove-RecipientPermission (SendAs; recommends Get-EXORecipientPermission over
      Get-RecipientPermission in Exchange Online PowerShell):
      https://learn.microsoft.com/powershell/module/exchangepowershell/remove-recipientpermission?view=exchange-ps

    VERIFY (README.md Section 11): the exact Exchange Online RBAC role for Remove-InboxRule/
    Set-Mailbox/Remove-MailboxPermission/Remove-RecipientPermission - documented here as the Mail
    Recipients role, based on its general description, not a per-cmdlet confirmation.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config/compromised-account-response.sample.json'),

    [Parameter()]
    [string]$BackupDir
)

$ErrorActionPreference = 'Stop'

# --- Preconditions: both surfaces must already be connected ---
foreach ($cmd in 'Update-MgUser', 'Revoke-MgUserSignInSession') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph PowerShell SDK cmdlet '$cmd' not found. Install Microsoft.Graph.Users and Microsoft.Graph.Users.Actions, then Connect-MgGraph first."
    }
}
if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
    throw "Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All' first (see docs/automation-surface.md Section 3)."
}
foreach ($cmd in 'Get-Mailbox', 'Set-Mailbox', 'Get-InboxRule', 'Remove-InboxRule', 'Get-MailboxPermission', 'Remove-MailboxPermission', 'Get-RecipientPermission', 'Remove-RecipientPermission') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Exchange Online PowerShell cmdlet '$cmd' not found. Install ExchangeOnlineManagement, then Connect-ExchangeOnline first."
    }
}
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($cfg.targetUserPrincipalName)) { throw "Config is missing targetUserPrincipalName." }
$upn = $cfg.targetUserPrincipalName

function New-StrongRandomPassword {
    # Upper/lower/digit/special, per Microsoft's own guidance (README.md Section 12 ref 1).
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@#$%^&*-_=+'
    )
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = [byte[]]::new(4)
        $pick = {
            param($alphabet)
            $rng.GetBytes($bytes)
            $i = [System.BitConverter]::ToUInt32($bytes, 0) % $alphabet.Length
            $alphabet[$i]
        }
        $chars = [System.Collections.Generic.List[char]]::new()
        foreach ($s in $sets) { $chars.Add((& $pick $s)) }
        $all = -join $sets
        for ($i = 0; $i -lt 12; $i++) { $chars.Add((& $pick $all)) }
        -join ($chars | Sort-Object { [guid]::NewGuid() })
    }
    finally { $rng.Dispose() }
}

Write-Host "Compromised account containment: $upn" -ForegroundColor Cyan

# --- 0. Read current state (never mutates) ---
$user = Get-MgUser -UserId $upn -Property Id, UserPrincipalName, AccountEnabled, SignInSessionsValidFromDateTime
$mailbox = Get-Mailbox -Identity $upn
$rules = @(Get-InboxRule -Mailbox $upn -IncludeHidden)
$fullAccessGrants = @(Get-MailboxPermission -Identity $upn | Where-Object {
        $_.AccessRights -contains 'FullAccess' -and -not $_.IsInherited -and $_.User -notlike '*\SELF' -and $_.User -notlike 'NT AUTHORITY\SELF'
    })
$sendAsGrants = @(Get-RecipientPermission -Identity $upn | Where-Object { $_.Trustee -notlike 'NT AUTHORITY\SELF' })

Write-Host "  Current state:" -ForegroundColor DarkGray
Write-Host "    accountEnabled: $($user.AccountEnabled)" -ForegroundColor DarkGray
Write-Host "    forwarding:     ForwardingAddress=$($mailbox.ForwardingAddress) ForwardingSmtpAddress=$($mailbox.ForwardingSmtpAddress) DeliverToMailboxAndForward=$($mailbox.DeliverToMailboxAndForward)" -ForegroundColor DarkGray
Write-Host "    inbox rules:    $($rules.Count) found (incl. hidden)" -ForegroundColor DarkGray
Write-Host "    FullAccess:     $($fullAccessGrants.Count) non-owner grant(s)" -ForegroundColor DarkGray
Write-Host "    SendAs:         $($sendAsGrants.Count) grant(s)" -ForegroundColor DarkGray

# --- 1. Backup pre-removal state to timestamped JSON (before any mutation) ---
$backupRoot = if ($BackupDir) { $BackupDir } elseif ($cfg.backupDir) { $cfg.backupDir } else { './out' }
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
$backupPath = Join-Path $backupRoot "compromised-account-backup-$stamp.json"
$backup = [ordered]@{
    capturedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
    targetUpn         = $upn
    account           = [ordered]@{
        id                            = $user.Id
        accountEnabled                = $user.AccountEnabled
        signInSessionsValidFromDateTime = $user.SignInSessionsValidFromDateTime
    }
    forwarding        = [ordered]@{
        forwardingAddress          = $mailbox.ForwardingAddress
        forwardingSmtpAddress      = $mailbox.ForwardingSmtpAddress
        deliverToMailboxAndForward = $mailbox.DeliverToMailboxAndForward
    }
    inboxRules        = @($rules | ForEach-Object {
            [ordered]@{
                identity = $_.Identity; name = $_.Name; enabled = $_.Enabled
                redirectTo = $_.RedirectTo; forwardTo = $_.ForwardTo; forwardAsAttachmentTo = $_.ForwardAsAttachmentTo
            }
        })
    fullAccessGrants  = @($fullAccessGrants | ForEach-Object { [ordered]@{ user = "$($_.User)"; accessRights = @($_.AccessRights) } })
    sendAsGrants      = @($sendAsGrants | ForEach-Object { [ordered]@{ trustee = "$($_.Trustee)"; accessRights = @($_.AccessRights) } })
    note              = "Evidence + rollback input. The reset password is deliberately NOT recorded here - see rollback.md."
}
if ($PSCmdlet.ShouldProcess($backupPath, "Write pre-removal state backup ($($rules.Count) rule(s), $($fullAccessGrants.Count + $sendAsGrants.Count) delegate grant(s))")) {
    if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
    $backup | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $backupPath -Encoding utf8
    Write-Host "  [backup] pre-removal state -> $backupPath" -ForegroundColor Cyan
}

# --- 2. Disable account (Step 1) ---
$disable = if ($null -ne $cfg.actions.disableAccount) { [bool]$cfg.actions.disableAccount } else { $true }
if ($disable) {
    if ($user.AccountEnabled -eq $false) {
        Write-Host "  [skip] account already disabled" -ForegroundColor DarkGray
    }
    elseif ($PSCmdlet.ShouldProcess("Entra ID user $upn", "Disable account (accountEnabled = false)")) {
        Update-MgUser -UserId $user.Id -AccountEnabled:$false
        Write-Host "  [done] account disabled" -ForegroundColor Green
    }
}

# --- 3. Revoke sessions (Step 2) ---
$revoke = if ($null -ne $cfg.actions.revokeSessions) { [bool]$cfg.actions.revokeSessions } else { $true }
if ($revoke) {
    if ($PSCmdlet.ShouldProcess("Entra ID user $upn", "Revoke all active sign-in sessions / refresh tokens")) {
        Revoke-MgUserSignInSession -UserId $user.Id | Out-Null
        Write-Host "  [done] sign-in sessions revoked" -ForegroundColor Green
    }
}

# --- 4. Reset password ---
$resetPw = if ($null -ne $cfg.actions.resetPassword) { [bool]$cfg.actions.resetPassword } else { $true }
if ($resetPw) {
    $newPassword = if (-not [string]::IsNullOrWhiteSpace($cfg.newPassword)) { $cfg.newPassword } else { New-StrongRandomPassword }
    if ($PSCmdlet.ShouldProcess("Entra ID user $upn", "Reset password (force change at next sign-in)")) {
        Update-MgUser -UserId $user.Id -PasswordProfile @{ ForceChangePasswordNextSignIn = $true; Password = $newPassword }
        Write-Host "  [done] password reset. NEW PASSWORD (shown once, not saved anywhere): $newPassword" -ForegroundColor Yellow
        Write-Host "         Relay this to the user OUT-OF-BAND - never through the mailbox you just locked down." -ForegroundColor Yellow
    }
}

# --- 5. Clear mailbox forwarding (Step 6) ---
$clearFwd = if ($null -ne $cfg.actions.clearForwarding) { [bool]$cfg.actions.clearForwarding } else { $true }
if ($clearFwd) {
    $hasForwarding = $mailbox.ForwardingAddress -or $mailbox.ForwardingSmtpAddress
    if (-not $hasForwarding) {
        Write-Host "  [skip] no mailbox forwarding configured" -ForegroundColor DarkGray
    }
    elseif ($PSCmdlet.ShouldProcess("Mailbox $upn", "Clear ForwardingAddress/ForwardingSmtpAddress and disable DeliverToMailboxAndForward")) {
        Set-Mailbox -Identity $upn -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false
        Write-Host "  [done] forwarding cleared" -ForegroundColor Green
    }
}

# --- 6. Remove Inbox rules (Step 6) ---
$ruleMode = if ($cfg.inboxRules.mode) { $cfg.inboxRules.mode } else { 'All' }
$rulesToRemove = switch ($ruleMode) {
    'All' { $rules }
    'ByIdentity' { $rules | Where-Object { @($cfg.inboxRules.identities) -contains "$($_.Identity)" } }
    default { throw "Unknown inboxRules.mode '$ruleMode' - expected 'All' or 'ByIdentity'." }
}
if (@($rulesToRemove).Count -eq 0) {
    Write-Host "  [skip] no Inbox rules to remove (mode: $ruleMode)" -ForegroundColor DarkGray
}
foreach ($rule in $rulesToRemove) {
    if ($PSCmdlet.ShouldProcess("Mailbox $upn", "Remove Inbox rule '$($rule.Name)' ($($rule.Identity))")) {
        Remove-InboxRule -Mailbox $upn -Identity $rule.Identity -Confirm:$false
        Write-Host "  [done] removed Inbox rule '$($rule.Name)'" -ForegroundColor Green
    }
}

# --- 7. Remove delegate grants (this scenario's extension - design.md Section 5) ---
$faMode = if ($cfg.delegatePermissions.fullAccess) { $cfg.delegatePermissions.fullAccess } else { 'All' }
$faToRemove = switch ($true) {
    ($faMode -eq 'All') { $fullAccessGrants }
    ($faMode -eq 'None') { @() }
    default { $fullAccessGrants | Where-Object { @($faMode) -contains "$($_.User)" } }
}
foreach ($grant in $faToRemove) {
    if ($PSCmdlet.ShouldProcess("Mailbox $upn", "Remove FullAccess grant from $($grant.User)")) {
        Remove-MailboxPermission -Identity $upn -User $grant.User -AccessRights FullAccess -InheritanceType All -Confirm:$false
        Write-Host "  [done] removed FullAccess grant from $($grant.User)" -ForegroundColor Green
    }
}

$saMode = if ($cfg.delegatePermissions.sendAs) { $cfg.delegatePermissions.sendAs } else { 'All' }
$saToRemove = switch ($true) {
    ($saMode -eq 'All') { $sendAsGrants }
    ($saMode -eq 'None') { @() }
    default { $sendAsGrants | Where-Object { @($saMode) -contains "$($_.Trustee)" } }
}
foreach ($grant in $saToRemove) {
    if ($PSCmdlet.ShouldProcess("Mailbox $upn", "Remove SendAs grant from $($grant.Trustee)")) {
        Remove-RecipientPermission -Identity $upn -Trustee $grant.Trustee -AccessRights SendAs -Confirm:$false
        Write-Host "  [done] removed SendAs grant from $($grant.Trustee)" -ForegroundColor Green
    }
}

Write-Host "`nContainment run complete for $upn. Backup: $backupPath" -ForegroundColor Cyan
Write-Host "Reminder: Steps 3-5 (MFA devices, app consent, admin roles) are not scripted - see README.md Section 5/8." -ForegroundColor Yellow
```