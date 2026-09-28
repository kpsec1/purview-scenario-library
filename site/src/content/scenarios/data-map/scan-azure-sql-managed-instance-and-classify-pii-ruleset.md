---
title: "PII-Only Scan Rule Set for Azure SQL Managed Instance"
category: "Data Map"
categorySlug: "data-map"
theme: "know-your-data"
slug: "scan-azure-sql-managed-instance-and-classify-pii-ruleset"
teaser: "Extends Scan Azure SQL Managed Instance and Classify Sensitive Columns: creates a custom, PII-only Data Map scan rule set for Azure SQL Managed Instance - every system classification excluded except the ones…"
readingMinutes: 7
whoFor: "A data governance or security team that has already run the base Azure SQL Managed Instance scanning scenario - commonly a lift-and-shift landing zone for on-premises SQL Server estates - knows their compliance driver is narrow (PCI cardholder data, or a PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the System default scan rule set produces."
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

Extends *Scan Azure SQL Managed Instance and Classify Sensitive Columns*: creates a **custom,
PII-only** Data Map scan rule set for Azure SQL Managed Instance - every system classification
excluded except the ones you name to keep (U.S. Social Security Number and Credit Card Number by
default) - and reconciles the base scenario's already-registered scan onto it. The exclusion list
is derived at deploy time from the tenant's own live classification type definitions (never a
hard-coded snapshot), the same self-maintaining pattern already proven by the Azure SQL Database
and Azure Synapse Analytics sibling scenarios (*PII-Only Scan Rule Set for Azure SQL Database*,
*PII-Only Scan Rule Set for Azure Synapse Analytics*).

## Why this matters

Same driver as both sibling scenarios: the base scenario's System default rule set (named
`AzureSqlDatabaseManagedInstance`, ~200 built-in classifications) is right for a first, exploratory
scan of a newly registered instance. It is the wrong steady-state configuration for a PCI DSS
Requirement 3.2/12.5.2 (cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA):
those care about a specific, narrow set of data categories, not currencies, cloud-provider
credentials, or national ID formats for dozens of countries never in scope for a given program. A
narrower rule set gives auditors a catalog whose classification tags map directly to the regulatory
driver being demonstrated, and a faster scan (fewer classification comparisons per column) - a more
visible effect on Managed Instance than on a small standalone database, since Managed Instance is
frequently a lift-and-shift target that inherited a large, long-lived on-premises schema.

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
*Scan Azure SQL Managed Instance and Classify Sensitive Columns* first with the System default to discover what's
actually in the instance, then apply this scenario once the program's classification scope is
known.

## How the control works

See the design notes for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSqlDatabaseManagedInstanceScanRuleset` object, then reconciles the base scenario's
existing scan onto it.

## What it takes

### Prerequisites

Full licensing detail and citations: [Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first) (unchanged from the base
scenario - this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| ***Scan Azure SQL Managed Instance and Classify Sensitive Columns* already deployed** | The target data source and scan must already exist, and already run successfully | This scenario reconciles an EXISTING scan onto a new ruleset - `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found. It assumes the base scenario's own extra prerequisites (public endpoint, Microsoft Entra admin, Directory Readers role, NSG rule, `db_datareader` grant) are already in place - see that scenario's the prerequisites |
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

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as
`AzureSqlDatabaseManagedInstance`/`Custom`; every classification in
`-ExpectedRetainedClassifications` is genuinely absent from the exclusion list (not accidentally
excluded); the exclusion list is large enough to be meaningfully narrower than System default (a
`[WARN]`, not a hard fail, since the exact count depends on the tenant's live classification count
at validation time); and the target scan's `scanRulesetName`/`scanRulesetType` point at this
ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal -
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** - that only
the retained classification types appear on newly classified columns.

## Where it stops

