---
title: "PII-Only Scan Rule Set for On-Premises SQL Server"
category: "Data Map"
categorySlug: "data-map"
slug: "scan-on-premises-sql-server-and-classify-pii-ruleset"
whoFor: "a data governance or security team that has already run the base on-premises SQL"
frameworks: ["GDPR","PCI DSS","CCPA"]
licensing: ["Pay-as-you-go"]
deployCount: 2
validateCount: 1
hasDesign: true
hasRollback: true
toc: [{"id":"1-scenario-summary","text":"1. Scenario summary"},{"id":"2-businessregulatory-driver","text":"2. Business/regulatory driver"},{"id":"3-prerequisites","text":"3. Prerequisites"},{"id":"4-architecture","text":"4. Architecture"},{"id":"5-step-by-step-implementation","text":"5. Step-by-step implementation"},{"id":"6-configuration-reference","text":"6. Configuration reference"},{"id":"7-validation--how-to-prove-it-works","text":"7. Validation / how to prove it works"},{"id":"8-operations--tuning-kpis-alert-thresholds-what-to-watch","text":"8. Operations & tuning (KPIs, alert thresholds, what to watch)"},{"id":"9-rollback--decommission","text":"9. Rollback / decommission"},{"id":"10-cost--licensing-notes","text":"10. Cost & licensing notes"},{"id":"11-known-limitations--gotchas","text":"11. Known limitations & gotchas"},{"id":"12-references","text":"12. References"}]
---
## 1. Scenario summary

Extends `scenarios/data-map/scan-on-premises-sql-server-and-classify/`: creates a **custom,
PII-only** Data Map scan rule set for on-premises SQL Server, every system classification excluded
except the ones you name to keep (U.S. Social Security Number and Credit Card Number by default), 
and reconciles the base scenario's already-registered, self-hosted-integration-runtime-backed scan
onto it. The exclusion list is derived at deploy time from the tenant's own live classification type
definitions (never a hard-coded snapshot), the same self-maintaining pattern already proven by the
three Azure Data Map PII-ruleset sibling scenarios in this repo
(`scan-azure-sql-and-classify-pii-ruleset`, `scan-azure-synapse-and-classify-pii-ruleset`,
`scan-azure-sql-managed-instance-and-classify-pii-ruleset`). This is the fourth and last of this
repo's Data Map source types to receive this treatment, no further siblings remain in
`PROGRESS.md`'s follow-up chain.

**Who it's for:** a data governance or security team that has already run the base on-premises SQL
Server scanning scenario, commonly the organization's oldest, least-documented regulated-data
estate, predating any cloud migration program, knows their compliance driver is narrow (PCI
cardholder data, or a PII-only privacy program), and wants a faster, quieter scan and a less
cluttered catalog than the System default scan rule set produces.

## 2. Business/regulatory driver

Same driver as every sibling scenario: the base scenario's System default rule set (inferred name
`SqlServerDatabase`, ~200 built-in classifications) is right for a first, exploratory scan of a
newly registered instance. It is the wrong steady-state configuration for a PCI DSS Requirement
3.2/12.5.2 (cardholder data discovery) or PII-focused program (GDPR Art. 30, CCPA/CPRA): those care
about a specific, narrow set of data categories, not currencies, cloud-provider credentials, or
national ID formats for dozens of countries never in scope for a given program. A narrower rule set
gives auditors a catalog whose classification tags map directly to the regulatory driver being
demonstrated, and a faster scan (fewer classification comparisons per column).

The stakes of this scope choice are unusually high for this specific source type: the base
scenario's own `design.md` §1 states plainly that on-premises SQL Server "is disproportionately
likely to be where an organization's oldest, least-documented regulated data lives, instances that
predate a cloud migration program, were never in scope for it, or are deliberately kept on-premises
for latency, licensing, or regulatory reasons." Narrowing classification scope on exactly this kind
of legacy, schema-drifted instance is a real monitoring-coverage trade-off, not just a performance
tweak, see §11 and `reviews.md`.

