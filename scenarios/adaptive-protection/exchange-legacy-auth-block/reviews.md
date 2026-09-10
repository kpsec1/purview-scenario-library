# Four-Lens Review — Exchange-Side Legacy Authentication Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail**
items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The `-Purge` safety check in the original draft used an unconfirmed `Get-User -Filter`
   expression that could fail open.** The first draft of `deploy/Remove-ExchangeLegacyAuthBlock.ps1`
   checked for users still assigned a policy before removing it with
   `Get-User -Filter "AuthenticationPolicy -eq '$name'"`. Whether `AuthenticationPolicy` is a
   supported OPATH filter property for `Get-User` was never confirmed against a Microsoft Learn
   reference during this build. If it isn't supported, the likely failure mode isn't a clean error
   — it's either an exception this script doesn't specifically handle, or (worse) a filter that
   silently matches nothing, making the "still assigned" safety check pass when it shouldn't and
   allowing `-Purge` to remove a policy still in active use.
   - **Resolution:** Replaced with an unfiltered `Get-User -ResultSize Unlimited` fetch piped to a
     client-side `Where-Object { $_.AuthenticationPolicy -eq $name }` comparison — slower on a
     large tenant, but the property comparison itself only depends on `Get-User` returning the
     `AuthenticationPolicy` property at all (independently confirmed, §PO below), not on an
     unconfirmed filter-query capability. See the script's inline comment at the fix site.
2. **The tenant default does not cover a user with a pre-existing explicit policy assignment.**
   `Set-OrganizationConfig -DefaultAuthenticationPolicy` only applies to users with no explicit
   `Set-User -AuthenticationPolicy` assignment already in place [[6]](#references) — a user
   assigned an older, more permissive policy by different automation (or by an admin working around
   a since-fixed issue) keeps that policy indefinitely, invisibly, unless someone specifically looks
   for it.
   - **Resolution:** Not a code fix — a documented, disclosed limitation this scenario cannot close
     unilaterally without risking breaking an intentional, still-needed per-user exception.
     `validate/Test-ExchangeLegacyAuthBlock.ps1 -CheckUserOverrides` surfaces every such user as a
     `WARN` rather than silently passing; `README.md` §11 and `design.md` §9 name it plainly.
3. **This scenario's SMTP AUTH block pushes a determined attacker/legacy integration toward Direct
   Send (anonymous relay) instead**, a materially different, unauthenticated abuse surface this
   scenario does not touch. Closing an authenticated legacy protocol doesn't reduce the value of a
   misconfigured mail flow connector that accepts anonymous relay from an allowed IP range.
   - **Resolution:** Confirmed as a genuine, separate gap this scenario was never scoped to close
     (`design.md` §7/§8, Non-goals and Residual risk) — not silently left unstated. No dedicated
     Direct Send scenario exists yet in this repo; tracked as a `PROGRESS.md` follow-up rather than
     folded into this fragment per `AGENTS.md` §6.
4. **Exception mailboxes are a real, named, narrower attack surface, not a fully closed gap.** A
   mailbox on `Allow-Smtp-Auth-Exception` is still reachable via SMTP AUTH by design — its
   credential hygiene now matters proportionally more, since it's one of the few remaining
   Basic-Auth-reachable accounts in the tenant.
   - **Resolution:** Already disclosed in the initial draft (`design.md` §9, `README.md` §8's
     tuning guidance recommending credential hygiene and OAuth migration for exception mailboxes)
     — confirmed accurate and left as-is, no further fix needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No dedicated event-level detection for a rejected SMTP AUTH attempt.** This scenario's
   validate script and `Get-*` read-backs confirm *configuration* (is the gate closed) but not
   *events* (who actually got rejected, and how often) — a real signal-to-noise gap for an on-call
   analyst trying to distinguish "expected, config just landed" from "a credential-stuffing
   campaign just lost its easiest path in and is now hammering the door."
   - **Resolution:** `README.md` §8 KPIs section names `Search-UnifiedAuditLog` mail-flow/connector
     events and the SMTP gateway's own logs as the actual event source, rather than implying the
     config read-back scripts themselves surface rejection events — no dedicated export script was
     built for this in this fragment (kept scoped to the deploy/validate/rollback core per
     `AGENTS.md` §6); tracked as a `PROGRESS.md` follow-up for a future `Export-*` companion script
     once the exact `Search-UnifiedAuditLog` `RecordType`/`Operations` values for a rejected SMTP
     AUTH attempt are grounded.
2. **The original `-Purge` safety check (Red Team finding 1, above) was also a Blue Team
   operability gap** — an operator relying on it to prevent an accidental removal of a live policy
   had no way to know the check itself might silently under-match. Same fix as Red Team finding 1
   closes this too — an unfiltered fetch with a client-side comparison is directly inspectable and
   has no filter-support assumption to silently fail on.
3. **The manual checklist didn't originally distinguish "config validated" from "actually tested
   with a real send."** A config-only check (`AllowBasicAuthSmtp` is `$false`, transport gate is
   `$true`) can be true while an exception mailbox is still broken for an unrelated reason (wrong
   mailbox identity string, a typo in `-ExceptionMailboxes`).
   - **Resolution:** `README.md` §7 (Validation) and the validate script's manual checklist both
     now explicitly call for an end-to-end functional test of every exception mailbox, not just the
     config read-back.

