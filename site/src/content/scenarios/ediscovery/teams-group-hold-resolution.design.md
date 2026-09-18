---
part: "design"
parent: "ediscovery/teams-group-hold-resolution"
---
## 1. Why this is a separate fragment, not a flag on the sibling scenario

[`ediscovery/location-scoped-legal-hold`](/scenarios/ediscovery/location-scoped-legal-hold/)'s `design.md` §8 explicitly named this as a
non-goal: "resolving *which* group/site pair to use from a Team name is a distinct, separately
scoped lookup this fragment doesn't automate." Two reasons that separation holds up under design,
not just convenience:

- **Different automation surface.** The sibling scenario's scripts are Graph-only (surface 3,
  `Invoke-MgGraphRequest` against v1.0 `ediscoveryHoldPolicy` endpoints). Resolving a group's
  `SharePointSiteUrl` from its display name is an **Exchange Online PowerShell** operation
  (`Get-UnifiedGroup`, surface 1) — Microsoft's own guidance names this specific cmdlet as "a good
  way to get the URL for the site that's associated with a Microsoft 365 group or a Microsoft Team"
  [[R1]](#references-design), and no Graph-only equivalent is documented for this scenario's stated
  purpose. Folding this into the sibling scenario's deploy script would mean that script suddenly
  needing two separate PowerShell module families and two separate connections for what had been a
  single-surface (Graph) design.
- **Different failure/staleness model.** A hold policy, once built, is stable until a human changes
  it. A Team/group's mailbox alias or SharePoint site URL can change independently of the hold
  (a rename, for example) — this scenario's own `validate/Test-TeamsGroupHoldLocations.ps1` exists
  specifically to catch that drift, a check that has no equivalent need in the sibling scenario's
  own validation (which only reads the hold's own already-resolved `userSource`/`siteSource`
  objects, not their upstream identity source).

## 2. Scope: group mailbox + site only, never member expansion

This scenario resolves and (optionally) attaches exactly one `userSource` (the group's own mailbox)
and, if present, one `siteSource` (the group's SharePoint site) per declared group — never an
expansion into individual members' mailboxes. This is a direct, deliberate mirror of Microsoft's own
documented behavior: "when you place a Team or Microsoft 365 group on eDiscovery hold, the hold
applies only to the group mailbox and group site. The mailboxes and OneDrive sites of group members
aren't placed on hold unless you explicitly add them" [[R2]](#references-design). A design that
silently expanded to members would misrepresent what "run this script" actually preserves — the
`-ResolveMembers` roster output exists so a human can make that expansion decision deliberately
(and, if they do, feed the resulting mailbox addresses into the sibling scenario's own
`userSources[]` array by hand, or a future fragment — §7), never as something this script does on
its own.

## 3. Idempotency design

| Object | Model | Why |
|---|---|---|
| Resolved JSON fragment (`teams-group-hold-locations.resolved.json`) | Overwritten every run — a snapshot, not an accumulating log | There is nothing to "already have" about a read; re-resolving is the correct behavior on every run, and a stale fragment left on disk from a prior run would be actively misleading if not overwritten |
| Member roster CSV | Same — overwritten every run | Same reasoning; also avoids silently accumulating a point-in-time snapshot as if it were a historical membership log, which it explicitly is not (§2, README.md §11) |

Both default to `deploy/out/` (created on first run if missing), not `deploy/config/` alongside the
tracked sample definition file — this repo's `.gitignore` already excludes `out/` tenant-wide. A
real run's resolved mailbox/site values, and especially the member-roster CSV (matter-related
personal data — display names and SMTP addresses of a group's actual membership), have no reason to
land in version control by default; this was a Blue Team finding during this scenario's own review
round (`reviews.md`), fixed before the initial draft was finalized.
| `-AddToHold` userSource/siteSource reconciliation | Find-or-create by `email`/site title, identical to the sibling scenario's own `Confirm-UserSource`/`Confirm-SiteSource` | Re-uses an already-reviewed idempotency mechanism rather than inventing a second one — see §5 |

## 4. Component summary

| Component | Purpose | Idempotency mechanism |
|---|---|---|
| `deploy/Resolve-TeamsGroupHoldLocations.ps1` | Stage 1 (always): resolve group(s) to userSource/siteSource + optional member roster. Stage 2 (`-AddToHold`): reconcile onto an existing hold policy | Stage 1: overwrite-as-snapshot (§3). Stage 2: find-or-create by key, duplicated from the sibling scenario (§5) |
| `deploy/config/teams-group-hold-resolution.sample.json` | Declarative list of group identities (+ optional per-group member resolution) | Single source of truth the deploy/validate scripts both read |
| `validate/Test-TeamsGroupHoldLocations.ps1` | Read-only: group-drift check (always) + hold-reconciliation check (if `-CaseId`/`-HoldId` given) | `Get-UnifiedGroup`/Graph reads only; never calls a mutating cmdlet/endpoint |

## 5. Duplicated, not shared, hold-reconciliation logic

`Confirm-UserSourceOnHold`/`Confirm-SiteSourceOnHold` in this scenario's deploy script are a direct
copy of the sibling scenario's already four-lens-reviewed `Confirm-UserSource`/`Confirm-SiteSource`
functions (`location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`), not a dot-sourced or
shared-module import. This follows the precedent this repo already established in
`scenarios/insider-risk/irm-case-escalation-to-ediscovery/deploy/
Confirm-EdiscoveryEscalationLink.ps1` (which duplicates the same sibling scenario's find-or-create
pattern for its own custodian reconciliation): each scenario's `deploy/` tree stays self-contained
and independently runnable, at the accepted cost of the two copies drifting if one is bug-fixed and
the other isn't. A future cross-cutting refactor into a shared PowerShell module is a legitimate
option once enough scenarios share this exact pattern, but is out of scope for a single fragment.

## 6. Non-goals (explicitly out of scope for this fragment)

- **Member mailbox/OneDrive expansion** — see §2. A human decision, not this script's to make.
- **Private channel resolution.** Private channel chats live in a dedicated mailbox separate from
  the parent Team's group mailbox [[R3]](#references-design) — resolving *which* private channels
  exist under a Team and their own mailbox identifiers is a distinct lookup this fragment doesn't
  attempt; Microsoft's own guidance doesn't describe a `Get-UnifiedGroup`-equivalent cmdlet for
  enumerating private channel mailboxes.
- **Building or modifying the hold policy/case itself.** `-AddToHold` requires an already-existing
  `-CaseId`/`-HoldId`, created via `location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`
  or the portal. This scenario never calls `POST .../legalHolds` itself.
- **Resolving a *distribution list* (as opposed to a Team/Microsoft 365 Group) into hold locations**
  — a distribution list has no associated mailbox/site of its own to resolve the way a Microsoft 365
  Group does; the sibling scenario's own design already treats a DL's SMTP address as a direct
  `userSource.email` value (with its own open VERIFY on server-side member expansion) rather than
  something this scenario's `Get-UnifiedGroup`-based lookup applies to.
- **Reconciling the 100-member vs. >1,000-member group-expansion-cap discrepancy** (README.md §11)
  — re-grounded 2026-09-04 (`location-scoped-legal-hold/design.md` §3): both figures come from
  current, non-legacy Microsoft Learn pages describing two different pipeline steps (the portal's
  interactive picker vs. a post-apply hold error), and Microsoft doesn't state whether they're the
  same limit. Not resolved to a single figure — kept as an open, dual-cited VERIFY rather than
  guessed.

## 7. Downstream follow-up this fragment sets up

Once a human uses `-ResolveMembers`'s roster output to decide individual members also need
preservation, feeding those resolved mailbox addresses into the sibling scenario's own
`userSources[]` array is currently a manual step. A future fragment could script that hand-off
(reading this scenario's roster CSV and appending entries to a `location-hold-definition.json`) —
deferred here to keep this fragment scoped to the resolve/attach lookup itself, consistent with
`AGENTS.md` §6's fragment-discipline guidance.

## References {#references-design}

- R1. Create holds in eDiscovery — "Preserve content in Microsoft Teams" / "Microsoft 365 groups" (Get-UnifiedGroup worked example, SharePointSiteUrl) — <https://learn.microsoft.com/purview/edisc-hold-create#preserve-content-in-microsoft-teams>
- R2. Manage holds in eDiscovery — "Place a hold on Microsoft Teams and Microsoft 365 groups" (hold covers only the group mailbox/site, not member mailboxes/OneDrive) — <https://learn.microsoft.com/purview/edisc-hold-manage#place-a-hold-on-microsoft-teams-and-microsoft-365-groups>
- R3. Create holds in eDiscovery — "Preserve content in private channels" (dedicated private-channel mailbox, separate from the parent Team's group mailbox) — <https://learn.microsoft.com/purview/edisc-hold-create#preserve-content-in-private-channels>
