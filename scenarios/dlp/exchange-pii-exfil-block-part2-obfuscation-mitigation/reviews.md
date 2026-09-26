# Four-Lens Review — Exchange PII Exfiltration Block, Part 2: Split/Obfuscated PII Compensating Control

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The parent scenario's `-ExceptionGroupEmail` population in `-Action Encrypt` mode gets ZERO
   additional protection from this fragment, and the original draft did not surface this.** Tracing
   the actual rule wiring: in Encrypt mode, exception-group members are excluded
   (`ExceptIfFromMemberOf`) from `PII-Exchange-Protect-External` (the parent policy's only
   High-severity external-recipient rule besides the Block-mode-only Override rule), and no
   equivalent override rule exists in Encrypt mode. Their matching traffic either generates no
   alert at all, or — if the separate Encrypt-mode audit companion scenario is deployed — a
   **Low**-severity one. This fragment's feeder IRM policy only triggers on High-severity alerts
   (§5, Step 2 of `README.md`). A compromised or malicious exception-group member in Encrypt mode
   can therefore send unlimited split-SSN/PAN content externally and never accumulate any signal
   this fragment relies on — the exact population the parent scenario's own `reviews.md` already
   flagged as a "silent exception" gets a compensating control that structurally cannot reach it.
   - **Resolution:** Added an explicit, detailed bullet to `README.md` §11 tracing the exact
     mechanism (not just asserting the gap) and naming the concrete mitigation an organization can take
     (raise the companion rule's `-ReportSeverityLevel` to `High`, with the resulting trade-off
     stated plainly). This is a genuine limitation of the current design, not fixable by this
     fragment alone without changing a different scenario's severity default — documented rather
     than silently left for a technical reviewer to discover independently.
2. **Zero detectable signal against a maximally disciplined attacker.** If a sender splits an
   SSN/PAN finely enough that no single message ever trips a SIT, and generates no other
   exfiltration-type activity, neither the parent policy's alert nor any other Cumulative
   Exfiltration Detection indicator produces any score for that user — there is nothing for
   Adaptive Protection to elevate.
   - **Resolution:** Already stated plainly in `README.md` §11 as an explicit bound on the
     control's real coverage, matching the standard this library's Teams sibling fragment already
     set for the same class of finding. No further change needed.
3. **A patient attacker who understands the ~daily cumulative-exfiltration-detection cadence and
   the up-to-36-hour Adaptive Protection propagation delay could complete an entire drip-feed
   exfiltration campaign inside that window and then stop**, evading an Elevated-risk assignment
   entirely before this control's block could ever apply.
   - **Resolution:** Not independently fixable — a backend processing characteristic of the
     Purview service, not a property of this fragment's code (`design.md` §7, non-goals).
     Documented as a residual timing gap in `README.md` §11 (the "on the order of one to two days"
     exposure-window callout) and tracked via the KPI in §8, matching the Teams sibling's own
     treatment of the identical timing constraint.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **If both this fragment and its Teams sibling (`pci-teams-exfil-block-part2-obfuscation-
   mitigation`) are deployed against the same tenant, an analyst investigating a block from this
   rule must determine *which* feeder IRM policy actually drove the Elevated-risk assignment**
   before assuming an Exchange-specific PII pattern — Cumulative Exfiltration Detection and
   Adaptive Protection compute one risk level per user across every in-scope feeder policy, so an
   Elevated block from this rule could equally have been driven by Teams card-data activity the
   sibling fragment's own feeder policy detected.
   - **Resolution:** `README.md` §8's incident-response runbook step 2 explicitly names checking
     "which feeder IRM policy" as part of confirming the triggering source, and cross-references
     the Teams sibling's feeder policy by name as a concrete alternative source to rule out — not
     left as a generic "check the alert" instruction.
2. **Pre-production validation is slow by construction** — a pilot test requires either a real
   detection cycle or manual "Start scoring activity for users," then waiting through Cumulative
   Exfiltration Detection's ~daily cadence and up-to-36-hour Adaptive Protection propagation before
   confirming the rule fires end-to-end.
   - **Resolution:** Not changed — the same class of inherent testing friction the Teams sibling
     fragment and `dynamic-risk-dlp-enforcement` already accepted for their own rules, not a defect
     this fragment introduces. Already documented in `README.md` §7 (functional test, marked
     VERIFY) and §11.
3. **The validate script's compaction check is name-agnostic by design (§ design.md §6), which
   means it cannot warn an operator if a rule they expected to exist (e.g., the Encrypt-mode audit
   companion) is silently absent** — it only confirms whatever rules *do* exist are correctly
   compacted, not that the *right set* of rules is present.
   - **Resolution:** Assessed and not changed as a hard failure — this script's stated scope (§
     `Test-ExchangePiiElevatedRiskBlock.ps1` header comment) is verifying this fragment's own rule
     and its interaction with whatever else exists, not auditing the parent scenario's or
     companion scenario's own deployment completeness, which each already has its own validate
     script for. Adding that cross-scenario check here would duplicate ownership rather than add
     real coverage.

