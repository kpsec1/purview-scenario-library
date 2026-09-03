# PROGRESS — build state & backlog

**This file is the single source of truth for what to do next.** Every loop turn: read this
first → pick the top unblocked `TODO` → do exactly one fragment → update this file → commit.

## Backlog policy
- Order: cross-cutting → Data Governance → Data Security → Risk & Compliance.
- **One fragment per turn.** A fragment = one scenario reaching definition-of-done (docs + code +
  four-lens review), or one scoped sub-task below. Split large scenarios into `-part1/-part2/-part3`.
- **Commit before ending the turn.** Nothing is "done" until committed.
- Ground all product facts in Microsoft Learn. Author-only code; never run against a live tenant.
- Definition of done: see `AGENTS.md` §9.

## In progress
- (none)

## TODO (ordered)

### Risk & Compliance
- [ ] `scenarios/communication-compliance/harassment-and-code-of-conduct/`
- [ ] `scenarios/ediscovery/premium-legal-hold-and-export/`
- [ ] `scenarios/audit/premium-audit-investigation/`
- [ ] `scenarios/data-lifecycle-management/retention-labels-financial-records/`
- [ ] `scenarios/records-management/regulatory-records-disposition/`
- [ ] `scenarios/information-barriers/segregate-trading-and-research/`

> After the starter scenario per module lands, expand each module across the AGENTS.md §3 axes
> (lifecycle, deployment posture, regulatory driver, failure/abuse, scale). Add those fragments
> here as they're scoped.

### Follow-ups discovered while building the DLP template scenario
- [ ] `scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/` (or fold into Adaptive
  Protection) — cross-message/behavioral correlation to close the split-PAN evasion gap flagged
  in `reviews.md` (Red Team) for the Teams template scenario; depends on
  `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/` or
  `scenarios/insider-risk/departing-employee-data-theft/` landing first.
- [ ] `scenarios/compliance-manager/pci-dss-assessment/` — Compliance Manager PCI DSS v4.0
  premium-template assessment scenario referenced from `scenarios/dlp/pci-teams-exfil-block/README.md`
  §2 as the assessment-side companion to this technical control.

### Follow-ups discovered while building the Endpoint DLP USB-block scenario
- [ ] `scenarios/dlp/removable-usb-device-groups-allowlist/` (or fold into a future Endpoint DLP
  hardening pass) — script/document the **Removable USB device groups** portal feature
  (`Set-PolicyConfig -DlpRemovableMediaGroups`) to allow specific IT-issued encrypted backup
  drives by device identity, complementing the group-based (user) exception in
  `scenarios/dlp/endpoint-dlp-usb-block/`. Flagged as out of scope there because the per-rule
  PowerShell syntax for referencing an authorization group inside `-EndpointDlpRestrictions`
  is not documented anywhere found during that scenario's build — needs a fresh grounding pass.
- [ ] Consider a companion `scenarios/dlp/defender-device-control-usb-allowlist/` (Microsoft
  Defender for Endpoint device control, not Purview DLP) — `endpoint-dlp-usb-block/README.md`
  §11 notes Endpoint DLP is content-aware but not device-identity-aware, and a buyer wanting "no
  unapproved USB devices, period" needs device control in addition, not instead.
- [ ] Verify (against a pilot tenant or an official Microsoft Learn source, not just the Tech
  Community blog cited in `scenarios/dlp/endpoint-dlp-usb-block/README.md` §11) the exact
  `-EndpointDlpRestrictions` `Setting`/`Value` strings this scenario's deploy script uses
  (`RemovableMedia` / `Block` / `Audit`) — flagged as an explicit VERIFY in that scenario because
  Microsoft's canonical `New-DlpComplianceRule`/`Set-DlpComplianceRule` reference documents the
  parameter only as an opaque hashtable array with no enumerated values, and
  techcommunity.microsoft.com was unreachable (network egress blocked) in this build environment
  to quote the walkthrough verbatim.

### Follow-ups discovered while building the Information Protection auto-labeling scenario
- [ ] Extend `docs/automation-surface.md` with a fifth automation surface: **SharePoint Online
  Management Shell** (`Connect-SPOService` / `Microsoft.Online.SharePoint.PowerShell`). Needed for
  `Set-SPOTenant -EnableAIPIntegration`, `-EnableSensitivityLabelforPDF`, and
  `-EnableSensitivityLabelForVideoFiles` — none of the four currently-documented surfaces (EXO,
  S&C PowerShell, Graph, Data Map REST) cover it, and `scenarios/information-protection/
  auto-label-confidential-sharepoint/` had to flag this as a manual/undocumented prerequisite
  rather than automate it.
- [ ] `scenarios/information-protection/auto-label-confidential-exchange/` — Exchange-location
  companion to `auto-label-confidential-sharepoint` using the same policy family
  (`New-AutoSensitivityLabelPolicy -ExchangeLocation`), extending coverage to email per the
  non-goal noted in that scenario's `design.md` §7.
- [ ] Consider a `scenarios/information-protection/` sub-scenario (or a cross-cutting note) on
  **localizing sensitive information type selection by data-residency/jurisdiction** — flagged as
  a Red Team/CISO finding in `auto-label-confidential-sharepoint/reviews.md`: the SSN + Credit
  Card Number starter set is U.S.-centric and should not be presented as GDPR-complete personal-
  data coverage for an EU/UK-only tenant without swapping in the relevant regional SITs.

### Follow-ups discovered while building the Insider Risk Management departing-employee scenario
- [ ] Consider scripting the HR-connector Entra app registration itself (Microsoft Graph
  `New-MgApplication`/`New-MgServicePrincipal`/app-password creation) instead of leaving it a
  manual portal prerequisite (`scenarios/insider-risk/departing-employee-data-theft/README.md`
  §5 step 2) — deferred in this build because no Graph-cmdlet quickstart specific to this
  HR-connector auth flow was independently grounded, and fabricating the exact parameter set
  risked violating `AGENTS.md` §4's no-invented-cmdlets rule. Worth a dedicated, narrowly-scoped
  follow-up fragment once grounded.
- [ ] `scenarios/insider-risk/security-policy-violations-by-departing-users/` — the related but
  distinct IRM template requiring Microsoft Defender for Endpoint integration, explicitly called
  out as a non-goal in `departing-employee-data-theft/design.md` §7.
- [ ] VERIFY (pilot tenant, before any customer relies on the daily-schedule pattern in
  `departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`): whether re-uploading an
  unchanged resignation CSV on a subsequent scheduled run is a safe no-op or creates a duplicate
  signal — undocumented by Microsoft as of this build (flagged inline in the script's `.NOTES`
  and `README.md` §11).
