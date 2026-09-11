# Four-Lens Review — Communication Compliance: Microsoft 365 Copilot Interaction Detection

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Copilot Studio/Microsoft Foundry agent coverage is unconfirmed, and the original draft implied
   full "Copilot" coverage without flagging it.** Microsoft's general channel-detection overview
   describes a "Microsoft Copilot experiences" location as covering Copilot Studio-built Copilots,
   but this scenario's specific template locks its location to the more narrowly-worded "Microsoft
   365 Copilot and Microsoft 365 Copilot Chat." A red-teamer probing for detection gaps would
   specifically ask: does a jailbreak attempt against a custom Copilot Studio agent even reach this
   policy, or does it silently fall outside its location scope? No worked example in this build's
   grounding pass resolved this either way.
   - **Resolution:** Added a dedicated `README.md` §11 VERIFY item and a matching `design.md` §8
     Non-goals entry, cross-referencing Insider Risk Management's dedicated **Risky Agents** template
     as the purpose-built control for that surface if agent-specific risk is the actual concern —
     rather than silently asserting or silently omitting the ambiguity.
2. **English-only classifier scope is a real, exploitable gap, and deserved sharper framing than a
   passing mention.** Both Prompt Shields and Protected material are documented as English-only.
   A non-English jailbreak attempt or a request to reproduce copyrighted non-English content is
   simply invisible to this policy — a meaningfully narrower language footprint than the harassment
   scenario's multi-language trainable classifiers, worth its own bullet rather than folding into a
   generic limitations list.
   - **Resolution:** `README.md` §11 already carried this as a named, standalone bullet in the
     initial draft (not merged into a generic catch-all) — confirmed correct on review, no further
     change needed.
3. **Client-side `-PolicyNameFilter` in the audit-trail script could, in principle, blend in
   unrelated policies' events when the parsed policy name is unattributable** — and a tenant running
   both this scenario and `harassment-and-code-of-conduct` side by side is the realistic case where
   that matters. The script's own design (keep unattributed records rather than drop them) is the
   correct data-safety choice, but a Red Team lens specifically asks whether that safety choice
   creates a *different* problem: diluted, less-trustworthy per-policy KPI counts that could mask a
   genuine volume spike in this scenario's own Prompt Shields/Protected material metrics.
   - **Resolution:** Already disclosed in the deploy script's own header comment and `Get-Verbose`
     output (`Write-Verbose` on every unattributed record), and `README.md` §11's VERIFY item on the
     unconfirmed `AuditData` shape already covers the underlying cause. No silent behavior — the
     script always tells the operator when this is happening. No further change needed beyond
     confirming this is disclosed, not hidden.
4. **Storage-limit auto-deactivation (the same silent-failure mode `harassment-and-code-of-conduct`
   already flagged)** — already correctly carried over into this scenario's `README.md` §8/§11 in
   the initial draft; no further change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The default alert-aggregation threshold (4 activities / 60-minute window) is the wrong default
   for a security-sensitive Prompt Shields match, and the original draft didn't call this out at
   all.** A single jailbreak attempt would not, by itself, generate an alert under Communication
   Compliance's default alert-policy settings — the system waits for a fourth matching activity
   within the hour before the first email notification fires. For a control whose own business
   driver (`README.md` §2) is timely visibility into AI-safety abuse attempts, silently inheriting a
   threshold tuned for general content monitoring undermines the control's stated purpose.
   - **Resolution:** Added an explicit `README.md` §8 recommendation to lower this policy's
     alert-policy threshold to Microsoft's documented minimum (3 activities), with the reasoning
     spelled out (a true single-event alert isn't configurable, but 3 is materially better than the
     default 4) rather than leaving alert tuning as an unstated assumption.
2. **No severity ranking for these two classifiers was already correctly disclosed** in the original
   draft (`README.md` §8/§11) — confirmed as an operationally material fact (every alert needs
   individual triage, no "review the high-severity ones first" shortcut), not just a footnote. No
   further change needed.
3. **Incident-response runbook correctly routes Prompt Shields matches toward Security and Protected
   material matches toward Legal**, while being honest that Communication Compliance's own queue
   doesn't enforce that split automatically — already present in the original draft (`README.md` §8,
   step 1); confirmed this meets the bar for an operable, severity-aware response process given the
   no-severity-column constraint above.
4. **SIEM integration scoped correctly** — documents the native Sentinel/`OfficeActivity` path
   without overclaiming a built Sentinel workbook, matching this repo's established scope boundary;
   no change needed.

