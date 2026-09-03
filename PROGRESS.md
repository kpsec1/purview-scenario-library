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

### Cross-cutting (do first)
- [ ] `docs/automation-surface.md` — Graph + PowerShell/EXO/S&C connection patterns, auth, module install
- [ ] `docs/glossary.md` — canonical terms

### Data Security (highest sales value — front-load)
- [ ] `scenarios/dlp/pci-teams-exfil-block/` — TEMPLATE scenario, full quality (others copy this)
- [ ] `scenarios/information-protection/auto-label-confidential-sharepoint/`
- [ ] `scenarios/dlp/endpoint-dlp-usb-block/`
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

## DONE
- [x] repo scaffold — AGENTS.md, README, PROGRESS, LICENSE, .gitignore, CONTRIBUTING — 4a79558 — 2026-09-02
- [x] `docs/licensing-matrix.md` — two-model (per-user + PAYG) licensing matrix, grounded in MS Learn — 2026-09-02
- [x] `docs/rbac-model.md` — four-RBAC-system model (Entra, Purview role groups, Data Governance, Exchange Online) + admin units + PowerShell/Graph auth patterns, grounded in MS Learn — 2026-09-03

## Blocked / needs user
- (none)
