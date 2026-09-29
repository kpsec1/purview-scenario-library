---
title: "PII-Only Scan Rule Set for Azure Synapse Analytics"
category: "Data Map"
categorySlug: "data-map"
theme: "know-your-data"
slug: "scan-azure-synapse-and-classify-pii-ruleset"
teaser: "Extends Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns: creates a custom, PII-only Data Map scan rule set for Azure Synapse Analytics (dedicated and/or serverless SQL pools) - every system classification excluded except the ones you…"
readingMinutes: 7
whoFor: "A data governance or security team that has already run the base Azure Synapse Analytics scanning scenario, knows their compliance driver is narrow (PCI cardholder data, or a PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the System default scan rule set produces across a Synapse workspace's dedicated and serverless pools."
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

Extends *Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns*: creates a **custom, PII-only** Data
Map scan rule set for Azure Synapse Analytics (dedicated and/or serverless SQL pools) - every
system classification excluded except the ones you name to keep (U.S. Social Security Number and
Credit Card Number by default) - and reconciles the base scenario's already-registered scan onto
it. The exclusion list is derived at deploy time from the tenant's own live classification type
definitions (never a hard-coded snapshot), the same self-maintaining pattern already proven by the
Azure SQL Database sibling scenario (*PII-Only Scan Rule Set for Azure SQL Database*).

## Why this matters

Same driver as the Azure SQL Database sibling: the base scenario's System default rule set (named
`AzureSynapseSQL`, ~200 built-in classifications) is right for a first, exploratory scan of a new
workspace. It is the wrong steady-state configuration for a PCI DSS Requirement 3.2/12.5.2
(cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA): those care about a
specific, narrow set of data categories, not currencies, cloud-provider credentials, or national ID
formats for dozens of countries never in scope for a given program. A narrower rule set gives
auditors a catalog whose classification tags map directly to the regulatory driver being
demonstrated, and a faster scan (fewer classification comparisons per column) across a Synapse
workspace's SQL pools - a workload that can already run for hours on a nontrivial dedicated pool per
the base scenario's own operational notes.

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
*Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* first with the System default to discover what's actually in the
workspace, then apply this scenario once the program's classification scope is known.

## How the control works

See the design notes for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSynapseWorkspaceScanRuleset` object (`kind: AzureSynapseWorkspace`), then reconciles
the base scenario's existing scan onto it - covering whichever of the dedicated/serverless pools
that scan already targets.

## What it takes

### Prerequisites

Full licensing detail and citations: [Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first) (unchanged from the base
scenario - this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| ***Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns* already deployed** | The target data source and scan must already exist | This scenario reconciles an EXISTING scan onto a new ruleset - `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires - Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself ([RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model)) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario - [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended) |

> Verify current entitlement names against [Licensing matrix](/docs/licensing-matrix/) (dated 2026-09-02) before a
> sales commitment.

### Cost and licensing

No new licensing surface - this scenario uses the same PAYG Data Map billing as the base scenario
([Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first)). A narrower scan rule set may modestly reduce scan **compute**
time (fewer classification comparisons per column) across the workspace's SQL pools, which is a
cost factor under Purview's consumption-based Data Map billing, though Microsoft does not publish a
per-classification cost breakdown to quantify the exact savings.

