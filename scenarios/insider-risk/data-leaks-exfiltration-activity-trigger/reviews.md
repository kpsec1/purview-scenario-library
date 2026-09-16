# Four-Lens Review — Insider Risk Management: Data Leaks (exfiltration-activity trigger)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A user is never analyzed for an exfiltration channel this policy scores but did not select as
   a trigger indicator — a structurally narrower attack surface than the DLP-trigger sibling.** The
   original draft documented the trigger-indicator/scoring-indicator distinction as a workflow
   mechanic (`design.md` §5) but did not draw out its security consequence: only the specific
   indicator(s) chosen on the Triggers page bring a user into scope at all. A tenant that selects a
   narrow trigger set (e.g. only SharePoint downloads) but a broader scoring set (e.g. also personal-
   cloud copying) never analyzes a user who exclusively performs the scoring-only activity and never
   crosses the trigger threshold for the selected trigger indicator — that user is invisible to this
   policy regardless of volume. This is a materially different (and easier to under-scope) coverage
   model than the DLP-trigger sibling, where a single DLP policy's rule scope can span multiple
   content types more broadly in one trigger condition.
   - **Resolution:** Added an explicit `README.md` §11 bullet naming this consequence directly (not
     just the mechanical distinction), a cross-reference from §8's operational reminder, and
     `design.md` §5's existing description of the overlap-or-differ property is now paired with this
     finding rather than left as a neutral workflow note.
2. **Static, disclosed trigger thresholds remain pace-able by a disciplined insider, and the
   "anomalous activity" alternative has its own disclosed evasion property.** Both are the same
   class of finding this library's other fixed-threshold Insider Risk Management scenarios already
   carry (`data-leaks-by-risky-users/README.md` §11).
   - **Reviewed, already correctly disclosed:** the original draft's §11 already states both the
     pacing-under-a-static-threshold evasion and the "paces within their own historical norm evades
     anomalous-activity detection too" property in the same bullet, correctly scoped as a structural
     property of the detection model rather than a fixable configuration gap. No additional change
     needed.
3. **Relying on Microsoft's undocumented default threshold values for a security-relevant trigger
   is a real operational risk, not just a grounding footnote** — an operator who accepts "Use
   default thresholds (Recommended)" for a customer-facing control has no way to state, or defend
   under audit, what volume of activity actually triggers analysis.
   - **Reviewed, already correctly disclosed and mitigated:** the original draft's §5 Step 5
     already recommends using custom thresholds specifically when exact sensitivity must be
     documented, and §11/the manifest both flag the unpublished-default-values gap as an open
     VERIFY rather than asserting a number. No additional change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A trigger indicator this policy depends on can be silently disabled by another administrator
   acting on an unrelated policy, with no notification to this policy's owner.** Because a trigger
   indicator must first be turned on tenant-wide (Settings → Policy indicators) before it's
   selectable in any policy, and that setting is shared across every Insider Risk Management policy
   in the tenant, a different team disabling an indicator to reduce noise on their own policy
   silently removes it from this policy's trigger set too — the same class of shared-tenant-wide-
   setting blast radius `data-leaks/README.md` §8 already documents for its own global DLP-alerts
   indicator setting, but the original draft of this scenario didn't carry an equivalent warning for
   built-in indicator enablement.
   - **Resolution:** Added a `README.md` §8 bullet naming this risk explicitly and recommending
     periodic re-verification, cross-referencing the sibling scenario's analogous finding rather than
     treating it as a new, unrelated risk class.
2. **No automated way to detect that a trigger or scoring threshold was changed from what the
   manifest records — the same disclosed limitation every portal-only IRM scenario in this library
   carries**, here doubled because two independent thresholds (trigger and scoring) both lack a read
   API.
   - **Reviewed, already correctly disclosed:** the original draft's §11 and the validation script's
     manual checklist both call out the no-read-API limitation for both threshold decisions
     separately, and the manifest is explicitly labeled a manually-maintained reference rather than
     a live source of truth. No additional change needed.
3. **If both this scenario and its DLP-trigger sibling are deployed in the same tenant, a SOC
   analyst triaging an exported alert cannot determine which policy — or which trigger mechanism —
   produced it**, compounding the already-disclosed `AlertPolicyId` gap with a second layer of
   ambiguity specific to having two Data-leaks-template policies active at once.
   - **Resolution:** Added a validation-script manual-checklist item and a `README.md` §8 bullet
     recommending distinct, clearly-differentiated policy names when both scenarios are deployed
     together, so at least the policy list (if not the exported alert itself) disambiguates them.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once the
Fix items above are applied.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** favorable, and materially cheaper to stand up than either the DLP-
  trigger sibling (requires an already-tuned qualifying DLP policy) or the HR-connector-triggered
  family (requires HR data-sharing governance review) — this trigger path needs only Insider Risk
  Management's own base entitlement and indicator enablement.
