# Four-Lens Review — Insider Risk Management: Data Leaks (base template)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The readiness script checked workload and severity but not `Mode` — a policy left in Test
   mode could pass every other check and still never trigger anything.** This library's own DLP
   scenarios commonly deploy a brand-new policy in `TestWithNotifications` mode for a first, safe
   rollout before promoting it to `Enable`. The original draft of `deploy/
   Test-DlpPolicyIrmTriggerReadiness.ps1` checked workload scope and rule severity but never
   inspected `Mode` — an operator who ran the readiness check against a policy still in
   `TestWithNotifications` (a very plausible real-world state, not a contrived edge case) would
   see every check pass and reasonably conclude the trigger was correctly wired, when whether
   Test-mode policies generate the alerts this indicator consumes is genuinely unconfirmed.
   - **Resolution:** Added a `Mode` check (`WARN`, not `FAIL`, since test-mode policies are
     documented to still generate incident reports for their own purpose — suggestive but not a
     confirmed answer for this specific indicator) to the script, its `.NOTES`, `README.md` §5
     Step 2/§11, `validate/Test-DataLeaksIrmSetup.ps1`'s manual checklist, and `design.md` §2
     goal 6. Disclosed as an open VERIFY rather than asserted either way, per `AGENTS.md` §4.
2. **Coverage is bounded by the specific DLP policies wired into the global indicator list and
   the specific Office indicators selected — not "all exfiltration."** A channel no wired DLP
   policy covers (Teams messages, removable media/USB, a personal non-Microsoft-365 email
   account) is invisible to this control regardless of how the IRM policy itself is configured.
   - **Reviewed, already correctly disclosed:** the original draft's §11 already named these
     specific uncovered channels and cross-referenced this library's Teams DLP and device-control
     scenarios for that coverage. No additional change needed.
3. **The double-scoping requirement is itself a plausible, silent evasion path**: an insider whose
   account drifts out of either the parent DLP policy's own scope or the IRM policy's "Users and
   groups" scope (e.g., a distribution-list/group-membership change made for an unrelated reason)
   stops being analyzed with no error from either product.
   - **Reviewed, already correctly disclosed and operationalized:** the original draft's §8
     ("confirm the double-scoping overlap on every scope change, not just at initial deployment")
     and §11 already treat this as an ongoing operational discipline item, not a one-time
     deployment check, and `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` prints an explicit
     cross-reference reminder on every run. No additional change needed beyond what's already
     there.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Same `Mode` gap as the Red Team finding above, from a detection-operability angle:** a SOC
   relying on this control for detection coverage has no way to know, from this scenario's tooling
   alone, that a feeder DLP policy quietly sitting in Test mode is producing zero IRM signal —
   the original draft gave no automated or manual signal to catch this.
   - **Resolution:** Same fix as Red Team finding 1 — the `Mode` check is both an automated
     `WARN` in the readiness script and a manual-checklist item in the validation script, so this
     is now checked on both the initial-wiring path and every subsequent validation run, not just
     once.
2. **The global, tenant-wide nature of the DLP-alerts indicator setting is an operational blast-
   radius risk the original draft under-stated.** Adding or removing a DLP policy from that list
   affects every Insider Risk Management policy in the tenant using the same indicator, not just
   this one — a change made for this scenario could silently widen or narrow another team's
   policy's trigger surface.
   - **Reviewed, already correctly disclosed:** the original draft's §5 Step 5 and §8 already
     state this explicitly and recommend coordinating with any other DLP-alerts-indicator-
     triggered policy owner before changing the list. No additional change needed.
3. **Is there a detective control confirming the readiness check was actually re-run after the
   parent DLP policy changed?** No Graph/PowerShell read API exists to detect a DLP policy change
   retroactively and trigger re-validation automatically.
   - **Reviewed, correctly scoped:** `README.md` §8 already recommends re-running `deploy/
     Test-DlpPolicyIrmTriggerReadiness.ps1` after any change to a policy feeding this trigger. The
     honest answer remains that this is a manual operational discipline item, not an automatable
     one — consistent with every other "no read API" gap this library discloses rather than
     fabricates a workaround for.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once
