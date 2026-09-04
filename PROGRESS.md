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
- (none — every module now has a starter scenario; remaining work is the follow-up expansion backlog below)

> After the starter scenario per module lands, expand each module across the AGENTS.md §3 axes
> (lifecycle, deployment posture, regulatory driver, failure/abuse, scale). Add those fragments
> here as they're scoped.

### Follow-ups discovered while building the IRM case-escalation-to-eDiscovery scenario
- [x] Consider a Power Automate flow (or Graph webhook-driven trigger...) that automatically runs
  `Confirm-EdiscoveryEscalationLink.ps1` right after escalation — **grounded and closed, not built**
  (see DONE below): the dedicated grounding pass this item asked for found no automatic/event-driven
  trigger exists. Power Automate's IRM case trigger is manually selected/run from the same dashboard
  toolbar (not fired by the escalation event), none of its five documented connector actions can
  invoke an external script, and the separate Insider Risk Management audit log that does record
  escalations has no documented Graph/REST query API (`Search-UnifiedAuditLog` doesn't cover it
  either). `irm-case-escalation-to-ediscovery/README.md` §8/§11 and `design.md` §4/§5 corrected in
  place; a scheduled poll remains the only unattended option. Re-open this item if Microsoft ever
  ships either a documented event-driven IRM trigger or a Graph/REST endpoint for the IRM audit log.
- [ ] VERIFY (pilot tenant): the exact format of the "Case ID" the Insider Risk Management Cases
  dashboard displays (numeric, GUID, or another scheme) — not documented by Microsoft beyond "The
  ID of the case." `irm-case-escalation-to-ediscovery`'s naming convention and scripts treat it as
  an opaque string throughout; confirming the format could enable format validation instead.
- [ ] VERIFY (pilot tenant): whether the portal's "Escalate for investigation" flow automatically
  adds the flagged user as a custodian with a hold applied, or leaves the new case empty — not
  documented either way by Microsoft. `irm-case-escalation-to-ediscovery/deploy/
  Confirm-EdiscoveryEscalationLink.ps1` doesn't assume an answer (design.md §3 explains why
  unconditional reconciliation is safe regardless), but confirming this would let the scenario's
  docs state the actual portal behavior instead of "unknown."

