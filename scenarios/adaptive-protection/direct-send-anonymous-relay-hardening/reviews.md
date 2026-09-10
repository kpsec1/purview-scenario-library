# Four-Lens Review — Direct Send and Anonymous Relay Hardening

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Could an external attacker forge the `X-MS-Exchange-Organization-AuthAs` header to evade the
   audit rule (and, by extension, hide Direct Send-style traffic from detection)?** This is the
   single most important integrity question for a detection rule built on a message header — if a
   client-supplied header value could survive to the point the transport rule evaluates it, the
   whole detection mechanism would be trivially bypassable.
   - **Resolution:** Confirmed **not exploitable** — Microsoft's own header-firewall reference states
     organization X-headers on a message arriving from outside the organization are stripped before
     the Transport service evaluates authentication and inserts its own `AuthAs` value. An external
     sender cannot pre-set this header; the value the rule sees is always the Transport service's
     own assessment. Documented explicitly in `design.md` §4 rather than left as an unstated
     assumption.
2. **A determined sender could still evade tenant-wide `RejectDirectSend` by migrating to the
   certificate-based relay connector this scenario itself creates, then abusing its broader reach**
   (external recipients, not just internal — `design.md` §9). If an attacker compromises a device
   whose certificate is provisioned for relay, they inherit a materially larger blast radius than
   Direct Send ever offered.
   - **Resolution:** Not a code fix — a disclosed, inherent trade-off of the documented Microsoft
     alternative. `README.md` §11 and `design.md` §9 both state this plainly: migrating a sender
     grants it more reach than Direct Send had, and `-RelaySenderDomains` should be scoped as
     narrowly as the actual sending application needs. Certificate compromise/rotation hygiene is
     named as the operator's residual responsibility, the same standard `exchange-legacy-auth-block`
     applies to its own exception mailboxes.
3. **The connector CIDR-width heuristic could give a false sense of security** — a narrow, unshared
   range can still be exploited if the single source device is compromised, and the heuristic says
   nothing about the strength of the device's own security posture.
   - **Resolution:** Already disclosed in the initial draft (`design.md` §5/§9 explicitly call the
     heuristic "disclosed, not authoritative" and warn it can under-flag a narrow-but-compromised
     source) — confirmed accurate and left as-is.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The audit rule goes silent exactly when it would be most useful to keep watching.** The initial
   draft's Operations & tuning section listed "count of rejected Direct Send attempts after
   enforcement" as a KPI without flagging that the audit rule — the scenario's own primary detection
   mechanism — cannot supply that count. Transport rules evaluate only messages already accepted
   into the pipeline; a Direct Send attempt rejected by `RejectDirectSend` at the SMTP session never
   reaches the pipeline, so the rule's match count reads near-zero post-enforcement regardless of
   actual attack volume. An on-call analyst trusting the rule's dashboard after Step 5 would see a
   false "all quiet" signal.
   - **Resolution:** `README.md` §8 rewritten with an explicit "Important monitoring blind spot after
     Step 5" callout naming the mechanism and redirecting post-enforcement monitoring to
     `Search-UnifiedAuditLog`/SMTP gateway logs. Same class of event-level gap this library's
     `exchange-legacy-auth-block` sibling already discloses for its own KPIs — named explicitly
     rather than left implicit.
2. **No dedicated event-level export script for rejected Direct Send attempts**, matching the
   sibling scenario's own disclosed gap for SMTP AUTH rejections.
   - **Resolution:** Consistent with this library's established pattern (`AGENTS.md` §6) — named as
     the actual, currently-unscripted event source in `README.md` §8 rather than built as a
     speculative `Export-*` script against an unconfirmed `Search-UnifiedAuditLog` `RecordType`.
     Tracked as a `PROGRESS.md` follow-up for a future dedicated export script once the exact
     `RecordType`/`Operations` values for a rejected Direct Send attempt are grounded.
3. **The manual checklist didn't originally distinguish "config validated" from "actually tested
   with a real send."** A config-only check (rule exists, `RejectDirectSend` is `$true`) can be true
   while a certificate-based relay connector is still broken for an unrelated reason (certificate not
   yet installed on the device, wrong Subject/SAN).
   - **Resolution:** `README.md` §7 (Validation) and the validate script's manual checklist both call
     for an end-to-end functional test of every relay connector, not just the config read-back.

No Fail items remain.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** no incremental license cost, and the risk closed — an unauthenticated,
  internet-reachable path into internal inboxes that requires no credential at all — is concrete,
  not a vague "best practice" argument. The internal-sender-spoofing angle (§2) gives this a direct
  BEC/phishing narrative a board understands without an Exchange-administration explanation.
- **Board-level narrative:** "we closed the SMTP AUTH door, and we've now closed the door right next
  to it that never needed a key" is a clean, specific two-sentence summary that pairs naturally with
  the `exchange-legacy-auth-block` sibling scenario in the same board conversation.
- **Business-continuity coordination:** the audit-before-enforce sequencing (§5 Steps 2–3) and the
  explicit migration path (Step 4) before enforcement (Step 5) is the right change-management
  sequencing — no buyer is asked to flip a tenant-wide switch on faith.
- **Would I fund this?** Yes — low cost, a real and concretely-explainable risk, complements rather
  than duplicates the existing legacy-authentication scenarios, and the exception path (certificate-
  based relay) gives operations a real "yes, and" answer instead of a blanket "no."

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **`RejectDirectSend` is a genuinely current, documented `Set-OrganizationConfig` parameter** —
   confirmed directly against its own reference page during this build, not assumed from a blog post
   or forum thread. The parameter's description text was not returned in full by this build's
   grounding pass (no default value or edge-case behavior documented beyond type), which is honestly
   disclosed as a VERIFY in `README.md` §11 rather than papered over with an invented description.
2. **Direct Send and IP-based relay are correctly distinguished as two different mechanisms**, not
   conflated into one control. `design.md` §2's comparison table is grounded directly against
   Microsoft's own "How to set up a multifunction device or application" reference — the single
   canonical source for both mechanisms' documented behavior.
3. **The certificate-based relay connector recommendation is Microsoft's own documented, stronger
   alternative**, not an invented workaround — `-RestrictDomainsToCertificate` and
   `-TlsSenderCertificateName` are both confirmed parameters on `New-InboundConnector`, and
   Microsoft's own SMTP relay guidance explicitly prefers a certificate over a static IP where
   possible.
4. **No deprecated or superseded cmdlet paths used.** `New-/Get-/Set-/Remove-TransportRule`,
   `New-/Get-/Set-/Remove-InboundConnector`, and `Get-/Set-OrganizationConfig` are all current,
   non-legacy cmdlets in the `ExchangePowerShell` module family — none flagged as deprecated in any
   source checked during this build.
5. **The scenario correctly declines to duplicate Defender for Office 365's anti-phishing/anti-
   spoofing capability** (`design.md` §8, Non-goals) rather than reinventing composite-authentication
   spoof detection with a hand-rolled transport rule — exactly the boundary the Microsoft Product
   Owner lens is meant to catch.

No Fix/Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 verified-safe and documented, 2 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a `README.md` §8 rewrite naming a real monitoring blind spot, 1 tracked as a `PROGRESS.md` follow-up, 1 closed with a checklist addition) | Closed |
| 🎩 CISO | Pass | 0 | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 confirmed correct/well-grounded, no fixes needed | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DirectSendHardening.ps1`, `deploy/Remove-DirectSendHardening.ps1`, and
`validate/Test-DirectSendHardening.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
