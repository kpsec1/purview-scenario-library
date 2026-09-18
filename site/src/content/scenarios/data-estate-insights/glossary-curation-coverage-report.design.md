---
part: "design"
parent: "data-estate-insights/glossary-curation-coverage-report"
---
## 1. Problem statement

Microsoft Purview's native **Data Estate Insights** application ships a **Classic glossary** report
with exactly the KPIs a Chief Data Officer or Data Steward wants: total terms, terms approved but
not yet attached to any asset, expired terms still attached to assets, a status/asset-attachment
snapshot, and a breakdown of incomplete terms by the specific field that's missing
(`README.md` reference 1). It requires no scripting and is the right first stop for interactively
exploring glossary health.

It has the same three structural limits `classification-coverage-report/design.md` §1 already
documents for its own sibling native report — no REST API of its own, an export/refresh model built
around portal roles rather than a least-privilege automation identity, and no durable point-in-time
history beyond the report's own refresh cadence — plus a **fourth, specific to this report**:

4. **It reports on the wrong term model for this repo's own glossary scenario.** The classic
   glossary report's status vocabulary (**Draft → Approved → Alert → Expired**,
   `README.md` reference 1) belongs to the **classic, Atlas-based Data Catalog glossary** — the
   legacy object model behind the classic Purview Data Catalog (`README.md` reference 9). This
   repo's own `scenarios/unified-catalog/curate-business-glossary/` deliberately builds terms
   through the **current Unified Catalog Terms REST API** instead (`design.md` §3 of that scenario),
   whose `Term.status` enum is **`DRAFT` → `PUBLISHED` → `EXPIRED`** — three values, no `Alert`
   equivalent (`README.md` reference 4). Microsoft's own Unified Catalog API overview states the API
   "only covers the Unified Catalog features that are available in General Availability (GA)"
   (`README.md` reference 5) — i.e. the forward path, not the classic model the native glossary
   report targets. A report built by calling the classic report's own (nonexistent) API, or by
   assuming its status vocabulary applies unchanged to the new term model, would misdescribe this
   repo's own glossary scenario. See §2 goal 1 for how this scenario resolves that.

## 2. Design goals

1. **Reproduce the classic glossary report's KPI *categories* against the term model this repo
   actually uses (Unified Catalog Terms), not the classic report itself, and say so plainly.** This
   scenario does not call, scrape, or automate the classic glossary report's UI or any undocumented
   API behind it. It computes the same four KPI *categories* — total terms, status/asset-attachment
   snapshot, and incomplete-term breakdown — from the Unified Catalog **Terms** operation group
   (`README.md` reference 7) directly, the same automation surface `curate-business-glossary`
   already uses (automation surface 4 per `docs/automation-surface.md` §1). Every place this
   scenario's terminology diverges from the classic report's own (status names, "steward" vs.
   "owner") is called out explicitly in §4/§7 below and `README.md` §11 — never silently assumed
   equivalent.
2. **Use the least-privileged role that can still answer the question asked, and disclose the one
   place that isn't Data Reader-level.** Unlike `classification-coverage-report` (Data Reader
   throughout), a status/completeness report that must see **`DRAFT`** terms cannot run as a pure
   reader: Microsoft's own glossary-terms guide states a term in `DRAFT` status "is visible only to
   Data Stewards and Governance Domain Owners" (`README.md` reference 6, already cited by
   `curate-business-glossary/README.md` §8), and the **Global/Local Catalog Reader** roles are
   documented as reading only **published** artifacts (`README.md` reference 8). This scenario is
   honest about that constraint rather than pretending a reader-level credential can see the whole
   picture: it defaults to requiring **Data Steward** on every domain in scope (full status
   coverage), and offers an explicit `-PublishedOnly` mode that runs as **Global/Local Catalog
   Reader** instead, at the cost of reporting Draft/Expired-dependent KPIs as `N/A` rather than a
   false zero. See §5.
