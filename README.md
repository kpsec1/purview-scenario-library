# Microsoft Purview Scenario & Automation Library

*A hundred-plus ways Purview actually gets deployed — not fifteen slides in a deck.*

Every module. Every failure mode. Every regulatory driver. Documented and shipped as working
PowerShell, reviewed from four angles before anything counts as done.

**[View the styled homepage →](docs/homepage.html)**

> Built scenario by scenario by Krunal Patel — free and MIT-licensed —
> [krunalpatel.ca@outlook.com](mailto:krunalpatel.ca@outlook.com)

---

## Why this exists

Most Purview content stops at the reference architecture. This doesn't. Every scenario here
ships as documentation *and* runnable automation — parameterized, idempotent, with a dry-run
path — because that's the gap I kept running into: a clean architecture diagram and no script I
could actually hand to a team.

I build it one scenario at a time: ground the facts in Microsoft's own documentation, write the
code, then argue with it from four different angles — how it gets bypassed, how it gets
operated, whether I'd fund it, whether Microsoft would call it correct — before it ships. It's
free for any business, MSSP, or practitioner to use — no license fee, no gated content — because
the point is to be genuinely useful to the Purview community, not to sell it.

> **Status:** in active build. See [`PROGRESS.md`](PROGRESS.md) for live coverage. This is a
> knowledge-and-code resource; code is authored to run in *your own* tenant (never auto-run here)
> and always ships with a dry-run path.

---

## The numbers

| | |
|---|---|
| **103** | scenarios shipped |
| **18** | Purview modules covered |
| **4** | review lenses, every scenario |
| **0** | invented cmdlets — unverified facts get tagged `VERIFY`, not guessed |

## What's covered

Eighteen Purview modules, organized the way Microsoft organizes them:

**Data Governance** — Data Map (9) · Unified Catalog (6) · Data Estate Insights (3) · Data Quality (2) · Data Lineage (2)
**Data Security** — DLP (18) · Insider Risk Management (10) · Information Protection (4) · Adaptive Protection (6) · DSPM for AI (3) · Data Security Investigations (1)
**Risk & Compliance** — Data Lifecycle Management (9) · eDiscovery (8) · Compliance Manager (6) · Records Management (5) · Communication Compliance (4) · Audit (4) · Information Barriers (3)
**Cross-cutting** — Licensing matrix · RBAC model · Graph/PowerShell automation surface · Migration

See the live coverage matrix in [`PROGRESS.md`](PROGRESS.md).

## How every scenario ships

Same six files, every time. No scenario is "done" until all six exist and the review below has
no open findings.

```
scenarios/<module>/<scenario-slug>/
├── README.md      # summary, drivers, prerequisites, steps (portal + script), config, validation, ops, rollback, cost, gotchas, refs
├── design.md      # architecture + decisions + data flow (Mermaid)
├── deploy/        # idempotent, parameterized code: *.ps1, *.bicep|*.tf, policy/*.json
├── validate/      # verification scripts (safe to re-run)
├── rollback.md    # clean undo
└── reviews.md     # Red / Blue / CISO / MS-Product-Owner assessment
```

## How it's reviewed

Before a scenario counts as finished, I argue with it from four seats at the table:

1. **Red Team** — how this gets bypassed: policy exceptions, coverage gaps, the unmonitored egress path.
2. **Blue Team** — is it detectable and operable: alerts, signal-to-noise, the runbook someone actually follows at 2am.
3. **CISO** — risk reduction against cost, licensing spend, change-management impact: would I actually fund this.
4. **Microsoft Product Owner** — right feature for the job, current with Microsoft's own direction, nothing deprecated or reinvented.

## Repository conventions

- **Build workflow & authoring rules:** [`AGENTS.md`](AGENTS.md)
- **State / backlog:** [`PROGRESS.md`](PROGRESS.md) — single source of truth for what's next
- **Contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Product facts are grounded in Microsoft Learn; no invented cmdlets or blade paths.

## License

MIT — see [`LICENSE`](LICENSE). Free to use, modify, and redistribute, including commercially,
in your own tenant.
