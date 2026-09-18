---
part: "design"
parent: "audit/compromised-account-incident-response"
---
## 1. Problem statement

`scenarios/audit/premium-audit-investigation/` deliberately investigates and never remediates
(`design.md` §7: "Responding/remediating... is a separate, mutating workflow"). Once that
investigation, or any other detection (user report, Defender alert, sign-in risk), confirms a
mailbox is compromised, someone has to actually **contain** it: block further access, invalidate
the stolen credential, and remove the persistence mechanisms a BEC attacker plants (mail forwarding,
Inbox rules, mailbox delegate grants) so the attack doesn't resume the moment normal access returns.
Doing this by hand, cmdlet by cmdlet, under incident pressure is slow and easy to get wrong (skip a
hidden rule, forget forwarding, leave a delegate grant in place). This scenario scripts that
containment as one repeatable, config-driven, idempotent run.

## 2. Design goals

1. **Match Microsoft's own documented playbook, not an invented one.** Every scripted action maps
 directly onto a numbered step in Microsoft's "Respond to a compromised cloud email account"
 article, Step 1 (disable/reset), Step 2 (revoke sessions), Step 6 (mail
 forwarders and Inbox rules). Steps 3-5 (MFA devices, OAuth app consent, admin roles) are
 documented as manual portal follow-ups (§8) rather than guessed at as scriptable.
2. **Idempotent and safe to re-run.** Every action checks current state first and skips what's
 already done (already disabled, no forwarding set, no rules left), re-running mid-incident, or
 after a partial failure, never errors or double-applies.
3. **Evidence before destruction.** Before removing anything, export the account's and mailbox's
 current state (accountEnabled, forwarding, every Inbox rule including hidden ones, every
 FullAccess/SendAs grant) to a timestamped JSON backup, the same evidence-grade export discipline
 `premium-audit-investigation` uses, and the only practical "undo" for a Remove-* action against a
 live mailbox (`rollback.md`).
4. **Config-driven, not interactive.** One JSON config names the target account and which
 containment actions to run (and in "surgical" mode, exactly which rule/delegate identities), 
 the same pattern as the investigation scenario's config, so an investigator can go from "confirmed
 compromise" export straight into a response config without re-typing identifiers by hand.
5. **`-WhatIf` previews every mutating action** before anything is disabled, revoked, reset, or
 removed. Read-only detection (what forwarding/rules/delegates currently exist) always runs so the
 preview is informative, not just "would call cmdlet X."
6. **Never touch the plaintext password.** A generated reset password is printed once to the console
 and never written to the backup file or any other artifact, matching Microsoft's own warning not
 to email a new password to a possibly-still-attacker-readable mailbox.

## 3. Two surfaces, one script

| Action | Surface | Cmdlet |
|---|---|---|
| Disable account | 3, Microsoft Graph (`Microsoft.Graph.Users`) | `Update-MgUser -AccountEnabled $false` |
| Revoke sessions | 3, Microsoft Graph (`Microsoft.Graph.Users.Actions`) | `Revoke-MgUserSignInSession` |
| Reset password | 3, Microsoft Graph (`Microsoft.Graph.Users`) | `Update-MgUser -PasswordProfile @{...}` |
| Read/clear forwarding | 1, Exchange Online PowerShell | `Get-Mailbox` / `Set-Mailbox -ForwardingAddress/-ForwardingSmtpAddress $null` |
| Read/remove Inbox rules | 1, Exchange Online PowerShell | `Get-InboxRule -IncludeHidden` / `Remove-InboxRule` |
| Read/remove delegate grants | 1, Exchange Online PowerShell | `Get-MailboxPermission`/`Get-RecipientPermission` / `Remove-MailboxPermission`/`Remove-RecipientPermission` |