- **This source type's custom ruleset `kind` is the SAME string as the System default ruleset's
  NAME (`AzureSqlDatabaseManagedInstance`) - confirmed independently, not inherited from either
  sibling by assumption.** The Azure SQL Database sibling has this same name-equals-kind property
  (`AzureSqlDatabase`); the Azure Synapse Analytics sibling does **not** (`AzureSynapseSQL` name vs.
  `AzureSynapseWorkspace` kind - a trap that sibling's own build specifically warned against
  assuming away for future source types). This build direct-fetched
  `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject`'s own documentation, which states
  the constructed object's `Kind` is `"AzureSqlDatabaseManagedInstance"` - the identical string to
  the base scenario's own `-ScanRulesetName` default. `deploy/Remove-PiiOnlyScanRuleset.ps1`'s
  `-RevertToRulesetName` default is therefore the same string used elsewhere in this scenario as
  the ruleset `kind` constant - correct for this source type, but confirmed rather than assumed
  (the design notes goal 6).
- **RESOLVED (2026-09-25): the exact REST JSON body for a Custom `AzureSqlDatabaseManagedInstanceScanRuleset`
  is now independently confirmed against the direct REST reference page**, not just the `Az.Purview`
  PowerShell module's GitHub source this scenario originally relied on (`learn.microsoft.com` was
  reachable in this later build, unlike the earlier one that hit `EGRESS_BLOCKED`). The
  [Scan Rulesets - Create Or Replace](https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace)
  reference page (api-version `2023-09-01`) documents `AzureSqlDatabaseManagedInstanceScanRuleset`
  (top-level `kind: "AzureSqlDatabaseManagedInstance"`, `scanRulesetType`, `properties`) with
  `AzureSqlDatabaseManagedInstanceScanRulesetProperties` containing exactly `createdAt` (read-only),
  `description`, `excludedSystemClassifications` (`string[]`), `includedCustomClassificationRuleNames`
  (`string[]`), `lastModifiedAt` (read-only) - matching what `deploy/New-PiiOnlyScanRuleset.ps1`
  already sends (`$rulesetBody.kind`/`.scanRulesetType`/`.properties.description`/
  `.properties.excludedSystemClassifications`/`.properties.includedCustomClassificationRuleNames`)
  with no discrepancy found. No code change required.
- **No `collection` property on the ruleset (account-wide, same as every sibling).** The
  `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject` constructor cmdlet exposes no
  collection or scan-scoping parameter (only `-Description`/`-ExcludedSystemClassification`/
  `-IncludedCustomClassificationRuleName`/`-Type`) - the same absence-of-a-collection-parameter
  evidence both sibling scenarios used to establish their own ruleset is account-wide, not scoped.
  One `AzureSqlDatabaseManagedInstance-PiiOnly` ruleset, created once, can be referenced by every
  Azure SQL Managed Instance scan in the account that wants this same narrower scope.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** Same
  finding as both sibling scenarios - classifications are listed by human-readable name and
  description only, no machine-parseable `MICROSOFT.*` identifier table. This is why the deploy
  script queries the tenant's live Types API instead of shipping a hand-typed snapshot (the design notes goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found - the same open item both sibling scenarios
  carry. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in its
  `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map
  sibling scenario - no documented REST endpoint for *creating* a custom classification rule was
  found. `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior - it always
  detaches the scan first (see the design notes goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs - see operations and tuning.
- **Inherits the base scenario's own open items.** The `AzureSqlDatabaseManagedInstanceCredential`
  scan kind (the alternative to the SAMI-authenticated default) still needs a Key Vault-backed
  credential object with no documented REST creation endpoint - the base scenario's the known limitations tracks this; this scenario's reconcile step is neutral toward whichever authentication kind
  the base scenario's scan already uses, and does not resolve that gap.
- **Does not extend to the on-premises SQL Server sibling.** *PII-Only Scan Rule Set for On-Premises SQL Server* (`kind: SqlServerDatabase`) remains a separate, not-yet-built fragment
 - do not assume its own name-vs-kind relationship without an independent check,
  per the design notes goal 6's explicit warning against pattern-matching across source types.