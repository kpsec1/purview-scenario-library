---
title: "PII-Only Scan Rule Set for Azure SQL Managed Instance"
fullTitle: "Data Map — PII-Only Scan Rule Set for Azure SQL Managed Instance"
category: "Data Map"
categorySlug: "data-map"
slug: "scan-azure-sql-managed-instance-and-classify-pii-ruleset"
repoPath: "scenarios/data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset"
parts: ["design","deploy","validate","rollback"]
related: ["data-map/scan-azure-sql-managed-instance-and-classify","data-map/scan-azure-sql-and-classify-pii-ruleset","data-map/scan-azure-synapse-and-classify-pii-ruleset"]
deployCount: 2
validateCount: 1
---
## 1. Scenario summary

Extends [`data-map/scan-azure-sql-managed-instance-and-classify`](/scenarios/data-map/scan-azure-sql-managed-instance-and-classify/): creates a **custom,
PII-only** Data Map scan rule set for Azure SQL Managed Instance — every system classification
excluded except the ones you name to keep (U.S. Social Security Number and Credit Card Number by
default) — and reconciles the base scenario's already-registered scan onto it. The exclusion list
is derived at deploy time from the tenant's own live classification type definitions (never a
hard-coded snapshot), the same self-maintaining pattern already proven by the Azure SQL Database
and Azure Synapse Analytics sibling scenarios (`scan-azure-sql-and-classify-pii-ruleset`,
`scan-azure-synapse-and-classify-pii-ruleset`).

**Who it's for:** a data governance or security team that has already run the base Azure SQL
Managed Instance scanning scenario — commonly a lift-and-shift landing zone for on-premises SQL
Server estates — knows their compliance driver is narrow (PCI cardholder data, or a PII-only
privacy program), and wants a faster, quieter scan and a less cluttered catalog than the System
default scan rule set produces.

## 2. Business/regulatory driver

Same driver as both sibling scenarios: the base scenario's System default rule set (named
`AzureSqlDatabaseManagedInstance`, ~200 built-in classifications) is right for a first, exploratory
scan of a newly registered instance. It is the wrong steady-state configuration for a PCI DSS
Requirement 3.2/12.5.2 (cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA):
those care about a specific, narrow set of data categories, not currencies, cloud-provider
credentials, or national ID formats for dozens of countries never in scope for a given program. A
narrower rule set gives auditors a catalog whose classification tags map directly to the regulatory
driver being demonstrated, and a faster scan (fewer classification comparisons per column) — a more
visible effect on Managed Instance than on a small standalone database, since Managed Instance is
frequently a lift-and-shift target that inherited a large, long-lived on-premises schema
[[7]](#references).

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
`scan-azure-sql-managed-instance-and-classify` first with the System default to discover what's
actually in the instance, then apply this scenario once the program's classification scope is
known.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md` §1–2 (unchanged from the base
scenario — this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| **[`data-map/scan-azure-sql-managed-instance-and-classify`](/scenarios/data-map/scan-azure-sql-managed-instance-and-classify/) already deployed** | The target data source and scan must already exist, and already run successfully | This scenario reconciles an EXISTING scan onto a new ruleset — `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found. It assumes the base scenario's own extra prerequisites (public endpoint, Microsoft Entra admin, Directory Readers role, NSG rule, `db_datareader` grant) are already in place — see that scenario's `README.md` §3 |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires — Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself (`docs/rbac-model.md` §5) [[7]](#references) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario — `docs/automation-surface.md` §3 |

> Verify current entitlement names against `docs/licensing-matrix.md` (dated 2026-09-02) before a
> sales commitment.

## 4. Architecture

See `design.md` §3 for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSqlDatabaseManagedInstanceScanRuleset` object, then reconciles the base scenario's
existing scan onto it.

## 5. Step-by-step implementation

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **Azure SQL Database Managed Instance** as the source type, name the ruleset (e.g.
   `AzureSqlDatabaseManagedInstance-PiiOnly`), and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected — deselect every one except the classifications you want to retain (U.S. Social
   Security Number, Credit Card Number, or whatever your program's driver requires). There is no
   documented "select none, then add back" toggle; for ~200 entries the portal path is
   significantly more tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'mi-contoso-prod-customerdb'
```

## 6. Configuration reference

See `design.md` §4 for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy, and the
system-ruleset-name-equals-kind relationship confirmed specifically for this source type).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `AzureSqlDatabaseManagedInstance-PiiOnly` | Account-wide object name — reusable across every Azure SQL Managed Instance scan that wants this scope (design.md §2 goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded — same default pair as every sibling Data Map PII-ruleset scenario in this repo |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only — see §11) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset |
| `-ApiVersion` | `2023-09-01` | Pinned; matches the base scenario and both sibling PII-ruleset scenarios |

## 7. Validation / how to prove it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as
`AzureSqlDatabaseManagedInstance`/`Custom`; every classification in
`-ExpectedRetainedClassifications` is genuinely absent from the exclusion list (not accidentally
excluded); the exclusion list is large enough to be meaningfully narrower than System default (a
`[WARN]`, not a hard fail, since the exact count depends on the tenant's live classification count
at validation time); and the target scan's `scanRulesetName`/`scanRulesetType` point at this
ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal —
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** — that only
the retained classification types appear on newly classified columns.

## 8. Operations & tuning (KPIs, alert thresholds, what to watch)

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against
  the prior System-default run — a narrower classification set should measurably reduce
  per-column comparison time, a more visible effect on a large lift-and-shift instance than on a
  small standalone database. Track this as a rough sanity check that the ruleset actually took
  effect, not a performance metric.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes (e.g. a new regulatory scope adds a data category), `-RetainedSystemClassifications`
  must be updated and the script re-run — there is no automatic sync between a program's stated
  scope and this ruleset's contents. Review the retained list at the same cadence as the licensing
  matrix review.
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
  type) so a ruleset narrowing on the managed instance scan is reviewed with the same rigor as a
  DLP policy exception — see references 12–13.

