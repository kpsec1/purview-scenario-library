# Four-Lens Review — Compliance Manager: Assess Against ISO/IEC 27001:2022

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The audit-trail script's "who can edit this assessment" coverage has a blind spot: implicit
   Entra-role access.** The deploy script only catches `ComplianceManagerRolesChange` — an
   explicit, Compliance-Manager-scoped role grant. A Global Administrator, Compliance
   Administrator, Compliance Data Administrator, or Security Administrator gets
   Administration-equivalent Compliance Manager access **implicitly** through their Entra ID role,
   generates no `ComplianceManagerRolesChange` event for it, and — per Microsoft's own
   documentation — doesn't even appear on the Compliance Manager **User access** settings page. A
   red-teamer (or a careless/malicious insider who already holds one of those four Entra roles for
   unrelated reasons) could edit or delete this assessment, or move improvement actions to Pass,
   with zero footprint in this scenario's monitored operation set. The original draft didn't call
   this out.
   - **Resolution:** Added an explicit limitation to `README.md` §11 naming all four Entra roles,
     added a matching note to `design.md` §4, and added a quarterly cross-check against Entra
     directory role-assignment history to `README.md` §8's operations cadence. Not fixable by
     widening the audit-trail script's `-Operations` filter — no Compliance-Manager-specific
     operation covers this population; the correct fix is documenting the blind spot and pointing
     at the separate signal (Entra directory audit log) that does cover it, per `docs/rbac-model.md`
     §3.
2. **A doctored Excel upload (§5 step 12, the "Action Update" bulk-import wizard) could mark
   failing controls Passed with fabricated evidence, and this is invisible to the audit-trail
   script.** `ComplianceManagerAutomationChange` only covers switching an action between automatic
   and manual testing — not an individual manual status edit or evidence upload via the Update
   Actions wizard.
   - **Resolution:** Not a gap this scenario's script can close (no such operation is documented —
     `design.md` §4). Already correctly scoped in the original draft: `README.md` §7 and §11
     explicitly state the native Reports page's score/action-history — not this script — is the
     mechanism for that class of change, and that this script is a secondary, complementary
     artifact. No further change needed beyond finding 3 below (durable retention of that
     history).
3. **The native Reports page's history that finding 2 depends on isn't preserved by this scenario
   beyond Microsoft's own 6-month native retention** — a change older than 6 months is simply gone,
   which weakens the "Reports page covers what this script doesn't" claim for any evidence window
   longer than 6 months (a realistic span for an annual ISO 27001 surveillance audit cycle).
   - **Resolution:** Added a quarterly **Export actions** durable-retention recommendation to
     `README.md` §8 and a corresponding limitation note to §11, so the gap is documented and
     mitigated with an operational practice rather than silently assumed away.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The manual verification checklist in `validate/Test-ComplianceManagerAuditTrail.ps1` has no
   wiring to make it actually get run** — unlike this scenario's automated checks (which can be
   scheduled), a printed checklist someone has to remember to read is a real operational-burden
   risk. Is this acceptable, or does it need a stronger nudge?
   - **Resolution:** Not changed — this mirrors the identical, already-reviewed pattern in
     `scenarios/insider-risk/departing-employee-data-theft/validate/
     Test-DepartingEmployeeIrmSetup.ps1` for the same underlying reason (no read API exists to
     automate it), and that scenario's own Blue Team review already accepted the pattern. Flagging
     for visibility, not as a new unresolved Fix — consistent precedent, not a regression.
