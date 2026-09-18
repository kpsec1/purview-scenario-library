---
part: "design"
parent: "data-security-investigations/post-breach-investigation-and-purge"
---
## 1. Problem statement

This library already has two eDiscovery scenarios that search for and permanently delete Exchange/
Teams content (`ediscovery/search-and-purge-data-spillage`, `ediscovery/search-and-purge-teams-
messages`): both assume an investigator already knows *what* to search for, a known keyword, a
known custodian, a known date range. **Microsoft Purview Data Security Investigations (DSI)** is a
different, complementary solution for the case that assumption doesn't hold: a Defender XDR incident
or an Insider Risk Management case surfaces a *user* or a *blast radius*, not a search query, and
answering "what did this actually expose?" across potentially thousands of files/emails/messages by
manual review doesn't scale. DSI uses generative AI (vector search, categorization, credential/risk/
personal-data examination) to triage that volume down to what actually matters, then hands the
investigator the same category of mitigation action, purge, once the triage is done.

This scenario grounds DSI as its own module (this library had no DSI scenario yet, flagged as a
follow-up during the `ediscovery/search-and-purge-teams-messages` build, since Microsoft's own "Find
and delete Microsoft Teams chat messages" documentation calls out DSI's purge queue as an alternative
entry point) and builds the parts of standing it up that are actually scriptable.

## 2. Design goals

1. **Be honest about what's portal-only.** Investigation creation, search/scope management, AI
   analysis (vectorization, categorization, examination), the mitigation plan, and purge itself have
   no documented Graph or PowerShell **write** API (§3 below), this design does not invent one. What
   this scenario ships is the two things that genuinely are scriptable: RBAC provisioning and the
   audit-trail export.
2. **Least-privilege by construction.** The three dedicated DSI role groups (Admins/Investigators/
   Reviewers) encode a real separation of duties, only Admins/Investigators can run a purge; only
   Admins see the Pay-as-you-go usage dashboard. `deploy/New-DsiRoleGroupAssignments.ps1` provisions
   exactly the declared membership, not a shortcut like adding everyone to Admins.
3. **The highest-risk action gets the loudest signal.** A purge is the one DSI action that can
   permanently, irreversibly delete tenant data. `deploy/Export-DsiActivityAuditTrail.ps1` singles out
   `DSIPurgeStarted` with an explicit warning on every run, not just a row in a CSV.
4. **Idempotent and additive-safe.** Re-running the role-group script never removes an existing member
   unless `-RemoveExtraMembers` is explicitly passed, a role group that gates purge permissions is
   the wrong place for a script to make a destructive change by default.
5. **Author-only, no live tenant.** Both scripts require an existing PowerShell session the operator
   establishes themselves; neither script provisions Data Security Investigations itself (billing, AI
   capacity, and the privacy-terms acceptance are one-time portal steps, README.md §5).

## 3. Why there's no write-API script for the DSI workflow itself

A dedicated grounding pass (Microsoft Learn search across the full `data-security-investigations-*`
documentation set, the `dataSecurityInvestigationAuditRecord` Graph resource, and the Purview REST/
Graph references this library already indexes for other scenarios) found:

- Every documented way to create an investigation, add search results to scope, run AI analysis, add
  an item to a mitigation plan, or create/run a purge query is a Microsoft Purview **portal** action
  (`https://purview.microsoft.com/dsi`), Microsoft's own step-by-step articles (get-started, search,
  scope, AI analysis, mitigation-actions) document only UI clicks, never a cmdlet or REST call.
- The only Graph resource this library found under the `microsoft.graph.security` namespace for DSI, 
  `dataSecurityInvestigationAuditRecord`, is a **read** schema: it describes the shape of a DSI event
  *inside* an audit log record returned by the general Security API audit log surface. It is not a
  management endpoint; it has no create/update/delete methods (confirmed: its reference page lists
  "Methods: None").
