---
part: "rollback"
parent: "data-lifecycle-management/adaptive-protection-deleted-content-preservation"
---
## ⚠️ Read first: this scenario's code has nothing to roll back

`deploy/Export-AdaptiveProtectionPreservationEvidence.ps1` and `validate/
Test-AdaptiveProtectionDlmPreservation.ps1` are both **read-only** against the tenant, the only
artifact either one produces is a local CSV file. There is no policy, label, or Graph object this
scenario's code creates. **Rolling back means turning off the underlying Microsoft control itself,
which is a portal-only action**, see `design.md` §2/§4 and `README.md` §5.

## Turning off the control

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com/) as a user with
   Adaptive Protection configuration permissions (**Insider Risk Management** or **Insider Risk
   Management Admins** role group, `docs/rbac-model.md` §4) [[1]](#references).
2. Go to **Solutions** → **Settings** → **Solution settings** → **Data lifecycle management** →
   **Adaptive protection**.
3. Turn **"Adaptive protection in Data Lifecycle Management"** off, confirm the choice, and select
   **Save** [[2]](#references).

## ⚠️ What turning it off actually does, read before doing this

Microsoft states this explicitly: **"Any retention labels that were applied as a result of
Adaptive Protection are removed so that the items can then become eligible for permanent
deletion"** [[2]](#references). This is materially different from every other rollback in this
library:

- It is **not** a pause. There is no "disable auto-apply, keep existing labels" middle state like
  `scenarios/data-lifecycle-management/retention-labels-financial-records/rollback.md` Stage 1, 
  turning this setting off immediately releases the retention label from **every item currently
  under it**, tenant-wide, not just future deletions.
- Content released this way had **no other retention or hold** protecting it (that was the entire
  point of the control), once released, it is eligible for the workload's normal permanent-
  deletion timeline. If any preserved item is still relevant to an open investigation, case, or
  legal hold, **secure it independently first** (a dedicated eDiscovery hold, or a Microsoft
  Support restore request per `README.md` §9) before turning the setting off.
- The setting "isn't enabled again unless you turn it back on" [[1]](#references), turning it
  back on later does **not** retroactively restore items already released by the earlier turn-off;
  it only re-arms the control for future Elevated-risk deletions.

**Who can do this:** whoever holds the **Insider Risk Management** or **Insider Risk Management
Admins** Purview role group (`README.md` §3/§11). Keep that membership minimal and reviewed, a
person in scope for Adaptive Protection monitoring who also holds one of these roles could disable
proactive preservation to destroy evidence of their own activity, and this action is not known to
be captured anywhere this library's own audit-evidence script can query (`README.md` §11).

**Recommended sequence, if you must turn this off:**

1. Run `deploy/Export-AdaptiveProtectionPreservationEvidence.ps1` first, tenant-wide, with a
   120-day `-StartDate` (the control's full preservation window), capture a final snapshot of
   what's currently preserved and by whom, before any of it is released.
2. Review that CSV against any open Insider Risk Management cases or investigations. For anything
   still relevant, place an independent hold (eDiscovery, or a manual retention label) or start
   the Microsoft Support restore request **before** step 3.
3. Only then perform the portal steps above.
4. Run `validate/Test-AdaptiveProtectionDlmPreservation.ps1 -LookbackDays 1` afterward, expect it
   to report `[INCONCLUSIVE]` (no new preservation events, since the control is now off), never
   `[PASS]` or `[FAIL]` (see `README.md` §7 for why this script never asserts a definitive on/off
   status).

## What rollback does **not** undo

- **Content already permanently deleted** in the normal course of a workload's own deletion
  timeline after this control released it, unrecoverable, by design of the underlying workload,
  not this scenario.
- **The audit trail.** `Search-UnifiedAuditLog` records for `SharePointDataProactivelyPreserved`/
  `ExchangeDataProactivelyPreserved` events that already fired remain in the audit log for its own
  retention period (subject to your tenant's Audit Standard/Premium retention tier, `deploy/
  Export-AdaptiveProtectionPreservationEvidence.ps1`'s own `.NOTES`) regardless of the control's
  current on/off state.
- **Any Microsoft Support restore already completed** for content this control previously
  preserved, that content is wherever Support placed it, independent of the toggle's current
  state.

## References

1. Help dynamically mitigate risks with Adaptive Protection, <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
2. Learn about retention policies and retention labels, "Dynamically mitigate the risk of
   accidental or malicious deletes" (exact turn-off steps and consequence), <https://learn.microsoft.com/purview/retention#retention-policies-and-retention-labels>