This scenario is deliberately a companion to, not a replacement for, the base scenario: run
`scan-on-premises-sql-server-and-classify` first with the System default to discover what's actually
in the instance, then apply this scenario once the program's classification scope is known.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md` §1-2 (unchanged from the base
scenario, this scenario adds no new licensing surface, only a different scan rule set object).

| Requirement | Minimum | Notes |
|---|---|---|
| **`scenarios/data-map/scan-on-premises-sql-server-and-classify/` already deployed and running successfully** | The self-hosted integration runtime node must be registered and **Running**, the data source and scan must already exist, and the Purview credential object must already exist | This scenario reconciles an EXISTING scan onto a new ruleset, `deploy/New-PiiOnlyScanRuleset.ps1` fails fast with a clear error if the scan is not found. It assumes the base scenario's own unusually long prerequisite list (SHIR resource + software install + node registration, SQL/Windows login + `db_datareader` grant, Key Vault secret, Purview credential object) is already satisfied, see that scenario's `README.md` §3. This scenario never grants, verifies, or troubleshoots any of it |
| Create/update the custom scan rule set and reconcile the scan | **Data Source Administrator** role on the target collection | Same role the base scenario's deploy script requires, Microsoft Learn does not document a role specific to scan rule sets; ruleset management falls under the same "configure and run a scan" boundary as the scan itself (`docs/rbac-model.md` §5) |
| Read the ruleset/scan for validation | **Data Reader** role on the target collection | Least-privilege for the read-only `validate/` script |
| Automation identity for the REST calls | App registration with the roles above, app-only OAuth2 | Same client-credentials flow as the base scenario, `docs/automation-surface.md` §3 |

> Verify current entitlement names against `docs/licensing-matrix.md` (dated 2026-09-02) before a
> sales commitment.

## 4. Architecture

See `design.md` §3 for the full Mermaid diagram. Summary: `deploy/New-PiiOnlyScanRuleset.ps1` reads
the tenant's live classification type definitions, computes an exclusion list, creates a `Custom`
`SqlServerDatabaseScanRuleset` object, then reconciles the base scenario's existing
SHIR/credential-backed scan onto it, preserving the `connectedVia` integration-runtime reference and
stored-credential reference untouched.

## 5. Step-by-step implementation

### Portal path

1. **Data Map → Management → Scan rule sets → New**.
2. Select **SQL Server** as the source type, name the ruleset (e.g. `SqlServerDatabase-PiiOnly`),
   and choose **Select classification rules**.
3. On the classification-rule picker, Microsoft's default view shows *all* system classifications
   selected, deselect every one except the classifications you want to retain (U.S. Social Security
   Number, Credit Card Number, or whatever your program's driver requires). There is no documented
   "select none, then add back" toggle; for ~200 entries the portal path is significantly more
   tedious than the script below, which is precisely why this scenario exists.
4. Save the ruleset, then open the target scan's configuration and change its scan rule set from
   **System default** to the new custom ruleset.

### Script path (recommended for anything beyond a one-off)

```powershell
# Dry run first - always.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' `
    -WhatIf

# Apply, with an immediate re-scan under the new ruleset.
./deploy/New-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local' `
    -RunNow
```

Validate:

```powershell
./validate/Test-PiiOnlyScanRuleset.ps1 `
    -PurviewAccountName 'contoso-purview' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -DataSourceName 'sql01-contoso-local'
```

`-DataSourceName` must match the data source name the base scenario registered, defaults to a
sanitized form of the SQL Server instance's `-ServerEndpoint` in that scenario (e.g.
`sql01-contoso-local` for `sql01.contoso.local`); pass the exact value you used there.

## 6. Configuration reference

See `design.md` §4 for the full table (ruleset `kind`/`scanRulesetType`, default retained
classifications, exclusion-list source, ruleset scope, reconciliation strategy, and exactly what is
confirmed vs. still `VERIFY` about the name-vs-kind relationship for this source type).