2. **Alert routing for the automation-trust-change warning is described but not wired to
   anything beyond the script's own console/log output.** An organization relying on cron/Task
   Scheduler/a pipeline to run this on a schedule needs that stdout warning to actually reach a
   human, which this scenario doesn't build.
   - **Resolution:** No code change — this is the same, already-accepted scope boundary
     `scenarios/dlp/pci-teams-exfil-block/README.md` §8 draws for its own alert routing ("this
     scenario's deliverable ends at the native alert surfaces; see `docs/automation-surface.md`
     §4 if building a custom pipeline"). `README.md` §8 here already directs the operator to
     treat any automation-trust-change warning as near-zero-tolerance and gives a full
     incident-response runbook for what to do once it's seen — wiring a specific SIEM/alerting
     product is out of a single scenario's scope, consistent with this library's established
     precedent.
3. **Severity clarity between the validate script's `[FAIL]` (file-integrity) and `[WARN]`
   (presence of an automation-trust-change event) outputs** — confirmed already correctly
   distinguished in the initial draft (the same lesson this repo already applied in
   `scenarios/data-estate-insights/classification-coverage-report/`'s Blue Team round): a
   hard-check failure exits non-zero, while the presence of a legitimately-logged event that
   merely deserves human review does not. No change needed.

No remaining Fail after resolution. Detection is honestly scoped (limitations 2/3 above are
inherent to the product surface, not gaps this script's design introduced), and the runbook in
`README.md` §8 gives an operable response path for the one signal this scenario's code can
actually produce.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** this is a governance/evidence control, not a technical control, and
  the scenario is honest about that distinction (`README.md` §2) rather than overselling a
  compliance score as risk reduction. Licensing cost is the premium-template allotment ISO 27001
  certification would require regardless of this scenario's existence (§3/§10) — this scenario adds
  no incremental Azure/PAYG spend, only the operational cost of running a lightweight PowerShell
  script on a schedule.
- **Board-level narrative:** "we track our ISO 27001 posture in the same platform that enforces our
  technical controls, we know who can edit that tracking, and we've been explicit about the one
  population (Global/Compliance/Security Administrators) we can't yet see edit it in real time" is
  a defensible, honest narrative — the Red Team findings became documented residual risk and an
  operational mitigation (quarterly Entra role cross-check) rather than a silent gap, which is
  exactly what a board/audit committee should see.
- **Compliance mapping:** correctly scoped to being an *evidence and tracking* mechanism for
  ISO/IEC 27001:2022, not a claim of certification or of technical risk reduction — `README.md`
  §11 explicitly repeats Microsoft's own "a high score isn't proof of compliance" caveat rather
  than letting an organization over-read the tooling.
- **Change-management impact:** the recommended deployment order (deploy technical controls first,
  then create the assessment — `design.md` §6, manifest `recommendedDeploymentOrder`) is the right
  sequencing call for the same reason `scenarios/dlp/pci-teams-exfil-block/`'s audit-first internal
  rule was: doing the technical work first means the assessment reflects real progress from day
  one instead of starting at zero and demoralizing whoever owns closing that gap.
- **Would I fund this?** Yes — the premium-template license cost is already a near-certain
  requirement for any ISO 27001 pursuit with or without this scenario; the scenario's own
  incremental cost (one scheduled PowerShell script, no new Azure spend) is negligible against the
  value of not silently missing the two administrative-drift signals this control catches.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Why does this scenario's `deploy/` folder look nothing like every other scenario's — no
   `New-*`/`Set-*` script that creates the Purview object?** On first read this could look like an
   incomplete scenario rather than a deliberately different one.
   - **Resolution:** `design.md` §2 was written specifically to pre-empt this read: it states
     directly that Compliance Manager has no write API as of this build (grounded via three
     separate Microsoft Learn articles — `compliance-manager-assessments`,
     `compliance-manager-update-actions`, `compliance-manager-setup` — plus the absence of any
     Compliance Manager row in this repo's own `docs/automation-surface.md` §4 routing table),
     and that fabricating one would violate `AGENTS.md` §4. This is the correct, current-product
     answer, not a shortfall in this scenario's research — confirmed by an independent search for
     `Get-ComplianceManagementAssessment`-style cmdlets, which returned only unrelated
     Configuration Manager/VMM cmdlets, not a real Compliance Manager equivalent.
2. **Is ISO/IEC 27001:2013 (not :2022) the right template to recommend for a new certification
   effort in 2026?** The 2022 edition superseded 2013 as the standard organizations actually
   certify against; recommending the older template without flagging this could misdirect an organization
   pursuing fresh certification.
   - **Original resolution (superseded — see correction below):** Added an item to `README.md` §11
     flagging this as a VERIFY — confirm current template availability (2013 vs. 2022 edition, or
     both) in the tenant's **Regulations** page at deploy time, since this scenario's own Microsoft
     Learn search only surfaced :2013 documentation as of the original build.
   - **Correction (2026-09-10, re-grounded via the Microsoft Learn MCP tool, PROGRESS.md follow-up
     item):** the VERIFY above is now resolved, not merely re-flagged. Direct fetch of
     `compliance-manager-regulations-list` confirms both :2013 and :2022 are live, separate premium
     templates. The IAF's mandatory transition document (IAF MD 26) closed the industry-wide
     :2013→:2022 certification transition window on October 31, 2025, with certification bodies
     having already stopped initial/recertification audits against :2013 after April 30, 2024 — both
     dates are now in the past. Microsoft's own Microsoft 365/Office 365 ISO/IEC 27001 certificate is
     itself now the "2022 Certificate (2024-2027)" cycle. This scenario, its manifest, and its
     validate script were switched to recommend and deploy **ISO/IEC 27001:2022** as the default —
     see `design.md` §5b for the full grounding and the disclosed citation gap (no dedicated
     `/compliance/regulatory/` Learn page is branded for the :2022 Compliance-Manager template
     specifically, unlike :2013's own page). The original finding's underlying concern (recommending
     the wrong edition to a 2026 organization) is now fully addressed rather than deferred.
3. **Is building a dedicated assessment instead of extending the Data Protection Baseline the
   right call, or does it read as reinventing something Microsoft already ships for free?**
   - **Resolution:** `design.md` §5 addresses this directly, using the same reasoning pattern this
     repo already established in `scenarios/dlp/pci-teams-exfil-block/design.md` §3a for a
     structurally identical question (why not tune the tenant's free default instead of deploying
     a dedicated object): the Data Protection Baseline blends multiple frameworks and isn't a
     citable, audit-mappable ISO 27001 control set on its own — building a dedicated,
     framework-specific assessment is Microsoft's own documented intended use of the premium
     template, not a deviation from it.
4. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`'s existing
   Compliance Manager row (E3 base / E5 premium templates) and confirmed consistent; the December
   2022 premium-template licensing change and the "3 free premium templates at A5/E5/G5" mechanic
   are both independently grounded from the current `compliance-manager-regulations-list` article,
   not assumed from an older source that might have predated that change.
5. **Role name accuracy** — `Compliance Manager Administration` / `Compliance Manager Contribution`
   / `Compliance Manager Assessor` / `Compliance Manager Reader` (the four assessment-access roles)
   and `Compliance Manager Administrators` / `...Assessors` / `...Contributors` / `...Readers` (the
   corresponding role groups) are used correctly and distinctly throughout — confirmed against the
   `scc-permissions` roles-and-role-groups reference and `compliance-manager-setup`'s role-types
   table, not conflated the way an early draft of this kind of table easily could.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (implicit-Entra-role blind spot, closed with documentation + operational mitigation; Excel-upload gap, confirmed already correctly scoped; Reports-page 6-month retention gap, closed with a quarterly export recommendation) | Closed |
| 🔵 Blue Team | Fix | 3 (manual-checklist burden, confirmed consistent with existing repo precedent; alert-routing scope, confirmed consistent with existing repo precedent; severity clarity, confirmed already correct) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 5 (no-write-API shape, confirmed correct and independently re-verified; 2013-vs-2022 template, originally closed with a VERIFY, now fully resolved 2026-09-10 — scenario switched to :2022; Data Protection Baseline reinvention question, closed with design rationale; licensing accuracy, confirmed; role-name accuracy, confirmed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/`. No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.

## Correction addendum (2026-09-10)

A dedicated `PROGRESS.md` follow-up item ("ISO/IEC 27001:2022 premium template is now confirmed to
exist," recorded while grounding the sibling `pci-dss-assessment` scenario) asked this scenario's
own :2013-vs-:2022 VERIFY (Microsoft Product Owner finding 2, above) to be revisited. A fresh
grounding pass this run resolved it definitively rather than re-deferring it: this scenario, its
`design.md` (new §5b), its deploy manifest, and its validate script were all switched from
ISO/IEC 27001:2013 to **ISO/IEC 27001:2022** as the recommended and scripted template. No other
finding in this review round was reopened or affected — the switch is a regulation-name/citation
change throughout the fragment's docs and manifest, not a change to the audit-trail script's logic,
the role model, or any of the four lenses' other conclusions.
