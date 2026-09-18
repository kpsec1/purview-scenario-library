---
part: "design"
parent: "data-lineage/end-to-end-lineage-validation"
---
## 1. Problem statement

Microsoft Purview captures lineage automatically for a specific, documented set of processing
systems (Azure Data Factory, Azure Synapse Analytics, Power BI, Azure Databricks, Airflow via
OpenLineage, Azure SQL Database stored-procedure execution [preview], and a handful of others -
`README.md` reference 4). Any transform that runs *outside* that list - a custom script, an
internal scheduler-driven job, a legacy on-prem batch process - produces a **silent gap**: Purview
shows the upstream table and the downstream table as two disconnected assets, with no visual or
programmatic evidence one feeds the other. A data engineer doing root-cause analysis on a bad
downstream number, or a security reviewer doing PII impact analysis before changing an upstream
schema, gets an incomplete picture and doesn't necessarily know it's incomplete - the missing hop
looks the same as "there is no relationship" as it does "the relationship exists but isn't
tracked."

This scenario closes that gap for one such custom hop (a nightly Python job, not ADF or any other
auto-integrated system, that produces `analyticsdb.dbo.CustomerRiskSummary` from
`customerdb.dbo.Customers`), and - the harder, more novel half of the scenario - builds a
repeatable way to **prove** the resulting graph is actually connected end-to-end, rather than
trusting that "we ran the custom-lineage script once" is the same thing as "the chain is intact
today."

## 2. Design goals

