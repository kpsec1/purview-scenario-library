---
title: "PII-Only Scan Rule Set for Azure SQL Database"
category: "Data Map"
categorySlug: "data-map"
theme: "know-your-data"
slug: "scan-azure-sql-and-classify-pii-ruleset"
teaser: "Extends Scan Azure SQL Database and Classify Sensitive Columns: creates a custom, PII-only Data Map scan rule set for Azure SQL Database - every system classification excluded except the ones you name to keep…"
readingMinutes: 5
whoFor: "A data governance or security team that has already run the base Azure SQL Database scanning scenario, knows their compliance driver is narrow (PCI cardholder data, or a PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the System default scan rule set produces."
frameworks: ["GDPR","PCI DSS","CCPA"]
licensing: ["Pay-as-you-go"]
deployCount: 2
validateCount: 1
hasDesign: true
hasRollback: true
hasRunbook: true
toc: [{"id":"the-short-version","text":"The short version"},{"id":"why-this-matters","text":"Why this matters"},{"id":"how-the-control-works","text":"How the control works"},{"id":"what-it-takes","text":"What it takes"},{"id":"proof-it-works","text":"Proof it works"},{"id":"where-it-stops","text":"Where it stops"}]
---
## The short version

Extends *Scan Azure SQL Database and Classify Sensitive Columns*: creates a **custom, PII-only** Data Map
scan rule set for Azure SQL Database - every system classification excluded except the ones you
name to keep (U.S. Social Security Number and Credit Card Number by default) - and reconciles the
base scenario's already-registered scan onto it. The exclusion list is derived at deploy time from
the tenant's own live classification type definitions (never a hard-coded snapshot), so an organization
with a narrow compliance driver gets a catalog and a scan that only ever surface the handful of
classifications their program actually cares about, instead of Microsoft's full ~200-classification
system set.

## Why this matters

The base scenario's System default rule set is the right choice for a first, exploratory scan -
you don't yet know what's in the database. It is the wrong steady-state configuration for a PCI
DSS or PII-focused program: PCI DSS Requirement 3.2/12.5.2 (cardholder data discovery) and most
privacy statutes (GDPR Art. 30, CCPA/CPRA) care about a specific, narrow set of data categories,
not the ~200 classification types Purview ships out of the box (currencies, cloud-provider
credentials, national ID formats for dozens of countries never in scope for a given program). A
narrower rule set gives auditors and reviewers a catalog whose classification tags map directly to
the regulatory driver being demonstrated, rather than a long tail of irrelevant matches to filter
through, and a faster scan (fewer classification comparisons per column).

This scenario is deliberately a companion to, not a replacement for, the base scenario: run the
base scenario first with the System default to discover what's actually in the database, then
apply this scenario once the program's classification scope is known.

## How the control works

See the design notes for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSqlDatabaseScanRuleset` object, then reconciles the base scenario's existing scan
onto it.

## What it takes

### Prerequisites

Full licensing detail and citations: [Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first) (unchanged from the base
scenario - this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| ***Scan Azure SQL Database and Classify Sensitive Columns* already deployed** | The target data source and scan must already exist | This scenario reconciles an EXISTING scan onto a new ruleset - `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires - Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself ([RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model)) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario - [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended) |

> Verify current entitlement names against [Licensing matrix](/docs/licensing-matrix/) (dated 2026-09-02) before a
> sales commitment.

### Cost and licensing

No new licensing surface - this scenario uses the same PAYG Data Map billing as the base scenario
([Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first)). A narrower scan rule set may modestly reduce scan **compute**
time (fewer classification comparisons per column), which is a cost factor under Purview's
consumption-based Data Map billing, though Microsoft does not publish a per-classification cost
breakdown to quantify the exact savings.

## Proof it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as `AzureSqlDatabase`/`Custom`;
every classification in `-ExpectedRetainedClassifications` is genuinely absent from the exclusion
list (not accidentally excluded); the exclusion list is large enough to be meaningfully narrower
than System default (a `[WARN]`, not a hard fail, since the exact count depends on the tenant's
live classification count at validation time); and the target scan's `scanRulesetName`/
`scanRulesetType` point at this ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal -
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** - that only
the retained classification types appear on newly classified columns.

## Where it stops

- **VERIFY (custom scan rule set REST creation) - CLOSED this build.** The base scenario's
  the known limitations carried this forward as an open VERIFY ("the exact REST JSON body for the 'Scan
  Rulesets - Create Or Update' operation was not independently confirmed"). This build
  direct-fetched the canonical **Scan Rulesets - Create Or Replace** and **- Get** REST reference
  pages in full - the `AzureSqlDatabaseScanRuleset`/`AzureSqlDatabaseScanRulesetProperties` body
  shape used by `deploy/New-PiiOnlyScanRuleset.ps1` is confirmed directly against Microsoft's own
  reference, not reconstructed from adjacent evidence. See reference 1 below.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** This
  build fetched `data-map-classification-supported-list` in full expecting a machine-parseable
  table of `MICROSOFT.*` names; the page instead lists classifications by human-readable name and
  description only (grep for `MICROSOFT\.` against the fetched page returned zero matches). This
  is precisely why the deploy script queries the tenant's live Types API instead of shipping a
  hand-typed snapshot - see the design notes goal 1.
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and this build found no
  documentation addressing pagination behavior for a tenant with an unusually large number of
  custom classification rules layered on top of the ~200 system ones. `deploy/New-PiiOnlyScanRuleset.ps1`
  does not implement paging; flagged inline in its `.NOTES`.
- **Custom classification rule authoring stays out of scope.** No documented REST endpoint for
  *creating* a custom classification rule was found - Microsoft's own community guidance states
  custom classification rules must be created manually in the portal. `-IncludedCustomClassificationRuleNames`
  only references rules that already exist; it does not author them.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation this build
  found states whether deleting a scan rule set still referenced by a scan succeeds, is rejected,
  or orphans the reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior -
  it always detaches the scan first (see the design notes goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs - see operations and tuning.