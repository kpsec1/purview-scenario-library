---
part: "design"
parent: "insider-risk/data-leaks-by-risky-users"
---
## 1. Problem statement

`security-policy-violations-by-risky-users` (already built) scores a Microsoft Defender for
Endpoint security-violation signal against an HR-/Communication-Compliance-triggered population.
**Data leaks by risky users** uses the **identical bring-into-scope mechanism**, the same HR
risk-indicator data types, the same Communication Compliance trigger integration, the same AND/OR
prerequisite shape, the same 7,500-user cap, but scores a **completely different indicator
family**: built-in Office exfiltration activity (SharePoint downloads, external sharing, copying
to personal cloud storage), cumulative exfiltration detection (on by default), and optionally
Communication Compliance content indicators, generative-AI indicators, and Defender-for-Cloud-Apps
cloud indicators. Critically, it has **no Microsoft Defender for Endpoint dependency at all**, 
the one prerequisite every member of the "Security policy violations…" family shares is simply
absent here [[2]](README.md#references).

## 2. Design goals

1. **Reuse the HR uploader without modification, it was already built generic enough.**
   `security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1`'s own
   `.SYNOPSIS` explicitly names "the 'Security policy violations by risky users' (and 'Data leaks
   by risky users')" templates as its two consumers, this generalization was anticipated and
   already done. Forking a near-identical copy here would be pure duplication; this scenario calls
   the sibling's script directly with its own `-AppId`/`-JobId`.
2. **Reuse, don't duplicate, the scope-candidate resolution**, identical reasoning to the sibling:
   this template's population mechanism is a plain Entra group checked against the same 7,500 cap,
   so `../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1
   -MaxUsers 7500` is the correct call, not a new script.
3. **Reuse the PLAIN alert-export script, not the sibling's Defender-for-Endpoint-joining
   variant.** `security-policy-violations-by-departing-users/deploy/
   Export-SecurityViolationInsiderRiskAlerts.ps1` exists specifically to join an IRM alert to its
   correlated Defender for Endpoint alert by `IncidentId`, logic that has nothing to join against
   here, since this template has no Defender for Endpoint signal. Calling that script against this
   policy's alerts would silently do wasted work and imply a correlation this template's mechanism
   doesn't produce. `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, the
   plain, no-join variant, is the correct reuse target; its own code comment already documents
   this exact class of scenario as "the same grounded boundary."
4. **Get the indicator-vs-trigger distinction right for THIS template, the mirror image of the
   sibling's own goal 3.** For `Security policy violations by risky users`, Communication
   Compliance integration is documented as a trigger mechanism ONLY. For `Data leaks by risky
   users`, Microsoft's own documentation lists this template among the four ("Data theft, Data
   leaks, Data leaks by risky users, and Data leaks by priority users") that additionally support
   Communication Compliance content indicators and generative-AI indicators as **scoring**
   indicators, a materially different, richer indicator surface than its cousin, using the same
   underlying product in two independently-optional roles within one policy. `README.md` §5 Step 6
   and §6 state this distinction explicitly, sourced from Microsoft's own "Select Insider Risk
   Management policy indicators for data-based policy templates" section, not assumed by analogy
   to the cousin template.
5. **Disclose, don't guess, whether the optional cloud-indicator category applies to this specific
   template.** Microsoft's per-template description text explicitly names "cloud indicators" for
   `Data theft by departing users` and the base `Data leaks` template, but the `Data leaks by risky
   users` section's own text does not repeat that sentence, while the general cloud-indicators
   configuration article makes no template-specific restriction either way. Rather than assume
   inclusion (optimistic) or exclusion (pessimistic), `README.md` §5 Step 6/§6/§11 states this as
   an open VERIFY against the live policy-creation workflow, per `AGENTS.md` §4's grounding
   standard.
6. **Provision a third, dedicated HR connector, same rationale as the sibling's own goal 4,
   extended by one.** This scenario's HR data types are identical to the sibling's, but Microsoft's
   documented connector-Edit behavior still doesn't confirm scenario-set extension is possible on
   an existing connector. Rather than reuse either the departing-employee-data-theft sibling's
   Resignation-scoped connector or the security-policy-violations-by-risky-users sibling's own
   risk-indicator connector (which would couple this template's operational lifecycle to a
   different policy's), this scenario provisions its own third connector object, its own app
   registration (via `Register-HrConnectorApp.ps1`, reused unmodified, its own `-DisplayName`), its
   own JobId. Carries the same open VERIFY the sibling already discloses about whether a shared
   connector is actually viable.
7. **Don't fabricate a policy- or Communication-Compliance-authoring API.** Same finding as every
   other Insider Risk Management/Communication Compliance scenario in this library, no documented
   Graph/PowerShell write surface exists for either (`docs/automation-surface.md` §6).
8. **Carry forward the HR/Legal governance recommendation from the sibling rather than treat it as
   template-specific.** The employment-law/perception risk the sibling's CISO review raised
   (`security-policy-violations-by-risky-users/design.md` §6, §2's governance note) attaches to the
   HR-connector mechanism itself, not to which indicator category the mechanism feeds. Since this
   scenario uses the identical mechanism, `README.md` §2/§8 restate the same standing
   recommendation rather than silently dropping it because the indicator side of the policy
   differs.

## 3. Why this template is NOT a copy of the sibling with a different indicator checkbox

| | `security-policy-violations-by-risky-users` | This scenario |
|---|---|---|
| Trigger mechanism | HR connector risk indicators AND/OR CC integration | **Identical** |
| HR data types | Job level change, Performance review, Performance improvement plan | **Identical** |
| Max actively-scored users | 7,500 | **Identical (same number, different template, do not conflate)** |
| Scoring indicator category | Microsoft Defender for Endpoint indicators (preview) | Office indicators (built-in) + cumulative exfiltration detection (default-on) + optional CC content/generative-AI indicators + optional cloud indicators |
| Microsoft Defender for Endpoint required | **Yes**, active subscription + Purview alert-sharing feature | **No** |
| Communication Compliance's role(s) in the policy | Trigger only | Trigger, **and** optionally a distinct scoring-indicator category (§2 goal 4) |
| Correct alert-export script to reuse | `…by-departing-users/deploy/Export-SecurityViolationInsiderRiskAlerts.ps1` (MDE-joining) | `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` (plain, no MDE join) |
| Preview label | Microsoft-labeled preview (template family + indicator category) | Not labeled preview as of this writing, re-verify |

The two templates share a trigger mechanism but score fundamentally different signals through a
fundamentally different licensing/deployment dependency (Defender for Endpoint vs. none). Treating
this scenario as "the sibling with a different indicator picked" would misrepresent both the
correct alert-export script to reuse and the correct licensing conversation with a customer who may
not have Defender for Endpoint at all.

## 4. Policy architecture (what's deployed where)

| Component | Mechanism | Scriptable? |
|---|---|---|
| HR risk-indicator upload (3 schemas) | `../security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1` (reused unmodified, this scenario's own `-AppId`/`-JobId`) → dedicated HR connector webhook | **Yes**, reused, not forked (§2 goal 1) |
| HR connector creation + column mapping | Purview portal → Settings → Data connectors → Add connector → HR (preview) | No, portal-only; the app-registration bootstrap (`Register-HrConnectorApp.ps1`) is reused, the connector object itself is not scriptable |
| Communication Compliance dedicated trigger policy | Auto-created by the IRM policy-creation workflow's own trigger option | No, portal-only, no PowerShell surface exists for this product at all [[3]](README.md#references) |
| Scope-candidate resolution | `../security-policy-violations/deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1 -MaxUsers 7500` | **Yes**, reused unmodified |
| Office indicators / cumulative exfiltration detection | Purview portal → Insider Risk Management → Policies → this policy's Indicators page | No, portal-only; selection choice documented in `deploy/policy/data-leaks-risky-users-policy-manifest.json` |
| Optional Communication Compliance/generative-AI scoring indicators | Same policy Indicators page, distinct checkboxes from the trigger option | No, portal-only |
| Optional cloud indicators | Microsoft Defender portal → Settings → Cloud Apps → App Connectors (prerequisite), then the same policy Indicators page | No, portal-only; connector-level setup only, no policy-indicator-selection API |
| IRM policy (template, indicators, triggers, scope) | Purview portal → Insider Risk Management → Policies | No, portal-only; `deploy/policy/data-leaks-risky-users-policy-manifest.json` is a reference, not an API payload |
| Alert export | `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` | **Yes**, reused unmodified, plain (non-MDE-joining) variant (§2 goal 3) |

## 5. Data flow / where scoring happens

An HR risk-indicator record or a Communication Compliance risky-message signal brings a user into
this policy's scope (the trigger), structurally identical two-stage model to the sibling. Once in
scope, the policy scores that user's Office exfiltration activity (SharePoint/OneDrive downloads,
external sharing, personal cloud copy) plus cumulative exfiltration detection, and optionally
Communication Compliance content matches, generative-AI matches, and cloud-app activity, a richer,
multi-source scoring surface than the sibling's single Defender-for-Endpoint-indicator category.
`README.md` §4's diagram shows this as multiple scoring inputs converging on the policy node,
distinct from the sibling's single-indicator-category diagram.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| HR uploader script | Reuse `security-policy-violations-by-risky-users/deploy/Send-HrRiskIndicatorRecord.ps1` unmodified | Already generalized for both templates' identical HR data shape, a fork would be pure duplication (§2 goal 1) |
| HR connector object | New, third, dedicated connector | Same unresolved "can an existing connector be extended" question as the sibling; provisioning a dedicated connector is the unambiguous, documented path (§2 goal 6) |
| Scope-candidate resolution | Reuse the base template's script with `-MaxUsers 7500` | No template-specific logic beyond the cap the script already parameterizes |
| Alert-export script | Reuse the plain, non-MDE-joining `departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`, NOT the sibling's MDE-joining variant | This template has no Defender for Endpoint signal to join against; using the MDE-joining script would do wasted, misleading work |
| Indicator category | Office indicators (built-in) + cumulative exfiltration detection (default-on), with CC content/generative-AI/cloud indicators as documented optional additions | Grounded directly against Microsoft's per-template description and the "Select Insider Risk Management policy indicators for data-based policy templates" section, not assumed by analogy to the sibling |
| Whether cloud indicators apply to this specific template | Not resolved, disclosed as an explicit VERIFY | Microsoft's per-template text names this capability for two sibling templates but not this one, while the general configuration article doesn't restrict by template; guessing either way would misrepresent an open question as settled, per `AGENTS.md` §4 |
| HR/Legal governance recommendation | Carried forward from the sibling scenario, not dropped | Attaches to the shared HR-connector trigger mechanism, not to the indicator category that differs between the two scenarios |

## 7. Non-goals

- This scenario does not deploy the base `Data leaks` or `Data leaks by priority users` templates,
  nor the `Security policy violations by risky users` cousin, each is its own, separately-scoped
  (built or future) fragment.
- This scenario does not configure Defender for Endpoint, Defender for Cloud Apps connector setup
  beyond referencing it as an optional prerequisite, or attempt to script Communication Compliance
  policy creation, editing, or reviewer assignment, no documented PowerShell/Graph surface exists
  for that product at all.
- This scenario does not attempt to resolve whether an existing HR connector can be edited to add
  new scenarios, it discloses the question and takes the documented, unambiguous path (a new
  connector), identical posture to the sibling.
- This scenario does not maintain the source Entra security group used for scope resolution, 
  group lifecycle is assumed to already be handled by whatever process governs that group.
- This scenario does not attempt cross-policy alert disambiguation, the same disclosed gap every
  IRM scenario in this library carries.
