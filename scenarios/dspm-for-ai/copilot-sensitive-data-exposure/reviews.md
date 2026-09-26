# Four-Lens Review — DSPM for AI Copilot Sensitive Data Exposure Protection

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **No documented pilot-group scoping.** Every worked example for the Copilot location's
   `-Locations` JSON in Microsoft's own reference scopes to the whole tenant
   (`{"Type":"Tenant","Identity":"All"}`). A group-scoped `Inclusions` entry is shown for the
   *collection*-policy cmdlets (`New-/Set-FeatureConfiguration`) but never confirmed for
   `New-DlpCompliancePolicy` on this location. As drafted, the scenario implied an organization could
   simply narrow `Inclusions` to a pilot group the same way this repo's Teams/Endpoint DLP
   scenarios scope to a specific group — that would have been fabricating an unconfirmed capability.
   - **Resolution:** Added an explicit callout to `README.md` §11 stating this is unconfirmed,
     naming `TestWithNotifications` (simulation) as the only pilot mechanism this scenario
     currently supports, and adding a `PROGRESS.md` follow-up to close the gap before a customer
     is promised group-scoped pilot rollout.
2. **Split/obfuscated SIT evasion in prompts.** Same class of bypass this repo has already
   documented for Teams/Endpoint DLP: a user who spells out an SSN as words, inserts unusual
   separators, or paraphrases rather than pasting a matching pattern defeats Rule 1's
   pattern-based SIT match. This is an inherent limitation of SIT-based detection, not fixable
   within this scenario's design space.
   - **Resolution:** Already implicit in the SIT-detection mechanism description; explicitly no
     new mitigation exists to document beyond what this repo's `pci-teams-exfil-block/README.md`
     §11 already establishes as the accepted, documented residual risk for this detection class.
     No further change needed — flagging here for visibility rather than as an unresolved gap.
3. **Rule 1 is a narrower control than its name suggests.** `RestrictWebGrounding` only blocks
   *external* web search; a user can still get Copilot to answer a sensitive-looking prompt using
   internal (already-accessible, possibly overshared) Microsoft 365 content. The initial draft's
   architecture diagram made this clear, but README §11 had not yet said it as plainly as the
   citation-leak point for Rule 0.
   - **Resolution:** README §11 already carried the "Rule 1 does not stop internal grounding"
     bullet from the first draft; confirmed no further wording change needed after adding the
     pilot-scoping finding above — both are now equally prominent in Known Limitations.