- This mirrors a pattern already established elsewhere in this library, Communication Compliance
  (`communication-compliance/harassment-and-code-of-conduct/design.md` §2) and the IRM case-escalation
  scenario both found the same shape: a rich portal workflow with a documented, scriptable audit
  footprint but no write API, and this scenario follows the same resolution rather than guessing an
  endpoint that doesn't exist (`AGENTS.md` §4).

Building a fake "automation" layer around a portal-only workflow would misrepresent what a buyer is
actually getting. Instead, this scenario ships what's real: RBAC as code, and an audited, exportable
trail of every DSI action, which is also what a SOC actually needs operationally (§8 in README.md).

## 4. Workflow

```mermaid
sequenceDiagram
    participant XDR as Defender XDR incident
    participant IRM as Insider Risk Management case
    participant Portal as Purview portal (purview.microsoft.com/dsi)
    participant AI as DSI AI analysis (vector search, categorization, examination)
    participant Mit as Mitigation plan
    participant Purge as Purge queue
    participant Src as Exchange mailbox / Teams

    alt From Defender XDR
        XDR->>Portal: Create investigation from incident
    else From Insider Risk Management
        IRM->>Portal: Create investigation from case
    else Manual
        Portal->>Portal: Create investigation (full draft mode)
    end
    Portal->>Portal: Add search results to investigation scope
    Portal->>AI: Automatic vectorization, then run categorization/examination
    AI-->>Portal: Risk-ranked, categorized items; credential/PII findings
    Portal->>Mit: Add high-risk items to mitigation plan
    Mit->>Purge: Save a purge query (soft or hard)
    Purge->>Src: Review for purge -> Confirm purge -> items removed from source
    Note over Portal,Src: Every step above is logged automatically to the<br/>unified audit log (28 DSI Operations - design.md Section 3)
```

```mermaid
sequenceDiagram
    participant Op as Operator
    participant IPPS as Security & Compliance PowerShell
    participant EXO as Exchange Online PowerShell
    participant UAL as Unified audit log

    Op->>IPPS: Connect-IPPSSession
    Op->>IPPS: New-DsiRoleGroupAssignments.ps1 (-WhatIf then apply)
    IPPS-->>Op: Admins/Investigators/Reviewers membership reconciled

    loop scheduled (e.g. daily)
        Op->>EXO: Connect-ExchangeOnline
        Op->>EXO: Export-DsiActivityAuditTrail.ps1 [-NdjsonOutDir optional]
        EXO->>UAL: Search-UnifiedAuditLog -Operations <28 DSI ops>
        UAL-->>EXO: Matching records
        EXO-->>Op: Rolling CSV merged; DSIPurgeStarted rows flagged
        Note over EXO,Op: If -NdjsonOutDir was supplied, new records are also<br/>written as DSI-Activity-<runStamp>.ndjson (Section 5 table)
    end
```

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope: RBAC + audit trail only | Two scripts, not an attempted end-to-end automation | The end-to-end workflow has no write API (§3), scripting around that would mean inventing cmdlets, against `AGENTS.md` §4 |
| Only the three dedicated role groups | `New-DsiRoleGroupAssignments.ps1` never touches Compliance Administrator / Organization Management / Data Security Management / Insider Risk Management | Those four role groups grant DSI access as a side effect of a broader Purview role; reconciling their membership here would risk unintended changes to unrelated solutions those role groups also govern (README.md §3) |
| Additive-only by default | `-RemoveExtraMembers` is opt-in, not the default | A role group that gates purge (a destructive, irreversible action for hard purge) should never silently lose a member because of an incomplete config, the safer default is to only ever grant, never revoke, unless explicitly asked |
| `-Operations` only, no `-RecordType` | `Export-DsiActivityAuditTrail.ps1` omits `-RecordType` | The RecordType enum value for DSI records isn't stated anywhere in Microsoft's audit-log-activities reference (VERIFY, README.md §11), `Search-UnifiedAuditLog` doesn't require it when `-Operations` is supplied, so this avoids guessing a value |
| Purge-start events get a dedicated warning | Every `DSIPurgeStarted` row triggers `Write-Warning`, not just a CSV row | It's the one action in this entire workflow that's genuinely irreversible (hard purge), the audit script's job is to make that impossible to miss in a log tail |
| Native `-WhatIf` | Both scripts use `[CmdletBinding(SupportsShouldProcess)]` | `Add-RoleGroupMember`/`Remove-RoleGroupMember`/`Update-RoleGroupMember` all natively support `-WhatIf` (confirmed against the Exchange PowerShell reference), unlike some Security & Compliance PowerShell cmdlets elsewhere in this library where `-WhatIf` is documented as non-functional and a custom dry-run flag was needed instead |
| SIEM companion feed is opt-in, additive, and reuses an existing convention rather than inventing one | `-NdjsonOutDir` on `Export-DsiActivityAuditTrail.ps1`, off by default | Building a third bespoke output format would fragment this library's SIEM hand-off story; reusing `Invoke-ManagementActivityPoll.ps1`'s own per-run `<label>-<runStamp>.ndjson` file convention means one downstream forwarder can watch a single directory for both scenarios' output, with zero new infrastructure, `AGENTS.md` §4's reuse-over-reinvention discipline applied across scenarios, not just within one |

