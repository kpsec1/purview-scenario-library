# Four-Lens Review — Compliance Manager: Entra Privileged Role Monitoring

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A role assigned to a role-assignable group is completely invisible to this script.**
   Microsoft's own `groups-concept` documentation confirms a role-assignable group (Entra ID
   P1/P2) can hold one of the four monitored roles, and that membership governance is expected to
   happen at the **group** level. Adding a new member to such a group grants the role but generates
   a `GroupManagement`-category "Add member to group" event, not a `RoleManagement`-category "Add
   member to role" event — a red-teamer (or an insider who already has group-management rights
   over such a group, a much less privileged and less monitored position than holding the role
   directly) could grant themselves Global Administrator-equivalent access with zero footprint in
   this script's monitored event set. The original draft didn't disclose this.
   - **Resolution:** Added `design.md` §4b (new section) and a matching, prominent limitation to
     `README.md` §11 with concrete portal/cmdlet guidance for checking whether any of the four
     roles is currently group-assigned. Not fixable within this fragment's scope by widening the
     `$filter` (it would require first enumerating role-assignable groups holding these roles, then
     monitoring a structurally different event category for that specific group set) — tracked as
     a follow-up in `PROGRESS.md` rather than silently left undisclosed.
2. **The "Add member to role (permanent)" naming discrepancy could mean a real, silent miss, not
   just a documentation curiosity.** Microsoft's own "Security operations for privileged accounts"
   guidance names a differently-suffixed activity for exactly this scenario's target risk
   (out-of-PIM role assignment). If that name is a genuinely distinct event (reading "b" in
   `design.md` §4a) rather than an alternate label for the same event, a role assigned permanently
   through the PIM blade itself could be missed entirely by the original draft's exact-match filter.
   - **Resolution:** Added `design.md` §4a documenting both readings explicitly, a VERIFY item to
     `README.md` §11, and a matching `.NOTES` VERIFY in the deploy script — including the concrete
     "practical consequence if reading (b) is correct" so a reader isn't left to infer the stakes.
     Deliberately **not** resolved by widening the filter to a wildcard match, which would guess at
     the answer rather than grounding it (`AGENTS.md` §4).
3. **Custom roles or renamed/cloned equivalents to the four monitored roles would evade the
   exact-name filter.** A sophisticated attacker with `RoleManagement.ReadWrite.Directory` could
   create a custom role with equivalent permissions under a different display name.
   - **Resolution:** Accepted, disclosed scope limitation — inherent to any name-based allow-list
     approach, not something a code change to this fragment can close without a much larger
     permission-diffing capability. `design.md` §6's role-list parameterization already documents
     this as an extension point (a buyer can add a known custom role's name to
     `-PrivilegedRoleDisplayNames`); no further code change needed.

No remaining Fix/Fail after resolution — findings 1 and 2 are genuine, bounded gaps now explicitly
disclosed with concrete mitigation guidance rather than silently assumed away; finding 3 is an
accepted limitation of the chosen (and correctly scoped, per the Microsoft Product Owner lens
below) approach.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Throttling/retry behavior wasn't stated anywhere**, unlike this library's other Graph-surface
   scripts, which `docs/automation-surface.md` §7 requires scenarios to address explicitly.
   - **Resolution:** Added a throttling note to `README.md` §5 and a `.NOTES` entry in the deploy
     script: the script calls the SDK cmdlet directly (never raw REST), so it inherits the SDK's
     automatic retry-with-backoff per `docs/automation-surface.md` §5 without needing its own
     429-handling.
2. **A failed/never-ran scheduled job is silent** — the original draft's §8 noted this but didn't
   push the reader toward actually fixing it.
   - **Resolution:** Strengthened `README.md` §8 with an explicit "wire this up from day one"
     instruction naming concrete scheduler options (Azure Automation, Task Scheduler, a CI
     pipeline) rather than leaving the gap as a passive observation.
3. **Severity clarity between the validate script's `[FAIL]` (file-integrity) and `[WARN]`
   (Global Administrator event presence) outputs** — confirmed already correctly distinguished in
   the initial draft, consistent with this repo's established pattern
   (`assess-against-iso27001/reviews.md` Blue Team finding 3 made the same confirmation for its
   sibling script). No change needed.
