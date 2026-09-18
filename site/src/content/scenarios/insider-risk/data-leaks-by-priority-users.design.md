---
part: "design"
parent: "insider-risk/data-leaks-by-priority-users"
---
## 1. Problem statement

`data-leaks-by-priority-users` is the third and last unbuilt member of the **Data leaks…** template
family (base `Data leaks`, `…by risky users`, `…by priority users` — `PROGRESS.md`'s own backlog
entry named it explicitly as "the last unbuilt member of this template family"). It is **not** a
hybrid of its two same-family siblings in the way that description might suggest. Grounded directly
against Microsoft Learn (MCP fetch, not WebSearch-only — see §7), this template turns out to be:

- **The base `Data leaks` template's own two triggering-event options, unchanged** — "User matches a
  data loss prevention (DLP) policy" (up to 20 policies, Exchange Online/SharePoint Online/OneDrive
  for Business only) **or** "User performs an exfiltration activity" (built-in indicators, default or
  custom thresholds) [[3]](README.md#references). This is a materially different shape from the
  `security-policy-violations-by-priority-users` sibling already built in this library, whose *only*
  trigger is a fixed Microsoft Defender for Endpoint alert with no trigger-choice at all.
- **`security-policy-violations-by-priority-users`'s population mechanism, unchanged** — a **priority
  user group** (Insider Risk Management → Settings → Priority user groups), required (not optional)
  for this template [[1]](README.md#references)[[8]](README.md#references), with the same
  10,000-member group cap and the same reviewer-permission-scoping capability.
- **Its own, independently-documented 1,000-actively-scored-user cap** — numerically identical to
  `security-policy-violations-by-priority-users`'s own cap, but a **separate, per-exact-template**
  ceiling, not a shared pool with that sibling or with either same-family sibling (`Data leaks` at
  15,000, `Data leaks by risky users` at 7,500) [[6]](README.md#references). §3 below grounds this
  precisely, correcting an ambiguity a same-library sibling's own README carries for itself.
- **A distinct "Users and groups" step UI, confirmed by name** — Microsoft's own step-by-step
  configuration guide names a dedicated **"Add or edit priority user groups"** option on the
  **Users and groups** page, stated to appear "only if you choose the *Data leaks by priority
  users* template" [[4]](README.md#references) — a materially more precise, directly-fetched fact
  than the `security-policy-violations-by-priority-users` sibling's own README could confirm for
  itself (that sibling left this as an open VERIFY; see §7).
- **A separately-selectable "risk score booster" indicator**, not an automatic scoring behavior —
  "User is a member of a priority user group" is one of four checkboxes under the **Risk score
  boosters** indicator group, alongside "User is detected as a potential high impact user"
  [[5]](README.md#references). §2 goal 4 treats this as a first-class configuration step this
  library's existing priority-users sibling did not call out explicitly.

## 2. Design goals

1. **Reuse the base `Data leaks` template's own DLP-trigger-readiness script, don't fork it a
   third time.** `../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` has no
   template-specific logic beyond workload/severity/Mode/20-policy-ceiling checks that apply
   identically to this template's own "User matches a DLP policy" trigger option
   [[3]](README.md#references) — calling it unmodified is the correct reuse, not a new script.
2. **Reuse `security-policy-violations-by-priority-users`'s priority-group candidate-resolution
   script, don't fork it a second time.** `Get-PriorityUserGroupScopeCandidates.ps1` already checks
   a candidate list against **both** the 10,000-member priority-group cap and a
   `-MaxActivelyScored` template cap, defaulting to 1,000 — a default that happens to be this
   template's own, independently-confirmed cap too [[6]](README.md#references). This scenario calls
   it with both values passed explicitly (not silently relying on the default matching) so the
   citation trail is unambiguous: this template's cap was independently verified at 1,000, not
   assumed identical to the sibling's number.
3. **Reuse the plain, non-Defender-for-Endpoint-joining alert-export script.** Identical reasoning
   to the base `Data leaks` scenario (`../data-leaks/design.md` §2 goal 4): this template has no
   Microsoft Defender for Endpoint signal to join against — `../departing-employee-data-theft/
   deploy/Export-InsiderRiskAlerts.ps1` is the correct reuse target, not the
   `security-policy-violations` family's Defender-for-Endpoint-joining variant.
4. **Surface the "risk score booster" checkbox as a distinct, easy-to-miss configuration step.**
   Microsoft's own settings documentation lists "User is a member of a priority user group" as one
   of four **Risk score boosters** — a separate indicator selection from both the priority-group
   population assignment (§1) and the primary Office/DLP-alerts indicators
   [[5]](README.md#references). Nothing in the `security-policy-violations-by-priority-users`
   sibling's own README calls this out as a distinct step; that scenario's README states the
   likelihood/severity increase as though it were an automatic consequence of population membership
   alone. This scenario's `README.md` §5 Step 6 and `deploy/policy/
   data-leaks-priority-users-policy-manifest.json` treat selecting this booster as a first-class,
   independently-checkable configuration item — a buyer who assigns a priority user group but never
   selects this booster gets the population-restriction and reviewer-scoping benefits (§1) without
   the scoring boost that is this template family's other headline differentiator.
5. **Ground the DLP-alerts indicator's current supported/unsupported workload list precisely,
   including one workload this library's own base `Data leaks` scenario's WebSearch-only grounding
   did not surface.** A direct Microsoft Learn fetch during this build confirms the **High Severity
   DLP Alert indicator** does not currently evaluate alerts generated exclusively by **Endpoint
   DLP**, **Microsoft Teams**, **Microsoft 365 Copilot**, **on-premises repositories**, or **Power
   BI** [[3]](README.md#references)[[9]](README.md#references) — the Microsoft 365 Copilot exclusion
   specifically is not named in `../data-leaks/README.md`'s own workload list, grounded earlier in
   this library via WebSearch snippets rather than a direct fetch. This scenario's own README §6/§11
   uses the fuller, newly-confirmed list rather than silently copying the sibling's slightly older
   one; §7 flags this as a candidate follow-up for that sibling scenario, not something this fragment
   edits directly.
6. **Correct, don't repeat, the cross-template cap-sharing ambiguity a same-family sibling carries.**
   `security-policy-violations-by-priority-users/README.md` §10 states its own 1,000-user cap "is
   shared with the base template as well" — but Microsoft's own **Policy template limits** section
   states plainly that a template's cap "applies to users across all policies using **a given
   policy template**" [[7]](README.md#references), i.e. per exact template, not per family. §3
   below states this precisely for this scenario rather than repeating the sibling's ambiguity;
   §7 flags the sibling's own statement as a candidate correction, not something this fragment edits
   directly (fragment-discipline boundary, `AGENTS.md` §6).
7. **Don't fabricate a policy- or priority-user-group-authoring API.** Same finding as every other
   Insider Risk Management scenario in this library — creation and membership of both the IRM policy
   and the priority user group are portal-only (`docs/automation-surface.md` §6).

## 3. The two caps, precisely stated for this exact template

| Cap | Value | Scope | Source |
|---|---|---|---|
| Priority user group membership | **10,000** members | Per priority user group object (a tenant-wide setting, not per-template) | [[8]](README.md#references) |
| "Data leaks by priority users" actively-scored population | **1,000** users | Cumulative **only across policies built from this exact template** — confirmed as its own row in Microsoft's Limits table, independent of the `Data leaks` (15,000), `Data leaks by risky users` (7,500), and `Security policy violations by priority users` (1,000, numerically identical but a **separate** cap) rows | [[6]](README.md#references) |

Unlike `security-policy-violations-by-priority-users/design.md` §3, which treats the interaction
between the priority-group cap and the template cap as a fully open, unresolved question, this
scenario can state one part of that interaction precisely: **the 1,000-user template cap is not
shared with any other template**, including the numerically-identical
`Security policy violations by priority users` cap — Microsoft's **Policy template limits** section
states the limit "applies to users across all policies using a given policy template"
[[7]](README.md#references), and the Limits table lists each template as its own row with its own
number [[6]](README.md#references). What remains genuinely unconfirmed — identical to the sibling's
own open question — is what happens when a priority user group **larger than 1,000** (up to the
group's own 10,000-member ceiling) is assigned to a policy built from *this* template specifically.
No worked example or explicit statement was found for this scenario's own template, so `deploy/
Get-PriorityUserGroupScopeCandidates.ps1`'s dual-cap check, `README.md` §6/§11, and `validate/
Test-DataLeaksPriorityUsersIrmSetup.ps1`'s manual checklist all carry this forward as an open
**VERIFY (pilot tenant)**, not resolved by analogy to the sibling.

## 4. Policy architecture (what's deployed where)

| Component | Mechanism | Scriptable? |
|---|---|---|
| DLP-policy trigger readiness (workload, High-severity rule, Mode, 20-policy ceiling) | `../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` (reused unmodified) | **Yes** — reused, not forked (§2 goal 1) |
| Priority-group candidate resolution + dual-cap sizing | `../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1` (reused, called with explicit `-MaxActivelyScored 1000 -MaxGroupMembers 10000`) | **Yes** — reused, not forked (§2 goal 2) |
| Priority user group creation + bulk member upload + reviewer-permission scoping | Purview portal → Insider Risk Management → Settings → Priority user groups | No — portal-only; no documented Graph/PowerShell write surface exists for this object |
| DLP-alerts global indicator wiring | Purview portal → Insider Risk Management → Settings → Policy indicators → Built-in Indicators → DLP indicators → Add DLP policies | No — portal-only, tenant-wide setting shared with every other Data-leaks-family policy in the tenant |
| IRM policy (template, "Add or edit priority user groups" scope step, triggers, indicators, risk score booster) | Purview portal → Insider Risk Management → Policies | No — portal-only; `deploy/policy/data-leaks-priority-users-policy-manifest.json` is a reference, not an API payload |
| Alert export | `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` (reused unmodified, plain non-MDE-joining variant) | **Yes** — reused (§2 goal 3) |

## 5. Data flow / where scoring happens

A candidate DLP policy (Exchange/SharePoint/OneDrive, at least one High-severity rule) or a set of
built-in exfiltration indicators brings a priority-user-group member into scope — identical
triggering mechanism to the base `Data leaks` template, with the double-scoping requirement that
template's own design already documents (a user's DLP-triggered alert requires membership in
**both** the DLP policy's own scope **and** the IRM policy's scope) carrying over unchanged here.
Once in scope, the policy scores Office/SharePoint/Teams/email activity (per the current,
directly-fetched **Office indicators** description [[5]](README.md#references)) plus cumulative
exfiltration detection (default-on for this template family [[10]](README.md#references)), with two
priority-group-specific effects layered on top: (1) an increased likelihood/severity for the same
underlying activity, which only takes effect if the **"User is a member of a priority user group"**
risk score booster is explicitly selected on the Indicators page (§2 goal 4); and (2) reviewer
visibility for this population can be restricted to a named subset of the Insider Risk Management
team via the priority user group's own settings, independent of the IRM policy itself
[[8]](README.md#references).

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Triggering event | Reuse the base `Data leaks` template's own choice: DLP-policy match (primary, worked example) or exfiltration activity (documented alternative) | Grounded directly against Microsoft's own "Data leaks by priority users" template description and Step 6/Step 12 of the configuration guide [[1]](README.md#references)[[4]](README.md#references) — not the fixed, single-trigger shape of the `security-policy-violations-by-priority-users` sibling |
| Population mechanism | A priority user group, required (not optional) — reuse the sibling's own candidate-resolution script with explicit cap arguments | §2 goal 2; the two templates share an identical population mechanism and numerically identical cap, independently confirmed rather than assumed |
| DLP-trigger readiness script | Reuse `../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` unmodified | §2 goal 1; no template-specific logic needed beyond what already exists |
| Alert-export script | Reuse the plain, non-MDE-joining `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` | §2 goal 3; no Defender for Endpoint signal exists for this template |
| Risk score booster | Documented as a required, separately-selectable step for the scoring-boost benefit to apply | §2 goal 4 — a genuinely new finding versus the sibling's own, less precise treatment |
| Cap-sharing claim | Stated precisely as per-exact-template, not per-family | §2 goal 6, §3 — corrects an ambiguity found in a same-family sibling's own README without editing that sibling directly (fragment-discipline boundary) |
| New deploy/ script | **None** — every mechanism this template needs is already built and reusable | Writing a third near-duplicate scope script or a second DLP-readiness script would be pure duplication; this fragment's only new artifact is `validate/Test-DataLeaksPriorityUsersIrmSetup.ps1`, which combines both reused scripts' checks into one scenario-specific manual/automated checklist |

## 7. Non-goals

- Does not deploy the base `Data leaks` or `Data leaks by risky users` templates, nor either
  `Security policy violations…` template — each is its own, already-built, separately-scoped
  fragment.
- Does not create or modify any DLP policy, priority user group, or IRM policy via script — every
  authoring step is portal-only, consistent with every other Insider Risk Management scenario in
  this library.
- Does not edit `security-policy-violations-by-priority-users/README.md` or `design.md` to correct
  the cap-sharing ambiguity (§2 goal 6) or add the newly-confirmed "Add or edit priority user
  groups" step name and risk-score-booster distinction (§1) — those are candidate follow-ups for a
  separate fragment, recorded in `PROGRESS.md`, not edits bundled into this one (`AGENTS.md` §6's
  one-fragment-per-turn discipline).
- Does not edit `../data-leaks/README.md`'s DLP-workload-exclusion list to add the newly-confirmed
  Microsoft 365 Copilot exclusion (§2 goal 5) — same reasoning, tracked as a follow-up instead.
- Does not resolve the open question of what happens when a priority user group exceeds 1,000
  members for this specific template (§3) — it discloses the question, consistent with this
  library's grounding standard (`AGENTS.md` §4).
- Does not attempt cross-policy alert disambiguation — the same disclosed gap every Insider Risk
  Management scenario in this library carries (`AlertPolicyId` has no documented policy-name
  mapping).