No remaining Fail. Detection, logging, the runbook, and the alert-threshold addition meet the bar
for an operable control.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **A deployed-but-unmonitored detection control is a worse legal position than no control at all,
   and the original draft didn't make this an explicit, gating consideration.** Once this policy is
   active, every Prompt Shields/Protected material match becomes a timestamped record that the
   organization was aware of a specific risky interaction. Deploying detection with no committed
   triage process turns "we didn't know" into "we knew and didn't act" if a jailbreak-related
   incident or a copyright claim is ever examined — a materially worse position from a
   discovery/audit-committee perspective.
   - **Resolution:** Added an explicit `README.md` §11 requirement to establish a defined
     Security/Responsible-AI/Legal triage SLA (e.g., same-business-day review of Prompt Shields
     matches) before enabling this policy tenant-wide — framed as a precondition of go-live, not an
     optional operational nicety, the same way `harassment-and-code-of-conduct/README.md` §3 gates
     its own deployment on an employment-counsel review.
2. **Risk reduction vs. cost is clear and proportionate.** No PAYG component for this scenario's
   scope (§10); the Communication Compliance E5-tier licensing this control needs is typically
   already satisfied by a tenant running other scenarios in this repo; the real incremental cost is
   the Microsoft 365 Copilot per-user license itself, which this control doesn't add to or reduce —
   correctly disclosed rather than conflated with this scenario's own cost.
3. **Board-level narrative is honest, not overclaiming.** "We monitor Copilot usage for jailbreak
   attempts and copyright exposure, with a role-separated Security/Legal review process" is
   defensible, and the scenario is explicit that this is detective, not preventive (§11), and that
   non-English interactions and content pasted into prompts remain outside this specific control's
   visibility. That honesty, not a claim of complete AI-safety coverage, is what a board or audit
   committee actually needs.
4. **Would I fund this?** Yes, conditional on the triage-SLA prerequisite (now explicit, per the fix
   above) actually being staffed and committed to before go-live — the same conditional-approval
   pattern this repo's CISO lens already applied to `harassment-and-code-of-conduct`.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **A genuine naming inconsistency across Microsoft's own documentation was present in the source
   material this build grounded against, and the original draft used only one name without flagging
   the other.** The policy-template catalog table names this template "Detect Microsoft 365 Copilot
   and Microsoft 365 Copilot Chat interactions"; the dedicated step-by-step configuration article
   instead instructs selecting "Detect Microsoft Copilot interactions" — the same underlying
   template, two different names, on two different (both current) Microsoft Learn pages. This
   mirrors the exact pattern `harassment-and-code-of-conduct/README.md` §11 already documents for
   its own "Harassment"/"Targeted harassment" classifier naming — shipping this scenario without the
   same disclosure would be an inconsistent editorial standard across this repo's own two
   Communication Compliance scenarios.
   - **Resolution:** Added a `README.md` §11 bullet documenting both names, which one this scenario
     standardizes on and why, and a VERIFY instruction to confirm the current portal-UI label at
     deploy time — matching the harassment scenario's treatment exactly.
2. **Correctly chose the template path over rebuilding as a custom policy.** Unlike the harassment
   scenario (which needed a custom keyword dictionary the template model doesn't support), this
   scenario's target configuration is already exactly the template's fixed defaults —
   `design.md` §2 gives the right reasoning (Microsoft owns keeping the template current; a
   hand-built custom-policy equivalent would drift from any future template update without the
   buyer noticing) rather than defaulting to "always build custom" out of habit.
3. **Correctly declined to add the content-safety (Hate/Sexual/Violence/Self-harm) classifiers to
   this policy** — those are a distinct, already-tracked-elsewhere concern (`design.md` §8), not
   something this scenario should bolt on to broaden scope without a corresponding review of its own.
4. **No-write-API claim correctly extended from the harassment scenario's precedent to explicitly
   cover template-based creation**, not just custom-policy creation — `design.md` §3 checked this
   explicitly against the same two Microsoft Learn pages rather than assuming template-based
   creation must be different because it's simpler in the portal.
5. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`'s existing
   Communication Compliance row and the PAYG-scope distinction (Microsoft 365 Copilot vs.
   Enterprise/Other AI apps); consistent, no discrepancy found.
6. **Reviewer role-group naming matches `docs/rbac-model.md`'s existing Communication Compliance
   row** exactly — no invented role name; correctly notes this scenario's different natural reviewer
   *pool* (Security/Responsible-AI/Legal) without inventing a different *role group*.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 closed with new VERIFY/limitations content, 2 already correctly covered or disclosed) | Closed |
| 🔵 Blue Team | Fix | 4 (1 closed with an alert-threshold recommendation, 3 already correctly scoped) | Closed |
| 🎩 CISO | Fix | 4 (1 closed by adding a gating triage-SLA prerequisite, 3 confirmed sound) | Closed |
| 🟦 Microsoft Product Owner | Fix | 6 (1 closed with a naming-inconsistency disclosure, 5 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-CopilotInteractionAuditTrail.ps1`, `validate/Test-CopilotInteractionAuditTrail.ps1`,
and `deploy/policy/copilot-interaction-policy-manifest.json`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9.
