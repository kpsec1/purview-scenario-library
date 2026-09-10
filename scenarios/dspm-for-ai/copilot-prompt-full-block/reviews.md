# Four-Lens Review — DSPM for AI Copilot Prompt Full-Response Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The user-visible block message is a probing oracle.** Because Microsoft's documented behavior
   for this action tells the blocked user their request was refused by an organizational policy
   (unlike the parent scenario's Rule 1, which is a silent web-grounding restriction), a user can
   iterate prompts against this visible feedback signal to map exactly which SIT patterns and
   formats trigger a block, then deliberately craft a near-miss variant to evade detection. This is
   a materially faster evasion feedback loop than anything the parent scenario's two rules expose.
   - **Resolution:** Added an explicit "user-visible block message is a probing oracle" bullet to
     `README.md` §11, and tied it into the §8 incident-response runbook's existing guidance to treat
     repeated near-miss attempts as an Insider Risk Management signal rather than only a tuning
     input.
2. **Multi-turn / split-content evasion.** A user could split sensitive data across multiple
   conversational turns (e.g., partial data in one prompt, the remainder in a follow-up) so no
   single prompt's text matches the configured SIT pattern in full. This is the same class of
   pattern-based-detection limitation this repo already documents for every other SIT-based DLP rule
   (`pci-teams-exfil-block/README.md` §11, parent scenario's Rule 1) — an inherent limitation of
   per-message SIT matching, not something specific to this scenario's design that could be fixed
   here.
   - **Resolution:** No new mitigation exists to add beyond what this repo's existing SIT-detection
     limitation disclosure already covers; the residual risk is implicitly the same class already
     accepted and documented elsewhere in this repo. Flagging here for visibility, consistent with
     how the parent scenario's own `reviews.md` handled the equivalent finding for Rule 1.
3. **Same file-upload bypass as the parent scenario.** DLP does not scan uploaded file content, only
   typed prompt text — a user can upload the sensitive data as a file attachment rather than typing
   it, bypassing this rule entirely.
   - **Resolution:** Already documented in the first draft of `README.md` §6 and §11 (carried
     forward from the parent scenario's own, already-reviewed disclosure of the same Microsoft-
     documented limitation) — no further change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Validation script's `-Identity`-only rule lookup couldn't confirm the rule actually belongs to
   the target policy.** The first draft of `validate/Test-CopilotPromptFullBlockRule.ps1` fetched the
   rule with a bare `Get-DlpComplianceRule -Identity $ruleName`, which succeeds even if a
   same-named rule exists under a different policy (DLP rule names are unique tenant-wide, not
   per-policy) — a false-positive PASS if an operator ever created a same-named rule elsewhere by
   mistake.
   - **Resolution:** Changed the lookup to `Get-DlpComplianceRule -Policy $PolicyName | Where-Object
     Name -eq $ruleName`, so the existence check is scoped to the expected policy, matching the
     pattern the parent scenario's own validate script already uses for its two rules.
2. **No check distinguishing this rule from an accidental Rule-1-style deployment.** Because this
   rule's condition type (CCSI) is identical to the parent scenario's Rule 1, a copy-paste deploy
   mistake (e.g., setting `-RestrictWebGrounding $true` instead of `-RestrictAccess`) would silently
   produce a weaker control than intended, and the original validate script draft would not have
   caught it.
   - **Resolution:** Added an explicit `RestrictWebGrounding -ne $true` check to
     `validate/Test-CopilotPromptFullBlockRule.ps1`, so a rule that was accidentally deployed as a
     web-grounding-only restriction (rather than a full block) fails validation instead of passing.
3. **Runbook didn't originally name a specific escalation path for repeated near-miss attempts.**
   Same class of gap the parent scenario's Blue Team lens found and the CISO lens cross-referenced.
   - **Resolution:** §8's incident-response runbook already named "Insider Risk Management or manager
     involvement" for repeated/rephrased attempts in the first draft, written specifically to close
     this gap before the review found it as a separate item — confirmed sufficient, tied explicitly
     to the new Red Team probing-oracle finding above so the two are cross-referenced rather than
     documented twice independently.

No remaining Fail. Detection, logging, and the runbook meet the bar for an operable control, with the
explicit caveat (repeated in `README.md` §5/§11 and the validate script's `[WARN]` output) that the
underlying `RestrictAccess` mechanism itself is not independently confirmed — an operability
statement about *this scenario's* logging and alerting, not a claim that the deployed rule's exact
server-side behavior is fully verified end-to-end.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Risk of driving users to ungoverned, personal AI tools if over-tuned.** This is the most
   consequential risk specific to this scenario (not shared with the parent's lighter-touch Rule 1):
   because this rule fully refuses a response rather than degrading gracefully, a poorly chosen SIT
   set that catches legitimate everyday requests creates real pressure for frustrated users to route
   around Copilot entirely using unmanaged tools — undermining the DSPM for AI oversharing-visibility
   thesis the parent scenario is built around, since an unmanaged tool has no DSPM for AI or DLP
   visibility at all. The first draft did not call this out explicitly.
   - **Resolution:** Added the "over-blocking risks pushing users to ungoverned tools" bullet to
     `README.md` §11, recommending user communications and a clear exception-request path alongside
     technical rollout, not as an afterthought.
- **Risk reduction vs. cost:** proportionate — no incremental licensing cost, and the control targets
  a narrow, buyer-chosen SIT set rather than broadly restricting Copilot usage.
- **Board-level narrative:** "for the specific categories of data we've decided are too sensitive for
  Copilot to touch under any circumstance, we don't just restrict web search — we stop the response
  entirely, and the user is told why" is accurate, and honestly distinguished from the parent
  scenario's lighter Rule 1 narrative rather than conflating the two rules' strength.
- **Compliance mapping:** correctly scoped — no invented regulatory citation; §2 ties the driver to
  Microsoft's own worked example (payment-card/regulated-identifier hygiene) rather than a named
  regulation this scenario doesn't actually map to a specific clause of.
- **Would I fund this?** Yes, conditioned on the user-communications/exception-path investment named
  above — funding the DLP rule alone without a plan for handling legitimate false positives would
  trade one risk (Copilot oversharing) for another (shadow IT), not eliminate risk.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Closes a `PROGRESS.md` follow-up correctly — re-checked the grounding, found new material, but
   did not overclaim GA status or a fully-confirmed PowerShell mechanism.** This is the check this
   fragment exists to satisfy: the original decision (parent scenario) to decline scripting this
   action was correct at that time given zero worked-example grounding; this fragment's re-check
   found a fuller Learn-page treatment (worked use case, clear actions table) but still no worked
   PowerShell example for this exact condition/action combination. The scenario correctly reflects
   both facts rather than treating "more documentation exists now" as equivalent to "the exact
   mechanism is confirmed."
   - No Fix needed — this is the primary check this review confirmed the scenario passes, not an
     unresolved finding.
2. **Terminology inconsistency in Microsoft's own source material ("Restrict" vs. "Prevent" Copilot
   from processing content) was reproduced without comment in the first draft**, which could read as
   an error in this scenario rather than a faithful quotation of Microsoft's own inconsistent
   wording across the same page's prose vs. its table.
   - **Resolution:** Added an explicit parenthetical to `README.md` §5 noting this is Microsoft's own
     documented inconsistency, not a typo introduced by this scenario.
3. **Correctly declines to fabricate the `-RestrictAccess` setting/value pair as fully confirmed.**
   `design.md` §5 lays out the reasoning for still scripting a best-effort inference rather than
   either fabricating certainty or declining outright, and every surface (`README.md`, the deploy
   script's `.NOTES`, the validate script's `[WARN]`-level check) is consistent about the caveat —
   the correct middle ground per `AGENTS.md` §4, not a deviation from this repo's no-invented-
   cmdlets discipline.
4. **Does not duplicate or conflict with the parent scenario's Rule 0/Rule 1.** Confirmed this
   scenario's rule is additive (a new rule on the existing policy, distinct name, distinct default
   SIT set) rather than restating or renumbering the parent's rules — correct extension pattern,
   consistent with how this repo's other "extends" scenarios (e.g.
   `data-estate-insights/sensitivity-label-coverage-report`) are structured.
5. **Licensing accuracy** — checked against the parent scenario's `README.md` §3/§10 and
   `docs/licensing-matrix.md`: this scenario correctly claims no incremental licensing beyond the
   parent, and correctly flags that preview-to-GA licensing terms for this specific action haven't
   been independently re-verified. No deprecated cmdlets used (`New-/Set-/Remove-/Get-
   DlpComplianceRule` are all current Security & Compliance PowerShell cmdlets).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 new finding closed with a `README.md` §11/§8 addition, 2 confirmed already correctly documented/inherent) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script lookup bug fixed, 1 validate-script gap closed, 1 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 (shadow-IT risk note added), remainder Pass | Closed |
| 🟦 Microsoft Product Owner | Fix | 5 (1 confirmed-correct grounding-discipline check, 1 terminology-clarity fix, 1 confirmed-correct no-fabrication discipline, 1 confirmed-correct extension pattern, 1 licensing accuracy confirmed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Add-CopilotPromptFullBlockRule.ps1`, and
`validate/Test-CopilotPromptFullBlockRule.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9, with the single open technical caveat (the `-RestrictAccess`
setting/value pair for this exact condition/action combination is a reasoned inference, not an
independently confirmed Microsoft worked example) disclosed consistently everywhere it matters
rather than hidden or resolved by guessing.