## 6. Non-goals

- **Scripting investigation creation, search, AI analysis, mitigation-plan changes, or purge itself.**
  No documented write API exists (§3). Building this would mean either inventing an undocumented
  endpoint or wrapping browser automation around the portal, both against this library's grounding
  discipline.
- **Configuring DSI billing / AI capacity / compute unit location.** These are one-time portal setup
  steps (README.md §5, Step 3) with no documented PowerShell/Graph configuration surface this build
  found.
- **The Data Security Posture (Copilot) agent.** A related but separate, independently-enabled
  feature (its own Preview) surfaced during this grounding pass, out of scope; a candidate for its
  own future fragment once it's further along.
- **DSPM (preview) proactive-AI-insights auto-investigation toggle.** Portal-only toggle, no API found;
  noted in README.md §11 rather than built.
- **Building a dedicated SIEM forwarder.** `Export-DsiActivityAuditTrail.ps1`'s CSV output remains the
  documented primary hand-off point. §8 below adds an *optional* `-NdjsonOutDir` companion output that
  reuses `audit/streaming-to-sentinel-or-management-api`'s own Path B per-run NDJSON convention so the
  two scenarios' outputs land in one directory, but this script still does not forward that NDJSON
  anywhere itself, same non-goal as `Invoke-ManagementActivityPoll.ps1` (a downstream forwarder is
  still required, and remains out of scope for a per-solution scenario like this one).
- **A dedicated custodian/reviewer notification workflow.** Not part of DSI's documented feature set.

## 7. Relationship to this library's other purge-capable scenarios

| Scenario | Trigger | Discovery method | Purge scope |
|---|---|---|---|
| `ediscovery/search-and-purge-data-spillage` | Known query (a specific spillage report) | Manual eDiscovery content search | Exchange mailboxes |
| `ediscovery/search-and-purge-teams-messages` | Known query (a specific incident) | Manual eDiscovery content search, Teams-scoped | Teams messages |
| **This scenario** | An XDR incident or IRM case surfacing a *user/blast-radius*, not a known query | AI-assisted triage (vector search, categorization, examination) across a broad scope | Exchange mailboxes + Teams messages (same two sources; SharePoint/OneDrive are excluded from purge even though they can be added to an investigation's *scope*, README.md §11) |

DSI is not a replacement for the eDiscovery-native scenarios, it's the tool for the case where the
investigator doesn't yet know what to search for. A buyer with both needs both; this scenario's
README §1 states that explicitly rather than implying DSI supersedes plain eDiscovery search-and-
purge.
