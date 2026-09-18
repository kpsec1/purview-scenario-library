---
part: "design"
parent: "ediscovery/gdpr-dsr-fulfillment"
---
## 1. Problem statement

[`compliance-manager/gdpr-assessment`](/scenarios/compliance-manager/gdpr-assessment/) names the gap directly: this library's closest
existing technical building block for a GDPR Data Subject Request,
[`ediscovery/search-and-purge-data-spillage`](/scenarios/ediscovery/search-and-purge-data-spillage/), was built for inadvertent data-spillage
remediation. It has no request-tracking, no per-request SLA timer against Article 12(3)'s
one-month (extendable by two further months) response deadline, and no rectification/restriction
workflow — only discovery/export/deletion, and only for one incident at a time, not a repeatable
per-person intake process
[[gdpr-assessment README §8/§11]](../../compliance-manager/gdpr-assessment/README.md). This
scenario builds the missing case-management layer — request intake, SLA computation and tracking,
and request-type routing — **on top of** the already-built, already-reviewed eDiscovery mechanics
in this repo's `search-and-purge-data-spillage` and `premium-legal-hold-and-export` siblings,
rather than duplicating them.

## 2. What Microsoft actually provides for this, and what doesn't exist anymore

Microsoft's own current guidance frames a DSR as six activities — **Discovery, Access,
Rectification, Restriction, Export, Deletion** [[1]](#references) — and a dedicated
Microsoft 365-specific page states plainly what tooling implements the first two: eDiscovery
search across Exchange (including mailboxes tied to Microsoft 365 Groups/Teams), Exchange public
folders, SharePoint, and OneDrive [[2]](#references). Two things this scenario's grounding pass
confirmed are **not** the current mechanism, despite surfacing prominently in search results and
older community writeups:

1. **The classic "User Data Search" DSR case tool.** It was retired and its functionality merged
   into eDiscovery (Standard) on **August 30, 2023** — over a year before the broader classic
   eDiscovery/Content Search retirement — and the redirect on Microsoft's current
   `ediscovery-search-for-content` page confirms the merge (its own URL carries the old DSR-tool
   article's redirect slug) [[3]](#references)[[4]](#references). There is no dedicated "create a
   DSR case" button or object type in the current experience; a DSR is just a regular eDiscovery
   case, search, and (for Access) export.
2. **Priva Subject Rights Requests.** Microsoft's separate **Microsoft Priva** product has a
   purpose-built Subject Rights Requests workflow with its own case-management UI and SLA tracking
   — genuinely closer to what this scenario's ledger approximates. It is explicitly **out of
   scope** for this library (`AGENTS.md` §10 default; `docs/automation-surface.md` §4 already lists
   its Graph surface, `/security/subjectRightsRequests`, as "Priva-adjacent — out of default
   scope"). This scenario does not reach for it, and does not reproduce its functionality beyond
   the minimal ledger described below.

Given both of those, the only current, non-retired, in-scope technical mechanism is the same
Microsoft Graph `ediscoveryCase` object model this repo already built two scenarios on top of.

## 3. Custodian-scoped search, not a tenant-wide sweep

`search-and-purge-data-spillage` searches with `dataSourceScopes: allTenantMailboxes` — appropriate
for "we don't yet know where the spilled content is," and already flagged by that scenario's own
Red Team review as carrying real blast-radius risk if the accompanying query is too broad
(`search-and-purge-data-spillage/reviews.md` finding 1). A DSR is the opposite case: the person is
already identified by name and email at intake. This scenario therefore uses the
**custodian-scoped** pattern `premium-legal-hold-and-export` already established — add the data
subject as a single `ediscoveryCustodian`, add their `userSource` (`includedSources: 'mailbox,
site'`, covering both Exchange and OneDrive/SharePoint), and scope the search to
`dataSourceScopes: 'allCaseCustodians'` [[5]](#references)[[6]](#references)[[7]](#references) —
narrower and lower-blast-radius than a tenant-wide sweep, and reuses an already-grounded,
already-reviewed cmdlet sequence rather than inventing a new one.

**Deliberately not applying a hold.** `premium-legal-hold-and-export`'s custodian workflow calls
`Add-MgSecurityCaseEdiscoveryCaseCustodianHold` immediately after adding a userSource, because that
scenario's purpose is legal preservation. A DSR intake is not litigation preservation — placing an
unrequested hold on a person's own mailbox because they exercised a GDPR right would be a
disproportionate, privacy-adverse side effect of processing their request, and Article 12(3) says
nothing about needing one. `New-DsrRequest.ps1` therefore adds the custodian and userSource but
**never calls the hold API**.

**Completeness gap, disclosed and made opt-in-fixable.** A custodian-scoped search only reaches
content the data subject owns or is a mailbox/site custodian of — it cannot see a message where the
data subject is merely a participant (sender/recipient/cc) in *someone else's* mailbox. That is a
real Article 15 completeness gap (`reviews.md` Red Team finding 1), not a hypothetical one. Rather
than silently accepting it or defaulting to the higher-blast-radius tenant-wide sweep, this
scenario exposes it as an explicit opt-in: `-IncludeParticipantSearch` adds a second search,
`dataSourceScopes: allTenantMailboxes` with `contentQuery: "participants:<email>"` — the same KQL
recipient-property expansion Microsoft documents for identity lookup across From/To/Cc/Bcc
[[13]](#references) — so the operator decides, per request, whether the completeness is worth the
broader scope, the same judgment call `search-and-purge-data-spillage`'s own Red Team review
already established for its `allTenantMailboxes` default.

**Empty `contentQuery` by default.** Microsoft's Create searches reference documents `contentQuery`
as optional [[7]](#references). An Access or Erasure request is about *all* of the person's data
in scope, not a keyword subset, so the sample definition ships with `contentQuery: ""` — combined
with `dataSourceScopes: allCaseCustodians`, this returns everything in the custodian's own
mailbox and site. A Rectification/Restriction/Objection request scoped to specific, already-known
records is the one case where narrowing the query makes sense (README.md §6).

## 4. The ledger: this scenario's own state, not Microsoft's

There is no Graph or PowerShell API for "GDPR request SLA tracking" — Compliance Manager tracks
regulatory *posture*, not individual request lifecycles, and Priva's request-tracking object model
is out of scope (§2). `New-DsrRequest.ps1` therefore maintains a small JSON ledger file (one record
per `requestId`) as this scenario's own artifact, computing:

- `dueDate` = `receivedDate` + 1 calendar month (Article 12(3) baseline)
- `maxExtendedDueDate` = `receivedDate` + 3 calendar months (if the two-further-months extension is
  invoked)

and a `status` field the operator drives manually (`Discovery` → `Reviewing` → `Fulfilled` →
`Closed`) — this scenario's scripts never infer status from Graph state, because "fulfilled" for a
Rectification/Restriction/Objection request happens entirely outside Purview (§6) and this
scenario cannot observe it.

**This is deliberately not a database, a workflow engine, or a notification system.** It is a flat
file an operator (or a scheduled job calling `validate/Test-DsrRequest.ps1`) reads. Treat it, and
the JSON request-definition files that feed it, as containing personal data in their own right
(data-subject email and name) — the same sensitivity discipline `search-and-purge-data-spillage`
already applies to its own query-definition file, extended here to a file that accumulates records
across every request, not just one incident (`reviews.md` Blue Team finding 1;
`rollback.md`).

## 5. Composition, not duplication: hand-off for Access/Portability and Erasure

Per `AGENTS.md` §5's Product Owner lens ("no reinventing a native capability"), this scenario does
not re-implement review-set/export or purge logic. Instead:

- **Access / Portability** → `premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1`
  and `Get-EdiscoveryExportPackage.ps1`, pointed at this scenario's `-CaseId`/`-SearchId`
  (README.md §5). That sibling's own review-set/export cmdlet grounding, idempotency behavior, and
  reviews.md findings all apply unchanged.
- **Erasure** → `search-and-purge-data-spillage/deploy/Invoke-DataSpillagePurge.ps1`, pointed at
  this scenario's `-CaseId`/`-SearchId` (README.md §5). That sibling's own litigation-hold gap and
  hand-off to `priority-cleanup-exchange-data-spillage` apply unchanged — a DSR erasure request
  against held content is exactly the case that hand-off already covers.
- **Rectification / Restriction / Objection** → no Purview-native technical fulfillment exists.
  §6 states why, rather than inventing a control Microsoft doesn't document.

## 6. Rectification, Restriction, and Objection: an honest non-goal

Microsoft's own DSR-activity definitions make the scope boundary explicit, not just a gap this
build happened not to fill:

- **Rectification** — "make changes or implement other requested actions on the personal data,
  **where applicable**" [[1]](#references). There is no generic Purview API to edit a message body
  or a document's field-level content; correction happens in the system of record (HR system, CRM,
  the document's own SharePoint/OneDrive location), not through eDiscovery. Where the record in
  question is a M365 mailbox/file item, the practical mechanism (if any) is: locate it via this
  scenario's Discovery search, then correct it through the native application (Outlook, Word,
  SharePoint), which is a normal edit, not a Purview action worth scripting.
- **Restriction** — per Microsoft's own definition, restricting processing means "removing licenses
  for various Azure services or turning off the desired services where possible... [or] remov[ing]
  data from the Microsoft cloud and retain[ing] it on-premises or at another location"
  [[1]](#references) — an account/license administrative action, not a document-level "restrict
  processing" flag Purview exposes. Scripting this would mean disabling a person's M365 services,
  which is a decision with consequences well beyond this scenario's scope to make unilaterally; it
  is left as an organizational decision informed by this scenario's Discovery search, not automated
  here.
- **Objection** (Article 21) — has no dedicated Microsoft 365/Purview technical control at all in
  any source this build found; like Rectification, it resolves to a business-process decision
  (stop a specific processing activity) that Purview's discovery/export/deletion primitives don't
  represent.

All three still get a ledger entry, an SLA timer, and a Discovery-stage search (so the organization
at least knows what data exists and where) — this scenario's honest claim is "we help you find it
and track the clock," not "we fulfill it."

## 7. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| API surface | Microsoft Graph (`ediscoveryCase`/custodian/search), not S&C PowerShell or Priva | Same automation-surface constraint as both eDiscovery siblings (§2); Priva explicitly out of scope (`AGENTS.md` §10) |
| Search scoping | Custodian-scoped (`allCaseCustodians`), not tenant-wide sweep | A DSR names one identified person at intake — lower blast radius than the data-spillage sibling's "don't yet know where" sweep (§3) |
| Hold | Never applied | A DSR intake is not litigation preservation; an unrequested hold on the requester's own mailbox is a disproportionate side effect (§3) |
| Default `contentQuery` | Empty string | An Access/Erasure request is about all of the person's data, not a keyword subset (§3) |
| SLA tracking | A new, scenario-owned JSON ledger | No Microsoft API exists for this; Priva's is out of scope (§4) |
| Access/Portability/Erasure fulfillment | Hand off to already-built sibling scripts, parameterized to this case/search | Avoids duplicating already-grounded, already-reviewed export/purge logic (§5) |
| Rectification/Restriction/Objection | Ledger + Discovery search only; no fulfillment script | No Purview-native technical control exists for any of the three (§6) — stated plainly rather than inventing one |

## 8. Non-goals

- **Priva Subject Rights Requests** — a materially different, purpose-built product surface; see §2.
- **Automated notification of the data subject** (acknowledgment, extension notice, or final
  response) — Article 12(3)'s extension-notice requirement is a legal communication the
  organization must send; this scenario tracks the deadline, it does not draft or send correspondence.
- **Rectification/Restriction/Objection technical fulfillment** — see §6.
- **Multi-tenant/bulk DSR intake at scale** (e.g., a web form or ticketing-system integration) — one
  request, one definition file, one ledger entry at a time; a future follow-up could wrap this in a
  queue-driven intake, tracked in `PROGRESS.md` rather than built speculatively here.
- **Breach-notification tracking (Article 33/34)** — a related but distinct GDPR obligation, already
  explicitly out of scope for `gdpr-assessment` itself
  (`compliance-manager/gdpr-assessment/design.md` §8) and not folded in here.

## References

See `README.md` §12 for the full, numbered source list shared with this file.