## 9. Rollback / decommission

See `rollback.md` for the full staged sequence (revert the scan to System default; optionally
delete the custom ruleset object).

## 10. Cost & licensing notes

No new licensing surface — this scenario uses the same PAYG Data Map billing as the base scenario
(`docs/licensing-matrix.md` §1–2). A narrower scan rule set may modestly reduce scan **compute**
time (fewer classification comparisons per column), which is a cost factor under Purview's
consumption-based Data Map billing, though Microsoft does not publish a per-classification cost
breakdown to quantify the exact savings.

## 11. Known limitations & gotchas

- **This source type's custom ruleset `kind` is the SAME string as the System default ruleset's
  NAME (`AzureSqlDatabaseManagedInstance`) — confirmed independently, not inherited from either
  sibling by assumption.** The Azure SQL Database sibling has this same name-equals-kind property
  (`AzureSqlDatabase`); the Azure Synapse Analytics sibling does **not** (`AzureSynapseSQL` name vs.
  `AzureSynapseWorkspace` kind — a trap that sibling's own build specifically warned against
  assuming away for future source types). This build direct-fetched
  `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject`'s own documentation, which states
  the constructed object's `Kind` is `"AzureSqlDatabaseManagedInstance"` — the identical string to
  the base scenario's own `-ScanRulesetName` default. `deploy/Remove-PiiOnlyScanRuleset.ps1`'s
  `-RevertToRulesetName` default is therefore the same string used elsewhere in this scenario as
  the ruleset `kind` constant — correct for this source type, but confirmed rather than assumed
  (design.md §2 goal 6).
- **VERIFY (pilot tenant or a future Microsoft Learn pass): the exact REST JSON body for a Custom
  `AzureSqlDatabaseManagedInstanceScanRuleset`.** This build confirmed the object shape and the
  `Kind: AzureSqlDatabaseManagedInstance` value directly against the `Az.Purview` PowerShell
  module's own GitHub source (`New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md`,
  fetched verbatim via `raw.githubusercontent.com` after `learn.microsoft.com`'s REST API
  reference pages returned `EGRESS_BLOCKED` in this build environment — the same access restriction
  and workaround the Synapse sibling's own build documented). The PowerShell object's property
  names (`ExcludedSystemClassification`, `IncludedCustomClassificationRuleName`, `Description`,
  `Type`) are carried into this scenario's REST body as `excludedSystemClassifications`/
  `includedCustomClassificationRuleNames`/`description`/`scanRulesetType`, matching the exact
  casing convention the Azure SQL Database sibling's REST body already uses and that its own build
  confirmed directly against the REST reference page (not blocked during that earlier build). This
  build did not get an independent direct fetch of the REST reference page itself for the Managed
  Instance variant specifically — flagged here rather than assumed identical without qualification.
  Re-open once `learn.microsoft.com` is reachable from this build environment, or against a pilot
  tenant.
