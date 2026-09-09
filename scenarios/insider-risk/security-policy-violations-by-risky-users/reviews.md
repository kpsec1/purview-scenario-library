# Four-Lens Review — Insider Risk Management: Security Policy Violations by Risky Users

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The Communication Compliance trigger path has a documented, fixed threshold (5+ risky
   messages within 24 hours) that a disciplined insider aware of this control can deliberately stay
   under.** The original draft documented the threshold as a configuration fact (§6) but never
   framed it as an evasion vector — an attacker limiting themselves to 4 or fewer threatening/
   harassing/discriminatory messages per rolling 24-hour window generates no signal at all through
   that path, however severe an individual message is, and a user with no qualifying HR
   risk-indicator record either never enters this policy's scope through any path.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming this as a structural,
     Microsoft-controlled evasion vector (not a configuration gap this scenario can close), and
     recommending pairing with the base template's plain-group scope (no message-count gate) for a
     population where this specific evasion is a live concern.
2. **A red-teamer aware of the AND/OR trigger shape could deliberately avoid both trigger paths
   simultaneously** (no qualifying HR event, and staying under the CC message threshold) to remain
   permanently out of scope regardless of underlying risk. This is the direct combination of
   finding 1 above with the HR path's own inherent gap (a user whose risk manifests without ever
   triggering an HR risk-indicator record, e.g. no formal PIP or review cycle was ever initiated).
   - **Reviewed, no additional structural change needed beyond finding 1's resolution:** this is
     the same class of structural, disclosed limitation as the "invisible to an offline/physical
     attack" gap every sibling in this family already documents (README.md §11) — the honest
     answer is that this template's coverage is bounded by its two documented trigger mechanisms,
     not universal, and the base template (unconditional scope, no trigger gate at all) remains the
     compensating control for a population where this gap matters. Already implied by finding 1's
     resolution and the existing base-template cross-reference; no separate bullet needed.
3. **A guest account or service/non-interactive account onboarded to Defender for Endpoint could be
   silently excluded from scope if it has no HR record and generates no message traffic Communication
   Compliance classifies.** Structurally identical to the priority-users sibling's own no-`mail`
   candidate finding, but for a different reason (no trigger event, not a missing directory
   attribute).
   - **Reviewed, no change needed:** this is a direct restatement of findings 1/2 above from a
     different angle (a service account is simply a user for whom neither trigger path is likely
     to fire) rather than a new mechanism — already covered by the same disclosure and the same
     compensating-control recommendation (pair with the base template for populations where trigger
     coverage matters more than trigger-driven scoping).

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass (with one Fix)**

1. **Two independent trigger paths, each with its own health signal, but the original draft's §8
   guidance described monitoring them as a single combined recommendation without being explicit
   that either path failing alone is invisible if the other is healthy.** An operator who only
   checks "is the policy generating alerts at all" could miss that, say, the Communication
   Compliance path silently stopped working weeks ago while the HR path alone kept the policy
   looking active.
   - **Resolution:** `README.md` §8's "Two independent trigger paths means two independent health
     checks, not one" bullet was written explicitly during this draft to state the two checks must
     be run independently, not inferred from overall policy health — this was already correctly
     scoped in the draft under review; verified as sufficient, no further change needed beyond
     confirming it during this review pass.
2. **`Send-HrRiskIndicatorRecord.ps1`'s per-scenario column validation is intentionally loose
   (only `UserPrincipalName`/`EffectiveDate`/the scenario column are validated; everything else
   passes through unvalidated) — is there a risk this silently ingests malformed data for the
   optional columns (e.g., a garbled `OldLevel`/`NewLevel` pair) without any warning?**
   - **Reviewed, no structural change needed:** consistent with Microsoft's own stated model
     (column names and presence beyond the shared invariant are examples, not a fixed contract,
     mapped at connector-creation time in the portal) — validating optional, per-scenario columns
     the script cannot know the tenant's actual column mapping for would mean guessing at a schema
     Microsoft itself doesn't fix. The unrecognized-scenario-value warning (non-fatal, printed
     per-group) is the appropriate level of automated check here; deeper validation would require
     tenant-specific configuration this script doesn't have. No change made.
