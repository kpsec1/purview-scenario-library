---
part: "runbook"
parent: "unified-catalog/manage-critical-data-elements-related-terms"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Unified Catalog**
   → **Catalog management** → **Governance domains** → select `Customer Experience` → **Critical
   data elements** → select `Customer ID`.
2. On the critical data element's details page, select **+ Add term**.
3. Search for the term(s) you want to link (e.g. `Customer ID`, `Customer`) and select them, then
   select **Add**.
4. To remove a related term later, select the term, then the **...** ellipsis button, then
   **Remove**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Dry run - reports every change, makes none (still performs read-only lookups against the
# live tenant, including the term/CDE existence checks, to accurately report the plan)
./deploy/Add-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json' -WhatIf

# 2. Deploy
./deploy/Add-CdeRelatedTerm.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json'

# 3. Validate
./validate/Test-CdeRelatedTerms.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DefinitionPath './deploy/config/customer-id-related-terms.sample.json'
```

No placeholder GUID to replace before running - unlike its column-mapping sibling, every object
this scenario touches is resolved by **name** (domain name, CDE name, term names), not by a
copied-from-the-portal GUID.

## Configuration reference

| Object | Field | Source | Notes |
|---|---|---|---|
| Relationship | `entityType` | `TERM` | The value this scenario sends - confirmed present in the `EntityCategory` enum on the Create/List/Delete Relationship reference pages, fetched directly this build - there is no enum-vs-example ambiguity for `TERM` (the sibling scenario's own `CRITICALDATACOLUMN`-vs-`DATACOLUMN` question never applied to `TERM`, and is itself now resolved - see its the known limitations) |
| Relationship | `entityId` | The glossary term's own `id` (GUID), resolved by name via **Terms - Query** | Same `nameKeyword` client-side-exact-match pattern every sibling Unified Catalog scenario in this library already uses |
| Relationship | `relationshipType` | `Related` | The only value this scenario's script sends, matching every other relationship this library creates across Unified Catalog object types |

Full request/response shapes: `deploy/Add-CdeRelatedTerm.ps1`'s inline comments and `.NOTES` block
cite the exact Microsoft Learn REST reference pages for every operation used.

## Operations and tuning

**Re-running after an edit:** add another term name to `relatedTerms`, or add a brand-new term via
*Curate a Business Glossary*, then re-run `Add-CdeRelatedTerm.ps1`. Existing links are untouched
(idempotent - the script only adds what's missing); removing a name from the file does **not**
unlink it - see the rollback runbook for the explicit unlinking path, the same additive-only discipline
*Manage a Critical Data Element* (operations and tuning) documents for its own column mappings.

**Run validate after every deploy, not just on demand:** `Add-CdeRelatedTerm.ps1` treats an
unresolvable term name as a non-fatal `Write-Warning`-and-skip, by design - one bad name in a
multi-term `relatedTerms` array shouldn't abort linking the rest. That means the deploy script's
own console output is not a reliable signal that every configured term actually got linked; treat
a deploy run as incomplete until `validate/Test-CdeRelatedTerms.ps1` has confirmed it - the same
named operational discipline *Manage a Critical Data Element* (operations and tuning) and
*Manage a Critical Data Element*'s Red Team finding 1 established for its own
silently-skipped-column risk, which applies identically here.

**Access-policy inheritance is not something this scenario configures or can verify by itself.**
why this matters above documents that a policy set on a linked term aggregates onto the CDE's associated data
products - but that aggregation is entirely computed by Microsoft's platform once the link exists;
this scenario's validate script confirms the *link*, not the resulting policy aggregation (which
would require calling into the separate access-policy configuration surface
*Manage a Data Product* (the implementation steps) already flags as having no discovered REST operation of its
own). Confirm the aggregated policy view in the portal's **Manage policies** → **Preview** flow
 if this link is being made specifically to extend a term's access policy.

**Preview-status caution:** both underlying features (critical data elements, glossary terms) are
Microsoft-labeled preview - re-check GA status before citing a term-CDE link as durable evidence in
a formal compliance narrative, the same caution *Manage a Critical Data Element* (operations and tuning)
already states for the CDE side alone.

## Rollback and decommission

See the rollback runbook for the full procedure. Quick reference: `./deploy/Remove-CdeRelatedTerm.ps1`
unlinks the terms named in the definition file by default; add `-TermNames <name[]>` to target
specific terms instead, or `-RemoveAll` to unlink every term the critical data element currently
has, regardless of source. Nothing this scenario does ever deletes the term, the critical data
element, or the governance domain - those lifecycles belong to their own owning scenarios.

## References

1. Critical data elements (preview) - "Manage related terms," "Delete critical data" prerequisite,
   role prerequisites - <https://learn.microsoft.com/purview/unified-catalog-critical-data-elements>
2. Manage data product access policies - inherited/aggregated policies from governance domains,
   glossary terms, and critical data elements onto data products - <https://learn.microsoft.com/purview/unified-catalog-data-product-access-policies>
3. Learn about Microsoft Purview Unified Catalog - critical data elements and glossary terms
   feature overview - <https://learn.microsoft.com/purview/unified-catalog>
4. Create and manage glossary terms - "Link terms to data products, assets, and critical data
   elements (preview)," including the Draft-state requirement for that reciprocal flow - <https://learn.microsoft.com/purview/unified-catalog-glossary-terms-create-manage>
5. Learn about data governance billing - Unified Catalog billing, governed assets defined via data
   products or critical data elements - <https://learn.microsoft.com/purview/data-governance-billing>
6. Data governance billing frequently asked questions - <https://learn.microsoft.com/purview/data-governance-billing-faq>
7. Data governance roles and permissions in Microsoft Purview - Data Steward role -
   <https://learn.microsoft.com/purview/data-governance-roles-permissions>
8. Purview Unified Catalog REST API - Critical Data Elements operation group (Create
   Relationship/List Relationships/Delete Relationship, and the shared `EntityCategory` enum
   confirming `TERM` as a valid value - fetched directly this build) -
   <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/critical-data-elements?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
9. Purview Unified Catalog REST API - Terms operation group (Query) -
   <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
10. Tutorial: Authenticate for APIs - service principal setup, Unified Catalog role assignment,
    client-credentials token flow - <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>

> Re-verify all links against current Microsoft Learn before a customer-facing engagement - this
> scenario targets Unified Catalog's **preview** REST API surface (`2026-03-20-preview`), and both
> underlying features (critical data elements, glossary terms) are separately Microsoft-labeled
> preview.