- **No `collection` property on the ruleset (account-wide, same as every sibling).** The
  `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject` constructor cmdlet exposes no
  collection or scan-scoping parameter (only `-Description`/`-ExcludedSystemClassification`/
  `-IncludedCustomClassificationRuleName`/`-Type`) — the same absence-of-a-collection-parameter
  evidence both sibling scenarios used to establish their own ruleset is account-wide, not scoped.
  One `AzureSqlDatabaseManagedInstance-PiiOnly` ruleset, created once, can be referenced by every
  Azure SQL Managed Instance scan in the account that wants this same narrower scope.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** Same
  finding as both sibling scenarios — classifications are listed by human-readable name and
  description only, no machine-parseable `MICROSOFT.*` identifier table. This is why the deploy
  script queries the tenant's live Types API instead of shipping a hand-typed snapshot (design.md
  §2 goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found — the same open item both sibling scenarios
  carry. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in its
  `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map
  sibling scenario — no documented REST endpoint for *creating* a custom classification rule was
  found. `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior — it always
  detaches the scan first (see `design.md` §2 goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs — see §8.
- **Inherits the base scenario's own open items.** The `AzureSqlDatabaseManagedInstanceCredential`
  scan kind (the alternative to the SAMI-authenticated default) still needs a Key Vault-backed
  credential object with no documented REST creation endpoint — the base scenario's `README.md`
  §11 tracks this; this scenario's reconcile step is neutral toward whichever authentication kind
  the base scenario's scan already uses, and does not resolve that gap.
- **Does not extend to the on-premises SQL Server sibling.** `scan-on-premises-sql-server-and-
  classify-pii-ruleset` (`kind: SqlServerDatabase`) remains a separate, not-yet-built fragment
  (`PROGRESS.md`) — do not assume its own name-vs-kind relationship without an independent check,
  per design.md §2 goal 6's explicit warning against pattern-matching across source types.

## 12. References

1. New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject (Az.Purview PowerShell module —
   confirms the Custom `AzureSqlDatabaseManagedInstanceScanRuleset` object shape and the
   `Kind: "AzureSqlDatabaseManagedInstance"` value, direct-fetched from GitHub raw source after
   `learn.microsoft.com` returned `EGRESS_BLOCKED` in this build environment) —
   <https://raw.githubusercontent.com/Azure/azure-powershell/main/src/Purview/Purview/help/New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md>
2. New-AzPurviewAzureSqlDatabaseManagedInstanceMsiScanObject (Az.Purview PowerShell module —
   confirms `Kind: AzureSqlDatabaseManagedInstanceMsi` and `ScanRulesetName:
   AzureSqlDatabaseManagedInstance` / `ScanRulesetType: System` as the shared System default via a
   worked example; reused from the base scenario's own citation) —
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasemanagedinstancemsiscanobject>
3. Scan Rulesets - Create Or Replace / - Get REST API reference (API version 2023-09-01; generic
   call shape confirmed by direct fetch during the Azure SQL Database sibling scenario's build, and
   reused unchanged here — only the request body's `kind` value differs per source type) —
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
4. Type - List REST API reference (Types API; confirmed `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape — tenant-wide, source-type-agnostic; reused unchanged
   from the Azure SQL Database sibling's own direct fetch) —
   <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
5. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace.") — <https://learn.microsoft.com/purview/data-map-classification-custom>
6. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary —
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) —
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
7. Connect to and manage an Azure SQL Managed Instance in Microsoft Purview (base scenario's
   registration/scan reference this scenario extends; confirms `AzureSqlDatabaseManagedInstance`
   as the System default scan rule set name) —
   <https://learn.microsoft.com/purview/register-scan-azure-sql-managed-instance>
8. Data Map classification supported list (confirmed to list classifications by human-readable
   name/description only, with no exact `MICROSOFT.*` identifier strings) —
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
9. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module — corroborates the scan rule set
   delete operation and its 204 response) — <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
10. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) — <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
11. [`data-map/scan-azure-sql-managed-instance-and-classify`](/scenarios/data-map/scan-azure-sql-managed-instance-and-classify/) (base scenario this fragment
    extends; confirms `AzureSqlDatabaseManagedInstanceMsi`/`AzureSqlDatabaseManagedInstanceCredential`
    as the two compatible scan kinds) — this repository.
12. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) —
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
13. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API — the SIEM-consumable record type for Data Map
    Management-category events, including scan rule set changes) —
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>
14. [`data-map/scan-azure-sql-and-classify-pii-ruleset`](/scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/) and
    [`data-map/scan-azure-synapse-and-classify-pii-ruleset`](/scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/) (sibling scenarios this
    fragment mirrors — pattern precedent for the live-Types-API exclusion-list design, the
    reconcile-not-reconstruct scan update, and the name-vs-kind independent-verification
    discipline) — this repository.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. Two VERIFYs remain open in §11 (the Managed Instance-specific REST
> body shape pending direct access to `learn.microsoft.com`, and Types API pagination behavior at
> scale) and should be closed against a pilot tenant or once the network restriction lifts, before
> production use.
