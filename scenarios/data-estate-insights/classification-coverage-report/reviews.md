# Four-Lens Review — Classification Coverage Report

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The trend-log CSV and breakdown JSON files are themselves a sensitive-data-location index and
   the original draft didn't say so.** A file listing "customerdb.dbo.Customers: 2 classified assets
   (SSN, Credit Card Number)" is, by construction, a curated map of where an organization's most
   sensitive data lives — exactly the kind of artifact an attacker doing reconnaissance would want,
   and materially more convenient to exfiltrate than the same information locked inside Purview's own
   RBAC boundary (a flat CSV/JSON file has no collection-scoped access control at all once it leaves
   the script's memory).
   - **Resolution:** `README.md` §11 now opens with an explicit note that this report is itself a
     sensitive artifact and must be protected at least as strictly as the source classifications it
     summarizes (access-controlled storage, not an open file share); `rollback.md` §3 reinforces this
     for the decommission path.
2. **The `-Mode Facets` fast path's top-N truncation (`-FacetTopN`, default 25) could silently hide
   low-count classification categories from a report consumer who doesn't read `design.md`.** A
   classification appearing on only 2 assets, below the top-25 cutoff, disappears from that mode's
   output entirely with no "and N more" indicator.
   - **Resolution:** `README.md` §11 now states this explicitly under the `-Mode Facets` trade-off
     bullet — a reviewer relying on that mode for a compliance narrative needs to know it's
     top-N-truncated, not exhaustive, unlike `-Mode Full`.
3. **A compromised or over-broadly-scoped Data Reader credential could still read every classified
   value in every collection it has access to** — correctly a Data Reader-level exposure (the same
   read boundary any Data Reader has), not something this scenario makes worse, but worth stating
   plainly given the report's aggregation makes bulk extraction of "everything classified" a single
   script run instead of manual portal browsing.
   - **Resolution:** `README.md` §3's Data Reader row now cross-references this report's own §11
     sensitivity note, so the privilege-boundary discussion and the aggregation-risk discussion are
     read together rather than in isolation.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The `Write-Warning` for a paged-count-vs-`@search.count` mismatch could be missed entirely in a
   scheduled/unattended run**, since `Write-Warning` output isn't captured by the console
   `Write-Host` summary a human might glance at, and the script doesn't fail non-zero on it.
   - **Resolution:** `README.md` §8's incident-response runbook now names this warning explicitly as
     something a scheduled pipeline should capture (PowerShell warning stream, not just stdout) and
     treat as a signal to re-run before trusting that run's split — not something to leave silently
     unread.
2. **No guidance on how to actually route the trend-log CSV into a SIEM or alerting system** — the
   original draft said "route it into whatever the deploying organization already uses" without naming the mechanism
   (flat-file ingestion vs. an API push), which is thinner than this repo's DLP/Data Quality
   scenarios' own alert-routing sections.
   - **Resolution:** `README.md` §8 now states plainly that this scenario deliberately ships no
     bespoke sink (Log Analytics/Sentinel/Power BI) and that the trend-log CSV/breakdown JSON are the
     integration point — consistent with, not thinner than, this repo's established pattern for
     surfaces without a native alert channel (the same treatment `scenarios/data-lineage/
     end-to-end-lineage-validation/README.md` §8 gives its own no-native-alert case).
3. **The live-reconciliation `[WARN]` vs. file-integrity `[FAIL]` distinction wasn't obvious enough
   on first read** — a scheduled job's alerting could reasonably treat every non-`[PASS]` line the
   same way, defeating the point of having two severities.
   - **Resolution:** `README.md` §8's incident-response runbook now opens by naming which check
     category (file-integrity vs. live-reconciliation) each severity maps to, so a pipeline's
     alerting logic can be built to match.
4. **No SIEM/Sentinel-specific detection rule suggested** for "coverage dropped sharply between two
   runs" — correctly out of scope for this scenario to build (it would be the SIEM's own alerting
   rule, not this script's job), but worth noting as a natural next integration once the trend log
   exists.
   - **Resolution:** No change needed; confirmed as correctly scoped rather than a gap — the trend
     log's existence is what makes such a rule possible for the deploying organization to build, and building it for
     them would exceed this scenario's stated non-goals (`design.md` §7).

No remaining Fail. The three Fixes bring this scenario's operational guidance to the standard this
repo's other reporting/validation scripts (Data Quality, Data Lineage) already set.

---

## 🎩 CISO

**Verdict: Pass**

1. **The privilege story is a genuine, citable improvement over the native path**, not just a
   convenience: Data Reader-only vs. the native report's Data-Curator-only export gate is a concrete,
   auditable reduction in blast radius for a reporting workload that has no legitimate need to write
   anything.
2. **Cost is negligible and well-scoped**, with the one honest caveat (`-Mode Full` at very large
   scale) called out rather than hidden — the right level of transparency for a funding decision.
3. **The Red Team's sensitivity-of-the-report-itself finding is the one thing that needed to be
   explicit before this scenario's output could be handed to a board or GRC tool without a second
   thought** — a report that inventories where an org's SSNs and credit-card numbers live is not a
   "low sensitivity, it's just metadata" artifact, and now the scenario says so plainly rather than
   leaving a reader to infer it.
4. **Change-management impact: none.** No M365 control, DLP policy, or user-facing behavior is
   touched — a pure read/report layer. Rollback (§9/`rollback.md`) is simpler than any other scenario
   in this repo, since there is no Purview object to remove.
5. **Would I fund this?** Yes. The narrative — "we can show classification coverage trending over
   time, to an auditor or a board, without granting anyone more access than they'd need to just read
   the data" — is specific, defensible, and directly answers the accountability question GDPR/PCI/SOC
   2 all ask in different words (§2).

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Strong, primarily-sourced grounding for the central design claim.** The "no documented filter
   for has-any-classification" claim — the load-bearing justification for this scenario's entire
   per-record-pagination design — is grounded first in Microsoft's own canonical Discovery - Query
   REST reference (which documents only an exact-value classification filter), with a Microsoft Q&A
   thread cited as corroborating, not primary, evidence. This is the right citation hierarchy and
   should be preserved as the standard.
2. **The role-privilege comparison (Data Reader here vs. Data Curator for the native export) rests on
   a directly-fetched, on-topic Microsoft Learn page written specifically about Data Estate Insights
   access control** — not inferred from a general RBAC article — which makes it a stronger, more
   citable claim than a paraphrase would be.
3. **This scenario correctly does not attempt to automate, scrape, or reverse-engineer the native
   Insights application's own internal implementation** — it goes to the public, documented Discovery
   - Query API instead, which is the right and only supportable approach; no risk of building on an
   undocumented internal surface that could change without notice.
4. **One citation-precision gap in the initial draft:** the "Unclassified assets" KPI definition
   (used in `design.md` §1 to explain what this scenario reproduces) was attributed generically to
   "the classic assets report" without the specific reference needed to confirm Microsoft's own
   wording ("Assets with no system or custom classification on the entity or its columns").
   - **Resolution:** `README.md` reference 3 now points directly at the `unified-catalog-reports-
     classic-assets` page, and `design.md` §1 quotes the confirmed definition rather than
     paraphrasing it.
5. **No deprecated cmdlets/endpoints used**, and the dual-endpoint parameterization reuses the
   already-established, explicitly-confirmed precedent from `scenarios/data-lineage/
   end-to-end-lineage-validation/` rather than re-deriving it independently.
6. **Reinventing-a-native-capability check:** this scenario does not attempt to rebuild the native
   Insights application's UI, drill-down browsing, or portal experience — it fills a specific,
   named gap (export/schedule/history/least-privilege) the native application itself doesn't cover,
   which is the correct scope for a companion automation rather than a competing one.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via README/rollback additions, 1 closed via cross-reference) | Closed |
| 🔵 Blue Team | Fix | 4 (3 closed via README additions, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Pass | — | — |
| 🟦 Microsoft Product Owner | Fix | 1 closed (citation precision); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`rollback.md`. No Fail items were raised. This fragment meets the definition of done in `AGENTS.md`
§9.
