# Four-Lens Review - Compliance Manager: Entra Privileged Role Monitoring

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
   member to role" event - a red-teamer (or an insider who already has group-management rights
   over such a group, a much less privileged and less monitored position than holding the role
   directly) could grant themselves Global Administrator-equivalent access with zero footprint in
   this script's monitored event set. The original draft didn't disclose this.
   - **Resolution:** Added `design.md` §4b (new section) and a matching, prominent limitation to
     `README.md` §11 with concrete portal/cmdlet guidance for checking whether any of the four
     roles is currently group-assigned. Not fixable within this fragment's scope by widening the
     `$filter` (it would require first enumerating role-assignable groups holding these roles, then
     monitoring a structurally different event category for that specific group set) - tracked as
     a follow-up in `PROGRESS.md` rather than silently left undisclosed.
2. **The "Add member to role (permanent)" naming discrepancy could mean a real, silent miss, not
   just a documentation curiosity.** Microsoft's own "Security operations for privileged accounts"
   guidance names a differently-suffixed activity for exactly this scenario's target risk
   (out-of-PIM role assignment). If that name is a genuinely distinct event (reading "b" in
   `design.md` §4a) rather than an alternate label for the same event, a role assigned permanently
   through the PIM blade itself could be missed entirely by the original draft's exact-match filter.
   - **Resolution:** Added `design.md` §4a documenting both readings explicitly, a VERIFY item to
     `README.md` §11, and a matching `.NOTES` VERIFY in the deploy script - including the concrete
     "practical consequence if reading (b) is correct" so a reader isn't left to infer the stakes.
     Deliberately **not** resolved by widening the filter to a wildcard match, which would guess at
     the answer rather than grounding it (`AGENTS.md` §4).
3. **Custom roles or renamed/cloned equivalents to the four monitored roles would evade the
   exact-name filter.** A sophisticated attacker with `RoleManagement.ReadWrite.Directory` could
   create a custom role with equivalent permissions under a different display name.
   - **Resolution:** Accepted, disclosed scope limitation - inherent to any name-based allow-list
     approach, not something a code change to this fragment can close without a much larger
     permission-diffing capability. `design.md` §6's role-list parameterization already documents
     this as an extension point (an organization can add a known custom role's name to
     `-PrivilegedRoleDisplayNames`); no further code change needed.

No remaining Fix/Fail after resolution - findings 1 and 2 are genuine, bounded gaps now explicitly
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
2. **A failed/never-ran scheduled job is silent** - the original draft's §8 noted this but didn't
   push the reader toward actually fixing it.
   - **Resolution:** Strengthened `README.md` §8 with an explicit "wire this up from day one"
     instruction naming concrete scheduler options (Azure Automation, Task Scheduler, a CI
     pipeline) rather than leaving the gap as a passive observation.
3. **Severity clarity between the validate script's `[FAIL]` (file-integrity) and `[WARN]`
   (Global Administrator event presence) outputs** - confirmed already correctly distinguished in
   the initial draft, consistent with this repo's established pattern
   (`assess-against-iso27001/reviews.md` Blue Team finding 3 made the same confirmation for its
   sibling script). No change needed.
