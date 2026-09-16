---
title: "PII-Only Scan Rule Set for Azure SQL Database"
fullTitle: "Data Map — PII-Only Scan Rule Set for Azure SQL Database"
category: "Data Map"
categorySlug: "data-map"
slug: "scan-azure-sql-and-classify-pii-ruleset"
repoPath: "scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset"
---
## 1. Scenario summary

Extends `scenarios/data-map/scan-azure-sql-and-classify/`: creates a **custom, PII-only** Data Map
scan rule set for Azure SQL Database — every system classification excluded except the ones you
name to keep (U.S. Social Security Number and Credit Card Number by default) — and reconciles the
base scenario's already-registered scan onto it. The exclusion list is derived at deploy time from
the tenant's own live classification type definitions (never a hard-coded snapshot), so a buyer
with a narrow compliance driver gets a catalog and a scan that only ever surface the handful of
classifications their program actually cares about, instead of Microsoft's full ~200-classification
system set.

**Who it's for:** a data governance or security team that has already run the base Azure SQL
Database scanning scenario, knows their compliance driver is narrow (PCI cardholder data, or a
PII-only privacy program), and wants a faster, quieter scan and a less cluttered catalog than the
System default scan rule set produces.

## 2. Business/regulatory driver

The base scenario's System default rule set is the right choice for a first, exploratory scan —
you don't yet know what's in the database. It is the wrong steady-state configuration for a PCI
DSS or PII-focused program: PCI DSS Requirement 3.2/12.5.2 (cardholder data discovery) and most
privacy statutes (GDPR Art. 30, CCPA/CPRA) care about a specific, narrow set of data categories,
not the ~200 classification types Purview ships out of the box (currencies, cloud-provider
credentials, national ID formats for dozens of countries never in scope for a given program). A
narrower rule set gives auditors and reviewers a catalog whose classification tags map directly to
the regulatory driver being demonstrated, rather than a long tail of irrelevant matches to filter
through, and a faster scan (fewer classification comparisons per column) [[7]](#references).

This scenario is deliberately a companion to, not a replacement for, the base scenario: run the
base scenario first with the System default to discover what's actually in the database, then
apply this scenario once the program's classification scope is known.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md` §1–2 (unchanged from the base
scenario — this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| **`scenarios/data-map/scan-azure-sql-and-classify/` already deployed** | The target data source and scan must already exist | This scenario reconciles an EXISTING scan onto a new ruleset — `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires — Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself (`docs/rbac-model.md` §5) [[7]](#references) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario — `docs/automation-surface.md` §3 |

> Verify current entitlement names against `docs/licensing-matrix.md` (dated 2026-09-02) before a
> sales commitment.

## 4. Architecture

See `design.md` §3 for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1`
reads the tenant's live classification type definitions, computes an exclusion list, creates a
`Custom` `AzureSqlDatabaseScanRuleset` object, then reconciles the base scenario's existing scan
onto it.

## 5. Step-by-step implementation

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **Azure SQL Database** as the source type, name the ruleset (e.g.
   `AzureSqlDatabase-PiiOnly`), and choose **Select classification rules**.
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
    -DataSourceName 'sql-contoso-prod-customerdb' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql-contoso-prod-customerdb'
```

## 6. Configuration reference

See `design.md` §4 for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `AzureSqlDatabase-PiiOnly` | Account-wide object name — reusable across every Azure SQL Database scan that wants this scope (design.md §2 goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only — see §11) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset |
| `-ApiVersion` | `2023-09-01` | Pinned; confirmed current for the Scan Rulesets and Types endpoints as of this build |

## 7. Validation / how to prove it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as `AzureSqlDatabase`/`Custom`;
every classification in `-ExpectedRetainedClassifications` is genuinely absent from the exclusion
list (not accidentally excluded); the exclusion list is large enough to be meaningfully narrower
than System default (a `[WARN]`, not a hard fail, since the exact count depends on the tenant's
live classification count at validation time); and the target scan's `scanRulesetName`/
`scanRulesetType` point at this ruleset.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal —
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified** — that only
the retained classification types appear on newly classified columns.

## 8. Operations & tuning (KPIs, alert thresholds, what to watch)

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against
  the prior System-default run — a narrower classification set should measurably reduce
  per-column comparison time on a nontrivial database. Track this as a rough sanity check that the
  ruleset actually took effect, not just as a performance metric.
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
  event catalog lists **Scan rule set: Create / Update / Delete** under the Management category
  (`docs/rbac-model.md` §14's "how scenarios should cite RBAC" pattern applies equally to audit
  citations); pull these events into the same SIEM/Sentinel pipeline that already ingests this
  repo's other Purview audit activity via `PurviewDataMapOperation` (Microsoft Graph security
  audit log record type) so a ruleset narrowing is reviewed with the same rigor as a DLP policy
  exception — see references 12–13.

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

- **VERIFY (custom scan rule set REST creation) — CLOSED this build.** The base scenario's
  `README.md` §11 carried this forward as an open VERIFY ("the exact REST JSON body for the 'Scan
  Rulesets - Create Or Update' operation was not independently confirmed"). This build
  direct-fetched the canonical **Scan Rulesets - Create Or Replace** and **- Get** REST reference
  pages in full — the `AzureSqlDatabaseScanRuleset`/`AzureSqlDatabaseScanRulesetProperties` body
  shape used by `deploy/New-PiiOnlyScanRuleset.ps1` is confirmed directly against Microsoft's own
  reference, not reconstructed from adjacent evidence. See reference 1 below.
- **The Data Map "list of supported system classifications" page has no exact identifiers.** This
  build fetched `data-map-classification-supported-list` in full expecting a machine-parseable
  table of `MICROSOFT.*` names; the page instead lists classifications by human-readable name and
  description only (grep for `MICROSOFT\.` against the fetched page returned zero matches). This
  is precisely why the deploy script queries the tenant's live Types API instead of shipping a
  hand-typed snapshot — see `design.md` §2 goal 1.
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and this build found no
  documentation addressing pagination behavior for a tenant with an unusually large number of
  custom classification rules layered on top of the ~200 system ones. `deploy/New-PiiOnlyScanRuleset.ps1`
  does not implement paging; flagged inline in its `.NOTES`.
- **Custom classification rule authoring stays out of scope.** No documented REST endpoint for
  *creating* a custom classification rule was found — Microsoft's own community guidance states
  custom classification rules must be created manually in the portal. `-IncludedCustomClassificationRuleNames`
  only references rules that already exist; it does not author them.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation this build
  found states whether deleting a scan rule set still referenced by a scan succeeds, is rejected,
  or orphans the reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior —
  it always detaches the scan first (see `design.md` §2 goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs — see §8.

## 12. References

1. Scan Rulesets - Create Or Replace REST API reference (API version 2023-09-01, confirmed
   `AzureSqlDatabaseScanRuleset`/`AzureSqlDatabaseScanRulesetProperties` body schema — direct
   fetch, this build) — <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
2. New-AzPurviewAzureSqlDatabaseScanRulesetObject (Az.Purview PowerShell module — confirms the
   `-ExcludedSystemClassification` exclusion model with a worked
   `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` example) — <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewazuresqldatabasescanrulesetobject>
3. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace. An example is `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`.") —
   <https://learn.microsoft.com/purview/data-map-classification-custom>
4. Type - List REST API reference (Types API; confirmed `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape, worked example `MICROSOFT.GOVERNMENT.CHILE.CDI_NUMBER` —
   direct fetch, this build) — <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
5. Scan Rulesets - Get REST API reference (API version 2023-09-01, direct fetch, this build) —
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
6. Data classification in Data Map ("System classifications: 200+ system classifications... formal
   names... prefixed by *MICROSOFT*.") — <https://learn.microsoft.com/purview/data-map-classification>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary —
   Data Source Administrator, Data Curator, Data Reader, Collection Admin) —
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Data Map classification supported list (fetched in full during this build; confirmed to list
   classifications by human-readable name/description only, with no exact `MICROSOFT.*`
   identifier strings — the finding behind §11's second limitation) —
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
9. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module — corroborates the scan rule set
   delete operation and its 204 response) — <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
10. Discover and govern Azure SQL Database (base scenario's scan/source registration this
    scenario extends) — <https://learn.microsoft.com/purview/register-scan-azure-sql-database>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference) — <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event) —
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
13. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API — the SIEM-consumable record type for Data Map
    Management-category events, including scan rule set changes) —
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. One VERIFY remains open in §11 (Types API pagination behavior at
> scale) and should be closed against a pilot tenant first.