4. **Manual verification checklist has no automated wiring**, mirroring the same accepted pattern
   already reviewed in `assess-against-iso27001/validate/Test-ComplianceManagerAuditTrail.ps1` (no
   read API exists to automate a portal spot-check). Flagging for visibility, not as a new
   unresolved Fix — consistent precedent, not a regression.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** closes a real, disclosed blind spot in an already-shipped scenario
  (`assess-against-iso27001`) at effectively zero incremental license cost (§10) — the
  `AuditLog.Read.All` Graph permission is available at every Entra ID tier. High risk-reduction
  value (visibility into changes to the tenant's four most powerful role assignments) for
  negligible cost is an easy funding decision.
- **Board-level narrative:** "we know who can edit our compliance evidence through an explicit
  Compliance Manager grant, and now we also monitor the population that can touch it implicitly
  through a directory role, with disclosed and bounded exceptions (role-assignable groups, PIM
  activation) rather than an unstated gap" is a materially stronger, more honest narrative than
  before this scenario existed — the two Red Team findings became documented residual risk with
  concrete mitigation paths, exactly what a board/audit committee should be shown.
- **Compliance mapping:** directly supports least-privilege/separation-of-duties evidence for
  ISO/IEC 27001:2022's Annex A access-control requirements (Organizational Controls theme, A.5) and
  SOC 2 CC6 — a natural, correctly-scoped complement to `assess-against-iso27001` rather than a
  standalone claim.
- **Change-management impact:** near-zero — one new scheduled script, no new portal object, no new
  role grant beyond a single least-privileged Graph application permission for the automation
  identity.
- **Would I fund this?** Yes — this is exactly the kind of small, cheap, high-signal control a CISO
  should not need convincing on, especially once framed against the specific Red Team finding in
  the sibling scenario it closes.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is this reinventing Microsoft's own native "Roles are being assigned outside of Privileged
   Identity Management" PIM alert?** On first read, a scenario that monitors exactly "roles
   assigned outside of PIM" could look like it's duplicating a capability Microsoft already ships.
   - **Resolution:** `design.md` §2 now states directly that this native alert is licensing-gated —
     Microsoft's own PIM alert configuration guidance documents a separate, dedicated alert that
     fires specifically because the tenant **lacks** Entra ID P2/Governance, confirming the primary
     alert doesn't function without it. This scenario is the equivalent detective control for
     tenants below that floor (a real segment of this library's target buyers per `AGENTS.md` §3's
     Scale axis), and a complementary, durably-exportable signal even for tenants above it (the
     native alert is portal/email-only, with no documented queryable export this script's CSV
     provides).
2. **Activity-name grounding accuracy** — checked the deploy script's six monitored activity names
   directly against the canonical `reference-audit-activities` Core Directory table; all six
   confirmed present verbatim. The original draft's two-activity list omitted four documented,
   directly-relevant sibling activities (the Administrative-Unit-scoped and "scoped member"
   variants) without disclosing the omission.
   - **Resolution:** Widened `$monitoredActivities` in the deploy script (and the matching
     validate-script allow-list) to all six documented Core Directory activities — a correctness
     fix grounded in the same source already cited, not scope creep into unconfirmed territory.
3. **Role name accuracy** — `Global Administrator`, `Compliance Administrator`, `Compliance Data
   Administrator`, `Security Administrator` checked against `docs/rbac-model.md` §3's own mapping
   table and Microsoft's `permissions-reference` built-in roles page; used correctly and
   consistently throughout.
4. **Is `Get-MgAuditLogDirectoryAudit` (Microsoft.Graph.Reports) the current, non-deprecated
   cmdlet for this resource, or should this target a newer Entra PowerShell module cmdlet
   instead?** Checked against the current `microsoft.graph.reports` module reference page (fetched
   directly, not assumed from memory) — confirmed current, with syntax and parameters matching
   what the deploy script uses (`-Filter`, `-All`, `-PageSize`). The newer `Microsoft.Entra`
   module family (referenced elsewhere in this library for `Add-EntraDirectoryRoleMember`-style
   role-management cmdlets) does not appear to expose an equivalent bulk *audit log* query cmdlet as
   of this build — `Microsoft.Graph.Reports` remains the correct choice for this specific task.
5. **Licensing citation accuracy** — the 7-day (Free) / 30-day (P1/P2) retention figures and the
   "no premium license required for the core capability" claim checked directly against Microsoft's
   `reference-reports-data-retention` page; consistent with `docs/licensing-matrix.md`'s existing
   general Entra ID P1/P2 prerequisite language (§4) without contradicting it.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (role-assignable-group blind spot, closed with documentation + mitigation guidance; PIM "(permanent)" naming ambiguity, closed with a VERIFY rather than a guess; custom/cloned-role evasion, confirmed as an accepted, disclosed limitation of the name-based approach) | Closed |
| 🔵 Blue Team | Fix | 4 (throttling/retry undocumented, closed by citing the SDK's built-in behavior; silent job-failure risk, closed with a stronger operational instruction; validate-script severity clarity, confirmed already correct; manual-checklist automation burden, confirmed consistent with existing repo precedent) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 5 (native-PIM-alert reinvention question, closed with a licensing-gate-based rationale; activity-list completeness, closed with a grounded widening from 2 to 6 activities; role-name accuracy, confirmed; cmdlet currency, confirmed; licensing-citation accuracy, confirmed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/`/`validate/`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.
