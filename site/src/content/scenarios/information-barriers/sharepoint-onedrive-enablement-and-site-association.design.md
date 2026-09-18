---
part: "design"
parent: "information-barriers/sharepoint-onedrive-enablement-and-site-association"
---
## 1. Problem statement

`segregate-trading-and-research` builds a two-segment ethical wall enforced via Information
Barriers block policies, but by default that wall only covers **Teams** chat, calls, and
membership. SharePoint and OneDrive, where the Trading desk's and Research's actual working
files live, are a **separate enablement step** that Microsoft explicitly calls out as required to
extend IB coverage to file access and sharing (`segregate-trading-and-research/design.md` §6,
`README.md` §11). Until this step runs, a Trading user and a Research user who can't chat in Teams
can still open, share, and collaborate on each other's SharePoint sites and OneDrive content, a
gap an examiner or a red-team exercise would find immediately. This scenario closes that gap: one
tenant-wide enablement switch, plus segment association for the specific standalone SharePoint
sites that need it.

## 2. Design goals

1. **Close the file-collaboration gap, not duplicate the wall.** Reuses the existing
   Trading/Research segments and block policies from `segregate-trading-and-research`, this
   scenario adds SharePoint/OneDrive enforcement on top of them, it doesn't define a new wall.
2. **Respect the two automatic paths.** Teams-connected sites (Implicit mode) and a segmented
   user's own OneDrive (Explicit mode) protect themselves automatically once the tenant switch is
   on, script only what's genuinely manual: standalone SharePoint sites.
3. **Idempotent, create-or-report / add-what's-missing.** Never silently remove a segment
   association the config didn't ask for; the tenant-enablement script is a true idempotent
   toggle (reads current state, changes only on a real diff).
4. **Honest about the two-surface, Windows-only automation reality.** This is the first scenario
   in this library to combine surface 2 (segment name → GUID resolution) with surface 5
   (`Set-SPOTenant`/`Set-SPOSite`) in one workflow, and surface 5 has no cross-platform CI/CD path
, both are stated plainly rather than glossed over.
5. **Don't overcorrect on rollback.** A full tenant-wide suspend is a blunt instrument that also
   drops enforcement on the Teams-Implicit sites the parent scenario already protects, the
   rollback path defaults to per-site removal and only escalates to suspension for a genuine
   decommission (§6).

## 3. Why this needs its own fragment (not folded into the parent)

- It is Microsoft's own **documented, separate configuration step** ("Step 5: Configure
  Information Barriers on SharePoint and OneDrive (optional)" in the IB configuration overview),
  with its own prerequisites (policies active + applied + 24h propagated first), its own cmdlets,
  and its own automation surface (5, not 2), genuinely distinct code and RBAC from the parent's
  segment/policy definitions.
- It generalizes beyond the Trading/Research pair: any scenario that builds a wall via
  `New-InformationBarrierPolicy` needs this same enablement + site-association step if the wall
  must also cover files, so keeping it a separate, referenceable fragment avoids duplicating this
  logic into every future IB scenario.

## 4. Object model and sequence

```mermaid
sequenceDiagram
    participant Admin as SharePoint Administrator
    participant EnableScript as Set-SharePointOneDriveIBEnablement.ps1
    participant SegScript as Set-SiteInformationSegments.ps1
    participant SPO as SharePoint Online Management Shell (surface 5)
    participant SCC as Security & Compliance PowerShell (surface 2)
    participant Sites as SharePoint sites / OneDrive

    Note over SCC: Prerequisite (segregate-trading-and-research):<br/>Trading/Research segments + block policies Active, applied, 24h propagated
    Admin->>EnableScript: run (after prerequisite confirmed)
    EnableScript->>SPO: Get-SPOTenant (read current state)
    EnableScript->>SPO: Set-SPOTenant -InformationBarriersSuspension $false
    Note over SPO,Sites: ~1 hour to take effect tenant-wide
    Sites-->>Sites: Teams-connected sites -> Implicit mode (auto, within 24h)
    Sites-->>Sites: Segmented users' OneDrive -> Explicit mode (auto, within 24h)
    Admin->>SegScript: run (for standalone, non-Teams-connected sites)
    SegScript->>SCC: Get-OrganizationSegment (resolve segment name -> GUID)
    SegScript->>SPO: Get-SPOSite -Identity <url> (read current segments)
    SegScript->>SPO: Set-SPOSite -AddInformationSegment <GUID>
    SPO-->>Sites: site mode -> Explicit; only matching-segment users can access/share
```

