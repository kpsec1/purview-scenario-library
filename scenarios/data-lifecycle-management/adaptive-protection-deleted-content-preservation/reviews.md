# Four-Lens Review — Adaptive Protection Deleted-Content Preservation

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This control preserves deletions, not exfiltration — and the original draft didn't say so
   plainly enough.** An Elevated-risk user who copies content out *before* deleting the local
   copy has already exfiltrated it; this control only stops them from also destroying the
   evidence. An organization skimming the summary could reasonably assume this closes exfiltration risk
   generally, which it doesn't — that's the paired DLP scenario's job.
   - **Resolution:** Added an explicit `README.md` §11 bullet stating the scope boundary plainly
     and cross-linking `dynamic-risk-dlp-enforcement` as the complementary control, not a
     duplicate.
2. **A privileged Elevated-risk user can destroy their own evidence by turning the control off —
   this is a real, high-severity bypass the original draft only implied through `rollback.md`'s
   "what turning it off does" section, without naming it as an attacker-usable path.** Anyone
   holding the Insider Risk Management/Insider Risk Management Admins role group can disable the
   toggle and immediately release everything currently preserved, tenant-wide, per Microsoft's
   own documented behavior (`design.md` §4). If that person is also the subject of the
   investigation, this is a direct self-sabotage vector.
   - **Resolution:** Added an explicit `README.md` §11 bullet and a `rollback.md` "Who can do
     this" section naming the risk, recommending minimal/reviewed role-group membership, and
     disclosing that this specific configuration change is not confirmed to be captured anywhere
     this scenario's own audit-evidence script can query (Insider Risk Management's own internal
     audit log has no documented Graph/REST API — a gap already tracked elsewhere in
     `PROGRESS.md` for a different scenario, cross-referenced here rather than re-investigated).
3. **No real-time alert on a preservation event** — an analyst only learns about it via a
   scheduled query, which is slow relative to how quickly an attacker could act on the same
   information (e.g., noticing they've been blocked elsewhere and escalating deletion attempts).
   - **Resolution:** Added a `README.md` §8/§11 recommendation to forward the two audit Operations
     to a SIEM for near-real-time alerting rather than relying solely on the daily scheduled
     export.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass (one clarification adopted from the Red Team round)**

1. **The `[INCONCLUSIVE]` (not `[PASS]`/`[FAIL]`) verdict on a zero-row result is the right call
   operationally, but risks being silently treated as `[PASS]` by a downstream dashboard that
   only checks exit code.** `validate/Test-AdaptiveProtectionDlmPreservation.ps1` exits `0` on an
   inconclusive result (correct — it's not a hard failure), but a naive CI/dashboard integration
   that maps "exit 0" to a green checkmark could misrepresent "no evidence either way" as
   "confirmed on."
   - **Resolution:** `README.md` §7 and the script's own `.DESCRIPTION`/output both state this
     explicitly and repeatedly (not just once) specifically to counter that failure mode; no
     further code change needed — this is a documentation/interpretation risk, not a script bug,
     and the script's exit-code semantics (non-zero only on genuine infrastructure failure) are
     correct as designed.
2. **The SIEM-forwarding recommendation (Red Team finding 3) is this scenario's real answer to
   "is it operable at scale," not the daily-scheduled scripts alone.** Confirmed consistent with
   how this library treats the audit-trail-export pattern elsewhere (`Export-EdiscoveryAuditTrail.
   ps1`'s own README guidance) — no new pattern invented.
3. **Correlating a preservation event back to the specific IRM case/alert that assigned the
   Elevated risk level is a manual step**, identical in shape to the same gap already reviewed and
   accepted in `dynamic-risk-dlp-enforcement/reviews.md` (Blue Team finding 2) — no shared
   correlation ID exists between the two systems.
   - **Not a new finding specific to this scenario** — consistent with already-accepted library
     precedent. No change needed beyond what §8 already says.

No Fail items.

---

## 🎩 CISO

**Verdict: Pass (one Fix)**

1. **The original draft didn't say clearly enough that this is a stopgap, not a substitute for a
   real hold once a matter is actually opened.** A preview feature, with a fixed 120-day window
   and no self-service restore, is a reasonable *automatic, always-on* safety net for the gap
   before anyone has reacted — but it is not adequate as the sole preservation mechanism once an
   investigation with real litigation exposure exists.
   - **Resolution:** Added an explicit `README.md` §8/§11 recommendation to escalate to a real
     eDiscovery hold (`scenarios/insider-risk/irm-case-escalation-to-ediscovery/`) the moment a
     case is actually opened, framing this control as defense-in-depth rather than a complete
     answer.
- **Risk reduction vs. cost:** meaningful, at zero incremental license cost for a tenant that
  already has Adaptive Protection deployed (§10) — the marginal cost is entirely the operational
  discipline in §8 (role-membership hygiene, SIEM forwarding, hold escalation), not licensing.
- **Board-level narrative:** "even if a flagged employee tries to cover their tracks by deleting
  data, we automatically keep a copy for 120 days, with no analyst having to react in time" is a
  clear, defensible narrative — now paired with an honest caveat about what it doesn't cover
  (post-fix §11) and the preview-status caveat (§3).
- **Would I fund this?** Yes, as an incremental, zero-cost addition for an organization already running
  `dynamic-risk-dlp-enforcement` — not as a standalone investment, and not presented as a
  litigation-hold replacement.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Preview status independently re-confirmed by direct fetch, not carried over from a snippet.**
   `microsoft_docs_fetch` against the live `purview/retention` page during this build returned the
   verbatim "In preview, you can use this solution with Insider Risk Management..." sentence —
   this scenario does not overclaim GA status the way a stale citation elsewhere in this library
   once did (now corrected — see `dynamic-risk-dlp-enforcement/reviews.md`'s correction addendum).
2. **No enablement cmdlet/Graph resource fabricated.** Checked: this scenario's `deploy/` script
   never claims to create, enable, or configure the underlying policy — it only queries the audit
   log, and the `.DESCRIPTION`/`design.md` are explicit that no such API exists. Consistent with
   `AGENTS.md` §4.
3. **`-RecordType` correctly omitted rather than guessed.** Checked against Microsoft's own "Audit
   log activities" reference — no RecordType is documented for these two Operations specifically;
   omitting it (rather than reusing, say, `SharePointFileOperation` by analogy) is the correct,
   conservative choice, since a wrong guess would silently under-match real events.
4. **Licensing citation accuracy.** Checked against `docs/licensing-matrix.md` §2: the "Adaptive
   Protection" row (E5/Suite, built on IRM+DLP) is the same one `dynamic-risk-dlp-enforcement`
   already cites — no new or inconsistent licensing claim introduced here.
5. **Correctly scoped as complementary to, not a replacement for, existing library scenarios** —
   `design.md` §3/§7 and `README.md` §2 place this precisely relative to
   `dynamic-risk-dlp-enforcement` (DLP half) and `irm-case-escalation-to-ediscovery` (real hold
   once a case opens), rather than re-implementing either.

No Fix/Fail items.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (all closed with `README.md`/`rollback.md` additions) | Closed |
| 🔵 Blue Team | Pass | 3 (1 confirmed as documentation risk already adequately mitigated, 1 confirmed as the Red Team fix, 1 confirmed consistent with existing library precedent) | Closed |
| 🎩 CISO | Pass | 1 closed with a `README.md` addition; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 confirmed correct/well-grounded, 0 Fix | Closed |

All Fix items from this round are resolved in the current state of `README.md` and `rollback.md`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
