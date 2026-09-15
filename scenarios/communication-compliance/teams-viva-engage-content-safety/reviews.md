# Four-Lens Review — Communication Compliance: Teams & Viva Engage Content Safety Detection

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Short messages bypass this classifier family entirely, and the original draft only disclosed
   the word-count figure as a documentation inconsistency, not as an exploitable detection gap.**
   Whether the true minimum is three or five words, a terse, unambiguous message — "going to hurt
   him", "want to end it" — can fall under either threshold and never reach the classifier. A
   deliberately evasive sender (or simply someone in crisis who writes tersely) is invisible to this
   policy on message length alone, independent of any classifier accuracy question.
   - **Resolution:** Added a named `README.md` §8 finding recommending a compensating custom keyword
     dictionary (via **Customize policy**) for tenants with a confirmed short-message risk profile,
     explicitly cross-referencing the evasion-phrase pattern `harassment-and-code-of-conduct`
     already established, rather than leaving the word-count gap as a passive disclosure only.
2. **The duty-of-care runbook implied continuous coverage without ever stating whether the named
   escalation contact is reachable outside business hours — a real gap given this scenario's own
   ~1 hour detection latency.** A message sent Friday evening to a business-hours-only contact could
   go unaddressed until Monday, a multi-day gap for the signal this scenario is built to catch
   quickly. The original draft's "routed immediately" language implied always-on coverage that was
   never actually confirmed to exist.
   - **Resolution:** Added an explicit after-hours/weekend coverage requirement to `README.md` §8
     (step 1) and §3's prerequisites table, and a corresponding `afterHoursCoverageConfirmed` field
     to `deploy/policy/content-safety-policy-manifest.json` so this isn't left as an unstated
     assumption — if coverage genuinely doesn't exist, the runbook now requires documenting that as
     an accepted residual risk rather than silently implying 24/7 response.