3. **Compute term-to-asset attachment honestly, from the documented relationship primitive, not a
   guessed field.** The `Term` object itself (`README.md` reference 4) carries no
   `hasAssets`/`assetCount` field. The only documented way to determine whether a term is linked to
   any data asset is the **Terms - List Related Entities** operation
   (`GET .../terms/{termId}/relationships?entityType=DATAASSET`, `README.md` reference 7) called
   per term — an N+1 pattern this scenario names as a real, disclosed cost (§6/`README.md` §11),
   exactly the same class of trade-off `classification-coverage-report/design.md` §2 goal 3 accepts
   for its own per-record pagination rather than inventing an unconfirmed shortcut filter.
4. **A trend log, not just a snapshot** — same replace-by-`RunId` idempotency pattern as
   `classification-coverage-report` (§5 below), so the longitudinal history the native report's own
   refresh cadence doesn't preserve is kept in a source-controllable CSV.
5. **Idempotent in the read-only-report sense**: this scenario creates no Purview object. Re-running
   for the same `-RunId` replaces that RunId's row(s) rather than duplicating them. A `-WhatIf` dry
   run still performs the live reads needed to report accurate numbers (same precedent as
   `curate-business-glossary/README.md` §11's "-WhatIf still performs live, read-only calls") but
   writes nothing to disk.
6. **Compose with, don't duplicate, this repo's existing Unified Catalog narrative.** The worked
   example reports on the `Customer Experience` domain `curate-business-glossary` already creates
   (`Customer`, `Customer ID`, `Customer Lifetime Value`, `Net Promoter Score`) — this report is the
   natural "how healthy is the glossary we just curated, over time" companion to that scenario, the
   same relationship `classification-coverage-report` has to `scan-azure-sql-and-classify`.

## 3. Why the Unified Catalog Terms REST API (not the classic report, not Discovery - Query)

- **The classic glossary report** (`README.md` reference 1) targets the classic, Atlas-based
  glossary model (§1, point 4) — a different object model from the one this repo's own glossary
  scenario builds. Reproducing *its* exact KPIs against terms that don't exist in that model would
  require either misrepresenting the new model's three-value status as the classic model's four, or
  silently pretending the classic report covers Unified Catalog terms at all — neither is
  supportable without a Microsoft statement confirming the classic report reads the new term model,
  which this build's grounding pass did not find. See §7 for what this rules out.
- **Discovery - Query** (`classification-coverage-report`'s own data source) returns Data Map search
  results with a documented `classification`/`label` array per asset (`classification-coverage-
  report/design.md` §2 goal 1) but its documented response schema carries no glossary-term
  attachment field for the *new* Unified Catalog term model — that relationship lives in the
  **Terms** operation group's own `List Related Entities` operation instead (§2 goal 3), a different
  primitive for a different object model, exactly as `classification-coverage-report/design.md` §7
  already anticipated ("would need a different REST primitive (likely the Unified Catalog Terms
  operation group)").
- **The Unified Catalog Terms REST API** is the same, already-grounded automation surface
  `curate-business-glossary` uses to author these exact terms (`README.md` reference 7) — reusing it
  here means this report's numbers are computed from the same object graph a Data Steward sees when
  editing a term in the portal, with no separate ingestion or duplication of Purview's own metadata
  store.

## 4. Status- and role-vocabulary mapping (stated explicitly, not assumed)

| Classic glossary report concept | This scenario's Unified Catalog Terms equivalent | Confidence |
|---|---|---|
| `Approved` status | `PUBLISHED` status | Both mean "reviewed and visible beyond curators" — the closest documented correspondence, not a Microsoft-stated equivalence (`README.md` §11) |
| `Alert` status | **No equivalent field exists on `Term`** | Not reproduced — see §7 non-goal. The classic report's `Alert` state (a data-quality-flagged term) has no documented analog in the `CatalogModelStatus` enum (`DRAFT`/`PUBLISHED`/`EXPIRED` only, `README.md` reference 4) |
| `Draft` status | `DRAFT` status | Same word, confirmed field (`README.md` reference 4) |
| `Expired` status | `EXPIRED` status | Same word, confirmed field (`README.md` reference 4) |
| "Missing steward" | Missing `contacts.owner` (empty array) | Interpretive mapping — the new `ContactsMap` schema's contact **types** are `owner`/`expert`/`databaseAdmin`, not `steward`/`expert` (`README.md` reference 4); this scenario treats `owner` as the closest documented analog of the classic report's "steward" concept and states so rather than asserting they're the same Microsoft-defined term |
| "Missing expert" | Missing `contacts.expert` (empty array) | Same field name in both models — highest-confidence mapping in this table |
| "Missing definition" | Empty/whitespace-only `description` | Same field name and meaning in both models |
| "Missing multiple" | 2 or more of the three checks above are true for the same term | Same aggregation logic as the classic report describes |
| Terms "with"/"without" assets | `List Related Entities?entityType=DATAASSET` returns a non-empty/empty `value[]` | Confirmed operation (§2 goal 3); the classic report's own definition of "asset" for this purpose isn't published beyond the screenshot in `README.md` reference 1, so this scenario treats *any* linked data asset as sufficient, not a specific count threshold |

## 5. Object model and REST call sequence

```mermaid
sequenceDiagram
    participant Report as Export-GlossaryCurationCoverageReport.ps1
    participant AAD as Microsoft Entra ID
    participant API as Purview Unified Catalog REST API

    Report->>AAD: OAuth2 client_credentials (resource=https://purview.azure.net)
    AAD-->>Report: Bearer token
    loop for each -DomainId
        loop while nextLink present
            Report->>API: GET terms?domainId={id}&skip&top
            API-->>Report: Term[] (id, name, status, description, contacts, ...), nextLink
        end
        Report->>Report: tally by status; tally completeness<br/>(empty description/owner/expert)
        alt -SkipAssetLinkCheck not set
            loop for each term in this domain
                Report->>API: GET terms/{termId}/relationships?entityType=DATAASSET
                API-->>Report: TermRelationship[] (empty = "without assets")
                Report->>Report: tally with-assets/without-assets per status
            end
        else
            Report->>Report: AssetLinkage fields reported as "Skipped" (README.md Section 11)
        end
    end
    Report->>Report: write/replace this RunId's row(s) in the trend-log CSV;<br/>write a per-run breakdown JSON
```

Every call is a **read-only GET** — the Terms operation group's own read operations
(`List`, `List Related Entities`) require no `ShouldProcess` gate on the Purview side. This
scenario's only side effect is the local (or blob-stored) report file it writes, wrapped in
`$PSCmdlet.ShouldProcess()` so `-WhatIf` shows exactly what would be written without touching disk.
Full grounding: `deploy/Export-GlossaryCurationCoverageReport.ps1`'s inline comments and `.NOTES`.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Data source for KPIs | Unified Catalog **Terms** operation group (`List`, `List Related Entities`), read-only | Same automation surface `curate-business-glossary` already grounds for this exact object model — §3 |
| Status tally | Client-side count of each returned `Term.status` value | Documented field on every `List` response item (`README.md` reference 4) — no separate filter call needed |
| Completeness tally | Client-side test of `description`/`contacts.owner`/`contacts.expert` emptiness per term | Same "test the documented field client-side, don't guess a filter" discipline as `classification-coverage-report/design.md` §2 goal 3 — `Terms - Get Facets`' `facets[].name` values are not enumerated anywhere in Microsoft's reference (only an `owner`-facet worked example exists, `README.md` reference 7), so this scenario does not attempt an unconfirmed `status`/`hasAssets` facet request — see `README.md` §11 |
| Asset-attachment tally | Per-term `List Related Entities?entityType=DATAASSET`, non-empty response = "has assets" | Only documented primitive for this relationship (§2 goal 3) — an N+1 cost, opt-out via `-SkipAssetLinkCheck` |
| Role required (default) | **Data Steward** on every `-DomainId` in scope | Only documented role that can see `DRAFT`-status terms (§2 goal 2) — this scenario states plainly that this is *more* privileged than `classification-coverage-report`'s Data Reader, rather than claiming parity it can't back up |
| Role required (`-PublishedOnly`) | **Global Catalog Reader** or **Local Catalog Reader** | Documented as reading only published artifacts (`README.md` reference 8) — the least-privileged path this report supports, at the cost of Draft/Expired KPIs being unavailable |
| Pagination | `skip`/`top` (Terms - List has no documented maximum `top` — this scenario defaults to a conservative 100 and follows `nextLink` until absent) | `README.md` reference 4's `PagedTerm` shape confirms `nextLink`-style paging, not `continuationToken` — a genuinely different pagination primitive from Discovery - Query, not copy-pasted from `classification-coverage-report` without checking |
| Idempotency mechanism | Replace-by-`RunId` in the trend-log CSV | Same precedent as `classification-coverage-report/design.md` §5 |
| Output format | CSV trend log (one row per `RunId` × `DomainId`) + a per-run JSON breakdown (per-status counts, per-domain incomplete-term names, per-domain unlinked-published-term names) | Same shape rationale as `classification-coverage-report/README.md` §6 |
| Scope parameter | `-DomainIds` (required, one or more governance-domain GUIDs) | Unified Catalog domains are the natural scoping unit for this API — mirrors `curate-business-glossary`'s own domain-scoped model, not a Data Map collection |

## 7. What this scenario assumes already exists

- A Microsoft Purview account with Unified Catalog enabled and at least one governance domain
  containing glossary terms — the worked example reuses the `Customer Experience` domain and its
  four terms from `scenarios/unified-catalog/curate-business-glossary/`.
- An app registration holding **Data Steward** (default mode) or **Global/Local Catalog Reader**
  (`-PublishedOnly` mode) on the domain(s) in scope.
- Wherever the trend-log CSV is written persists between runs — this scenario does not provision
  that storage; see `README.md` §6/§9.

## 8. Non-goals

- **This scenario does not call, scrape, or reverse-engineer the classic glossary report's own UI or
  any internal API behind it** — only the public Unified Catalog Terms REST operations (§2 goal 1).
- **No `Alert`-status equivalent is computed or invented.** The classic report's data-quality-style
  `Alert` state has no documented field on the new `Term` object (§4) — this scenario reports three
  statuses (`DRAFT`/`PUBLISHED`/`EXPIRED`), not four, and says why rather than fabricating a fourth.
- **"Weekly/monthly active users of the catalog" (the native Data Stewardship/Catalog Adoption
  dashboards' usage-telemetry metric, `README.md` reference 2) is explicitly out of scope.** That
  metric is Microsoft-internal portal-usage telemetry, not glossary metadata — no documented REST
  operation on the Terms (or any Unified Catalog) operation group exposes it, and this scenario does
  not attempt to approximate it from an unrelated signal (e.g. `systemData.lastModifiedAt` recency is
  an edit-activity proxy, not a view/search-activity count, and this scenario does not present it as
  one). This was the specific gap the original `PROGRESS.md` follow-up flagged as needing "a
  different REST primitive" — this build confirms none exists, rather than guessing one.
- **This scenario does not reconcile against the classic Data Catalog's own Atlas-based glossary
  terms** (the object model the classic report actually reads, per §1 point 4) — a buyer who has
  *not* migrated to Unified Catalog terms would see this scenario's KPIs report zero/empty results
  against the classic report's non-zero classic-glossary numbers. That migration gap is a real,
  disclosed limitation (`README.md` §11), not a bug in this scenario's logic.
- **No native Purview alert or SIEM sink** — same treatment as `classification-coverage-report/
  design.md` §7: this scenario writes flat CSV/JSON files and leaves routing them into a SIEM or BI
  tool as the buyer's own integration.
- **At very large glossary scale**, the per-term `List Related Entities` call (§2 goal 3) has a real,
  non-trivial API-call cost (one call per term, every run, unless `-SkipAssetLinkCheck` is set) —
  this scenario does not implement incremental/delta asset-link tallying; see `README.md` §11.