1. **Close gaps without inventing a Process asset.** Microsoft's lineage model supports three
 relationship shapes (`README.md` reference 5): DataSet -> Process -> DataSet (models the
 transform as its own asset), or a direct DataSet -> DataSet edge ("we know table A feeds table
 B, although we wouldn't know exactly which Process is between them"). This build's grounding
 pass confirmed the entity/relationship shape for the *direct* dataset-to-dataset case from
 Microsoft's own worked REST example, but did not find a REST-documented worked example for
 creating a *custom* Process-typed entity (as opposed to referencing a Process by
 `uniqueAttributes` in a relationship, which the tutorial does show for the built-in `Process`
 type against entities the tutorial itself created earlier in the same walkthrough). Rather than
 fabricate a custom-type-creation body for the Process option, this scenario uses only the
 directly-confirmed `direct_lineage_dataset_dataset` shape - see `design.md` Section 7 non-goals
 and `README.md` Section 11.
2. **Idempotent without depending on unconfirmed create semantics.** Like this repo's Data Quality
 and Unified Catalog scenarios, this build's grounding pass could not confirm whether
 Relationship - Create rejects, no-ops, or duplicates a second POST of an identical relationship.
 Rather than guess, this scenario's idempotency comes from an explicit existence check
 (Lineage - Get By Unique Attribute) before every create - the same pattern already established
 in `scenarios/data-quality/rules-and-scorecards/design.md` Section 2.
3. **Validation is not the same claim as deployment.** Creating a lineage link and *proving the
 whole chain is connected* are different guarantees. This scenario's `validate/` script doesn't
 just re-check that the one link this scenario created still exists (deploy's own idempotency
 check already effectively does that) - it walks the full lineage graph from the origin asset
 and confirms every asset in an independently-declared "expected chain" is reachable by an
 actual walkable path, which is what "end-to-end lineage validation" means in this scenario's
 name. This generalizes past this scenario's one custom link to any mix of natively-captured and
 custom-asserted hops in a longer real chain.
4. **Compose with, don't duplicate, this repo's existing Data Governance scenarios.** The upstream
 asset (`customerdb.dbo.Customers`) is the same asset `scenarios/data-map/
 scan-azure-sql-and-classify/` already registers and classifies (carrying the SSN/Credit Card
 Number classifications that repo's scenario establishes) - this scenario doesn't re-scan or
 re-register it. The downstream asset is assumed registered and scanned the same way, against a
 second (analytics) Azure SQL Database - see Section 6.
5. **Read-only validation, least privilege.** `validate/Test-EndToEndLineage.ps1` never mutates
 anything and needs only the Data Reader role, distinct from `deploy/`'s Data Curator
 requirement - matching this repo's established convention for every scenario with a
 `validate/` script.

## 3. Why custom lineage via REST (not the portal's manual-lineage UI, not a third-party lineage tool)

- **Manual lineage entries in the portal** (`README.md` reference 6) are a legitimate one-off
 option for a single missing link, but aren't code-reviewable, aren't repeatable across
 environments (dev/test/prod Purview accounts), and leave no artifact a pull request can diff -
 the same rationale this repo has already applied to DLP policies, labels, and Data Quality rules
 living in source-controlled JSON rather than being hand-clicked.
- **A third-party data-lineage/catalog tool** (e.g. running lineage tracking entirely outside
 Purview) would duplicate infrastructure Microsoft already operates and would not appear in the
 same Unified Catalog view as this repo's classification, glossary, and data-quality scenarios -
 a reviewer checking `customerdb.dbo.Customers`' governance posture in one place wouldn't see the
 downstream risk-summary hop at all.
- **Purview's own REST API for custom lineage** puts the gap-closing link in the same graph, the
 same portal Lineage tab, and the same `Get Lineage` API surface that natively-captured hops (ADF,
 Synapse, Power BI) already populate - a consumer browsing lineage in the portal sees one
 continuous chain, with no visual distinction between "Purview saw this automatically" and "an
 engineer asserted this via script," which is exactly the outcome Microsoft's own documented
 recommendation calls for: "Enable automated lineage where available and close gaps manually
 where required" (`README.md` reference 3).

## 4. Object model and REST call sequence

```mermaid
sequenceDiagram
    participant Deploy as New-CustomLineageRelationship.ps1
    participant AAD as Microsoft Entra ID
    participant API as Purview Data Map / Atlas v2 REST API
    participant Validate as Test-EndToEndLineage.ps1

    Deploy->>AAD: OAuth2 client_credentials (resource=https://purview.azure.net)
    AAD-->>Deploy: Bearer token
    loop for each link in the definition file
        Deploy->>API: GET lineage/uniqueAttribute/type/azure_sql_table (upstream, direction=OUTPUT, depth=1)
        API-->>Deploy: existing downstream relations (may not include this link yet)
        alt link already exists
            Deploy->>Deploy: skip (idempotent no-op)
        else link missing
            Deploy->>API: POST relationship (direct_lineage_dataset_dataset, end1/end2 by uniqueAttributes.qualifiedName, columnMapping)
            API-->>Deploy: 200 OK (relationship guid)
        end
    end
    Note over API: Natively-captured hops elsewhere in the chain (e.g. a future Power BI report<br/>built on CustomerRiskSummary) are populated by their own scan/connector, not this script.
    Validate->>AAD: OAuth2 client_credentials
    AAD-->>Validate: Bearer token
    Validate->>API: GET lineage/uniqueAttribute/type/azure_sql_table (origin, direction=OUTPUT, depth=MaxDepth)
    API-->>Validate: full downstream graph (guidEntityMap + relations)
    Validate->>Validate: breadth-first walk from baseEntityGuid; confirm every expectedDownstreamChain asset is reachable
```

Both scripts call the *same* Lineage - Get By Unique Attribute operation for two different
purposes: the deploy script uses a shallow (depth-1) call as an existence check before creating one
specific edge, while the validate script uses a deep (`-MaxDepth`) call to walk the entire
reachable graph and answer a broader question ("is the whole chain connected", not just "does this
one edge exist"). This is a deliberate design choice - it means the validate script doesn't merely
duplicate the deploy script's own existence check with weaker privilege, it answers a materially
different and more useful question. Full grounding: `deploy/New-CustomLineageRelationship.ps1` and
`validate/Test-EndToEndLineage.ps1` inline comments and `.NOTES` blocks.

## 5. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Relationship shape | `direct_lineage_dataset_dataset` only (no custom Process entity) | Directly confirmed via Microsoft's own worked REST example; a custom Process-type entity-creation body was not independently confirmed in this build - Design goal 1 |
| Idempotency mechanism | Explicit `Lineage - Get By Unique Attribute` existence check before every relationship POST | Doesn't depend on unconfirmed create-vs-duplicate semantics for `Relationship - Create` - Design goal 2, matches this repo's Data Quality scenario precedent |
| What "end-to-end validation" checks | Graph connectivity (breadth-first reachability from the origin), not just per-link existence | A link can exist while still being unreachable from a given origin in unusual graph shapes; presence in `guidEntityMap` alone is not proof of a walkable path - Design goal 3 |
| Column-level detail | `columnMapping` attribute (JSON-encoded string, matching Microsoft's own worked example exactly) on the custom relationship, checked (as a warning, not a hard failure) by validate | Table-level connectivity proves *that* data flows; column-level mapping is what lets a PII-impact-analysis question ("does a schema change to `Customers.SSN` affect `CustomerRiskSummary`?") be answered precisely rather than "somehow, probably" |
| Deploy/validate role split | Data Curator (deploy) vs. Data Reader (validate) | Matches this repo's least-privilege convention for every scenario with a `validate/` script ([RBAC model](/docs/rbac-model/) Section 5) |
| Endpoint parameterization | `-PurviewAccountEndpoint`, accepting either `https://api.purview-service.microsoft.com` (new portal) or `https://<account>.purview.azure.com` (classic portal) | Both are Microsoft's own documented valid values for this exact `/datamap/api/...` path family (`README.md` reference 9) - stronger grounding than this repo's earlier Unified Catalog/Data Quality scenarios had for the same dual-endpoint pattern |

## 6. What this scenario assumes already exists

- A Microsoft Purview account with Data Map enabled.
- The upstream asset, `customerdb.dbo.Customers`, already registered and scanned via
 `scenarios/data-map/scan-azure-sql-and-classify/` (or an equivalent Azure SQL Database scan).
- The downstream asset, `analyticsdb.dbo.CustomerRiskSummary`, already registered and scanned the
 same way, against a second (analytics) Azure SQL Database - this scenario does not create,
 register, or scan either database or table.
- The custom nightly transform job itself (the Python/Azure Functions process that actually reads
 `Customers` and writes `CustomerRiskSummary`) already exists and runs on its own schedule - this
 scenario only asserts the lineage fact about what that job does; it does not create, deploy, or
 orchestrate the job.
- An app registration with the Data Curator role (deploy) or Data Reader role (validate) on the
 collection containing both assets.

## 7. Non-goals

- This scenario does not create, register, or scan either the upstream or downstream data source -
 see Section 6.
- This scenario does not model the transform as a distinct Process-typed asset in the lineage
 graph (no intermediate node appears between the two tables) - see Design goal 1. A follow-up
 scoped to a confirmed custom-Process-entity REST shape is tracked in `PROGRESS.md`.
- This scenario does not attempt to enable or configure any of Microsoft's *native* lineage
 integrations (ADF, Synapse, Power BI, Databricks, Airflow/OpenLineage) - those are separate,
 connector-specific setup steps each covered by their own Microsoft Learn article
 (`README.md` reference 4), orthogonal to the custom-lineage gap this scenario closes.
- This scenario does not build or deploy the nightly transform job itself - see Section 6.
- This scenario does not attempt column-level lineage *validation against the live schema* (e.g.
 confirming `CustomerId` still exists as a column on both tables) - it only confirms the
 `columnMapping` attribute this scenario's own deploy script wrote is still present and non-empty.
 A schema-drift check is a different scenario, not duplicated here.
- This scenario's shipped example (`deploy/lineage/customer-risk-summary-lineage.json`) models a
 single hop only. `validate/Test-EndToEndLineage.ps1`'s Check 2 now resolves each
 `customLineageLinks` entry's relation edge against its own declared upstream node (falling back
 to the already-known `baseEntityGuid` only when that upstream node is the origin asset itself),
 so a longer, multi-hop definition file with a custom link further downstream than the origin's
 immediate output validates correctly without further script changes - the generalization
 previously tracked as a follow-up in `PROGRESS.md` is resolved. Authoring a multi-hop example
 definition file remains a separate, not-yet-built follow-up.
