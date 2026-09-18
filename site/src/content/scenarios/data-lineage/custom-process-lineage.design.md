---
part: "design"
parent: "data-lineage/custom-process-lineage"
---
## 1. Problem statement

[`data-lineage/end-to-end-lineage-validation`](/scenarios/data-lineage/end-to-end-lineage-validation/) closes a lineage gap for a custom nightly
job by asserting a single `direct_lineage_dataset_dataset` edge - "table A feeds table B, although
we wouldn't know exactly which Process is between them" (that scenario's own README.md reference
5). That was a deliberate scope decision, not an oversight: its own grounding pass confirmed the
direct-edge shape from a worked REST example but did not find a REST-documented body for creating
a *custom* Process-typed entity - so it declined to model the transform itself, and left a tracked
follow-up in `PROGRESS.md` instead of guessing.

This scenario is that follow-up, closed. A fresh grounding pass against Microsoft's own "Create and
get lineage relationships using the REST API" tutorial found the exact body the earlier build was
missing: Example 1 in that tutorial creates a Process-typed entity (`hive_view_query`) via Entity -
Bulk Create Or Update, then links it to two DataSet entities with `dataset_process_inputs` and
`process_dataset_outputs` relationships - and the same tutorial's "Create New Custom Types" section
separately confirms the request body for a *custom* Process type (`superTypes: ["Process"]`) via
Type - Bulk Create. Both are directly, literally confirmed - not inferred by analogy - which is
what makes this a buildable fragment now rather than another deferred item.

Modeling the transform explicitly matters for exactly the reason `end-to-end-lineage-validation/
README.md` Section 11 names as a limitation: a direct edge tells a reviewer *that* data flows from
`customerdb.dbo.Customers` to `analyticsdb.dbo.CustomerRiskSummary`, but not *how* - which job,
whose runbook, on what schedule. A Process node carries that context in the graph itself, visible
to anyone browsing lineage in the portal, not buried in a separate wiki page a reviewer has to know
to go looking for.

## 2. Design goals

1. **Use only directly-confirmed request bodies - no analogy-based guessing.** Every REST call this
   scenario makes (Type - Bulk Create, Type - Get Entity Def By Name, Entity - Bulk Create Or
   Update, Relationship - Create x2, Lineage - Get By Unique Attribute) is grounded against its own
   canonical Microsoft Learn reference page or a literal worked example - see `README.md` Section
   12. Where this scenario's grounding pass could not independently confirm a detail (the relation-
   end typeName question, the not-found status code for Type - Get Entity Def By Name), it is
   flagged as a VERIFY rather than asserted - `README.md` Section 11.
2. **Prefer a confirmed upsert over a hand-rolled existence check, where one is documented.**
   Entity - Bulk Create Or Update's own reference page states plainly that it matches an existing
   entity by qualifiedName. This scenario relies on that directly for the Process entity - a
   stronger, simpler, better-grounded pattern than `end-to-end-lineage-validation`'s own approach
   (a separate existence-check GET before every mutating call), which that scenario used only
   because *its* mutating call's idempotency was unconfirmed. Where this scenario's own mutating
   calls carry the same unconfirmed-duplicate-POST risk (Relationship - Create, Type - Bulk
   Create - whose reference page explicitly warns "avoid recreating existing types"), it uses the
   same existence-check idiom the sibling scenario established, for the same reason.
3. **One Process entity, not the bare built-in `Process` type.** A custom subtype
   (`PurviewScenarioLibraryEtlProcess`) lets this scenario carry two scenario-specific attributes
   (`runbookUrl`, `scheduleExpression`) using the confirmed `AtlasAttributeDef` shape from
   Microsoft's own `Type - Bulk Create` worked example (`azure_sql_server_example`) - context a bare
   `Process` entity instance couldn't hold without those attributes being defined somewhere first.
4. **Compose with, don't duplicate, `end-to-end-lineage-validation`.** Same upstream/downstream
   assets, same underlying narrative (the nightly Python job) - this scenario adds the Process node
   *in addition to* whatever edge already exists, it doesn't remove or require removing the
   sibling scenario's direct edge first (see Section 6 for what that means for the graph).
5. **Least-privilege validate.** `validate/Test-ProcessLineage.ps1` never mutates anything and
   needs only the Data Reader role, matching this repo's established convention.

## 3. Why a custom Process type (not the bare built-in `Process` type, not a different built-in
   subtype like `hive_view_query`)

