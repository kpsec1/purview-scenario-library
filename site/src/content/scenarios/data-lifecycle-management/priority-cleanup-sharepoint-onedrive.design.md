---
part: "design"
parent: "data-lifecycle-management/priority-cleanup-sharepoint-onedrive"
---
## 1. Problem statement

Microsoft Teams meeting recordings and transcripts, kept for Copilot recap, accumulate in OneDrive
(most recordings) and SharePoint (channel-meeting recordings) and are typically low-value after
1-3 months, but a retention policy can keep them far longer, growing storage cost with no
compensating benefit. A second, related use case: when an employee leaves, items
in their OneDrive's Preservation Hold library with an unexpired retention period block deletion of
the entire OneDrive site. Microsoft Purview's **Priority cleanup** feature
(Data Lifecycle Management), already built for Exchange in this repo's
`priority-cleanup-exchange-data-spillage` sibling, also covers this workload, but with a
materially different approver model, mandatory simulation, and a softer deletion mechanism
(Recycle Bin, not instant permanent delete). This scenario builds that SharePoint/OneDrive variant
as code.

## 2. Design goals

Same five goals as the Exchange sibling (script the real documented mechanism; never deploy live
by accident; be honest about where the paper trail ends; disclose every judgment call; match the
irreversibility, or, here, the **lack** of full irreversibility, with the guardrail). This
scenario additionally must **not** silently reuse the Exchange sibling's approval/deploy shape
where Microsoft's own documentation shows the two workloads differ.

## 3. Why this is a separate fragment, not a copy-paste of the Exchange scenario

Microsoft documents priority cleanup as materially different per workload
:

| | Exchange (built) | SharePoint/OneDrive (this fragment) |
|---|---|---|
| Typical use | Data spillage / compliance deletion (**rare**) | Stale Teams recordings (**continual**); Preservation Hold library cleanup (**per departure**) |
| Two-person rule | A second Priority Cleanup Admin reviews items **after** the policy is turned on (a Pending Cleanups stage) | A second Priority Cleanup Admin reviews simulation and turns the policy on **before** any item is identified, not a Pending Cleanups stage |
| Approvers | Priority cleanup admin + retention manager + eDiscovery admin (3 stages, always) | eDiscovery admin only, and **only if** the item is under an eDiscovery hold (0 or 1 stage) |
| Simulation | Recommended, not required | **Required**, to initially set up, and again for any change other than the description |
| Deletion mechanism | Instant, permanent | Second-stage **Recycle Bin**, same timers as an ordinary delete |
| Overrides Preservation Lock | Yes, unconditionally | Only if the policy is configured delete-only |
| Location parameter | `-ExchangeLocation` | `-OneDriveLocation` / `-SharePointLocation` |

Given these differences touch the approval model, the deploy script's required flags, the
validation script's "healthy" baseline state, and the rollback story, this fragment could not have
been a parameterized copy of the Exchange sibling, each of those four areas needed independent
design decisions, tracked below.

## 4. Object model and the construction choices carried over or newly made

```mermaid
sequenceDiagram
    participant Script as New-PriorityCleanupSharePointOneDrivePolicy.ps1
    participant SCC as Security & Compliance PowerShell

    Script->>SCC: Get-ComplianceTag -PriorityCleanup (label exists?)
    alt not found
        Script->>SCC: New-ComplianceTag -PriorityCleanup -RetentionAction Delete<br/>-RetentionDuration 0 -RetentionType TaggedAgeInDays<br/>-MultiStageReviewProperty '{1-stage JSON: EDiscoveryAdmin}'
    end
    Script->>SCC: Get-RetentionCompliancePolicy -PriorityCleanup (policy exists?)
    alt not found
        Script->>SCC: New-RetentionCompliancePolicy -PriorityCleanup -IsSimulation<br/>-OneDriveLocation/-SharePointLocation <locations>
    end
    Script->>SCC: Get-RetentionComplianceRule -PriorityCleanup -Policy (rule exists?)
    alt not found
        Script->>SCC: New-RetentionComplianceRule -PriorityCleanup<br/>-ApplyComplianceTag <label> -ContentMatchQuery 'ProgID:Media AND ProgID:Meeting'
    end
    Script->>SCC: Set-RetentionCompliancePolicy -StartSimulation $true
    Note over SCC: simulation results (up to ~2 hours); a SECOND, DIFFERENT admin reviews them<br/>in the portal, then runs -EnforceSimulationPolicy $true to turn the policy ON.<br/>Conditional eDiscovery-admin approval happens in the PORTAL ONLY (Pending cleanups)<br/>- no documented approval cmdlet exists.
```

Two places this scenario had to construct something, one carried over from the Exchange sibling and
one genuinely new, both flagged inline (deploy script `.NOTES`, config `_labelNote`, `README.md`
§11) rather than guessed silently:

- **`RetentionDuration`/`RetentionType` for "delete as soon as possible", carried over.** Same
 inference as the Exchange sibling (`RetentionDuration 0`, `RetentionType TaggedAgeInDays`), for
 the same reason: the cmdlet reference doesn't publish the literal value ASAP maps to, and no
 worked example is specific to priority cleanup for either workload. Still VERIFY, still open.
