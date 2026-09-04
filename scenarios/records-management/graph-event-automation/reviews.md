# Four-Lens Review — Event Automation via Microsoft Graph

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A runaway integration firing broad events.** An automated trigger is more dangerous than a human
   one: a bug that fires an event with no `eventQuery` starts irreversible retention across **all**
   content carrying the event type's label.
   - **Resolution:** The sample config ships an `eventQuery` (Asset ID) and the deploy prints a **red
     CAUTION** when firing with no query; `README.md` §8/§11 and `design.md` §6 make precise scoping the
     dominant control.
2. **Accidental clock start on a routine run.** The event type is ensured on every integration run — the
   fire must not ride along.
   - **Resolution:** Firing is **double-gated** (`-FireEvent` **and** `event.fire=true`) **and** goes
     through `ShouldProcess`, so `-WhatIf` fires nothing; the default run only ensures the event type.
3. **Over-privileged, long-lived app identity.** `RecordsManagement.ReadWrite.All` app-only can start
   irreversible retention; a leaked credential is a records-integrity risk.
   - **Resolution:** `README.md` §8/§11 flag it as high-privilege, recommend certificate app-only and
     monitoring, and treat the identity as a governed records actor.
4. **"Delete the event to undo it."** An operator assuming deletion cancels retention.
   - **Resolution:** `rollback.md` opens with, and `README.md` §9/§11 repeat, that deletion is
     bookkeeping only and never stops retention.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **"Did the event actually land?"** Propagation is async and per-workload; a fired event may not have
   reached SharePoint/Exchange yet.
   - **Resolution:** Both the deploy and validate report `eventStatus` and `eventPropagationResults` per
     workload — the Graph-native signal the PowerShell path lacks; `README.md` §7/§8 make it the KPI.
2. **Paging over collections.** Event types/events are collections; a naive single GET can miss items.
   - **Resolution:** A shared `Get-AllGraphValues` helper follows `@odata.nextLink` in the deploy,
     remove, and validate scripts.
3. **Real dry-run.** Operators need to see exactly what will be POSTed before an irreversible fire.
   - **Resolution:** `SupportsShouldProcess` + `ConfirmImpact = High`; `-WhatIf` prints the intended
     event type / event and creates nothing; `README.md` §5 makes it step 1.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Auditable, reproducible triggering.** Regulators ask how retention starts and whether it's applied
   consistently — a human clicking in a portal is neither reproducible nor evidenced at volume.
   - **Resolution:** The config is the versioned trigger definition; `README.md` §2 frames automated,
     scoped, logged triggering as the audit-defensible path, and §8 ties event count to business-event
     count as a control.
2. **Risk vs. cost:** honestly stated in §10 — E5 entitlement (no meter), no per-API charge; the real
   cost is integration engineering and the storage of records held once events fire.
3. **Board/compliance narrative:** "our records schedule fires automatically and precisely from the
   systems of record, over Microsoft's supported API, with per-workload confirmation" — a strong
   position.
4. **Change management:** the firing identity is high-privilege and irreversible in effect, so it's
   treated as a governed records actor (cert app-only, monitored, least-privilege scope).
5. **Would I fund this?** Yes — it's what turns an event-based schedule from a manual aspiration into an
   operational, evidenced control.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current API and cmdlets.** `POST /security/triggerTypes/retentionEventTypes`,
   `POST /security/triggers/retentionEvents` with `eventQuery` (queryType `files`/`messages`),
   `eventTriggerDateTime`, and `retentionEventType@odata.bind` are reproduced from Microsoft's v1.0
   reference; the equivalent typed cmdlets (`New-MgSecurityTriggerTypeRetentionEventType`,
   `New-MgSecurityTriggerRetentionEvent`) and `RecordsManagement.ReadWrite.All` permission were verified.
2. **Supported path.** Uses Microsoft Graph — Microsoft marks the older REST event API deprecated —
   which is the current-best-practice automation surface.
3. **Honest about doc quirks.** The `@odata.bind` singular/plural inconsistency and the
   `eventQuery`/`eventQueries` naming difference are flagged (`README.md` §11) rather than silently
   guessed — no invented parameters.
4. **Accurate behavior.** ≤7-day sync, can't-cancel semantics, and per-workload `eventPropagationResults`
   are stated per the docs.
5. **Not reinventing.** Complements — doesn't duplicate — the PowerShell scenario; label/policy
   definition stays in the records solution.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (scoped events + caution; double-gated + ShouldProcess fire; high-privilege app identity; deletion-isn't-undo) | Closed |
| 🔵 Blue Team | Fix | 3 (per-workload propagation reporting; nextLink paging; real `-WhatIf`) | Closed |
| 🎩 CISO | Fix | 1 (auditable automated triggering); Pass on cost/narrative/change-mgmt | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (doc quirks flagged); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-GraphRetentionEvent.ps1`, `deploy/Remove-GraphRetentionEvent.ps1`,
`deploy/config/graph-event-automation.sample.json`, and `validate/Test-GraphRetentionEvent.ps1`. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are
grounded in Microsoft Learn (no invented cmdlets — the Graph endpoints, `eventQuery` shape,
`@odata.bind` binding, permission, and typed cmdlet names were verified) and the irreversibility of a
fired event is treated as a first-class safety constraint.