### Follow-ups discovered while building the Adaptive Protection dynamic-risk-DLP scenario
- [ ] `scenarios/dlp/endpoint-dlp-usb-block-adaptive-protection/` (or fold into a future Endpoint
  DLP hardening pass) — script the **Devices** half of Adaptive Protection (risk-based
  clipboard/USB/print/network-share/restricted-app restrictions via `-SharedByIRMUserRisk` +
  `-EndpointDlpRestrictions`), deferred from `dynamic-risk-dlp-enforcement` because
  `-EndpointDlpRestrictions`'s exact `Setting`/`Value` strings already carry an open VERIFY from
  `scenarios/dlp/endpoint-dlp-usb-block/` — needs that VERIFY closed first (ideally via a pilot
  tenant) rather than compounding a second unverified use of the same parameter. Also requires
  either Advanced classification scanning and protection enabled, or an explicit File Type
  condition, per Microsoft's documented Devices-policy prerequisite.
- [ ] `scenarios/adaptive-protection/conditional-access-insider-risk-block/` — script/document
  the Conditional Access "Insider risk" condition integration (Microsoft Entra admin center,
  requires **Microsoft Entra ID P2**), deferred from `dynamic-risk-dlp-enforcement` because it's
  a different admin surface (Entra, not Purview/EXO) with its own license prerequisite this
  scenario's DLP-only design doesn't otherwise require. Still a Microsoft-labeled **preview**
  integration as of this build — re-check GA status before scoping.
- [ ] Consider a cross-cutting or Data Lifecycle Management-module scenario covering the
  120-day deleted-content preservation policy Adaptive Protection can auto-create for
  Elevated-risk users — deferred from `dynamic-risk-dlp-enforcement` as a separate opt-in with
  its own retention-policy implications, better scoped alongside this library's future Data
  Lifecycle Management module scenarios (still TODO below) than bundled into the DLP scenario.
