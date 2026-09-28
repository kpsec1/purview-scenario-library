---
part: "runbook"
parent: "audit/compromised-account-incident-response"
---
## Implementation steps

### Portal path (for a first manual walkthrough)

Follow Microsoft's own documented sequence directly - this scenario's script automates exactly these
steps:

1. **Microsoft Entra admin center** → **Users** → the affected user → **Block sign-in** (disables the
   account), or use **Reset password** if you can't disable it yet.
2. **Microsoft Entra admin center** → the user → **Revoke sessions** (or the Graph/PowerShell
   equivalent below - there's no separate portal button beyond block-sign-in in some tenants).
3. **Microsoft Entra admin center** → the user → **Authentication methods** - review and remove any
   attacker-added MFA method (Step 3, not scripted - see the design notes).
4. **Microsoft Entra admin center** → **Enterprise applications** → **Consent and permissions** -
   review and revoke any suspicious app consent (Step 4, not scripted).
5. **Microsoft Entra admin center** → the user → **Assigned roles** - remove any role that shouldn't
   be there (Step 5, not scripted).
6. **Exchange admin center** → **Recipients** → the mailbox → **Mail flow settings** - clear
   forwarding; and → **Mailbox features** → review/remove Inbox rules and delegate access.

### Script path (repeatable, parameterized, `-WhatIf` preview)

```powershell
# Connect both surfaces first (the script opens neither)
Connect-MgGraph -Scopes 'User.EnableDisableAccount.All','User.Read.All','User.RevokeSessions.All','User-PasswordProfile.ReadWrite.All'
Connect-ExchangeOnline

# 0. Readiness check (both connections, config, current-state read)
./validate/Test-CompromisedAccountResponse.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json

# 1. Preview every action this run would take - nothing is changed
./deploy/Invoke-CompromisedAccountResponse.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json -WhatIf

# 2. Contain: backup -> disable -> revoke sessions -> reset password -> clear forwarding ->
#    remove Inbox rules -> remove delegate grants
./deploy/Invoke-CompromisedAccountResponse.ps1 -ConfigPath ./deploy/config/compromise-jdoe.json -BackupDir ./out/jdoe
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| `targetUserPrincipalName` | the compromised account's UPN | Required |
| `actions.disableAccount` | `true`/`false` | `Update-MgUser -AccountEnabled $false` - skipped if already disabled |
| `actions.revokeSessions` | `true`/`false` | `Revoke-MgUserSignInSession` - always safe to re-run |
| `actions.resetPassword` | `true`/`false` | `Update-MgUser -PasswordProfile @{ForceChangePasswordNextSignIn=$true; Password=...}`; new password printed once to console, never written to disk |
| `newPassword` | optional; generated if omitted | Never emailed to the user - hand off out-of-band |
| `actions.clearForwarding` | `true`/`false` | `Set-Mailbox -ForwardingAddress $null -ForwardingSmtpAddress $null -DeliverToMailboxAndForward $false` - skipped if already clear |
| `inboxRules.mode` | `"All"` (default) or `"ByIdentity"` | `Get-InboxRule -IncludeHidden` to detect, `Remove-InboxRule` to remove; the design notes on why "All" is the sensible default |
| `inboxRules.identities` | rule `Identity` values | Only used when `mode` is `"ByIdentity"` |
| `delegatePermissions.fullAccess` / `.sendAs` | `"All"` (default), `"None"`, or a trustee-identity array | `Get-MailboxPermission`/`Remove-MailboxPermission` and `Get-RecipientPermission`/`Remove-RecipientPermission` - this scenario's own extension, the design notes |
| `backupDir` | output directory for the pre-removal JSON export | Default `./out`; treat as evidence, same handling as *Forensic Investigation of a Compromised Account*'s exports |

## Operations and tuning

**Incident containment runbook:**
1. Confirm compromise first (this scenario assumes it - see *Forensic Investigation of a Compromised Account* or your
   detection source). Don't run this against an account you're still triaging.
2. `-WhatIf` the run, review the printed Inbox-rule/delegate-grant lists for anything the investigator
   already knows is legitimate; switch to `"ByIdentity"`/an explicit trustee array if so.
3. Run for real. Record the printed generated password and relay it to the user **out-of-band**
   (phone, in person) - never through the mailbox you just locked down.
4. Complete Microsoft's Steps 3-5 manually - MFA-registered-device review, OAuth app consent
   review, admin-role review - this script does not touch them.
5. Hand the backup JSON to the case file alongside any *Forensic Investigation of a Compromised Account* export.
6. **Confirm the change independently, don't just trust the script's own success output** - search the
   audit log for the `Disable account.`/`Update user.` and `Set-Mailbox` operations this run should
   have produced (`Search-UnifiedAuditLog` or *Forensic Investigation of a Compromised Account*'s own query), and check
   Entra ID sign-in logs for continued (now-failing) sign-in attempts against the account, ideally
   from the same suspicious IP the investigation flagged.
7. When the investigation concludes, follow Microsoft's own "after the investigation" steps: reset
   the password again, re-enable the account, and check the Restricted entities page if the mailbox
   was used to send spam - see the rollback runbook.

**Governance:** running this script disables an account, invalidates its credential, and deletes mail
artifacts - the same power a rogue or compromised admin could abuse against an arbitrary user under
the pretext of "incident response." Restrict who holds the Entra ID roles in the prerequisites (Privileged
Authentication Administrator especially), and treat every run - success or failure - as an event
worth alerting on in its own right (the audit records checked in step 6 above double as that alert
source).

**Tuning:** in a tenant with frequent false-positive compromise alerts, prefer `"ByIdentity"`/an
explicit trustee array over blanket `"All"` removal to avoid unnecessarily destroying legitimate
rules on a borderline call - see the design notes for the tradeoff this scenario's default makes.

## Rollback and decommission

See the rollback runbook. This scenario is **destructive by design** (that's the point of containment) -
"rollback" means restoring specific pre-removal state from the backup JSON if the compromise call
turns out to be a false positive, and re-enabling the account once the investigation concludes.

## References

1. Respond to a compromised cloud email account (the six-step containment playbook this scenario
   automates: disable account, revoke sessions, review MFA devices, review app consent, review admin
   roles, review mail forwarders/Inbox rules) - <https://learn.microsoft.com/defender-office-365/responding-to-a-compromised-email-account>
2. Update user (`accountEnabled`, `passwordProfile` properties; least-privileged permissions per
   property) - <https://learn.microsoft.com/graph/api/user-update?view=graph-rest-1.0>
3. Manage passwords with Microsoft Graph PowerShell (`Update-MgUser -PasswordProfile` worked example) - <https://learn.microsoft.com/microsoft-365/enterprise/manage-passwords-with-microsoft-365-powershell?view=o365-worldwide>
4. Privileged roles and permissions in Microsoft Entra ID - who can perform sensitive actions / who
   can reset passwords - <https://learn.microsoft.com/entra/identity/role-based-access-control/privileged-roles-permissions>
5. revokeSignInSessions action (`Revoke-MgUserSignInSession`; `User.RevokeSessions.All`) - <https://learn.microsoft.com/graph/api/user-revokesigninsessions?view=graph-rest-1.0>
6. Manage permissions for recipients in Exchange Online (`Add-MailboxPermission`/`Remove-MailboxPermission` for FullAccess) - <https://learn.microsoft.com/exchange/recipients-in-exchange-online/manage-permissions-for-recipients>
7. Remove-RecipientPermission (SendAs removal; recommends `Get-EXORecipientPermission` over
   `Get-RecipientPermission`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-recipientpermission?view=exchange-ps>
8. Set-Mailbox (`ForwardingAddress`, `ForwardingSmtpAddress`, `DeliverToMailboxAndForward`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-mailbox?view=exchange-ps>
9. Remove-InboxRule / Get-InboxRule (`-IncludeHidden`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-inboxrule?view=exchange-ps>
10. Feature permissions in Exchange Online - the **Mailbox settings** and **Permissions and
    delegation** feature-to-role-group mapping this scenario's RBAC guidance is grounded in - <https://learn.microsoft.com/exchange/permissions-exo/feature-permissions>
11. Risk-based access policies - Microsoft Entra ID Protection automatic risk remediation (require
    password change, block access, session revocation) - <https://learn.microsoft.com/entra/id-protection/concept-identity-protection-policies>

> Re-verify all links, cmdlet syntax, and role/permission names against current Microsoft Learn before
> a customer-facing deployment. This scenario is destructive by design once run for real - always
> `-WhatIf` first.