4. **Direct file upload bypasses both rules.** Files uploaded straight into a prompt are not
   scanned by DLP at all (Microsoft's own documentation states DLP inspects only the typed prompt
   text). A user could upload the very labeled/sensitive file this scenario is meant to exclude and
   have Copilot process it in full.
   - **Resolution:** Documented as an explicit, unmitigated bypass in `README.md` §11 (already
     present in the first draft) — correctly tagged as a Microsoft-documented product limitation,
     not something this scenario's DLP policy can close.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Validation script didn't confirm alerting was wired, only that the blocking actions existed.**
   A policy that correctly excludes content but silently drops the alert defeats the operational
   purpose of this control (§8's entire KPI/runbook section assumes alerts exist to review). The
   first draft of `validate/Test-CopilotSensitiveDataProtectionPolicy.ps1` checked `RestrictAccess`
   and `RestrictWebGrounding` but not `GenerateAlert` on either rule.
   - **Resolution:** Added a `GenerateAlert`-not-empty check to both rule sections of the validate
     script, mirroring the equivalent check this repo's `auto-label-confidential-sharepoint` and
     `pci-teams-exfil-block` validate scripts already perform for their own rules.
2. **Incident-response runbook present but initially generic about escalation ownership.** The
   first draft's runbook told an analyst to "escalate anomalies" and "escalate to permissions
   remediation" without naming who that escalation goes to, which — given this scenario's central
   thesis that DLP alone doesn't fix oversharing — is exactly the kind of gap that lets a security
   team quietly absorb an cross-functional problem instead of routing it correctly.
   - **Resolution:** Added the explicit ownership note to `README.md` §8 (see CISO lens below,
     same finding from a different angle — resolved once, cross-referenced from both lenses).
3. **Alert routing described but not wired.** Same accepted scoping as this repo's other DLP
   scenarios — native Purview alert surfaces are the deliverable; SIEM integration is pointed at
   `docs/automation-surface.md` §4, not built here.
   - **Resolution:** No change needed; confirmed `README.md` §8 already scopes this correctly.

No remaining Fail. Detection, logging, and the runbook (once the alert-generation check and
ownership note were added) meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Risk of the control being reported as "oversharing solved" when it is a content-level
   backstop only.** This is the most consequential risk this scenario carries: a CISO who funds
   and deploys this DLP policy alone, without also funding the SharePoint permissions remediation
   the DSPM for AI assessment surfaces, gets a real but narrow reduction in risk (labeled content
   only) while the underlying oversharing exposure — the majority of realistic Copilot exposure,
   since most organizations' oversharing backlog is on *unlabeled* content — remains completely
   unaddressed. The first draft said this clearly in §2 and §11 but didn't say who should own the
   follow-through.
   - **Resolution:** Added the ownership note to `README.md` §8 (Operations & tuning) naming
     SharePoint admin/data governance as the typical owner for permissions remediation, distinct
     from the Security/DLP team that owns this policy — so a board-level report can't quietly
     conflate "the DLP policy is deployed" with "oversharing is fixed."
- **Risk reduction vs. cost:** proportionate and honestly scoped — this is a genuine, low-cost
  addition for organizations already funding Copilot licensing, and the licensing table in §3
  correctly distinguishes the E5-only label-exclusion rule from the all-tier prompt-safeguard rule
  rather than over-claiming a single licensing bar for the whole scenario.
- **Board-level narrative:** "we stop Copilot from summarizing anything marked confidential, we
  stop sensitive prompt fragments from leaking to web search, and we're actively finding and
  reducing the oversharing exposure neither of those controls can see" is accurate and defensible —
  notably more honest than a narrative that claims Copilot oversharing risk is "solved" by DLP
  alone, which the Red Team and Product Owner lenses both confirm would be incorrect.
- **Compliance mapping:** correctly scoped to GDPR/data-minimization and pre-rollout security
  review drivers; does not over-claim a specific named regulatory requirement the way the PCI Teams
  scenario can (there is no single named "Copilot DLP" regulatory clause to cite), and the
  scenario's driver section (§2) reflects that difference honestly rather than inventing one.
- **Would I fund this?** Yes, and I would fund the permissions-remediation follow-through
  identified by the DSPM for AI assessment alongside it, per the ownership note above — funding
  this DLP policy alone would be funding the easier, smaller half of the actual problem.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Selling this scenario as "the" Copilot oversharing fix would misrepresent the product.** This
   is the single most important correctness issue a Microsoft reviewer would raise: DLP for the
   Copilot location is explicitly a content-processing control, and Microsoft's own guidance pairs
   it with DSPM for AI's oversharing assessment and permissions remediation, never as a
   standalone fix. The first draft already led with this distinction in §2, so no rewrite was
   needed — flagging it here as the primary check this review confirmed the scenario passes, not
   as an unresolved finding.
2. **Not reinventing the one-click DSPM for AI default policy without explanation.** Same pattern
   this repo already established in `pci-teams-exfil-block/design.md` §3a: `design.md` §3a here
   explains why a separately named, script-managed policy is used instead of activating DSPM for
   AI's "Protect sensitive data from Copilot processing" one-click policy — correct, current
   best-practice reasoning (versioned/auditable vs. portal-managed state that can be silently
   reset), not a deviation from product direction.
3. **Correctly declines to fabricate the "Processing prompts" full-block action.** Microsoft
   documents this as a distinct, currently-preview action with its own conditions/actions table row
   but no published PowerShell worked example. The scenario documents the portal path for it and
   explicitly excludes it from the deploy script rather than guessing a `-RestrictAccess` setting
   string — the correct call per `AGENTS.md` §4, and the kind of gap a real Microsoft reviewer would
   specifically check was not silently papered over.
4. **`-RestrictWebGrounding` parameter use is a reasonable, named-parameter-backed choice but not
   independently confirmed against a full worked Copilot-location example.** The parameter exists
   in `New-DlpComplianceRule`'s own reference and its name matches the documented "Performing Web
   Searches" action, but Microsoft's reference doesn't publish a complete script combining it with
   the Copilot location and a real SIT condition the way it does for the label-exclusion rule
   (Example 4). This is a materially weaker grounding than Rule 0's.
   - **Resolution:** Confirmed the deploy script's `.NOTES` and `design.md` §6 already flag this as
     a "confirmed parameter, name-matched to the documented action, not independently verified
     end-to-end" distinction rather than presenting both rules as equally grounded — no further
     change needed once re-checked, but recorded here so the distinction isn't lost.
5. **Licensing accuracy** — checked against `docs/licensing-matrix.md` and the Microsoft Purview
   service description table: correctly distinguishes E5-tier-only (label-exclusion rule) from
   all-tier (prompt-safeguard rule) licensing, which is easy to get wrong by quoting a single bar
   for the whole scenario. No deprecated cmdlets used.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 closed with a scoped-back claim + follow-up, 3 confirmed already correctly documented) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script gap closed, 1 ownership gap closed via the CISO-lens fix, 1 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 (ownership note added), remainder Pass | Closed |