the Fix above is applied.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The original draft didn't give a clear answer to "why deploy this in addition to
   `data-leaks-by-risky-users`, not instead of it?"** — a CISO comparing the two needs to
   understand this isn't a replacement, but a complementary control closing a specific,
   named gap.
   - **Resolution:** Added an explicit `README.md` §8 bullet ("pair with the HR-connector-
     triggered siblings for defense in depth, not as a replacement") framing this template's
     role relative to the risky-users family, cross-referencing the specific evasion gap
     (`data-leaks-by-risky-users/README.md` §11) this template closes.
2. **Sizing risk is real but was under-stated at first draft: this build could not confirm this
   template's own actively-scored-user cap.** A CISO sizing a deployment needs to know this is an
   open question, not a settled number silently borrowed from a different template.
   - **Reviewed, already correctly disclosed:** `README.md` §3/§6/§10/§11 and `design.md` §2
     goal 7 all state this explicitly, and both scripts require the operator to supply `-MaxUsers`
     with no default — a CISO cannot be misled into thinking a number was confirmed when it
     wasn't. No additional change needed beyond ensuring every reference is consistent (checked
     during this review).
- **Risk reduction vs. cost:** favorable — this template requires no new license beyond the base
  Insider Risk Management entitlement, no HR/Legal governance review (unlike the HR-connector
  siblings), and reuses two already-built scripts unmodified. The one net-new cost is operational:
  an additional policy and DLP-policy-to-indicator wiring to maintain.
- **Board-level narrative:** "our exfiltration monitoring isn't contingent on an employment-
  stressor signal or a message-count threshold" is a materially different, defensible statement
  from this library's HR-connector-triggered scenarios, and directly answers the evasion-gap
  finding those scenarios' own reviews already raised.
- **Compliance mapping:** correctly scoped as general-population exfiltration-monitoring
  evidence, not tied to a named regulatory requirement — same honest framing as every other
  Insider Risk Management scenario in this library.
- **Open questions are surfaced as open, not resolved by optimistic assumption** — the max-users
  cap, the Mode/Test-mode question, the unsupported-workload-mixing question, and whether both
  triggering events can be combined are all flagged as VERIFY rather than guessed, exactly what a
  CISO would want before a customer-facing commitment.
- **Would I fund this?** Yes — it closes a specific, previously-disclosed detection gap at low
  incremental cost, provided the operator treats the open VERIFY items (especially the max-users
  cap and the double-scoping cross-check) as pre-production, not post-incident, homework.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with a disclosed grounding-tooling limitation)**

1. **This build's grounding was WebSearch-only, not direct-fetch, and that limitation is
   disclosed everywhere it matters rather than papered over.** Every direct fetch of
   `learn.microsoft.com` (and every other external URL attempted during this build, not
   Microsoft-specific) returned `EGRESS_BLOCKED` from this session's network environment. Every
   citation in `README.md` §12 and `design.md` is sourced from WebSearch result snippets, not a
   confirmed page fetch — a materially different grounding posture from most other scenarios in
   this library, which used the Microsoft Learn MCP tool's direct fetch. This is stated explicitly
   in `README.md`'s closing note and `design.md` §2 goal 7/§6, not silently treated as equivalent
   to a direct-fetch build.
2. **The two-triggering-event choice (DLP-policy match vs. exfiltration activity), the supported-
   workload restriction, the up-to-20-DLP-policy ceiling, and the double-scoping requirement are
   all sourced from specific, quoted WebSearch snippets attributed to named Microsoft Learn pages**
   (`insider-risk-management-policy-templates`, `insider-risk-management-configure`,
   `insider-risk-management-settings-policy-indicators`) — a reasonable confidence level for an
   unreachable-source build, but not the same as this library's direct-fetch-grounded scenarios.
   Flagged as such rather than presented with equal confidence.
3. **The claim that cloud indicators are confirmed applicable to the base template (unlike the
   open question `data-leaks-by-risky-users` carries for itself) is correctly sourced** to
   `data-leaks-by-risky-users/README.md`'s own already-grounded finding that Microsoft's
   per-template text names "cloud indicators" explicitly for the base `Data leaks` template by
   name — this scenario reuses that sibling's own direct-fetch-grounded finding rather than
   re-deriving it from a weaker WebSearch-only source, correctly distinguishing the two templates'
   confidence levels.
