---
part: "design"
parent: "unified-catalog/curate-business-glossary"
---
## 1. Problem statement

Every Unified Catalog rollout eventually needs a governed, shared vocabulary, "what do we mean
by *Customer*, *Revenue*, *Customer ID*", before glossary terms can carry policies, link to data
products, or give a Copilot/search experience business-context answers instead of raw column
names. Microsoft's own Cloud Adoption Framework guidance for Purview names "populate the glossary"
as the second step of the data-visibility baseline, right after standing up governance domains
. Doing this by hand in the portal, one term at a time, does not
scale past a handful of terms and leaves no reviewable, re-runnable record of who defined what, 
exactly the kind of artifact this repo's buyers expect to manage as code, in a pull request, not
as tribal portal-click knowledge.

## 2. Design goals

1. Author a governance domain and its glossary terms, including a parent/child hierarchy,
 acronyms, resources, owners, and a term-to-term relationship, from a single declarative JSON
 file checked into source control, not from portal clicks.
2. Make re-running the deploy script safe: a second run with the same input file must **update**
 terms that already exist (definition changed, owner added) rather than creating duplicates or
 erroring. See §4 for why this is harder than it sounds for this specific API.
3. Resolve human-readable owner/expert identities (UPN/email, the form a business glossary curator
 naturally writes) to the Microsoft Entra object IDs the Unified Catalog API actually requires
 for contacts, without asking the operator to look up GUIDs by hand.
4. Ship "draft" by default. Terms and the domain are created in `DRAFT` status; publishing
 (making them visible outside Data Stewards/Governance Domain Owners) is a separate, explicit
 `-Publish` flag, mirroring this library's "off by default" code standard (`AGENTS.md` §4) and
 the portal's own two-step create-then-publish flow.
5. Everything idempotent and re-runnable per `AGENTS.md` §4, with a `-WhatIf` dry-run path.

## 3. Why the REST API, not the portal's CSV bulk-import (preview)

Unified Catalog already ships a portal-native bulk-import path: download a sample CSV, fill in
name/description/owners/acronyms/resources/custom-attributes, upload it, and up to 1,000 terms are
created in one pass. That path is real and useful for a **one-time**
seed of a large glossary. It is the wrong tool for the ongoing, git-reviewed curation this scenario
targets, for one documented reason that matters more than any convenience difference:

> "The bulk import process **can't be used to edit or update** glossary terms." 

A CSV re-upload with an existing term's name in it creates a **second, duplicate-named term**
rather than updating the first, the portal explicitly warns duplicate names are allowed, not
blocked. That makes CSV import a one-shot import tool, not a
glossary-as-code mechanism: there is no safe way to express "the *Customer* term's definition
changed, reconcile it" as a re-run of the same CSV. The REST API's `Update` operation (`PUT
/datagovernance/catalog/terms/{termId}`) has no such limitation, it is a true upsert against a
known term ID, which is why this scenario's deploy script uses the REST API's `Create`/`Update`/
`Query` operations directly instead of wrapping the CSV import flow.

## 4. Idempotency design, the identity problem

The Unified Catalog Terms API does not enforce unique names: the portal itself only warns on a
duplicate name, it doesn't block it, and the `Create` operation
requires the caller to supply a client-generated `id` (a GUID), there is no server-assigned,
name-derived identity to key off of. A naive idempotent-upsert
script therefore cannot just "create if the name doesn't exist" using a fresh random GUID each
run, because a second run would never find its own prior term by name and would create a
duplicate every time.

This scenario resolves that by using the **Query Terms** operation
(`POST /datagovernance/catalog/terms/query`) scoped to the target domain (`domainIds`) with a
`nameKeyword` filter, before every create, then filtering the results **client-side for an exact
(case-insensitive) name match** within that domain. If an exact
match exists, the script reuses its `id` and calls `Update`; if not, it generates a new GUID and
calls `Create`. This mirrors the intent signaled by the API's own **Count** operation, whose stated
purpose is "retrieves the count of duplicate Term by passing namekeyword" 
, Microsoft's own surface treats name-based lookup within a domain as the expected way to reason
about duplicates, which is exactly the check this script performs before deciding create vs.
update.

**VERIFY** before relying on this at scale: Microsoft's reference does not document whether
`nameKeyword` performs a substring, prefix, or tokenized match server-side. This script treats it
as a pre-filter only and always re-checks for an **exact** name match in the returned page before
treating a term as "found", so a broad or narrow server-side match behavior cannot cause a false
duplicate-vs-create decision, but a tenant with more matching terms than one page (`top`, default
unconfirmed) could in principle miss an existing term on the far side of pagination. This
scenario's term set is small enough that pagination doesn't bite; a larger rollout should confirm
`nameKeyword` semantics and page fully before trusting the exact-match check unconditionally.

## 5. Owner/expert identity resolution

The `contacts.owner[].id` / `contacts.expert[].id` fields are documented as "AAD oid for the
person or group", a raw Microsoft Entra object ID, not an email
address. A human-authored glossary definition file naturally lists owners by UPN/email (as the
portal's own CSV import does), so this script resolves each
`owners`/`experts` entry that isn't already a GUID to its Entra object ID via a single Microsoft
Graph `GET /v1.0/users/{upn}?$select=id` call per identity, using
the same app registration with the least-privileged `User.Read.All` **application** permission
. This is the one place this scenario's automation spans two
surfaces (`automation-surface.md` surface 3 for identity resolution, surface 4 for the Unified
Catalog write) in a single script, documented explicitly here rather than left implicit, per
`automation-surface.md` §7.

## 6. Governance domain scope

This scenario's deploy script resolves-or-creates **one** governance domain (`-DomainName`) before
authoring terms into it, a full domain-portfolio design (parent/child domain hierarchies, data
estate mappings, custom attributes) is out of scope; see §7. The example input file
(`deploy/glossary/customer-experience-glossary.json`) models a single `FunctionalUnit`-type
domain, "Customer Experience," matching the pattern in Microsoft's own sample data-governance
setup walkthrough.

## 7. Non-goals

- **Linking terms to data products, data assets, or columns.** That requires the target assets to
 already exist in a data product (this repo's Data Map scenarios cover asset scanning) and the
 service principal to hold Data Reader on the assets' Data Map collection in addition to Data
 Steward on the domain, a natural follow-up scenario once a Data
 Products scenario exists in this library (see `PROGRESS.md`).
- **Term policies** (access/data-handling policies attached to a term), a distinct Unified
 Catalog capability (`Policies` operation group) with its own review surface; out of scope here.
- **The portal-only "Term publish" approval workflow** (Catalog curation → Term publish, a
 maker-checker gate before a term becomes visible org-wide), configured entirely in the
 Workflows canvas in the portal; Microsoft does not publish a REST/PowerShell surface for
 authoring workflow definitions themselves as of this build. This script's `-Publish` flag
 performs the same status transition (`DRAFT` → `PUBLISHED`) a workflow would eventually approve;
 see `README.md` §11 for the operational implication of bypassing that gate via direct API calls.
- **Multi-domain governance hierarchies and custom attributes**, this scenario models one
 standalone domain; domain parent/child nesting and org-defined custom attribute groups are a
 natural larger-scale follow-up once more domains exist in a buyer's catalog.
