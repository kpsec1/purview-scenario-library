---
part: "design"
parent: "insider-risk/data-leaks-exfiltration-activity-trigger"
---
## 1. Problem statement

[`insider-risk/data-leaks`](/scenarios/insider-risk/data-leaks/) builds the base **Data leaks** template's own primary,
general-purpose worked example — the **"User matches a data loss prevention (DLP) policy"**
triggering event. That scenario's own `design.md` §2 goal 2/§3/§7 explicitly scoped the template's
**second**, equally valid triggering-event option — **"User performs an exfiltration activity"** —
as a documented configuration reference only, not a full end-to-end implementation, "to keep this
one fragment scoped." `PROGRESS.md`'s own follow-up backlog names this gap directly: "consider
building a second worked example for the 'User performs an exfiltration activity' triggering
event... `data-leaks-by-priority-users` inherited and repeated the same scope decision rather than
resolving it." This fragment is that second worked example — the same **Data leaks** policy
template, the same population mechanism, but the trigger path a tenant with **no qualifying DLP
policy yet** actually needs.

## 2. Design goals

1. **Same template, same population mechanism, different trigger — don't re-derive what's already
   grounded.** This is not a new policy template; it is the base `Data leaks` template's other
   documented triggering-event choice. Every fact this library already grounded for the sibling
   scenario about the template itself (15,000-actively-scored-user cap, population = a plain Entra
   group with no HR/priority-user/Communication-Compliance-trigger requirement, Cumulative
   exfiltration detection default-on, the optional Communication Compliance/generative-AI/cloud
   indicator categories) applies identically here and is cross-referenced, not re-grounded from
   scratch.
2. **Ground the specific mechanics of the exfiltration-activity trigger the sibling scenario left
   as a configuration reference, not a worked example: which indicators are selectable as the
   trigger, and how default vs. custom thresholds actually work.** A direct Microsoft Learn fetch
   of "Get started with Insider Risk Management" (`insider-risk-management-configure`) Step 6,
   sub-steps 12/14/15, confirms two **separate** threshold decisions exist in the policy-creation
   workflow for this template, not one:
   - **Triggering-indicator thresholds** (sub-steps 12/14/15) — chosen when selecting which
     built-in indicator(s) bring a user **into scope** for the exfiltration-activity trigger.
     "Choose either **Use default thresholds (Recommended)** or **Use custom thresholds for the
     triggering events**." If custom is chosen, each selected trigger indicator gets its own
     threshold, using "the recommended thresholds, custom thresholds, or thresholds based on
     anomalous activities (for certain indicators) over the daily norm for users."
   - **Policy (scoring) indicator thresholds** (sub-step 17, a later page in the same workflow) —
     a **separate** default-vs-custom choice for the indicators that score an **already-triggered**
     user's risk once they're in scope. This is the same threshold model every other Office-
     indicator-scoring template in this library already documents (`data-leaks/README.md` §6), not
     specific to this trigger path.

   Conflating these two as a single decision would misstate the actual policy-creation workflow —
   `README.md` §5 Step 4/§6 and this file's §5 keep them explicitly distinct.
3. **Document the worked threshold example Microsoft itself publishes, without inventing a default
   numeric value Microsoft doesn't state.** The same "Configure policy indicators in Insider Risk
   Management" page gives a fully worked, named example for a SharePoint Online download indicator:
   three custom daily-event levels — 10+/day (low), 20+/day (medium), 30+/day (high) — each mapped
   to a resulting alert-severity tendency. Microsoft frames this explicitly as an illustration
   ("For example, suppose you decide..."), not a universal default value, and does not publish the
   actual **default** thresholds behind "Use default thresholds (Recommended)" for any indicator.
   `README.md` §6 reproduces the worked example with its sourcing intact and flags the underlying
   default numeric values as an open VERIFY (portal) rather than guessing them.
4. **Reuse the scope-candidate and alert-export scripts already generalized for this template
   family — same reasoning as the DLP-trigger sibling, don't fork a third time.** This trigger path
   changes nothing about how the policy's population is resolved or how alerts are exported; both
   scripts are called with this scenario's own parameters, unmodified.