- **`-MultiStageReviewProperty` stage count, a new, different construction.** The Exchange
 sibling used three stages (`PriorityCleanupAdmin`/`RetentionManager`/`EDiscoveryAdmin`) because
 Microsoft's prose names three roles that approve **after** turn-on. For SharePoint/OneDrive,
 Microsoft's prose names only **one** role that approves after turn-on (eDiscovery admin,
 conditionally), the "second Priority Cleanup Admin" requirement is satisfied differently, by a
 pre-turn-on simulation review and turn-on step that this scenario's scripts model as a *separate
 invocation* (`-EnforceSimulation`, gated on operator discipline), not as a label-level review
 stage. This scenario's `-MultiStageReviewProperty` therefore carries **one** stage
 (`EDiscoveryAdmin`) rather than the sibling's three. Whether the underlying service also expects
 (or silently ignores, or requires) a `PriorityCleanupAdmin` stage entry in that same JSON for its
 own bookkeeping is **not confirmed** by any Microsoft worked example specific to priority cleanup
 for this workload, this scenario's own open construction gap, distinct from the one it inherited.
 Failure mode if wrong in the "missing a required stage" direction: per the Exchange sibling's
 confirmed behavior for its own stage set, an incorrect approver-role mapping surfaces as a loud,
 synchronous policy-creation failure, not a silent misconfiguration, so this
 scenario's single-stage construction is expected to fail loudly at deploy time if it's wrong,
 the same safety property the Exchange sibling relies on.

## 5. Idempotency and safety posture

Idempotency is **create-or-report**, identical in mechanism to the Exchange sibling: each object is
located via the official `-PriorityCleanup` filter switch and, if present, reported rather than
mutated. The deploy script's safety posture is **stricter** than the Exchange sibling's in one
respect: there is no `-Enabled` flag at all (Exchange's script accepts `-Simulate` **or**
`-Enabled`; this script accepts only `-Simulate`), because Microsoft documents simulation as
mandatory, not optional, for this workload's initial setup. `-EnforceSimulation` remains a
separate, deliberate invocation gated on a second, different admin having reviewed simulation
results in the portal, this script cannot review or export those results itself (no documented
API), and cannot verify "different admin" itself either (no documented "last editor" API).
Rollback disables/deletes the policy but never force-removes the label; unlike the Exchange
sibling's rollback, items already moved to the Recycle Bin by a completed approval **can** still be
recovered from there within its own retention window, a materially softer rollback story, stated
plainly in `rollback.md` rather than glossed as identical to the Exchange sibling's "cannot be
undone" framing.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Workload | SharePoint/OneDrive, stale Teams recordings (primary), Preservation Hold library cleanup (secondary, same mechanism, different scope) | Microsoft's own lead use cases; distinct from the Exchange sibling's rare/incident-driven framing |
| Scope | Static `-OneDriveLocation All` + named SharePoint site(s) | Matches "continual, tenant-wide" framing for the primary use case; adaptive scopes are a follow-up, same non-goal as the Exchange sibling |
| Query | `ProgID:Media AND ProgID:Meeting` (verbatim Microsoft worked example) | No construction needed, stronger grounding than the Exchange sibling's own hand-built query |
| Deploy default | `-Simulate` only (no `-Enabled`); refuses without `-Simulate` or `-DryRun` | Mirrors Microsoft's documented mandatory-simulation requirement for this workload specifically |
| Approver encoding | `-MultiStageReviewProperty`, 1 stage (`EDiscoveryAdmin`) | Matches the one documented post-turn-on approval role for this workload; explicitly flagged as this scenario's own construction, distinct from the Exchange sibling's 3-stage shape |
| "Delete ASAP" mapping | `RetentionDuration 0`, `RetentionType TaggedAgeInDays` | Carried over from the Exchange sibling's inference; still VERIFY |
| Idempotency | Create-or-report via `-PriorityCleanup` filtered `Get-*` | Same pattern as the Exchange sibling |
| Approval execution | Not scripted | No documented PowerShell/Graph cmdlet exists for the "Pending cleanups" approval queue, same gap as the Exchange sibling |
| Rollback | Disable/delete policy; never force-remove label; states Recycle-Bin recovery is possible (softer than the Exchange sibling) | Matches the workload's actual, less-irreversible deletion mechanism |

## 7. Non-goals

- **Permanent deletion sub-feature** (bypasses the Recycle Bin; public preview from 2026-08-24), 
 a distinct capability with its own approval model and irreversibility profile; built as its own
 sibling scenario, `scenarios/data-lifecycle-management/priority-cleanup-permanent-deletion/`.
- **Adaptive-scope targeting**, this scenario is static-scope only, same non-goal as the Exchange
 sibling.
- **Scripting the approval workflow itself**, no documented API exists; portal-only by design.
- **Tenant-wide on/off toggle automation**, shared gap with the Exchange sibling; the toggle
 itself is also shared between both workloads, so this is genuinely the same open item, not a
 duplicate one.
- **Scripting a scheduled query-date-rolling helper** for the "no age filter in KeyQL" gap
 identified in `README.md` §8, a real operational need, but a distinct fragment (a small
 scheduled-task script that edits/re-simulates the rule on a cadence) rather than something to
 bolt onto this deploy script's one-shot create-or-report model.

## References

See `README.md` §12 for the full, numbered source list shared with this file.