- **The bare built-in `Process` type is the abstract base every Process subtype inherits from.**
  Microsoft's own worked examples never create an entity with the literal typeName `Process` -
  every example (`hive_view_query`, `Oracle_function`, etc.) uses a concrete subtype. This
  scenario follows that same pattern rather than being the first to instantiate the abstract base
  type directly, which this build's grounding pass found no confirmed example of.
- **A different built-in subtype (e.g. `hive_view_query`) would misdescribe the asset.** The
  nightly job this scenario models is an Azure Functions Python job, not a Hive query - reusing a
  Hive-specific built-in type would be technically functional (Atlas doesn't enforce semantic
  fitness) but misleading to anyone browsing the portal's **Browse by source type** view, which
  groups assets by their type's `serviceType`/name.
- **A custom type is the only option that lets this scenario attach scenario-specific attributes**
  (`runbookUrl`, `scheduleExpression`) without guessing at an undocumented attribute name on some
  other built-in type that happens to have a similarly-named field.

## 4. Object model and REST call sequence

```mermaid
sequenceDiagram
    participant Deploy as New-CustomProcessLineage.ps1
    participant AAD as Microsoft Entra ID
    participant API as Purview Data Map / Atlas v2 REST API
    participant Validate as Test-ProcessLineage.ps1

    Deploy->>AAD: OAuth2 client_credentials (resource=https://purview.azure.net)
    AAD-->>Deploy: Bearer token
    Deploy->>API: GET types/entitydef/name/PurviewScenarioLibraryEtlProcess
    alt type already exists
        API-->>Deploy: 200 OK
        Deploy->>Deploy: skip (idempotent no-op)
    else type missing
        API-->>Deploy: non-success response
        Deploy->>API: POST types/typedefs (entityDefs: [{name, superTypes:[Process], attributeDefs}])
        API-->>Deploy: 200 OK
    end
    Deploy->>API: POST entity/bulk (Process entity; upsert-by-qualifiedName, confirmed)
    API-->>Deploy: 200 OK (guidAssignments / mutatedEntities)
    Deploy->>API: GET lineage/uniqueAttribute/type/azure_sql_table (upstream, direction=OUTPUT, depth=2)
    API-->>Deploy: two-hop graph (guidEntityMap + relations)
    Deploy->>Deploy: resolve Process/downstream GUIDs by qualifiedName; check both relations
    opt dataset_process_inputs missing
        Deploy->>API: POST relationship (dataset_process_inputs; end1=upstream DataSet, end2=Process)
    end
    opt process_dataset_outputs missing
        Deploy->>API: POST relationship (process_dataset_outputs; end1=Process, end2=downstream DataSet)
    end
    Validate->>AAD: OAuth2 client_credentials
    AAD-->>Validate: Bearer token
    Validate->>API: GET types/entitydef/name/PurviewScenarioLibraryEtlProcess
    Validate->>API: GET lineage/uniqueAttribute/type/azure_sql_table (upstream, direction=OUTPUT, depth=2)
    API-->>Validate: two-hop graph
    Validate->>Validate: confirm type exists; confirm both hops walkable in order; confirm columnMapping survived
```

