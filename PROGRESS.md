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

### Data Governance
- [ ] `scenarios/data-quality/rules-and-scorecards/`
- [ ] `scenarios/data-lineage/end-to-end-lineage-validation/`
- [ ] `scenarios/data-estate-insights/classification-coverage-report/`

### Risk & Compliance
- [ ] `scenarios/compliance-manager/assess-against-iso27001/`
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

## DONE
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
