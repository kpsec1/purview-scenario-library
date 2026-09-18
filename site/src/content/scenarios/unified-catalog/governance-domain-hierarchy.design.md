---
part: "design"
parent: "unified-catalog/governance-domain-hierarchy"
---
## 1. Problem statement

`scenarios/unified-catalog/curate-business-glossary/` deliberately scoped itself to **one**
standalone governance domain (`design.md` Section 6 there), leaving "multi-domain governance
hierarchies, custom attribute groups, and data estate mappings to Data Map collections" as an
explicit follow-up (`PROGRESS.md`). A single flat domain does not survive contact with a real
enterprise: Microsoft's own sample data-governance walkthrough models exactly this next step, a
**Corporate** parent domain with **Sales** as a child, because "these domains are key points of
federation for collaboration and governance in your organization"
. This scenario builds that parent/child domain tree, applies
admin-defined business-concept attribute values to each domain, and (optionally) records a
recommended Data Map collection for each domain via the **Data estate mappings** relationship, 
all from one declarative JSON file, idempotently.

## 2. Design goals

1. Author a **domain tree** (a root domain plus nested child domains, up to Microsoft's documented
 five-level depth ceiling) from a single JSON file, in one script run, not one domain per portal
 session.
2. Set **business concept attribute values** (`managedAttributes`) on each domain from the same
 file. This scenario does **not** create the attribute *definitions* themselves, see Section 7.
3. Optionally record a **data estate mapping**, the recommended Data Map collection for a domain, 
 using the Business Domain object's own `domains[].relatedCollections[]` structure, with the
 ambiguity that construction carries (Section 5) disclosed rather than guessed past.
4. Idempotent: re-running with an unchanged file makes no mutating calls; re-running after editing
 a domain's description, attributes, or mapping reconciles it in place; re-running after adding a
 new child domain creates only that domain, leaving its siblings untouched.
5. Deletion must go **child-before-parent**, Microsoft's own portal guidance states a domain can
 only be deleted after "you unpublish it and delete all business concepts within it, **including
 any subdomains**", so `Remove-GovernanceDomainHierarchy.ps1`
 walks the tree in the reverse order this scenario's deploy script uses.
6. `-WhatIf` dry-run and DRAFT-by-default publish gating, matching this repo's code standard
 (`AGENTS.md` Section 4) and `curate-business-glossary`'s own precedent.

## 3. Why a full `Enumerate` pass, not a per-node lookup

The Business Domain operation group has no `Query`/name-filter operation, only `Enumerate`
(list all, paginated by `$skipToken`), unlike Terms' dedicated
`Query` operation `curate-business-glossary` uses. This scenario's deploy script therefore performs
**one** full, paginated `Enumerate` pass at the start of a run (identical pagination pattern to
`curate-business-glossary`'s own `Find-BusinessDomainByName`, generalized to page through every
domain instead of stopping at the first name match) and builds an in-memory `(name, parentId)`
lookup table before touching the tree. This is deliberate for two reasons this scenario adds beyond
the glossary scenario's single-domain lookup:

- **Name reuse across different parents is expected, not a bug.** The portal does not enforce
 unique domain names tenant-wide (mirroring the same non-uniqueness Terms already has,
 `curate-business-glossary/design.md` Section 4), a hierarchy with a `Sales` child under
 `Corporate` and an unrelated `Sales` child under a `Personal Health` domain elsewhere in the
 tenant is a realistic shape this scenario must not confuse. Matching on the **pair**
 `(name, parentId)`, not name alone, avoids reconciling the wrong domain.
- **A single pass amortizes the cost.** `Enumerate`'s 500-request/20-second rate limit is generous,
 but a tree of `N` domains looked up one-by-one with per-node pagination would cost `O(N × pages)`
 calls; one shared pass costs `O(pages)` regardless of tree size, then every node lookup is an
 in-memory hash lookup.

