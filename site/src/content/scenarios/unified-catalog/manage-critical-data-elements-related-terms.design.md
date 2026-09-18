---
part: "design"
parent: "unified-catalog/manage-critical-data-elements-related-terms"
---
## 1. Problem statement

`scenarios/unified-catalog/manage-critical-data-elements/` maps physical columns into a named,
governance-domain-scoped concept (a CDE) but explicitly deferred one capability as a non-goal:
"Linking the CDE to glossary terms. Microsoft's portal exposes a 'Manage related terms' action on
a CDE's details page; this scenario's definition file and scripts don't script it... would extend
to a CDE with no new grounding required, a natural, small follow-up"
(`manage-critical-data-elements/design.md` §7). `PROGRESS.md` recorded this exact deferred item as
a follow-up fragment. This scenario is that follow-up: it links an existing CDE to one or more
existing glossary terms via the same `criticalDataElements/{id}/relationships` operation the
sibling scenario already uses for its own `DATACOLUMN` relationships, this time with
`entityType=TERM`.

## 2. Design goals

1. Link, not create. This scenario never creates a governance domain, a critical data element, or
 a glossary term, all three are resolved strictly by name and must already exist, created by
 `curate-business-glossary` and `manage-critical-data-elements` respectively. If either the CDE
 or a named term doesn't resolve, that is a hard failure (CDE) or a skipped, warned entry (term)
, never a silent creation of a placeholder object.
2. Reuse the exact idempotency pattern (list relationships, skip if already present, otherwise
 create) every other relationship-creating scenario in this repo's Unified Catalog family
 already establishes, `manage-critical-data-elements`'s `Test-CdeRelationshipExists`/
 `Add-CdeColumnRelationship` and `manage-data-products`'s `Test-RelationshipExists`/
 `Add-DataProductRelationship`, parameterized only by `entityType=TERM` instead of
 `DATACOLUMN`/`DATAASSET`.
3. Reuse the exact term-resolution code `manage-data-products/deploy/New-DataProduct.ps1`'s own
 `Find-TermByName` already implements verbatim (design goal explicitly named in the
 `PROGRESS.md` follow-up this fragment closes: "the code pattern already exists... and would
 need no new grounding to port").
4. No new REST surface, no new API version, no new authentication flow. This is the smallest
 possible new fragment that still meets `AGENTS.md`'s full per-scenario deliverable bar, a
 companion scenario, not a sibling scenario's rewrite.
5. Everything idempotent and re-runnable per `AGENTS.md` §4, with a `-WhatIf` dry-run path.

## 3. Why `entityType=TERM` needed no new grounding

`manage-critical-data-elements/design.md` §6 already documents, from three independently-fetched
Microsoft Learn REST reference pages, the full `EntityCategory` enum the Critical Data Elements
Create/List/Delete Relationship operations share: `DOMAIN`, `DATAPRODUCT`, `TERM`, `DATAASSET`,
`OBJECTIVE`, `KEYRESULT`, `CRITICALDATAELEMENT`, `DATACOLUMN`, `CUSTOMMETADATA`, `ATTRIBUTE`,
`ATTRIBUTEINSTANCE`, `WORKFLOW`, `CATALOGSNAPSHOT`, `WORKFLOWRUN`. `TERM` was already a confirmed,
formally-documented value in that enum before this fragment started, this build's own fresh
direct fetch of the Create Relationship, List Relationships, and Delete Relationship reference
pages (README.md §12, refs 8) re-confirms it, and, unlike the sibling scenario's own
`DATACOLUMN`-vs-`CRITICALDATACOLUMN` finding, every one of those three pages' formal enum table
lists `TERM` with **no** competing example-only value in tension with it. There is no analogous
discrepancy to disclose for this entity type.

The relationship-creation request/response shape is also unchanged from the sibling's own
`DATACOLUMN` call: `{ entityId, relationshipType }` in, `CdeRelationshipWithSystemData` out, the
sibling's own `Add-CdeColumnRelationship` function's structure ports directly; this scenario's
`Add-CdeTermRelationship` differs from it only in the `EntityType` literal and the identifier it
resolves (`Find-TermByName` instead of a Data Map column lookup).

## 4. The two-sided linking flow, and why this scenario picks one side

Microsoft documents what is, by every indication, the **same relationship** reachable from two
different portal surfaces:

- **From the CDE's own page**, "Manage related terms," documented on the critical-data-elements
 concept page: select the CDE, select **+ Add term**, search and select term(s), select **Add**
.
- **From the term's own page**, "Link terms to data products, assets, and critical data elements
 (preview)," documented on the glossary-terms concept page: select the term, select **Related**,
 select **Add critical data element**, search and select CDE(s), select **Add**
.

This scenario scripts the **first** flow, matching its own name and the `PROGRESS.md` follow-up's
own framing ("script the 'Manage related terms' action"). Both flows almost certainly write to the
identical underlying relationship object (there is exactly one Create Relationship operation on
the Critical Data Elements operation group, and the term's own "Related" tab is documented as
showing "which data products, data assets, and columns the term is linked to", the reciprocal
view of the same graph edge, per the Enterprise Glossary and Search-for-data-assets pages'
description of bidirectional relationship visibility that this repo's sibling scenarios already
rely on for their own `manage-critical-data-elements`↔`manage-data-products` DATAPRODUCT rollup).
`README.md` §7's "reciprocal check" step asks an operator to confirm this bidirectional visibility
directly against a real tenant rather than asserting it as a certainty this build's own grounding
pass (Microsoft Learn page fetches only, no pilot tenant) can fully confirm.

## 5. The Draft-state discrepancy, a genuine, disclosed open question

Section 4's second flow (from the *term's* page) carries an explicit stated precondition on
Microsoft's own glossary-terms page: "Glossary terms must be in **Draft** state in order to add
links; if the term is published, select **Unpublish** on the term's page to put it in **Draft**
state". The critical-data-elements page's own "Manage related
terms" section, the flow this scenario automates, states no equivalent restriction
.

