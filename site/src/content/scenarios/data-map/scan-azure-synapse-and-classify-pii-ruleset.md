---
title: "PII-Only Scan Rule Set for Azure Synapse Analytics"
fullTitle: "Data Map — PII-Only Scan Rule Set for Azure Synapse Analytics"
category: "Data Map"
categorySlug: "data-map"
slug: "scan-azure-synapse-and-classify-pii-ruleset"
repoPath: "scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset"
parts: ["design","deploy","validate","rollback"]
deployCount: 2
validateCount: 1
---
## 1. Scenario summary

Extends `scenarios/data-map/scan-azure-synapse-and-classify/`: creates a **custom, PII-only** Data
Map scan rule set for Azure Synapse Analytics (dedicated and/or serverless SQL pools) — every
system classification excluded except the ones you name to keep (U.S. Social Security Number and
Credit Card Number by default) — and reconciles the base scenario's already-registered scan onto
it. The exclusion list is derived at deploy time from the tenant's own live classification type
definitions (never a hard-coded snapshot), the same self-maintaining pattern already proven by the
Azure SQL Database sibling scenario (`scan-azure-sql-and-classify-pii-ruleset`).

**Who it's for:** a data governance or security team that has already run the base Azure Synapse
Analytics scanning scenario, knows their compliance driver is narrow (PCI cardholder data, or a
PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the
System default scan rule set produces across a Synapse workspace's dedicated and serverless pools.

## 2. Business/regulatory driver

Same driver as the Azure SQL Database sibling: the base scenario's System default rule set (named
`AzureSynapseSQL`, ~200 built-in classifications) is right for a first, exploratory scan of a new
workspace. It is the wrong steady-state configuration for a PCI DSS Requirement 3.2/12.5.2
(cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA): those care about a
specific, narrow set of data categories, not currencies, cloud-provider credentials, or national ID
formats for dozens of countries never in scope for a given program. A narrower rule set gives
auditors a catalog whose classification tags map directly to the regulatory driver being
demonstrated, and a faster scan (fewer classification comparisons per column) across a Synapse
workspace's SQL pools — a workload that can already run for hours on a nontrivial dedicated pool per
the base scenario's own operational notes [[7]](#references).

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
`scan-azure-synapse-and-classify` first with the System default to discover what's actually in the
workspace, then apply this scenario once the program's classification scope is known.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md` §1–2 (unchanged from the base
scenario — this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| **`scenarios/data-map/scan-azure-synapse-and-classify/` already deployed** | The target data source and scan must already exist | This scenario reconciles an EXISTING scan onto a new ruleset — `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires — Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself (`docs/rbac-model.md` §5) [[7]](#references) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario — `docs/automation-surface.md` §3 |

> Verify current entitlement names against `docs/licensing-matrix.md` (dated 2026-09-02) before a
> sales commitment.

## 4. Architecture

See `design.md` §3 for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSynapseWorkspaceScanRuleset` object (`kind: AzureSynapseWorkspace`), then reconciles
the base scenario's existing scan onto it — covering whichever of the dedicated/serverless pools
that scan already targets.

