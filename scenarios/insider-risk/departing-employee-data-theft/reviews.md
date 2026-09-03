# Four-Lens Review — Insider Risk Management: Departing Employee Data Theft

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Retrospective lookback is capped at 90 days before the triggering event — this scenario
   didn't say so.** The draft's Known limitations covered the *forward* lag (HR feed cadence,
   the late-firing Entra fallback) but not the *backward* boundary: risk scoring only looks
   back up to 90 days from the resignation/deletion signal. An employee who exfiltrates data
   and stays in the role for more than 90 days before resigning gets that earlier activity
   scored — never. A red-teamer with patience (wait out the lookback window before resigning)
   defeats this control entirely, and the original draft implied only a lag problem, not a hard
   ceiling.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming the 90-day (10-day for
     Exchange Online) limit as a hard, Microsoft-fixed boundary of what any resignation-
     triggered template can catch — framed correctly as a structural limit of the template,
     not a configuration gap this scenario failed to close.
2. **HR-connector app-registration credential has no stated scoping or rotation guidance.**
   The client secret used by `Send-HrTerminationRecord.ps1` is a standing bearer credential;
   the original draft told the operator to vault it but said nothing about what Graph
   permissions the app registration should (or shouldn't) hold, or how often to rotate the
   secret. A compromised, over-permissioned app registration is a materially worse outcome
   than a compromised single-purpose one.
   - **Resolution:** Added an explicit callout to `README.md` §3 (and a matching row edit in
     `design.md` §6) requiring the app registration to be single-purpose with **no Microsoft
     Graph API permissions granted** — it only needs the HR-connector ingestion webhook's own
     OAuth resource — plus a concrete rotation-cadence recommendation (every 90 days).
3. **Split/spread exfiltration across the 30-day activation window** — a red-teamer aware of
   the default thresholds could pace downloads/uploads to stay under per-day indicator
   thresholds throughout the window.
   - **Not a new finding specific to this scenario** — this is exactly the class of gap
     **cumulative exfiltration detection** and **sequence detection** (both enabled by default
     here, §6) exist to close; Microsoft's own worked examples (README.md reference 1 territory)
     show tiered severity scaling with event count precisely to catch a paced attacker. No
     change needed — already correctly configured, not a residual gap.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`Export-InsiderRiskAlerts.ps1` has no run-to-run state, and the draft didn't say what that
   means operationally.** Run on a schedule with the default 7-day `-SinceDateTime`, every run
   re-exports alerts the previous run already sent — a SIEM/ticketing integration built without
   knowing this will create duplicate tickets for the same alert.
   - **Resolution:** Added an explicit bullet to `README.md` §11 explaining the tradeoff and the
     two supported mitigations (narrow the window to just over the schedule interval and accept
     overlap, or dedupe downstream on the alert `Id`). Deliberately did **not** add cursor-file
     state to the script itself — that's scope creep for a single scenario's automation
     (`AGENTS.md` "don't add abstractions beyond what the task requires") when the standard,
     documented integration pattern (dedupe on a stable ID) already solves it at the SIEM layer.
2. **Runbook didn't explicitly branch on false positive vs. true positive before the
   escalation step**, unlike the DLP template scenario's runbook.
   - **Resolution:** Reviewed `README.md` §8's runbook step 2 (Classify) — it already asks
     "is the pattern consistent with normal end-of-employment activity... or does it suggest
     exfiltration," which is the false/true-positive branch; step 3 ("Escalate if warranted")
     is conditioned on that classification. No structural change needed, confirmed the existing
     wording already covers this rather than assuming a gap.
3. **Alert-to-Defender-portal routing claimed in the architecture diagram without an inline
   citation next to the claim itself.**
   - **Resolution:** Confirmed the claim ("Microsoft Purview Insider Risk Management alerts...
     automatic synchronization of alert updates between Microsoft Purview and the Defender
     portals") is directly grounded in reference 16 (`irm-investigate-alerts-defender`), already
     cited in `README.md` §12. No content change needed — flagged here so the grounding chain is
     visible in this review rather than assumed correct silently.

No remaining Fail. Detection, export, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **This control's efficacy is entirely dependent on HR process discipline, and that failure
   mode is invisible by default.** A technically green HR connector (successful daily imports,
   no script errors) tells you nothing about whether HR actually included *every* departing
   employee in the export. There's no independent signal this scenario can compute to catch
   "HR simply forgot someone" — that's a governance gap, not a technical one, and the original
   draft's KPI section only covered technical health (import success rate), which could read as
   a false assurance that the control is complete when it's really only confirming the pipe is
   open.
   - **Resolution:** Added an explicit callout to `README.md` §8 naming this dependency directly
     and recommending it become a line item in the org's HR/IT offboarding SOP — not something
     this scenario's automation can close on its own, and said so plainly rather than
     implying otherwise.
- **Risk reduction vs. cost:** proportionate. For a tenant already at E5 for other Purview
  controls in this library, this scenario is incremental cost only if cloud indicators for
  non-M365 destinations are enabled (PAYG) — clearly scoped in §10.
- **Board-level narrative:** "we detect and alert on data-theft patterns from employees who are
  leaving, during the window when the risk is highest and before we'd otherwise notice" is a
  clear, defensible narrative, and now (post-fix) an honest one about what it does and doesn't
  close — the 90-day lookback boundary and the HR-process dependency are documented residual
  considerations, not silent gaps.
- **Compliance mapping:** correctly scoped as supporting evidence for trade-secret "reasonable
  measures," SOC 2/ISO 27001 termination-monitoring expectations, and cyber-insurance
  underwriting questionnaires — does not overclaim a specific named regulatory mandate the way
  the PCI DLP scenario correctly can (§2 is honest that no regulation names this control by
  requirement number).
- **Would I fund this?** Yes — the cost is bounded, the risk it closes (notice-period
  exfiltration) is real and common, and the residual-risk documentation (Red Team findings,
  the HR-dependency note) gives an honest basis for follow-on investment decisions (Adaptive
  Protection, a priority user group for high-access roles).

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **No PowerShell/Graph write API exists for Insider Risk Management policy authoring, and
   this scenario correctly doesn't pretend otherwise.** Checked against `docs/
   automation-surface.md` §6 ("IRM has limited PowerShell coverage; most policy authoring is
   portal-driven") and independently confirmed during this build: no `*-InsiderRiskPolicy`
   cmdlet family exists in either Security & Compliance PowerShell or the Microsoft Graph
   PowerShell SDK as of this writing. `design.md` §4's component table and the policy
   manifest's own `_comment` field are both explicit that the manifest is a reference, not an
   API payload. This is the correct, honest shape for a module with no policy-authoring API —
   not a shortfall of this build.
2. **Role group names, `Data Connector Admin` inclusion, and the `SecurityAlert.Read.All`
   permission are all verified against current Microsoft Learn**, not assumed: role-group-to-
   role mapping (`insider-risk-management-permissions`), and the Graph permissions reference
   entry for `SecurityAlert.Read.All` (least-privileged, application-type, matches the
   `Get-MgSecurityAlertV2` cmdlet's documented usage). No deprecated or fabricated cmdlet names
   used anywhere in `deploy/` or `validate/`.
3. **`serviceSource` vs. `detectionSource` distinction is correctly resolved, not glossed
   over.** An earlier pass through Microsoft Learn's `security-list-alerts_v2` `$filter`
   documentation could easily have led to writing `$filter=serviceSource eq
   'insiderRiskManagement'` by analogy with the documented Sentinel example — but
   `serviceSource`'s enum has no Insider-Risk-Management member; the correct property
   (`detectionSource`, member `microsoftInsiderRiskManagement`) does not support server-side
   `$filter` at all. `Export-InsiderRiskAlerts.ps1` gets this right (client-side filter) and
   documents *why* in both its own `.NOTES` and `README.md` §11, rather than shipping a filter
   clause that would fail at runtime.
4. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md` §2/§3: E5/Suite/
   E5-Insider-Risk-Management-add-on entitlement and the PAYG carve-out for non-M365 cloud
   indicators both match the cross-cutting matrix exactly, with no new claims introduced here
   that aren't already grounded there.
5. **Client-secret-only auth for the HR connector is appropriately hedged, not overclaimed.**
   The README and script `.NOTES` both state plainly that no certificate-credential variant of
   *this specific ingestion flow* is documented — correctly narrower than claiming certificate
   auth is impossible in general (the underlying `login.windows.net` v1 token endpoint likely
   supports certificate-based client assertions for other flows; this scenario doesn't assert
   that either way for the ingestion webhook specifically, since it wasn't independently
   verified during this build).

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with README/design changes, 1 confirmed already correctly mitigated by existing detection options) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with documentation, 2 confirmed already correctly scoped/cited) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a README addition; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 (all confirmed correct/well-grounded, no changes required) | — |

All Fix items from this round are resolved in the current state of `README.md` and
`design.md`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.
