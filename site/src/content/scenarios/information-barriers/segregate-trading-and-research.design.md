---
part: "design"
parent: "information-barriers/segregate-trading-and-research"
---
## 1. Problem statement

A regulated financial firm must prevent inappropriate information flow between people who produce
research and people who trade or sell — a conflict-of-interest "ethical wall" required by FINRA 2241,
SEC Reg AC, MiFID II, and market-abuse rules. The control must be enforced in the collaboration layer
(Teams, SharePoint, OneDrive), reproducible for audit, and safe to roll out — because turning it on
changes live communication. This scenario builds the wall as code: two attribute-driven segments and
the two one-way block policies that segregate them, staged inactive for review and enforced only on an
explicit, signed-off activation.

## 2. Design goals

1. **Correct segregation by construction.** Two mutually-exclusive segments and **both** one-way block
   policies — the only way to fully wall two sides.
2. **Safe by default.** Create everything **inactive**; activation + tenant-wide application (which
   blocks live communication) is a separate, explicit `-Activate` gated behind `-DryRun` review and
   Compliance/Legal sign-off.
3. **Reproducible and auditable.** The config file is the versioned definition of the wall — what an
   examiner or internal audit wants to see.
4. **Idempotent create-or-report.** Locate segments/policies by name; never silently mutate an existing
   one (IB objects gate real communication).
5. **Honest about async, delayed enforcement.** Document the ~30-min start, ~5,000-users/hour, and
   24-hour SharePoint propagation rather than implying instant blocking.

## 3. Why Information Barriers (not just permissions or DLP)

- **Directory/permission separation** (separate sites, groups) is porous — people can still Teams-chat,
  be added to a group call, or be @mentioned across the wall. It doesn't enforce a communication
  barrier.
- **DLP** inspects *content*; it doesn't stop two people from *communicating* in the first place, which
  is the ethical-wall requirement.
- **Information Barriers** is the Microsoft-native control that actually prevents communication/
  collaboration between incompatible groups across Teams, SharePoint, and OneDrive — the right tool for
  a conflict-of-interest wall.

## 4. Object model and sequence

```mermaid
sequenceDiagram
    participant Script as New-TradingResearchBarrier.ps1
    participant SCC as Security & Compliance PowerShell
    participant M365 as Teams / SharePoint / OneDrive

    Script->>SCC: New-OrganizationSegment (Trading), New-OrganizationSegment (Research)
    Script->>SCC: New-InformationBarrierPolicy Trading-block-Research -State Inactive
    Script->>SCC: New-InformationBarrierPolicy Research-block-Trading -State Inactive
    Note over SCC: nothing enforced yet — objects staged for review
    opt -Activate (after sign-off)
        Script->>SCC: Set-InformationBarrierPolicy -State Active (each)
        Script->>SCC: Start-InformationBarrierPoliciesApplication
        SCC-->>M365: apply user-by-user (~5,000/hr; SharePoint up to 24h)
        M365-->>M365: block Trading<->Research communication/collaboration
    end
```

Segments and policies are inert until activated and applied; the two one-way policies together form the
bidirectional wall. Application is asynchronous and user-by-user.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Policy type | **Block** (not Allow) | Microsoft recommends block policies for most scenarios; behaves consistently across IB modes for non-IB users |
| Directions | Two one-way block policies | A single policy blocks one direction only; a wall needs both |
| Default state | **Inactive**, not applied | Activation changes live communication — must be a deliberate, reviewed step |
| Activation | Explicit `-Activate` (+ `Start-...Application`) | Separates "define" from "enforce"; gated behind `-DryRun` + sign-off |
| Idempotency | Create-or-report by name | Never silently mutate a communication-gating object |
| Dry-run | Custom `-DryRun` | `-WhatIf` is non-functional in S&C PowerShell |
| Segmentation | One exclusive segment per side, attribute-driven | Mutually-exclusive segments are required; attribute keeps it authoritative and auto-updating |

## 6. Non-goals

- **Allow-list topologies** (a segment that may talk to only certain others) — supported via
  `-SegmentsAllowed`; this scenario uses the simpler, recommended block model.
- **SharePoint/OneDrive IB enablement and site association** — a separate enablement step
  (`Set-SPOTenant`, site-segment association); documented as a prerequisite/extension, not scripted
  here.
- **Address book policy / GAL segmentation** — full directory separation is a related but distinct
  configuration.
- **Exceptions modeling** (e.g. a control-room/compliance function that must see both sides) — real
  deployments add such segments/policies; the starter keeps a clean two-sided wall.
- **Multi-segment mode migration** — changing IB mode to allow users in multiple segments is a
  tenant-level operation out of scope here.
- **Editing an existing wall in place** — the deploy reports and does not mutate; changes are a
  deliberate, reviewed action.
