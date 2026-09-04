# Four-Lens Review — PCI Teams Exfiltration Block, Part 2: Split/Obfuscated PAN Compensating Control

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This control produces zero detectable signal against a maximally disciplined attacker.** If
   a sender splits a PAN finely enough (one digit per message) and generates no other
   exfiltration-type activity, neither the Communication Compliance SIT indicator nor any other
   Cumulative Exfiltration Detection indicator this fragment enables produces any score for that
   user — there is nothing for Adaptive Protection to elevate. The original draft implied this
   fragment "closes" the split-PAN gap without stating this hard bound on its real coverage.
   - **Resolution:** Added an explicit bullet to `README.md` §11 stating this bound plainly:
     the control helps against an *imperfect* evasion attempt (one that trips a SIT somewhere, or
     is paired with other exfiltration activity), not a theoretically perfect one. `design.md` §1
     already framed this fragment as a compensating control rather than a fix; the new bullet
     makes the specific mechanism of the remaining gap explicit rather than only asserting it in
     general terms.
2. **A patient attacker who understands the ~daily cumulative-exfiltration-detection cadence and
   the up-to-36-hour Adaptive Protection propagation delay could complete an entire drip-feed
   exfiltration campaign inside that window and then stop**, evading an Elevated-risk assignment
   entirely before this control's block could ever apply.
   - **Resolution:** Not independently fixable — this is a backend processing characteristic of
     the Purview service, not a property of this fragment's code (`design.md` §7, non-goals).
     Documented as a residual timing gap in `README.md` §11 (the "on the order of one to two
     days" exposure-window callout) rather than left unstated. A CISO evaluating this control
     should weigh it against the realistic threat model — a slow, low-volume drip campaign, not a
     single-session dump — per the CISO lens below.
3. **Card Operations override removal could itself become an operational-disruption attack
   surface** — could a bad actor deliberately manufacture activity that drives a *legitimate* Card
   Ops user's risk level to Elevated (e.g., reporting them for unrelated policy violations) purely
   to cut off their ability to do their job via the override path?
   - **Resolution:** Assessed and not changed. This risk exists at the Insider Risk Management
     layer generally (any IRM-fed control can, in principle, be gamed by manufacturing a false
     signal) and is not specific to this fragment; the incident-response runbook's requirement to
     confirm the actual triggering indicator before treating a block as a true positive (`README.md`
     §8, step 2) is the existing, proportionate mitigation. No new control was added, since doing
     so would duplicate IRM's own alert-triage process rather than add real value.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A user can reach Elevated risk — and be fully blocked by this rule — from activity unrelated
   to card data**, since the triggering event and Cumulative Exfiltration Detection score *all*
   enabled indicators for an in-scope user, not just the Credit Card Number one. The original
   draft's runbook didn't explicitly direct an analyst to check *which* indicator caused the
   assignment before treating a block as a card-data incident.
   - **Resolution:** Added an explicit bullet to `README.md` §11 and strengthened runbook step 2
     in §8 to require confirming the specific triggering indicator, not just cross-referencing
     that *an* IRM alert exists.
2. **Pre-production validation is slow by construction** — a pilot test requires either a real
   detection cycle or manual "Start scoring activity for users," then waiting through the ~daily
   cumulative-exfiltration-detection cadence and up-to-36-hour Adaptive Protection propagation
   before confirming the rule fires end-to-end.
   - **Resolution:** Not changed — this is the same class of inherent testing friction
     `dynamic-risk-dlp-enforcement/reviews.md` already accepted for its own rule, not a defect
     this fragment introduces. Already documented in `README.md` §7 (functional test) and §11.
3. **No dashboard view correlates this specific rule's blocks with the feeder policy's Communication
   Compliance indicator specifically** (vs. its other enabled indicators) — an analyst has to
   open the individual alert to know which indicator fired.
   - **Resolution:** Not changed — this is a portal capability gap, not something this fragment's
     code can add; flagged as inherent to the platform (same class of gap as finding 1's
     resolution already documents at the alert-detail level, which *is* where the indicator
     breakdown is visible per Microsoft's own Activity explorer documentation).

No remaining Fail. The runbook update closes the one gap that was actually actionable from this
fragment's own scope.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate and honestly bounded. This fragment reuses licensing
  already required by Part 1 and `dynamic-risk-dlp-enforcement` — no incremental spend — and
  converts a previously undocumented-and-permanent gap into a documented, partially-mitigated one
  with a clear, stated limit on its coverage (§11). That honesty is itself the right board-level
  posture: "we closed what's closable, and here's exactly what remains open" is defensible in a
  way that a silent claim of full coverage is not.
- **Change-management impact:** correctly flags the HR/Legal coordination requirement (§8) before
  broad rollout, consistent with `dynamic-risk-dlp-enforcement`'s own CISO finding — this fragment
  doesn't relitigate that finding, it correctly inherits and applies it to a new, even more
  consequential action (full external-Teams block, no override, even for a previously-trusted
  Card Ops member).
- **Board-level narrative:** "the DLP control alone can't catch a deliberately split card number,
  so we pair it with behavioral detection that shuts off the channel once a pattern emerges — it
  won't catch the first message of a perfect attempt, but it closes the door on every attempt
  after" is a defensible, specific narrative that matches what the technical control actually
  does, per the Red Team findings above.
- **Compliance mapping:** unchanged from Part 1 (PCI DSS Requirement 4.2 primary, Requirement 10
  secondary) — this fragment strengthens the existing control's defensibility rather than
  claiming a new compliance citation of its own.
- **Would I fund this?** Yes, specifically because the residual-risk framing in `README.md` §11
  is honest rather than promotional — a CISO can present this to an assessor or board without
  risk of the claim being contradicted on closer technical review.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Teams DLP alerts are not a supported Insider Risk Management trigger workload — the original
   design direction (before this build's grounding pass) assumed otherwise.** This is exactly the
   kind of assumption `AGENTS.md` §4 requires be caught before shipping, not fabricated around.
   - **Resolution:** The build discarded that direction once the constraint was confirmed against
     Microsoft's own documentation (`design.md` §3) and rebuilt the design around the
     Communication Compliance SIT indicator instead — the only documented path that actually
     covers Teams. This isn't a resolution applied after review; it's the reason the shipped
     design looks the way it does. Recorded explicitly in `design.md` §3 so a future maintainer
     doesn't rediscover and re-attempt the non-working approach.
2. **No single Microsoft-published example validates this exact end-to-end composition** (SIT
   indicator → Data-leaks cumulative scoring → Adaptive Protection → a rule on one specific named
   policy) as one worked scenario, even though every individual piece is independently grounded.
   - **Resolution:** Added `design.md` §6b, an explicit `VERIFY` flag distinguishing "every piece
     is grounded" from "the composition is Microsoft-validated end-to-end," and pointed it at the
     pilot-tenant functional test in `README.md` §7 rather than asserting the combination works
     as designed without qualification.
3. **Template choice (`Data leaks` vs. `Data leaks by priority users`) wasn't justified in the
   original draft** — a reviewer familiar with the priority-users template could reasonably ask
   why it wasn't used for a role-scoped population like Card Operations.
   - **Resolution:** Added `design.md` §6a explaining the choice: priority-users scoring is
     designed for a priori higher-risk populations identified independent of activity, which
     would misrepresent Card Ops/Finance as inherently risky rather than activity-risky; also
     keeps scoping mechanism consistent with this library's other IRM/Adaptive Protection
     scenarios.
4. **No override / hard-block scope for the new rule matches Microsoft's own documented
   Quick-Setup Elevated-block behavior** (no user override on Elevated, per
   `dynamic-risk-dlp-enforcement/design.md` §6, already reviewed and confirmed there) — correctly
   reused rather than re-derived or diverged from without cause.
5. **Cmdlet/parameter grounding** — `SharedByIRMUserRisk`, `AccessScope`, `BlockAccess`,
   `Priority` are all reused from already-reviewed prior scenarios in this library
   (`pci-teams-exfil-block`, `dynamic-risk-dlp-enforcement`); no new unverified parameter usage
   was introduced by this fragment's deploy script.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 coverage-bound clarified, closed; 1 timing gap documented, not fixable; 1 assessed, no change needed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 runbook gap closed; 2 confirmed inherent, not fixable by this fragment) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 5 (2 closed with design.md additions, 1 explains a discarded design direction, 2 confirmed correct reuse) | Closed |

All Fix items from this round are resolved in the current state of `README.md` and `design.md`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
