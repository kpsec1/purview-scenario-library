---
part: "rollback"
parent: "ediscovery/teams-purge-hold-lifecycle-management"
---
This scenario's own **Restore** stage (`deploy/Restore-TeamsPurgeMailboxHolds.ps1`) already *is* the
rollback for the state changes it makes — running it is not an optional cleanup step but part of the
scenario's normal sequence (README.md §5 Stage 6). What follows covers what to do if Restore itself
needs to be undone, re-run, or if the incident's records should be cleaned up afterward.

## Recommended sequence

### Stage 1 — Re-run Restore if it didn't complete cleanly

`Restore-TeamsPurgeMailboxHolds.ps1` is safe to re-run: it checks each mailbox's current state before
issuing an Add/Remove call and skips anything already in its target state (README.md §7). If a prior
run failed partway (connection drop, a policy renamed mid-incident), simply re-run it against the same
`-StatePath` file — it will pick up wherever it left off rather than duplicating already-applied
changes.

```powershell
./deploy/Restore-TeamsPurgeMailboxHolds.ps1 -StatePath ./hold-removal-state-2026-014.json
./validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1 -StatePath ./hold-removal-state-2026-014.json
```

### Stage 2 — If a hold was removed and should NOT have been (undo before Restore's normal path)

Because `Remove-TeamsPurgeMailboxHolds.ps1` re-identifies fresh and records only what it actually
changed, the fastest "undo" for a mistaken removal is simply running `Restore-
TeamsPurgeMailboxHolds.ps1` against the `-StatePath` file that removal run produced — there is no
separate reversal mechanism to learn. If the state file itself was lost or never written, fall back to
Microsoft's own manual procedure (README.md §5 "Portal reference") using whatever hold/policy-name
record your incident ticket carries.

### Stage 3 — What cannot be undone by this scenario

- **A `-IncludeComplianceTagHold` clear.** Once `ComplianceTagHoldApplied` is cleared, no documented
  cmdlet sets it back to `True` (design.md §5). If this was done in error, the only path forward is
  re-labeling the affected content so the property naturally re-sets itself, or accepting the mailbox
  no longer carries this specific hold signal — there is no scripted or portal "undo" for this one
  property.
- **A delay hold's own 30-day timer.** This scenario can clear a *pre-existing* delay hold
  (`-RemoveDelayHoldApplied`/`-RemoveDelayReleaseHoldApplied`), but cannot prevent the Managed Folder
  Assistant from applying a *new* one after this scenario's own removal — that's system-scheduled, not
  reversible on demand (design.md §5).
- **Anything this scenario never touched.** eDiscovery case holds and legacy In-Place Holds were never
  removed by this scenario in the first place (design.md §6), so there is nothing to roll back for
  them here — any change to those was made manually, outside this scenario's scripts, and must be
  reversed the same way.

### Stage 4 — Clean up state files (optional, incident-closure only)

```powershell
Remove-Item ./hold-removal-state-2026-014.json
```

The `-StatePath` JSON contains mailbox addresses and retention-policy names — treat it as sensitive
for the life of the incident, the same guidance this repo's sibling scenario gives its own search
definition file (`search-and-purge-teams-messages/rollback.md` Stage 2). Not required — keeping it has
no ongoing cost and can help a later audit confirm exactly what was changed and restored.

## What this rollback cannot do

- **Reverse a `ComplianceTagHoldApplied` clear.** See Stage 3 — no cmdlet exists for this.
- **Guarantee a restored hold has actually finished re-synchronizing tenant-wide.** Microsoft documents
  up to a 24-hour synchronization window for the org-wide-exclusion path specifically
  (`README.md` §11); `validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1` reports current observed state,
  which may lag the true target state shortly after a Restore run.
- **Undo anything the sibling `search-and-purge-teams-messages` scenario's own purge already did.**
  That scenario's own `rollback.md` covers its irreversible-purge limitations; this scenario's rollback
  is scoped entirely to hold state, not message content.
