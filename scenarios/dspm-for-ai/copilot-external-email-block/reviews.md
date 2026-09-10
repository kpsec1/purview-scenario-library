# Four-Lens Review — DSPM for AI Copilot External Email Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The accepted-domains list is the actual trust boundary, and this scenario doesn't own or check
   it.** This rule's entire "internal vs. external" determination rests on the tenant's Exchange
   accepted-domains configuration (`design.md` §4). A sender domain incorrectly configured as an
   *internal relay domain* — whether by misconfiguration or by an attacker who has compromised a
   partner relationship that already has accepted-domain status — is treated as trusted by this rule
   with no additional check. The first draft disclosed the dependency but didn't frame it as a
   concrete bypass path.
   - **Resolution:** `README.md` §3 already named the accepted-domains prerequisite; strengthened
     §11's limitation bullet to state explicitly that a compromised or misconfigured accepted domain
     is a full bypass of this control, not a partial degradation, and cross-referenced it from §8's
     KPI guidance (treat unexpected external-email exclusions as a hygiene check first, but also
     treat an unexpected *lack* of exclusion from a domain that should be external as a potential
     accepted-domains integrity question, not merely "the rule isn't matching"). The concrete
     compensating control this finding asked for — a scheduled check cross-referencing
     `Get-AcceptedDomain` against a reviewed allowlist in both directions — was tracked in
     `PROGRESS.md` as a follow-up rather than built inline here (out of this scenario's own scope,
     `design.md` §7) and has since been built as `scenarios/dlp/accepted-domains-hygiene-check/`.
2. **This control closes exactly one grounding vector, not the general prompt-injection problem.** A
   determined actor can still attempt prompt injection through any Copilot grounding source this
   rule doesn't touch — an external SharePoint guest share, a Teams message from a guest account, or
   content surfaced through Rule 1's still-permitted internal web search path. A buyer could read the
   use-case narrative in §2 as "Copilot is now protected from prompt injection" if this isn't stated
   plainly.
   - **Resolution:** `design.md` §7 (non-goals) and `README.md` §11 both state explicitly that this
     closes only the one documented email vector; §11's closing bullet is written specifically to
     preempt an overclaim in a sales conversation.