- VERIFY (pilot tenant, before a customer relies on it in production): whether representing the
  portal's compound "Content is shared from Microsoft 365 with people outside my organization"
  condition using `-AccessScope NotInOrganization` alone (this scenario's and
  `pci-teams-exfil-block`'s shared pattern) is a byte-for-byte match to the portal-rendered rule,
  or whether a separate `-ContentIsShared` boolean condition is also required — flagged inline in
  `dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1`'s `.NOTES` and
  `README.md` §11.

### Follow-ups discovered while building the Data Map Azure SQL scan-and-classify scenario
- [ ] VERIFY (pilot tenant or the Purview OpenAPI spec, before production use): the exact REST
  request body shapes for the **Data Sources - Create Or Update**, **Triggers - Create Or
  Replace**, and **Scan Result - Run Scan** operations used by
  `scenarios/data-map/scan-azure-sql-and-classify/deploy/New-AzureSqlDataMapScan.ps1`. Their
  canonical Microsoft Learn REST reference pages returned fetch errors in this build environment;
  the shapes used are reconstructed from the confirmed sibling **Scans - Create Or Replace**
  endpoint (direct-fetched, API version `2023-09-01`), the official
  `@azure-rest/purview-scanning` JS SDK type definitions, and the `Az.Purview` PowerShell module's
  parameter signatures — three converging but indirect sources. Flagged inline in that scenario's
  `README.md` §11 and the deploy script's `.NOTES`.
- [ ] `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/` (or fold into a future Data
  Map hardening pass) — script a **custom, PII-only scan rule set** (excluding all system
  classifications except U.S. Social Security Number and Credit Card Number) once the "Scan
  Rulesets - Create Or Update" REST body is independently grounded, or by wrapping the `Az.Purview`
  PowerShell module's `New-AzPurviewAzureSqlDatabaseScanRulesetObject
  -ExcludedSystemClassification` cmdlet directly instead of raw REST. Deferred from
  `scan-azure-sql-and-classify` because the exact REST JSON shape wasn't confirmed during that
  build — see its `README.md` §11 VERIFY.
- [ ] Consider scripting **credential-object creation** (Key Vault-backed, for the
  `AzureSqlDatabaseCredential` scan kind — SQL authentication or service principal) once a
  documented REST endpoint for it is found; deferred from `scan-azure-sql-and-classify` because no
  such endpoint was located during that build (Microsoft's own docs show credential creation only
  via the portal UI). Needed for any buyer whose target SQL Server can't use SAMI (e.g. reachable
  only via a self-hosted integration runtime, which doesn't support managed-identity auth).
- [ ] Sibling Data Map scan scenarios for **Azure SQL Managed Instance**, **Azure Synapse
  Analytics** (dedicated + serverless SQL pools), and **on-premises SQL Server** (via self-hosted
  IR) — each has its own registration/authentication nuances Microsoft documents separately;
  explicitly called out as a non-goal in `scan-azure-sql-and-classify/design.md` §7.
- [ ] `scenarios/data-map/scan-azure-sql-and-classify/` also assumes downstream scenarios will
  consume its classification output — once `scenarios/data-estate-insights/
  classification-coverage-report/` (already TODO below) is built, cross-link it back into this
  scenario's §8 "Downstream use" note.

### Follow-ups discovered while building the DSPM for AI Copilot sensitive-data-exposure scenario
- [ ] VERIFY (pilot tenant): whether a `{"Type":"Group","Identity":"..."}` `Inclusions` entry in
  the Copilot-location `-Locations` JSON works for `New-DlpCompliancePolicy`/`New-DlpComplianceRule`
  the same way a group inclusion is documented for the *collection*-policy cmdlets
  (`New-/Set-FeatureConfiguration`) — needed before this repo can promise a group-scoped pilot
  rollout of `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` instead of tenant-wide
  `TestWithNotifications` simulation as the only pre-enforcement pilot mechanism. Flagged inline in
  that scenario's `README.md` §11 and `reviews.md` (Red Team).
- [ ] `scenarios/dspm-for-ai/copilot-prompt-full-block/` (or fold into a future DSPM-for-AI pass) —
  script the "Prevent Copilot from processing content > Processing prompts" action (full response
  block on a sensitive-information-type match in the prompt itself), deferred from
  `copilot-sensitive-data-exposure` because it is a preview feature with no published Microsoft
  PowerShell worked example as of this build (only the label-exclusion and web-grounding-
  restriction actions have one) — needs a fresh grounding pass once Microsoft publishes an example
  or the feature reaches GA.
- [ ] `scenarios/dspm-for-ai/third-party-ai-site-adaptive-block/` — the Adaptive-Protection-driven,
  risk-based DLP policies for **third-party** generative AI sites accessed via a browser
  (`DSPM for AI - Block sensitive info from AI sites`, `DSPM for AI - Block elevated risk users
  from submitting prompts to AI apps in Microsoft Edge`), explicitly called out as a non-goal in
  `copilot-sensitive-data-exposure/design.md` §7 — a different policy location/enforcement plane
  from the first-party Microsoft 365 Copilot location that scenario covers, and a natural extension
  of `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/`'s existing pattern.
- [ ] Consider updating `docs/licensing-matrix.md` to add the DLP-for-Copilot licensing-tier split
  (label-exclusion rule requires E5-tier; prompt-safeguard/web-grounding rule is available at all
  Copilot licensing tiers) as its own row/footnote — currently only cited inline in
  `copilot-sensitive-data-exposure/README.md` §3, not surfaced in the cross-cutting matrix.

### Follow-ups discovered while building the Unified Catalog business-glossary scenario
- [ ] `scenarios/unified-catalog/link-glossary-terms-to-data-products/` — link this scenario's
  (or any) glossary terms to data products/assets/columns via the `Terms - Add Related Entity`
  and Data Products operation groups, deferred as a non-goal in `curate-business-glossary/
  design.md` §7 because it requires a Data Products scenario (and Data Map-scanned assets) to
  already exist to link against — natural follow-up once `scenarios/data-map/
  scan-azure-sql-and-classify/` output has a data product to attach to.
- [ ] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row (currently
  "evolving surface — VERIFY exact endpoint names per release") with the confirmed exact
  operation groups/paths grounded in `curate-business-glossary` (`Terms` and `Business Domain`
  operation groups, `POST/PUT/DELETE/GET /datagovernance/catalog/terms(|/{id})`,
  `.../businessdomains(|/{id})`, `.../terms/{id}/relationships`, API version
  `2026-03-20-preview`) — closes that cross-cutting doc's open VERIFY for this one surface.
- [ ] VERIFY (pilot tenant, before production reliance): the Unified Catalog `Terms - Query`
  `nameKeyword` filter's exact match semantics (substring/prefix/tokenized) are undocumented;
  `curate-business-glossary`'s idempotency design always re-checks for an exact client-side name
  match rather than trusting the filter, but a domain with more than one page of name-matching
  terms could in principle need pagination the deploy script doesn't yet implement — flagged
  inline in `README.md` §11 and the deploy script's `.NOTES`.
- [ ] VERIFY (pilot tenant): the Unified Catalog `Business Domain - Create`/`Update` REST
  reference marks `systemData`/`thumbnail`/`domains`/`managedAttributes` as required request-body
  fields in a way that contradicts Microsoft's own worked examples and ordinary REST semantics;
  `curate-business-glossary`'s deploy script sends a minimal practical body instead and flags this
  discrepancy rather than fabricating placeholder values for those fields — confirm the minimal
  body is accepted (or find the correct minimal shape) against a pilot tenant.
- [ ] Consider a `scenarios/unified-catalog/governance-domain-hierarchy/` (or fold into a future
  Unified Catalog pass) covering multi-domain parent/child governance hierarchies, custom
  attribute groups, and data estate mappings to Data Map collections — explicitly out of scope in
  `curate-business-glossary/design.md` §6–7, which models a single standalone domain.

### Follow-ups discovered while building the Data Lineage end-to-end-lineage-validation scenario
- [ ] `scenarios/data-lineage/custom-process-lineage/` (or fold into a future Data Lineage
  hardening pass) — script the richer DataSet -> Process -> DataSet lineage shape (a custom
  Process-typed entity representing the transform itself, not just a direct dataset-to-dataset
  edge), once a REST-documented body for creating a *custom* Process entity type is independently
  grounded — deferred from `end-to-end-lineage-validation` because this build's grounding pass only
  confirmed the `direct_lineage_dataset_dataset` shape via Microsoft's own worked example; see that
  scenario's `README.md` §11 and `design.md` §1/§7.
- [ ] Generalize `scenarios/data-lineage/end-to-end-lineage-validation/validate/
  Test-EndToEndLineage.ps1`'s column-mapping check ("Check 2") to match each `customLineageLinks`
  entry against its own declared upstream node rather than always the origin asset — needed before
  that scenario's definition file can correctly model a multi-hop chain with a custom link further
  downstream than the origin's immediate output. Currently correct only for the shipped
  single-hop example; flagged inline in the script and in `design.md` §7.
- [ ] VERIFY (pilot tenant): the exact qualifiedName string format Purview assigns to an
  `azure_sql_table` asset (e.g. whether it follows an `mssql://...` scheme) — not found during this
  build's grounding pass; `end-to-end-lineage-validation`'s definition file currently requires the
  operator to copy the value from the portal rather than having either script construct it. Closing
  this would let a future scenario auto-resolve qualifiedNames instead of requiring manual copy.
- [ ] VERIFY (pilot tenant): whether `Relationship - Create` rejects, no-ops, or duplicates a
  second POST of an identical relationship — this build's grounding pass confirmed the operation's
  request/response shape directly from Microsoft's REST reference but not this specific behavior;
  `end-to-end-lineage-validation`'s own existence-check design makes its idempotency independent of
  the answer, but a production integration bypassing that check should confirm it first.
- [ ] Extend `docs/automation-surface.md` §4's routing table with a row for Data Map lineage
  (`entity/bulk`, `relationship`, `lineage/uniqueAttribute/type/{typeName}` — surface 4,
  `datamap/api/atlas/v2/...`, API version `2023-09-01`) — not added in this build to keep the
  fragment scoped to one scenario; `scan-azure-sql-and-classify`'s and
  `curate-business-glossary`'s own automation-surface.md follow-ups set the same precedent of
  tracking doc extensions separately rather than bundling them into a scenario fragment.

### Follow-ups discovered while building the Data Quality rules-and-scorecards scenario
- [ ] `scenarios/data-quality/connection-and-scorecard-alerts/` (or fold into a future Data Quality
  hardening pass) — script the DQ data-source connection (`Create Data Source`) and score-threshold
  alerts (`Get Alerts`/`Update Alert`), both deferred from `rules-and-scorecards` because
  `Create Data Source`'s `computeId` field has no documented provisioning endpoint this build could
  find, and the Alerts operations weren't independently fetched/grounded in this build — see that
  scenario's `README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the Data Quality Schedule object's
  trigger `type` values beyond the confirmed `RunOnce` shape — a `Recurrence` type with frequency/
  interval fields almost certainly exists (the portal's own Scheduled scans wizard supports daily/
  weekly/monthly recurrence) but wasn't found in this build's REST reference fetch. Needed before
  `rules-and-scorecards` (or a follow-up) can script an ongoing scan cadence instead of a one-time
  `RunOnce` schedule.
- [ ] VERIFY (pilot tenant): the exact mechanism by which a `TypeMatch` (Data type match) rule's
  `typeProperties` specifies the target type a column is checked against — the confirmed REST
  `TypeProperties` schema has no field name for it despite Microsoft's conceptual documentation
  describing the behavior. Flagged inline in `rules-and-scorecards/deploy/
  New-DataQualityRulesAndSchedule.ps1`'s `.NOTES` and `README.md` §11.
- [ ] A Unified Catalog **data products** scenario (create/manage a data product, add data assets to
  it) is a shared, still-unbuilt dependency both `curate-business-glossary`'s and
  `rules-and-scorecards`' non-goals point to — every module scenario that targets an existing
  "governed data asset" (Data Quality rules, future access-policy scenarios) assumes one already
  exists. Worth prioritizing given how many follow-ups now depend on it.

### Follow-ups discovered while building the Data Estate Insights classification-coverage-report scenario
- [ ] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` (or fold into a future
  Data Estate Insights hardening pass) — extend `classification-coverage-report`'s exact pattern
  (paginated `Discovery - Query`, client-side tally, replace-by-`RunId` trend log) to the `label`
  field on the same `SearchResultValue` schema, reproducing the native "Labeling insights" report's
  KPIs the same way this fragment reproduces "Classification insights" — explicitly scoped out of
  `classification-coverage-report/design.md` §7.
- [ ] `scenarios/data-estate-insights/glossary-curation-coverage-report/` — the native "Glossary
  insights"/"Data stewardship" dashboards (term-to-asset attachment rates, active-user counts) use
  different underlying data than `Discovery - Query`'s per-asset `classification`/`label` fields and
  would need a different REST primitive (likely the Unified Catalog Terms operation group this
  repo's `scenarios/unified-catalog/curate-business-glossary/` already grounds) — explicitly scoped
  out of `classification-coverage-report/design.md` §7 as a different data source, not a copy-paste
  extension of this fragment's pattern.
- [ ] VERIFY (pilot tenant, before production reliance): `classification-coverage-report/deploy/
  Export-ClassificationCoverageReport.ps1`'s `Get-FullBreakdown` warns (but does not fail) when the
  number of records actually paged via `continuationToken` doesn't match the response's own
  `@search.count` — Microsoft's Discovery - Query REST reference doesn't document whether this
  mismatch is expected (e.g. due to near-real-time index changes mid-page-through) or a sign of a
  client-side pagination bug. Confirm against a pilot tenant with a large, stable (non-changing)
  asset population before treating a persistent mismatch as benign.
- [ ] Note for a future Data Lineage follow-up: this build's `Discovery_Query_Collection` worked
  example response (Microsoft's own REST reference page for Discovery - Query) shows a real
  `azure_sql_table` `qualifiedName` value —
  `mssql://exampleserver.database.windows.net/examplesqldb/examplepath/exampledata1` — which
  directly bears on the open VERIFY in `scenarios/data-lineage/end-to-end-lineage-validation/
  README.md` §11 ("the exact qualifiedName string format Purview assigns to an azure_sql_table
  asset"). Not applied retroactively to that already-DONE fragment in this build (out of scope for
  this turn), but the next pass on that scenario (or a dedicated Data Map/Data Lineage grounding
  fragment) should confirm this `mssql://` scheme against a pilot tenant and, if confirmed, update
  that scenario's README/design.md to close the VERIFY instead of requiring manual portal copy.

### Follow-ups discovered while building the Compliance Manager ISO 27001 assessment scenario
- [ ] `scenarios/compliance-manager/entra-privileged-role-monitoring/` (or fold into a future
  cross-cutting RBAC-hardening pass) — script monitoring of Entra directory role-assignment changes
  for Global Administrator/Compliance Administrator/Compliance Data Administrator/Security
  Administrator, the four Entra roles that grant implicit Compliance Manager Administration-
  equivalent access invisibly to `assess-against-iso27001`'s audit-trail script (flagged as a Red
  Team finding in that scenario's `reviews.md` and `README.md` §11) — via Microsoft Graph's Entra
  directory audit log / `auditLogs/directoryAudits`, not the Compliance-Manager-specific
  `Search-UnifiedAuditLog` operations this scenario already covers.
- [ ] VERIFY (pilot tenant, before production reliance): the internal JSON shape of the `AuditData`
  payload for `ComplianceManagerRolesChange`/`ComplianceManagerAutomationLevelChange`/
  `ComplianceManagerAutomationChange` audit records — not published in Microsoft's
  `audit-log-activities` reference. `assess-against-iso27001/deploy/
  Export-ComplianceManagerAuditTrail.ps1`'s `Get-BestEffortTargetObjectId` function assumes an
  `ObjectId` property *might* exist inside that JSON (best-effort, non-blocking) but does not rely
  on it for correctness — the script's real de-duplication key hashes the full raw payload instead.
  Confirming the actual shape would let a future revision surface richer, grounded columns (e.g.
  which specific improvement action or role was changed) instead of the current opaque JSON blob.
- [ ] Re-check whether Compliance Manager has added an ISO/IEC 27001:2022 premium template (the
  version organizations now actually certify against) — only the :2013 template was found during
  this build's grounding pass (`assess-against-iso27001/README.md` §11, tagged VERIFY). If a :2022
  template exists, add a sibling scenario or update this one rather than leaving :2013 as the only
  documented path.
- [ ] `scenarios/compliance-manager/pci-dss-assessment/` (already tracked above, under the DLP
  PCI Teams follow-ups) — once built, cross-link it into `assess-against-iso27001`'s manifest
  `recommendedDeploymentOrder`/group-sharing guidance as a sibling assessment in the same
  `Security & Compliance Assessments` group.
- [ ] Once Compliance Manager's **Export actions** Excel file has been inspected against a real
  tenant, ground the "Action Update" tab's exact column schema and revisit the non-goal recorded in
  `assess-against-iso27001/design.md` §7 — a schema-accurate generator script would be a genuine,
  higher-value addition to this scenario that this build deliberately declined to fabricate.

## DONE
- [x] `scenarios/compliance-manager/assess-against-iso27001/` — first Risk & Compliance-module
  scenario, and the first scenario in this repo built against a Purview surface with **no write
  API**: full README (12-section skeleton, explicit up-front note on why this scenario's shape
  differs from every prior one), design.md (grounds the no-write-API finding across three
  independently-fetched Microsoft Learn articles plus this repo's own `docs/automation-surface.md`
  routing-table gap, explains why a dedicated assessment beats extending the default Data
  Protection Baseline, and documents the built-in-automation evidence-feed mechanism without
  fabricating Microsoft's proprietary per-control mapping), deploy/ (a reference-only, explicitly
  non-executable `iso27001-assessment-manifest.json` for the portal-driven assessment-creation
  runbook — the same pattern `scenarios/insider-risk/departing-employee-data-theft/` already
  established for another no-write-API Purview surface — plus the one genuinely scriptable piece:
  `Export-ComplianceManagerAuditTrail.ps1`, idempotent/parameterized Exchange Online PowerShell
  automation (surface 1) that pulls the exactly three Compliance-Manager-specific operations
  Microsoft's audit log documents (`ComplianceManagerRolesChange`,
  `ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange`), merging into a
  rolling CSV de-duplicated by a composite key that deliberately avoids assuming an unconfirmed
  flat `ObjectId` output property exists — instead hashing the full `AuditData` JSON payload —
  with a best-effort, non-authoritative `ObjectId` extraction surfaced only as a display column;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only query and
  reports would-be merge counts), validate/ script (`Test-ComplianceManagerAuditTrail.ps1` —
  automated CSV schema/de-duplication/operation-value/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the assessment's existence/scope/group/role
  assignments, none of which have a read API either), rollback.md (the first in this repo to
  separate a portal-only object's rollback — staged scope-down/access-revocation/deletion, all
  manual — from a scripted artifact's rollback — schedule + role removal — as two independent
  procedures), four-lens reviews.md (Red Team Fix round resolved — flagged that the audit-trail
  script is blind to Compliance Manager access granted implicitly via the Global Administrator/
  Compliance Administrator/Compliance Data Administrator/Security Administrator Entra roles, none
  of which trigger a `ComplianceManagerRolesChange` event, and that the native Reports page's
  6-month history isn't durably preserved by this scenario — both closed with documented
  operational mitigations rather than fabricated code fixes; Blue Team clarifications — confirmed
  the manual-checklist and alert-routing scope boundaries match this repo's own established
  precedent in `departing-employee-data-theft`/`pci-teams-exfil-block`; CISO Pass; Product Owner
  Fix round resolved — independently re-confirmed the no-write-API finding, flagged a VERIFY on
  ISO 27001:2013-vs-2022 template currency, and confirmed Compliance Manager role-name/role-group
  naming accuracy) — grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (`compliance-manager-assessments`, `compliance-manager-update-actions`,
  `compliance-manager-setup`, `compliance-manager-improvement-actions`,
  `compliance-manager-regulations`/`-regulations-list`, `compliance-manager-faq`, the ISO 27001
  regulatory-offering page, `audit-log-activities`'s Compliance Manager activities table,
  `Search-UnifiedAuditLog`'s own reference page plus two independent worked-example pages, and
  `audit-log-retention-policies` for the 180-day/1-year/10-year retention tiers) — three real bugs
  caught and fixed during a post-draft self-review before this fragment was finalized: an
  unconfirmed flat `ObjectId` property assumed on `Search-UnifiedAuditLog` output (replaced with a
  hash-of-`AuditData` composite-key component plus a clearly-labeled best-effort display column), a
  process-randomized `[string]::GetHashCode()`-style hash that would have silently broken
  cross-run de-duplication (replaced with `MD5.ComputeHash`), and a single-object-vs-array paging
  loop that could misbehave when a page returned exactly one record (fixed by wrapping in `@()`
  before checking `.Count`) — 2026-09-03