**VERIFY** (pilot tenant, before relying on this at a scale approaching the 200-domain ceiling):
`Enumerate`'s own reference documents no `$top`/page-size parameter, the page size and thus the
total call count for a very large tenant's full enumeration is not something this build could
confirm from the reference alone.

## 4. Idempotency and update semantics, reusing, not repeating, a known lesson

`curate-business-glossary/README.md` Section 11 already discloses that **Update Term is a
full-replace `PUT`, not a merge `PATCH`**, every field the caller's body omits is implicitly
cleared. That scenario's own `Publish-BusinessDomain` helper is a live example of *not* fully
following that discipline: it rebuilds the domain's update body from only
`id`/`name`/`description`/`type`/`status`, which would silently drop any `managedAttributes`,
`thumbnail`, or `domains` (data estate mapping) the domain already carried, had that scenario ever
set them.

This scenario does not repeat that gap. Its `Get-OrNewDomainNode` update path always starts from
the **domain object `Enumerate` already returned** (Section 3), which is a complete `Domain`
object, including any existing `managedAttributes`/`domains`/`thumbnail`, and layers the
definition file's declared attributes/mapping on top of that snapshot, rather than reconstructing
the body from only the fields this scenario's own JSON schema knows about. A domain whose portal
users have set a `thumbnail` color, for example, keeps that color across a re-run this scenario
performs, because the update body is seeded from the live object, not from the local file's schema.

**Residual gap, disclosed rather than fixed silently:** if a *different* automation (or a portal
user) adds a *second* business concept attribute to a domain between this script's `Enumerate` read
and its `Update` write, that attribute is still preserved (it's part of the object this script
seeded its body from), but only for the single run that already has that object in memory. A
long-running batch that processes hundreds of domains sequentially could, in principle, read a
domain early in the run and write it back late in the run after an out-of-band change happened
in between (a classic read-then-write race, not specific to this API). This scenario's tree sizes
are small enough that the window is negligible; a much larger rollout should re-`GET` the specific
domain immediately before each `Update` rather than relying on the batch-start `Enumerate` snapshot.

## 5. Data estate mapping, the ambiguous part, disclosed rather than guessed

The Business Domain object's request/response schema nests a `domains` array
(`CatalogModelPlatformDomain[]`) inside every Business Domain, each element carrying its own
`name`/`friendlyName` and a `relatedCollections[]` array (`CatalogModelRelatedCollection[]`, each
with `name`/`friendlyName`/`parentCollection.refName`/`parentCollection.type`)
. The portal-facing feature this almost certainly backs is
**Data estate mappings**, mapping a governance domain to "a specific Data Map collection," found
on the domain's own **Data estate mappings** tab, described as "recommended guidance" for stewards
and product owners rather than an access-control mechanism.

That correspondence is this build's own inference, not something Microsoft's REST reference states
directly. Two things support it: the nesting under a Business Domain object (Data estate mappings
are configured *per domain*, exactly this shape) and the field names themselves
(`relatedCollections`, `parentCollection`). But the reference provides **no prose description** for
what `domains[]` or `relatedCollections[].parentCollection.refName` actually mean, and, unusually
for this API surface, whose Terms/Data Products/Okr worked examples elsewhere in this library use
readable, plausible sample values, this specific operation's worked examples use meaningless
placeholder strings for these exact fields (`"eyznsozkzxsaft"`, `"jvtpbgjja"`,
`"kknzzmpwlwuoieiyorqybvd"`), unlike the same request's `name`/`description`/`parentId` fields,
which use realistic values. That inconsistency reads as generated placeholder filler for a nested
object the reference's authoring pipeline didn't hand-populate with a realistic worked example, 
a strong signal this specific nesting is thin on documentation, not that the feature is unsupported.

