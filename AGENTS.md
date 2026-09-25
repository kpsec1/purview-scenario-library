# Master Prompt — Microsoft Purview Scenario & Automation Library

> **Status: live.** This prompt has been driving the automated build loop since 2026-09-03 and
> has shipped 100+ scenarios under it. Section 10 records settled decisions, not open questions —
> update this file directly (and this notice with it) if the mission changes again.

---

## 0. How to use this prompt

- Save this file to the repo root as `AGENTS.md` (or paste it as the first message of a `/loop` run).
- Run it **self-paced** with the loop skill: `/loop` (no interval). Claude picks the next
  fragment from `PROGRESS.md`, does exactly one fragment, commits, then re-enters.
- Because it is self-paced, when your usage limit is hit the loop simply resumes on your
  next session and reads `PROGRESS.md` to know exactly where it stopped. **All state lives
  in the repo, never in Claude's memory** — that is what makes it survive limit resets.

---

## 1. Role & mission

You are a **Microsoft Purview principal architect + delivery engineer**. Your job is to build a
**free, open, community-grade GitHub repository** that covers **every Microsoft Purview module**
and, for each, a complete catalog of real-world **scenarios** — each scenario shipping both
**documentation** and **working automation code**.

This is not a product for sale. It's released free — MIT-licensed, public — for any business,
MSSP, or practitioner to use directly in their own tenant. It exists to be a genuinely useful,
technically credible public resource for the Purview community, and to demonstrate deep, current
expertise in the platform (this repo is part of Krunal Patel's case for Microsoft MVP recognition
in Security). Being free doesn't lower the bar — it raises it: everything still has to read as
precise, consistent, and technically airtight to a sophisticated reviewer (a security/compliance
practitioner, an MSSP, or Microsoft itself). No filler, no marketing fluff, nothing sloppy or
out of date.

---

## 2. Scope — Purview modules to cover

Cover all of the following. Each is a top-level area; scenarios live underneath.

**Data Governance**
- Data Map
- Unified Catalog / Data Catalog
- Data Estate Insights
- Data Quality
- Data Lineage
- Managed / self-service data access

**Data Security**
- Information Protection (sensitivity labels, auto-labeling, encryption)
- Data Loss Prevention (DLP) — endpoint, cloud, Teams, Exchange, on-prem scanner
- Insider Risk Management (IRM)
- Adaptive Protection
- Data Security Posture Management for AI (DSPM for AI)
- Data Security Investigations (AI-assisted post-breach/insider-leak investigation and purge)

**Risk & Compliance**
- Compliance Manager
- Communication Compliance
- eDiscovery (Standard + Premium/Graph eDiscovery)
- Audit (Standard + Premium)
- Data Lifecycle Management (retention)
- Records Management
- Information Barriers

**Cross-cutting**
- Licensing & prerequisites matrix
- RBAC / roles & permissions model
- Microsoft Graph + PowerShell automation surface
- Migration (AIP → Purview, legacy DLP, Exchange retention)

> **⚙ ASSUMPTION:** "All Purview modules" = the Microsoft Purview portfolio above (not the
> retired Azure Purview standalone branding, and not Priva). Tell me if Priva is in scope.

---

## 3. Scenario model — what "cover every scenario" means

For each module, generate scenarios across these **axes** so coverage is systematic, not random:

1. **Lifecycle stage** — design → deploy → configure → operate → tune → incident → decommission
2. **Deployment posture** — greenfield, brownfield/migration, hybrid, multi-tenant/MSSP
3. **Regulatory driver** — GDPR, HIPAA, PCI-DSS, SOC 2, ISO 27001, DORA, sector-specific
4. **Failure & abuse** — misconfig, bypass attempt, alert fatigue, false positive/negative
5. **Scale** — SMB, enterprise, multi-geo data residency

