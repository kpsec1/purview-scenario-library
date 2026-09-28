---
part: "runbook"
parent: "unified-catalog/curate-business-glossary"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Governance domains** → **New Governance domain**.
2. Name: `Customer Experience`. Type: **Functional unit**. Leave parent blank. **Create**.
3. On the new domain's **Roles** tab, confirm you (and any Data Stewards) are assigned; add the
   automation service principal as **Data Steward** here for the script path below.
4. On the domain's **Details** tab, **Glossary terms** card → **View all** → **New term**.
5. Create `Customer` with its definition, an owner, and a resource link; **Create**, then
   **Publish** once reviewed. Repeat for `Customer ID` and `Customer Lifetime Value`, selecting
   `Customer` as **Parent term** for both; repeat for `Net Promoter Score` with no parent.
6. On `Customer Lifetime Value`'s **Related** tab, **Add term** → select `Net Promoter Score` as a
   **Related term**.
7. **Publish** the governance domain itself (required before its terms are visible tenant-wide).

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

The deploy script uses the Purview Unified Catalog REST API directly (`Invoke-RestMethod`) -
automation surface 4 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first); there is no PowerShell cmdlet module for
Unified Catalog term authoring today. It also calls Microsoft Graph (surface 3) once per
not-already-a-GUID owner/expert identity, cached per run so the same person is resolved only once.

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Governance domain | `type` | `FunctionalUnit` \| `LineOfBusiness` \| `DataDomain` \| `Regulatory` \| `Project` | Descriptive only - Microsoft documents no behavioral difference between types |
| Governance domain | `status` | `DRAFT` → `PUBLISHED` | Must be `PUBLISHED` before any of its terms can be published |
| Term | `id` | Client-generated GUID | The API has no server-assigned, name-derived identity - see the design notes for why this matters for idempotency |
| Term | `contacts.owner[].id` / `.expert[].id` | Entra object ID (AAD oid) | **Not** an email address - resolved from the definition file's UPN by this script |
| Term | `parentId` | Another term's `id`, same domain | Portal calls this "Parent term"; up to five levels of domain nesting are supported tenant-wide, but term hierarchy depth itself isn't separately documented as limited |
| Term relationship | `relationshipType` | `Related` \| `Synonym` \| `Parent` | This scenario's script only wires `Related`; `Synonym` and portal-driven `Parent` (set via `parentId` instead) are the other two |
| Term / domain | `status` lifecycle | `DRAFT` → `PUBLISHED` → `EXPIRED` | `EXPIRED` ("Set to Expired") is a soft-retire step this scenario doesn't script - see the rollback plan |

Full request/response shapes: `deploy/New-BusinessGlossary.ps1`'s inline comments and `.NOTES`
block cite the exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Review-before-publish workflow:** this script's default (`DRAFT`, no `-Publish`) intentionally
mirrors Unified Catalog's own two-step create-then-publish model - a term in `DRAFT` is visible
only to Data Stewards and Governance Domain Owners, giving a human review
point (a PR review of the JSON diff, then a deliberate `-Publish` run) before a term becomes
visible catalog-wide. An organization with a mature governance practice can additionally configure
Unified Catalog's native **Term publish workflow** (Process automation → Workflows → Catalog
curation → Term publish), which adds an in-portal maker-checker approval gate on top of the
`DRAFT`→`PUBLISHED` transition - this is portal-only and complements,
rather than replaces, this script's own review-before-`-Publish` discipline.

**Re-running after an edit:** change the definition file (add a term, edit a description, add an
owner) and re-run `New-BusinessGlossary.ps1` without `-Publish` first - review the change, then
re-run with `-Publish`. Never edit a published term directly in the portal and expect this
script's next run to "know" about it: the script's create/update path always reconciles the term
**to the definition file's current content** (not a merge), so a portal-made edit not reflected in
the file will be overwritten on the next deploy run. (The narrower `-Publish`-only status
transition does **not** have this problem - see the design notes's `ConvertTo-TermUpdateBody`
design note.)

**Governance domain sprawl:** Unified Catalog supports up to 200 domains and five levels of
hierarchy depth tenant-wide. Track domain count as an operational metric
once multiple teams start self-service authoring - a domain-per-small-team pattern can approach
that ceiling faster than expected in a large enterprise; consider domain hierarchies (parent/child)
before the ceiling is hit, not after.

