---
part: "rollback"
parent: "ediscovery/roster-to-hold-locations"
---
This scenario has two independent stages with two independent rollback stories, the same shape as
`teams-group-hold-resolution/rollback.md`.

## Stage 1 — Merge (always runs)

**Nothing to roll back on the tenant.** `Merge-RosterIntoHoldDefinition.ps1`'s default,
non-`-AddToHold` behavior only reads the roster CSV, the selection JSON, and the definition file,
then writes a merged copy. Neither the roster, the selection file, nor the original definition file
is ever modified in place unless `-InPlace` was explicitly used.

**Default (`-OutputPath`) run:**

```powershell
Remove-Item ./deploy/out/location-hold-definition.merged.json -ErrorAction SilentlyContinue
```

No further action — the original `-DefinitionPath` file was never touched.

**`-InPlace` run:** restore the pre-merge file from the backup this script wrote automatically
before overwriting:

```powershell
$backup = Get-ChildItem -Path "$DefinitionPath.bak-*" | Sort-Object Name -Descending | Select-Object -First 1
Copy-Item -Path $backup.FullName -Destination $DefinitionPath -Force
```

If no `.bak-*` file exists (a `-WhatIf` run, or the backup step itself was interrupted), the
original file's prior state must come from version control (`git checkout -- <DefinitionPath>`, if
it's a tracked file) or a separate backup outside this script's own mechanism.

## Stage 2 — `-AddToHold` (opt-in)

**This scenario does not ship its own removal script**, the same design as
`teams-group-hold-resolution/rollback.md`. `-AddToHold` calls the identical `ediscoveryHoldPolicy`
`userSources` `POST` endpoint the two sibling scenarios' own deploy scripts call — the objects it
creates are, from the API's perspective, indistinguishable from ones either sibling scenario
created directly. Releasing them is the `location-scoped-legal-hold` scenario's own rollback path:

```powershell
../location-scoped-legal-hold/deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
    -UserSourceEmail '<individually added member''s email>' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Repeat once per member this scenario added. **The same warnings apply as
`location-scoped-legal-hold/rollback.md`**: there is no v1.0 reversible "pause" for a `userSource`,
removal carries Microsoft's own documented risk of permanent deletion of content currently being
preserved, and a preservation duty should be confirmed lapsed with counsel before running this
against a matter that involved actual litigation or a regulatory inquiry. This scenario adds no new
risk here beyond what that rollback doc already documents — it only changed how the `userSource`
values were originally selected (from a curated roster subset instead of typed directly into a
definition file), not what removing them means.

## What rollback does **not** undo

- **The underlying roster or group.** This scenario never creates, modifies, or deletes a Team,
  Microsoft 365 Group, or any individual's mailbox — it only reads a roster CSV someone else
  produced and, optionally, references addresses from it in a hold. Removing the hold has zero
  effect on the group or its members.
- **The selection file's own history.** Deleting a merged output file removes that file, not any
  record of what selection produced it — this scenario never persists selection decisions anywhere
  beyond the `-SelectionPath` file itself and the `note` field it copies into the merged output;
  treat `-SelectionPath` files as records worth keeping (in version control, in a matter file) if
  the decision they represent needs a durable audit trail beyond this scenario's own outputs.

## Verification after rollback

Re-run `./validate/Test-RosterHoldDefinitionMerge.ps1 -RosterPath ... -SelectionPath ... -MergedDefinitionPath
... -CaseId $caseId -HoldId $holdId ...` after a Stage 2 release — the hold-reconciliation check
should report `FAIL` (userSource not found) for the released member, the expected post-rollback
state, not a validate-script bug. For a Stage 1-only rollback (no `-AddToHold` was ever used),
re-running the merge from the restored/deleted state simply reproduces the same result as a fresh
first run.

Reference: `location-scoped-legal-hold/rollback.md` (the removal procedure and permanent-deletion
warnings this stage's rollback fully inherits) — same file, this repo.