| Parameter | Default | Notes |
|---|---|---|
| `-ScanRulesetName` | `SqlServerDatabase-PiiOnly` | Account-wide object name, reusable across every on-premises SQL Server scan that wants this scope (design.md §2 goal 3) |
| `-RetainedSystemClassifications` | `MICROSOFT.GOVERNMENT.US.SOCIAL_SECURITY_NUMBER`, `MICROSOFT.FINANCIAL.CREDIT_CARD_NUMBER` | Everything else in the tenant's `MICROSOFT.*` namespace is excluded, same default pair as every sibling Data Map PII-ruleset scenario in this repo |
| `-IncludedCustomClassificationRuleNames` | none | Names of pre-existing custom classification rules (portal-authored only, see §11) |
| `-RunNow` | off | Starts an immediate Full scan under the new ruleset, fails immediately if the SHIR node isn't registered/running |
| `-ApiVersion` | `2023-09-01` | Pinned; matches the base scenario and every sibling PII-ruleset scenario |

## 7. Validation / how to prove it works

`validate/Test-PiiOnlyScanRuleset.ps1` confirms: the ruleset exists as `SqlServerDatabase`/`Custom`;
every classification in `-ExpectedRetainedClassifications` is genuinely absent from the exclusion
list (not accidentally excluded); the exclusion list is large enough to be meaningfully narrower than
System default (a `[WARN]`, not a hard fail, since the exact count depends on the tenant's live
classification count at validation time); the target scan's `scanRulesetName`/`scanRulesetType`
point at this ruleset; and the scan's `kind` is `SqlServerDatabaseCredential` with a `connectedVia`
reference still present (i.e. this scenario didn't accidentally strip the SHIR wiring during the
reconcile step).

This script **cannot** confirm self-hosted integration runtime node health, the Integration Runtimes
- Get REST operation returns the resource definition, not live node status. Check **Data Map →
Integration runtimes → the runtime → Nodes** tab separately (same limitation the base scenario's own
`README.md` §7 check 2 discloses); a scan can pass every check here and still fail at run time if no
node has registered.

After a `-RunNow` (or the base scenario's recurring trigger fires again), confirm in the portal, 
**Data Map → Data sources → \<source\> → Recent scans → \<run\> → Assets classified**, that only the
retained classification types appear on newly classified columns.

## 8. Operations & tuning (KPIs, alert thresholds, what to watch)

- **Scan duration delta.** Compare the run duration of the first post-ruleset-change scan against the
  prior System-default run, a narrower classification set should measurably reduce per-column
  comparison time.
- **Drift between the retained list and the program's actual driver.** If the compliance driver
  changes (e.g. a new regulatory scope adds a data category), `-RetainedSystemClassifications` must be
  updated and the script re-run, there is no automatic sync between a program's stated scope and
  this ruleset's contents. Review the retained list at the same cadence as the licensing matrix
  review.
- **New system classifications Microsoft adds.** Because the exclusion list is derived live at deploy
  time (design.md §1), a classification Microsoft adds after this ruleset was last applied is
  automatically excluded on the *next* run of `New-PiiOnlyScanRuleset.ps1`, but not retroactively on
  the existing ruleset object until that script is re-run. Re-run it periodically (e.g. quarterly)
  rather than treating "deployed once" as "current forever."
- **Every scan rule set change is audit-logged, so treat the change itself as security-relevant.**
  Narrowing a scan's classification scope is a monitoring-coverage decision, not just a performance
  tweak, a scan under this ruleset will never surface a credential, key, or out-of-program data
  category that the System default would have caught. This is a genuinely elevated concern for this
  specific source type (§2): on-premises SQL Server instances are the estate most likely to hold an
  undocumented sensitive column the System default's ~200-classification sweep would have caught.
  Pull **Scan rule set: Create / Update / Delete** Management-category audit events (via the
  `PurviewDataMapOperation` Microsoft Graph security audit log record type) into the same
  SIEM/Sentinel pipeline that already ingests this repo's other Purview audit activity, and correlate
  a ruleset-narrowing event with the SHIR node's own health signal, a narrower ruleset on a scan that
  is *also* silently failing at the SHIR layer compounds two independent coverage gaps into one blind
  spot that neither Purview's own UI nor a naive "scan succeeded" check would surface on its own.
- **SHIR-specific operational risks are unchanged by this scenario**, see the base scenario's
  `README.md` §8 for the full on-premises incident-response list (SHIR node down, credential password
  rotated without the Purview credential object being updated, network/firewall change, SHIR software
  expiration). This scenario does not add or remove any of those risks; it only changes what a
  *successful* scan run classifies.

## 9. Rollback / decommission

See `rollback.md` for the full staged sequence (revert the scan to System default; optionally delete
the custom ruleset object).

## 10. Cost & licensing notes

No new licensing surface, this scenario uses the same PAYG Data Map billing as the base scenario
(`docs/licensing-matrix.md` §1-2), plus the base scenario's own SHIR host cost (a dedicated VM or
on-premises server, not a Data Map billing meter). A narrower scan rule set may modestly reduce scan
**compute** time (fewer classification comparisons per column), which is a cost factor under
Purview's consumption-based Data Map billing, though Microsoft does not publish a per-classification
cost breakdown to quantify the exact savings.