## 5. Step-by-step implementation

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **Azure Synapse Analytics** as the source type, name the ruleset (e.g.
   `AzureSynapseWorkspace-PiiOnly`), and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected — deselect every one except the classifications you want to retain (U.S. Social
   Security Number, Credit Card Number, or whatever your program's driver requires). There is no
   documented "select none, then add back" toggle; for ~200 entries the portal path is
   significantly more tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default (`AzureSynapseSQL`)** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'ws-contoso-prod'
```

## 6. Configuration reference

See `design.md` §4 for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy, and the
system-ruleset-name-vs-kind naming nuance specific to this source type).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `AzureSynapseWorkspace-PiiOnly` | Account-wide object name — reusable across every Azure Synapse Analytics scan that wants this scope (design.md §2 goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded — same default pair as every sibling Data Map PII-ruleset scenario in this repo |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only — see §11) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset |
| `-ApiVersion` | `2023-09-01` | Pinned; matches the base scenario and the Azure SQL Database sibling |

## 7. Validation / how to prove it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as
`AzureSynapseWorkspace`/`Custom`; every classification in `-ExpectedRetainedClassifications` is
genuinely absent from the exclusion list (not accidentally excluded); the exclusion list is large
enough to be meaningfully narrower than System default (a `[WARN]`, not a hard fail, since the exact
count depends on the tenant's live classification count at validation time); and the target scan's
`scanRulesetName`/`scanRulesetType` point at this ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal —
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** — that only
the retained classification types appear on newly classified columns, across both the dedicated and
serverless pools if the base scenario's scan covers both.

## 8. Operations & tuning (KPIs, alert thresholds, what to watch)

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against
  the prior System-default run — a narrower classification set should measurably reduce
  per-column comparison time, a more visible effect on a nontrivial dedicated pool than on a small
  database given how long the base scenario's own README already documents Synapse scans can run.
  Track this as a rough sanity check that the ruleset actually took effect, not a performance
  metric.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes, `-RetainedSystemClassifications` must be updated and the script re-run — there is no
  automatic sync between a program's stated scope and this ruleset's contents. Review the retained
  list at the same cadence as the licensing matrix review.
- **New system classifications Microsoft adds.** Because the exclusion list is derived live at
  deploy time (design.md §1), a classification Microsoft adds after this ruleset was last applied
  is automatically excluded on the *next* run of `New-PiiOnlyScanRuleset.ps1` — but not
  retroactively on the existing ruleset object until that script is re-run. Re-run it periodically
  (e.g. quarterly) rather than treating "deployed once" as "current forever."
- **Every scan rule set change is audit-logged, so treat the change itself as security-relevant.**
  Narrowing a scan's classification scope is a monitoring-coverage decision, not just a
  performance tweak — a scan under this ruleset will never surface a credential, key, or
  out-of-program data category that the System default would have caught. Microsoft's own audit
  event catalog lists **Scan rule set: Create / Update / Delete** under the Management category;
  pull these events into the same SIEM/Sentinel pipeline that already ingests this repo's other
  Purview audit activity via `PurviewDataMapOperation` (Microsoft Graph security audit log record
  type) so a ruleset narrowing on the Synapse workspace scan is reviewed with the same rigor as a
  DLP policy exception — see references 12–13.

## 9. Rollback / decommission

See `rollback.md` for the full staged sequence (revert the scan to the `AzureSynapseSQL` System
ruleset; optionally delete the custom ruleset object).

## 10. Cost & licensing notes

No new licensing surface — this scenario uses the same PAYG Data Map billing as the base scenario
(`docs/licensing-matrix.md` §1–2). A narrower scan rule set may modestly reduce scan **compute**
time (fewer classification comparisons per column) across the workspace's SQL pools, which is a
cost factor under Purview's consumption-based Data Map billing, though Microsoft does not publish a
per-classification cost breakdown to quantify the exact savings.

## 11. Known limitations & gotchas

- **The system ruleset NAME (`AzureSynapseSQL`) is not the same string as the custom ruleset KIND
  (`AzureSynapseWorkspace`) — a naming trap this source type has and the Azure SQL Database sibling
  does not.** For Azure SQL Database, the System default ruleset name and the custom ruleset `kind`
  are the identical string (`AzureSqlDatabase`), so reverting a scan and picking the custom-ruleset
  `kind` value are the same lookup. For Azure Synapse Analytics they are **not**: the System default
  ruleset the base scenario's scan starts on is named `AzureSynapseSQL`
  (`scan-azure-synapse-and-classify/deploy/New-AzureSynapseDataMapScan.ps1`'s own
  `-ScanRulesetName` default), while a *custom* ruleset for this source type must be created with
  `kind: AzureSynapseWorkspace` (confirmed directly against the
  `New-AzPurviewAzureSynapseWorkspaceScanRulesetObject` Az.Purview module source below — its worked
  example's output shows `Kind : AzureSynapseWorkspace`). `deploy/Remove-PiiOnlyScanRuleset.ps1`'s
  `-RevertToRulesetName` default is hard-coded to `'AzureSynapseSQL'` precisely because of this
  split; do not "simplify" it to match the ruleset `kind` string, which would point the revert at a
  ruleset object that does not exist.
- **VERIFY (pilot tenant or a future Microsoft Learn pass): the exact REST JSON body for a Custom
  `AzureSynapseWorkspaceScanRuleset`.** This build confirmed the object shape and the `Kind:
  AzureSynapseWorkspace` value directly against the `Az.Purview` PowerShell module's own GitHub
  source (`New-AzPurviewAzureSynapseWorkspaceScanRulesetObject.md`, fetched verbatim via
  `raw.githubusercontent.com` after `learn.microsoft.com`'s REST API reference pages returned
  `EGRESS_BLOCKED` in this build environment — the same access restriction and same workaround the
  base Synapse scenario's own build documented). The PowerShell object's property names
  (`ExcludedSystemClassification`, `IncludedCustomClassificationRuleName`, `Description`, `Type`)
  are carried into this scenario's REST body as `excludedSystemClassifications`/
  `includedCustomClassificationRuleNames`/`description`/`scanRulesetType`, matching the exact
  casing convention the Azure SQL Database sibling's REST body already uses and that its own build
  confirmed directly against the REST reference page (not blocked during that earlier build). This
  build did not get an independent direct fetch of the REST reference page itself for the Synapse
  variant specifically — flagged here rather than assumed identical without qualification. Re-open
  once `learn.microsoft.com` is reachable from this build environment, or against a pilot tenant.
- **No `collection` property on the ruleset (account-wide, same as every sibling).** The
  `New-AzPurviewAzureSynapseWorkspaceScanRulesetObject` constructor cmdlet exposes no collection or
  scan-scoping parameter (only `-Description`/`-ExcludedSystemClassification`/
  `-IncludedCustomClassificationRuleName`/`-Type`) — the same absence-of-a-collection-parameter
  evidence the Azure SQL Database sibling used to establish its own ruleset is account-wide, not
  scoped. One `AzureSynapseWorkspace-PiiOnly` ruleset, created once, can be referenced by every
  Azure Synapse Analytics scan in the account that wants this same narrower scope.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** Same
  finding as the Azure SQL Database sibling — classifications are listed by human-readable name and
  description only, no machine-parseable `MICROSOFT.*` identifier table. This is why the deploy
  script queries the tenant's live Types API instead of shipping a hand-typed snapshot (design.md
  §2 goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found — the same open item the Azure SQL Database
  sibling carries. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in
  its `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map
  sibling scenario — no documented REST endpoint for *creating* a custom classification rule was
  found. `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior — it always
  detaches the scan first (see `design.md` §2 goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs — see §8.
- **Inherits the base scenario's own open item on the `resourceTypes` scan property.** The base
  scenario's `deploy/New-AzureSynapseDataMapScan.ps1` deliberately omits the scan object's optional
  `resourceTypes` field (no confirmed JSON shape found during that build). This scenario's own
  reconcile step (`design.md` §2 goal 2: `GET` the scan, copy every property forward, overwrite only
  the two ruleset fields) preserves whatever `resourceTypes` state the scan already has — it neither
  adds nor removes that property, so it introduces no new risk on this specific point.

## 12. References

1. New-AzPurviewAzureSynapseWorkspaceScanRulesetObject (Az.Purview PowerShell module — confirms the
   Custom `AzureSynapseWorkspaceScanRuleset` object shape and the `Kind: AzureSynapseWorkspace`
   value via a worked example, direct-fetched from GitHub raw source after `learn.microsoft.com`
   returned `EGRESS_BLOCKED` in this build environment) —
   <https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSynapseWorkspaceScanRulesetObject.md>
2. New-AzPurviewAzureSynapseWorkspaceCredentialScanObject (Az.Purview PowerShell module — confirms
   `Kind: AzureSynapseWorkspaceCredential` for the credential-authenticated scan variant, and
   confirms `ScanRulesetName: AzureSynapseSQL`/`ScanRulesetType: System` as the shared System
   default for both Msi- and Credential-authenticated Synapse scans, via a worked example) —
   <https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSynapseWorkspaceCredentialScanObject.md>
3. New-AzPurviewAzureSynapseWorkspaceMsiScanObject (Az.Purview PowerShell module — confirms `Kind:
   AzureSynapseWorkspaceMsi`, reused unchanged from the base scenario's own citation) —
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresynapseworkspacemsiscanobject>
4. Scan Rulesets - Create Or Replace / - Get REST API reference (API version 2023-09-01; generic
   call shape confirmed by direct fetch during the Azure SQL Database sibling scenario's build, and
   reused unchanged here — only the request body's `kind` value differs per source type) —
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
5. Type - List REST API reference (Types API; confirmed `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape — tenant-wide, source-type-agnostic; reused unchanged
   from the Azure SQL Database sibling's own direct fetch) —
   <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
6. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace.") — <https://learn.microsoft.com/purview/data-map-classification-custom>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary —
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) —
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Data Map classification supported list (confirmed to list classifications by human-readable
   name/description only, with no exact `MICROSOFT.*` identifier strings) —
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
9. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module — corroborates the scan rule set
   delete operation and its 204 response) — <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
10. Connect to and manage Azure Synapse Analytics workspaces in Microsoft Purview (base scenario's
    registration/scan reference this scenario extends; confirms `AzureSynapseSQL` as the System
    default scan rule set name) — <https://learn.microsoft.com/purview/register-scan-synapse-workspace>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) — <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) —
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
13. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API) —
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>
14. `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/` (sibling scenario this fragment
    mirrors — pattern precedent for the live-Types-API exclusion-list design and the reconcile-not-
    reconstruct scan update) — this repository.
15. `scenarios/data-map/scan-azure-synapse-and-classify/` (base scenario this fragment extends) —
    this repository.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. Two VERIFYs remain open in §11 (the Synapse-specific REST body shape
> pending direct access to `learn.microsoft.com`, and Types API pagination behavior at scale) and
> should be closed against a pilot tenant or once the network restriction lifts, before production
> use.