No remaining Fail. The runbook update closes the one gap that was actually actionable from this
fragment's own scope.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost — the E3→E5 tier transition is the real conversation, and it's stated
  honestly.** The parent scenario deliberately stays on base E3 specifically to keep Part 1's cost
  profile minimal (`exchange-pii-exfil-block/README.md` §10). This fragment cannot be added without
  committing to the E5/Purview Suite tier for Insider Risk Management and Adaptive Protection —
  `README.md` §10 states this as a tier decision, not an incremental line item, which is the
  correct level of honesty for a budget conversation. A CISO evaluating "Part 1 alone" vs. "Part 1
  + Part 2" is evaluating two different licensing commitments, and the docs make that explicit
  rather than burying it as a footnote.
- **Change-management impact:** correctly flags the HR/Legal coordination requirement (§8) before
  broad rollout, consistent with every other Elevated-block rule in this library — this fragment
  doesn't relitigate that finding, it correctly inherits and applies it to a new consequential
  action (full external-Exchange block, no override, even for a previously-trusted exception-group
  member).
- **Board-level narrative:** "the DLP control alone can't catch a deliberately split SSN or card
  number, so we pair it with behavioral detection that shuts off the channel once a pattern
  emerges — it won't catch the first message of a perfect attempt, but it closes the door on every
  attempt after" is a defensible, specific narrative that matches what the technical control
  actually does, per the Red Team findings above. The Red Team's exception-group-in-Encrypt-mode
  finding is a genuine residual gap a CISO should know about before presenting this as complete
  coverage — it's disclosed, not hidden, which keeps the narrative defensible under scrutiny.
- **Compliance mapping:** unchanged from Part 1 (GDPR Article 32 / CCPA/CPRA / ISO/IEC 27001:2022
  Annex A.5.12/A.8.2) — this fragment strengthens the existing control's defensibility rather than
  claiming a new compliance citation of its own.
- **Would I fund this?** Yes, conditional on the deploying organization already needing or accepting the E5 tier for
  other reasons (this library's Adaptive Protection/IRM scenarios generally assume that tier is in
  scope) — for an organization that specifically wants to stay at E3, this fragment is a deliberate
  "not yet" rather than something to force through, and the docs make that tradeoff visible enough
  for that decision to be made deliberately rather than by accident.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

- **Correct capability, and a better-fitting one than the pattern being copied.** This fragment
  does not merely port the Teams sibling's design — `design.md` §3 and §6a correctly identify that
  Exchange Online is a natively supported DLP-alerts workload and uses the more precise, more
  directly Microsoft-endorsed "User matches a DLP policy" triggering event instead of defaulting to
  the broader exfiltration-activity trigger the Teams sibling was forced into by a workload gap.
  Recognizing when *not* to copy a sibling pattern verbatim, because a better-fitting native option
  exists, is the right instinct and is explicitly justified rather than asserted.
- **Priority-compaction generalization is a genuine improvement, correctly scoped to why it's
  needed.** `design.md` §6 explains precisely why a hardcoded rule-name list (the Teams sibling's
  approach) would be wrong here: the parent Exchange scenario has an *optional* rule
  (`-ExceptionGroupEmail`) and an entirely separate, optionally-deployed companion scenario that
  appends its own rule at a dynamically-computed priority. The name-agnostic compaction algorithm
  is the correct generalization for that specific interaction, not generalization for its own sake.
- **Cmdlet/parameter grounding** — `SharedByIRMUserRisk`, `AccessScope`, `BlockAccess`, `Priority`
  are all reused from already-reviewed prior scenarios in this library (`exchange-pii-exfil-block`,
  `dynamic-risk-dlp-enforcement`, the Teams sibling); no new unverified parameter usage was
  introduced by this fragment's deploy script.
- **"Hard block regardless of the parent policy's `-Action` mode" is correctly justified, not just
  asserted.** `design.md` §6 states the reasoning (an Elevated-risk sender should not receive the
  operator's chosen leniency level for the general population) rather than leaving the
  Block-vs-Encrypt interaction ambiguous — a reviewer checking whether this fragment "does the
  obviously right thing" for both parent-scenario modes can confirm it does from the design
  rationale alone, without needing to trace the code.
- **No single Microsoft-published example validates this exact end-to-end composition** (a named
  DLP policy's High-severity alerts → Data-leaks direct trigger → Cumulative exfiltration scoring →
  Adaptive Protection → a rule on that same named policy), even though every individual piece is
  independently grounded.
  - Already flagged as an explicit `VERIFY` in `design.md` §6b and `README.md` §11/§7, at the same
    standard the Teams sibling fragment already set for its own analogous composition — not
    asserted as Microsoft-validated without qualification.

No Fix/Fail items from this lens — the one open item (§6b, end-to-end composition VERIFY) is
already correctly flagged rather than needing a review-driven fix.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 genuine coverage gap newly surfaced and documented with a concrete mitigation; 2 confirmed inherent/already documented) | Closed |
| 🔵 Blue Team | Fix | 3 (1 runbook gap closed with a concrete cross-reference; 2 assessed as correctly scoped, no change needed) | Closed |
| 🎩 CISO | Pass | 0 (E3→E5 tier transition scrutinized and confirmed already stated honestly) | — |
| 🟦 Microsoft Product Owner | Pass | 0 (design choices confirmed as correct, better-fitting adaptations of the sibling pattern rather than blind reuse) | — |

All Fix items from this round are resolved in the current state of `README.md` and `design.md`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