- **Board-level narrative:** "we can stand up general-population exfiltration monitoring today,
  without waiting on a DLP rollout or an HR data-sharing agreement" is a materially different, easy-
  to-communicate value statement distinct from every other scenario in this Data-leaks family.
- **Compliance mapping:** correctly scoped as general-population exfiltration-monitoring evidence
  with no named regulatory requirement number — same honest framing as every Insider Risk
  Management scenario in this library; the original draft did not overstate this.
- **Cost/complexity of running this alongside the DLP-trigger sibling is disclosed, not
  hand-waved** — §10's sizing note and §8's coordination bullet both correctly identify the shared
  15,000-user cap and the two-separately-maintained-policies overhead as the real cost of running
  both rather than one.
- **Open questions are surfaced as open, not resolved by optimistic assumption** — the unpublished
  default-threshold values, the trigger-vs-scoring coverage gap, and the DLP-trigger combinability
  question are all flagged as VERIFY/disclosed limitations rather than guessed, exactly what a CISO
  needs before a customer-facing commitment.
- **Would I fund this?** Yes — it is the lowest-prerequisite path in this library's entire
  Data-leaks family to general-population exfiltration monitoring, provided the operator treats
  trigger-indicator breadth (Red Team finding 1) as a coverage decision, not an afterthought.

No Fix/Fail raised from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **This build's citations were grounded via a direct Microsoft Learn MCP fetch, not WebSearch
   snippets** — a stronger grounding posture than the original `data-leaks/` sibling's own
   WebSearch-only build (later supplemented by a follow-up direct-fetch pass for specific facts).
   Every quoted phrase in `README.md` §12 and `design.md` traces to a specific fetched page section.
2. **The trigger-vs-scoring indicator threshold distinction (two separate decision pages in the same
   workflow) is a genuinely new grounding contribution to this library** — no other Insider Risk
   Management scenario in this repo had previously called out that a template supporting
   customizable triggering indicators involves two independent threshold configurations, not one.
   Correctly sourced to specific numbered sub-steps of the "Get started" page's Step 6, not inferred.
3. **The combinability question (§2 goal 6) is handled with appropriate nuance** — this build's
   direct fetch found stronger (if still inconclusive) evidence than the sibling's own framing, and
   the scenario's docs state that nuance precisely (a single-select-suggestive phrasing, not a
   confirmed exclusivity statement) rather than either overriding the sibling's weaker claim or
   inflating this build's own finding into false certainty.
4. **No fabricated threshold-recommendation API, trigger-configuration read/write API, or
   combinability-toggle API.** Consistent with every other scenario in this library, this build
   found and restated the existing disclosed gaps (portal-only policy authoring, no programmatic
   threshold read-back, no way to script real-time analytics) rather than inventing a workaround.
5. **Script reuse is correctly justified, and the one new script is a genuine, non-duplicate
   contribution** — `validate/Test-DataLeaksExfiltrationActivityTriggerSetup.ps1` covers a
   materially different manual checklist (trigger indicator enablement, the two independent
   threshold decisions, the DLP-trigger-sibling-coexistence reminder) than `data-leaks/validate/
   Test-DataLeaksIrmSetup.ps1`'s own checklist, which is centered on the DLP-policy trigger's
   double-scoping requirement — not a copy-paste of the sibling script with the DLP items stripped
   out; the manual items were re-derived from this trigger path's own actual configuration surface.
6. **This scenario correctly declines to build a threshold-recommendation script** in place of
   Microsoft's own real-time analytics (preview) feature (`design.md` §7) — no Graph/PowerShell API
   exists for it, and approximating it with a custom Graph-reports-based heuristic would risk
   presenting an unconfirmed recommendation with false authority, which `AGENTS.md` §4's grounding
   standard does not permit.

No Fix/Fail from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with new README §8/§11 disclosure, 2 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed with new README §8/validation-checklist content, 1 confirmed already correctly disclosed) | Closed |
| 🎩 CISO | Pass | — | — |
| 🟦 Microsoft Product Owner | Pass | — | — |

The Red Team finding that a user is never analyzed for an exfiltration channel selected only as a
scoring indicator — not as a trigger indicator — was this round's most operationally significant
finding: it is a real, easy-to-make under-scoping mistake with no error or warning from the product
itself, and is now disclosed as a named consequence (not just a neutral mechanical description) in
both `README.md` §8 and §11. The Blue Team's tenant-wide-indicator-disable finding closes the same
class of shared-setting blast-radius gap the DLP-trigger sibling scenario already discloses for its
own global indicator setting, applied here to built-in indicator enablement. Both fixes were applied
as doc changes (this scenario introduces no new mutating script whose behavior needed a code fix —
its only new script, `validate/Test-DataLeaksExfiltrationActivityTriggerSetup.ps1`, is read-only by
design). No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
