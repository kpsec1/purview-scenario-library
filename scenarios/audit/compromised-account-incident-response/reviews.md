# Four-Lens Review - Compromised Account Incident Response

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, `validate/`, and
`rollback.md`. One round of findings below; all **Fix** items were applied before this file was
finalized. No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The printed reset password can leak through channels the script doesn't control.** The script
   never writes the password to disk or the backup JSON, but `Write-Host` output is still visible to
   a PowerShell transcript, a CI/CD job log, or a recorded terminal session if the operator has one
   running - the same exposure Microsoft's own article warns against for emailing the password
   [[1]](#references), just via a different channel.
   - **Resolution:** `README.md` §11 now names this risk explicitly and recommends disabling
     transcript/session logging (or redirecting that one line to a secured channel) before the
     password-reset step.
2. **Blind restoration from the backup re-introduces the attacker's persistence.** An admin resolving
   a false-positive call, or closing out an incident, could naively "restore everything from the
   backup" and put the attacker's own forwarding rule or delegate grant right back.
   - **Resolution:** `rollback.md` §2.3 states explicitly: review each restored item, don't blindly
     reverse containment; the backup exists for human judgment, not automatic reversal.
3. **Mailbox-level scope leaves organization-wide mail flow persistence untouched.** An attacker with
   broader access (e.g., a compromised admin) could plant a tenant-wide transport rule or connector
   instead of (or in addition to) per-mailbox persistence - this scenario wouldn't detect or remove
   that.
   - **Resolution:** `README.md` §11 and `design.md` §8 state this as an explicit scope boundary,
     pointing at this library's own connector-hardening scenarios for that surface rather than
     silently ignoring it.
4. **A powerful script is itself an attack surface if access to run it is loosely controlled.** The
   same capabilities that make this scenario valuable for containment (disable any account, reset any
   password, delete mail artifacts) make it valuable to a rogue or already-compromised administrator.
   - **Resolution:** `design.md` §9 (Governance) and `README.md` §8 call this out directly: restrict
     who holds the Entra ID roles this scenario needs, and audit every run.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The script's own "[done]" output is the only evidence a change actually landed.** If a call
   silently no-ops or the local report is wrong, an investigator relying only on console output could
   believe containment succeeded when it didn't.
   - **Resolution:** `README.md` §8 step 6 now tells the operator to independently confirm via the
     audit log (`Disable account.`/`Update user.`/`Set-Mailbox` operations) and Entra ID sign-in logs
     (continued, now-failing attempts from the flagged IP) rather than trusting the script's own
     success text alone. `validate/Test-CompromisedAccountResponse.ps1` is also explicitly documented
     as safe to re-run *after* containment as a second, independent state check.
2. **Ordering matters and is already correct.** Identity actions (disable, revoke sessions, reset
   password) run before mailbox cleanup (forwarding, rules, delegate grants) - so a still-live
   attacker session can't recreate a rule in the gap between cleanup steps. This was already the
   script's design; no change needed, but it's worth stating as a positive finding, not an accident.
3. **Idempotency is genuinely testable, not just claimed.** `README.md` §7 item 4 has the investigator
   re-run the same config twice and confirm the second run reports everything as already-applied -
   a concrete pass/fail check, not just a design assertion.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Governance gap: who is allowed to run this, and is every run itself monitored?** A tool this
   powerful needs the same access discipline as any other privileged emergency action - without it,
   the tool becomes a new insider-threat vector rather than a pure risk reduction.
   - **Resolution:** `design.md` §9 and `README.md` §8 add explicit governance guidance: restrict the
     Entra ID roles, audit every run.
2. **Cost/risk: strong and cheap.** No license or consumption cost - every action uses baseline
   Exchange Online/Entra ID capability. The cost is the (necessary, intentional) disruption to the
   user while the account is disabled, and the operational discipline in finding #1.
3. **Board/IR narrative:** "confirmed account compromises are contained - access blocked, credential
   rotated, attacker persistence removed - in one auditable, evidence-producing run, with the
   emergency capability itself access-controlled and monitored." Concrete and defensible.
4. **Relationship to existing controls, not a gap it creates:** for tenants with Entra ID Protection
   P2, this scenario is a deliberate complement (mailbox cleanup ID Protection doesn't reach), not a
   sign the license is being under-used - `design.md` §7 states this so a CISO evaluating the license
   mix understands the overlap correctly.
5. **Would I fund this?** Yes - low cost, high-value emergency capability, with the access-governance
   condition in #1 attached as a deployment requirement, not an afterthought.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Directly grounded in Microsoft's own documented playbook, not an invented one.** Every scripted
   action (disable, revoke sessions, clear forwarding, remove Inbox rules including hidden ones) maps
   onto a specific, numbered step of "Respond to a compromised cloud email account"
   [[1]](#references), with cmdlets and parameters matched to that article's own worked examples, not
   paraphrased.
   - No change needed - confirmed correct.
2. **Not reinventing a native capability - initially unclear, now stated honestly.** Microsoft Entra
   ID Protection's risk-based Conditional Access already automates password-change/block/session-
   revocation for P2 tenants.
   - **Resolution:** `design.md` §7 and `README.md` §11 name this directly and scope this scenario's
     value-add correctly: the mailbox-level cleanup ID Protection doesn't reach, plus a path for
     tenants or incidents outside ID Protection's automatic coverage.
3. **Correct RBAC nuance, honestly flagged where unconfirmed.** `accountEnabled`/`passwordProfile` are
   correctly identified as Entra ID "sensitive properties" with role requirements confirmed directly
   against the privileged-roles reference; the Exchange Online RBAC role for the mailbox cmdlets is
   the one item this build could not pin to a specific role from each cmdlet's own reference page -
   `README.md` §11 flags it as VERIFY with a concrete tenant-side confirmation command
   (`Get-ManagementRoleEntry`) rather than asserting a role unconfirmed by Microsoft's own docs.
4. **Delegate-permission cleanup is honestly scoped as this scenario's own extension**, not
   misattributed to Microsoft's numbered Step 6, which only covers forwarding/rules - `design.md` §5.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (password-exposure channel; blind-restore risk; org-wide scope boundary; tool-as-attack-surface) | Closed |
| 🔵 Blue Team | Fix | 1 (independent audit-log confirmation); 2 confirmed correct (ordering, idempotency test) | Closed |
| 🎩 CISO | Fix | 1 (access governance); Pass on cost/narrative/license-overlap framing | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (native-capability comparison); 3 confirmed correct (playbook grounding, RBAC nuance, honest scenario-extension labeling) | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/Invoke-CompromisedAccountResponse.ps1`, `deploy/config/compromised-account-response.sample.json`,
`validate/Test-CompromisedAccountResponse.ps1`, and `rollback.md`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9, with the Exchange Online RBAC role mapping
recorded as an explicit VERIFY (not fabricated) per `AGENTS.md` §4.
