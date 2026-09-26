# Four-Lens Review - Adaptive Protection: Dynamic Risk-Based DLP Enforcement

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The original policy-tip text told the user they were flagged as an insider risk.** The
   first draft's `NotifyPolicyTipCustomText` for the Elevated-block rule read "Your account is
   currently flagged as elevated risk by Insider Risk Management." For a genuine malicious
   insider, this is a direct tip-off mid-investigation - the moment they're blocked, they know
   they've been detected and can accelerate exfiltration through an uninspected channel (a
   personal cloud upload, a USB copy, printing) before anyone has triaged the underlying alert.
   A false-positive'd innocent user is equally well served by a generic message; there is no
   legitimate operational reason to reveal the specific detection reason to the end user.
   - **Resolution:** Rewrote both rules' `NotifyPolicyTipCustomText` in
     `deploy/New-AdaptiveProtectionDlpPolicy.ps1` to generic DLP-policy language that never
     mentions insider risk, risk level, or Insider Risk Management. Documented the reasoning
     explicitly in the script's `.NOTES` block and `README.md` §6/§11 so a future maintainer
     doesn't "fix" this back to something more descriptive without understanding the tradeoff.
2. **This policy alone is trivially bypassed by switching exfiltration channel.** The original
   draft's Known Limitations mentioned Endpoint DLP/Conditional Access/Data Lifecycle Management
   were "out of scope" in a way that read as a scoping footnote rather than an active bypass
   path a red-teamer would use immediately: an Elevated-risk user blocked from emailing a file
   externally can, today, still walk out with the identical file via a direct SharePoint/OneDrive
   download, USB copy, printing, or a personal cloud-storage upload - none inspected by this
   scenario's Exchange/Teams-only policy.
   - **Resolution:** Rewrote the relevant `README.md` §11 bullet to state this plainly as a real,
     exploitable gap ("communicate this plainly to an organization: this scenario closes one exfiltration
     channel for risky users, not all of them") rather than a scoping technicality, and named the
     specific bypass techniques.
3. **Risk-level reset timing could be gamed by a patient attacker.** A red-teamer who suspects
   they've been assigned an Elevated level could simply wait out the 7-day insider risk level
   timeframe (§6) - or, more directly, wait for a case to be dismissed/resolved, which also
   resets the level per Microsoft's own documented behavior - before resuming exfiltration.
   - **Not a new finding specific to this scenario** - this is a property of Adaptive
     Protection's risk-level lifecycle itself (documented, not hidden), and the feeder IRM
     policy's own sequence/cumulative detection (already reviewed in
     `departing-employee-data-theft/reviews.md`) is the layer designed to catch a paced,
     patient attacker across multiple detection windows. No change needed in this scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass (confirmed, one clarification)**

1. **No dedicated Graph export script for this scenario's DLP alerts, unlike the departing-
   employee IRM scenario's `Export-InsiderRiskAlerts.ps1`.** Checked against this library's
   existing pattern: `scenarios/dlp/pci-teams-exfil-block` also has no dedicated alert-export
   script and relies on the DLP Alerts dashboard / Microsoft Defender portal plus
   `docs/automation-surface.md`'s general SIEM-integration guidance - this scenario is
   consistent with that established precedent, not a new gap. No change needed.
2. **Correlating a DLP block back to the specific IRM alert that caused the risk-level
   assignment is a manual step**, not an automated linkage - Microsoft does not document a
   shared correlation ID between a DLP incident report and the Insider Risk Management alert
   that produced the triggering risk level.
   - **Resolution:** `README.md` §8's incident-response runbook step 2 already instructs the
     analyst to manually cross-reference the feeder IRM policy's alert by user/timestamp; added
     an explicit note there that this is a manual correlation by design (no shared ID exists),
     so operators build the correct runbook expectation rather than assuming automated linkage
     exists and being surprised when it doesn't.
3. **Two independent propagation delays could confuse on-call triage if conflated.** Policy sync
   (~1 hour, same as every other DLP scenario in this library) and Adaptive Protection's own
   risk-level propagation delay (up to 36 hours after first enabling) are different delays with
   different causes.
   - **Confirmed already correctly separated** - the deploy script's completion message and
     `README.md` §11 state both delays distinctly with their own numbers and causes. No change
     needed; flagged here so the distinction is visibly reviewed, not assumed.

No Fail items. Detection-to-enforcement latency, alerting, and the runbook meet the bar for an
operable control, with the one documentation clarification above applied.

---

## 🎩 CISO

**Verdict: Pass (with two Fix items)**

1. **Enabling automated enforcement on top of a newly-deployed, still-tuning feeder IRM policy
   compounds two unknowns into one harder-to-diagnose outcome.** The original draft's Step 6
   said only "pilot, then enforce" without connecting enforcement-readiness to the feeder
   policy's own tuning maturity. An IRM policy in its first weeks of operation typically has a
   higher false-positive rate than one that's completed a full baseline cycle (the departing-
   employee scenario's own `README.md` §8 makes this same point about its detection thresholds)
   - automatically blocking real users on top of an untuned detector multiplies business-impact
   risk for a benefit (faster containment) the org hasn't yet earned confidence in.
   - **Resolution:** Added an explicit recommendation to `README.md` §5 Step 6 to confirm the
     feeder IRM policy has completed at least one full baseline/tuning cycle before promoting
     this scenario's DLP policy to `-Mode Enable`.