Two independent automatic paths (Teams-connected sites, OneDrive) require nothing beyond the
tenant switch; the one manual path (standalone SharePoint sites) is what this scenario's second
script scripts.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Tenant enablement + standalone-site association only | Teams-connected sites and OneDrive self-associate; scripting them would duplicate Microsoft's own automatic behavior |
| Segment resolution | Try `EXOSegmentId`, fall back to `Guid` | Microsoft's own SharePoint-association example uses `EXOSegmentId`; `segregate-trading-and-research`'s scripts use `.Guid` for the same `Get-OrganizationSegment` objects within S&C PowerShell, unreconciled, so both are tried rather than guessing one (§4 of `AGENTS.md`) |
| Incompatible-segment handling | Surface the per-site error, continue with remaining sites | A rejected `Set-SPOSite -AddInformationSegment` call (segments blocked by an active policy) shouldn't abort an otherwise-valid batch of unrelated sites |
| Idempotency (tenant switch) | Read `Get-SPOTenant` first; skip the call if already in the desired state | True toggle idempotency, not just create-or-report |
| Idempotency (site segments) | Additive by default; `-RemoveConfigured` removes only what the config lists | Never silently detaches a segment the config didn't mention, a site may carry segments this scenario doesn't manage |
| Dry-run | Custom `-DryRun` | `-WhatIf` is non-functional on `Set-SPOTenant`/`Set-SPOSite` in the SharePoint Online Management Shell |
| Rollback default | Per-site removal, not tenant suspend | Suspending is tenant-wide and would also drop the Teams-Implicit-site protection the parent scenario relies on, a much larger blast radius than "undo this scenario's own additions" |
| Automation surface | Surface 5 (`Connect-SPOService`) + Surface 2 (`Connect-IPPSSession`) | First scenario in this library to require both in one workflow; documented explicitly rather than assumed |

## 6. Non-goals

- **Teams-connected site management.** Implicit mode is Microsoft-managed via Team/Microsoft 365
  group membership; a SharePoint Administrator can't directly manage segments on an Implicit-mode
  site (per Microsoft's own guidance), out of scope here.
- **Per-user OneDrive mode management** (`Owner Moderated`/`Mixed` via `Set-SPOSite -Identity
  <OneDrive URL> -InformationBarriersMode ...`), a real, documented capability, but a distinct
  exception-handling scenario (e.g. "let a compliance officer's OneDrive be visible across the
  wall"), not this scenario's baseline enablement.
- **`DefaultOneDriveInformationBarrierMode` tuning**, `Set-SPOTenant` exposes this parameter, but
  the fetched Microsoft Learn reference for it doesn't enumerate accepted values or describe its
  effect distinctly from the per-site `-InformationBarriersMode` values; not scripted here rather
  than guessed (`README.md` §11).
- **Auto-discovery of SharePoint sites needing segments.** The config is a human-curated list; a
  scan of all tenant sites to propose segment associations is a natural follow-up, not built here
  (`docs/automation-surface.md` §5 already notes surface 5 isn't a bulk-iteration surface in this
  library).
- **App-only/people-picker bypass toggles** (`-AppBypassInformationBarriers`,
  `-AppOnlyBypassPeoplePickerPolicies`), documented, real settings for apps that need to reach IB
  sites; left as a manual, case-by-case decision rather than defaulted on, since enabling them
  widens the wall's exceptions.
- **Audit-log export script** for the seven documented SharePoint IB audit activities (enable,
  apply/change/remove segment, apply/change mode, disable), the exact `RecordType`/`Operations`
  values for `Search-UnifiedAuditLog` aren't confirmed in this build; a natural companion to
  `segregate-trading-and-research`'s own open audit-trail item, tracked as a follow-up rather than
  guessed.