| 🟦 Microsoft Product Owner | Fix | 5 (2 confirmed-correct checks, 1 confirmed-correct grounding discipline, 1 grounding-strength distinction recorded, 1 licensing accuracy confirmed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-CopilotSensitiveDataProtectionPolicy.ps1`, and
`validate/Test-CopilotSensitiveDataProtectionPolicy.ps1`. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.

---

## Follow-up round — 2026-09-09: correcting the third-party-AI-site non-goal cross-reference

Triggered by closing a `PROGRESS.md` backlog item (`scenarios/dspm-for-ai/
third-party-ai-site-adaptive-block/`) that this scenario's original `design.md` §7 pointed at as a
straightforward future extension of `dynamic-risk-dlp-enforcement`'s Adaptive Protection pattern.
A dedicated grounding pass found that claim overstated what's actually scriptable — see
`design.md` §7's corrected wording. Re-reviewed under all four lenses; no code, README, or deploy
script changed (only `design.md` §7's prose), so this is a narrow, targeted check rather than a
full re-review.

- **🔴 Red Team — Pass.** No control changed; the correction only removes an inaccurate forward
  pointer. Nothing new to attack.
- **🔵 Blue Team — Pass.** No detection/alerting surface changed.
- **🎩 CISO — Pass.** Prevents a future sales conversation from promising a "simple extension"
  that doesn't exist yet — a smaller, correctness-preserving change, not a new cost or risk.
- **🟦 Microsoft Product Owner — Pass.** This is exactly the kind of correction this lens exists to
  catch: the original non-goal note implied a scriptable path (via the existing Adaptive Protection
  DLP pattern) that Microsoft doesn't currently document for either constituent one-click policy.
  Leaving it uncorrected risked a future fragment fabricating `-EndpointDlpRestrictions` or
  "Inline web traffic" location parameters to match the (incorrect) claim that this was a routine
  extension. Confirmed the corrected §7 wording accurately reflects both mechanisms and cites the
  closed `PROGRESS.md` item rather than asserting a capability from memory.

No Fix/Fail. Correction confirmed sound.

---

## Follow-up round — 2026-09-10: cross-linking the new Copilot prompt full-block scenario

Triggered by building `scenarios/dspm-for-ai/copilot-prompt-full-block/`, which fulfils the
`PROGRESS.md` follow-up to re-check the "Processing prompts" full-block action this scenario's
README §5, §11 and design.md §6 originally flagged as portal-only/not-scripted. Updated those three
callouts in place to point at the new scenario instead of describing the action as permanently
unscripted. No code in this scenario's `deploy/`/`validate/` changed — only prose pointing at the new
extending scenario — so this is a narrow, targeted check.

- **🔴 Red Team — Pass.** No control in this scenario changed; the new scenario's own `reviews.md`
  carries its own Red Team findings for the newly-added rule.
- **🔵 Blue Team — Pass.** No detection/alerting surface in this scenario changed.
- **🎩 CISO — Pass.** Accurately signals to an organization that the previously-noted gap has a documented
  (if still partially unconfirmed) path forward, without overstating that the underlying
  PowerShell-grounding question is fully closed.
- **🟦 Microsoft Product Owner — Pass.** Confirmed the updated callouts do not overclaim GA status or
  a fully-confirmed mechanism for the new rule — they accurately say "built separately, gap still
  disclosed there," matching what `copilot-prompt-full-block/README.md` §5 and `design.md` §5 actually
  say.

No Fix/Fail. Correction confirmed sound.