### Follow-ups discovered while building the eDiscovery Premium legal-hold-and-export scenario
- [x] Ground the exact `RecordType`/`Operations` values for eDiscovery hold-apply/hold-release/
  case-close/case-delete events in `Search-UnifiedAuditLog`, then add a dedicated
  `Export-EdiscoveryAuditTrail.ps1` to `premium-legal-hold-and-export/deploy/` — **built** (see
  DONE below): `RecordType Discovery` with `CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/
  `CaseRemoved` (case lifecycle) and `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` (hold-**policy** lifecycle), both grounded verbatim against
  Microsoft's "Audit log activities" eDiscovery reference. One genuine gap carried forward rather
  than resolved by guessing — see the new VERIFY item immediately below.
- [ ] VERIFY (pilot tenant): whether the `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` operations `Export-EdiscoveryAuditTrail.ps1` queries (confirmed for
  the case-level `ediscoveryHoldPolicy` object) also fire for `premium-legal-hold-and-export`'s own
  custodian-scoped `ediscoveryCustodian: applyHold`/`release` calls — a different object model. One
  Microsoft Learn page claims custodian holds are internally modeled as a "custodian hold policy"
  (suggesting yes); the only page describing a dedicated per-custodian audit search UI, and that
  "custodian hold policy" page itself, both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic eDiscovery experience's August 2025 retirement
  everywhere else — neither is confirmed for the current, non-legacy experience this scenario
  targets. Flagged inline in `deploy/Export-EdiscoveryAuditTrail.ps1`'s `.NOTES`,
  `README.md` §8, and `design.md` §8 rather than resolved by guessing, per `AGENTS.md` §4.
- [x] `scenarios/ediscovery/legal-hold-notifications/` — **investigated, not built** (see DONE
  below): the Premium custodian-communication workflow this item originally scoped was
  **permanently retired by Microsoft on August 31, 2025** and isn't available in the current
  eDiscovery experience — not merely unautomatable. `premium-legal-hold-and-export/README.md` §11
  and `design.md` §7 corrected in place instead of a companion scenario being built on the original
  (now-superseded) assumption.
- [ ] VERIFY (pilot tenant, before production reliance): whether the custodian `userSource`
  `includedSources` property accepts the combined string `"mailbox, site"` (Microsoft's own worked
  *beta*-namespace example) on the current *v1.0* `POST .../custodians/{id}/userSources` endpoint,
  whose own v1.0 worked example shows only a single value (`"mailbox"`) — flagged inline in
  `premium-legal-hold-and-export/README.md` §11 and `deploy/New-EdiscoveryPremiumLegalHold.ps1`'s
  `.NOTES` rather than resolved by guessing a JSON-array shape neither reference confirms.
- [x] Once `scenarios/insider-risk/` has a scenario producing an escalatable Insider Risk
  Management case, wire the documented IRM-case → eDiscovery (Premium) case escalation integration
  — **built** as `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` (see DONE below).

### Follow-ups discovered while building the eDiscovery location-scoped-legal-hold scenario
- [ ] VERIFY (pilot tenant, before pointing this at a distribution list you haven't already
  tested): whether a distribution list's own SMTP address is accepted as a `userSource.email`
  value on the v1.0 `ediscoveryHoldPolicy` endpoint and expanded server-side to member mailboxes.
  Corroborated by Microsoft's beta custodian-context userSource reference ("or the SMTP address of
  the group mailbox") and by the "Distribution group has too many members" (>1,000) error
  reference, but the v1.0, non-beta endpoint this scenario actually calls documents `email` only
  as "SMTP address of the user" — flagged inline in `location-scoped-legal-hold/README.md` §11,
  `design.md` §3, and `deploy/New-EdiscoveryLocationHold.ps1`'s `.NOTES`.
- [ ] VERIFY (pilot tenant): whether the `siteSource` list/create v1.0 response ever exposes a
  stable, directly comparable URL (rather than only `displayName`, the site's title) — if
  Microsoft adds one, replace `location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`'s
  and `validate/Test-EdiscoveryLocationHold.ps1`'s URL-slug-vs-title matching (the disclosed weak
  point in `design.md` §6) with a direct comparison instead.
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` — **built** (see DONE below): script
  resolving a Microsoft Teams/Microsoft 365 Group's own mailbox + SharePoint site
  (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` in Exchange Online PowerShell) into the userSource/
  siteSource pair `location-scoped-legal-hold`'s scripts already accept.
- [x] Reconcile the group-expansion member-cap discrepancy this build surfaced — **investigated and
  re-grounded, not merged into one figure** (see DONE below): both the 100-member and >1,000-member
  pages are current, non-legacy Microsoft Learn articles (the ">1,000" figure is not from an older
  page as originally suspected); Microsoft never states they're the same limit, so both scenarios now
  cite both figures explicitly and treat 100 as the conservative planning threshold, with the
  cross-code-path question kept as an open pilot-tenant VERIFY per `AGENTS.md` §4.
- [ ] `scenarios/ediscovery/roster-to-hold-locations/` (or fold into a future eDiscovery pass) —
  script the hand-off `teams-group-hold-resolution/design.md` §7 left manual: reading that
  scenario's `-ResolveMembers` roster CSV and appending the chosen members' mailbox addresses as
  new `userSources[]` entries in a `location-hold-definition.json`, once a human has decided
  individual member preservation (not just the group's own mailbox/site) is actually needed for a
  matter.
- [ ] Re-check whether `ediscoveryHoldPolicy: enablePolicy`/`disablePolicy` have been promoted from
  beta to v1.0 — as of this build they exist only in `/beta` (`location-scoped-legal-hold/
  design.md` §4), which is why that scenario's `Remove-EdiscoveryLocationHold.ps1` has no
  reversible "pause" stage. If promoted, add a reversible disable/re-enable rollback stage instead
  of only delete-one-source/delete-everything.

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
- [x] `scenarios/unified-catalog/link-glossary-terms-to-data-products/` — **superseded by**
  `scenarios/unified-catalog/manage-data-products/` (see DONE below), which creates a data
  product, wraps a `scan-azure-sql-and-classify`-scanned asset as a Unified Catalog data asset,
  and links both that asset and this scenario's `Customer`/`Customer ID` terms to it via the
  `Data Products - Create Relationship` operation.
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

### Follow-ups discovered while building the Unified Catalog manage-data-products scenario
- [ ] VERIFY (pilot tenant or the Swagger spec linked from the Unified Catalog API overview page):
  the exact `Data Products - Create Relationship` request body per `entityType` — the REST
  reference's only worked example (`entityType=CRITICALDATACOLUMN`) includes an `assetId` field
  this scenario's `DATAASSET`/`TERM` calls omit. Flagged inline in `manage-data-products/README.md`
  §11, `design.md` §3, and `deploy/New-DataProduct.ps1`'s `.NOTES` rather than resolved by
  guessing. Closing this would also let `scenarios/unified-catalog/link-glossary-terms-to-data-
  products/`-style critical-data-element/column linking be added with confidence.
- [ ] VERIFY (pilot tenant): whether the Unified Catalog `Data Products - Update` REST operation
  enforces the portal's "must configure a data access policy before Publish" business rule
  server-side, or whether that is a portal-UX-only guardrail this scenario's direct `PUT` call
  bypasses — flagged as a Red Team/CISO finding in `manage-data-products/reviews.md` and as a
  gating prerequisite in `README.md` §3, with a `Write-Warning` as the interim compensating
  control. No REST operation for configuring a data product access policy itself was found during
  this build's grounding pass (`design.md` §5) — that stays a portal-only manual step.
- [ ] `scenarios/unified-catalog/manage-critical-data-elements/` — script the `Critical Data
  Elements` operation group (create a CDE, map asset columns to it, the auto-linking-to-data-
  products behavior Microsoft documents) — explicitly out of scope in `manage-data-products/
  design.md` §6, which links only `DATAASSET` and `TERM` entity types.
- [ ] `scenarios/unified-catalog/manage-okrs/` — script the `Okr`/`Key Result` operation groups and
  link them to data products, closing the last `EntityCategory` gap `manage-data-products/design.md`
  §6 leaves open (OKR linking).
- [ ] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row with the
  confirmed `Data Products` and `Data Assets` operation groups/paths grounded in
  `manage-data-products` (`POST/PUT/DELETE/GET /datagovernance/catalog/dataProducts(|/{id})`,
  `.../dataProducts/{id}/relationships`, `.../dataAssets(|/{id})`, `.../dataAssets/query`, API
  version `2026-03-20-preview`) — same pattern `curate-business-glossary`'s and
  `end-to-end-lineage-validation`'s own automation-surface.md follow-ups already established of
  tracking doc extensions separately rather than bundling them into a scenario fragment.
- [ ] Once `scenarios/compliance-manager/` or a future access-governance scenario needs it,
  consider scripting **data product access policy** configuration if Microsoft publishes a REST
  surface for it — confirmed not to exist as of this build (`manage-data-products/design.md` §5);
  the REST API's own `Policies` operation group is a different feature (the RBAC authorization-
  policy engine), not the consumer-facing access-request workflow.

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
- [x] A Unified Catalog **data products** scenario (create/manage a data product, add data assets to
  it) is a shared, still-unbuilt dependency both `curate-business-glossary`'s and
  `rules-and-scorecards`' non-goals point to — **built** as
  `scenarios/unified-catalog/manage-data-products/` (see DONE below). `rules-and-scorecards`'s own
  `Create Data Source`/`computeId`-provisioning gap (above) is a separate, still-open item.

### Follow-ups discovered while building the Data Estate Insights classification-coverage-report scenario
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — extends
  `classification-coverage-report`'s exact pattern (paginated `Discovery - Query`, client-side tally,
  replace-by-`RunId` trend log) to the `label` field on the same `SearchResultValue` schema — **built**
  (see DONE below).
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

### Follow-ups discovered while building the Communication Compliance harassment-and-code-of-conduct scenario
- [ ] `scenarios/communication-compliance/financial-regulatory-supervision/` (or similar) — the
  FINRA/SEC-oriented "Regulatory compliance" policy template (Customer complaints, Gifts &
  entertainment, Money laundering, Regulatory collusion, Stock manipulation, Unauthorized
  disclosure classifiers) — a different regulatory driver (broker-dealer supervision) from
  `harassment-and-code-of-conduct`'s HR/code-of-conduct focus; explicitly called out as a non-goal
  in that scenario's `design.md` §7.
- [ ] Consider a `scenarios/insider-risk/` or `scenarios/adaptive-protection/` follow-up wiring the
  documented Communication Compliance → Insider Risk Management integration (the auto-created
  "Insider risk trigger" policy using the Threat/Harassment/Discrimination classifiers) — deferred
  from `harassment-and-code-of-conduct/design.md` §6 as a separate, deliberate opt-in rather than
  bundled into a standalone Communication Compliance policy.
- [ ] `scenarios/dspm-for-ai/` or `scenarios/communication-compliance/` — the "Detect Microsoft 365
  Copilot and Microsoft 365 Copilot Chat interactions" policy template (Prompt Shields/Protected
  material classifiers) and the preview LLM-based content-safety classifiers (Hate/Sexual/Violence/
  Self-harm, Teams/Viva Engage/Copilot-only) — both explicitly out of scope in
  `harassment-and-code-of-conduct/design.md` §4/§7 since this scenario's Exchange-inclusive scope
  needs the trainable-classifier family for full location coverage; the content-safety classifiers
  are candidates for a higher-accuracy, Teams/Viva-Engage-specific follow-up.
- [ ] VERIFY (portal, at deploy time, before a customer-facing deployment): the exact current-UI
  label for the "Harassment"/"Targeted harassment" trainable classifier — Microsoft's own docs use
  both names for what reads as the same classifier across different pages
  (`harassment-and-code-of-conduct/README.md` §11, `design.md` §4). Not resolved by guessing in
  this build per `AGENTS.md` §4.
- [ ] VERIFY (employment counsel, jurisdiction-by-jurisdiction): monitoring-notice/consent
  obligations for the Investigator-role full-content-visibility design in
  `harassment-and-code-of-conduct` — flagged as a gating prerequisite in that scenario's `README.md`
  §3/§11 (CISO lens finding in `reviews.md`) but is a legal determination outside this repo's
  grounding scope, not something this build can resolve.
- [ ] Re-check the EEOC's sub-regulatory harassment-guidance status before any customer-facing use
  of `harassment-and-code-of-conduct`'s regulatory-driver narrative (`README.md` §2/§11) — the 2024
  EEOC Enforcement Guidance on Harassment in the Workplace was rescinded by a 2–1 Commission vote on
  January 23, 2026, mid-way through this build's own grounding pass; the scenario's driver rests on
  the underlying Title VII statute and *Faragher*/*Ellerth* case law instead, but this area is
  actively moving and should be re-verified before every future sale referencing it.

### Follow-ups discovered while building the Audit premium-audit-investigation scenario
- [ ] `scenarios/audit/retention-policy-management/` — script **audit log retention policies** (a
  Premium feature: create/manage custom retention durations per record type/user via SCC PowerShell
  `New-/Set-UnifiedAuditLogRetentionPolicy`), the configuration counterpart to this read-only
  investigation scenario.
- [ ] `scenarios/audit/streaming-to-sentinel-or-management-api/` — continuous audit streaming via the
  Office 365 Management Activity API (or a Sentinel connector) for real-time detection, contrasted
  with this on-demand investigation in `audit/premium-audit-investigation/design.md` §7.
- [ ] VERIFY (pilot tenant): the exact `auditLogQueryStatus` terminal values (the runner polls
  defensively and flags this in `audit/premium-audit-investigation/README.md` §11), and the current
  crucial-events list / operation names for the compromise preset.
- [ ] Consider an **incident-response (mutating) companion** scenario — disable account, revoke
  sessions, remove malicious inbox rules — the deliberate response workflow this read-only
  investigation explicitly scopes out (`audit/premium-audit-investigation/design.md` §7).

### Follow-ups discovered while building the DLM retention-labels-financial-records scenario
- [ ] `scenarios/data-lifecycle-management/event-based-retention-and-disposition/` — event-based
  retention (`New-ComplianceTag -EventType`), `KeepAndDelete` with disposition review
  (`-ReviewerEmail`, multi-stage), and the disposition workflow — powerful RM features layered on the
  same cmdlets, non-goals of this starter (`design.md` §7). Overlaps the records-management starter.
- [ ] `scenarios/data-lifecycle-management/publish-labels-for-manual-application/` — a **publish**
  label policy (`New-RetentionComplianceRule -PublishComplianceTag`) so users can manually apply the
  financial-records label, complementing this scenario's auto-apply.
- [ ] `scenarios/data-lifecycle-management/adaptive-scope-retention/` — auto-apply/retention scoped by
  an **adaptive scope** (attribute-driven) instead of static locations, for large/dynamic estates
  (noted as out of scope here).
- [ ] Consider **file plan descriptors** (`-FilePlanProperty`: categories, citations, authorities,
  provisions) for a formal records file plan, and bulk label/policy creation via the documented CSV
  script (`bulk-create-publish-labels-using-powershell`).

### Follow-ups discovered while building the Information Barriers segregate-trading-and-research scenario
- [ ] `scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/` — enable IB
  for SharePoint/OneDrive (`Set-SPOTenant`) and associate segments to sites, the file-level half beyond
  the Teams wall (noted as an extension in this scenario's `design.md` §6 / `README.md` §11).
- [ ] `scenarios/information-barriers/allow-list-and-control-room-exceptions/` — model allow-list
  topologies (`-SegmentsAllowed`) and a control-room/compliance segment that must see both sides, the
  exception pattern real deployments need (non-goal here).
- [ ] Consider a multi-segment-mode migration note/scenario (Legacy → SingleSegment/MultiSegment) and
  address-book-policy / GAL segmentation as companions.

### Follow-ups discovered while building the Records Management regulatory-records-disposition scenario
- [ ] `scenarios/records-management/file-plan-bulk-import/` — bulk create a full file plan (retention
  schedule with citations, departments, authorities across many record classes) via the documented CSV
  import, the multi-class complement to this single representative class (non-goal here).
- [ ] `scenarios/records-management/multi-stage-disposition-review/` — model a multi-stage disposition
  panel (up to 5 stages / 10 reviewers each) using `-MultiStageReviewProperty` /
  `-ComplianceTagForNextStage`, for sign-off chains where one approver isn't enough (noted as a non-goal
  in this scenario's `design.md` §7).
- [x] `scenarios/records-management/graph-event-automation/` — **built** (see DONE): fire retention
  events from a business system via the Microsoft Graph records-management APIs
  (`retentionEvent`/`retentionEventType`, the modern path since the REST event API was deprecated), the
  automation complement to the PowerShell `New-ComplianceRetentionEvent` scenario (surface 2/3).
- [ ] `scenarios/records-management/disposition-proof-export/` — export proof-of-disposition and the
  disposition views for audit (Records Management → Disposition filter/export), closing the evidence
  loop this scenario's §7 references.
- [ ] Consider an adaptive-scope variant of the publish policy for large/dynamic estates (a cross-module
  follow-up shared with the DLM scenarios), and a records-vs-regulatory decision note linking this
  scenario with the DLM `retention-labels-financial-records` sibling.

### Follow-ups discovered while building the Data Map Azure SQL Managed Instance scenario
- [x] **Backport two corrected REST shapes into `scenarios/data-map/scan-azure-sql-and-classify/`.**
  — **built**, see DONE below.
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` — the next explicitly-flagged sibling in
  `scan-azure-sql-and-classify/design.md` §7's original list (Azure Synapse Analytics dedicated +
  serverless SQL pools) — **built** (see DONE below): reuses the proven object model, documents the
  genuine `kind`/auth/network differences Microsoft's own docs describe (registration per workspace
  with two optional SQL endpoints, a three-part serverless enumeration-authentication story, the
  distinct system scan rule set `AzureSynapseSQL`).
- [ ] `scenarios/data-map/scan-on-premises-sql-server-and-classify/` — the third sibling (on-premises
  SQL Server via self-hosted integration runtime), deferred from both this fragment and the original
  sibling scenario's non-goals — a materially different registration/auth story (no managed identity
  path at all; self-hosted IR is mandatory) worth its own careful grounding pass.
- [ ] `scenarios/data-map/verify-purview-entra-graph-prerequisites/` (or fold into a future Data Map
  hardening pass) — a Microsoft Graph-permissioned checker script confirming Directory Readers (or
  equivalent fine-grained Graph permission) membership for every Managed-Instance-backed Purview
  data source's managed identity, deferred from this scenario's `validate/
  Test-AzureSqlManagedInstanceDataMapScan.ps1` because that script's own auth surface (the Purview
  Data Map data-plane token) has no reason to also hold Graph directory-read permissions — flagged
  as a Blue Team finding in this scenario's `reviews.md`.
- [ ] VERIFY (pilot tenant): the exact TCP port a newly registered managed instance's public endpoint
  listens on. This scenario defaults `-Port` to `3342` (Microsoft's own worked *registration*
  example), but the actual port depends on the instance's connection-policy configuration
  (Redirect vs. Proxy) — flagged inline in `README.md` §11 and the deploy script's parameter help.
- [ ] Consider scripting `Set-AzSqlInstanceActiveDirectoryAdministrator` and the Directory Readers
  Microsoft Graph role-assignment step (the PowerShell pattern Microsoft publishes for it) instead
  of leaving both as manual portal/PowerShell prerequisites (`README.md` §5 steps 2–3) — deferred in
  this build to keep the fragment scoped to the Data Map REST surface itself, consistent with this
  repo's existing precedent of not automating rare, high-privilege, one-time setup steps that sit
  outside the automation identity's own Purview/Azure IAM role scope (see `design.md` §8).

