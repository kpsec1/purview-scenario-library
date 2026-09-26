# Four-Lens Review - Priority Cleanup for SharePoint & OneDrive

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The routine case gets zero per-item human review.** Unlike the Exchange sibling, which always
   requires 3 approval stages, this workload's post-turn-on approval is **conditional on an
   eDiscovery hold existing** - content that was never put on hold (the overwhelming majority of
   stale Teams recordings) is moved to the Recycle Bin with **no per-item approval at all** once
   the policy is live. The entire safety burden sits on the one-time pre-turn-on simulation review.
   - **Resolution:** `design.md` §3's comparison table states this plainly ("0 or 1 stage"
     vs. Exchange's "3 stages, always"); `README.md` §2's callout and §8's tuning guidance name the
     query as the single point of failure precisely because no per-item backstop exists for
     un-held content.
2. **A continual policy with no age filter can widen its own blast radius over time without anyone
   re-approving it.** `ProgID:Media AND ProgID:Meeting` matches every Teams recording ever created
   in scope, not just stale ones - if the policy's location scope is later widened (e.g. from a
   pilot OneDrive account to `-OneDriveLocation All`), that widening requires a fresh mandatory
   simulation, but the query itself staying broad is not something the platform flags as risky.
   - **Resolution:** `README.md` §8 states this explicitly as a tuning gap with no scripted
     mitigation, rather than presenting the sample query as a complete "stale-only" filter; `design.md`
     §7 tracks a scheduled query-review helper as a deliberately out-of-scope follow-up rather than a
     silently-assumed non-issue.
3. **The Recycle Bin safety net is only as strong as its own retention window and who can empty
   it.** Framing this workload's deletion as "softer" than Exchange's is only true until the
   Recycle Bin's own retention period lapses, or until someone with Recycle Bin permissions empties
   it early.
   - **Resolution:** `README.md` §11 and `rollback.md` state the Recycle Bin recovery window as
     time-bounded, not permanent recourse; `rollback.md` Stage 4 tells the operator to act before
     that window expires rather than treating Recycle Bin placement as equivalent to safety.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Different audit operation name from the Exchange sibling.** `PriorityCleanupFileRecycled`
   (this workload) vs. `PriorityCleanupDelete` (Exchange) - a SOC that built a single detection
   rule off one sibling's operation name, assuming it covers "priority cleanup" generally, misses
   the other workload's events entirely.
   - **Resolution:** `README.md` §7 states the operation name explicitly and calls out that it
     differs from the Exchange sibling's; `validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1`
     prints the correct operation name for this workload rather than reusing the sibling's.
2. **`Enabled: $false` means something different here than in the Exchange sibling.** For Exchange,
   `Enabled: $false` signals a disabled/rolled-back policy. For this workload, it's also the
   **normal** state for most of a policy's early lifecycle (mandatory simulation). An operator or
   dashboard treating the raw `Enabled` flag identically across both sibling scenarios would
   misread a healthy, in-simulation SharePoint/OneDrive policy as broken.
   - **Resolution:** `validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1` prints an explicit
     note next to the Enabled/Mode line clarifying this is expected; `README.md` §7 states it too.
3. **No API-level visibility into the approval queue** - same hard platform limitation as the
   Exchange sibling.
   - **Resolution:** Disclosed, not glossed over - `README.md` §7/§11 and `design.md` §5 state
     plainly that this scenario's scripts stop at provisioning/validation.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **This is an ongoing-governance control, not a deploy-and-close incident response** - the
   opposite operational posture from the Exchange sibling. "Leave the shredder running" needs
   periodic review that the query and scope are still correct, not a one-time sign-off.
   - **Resolution:** `README.md` §8 and `design.md` §1 frame this explicitly as continual/standing,
     and §10 states the mandatory-resimulation-per-change cost as a recurring line item, not a
     one-time setup cost.
2. **The funding narrative here is cost-avoidance (storage reclaim), not risk-avoidance** - a
   different, and for many organizations an easier, argument than the Exchange sibling's incident-response
   framing.
   - **Resolution:** `README.md` §10 states this distinction directly rather than reusing the
     Exchange sibling's risk-reduction framing verbatim.
3. **Preservation Lock override strength must not be assumed equal to the Exchange sibling's.**
   A CISO who read the Exchange scenario first could wrongly assume this one also unconditionally
   defeats Preservation Lock.
   - **Resolution:** `README.md` §2's callout and §11 state the conditional (delete-only-only)
     override explicitly, with a direct citation, rather than leaving it implied by silence.
4. **Would I fund this?** Yes - the storage-reclamation case is concrete and the risk profile is
   genuinely lower than the Exchange sibling (Recycle Bin recovery window, conditional per-item
   approval only where holds exist). The CISO's real ask is a recurring calendar reminder to
   re-review the query/scope, not a one-time governance gate.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets, confirmed directly against a fresh fetch of both the feature
   documentation and the cmdlet reference pages during this build** - `-OneDriveLocation`/
   `-SharePointLocation` support under `New-RetentionCompliancePolicy`'s `-PriorityCleanup`-bearing
   parameter set, and the `ProgID:Media AND ProgID:Meeting` query, are both confirmed verbatim
   rather than inferred by analogy to the Exchange sibling.
2. **Two disclosed construction gaps, correctly flagged rather than glossed** - the carried-over
   `RetentionDuration`/`RetentionType` inference, and this scenario's own new single-stage
   `-MultiStageReviewProperty` construction (`design.md` §4). Neither is presented as confirmed.
3. **Right feature for the job, correctly differentiated from ordinary SharePoint/OneDrive
   retention policies** - this scenario is the override-existing-holds control, not a duplicate of
   standard auto-apply retention already covered elsewhere in this repo's Data Lifecycle Management
   scope.
4. **Accurate, shared licensing** - same E5-tier entitlement and the same tenant-wide feature
   toggle as the Exchange sibling, correctly stated as shared rather than duplicated per workload.
5. **No deprecated paths.** Both cited Microsoft Learn pages and all cited cmdlet references were
   fetched directly during this build, not carried over from a stale prior grounding pass.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (no per-item review for un-held content; unbounded query scope over time; Recycle Bin is time-bounded recourse, not permanent safety) | Closed |
| 🔵 Blue Team | Fix | 3 (different audit op name than Exchange sibling; `Enabled:$false` means something different here; no approval-queue API - disclosed, not hidden) | Closed |
| 🎩 CISO | Fix | 3 (continual-governance framing; cost-avoidance funding narrative; conditional Preservation Lock override); confirmed on funding recommendation | Closed |
| 🟦 Microsoft Product Owner | Fix | 2 (two construction gaps correctly flagged as VERIFY); confirmed correct on cmdlets, feature choice, and shared licensing | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-PriorityCleanupSharePointOneDrivePolicy.ps1`,
`deploy/Remove-PriorityCleanupSharePointOneDrivePolicy.ps1`,
`deploy/config/priority-cleanup-sharepoint-onedrive.sample.json`,
`validate/Test-PriorityCleanupSharePointOneDrivePolicy.ps1`, and `rollback.md`. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are grounded in
Microsoft Learn (no invented cmdlets - the two genuine construction gaps are disclosed as VERIFY,
not presented as confirmed), and this scenario's materially different approval model, mandatory
simulation, and softer (Recycle Bin) deletion mechanism are treated as first-class design
constraints throughout, not as a relabeled copy of the Exchange sibling.