2. **Blocking a named employee's external communication based on an ML risk score carries
   employment-relations/optics risk the original draft didn't name.** Every other DLP scenario
   in this library blocks based on *content* (a credit-card number, a confidential label) -
   content-based rules are relatively easy to defend to an employee or their counsel. This
   scenario blocks based on a *person's* computed risk score, which is a materially different
   and more sensitive basis for an automated employment-affecting action, even though the
   underlying goal (contain a real threat faster) is sound.
   - **Resolution:** Added an explicit callout to `README.md` §8 recommending HR/Legal
     coordination before broad enforcement-mode rollout, framed as a residual consideration for
     CISO sign-off rather than something this scenario's code can resolve unilaterally.
- **Risk reduction vs. cost:** proportionate and, for a tenant already at E5/Suite with the
  feeder IRM policy and a DLP scenario from this library already deployed, incremental cost is
  zero (§10) - the marginal cost of this scenario is entirely the operational discipline
  described in §8, not licensing.
- **Board-level narrative:** "we automatically tighten controls on the exact users our insider
  risk program has flagged, without waiting for an analyst to act, and we ease off automatically
  once the risk is resolved" is a strong, defensible narrative - and, post-fix, an honestly
  scoped one about what channel it closes and what it doesn't (§11).
- **Would I fund this?** Yes, for an organization that already has (or is deploying via this library) a
  tuned feeder IRM policy and has read and accepted the HR/Legal coordination note above - not
  as a first Purview investment on its own.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with one Fix)**

1. **`-SharedByIRMUserRisk` is independently confirmed as the correct, current parameter for
   the "Insider risk level for Adaptive Protection is" condition** - checked against both
   `New-DlpComplianceRule` and `Set-DlpComplianceRule`'s Microsoft Learn parameter references,
   which list the identical parameter with the same three fixed GUID values on both cmdlets.
   Not fabricated, not inferred by analogy to a differently-named parameter.
2. **An earlier draft added an unverified `-ContentIsShared $true` condition alongside
   `-AccessScope NotInOrganization`**, intending to more precisely mirror the portal's compound
   "Content is shared from Microsoft 365 with people outside my organization" condition - but
   this combination was not independently confirmed against a real portal-rendered rule, and
   this library's own already-reviewed `pci-teams-exfil-block` scenario achieves the equivalent
   "shared externally" scoping using `-AccessScope` alone.
   - **Resolution:** Removed `-ContentIsShared` from both rules in
     `deploy/New-AdaptiveProtectionDlpPolicy.ps1`, reverting to the already-grounded
     `AccessScope`-only pattern. Added an explicit VERIFY note (script `.NOTES`, `README.md`
     §11) flagging that the exact condition decomposition wasn't independently confirmed, rather
     than shipping the extra parameter on an assumption.
3. **Data Lifecycle Management and Conditional Access integrations are correctly labeled
   preview.** The original draft's Non-goals section (`design.md` §7) omitted the "(preview)"
   qualifier Microsoft's own documentation attaches to both integrations
   (`insider-risk-management-adaptive-protection`, top of page: "Microsoft Purview Data
   Lifecycle Management (preview)" and "Microsoft Entra Conditional Access (preview)").
   - **Resolution:** Added "(preview)" to both mentions in `design.md` §7 and the corresponding
     architecture-diagram/Non-goals cross-references, so a reader doesn't mistake either
     integration for generally-available.
4. **Endpoint DLP's File Type / Advanced Classification Scanning prerequisite is correctly
   scoped as a reason to defer, not glossed over.** Checked against `dlp-adaptive-protection-learn`'s
   explicit "Important" callout for the Devices policy - this scenario's decision to exclude
   Endpoint DLP (`design.md` §6/§7) cites that exact prerequisite rather than an unexplained
   scope cut.
5. **Licensing citation accuracy** - checked against `docs/licensing-matrix.md` §2: the
   Adaptive Protection row ("E5/Suite, built on IRM+DLP") matches this scenario's §3/§10 claims
   exactly, with no new licensing claim introduced here that isn't already grounded there.

No remaining Fix/Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with script/doc changes, 1 confirmed already correctly mitigated by the feeder IRM policy's own detection design) | Closed |
| 🔵 Blue Team | Pass (1 clarification) | 3 (1 confirmed consistent with existing library precedent, 1 closed with a runbook clarification, 1 confirmed already correctly handled) | Closed |
| 🎩 CISO | Pass (2 Fix) | 2 closed with README additions; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass (1 Fix) | 5 (1 closed by removing an unverified condition parameter, 1 closed by adding preview labels, 3 confirmed correct/well-grounded) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
and `deploy/New-AdaptiveProtectionDlpPolicy.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.

---

## Correction addendum (2026-09-09)

Finding 3 above (Microsoft Product Owner lens) resolved this scenario's original draft by
**adding** "(preview)" labels to the Data Lifecycle Management and Conditional Access
integrations named in `design.md` §7's Non-goals. The Conditional Access half of that fix is now
stale: the sibling scenario `scenarios/adaptive-protection/conditional-access-insider-risk-block/`
independently re-grounded GA status while being built, finding no preview label on Microsoft's
current "Block access for users with insider risk" how-to guide or the Graph v1.0
`conditionalAccessConditionSet.insiderRiskLevels` resource. Both sources were re-fetched directly
during this correction pass (not just carried over from the sibling's citation) - no preview
label on either. `design.md` §2/§7 and `README.md` §11 updated in place to remove the stale
"(preview)" qualifier for Conditional Access specifically and point at the now-built sibling
scenario; the Data Lifecycle Management preview label is untouched (out of scope for this
correction - no fresh grounding pass was done on it here). This is a doc-only correction, not a
new review round: no code changed, so no new four-lens pass was run.