### Follow-ups discovered while building the Data Estate Insights sensitivity-label-coverage-report scenario
- [ ] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — add a source-type-support
  check to `deploy/Export-SensitivityLabelCoverageReport.ps1`/`validate/
  Test-SensitivityLabelCoverageReport.ps1` that flags when a scoped `-CollectionId`/`-ObjectTypes`
  combination is outside Microsoft's documented Data Map sensitivity-label source-type list (Azure
  Blob Storage, ADLS Gen1/Gen2, SQL Server, Azure SQL Database, Azure SQL Managed Instance, Amazon S3,
  Amazon RDS (preview), Power BI), so a `0% labeled` reading for an unsupported source type isn't
  mistaken for a real governance gap — deferred from that scenario's build (flagged as a Red Team/Blue
  Team finding in `reviews.md`, and as a non-goal in `design.md` §7) because this build did not
  independently re-verify that supported-source list is complete/current enough to hard-code as a
  validation rule; needs a fresh grounding pass specifically on that list before encoding it.
- [ ] Once Microsoft's "Extend sensitivity labels to Data Map" capability reaches GA (it is Public
  Preview as of this build — `sensitivity-label-coverage-report/README.md` §3/§11), re-verify the
  `label` field/facet semantics on Discovery - Query still hold and drop the preview callout.
- [ ] Consider a `scenarios/information-protection/` or cross-cutting follow-up scripting the "extend
  sensitivity labels to Data Map" enablement itself (turning on the capability, scoping a label to
  "Files & other data assets") — left as a manual portal prerequisite in
  `sensitivity-label-coverage-report/README.md` §5 step 1/`design.md` §7, since this scenario only
  reads labels already applied, consistent with `classification-coverage-report`'s own non-goal of not
  building the scan it reports on.

### Follow-ups discovered while building the Data Map Azure Synapse Analytics scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/SDK grounding pass): the exact JSON shape of the
  `AzureSynapseWorkspaceMsiScan` object's optional `resourceTypes` property (seen only as an opaque
  `-ResourceType` parameter on the Az.Purview PowerShell module's `New-AzPurviewAzureSynapseWorkspaceMsiScanObject`
  cmdlet, with no worked example of its value) — `scan-azure-synapse-and-classify/deploy/
  New-AzureSynapseDataMapScan.ps1` omits the property entirely rather than guess a shape that could
  silently mis-scope the scan between dedicated and serverless pools. Flagged inline in the deploy
  script's `.NOTES`, `README.md` §6/§11, and `design.md` §5/§7.
- [ ] `scenarios/data-map/bulk-grant-synapse-serverless-access/` (or fold into a future Data Map
  hardening pass) — script to bulk-apply the per-serverless-database `CREATE LOGIN`/`CREATE USER`/
  `db_datareader` grants across every database in a workspace (e.g. iterating `sys.databases` via
  `Invoke-Sqlcmd`), closing the CISO-flagged per-database prerequisite-cost scaling noted in
  `scan-azure-synapse-and-classify/README.md` §3 and `reviews.md`.
- [ ] `scenarios/data-map/verify-synapse-serverless-enumeration-grants/` (or combine with the Managed
  Instance sibling's already-tracked `verify-purview-entra-graph-prerequisites/` follow-up into one
  broader SQL/Graph-permissioned checker) — a SQL-permissioned checker script confirming the serverless
  `CREATE LOGIN` and `db_datareader` grants exist per database, deferred from `scan-azure-synapse-and-
  classify/validate/Test-AzureSynapseDataMapScan.ps1` because that script's own auth surface (the
  Purview Data Map data-plane token) has no reason to also hold a SQL connection to the serverless
  endpoint — flagged as a Blue Team finding in that scenario's `reviews.md`.
- [ ] Consider scripting the **REST API + SQL Auth fallback** for a Synapse workspace whose "Allow
  Azure services and resources to access this workspace" firewall control cannot be enabled — deferred
  from `scan-azure-synapse-and-classify/design.md` §8 as a materially different auth/credential story
  (a Key Vault-backed SQL credential object, the same open portal-only credential-object gap both
  sibling Data Map scenarios already carry).

## DONE
- [x] **Reconcile the eDiscovery group-expansion member-cap discrepancy (100 vs. >1,000 members)**
  — twelfth **follow-up expansion** fragment (eDiscovery), a correctness/grounding correction rather
  than a new scenario, closing the item logged during the `teams-group-hold-resolution` build:
  "Microsoft's current 'Create holds in eDiscovery' page states... 100 members... a smaller... figure
  than the '>1,000 members' cap `location-scoped-legal-hold/design.md` §3 cites (from the older
  'Manage hold status errors' reference page)... Determine whether these describe the same underlying
  limit." Re-fetching both pages directly (`edisc-hold-create` and `edisc-hold-manage`) found the
  original premise wrong in one respect: the ">1,000" figure is **not** from an older or separate
  page — it lives in a still-current table ("Manage hold status errors") on the same, current, non-
  legacy "Manage holds in eDiscovery" article. Both figures are live simultaneously. Read literally,
  they describe two different pipeline moments: the **100-member** figure is the portal's own
  interactive data-source picker (checkbox enumeration of group members), documented for "every
  supported group type"; the **>1,000-member** figure is a **hold-application/retry** error
  ("Distribution group has too many members") surfaced on the Hold policy Details tab after a hold is
  applied, documented specifically for distribution groups. Microsoft's text never cross-references
  the two or states they're the same limit measured twice — so this was **not** resolved by picking
  one as "the current figure" (neither superseded the other). Instead: `location-scoped-legal-hold/
  design.md` §3 was rewritten with the full re-grounded analysis and a new reference (R11, the
  `edisc-hold-create` "Create a hold" section); `README.md` §8 and §11 now cite both figures
  side-by-side, name **100 members** as the conservative KPI/planning threshold (the smaller number,
  tied to "every supported group type"), and keep the >1,000-member error string as the specific
  documented failure condition to watch for by name; the deploy script's `.NOTES` and the sample
  `location-hold-definition.json`'s inline comment were updated to match.
  `teams-group-hold-resolution/README.md` §11/§12, `design.md` §6, and `deploy/
  Resolve-TeamsGroupHoldLocations.ps1`'s `.NOTES` were updated in step, including a new reference
  ([[10]], the "Manage hold status errors" page) that scenario's citation list was previously missing.
  Both scenarios' `reviews.md` got a short follow-up four-lens round (all four lenses Pass, no
  Fix/Fail — a precision improvement to already-disclosed content, not a new capability or risk
  surface). The underlying question — which limit, if either, governs this scenario's own
  REST-driven `userSources` expansion path (neither the portal picker nor confirmed to be the same
  code path as the documented error) — remains an explicit, open pilot-tenant VERIFY in both
  scenarios rather than resolved by guessing, per `AGENTS.md` §4. Grounded via the Microsoft Learn
  MCP tool (direct fetch of `purview/edisc-hold-create` and `purview/edisc-hold-manage`,
  2026-09-04) — no cmdlet, endpoint, or product behavior was fabricated to close this gap. —
  2026-09-04