Two explanations are equally plausible from the documentation alone:
1. The restriction is a genuine asymmetry, the term's own edit surface enforces Draft state for
 any edit made *from that page*, including adding a link, while the CDE's edit surface (which is
 editing the *CDE's* own relationship list, not the term) has no such gate.
2. The restriction applies to the underlying relationship-creation operation regardless of which
 page initiates it, and the critical-data-elements page simply omits repeating it.

This build's grounding pass (Microsoft Learn page fetches only) cannot distinguish these two
explanations, and neither can be resolved without a pilot tenant test against a *published* term
specifically. Per `AGENTS.md` §4's no-guessing standard, `deploy/Add-CdeRelatedTerm.ps1` does
**not** encode either explanation as fact: it does not pre-emptively check or change a term's
publish status, and it does not suppress or reinterpret whatever error the live API returns if
explanation 2 turns out to be correct. `README.md` §11 states the open question plainly, naming
both source pages, rather than picking the more convenient reading.

## 6. Non-goals

- **Creating, editing, or publishing the critical data element itself.** Owned entirely by
 `manage-critical-data-elements`; this scenario only reads it (by name) to get its `id`.
- **Creating, editing, or publishing the glossary term(s) themselves.** Owned entirely by
 `curate-business-glossary`; this scenario only reads them (by name) to get their `id`s.
- **Configuring or verifying the resulting access-policy inheritance** described in `README.md`
 §2/§8. No REST operation for the access-policy *configuration* surface itself was found during
 this build's grounding pass or the sibling `manage-data-products/design.md` §5's own pass before
 it, this remains a portal-only step for the underlying policy object, same as every other
 Unified Catalog access-policy reference in this repo.
- **Scripting the reciprocal "Add critical data element" flow from the term's own page.** Covered
 by §4 above, a natural, near-zero-new-grounding follow-up (swap which object is resolved first
 and which REST path is called, `terms/{id}/relationships` instead of
 `criticalDataElements/{id}/relationships`) not built here to keep this fragment scoped to the
 one flow `PROGRESS.md`'s follow-up item named.
- **Synonym/parent-term relationships (`terms/{id}/relationships`, term-to-term).** Already
 scripted by `curate-business-glossary` for its own `parent`/`relatedTerms` fields, out of scope
 here, which only creates critical-data-element-to-term links.