**This scenario's design decision:** ship the data estate mapping as an **opt-in**
(`dataEstateMapping` block in the definition file, omit it to skip entirely) rather than a required
part of every domain, with:
- `dataMapDomainName` → sent as `domains[].name` / `.friendlyName`.
- `collectionReferenceName` → sent as `domains[].relatedCollections[].name`.
- `collectionFriendlyName` → sent as `domains[].relatedCollections[].friendlyName`.
- `parentCollectionReferenceName` (defaults to `collectionReferenceName` if omitted) → sent as
 `domains[].relatedCollections[].parentCollection.refName`, with `.type` hardcoded to
 `CollectionReference` (the only enum value documented).

**VERIFY (pilot tenant) before relying on this in production**, flagged inline in the deploy
script's `.NOTES`, `README.md` Section 11, and here: whether `refName` must reference a *different*,
already-registered Data Map collection reference (e.g. a parent collection's technical name in
Data Map's own collection hierarchy) rather than the same collection's own name; whether the
mapping this script writes actually surfaces on the portal's **Data estate mappings** tab and
`Select a mapping` dropdown the way a portal-driven mapping would; and whether this operation
enforces that the named Data Map collection already exists (a dangling reference to a
not-yet-created collection is a plausible, undocumented failure mode). Until confirmed, treat this
script's `-SkipDataEstateMapping` switch (default: mapping is attempted; pass the switch to omit it
entirely) as the safer default for a first pilot-tenant run, and confirm the resulting state in the
portal (README.md Section 7) before trusting a scripted mapping unattended.

## 6. Custom attribute values, definitions are portal-only, values are not

Microsoft documents business concept attribute *definitions* (attribute groups, field types,
required flags, scope) as created exclusively through **Unified Catalog → Catalog management →
Custom metadata (preview)** by an admin, the Unified Catalog API's documented resource list
(Objectives/Key Results, Business Domains, Critical Data Elements, Data Products, Glossary Terms,
Data Access Policies, Data Assets, Data Columns) has no
"Attributes" resource of its own. This scenario's script can therefore only **set values** for
attributes an admin has already defined and scoped to include Governance Domains
, sending a `managedAttributes[].name` the tenant hasn't defined
yet fails at the API (an expected, not a script, error). See Section 7 for the explicit non-goal
this implies.

**Disclosed schema oddity, not resolved by guessing:** `CatalogModelManagedAttribute` includes an
`isRequired` boolean **on each value entry itself**
, an unusual place for a "required" flag to live, since
"required" is normally a property of the attribute *definition* (confirmed portal-only, above), not
of each domain's individual value for it. This script never sets `isRequired` in a request body (it
isn't meaningful input from this scenario's side); if the API ever echoes it back on a `GET`, treat
it as a read-only reflection of the admin-side definition, not a lever this automation controls.

## 7. Non-goals

- **Creating business concept attribute *definitions*, attribute groups, or their scope.**
 Portal-only, admin-role work (Section 6), this scenario assumes the attributes named in its
 definition file already exist and are scoped to Governance Domains.
- **Creating the target Data Map collection** a data estate mapping references. This scenario
 assumes the collection already exists in Data Map (see this repo's Data Map scenarios for
 collection/source provisioning); it only records the mapping on the Unified Catalog side.
- **Domain-level access policies** (the portal's **Configure access** / **Manage domain policies**
 action), a distinct Unified Catalog capability with its own review surface, same non-goal
 `curate-business-glossary/design.md` Section 7 already carves out for Term policies.
- **Glossary terms, data products, critical data elements, or OKRs within each domain**, this
 scenario stops at the domain tree itself; those are `curate-business-glossary`'s,
 `manage-data-products`'s, `manage-critical-data-elements`'s, and `manage-okrs`'s jobs
 respectively, each of which takes a `-DomainName` and can be pointed at any domain this scenario
 creates.
- **The portal's role assignment step** (adding Data Stewards/Data Product Owners on each domain's
 **Roles** tab), no REST operation for role assignment was found in this build's grounding pass;
 treated as a manual, per-domain follow-up step, same conclusion `curate-business-glossary`
 reached for its own single domain.
