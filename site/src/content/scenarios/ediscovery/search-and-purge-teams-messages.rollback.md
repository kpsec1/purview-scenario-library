---
part: "rollback"
parent: "ediscovery/search-and-purge-teams-messages"
---
There is **no recovery stage for a purged Teams message**, the single biggest difference from this
repo's `search-and-purge-data-spillage` (mailbox) sibling. That sibling's `-PurgeType Recoverable`
gives an end user a real recovery window via Outlook's Recover Deleted Items. Teams has no equivalent:
Microsoft's own Graph reference states that **either** `purgeType` value permanently deletes the
Teams user-visible message on success (README.md §2). Once a purge operation reaches `succeeded`,
this scenario's scripts, and Microsoft, cannot restore the message. What follows is staged by what
*is* still reversible: process state, not content.

## Recommended sequence

### Stage 1, Reapply any hold or retention policy removed before the purge

This is the most time-sensitive rollback-adjacent action in this scenario, and it is **not**
optional even though it doesn't restore anything already deleted:

- If a hold or retention policy was removed from a target mailbox to allow the purge to proceed
  (README.md §5 step 3), **reapply it immediately** after the purge completes and is validated.
  Leaving it off is a preservation-duty gap for that mailbox's other content, not just the purged
  message.
- Microsoft notes that reapplying a hold **within 24 hours** of the purge can preserve the
  **compliance copy** (not the already-deleted user copy) from the background deletion job that
  would otherwise remove it in 1-7 days (README.md §6), a reason to treat this step as urgent, not
  a background chore.

This scenario's scripts do not automate hold removal or reapplication (`design.md` §3 goal 5); track
which holds you removed and confirm each is back in place using your organization's standard hold
management tooling.

### Stage 2, Delete the search (removes the query record, not the purge's effect)

```powershell
Remove-MgSecurityCaseEdiscoveryCaseSearch -EdiscoveryCaseId $caseId -EdiscoverySearchId $searchId
```

Removes the search definition from the case. If the `contentQuery` itself contained sensitive
keywords drawn from the incident, delete the search once the incident is closed, the same guidance
as the mailbox sibling's `rollback.md` Stage 2. Has no effect on messages already purged.

### Stage 3, Remove the target-mailbox non-custodial sources (optional cleanup)

```powershell
Remove-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource -EdiscoveryCaseId $caseId -EdiscoveryNoncustodialDataSourceId $sourceId
```

Case-level cleanup once the incident record no longer needs the resolved target-mailbox list
preserved. Not required, leaving these in place has no ongoing cost or effect, and keeping them can
help a later audit confirm exactly which mailboxes were in scope.

### Stage 4, Close or delete the case

```powershell
# Close: case record remains, reopenable later via the Purview portal case Actions menu.
Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId -BodyParameter @{ status = 'closed' }

# Delete: permanently removes the case and its search/operation history. No "undo."
Remove-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId
```

Closing preserves the case's audit value (what was searched, what mailboxes were targeted, what was
purged, when), the recommended default. Delete only once your incident-record retention requirement
for this case has been satisfied.

## What this rollback cannot do

- **Restore a purged Teams message.** There is no stage for this, for either `-PurgeType` value, it
  is irreversible by design once the purge operation succeeds (README.md §2, `design.md` §7).
- **Confirm a hold was reapplied correctly.** That is a manual verification against your hold
  management tooling; this scenario's validation script cannot check hold state (README.md §11).
- **Tell you whether a specific purge run needs to be reversed at all.** Review the purge job report
  (`reportFileMetadata`, printed by `Invoke-TeamsMessagePurge.ps1`) and the Teams client tombstone
  before deciding a purge was scoped incorrectly, by then, the message itself is already gone.
