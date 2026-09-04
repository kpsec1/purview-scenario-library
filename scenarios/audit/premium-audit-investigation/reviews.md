# Four-Lens Review — Audit (Premium) Forensic Investigation

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The export is a data-exfiltration target.** The investigation is read-only, but its output
   concentrates highly sensitive content and PII (mailbox subjects, file paths, IPs, full
   `auditData`) into files — a tempting target and an easy accidental-leak.
   - **Resolution:** `README.md` §9/§11 and `rollback.md` treat the export as **evidence**: restrict
     access, store per IR policy, dispose when the matter closes; the deploy script prints a handling
     warning after export. The scenario never widens access to produce the export.
2. **Least-privilege scope.** `AuditLogsQuery.Read.All` is a broad, all-workload read grant.
   - **Resolution:** `README.md` §3 documents the **service-scoped** variants
     (`AuditLogsQuery-Exchange.Read.All`, `-Entra.Read.All`, …) and names the least-privileged option,
     so an investigator scoped to one workload doesn't take the tenant-wide grant. Validation checks
     for *an* `AuditLogsQuery*` scope rather than demanding the broadest.
3. **Investigation vs. tipping off / altering evidence.** A tool that could modify the account under
   investigation would be dangerous (evidence tampering, alerting the adversary).
   - **Resolution:** The scenario is strictly read-only (`design.md` §2/§6); response/remediation is
     explicitly a **non-goal** and a separate workflow. `-WhatIf` previews without even creating the
     job.
4. **False "no activity" conclusion.** An attacker-aware investigator running immediately after an
   incident could wrongly conclude "nothing happened" due to ingestion lag.
   - **Resolution:** `README.md` §8/§11 state the ~60–90 minute ingestion latency explicitly and warn
     against concluding too early.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Async jobs must be handled correctly.** A naive script could read records before the job
   finished, or hang forever.
   - **Resolution:** The runner polls the query status until it leaves the running set, with a
     bounded `-PollTimeoutMinutes`, and only reads records after a terminal status; large result sets
     are paged via `@odata.nextLink` so nothing truncates.
2. **Triage needs to be fast and directed.** Raw records aren't actionable under incident pressure.
   - **Resolution:** The script prints a **top-operations summary** and exports a triage CSV of key
     fields; `README.md` §8 gives an explicit compromise runbook keyed to the crucial-event
     operations (malicious inbox rules, delegate grants, `MailItemsAccessed`, exfil, sign-in
     patterns).
3. **Readiness before an incident.** Discovering a missing permission mid-incident wastes precious
   time.
   - **Resolution:** `validate/Test-AuditInvestigation.ps1` checks connectivity, scope, config, and
     runs a **live 1-hour probe query** end-to-end — so readiness is proven before it's needed.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Defensibility and breach-clock pressure.** Investigations must be complete, reproducible, and
   fast enough for notification deadlines.
   - **Resolution:** `README.md` §2 ties the scenario to breach-notification obligations and frames
     reproducibility (same config → same evidence set, immutable records) as the defensibility
     argument; §7 includes a repeatability test.
2. **Risk reduction vs. cost:** strong and cheap. No consumption meter — the cost is investigator time
   (which automation reduces) plus secure evidence storage; the Premium delta (crucial events + long
   retention) is exactly what makes mailbox-compromise scoping possible.
3. **Board/IR narrative:** "we can reconstruct any account's activity across the estate from a
   reviewed, repeatable query, retaining evidence appropriately" — concrete and defensible.
4. **Privacy/proportionality:** monitoring employee activity is sensitive — mitigated by read-only
   posture, least-privilege scoping, tight time/user windows, and evidence-handling discipline.
5. **Would I fund this?** Yes — high-value IR capability, low cost, clear guardrails.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Right, current surface.** The async **Audit Search Graph API** (v1.0 `security`) is the modern,
   scalable path (paging, app-only, service-scoped permissions) versus the classic
   `Search-UnifiedAuditLog` (5k/50k caps, synchronous) — the latter is honestly noted as the
   alternative, not ignored (`design.md` §3).
2. **Correct endpoints and fields.** Create/get/list-records, the query body filters
   (`filterStartDateTime`, `operationFilters`, `recordTypeFilters`, `userPrincipalNameFilters`, …),
   the `AuditLogsQuery*` permission set, and the record fields are reproduced from their v1.0
   reference pages, not paraphrased.
3. **Accurate Standard-vs-Premium framing.** Crucial events (`MailItemsAccessed`) and 1-year/10-year
   retention are correctly attributed to Premium/add-on tiers.
4. **Honest about the status enum.** The exact `auditLogQueryStatus` terminal values weren't pinned
   this build, so the script polls defensively (running-set exclusion + a `succeeded`-like check) and
   flags a VERIFY rather than hard-coding an unconfirmed value.
5. **Not reinventing native capability.** Uses the native API and points at the portal search for the
   manual path; adds value only in repeatable, exportable, as-code investigation.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (evidence handling; least-privilege scope; read-only/no-tamper; ingestion-lag false negatives) | Closed |
| 🔵 Blue Team | Fix | 3 (async polling + paging; triage summary/runbook; live readiness probe) | Closed |
| 🎩 CISO | Fix | 1 (defensibility/breach-clock foregrounded); Pass on cost/narrative/proportionality | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (status-enum VERIFY, defensive polling); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/Invoke-AuditInvestigation.ps1`, `deploy/config/audit-investigation.sample.json`, and
`validate/Test-AuditInvestigation.ps1`. No Fail items were raised. This fragment meets the definition
of done in `AGENTS.md` §9, with the audit-query status enum recorded as an explicit VERIFY (not
fabricated) per `AGENTS.md` §4.