The deploy script's Step 3 deliberately fetches the whole two-hop graph in **one** call (depth 2
from the upstream asset) rather than one existence check per relationship - it needs both the
Process entity's GUID and the downstream asset's GUID to evaluate both relations, and both are
already present in a single depth-2 response. This also sidesteps a genuinely open question this
scenario's grounding pass could not resolve: whether Lineage - Get By Unique Attribute, called
*on the Process entity itself*, would need the entity's concrete custom typeName or would accept
the literal `Process` ancestor type in its path parameter the way Relationship - Create's `end`
objects are directly confirmed to (Section 5, and `README.md` Section 11) - this design avoids
needing to answer that question at all, by only ever calling Lineage - Get By Unique Attribute on
the upstream `azure_sql_table` asset, whose typeName usage is unambiguous and matches
`end-to-end-lineage-validation`'s own already-proven call shape exactly.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Process entity type | Custom subtype `PurviewScenarioLibraryEtlProcess` (`superTypes: ["Process"]`) | Directly confirmed body from Microsoft's own "Create New Custom Types" section; carries scenario-specific attributes a bare `Process`/reused built-in subtype couldn't - Design goals 1, 3 |
| Process entity idempotency | Rely on Entity - Bulk Create Or Update's documented upsert-by-qualifiedName - no separate existence check | Directly stated in that operation's own reference page - Design goal 2 |
| Type definition idempotency | Explicit `Type - Get Entity Def By Name` check before `Type - Bulk Create` | That operation's reference page warns "avoid recreating existing types" and is not documented as an upsert - Design goal 2 |
| Relationship idempotency | Single depth-2 `Lineage - Get By Unique Attribute` call from the upstream asset before either relationship POST | `Relationship - Create`'s duplicate-POST behavior is unconfirmed - same idiom as `end-to-end-lineage-validation` (Design goal 2), and sidesteps the open Process-entity-lineage-lookup-typeName question (Section 4) |
| Relationship end typeName for the Process node | Literal `Process` (not the custom subtype name) | Matches Microsoft's own worked example exactly: the created entity's concrete type was `hive_view_query`, but the relationship JSON referenced it as `Process` - `README.md` reference 5. Flagged as not independently re-confirmed for a *custom* subtype specifically - `README.md` Section 11 |
| columnMapping placement | On the **Process entity's own attributes**, not on either relationship | Matches Microsoft's own worked DataSet -> Process -> DataSet example exactly (as opposed to the sibling scenario's direct-edge case, where Microsoft's example places it on the relationship instead) - the two shapes are genuinely different in the source material, not an inconsistency in this scenario |
| Deploy/validate role split | Data Curator (deploy) vs. Data Reader (validate) | Matches this repo's least-privilege convention (`docs/rbac-model.md` Section 5) |
| Relationship to `end-to-end-lineage-validation` | Independent, composable companion - not a replacement | Section 6 |

## 6. Relationship to `end-to-end-lineage-validation`

This scenario does not require, assume, or remove `end-to-end-lineage-validation`'s
`direct_lineage_dataset_dataset` edge between the same two tables. If both scenarios are deployed
against the same tenant, the lineage graph shows **both** a direct edge and a Process-mediated path
between `customerdb.dbo.Customers` and `analyticsdb.dbo.CustomerRiskSummary` simultaneously -
Atlas's lineage model has no exclusivity constraint preventing two different relationship paths
between the same two DataSets (Microsoft's own tutorial demonstrates exactly this coexistence in
its "Example 2," where a `direct_lineage_dataset_dataset` edge is added between `table2` and
`table3` *alongside* the pre-existing `table1 -> HiveQuery1 -> table2` Process-mediated path,
without removing anything - `README.md` reference 5). This is a genuinely useful pattern for a
buyer who deployed the sibling scenario first and later wants to enrich the graph with the process
node, without a migration step - see `README.md` Section 1 and Section 11 for how a reader should
interpret seeing both edges in the portal.

## 7. What this scenario assumes already exists

- A Microsoft Purview account with Data Map enabled.
- The upstream asset, `customerdb.dbo.Customers`, and the downstream asset,
  `analyticsdb.dbo.CustomerRiskSummary`, both already registered and scanned - same assumption as
  `end-to-end-lineage-validation/design.md` Section 6, and this scenario does not create, register,
  or scan either one.
- The nightly transform job itself already exists and runs on its own schedule - this scenario only
  models it as a metadata entity in the lineage graph; it does not create, deploy, or orchestrate
  the job.
- An app registration with the Data Curator role (deploy) or Data Reader role (validate) on the
  collection containing both DataSet assets, and (for the custom type creation step specifically)
  sufficient rights to create type definitions at the account level - see `README.md` Section 3 for
  the open question this raises about whether type creation is itself collection-scoped or
  account-wide.

## 8. Non-goals

- This scenario does not create, register, or scan either the upstream or downstream data source -
  Section 7.
- This scenario does not build, deploy, or orchestrate the nightly transform job itself - Section 7.
- This scenario does not remove or modify `end-to-end-lineage-validation`'s own direct edge -
  Section 6.
- This scenario does not attempt `vendorId`/`productId`-style richer typing for the Process entity
  beyond the two attributes shipped (`runbookUrl`, `scheduleExpression`) - a buyer with a larger
  catalog of custom jobs may want a richer attribute set (owning team, source-code repository URL,
  last-run status), all straightforward extensions of the same confirmed `AtlasAttributeDef` shape,
  deferred to keep this fragment scoped.
- This scenario does not script deletion of the custom Process type definition itself as part of
  rollback - see `rollback.md` "What rollback does not undo."