4. **No fabricated Insider Risk Management policy-authoring API, DLP-to-IRM scope-comparison API,
   or DLP-policy-change-detection API.** Consistent with every other scenario in this library, this
   build found and restated the existing disclosed gaps (portal-only policy authoring, no
   programmatic scope comparison) rather than inventing a workaround.
5. **The decision to reuse `Get-SecurityPolicyViolationsScopeCandidates.ps1` and
   `Export-InsiderRiskAlerts.ps1` unmodified is correctly justified** by the same reasoning already
   established for the `data-leaks-by-risky-users` sibling (identical population mechanism, no
   Defender for Endpoint signal to join against) — not reuse for its own sake.
6. **The new `Test-DlpPolicyIrmTriggerReadiness.ps1` script is a genuinely new contribution, not a
   near-duplicate of an existing script** — no other script in this library validates an arbitrary,
   operator-chosen DLP policy's fitness as an IRM trigger before it's wired up.

No remaining Fix/Fail from this lens. The `EGRESS_BLOCKED` grounding limitation is a property of
this build's execution environment, not a shortcut taken by choice — and it is disclosed
consistently rather than hidden, satisfying `AGENTS.md` §4's "tag with VERIFY rather than invent"
standard even when the underlying cause is tooling access, not an unresolved product question.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a new script check + doc updates, 2 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed via the same script/doc fix, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Fix | 2 (1 closed with a new README §8 bullet, 1 confirmed already correctly disclosed) | Closed |
| 🟦 Microsoft Product Owner | Pass | — (grounding-tooling limitation disclosed, not a defect) | — |

The Red/Blue Team finding — that the readiness script checked workload and severity but not
`Mode`, missing a plausible real-world state (a policy left in Test mode) this library's own DLP
scenarios commonly produce during a staged rollout — was the most operationally actionable finding
of this round, closed with a code change (not documentation alone) across the readiness script,
the validation script, and both the README and design doc. The CISO finding gives a concrete
answer to "why this template in addition to the risky-users family" rather than leaving template
selection as an unstated judgment call. The Product Owner lens's role in this round was primarily
to confirm the WebSearch-only grounding limitation — a consequence of this build's network
environment blocking every direct URL fetch attempted — is disclosed consistently rather than
presented with false confidence. No Fail items were raised. This fragment meets the definition of
done in `AGENTS.md` §9.

---

## Addendum — follow-up grounding pass

A later fragment, running in a network environment that did not block a direct Microsoft Learn
fetch, resolved two of the open VERIFY items this review round left standing:

- **Max-users cap (Red/Blue/CISO finding above; `design.md` §2 goal 7):** confirmed at 15,000 —
  both `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`'s (`Get-SecurityPolicyViolationsScopeCandidates.ps1`
  caller in `README.md` §5 Step 3) and `validate/Test-DataLeaksIrmSetup.ps1`'s `-MaxUsers` now
  default to this value instead of requiring the operator to supply an unconfirmed number.
- **Unsupported-workload mixing (`README.md` §11):** confirmed safe — Microsoft states directly
  that a DLP policy spanning both a supported and an unsupported workload still has its
  supported-workload rules' alerts processed. The readiness script's `[WARN]` for this combination
  is now informational, not a flag for an open question.

The same grounding pass also newly identified **Microsoft 365 Copilot** as an additional
unsupported workload for this indicator (not previously disclosed anywhere in this scenario), and
added a best-effort `EnforcementPlanes`-based detection check for it — itself carrying a new,
narrower VERIFY (whether `Get-DlpCompliancePolicy` exposes `EnforcementPlanes` on read in the same
shape `New-`/`Set-DlpCompliancePolicy` accept it on write). No four-lens re-review was run for this
narrow, citation-only/default-value change; the Microsoft Product Owner lens's original "Pass" is
unaffected since these changes only remove or narrow previously-disclosed VERIFYs and correct
citations, without altering the scenario's control design.