3. **Is there a detective control confirming the dedicated HR connector wasn't accidentally created
   pointing at the wrong app registration or scenario mapping?** No Graph/PowerShell read API
   exists for HR connector configuration (same disclosed gap as the departing-users sibling).
   - **Reviewed, correctly scoped:** already captured in
     `validate/Test-RiskyUsersIrmSetup.ps1`'s manual checklist as an explicit item to confirm the
     dedicated connector (not the sibling's) exists with a recent successful import log entry — the
     honest answer here is "no automated detective control exists for connector configuration
     itself," stated plainly rather than fabricated. No change needed.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once the
Fix above is applied (already present in the draft under review, confirmed during this pass).

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **This is the only Insider Risk Management scenario in this library whose triggering signal is
   drawn from performance-management HR data (PIP notifications, poor performance reviews,
   demotions) rather than a security-activity signal — the original draft treated this as a
   technical prerequisite (§3) without flagging the employment-law and perception risk of feeding
   that specific data into a security-monitoring trigger.** A CISO evaluating this template needs
   to know this before recommending it: an employee who disputes a performance action and later
   discovers it fed a security-monitoring trigger could reasonably perceive retaliation, regardless
   of the technical safeguard that a Defender for Endpoint signal is still independently required
   before any alert is generated. This is a governance question this library's security/compliance
   scope cannot itself resolve — it needs HR and Legal sign-off, not just a security team's
   approval.
   - **Resolution:** Added an explicit governance note to `README.md` §2 (recommending HR/Legal
     review before enabling this trigger path) and a corresponding standing operational item to
     §8, plus a cross-reference in `design.md` §6's decision table. This is now stated as a
     deployment prerequisite this scenario's own scope cannot satisfy, not a footnote.
- **Risk reduction vs. cost, otherwise:** proportionate — no new licensing tier beyond Communication
  Compliance's own entitlement if that trigger path is used (§10), and the added operational cost
  (a second HR connector, a second app registration, two independent health checks) is
  clearly-stated rather than hidden.
- **Board-level narrative:** "we correlate behavioral/employment-stressor signals with device
  security violations, with two independent, documented trigger paths" is a clear, differentiated
  narrative from the other three siblings — `README.md` §1/§2 make the distinction explicit.
- **Compliance mapping:** correctly scoped as endpoint-integrity monitoring evidence for a
  behaviorally-flagged population, not tied to a named regulatory requirement — same honest framing
  precedent as every other Insider Risk Management scenario in this library, now supplemented with
  the governance note above rather than presenting this as compliance-clean by default.
- **Open questions are surfaced as open, not resolved by optimistic assumption** — the "editable
  existing connector" question (§6, `design.md` §2 goal 4) and the CC-message-threshold evasion
  vector (§11) are both exactly the kind of unresolved technical and coverage detail a CISO would
  want flagged before committing this template to a customer-facing assessment.
- **Would I fund this?** Yes, for a tenant that already runs at least one sibling in this template
  family and wants a genuinely different (behaviorally-triggered) detection lens — **conditioned
  explicitly on HR/Legal sign-off for the HR-connector trigger path**, which this scenario now
  states as a standing prerequisite rather than an implementation detail.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Template name, the AND/OR trigger-path prerequisite shape, the 7,500-user cap, and the
   HR-connector three-scenario data-type requirement are all directly grounded via the Microsoft
   Learn MCP tool's live fetch of `insider-risk-management-policy-templates`, `import-hr-data`, and
   `insider-risk-management-limits`** — not web-search-corroborated secondary sources, unlike some
   earlier scenarios in this family whose network access to learn.microsoft.com was proxy-blocked
   at build time. This is the strongest-available grounding path this library uses.
2. **The claim that Communication Compliance content indicators are NOT selectable scoring
   indicators for this specific template (only for its "Data leaks by risky users" cousin) is
   directly sourced from Microsoft's own indicator-category documentation, which names the four
   templates that DO support them and does not include this one.** Correctly distinguishes the two
   "risky users" templates rather than treating this scenario as a smaller copy of its cousin —
   `design.md` §2 goal 3 states the distinction explicitly with its source.
3. **No fabricated Communication Compliance authoring API.** This build found and quoted Microsoft's
   own explicit statement that PowerShell isn't supported for Communication Compliance policy
   management — this scenario correctly treats that integration option as portal-only throughout,
   consistent with `docs/automation-surface.md` §6's broader finding for this product family.
4. **The documented Microsoft-side inconsistency in the Performance improvement plan CSV column
   reference (worked example vs. column-description table) is disclosed accurately and precisely**
   — quoting both conflicting sections rather than silently picking one, and correctly noting
   Microsoft's own "these are examples, not a fixed contract" framing means the inconsistency
   doesn't block the script's actual (looser) validation model. This is exactly the kind of
   fact-checking discipline this lens exists to enforce.
5. **`Get-MgGroupTransitiveMemberAsUser`'s cmdlet syntax, required `ConsistencyLevel: eventual`
   header, and permission set are reused unmodified from the base template scenario's own,
   independently-grounded usage** — not re-derived by potentially-drifting analogy.
6. **The scenario correctly distinguishes this template's two-stage trigger-then-score model from
   the base/priority-users siblings' single-stage model, and from the departing-users sibling's own
   two-stage model** — `design.md` §5 states this explicitly with the structural comparison, rather
   than treating all four family members as interchangeable variations on one mechanism.
7. **The decision to provision a dedicated, second HR connector rather than assume an existing
   connector can be extended is disclosed as an open VERIFY, not asserted as Microsoft's confirmed
   behavior either way** — consistent with this library's grounding standard (`AGENTS.md` §4) of
   not guessing at unconfirmed portal capabilities.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a README §11 addition, 2 confirmed already covered by that same resolution) | Closed |
| 🔵 Blue Team | Fix | 3 (1 confirmed already correctly scoped in the draft under review, 2 confirmed correctly scoped/handled) | Closed |
| 🎩 CISO | Fix | 1 (closed with a README §2/§8 governance-note addition and a design.md cross-reference) | Closed |
| 🟦 Microsoft Product Owner | Pass | — | — |

The CISO finding — that this is the only scenario in this library whose trigger draws on
performance-management HR data, carrying employment-law/perception risk this library's own scope
cannot resolve — was the most consequential finding of this review round, and is now stated as a
standing deployment prerequisite (HR/Legal sign-off) rather than an implementation footnote. The
Red Team finding (the CC message-count threshold as a structural evasion vector) was resolved with
a disclosure and a compensating-control cross-reference, not a fabricated workaround. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.