## Proof it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as
`AzureSynapseWorkspace`/`Custom`; every classification in `-ExpectedRetainedClassifications` is
genuinely absent from the exclusion list (not accidentally excluded); the exclusion list is large
enough to be meaningfully narrower than System default (a `[WARN]`, not a hard fail, since the exact
count depends on the tenant's live classification count at validation time); and the target scan's
`scanRulesetName`/`scanRulesetType` point at this ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal -
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** - that only
the retained classification types appear on newly classified columns, across both the dedicated and
serverless pools if the base scenario's scan covers both.

## Where it stops

- **The system ruleset NAME (`AzureSynapseSQL`) is not the same string as the custom ruleset KIND
  (`AzureSynapseWorkspace`) - a naming trap this source type has and the Azure SQL Database sibling
  does not.** For Azure SQL Database, the System default ruleset name and the custom ruleset `kind`
  are the identical string (`AzureSqlDatabase`), so reverting a scan and picking the custom-ruleset
  `kind` value are the same lookup. For Azure Synapse Analytics they are **not**: the System default
  ruleset the base scenario's scan starts on is named `AzureSynapseSQL`
  (`scan-azure-synapse-and-classify/deploy/New-AzureSynapseDataMapScan.ps1`'s own
  `-ScanRulesetName` default), while a *custom* ruleset for this source type must be created with
  `kind: AzureSynapseWorkspace` (confirmed directly against the
  `New-AzPurviewAzureSynapseWorkspaceScanRulesetObject` Az.Purview module source below - its worked
  example's output shows `Kind : AzureSynapseWorkspace`). `deploy/Remove-PiiOnlyScanRuleset.ps1`'s
  `-RevertToRulesetName` default is hard-coded to `'AzureSynapseSQL'` precisely because of this
  split; do not "simplify" it to match the ruleset `kind` string, which would point the revert at a
  ruleset object that does not exist.
- **RESOLVED (2026-09-25): the exact REST JSON body for a Custom `AzureSynapseWorkspaceScanRuleset`
  is now independently confirmed against the direct REST reference page**, not just the `Az.Purview`
  PowerShell module's GitHub source this scenario originally relied on (`learn.microsoft.com` was
  reachable in this later build, unlike the earlier one that hit `EGRESS_BLOCKED`). The
  [Scan Rulesets - Create Or Replace](https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace)
  reference page (api-version `2023-09-01`) documents `AzureSynapseWorkspaceScanRuleset` (top-level
  `kind: "AzureSynapseWorkspace"`, `scanRulesetType`, `properties`) with
  `AzureSynapseWorkspaceScanRulesetProperties` containing exactly `createdAt` (read-only),
  `description`, `excludedSystemClassifications` (`string[]`), `includedCustomClassificationRuleNames`
  (`string[]`), `lastModifiedAt` (read-only) - matching what `deploy/New-PiiOnlyScanRuleset.ps1`
  already sends (`$rulesetBody.kind`/`.scanRulesetType`/`.properties.description`/
  `.properties.excludedSystemClassifications`/`.properties.includedCustomClassificationRuleNames`)
  with no discrepancy found. No code change required.
- **No `collection` property on the ruleset (account-wide, same as every sibling).** The
  `New-AzPurviewAzureSynapseWorkspaceScanRulesetObject` constructor cmdlet exposes no collection or
  scan-scoping parameter (only `-Description`/`-ExcludedSystemClassification`/
  `-IncludedCustomClassificationRuleName`/`-Type`) - the same absence-of-a-collection-parameter
  evidence the Azure SQL Database sibling used to establish its own ruleset is account-wide, not
  scoped. One `AzureSynapseWorkspace-PiiOnly` ruleset, created once, can be referenced by every
  Azure Synapse Analytics scan in the account that wants this same narrower scope.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** Same
  finding as the Azure SQL Database sibling - classifications are listed by human-readable name and
  description only, no machine-parseable `MICROSOFT.*` identifier table. This is why the deploy
  script queries the tenant's live Types API instead of shipping a hand-typed snapshot (the design notes goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found - the same open item the Azure SQL Database
  sibling carries. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in
  its `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map
  sibling scenario - no documented REST endpoint for *creating* a custom classification rule was
  found. `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior - it always
  detaches the scan first (see the design notes goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs - see operations and tuning.
- **Inherits the base scenario's own open item on the `resourceTypes` scan property.** The base
  scenario's `deploy/New-AzureSynapseDataMapScan.ps1` deliberately omits the scan object's optional
  `resourceTypes` field (no confirmed JSON shape found during that build). This scenario's own
  reconcile step (the design notes goal 2: `GET` the scan, copy every property forward, overwrite only
  the two ruleset fields) preserves whatever `resourceTypes` state the scan already has - it neither
  adds nor removes that property, so it introduces no new risk on this specific point.