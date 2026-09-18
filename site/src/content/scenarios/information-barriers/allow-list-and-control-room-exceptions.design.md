---
part: "design"
parent: "information-barriers/allow-list-and-control-room-exceptions"
---
## 1. Problem statement

`segregate-trading-and-research` builds a clean, two-sided ethical wall with **Block**-type
policies. Real deployments are rarely that clean: a compliance officer, control-room analyst, or
legal counsel often has a legitimate, examinable need to see **both** sides of a wall (or, in a
narrower case, one side that isn't their own), without dismantling the wall for anyone else. This
scenario models that need as code: **Allow**-type (`-SegmentsAllowed`) segments and policies layered
alongside an existing Block-type wall, plus the reconciliation logic to change an allow-list's
membership over time.

## 2. Design goals

1. **Additive, not destructive.** Never touch the `Trading`/`Research` segments or their Block
 policies, this scenario only adds new segments/policies alongside them.
2. **Model the general pattern, not just one example.** The sample config carries two allow-list
 shapes, a "sees both sides" control-room exception and a narrower, one-sided asymmetric
 allow-list, so the deploy script demonstrably generalizes rather than special-casing one segment.
3. **Safe by default.** Create/reconcile everything **Inactive**; enforcement is a separate, explicit
 `-Activate` gated behind `-DryRun` review.
4. **Honest about editing a live policy.** Changing an Allow policy's membership on an **Active**
 policy requires deactivating it first (Microsoft's own documented edit workflow); the script does
 this automatically and makes the reactivation requirement explicit rather than silently leaving a
 stale allow-list enforced.
5. **Idempotent create-or-reconcile.** Segments are create-or-report (as in the base scenario); allow
 policies additionally support **reconciliation**, if the live `SegmentsAllowed` set drifts from
 config, the script corrects it, because an allow-list's membership is expected to change over
 time (a new compliance analyst joins the control room) in a way a static ethical wall is not.

## 3. Why allow-list (not just "no policy") for the exception segment

An unlisted segment (no IB policy at all) already communicates with everyone by default under a
Block-only wall, so the *simplest* way to give a control room visibility into both sides is to
simply not assign it any policy. This scenario deliberately scripts an **explicit Allow policy**
instead, for three reasons documented in Microsoft's own IB guidance and this repo's audit-first
posture:

- **Explicit allow-list is examinable.** "No policy" is invisible in `Get-InformationBarrierPolicy`
 output, an examiner or internal audit has nothing to point at. An Allow policy is a named,
 reviewable object stating exactly which two segments the control room may reach.
- **Default-deny for the exception segment itself.** An Allow-type policy makes its **assigned**
 segment default-deny to everything *except* what's listed, so if the control room should reach
 only Trading and Research (not, say, a future `Investment-Banking-Advisory` segment), the allow
 policy enforces that boundary too, rather than leaving the control room's own scope implicitly open
 to every future segment.
- **Matches Microsoft's own worked pattern.** The "Get started with Information Barriers" walkthrough
 describes exactly this shape, a third segment (their example: HR) that stays "compatible" with two
 segments a Block policy keeps apart from each other. This scenario's
 `ComplianceControlRoom` plays that same role for `Trading`/`Research`.

## 4. Object model and sequence

```mermaid
sequenceDiagram
    participant Script as New-ControlRoomAllowException.ps1
    participant SCC as Security & Compliance PowerShell
    participant M365 as Teams / SharePoint / OneDrive

    Note over SCC: Trading, Research already exist (segregate-trading-and-research)
    Script->>SCC: Get-OrganizationSegment - verify Trading, Research exist (hard-fail if not)
    Script->>SCC: New-OrganizationSegment (ComplianceControlRoom), New-OrganizationSegment (Legal)
    Script->>SCC: New-InformationBarrierPolicy ComplianceControlRoom-allow-Trading-Research -SegmentsAllowed 'Trading,Research' -State Inactive
    Script->>SCC: New-InformationBarrierPolicy Legal-allow-Research -SegmentsAllowed 'Research' -State Inactive
    Note over SCC: nothing enforced yet - objects staged for review
    opt config later adds a segment to an allow-list (e.g. Legal must now also see Trading)
        Script->>SCC: Get-InformationBarrierPolicy - detect SegmentsAllowed drift
        alt policy currently Active
            Script->>SCC: Set-InformationBarrierPolicy -State Inactive (required before editing)
        end
        Script->>SCC: Set-InformationBarrierPolicy -SegmentsAllowed '<new full list>'
        Note over SCC: policy left Inactive - operator must re-run with -Activate
    end
    opt -Activate (after sign-off)
        Script->>SCC: Set-InformationBarrierPolicy -State Active (each managed policy)
        Script->>SCC: Start-InformationBarrierPoliciesApplication
        SCC-->>M365: apply user-by-user (~5,000/hr; SharePoint up to 24h)
        M365-->>M365: ComplianceControlRoom reaches Trading+Research; Legal reaches Research only
    end
```

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Policy type | **Allow** (`-SegmentsAllowed`), not Block | The exception segment's access must be a named, bounded allow-list, not an absence of restriction |
| Scope | Additive companion, not a rewrite | `Trading`/`Research` segments and their Block policies are owned by `segregate-trading-and-research`; this scenario never creates or edits them |
| Naming | `<assignedSegment>-allow-<allows, joined by '->'` | Mirrors the base scenario's `<assigned>-block-<blocks>` convention so both wall types read consistently in `Get-InformationBarrierPolicy` output |
| Membership drift | Reconcile via `Set-InformationBarrierPolicy -SegmentsAllowed <full list>` | Allow-lists are expected to change membership over time (new analyst, offboarded reviewer), a static create-only script would silently ignore config changes |
| Editing an Active policy | Deactivate automatically, then require a fresh `-Activate` | Microsoft's documented edit workflow: set Inactive before changing `SegmentsAllowed`/`SegmentsBlocked`, then reactivate and re-apply; the script never silently reactivates an edited policy without an explicit re-run |
| IB mode | Require **SingleSegment**, not Legacy, not MultiSegment | MultiSegment requires **every** policy in the tenant to be Allow-type, configuring even one Block policy (as the base wall does) breaks it. **Legacy** mode has a separate, sharper problem: an Allow policy in Legacy mode hides **all** non-IB users/groups from the assigned segment's members, not just unlisted segments, a severe collateral impact for a role that still needs ordinary communication. SingleSegment mode has neither problem, so the scripts check `Get-PolicyConfig` and warn (non-fatally) if the tenant isn't in it |
| Dry-run | Custom `-DryRun` | `-WhatIf` is non-functional in S&C PowerShell |
| Idempotency | Segments: create-or-report. Policies: create-or-reconcile | Segments rarely change definition; allow-list membership plausibly does |

## 6. Non-goals

- **MultiSegment mode / multi-segment membership.** Letting a single user sit in more than one
 segment (e.g. a person who is genuinely both "Trading" and "ComplianceControlRoom") requires
 tenant-wide MultiSegment mode, which in turn requires **every** IB policy in the tenant to be
 Allow-type, incompatible with the existing Block-type wall unless it's also rebuilt as Allow
 policies. Out of scope; flagged as a real migration path in `README.md` §11, not scripted here.
- **Rebuilding the wall as Allow-only policies.** An alternative design converts `Trading`/`Research`
 themselves to Allow policies (each allowed to talk only to everyone except the other side) to enable
 MultiSegment mode later. Not attempted, it would mean rewriting a scenario this one is a companion
 to, not an extension of it.
- **Automatic membership sourcing for the exception segments.** Like the base scenario, segment
 membership comes from an Entra attribute (`Department`) set by whatever process manages org data;
 this scenario doesn't build an HR-feed or attestation workflow for who belongs in
 `ComplianceControlRoom` or `Legal`.
- **A three-or-more-way wall.** This models one wall (`Trading`/`Research`) plus exceptions; a
 scenario with three or more mutually-walled sides is a different, larger topology.
- **Auditing who actually used the exception access.** Detecting/alerting when a
 `ComplianceControlRoom` member reads Trading-side content is a Blue Team/DLP/Activity Explorer
 concern, not an IB-policy concern, noted in `README.md` §8, not built here.