3. **English-language-only reliability for a crisis-detection use case is a sharper finding here
   than a passing footnote.** Azure AI Content Safety's text models are specially trained/tested on
   eight languages, with lower, untested quality elsewhere [[5]](README.md#references) — for the
   Hate/Violence classifiers this is a conduct-monitoring accuracy question, but for Self-harm
   specifically, a missed non-English crisis signal is the single worst-case outcome this scenario
   exists to prevent.
   - **Resolution:** `README.md` §11 already carried this as a standalone, VERIFY-tagged bullet in
     the initial draft — confirmed correct and appropriately weighted on review (it already avoids
     asserting Purview's general "12 languages" claim applies to this specific preview classifier
     family); no further change needed beyond the sharper framing already applied to finding 2 above,
     which shares the same underlying "don't imply coverage that isn't confirmed" principle.
4. **Storage-limit auto-deactivation (the same silent-failure mode both sibling scenarios already
   flag) carries a worse consequence here** (losing Self-harm coverage, not just general
   conduct-monitoring) — already correctly escalated in the initial draft's `README.md` §8/§9/§10
   language ("materially worse consequence... monitor actively"); no further change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The runbook's "immediate escalation" instruction had no operational teeth without confirmed
   after-hours reachability** — same underlying gap as Red Team finding 2, from the operability
   angle: a runbook step that assumes continuous coverage without confirming it is not actually
   operable, it's aspirational. Closed by the same `README.md` §8/§3 and manifest changes described
   under Red Team finding 2 above.
2. **The audit-trail script's Self-harm warning could be misread as a substitute for real-time
   alerting, and the original draft's wording didn't foreclose that reading strongly enough.** The
   script runs on whatever schedule it's given (daily/weekly) — a `Write-Warning` appearing in that
   run's console output, hours or days after the underlying message, is not the same signal as the
   in-portal alert the actual runbook depends on.
   - **Resolution:** Confirmed `deploy/Export-ContentSafetyAuditTrail.ps1`'s Self-harm warning
     message already states explicitly "this is a SECONDARY, schedule-dependent record" and
     instructs the operator not to treat discovering it here as the first response; `validate/
     Test-ContentSafetyAuditTrail.ps1`'s corresponding check carries the same language. Confirmed
     sufficient on review — no further change needed, this was already correctly scoped in the
     initial draft, not a gap.
3. **Alert-aggregation threshold guidance correctly carried over** from `copilot-interaction-
   detection`'s own finding (lower to the documented minimum of 3) — present in the initial draft's
   `README.md` §8; confirmed appropriate for this scenario's risk profile, no change needed.
4. **Incident-response runbook correctly separates Self-harm's welfare-response framing from
   standard conduct-violation remediation vocabulary** (Resolve/Tag as/Notify/Escalate) — already
   present in the initial draft; confirmed this avoids the failure mode of an Investigator applying
   a "Noncompliant" conduct tag to what is actually a crisis signal.

No remaining Fail. Detection, logging, the runbook, and the after-hours-coverage addition meet the
bar for an operable control — conditional on the manifest's `afterHoursCoverageConfirmed` field
actually being set to `true` with real coverage behind it before go-live, not left at its default.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **A deployed self-harm-detection control that the organization treats as "problem addressed"
   is a worse framing than not deploying it at all, and the original draft's business-driver
   section stated the legal-liability side of this argument but not the compliance-theater side
   explicitly enough.** A preview classifier with disclosed word-count and language gaps, paired
   with an org that stops promoting its actual EAP/crisis-support program because "the Purview
   policy has it covered," would be a worse outcome than the status quo — this needed to be a named
   risk, not left implicit in the "not a substitute" line already in §11.
   - **Resolution:** Added an explicit `README.md` §2 paragraph naming this directly ("should not be
     represented as [a wellbeing program]... compliance-theater framing this scenario's own docs
     reject") as a companion to the existing legal-liability framing, so both sides of the CISO
     risk-narrative are stated with equal weight rather than one being a full paragraph and the
     other a single limitations-list bullet.
2. **Risk reduction vs. cost is clear and proportionate.** No PAYG component found for this
   scenario's scope, appropriately hedged rather than asserted as a guarantee (§10); the
   Communication Compliance E5-tier licensing is typically already satisfied by a tenant running
   either sibling scenario — correctly disclosed, no discrepancy found on review.
3. **Board-level narrative is honest, not overclaiming.** "We monitor Teams/Viva Engage for
   conduct-safety and self-harm risk signals, with a trained HR/Legal review team and a documented
   duty-of-care escalation path" is defensible — and, after this round's fixes, now explicitly
   conditioned on that escalation path actually having after-hours coverage and the classifier's
   real limitations being disclosed, not glossed over.
4. **Would I fund this?** Yes, conditional on (a) the duty-of-care runbook actually being staffed
   with confirmed after-hours coverage before go-live (now an explicit precondition, not an
   assumption) and (b) the reviewer team completing the tabletop drill (§7) — the same
   conditional-approval pattern this repo's CISO lens already applied to both sibling scenarios,
   extended here with the after-hours-specific condition this scenario's risk profile requires.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correctly distinguished the "Detect inappropriate content" template (this scenario) from
   "Detect inappropriate text" (`harassment-and-code-of-conduct`) throughout** — these are easy to
   conflate given the near-identical names in Microsoft's own template catalog table; verified on
   review that every reference in `README.md`, `design.md`, and the manifest consistently uses the
   correct, full template name with no drift. No change needed.
2. **A genuine, disclosed source inconsistency in Microsoft's own documentation — verified, not
   assumed.** This build independently fetched the live `communication-compliance-policies` page and
   confirmed both "three or more words" and "five or more words" appear verbatim in two different
   sections of the *same current page*, not a stale-cache artifact from comparing two page versions.
   Correctly surfaced as a disclosed inconsistency (`README.md` §6/§11) rather than silently picking
   one figure, matching this repo's established pattern for the "Harassment"/"Targeted harassment"
   and template-naming inconsistencies both sibling scenarios already document.
3. **Correctly declined to assert the Severity-column level-name mapping (Safe/Low/Medium/High)
   as Purview-specific behavior.** Those descriptions come from Azure OpenAI content-filter and
   Content Safety Transparency Note documentation, not a Purview-specific source confirming the
   Communication Compliance UI surfaces those exact labels — `README.md` §6 cites only the
   confirmed 0–7/trimmed-to-0,2,4,6 scale and the ≥4 alert threshold, both of which *are* documented
   on the Purview-specific page, without over-extending into an unconfirmed UI-label claim. Correct,
   disciplined sourcing; no change needed.
4. **Reviewer-pool reuse decision (same HR/Legal team as `harassment-and-code-of-conduct`, not a new
   pool) is well-reasoned and consistent with this repo's role-group naming** (`docs/rbac-model.md`
   §4) — no invented role name, and the rationale (one trained team, one duty-of-care runbook to
   maintain) is sound and explicitly stated rather than assumed. No change needed.
5. **No-write-API claim correctly extended from both sibling scenarios' precedent** to this
   template specifically, checked against the same primary source rather than assumed identical by
   analogy alone. No change needed.
6. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`'s existing
   Communication Compliance row; consistent, no discrepancy found. The PAYG claim is correctly
   hedged as "not documented as required" rather than asserted as a confirmed absence, which is the
   correct level of confidence given this build's grounding pass did not find an explicit statement
   either way for this specific classifier family (distinct from the Copilot scenario's PAYG
   footnote, which does have a direct, explicit source).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 closed with new README/manifest content, 2 already correctly covered) | Closed |
| 🔵 Blue Team | Fix | 4 (1 closed via the shared after-hours fix, 3 confirmed already sound) | Closed |
| 🎩 CISO | Fix | 4 (1 closed with a new compliance-theater-risk paragraph, 3 confirmed sound) | Closed |
| 🟦 Microsoft Product Owner | Fix | 6 (all 6 confirmed correct on verification, no changes needed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-ContentSafetyAuditTrail.ps1`, `validate/Test-ContentSafetyAuditTrail.ps1`, and
`deploy/policy/content-safety-policy-manifest.json`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.