5. **This trigger path needs no DLP-policy readiness check — the one new building block the sibling
   scenario contributed doesn't apply here, so don't force it in.** `data-leaks/deploy/
   Test-DlpPolicyIrmTriggerReadiness.ps1` validates an operator-chosen DLP policy's fitness as a
   trigger; this scenario has no DLP policy in its trigger path at all. The genuinely new
   contribution this fragment makes instead is a **policy-configuration manifest and matching
   validation checklist scoped to the exfiltration-activity trigger's own decision points**
   (which indicators are selected as the trigger, which threshold mode was chosen, and — because
   there is no API to read any of this back — a durable, versioned record of what the workflow
   button-clicks actually selected, the same role every other portal-only IRM scenario's manifest
   plays in this library).
6. **Ground, don't guess, whether the two triggering-event options can be combined on one policy —
   report the sibling's open VERIFY plus a materially stronger signal this fragment's own direct
   fetch surfaced, without overriding it.** The DLP-trigger sibling's own `design.md` §6 disclosed
   this as unresolved based on WebSearch-only grounding. This fragment's direct fetch of the same
   "Get started" page's Step 6, sub-step 12, phrases the two triggering-event choices as mutually
   exclusive workflow branches — "If you select the **User matches a data loss prevention (DLP)
   policy** triggering event option, you must select a DLP policy... If you select the **User
   performs an exfiltration activity** triggering event option, you must select one or more of the
   listed indicators" — worded as alternative "if you select X... if you select Y..." branches, not
   an explicit "select either or both" statement either sibling template's own risky-users-family
   cousin carries for its AND/OR HR-connector/Communication-Compliance prerequisite. This is
   **suggestive of a single-select choice, not confirmed as mutually exclusive by an explicit
   statement** — `README.md` §11 states this exact nuance (stronger than the sibling's own framing,
   still short of confirmed) rather than either re-asserting the sibling's weaker framing or
   claiming full confirmation. This scenario's own docs use this reading; the sibling's own
   `data-leaks/design.md` §6 and `README.md` §6/§11 are **not** edited in this fragment (a
   separate scenario's files, out of scope for a one-fragment turn) — tracked as a follow-up in
   `PROGRESS.md` instead.

## 3. Why this is its own scenario folder, not an edit to `data-leaks/`

Same precedent this library already established for the base template's own siblings
(`data-leaks-by-priority-users`, `data-leaks-by-risky-users` — each its own folder despite sharing
the "Data leaks…" template family): a materially different triggering-event mechanism, with its own
prerequisites, configuration reference, and validation checklist, warrants its own scenario rather
than growing the base scenario's README past a single coherent worked example. `data-leaks/design.md`
§7 already lists "does not build a second full worked example for the exfiltration-activity
triggering event" as an explicit non-goal — this fragment is that follow-up, not a revision of the
original.

## 4. Policy architecture (what's deployed where)

| Component | Mechanism | Scriptable? |
|---|---|---|
| Scope-candidate resolution | `../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` (reused unmodified, `-MaxUsers 15000`) | **Yes** — reused, no template-specific logic beyond the cap |
| IRM policy (template, trigger indicators + thresholds, policy indicators, scope) | Purview portal → Insider Risk Management → Policies → Create policy | No — portal-only; `deploy/policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json` is a reference, not an API payload |
| Alert export | `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` (reused unmodified, plain non-MDE-joining variant) | **Yes** — reused, correct choice given this template has no Defender for Endpoint signal |
| Trigger + scoring threshold configuration record | `deploy/policy/data-leaks-exfiltration-activity-trigger-policy-manifest.json` (new — this fragment's own contribution) | No — portal-only workflow; this manifest is the durable record of what was selected, since no read API exists |
| Trigger/threshold validation checklist | `validate/Test-DataLeaksExfiltrationActivityTriggerSetup.ps1` (new — this fragment's own contribution) | **Yes** — automated Graph-session/scope-cap check + a manual checklist scoped to this trigger's own decision points |

## 5. Data flow / where the two threshold decisions happen

A plain Entra group (or groups) is resolved via the reused scope script, identically to the DLP-
trigger sibling. In the policy-creation workflow, the operator picks **one** of the two triggering-
event branches (§2 goal 6) — this scenario's worked path is **"User performs an exfiltration
activity"** — then selects one or more built-in indicators to act as the trigger and chooses
**default or custom thresholds for those specific trigger indicators** (§2 goal 2, first bullet).
Once a user crosses that trigger threshold and enters scope, the policy separately scores their
ongoing activity against whichever **policy (scoring) indicators** were selected on a later page of
the same workflow — Office indicators, Cumulative exfiltration detection (default-on), and
optionally Communication Compliance content indicators, generative-AI indicators, or cloud
indicators — each with its **own**, independently-configured default-or-custom threshold decision
(§2 goal 2, second bullet). The trigger indicator(s) and the scoring indicator(s) may overlap (e.g.,
"downloading content from SharePoint" can be both what brings a user into scope and part of what
continues to score them afterward) or differ — Microsoft's workflow does not require them to be the
same set, and this scenario's manifest records both selections independently rather than assuming
they match.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Triggering event | "User performs an exfiltration activity" (one or more built-in indicators) | The specific gap `PROGRESS.md` scoped this fragment to close — `data-leaks/design.md` §7's own disclosed non-goal |
| Trigger indicator threshold mode | Documented as an operator choice (default/custom/anomalous-activity, where offered) — not defaulted to one option by this scenario | Microsoft doesn't publish the numeric default values behind "Use default thresholds (Recommended)" for any indicator (§2 goal 3); asserting a specific default would be guessing per `AGENTS.md` §4 |
| Worked threshold example cited | The Microsoft-published SharePoint-download 10/20/30-events/day (low/medium/high) illustration | Explicitly sourced as Microsoft's own worked example, not this scenario's invented default (§2 goal 3) |
| Scoring-indicator selection | Office indicators (primary, built-in) + Cumulative exfiltration detection (default-on) + optional Communication Compliance/generative-AI/cloud indicators | Identical to the DLP-trigger sibling — same template, same scoring surface (§2 goal 1) |
| New script scope | A validation script covering the Graph-side scope check (reused logic) plus a manual checklist for this trigger's own configuration points — no new *deploy*-time mutating or readiness-check script | This trigger path has no DLP policy to check readiness against, unlike the sibling scenario's genuinely new contribution (§2 goal 5) |
| Whether both triggering events (DLP-policy match and exfiltration activity) can be combined | **Still not confirmed — a stronger, but not conclusive, single-select signal is now disclosed** | §2 goal 6 — this fragment's own direct fetch found alternative "if you select X... if you select Y..." phrasing, stronger than the sibling's WebSearch-only framing, but not an explicit "cannot combine" statement |
| Max-users cap | **15,000**, identical to and shared cumulatively with the DLP-trigger sibling (same template) | Confirmed via the same Microsoft Learn "Limits in Insider Risk Management" table the sibling scenario already cites — this is a per-template cap, not a per-trigger-event cap |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | Identical reasoning to the DLP-trigger sibling |
| Alert-export script | Reuse the plain, non-MDE-joining `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` | Same reasoning as the DLP-trigger sibling — no Defender for Endpoint signal to join against |

## 7. Non-goals

- **Does not configure the DLP-policy triggering event** — that is `data-leaks/`'s own worked
  example; a tenant that already has a qualifying DLP policy should use that scenario instead of
  (or, pending §2 goal 6's open question, possibly in addition to) this one.
- **Does not build `Data leaks by priority users` or `Data leaks by risky users`** — the latter is
  already built as its own scenario; the former remains open in `PROGRESS.md`.
- **Does not attempt to script or predict threshold values.** Real-time analytics (preview) can
  provide data-driven threshold recommendations directly in the portal workflow
  (`insider-risk-management-settings-policy-indicators#use-real-time-analytics-recommendations-to-set-thresholds`)
  — this scenario documents that this exists and its prerequisite (insider risk analytics enabled,
  policy scoped to "Include all users and groups"), but does not attempt to replicate or fabricate
  an equivalent scripted recommendation engine; no Graph/PowerShell API exists for it.
- **Does not create a custom indicator via the Insider Risk Indicators (preview) connector** — a
  separately-scoped capability (non-Microsoft-workload detections) that could be a future,
  independently-scoped fragment for either template's trigger path, not built here.
- **Does not edit `data-leaks/README.md` or `design.md`'s own disclosed VERIFY items** — this
  fragment's own stronger (but still inconclusive) evidence on the combinability question is
  recorded in this scenario's own docs and as a `PROGRESS.md` follow-up, not applied to a sibling
  scenario's files in the same turn (`AGENTS.md` §6 one-fragment-per-turn discipline).
- **Does not configure Adaptive Protection** — same non-goal as every base Insider Risk Management
  scenario in this library that isn't itself an Adaptive Protection scenario.
- **Does not attempt cross-policy alert disambiguation** — the same disclosed gap every Insider Risk
  Management scenario in this library carries (`AlertPolicyId` has no documented policy-name
  mapping).
