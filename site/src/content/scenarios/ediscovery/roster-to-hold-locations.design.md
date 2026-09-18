---
part: "design"
parent: "ediscovery/roster-to-hold-locations"
---
## 1. Why this is a separate fragment, not a flag on either sibling scenario

`scenarios/ediscovery/teams-group-hold-resolution/design.md` §7 named this exact gap: "Once a
human uses `-ResolveMembers`'s roster output to decide individual members also need preservation,
feeding those resolved mailbox addresses into the sibling scenario's own `userSources[]` array is
currently a manual step. A future fragment could script that hand-off... deferred here to keep
this fragment scoped to the resolve/attach lookup itself." This fragment is that hand-off, and
only that hand-off:

- It is not part of `teams-group-hold-resolution` because that scenario's own `design.md` §2 is
 explicit that member expansion is "a human decision, not this script's to make", folding an
 auto-selecting merge into the resolve script would blur a boundary that scenario deliberately
 drew.
- It is not part of `location-scoped-legal-hold` because that scenario's scripts never read a
 roster CSV or a group identity at all, they consume an already-fully-specified
 `location-hold-definition.json` (`design.md` there, throughout). Teaching that scenario's deploy
 script to also understand roster CSVs and selection files would widen its own scope past a single
 concern (building/removing a hold from a declarative definition).

## 2. The human decision this script never makes

Per `teams-group-hold-resolution/design.md` §2, this fragment inherits the same non-negotiable
boundary: **which** roster members get individually preserved is a matter/counsel decision, never
a heuristic this script applies (not "everyone in the roster," not "everyone with a certain title,"
not "the N most active members"). `-SelectionPath` exists specifically to make that decision an
explicit, reviewable artifact, a small JSON file naming exact email addresses and a `reason`, 
rather than an implicit parameter sweep. `Merge-RosterIntoHoldDefinition.ps1` fails fast if a
selected email doesn't trace back to a roster row (§4 below), but it never adds an email the
caller didn't explicitly list.

## 3. Idempotency design

| Object | Model | Why |
|---|---|---|
| Merged definition file (default `deploy/out/<name>.merged.json`) | Additive, key-matched merge, existing `userSources[]` entries are never removed or altered; a selected email already present is skipped, not duplicated | Matches the sibling scenarios' own find-or-create idempotency model (§5); running the same selection twice against the same definition file is a safe no-op after the first run |
| `-InPlace` overwrite of `-DefinitionPath` | Guarded by a timestamped `.bak-<yyyyMMddHHmmss>` copy written immediately before the overwrite | `-InPlace` is the one path in this fragment that mutates a file the caller may not have a separate backup of (unlike `-OutputPath`'s default, which never touches the original); the backup makes an `-InPlace` run recoverable without depending on git history existing or being current for that specific file |
| `-AddToHold` Graph reconciliation | Find-or-create by `email`, duplicated from the sibling scenarios' own `Confirm-UserSource`/`Confirm-UserSourceOnHold` | Re-uses an already-reviewed idempotency mechanism rather than inventing a third copy of the same logic (§5) |

## 4. Why an unresolved selection is a hard error, not a warning

The original design considered treating a `-SelectionPath` email that isn't in `-RosterPath` as a
`Write-Warning`-and-skip case, matching this script's otherwise permissive tone elsewhere. Rejected:
a selection file exists specifically to be the auditable record of *which* roster-verified members
a human chose. An email that isn't in the roster is either a typo (the far more likely case, a
hand-typed selection file with no autocomplete) or a reference to someone who has since left the
group and is no longer even in a current roster snapshot. Silently skipping either case would let a
selection file with a real defect produce a merged definition file that looks complete (exit code
0, no obvious error) while quietly missing a custodian counsel actually decided needed preservation
, a spoliation-adjacent failure mode this fragment treats as unacceptable to leave to a `WARN` a
caller could miss. `AddToHold`'s own fail-fast precedent (a bad `userSource`/`siteSource` identity
aborting the whole run in `location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`) is
the same reasoning already established elsewhere in this repo.

## 5. Duplicated, not shared, hold-reconciliation logic

`Confirm-UserSourceOnHold` in this scenario's deploy script is a direct copy of
`location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`'s `Confirm-UserSource` (already
duplicated once before, into `teams-group-hold-resolution/deploy/
Resolve-TeamsGroupHoldLocations.ps1`'s own `Confirm-UserSourceOnHold`). This is now the third copy
of the same find-or-create pattern in this repo, following the precedent `teams-group-hold-
resolution/design.md` §5 already set (itself citing `scenarios/insider-risk/
irm-case-escalation-to-ediscovery/deploy/Confirm-EdiscoveryEscalationLink.ps1` as the first). Each
scenario's `deploy/` tree stays self-contained and independently runnable, at the accepted,
now-tripled cost of drift if one copy is bug-fixed and the others aren't, see §7 for why a shared
module is the right next step once a fourth consumer appears.

This fragment does **not** duplicate `Confirm-SiteSourceOnHold`, a roster of individual people has
no associated SharePoint site of its own to attach; only mailbox `userSources[]` are in scope here
(§6).

## 6. Non-goals (explicitly out of scope for this fragment)

- **Deciding which members to select.** See §2. Always supplied by the caller via `-SelectionPath`.
- **Re-validating current group membership.** This script reads the roster CSV as a point-in-time
 record; it never calls `Get-UnifiedGroupLinks` itself. If the roster is stale (a selected member
 has since left the group), this script still merges them, the roster is the audit trail for what
 the human's decision was based on at decision time, not a live membership re-check. A caller who
 needs current-membership confirmation runs `teams-group-hold-resolution/validate/
 Test-TeamsGroupHoldLocations.ps1`'s group-drift check separately.
- **Attaching a `siteSource`.** Individual members don't have their own SharePoint site in this
 context (their OneDrive is a materially different Purview hold-location type, not `siteSource`
 the way a group's Team site is), this fragment adds `userSources[]` entries only, never
 `siteSources[]`.
- **Adding a member's personal OneDrive to the hold.** A different location type from either
 sibling scenario's scope; not addressed here or in either sibling scenario.
- **Building or modifying the hold policy/case itself.** `-AddToHold` requires an already-existing
 `-CaseId`/`-HoldId`, exactly like `teams-group-hold-resolution`'s own `-AddToHold` path. This
 scenario never calls `POST.../legalHolds` itself.

## 7. Future refactor this fragment (again) sets up

Three independent `deploy/` trees in this repo now each carry their own copy of the same
find-or-create `userSource`/`siteSource` reconciliation logic (`location-scoped-legal-hold`,
`teams-group-hold-resolution`, and this fragment). A shared PowerShell module
(`PurviewEdiscoveryHoldHelpers.psm1` or similar) exporting `Confirm-UserSourceOnHold`/
`Confirm-SiteSourceOnHold` would remove the drift risk `teams-group-hold-resolution/design.md` §5
already flagged as an accepted cost, now a stronger case with a third copy in place. Still deferred
here, consistent with that scenario's own reasoning: a cross-cutting refactor is a legitimate
follow-up once enough scenarios share the exact pattern, not something a single fragment should take
on unprompted.

## References {#references-design}

No new Microsoft Learn citations are introduced by this fragment, every product fact it depends on
(the `userSources[]` JSON shape, the `Create userSource` v1.0 Graph endpoint, the roster CSV's own
column shape) is already grounded in the two sibling scenarios this fragment connects. See
`location-scoped-legal-hold/README.md` §12 and `teams-group-hold-resolution/README.md` §12 for the
full citation set.