**Ownership hygiene:** every term should have at least one owner (this script warns, but does not
hard-fail, if `owners` is empty in the definition file - an ownerless term is valid at the API
level but defeats the accountability purpose of the glossary). Review the `contacts.owner` field
via `validate/Test-BusinessGlossary.ps1` as part of any periodic glossary health review. Note that
owner resolution only confirms the UPN resolves to **an** Entra account - it
does not confirm that account is still active or still the right owner. A departed employee whose
account is disabled but not yet deleted resolves successfully and is silently assigned as owner
indefinitely; fold a glossary-owner review into the same offboarding/access-review process that
already re-points other Purview role assignments ([RBAC model, section 9](/docs/rbac-model/#9-microsoft-intune-rbac---a-fifth-system-for-intune-deployed-scenarios)), rather than treating
glossary ownership as self-maintaining.

**Change attribution and drift detection:** every term and domain object returned by the API
carries `systemData.createdBy`/`createdAt`/`lastModifiedBy`/`lastModifiedAt` (Entra object IDs and
timestamps) - this is the built-in point-in-time attribution for "who last touched this," queryable
via a plain `GET`, though Microsoft documents no full change-history/diff API beyond that single
last-modified snapshot. Because this script's create/update path always reconciles a term to
exactly the definition file's content (operations and tuning, "Re-running after an edit"), running
`validate/Test-BusinessGlossary.ps1` on a schedule (a CI cron job, not just after a deploy) doubles
as drift detection: a portal-made edit that hasn't been reflected back into the definition file
will show up as a content-mismatch `[FAIL]` before the next scripted deploy silently overwrites it.

## Rollback and decommission

See the rollback runbook for the full staged procedure (unpublish → purge). Quick reference:
`./deploy/Remove-BusinessGlossary.ps1` unpublishes the domain and its terms (reversible); add
`-Purge` to permanently delete them.

## References

1. Glossary terms in Unified Catalog (active terms, policies, scaling data governance) - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms>
2. Data governance and security baselines with Microsoft Purview - data visibility baseline, "populate the glossary" step - <https://learn.microsoft.com/azure/cloud-adoption-framework/data/governance-security-baselines-purview-data-estate-unify-data-platform>
3. Disaster recovery for Unified Catalog (manual) - data estate health, CDMC control templates - <https://learn.microsoft.com/purview/unified-catalog-disaster-recovery>
4. Learn about data governance billing (governed assets, what counts, what doesn't) - <https://learn.microsoft.com/purview/data-governance-billing>
5. Learn about Microsoft Purview billing models (PAYG, Azure subscription prerequisite) - <https://learn.microsoft.com/purview/purview-billing-models>
6. Get a user (Microsoft Graph) - `User.Read.All` application permission - <https://learn.microsoft.com/graph/api/user-get>
7. Create and manage glossary terms - create, publish, related terms, DRAFT visibility - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage>
8. Create and manage governance domains - publish domain before publishing its terms - <https://learn.microsoft.com/purview/unified-catalog-governance-domains-create-manage>
9. Governance domains in Unified Catalog - domain types, 200-domain / 5-level hierarchy limit - <https://learn.microsoft.com/purview/unified-catalog-governance-domains>
10. Create and manage glossary terms - Tree view for parent/child hierarchy - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage#access-glossary-terms>
11. Enterprise glossary (preview) - Catalog Reader role, published-concept discovery - <https://learn.microsoft.com/purview/unified-catalog-enterprise-glossary>
12. Create workflows to automate processes in Unified Catalog - Term publish workflow, Governance Domain Creator prerequisite - <https://learn.microsoft.com/purview/unified-catalog-workflows>
13. Data governance billing frequently asked questions - unattached domains/data products aren't charged - <https://learn.microsoft.com/purview/data-governance-billing-faq>
14. Migrate governance private endpoints from classic portal to Microsoft Purview portal - the two API endpoint hosts - <https://learn.microsoft.com/purview/data-governance-private-endpoints-migrate>
15. Purview Unified Catalog REST API - Terms operation group (Create/Update/Delete/Get/List/Query/AddRelatedEntity/ListRelatedEntities/Count) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
16. Purview Unified Catalog REST API - Business Domain - Create (Request Body table, auto-generated schema shared with the response `Domain` type) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain/create?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
16. Purview Unified Catalog REST API - Business Domain operation group (Create/Update/Delete/Get/Enumerate) - <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
17. Unified Catalog API (Public Preview) overview - scope, GA-only coverage, preview API versions - <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
18. Tutorial: Authenticate for APIs - service principal setup, Unified Catalog role assignment, client-credentials token flow - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
19. Data governance roles and permissions in Microsoft Purview - Data Steward, Governance Domain Creator/Owner, Catalog Reader - <https://learn.microsoft.com/purview/data-governance-roles-permissions>
20. Microsoft identity platform and the OAuth 2.0 client credentials flow - v2.0 token endpoint, `scope=.default` - <https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), which
> Microsoft explicitly documents as covering only GA Unified Catalog features and subject to
> change before general availability.