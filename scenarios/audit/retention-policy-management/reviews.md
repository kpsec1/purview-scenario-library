# Four-Lens Review — Audit Log Retention Policy Management

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied before this file was finalized. No **Fail**
items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A retention *shortening* could be misused to destroy evidence early.** This scenario lets an
   admin with Organization Configuration rights create a policy that shortens retention for
   specific users or activities below the tenant default — in the wrong hands, a fast way to make
   an investigation's evidence expire sooner than it otherwise would.
   - **Resolution:** `README.md` §2 explicitly frames shortening as legitimate only for
     *identified-noisy, low-value* activity, never as a compliance shortcut, and calls out that it
     must never undercut an applicable legal-hold or regulatory floor. §11's retroactive-vs-
     forward-only VERIFY is foregrounded specifically because it's the mechanism an attacker or a
     bad-faith insider would need to understand to actually shorten retention on *already-
     committed* records — this scenario deliberately does not assert an answer that could be
     misread as "yes, shortening retroactively deletes old evidence."
2. **Who can grant the Organization Configuration role is itself a high-value target.** Any
   principal that can assign the Compliance Data Administrator role group (or edit role-group
   membership generally) can indirectly gain the power described in finding 1.
   - **Resolution:** `README.md` §3 names the specific role and role group rather than a vague
     "admin access," making it a concrete, auditable thing an organization's access review can check for.
     Broader role-group-assignment governance is out of this scenario's scope — it's covered by
     `docs/rbac-model.md`'s role-management guidance, which this scenario now cross-references.
3. **Priority-collision handling as a denial-of-service vector.** A malicious or careless actor
   who claims a low-numbered (high) priority for a broad, low-retention policy could effectively
   starve out a legitimate high-retention policy's intended coverage for overlapping activity.
   - **Resolution:** This is a real product-level risk `design.md` §5 acknowledges but doesn't
     invent a mitigation for beyond what Microsoft's own priority model provides — same-severity
     risk exists for a purely portal-driven deployment too. `README.md` §8 recommends a numbering
     convention and periodic review as the practical control; the validate script's priority-
     collision check at least surfaces any *unintentional* collision immediately.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Config drift between the portal and this script is silent without a check.** A portal admin
   editing a PowerShell-authored policy directly (where the dashboard even permits it) would
   silently diverge from the config file with no alert.
   - **Resolution:** `validate/Test-AuditRetentionPolicy.ps1` diffs every field (not just
     existence) against the live policy and is designed to run on a recurring cadence (`README.md`
     §8) specifically to catch this kind of drift, `[FAIL]`ing loudly rather than passing on a
     partial match.
2. **A partially-applied config is worse than a rejected one.** If validation happened per-entry
   during the write loop instead of up front, one bad entry could leave the tenant in a mixed
   state — some policies created, others not, with the operator unsure which.
   - **Resolution:** `design.md` §4 and the deploy script's structure explicitly validate and
     cross-check every entry (name/description limits, duration enum, priority collisions, the
     50-policy cap) **before** any cmdlet runs — a single bad entry stops the whole run with zero
     writes attempted, not a partial apply.
3. **The one test that actually proves retention takes the longest to run.** Config-object checks
   (§7 items 1, 4, 5) prove the *policy* is correct; they don't prove data actually survives
   longer under it.
   - **Resolution:** `README.md` §7 item 3 calls this out explicitly as the long-lead-time test and
     recommends starting it first, rather than letting the fast config checks create false
     confidence that retention itself has been proven.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Cost/benefit is genuinely favorable, but the value is easy to overstate.** Retention alone
   doesn't detect or prevent anything — it only preserves the evidence an already-deployed
   detection/investigation capability (or a future one) will need.
   - **Resolution:** `README.md` §1/§2 frame this explicitly as the companion to
     `premium-audit-investigation`, not a standalone control, and §2's driver section ties the
     Teams-retention gap to specific already-shipped Teams controls in this library rather than a
     generic "more retention is good" pitch.
2. **The 50-policy cap and Organization Configuration role gap are real governance-process risks,
   not just technical trivia.** An organization that doesn't plan a priority-numbering convention, or
   doesn't realize Audit Manager alone can't manage retention, will hit friction mid-rollout.
   - **Resolution:** Both are foregrounded in §3 (prerequisites, with an explicit "not sufficient
     alone" row) and §8 (operational planning), not buried in §11 as afterthoughts.
3. **Board/IR narrative:** "We retain regulated-communication and admin-activity audit data for as
   long as our compliance obligations and investigation needs require — deliberately, as code, not
   by whatever a service's default happens to be — and we can prove what that policy set is at any
   point in time via version control."
4. **Would I fund this?** Yes — low cost (config/role work only, no new license spend unless a
   duration genuinely requires a higher tier), and it closes a real gap (Teams) this library's own
   Teams-focused controls already assume is covered.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Right, current surface and cmdlets.** `New-`/`Set-`/`Get-`/`Remove-UnifiedAuditLogRetentionPolicy`
   are the current, non-deprecated Security & Compliance PowerShell cmdlets for this object, each
   independently fetched in full from their official reference pages this build (not paraphrased
   from a search snippet) — parameter sets, the `RetentionDuration` enum (confirmed identical
   between `New-` and `Set-`), the `Operations`/`RecordTypes` mutual-exclusivity rule, and the
   worked examples this scenario's sample config directly adapts.
2. **A real product-surface gap is disclosed, not glossed over.** The PowerShell `RetentionDuration`
   enum's five values vs. the portal's nine is confirmed by comparing two official pages against
   each other, not asserted from memory — and the scenario's own script actively rejects a config
   entry requesting one of the five it can't create, rather than silently misbehaving.
3. **Not reinventing a native capability.** This scenario is a thin, validated reconciliation layer
   over the native cmdlets — it doesn't reimplement retention logic, doesn't bypass the documented
   50-policy/priority-uniqueness constraints, and explicitly declines to fabricate a workaround for
   the five portal-only durations.
4. **Honest about two genuine unknowns instead of guessing.** The retroactive-vs-forward-only
   retention-edit behavior (Microsoft's own page is internally ambiguous) and the `$null`-clearing
   extrapolation from `-UserIds` to `-RecordTypes`/`-Operations` are both flagged as explicit
   VERIFYs with the exact reasoning, per `AGENTS.md` §4, rather than presented as confirmed fact.
5. **RBAC finding correctly scoped as a citation gap, not a functional bug.** The Organization
   Configuration vs. Audit Manager distinction is real and independently confirmed against the
   `scc-permissions` role-group reference — filed as a `docs/rbac-model.md` backport follow-up
   rather than silently assumed to already be covered there.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (evidence-destruction misuse framing; role-assignment governance boundary; priority-collision DoS risk) | Closed |
| 🔵 Blue Team | Fix | 3 (drift detection via validate script; all-or-nothing pre-flight validation; long-lead-time retention-proof test called out) | Closed |
| 🎩 CISO | Fix | 2 (value framed as a companion capability, not standalone; cap/role governance risks foregrounded); Pass on cost/narrative | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (RBAC citation gap filed as a follow-up); 4 confirmed correct via direct source comparison | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AuditRetentionPolicy.ps1`, `deploy/Remove-AuditRetentionPolicy.ps1`,
`deploy/config/audit-retention-policies.sample.json`, and `validate/Test-AuditRetentionPolicy.ps1`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9, with two
explicit VERIFYs recorded (retroactive-vs-forward-only retention-edit behavior; the `$null`-
clearing extrapolation) rather than fabricated, per `AGENTS.md` §4.
