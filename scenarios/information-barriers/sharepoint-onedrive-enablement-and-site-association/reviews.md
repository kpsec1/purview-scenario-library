# Four-Lens Review - SharePoint/OneDrive Information Barriers Enablement and Site Association

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail**
items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Rollback-by-suspend is a much bigger hole than intended.** An operator rolling back this
   scenario's own site associations could reach for `-Suspend` out of habit (it's the obvious
   "undo enablement" lever) and unknowingly drop IB enforcement on every Teams-connected site and
   every OneDrive account tenant-wide - including the parent scenario's own protected surfaces.
   - **Resolution:** `rollback.md` opens with an explicit blast-radius warning and a two-stage
     structure that defaults to `-RemoveConfigured` (narrow); the deploy script itself prints a
     red warning when `-Suspend` is invoked, naming exactly what else it affects.
2. **Coverage gap for newly provisioned sites.** The site list is a human-curated config; a new
   standalone SharePoint site created after this fragment ships starts in Open mode and stays
   uncovered until someone adds it to the config and re-runs - a real, findable bypass path (create
   a new site, work there instead).
   - **Resolution:** `design.md` §6 states this as a non-goal rather than implying full coverage;
     `README.md` §8 gives the operational trigger ("re-run whenever a new standalone site is
     provisioned") and points at Microsoft's own Information Barriers policy compliance report as
     a detective control for drift. Not eliminated - Microsoft doesn't offer an enforcement-side
     answer here - but no longer silently assumed away.
3. **Bypass via app-only/people-picker exceptions.** `-AppBypassInformationBarriers` and
   `-AppOnlyBypassPeoplePickerPolicies` are real, documented settings that widen the wall's
   exceptions if another team enables them for an unrelated app.
   - **Resolution:** `README.md` §6/§11 lists these as **not enabled by default** and flags them
     as widening exceptions; `design.md` §6 keeps them an explicit non-goal rather than a silent
     default-on.
4. **Site owners can loosen scope less than it first appears.** Site owners can *add* compatible
   segments to a site they own but Microsoft doesn't let them *remove* one - checked, this cuts the
   wrong way for an attacker (it can only narrow a site further, not open it back up), so it's
   noted as a design strength rather than a finding requiring a fix.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A silently-skipped tenant-state check could look like a pass.** `Get-SPOTenant`'s own
   reference doesn't confirm `InformationBarriersSuspension` is a returned property - a naive
   validate script could either throw or silently report nothing useful.
   - **Resolution:** both the deploy and validate scripts check for the property explicitly and
     emit a `[WARN]` (never a silent skip or a false `[PASS]`) when it's absent, and the deploy
     script degrades to "set explicitly" rather than trusting an unreadable current state.
2. **Segment-GUID property ambiguity could produce a confusing false negative.** If
   `Get-OrganizationSegment` exposes a different property than the script tries first, a validate
   run could report "segment not associated" when the real issue is identifier resolution, not
   association.
   - **Resolution:** both scripts try `EXOSegmentId` then fall back to `.Guid`, and the validate
     script prints which property resolved each segment (`resolved 'Trading' -> <guid> (via
     EXOSegmentId)`) so an operator can immediately tell resolution-failure apart from
     association-failure.
3. **Detection gap: no scripted audit-log export.** The seven documented SharePoint IB audit
   activities are real, but this build couldn't confirm the exact `Search-UnifiedAuditLog`
   `RecordType`/`Operations` values needed to script their export.
   - **Resolution:** `README.md` §8/§11 states this honestly as an open item (shared with the
     parent scenario's own audit-trail follow-up) rather than inventing plausible-looking values;
     the Purview portal audit log is named as the interim, manually-searchable detection path.
4. **Propagation delay could be mistaken for failure.** ~1 hour tenant-wide, up to 24h per site/
   OneDrive - a validate run immediately after deploy could look "wrong" when it's just not
   propagated yet.
   - **Resolution:** both the deploy script's own output and the validate script's closing note
     state the exact windows, matching `README.md` §7/§8.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Closes a gap the org's own prior scenario flagged.** `segregate-trading-and-research`'s
   `README.md` §11 explicitly named SharePoint/OneDrive as required, unbuilt follow-up work - this
   fragment closes that gap rather than leaving it as a permanent disclosed limitation, which
   matters directly for an examiner or auditor reviewing the wall's completeness.
   - **Resolution:** `README.md` §1/§2 states the completion explicitly; `design.md` §1 frames the
     problem as exactly this gap.
2. **Zero incremental licensing cost, real incremental coverage.** Confirmed against the same E5/
   E5 Compliance/IRM/IB add-on entitlement as the parent - no new SKU, no new meter (§10).
3. **Residual risk is a process control, not a technical one.** New-site coverage (Red Team finding
   2) can't be fully automated away with what Microsoft documents; the CISO narrative has to be
   "the technical control is complete for what it's pointed at; keeping it pointed at everything
   requires a provisioning-time checklist," not "fully automatic."
   - **Resolution:** stated plainly in `README.md` §8 and `design.md` §6 rather than oversold.
4. **Would I fund this?** Yes - it's the second half of a control the org already committed to
   funding, at no additional license cost, closing a specific documented gap.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets.** `Set-SPOTenant -InformationBarriersSuspension`, `Set-SPOSite
   -AddInformationSegment`/`-RemoveInformationSegment`/`-InformationBarriersMode`, and
   `Get-OrganizationSegment` are reproduced from Microsoft's own reference pages and worked
   examples, not invented.
2. **Correctly models Microsoft's own automatic/manual split.** Teams-connected sites (Implicit)
   and segmented users' OneDrive (Explicit) are documented as self-associating; this scenario
   scripts only the genuinely manual standalone-site path - not reinventing what the platform
   already automates.
3. **Honest about genuine documentation gaps rather than inventing specifics.** The `EXOSegmentId`
   vs. `.Guid` property-name discrepancy, the unconfirmed `Get-SPOTenant` readback surface, and the
   undocumented `-DefaultOneDriveInformationBarrierMode` value set are all flagged inline as VERIFY
   items instead of guessed - meeting `AGENTS.md` §4's grounding bar.
   - **Fix applied:** the initial draft's automation-surface citation didn't reflect that this
     scenario introduces a genuinely new surface-5 usage pattern (a per-site loop, not a single
     tenant toggle) - `docs/automation-surface.md` §1's surface-5 row and blockquote were updated
     in this same fragment to describe both the existing toggle-only use and this scenario's
     per-site association use, so the cross-cutting doc doesn't go stale the moment this fragment
     ships.
4. **Accurate licensing and RBAC.** Same E5/E5 Compliance/IRM/IB add-on entitlement as the parent;
   SharePoint Administrator/Global Administrator role requirement matches Microsoft's own guidance
   for both the tenant switch and per-site segment management.
5. **Right ordering, stated explicitly.** The prerequisite that IB policies be Active, applied, and
   24h-propagated *before* enabling SharePoint/OneDrive IB is Microsoft's own documented sequence,
   carried into this scenario's README §5 step order rather than left implicit.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (suspend blast-radius warning; new-site coverage gap named; app-only bypass kept off by default; site-owner asymmetry confirmed safe) | Closed |
| 🔵 Blue Team | Fix | 4 (explicit WARN over silent pass; segment-resolution transparency; honest audit-export gap; propagation-delay guidance) | Closed |
| 🎩 CISO | Fix | 1 (gap-closure narrative stated explicitly); Pass on cost/residual-risk framing/funding | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (automation-surface.md updated to reflect the new per-site usage pattern); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/Set-SharePointOneDriveIBEnablement.ps1`, `deploy/Set-SiteInformationSegments.ps1`,
`deploy/config/sharepoint-site-segments.sample.json`,
`validate/Test-SharePointOneDriveInformationBarrierSetup.ps1`, `rollback.md`, and
`docs/automation-surface.md`. No Fail items were raised. This fragment meets the definition of done
in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented cmdlets or property
names presented as confirmed), and genuine documentation gaps are tagged VERIFY rather than
guessed.
