---
part: "rollback"
parent: "ediscovery/search-and-purge-data-spillage"
---
Unlike most rollback docs in this repo, there is no "undo the purge" stage, a purge is the
scenario's entire purpose, and Microsoft states plainly that a purged message can't be restored by
this scenario, the user, an admin, or Microsoft once the applicable recovery window has elapsed
(§9 of README.md). What follows is staged by how much can still be reversed, least-disruptive first.

## Recommended sequence

### Stage 1, Recover a `Recoverable`-purged item (end-user or admin action, time-limited)

A `-PurgeType Recoverable` purge moves the item to the mailbox's **Recoverable Items > Deletions**
folder. Until the mailbox's deleted-item retention period expires:

- **The end user** can recover it themselves: Outlook → Deleted Items → **Recover Items Recently
  Removed From This Folder**.
- **An admin** can restore it via `New-MailboxRestoreRequest` targeting the Recoverable Items
  folder, or (for a single item) an eDiscovery search scoped to that folder plus an export, this
  scenario's own scripts don't automate that restore path, since restoring a spillage message
  defeats the containment purpose in nearly every real incident; if a restore is genuinely needed
  (for example, the purge matched an over-broad query and caught a legitimate message), do it
  through the standard Exchange Online restore tooling, not by re-running this scenario's scripts.

This is the **only** recoverable stage. It stops being available once the deleted-item retention
period expires (the item then moves to the Purges folder and is gone) or if `-PurgeType
PermanentlyDelete` was used (Stage 1 never applies, see the warning in README.md §2).

### Stage 2, Delete the search (removes the query record, not the purge's effect)

```powershell
Remove-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $caseId -EdiscoverySearchId $searchId
```

Removes the search definition from the case. If the `contentQuery` itself contained spilled data
(a distinctive phrase from the leaked document, per the sample config's own `_comment`), deleting
the search is the recommended step once the incident is closed, matching the retired walkthrough's
own "delete the search query to prevent further data spillage" guidance (`design.md` §1, source 1).
This has no effect on items already purged.

### Stage 3, Close or delete the case (case-record retention decision, not a content rollback)

```powershell
# Close: case record remains, reopenable later via the Purview portal case Actions menu.
Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId -BodyParameter @{ status = 'closed' }

# Delete: permanently removes the case and its search/operation history. No "undo."
Remove-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId
```

Closing preserves the case's audit value (what was searched, what was purged, when) for later
reference, the recommended default once an incident is resolved. Deleting is appropriate only once
your organization's own incident-record retention requirement for this case has been satisfied;
there is no reference to `Remove-MgSecurityCaseEdiscoveryCase` elsewhere in this scenario's deploy
scripts, since case deletion is a deliberate, rare, end-of-lifecycle action, not part of the normal
search-and-purge workflow.

## What this rollback cannot do

- **Restore a `PermanentlyDelete` purge.** There is no stage for this, it is irreversible by
  design, the same way `priority-cleanup-exchange-data-spillage`'s permanent deletion is.
- **Restore a `Recoverable` purge after the deleted-item retention period expires.** Once the item
  reaches the Purges folder, it follows the same "gone" path as a hard delete.
- **Tell you whether a specific purge run needs to be reversed at all.** That is an incident-response
  judgment call (was the query over-broad? did it catch a legitimate message?) this scenario's
  scripts cannot make for you, review the purge job report (`reportFileMetadata`, printed by
  `Invoke-DataSpillagePurge.ps1`) before deciding.
