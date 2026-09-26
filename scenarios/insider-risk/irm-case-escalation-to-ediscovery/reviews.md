# Four-Lens Review — Insider Risk Management Case Escalation to eDiscovery (Premium)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Case-name reuse could silently misattribute provenance.** The draft's `Confirm-
   ProvenanceBlock` treated "a provenance block already exists" as "done, skip" without checking
   *which* IRM case/user that block named. Given the naming convention is a human-typed,
   Microsoft-unenforced string (README.md §11), two different investigators (or the same one,
   months apart) reusing the same case display name for two genuinely different escalations would
   have caused the second run to silently leave the *first* escalation's provenance stamped on a
   case that actually belongs to a different user's investigation — exactly the kind of
   evidentiary-chain error §2's "reconstructible later" driver exists to prevent, and a plausible
   real-world occurrence (not just a contrived attack) given how ordinary case-naming collisions
   are.
   - **Resolution:** `deploy/Confirm-EdiscoveryEscalationLink.ps1`'s `Confirm-ProvenanceBlock` now
     compares the existing block's IRM case ID and user against the current run's definition file;
     a mismatch throws (fails closed) unless the caller passes the new `-Force` switch, and even
     then the script *appends* an additional block rather than overwriting the original, so no
     prior provenance record is ever destroyed by a later run. Documented in `design.md` §2,
     `README.md` §11, and the script's own `.PARAMETER Force` help.
2. **A malicious or careless investigator could type an arbitrary, misleading case name.** Nothing
   stops someone from naming the escalated case `IRM-9999-innocent.user` for a different user
   entirely, or a name that doesn't match any real IRM case ID, and this script would stamp
   whatever `irmCase.caseId`/`userPrincipalName` values are in the definition file onto it without
   any independent way to verify those values against the actual IRM case (design.md §4 — IRM case
   data has no read API this scenario can cross-check against).
   - **Not fixed in code — disclosed as a residual, human-process risk.** This is the same class of
     "getting the input right is a human judgment call, not something code can verify" limitation
     `scenarios/ediscovery/premium-legal-hold-and-export/README.md` §8 already accepts for its own
     custodian list. Adding a bullet to `README.md` §11 stating this plainly (rather than implying
     the provenance block is independently verified) is the right-sized response — a stronger
     control (e.g., requiring a second reviewer to countersign the definition file before running
     the script) is an organizational process decision outside this scenario's scope, not a gap
     this code should paper over with false assurance.
3. **`-ReleaseHold` on the rollback script has no independent counsel-confirmation enforcement.**
   Like the sibling scenario's own hold-release, nothing in code stops an operator from running
   `-ReleaseHold` without actually having counsel's sign-off — it's a documentation-only gate
   (`rollback.md`).
   - **Not a new finding requiring a scenario change** — this is the identical, already-accepted
     limitation the sibling scenario's own `rollback.md`/`reviews.md` carries (a legal
     determination no script can enforce). Confirmed this scenario's `rollback.md` states the gate
     with the same prominence rather than a weaker one.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No operational trigger named for actually running this scenario's scripts after an
   escalation.** The initial draft documented the script path but not *when* or *how* an operator
   would know to run it — a manual escalation with no follow-up automation trigger is exactly the
   "easy to forget" gap this scenario exists to close, and the draft didn't say so out loud.
   - **Resolution:** Added a KPI/operational guidance bullet to `README.md` §8 ("Time from
     escalation to a reconciled hold") explicitly naming the gap and pointing at the IRM case
     action toolbar's own **Automate** (Power Automate) option as the realistic way to trigger this
     script promptly rather than relying on a human remembering a manual step.
2. **The validate script's alert-resolution check had no clear severity guidance for the operator
   reading the report.** The initial draft reported alert-lookup failures the same visual weight as
   the hard case/custodian/hold checks, risking an operator treating a merged-into-an-incident alert
   (expected, benign drift) as equivalent to a missing custodian (a real gap).
   - **Resolution:** `validate/Test-EdiscoveryEscalationLink.ps1` reports alert-lookup misses as
     `WARN` with an explicit "informational only, does not affect the escalation link's own
     validity" message, distinct from the `FAIL` severity used for case/custodian/userSource/hold
     gaps — matching the PASS/WARN/FAIL severity discipline this library's other validate scripts
     already use.
3. **No guidance on what a validate-script mismatch (case found, but provenance doesn't match)
   actually means operationally.** The initial draft's validate check reported a bare `FAIL` for a
   provenance mismatch without telling the operator what to do about it.
   - **Resolution:** The `FAIL` message in `validate/Test-EdiscoveryEscalationLink.ps1` now names
     the two likely causes (stale definition file vs. a hand-edited description) and the concrete
     remediation (reconcile the definition file, then re-run the deploy script), consistent with
     the newly added `-Force`-gated mismatch handling in the deploy script.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction is real and cheap.** The control this scenario adds — closing the
  "investigator forgot to finish provisioning the escalated case" gap and creating a durable,
  in-product evidentiary trail from alert to hold — directly reduces spoliation and
  chain-of-custody risk for the highest-stakes subset of an Insider Risk Management program (cases
  serious enough to escalate), at effectively zero incremental licensing cost (§10) since it only
  automates a workflow across two already-licensed Purview capabilities.
- **Board-level narrative is straightforward:** "every insider-risk case that goes to legal review
  automatically gets a documented, timely legal hold, with a durable record of why" is a clean,
  defensible line for an audit committee or outside counsel, and the scenario's own Known
  Limitations (§11) are honest about where that story has edges (naming-convention reliance, no
  independent verification of investigator-supplied case data) rather than overselling it.
- **Adoption friction is low** — no new role, no new license, no new admin console to learn beyond
  what `departing-employee-data-theft` and `premium-legal-hold-and-export` already require of the
  same investigator/legal population. The one process change this scenario asks for (the case
  naming convention, §5 step 2) is a two-minute habit change for a small population of
  investigators, not an org-wide rollout.
- Would fund this as a natural, low-cost extension once both prerequisite scenarios are in
  production — it's the kind of "glue automation" that pays for itself the first time it prevents
  a forgotten hold.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Initial draft implied a stronger IRM↔eDiscovery linkage than Microsoft actually documents.**
   An early pass of the README's architecture description read as though Microsoft's escalation
   flow itself populates some form of cross-reference — it does not (design.md §2's grounding: the
   `ediscoveryCase` resource has no source/origin field of any kind).
   - **Resolution:** Reworded README.md §1/§2/§8 and design.md §2 throughout to state plainly that
     the provenance link is *this scenario's own construction* (naming convention + stamped
     description block), never attributed to a native Microsoft linking capability. §8's
     "Provenance is one-directional" callout was added specifically to prevent a reader from
     assuming the IRM side reflects this scenario's work.
2. **Confirmed, not assumed, that custodian/hold auto-provisioning on escalation is genuinely
   undocumented** — independently re-checked both grounding pages cited in `design.md` §3 (`Take
   action on Insider Risk Management cases` and the eDiscovery legacy-solutions integration
   summary) and found neither states whether the flagged user becomes a custodian automatically.
   Confirmed the scenario's unconditional-reconciliation design (§3) is the correct response to
   genuine ambiguity, not a workaround for a fact the team was simply too lazy to find — no
   fabricated claim either direction.
3. **No deprecated or incorrect API surface used.** Every Graph cmdlet/endpoint this scenario calls
   (`Get`/`Update-MgSecurityCaseEdiscoveryCase`, the custodian/userSource/hold family,
   `Get-MgSecurityAlertV2 -AlertId`) is identical to, or a documented parameter set of, cmdlets
   already grounded and in production use by the two scenarios this one sits on top of — no new
   API surface was introduced that required independent grounding beyond what design.md §1–§3
   already cites.
4. **Right feature for the job, not a reinvention.** This scenario doesn't attempt to build a
   custom case-management or alert-triage system — it strictly automates the gap between a
   Microsoft-documented manual action and Microsoft-documented downstream APIs, which is exactly
   the scope this library's "wire the documented integration" follow-up item (tracked in
   `PROGRESS.md`) called for.

No remaining Fix/Fail after resolution.

---

## Follow-up review round — correcting the "automatic Power Automate trigger" claim in README.md §8

Triggered by a `PROGRESS.md` follow-up item ("consider a Power Automate flow … that automatically
runs `Confirm-EdiscoveryEscalationLink.ps1` right after an investigator completes the portal
'Escalate for investigation' step … deferred because [it] wasn't independently grounded"). This pass
grounded it and found the original README.md §8 wording ("a Power Automate flow triggered on
escalation") overstated what Microsoft documents — see design.md §5 for the full finding. Scope:
README.md §8/§11/§12, design.md §4/§5. No code changed (nothing to build once the "automatic
trigger" premise didn't hold up).

### 🔴 Red Team

**Verdict: Pass**

- The corrected wording removes a real operational risk the original draft would have created: a
  organization reading "Power Automate flow triggered on escalation" as a genuine automatic-trigger option
  could have skipped implementing the scheduled poll entirely, leaving cases un-reconciled
  indefinitely whenever the investigator forgot the manual "Automate → Run flow" click too. The
  correction makes explicit that the scheduled poll is the only unattended option today.
- No new bypass surface introduced — this is a documentation-only correction with no code change.

### 🔵 Blue Team

**Verdict: Pass**

- The corrected §8 now gives an operator two honestly-labeled options with their real trade-offs
  (poll latency vs. one-fewer-click manual convenience) instead of one option that silently doesn't
  do what its name implies. That's a strict improvement for whoever has to actually decide which to
  operate.
- Confirmed the premium-connector licensing caveat (design.md §5, R6) is worth surfacing now rather
  than being discovered mid-rollout by whoever tries to add an HTTP action to a custom flow.

### 🎩 CISO

**Verdict: Pass**

- No cost or risk-posture change from this correction — it doesn't add or remove a control, it
  corrects the operating instructions for one that already exists (the scheduled-poll path was
  already documented as an option, just not correctly distinguished from the Power Automate path).
- The corrected narrative is, if anything, a *more* defensible one for an audit committee: "we run
  a scheduled reconciliation job, because Microsoft doesn't offer an automatic trigger for this
  event" is a straightforward, honest control description, rather than one that would have
  overstated automation coverage if scrutinized by an outside auditor asking how the control
  actually fires.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- Independently re-confirmed via the Microsoft Learn MCP tool that both cited pages state manual
  invocation ("you can select … from the Insider Risk Management Cases dashboard"; "Select
  **Automate** on the case action toolbar … select **Run flow**") rather than an automatic
  subscription — the correction is grounded, not a guess in the other direction.
- Confirmed the five documented Purview-connector actions for a custom IRM flow (Get alert/case/
  user/alerts-for-case, Add case note) contain no action capable of invoking an external script or
  webhook directly — the "add a generic HTTP/Azure Automation action" framing in design.md §5 is the
  correct characterization of what an organization would actually need to build, not an oversimplification.
- Confirmed the Insider Risk Management audit log's "independent of the Microsoft 365 audit log"
  statement is current (not a legacy/retired-feature caveat like some other findings this library has
  corrected) — it's an active, if API-less, feature.

No remaining Fix/Fail after resolution.