Per [Automation surface §7](/docs/automation-surface/#7-how-scenarios-should-cite-the-automation-surface), the script requires both an existing `Connect-MgGraph` session
(surface 3) and an existing `Connect-ExchangeOnline` session (surface 1), it does not open either
session itself, matching every other scenario in this library. A single incident response touches
identity (Entra ID) and mail flow (Exchange Online), which are two distinct services with two
distinct RBAC models ([RBAC model §1](/docs/rbac-model/#1-four-rbac-systems-not-one-read-this-first) #1/#4); there is no single surface that reaches both.

## 4. Why "All" is the sensible default, not a footgun

The config's `inboxRules.mode` and `delegatePermissions.fullAccess`/`sendAs` default to `"All"`, 
remove every Inbox rule and every non-owner delegate grant found, not a curated subset. This looks
aggressive next to `premium-audit-investigation`'s read-only posture, but the two scenarios sit on
opposite sides of a deliberate decision boundary: this script only runs **after** an investigator (or
another detection) has already decided the account is compromised and containment is warranted. At
that point, asking the script to distinguish "the attacker's rule" from "a legitimate rule the user
made three years ago" is asking it to guess, the safer failure mode is removing everything and
letting the user recreate the handful of legitimate rules they actually use, backed by the pre-removal
export (§3 goal 3) if anything needs restoring. `"ByIdentity"`/`"ByTrustee"` modes are available for a
narrower, surgical response when the investigation already pinpointed the exact malicious rule or
delegate (e.g., from `premium-audit-investigation`'s own `New-InboxRule`/`Add-MailboxPermission`
crucial-events export).

## 5. Delegate-permission cleanup extends, but doesn't misquote, Microsoft's Step 6

Microsoft's own article's Step 6 ("Review mail forwarders") covers mailbox-level forwarding and
Inbox-rule forwarding/redirect only, it does not mention `FullAccess`/`SendAs` delegate grants
. This scenario adds that cleanup anyway, because it is the same class of
mail-flow persistence the sibling `premium-audit-investigation` scenario's own crucial-events preset
already watches for (`Add-MailboxPermission`, `SendAs`, `SendOnBehalf`, its `design.md` §5 table).
`README.md` §5/§11 and this file are explicit that the delegate cleanup is this scenario's own
addition, grounded independently against the `Add-MailboxPermission`/`Remove-MailboxPermission` and
`Remove-RecipientPermission` reference pages, not Microsoft's
own numbered Step 6.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Steps 1, 2, and 6 of Microsoft's playbook, plus delegate-permission cleanup | The four actions with a documented, scriptable cmdlet; Steps 3-5 are portal-review workflows (§8) |
| Disable vs. password reset | Both, by default | Microsoft frames password reset as the fallback "if you can't disable"; this scenario does both so the account is inert *and* its old credential is dead before anyone re-enables it |
| Password handling | Generated if not supplied; printed once, never written to any file | Matches Microsoft's own warning not to relay a new password through a possibly-compromised mailbox; avoids embedding a secret in the evidence bundle (`AGENTS.md` §4 code standard) |
| Removal scope | Config-driven `"All"` (default) or `"ByIdentity"`/`"ByTrustee"` (surgical) | §4 above |
| Pre-removal backup | Always exports current state to timestamped JSON before any `Remove-*`/`Set-Mailbox` call | The only practical undo path for mailbox mutations (`rollback.md`) |
| Idempotency | Every action reads current state first and skips what's already applied | `AGENTS.md` §4 code standard; safe to re-run after a partial failure mid-incident |

## 7. Relationship to Microsoft Entra ID Protection's automatic risk remediation

A Microsoft Entra ID P2 (or Suite) tenant can already automate the identity half of this scenario:
risk-based Conditional Access can require a secure password change or block access, with automatic
session revocation, the moment ID Protection flags a user as risky, no script required
. This scenario doesn't reinvent that: it exists for the mailbox-level cleanup
(forwarding, Inbox rules, delegate grants) ID Protection's identity-layer remediation never reaches,
and for tenants/incidents where automatic risk detection isn't in play (no P2 license, or a
human-confirmed compromise ID Protection's own signals didn't flag). `README.md` §11 states this
comparison for buyers evaluating whether they need this scenario alongside ID Protection or instead
of it.

## 8. Non-goals

- **Steps 3-5 of Microsoft's playbook** (MFA-registered-device review, OAuth app consent review,
 admin-role review), documented in `README.md` §5 with direct Learn links, but not scripted here:
 Microsoft's own article points to portal workflows for each, not a PowerShell/Graph cmdlet
 sequence, and reviewing *which* devices/apps/roles are suspicious is a human judgment call this
 script can't safely automate.
- **Detection/triage**, this scenario assumes compromise is already confirmed (by
 `premium-audit-investigation`, a Defender/Entra ID Protection alert, or a user report). It does not
 search the audit log itself.
- **Re-enabling the account / after-the-incident cleanup**, Microsoft's own "After the investigation
 is complete" section (reset password, re-enable, check Restricted entities for a spam block)
 is a distinct, deliberate follow-on action, not part of containment; see
 `rollback.md`.
- **Non-mailbox persistence** (OAuth app grants, admin role assignments, MFA method changes), see
 the first bullet; also out of scope for the same reason.
- **Sending the new password to the user**, deliberately not automated; hand off out-of-band per
 Microsoft's own guidance.
- **Organization-wide mail flow persistence** (transport rules, inbound connectors), this scenario is
 scoped to the one compromised mailbox; a compromise that also reaches tenant-wide mail flow is a
 different, broader incident (`README.md` §11 points at this library's connector-hardening
 scenarios for that surface).

## 9. Governance

This script disables an account, invalidates its credential, and deletes mail artifacts, real power
that a rogue or compromised administrator could misuse against an arbitrary user under the pretext of
"incident response." This isn't a code control this scenario can enforce; it's an operational one:
restrict who holds the Entra ID roles in `README.md` §3 (Privileged Authentication Administrator
especially), and audit every run of this script the same way any other privileged action is audited
, `README.md` §8 names the specific audit-log operations to check.

## References

Full citations in `README.md` §12.
