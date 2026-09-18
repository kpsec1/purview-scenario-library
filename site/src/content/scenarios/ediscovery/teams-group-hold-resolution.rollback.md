---
part: "rollback"
parent: "ediscovery/teams-group-hold-resolution"
---
This scenario has two independent stages with two independent (and very different) rollback
stories.

## Stage 1, Resolve (always runs)

**Nothing to roll back on the tenant.** `Resolve-TeamsGroupHoldLocations.ps1`'s default,
non-`-AddToHold` behavior only reads Exchange Online directory state and writes two local files
(the resolved JSON fragment, and, if requested, the member roster CSV). Neither has any effect on
a live hold, case, mailbox, or site. To "roll back" Stage 1, delete the two output files:

```powershell
Remove-Item ./deploy/out/teams-group-hold-locations.resolved.json -ErrorAction SilentlyContinue
Remove-Item ./deploy/out/teams-group-hold-members.roster.csv -ErrorAction SilentlyContinue
```

## Stage 2, `-AddToHold` (opt-in)

**This scenario does not ship its own removal script.** `-AddToHold` calls the identical
`ediscoveryHoldPolicy` `userSources`/`siteSources` `POST` endpoints the sibling
`location-scoped-legal-hold` scenario's own `New-EdiscoveryLocationHold.ps1` calls (`design.md` §5)
, the objects this stage creates are, from the API's perspective, indistinguishable from ones the
sibling scenario's own deploy script created directly. Releasing them is therefore the sibling
scenario's own rollback path, not a duplicate implementation here:

```powershell
# Release the group's mailbox:
../location-scoped-legal-hold/deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
    -UserSourceEmail '<group PrimarySmtpAddress>' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Release the group's SharePoint site:
../location-scoped-legal-hold/deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
    -SiteSourceUrl '<group SharePointSiteUrl>' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

**The same warnings apply as the sibling scenario's own `rollback.md`**: there is no v1.0
reversible "pause" for either object, both removal paths carry Microsoft's own documented risk of
permanent deletion of content currently being preserved, and a preservation duty should be
confirmed lapsed with counsel before running either command against a matter that involved actual
litigation or a regulatory inquiry. This scenario adds no new risk here beyond what
`location-scoped-legal-hold/rollback.md` already documents, it only changed how the userSource/
siteSource values were originally *resolved* (from a Team/group name instead of typed directly into
a definition file), not what removing them means.

## What rollback does **not** undo

- **The group itself, its mailbox, or its SharePoint site.** This scenario never creates, modifies,
 or deletes a Team/Microsoft 365 Group, it only reads and, optionally, references its existing
 mailbox/site in a hold. Removing the hold has zero effect on the group.
- **Member-roster CSV history.** Deleting the CSV (Stage 1 rollback, above) removes the file, not
 any record of who was a member at resolution time, this scenario never persisted that anywhere
 else, and Microsoft's own audit trail for group-membership changes is a separate Entra/Exchange
 concern, not something this scenario's rollback touches.

## Verification after rollback

Re-run `./validate/Test-TeamsGroupHoldLocations.ps1 -DefinitionPath... -CaseId $caseId -HoldId
$holdId...` after a Stage 2 release, the hold-reconciliation check should report `FAIL` (location
not found) for the released group, the expected post-rollback state, not a validate-script bug. The
group-drift check (Stage 1's own concern) is unaffected by a Stage 2 release and will continue to
pass as long as the group itself still resolves normally.

Reference: `location-scoped-legal-hold/rollback.md` (the removal procedure and permanent-deletion
warnings this stage's rollback fully inherits), same file, this repo.
