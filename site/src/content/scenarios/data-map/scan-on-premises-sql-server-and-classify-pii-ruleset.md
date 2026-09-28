---
title: "PII-Only Scan Rule Set for On-Premises SQL Server"
category: "Data Map"
categorySlug: "data-map"
theme: "know-your-data"
slug: "scan-on-premises-sql-server-and-classify-pii-ruleset"
teaser: "Extends Scan On-Premises SQL Server and Classify Sensitive Columns: creates a custom, PII-only Data Map scan rule set for on-premises SQL Server - every system classification excluded except the ones you name to keep…"
readingMinutes: 9
whoFor: "A data governance or security team that has already run the base on-premises SQL Server scanning scenario - commonly the organization's oldest, least-documented regulated-data estate, predating any cloud migration program - knows their compliance driver is narrow (PCI cardholder data, or a PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the System default scan rule set produces."
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

Extends *Scan On-Premises SQL Server and Classify Sensitive Columns*: creates a **custom,
PII-only** Data Map scan rule set for on-premises SQL Server - every system classification excluded
except the ones you name to keep (U.S. Social Security Number and Credit Card Number by default) -
and reconciles the base scenario's already-registered, self-hosted-integration-runtime-backed scan
onto it. The exclusion list is derived at deploy time from the tenant's own live classification type
definitions (never a hard-coded snapshot), the same self-maintaining pattern already proven by the
three Azure Data Map PII-ruleset sibling scenarios in this library
(*PII-Only Scan Rule Set for Azure SQL Database*, *PII-Only Scan Rule Set for Azure Synapse Analytics*,
*PII-Only Scan Rule Set for Azure SQL Managed Instance*). This is the fourth and last of this
repo's Data Map source types to receive this treatment - no further siblings remain in
the project backlog's follow-up chain.

## Why this matters

Same driver as every sibling scenario: the base scenario's System default rule set (inferred name
`SqlServerDatabase`, ~200 built-in classifications) is right for a first, exploratory scan of a
newly registered instance. It is the wrong steady-state configuration for a PCI DSS Requirement
3.2/12.5.2 (cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA): those care
about a specific, narrow set of data categories, not currencies, cloud-provider credentials, or
national ID formats for dozens of countries never in scope for a given program. A narrower rule set
gives auditors a catalog whose classification tags map directly to the regulatory driver being
demonstrated, and a faster scan (fewer classification comparisons per column).

The stakes of this scope choice are unusually high for this specific source type: the base
scenario's own design notes states plainly that on-premises SQL Server "is disproportionately
likely to be where an organization's oldest, least-documented regulated data lives - instances that
predate a cloud migration program, were never in scope for it, or are deliberately kept on-premises
for latency, licensing, or regulatory reasons." Narrowing classification scope on exactly this kind
of legacy, schema-drifted instance is a real monitoring-coverage trade-off, not just a performance
tweak - see the known limitations and the review notes.

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
*Scan On-Premises SQL Server and Classify Sensitive Columns* first with the System default to discover what's actually
in the instance, then apply this scenario once the program's classification scope is known.

## How the control works

See the design notes for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1` reads
the tenant's live classification type definitions, computes an exclusion list, creates a `Custom`
`SqlServerDatabaseScanRuleset` object, then reconciles the base scenario's existing
SHIR/credential-backed scan onto it - preserving the `connectedVia` integration-runtime reference and
stored-credential reference untouched.

## What it takes

### Prerequisites

Full licensing detail and citations: [Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first) (unchanged from the base
scenario - this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| ***Scan On-Premises SQL Server and Classify Sensitive Columns* already deployed and running successfully** | The self-hosted integration runtime node must be registered and **Running**, the data source and scan must already exist, and the Purview credential object must already exist | This scenario reconciles an EXISTING scan onto a new ruleset - `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found. It assumes the base scenario's own unusually long prerequisite list (SHIR resource + software install + node registration, SQL/Windows login + `db_datareader` grant, Key Vault secret, Purview credential object) is already satisfied - see that scenario's the prerequisites. This scenario never grants, verifies, or troubleshoots any of it |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires - Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself ([RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model)) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario - [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended) |

> Verify current entitlement names against [Licensing matrix](/docs/licensing-matrix/) (dated 2026-09-02) before a
> sales commitment.

### Cost and licensing

No new licensing surface - this scenario uses the same PAYG Data Map billing as the base scenario
([Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first)), plus the base scenario's own SHIR host cost (a dedicated VM or
on-premises server, not a Data Map billing meter). A narrower scan rule set may modestly reduce scan
**compute** time (fewer classification comparisons per column), which is a cost factor under
Purview's consumption-based Data Map billing, though Microsoft does not publish a per-classification
cost breakdown to quantify the exact savings.

## Proof it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as `SqlServerDatabase`/`Custom`;
every classification in `-ExpectedRetainedClassifications` is genuinely absent from the exclusion
list (not accidentally excluded); the exclusion list is large enough to be meaningfully narrower than
System default (a `[WARN]`, not a hard fail, since the exact count depends on the tenant's live
classification count at validation time); the target scan's `scanRulesetName`/`scanRulesetType`
point at this ruleset; and the scan's `kind` is `SqlServerDatabaseCredential` with a `connectedVia`
reference still present (i.e. this scenario didn't accidentally strip the SHIR wiring during the
reconcile step).

