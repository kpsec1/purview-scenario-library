---
part: "rollback"
parent: "audit/compromised-account-incident-response"
---
## This scenario is destructive by design — "rollback" means restoring specific state, not undoing everything

Unlike every read-only scenario in this library's `audit/` module, `Invoke-CompromisedAccountResponse.ps1`
changes tenant state on purpose: that's what containment means. There is no single "undo" command.
What follows is how to restore specific pieces of state from the pre-removal backup JSON, and how to
close out the incident once the investigation concludes.

## 1. If the compromise call was a false positive

1. **Re-enable the account:**
   ```powershell
   Update-MgUser -UserId <UserId-or-UPN> -AccountEnabled:$true
   ```
2. **Restore mailbox forwarding**, if the pre-removal backup JSON shows a value was set:
   ```powershell
   $backup = Get-Content ./out/compromised-account-backup-<stamp>.json -Raw | ConvertFrom-Json
   Set-Mailbox -Identity <UPN> `
       -ForwardingAddress $backup.forwarding.forwardingAddress `
       -ForwardingSmtpAddress $backup.forwarding.forwardingSmtpAddress `
       -DeliverToMailboxAndForward $backup.forwarding.deliverToMailboxAndForward
   ```
3. **Recreate removed Inbox rules** from the backup's `inboxRules` array. The backup records
   `identity`, `name`, `enabled`, `redirectTo`, `forwardTo`, and `forwardAsAttachmentTo` — enough to
   recreate the rule's forwarding/redirect behavior with `New-InboxRule`, but **not** the rule's full
   condition/action set (the backup is an evidence summary, not a complete rule export). For a rule
   with conditions beyond forwarding, the user or an admin should recreate it from memory or from
   their own prior documentation — this is a known, disclosed gap (§4 below).
4. **Restore delegate grants** from `fullAccessGrants`/`sendAsGrants`:
   ```powershell
   foreach ($g in $backup.fullAccessGrants) {
       Add-MailboxPermission -Identity <UPN> -User $g.user -AccessRights FullAccess -InheritanceType All
   }
   foreach ($g in $backup.sendAsGrants) {
       Add-RecipientPermission -Identity <UPN> -Trustee $g.trustee -AccessRights SendAs -Confirm:$false
   }
   ```
5. **The reset password cannot be rolled back** — it was never recorded (`design.md` §2 goal 6). Issue
   the user a new password through the normal (non-incident) reset process.
6. **Sign-in sessions cannot be "un-revoked"** — this is expected and harmless; the user simply signs
   in again with their (possibly newly reset) credential.

## 2. When the investigation confirms compromise and concludes (the normal path)

Follow Microsoft's own documented close-out steps [[1]](#references) rather than this library's
`premium-audit-investigation` rollback pattern (which had nothing to restore) — here there genuinely
is tenant state to bring back to normal, deliberately, once the incident is resolved:

1. **Reset the password again** (the credential used during the compromise window should never be
   reactivated) and **re-enable the account** — same commands as §1 steps 1 and the password-reset
   step in `deploy/Invoke-CompromisedAccountResponse.ps1`.
2. **Check the Restricted entities page** if the mailbox was used to send spam during the compromise —
   the mailbox may be blocked from sending until removed from that list [[1]](#references).
3. **Do not automatically restore forwarding/rules/delegate grants** found in the backup — review each
   one first. The backup exists so a human can decide what was legitimate, not so the containment can
   be blindly reversed. A forwarding rule or delegate grant the attacker added should stay removed.
4. **Complete Microsoft's Steps 3–5** if not already done during containment: MFA-registered-device
   review, OAuth app consent review, admin-role review (`README.md` §5/§8) — these often reveal
   persistence this scenario's automated Steps 1/2/6 don't touch.

## 3. What is never automatically restored

- **The plaintext reset password** — never recorded anywhere (§1.5).
- **Revoked sign-in sessions** — not reversible or meaningful to reverse (§1.6).
- **A full Inbox rule definition** beyond its forwarding/redirect behavior — the backup is a triage
  summary, not a complete `New-InboxRule` parameter set (§1.3).

## 4. Known gap

The Inbox-rule backup does not capture every condition/action a rule might have (subject contains,
move-to-folder, mark-as-read, etc.) — only the fields relevant to detecting attacker forwarding
(`RedirectTo`/`ForwardTo`/`ForwardAsAttachmentTo`), matching Microsoft's own detection guidance
[[1]](#references). A legitimate rule with other conditions/actions needs to be recreated from the
user's own knowledge of what they had configured, not purely from this backup. Consider a future
follow-up that captures the full rule object (`Get-InboxRule -IncludeHidden | Select-Object *`) if a
buyer needs complete rule-restoration fidelity rather than just evidence of what was removed.

## References

1. Respond to a compromised cloud email account — <https://learn.microsoft.com/defender-office-365/responding-to-a-compromised-email-account>
