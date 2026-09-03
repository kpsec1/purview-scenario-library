# Microsoft Purview Scenario & Automation Library

A commercial-grade, vendor-ready library covering **every Microsoft Purview module**. For each
module it ships a systematic catalog of real-world **scenarios**, and every scenario delivers
both **documentation** and **working automation code** (PowerShell / Microsoft Graph, IaC, and
ready-to-import policy definitions).

Each scenario is independently reviewed from four perspectives — **Red Team, Blue Team, CISO,
and Microsoft Product Owner** — so what ships is attack-tested, operable, fundable, and correct.

> **Status:** in active build. See [`PROGRESS.md`](PROGRESS.md) for live coverage. This is a
> knowledge-and-code product; code is authored to run in the buyer's own tenant (never auto-run
> here) and always ships with a dry-run path.

---

## Module coverage

**Data Governance** — Data Map · Unified Catalog · Data Estate Insights · Data Quality · Data Lineage
**Data Security** — Information Protection · DLP · Insider Risk Management · Adaptive Protection · DSPM for AI
**Risk & Compliance** — Compliance Manager · Communication Compliance · eDiscovery · Audit · Data Lifecycle Management · Records Management · Information Barriers
**Cross-cutting** — Licensing matrix · RBAC model · Graph/PowerShell automation surface · Migration

See the live coverage matrix in [`PROGRESS.md`](PROGRESS.md).

## How each scenario is structured

```
scenarios/<module>/<scenario-slug>/
├── README.md      # summary, drivers, prerequisites, steps (portal + script), config, validation, ops, rollback, cost, gotchas, refs
├── design.md      # architecture + decisions + data flow (Mermaid)
├── deploy/        # idempotent, parameterized code: *.ps1, *.bicep|*.tf, policy/*.json
├── validate/      # verification scripts (safe to re-run)
├── rollback.md    # clean undo
└── reviews.md     # Red / Blue / CISO / MS-Product-Owner assessment
```

## Repository conventions

- **Build workflow & authoring rules:** [`AGENTS.md`](AGENTS.md)
- **State / backlog:** [`PROGRESS.md`](PROGRESS.md) — single source of truth for what's next
- **Contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Product facts are grounded in Microsoft Learn; no invented cmdlets or blade paths.

## License

Proprietary — see [`LICENSE`](LICENSE). All rights reserved.