This script **cannot** confirm self-hosted integration runtime node health - the Integration Runtimes
- Get REST operation returns the resource definition, not live node status. Check **Data Map →
Integration runtimes → the runtime → Nodes** tab separately (same limitation the base scenario's own
the validation steps check 2 discloses); a scan can pass every check here and still fail at run time if no
node has registered.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal -
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** - that only the
retained classification types appear on newly classified columns.

## Where it stops

- **This source type's custom ruleset `kind` is confirmed `SqlServerDatabase` - independently
  grounded via THREE converging Microsoft sources in this build, not inherited from any sibling by
  assumption.** Unlike the Azure Synapse Analytics and Azure SQL Managed Instance sibling builds
  (both of which hit `EGRESS_BLOCKED` against `learn.microsoft.com`), this build reached
  `learn.microsoft.com` directly and confirmed the `kind` value against: (1) the
  `New-AzPurviewSqlServerDatabaseScanRulesetObject` PowerShell reference's own worked example
  (`Kind: SqlServerDatabase`); (2) the Scan Rulesets - Get REST API reference's
  `SqlServerDatabaseScanRuleset` object definition; and (3) the `@azure-rest/purview-scanning`
  JavaScript SDK's `SqlServerDatabaseScanRuleset`/`SqlServerDatabaseSystemScanRuleset` TypeScript
  interfaces - all three independently agree on the literal string `"SqlServerDatabase"`, and
  notably the System *and* Custom ruleset variants share the identical `kind` discriminator. This is
  the SAME string as the base scenario's own already-shipped `-ScanRulesetName` default and as the
  data source `kind` itself - consistent with the Azure SQL Database/Managed Instance siblings'
  simpler name-equals-kind pattern, **not** the Azure Synapse Analytics sibling's naming trap
  (`AzureSynapseSQL` name vs. `AzureSynapseWorkspace` kind, two different strings).
- **VERIFY (still open, NOT resolved by this build): the System default scan rule set's literal
  resource `name` for this source type.** The base scenario's own the known limitations already flagged
  this as unconfirmed (`-ScanRulesetName` default `'SqlServerDatabase'` is inferred from the
  "system ruleset name == data source kind" pattern, not confirmed by a worked example). This build
  confirmed the ruleset **`kind`** (above) but found no worked example anywhere - despite searching
  specifically for one - pairing a literal `scanRulesetName: "SqlServerDatabase"` with
  `scanRulesetType: "System"` in a live scan object. The one worked scan-creation example this build
  found (`New-AzPurviewSqlServerDatabaseCredentialScanObject`) uses an arbitrary custom ruleset name,
  `'SqlServer'`, not the System default, so it doesn't close this gap either way. `deploy/
  Remove-PiiOnlyScanRuleset.ps1`'s `-RevertToRulesetName` default (`'SqlServerDatabase'`) is
  therefore still an inherited best-effort default, not an independently confirmed one - precisely
  the distinction the design notes goal 6 draws out. Confirm the real name (Purview portal →
  **Management Center → Scan rule sets → System** tab → filter by source type) before relying on the
  default in an unattended pipeline - a wrong name fails the scan loudly (400/404) rather than
  silently under-classifying, so the blast radius of shipping this unconfirmed default is bounded,
  but should still be closed.
- **Grounding method note (repo-wide relevance): this build's execution environment reached
  `learn.microsoft.com` directly** via the Microsoft Learn MCP tool, with no `EGRESS_BLOCKED`
  restriction encountered - unlike every recent fragment noted in the project backlog's own "Blocked /
  needs user" section. Future runs that also have this access should prefer it, and, time permitting,
  could re-verify the Azure Synapse Analytics and Azure SQL Managed Instance siblings' own
  GitHub-raw-source-only citations against the full `learn.microsoft.com` REST reference pages now
  that access appears to have been restored (not attempted in this build - out of scope for a
  fragment focused on a fourth, different source type).
- **The exclusion list is derived live, not hard-coded - same reasoning as every sibling.** The Data
  Map classification-supported-list page has no exact `MICROSOFT.*` identifier strings, only
  human-readable names, so the deploy script queries the tenant's live Types API instead of shipping
  a hand-typed snapshot (the design notes goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found - the same open item every sibling scenario
  carries. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in its
  `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map sibling
  scenario - no documented REST endpoint for *creating* a custom classification rule was found.
  `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior - it always detaches
  the scan first (see the design notes goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs - see operations and tuning.
- **Only ONE compatible scan kind exists for this source type.** Unlike the Azure siblings (each with
  a managed-identity and a credential-authenticated variant), on-premises SQL Server has only
  `SqlServerDatabaseCredential` - no managed-identity path exists at all (base scenario's own design notes). The deploy script's scan-kind compatibility guard reflects this - there is no
  second kind to accept.
- **Inherits the base scenario's own open items unchanged.** The Windows-Authentication
  `CredentialType` VERIFY (`'BasicAuth'` is a best-effort, unconfirmed mapping), the credential
  object's portal-only creation (no documented REST endpoint), and the printed-SHIR-auth-key
  handling discipline are all the base scenario's own concerns - this scenario's reconcile step is
  neutral toward whichever authentication configuration the base scenario's scan already uses, and
  does not resolve or restate any of them beyond what's needed here.
- **This is the last remaining Data Map PII-ruleset sibling.** No further "apply the same pattern to
  source type X" follow-up remains in the project backlog's Data Map PII-ruleset chain after this scenario.