3. **A silently-unenforced preview feature would look identical to a working one from this
   scenario's own tooling.** If the "Block external email from being processed" capability hasn't
   reached a tenant yet, Microsoft's own documentation doesn't state whether `New-DlpComplianceRule`
   errors, silently accepts the rule with no effect, or something else — the same class of risk this
   repo has already flagged for other preview Copilot-location actions.
   - **Resolution:** Already disclosed in the deploy script's `.NOTES` and `README.md` §5 step 1 in
     the first draft (carried forward from the same pattern in `copilot-prompt-full-block`) — no
     further change needed, confirmed sufficient on review.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The first draft of `validate/Test-CopilotExternalEmailBlockRule.ps1` didn't check
   `ReportSeverityLevel` at all**, even though the deploy script exposes it as a configurable
   parameter with a deliberately non-default-obvious value (`Low`, not Microsoft's typical `Medium`)
   — an operator who reconciled a rule with `-Force -ReportSeverityLevel 'Medium'` would have no
   automated way to confirm the change took effect; the sibling scenarios' own validate scripts all
   check their equivalent severity setting.
   - **Resolution:** Added a `-ReportSeverityLevel` parameter and a matching `[WARN]`-level check
     (`design.md` §6 explains why this rule's default is intentionally lower than its three
     siblings, so a mismatch is worth flagging without hard-failing).
2. **Alert-volume framing needed to be explicit up front, not just implied.** Because every external
   email a monitored user receives is a potential match, a SOC team unfamiliar with this rule's
   intent could reasonably read a rising match count as a developing incident rather than routine,
   expected behavior — a real signal-to-noise risk distinct from anything the three sibling rules
   raise.
   - **Resolution:** `README.md` §8's KPI section and incident-response runbook were written from the
     first draft specifically to frame this rule's alerts as a baseline-monitoring signal, not a
     per-event investigation queue — confirmed sufficient on review; no further change needed.
3. **Validation script's rule lookup correctly scopes by policy, not by a bare `-Identity`.** Checked
   against the same false-positive-PASS risk the `copilot-prompt-full-block` review caught and fixed
   in its own sibling script — this scenario's first draft already used the `-Policy`-scoped lookup
   pattern from the start, so no fix was needed here; confirmed correct by inspection, not assumed by
   analogy.

No remaining Fail. Detection, logging, and the runbook meet the bar for an operable control, with
the explicit caveat (repeated in `README.md` §5/§11 and the validate script's `[WARN]`-level checks)
that neither the `FromScope` condition itself nor the `ReportSeverityLevel` reconciliation path is
independently confirmed end-to-end against a live tenant.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Licensing tier framing needed to be explicit, not buried in a citation.** This rule sits in
   Microsoft's higher "files and emails" Copilot-DLP licensing tier (E5-class), unlike its two
   prompt-facing siblings which Microsoft's own service description marks available to any tenant
   with Copilot access. The first draft cited the source but didn't foreground the practical
   implication for a buyer who already has the parent policy deployed and might assume this fourth
   rule is licensing-neutral.
   - **Resolution:** Added a dedicated licensing callout to `README.md` §3 (Prerequisites) in
     addition to §10 (Cost & licensing notes), so the tier distinction is visible before a buyer gets
     to the cost section, not only after.
- **Risk reduction vs. cost:** proportionate for a buyer already licensed at the E5-class tier this
  rule requires — the control targets a specific, named threat class (untrusted external data
  influencing an AI agent's reasoning) rather than a vague "AI safety" gesture, and costs nothing
  incremental beyond the tier the parent policy's other file/email-facing capabilities may already
  require.
- **Board-level narrative:** "Copilot only reasons over trusted internal data, plus internal email —
  external email is excluded from its context by policy, not by hope" is accurate and specific,
  distinguished honestly from the narrower claim that this closes prompt injection generally (Red
  Team finding 2, above).
- **Compliance mapping:** correctly scoped — no invented regulatory citation; §2 ties the driver to
  Microsoft's own worked prompt-injection use case rather than a named regulation this control
  doesn't actually map to a specific clause of.
- **Would I fund this?** Yes, for an organization already at the E5-class tier and already running
  the parent policy — the incremental engineering cost of one more rule is low and the threat class
  (AI agent manipulated by untrusted external content) is a legitimate, rising concern for any
  Copilot deployment. Not a reason on its own to upgrade licensing tiers if a buyer is not already
  there for other reasons.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correctly identifies and closes the fourth (and, as of this grounding pass, final) documented
   Copilot-location condition/action pair**, matching `PROGRESS.md`'s own tracking of this item as
   the direct follow-up to `copilot-prompt-full-block/design.md` §7's explicit non-goal. Confirmed by
   re-fetching the same canonical Learn page and cross-checking its supported-conditions-and-actions
   table shows exactly four rows, all four now covered across this repo's three `dspm-for-ai`
   scenarios.
   - No Fix needed — this is the primary check this review confirmed the scenario passes.
2. **Correctly distinguishes this rule's better-grounded action from its less-grounded condition,
   rather than treating the whole rule as equally uncertain.** The first draft's `design.md` §5
   already made this distinction (the action matches Microsoft's one fully-worked example verbatim;
   only the condition is a cross-location inference) — reviewed and confirmed this framing is
   accurate, not an inflated confidence claim.
3. **Terminology check: the Copilot-location page's own action text for this row ("Prevent Copilot
   from processing content", no sub-action) was reproduced verbatim in `README.md` §5/§6 rather than
   introducing a new paraphrase** — avoids repeating the "Restrict" vs. "Prevent" inconsistency this
   repo already flagged and disclosed for the `copilot-prompt-full-block` sibling, since this
   particular row of Microsoft's table only ever uses "Prevent."
4. **Does not duplicate or conflict with any existing rule.** Confirmed this scenario's rule is
   additive (a new rule on the existing policy, distinct name, structurally distinct condition type)
   rather than restating or renumbering Rules 0–2 — correct extension pattern, consistent with how
   this repo's other "extends" scenarios are structured.
5. **Licensing accuracy — the tier-split finding is new grounding, not carried over from a sibling.**
   Checked the cited Microsoft Purview service description table directly (fetched this build, not
   assumed): confirmed the "files and emails" vs. "prompts" row split and confirmed no sibling
   scenario in this repo had previously surfaced it. Correctly flagged as **not yet reflected** in
   `docs/licensing-matrix.md` rather than silently left inconsistent with that cross-cutting doc — a
   separate `PROGRESS.md` follow-up already exists for that broader backport (this scenario does not
   duplicate or preempt it, per `AGENTS.md` §6's one-fragment-per-turn discipline).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 bypass-framing strengthened, 1 scope-boundary reinforced, 1 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script gap closed, 1 confirmed already correctly framed, 1 confirmed already correct by inspection) | Closed |
| 🎩 CISO | Fix | 1 (licensing-tier visibility moved earlier in the doc), remainder Pass | Closed |
| 🟦 Microsoft Product Owner | Fix | 5 (1 confirmed-correct scope-closure check, 1 confirmed-correct grounding-confidence framing, 1 terminology-accuracy confirmation, 1 confirmed-correct extension pattern, 1 new licensing finding correctly scoped) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Add-CopilotExternalEmailBlockRule.ps1`, and
`validate/Test-CopilotExternalEmailBlockRule.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9, with one open technical caveat disclosed consistently
everywhere it matters rather than hidden or resolved by guessing: the `-FromScope` condition is
not independently confirmed for the Microsoft 365 Copilot location. The second caveat this round
raised — the "files and emails" Copilot-DLP licensing tier this rule requires not yet being
reflected in `docs/licensing-matrix.md` — is now closed: `docs/licensing-matrix.md` §2 carries the
same tier split as its own dedicated DSPM for AI rows (see `PROGRESS.md`).
