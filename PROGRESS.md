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

### Data Security (highest sales value — front-load)
- [ ] `scenarios/insider-risk/departing-employee-data-theft/`
- [ ] `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/`
- [ ] `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/`

### Data Governance
- [ ] `scenarios/data-map/scan-azure-sql-and-classify/`
- [ ] `scenarios/unified-catalog/curate-business-glossary/`
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

## DONE
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