No Fail items remain.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **The original cost section didn't lead with the time-boxed urgency angle strongly enough** —
   framing this purely as "a good practice" undersells why a board should approve it *now* rather
   than deferring to Microsoft's own December 2026 default-disable date.
   - **Resolution:** Rewrote `README.md` §10 to lead with the "control the transition on your
     terms, before Microsoft controls it on theirs" framing, directly tied to the cited deprecation
     timeline.
- **Risk reduction vs. cost:** genuinely no incremental license cost (Exchange Online-native
  capability), and the risk being closed — an unauthenticated-MFA-bypassable credential-stuffing
  surface with an active deprecation clock already ticking — is concrete and dated, not a vague
  "best practice" argument.
- **Board-level narrative:** "we've closed the one legacy-authentication protocol Microsoft hasn't
  already force-disabled for us, months ahead of Microsoft's own timeline, with a named, tracked
  exception list instead of an ungoverned blanket allowance" is specific and easy to defend in an
  audit.
- **Business-continuity coordination:** `README.md` §8's tuning guidance correctly identifies the
  realistic friction point (multifunction devices, relay apps, monitoring tools using SMTP AUTH),
  and §5 Step 2's inventory-before-enforcement discipline is the right sequencing for a
  change-management conversation.
- **Would I fund this?** Yes — low cost, a real and dated risk, and it complements (doesn't
  duplicate) the Conditional Access sibling scenario, which this library's own Microsoft Product
  Owner lens already confirmed is correctly scoped as a *different* control layer.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **The core design decision — center this scenario on SMTP AUTH rather than presenting it as a
   general "block legacy auth in Exchange" tool — is correctly grounded, not assumed.** Verified
   directly against Microsoft's "Disable Basic authentication in Exchange Online" reference: eight
   named protocols are already permanently disabled tenant-wide with no re-enable option, which
   this build confirmed before designing around it rather than after. Avoids exactly the kind of
   "oversell a control Microsoft already gives away" mistake `AGENTS.md` §5 asks this lens to
   catch — the same standard the Conditional Access sibling's Microsoft-managed-policy finding set.
2. **`AllowBasicAuth*` (cloud) vs. `BlockLegacyAuth*`/`BlockModernAuth*` (on-premises-only) are
   correctly distinguished.** An earlier framing of this follow-up in `PROGRESS.md` referenced
   `-BlockLegacyAuth*` for Exchange Online, which this build's grounding pass found is actually an
   **on-premises-only** parameter family (Exchange 2019 CU2+/CU13+) — not usable against Exchange
   Online at all. This scenario correctly uses the cloud-only `-AllowBasicAuth*` switches instead;
   the corrected framing is documented in `design.md` §7 rather than silently carried forward.
3. **The two independent SMTP AUTH gates (AuthenticationPolicy vs. transport config) are treated
   honestly as independently-documented, not assumed to have a single well-known precedence.**
   Checked both the `Set-AuthenticationPolicy` reference and Microsoft's dedicated SMTP AUTH guide
   directly — neither states how the two interact if only one is opened. Closing both together
   rather than picking one and hoping is the correct, non-speculative choice.
4. **RBAC recommendation is honestly scoped as broad-but-confirmed, not narrowed by guessing.**
   Microsoft's own `New-/Set-/Remove-AuthenticationPolicy` reference pages don't name a specific
   least-privilege role — this scenario recommends the confirmed-sufficient **Organization
   Management** role group and flags the narrower-role question as an open VERIFY rather than
   inventing a plausible-sounding custom role name.
5. **No deprecated or superseded cmdlet paths used.** `New-/Set-/Get-/Remove-AuthenticationPolicy`,
   `Set-User -AuthenticationPolicy`, `Set-OrganizationConfig -DefaultAuthenticationPolicy`, and
   `Set-TransportConfig`/`Set-CASMailbox -SmtpClientAuthenticationDisabled` are all current,
   non-legacy cmdlets in the `ExchangePowerShell`/`ExchangeOnlineManagement` module family — none
   flagged as deprecated in any source checked during this build.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 closed with a real script-safety fix, 1 closed by disclosure/validate-script surfacing, 2 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with the same script-safety fix as Red Team finding 1, 1 tracked as a `PROGRESS.md` follow-up, 1 closed with a checklist addition) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a `README.md` §10 rewrite; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 confirmed correct/well-grounded, no fixes needed | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-ExchangeLegacyAuthBlock.ps1`, `deploy/Remove-ExchangeLegacyAuthBlock.ps1`, and
`validate/Test-ExchangeLegacyAuthBlock.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
