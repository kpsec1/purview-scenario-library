# Four-Lens Review - Adaptive Protection: Conditional Access Step-Up for Moderate/Minor Insider Risk

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The Minor policy's original "block"-shaped payload container was a bad fail-safe choice.**
   The initial draft reused the Elevated sibling's `grantControls.builtInControls = ['block']`
   shape purely as a container for a policy meant to stay permanently Report-only. But the deploy/
   remove scripts are the *only* place this scenario prevents enforcement - a manual portal edit
   changing the policy's `state` to `enabled` (outside this scenario's own automation, which is
   exactly the kind of drift `validate/` scripts in this library exist to catch) would, with the
   original `block` container, lock out **every Minor-risk user, tenant-wide, on all resources** -
   a catastrophic failure mode for a control Microsoft's own guidance says must never restrict
   Minor-risk users' productivity in the first place.
   - **Resolution:** Changed the container to `['mfa']` in `deploy/New-InsiderRiskStepUpPolicies.ps1`,
     added a hard `FAIL` check in `validate/Test-InsiderRiskStepUpPolicies.ps1` if `block` is ever
     found on this policy, and documented the fail-safe reasoning in `design.md` §6 and
     `README.md` §6/§11. (This finding is also reported under Microsoft Product Owner below, since
     it is as much a sound-engineering-judgment finding as an attacker-mindset one - recorded once
     here to avoid duplication, cross-referenced there.)
2. **The Moderate policy's scope is narrower than a reader might assume.** The original draft's
   §1/§2 described this scenario as the "Conditional-Access-side analog" of the DLP sibling's
   Moderate/Minor treatment without stating plainly that the Moderate policy only evaluates
   sign-ins to **Microsoft Admin Portals** - matching Microsoft's own documented scope exactly, but
   meaning a non-admin Moderate-risk user who never touches an admin portal may never be prompted
   at all. An organization could reasonably assume broader coverage than this control actually provides.
   - **Resolution:** Added an explicit `README.md` §11 bullet naming this scope limitation plainly
     and positioning the control as a complement to (not a substitute for) the DLP sibling's own
     Moderate/Minor audit rule, which does inspect regular content-sharing activity.
3. **Terms of Use provides no technical barrier against a determined insider.** The original draft
   did not state this baldly enough - accepting a Terms of Use prompt is a single click with no
   comprehension check and no effect on any actual data-handling capability.
   - **Resolution:** Added a `README.md` §11 bullet stating this plainly, and a CISO-lens framing
     note below so this scenario is never pitched as technically equivalent to the Elevated
     sibling's block or the DLP sibling's restrict/audit actions.
4. **An already-issued admin-portal session is not necessarily re-prompted the instant a user
   becomes Moderate-risk**, for the same CAE/token-lifetime reason already reviewed for the
   Elevated sibling. Not previously stated for this scenario specifically.
   - **Resolution:** Added a `README.md` §11 bullet naming this, with the (materially smaller,
     since nothing is denied outright) exposure window disclosed rather than assumed away.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved), otherwise Pass**

1. **No runbook guidance existed for a user who reports being unable to complete admin-portal
   sign-in.** The original draft's §8 runbook only covered the "user got prompted" path, not "user
   declined the prompt and can't get in" - a real help-desk scenario this control introduces that
   the Elevated sibling's own (block-only) runbook doesn't have an analog for.
   - **Resolution:** Added `README.md` §8 runbook step 3 (declined ToU = unmet grant control =
     standard retry-and-accept resolution, not an outage) and a `README.md` §11 VERIFY item on
     whether sign-in logs distinguish "declined" from "pending" for this specific policy.
2. **Detection/telemetry relies entirely on native Entra reporting**, consistent with - not a new
   gap versus - this library's established precedent (checked against both siblings, neither ships
   a dedicated alert-export script either). No change needed.
3. **Manual correlation between a prompt event and the triggering IRM alert** is called out
   explicitly in `README.md` §8, matching both siblings' already-reviewed runbook language.
   Confirmed present and consistent; no change needed.
4. **The Minor policy generates no operational burden at all** (never prompts, never blocks) -
   checked and confirmed `README.md` §8 states this plainly rather than implying a runbook is
   needed where none exists.