- [x] **Investigate and correct: automatic Power Automate/webhook trigger for IRM case escalation**
  — eleventh **follow-up expansion** fragment (Insider Risk Management / eDiscovery), a correctness
  correction rather than a new scenario, closing the item logged during the original
  `irm-case-escalation-to-ediscovery` build ("consider a Power Automate flow … that automatically
  runs `Confirm-EdiscoveryEscalationLink.ps1` right after an investigator completes … 'Escalate for
  investigation' … deferred because [it] wasn't independently grounded"). Grounding this pass found
  the original README.md §8 wording ("a Power Automate flow triggered on escalation") overstated
  what Microsoft documents: the custom-flow "For a selected Insider Risk Management case" trigger is
  manually selected and run from the same Cases-dashboard **Automate** toolbar the investigator just
  used to escalate — not an event-driven subscription — and none of the five documented Purview-
  connector actions available to a custom IRM flow (Get alert/case/user/alerts-for-case, Add case
  note) can invoke an external script; doing so would need a generic, non-Purview HTTP/Azure-
  Automation action on top, which Microsoft's own docs flag as potentially needing extra Power
  Automate licensing. The other plausible automation path — polling the dedicated **Insider Risk
  Management audit log** instead of the case itself — was also checked and is not available either:
  Microsoft states that log "isn't associated with the Microsoft 365 audit log," is portal-view/CSV-
  export only, and has no documented Graph/REST endpoint (`Search-UnifiedAuditLog` doesn't cover it).
  Corrected `irm-case-escalation-to-ediscovery/README.md` §8 (rewrote the KPI bullet to present the
  scheduled poll as the only unattended option and the Power Automate path as a manually-invoked,
  one-click convenience rather than automatic, with the premium-connector licensing caveat), §11 (new
  Known Limitations bullet), and §12 (two new citations); `design.md` (new §5 documenting the
  finding, a new §4 non-goal, two new references); `reviews.md` (a follow-up four-lens round — Red
  Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail — confirming the correction itself is
  sound). No code changed — there was nothing to build once the "automatic trigger" premise the
  original item was scoped around didn't hold up under grounding; writing a Power Automate flow
  anyway would have shipped a control that doesn't do what its name implies, which is exactly the
  failure mode this correction exists to prevent. Grounded via the Microsoft Learn MCP tool
  (`insider-risk-management-cases#case-actions` for the toolbar-invocation walkthrough;
  `insider-risk-management-settings-power-automate` for the custom-flow trigger/action/licensing
  detail; `insider-risk-management-audit-log` for the IRM audit log's independence from the unified
  audit log and its portal-only access) — per `AGENTS.md` §4, no cmdlet, endpoint, or product
  behavior was fabricated to fill the gap this item originally left open. — 2026-09-04
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` — tenth **follow-up expansion** fragment
  (eDiscovery), closing the item logged during the `location-scoped-legal-hold` build: "resolving
  *which* group/site pair to use from a Team name is a distinct, separately scoped lookup this
  fragment doesn't automate." Full README (12-section skeleton), design.md (grounds the surface
  split — Exchange Online PowerShell for resolution, Microsoft Graph only for the optional
  reconciliation stage — against this library's existing EXO-primary-script precedent rather than
  the Graph-only sibling scenario's pattern; explicit non-goals for member expansion, private
  channels, and DL resolution), deploy/ (`Resolve-TeamsGroupHoldLocations.ps1` — Stage 1 always
  runs: idempotent/parameterized `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` resolution (Exchange
  Online PowerShell, surface 1; caller must already be connected, matching
  `premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`'s convention) writing a
  `userSources[]`/`siteSources[]` JSON fragment in the exact shape
  `location-scoped-legal-hold/deploy/policy/location-hold-definition.json` uses, plus an optional
  member-roster CSV (informational only, never auto-added to a hold); Stage 2 (`-AddToHold`,
  opt-in) self-connects to Microsoft Graph (surface 3) and idempotently reconciles each resolved
  location onto an existing hold policy, duplicating (not dot-sourcing) the sibling scenario's own
  `Confirm-UserSource`/`Confirm-SiteSource` find-or-create logic, `$PSCmdlet.ShouldProcess()`-gated
  throughout for a true `-WhatIf`), validate/ (`Test-TeamsGroupHoldLocations.ps1` — read-only
  group-drift check always, plus an optional hold-reconciliation check scoped to just this
  scenario's own resolved groups), rollback.md (Stage 1: delete two local files, no tenant effect;
  Stage 2: defers entirely to the sibling scenario's own `Remove-EdiscoveryLocationHold.ps1` rather
  than duplicating a second removal implementation), four-lens reviews.md (Red Team Fix round
  resolved — a missing-SharePoint-site rollup warning so the gap is visible without reading
  interleaved per-group output, a `deploy/out/` default output directory instead of the tracked
  `deploy/config/` to keep a real run's resolved values and the PII-bearing member roster out of
  git history, and a real `Set-StrictMode`-under-optional-JSON-property bug caught and fixed during
  review (`$groupDef.resolveMembers` would have thrown for any config that omitted the documented-
  optional key) — two further items confirmed already correctly scoped, not changed; Blue Team Fix
  round resolved — same code changes as the Red Team detectability findings; CISO Pass — the
  asymmetric over-preserve/under-preserve risk reasoning for why this scenario needs no removal-side
  counsel gate of its own; Product Owner Pass — confirmed leaner Graph module dependency than the
  sibling scenario (no typed `Microsoft.Graph.Security` cmdlet needed for attach-only reconciliation
  against an already-existing case/hold), confirmed the EXO/Graph connection-pattern split is
  deliberate and documented rather than an unexplained inconsistency) — grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` Exchange PowerShell
  reference pages for exact syntax/role requirements; "Create holds in eDiscovery" direct-fetched in
  full for the "Preserve content in Microsoft Teams"/"Microsoft 365 groups" worked example, the
  group-membership point-in-time-snapshot behavior, and the 100-member group-expansion cap; "Manage
  holds in eDiscovery" for the hold-management-context restatement of the same Teams/group guidance;
  "Microsoft 365 Group behaviors and provisioning options" for the confirmed `ProvisionSiteOnDemand`
  site-provisioning-deferral option) — two items recorded as explicit VERIFY rather than resolved by
  guessing (no canonical SLA for `SharePointSiteUrl` populating after group creation; the 100-vs-
  >1,000-member cap discrepancy against the sibling scenario's own citation, logged above as a new
  follow-up to reconcile), per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` — third scenario in this repo's
  Azure-SQL-family Data Map series (after `scan-azure-sql-and-classify` and
  `scan-azure-sql-managed-instance-and-classify`), closing the explicitly-flagged sibling item from
  the Managed Instance scenario's own follow-up backlog. Registers an Azure Synapse Analytics
  **workspace** (not a single database) as a Purview Data Map source, with the dedicated and/or
  serverless SQL pool endpoints as two optional properties on one `AzureSynapseWorkspace` data source
  object, and configures an `AzureSynapseWorkspaceMsi` SAMI-authenticated scan against it using the
  system default `AzureSynapseSQL` scan rule set. Full README (12-section skeleton, an up-front callout
  distinguishing this workspace-based data source from Microsoft's separate, older standalone
  "dedicated SQL pool (formerly SQL DW)" source), design.md (a `design.md` §4 diff table against both
  sibling scenarios covering the three-part serverless enumeration-authentication story, the
  firewall-or-SQL-Auth-fallback distinction, and the portal's single "SQL Database" scan Type), deploy/
  (`New-AzureSynapseDataMapScan.ps1` / `Remove-AzureSynapseDataMapScan.ps1` — idempotent, parameterized,
  `-WhatIf` throughout, reusing the generic Data Sources/Scans/Triggers/Scan Result REST call shapes the
  Managed Instance sibling scenario already confirmed by direct fetch, with Synapse-specific `kind`/body
  properties independently confirmed via the Az.Purview PowerShell module's own worked examples),
  validate/ script, four-lens reviews.md (Red Team Fix round resolved — Storage Blob Data Reader
  over-scoping risk and the silent external-table coverage gap; Blue Team Fix round resolved — the
  serverless-enumeration-login validate-script gap explained rather than left silent; CISO Fix round
  resolved — per-database prerequisite cost scales with workspace database count, unlike either sibling
  scenario's fixed one-time cost; Product Owner Fix round resolved — distinguished this scenario's
  workspace-based data source from Microsoft's separate, older standalone dedicated-SQL-pool source) —
  grounded in Microsoft Learn (`register-scan-synapse-workspace`'s full registration/scan/permissions
  workflow, fetched via a verified byte-for-byte mirror after direct `learn.microsoft.com` fetches
  returned `EGRESS_BLOCKED` throughout this build; the Az.Purview PowerShell module's
  `New-AzPurviewAzureSynapseWorkspaceDataSourceObject`/`-MsiScanObject` cmdlet references, fetched via
  GitHub raw source, for the `kind` and property names; `register-scan-azure-synapse-analytics` and
  `data-governance-private-endpoints-managed-virtual-network` for the two Product Owner/limitations
  citations). One property (the scan object's optional `resourceTypes`) could not be independently
  confirmed to an exact JSON shape and is deliberately omitted rather than guessed — flagged as an
  explicit VERIFY in `README.md` §11 and `design.md` §5, with three new follow-ups recorded below
  rather than resolved by guessing, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — ninth **follow-up
  expansion** fragment (Data Estate Insights), closing the item logged during the
  `classification-coverage-report` build: extend that scenario's exact pattern (paginated Discovery -
  Query, client-side tally, replace-by-`RunId` trend log) to the `label` field on the same
  `SearchResultValue` schema. Full README (12-section skeleton, Public Preview callout up front per
  this repo's established pattern for the upstream "extend sensitivity labels to Data Map" preview
  dependency), design.md (five design goals mirroring the sibling scenario's own, plus a fifth,
  label-specific consideration — labels surfaced through this extension are metadata-only, not
  enforced protection), deploy/ (`Export-SensitivityLabelCoverageReport.ps1` — idempotent/
  parameterized Purview Data Map Discovery - Query REST automation (surface 4, API version
  `2023-09-01`, independently re-confirmed via direct fetch for this build) applying the sibling
  scenario's already-reviewed client-side-tally design to the `label` field/facet instead of
  `classification`; `-Mode Full`/`-Mode Facets`, replace-by-`RunId` trend log, manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf`), validate/ script (identical file-integrity + optional
  live-reconciliation check structure, `label`-specific column names), four-lens reviews.md (Red Team
  Fix round resolved — found and flagged a genuine new risk the sibling scenario didn't have: a
  `0% labeled` reading is ambiguous between "unprotected" and "source type doesn't support Data Map
  labeling at all," closed via README/design additions rather than a guessed validation rule; Blue
  Team Fix round resolved — operability guidance for the same ambiguity, a self-contained incident-
  response runbook, and explicit file-naming non-collision with the sibling scenario; CISO Fix round
  resolved — the review's most consequential finding: sensitivity labels surfaced via this Data Map
  extension are metadata-only per Microsoft's own FAQ (no encryption, no content marking, no DLP), so
  a high `PercentLabeled` must never be presented as "this data is protected" — added as an explicit
  callout in README §2/§11 and design.md §1 before this scenario's output could be handed to a board
  without risk of a false-assurance narrative; Product Owner Fix round resolved — corrected the native
  report's name from `PROGRESS.md`'s own loose paraphrase ("Labeling insights") to Microsoft's actual
  current name, "Classic sensitivity labels" report) — grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (a direct fetch of the Discovery - Query REST reference confirming the `label`
  response field (`string[]`) and the `label` facet as one of exactly four documented facets, and
  confirming no worked exact-value `label` filter example exists (only `classification` does);
  Understand the classic sensitivity labels report in Unified Catalog; Understand the classic assets
  report; Access control in Data Estate Insights within Microsoft Purview; Learn about sensitivity
  labels in Data Map (preview) and its FAQ, including the licensing-tier list and the metadata-only/
  no-encryption/no-DLP confirmations; Understand the Microsoft Purview Data Estate Insights
  application) — one gap (the source-type-support check) recorded as a follow-up rather than resolved
  by guessing, per `AGENTS.md` §4 — 2026-09-04