4. **Manual verification checklist has no automated wiring**, mirroring the same accepted pattern
   already reviewed in `assess-against-iso27001/validate/Test-ComplianceManagerAuditTrail.ps1` (no
   read API exists to automate a portal spot-check). Flagging for visibility, not as a new
   unresolved Fix - consistent precedent, not a regression.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** closes a real, disclosed blind spot in an already-shipped scenario
  (`assess-against-iso27001`) at effectively zero incremental license cost (§10) - the
  `AuditLog.Read.All` Graph permission is available at every Entra ID tier. High risk-reduction
  value (visibility into changes to the tenant's four most powerful role assignments) for
  negligible cost is an easy funding decision.
- **Board-level narrative:** "we know who can edit our compliance evidence through an explicit
  Compliance Manager grant, and now we also monitor the population that can touch it implicitly
  through a directory role, with disclosed and bounded exceptions (role-assignable groups, PIM
  activation) rather than an unstated gap" is a materially stronger, more honest narrative than
  before this scenario existed - the two Red Team findings became documented residual risk with
  concrete mitigation paths, exactly what a board/audit committee should be shown.
- **Compliance mapping:** directly supports least-privilege/separation-of-duties evidence for
  ISO/IEC 27001:2022's Annex A access-control requirements (Organizational Controls theme, A.5) and
  SOC 2 CC6 - a natural, correctly-scoped complement to `assess-against-iso27001` rather than a
  standalone claim.
- **Change-management impact:** near-zero - one new scheduled script, no new portal object, no new
  role grant beyond a single least-privileged Graph application permission for the automation
  identity.
- **Would I fund this?** Yes - this is exactly the kind of small, cheap, high-signal control a CISO
  should not need convincing on, especially once framed against the specific Red Team finding in
  the sibling scenario it closes.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is this reinventing Microsoft's own native "Roles are being assigned outside of Privileged
   Identity Management" PIM alert?** On first read, a scenario that monitors exactly "roles
   assigned outside of PIM" could look like it's duplicating a capability Microsoft already ships.
   - **Resolution:** `design.md` §2 now states directly that this native alert is licensing-gated -
     Microsoft's own PIM alert configuration guidance documents a separate, dedicated alert that
     fires specifically because the tenant **lacks** Entra ID P2/Governance, confirming the primary
     alert doesn't function without it. This scenario is the equivalent detective control for
     tenants below that floor (a real segment of this library's target organizations per `AGENTS.md` §3's
     Scale axis), and a complementary, durably-exportable signal even for tenants above it (the
     native alert is portal/email-only, with no documented queryable export this script's CSV
     provides).
2. **Activity-name grounding accuracy** - checked the deploy script's six monitored activity names
   directly against the canonical `reference-audit-activities` Core Directory table; all six
   confirmed present verbatim. The original draft's two-activity list omitted four documented,
   directly-relevant sibling activities (the Administrative-Unit-scoped and "scoped member"
   variants) without disclosing the omission.
   - **Resolution:** Widened `$monitoredActivities` in the deploy script (and the matching
     validate-script allow-list) to all six documented Core Directory activities - a correctness
     fix grounded in the same source already cited, not scope creep into unconfirmed territory.
3. **Role name accuracy** - `Global Administrator`, `Compliance Administrator`, `Compliance Data
   Administrator`, `Security Administrator` checked against `docs/rbac-model.md` §3's own mapping
   table and Microsoft's `permissions-reference` built-in roles page; used correctly and
   consistently throughout.
4. **Is `Get-MgAuditLogDirectoryAudit` (Microsoft.Graph.Reports) the current, non-deprecated
   cmdlet for this resource, or should this target a newer Entra PowerShell module cmdlet
   instead?** Checked against the current `microsoft.graph.reports` module reference page (fetched
   directly, not assumed from memory) - confirmed current, with syntax and parameters matching
   what the deploy script uses (`-Filter`, `-All`, `-PageSize`). The newer `Microsoft.Entra`
   module family (referenced elsewhere in this library for `Add-EntraDirectoryRoleMember`-style
   role-management cmdlets) does not appear to expose an equivalent bulk *audit log* query cmdlet as
   of this build - `Microsoft.Graph.Reports` remains the correct choice for this specific task.
5. **Licensing citation accuracy** - the 7-day (Free) / 30-day (P1/P2) retention figures and the
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
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 5 (native-PIM-alert reinvention question, closed with a licensing-gate-based rationale; activity-list completeness, closed with a grounded widening from 2 to 6 activities; role-name accuracy, confirmed; cmdlet currency, confirmed; licensing-citation accuracy, confirmed) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/`/`validate/`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.

---

# Round 2 - `Export-RoleAssignableGroupMembershipAuditTrail.ps1` (companion script)

Reviewed after drafting the companion script that closes round 1's Red Team finding 1 (the
role-assignable-group blind spot) - `deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1`,
`validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1`, `design.md` §10, and the matching
`README.md`/`rollback.md` updates. One round of findings below; all **Fix** items were applied
before this file was finalized. No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Does closing the group-membership gap open a narrower, second-order gap: what if the
   *role-to-group assignment itself* changes, not the group's membership?** If `Global
   Administrator` is *removed* from a role-assignable group entirely (not a membership change to
   the group, but the group-to-role unassignment itself), that's a `RoleManagement`-category event
   on the **group** as principal - does the sibling script's `Export-EntraPrivilegedRoleAuditTrail.ps1`
   catch it (its `targetResources` Role-type filter doesn't care what kind of principal was added/
   removed), or does it fall in a gap between the two scripts?
   - **Resolution:** Traced through both scripts' logic: `Export-EntraPrivilegedRoleAuditTrail.ps1`
     filters on `activityDisplayName in ('Add member to role', 'Remove member from role', ...)` and
     a `Role`-typed `targetResources` entry matching a monitored role name - it does **not** filter
     on the affected principal's type (user vs. group), so a role assigned to or removed from a
     **group** (the role-to-group assignment/unassignment itself, as opposed to the group's own
     membership) is a `RoleManagement`-category "Add/Remove member to/from role" event exactly like
     a role assigned to a user, and the sibling script already catches it - confirmed by re-reading
     its existing code rather than assumed. Only the group's own **membership** (who's inside it)
     needed a separate `GroupManagement`-category watcher, which is exactly what this companion
     builds. No gap between the two scripts. Documented this boundary explicitly in `design.md` §10
     so a future reader doesn't have to re-derive it.
2. **A sophisticated attacker with `RoleManagement.ReadWrite.Directory` could create a brand-new
   role-assignable group, assign it a monitored role, and add themselves to it - all inside one
   Phase 1-to-Phase 1 discovery gap (between two scheduled runs of this companion script).** Is
   that window a real, disclosed risk?
   - **Resolution:** Yes, and it's inherent to any poll-based (not event-driven) detective control -
     the same accepted trade-off `Export-EntraPrivilegedRoleAuditTrail.ps1` already carries for its
     own daily-poll cadence (round 1 didn't flag this for the sibling script because polling is this
     entire scenario's chosen architecture, `design.md` §2). Added an explicit note to `README.md`
     §11: the companion's window of exposure is bounded by its own run interval (daily by default,
     `design.md` §10) - the same "run daily, not weekly" guidance the sibling script's §8 already
     gives applies identically here, and a tighter interval (e.g. hourly) directly narrows this
     window for an organization with a lower risk tolerance. Not a code change - a disclosed operational
     parameter, consistent with how this scenario already treats cadence.
3. **Could an attacker evade detection by adding themselves to the role-assignable group's
   membership through a path other than the standard `Add member to group` activity - e.g. a bulk
   import?** `reference-audit-activities` documents a distinct
   `"GroupManagement | Bulk import group members - finished (bulk)"` activity under a *different*
   name than the two this script's `$monitoredActivities` filters on.
   - **Resolution:** Genuine, disclosed gap - added to `README.md` §11: the companion currently
     monitors only the two standard single-member `Add member to group`/`Remove member from group`
     activities; a bulk-import path (`Microsoft Entra (AAD) Management UX` audit source, a distinct
     activity name) is not covered by the current `$monitoredActivities` list. Not fixed by silently
     widening the filter to an unconfirmed bulk-activity shape this build didn't independently
     verify targets the same `targetResources` schema - tracked as a follow-up in `PROGRESS.md`
     rather than guessed at, consistent with `AGENTS.md` §4.

No remaining Fail after resolution - finding 1 was resolved by tracing existing code (no scope
gap existed); findings 2 and 3 are genuine, now-disclosed residual gaps with concrete guidance
(narrower poll interval; a follow-up to ground the bulk-import activity name) rather than silently
assumed away.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Two structurally different `Write-Warning` types (Phase 1 "group discovered" vs. Phase 2
   "membership changed") could be confused by an on-call responder skimming console output or a
   log aggregator that doesn't preserve the full message text** - the original draft didn't call
   this out.
   - **Resolution:** Added an explicit operations note to `README.md` §8 distinguishing the two
     warning types and what each means (informational scope-change vs. actionable incident signal).
2. **The validate script's manual checklist item about cross-referencing Phase 1 discovery against
   the portal is good, but nothing tells a responder what to do if the two *disagree*** (i.e. the
   CSV's discovered `GroupDisplayName`/`RoleDisplayName` doesn't match what the Roles & admins blade
   currently shows).
   - **Resolution:** Confirmed this is expected and time-bound, not necessarily a bug: Phase 1 runs
     fresh each invocation, so a portal check performed *after* the script ran (and after a role
     was reassigned) will legitimately show a different current state than the CSV's per-run
     snapshot. Clarified this in the validate script's manual checklist wording (checking against
     the portal "at the time this run executed" rather than "now") rather than leaving it as an
     apparent discrepancy with no explanation.
3. **Throttling/retry behavior for the two new Graph resources (`groups`, `roleManagement/
   directory`) wasn't separately confirmed** - the deploy script's `.NOTES` asserted "all three
   Graph resources ... implement automatic retry" without independently checking the two new ones.
   - **Resolution:** Confirmed: `Get-MgGroup` and `Get-MgRoleManagementDirectoryRoleAssignment`/
     `Get-MgRoleManagementDirectoryRoleDefinition` are Microsoft Graph PowerShell SDK cmdlets from
     the same SDK family (`Microsoft.Graph.Groups`, `Microsoft.Graph.Identity.Governance`) as the
     already-confirmed `Get-MgAuditLogDirectoryAudit` - the SDK's retry-with-backoff behavior is a
     property of the SDK's HTTP pipeline, not resource-specific, so it applies uniformly. No change
     needed beyond the existing `.NOTES` wording, which already states this correctly.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** fully closes a Red-Team-disclosed, previously-accepted-as-residual
  gap in an already-shipped, already-funded scenario, at a small, bounded incremental cost (two
  additional least-privileged Graph application permissions, no new license tier). This is exactly
  the kind of gap-closure a CISO should expect a vendor to deliver as a matter of course once
  disclosed, not treat as a new discretionary spend decision.
- **Board-level narrative upgrade:** "we monitor privileged role changes made directly to a user,
  AND to a role-assignable group's own membership, with only two narrow, disclosed residual gaps
  (a bounded polling window; an unconfirmed bulk-import activity path) instead of one large,
  previously-accepted gap" is a materially stronger position for an ISO 27001/SOC 2 auditor
  conversation than round 1's "disclosed but unmitigated" framing.
- **Compliance mapping:** same ISO/IEC 27001:2022 Annex A (A.5) and SOC 2 CC6 mapping as the parent
  scenario - this companion is additive evidence for the same control objective, not a new one.
- **Change-management impact:** near-zero - one new scheduled script sharing the existing app
  registration (two additional permission grants), no new portal object.
- **Would I fund this?** Yes, without hesitation - closing a self-disclosed gap in a shipped
  control at negligible incremental cost is the easiest follow-on funding decision a CISO can make.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is the two-phase discover-then-monitor design the right shape, or should this have been built
   as a single combined query?** Checked whether Microsoft Graph's `directoryAudits` resource could
   instead be filtered directly for "any GroupManagement event on any role-assignable group," which
   would avoid a separate discovery phase.
   - **Resolution:** No such combined filter exists - `targetResources` on a `GroupManagement` event
     identifies the affected group by `id`/`displayName` only, with no queryable "is this group
     role-assignable and does it currently hold role X" property exposed on the audit record itself.
     The two-phase design (resolve the group set first via `groups`/`roleManagement` resources, then
     query `directoryAudits` for exactly that set) is the only grounded approach - confirmed correct,
     not just convenient.
2. **Cmdlet currency check** - `Get-MgGroup`, `Get-MgRoleManagementDirectoryRoleDefinition`, and
   `Get-MgRoleManagementDirectoryRoleAssignment` checked directly against their current Microsoft
   Learn reference pages (not assumed from memory); all current, non-deprecated, with the
   `-Filter`/`-All` syntax the deploy script uses matching the documented parameter sets.
3. **Permission accuracy** - `Group.Read.All` and `RoleManagement.Read.Directory` checked against
   the `Get-MgGroup` and `Get-MgRoleManagementDirectoryRoleAssignment` cmdlet reference pages'
   own Application-permissions tables (the actual cmdlets the deploy script calls, not just the
   underlying REST resource) - both confirmed directly listed. Note: the generic REST "List groups"
   API page documents a differently-shaped, oddly-narrow permission
   (`Group-NestingSupport.ReadWrite.All`) as its own least-privileged option; the deploy script's
   `.NOTES` and `README.md` §12 cite the `Get-MgGroup` cmdlet page specifically rather than that REST
   page, avoiding the mismatch.
4. **Is this reinventing a native Microsoft capability?** Checked whether Entra ID, PIM, or Access
   Reviews ship a built-in alert specifically for "role-assignable group membership changed." No
   such native alert was found distinct from Access Reviews' own periodic (not real-time/audit-
   driven) recertification workflow for role-assignable groups - this script remains a genuinely
   complementary, real-time-capable detective control, not a duplicate of an existing native alert.

No remaining Fail after resolution.

---

## Round 2 Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (group-vs-role-assignment boundary, resolved by tracing existing code - no gap; poll-window exposure, disclosed with operational guidance; bulk-import activity path, disclosed as a follow-up rather than guessed at) | Closed |
| 🔵 Blue Team | Fix | 3 (warning-type confusion risk, closed with an operations note; discovery-vs-portal timing discrepancy, closed with clarified checklist wording; new-resource throttling, confirmed already correctly covered) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 4 (two-phase design necessity, confirmed correct; cmdlet currency, confirmed; permission accuracy, confirmed with a transparency note on the odd "least privileged" naming; native-capability reinvention, confirmed not a duplicate) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/`/`validate/`. No Fail items were raised. This fragment (the companion script closing round
1's Red Team finding 1) meets the definition of done in `AGENTS.md` §9.

---

## Round 3 - revisiting round 2 Red Team finding 3 (bulk import group members)

Reviewed after grounding `PROGRESS.md`'s open follow-up on whether "Bulk import group members -
finished (bulk)"/"Bulk remove group members - finished (bulk)" are real, monitorable activities, and
adding them to `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s `$monitoredActivities`.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Is "confirmed as a real activity name" enough to add it to `$monitoredActivities`, or does
   doing so risk a false sense of coverage if the record shape doesn't match?** Round 2 correctly
   declined to guess at the `targetResources` shape. Simply adding the two activity names without
   also checking whether the existing shape-matching logic degrades safely would risk the opposite
   failure mode - claiming coverage that silently isn't there.
   - **Resolution:** Confirmed `Get-GroupTargetFromTargetResources` already fails soft (returns
     nothing if no `Group`-typed entry is present) rather than assuming a shape - adding the two
     activity names can only ever gain matches, never fabricate one, because a record that doesn't
     carry a `Group`-typed target is filtered out by the same logic that already handles the
     "Remove member from group" symmetry VERIFY. This is a strictly safe addition given that
     existing invariant, not a new guess. `README.md` §11 and the deploy script's `.NOTES` state the
     shape is still unconfirmed rather than declaring the gap fully closed.
2. **A bulk operation can affect many members in one audit record - does the single
   `PrincipalDisplayName` column silently under-report if only the first `User`-typed target is
   captured?** The pre-existing `Get-PrincipalDisplayNameFromTargetResources` took only the first
   match, which was harmless when every monitored activity was single-member, but would silently
   drop members 2..N of a bulk record once bulk activities were added.
   - **Resolution:** Widened the function to collect every `User`-typed target and join them
     (semicolon-separated) rather than only the first. This is shape-agnostic (doesn't assume a bulk
     record has more than one, or exactly how many) and doesn't change output for any single-member
     event, which continues to yield exactly one name as before.

No remaining Fail. The "not monitored at all" half of round 2 finding 3 is now closed; the
`targetResources`-shape half remains open and is carried forward as a `PROGRESS.md` VERIFY
(pilot-tenant test described in `validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1`'s new
manual-checklist item) rather than closed by assumption.

### 🔵 Blue Team

**Verdict: Pass**

- The widened `PrincipalDisplayName` extraction is a strict improvement for an on-call responder
  reading the CSV - a semicolon-separated list is still human-readable, and the column's meaning
  ("who was affected") is unchanged for the pre-existing single-member activities.
- `validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1`'s automated check was widened from a
  2-activity to a 4-activity allowlist, so a record with an unexpected `ActivityDisplayName` still
  fails the same automated check as before - no coverage regression in the validation script itself.
- The new manual-checklist item gives a responder a concrete, actionable pilot-tenant test (a
  throwaway bulk add/remove) to close the remaining VERIFY, rather than leaving it as an abstract
  research question with no way to act on it operationally.

No Fix/Fail items from this lens.

### 🎩 CISO

**Verdict: Pass**

- Same low-cost, no-new-license-tier profile as round 2's companion script - this is a same-day
  refinement of already-funded automation, not a new spend decision.
- Narrative improvement is incremental but real: "bulk group-membership changes are now in the
  monitored activity list, with one disclosed, pilot-testable residual gap" is a stronger audit
  answer than round 2's "not monitored at all."

No Fix/Fail items from this lens.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- Both new activity names were confirmed against Microsoft's own `reference-audit-activities.md`
  documentation source (fetched directly, not inferred from a search snippet), consistent with
  `AGENTS.md` §4's grounding requirement - no invented activity name or cmdlet was introduced.
- No native Microsoft alert or built-in report was found that already covers "bulk group-membership
  change on a privileged role-assignable group" specifically - this remains a complementary control,
  not a duplicate of an existing product capability.

No Fix/Fail items from this lens.

### Round 3 Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (safe-addition invariant confirmed; multi-member under-reporting closed by widened extraction) | Closed |
| 🔵 Blue Team | Pass | 0 | - |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Pass | 0 | - |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`,
`README.md`, and `design.md`. No Fail items were raised. The residual `targetResources`-shape VERIFY
is deliberately left open (not guessed at) and tracked in `PROGRESS.md`.

## Round 4 - closing the "Add member to role (permanent)" naming VERIFY (round 1 Red Team finding 2)

Reviewed after grounding `PROGRESS.md`'s open VERIFY on whether Microsoft's "Security operations for
privileged accounts" guidance's `"Add member to role (permanent)"` (Service = PIM) is the same
underlying event as, or genuinely distinct from, the plain `"Add member to role"` (Core Directory)
`Export-EntraPrivilegedRoleAuditTrail.ps1` filters on, and updating `$monitoredActivities` to match.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Round 1 correctly declined to guess, but that left a real, bounded detection gap open for three
   rounds.** If reading (b) from `design.md` §4a was correct, a role assigned permanently through the
   PIM blade while bypassing PIM's eligible/active workflow would log only under the
   `(permanent)`-suffixed PIM activity and never appear in this script's output at all - exactly the
   "roles assigned outside of PIM" risk this scenario exists to catch.
   - **Resolution:** A direct fetch of Microsoft's canonical `reference-audit-activities` reference
     (not a search snippet) confirms `Add member to role outside of PIM (permanent)` is listed as
     its own, separately-documented activity under the PIM service's `RoleManagement` category -
     distinct from `Add member to role`, listed only under Core Directory's `RoleManagement`
     category. Reading (b) is confirmed. `$monitoredActivities` now includes both names; the
     `Get-RoleDisplayNameFromTargetResources`/`Get-PrincipalDisplayNameFromTargetResources` extraction
     logic is unchanged (already shape-agnostic, filters by `.Type` rather than assuming a specific
     activity), so no new guess was introduced alongside the fix.

No remaining Fail. This closes the last open item from round 1 Red Team finding 2.

### 🔵 Blue Team

**Verdict: Pass**

- The added activity flows through the same de-duplication (by `Id`), CSV schema, and
  `Write-Warning` severity logic as the existing six - no new code path for an on-call responder to
  learn, just a wider net on the existing one.
- `validate/Test-EntraPrivilegedRoleAuditTrail.ps1`'s allowlist was widened from 6 to 7 activities in
  lockstep, so a genuinely unexpected `ActivityDisplayName` still fails the same automated check as
  before.

No Fix/Fail items from this lens.

### 🎩 CISO

**Verdict: Pass**

- Closes a previously-disclosed, bounded detection gap at zero incremental cost - same script,
  same schedule, same licensing profile (`README.md` §10 unchanged).
- Strengthens the audit narrative: "this scenario now directly implements Microsoft's own published
  out-of-PIM detection signal" is a stronger answer than round 1's disclosed VERIFY.

No Fix/Fail items from this lens.

### 🟦 Microsoft Product Owner

**Verdict: Pass**

- The added activity name was confirmed against Microsoft's own `reference-audit-activities`
  documentation source via a direct fetch, consistent with `AGENTS.md` §4's grounding requirement -
  no invented activity name was introduced, and no wildcard/fuzzy match was used to guess at it.
- This scenario now aligns precisely with the specific activity Microsoft's own "Security operations
  for privileged accounts" guidance names for this exact detection scenario, closing the one
  documented gap between this script's filter and Microsoft's published guidance.

No Fix/Fail items from this lens.

### Round 4 Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 1 (naming discrepancy grounded as two genuinely distinct events; missing PIM activity added to `$monitoredActivities`) | Closed |
| 🔵 Blue Team | Pass | 0 | - |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Pass | 0 | - |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`,
`README.md`, and `design.md`. No Fail items were raised. No VERIFY items remain open for this
specific naming discrepancy; the unrelated `targetResources`-shape VERIFY from round 3 (bulk import
group members) remains open and tracked in `PROGRESS.md`.