## 11. Known limitations & gotchas

- **This source type's custom ruleset `kind` is confirmed `SqlServerDatabase`, independently
  grounded via THREE converging Microsoft sources in this build, not inherited from any sibling by
  assumption.** Unlike the Azure Synapse Analytics and Azure SQL Managed Instance sibling builds
  (both of which hit `EGRESS_BLOCKED` against `learn.microsoft.com`), this build reached
  `learn.microsoft.com` directly and confirmed the `kind` value against: (1) the
  `New-AzPurviewSqlServerDatabaseScanRulesetObject` PowerShell reference's own worked example
  (`Kind: SqlServerDatabase`); (2) the Scan Rulesets - Get REST API reference's
  `SqlServerDatabaseScanRuleset` object definition; and (3) the `@azure-rest/purview-scanning`
  JavaScript SDK's `SqlServerDatabaseScanRuleset`/`SqlServerDatabaseSystemScanRuleset` TypeScript
  interfaces, all three independently agree on the literal string `"SqlServerDatabase"`, and
  notably the System *and* Custom ruleset variants share the identical `kind` discriminator. This is
  the SAME string as the base scenario's own already-shipped `-ScanRulesetName` default and as the
  data source `kind` itself, consistent with the Azure SQL Database/Managed Instance siblings'
  simpler name-equals-kind pattern, **not** the Azure Synapse Analytics sibling's naming trap
  (`AzureSynapseSQL` name vs. `AzureSynapseWorkspace` kind, two different strings).
- **VERIFY (still open, NOT resolved by this build): the System default scan rule set's literal
  resource `name` for this source type.** The base scenario's own `README.md` §11 already flagged
  this as unconfirmed (`-ScanRulesetName` default `'SqlServerDatabase'` is inferred from the
  "system ruleset name == data source kind" pattern, not confirmed by a worked example). This build
  confirmed the ruleset **`kind`** (above) but found no worked example anywhere, despite searching
  specifically for one, pairing a literal `scanRulesetName: "SqlServerDatabase"` with
  `scanRulesetType: "System"` in a live scan object. The one worked scan-creation example this build
  found (`New-AzPurviewSqlServerDatabaseCredentialScanObject`) uses an arbitrary custom ruleset name,
  `'SqlServer'`, not the System default, so it doesn't close this gap either way. `deploy/
  Remove-PiiOnlyScanRuleset.ps1`'s `-RevertToRulesetName` default (`'SqlServerDatabase'`) is
  therefore still an inherited best-effort default, not an independently confirmed one, precisely
  the distinction `design.md` §2 goal 6 draws out. Confirm the real name (Purview portal →
  **Management Center → Scan rule sets → System** tab → filter by source type) before relying on the
  default in an unattended pipeline, a wrong name fails the scan loudly (400/404) rather than
  silently under-classifying, so the blast radius of shipping this unconfirmed default is bounded,
  but should still be closed.
- **Grounding method note (repo-wide relevance): this build's execution environment reached
  `learn.microsoft.com` directly** via the Microsoft Learn MCP tool, with no `EGRESS_BLOCKED`
  restriction encountered, unlike every recent fragment noted in `PROGRESS.md`'s own "Blocked /
  needs user" section. Future runs that also have this access should prefer it, and, time permitting,
  could re-verify the Azure Synapse Analytics and Azure SQL Managed Instance siblings' own
  GitHub-raw-source-only citations against the full `learn.microsoft.com` REST reference pages now
  that access appears to have been restored (not attempted in this build, out of scope for a
  fragment focused on a fourth, different source type).
- **The exclusion list is derived live, not hard-coded, same reasoning as every sibling.** The Data
  Map classification-supported-list page has no exact `MICROSOFT.*` identifier strings, only
  human-readable names, so the deploy script queries the tenant's live Types API instead of shipping
  a hand-typed snapshot (design.md §2 goal 1).
- **VERIFY (pilot tenant): Types API pagination.** `GET .../types/typedefs?type=CLASSIFICATION`'s
  documented response shape has no continuation-token field, and no documentation addressing
  pagination behavior for a tenant with an unusually large number of custom classification rules
  layered on top of the ~200 system ones was found, the same open item every sibling scenario
  carries. `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging; flagged inline in its
  `.NOTES`.