- [x] `scenarios/data-estate-insights/classification-coverage-report/` — first Data Estate
  Insights-module scenario: full README (12-section skeleton), design.md, deploy/
  (`Export-ClassificationCoverageReport.ps1` — idempotent/parameterized Purview Data Map Discovery
  REST automation (surface 4, API version `2023-09-01`) that reproduces the native "Classic
  classifications" report's headline KPIs — total/classified/unclassified asset counts and a full
  classification-value histogram, per object type — via two modes: `-Mode Full` (paginated,
  `continuationToken`, page size 1000, tallies each record's `classification[]` array client-side
  since no "has any classification" filter is documented) and `-Mode Facets` (a single faceted query,
  cheaper but top-N-truncated and double-counting, mirroring the native "Top classifications" chart's
  own behavior); requires only the **Data Reader** role — deliberately narrower than the native
  report's own Data-Curator-only "Export to CSV" gate; idempotent via replace-by-`-RunId` in a
  trend-log CSV rather than a create/skip check, since this scenario creates no Purview object to
  check existence against; `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` reports
  computed KPIs without touching disk), validate/ script (`Test-ClassificationCoverageReport.ps1` —
  read-only file-integrity checks (schema, no duplicate RunId+ObjectType rows, per-row arithmetic)
  runnable with no tenant credentials, plus an optional live-reconciliation check against current
  `@search.count`), rollback.md (the first in this repo describing a scenario with **no Purview
  object** to roll back — decommissioning is stopping the schedule, removing the Data Reader role
  assignment, and deciding the fate of already-produced report files), four-lens reviews.md (Red Team
  Fix round resolved — flagged the trend-log/breakdown files themselves as a sensitive artifact
  requiring the same protection as the classifications they summarize, and the `-Mode Facets`
  top-N-truncation as a silent-gap risk; Blue Team Fix round resolved — warning-stream capture
  guidance for unattended runs, and severity-mapping clarity between file-integrity `[FAIL]` and
  live-reconciliation `[WARN]`; CISO Pass; Product Owner Fix round resolved — tightened the
  "Unclassified assets" KPI citation to the specific classic-assets-report page and its exact quoted
  definition) — grounded in Microsoft Learn via the Microsoft Learn MCP tool (the Data Estate
  Insights application overview, classic classifications/assets reports, the Data Estate Insights
  access-control page confirming Data Reader can view but not export while only Data Curator can,
  the "Disable Data Estate Insights" page's weekly-refresh/no-separate-billing notes, the Data
  governance glossary, the data-plane API authentication tutorial, and the Discovery - Query REST
  reference directly fetched at API version `2023-09-01` — request/response shape, `@search.count`
  semantics, `continuationToken` pagination, facets, and worked filter examples including the
  documented `objectType`/`collectionId`/exact-value-`classification` filter shapes) plus a Microsoft
  Q&A thread corroborating (not as primary evidence) that no broader classification-existence filter
  is exposed — one design choice (computing classified/unclassified by client-side pagination rather
  than an invented filter) recorded and justified rather than guessed, per `AGENTS.md` §4; also
  caught and fixed a citation-numbering bug during a post-draft self-review (four `design.md`
  cross-references pointed at the wrong `README.md` reference number) and a scoping bug (an unused,
  fully-redundant `Get-TotalCount` helper function) — 2026-09-03

