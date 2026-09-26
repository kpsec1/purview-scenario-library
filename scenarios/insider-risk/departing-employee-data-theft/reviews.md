# Four-Lens Review - Insider Risk Management: Departing Employee Data Theft

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Retrospective lookback is capped at 90 days before the triggering event - this scenario
   didn't say so.** The draft's Known limitations covered the *forward* lag (HR feed cadence,
   the late-firing Entra fallback) but not the *backward* boundary: risk scoring only looks
   back up to 90 days from the resignation/deletion signal. An employee who exfiltrates data
   and stays in the role for more than 90 days before resigning gets that earlier activity
   scored - never. A red-teamer with patience (wait out the lookback window before resigning)
   defeats this control entirely, and the original draft implied only a lag problem, not a hard
   ceiling.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming the 90-day (10-day for
     Exchange Online) limit as a hard, Microsoft-fixed boundary of what any resignation-
     triggered template can catch - framed correctly as a structural limit of the template,
     not a configuration gap this scenario failed to close.
2. **HR-connector app-registration credential has no stated scoping or rotation guidance.**
   The client secret used by `Send-HrTerminationRecord.ps1` is a standing bearer credential;
   the original draft told the operator to vault it but said nothing about what Graph
   permissions the app registration should (or shouldn't) hold, or how often to rotate the
   secret. A compromised, over-permissioned app registration is a materially worse outcome
   than a compromised single-purpose one.
   - **Resolution:** Added an explicit callout to `README.md` §3 (and a matching row edit in
     `design.md` §6) requiring the app registration to be single-purpose with **no Microsoft
     Graph API permissions granted** - it only needs the HR-connector ingestion webhook's own
     OAuth resource - plus a concrete rotation-cadence recommendation (every 90 days).
3. **Split/spread exfiltration across the 30-day activation window** - a red-teamer aware of
   the default thresholds could pace downloads/uploads to stay under per-day indicator
   thresholds throughout the window.
   - **Not a new finding specific to this scenario** - this is exactly the class of gap
     **cumulative exfiltration detection** and **sequence detection** (both enabled by default
     here, §6) exist to close; Microsoft's own worked examples (README.md reference 1 territory)
     show tiered severity scaling with event count precisely to catch a paced attacker. No
     change needed - already correctly configured, not a residual gap.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`Export-InsiderRiskAlerts.ps1` has no run-to-run state, and the draft didn't say what that
   means operationally.** Run on a schedule with the default 7-day `-SinceDateTime`, every run
   re-exports alerts the previous run already sent - a SIEM/ticketing integration built without
   knowing this will create duplicate tickets for the same alert.
   - **Resolution:** Added an explicit bullet to `README.md` §11 explaining the tradeoff and the
     two supported mitigations (narrow the window to just over the schedule interval and accept
     overlap, or dedupe downstream on the alert `Id`). Deliberately did **not** add cursor-file
     state to the script itself - that's scope creep for a single scenario's automation
     (`AGENTS.md` "don't add abstractions beyond what the task requires") when the standard,
     documented integration pattern (dedupe on a stable ID) already solves it at the SIEM layer.
2. **Runbook didn't explicitly branch on false positive vs. true positive before the
   escalation step**, unlike the DLP template scenario's runbook.
   - **Resolution:** Reviewed `README.md` §8's runbook step 2 (Classify) - it already asks
     "is the pattern consistent with normal end-of-employment activity... or does it suggest
     exfiltration," which is the false/true-positive branch; step 3 ("Escalate if warranted")
     is conditioned on that classification. No structural change needed, confirmed the existing
     wording already covers this rather than assuming a gap.
3. **Alert-to-Defender-portal routing claimed in the architecture diagram without an inline
   citation next to the claim itself.**
   - **Resolution:** Confirmed the claim ("Microsoft Purview Insider Risk Management alerts...
     automatic synchronization of alert updates between Microsoft Purview and the Defender
     portals") is directly grounded in reference 16 (`irm-investigate-alerts-defender`), already
     cited in `README.md` §12. No content change needed - flagged here so the grounding chain is
     visible in this review rather than assumed correct silently.

No remaining Fail. Detection, export, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **This control's efficacy is entirely dependent on HR process discipline, and that failure
   mode is invisible by default.** A technically green HR connector (successful daily imports,
   no script errors) tells you nothing about whether HR actually included *every* departing
   employee in the export. There's no independent signal this scenario can compute to catch
   "HR simply forgot someone" - that's a governance gap, not a technical one, and the original
   draft's KPI section only covered technical health (import success rate), which could read as
   a false assurance that the control is complete when it's really only confirming the pipe is
   open.
   - **Resolution:** Added an explicit callout to `README.md` §8 naming this dependency directly
     and recommending it become a line item in the org's HR/IT offboarding SOP - not something
     this scenario's automation can close on its own, and said so plainly rather than
     implying otherwise.
- **Risk reduction vs. cost:** proportionate. For a tenant already at E5 for other Purview
  controls in this library, this scenario is incremental cost only if cloud indicators for
  non-M365 destinations are enabled (PAYG) - clearly scoped in §10.
- **Board-level narrative:** "we detect and alert on data-theft patterns from employees who are
  leaving, during the window when the risk is highest and before we'd otherwise notice" is a
  clear, defensible narrative, and now (post-fix) an honest one about what it does and doesn't
  close - the 90-day lookback boundary and the HR-process dependency are documented residual
  considerations, not silent gaps.
- **Compliance mapping:** correctly scoped as supporting evidence for trade-secret "reasonable
  measures," SOC 2/ISO 27001 termination-monitoring expectations, and cyber-insurance
  underwriting questionnaires - does not overclaim a specific named regulatory mandate the way
  the PCI DLP scenario correctly can (§2 is honest that no regulation names this control by
  requirement number).
- **Would I fund this?** Yes - the cost is bounded, the risk it closes (notice-period
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
   API payload. This is the correct, honest shape for a module with no policy-authoring API -
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
   'insiderRiskManagement'` by analogy with the documented Sentinel example - but
   `serviceSource`'s enum has no Insider-Risk-Management member; the correct property
   (`detectionSource`, member `microsoftInsiderRiskManagement`) does not support server-side
   `$filter` at all. `Export-InsiderRiskAlerts.ps1` gets this right (client-side filter) and
   documents *why* in both its own `.NOTES` and `README.md` §11, rather than shipping a filter
   clause that would fail at runtime.
4. **Licensing citation accuracy** - checked against `docs/licensing-matrix.md` §2/§3: E5/Suite/
   E5-Insider-Risk-Management-add-on entitlement and the PAYG carve-out for non-M365 cloud
   indicators both match the cross-cutting matrix exactly, with no new claims introduced here
   that aren't already grounded there.
5. **Client-secret-only auth for the HR connector is appropriately hedged, not overclaimed.**
   The README and script `.NOTES` both state plainly that no certificate-credential variant of
   *this specific ingestion flow* is documented - correctly narrower than claiming certificate
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
| 🟦 Microsoft Product Owner | Pass | 5 (all confirmed correct/well-grounded, no changes required) | - |

All Fix items from this round are resolved in the current state of `README.md` and
`design.md`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.

---

## Addendum - HR-connector app-registration automation follow-up

A follow-up fragment (tracked in `PROGRESS.md`) resolved the previously-deferred item "script
the HR-connector Entra app registration" by adding `deploy/Register-HrConnectorApp.ps1` and
`validate/Test-HrConnectorAppRegistration.ps1`. Mini four-lens pass on the new capability only -
the original verdicts above are not reopened.

- 🔴 **Red Team** - does automating app-registration creation introduce a new bypass or a
  higher-value credential? No: the script grants **no** Microsoft Graph API permission to the
  app it creates (no `RequiredResourceAccess` call anywhere in it), matching the single-purpose
  scoping the original Red Team round already required. The one new consideration is the
  *operator's own* credential during the bootstrap run: the script uses interactive delegated
  `Connect-MgGraph -Scopes 'Application.ReadWrite.All'`, not a standing app-only credential - a
  deliberate choice (`design.md` §6) because a standing credential empowered to create other
  app registrations and mint their secrets would itself be a higher-value target than the
  one-time interactive session this bootstrap task needs. `-RotateSecret` adds a secret rather
  than replacing one (Microsoft Entra applications support multiple concurrent secrets by
  design); this is documented as a known limitation (README §11) rather than silently leaving a
  stale secret's exposure window open without comment. **Verdict: Pass.**
- 🔵 **Blue Team** - is the hygiene guarantee (no Graph permissions) enforceable, not just
  documented? `validate/Test-HrConnectorAppRegistration.ps1` makes it a repeatable, scriptable
  [PASS]/[FAIL] check (`RequiredResourceAccess` is empty) rather than a one-time manual glance
  at creation - so permission drift introduced later by an unrelated admin action gets caught on
  the next validation run, not only at bootstrap. The script also warns inside 30 days of secret
  expiry, giving an operational lead time the original manual-portal process had no equivalent
  reminder for. **Verdict: Pass.**
- 🎩 **CISO** - this closes a real, if narrow, gap: a manual, undocumented-by-Microsoft portal
  step is exactly the kind of one-off task that gets done inconsistently across environments (a
  wider `SignInAudience`, a permission added "just in case," no rotation cadence). Scripting it
  with an idempotent, `-WhatIf`-capable, permission-free-by-construction tool is a small but
  genuine reduction in that variance, at no incremental licensing cost - this is ordinary
  `Microsoft.Graph.Applications` tooling already available to any Entra-licensed tenant. **Would
  I fund this?** Yes, though it's a minor increment on an already-funded scenario, not a
  standalone business case.
- 🟦 **Microsoft Product Owner** - `New-MgApplication`, `New-MgServicePrincipal`,
  `Get-MgApplication`, `Add-MgApplicationPassword`, `Remove-MgApplication`, and
  `Remove-MgServicePrincipal` are all current, non-deprecated `Microsoft.Graph.Applications`
  (v1.0) cmdlets, verified against their individual Microsoft Learn reference pages rather than
  assumed by analogy - including the easy-to-get-wrong detail that `Add-MgApplicationPassword`'s
  `-ApplicationId` parameter is aliased `ObjectId` and takes the application's object ID, not its
  `AppId` (client ID); the script and its `.NOTES` call this out explicitly. The Entra-role
  guidance added to `docs/rbac-model.md` §11 (self-service app registration is on by default;
  **Application Developer** is the narrowest role that restores it if disabled, ahead of the
  broader **Cloud Application Administrator**/**Application Administrator**) is grounded against
  Microsoft's own built-in-roles reference and delegation guide, not guessed at. **Verdict: Pass.**

No Fix/Fail from this addendum.

---

## Addendum 2 - HR-connector app-secret cleanup follow-up

A follow-up fragment (tracked in `PROGRESS.md`, discovered while building the app-registration
automation above) resolved the previously-deferred item "script the superseded-secret cleanup
`-RotateSecret` leaves behind" by adding `deploy/Remove-HrConnectorAppSecret.ps1` and a matching
WARN check in `validate/Test-HrConnectorAppRegistration.ps1`. Mini four-lens pass on the new
capability only - the original verdicts above and Addendum 1 are not reopened.

- 🔴 **Red Team** - could a cleanup script itself become a footgun (e.g. deleting the only
  working secret and silently breaking the integration, or deleting it unnoticed by an attacker
  covering their tracks after planting a rogue secret)? The default `-RemoveExpired` mode can
  only ever delete credentials that are *already* dead (`EndDateTime` in the past), so it can
  never reduce the app's working-secret count - there is no default-path way to break
  `Send-HrTerminationRecord.ps1`. The narrower `-KeyId` mode, which *can* target a still-valid
  secret, refuses to proceed if doing so would leave zero unexpired secrets unless `-Force` is
  also passed - an explicit, deliberate override, not an accidental one-flag mistake. The script
  never prints or logs `SecretText` (only the non-secret `KeyId`/`DisplayName`/`EndDateTime`),
  so it doesn't introduce a new place a secret's plaintext could leak. **Verdict: Pass.**
- 🔵 **Blue Team** - is the cleanup gap now actually caught, not just fixable? Yes:
  `Test-HrConnectorAppRegistration.ps1` now WARNs whenever an already-expired secret is still
  present, so a superseded secret left behind after a `-RotateSecret` run surfaces on the very
  next validation pass instead of persisting silently until someone happens to check the
  Microsoft Entra admin center. Both new checks (this one and the pre-existing 30-day
  expiry-warning) are WARN, not FAIL, deliberately - an expired secret sitting unused is
  unwanted hygiene debt, not an active control failure, and forcing it to FAIL would make the
  validation script cry wolf on a routine, non-urgent condition. **Verdict: Pass.**
- 🎩 **CISO** - closes the residual-risk item Addendum 1's own Red Team finding named but
  deferred ("this script won't guess at that timing for you") with essentially zero incremental
  cost: same `Microsoft.Graph.Applications` module and `Application.ReadWrite.All` delegated
  scope the bootstrap script already uses, no new licensing dependency. A standing, unused client
  secret is exactly the kind of small residual exposure that accumulates unnoticed across a
  fleet of tenants an MSSP operates - scripting its removal is a proportionate, low-cost
  reduction in that exposure. **Would I fund this?** Yes, as a minor increment on an
  already-funded scenario, consistent with Addendum 1's own framing.
- 🟦 **Microsoft Product Owner** - `Remove-MgApplicationPassword` is confirmed current, non-beta
  `Microsoft.Graph.Applications` (v1.0), re-verified directly against its Microsoft Learn
  reference page during this build (not assumed from `Add-MgApplicationPassword`'s shape by
  analogy) - including that `-ApplicationId` is aliased `ObjectId` and takes the object ID, the
  same easy-to-get-wrong detail Addendum 1 already called out for the add-password cmdlet. The
  underlying `application: removePassword` REST reference documents object-ID addressing only
  (`POST /applications/{id}/removePassword`); the script's own `.NOTES` states this precisely
  rather than assuming, by analogy with `addPassword`'s documented dual `id`/`appId` addressing,
  that the same flexibility exists here. `passwordCredential.keyId`'s type (`Guid`) was
  independently confirmed against the Graph resource-type reference before being used as this
  script's `-KeyId` parameter type. **Verdict: Pass.**

No Fix/Fail from this addendum.
