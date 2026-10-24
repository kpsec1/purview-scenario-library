---
part: "runbook"
parent: "ediscovery/roster-to-hold-locations"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

There is no dedicated portal equivalent for this specific hand-off - the portal's own **Create a
hold** → **Manage data sources** flow lets an operator add an individual custodian's mailbox
directly by typing their name/address, which is exactly what this script
automates from a roster + selection file instead of manual entry. Use the portal path for a single
one-off addition; use this script when the addition needs to be reproducible, auditable (the
`-SelectionPath` `reason` field), or applied consistently across more than one matter.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Produce the roster (if not already done -- see teams-group-hold-resolution).
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
../teams-group-hold-resolution/deploy/Resolve-TeamsGroupHoldLocations.ps1 `
    -DefinitionPath ../teams-group-hold-resolution/deploy/config/teams-group-hold-resolution.sample.json `
    -ResolveMembers

# 2. Author the selection file recording which roster members counsel identified, and why
# (see deploy/config/roster-selection.sample.json).

# 3. Dry-run the merge -- reports what would change, writes nothing.
./deploy/Merge-RosterIntoHoldDefinition.ps1 `
    -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
    -SelectionPath ./deploy/config/roster-selection.sample.json `
    -DefinitionPath ../location-scoped-legal-hold/deploy/policy/location-hold-definition.json `
    -WhatIf

# 4. Merge for real -- writes deploy/out/location-hold-definition.merged.json (gitignored).
./deploy/Merge-RosterIntoHoldDefinition.ps1 `
    -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
    -SelectionPath ./deploy/config/roster-selection.sample.json `
    -DefinitionPath ../location-scoped-legal-hold/deploy/policy/location-hold-definition.json

# 5a. Feed the merged file into location-scoped-legal-hold's own deploy script -- OR --
../location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1 `
    -DefinitionPath ./deploy/out/location-hold-definition.merged.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 5b. -- or reconcile directly onto an already-existing hold policy in one step:
./deploy/Merge-RosterIntoHoldDefinition.ps1 `
    -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
    -SelectionPath ./deploy/config/roster-selection.sample.json `
    -DefinitionPath ../location-scoped-legal-hold/deploy/policy/location-hold-definition.json `
    -AddToHold -CaseId $caseId -HoldId $holdId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf
# then re-run without -WhatIf once the plan looks right.

# 6. Validate.
./validate/Test-RosterHoldDefinitionMerge.ps1 `
    -RosterPath ../teams-group-hold-resolution/deploy/out/teams-group-hold-members.roster.csv `
    -SelectionPath ./deploy/config/roster-selection.sample.json `
    -MergedDefinitionPath ./deploy/out/location-hold-definition.merged.json `
    -CaseId $caseId -HoldId $holdId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

## Configuration reference

| Field (`deploy/config/roster-selection.sample.json`) | Meaning |
|---|---|
| `reason` | Free-text record of why these members were selected (matter/counsel decision) - carried into each merged `userSource`'s `note` field for audit purposes |
| `selectedEmails[]` | Exact SMTP addresses to add as individual `userSources[]`. Every entry must exist in `-RosterPath`'s `MemberPrimarySmtpAddress` column - the script throws on any that don't |

| Parameter | Effect |
|---|---|
| `-OutputPath` | Where the merged definition file is written. Defaults to a gitignored `deploy/out/<name>.merged.json` |
| `-InPlace` | Overwrite `-DefinitionPath` directly instead of `-OutputPath`; first writes a `.bak-<yyyyMMddHHmmss>` backup alongside it |
| `-AddToHold` + `-CaseId`/`-HoldId` | Also reconcile newly merged members directly onto a live hold policy (requires Graph auth parameters) |

| Output object | Written by | Shape |
|---|---|---|
| Merged definition file | `Merge-RosterIntoHoldDefinition.ps1` (Stage 1, always) | Same shape as `location-scoped-legal-hold/deploy/policy/location-hold-definition.json`, with new `userSources[]` entries appended: `{ "email": "...", "note": "Individual member of '<Group>' (<Name>) added via roster-to-hold-locations/deploy/Merge-RosterIntoHoldDefinition.ps1. Reason: <reason>" }` |

Graph endpoint used by `-AddToHold` (identical to both sibling scenarios' own - full grounding
there): `POST .../legalHolds/{id}/userSources`.

## Operations and tuning

**KPIs to watch:**
- **A roster/selection pair that has drifted apart** - if `-RosterPath` is re-generated (a group's
  membership changed) after a `-SelectionPath` was authored against an older roster, re-run
  `validate/Test-RosterHoldDefinitionMerge.ps1`'s traceability check before re-running the merge;
  a selected email that no longer appears in a refreshed roster is a signal to confirm with counsel
  whether that person is still relevant, not to silently drop or silently keep them.
- **An `-InPlace` run's `.bak-*` files accumulating** - these are plain local backups with no
  automatic cleanup; prune them like any other local working file once a matter's holds are
  confirmed stable.

**Review cadence:** re-run `validate/Test-RosterHoldDefinitionMerge.ps1` on the same cadence as
*Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)*'s own hold-status checks (at least weekly for the life of the matter),
since this scenario's output feeds directly into that hold.

**What this scenario deliberately does not monitor:** current group membership (no live
`Get-UnifiedGroupLinks` re-check - the design notes), and any location type other than a mailbox
`userSource` (no `siteSource`, no OneDrive).

## Rollback and decommission

See the rollback runbook. Quick reference: Stage 1 (the merge itself) has no tenant-side effect - its
output is a plain file; delete it, or restore an `-InPlace` run's `.bak-*` copy, with no further
action. If `-AddToHold` was used, releasing an individually added member's mailbox from the hold is
`location-scoped-legal-hold/deploy/Remove-EdiscoveryLocationHold.ps1 -UserSourceEmail`, not a script
this scenario ships separately - see the rollback runbook for why.

## References

1. Create holds in eDiscovery - "Create a hold" (adding an individual custodian mailbox as a data source) - <https://learn.microsoft.com/purview/edisc-hold-create>
2. Create userSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-usersources?view=graph-rest-1.0>
3. Manage holds in eDiscovery - "Check the status of a hold" - <https://learn.microsoft.com/purview/edisc-hold-manage>
4. *Microsoft Teams / Microsoft 365 Group Hold-Location Resolution* - the roster-producing sibling this fragment consumes; see its own page the references for the `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` grounding not repeated here.
5. *Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)* - the hold-definition-consuming sibling this fragment feeds; see its own page the references for the full `ediscoveryHoldPolicy` v1.0 REST citation set not repeated here.

> This fragment introduces no new Microsoft Learn citations beyond confirming the portal path
> (reference 1) and re-linking the already-grounded `Create userSource` endpoint (reference 2) -
> every other product fact it depends on was grounded in the two sibling scenarios above. Re-verify
> all links against current Microsoft Learn before a customer-facing deployment.