- [x] `scenarios/data-lineage/end-to-end-lineage-validation/` — first Data Lineage-module
  scenario: full README (12-section skeleton), design.md, deploy/ (`New-CustomLineageRelationship.ps1`
  — idempotent/parameterized Purview Data Map/Atlas v2 REST automation (surface 4, API version
  `2023-09-01`) that creates a `direct_lineage_dataset_dataset` custom lineage relationship (with a
  JSON-encoded `columnMapping` attribute) between two already-scanned `azure_sql_table` assets to
  close a gap left by a non-auto-lineage-integrated custom transform job, existence-checked via
  `Lineage - Get By Unique Attribute` before every `Relationship - Create` POST so idempotency
  doesn't depend on that operation's unconfirmed duplicate-POST behavior; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-CustomLineageRelationship.ps1` —
  looks up each relationship's GUID via the same lineage call and deletes it via the (directly
  confirmed) `Relationship - Delete` operation; a JSON lineage-definition file continuing this
  repo's Customer/customerdb narrative), validate/ script (`Test-EndToEndLineage.ps1` — the
  "end-to-end" half of the scenario's name: walks the full reachable lineage graph from an origin
  asset via a breadth-first traversal of the `Lineage - Get By Unique Attribute` response and
  proves every asset in an independently-declared expected chain is both present *and* connected
  by a walkable path, not merely co-listed; read-only, Data Reader role), rollback.md, four-lens
  reviews.md (Red Team Fix round resolved — documented the Data Curator role's collection-wide
  blast radius, and added an explicit "custom lineage is asserted, not verified" evidentiary-
  honesty note for any compliance narrative built on this graph; Blue Team Fix round resolved —
  sharpened the ambiguous "asset not found" failure mode to name `-MaxDepth` as a possible cause
  alongside a deleted link or stale qualifiedName, and documented the column-mapping check's
  single-hop-from-origin scope assumption as a tracked limitation rather than a silent gap; CISO
  Pass; Product Owner Fix round resolved — clarified that the "classic Data Catalog" citations
  ground lineage *concepts* only, while the REST surface this scenario calls is the current,
  non-deprecated Data Map/Atlas API also read by Unified Catalog's own Lineage tab) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (the current, non-legacy "Create and get lineage
  relationships using the REST API" tutorial and its worked Bulk Create/Create Relationship/Get
  Lineage examples; the classic Data Catalog lineage overview/user-guide articles for concepts and
  the auto-lineage-integrated-systems table; the Cloud Adoption Framework's explicit "close gaps
  manually where required" recommendation; the `data-gov-api-custom-types` tutorial confirming the
  `azure_sql_table` type name; the `data-gov-api-rest-data-plane` tutorial confirming Data
  Curator/Data Reader as the Catalog Data plane roles; and four REST operations — Relationship -
  Create, Relationship - Delete, Lineage - Get, Lineage - Get By Unique Attribute — all directly
  fetched from their own canonical REST reference pages at a consistent API version `2023-09-01`,
  a stronger grounding bar than this repo's average scenario) — two items recorded as explicit
  VERIFY rather than resolved by guessing (the exact `azure_sql_table` qualifiedName string format;
  `Relationship - Create`'s duplicate-POST behavior), per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/data-quality/rules-and-scorecards/` — first Data Quality-module scenario: full
  README (12-section skeleton, Public Preview callout up front per Product Owner fix), design.md
  (declarative JSON rule definitions, idempotency design independent of Create Rules' unconfirmed
  create-vs-replace semantics, type-agnostic typeProperties pass-through so no rule-type shape is
  fabricated), deploy/ (`New-DataQualityRulesAndSchedule.ps1` — idempotent/parameterized Purview
  Data Quality REST automation (surface 4, API version `2026-01-12-preview`) that reconciles five
  rules (NotNull/Unique/TypeMatch/Duplicate/CustomTruth, deliberately omitting the Azure-SQL-
  unsupported Freshness rule) against an already-governed "Customer" data asset shared with
  `scan-azure-sql-and-classify`/`curate-business-glossary`'s narrative, plus a one-time (`RunOnce`)
  scan schedule; `-RuleStatus Draft`/`-CreateSchedule:$false` review-first path; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-DataQualityRulesAndSchedule.ps1` —
  staged schedule-only vs. schedule+rules rollback; a JSON rules definition file), validate/ script
  (rule/status/schedule/score checks with a sharpened ambiguous-failure-mode warning), four-lens
  reviews.md (Red Team Fix round resolved — documented the Data Quality Steward role's domain-wide
  blast radius, a Draft-status "quality theater" drift risk, and the example custom rule's weak
  regex; Blue Team Fix round resolved — made portal alert configuration an explicit go-live gate and
  recommended wiring the validate script into a recurring pipeline check; CISO Fix round resolved —
  funding conditionality made explicit via the Blue Team fix; Product Owner Fix round resolved —
  sharpened Public Preview prominence to the README's opening section) — grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (Data Quality overview/rules/scan/scores/alerts/roles-permissions
  articles, the incremental-scan cost rationale, and the Purview Data Quality REST API's Create
  Rules/Get Rules/Create Schedule/Get Schedule/Get Asset Scores For Asset DQ/Create Data Source/
  Delete Rule/Delete Schedule operations directly fetched at API version `2026-01-12-preview`) — four
  gaps (TypeMatch's target-type field, Create Rules' create-vs-replace semantics, the Schedule
  object's recurring-trigger shape, and the unfetched Alerts operations) recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4; also caught and fixed two real bugs
  during a post-draft self-review (a missing `api-version` query parameter on two "list existing
  rules" GET calls that would have 400'd against the live API) — 2026-09-03

- [x] `scenarios/unified-catalog/curate-business-glossary/` — first Unified Catalog-module
  scenario: full README (12-section skeleton), design.md (idempotency design against a
  name-less-unique API, the CSV-bulk-import-can't-update rationale for using REST instead,
  UPN-to-Entra-object-ID owner resolution design), deploy/ (`New-BusinessGlossary.ps1` —
  idempotent/parameterized Unified Catalog REST automation (surface 4) plus a Microsoft Graph
  call (surface 3) to resolve owner/expert UPNs to Entra object IDs; resolves-or-creates a
  governance domain, upserts a small parent/child term hierarchy with acronyms/resources/related-
  term links from a declarative JSON file, `-Publish` gate, manual `$PSCmdlet.ShouldProcess()`
  `-WhatIf` throughout with an explicit `-ReadOnly` bypass for the read-only Query Terms lookup so
  dry-run create-vs-update detection stays accurate; `Remove-BusinessGlossary.ps1` — unpublish
  (reversible, reuses the server's own current fields via GET so it can't clobber a portal-made
  edit) and `-Purge` (permanent delete) rollback; a JSON glossary definition example modeling
  Microsoft's own CAF-recommended Customer/Revenue-style term set), validate/ script (read-only
  content/hierarchy/relationship/publish-status checks), four-lens reviews.md (Red Team Fix round
  resolved — added `User.Read.All` blast-radius compensating controls and stale/departed-owner
  review guidance; Blue Team Fix round resolved — added `systemData` attribution and scheduled-
  validation drift-detection guidance; CISO Pass; Product Owner Fix round resolved — sharpened
  preview-API-surface prominence) — grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (Unified Catalog glossary-terms/governance-domains/roles-permissions/billing/CAF-baseline
  guidance pages, and the Purview Unified Catalog REST API's Terms and Business Domain operation
  groups directly fetched at API version `2026-03-20-preview` — Create/Update/Delete/Get/List/
  Query/AddRelatedEntity/ListRelatedEntities for Terms, Create/Update/Delete/Enumerate for
  Business Domain — plus the Microsoft identity platform client-credentials flow and Graph
  `Get a user`/`User.Read.All` reference for the owner-resolution design) — two REST-schema
  discrepancies recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md`
  §4 — 2026-09-03

- [x] `scenarios/data-map/scan-azure-sql-and-classify/` — first Data Governance-module scenario:
  full README (12-section skeleton), design.md, deploy/ (`New-AzureSqlDataMapScan.ps1` —
  idempotent/parameterized Purview Data Map REST automation (surface 4), registers an
  `AzureSqlDatabase` data source and an `AzureSqlDatabaseMsi` (SAMI-authenticated, credential-free)
  scan against Microsoft's system default scan rule set, with optional recurring trigger and
  `-RunNow`, manual `$PSCmdlet.ShouldProcess()`-wrapped `-WhatIf` throughout since
  `Invoke-RestMethod` has no native ShouldProcess integration; `Remove-AzureSqlDataMapScan.ps1` —
  staged trigger/scan/data-source removal, idempotent on 404; a JSON reference manifest of the
  three REST bodies), validate/ script (read-only config + scan-history check), four-lens
  reviews.md (Red Team Fix round resolved — narrowed the recommended Azure IAM `Reader` scope to
  the SQL Server resource itself instead of resource group/subscription, and flagged the broad
  "Allow Azure services" firewall toggle's tradeoff explicitly; Blue Team Fix round resolved —
  added a four-step incident-response runbook for non-`Succeeded` scan runs and hardened the
  validate script's ambiguous-failure-mode warning; CISO Fix round resolved — added an explicit
  Azure Cost Management budget/alert recommendation given PAYG's uncapped cost-growth model;
  Product Owner Fix round resolved — dropped an unverified custom "PII-only" scan-rule-set default
  in favor of Microsoft's confirmed system default rule set, which already includes the SSN/Credit
  Card Number pair this repo standardizes on) — grounded in Microsoft Learn (Azure SQL Database
  registration/firewall/authentication-options/scan-setup walkthrough and its four supported
  authentication methods' exact T-SQL grants, the Scans - Create Or Replace REST reference
  directly fetched at API version `2023-09-01` with its full `AzureSqlDatabaseMsiScanProperties`
  schema, the Data Map data-plane API-authentication tutorial's service-principal/role-assignment/
  token-acquisition flow, scan run monitoring and 90-day history retention, scan rule set and
  classification-best-practices guidance) plus the `@azure-rest/purview-scanning` JS SDK's type
  definitions and the `Az.Purview` PowerShell module's confirmed cmdlet/parameter surface as
  corroborating (not primary) sources for the three REST operations whose own canonical reference
  pages could not be fetched in this build environment — those three gaps recorded as explicit
  VERIFY items rather than fabricated, per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` — full README (12-section skeleton),
  design.md, deploy/ (`New-CopilotSensitiveDataProtectionPolicy.ps1` — idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule DLP policy on the Microsoft 365 Copilot and
  Copilot Chat location: Rule 0 excludes Confidential/Highly Confidential-labeled content from
  Copilot processing via the `-AdvancedRule`/`-RestrictAccess ExcludeContentProcessing` pattern
  reproduced from Microsoft's own `New-DlpCompliancePolicy` reference Example 4, Rule 1 restricts
  external web-search grounding for SSN/Credit-Card-Number-bearing prompts via `-RestrictWebGrounding`;
  cert app-only, `-WhatIf` throughout; `Remove-CopilotSensitiveDataProtectionPolicy.ps1` —
  disable/purge rollback; a policy JSON reference manifest), validate/ script (automated
  policy/rule/alert-wiring checks), four-lens reviews.md (Red Team Fix round resolved — added an
  explicit VERIFY + follow-up on unconfirmed group-scoped pilot rollout rather than implying it
  works; Blue Team Fix round resolved — added missing `GenerateAlert` checks to the validate
  script; CISO Fix round resolved — added an explicit remediation-ownership note so the DLP policy
  isn't mistakenly reported as "oversharing solved"; Product Owner Pass, with the grounding-strength
  distinction between the two rules recorded) — grounded in Microsoft Learn (DSPM for AI classic
  overview and permissions, the DLP-for-Microsoft-365-Copilot-and-Copilot-Chat location's full
  conditions/actions table and licensing tiers, the exact Copilot location GUID and
  `-AdvancedRule`/`-RestrictAccess`/`-RestrictWebGrounding` PowerShell patterns from
  `New-DlpCompliancePolicy`/`New-DlpComplianceRule`'s own published examples, and DSPM for AI's
  one-click-policy catalog) — deliberately declined to script the preview-only "Processing prompts"
  full-block action for lack of a published PowerShell example (flagged VERIFY/follow-up instead)
  — 2026-09-03

- [x] `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/` — full README (12-section
  skeleton), design.md, deploy/ (`New-AdaptiveProtectionDlpPolicy.ps1` — idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule Exchange+Teams DLP policy keyed on the
  `-SharedByIRMUserRisk` condition, Elevated=block/Moderate+Minor=audit, cert app-only, `-WhatIf`
  throughout, mirrors Microsoft's own documented Quick Setup rule values via the custom-setup
  path; `Remove-AdaptiveProtectionDlpPolicy.ps1` — disable/purge rollback; a portal-configuration
  reference manifest for the non-scriptable Adaptive Protection enablement/insider-risk-level
  steps), validate/ script (automated policy/rule/condition checks plus a manual checklist for
  the portal-only pieces), four-lens reviews.md (Red Team Fix round resolved — removed a
  policy-tip wording that would have tipped off a flagged insider mid-investigation, and
  sharpened the Known Limitations section to name the Endpoint-DLP/Conditional-Access/DLM bypass
  gap explicitly rather than as a scoping footnote; Blue Team clarification — manual DLP-to-IRM-
  alert correlation documented in the runbook; CISO Fix round resolved — added a
  feeder-policy-baseline-first recommendation and an HR/Legal-coordination note before broad
  enforcement rollout; Product Owner Fix round resolved — removed an unverified `-ContentIsShared`
  condition in favor of this library's already-grounded `-AccessScope`-only pattern, added
  "(preview)" labels for the Conditional Access/Data Lifecycle Management integrations) —
  grounded in Microsoft Learn (Adaptive Protection overview/configuration/permissions/36-hour
  propagation delay, the documented Quick-Setup DLP rule values for Teams+Exchange this scenario
  reproduces, the Adaptive-Protection-guide's recommended insider-risk-level definitions, and
  independently confirming `New-/Set-DlpComplianceRule -SharedByIRMUserRisk` and its three fixed
  risk-level GUIDs on both cmdlets' own parameter references) — 2026-09-03

- [x] `scenarios/insider-risk/departing-employee-data-theft/` — full README (12-section
  skeleton), design.md, deploy/ (`Send-HrTerminationRecord.ps1` — parameterized/idempotent HR
  resignation-CSV upload via the documented HR-connector ingestion webhook, chunked at the
  500-row limit, SecureString secret handling, `-WhatIf`; `Export-InsiderRiskAlerts.ps1` —
  read-only Graph Security API alert pull with a correctly-grounded client-side
  `detectionSource` filter after discovering `serviceSource` has no IRM enum member; a portal-
  configuration reference manifest, explicitly labeled as non-executable since IRM policy
  authoring has no PowerShell/Graph write API), validate/ script (automated Graph-permission +
  CSV-schema checks plus an explicit manual-verification checklist for the portal-only pieces),
  four-lens reviews.md (Red Team Fix round resolved — 90-day retrospective-lookback boundary and
  HR-connector app-registration scoping/rotation; Blue Team Fix round resolved — alert-export
  dedup/cursor caveat; CISO Fix round resolved — HR-process-dependency visibility gap; Product
  Owner Pass) — grounded in Microsoft Learn (policy templates and triggering-event prerequisites,
  HR connector CSV schema/webhook/auth flow, priority user groups, role groups and Data Connector
  Admin inclusion, Graph security API alert/detectionSource/serviceSource resource definitions,
  SecurityAlert.Read.All permission, insider-risk-to-Defender-portal integration path) plus two
  PowerShell correctness bugs caught and fixed during a syntax self-review (a single-chunk-CSV
  array-unwrapping bug, and a backslash-vs-backtick string-escaping bug) — 2026-09-03


- [x] repo scaffold — AGENTS.md, README, PROGRESS, LICENSE, .gitignore, CONTRIBUTING — 4a79558 — 2026-09-02
- [x] `docs/licensing-matrix.md` — two-model (per-user + PAYG) licensing matrix, grounded in MS Learn — 2026-09-02
- [x] `docs/rbac-model.md` — four-RBAC-system model (Entra, Purview role groups, Data Governance, Exchange Online) + admin units + PowerShell/Graph auth patterns, grounded in MS Learn — 2026-09-03
- [x] `docs/automation-surface.md` — four automation surfaces (EXO/S&C PowerShell, Graph, Data Map REST), module install, app-only auth setup, task-routing table, throttling/CI-CD patterns, grounded in MS Learn — 2026-09-03
- [x] `docs/glossary.md` — canonical A-Z term list spanning all 14 modules (module-tagged, cross-referencing licensing-matrix.md and rbac-model.md), grounded in MS Learn (incl. the official Purview data-governance and Compliance Manager glossaries) — 2026-09-03
- [x] `scenarios/dlp/pci-teams-exfil-block/` — TEMPLATE scenario: full README (12-section skeleton), design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell, cert app-only pattern, -WhatIf throughout), validate script, four-lens reviews.md (Red/Blue Fix rounds resolved; CISO Pass; Product Owner Fix round resolved) — grounded in MS Learn (DLP-for-Teams scoping/licensing, New-/Set-/Remove-DlpCompliancePolicy/Rule reference, Credit Card Number SIT, PCI DSS v4.0.1 Requirement 4.2) — 2026-09-03

- [x] `scenarios/information-protection/auto-label-confidential-sharepoint/` — TEMPLATE-pattern
  scenario: full README (12-section skeleton with a scope note on U.S.-centric SIT coverage),
  design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance
  PowerShell, two rules — one per workload per the `-Workload` cmdlet constraint, cert app-only
  pattern, `-WhatIf` throughout), validate script (explicit config-vs-match-validation caveat),
  four-lens reviews.md (Red Team Fix round resolved — manual-label-first bypass, exclusion-list
  blind spot, and scan-cadence detection gap documented as residual risks; Blue Team Fix round
  resolved; CISO Pass; Product Owner Fix round resolved — added the `EnableSensitivityLabelforPDF`
  prerequisite) — grounded in MS Learn (apply-sensitivity-label-automatically prerequisites and
  override-behavior tables, New-/Set-/Remove-AutoSensitivityLabelPolicy and
  -AutoSensitivityLabelRule reference, DLP policy reference condition-group OR/AND semantics,
  Set-SPOTenant EnableAIPIntegration) — 2026-09-03

- [x] `scenarios/dlp/endpoint-dlp-usb-block/` — full README (12-section skeleton with an
  explicit VERIFY callout on `EndpointDlpRestrictions` Setting/Value strings), design.md,
  idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell,
  `EndpointDlpLocation`/`EndpointDlpRestrictions`, group-based IT Data Custodians audit-only
  exception mirroring the Card Ops pattern, cert app-only, `-WhatIf` throughout), validate script
  (explicit device-onboarding/policy-sync caveat), four-lens reviews.md (Red/Blue Fix rounds
  resolved; CISO Pass; Product Owner Fix round resolved) — grounded in MS Learn (Endpoint DLP
  licensing/service description, device onboarding overview and permissions, DLP policy reference
  device-restriction action semantics, New-/Set-/Remove-DlpCompliancePolicy/Rule reference,
  reuses the SSN + Credit Card Number SIT pair from `auto-label-confidential-sharepoint`) plus a
  Microsoft Security Blog Tech Community PowerShell walkthrough (not independently fetchable in
  this environment — network egress to techcommunity.microsoft.com blocked — corroborated via two
  independent search-tool summaries and tagged VERIFY for pilot-tenant confirmation) — 2026-09-03

## Blocked / needs user
- (none)
