---
title: "Curate a Business Glossary"
fullTitle: "Unified Catalog — Curate a Business Glossary"
category: "Unified Catalog"
categorySlug: "unified-catalog"
slug: "curate-business-glossary"
repoPath: "scenarios/unified-catalog/curate-business-glossary"
parts: ["design","deploy","validate","rollback"]
related: []
deployCount: 3
validateCount: 1
---
## 1. Scenario summary

Stands up a governance domain and its business glossary — a hierarchy of defined terms with
owners, experts, acronyms, resources, and term-to-term relationships — in Microsoft Purview
Unified Catalog, driven by a single declarative JSON file checked into source control instead of
one-at-a-time portal clicks. The deploy script is a true idempotent upsert: re-running it after
editing a term's definition reconciles the existing term in place rather than creating a
duplicate, something the portal's own bulk-import feature explicitly cannot do (§11).

**Who it's for:** a data governance or platform team standing up Unified Catalog for the first
time (or extending an existing one), who wants their glossary defined, reviewed, and versioned the
same way the rest of their infrastructure is — via a pull request — rather than as tribal
portal-click knowledge held by whoever happened to create each term.

## 2. Business/regulatory driver

A governed, shared vocabulary is the prerequisite every later Unified Catalog capability builds
on: glossary terms carry the policies that scale data governance to data products and assets
[[1]](#12-references), and Microsoft's own Cloud Adoption Framework guidance for Purview names
**"populate the glossary"** as the second step of the data-visibility baseline — right after
standing up governance domains and before mapping data sources — specifically to harmonize terms
like *Customer*, *Product*, *Employee*, *Location*, *Revenue*, and *Headcount* that otherwise mean
different things to different departments [[2]](#12-references).

This is a **foundational governance-maturity driver**, not a specific technical control tied to
one regulation — but it directly supports:
- **GDPR/CCPA data-mapping obligations** — a governed *Customer* / *Customer ID* definition is
  what lets a later Data Products or Critical Data Elements scenario correctly scope which assets
  hold regulated personal data, rather than each team guessing independently.
- **SOC 2 / ISO 27001 change-management evidence** — every domain and term change in this
  scenario's model is a reviewable JSON diff in a pull request, not an unaudited portal edit.
- **CDMC (Cloud Data Management Capabilities)** — Unified Catalog's own data-estate-health surface
  tracks control maturity against **CDMC control templates** [[3]](#12-references); a curated
  glossary is a direct input to several of those controls (ownership, business-context, lineage
  intelligibility).

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md`. Summary for this scenario:

| Requirement | Minimum | Notes |
|---|---|---|
| Unified Catalog data governance | **Pay-as-you-go (PAYG)**, billed on unique **governed assets/day** | See §10 — creating a domain and glossary terms with **no** data assets attached costs **nothing**; the meter only starts once a term/domain is linked to an actual data asset [[4]](#12-references) |
| Azure subscription + resource group | Same tenant as the Purview account | Required to enable Purview PAYG billing at all [[5]](#12-references) |
| Role to author the domain (if it doesn't exist yet) | **Governance Domain Creator** (Unified Catalog catalog-level role) | `docs/rbac-model.md` §5 |
| Role to author terms in an existing domain | **Data Steward** (governance-domain-level role, assigned on the domain's **Roles** tab — a *different* role model from Data Map collections) | `docs/rbac-model.md` §5 |
| Automation identity (Unified Catalog) | App registration whose service principal is assigned **Data Steward** (and **Governance Domain Creator** if the domain must be created) in Unified Catalog's **Roles and permissions** / the domain's **Roles** tab | Client-credentials OAuth2 against resource `https://purview.azure.net` — see `docs/automation-surface.md` §3 |
| Automation identity (Microsoft Graph) | Same app registration, granted the **`User.Read.All`** Graph **application** permission with admin consent | Needed only to resolve owner/expert UPNs to Entra object IDs (§5 of `design.md`) — least-privileged app permission documented for reading any user by ID/UPN [[6]](#12-references) |

> Verify current entitlement names against `docs/licensing-matrix.md` and the Product Terms before
> a sales commitment — SKU names and PAYG meters change.

**Compensating controls for `User.Read.All`:** this is a tenant-wide **read-any-user** grant —
Microsoft Graph publishes no narrower application permission for "resolve a UPN to an object ID"
(§11 Known limitations expands on this). Because a compromised client secret for this app would
therefore expose basic profile data for every directory user, not just the glossary's owners,
treat the secret with the same handling as any tenant-wide read credential: short expiry, rotation
via a vault (never checked into the definition file or the repo), and — separately — scope the
Unified Catalog **Data Steward**/**Governance Domain Creator** role assignment itself to only the
governance domain(s) this automation is meant to curate, not tenant-wide, so a leaked credential's
blast radius on the Purview side stays bounded even though the Graph side cannot be narrowed
further.

## 4. Architecture

```mermaid
flowchart TD
    A[glossary definition JSON<br/>domain + terms, in source control] --> B[New-BusinessGlossary.ps1]
    B --> C{Governance domain<br/>exists by name?}
    C -- No --> D[POST businessdomains<br/>DRAFT status]
    C -- Yes --> E[Reuse existing domain id]
    D --> F
    E --> F[For each term: resolve owners/experts]
    F -->|UPN| G[Microsoft Graph<br/>GET /users/{upn}?$select=id]
    F -->|already a GUID| H[Use as-is]
    G --> I
    H --> I{Term exists by<br/>exact name in domain?}
    I -- No --> J["POST terms (Create)<br/>client-generated id, DRAFT"]
    I -- Yes --> K["PUT terms/{id} (Update)<br/>reconcile in place"]
    J --> L[Wire declared<br/>Related term relationships]
    K --> L
    L --> M{-Publish?}
    M -- No --> N[Left in DRAFT -<br/>visible to Data Stewards only]
    M -- Yes --> O[PUT status: PUBLISHED<br/>domain, then every term]
    O --> P[Visible catalog-wide -<br/>Enterprise glossary, search]
```

One Unified Catalog governance domain, authored via the **Purview Unified Catalog REST API**
(`docs/automation-surface.md` surface 4), containing a small hierarchy of glossary terms. Term
identity resolution for owners/experts is the one place this scenario also calls **Microsoft
Graph** (surface 3) — see `design.md` §5.

## 5. Step-by-step implementation

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Governance domains** → **New Governance domain**.
2. Name: `Customer Experience`. Type: **Functional unit**. Leave parent blank. **Create**.
3. On the new domain's **Roles** tab, confirm you (and any Data Stewards) are assigned; add the
   automation service principal as **Data Steward** here for the script path below.
4. On the domain's **Details** tab, **Glossary terms** card → **View all** → **New term**.
5. Create `Customer` with its definition, an owner, and a resource link; **Create**, then
   **Publish** once reviewed. Repeat for `Customer ID` and `Customer Lifetime Value`, selecting
   `Customer` as **Parent term** for both; repeat for `Net Promoter Score` with no parent
   [[7]](#12-references).
6. On `Customer Lifetime Value`'s **Related** tab, **Add term** → select `Net Promoter Score` as a
   **Related term** [[7]](#12-references).
7. **Publish** the governance domain itself (required before its terms are visible tenant-wide)
   [[8]](#12-references).

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every change, makes none (still performs read-only lookups against the
#    live tenant to accurately report create-vs-update - see README.md Section 11)
./deploy/New-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json' -WhatIf

# 2. Deploy in DRAFT status (default) for review
./deploy/New-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json'

# 3. After review, publish
./deploy/New-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json' -Publish

# 4. Validate
./validate/Test-BusinessGlossary.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -GlossaryDefinitionPath './deploy/glossary/customer-experience-glossary.json'
```

The deploy script uses the Purview Unified Catalog REST API directly (`Invoke-RestMethod`) —
automation surface 4 per `docs/automation-surface.md` §1; there is no PowerShell cmdlet module for
Unified Catalog term authoring today. It also calls Microsoft Graph (surface 3) once per
not-already-a-GUID owner/expert identity, cached per run so the same person is resolved only once.

## 6. Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Governance domain | `type` | `FunctionalUnit` \| `LineOfBusiness` \| `DataDomain` \| `Regulatory` \| `Project` | Descriptive only — Microsoft documents no behavioral difference between types [[9]](#12-references) |
| Governance domain | `status` | `DRAFT` → `PUBLISHED` | Must be `PUBLISHED` before any of its terms can be published [[8]](#12-references) |
| Term | `id` | Client-generated GUID | The API has no server-assigned, name-derived identity — see `design.md` §4 for why this matters for idempotency |
| Term | `contacts.owner[].id` / `.expert[].id` | Entra object ID (AAD oid) | **Not** an email address — resolved from the definition file's UPN by this script (`design.md` §5) |
| Term | `parentId` | Another term's `id`, same domain | Portal calls this "Parent term"; up to five levels of domain nesting are supported tenant-wide, but term hierarchy depth itself isn't separately documented as limited |
| Term relationship | `relationshipType` | `Related` \| `Synonym` \| `Parent` | This scenario's script only wires `Related` (§4 of this README); `Synonym` and portal-driven `Parent` (set via `parentId` instead) are the other two |
| Term / domain | `status` lifecycle | `DRAFT` → `PUBLISHED` → `EXPIRED` | `EXPIRED` ("Set to Expired") is a soft-retire step this scenario doesn't script — see §9 |

Full request/response shapes: `deploy/New-BusinessGlossary.ps1`'s inline comments and `.NOTES`
block cite the exact Microsoft Learn REST reference pages for every operation used.

## 7. Validation / how to prove it works

1. **Automated check** — `./validate/Test-BusinessGlossary.ps1` confirms the domain and every term
   exist with the expected type/description/acronyms/parent/owner-contact/relationships, exits
   non-zero on any hard failure (safe for a CI-style pre-flight). Publish status is reported as a
   warning, not a hard failure, since DRAFT is a valid pre-review state.
2. **Portal check** — Purview portal → Unified Catalog → the `Customer Experience` domain →
   **Glossary terms** → **View all** → switch the view to **Tree** to visually confirm the
   `Customer` → `Customer ID` / `Customer Lifetime Value` hierarchy [[10]](#12-references).
3. **Enterprise glossary check (after `-Publish`)** — Unified Catalog → **Discovery** → **Enterprise
   glossary** → **Glossary terms** tab; confirm all four terms appear and are searchable by a
   **Catalog Reader**-only account (not just Data Stewards) [[11]](#12-references).
4. **Relationship check** — open `Customer Lifetime Value`'s **Related** tab in the portal and
   confirm `Net Promoter Score` appears as a related term.

## 8. Operations & tuning

**Review-before-publish workflow:** this script's default (`DRAFT`, no `-Publish`) intentionally
mirrors Unified Catalog's own two-step create-then-publish model — a term in `DRAFT` is visible
only to Data Stewards and Governance Domain Owners [[7]](#12-references), giving a human review
point (a PR review of the JSON diff, then a deliberate `-Publish` run) before a term becomes
visible catalog-wide. A buyer with a mature governance practice can additionally configure
Unified Catalog's native **Term publish workflow** (Process automation → Workflows → Catalog
curation → Term publish), which adds an in-portal maker-checker approval gate on top of the
`DRAFT`→`PUBLISHED` transition [[12]](#12-references) — this is portal-only (§11) and complements,
rather than replaces, this script's own review-before-`-Publish` discipline.

**Re-running after an edit:** change the definition file (add a term, edit a description, add an
owner) and re-run `New-BusinessGlossary.ps1` without `-Publish` first — review the change, then
re-run with `-Publish`. Never edit a published term directly in the portal and expect this
script's next run to "know" about it: the script's create/update path always reconciles the term
**to the definition file's current content** (not a merge), so a portal-made edit not reflected in
the file will be overwritten on the next deploy run. (The narrower `-Publish`-only status
transition does **not** have this problem — see `design.md` §5's `ConvertTo-TermUpdateBody`
design note.)

**Governance domain sprawl:** Unified Catalog supports up to 200 domains and five levels of
hierarchy depth tenant-wide [[9]](#12-references). Track domain count as an operational metric
once multiple teams start self-service authoring — a domain-per-small-team pattern can approach
that ceiling faster than expected in a large enterprise; consider domain hierarchies (parent/child)
before the ceiling is hit, not after.

**Ownership hygiene:** every term should have at least one owner (this script warns, but does not
hard-fail, if `owners` is empty in the definition file — an ownerless term is valid at the API
level but defeats the accountability purpose of the glossary). Review the `contacts.owner` field
via `validate/Test-BusinessGlossary.ps1` as part of any periodic glossary health review. Note that
owner resolution (§5 of `design.md`) only confirms the UPN resolves to **an** Entra account — it
does not confirm that account is still active or still the right owner. A departed employee whose
account is disabled but not yet deleted resolves successfully and is silently assigned as owner
indefinitely; fold a glossary-owner review into the same offboarding/access-review process that
already re-points other Purview role assignments (`docs/rbac-model.md` §9), rather than treating
glossary ownership as self-maintaining.

**Change attribution and drift detection:** every term and domain object returned by the API
carries `systemData.createdBy`/`createdAt`/`lastModifiedBy`/`lastModifiedAt` (Entra object IDs and
timestamps) — this is the built-in point-in-time attribution for "who last touched this," queryable
via a plain `GET`, though Microsoft documents no full change-history/diff API beyond that single
last-modified snapshot. Because this script's create/update path always reconciles a term to
exactly the definition file's content (§8, "Re-running after an edit"), running
`validate/Test-BusinessGlossary.ps1` on a schedule (a CI cron job, not just after a deploy) doubles
as drift detection: a portal-made edit that hasn't been reflected back into the definition file
will show up as a content-mismatch `[FAIL]` before the next scripted deploy silently overwrites it.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure (unpublish → purge). Quick reference:
`./deploy/Remove-BusinessGlossary.ps1` unpublishes the domain and its terms (reversible); add
`-Purge` to permanently delete them.

## 10. Cost & licensing notes

- **This scenario, by itself, costs nothing beyond the base Purview PAYG enablement.** Unified
  Catalog's billing meter counts **governed assets** — a data asset (table, file, report) actively
  linked to a governance concept (data product, critical data element, glossary term) — **not**
  the governance domain or glossary term objects themselves [[4]](#12-references). Microsoft's own
  billing FAQ states this explicitly: "you create 50 governance domains and data products, but
  don't attach any tables, files, reports, or dashboards... you aren't charged for any governed
  assets" [[13]](#12-references). This scenario creates a domain and four terms with **zero**
  linked data assets, so it incurs **no PAYG charge** on its own.
- **Cost activates later**, once a future scenario (e.g. linking these terms to data products or
  Data Map-scanned assets — `PROGRESS.md` follow-up) actually attaches a data asset to a term or
  product. At that point, billing is **per unique governed asset per day**, deduplicated across
  however many governance concepts reference the same asset (an asset in five data products is
  still billed once) [[4]](#12-references).
- **No per-user license required.** Unlike the DLP/Information Protection scenarios in this
  library, Unified Catalog curation is PAYG-only — it doesn't require Purview E5-tier per-user
  entitlements (`docs/licensing-matrix.md` §2).

## 11. Known limitations & gotchas

- **Portal-only "Term publish" approval workflow.** Microsoft ships an in-portal maker-checker
  workflow for term/data-product publishing (§8) but publishes no REST/PowerShell surface for
  *authoring* workflow definitions as of this build. This script's `-Publish` flag performs the
  same `DRAFT`→`PUBLISHED` transition a workflow would eventually gate — if a buyer configures the
  native publish workflow, running this script's `-Publish` against a domain in scope for that
  workflow submits the transition for approval rather than completing it immediately; confirm the
  resulting behavior in a pilot tenant before assuming synchronous publish.
- **Two Purview portal generations, two different base URLs.** This scenario's `-PurviewAccountEndpoint`
  parameter must be `https://api.purview-service.microsoft.com` for tenants on the current
  Microsoft Purview portal, or `https://<account>.purview.azure.com` for the classic portal
  [[14]](#12-references) — passing the wrong one for a given tenant will fail authentication or
  routing, not silently succeed against the wrong data.
- **`-WhatIf` still performs live, read-only calls.** Unlike some scenarios in this library whose
  dry-run path needs no tenant connectivity at all, this script's existence checks (Query Terms,
  Enumerate Business Domains) are **not** gated behind `ShouldProcess` — they must run for real,
  even under `-WhatIf`, so the script can accurately report "would create" vs. "would update".
  Only the mutating POST/PUT/DELETE calls are suppressed. A `-WhatIf` run therefore still requires
  a reachable tenant and a valid token.
- **VERIFY — `nameKeyword` match semantics.** The Query Terms filter's exact matching behavior
  (substring / prefix / tokenized) isn't documented by Microsoft. This script always re-checks for
  an exact, case-insensitive name match in the returned page rather than trusting the filter
  alone (`design.md` §4) — safe against a false-positive match, but a domain with more
  name-matching terms than fit in one page (`top`, capped at 50 by this script) could in principle
  miss an existing term past that page. This scenario's four-term glossary never approaches that
  limit; a much larger rollout should confirm pagination behavior first.
- **VERIFY — Business Domain Create/Update "required" fields.** The formal REST reference marks
  `systemData`, `thumbnail`, `domains`, and `managedAttributes` as required in the request body for
  both operations — a claim that contradicts Microsoft's own worked examples (which omit several
  of these) and ordinary REST semantics (a create call cannot require the caller to supply
  server-computed system metadata like `systemData.createdAt`). This script sends the minimal,
  practical body pattern used in Microsoft's Unified Catalog disaster-recovery article instead.
  Confirm against a pilot tenant if a tenant's API instance rejects the minimal body.
- **This scenario does not link terms to data products, data assets, or columns.** That requires
  the target assets to already exist and the automation identity to also hold **Data Reader** on
  the assets' Data Map collection — a natural follow-up scenario once this library has a Data
  Products scenario (`PROGRESS.md`); see `design.md` §7 for the full non-goal list.
- **Update Term is a full-replace `PUT`, not a merge `PATCH`.** Every field this script doesn't
  explicitly send in a create/update call is implicitly cleared by the API on that call — the
  script's body builders (`New-TermRequestBody`, `ConvertTo-TermUpdateBody`) are written to always
  include the complete intended state for exactly this reason. A hand-written call to the API that
  doesn't follow the same discipline will silently drop fields.

## 12. References

1. Glossary terms in Unified Catalog (active terms, policies, scaling data governance) — <https://learn.microsoft.com/purview/unified-catalog-glossary-terms>
2. Data governance and security baselines with Microsoft Purview — data visibility baseline, "populate the glossary" step — <https://learn.microsoft.com/azure/cloud-adoption-framework/data/governance-security-baselines-purview-data-estate-unify-data-platform>
3. Disaster recovery for Unified Catalog (manual) — data estate health, CDMC control templates — <https://learn.microsoft.com/purview/unified-catalog-disaster-recovery>
4. Learn about data governance billing (governed assets, what counts, what doesn't) — <https://learn.microsoft.com/purview/data-governance-billing>
5. Learn about Microsoft Purview billing models (PAYG, Azure subscription prerequisite) — <https://learn.microsoft.com/purview/purview-billing-models>
6. Get a user (Microsoft Graph) — `User.Read.All` application permission — <https://learn.microsoft.com/graph/api/user-get>
7. Create and manage glossary terms — create, publish, related terms, DRAFT visibility — <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage>
8. Create and manage governance domains — publish domain before publishing its terms — <https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage>
9. Governance domains in Unified Catalog — domain types, 200-domain / 5-level hierarchy limit — <https://learn.microsoft.com/purview/unified-catalog-governance-domains>
10. Create and manage glossary terms — Tree view for parent/child hierarchy — <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage#access-glossary-terms>
11. Enterprise glossary (preview) — Catalog Reader role, published-concept discovery — <https://learn.microsoft.com/purview/unified-catalog-enterprise-glossary>
12. Create workflows to automate processes in Unified Catalog — Term publish workflow, Governance Domain Creator prerequisite — <https://learn.microsoft.com/purview/unified-catalog-workflows>
13. Data governance billing frequently asked questions — unattached domains/data products aren't charged — <https://learn.microsoft.com/purview/data-governance-billing-faq>
14. Migrate governance private endpoints from classic portal to Microsoft Purview portal — the two API endpoint hosts — <https://learn.microsoft.com/purview/data-governance-private-endpoints-migrate>
15. Purview Unified Catalog REST API — Terms operation group (Create/Update/Delete/Get/List/Query/AddRelatedEntity/ListRelatedEntities/Count) — <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
16. Purview Unified Catalog REST API — Business Domain operation group (Create/Update/Delete/Get/Enumerate) — <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
17. Unified Catalog API (Public Preview) overview — scope, GA-only coverage, preview API versions — <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
18. Tutorial: Authenticate for APIs — service principal setup, Unified Catalog role assignment, client-credentials token flow — <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
19. Data governance roles and permissions in Microsoft Purview — Data Steward, Governance Domain Creator/Owner, Catalog Reader — <https://learn.microsoft.com/purview/data-governance-roles-permissions>
20. Microsoft identity platform and the OAuth 2.0 client credentials flow — v2.0 token endpoint, `scope=.default` — <https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement — this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), which
> Microsoft explicitly documents as covering only GA Unified Catalog features and subject to
> change before general availability [[17]](#12-references).