- **Custom classification rule authoring stays out of scope.** Same finding as every Data Map sibling
  scenario, no documented REST endpoint for *creating* a custom classification rule was found.
  `-IncludedCustomClassificationRuleNames` only references rules that already exist.
- **Deleting an in-use ruleset is unconfirmed either way.** No Microsoft documentation confirms
  whether deleting a scan rule set still referenced by a scan succeeds, is rejected, or orphans the
  reference. `deploy/Remove-PiiOnlyScanRuleset.ps1` never assumes either behavior, it always detaches
  the scan first (see `design.md` §2 goal 5).
- **Reclassification is not retroactive.** Narrowing the ruleset does not retroactively change
  classification tags already recorded from prior scan runs, see §8.
- **Only ONE compatible scan kind exists for this source type.** Unlike the Azure siblings (each with
  a managed-identity and a credential-authenticated variant), on-premises SQL Server has only
  `SqlServerDatabaseCredential`, no managed-identity path exists at all (base scenario's own
  `design.md` §4). The deploy script's scan-kind compatibility guard reflects this, there is no
  second kind to accept.
- **Inherits the base scenario's own open items unchanged.** The Windows-Authentication
  `CredentialType` VERIFY (`'BasicAuth'` is a best-effort, unconfirmed mapping), the credential
  object's portal-only creation (no documented REST endpoint), and the printed-SHIR-auth-key
  handling discipline are all the base scenario's own concerns, this scenario's reconcile step is
  neutral toward whichever authentication configuration the base scenario's scan already uses, and
  does not resolve or restate any of them beyond what's needed here.
- **This is the last remaining Data Map PII-ruleset sibling.** No further "apply the same pattern to
  source type X" follow-up remains in `PROGRESS.md`'s Data Map PII-ruleset chain after this scenario.

## 12. References