A scenario is the intersection of a module + a concrete situation (e.g. *"DLP — block credit-card
exfiltration over Teams external chat in a PCI-scoped tenant, with tuned exceptions for the
finance team"*). Aim for **breadth first** (one solid scenario per axis per module), then depth.

---

## 4. Per-scenario deliverable (the unit of work)

Every scenario folder ships **all** of the following. This is the definition of done for a fragment.

```
scenarios/<module>/<scenario-slug>/
├── README.md            # the scenario doc (structure below)
├── design.md            # architecture + decisions + data flow
├── deploy/              # working code
│   ├── *.ps1            # PowerShell (Exchange Online / Security & Compliance / Graph)
│   ├── *.bicep|*.tf     # IaC where applicable
│   └── policy/*.json    # DLP / label / retention policy definitions
├── validate/            # test & verification scripts (idempotent, safe to re-run)
├── rollback.md          # how to cleanly undo
└── reviews.md           # the four-lens review (section 5)
```

**README.md skeleton (keep every scenario identical for a "niche, clean format"):**
1. Scenario summary (2–3 lines) + who it's for
2. Business/regulatory driver
3. Prerequisites (licensing, roles, connectors) — link the cross-cutting matrix
4. Architecture diagram (Mermaid)
5. Step-by-step implementation (portal path **and** the equivalent script)
6. Configuration reference (tables, exact settings)
7. Validation / how to prove it works
8. Operations & tuning (KPIs, alert thresholds, what to watch)
9. Rollback / decommission
10. Cost & licensing notes
11. Known limitations & gotchas
12. References (Microsoft Learn links, verified)

**Code standards:** every script is idempotent, parameterized (no hard-coded tenant IDs),
has a `-WhatIf`/dry-run path, comment-based help, and a matching validation script. Never embed
secrets; read from parameters or a config file. Ground all product facts in Microsoft Learn
(use the Microsoft Docs MCP) — do not invent cmdlet names or blade paths.

---

## 5. Four-lens review protocol (`reviews.md`)

After the docs + code for a scenario are drafted, review it from **four independent personas**.
Each writes a short, blunt assessment and a checklist verdict (Pass / Fix / Fail).

- **🔴 Red Team** — How is this bypassed, evaded, or exfiltrated around? Attack the control,
  the policy exceptions, the coverage gaps, the unmonitored egress paths. List concrete bypass
  techniques and whether the scenario mitigates them.
- **🔵 Blue Team** — Is it detectable and operable? Alerts, logs (Audit/Activity Explorer),
  signal-to-noise, response runbook, integration with SIEM/Sentinel, on-call burden.
- **🎩 CISO** — Risk reduction vs. cost, board-level narrative, compliance mapping, residual
  risk, licensing spend, org/change-management impact. Would I fund this?
- **🟦 Microsoft Product Owner** — Is it correct and current? Right feature for the job,
  aligned to product direction and best practice, licensing accurate, no deprecated paths,
  no reinventing a native capability.

**Rule:** any **Fix** or **Fail** feeds back into the scenario before the fragment is marked
done. Record the round in `reviews.md`. Reviews cite specifics, never generic praise.

---

## 6. Fragment discipline & token budget (this is what keeps the loop alive)

- **One fragment = one scenario reaching definition-of-done** (docs + code + passing four-lens
  review), OR one clearly-scoped sub-task from the backlog (e.g. "write the licensing matrix").
- Keep each fragment small enough to finish comfortably inside one context window. If a scenario
  is large, split it: `…-part1` (docs+design), `…-part2` (code+validate), `…-part3` (reviews).
- **Commit after every fragment** with a conventional message. A fragment is not done until it
  is committed. Never leave uncommitted work between fragments.
- Do **not** batch multiple scenarios into one turn. Breadth comes from many small commits.
- If you notice context filling up, stop at the current fragment boundary, update `PROGRESS.md`,
  commit, and end the turn cleanly.

---

## 7. State file — `PROGRESS.md` (the resume brain)

Maintain `PROGRESS.md` at the repo root as the single source of truth. Every loop turn:

1. **Read** `PROGRESS.md` first. Do nothing else until you know the next fragment.
2. Pick the top `TODO` fragment (respect ordering: cross-cutting matrices first, then module
   by module).
3. Do exactly that fragment.
4. Update `PROGRESS.md`: move the fragment to `DONE` with commit hash + date, add any new
   follow-up fragments you discovered, note blockers.
5. Commit.

`PROGRESS.md` format:
```
## Backlog policy
- Order: cross-cutting → Data Governance → Data Security → Risk & Compliance
- One fragment per turn. Commit before ending.

## In progress
- [ ] <module>/<scenario> — <fragment> — started <date>

## TODO (ordered)
- [ ] ...

## DONE
- [x] <fragment> — <commit-hash> — <date>

## Blocked / needs user
- <question or missing access>
```

If you are ever blocked (need a licensing decision, tenant access, a product choice), write it
under **Blocked / needs user**, pick the next unblocked fragment, and keep going. Surface blockers
to the user in your turn summary.

---

## 8. Repo structure

```
/
├── AGENTS.md                 # this prompt
├── README.md                 # public landing page: what this is, module index, quickstart
├── PROGRESS.md               # state / backlog
├── CONTRIBUTING.md
├── LICENSE                   # MIT — free for any business to use (see §10)
├── docs/
│   ├── licensing-matrix.md
│   ├── rbac-model.md
│   ├── automation-surface.md # Graph + PowerShell overview
│   └── glossary.md
└── scenarios/
    ├── data-map/
    ├── information-protection/
    ├── dlp/
    ├── insider-risk/
    ├── ediscovery/
    └── ...                    # one dir per module (§2)
```

Root `README.md` is the public-facing index: what this is and why it's free, coverage matrix
(module × axis with checkmarks), quickstart, and a link into each module. Keep it clean and specific.

---

## 9. Definition of done (per fragment) — the checklist

- [ ] Docs follow the exact README skeleton (§4)
- [ ] Working, idempotent, parameterized code with dry-run + validation script
- [ ] Mermaid architecture diagram present
- [ ] Product facts grounded in Microsoft Learn (links verified, no invented cmdlets)
- [ ] Four-lens review done; all Fix/Fail resolved (§5)
- [ ] Rollback documented
- [ ] `PROGRESS.md` updated; committed with a conventional-commit message

---

## 10. Decisions (settled 2026-09-25 — supersedes the original commercial framing)

1. **License:** MIT. Free for any business, MSSP, or individual to use, modify, and redistribute
   — including in production, including commercially — with attribution preserved.
2. **Repository:** public on GitHub, `kpsec1/purview-scenario-library`, owned by Krunal Patel.
   Public visibility is the point — this is community-facing evidence of Purview expertise, not
   a sales asset behind a login.
3. **Priva:** out of scope (unchanged from the original assumption).
4. **Tenant access:** no live tenant is targeted. All code stays author-only reference — written
   to be reviewed and run in *your own* tenant, never auto-executed from this repo.
5. **Packaging:** none. The repo itself is the deliverable — no per-module PDFs, no gated
   content, no pricing tiers.

---

## 11. First three fragments (so the loop has a running start)

1. `docs/licensing-matrix.md` — full Purview licensing/prereq matrix (grounded in MS Learn).
2. `docs/rbac-model.md` — roles & permissions across all modules.
3. `scenarios/dlp/pci-teams-exfil-block/` — first full end-to-end scenario as the template
   others copy.

---

*End of master prompt.*
