---
part: "design"
parent: "insider-risk/data-leaks"
---
## 1. Problem statement

Every "Data leaks…" family member this library has built so far requires a gate that can be
evaded by staying under it: `data-leaks-by-risky-users` and (documented, not yet built)
`data-leaks-by-priority-users` only score a user once an HR-connector employment-stressor signal
or a Communication Compliance 5-messages-in-24-hours threshold brings them into scope. Both gates
are named, explicitly, as evadable in `data-leaks-by-risky-users/README.md` §11's own Red Team
finding: a disciplined insider who never triggers either signal never enters either policy's
scope, regardless of actual exfiltration risk. That same README repeatedly cross-references the
**base `Data leaks` template, unconditional population scope, no employment-stressor or
message-count gate at all, as the compensating control for exactly this gap**, and two DLP
scenarios elsewhere in this library (`scenarios/dlp/exchange-pii-exfil-block-part2-obfuscation-
mitigation/`, `scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/`) already deploy
narrow, single-purpose instances of this exact template as feeder policies for their own Adaptive
Protection rules. This fragment is the base template's own standalone scenario: general
population, general trigger, not tied to any one parent DLP policy or narrowly-scoped population.

## 2. Design goals

1. **No employment-stressor or message-count gate.** This is the entire reason this fragment
   exists. Population scope is an ordinary Entra group (or groups) the operator chooses, no HR
   connector, no Communication Compliance trigger integration, no priority-user-group
   requirement. `README.md` §2 states this explicitly as the scenario's defining trait relative to
   every other Insider Risk Management scenario in this library.