1. New-AzPurviewSqlServerDatabaseScanRulesetObject (Az.Purview PowerShell module, confirms the
   Custom `SqlServerDatabaseScanRuleset` object shape and the `Kind: "SqlServerDatabase"` value,
   direct fetch from `learn.microsoft.com` in this build's environment), 
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasescanrulesetobject>
2. Scan Rulesets - Get / Create Or Replace REST API reference (API version 2023-09-01; confirms the
   `SqlServerDatabaseScanRuleset` object definition and `kind` literal alongside every sibling source
   type's own analogous object; generic call shape shared across source types; direct fetch this
   build), 
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/get>
   <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace>
3. SqlServerDatabaseScanRuleset / SqlServerDatabaseSystemScanRuleset interfaces
   (`@azure-rest/purview-scanning` JavaScript SDK, confirms `kind: "SqlServerDatabase"` for BOTH the
   Custom and System ruleset variants of this source type, direct fetch this build), 
   <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/sqlserverdatabasescanruleset>
   <https://learn.microsoft.com/javascript/api/@azure-rest/purview-scanning/sqlserverdatabasesystemscanruleset>
4. New-AzPurviewSqlServerDatabaseCredentialScanObject (Az.Purview PowerShell module, confirms the
   scan object's field names via a worked example; that example uses an arbitrary custom ruleset
   name `'SqlServer'`, not the System default, which is why reference 1/2/3's `kind` confirmation
   does not also close the System ruleset's literal `name`, see §11), 
   <https://learn.microsoft.com/powershell/module/az.purview/new-azpurviewsqlserverdatabasecredentialscanobject>
5. Type - List REST API reference (Types API; confirms `type=CLASSIFICATION` query filter and the
   `classificationDefs[].name` response shape, tenant-wide, source-type-agnostic; reused unchanged
   from the Azure SQL Database sibling's own direct fetch), 
   <https://learn.microsoft.com/rest/api/purview/catalogdataplane/types/get-all-type-definitions>
6. Custom classifications in Data Map ("The Microsoft system classifications are grouped under the
   reserved `MICROSOFT.` namespace."), <https://learn.microsoft.com/purview/data-map-classification-custom>
7. Data governance roles and permissions in Microsoft Purview (classic Data Map role vocabulary, 
   Data Source Administrator, Data Curator, Data Reader, Collection Admin), 
   <https://learn.microsoft.com/purview/data-gov-classic-permissions>
8. Connect to and manage an on-premises SQL server instance in Microsoft Purview (base scenario's
   registration/scan reference this scenario extends; confirms the mandatory SHIR requirement and
   the stored-credential-only authentication story this scenario's reconcile step preserves), 
   <https://learn.microsoft.com/purview/register-scan-on-premises-sql-server>
9. Data Map classification supported list (confirmed to list classifications by human-readable
   name/description only, with no exact `MICROSOFT.*` identifier strings), 
   <https://learn.microsoft.com/purview/data-map-classification-supported-list>
10. Remove-AzPurviewScanRuleset (Az.Purview PowerShell module, corroborates the scan rule set
    delete operation and its 204 response), 
    <https://learn.microsoft.com/powershell/module/az.purview/remove-azpurviewscanruleset>
11. Scans - Create Or Replace REST API reference (reused here to reconcile the existing scan's
    ruleset reference), 
    <https://learn.microsoft.com/rest/api/purview/scanningdataplane/scans/create-or-replace>
12. `scenarios/data-map/scan-on-premises-sql-server-and-classify/` (base scenario this fragment
    extends; confirms `SqlServerDatabaseCredential` as the only compatible scan kind, and discloses
    the System-ruleset-name VERIFY this scenario inherits unresolved), this repository.
13. Audit logs, diagnostics, and activity history in Microsoft Purview governance portal (confirms
    "Scan rule set: Create/Update/Delete" as an audited Management-category event), 
    <https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics#audit-event-categories>
14. microsoftPurviewDataMapOperationRecord resource type / `PurviewDataMapOperation` audit log
    record type (Microsoft Graph security API, the SIEM-consumable record type for Data Map
    Management-category events, including scan rule set changes), 
    <https://learn.microsoft.com/graph/api/resources/security-microsoftpurviewdatamapoperationrecord>
15. `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/`,
    `scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/`, and
    `scenarios/data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset/` (sibling
    scenarios this fragment mirrors, pattern precedent for the live-Types-API exclusion-list
    design, the reconcile-not-reconstruct scan update, and the name-vs-kind independent-verification
    discipline), this repository.

> Re-verify all links, API versions, and REST body shapes against current Microsoft Learn before a
> customer-facing deployment. One VERIFY remains open in §11 (the System default scan rule set's
> literal resource `name` for this source type, inherited unresolved from the base scenario) and
> should be closed against a pilot tenant or the Purview portal's own Scan rule sets → System tab
> before production use.
