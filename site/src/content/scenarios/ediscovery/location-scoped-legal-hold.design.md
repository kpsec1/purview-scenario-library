---
part: "design"
parent: "ediscovery/location-scoped-legal-hold"
---
## 1. Why this is a genuinely separate object model, not a custodian-hold variant

[`ediscovery/premium-legal-hold-and-export`](/scenarios/ediscovery/premium-legal-hold-and-export/) covers `ediscoveryCustodian.applyHold` —
a named person's mailbox/OneDrive, added to a case as a custodian with rich case-management
semantics (hold status, release, re-activate, review-set participation). This scenario covers the
v1.0 API's other hold object, `microsoft.graph.security.ediscoveryHoldPolicy`
(`POST .../legalHolds`), which that sibling scenario's `design.md` §3 and `README.md` §11
explicitly scoped out. An `ediscoveryHoldPolicy` is not tied to a named person at all — it holds
whatever `siteSources`/`userSources` you attach to it directly, which makes it the right object
for:

- A **shared departmental mailbox and site** with no single owning individual (this scenario's
  worked example — a Payments team inbox and SharePoint site).
- A **regulatory-sweep distribution list**, where the population of in-scope mailboxes is defined
  by list membership rather than a legal team naming each person as a custodian.
- Any hold where the case doesn't need custodian-level case-management features (interview
  tracking, custodian communications, review-set-search participation as a named party) — just
  "preserve this location" [[R1]](#references-design).

Both mechanisms are called "legal hold" in Microsoft's own documentation and both live under the
same `ediscoveryCase`, which is why a reader coming from one scenario can reasonably expect the
other to behave the same way. It doesn't, in three concrete respects covered below.

## 2. `userSource` shape differs from the custodian version

The custodian scenario's `userSource.includedSources` accepts a combined string
(`"mailbox, site"`, per its own §11 VERIFY) covering both the person's mailbox and their OneDrive
site in one object. A legal-hold-policy `userSource` is narrower: **only `mailbox` is a valid
`includedSources` value** — the v1.0 "Create userSource" reference states this explicitly ("Only
`mailbox` is applicable for user sources") [[R2]](#references-design). A SharePoint or OneDrive
site is added as a **separate `siteSource`** object, keyed by the site's `webUrl`
[[R3]](#references-design), not folded into the userSource the way the custodian shape folds
OneDrive into the person. This scenario's `deploy/New-EdiscoveryLocationHold.ps1` therefore always
sends `includedSources = 'mailbox'` for every userSource and treats `siteSources[]` in the
definition file as its own independent list — this is a resolved design decision grounded directly
in the v1.0 reference's own wording, not a guess.

## 3. Distribution-list expansion — grounded but flagged

A hold organized around "a regulatory-sweep distribution list" needs the API to either (a) accept
a group's own SMTP address as a `userSource.email` and expand it server-side to member mailboxes,
or (b) require the caller to resolve membership and add each mailbox individually. Two pieces of
Microsoft's own documentation point at (a):

- The **beta**, custodian-context `userSource` reference explicitly documents `email` as "SMTP
  address of the user **or the SMTP address of the group mailbox**" [[R4]](#references-design).
- Microsoft's **"Manage hold status errors"** table documents a **"Distribution group has too many
  members"** error — "more than 1,000 email addresses can't be expanded and placed on hold" —
  which only makes sense if a distribution list's own address is an accepted, server-expanded
  input somewhere in the hold pipeline [[R5]](#references-design).

The v1.0, non-beta "Create userSource" reference for the `ediscoveryHoldPolicy` context (the one
this scenario's script actually calls) does **not** explicitly repeat the "or group mailbox"
language — it documents `email` only as "SMTP address of the user." This scenario's
`deploy/policy/location-hold-definition.json` sample includes a distribution-list email in
`userSources[]` on the strength of the two corroborating references above, but this is recorded as
an explicit `README.md` §11 VERIFY rather than presented as v1.0-confirmed, per `AGENTS.md` §4 —
the same "beta worked example + indirect corroboration, not a direct v1.0 confirmation" pattern
the sibling scenario already used for its own `includedSources` combined-string VERIFY.

**The 100-member vs. >1,000-member cap discrepancy, re-grounded and not reconciled.** A later
build (`teams-group-hold-resolution/README.md` §11) surfaced a second, smaller figure: "Create
holds in eDiscovery" states the **portal's** own interactive data-source picker — "all current
members of the distribution group are listed [with a checkbox]... Distribution list expansion is
limited to a maximum of 100 members. If a distribution list contains more than 100 members, the
expansion might fail" — for "every supported group type — distribution list, mail-enabled
security group, Microsoft 365 group, Microsoft Teams group, and Viva Engage group"
[[R12]](#references-design). Re-fetching both pages directly (2026-09-04) confirms neither is
stale or superseded: both are the current, non-legacy "Create holds in eDiscovery" and "Manage
holds in eDiscovery" articles, and the >1,000-member figure lives in the latter's still-current
"Manage hold status errors" table, not an older page as originally suspected when this VERIFY was
first logged. Microsoft's text does not cross-reference the two figures or state they're the same
limit measured two ways. Read literally, they describe two different steps of the pipeline: the
**100-member** figure is the portal's own member-**enumeration/checkbox-picker** UI, scoped to
"every supported group type"; the **>1,000-member** figure is a **hold-application/retry** error
surfaced on the **Hold policy Details** tab after a hold is applied, scoped to "distribution
group" specifically. Nothing in either page states whether the picker's 100-member ceiling and the
application-time 1,000-address error are the same underlying limit reported at two different UI
moments, or two independent limits on two different code paths — and this scenario's own script
never goes through the portal picker at all (it calls the v1.0 `ediscoveryHoldPolicy` REST
`userSources` endpoint directly), so neither figure is confirmed to govern *this* code path
either. Per `AGENTS.md` §4, this is recorded as an open VERIFY rather than resolved by picking
whichever page reads as more authoritative: `README.md` §11 and §8 now cite **both** figures
side by side, treat **100 members** as the conservative planning/KPI threshold (it is the smaller
number and the one Microsoft ties to "every supported group type," which covers the
Teams/Microsoft 365 Group population `teams-group-hold-resolution` also produces), and keep the
>1,000-member error string as the specific, documented condition the validate script's `errors`
check should recognize by name. A buyer who already knows a distribution list is near either
threshold should resolve and list individual member mailboxes instead of relying on server-side
expansion, both to stay clear of whichever cap actually applies and because this script doesn't
detect or report a partial-expansion failure beyond surfacing the policy's own `errors`
collection.

## 4. No v1.0 enable/disable — the real API gap this scenario is built around

The Purview portal exposes **Turn on** / **Turn off** actions on a hold policy, independent of
deleting it [[R6]](#references-design). The Graph API mirrors this — `enablePolicy` and
`disablePolicy` actions exist, are asynchronous, and are tracked via the policy's own `isEnabled`
property — but **both actions exist only in the `/beta` namespace**
[[R7]](#references-design)[[R8]](#references-design). Neither has a v1.0 equivalent, and neither
appears in the v1.0 `ediscoveryHoldPolicy` resource's own documented method list
[[R9]](#references-design). `docs/automation-surface.md` §2 directs this library's shipped
automation to pin to v1.0 and avoid `Microsoft.Graph.Beta.*` — beta endpoints "can change without
notice" — so this scenario does not call `enablePolicy`/`disablePolicy`, and as a direct
consequence, **`Remove-EdiscoveryLocationHold.ps1` has no reversible "pause" stage**: v1.0 only
exposes deleting an individual source (permanently releasing that one location) or deleting the
entire policy object (permanently releasing all of them). This is disclosed as a first-class
architectural fact in `README.md` §9/§11 and `rollback.md`, not silently worked around by calling
the beta action anyway — a customer who genuinely needs a reversible on/off toggle for a hold
policy should be told that capability is beta-only today, not sold a v1.0 automation that quietly
depends on it.

**Re-verified 2026-09-04, promotion status unchanged.** A `PROGRESS.md` follow-up asked to
periodically re-check whether `enablePolicy`/`disablePolicy` have since been promoted to v1.0. A
fresh direct fetch of the v1.0 `ediscoveryHoldPolicy` resource page's method table
[[R9]](#references-design) still lists only List/Create/Get/Update/Delete/`retryPolicy`/site
sources/user sources — no enable or disable action. A follow-up search for
`ediscoveryHoldPolicy enablePolicy disablePolicy v1.0` returns exclusively
`?view=graph-rest-beta`-namespaced result pages, each still carrying the standard "APIs under the
`/beta` version ... are subject to change" banner. The v1.0 Update reference
[[R9b]](#references-design) was also re-checked as the one remaining candidate workaround (a PATCH
that sets `isEnabled` directly instead of calling a dedicated action) — its documented updatable
property set is still exactly `contentQuery`/`description` only; `isEnabled` is not
PATCH-settable on v1.0 either. No promotion has occurred and no alternate v1.0 path to a
reversible pause exists. This finding was already correctly disclosed before this re-check
(`README.md` §9/§11, this section, above) and required no correction — recorded here, and in
`reviews.md`, as a closed re-verification rather than a new architectural finding.

## 5. Idempotency design

| Object | Lookup key | Why this key |
|---|---|---|
| Case | `displayName` (exact match, client-side) | Same rationale as `premium-legal-hold-and-export/design.md` §4 — no documented uniqueness-filter API |
| Hold policy | `displayName` within the case's `legalHolds` list | No documented uniqueness filter for hold-policy names either; the v1.0 API exposes no `Get` by name, only `List` + `Get by id`, so this script always lists and filters client-side |
| userSource | `email` within the hold's `userSources` list | The one identifying property the v1.0 resource exposes for this purpose |
| siteSource | site title (parsed from the definition file's URL, matched against the returned `displayName`) | **Weakest link in this design** — see §6 below |
| retryPolicy | not idempotency-gated; only called with `-Retry`, and only when the policy's `errors` collection is non-empty or a source isn't `applied`/`applying` | Retrying a healthy policy is a documented no-op-shaped restamp, but this script still gates it to avoid generating unnecessary restamp operations on every re-run |

## 6. `siteSource` matching is a known weak point

The `siteSource` resource's `id` is an opaque identifier and its `displayName` is the SharePoint
site's **title**, not its URL [[R3]](#references-design) — but the only value this scenario's
definition file (and the only value a buyer naturally has on hand) is the site's `webUrl`. Neither
the `List siteSources` nor the `Create siteSource` v1.0 reference documents a `webUrl` field on the
*response* object, so there's no direct URL-to-URL comparison available for find-or-create
matching. `deploy/New-EdiscoveryLocationHold.ps1` and `validate/Test-EdiscoveryLocationHold.ps1`
both fall back to parsing the last path segment of the definition file's URL and comparing it
against the returned `displayName`, on the assumption that a site's URL slug and its title are the
same string — true for the common case (a site created with **Create site** using its intended
name) but not guaranteed, and silently wrong if someone renames the site's title without changing
its URL, or vice versa. This is disclosed here and in `README.md` §11 rather than presented as a
robust match; a production deployment with sites whose titles and URL slugs diverge should treat a
"siteSource not found" `FAIL` from the validate script as ambiguous (confirm in the portal) rather
than conclusive.

## 7. Component summary

| Component | Purpose | Idempotency mechanism |
|---|---|---|
| `deploy/New-EdiscoveryLocationHold.ps1` | Case + hold policy + userSources + siteSources, with optional `retryPolicy` | Find-or-create by key (§5); hand-rolled `$PSCmdlet.ShouldProcess()` around every `Invoke-MgGraphRequest` write (no typed cmdlet exists for these endpoints — §4) |
| `deploy/Remove-EdiscoveryLocationHold.ps1` | Staged rollback: remove named sources, or delete the whole policy | Each stage gated by an explicit parameter; no "disable" stage exists on v1.0 (§4) |
| `deploy/policy/location-hold-definition.json` | Declarative case/hold/userSources/siteSources definition | Single source of truth both scripts read |
| `validate/Test-EdiscoveryLocationHold.ps1` | Read-only proof the case/hold/sources match the definition file and report no errors | `eDiscovery.Read.All` only; never calls a mutating endpoint |

## 8. Non-goals (explicitly out of scope for this fragment)

- **Custodian-scoped holds** — covered by [`ediscovery/premium-legal-hold-and-export`](/scenarios/ediscovery/premium-legal-hold-and-export/).
  A matter needing both a named-custodian hold and a location-scoped sweep in the same case can
  run both scenarios' deploy scripts against the same `-CaseId`; nothing in either script assumes
  it owns the case exclusively.
- **Microsoft Teams / Microsoft 365 Group holds via this object.** Microsoft's guidance for
  holding a Team or group is to add the group's own mailbox and SharePoint site as data sources
  (resolved via `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` in Exchange Online PowerShell)
  [[R10]](#references-design) — mechanically a userSource + siteSource pair this scenario's script
  can already accept, but resolving *which* group/site pair to use from a Team name is a distinct,
  separately scoped lookup this fragment doesn't automate.
- **`enablePolicy`/`disablePolicy`** — beta-only; see §4. Not called from this scenario's
  supported-surface deploy/rollback scripts.
- **Condition filters and KeyQL filters beyond `contentQuery`** — the portal's hold-policy editor
  exposes richer condition-filter UI than the single `contentQuery` string this scenario's
  definition file models [[R11]](#references-design); this scenario covers the API-documented
  property, not the full portal filter surface.
- **Splitting a distribution list that already exceeds the 1,000-member expansion cap** — see §3.
  A buyer who hits the "Distribution group has too many members" error needs to resolve and list
  individual member mailboxes; this scenario doesn't implement that resolution/splitting logic.
- **Search, review set, and export against this hold's preserved content** — the sibling
  scenario's `deploy/New-EdiscoverySearchReviewSetExport.ps1` already covers that pipeline and
  works against any case regardless of which hold mechanism populated it; not duplicated here.

## References {#references-design}

- R1. Manage holds in eDiscovery (hold policy dashboard, states, data source types) — <https://learn.microsoft.com/purview/edisc-hold-manage>
- R2. Create userSource (v1.0, `ediscoveryHoldPolicy` context — `includedSources` "Only mailbox is applicable for user sources") — <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-usersources?view=graph-rest-1.0>
- R3. siteSource resource type (v1.0 — `displayName` is the site's title; `site` relationship) — <https://learn.microsoft.com/graph/api/resources/security-sitesource?view=graph-rest-1.0>
- R4. Create legalHold userSource (beta, custodian/legalHold context — "SMTP address of the user or the SMTP address of the group mailbox") — <https://learn.microsoft.com/graph/api/ediscovery-legalhold-post-usersources?view=graph-rest-beta>
- R5. Manage holds in eDiscovery — "Manage hold status errors" (Distribution group has too many members, >1,000 addresses; current page, re-fetched 2026-09-04) — <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>
- R6. Manage holds in eDiscovery — "Turn off a hold policy" / "Turn on a hold policy" (portal actions, independent of delete) — <https://learn.microsoft.com/purview/edisc-hold-manage#turn-off-a-hold-policy>
- R7. ediscoveryHoldPolicy: enablePolicy (beta only) — <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-enablepolicy?view=graph-rest-beta>
- R8. ediscoveryHoldPolicy: disablePolicy (beta only) — <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-disablepolicy?view=graph-rest-beta>
- R9. ediscoveryHoldPolicy resource type (v1.0 — documented method list has no enable/disable action; re-fetched 2026-09-04, unchanged) — <https://learn.microsoft.com/graph/api/resources/security-ediscoveryholdpolicy?view=graph-rest-1.0>
- R9b. Update ediscoveryHoldPolicy (v1.0 — updatable properties are `contentQuery`/`description` only; `isEnabled` is not PATCH-settable; re-checked 2026-09-04) — <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-update?view=graph-rest-1.0>
- R10. Manage holds in eDiscovery — "Place a hold on Microsoft Teams and Microsoft 365 groups" (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks`) — <https://learn.microsoft.com/purview/edisc-hold-manage#place-a-hold-on-microsoft-teams-and-microsoft-365-groups>
- R11. Manage holds in eDiscovery — "Edit a hold policy" (data sources, condition filters, KeyQL filters as separate, richer portal concepts) — <https://learn.microsoft.com/purview/edisc-hold-manage#edit-a-hold-policy>
- R12. Create holds in eDiscovery — "Create a hold" (portal data-source picker: distribution list expansion "limited to a maximum of 100 members," applies to every supported group type; current page, re-fetched 2026-09-04) — <https://learn.microsoft.com/purview/edisc-hold-create#create-a-hold>