- [x] `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` — eighth **follow-up expansion**
  fragment (Insider Risk Management / eDiscovery), closing the item logged during the
  `premium-legal-hold-and-export` build: "once `scenarios/insider-risk/` has a scenario producing
  an escalatable IRM case [it now does — `departing-employee-data-theft`], wire the documented
  IRM-case → eDiscovery (Premium) case escalation integration." Full README (12-section skeleton),
  design.md (grounds why the escalation trigger itself has no Graph/PowerShell API — portal-only,
  same shape as several other no-write-API Purview surfaces this library documents — and why the
  `ediscoveryCase` resource's `description` field, its only free-text property, is the correct,
  non-fabricated place to stamp a provenance link back to the source IRM case/alerts, since the
  resource has no source/origin field of any kind), deploy/
  (`Confirm-EdiscoveryEscalationLink.ps1` — idempotent/parameterized Microsoft Graph automation
  (surface 3) that finds the already-escalated eDiscoveryCase by a documented naming convention
  (`IRM-<Case ID>-<UPN local part>`, this repo's own convention, not Microsoft's), best-effort
  resolves declared IRM alert IDs via `Get-MgSecurityAlertV2 -AlertId` for a human-readable
  record, stamps a delimited, idempotent provenance block onto the case description via
  `Update-MgSecurityCaseEdiscoveryCase`, and unconditionally reconciles the flagged user as a
  custodian with a mailbox+OneDrive hold using the identical find-or-create/`applyHold` pattern as
  the sibling `premium-legal-hold-and-export` scenario (duplicated, not dot-sourced, per this
  repo's self-contained-deploy-tree convention); `Remove-EdiscoveryEscalationLink.ps1` — staged
  rollback (strip the provenance block → optionally release the hold, counsel-gated, identical to
  the sibling scenario's own gate) that never closes/deletes the case itself, deferring to the
  sibling scenario's own rollback script for that; a JSON escalation-link definition file), validate/
  (`Test-EdiscoveryEscalationLink.ps1` — read-only PASS/WARN/FAIL checks of case existence,
  provenance-block presence *and* content match against the definition file, custodian/userSource/
  hold state, and best-effort alert resolution), four-lens reviews.md (Red Team Fix round resolved
  — found and fixed a real idempotency gap during review: the initial draft treated "a provenance
  block already exists" as "done," which would have silently left a *different* escalation's
  provenance stamped on a case whose name was accidentally reused; fixed by comparing the existing
  block's IRM case ID/user against the current run before skipping, throwing on a mismatch unless
  a new `-Force` switch is passed, and even then appending rather than overwriting so no prior
  provenance record is ever destroyed; Blue Team Fix round resolved — added an explicit
  escalation-to-automation trigger gap callout (README §8) and severity discipline to the validate
  script's alert-resolution check; CISO Pass; Product Owner Fix round resolved — reworded several
  passages that had implied a stronger native Microsoft linkage than is actually documented) —
  grounded in Microsoft Learn via the Microsoft Learn MCP tool (`insider-risk-management-cases`'s
  full "Escalate for investigation" portal walkthrough and system-generated-note behavior, the
  `ediscovery` legacy-solutions page's IRM-integration summary, the `ediscoveryCase` resource type
  and its Update operation directly fetched to confirm `description` is the only writable
  free-text field and that no source/origin field exists, and `Get-MgSecurityAlertV2`'s PowerShell
  reference directly fetched to confirm the `-AlertId` get-by-ID parameter set before using it) —
  three items recorded as explicit VERIFY rather than resolved by guessing (the IRM "Case ID"
  dashboard field's exact format; whether the portal escalation flow auto-provisions a
  custodian/hold; alert-metadata staleness after re-triage), per `AGENTS.md` §4 — 2026-09-04
- [x] **Investigate `scenarios/ediscovery/legal-hold-notifications/` — closed without building a
  scenario** — seventh **follow-up expansion** fragment (eDiscovery), a correctness correction
  rather than a new scenario. The original follow-up (logged during the
  `premium-legal-hold-and-export` build) assumed the Premium custodian-communication workflow
  (initial notice, reminders, escalations, acknowledgment tracking) was a live, portal-driven-only
  Purview feature with no Graph write API — the same shape as several other no-write-API surfaces
  this library already documents (Communication Compliance, Compliance Manager). Re-grounding for
  this fragment found something different: Microsoft's current, non-legacy-banner "Manage hold
  notifications" page states in an `Important` callout that legal hold custodian communications
  were **permanently retired on August 31, 2025** and aren't available in the new eDiscovery
  experience. The two walkthrough pages this follow-up would otherwise have built a portal runbook
  from ("Create a legal hold notice," "Work with communications in eDiscovery (Premium)") both
  carry the classic-experience/21Vianet-China-only caution banner rather than current guidance — a
  detail easy to miss if only the feature-comparison table on the legacy `ediscovery` overview page
  is checked, since the *current* `edisc-permissions` RBAC page still lists a "Communication" role
  for eDiscovery Manager/Administrator (stale documentation debt, not evidence the feature survived
  — the explicit retirement callout on the more specific, current "Manage hold notifications" page
  is the higher-confidence source and the one this correction relies on). No companion scenario was
  built, since there is no current-experience feature left to document or automate. Instead:
  corrected `premium-legal-hold-and-export/README.md` §11 (replaced the "portal-driven, no API"
  characterization with the retirement finding, the concrete consequence that
  `ediscoveryCustodian.acknowledgedDateTime`/`releasedDateTime` should be expected to stay null in
  the current experience rather than read as a live signal, and a recommendation to treat
  notice-and-acknowledgment as an external, non-Purview process until Microsoft ships a
  replacement) and its `.NOTES`-equivalent §12 reference list (added reference 28);
  `design.md` §7's non-goal bullet and References (added R12); a short follow-up four-lens review
  round in `reviews.md` (Red Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail) confirming the
  correction is itself sound rather than a new unverified claim. Grounded via the Microsoft Learn
  MCP tool (`ediscovery-manage-hold-notifications`'s retirement callout — the decisive source;
  `ediscovery-create-hold-notification` and `ediscovery-managing-custodian-communications` for the
  now-legacy workflow's own shape, both banner-flagged; the current, non-legacy `edisc` feature-
  comparison table, which has no "legal hold notifications" row at all, corroborating the
  retirement; the current, non-legacy `edisc-permissions` RBAC table, whose still-present
  "Communication" role was deliberately *not* treated as evidence to the contrary). No code written
  — there was nothing left to script once the underlying feature was confirmed retired, and writing
  a scenario anyway would have violated `AGENTS.md` §4's no-fabrication rule by presenting a dead
  feature as current guidance — 2026-09-04
- [x] **Backport: corrected Run Scan / List Scan History REST shapes into
  `scenarios/data-map/scan-azure-sql-and-classify/`** — sixth **follow-up expansion** fragment
  (Data Map, Data Governance), a correctness fix rather than a new scenario, per the item the
  `scan-azure-sql-managed-instance-and-classify` build logged: that sibling build independently
  direct-fetched the canonical Microsoft Learn **Scan Result - Run Scan** and **Scan Result - List
  Scan History** REST reference pages this scenario's own build could not reach, and found both of
  this scenario's reconstructed shapes were genuinely wrong, not just unverified. Corrected both:
  (1) `deploy/New-AzureSqlDataMapScan.ps1`'s `-RunNow` path now sends the confirmed action-style
  `POST {endpoint}/scan/datasources/{ds}/scans/{scan}:run?runId={guid}&scanLevel={level}&
  api-version=...` instead of the unconfirmed resource-style `PUT .../runs/{runId}` it previously
  sent (verb changed from `Put` to `Post`, URI changed to the colon-suffixed action form); (2)
  `validate/Test-AzureSqlDataMapScan.ps1`'s scan-history check now reads the confirmed nested
  `discoveryExecutionDetails.statistics.assets.discovered`/`.classified` fields instead of the
  unconfirmed flat `.assetsDiscovered`/`.assetsClassified` properties it previously read. Updated
  `design.md` (§5 sequence diagram + prose narrowing the still-open VERIFY to Data Sources/Triggers
  only), `README.md` (§6 config-reference row, §11 — replaced the three-way Data
  Sources/Triggers/Run-Scan VERIFY with a RESOLVED entry for the two corrected shapes plus a
  narrower two-item VERIFY for Data Sources/Triggers alone, §12 added reference 17, footer VERIFY
  count corrected from three to two), and `reviews.md` (a targeted four-lens follow-up pass on the
  correction itself — Red Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail, explicitly
  noting the Blue Team's original review-round mitigation for the *unconfirmed* shape now becomes a
  true error-handler rather than a shape-guess mask). No code executed against a live tenant
  (author-only reference code per `AGENTS.md` §5); both scripts hand-verified line-by-line against
  the sibling scenario's independently-confirmed shapes rather than executed, since `pwsh` is not
  available in this build environment. Two narrower VERIFY items remain open on this scenario (Data
  Sources/Triggers body shapes for the `AzureSqlDatabase` kind; the unrelated custom-scan-rule-set
  and credential-object REST-creation gaps, unchanged) — not resolved by this fragment and not
  claimed to be, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`
  — fifth **follow-up expansion** fragment (eDiscovery), closing the item that scenario's `README.md`
  §8/`reviews.md` (Red Team finding 1) tracked from its original build: no independent audit trail
  for who released a hold or closed/deleted a case. Grounded (Microsoft Learn MCP tool + WebSearch)
  the exact `RecordType`/`Operations` values rather than fabricating them: `RecordType Discovery`
  with two confirmed `Operation` sets from Microsoft's own "Audit log activities" eDiscovery
  reference — case lifecycle (`CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/`CaseRemoved`)
  and hold-**policy** lifecycle (`HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync`). Added `deploy/Export-EdiscoveryAuditTrail.ps1` (idempotent,
  parameterized Exchange Online PowerShell automation, surface 1 — rolling CSV merge de-duplicated
  by a composite key hashing the full `AuditData` JSON payload, same mechanism as
  `scenarios/compliance-manager/assess-against-iso27001/`'s and
  `scenarios/communication-compliance/harassment-and-code-of-conduct/`'s own audit-trail scripts;
  optional `-CaseName` client-side filter parsed from each record's `AuditData` JSON to scope a
  tenant-wide trail to one matter; `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still
  runs the read-only queries; `Write-Warning` on `CaseRemoved`/`HoldRemoved` rows) and
  `validate/Test-EdiscoveryAuditTrail.ps1` (automated CSV schema/de-duplication/operation-value/
  sort-order checks needing no tenant connection). Updated `README.md` §5 (script-path step 7), §6
  (configuration reference row), §8 (rewrote the "Audit visibility" subsection from "not grounded,
  tracked as a follow-up" to the grounded design plus the one genuine remaining gap), and §12
  (three new citations); `design.md` (new §8, plus three new `R9`–`R11` references) and `reviews.md`
  (a follow-up four-lens pass on the addition itself: Red Team/Blue Team/CISO/Product Owner all
  Pass, no Fix/Fail) and `rollback.md` (audit-log-entries note updated to name the new script).
  **One real gap deliberately not resolved by guessing** — whether those hold-policy `Operation`
  values also cover this scenario's own custodian-scoped `applyHold`/`release` calls (a different
  object from the case-level `ediscoveryHoldPolicy` the operations are documented against) is
  unconfirmed for the current, non-legacy eDiscovery experience: the one Microsoft Learn page
  describing per-custodian audit search, and the page claiming custodian holds are internally
  modeled as a "custodian hold policy," both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic experience's August 2025 retirement everywhere else
  — recorded as an explicit pilot-tenant VERIFY in this file (above), the script's own `.NOTES`,
  `README.md` §8, and `design.md` §8, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-map/scan-azure-sql-managed-instance-and-classify/` — fourth **follow-up
  expansion** fragment (Data Map, Data Governance), closing one of the three sibling-scan-scenario
  items `scan-azure-sql-and-classify/design.md` §7 explicitly scoped out (Azure SQL Managed
  Instance, Azure Synapse Analytics, on-premises SQL Server): full README (12-section skeleton,
  every delta from the sibling scenario's prerequisites/config/architecture called out explicitly
  rather than silently re-derived), design.md (§3 grounds why this is a separate scenario rather
  than a `-SourceKind` flag on the sibling script; §4 is a single source-of-truth diff table; §5
  documents this build's own grounding-quality improvement over the sibling — direct fetches of all
  four canonical REST reference pages succeeded where three of the sibling's four failed at build
  time, surfacing two real, previously-unconfirmed shape corrections), deploy/
  (`New-AzureSqlManagedInstanceDataMapScan.ps1` — idempotent/parameterized Purview Data Map REST
  automation (surface 4) reusing the sibling's create-or-replace pattern for the
  `AzureSqlDatabaseManagedInstance` data source and `AzureSqlDatabaseManagedInstanceMsi`
  SAMI-authenticated scan (distinct `kind` values, a `tcp:<fqdn>,<port>` server-endpoint format, and
  a different system scan-rule-set name from the sibling scenario), optional recurring trigger,
  `-WhatIf` throughout; `Remove-AzureSqlManagedInstanceDataMapScan.ps1` — staged trigger/scan/
  data-source removal mirroring the sibling's rollback shape; `deploy/policy/
  azure-sql-mi-datamap-scan.json` — reference copy of all four REST bodies, each body's `$comment`
  flagging where its shape came from a direct fetch this build performed itself), validate/
  (`Test-AzureSqlManagedInstanceDataMapScan.ps1` — read-only config + scan-history check reading the
  corrected nested asset-count fields), rollback.md (the sibling's three-stage procedure plus a
  fourth, Managed-Instance-specific stage for the tenant-wide Directory Readers role grant, framed as
  a deliberately-manual, Privileged-Role-Administrator-gated step outside this scenario's own
  automation), four-lens reviews.md (Red Team Fix round resolved — the public endpoint's larger
  network exposure than the sibling's firewall toggle made explicit with a private-endpoint
  recommendation, and a Directory Readers membership-drift monitoring gap closed; Blue Team Fix
  round resolved — explained why Directory Readers membership isn't part of the automated validate
  script (a different auth surface than the rest of the script needs) rather than leaving it an
  unexplained gap, and added two Managed-Instance-specific incident-response causes; CISO Fix round
  resolved — the Privileged-Role-Administrator cross-team coordination cost made explicit as a
  distinct adoption-friction dimension from the sibling scenario's own three same-team
  prerequisites; Product Owner Fix round resolved — separated the registration `-Port` parameter
  from the NSG network-path port requirement, citing Microsoft's October 2025 Redirect-becomes-
  default-inside-Azure connection-policy change) — grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (register-scan-azure-sql-managed-instance's full register/scan/prerequisites
  sections including the public-endpoint and Directory-Readers requirements; the Entra
  authentication configuration guide's Managed-Instance-specific admin/Directory-Readers/contained-
  user sections, `CREATE USER ... FROM EXTERNAL PROVIDER` syntax quoted directly; the Azure SQL
  Managed Instance connection-types and connectivity-architecture articles for the October 2025
  Redirect-default change and the Proxy/Redirect NSG port tables; the data-source-readiness-
  checklist article's AzureSQLMI-specific network/RBAC checklist; and — the headline grounding
  improvement over the sibling scenario — direct fetches of all four canonical REST reference pages
  (Data Sources - Create Or Replace, Scans - Create Or Replace, Triggers - Create Or Replace, Scan
  Result - Run Scan / List Scan History) at API version `2023-09-01`, which the sibling scenario's
  own build could not reach for three of the four and had reconstructed from SDK/PowerShell
  signatures instead — two of those reconstructed shapes turned out to not match the confirmed
  contract (Run Scan's action-style POST; List Scan History's nested asset-count fields), corrected
  here and logged as a backport follow-up rather than silently repeated) — two items recorded as
  explicit VERIFY rather than resolved by guessing (the default public-endpoint port; the
  `AzureSqlDatabaseManagedInstanceCredential` credential-object REST creation gap, carried over
  unchanged from the sibling scenario), per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/ediscovery/location-scoped-legal-hold/` — third **follow-up expansion** fragment
  (eDiscovery), closing the item `premium-legal-hold-and-export/design.md` §3/§7 explicitly scoped
  out: the `ediscoveryHoldPolicy` (`POST .../legalHolds`) path for a hold organized around a
  *location* (a shared departmental mailbox, a regulatory-sweep distribution list, a SharePoint
  site) rather than a named custodian. Full README (12-section skeleton), design.md (grounds why
  this is a genuinely separate v1.0 object model — narrower `userSource` shape (`mailbox`-only,
  siteSources split out as their own collection, unlike the custodian shape's combined `"mailbox,
  site"` string), the distribution-list-expansion evidence trail (a beta reference documenting
  group-mailbox support + the "Distribution group has too many members" >1,000 error, vs. the v1.0
  endpoint's own narrower "SMTP address of the user" wording), and the headline finding that
  `enablePolicy`/`disablePolicy` exist only in the beta namespace — v1.0 has no reversible
  "turn off and keep for later," only delete-one-source or delete-the-whole-policy, both
  Microsoft-documented as capable of **permanently deleting content currently being preserved**),
  deploy/ (`New-EdiscoveryLocationHold.ps1` — reuses the sibling scenario's typed
  `New-MgSecurityCaseEdiscoveryCase` cmdlet for the case, then `Invoke-MgGraphRequest` against the
  v1.0 REST endpoints directly for the hold policy/userSources/siteSources/retryPolicy, since no
  v1.0 typed cmdlet exists for any of them (only `Microsoft.Graph.Beta.Security` has one); a
  hand-rolled `$PSCmdlet.ShouldProcess()` gate around every write for a true `-WhatIf`; an optional
  `-Retry` that calls `retryPolicy` only when the policy reports errors or an unhealthy source; an
  optional `-WaitForApplied` poll switch (added during Blue Team review to mirror the sibling
  scenario's `-WaitForHold`); a loud `Write-Warning` when `contentQuery` is left blank (added
  during Red Team review — an unfiltered hold on every location's content); `Remove-
  EdiscoveryLocationHold.ps1` — release one or more named userSources/siteSources, or `-DeleteHold`
  for the entire policy, both paths carrying Microsoft's own permanent-deletion warning quoted
  verbatim rather than softened; `deploy/policy/location-hold-definition.json` — a Payments-team
  shared mailbox + compliance distribution list + SharePoint site, `contentQuery` scoped to a CID
  date range), validate/ (`Test-EdiscoveryLocationHold.ps1` — read-only checks of the case, hold
  policy, every declared userSource/siteSource's `holdStatus`, the policy's own `errors`
  collection, and a `WARN` on a blank `contentQuery`), rollback.md (the two-stage release-one/
  delete-all procedure with the counsel-confirmation gate promoted to a `README.md` §3 gating
  prerequisite from the outset, applying the precedent the sibling scenario's own CISO review round
  established), four-lens reviews.md (Red Team Fix round resolved — sharpened the
  distribution-list-expansion VERIFY with a concrete pilot-tenant verification step rather than a
  generic caveat, added the blank-`contentQuery` warning, confirmed the `siteSource`
  title-matching weak point never risks holding the *wrong* site's content, only an idempotency
  false-positive/negative on this scenario's own bookkeeping; Blue Team Fix round resolved — added
  `-WaitForApplied` and the blank-`contentQuery` `WARN`, confirmed `retryPolicy`'s
  restamp-everything behavior was already correctly disclosed as a deliberate, human-triggered
  action; CISO Pass — confirmed the counsel-confirmation gate and the higher-stakes
  no-reversible-pause framing were both already applied proactively in the initial draft; Product
  Owner Pass — independently re-confirmed the beta-only enable/disable finding via direct fetches
  of the v1.0 resource/update references and both beta action pages, and called out the
  `mailbox`-only `userSource` finding as *more* directly grounded than the sibling scenario's own
  open VERIFY on the same property family) — grounded in Microsoft Learn via the Microsoft Learn
  MCP tool (`ediscoveryHoldPolicy` v1.0 resource/create/update/delete/retryPolicy references;
  `userSource`/`siteSource` v1.0 resource + create + delete references for the `legalHolds`
  context specifically, distinct from the custodian-context ones the sibling scenario cites; the
  beta `enablePolicy`/`disablePolicy` action pages confirming no v1.0 equivalent exists; the beta
  custodian-context `userSource` create reference for the group-mailbox-email corroboration; and
  "Manage holds in eDiscovery" for the portal-side hold-policy-states, retry/turn-off/delete
  procedures with their permanent-deletion warnings quoted verbatim, the full "Manage hold status
  errors" table, and the Teams/Microsoft 365 Group hold-placement guidance) — two real gaps
  (distribution-list expansion on the exact v1.0 endpoint; `siteSource` URL-vs-title matching)
  recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md` §4.
  (2026-09-04)
- [x] `scenarios/unified-catalog/manage-data-products/` — second **follow-up expansion** fragment
  (Unified Catalog, Data Governance), closing the shared "Data Products scenario doesn't exist yet"
  dependency both `curate-business-glossary`'s and `data-quality/rules-and-scorecards`'s non-goals
  pointed to: full README (12-section skeleton), design.md (grounds the choice of the newly-added
  2026-03-20-preview `Data Assets` operation group over the raw Data Map/Atlas entity API, and the
  distinction between the REST API's `Policies` operation group — the RBAC authorization-policy
  engine — and the portal's unrelated "data product access policy" feature), deploy/
  (`New-DataProduct.ps1` — idempotent/parameterized Purview Unified Catalog REST automation
  (surface 4) plus a Microsoft Graph owner-resolution call (surface 3, reusing
  `curate-business-glossary`'s UPN→Entra-object-ID pattern) that create-or-updates a "Customer
  Master Data" data product in an existing governance domain, wraps the `scan-azure-sql-and-
  classify`-scanned `customerdb.dbo.Customers` Data Map asset as a Unified Catalog data asset
  (`POST dataAssets` with `source.assetId`, idempotent via the `sourceAssetIds` Query filter), and
  links both that asset and the `Customer`/`Customer ID` glossary terms to the product via `Data
  Products - Create Relationship`, list-before-create idempotent; `-Publish` gate with a loud
  pre-publish warning naming the portal-only data-product-access-policy prerequisite Microsoft's
  own docs require before Publish; `Remove-DataProduct.ps1` — staged unpublish (default) →
  `-RemoveLinks` (delete both relationships, never the shared asset wrapper or terms) →
  `-Purge` (delete the data product; `-DeleteDataAssetWrapper` opt-in and explicitly unchecked
  against orphaning another product's link); `deploy/config/
  customer-master-data-product.sample.json`), validate/ (`Test-DataProduct.ps1` — read-only checks
  of the product's fields/status, the data asset wrapper (reporting its Data-Map-sourced
  classifications as a live cross-check into `scan-azure-sql-and-classify`'s own output), and both
  relationships), four-lens reviews.md (Red Team Fix round resolved — publish-gate-bypass risk
  elevated to a loud warning + README gating prerequisite, orphan-wrapper-deletion risk confirmed
  unfixable in tooling and documented instead, domain-scoped-role risk inherited by reference from
  `curate-business-glossary`; Blue Team Fix round resolved — classification-report and
  access-request-backlog scope boundaries clarified as portal-only, not scripting gaps; CISO Fix
  round resolved — PAYG cost-activation contrast stated locally in §10, access-governance narrative
  sharpened, publish-gate VERIFY promoted to a tracked finding; Product Owner Fix round resolved —
  closed a near-miss conflation of the REST `Policies` group with the portal's access-policy
  feature before it shipped, documented the portal-vs-REST `type` enum label mismatch, independently
  confirmed the newer Data Assets surface and the bulk-import-avoidance reasoning) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (Unified Catalog API overview + release notes
  confirming Data Assets/Data Columns as newly added in `2026-03-20-preview`; the Data Products and
  Data Assets REST operation groups directly fetched — Create/Update/Delete/Get/List/Query/Create
  Relationship/List Relationships/Delete Relationship for both, plus Data Assets' `sourceAssetIds`
  Query filter; Create and manage data products, incl. the exact Publish-gating prerequisite
  quote; Manage data product access policies; Master data management in Microsoft Purview's
  five-step register→create→link→curate flow this scenario automates; Data governance roles and
  permissions for Data Product Owner; data governance billing + FAQ for the per-governed-asset PAYG
  trigger; the `Policies - List` operation's own worked example, directly inspected to rule out
  conflating it with the portal's access-policy feature) — the Create Relationship body-shape
  ambiguity and the publish-gate server-side-enforcement question both recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4. (2026-09-04)
- [x] `scenarios/records-management/graph-event-automation/` — first **follow-up expansion** fragment
  (Records Management, Microsoft Graph surface 2/3), the automation complement to the PowerShell
  regulatory-records-disposition scenario: full README (12-section skeleton), design.md, deploy/
  (`New-GraphRetentionEvent.ps1` — `Invoke-MgGraphRequest` against the v1.0 records-management API that
  ensures a retention **event type** exists via GET/POST `/security/triggerTypes/retentionEventTypes`
  (create-or-report by displayName, `@odata.nextLink` paging) and — **double-gated** behind `-FireEvent`
  **and** config `event.fire=true`, always through `$PSCmdlet.ShouldProcess` (real `-WhatIf`) — fires a
  retention **event** via POST `/security/triggers/retentionEvents` (`eventQuery` files/messages +
  AssetID/keywords, `eventTriggerDateTime`, `retentionEventType@odata.bind`), reporting Graph-native
  `eventStatus`/`eventPropagationResults`; `Remove-GraphRetentionEvent.ps1` — deletes matching event
  records and, with `-DeleteEventType`, the event type, with the loud note that deleting an event does
  NOT stop retention already started; `deploy/config/graph-event-automation.sample.json` — Contract
  Expiration event type + asset-ID-scoped event with `fire=false`), validate/
  (`Test-GraphRetentionEvent.ps1` — read-only GET checks of the event type + report of fired events and
  per-workload propagation), four-lens reviews.md (Red Team Fix round resolved — scoped events,
  double-gated + ShouldProcess fire, high-privilege app identity, deletion-isn't-undo; Blue Team Fix
  round resolved — per-workload propagation reporting, nextLink paging, real `-WhatIf`; CISO Fix round
  resolved — auditable automated triggering; Product Owner Fix round resolved — doc quirks
  (`@odata.bind` singular/plural, `eventQuery`/`eventQueries`) flagged) — grounded in Microsoft Learn
  (records-management API overview, create retentionEvent/retentionEventType, eventQuery, permission
  `RecordsManagement.ReadWrite.All`, typed cmdlets `New-MgSecurityTriggerTypeRetentionEventType` /
  `New-MgSecurityTriggerRetentionEvent` verified); uses Microsoft's supported path (REST event API
  deprecated), a fired event is treated as irreversible. (2026-09-04)
- [x] `scenarios/records-management/regulatory-records-disposition/` — seventh Risk & Compliance
  scenario (Records Management), a genuinely distinct records-management lifecycle vs. the DLM sibling:
  full README (12-section skeleton), design.md, deploy/ (`New-RecordsDisposition.ps1` — SCC PowerShell
  (surface 1) that builds the *event-anchored* disposition lifecycle: `New-ComplianceRetentionEventType`
  → `New-ComplianceTag -RetentionType EventAgeInDays -RetentionAction KeepAndDelete -EventType
  -ReviewerEmail -IsRecordLabel` (event-based record label ending in a **disposition review**, not
  auto-delete) → `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule -PublishComplianceTag`
  (**publish**, not auto-apply) → **gated** `New-ComplianceRetentionEvent` created only with
  `-TriggerEvent` **and** config `event.create=true` because a triggered event is irreversible;
  create-or-report idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud
  warnings on the two irreversible edges (triggered event can't be cancelled; applied record label
  can't be deleted) and on un-scoped events / missing reviewer; `Remove-RecordsDisposition.ps1` —
  disable publish policy by default, `-Delete` removes policy/rule and *attempts* (reports, never
  forces via `-ForceDeletion`) label + event-type removal; `deploy/config/records-disposition.sample.json`
  — Contract Expiration event type + event-based record label + publish policy + asset-ID-scoped event
  with `create=false`), validate/ (`Test-RecordsDisposition.ps1` — read-only Get-* checks of event
  type, label action/type/event-binding/record-flag/reviewer, publish policy enabled + locations, rule
  `PublishComplianceTag`, and an informational report of already-triggered events), four-lens reviews.md
  (Red Team Fix round resolved — asset-ID-scoped events, gated irreversible trigger, reviewer-required
  disposition, governed teardown; Blue Team Fix round resolved — event-triggered reporting, separate
  Disposition Management RBAC, working `-DryRun`; CISO Fix round resolved — examiner-grade schedule
  reproducibility; Product Owner Fix round resolved — limits/latency/immutability documented) — grounded
  in Microsoft Learn (event-driven-retention, disposition, New-ComplianceTag/-ComplianceRetentionEventType/
  -ComplianceRetentionEvent with Get/Remove `-Identity` verified, `-PublishComplianceTag`); this
  **completes a starter scenario for every Purview module** — remaining work is the follow-up expansion
  backlog above. (2026-09-04)
- [x] `scenarios/information-barriers/segregate-trading-and-research/` — sixth Risk & Compliance
  scenario (Information Barriers), and the last remaining Risk & Compliance **starter** (every module
  now has a starter scenario): full README (12-section skeleton), design.md, deploy/
  (`New-TradingResearchBarrier.ps1` — SCC PowerShell (surface 1) that builds an ethical wall:
  `New-OrganizationSegment` per side from an Entra attribute filter + two one-way
  `New-InformationBarrierPolicy -SegmentsBlocked` policies created **-State Inactive**, and — only with
  `-Activate` — `Set-InformationBarrierPolicy -State Active` + `Start-InformationBarrierPoliciesApplication`;
  safe-by-default (staged inactive, no user impact until explicit activation); create-or-report
  idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud live-communication-impact
  warnings; `Remove-TradingResearchBarrier.ps1` — staged deactivate → `-Apply` to lift the wall →
  `-Delete` policies + segments, with the deactivation-needs-application trap called out;
  `deploy/config/trading-research-barrier.sample.json` — Trading/Research segments + both block pairs),
  validate/ (`Test-TradingResearchBarrier.ps1` — read-only Get-* checks of both segments, both block
  policies + assignment + Active state (`-RequireActive`), and application status), four-lens reviews.md
  (Red Team Fix round resolved — both-direction + mutually-exclusive-segment wall, safe-by-default
  activation + no-collateral test, app-only/non-IB edges, governed deletion; Blue Team Fix round
  resolved — application-status detection + `-RequireActive`, deactivation-needs-apply trap, working
  `-DryRun`; CISO Fix round resolved — examiner-grade reproducibility; Product Owner Fix round resolved
  — IB modes/timings documented) — grounded in Microsoft Learn (Get started with Information Barriers:
  segments/block-policies/apply + one-policy-per-segment + two-one-way-policies pattern, multi-segment
  IB modes and limits, New-OrganizationSegment / New-InformationBarrierPolicy /
  Start-InformationBarrierPoliciesApplication references, IB attributes, SharePoint IB enablement + 24h
  propagation, Teams block behavior, troubleshooting) — no invented cmdlets; activation's
  live-communication impact treated as a first-class safety constraint, per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/data-lifecycle-management/retention-labels-financial-records/` — fifth Risk &
  Compliance scenario (Data Lifecycle / Records Management): full README (12-section skeleton),
  design.md, deploy/ (`New-FinancialRecordsRetention.ps1` — SCC PowerShell (surface 1) that creates a
  **regulatory record** retention label (`New-ComplianceTag -Regulatory $true -RetentionAction Keep
  -RetentionDuration 2555 -RetentionType CreationAgeInDays` — SEC 17a-4-style WORM immutability, a
  PowerShell-only capability the portal hides), an **auto-apply** label policy
  (`New-RetentionCompliancePolicy` with finance SharePoint location), and the rule binding them
  (`New-RetentionComplianceRule -ApplyComplianceTag -ContentMatchQuery`); **create-or-report**
  idempotency via Get-* (never silently mutates high-consequence retention objects); custom `-DryRun`
  (S&C `-WhatIf` non-functional); loud irreversibility warnings; `Remove-FinancialRecordsRetention.ps1`
  — staged disable → `-Delete` policy/rule, and `-TryRemoveLabel` that reports the expected refusal for
  a regulatory record in use rather than forcing it; `deploy/config/
  financial-records-retention.sample.json`), validate/ (`Test-FinancialRecordsRetention.ps1` —
  read-only Get-* checks of label action/duration/record flags, policy enabled + locations +
  distribution status, and the rule's applied label), four-lens reviews.md (Red Team Fix round
  resolved — over-scoping guardrails (dry-run, narrow query, lab-test + Records/Legal sign-off),
  least-restrictive-control ladder, create-or-report + no force-release of records; Blue Team Fix round
  resolved — working `-DryRun`, auto-apply latency/RetryDistribution/DistributionStatus, validate
  pre-flight; CISO Fix round resolved — irreversibility as a governance gate; Product Owner Fix round
  resolved — PowerShell-only regulatory records + the retention-strength ladder documented) — grounded
  in Microsoft Learn (New-ComplianceTag / New-RetentionCompliancePolicy / New-RetentionComplianceRule
  references incl. -Regulatory/-IsRecordLabel/-RetentionAction/-RetentionType/-ApplyComplianceTag,
  records-management immutability semantics, auto-apply latency/limits, retention cmdlets overview) —
  a deliberately conservative scenario given regulatory records are irreversible; no invented cmdlets,
  per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/audit/premium-audit-investigation/` — fourth Risk & Compliance scenario (Audit
  Premium), a **read-only forensic investigation** built on the **Microsoft Graph Audit Search API**
  (v1.0 `security` namespace, surface 3): full README (12-section skeleton), design.md, deploy/
  (`Invoke-AuditInvestigation.ps1` — an async investigation runner via `Invoke-MgGraphRequest`:
  `POST /security/auditLog/queries` to create the search job from a JSON config (target UPNs, time
  window via `lookbackDays` or explicit ISO dates, a crucial-events `operationFilters` preset,
  optional record-type/keyword/IP filters), polls `GET .../queries/{id}` until a terminal status
  (defensive running-set exclusion + `succeeded`-like check, bounded `-PollTimeoutMinutes`),
  retrieves `GET .../queries/{id}/records` with `@odata.nextLink` paging, and exports CSV (key
  fields) + JSON (full `auditData`) with a top-operations summary; `-WhatIf` previews the query body
  without creating the job; read-only — no tenant mutation; `deploy/config/
  audit-investigation.sample.json` — an account-compromise crucial-events preset (MailItemsAccessed
  [Premium], Send/SendAs, New-/Set-InboxRule, Add-MailboxPermission, FileDownloaded,
  AnonymousLinkCreated, UserLoggedIn/UserLoginFailed, role/user changes)), validate/
  (`Test-AuditInvestigation.ps1` — Graph connectivity + `AuditLogsQuery*` scope + config validation
  + a live 1-hour probe query proving API/permission/audit availability), rollback.md (read-only:
  no tenant state to undo — focuses on securing/disposing the exported evidence and the 30-day
  auto-retained job), four-lens reviews.md (Red Team Fix round resolved — export-as-evidence
  handling, least-privilege service-scoped permissions, read-only/no-tamper posture, ingestion-lag
  false-negative warning; Blue Team Fix round resolved — async polling + paging, triage
  summary/runbook, live readiness probe; CISO Fix round resolved — defensibility/breach-clock
  foregrounded; Product Owner Fix round resolved — Graph async API over classic
  Search-UnifiedAuditLog, status-enum VERIFY) — grounded in Microsoft Learn (auditing solutions
  overview + Standard-vs-Premium capability comparison + service description for crucial events and
  retention tiers, the Audit Search Graph API create/get/list-records references incl. body filters
  and the recordType enum and AuditLogsQuery permission set, audit-search ingestion-latency/job
  limits, and the classic Search-UnifiedAuditLog caps) — the `auditLogQueryStatus` terminal values
  and current crucial-events list recorded as explicit VERIFY items rather than fabricated, per
  `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/ediscovery/premium-legal-hold-and-export/` — first eDiscovery-module scenario,
  and the first Risk & Compliance scenario in this repo built against a Purview surface with a
  **rich, fully app-only-supported write API** (the opposite grounding challenge from
  `assess-against-iso27001`/`harassment-and-code-of-conduct`, which had none): full README
  (12-section skeleton; a promoted §3 gating prerequisite requiring counsel confirmation before
  any hold release, added during the CISO review round), design.md (grounds the mandatory
  Graph-not-S&C-PowerShell choice across Microsoft's own "app-only auth for eDiscovery cmdlets is
  unsupported" statement, explains the two-separate-API authoring-vs-download architecture, and
  documents the deliberate choice of custodian-scoped `applyHold` over the sibling
  `ediscoveryHoldPolicy` location-scoped hold object), deploy/ (`New-EdiscoveryPremiumLegalHold.ps1`
  — idempotent/parameterized Microsoft Graph automation (surface 3, `microsoft.graph.security`
  v1.0 namespace) that finds-or-creates an eDiscovery (Premium) case, custodians, and their
  mailbox+OneDrive userSources, then applies hold, using every Graph SDK cmdlet's native
  `SupportsShouldProcess` for a true `-WhatIf` dry run rather than a hand-rolled one;
  `New-EdiscoverySearchReviewSetExport.ps1` — finds-or-creates a case-custodian-scoped search,
  commits it to a review set via the asynchronous `addToReviewSet` `caseOperation`, and starts an
  export, polling both long-running operations against the exact v1.0 `caseOperationStatus` enum
  rather than assuming synchronous completion or reusing beta-namespace casing;
  `Get-EdiscoveryExportPackage.ps1` — a parameterized, idempotent (skip-if-already-downloaded)
  adaptation of Microsoft's own published `DownloadExportUsingAppCert.ps1` reference script for
  the *separate*, non-Graph Purview eDiscovery download API and its own `MSAL.PS` token;
  `Remove-EdiscoveryPremiumLegalHold.ps1` — staged rollback (release named custodian(s) → close
  case → delete case, each stage behind its own explicit switch) using the confirmed v1.0
  `ediscoveryCustodian: release` action and `caseStatus` enum; a JSON case/custodian/search/
  reviewSet/export definition file all four scripts share as the single source of truth), validate/
  script (`Test-EdiscoveryPremiumCaseSetup.ps1` — read-only, `eDiscovery.Read.All`-only checks of
  case/custodian/hold-status/userSource/search/review-set state, plus an opt-in export-age check
  against the documented 30-day download window), rollback.md (four explicit stages from
  targeted-custodian release through permanent case deletion, with an up-front warning that
  releasing a hold before the preservation duty lapses can itself be a spoliation event), four-lens
  reviews.md (Red Team Fix round resolved — added an audit-visibility subsection to README.md §8
  naming the gap in per-actor hold-release/case-lifecycle history and pointing to
  `Search-UnifiedAuditLog` as the correct channel rather than fabricating the exact eDiscovery
  audit RecordType/Operations values, and flagged that a custodian's mailbox+OneDrive hold does
  not cover Teams channel messages without an added non-custodial data source; Blue Team
  clarifications — confirmed the weekly validate-script review cadence and the download-step's own
  status check already mitigate the async-timeout risk raised; CISO Fix round resolved — promoted
  the legal-counsel-confirmation-before-hold-release requirement from `rollback.md` alone to a
  gating README §3 prerequisite; Product Owner Pass — independently re-confirmed the
  Graph-not-S&C-PowerShell finding, verified the one cmdlet name inferred by naming-pattern analogy
  (`New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource`) actually exists before citing it, and
  confirmed strict v1.0-vs-beta namespace discipline throughout) — grounded in Microsoft Learn via
  the Microsoft Learn MCP tool (`edisc-hold-create`, `edisc-settings-cases`/`-general`,
  `edisc-permissions` including its app-only-auth-unsupported section,
  `edisc-ref-api-guide`/`security-ediscovery-appauthsetup` for the full two-API app-only setup
  sequence and the published PowerShell download-script examples this repo's
  `Get-EdiscoveryExportPackage.ps1` adapts, `edisc-cases-manage`, `edisc-search-add-to-review-set`,
  `edisc-review-set-export` (including the official-not-just-community-sourced 30-day download-
  window statement), `edisc-hold-report`, `edisc-ref-limits`, `edisc-billing`, `ediscovery`'s
  Standard/Premium capability comparison, and eleven-plus REST/PowerShell reference pages directly
  fetched at v1.0 — `ediscoveryCase`, `ediscoveryCustodian` (including its `applyHold`/`release`/
  `activate` action set), `ediscoveryHoldPolicy`, `ediscoverySearch`, `ediscoveryReviewSet`
  (`addToReviewSet`/`export`), `caseOperation` (confirming the exact `caseOperationStatus` enum
  distinct from beta's casing/shape), and the `New-`/`Get-`/`Add-`/`Export-`/`Update-`/`Remove-`
  `MgSecurityCaseEdiscoveryCase*` PowerShell cmdlet family) — one REST-shape ambiguity (the
  `userSource.includedSources` combined-string form) recorded as an explicit VERIFY rather than
  resolved by guessing, per `AGENTS.md` §4 — 2026-09-04

- [x] `scenarios/communication-compliance/harassment-and-code-of-conduct/` — first Communication
  Compliance-module scenario, and the second scenario in this repo (after
  `scenarios/compliance-manager/assess-against-iso27001/`) built against a Purview surface with
  **no write API** — Microsoft's own docs state "PowerShell isn't supported for creating and
  managing Communication Compliance policies" verbatim on two independently-fetched pages: full
  README (12-section skeleton, an up-front scope note explaining why this scenario's shape differs
  from the DLP/Information Protection scenarios, a promoted gating prerequisite for
  employment-counsel monitoring-notice review), design.md (grounds the no-write-API finding across
  two independently-fetched Microsoft Learn pages plus the legacy `New-SupervisoryReviewPolicyV2`
  cmdlet's continued-but-unsupported presence in the module reference, explains the Investigators-
  vs-Analysts reviewer-role choice, and documents why a custom keyword dictionary was scoped to
  evasion/concealment phrases rather than duplicating classifier-covered profanity/slurs), deploy/
  (a reference-only, explicitly non-executable `communication-compliance-policy-manifest.json` for
  the portal-driven policy-creation runbook — the same pattern `assess-against-iso27001` and
  `departing-employee-data-theft` already established for other no-write-API Purview surfaces —
  plus a genuinely uploadable `code-of-conduct-evasion-phrases.txt` custom keyword dictionary, and
  the one genuinely scriptable piece: `Export-CommunicationComplianceAuditTrail.ps1`, idempotent/
  parameterized Exchange Online PowerShell automation (surface 1) that runs three separate
  `Search-UnifiedAuditLog` queries mirroring Microsoft's own three distinct worked-example
  RecordType/Operations shapes — `SupervisionRuleMatch` alone, `RecordType Discovery` +
  `SupervisionPolicyCreated`/`Updated`/`Deleted`, and `RecordType AeD` + `SupervisoryReviewTag` —
  rather than guessing a single unified query covers all five operation values, merging into a
  rolling CSV de-duplicated by a composite key hashing the full `AuditData` JSON payload;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only queries and
  reports would-be merge counts), validate/ script (`Test-CommunicationComplianceAuditTrail.ps1` —
  automated CSV schema/de-duplication/category/operation/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the policy's existence/scope/classifiers/
  reviewers/anonymization/notice-template/storage-limit health, none of which have a read API
  either), rollback.md (staged pause → revoke access → delete for the portal-only policy, a
  dedicated note on the separate, non-deletable User-reported messages system policy, and the
  audit-trail script's independent schedule/CSV/role rollback), four-lens reviews.md (Red Team Fix
  round resolved — flagged that publishing a real tenant's exact keyword-dictionary contents
  undermines it, distinguished the non-transcribed-Teams-meeting gap from the general off-platform
  limitation, and elevated storage-limit auto-deactivation to an actively-monitored KPI rather than
  a background fact; Blue Team Fix round resolved — added an explicit phased-pilot-before-All-users
  rollout recommendation; CISO Fix round resolved — promoted the monitoring-notice/consent VERIFY
  item from a Known Limitations footnote to a gating README §3 prerequisite; Product Owner Fix round
  resolved — re-confirmed the Harassment/Targeted-harassment naming inconsistency, the correct
  exclusion of preview content-safety classifiers for Exchange coverage, and the correct exclusion of
  custom trainable classifiers, which Communication Compliance doesn't support) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (communication-compliance-solution-overview,
  -policies, -plan, -configure, -permissions, -investigate-remediate, -siem, -reports-audits,
  -alerts-best-practices, audit-log-activities' Communication compliance activities table,
  Search-UnifiedAuditLog and New-SupervisoryReviewPolicyV2 reference pages, and the Microsoft
  Purview service description's Communications Compliance licensing table) plus WebSearch grounding
  for the regulatory driver (Title VII/*Faragher*/*Ellerth* case-law framework, and — caught mid-
  build — the EEOC's January 23, 2026 rescission of its 2024 sub-regulatory harassment guidance,
  which changed this scenario's citation from "current EEOC guidance" to "rescinded guidance;
  statute and case law still stand," tagged VERIFY per `AGENTS.md` §4 rather than left stale) —
  2026-09-04

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