No Fail items. Detection-to-response latency and the runbook meet the bar for an operable control
once the additions above are in place.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **The original draft's board narrative implicitly overstated this control's technical strength**
   by presenting it as a natural continuation of the Elevated sibling's block policy without
   distinguishing "prevents access" from "requires acknowledgment."
   - **Resolution:** Reframed in `README.md` §11 (Red Team finding 3) - this scenario should be
     pitched to a board as a **low-cost, evidentiary/behavioral-nudge control** (documented notice
     for HR/Legal/audit purposes, mild friction) layered *underneath* the real technical controls
     (the Elevated block, the DLP sibling's restrict/audit actions), not as an equivalent-strength
     alternative to either.
- **Risk reduction vs. cost:** genuinely low incremental cost - no new license tier versus the
  Elevated sibling (§10), and the one manual step (agreement creation) is a few minutes of admin
  time, once. This is one of the cheapest controls in this library to add on top of an existing
  Elevated-sibling deployment.
- **Board-level narrative:** "we've extended our insider-risk response to a documented,
  Microsoft-recommended, graduated response across all three risk tiers, not just the highest one"
  is a defensible, complete-looking story - provided the CISO framing above (notice, not a
  barrier) is used honestly rather than oversold.
- **Would I fund this?** Yes, for an organization that has already funded (or is funding) the Elevated
  sibling - this is a small, cheap addition that completes the documented three-tier picture. Not
  worth funding in isolation without the Elevated sibling already in place, since the real
  technical risk reduction in this control family sits there.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with one Fix)**

1. **The Moderate/Minor Conditional Access pairing is independently confirmed against Microsoft's
   own "Adaptive Protection configuration guide"** - a specific, named recommendation, not this
   library inventing a plausible alternative (`design.md` §3 documents the earlier, unverified
   "require MFA/compliant device" idea that was considered and rejected in favor of this grounded
   one).
2. **`grantControls.termsOfUse` and the `MicrosoftAdminPortals` special `includeApplications`
   value are both independently confirmed** against current, non-beta Graph resource references -
   not fabricated, not inferred by analogy.
3. **The Minor policy's original `block`-shaped grant-control container was poor engineering
   judgment, independent of the Red Team framing above** - reusing a shape that happens to be
   available is not the same as reusing the *right* shape for a container that exists only to
   satisfy a schema requirement. A policy object's fields should fail safely if the one
   script-level guard (`-MinorMode`'s restricted `ValidateSet`) is ever bypassed by an out-of-band
   change.
   - **Resolution:** Same fix as Red Team finding 1 - `mfa` replaces `block` as the container
     value, with the reasoning recorded in `design.md` §6 as a design decision, not just a
     disclosed quirk.
4. **This scenario correctly avoids overclaiming Microsoft's endorsement of the Minor policy's
   specific grant-control shape** - `README.md` §6/§11 and `design.md` §6 all state plainly that
   Microsoft names no control for Minor risk, and that this scenario's choice is disclosed, not
   sourced. Checked and confirmed no wording anywhere implies otherwise.
5. **Licensing citation accuracy** - Terms of Use's own Entra ID P1 floor is correctly distinguished
   from the P2 floor this scenario's underlying Insider Risk condition still requires, without
   implying P1 alone would be sufficient to deploy this scenario. Checked against
   `docs/licensing-matrix.md` §8 (updated in this build) for consistency.
6. **Agreement-creation's delegated-only permission model is independently confirmed** against the
   `Create agreement` Graph reference's own permissions table ("Application: Not supported") -
   this is the correct, specific reason this scenario's automation has a genuine gap here, not a
   generic "portal-only" hand-wave.

No remaining Fix/Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 shared with Product Owner below, resolved once) | Closed |
| 🔵 Blue Team | Fix | 4 (1 closed with a new runbook step + VERIFY, 3 confirmed consistent with existing library precedent) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a board-narrative reframing; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass (1 Fix) | 6 (1 closed by changing the Minor policy's grant-control container from `block` to `mfa`, 5 confirmed correct/well-grounded) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-InsiderRiskStepUpPolicies.ps1`, and `validate/Test-InsiderRiskStepUpPolicies.ps1`. No
Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