2. **Use the template's own two documented triggering-event mechanisms, don't invent a third.**
   Microsoft's Insider Risk Management policy workflow for this template offers exactly two
   triggering-event choices, "User matches a data loss prevention (DLP) policy" and "User
   performs an exfiltration activity", sourced from the same "Triggers for this policy" reference
   page already grounded in this library's `exchange-pii-exfil-block-part2-obfuscation-mitigation/
   design.md` §6a for the identical template [[3]](README.md#references). This fragment documents
   and worked-examples the DLP-policy trigger as the primary path (§3), because it is the specific
   shape `PROGRESS.md`'s own backlog item scoped this fragment around, and documents the
   exfiltration-activity trigger as a fully valid, Microsoft-documented alternative for a tenant
   with no qualifying DLP policy yet (§6), without building a second full worked example for it,
   to keep this one fragment scoped (§7).
3. **Ground, don't guess, the DLP-policy trigger's double-scoping requirement.** This build's
   grounding pass surfaced a specific, easy-to-miss operational fact not previously documented
   anywhere else in this library: a user's DLP-policy-triggered alert is only processed by this
   template if that user is in scope of **both** the parent DLP policy's own rule scope **and**
   the IRM policy's own "Users and groups" scope, matching neither alone is insufficient
   [[2]](README.md#references). `README.md` §5 Step 3/§6/§11 and `deploy/
   Test-DlpPolicyIrmTriggerReadiness.ps1` treat this as a first-class configuration check, not a
   footnote.
4. **Reuse the scope-candidate and alert-export scripts already generalized for this purpose, 
   don't fork them a third time.** Identical reasoning to `data-leaks-by-risky-users/design.md`
   §2 goals 1-3: this template's population mechanism is a plain Entra group with no
   template-specific resolution logic, and this template has no Microsoft Defender for Endpoint
   signal to join against, so the plain (non-MDE-joining) alert-export script is the correct reuse
   target. Both scripts are called with this scenario's own parameters, not modified.
5. **Build the one genuinely new, missing building block: a DLP-policy trigger-readiness check.**
   Unlike the two "part2" DLP scenarios that each point this template at one specific,
   already-known parent policy, this fragment must work for **any** operator-chosen DLP policy
   (or up to 20 of them [[2]](README.md#references)). No script in this library validates whether
   a candidate DLP policy actually qualifies as a Data-leaks trigger (supported workload, High
   severity present) before the operator wires it up in the portal, `deploy/
   Test-DlpPolicyIrmTriggerReadiness.ps1` is that missing check, not a duplicate of any existing
   script.
6. **Check the parent DLP policy's `Mode`, not just its workload and severity.** This build's own
   four-lens review (`reviews.md`) surfaced a gap the first draft of `deploy/
   Test-DlpPolicyIrmTriggerReadiness.ps1` didn't check: this library's own DLP scenarios commonly
   deploy a new policy in `TestWithNotifications` mode for a first, safe rollout, and whether a
   Test-mode policy still generates the High-severity alerts this indicator consumes is
   unconfirmed in this build's WebSearch-only grounding. The script now WARNs (not FAILs, since
   test-mode policies are documented to still generate incident reports for their own purpose) on
   `Mode -ne 'Enable'`, and `README.md` §5 Step 2/§11 disclose the open question rather than
   silently assuming test-mode policies work identically to enforced ones.
7. **Ground, don't guess, the max-users cap for this specific template.** Every sibling
   Insider-Risk-Management scenario in this library states a specific, Microsoft-documented
   actively-scored-user cap (1,000 for `security-policy-violations`; 7,500 for the
   risky/priority-users family). This scenario's original build session's grounding tooling, 
   WebSearch only; direct `learn.microsoft.com` fetch returned `EGRESS_BLOCKED` from that
   session's network environment for every URL attempted, not just Microsoft's domain, could not
   retrieve the `Limits in Insider Risk Management` page's specific row for the base `Data leaks`
   template, so this cap was left as an explicit, unresolved VERIFY. A later follow-up fragment,
   from a session whose network environment did not block a direct Microsoft Learn fetch,
   confirmed the base `Data leaks` template's own row at **15,000** (distinct from `Data leaks by
   priority users` at 1,000 and `Data leaks by risky users` at 7,500), 
   <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>.
   `README.md` §3/§6/§11 and both scripts' `-MaxUsers` parameters now state/default to this
   confirmed number rather than an unresolved VERIFY.

## 3. Why the DLP-policy trigger, not the exfiltration-activity trigger, is this fragment's worked example

`PROGRESS.md`'s own backlog entry for this fragment names it explicitly as "its own DLP-policy-
as-trigger scenario (Exchange Online/SharePoint Online/OneDrive for Business High severity
alerts)", the specific shape needed as the "no trigger-count gate" compensating control the
`data-leaks-by-risky-users` sibling's own Red Team finding calls for. Both triggering-event
options are genuinely valid per Microsoft's own documentation (§2 goal 2), but the DLP-policy
trigger is:

- **The more general building block.** A DLP-policy trigger works with **any** existing,
  already-tuned Purview DLP policy the tenant has deployed for Exchange/SharePoint/OneDrive, this
  library alone already has several qualifying candidates (`exchange-pii-exfil-block`,
  and whatever SharePoint/OneDrive DLP policies a buyer already runs). The exfiltration-activity
  trigger instead depends on Microsoft's own built-in indicator thresholds, with no connection to
  content a buyer has already classified as sensitive via DLP.
- **The one this library has not yet given a general-purpose worked example for.** Both existing
  "part2" scenarios that already deploy this template do so narrowly, pointed at one specific
  named parent policy as an Adaptive Protection feeder, neither is written as a standalone,
  reusable "wire any qualifying DLP policy into a Data-leaks IRM policy" runbook. This fragment is
  that general runbook; the two "part2" scenarios' own narrower deployments remain unmodified
  (§7).

## 4. Policy architecture (what's deployed where)

| Component | Mechanism | Scriptable? |
|---|---|---|
| Candidate DLP policy readiness check (workload, High-severity rule presence, 20-policy ceiling) | `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` against one or more existing DLP policies | **Yes**, new script, this fragment's own contribution (§2 goal 5) |
| DLP-alerts indicator, pointed at the chosen DLP policy/policies | Purview portal → Insider Risk Management → Settings → Policy indicators → Built-in indicators → Data loss prevention (DLP) indicators → Add DLP policies | No, portal-only global setting, same already-documented finding every DLP-alerts-indicator scenario in this library carries |
| Scope-candidate resolution | `../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` (reused unmodified, operator supplies `-MaxUsers` per §2 goal 7) | **Yes**, reused, no template-specific logic beyond the cap |
| IRM policy (template, triggering event, indicators, scope) | Purview portal → Insider Risk Management → Policies → Create policy | No, portal-only; `deploy/policy/data-leaks-policy-manifest.json` is a reference, not an API payload |
| Alert export | `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` (reused unmodified, plain non-MDE-joining variant) | **Yes**, reused, correct choice given this template has no Defender for Endpoint signal |

## 5. Data flow / where scoping happens

A candidate DLP policy (Exchange/SharePoint/OneDrive, at least one High-severity rule) is checked
for readiness, then added as this IRM policy's triggering event via the global DLP-alerts
indicator setting. Two independent scopes must overlap for a given user's alert to actually be
processed: the DLP policy's own rule scope, and the IRM policy's own "Users and groups" scope
(§2 goal 3), this fragment's readiness script and validation checklist both treat that overlap
as something to actively confirm, not assume. Once triggered, the policy scores the user's Office
exfiltration activity (SharePoint/OneDrive downloads, external sharing, printing, personal-cloud
copy) plus cumulative exfiltration detection (default-on for this template), and optionally
Communication Compliance content indicators, generative-AI indicators, and Defender-for-Cloud-Apps
cloud indicators, the same optional-indicator surface already documented for this template family
in `data-leaks-by-risky-users/README.md` §6, confirmed applicable to the **base** template
specifically (Microsoft's per-template description text names cloud indicators for this template
by name, unlike the open question that sibling's own README carries for itself).

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Primary triggering event | "User matches a DLP policy" (up to 20 policies) | §3, the general-purpose shape `PROGRESS.md` scoped this fragment around, and the one this library has no standalone worked example for yet |
| Alternative triggering event, documented not worked-example'd | "User performs an exfiltration activity" (built-in indicators, default or custom thresholds) | Fully valid per Microsoft's own documentation (§2 goal 2); not given a second full implementation in this fragment to keep scope to one fragment (§7), a tenant that wants this path instead follows README.md §6's configuration reference directly |
| Whether both triggering events can be combined on one policy | **Still not resolved, disclosed as an open VERIFY**, now with a stronger (but still inconclusive) single-select signal | This scenario's own grounding found only "DLP policy **or** exfiltration activity" phrasing. A later sibling fragment (`data-leaks-exfiltration-activity-trigger/design.md` §2 goal 6) direct-fetched the same "Get started with Insider Risk Management" Step 6 workflow and found the two triggering-event options worded as alternative "if you select X... if you select Y..." branches, suggestive of a single-select choice, but not an explicit "cannot combine" statement. Guessing symmetry with the risky-users family's own explicit AND/OR statement would still misrepresent an unconfirmed detail as settled, per `AGENTS.md` §4 |
| New script scope | Read-only readiness CHECK, not a policy-creation script | The DLP policies this fragment wires up are pre-existing, operator-owned policies from elsewhere in the tenant (or this library), this fragment's job is to confirm they qualify, not to create or modify them |
| Parent DLP policy `Mode` check | WARN (not FAIL) if `Mode -ne 'Enable'` | §2 goal 6, found during this scenario's own four-lens review (`reviews.md`), whether a Test-mode policy still generates the alerts this indicator consumes is unconfirmed; WARN rather than FAIL because test-mode policies are documented to still generate incident reports for their own purpose, which is suggestive but not confirmed for this specific indicator |
| Max-users cap | **15,000**, both scripts now default `-MaxUsers` to this confirmed value, overridable | §2 goal 7, confirmed via a follow-up fragment's direct Microsoft Learn fetch, after the original build session's WebSearch-only grounding (blocked from a direct `learn.microsoft.com` fetch) left it as an open VERIFY |
| Population mechanism | A plain Entra group (or groups), resolved via the reused base-template scope script | Identical reasoning to every other "no priority/HR-connector requirement" template in this library |
| Alert-export script | Reuse the plain, non-MDE-joining `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` | This template has no Defender for Endpoint signal to join against, same reasoning as `data-leaks-by-risky-users/design.md` §6 |

## 7. Non-goals

- **Does not build a second full worked example for the "User performs an exfiltration activity"
  triggering event.** Documented as a valid alternative in `README.md` §6/§11, not implemented
  end-to-end, see §3/§6 above.
- **Does not modify either existing "part2" scenario's own narrower `Data leaks`-template
  deployment** (`exchange-pii-exfil-block-part2-obfuscation-mitigation`,
  `pci-teams-exfil-block-part2-obfuscation-mitigation`), both remain independent, single-purpose
  feeder policies for their own Adaptive Protection rules; this fragment is a separate,
  general-purpose policy an operator would create in addition to (not instead of) either.
- **Does not deploy `Data leaks by risky users` or `Data leaks by priority users`**, the former
  is already built as its own scenario, the latter remains open in `PROGRESS.md`.
- **Does not create or modify any DLP policy.** The candidate policies this scenario points at
  are assumed to already exist and be independently owned/tuned; `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1` only reads and reports.
- **Does not configure Adaptive Protection.** Same non-goal as every base Insider Risk Management
  scenario in this library that isn't itself an Adaptive Protection scenario, a buyer who wants
  this policy's alerts to drive DLP enforcement wires it into
  `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/` separately.
- **Does not attempt cross-policy alert disambiguation**, the same disclosed gap every Insider
  Risk Management scenario in this library carries (`AlertPolicyId` has no documented
  policy-name mapping).
