# Four-Lens Review — Post-Breach Investigation and AI-Triaged Purge

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Reviewer role is a data-exposure surface, not just a "can't purge, so it's safe" role.** The
   initial draft's README treated Reviewers as the low-risk tier (no purge access) without calling
   out that Reviewers *can* run categorization, examination, and vector search, and *can* view data
   risk graphs — meaning a Reviewer already sees extracted credentials, PII, and risk-ranked
   sensitive content at scale. Over-granting Reviewer access is a real exposure even without purge
   rights.
   - **Resolution:** README.md §8 now states this explicitly as an operational discipline item —
     Reviewer assignment needs the same care as any role with bulk visibility into sensitive content,
     not just the roles that can delete.
2. **Stale saved purge query = broader-than-reviewed deletion.** Microsoft's own documentation warns
   that a saved purge query's item-count estimate can go stale before it's run, potentially deleting
   more (or different) items than were reviewed — a real, documented attack-adjacent risk (an
   over-broad purge, whether malicious or accidental) the initial README mentioned only in passing.
   - **Resolution:** Promoted to its own bullet in README.md §8 with an explicit operational policy
     (always re-review immediately before running a saved query) rather than leaving it buried in the
     configuration reference table.
3. **RBAC script default must never silently narrow purge-capable membership.** Reviewed
   `New-DsiRoleGroupAssignments.ps1` for a scenario where a config drifts (e.g. a member typo) and a
   scheduled re-run under `-RemoveExtraMembers` silently revokes a legitimate Investigator's purge
   access mid-incident.
   - **Disposition: accepted, by design.** `-RemoveExtraMembers` is opt-in, off by default
     (`design.md` §5) — a scheduled/automated re-run without that flag is additive-only and can never
     remove access. The risk only exists if an operator explicitly chooses full reconciliation *and*
     schedules it unattended; README.md §5 presents `-RemoveExtraMembers` as a one-time/manual
     reconciliation action, not part of the suggested scheduled command.
4. **No script exists that could be abused to trigger a purge.** Confirmed neither
   `deploy/` script calls any purge-related endpoint or cmdlet — by design (`design.md` §3), since no
   such write API exists. This scenario's automation surface cannot itself be a vector for an
   unauthorized purge; the risk is entirely in DSI's own portal RBAC, which is exactly what §6/§8
   address.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Purge-start detection needed to be unmissable, not just logged.** The initial audit-export
   script draft recorded `DSIPurgeStarted` as an ordinary CSV row alongside 27 other Operations —
   indistinguishable in a log tail from a routine `DSIActivitiesViewed` event.
   - **Resolution:** `Export-DsiActivityAuditTrail.ps1` now emits an explicit `Write-Warning` for
     every `DSIPurgeStarted` row, and README.md §8 names it the scenario's single highest-priority
     signal with an explicit real-time-alerting recommendation, not "review on the next scheduled
     pass."
2. **No job-status visibility is a real operational gap, not just a documentation footnote.** Neither
   an AI-analysis job's completion nor a purge job's actual outcome (success/failure/partial) has a
   documented API — meaning a SOC's SIEM can see that a purge *started* but not, without going to the
   portal, whether it *succeeded*.
   - **Disposition: accepted limitation, not fixed.** README.md §7 and §11 both state this plainly
     (the portal's per-investigation Activities tab is authoritative) rather than implying the audit
     export provides complete operational visibility — consistent with `AGENTS.md` §4's no-guessing
     rule. A future Microsoft Learn revision documenting a job-status endpoint would be a natural
     follow-up.
3. **RecordType omission needed to be justified, not just silently absent.** An initial pass at the
   audit script considered adding a guessed `-RecordType 'DataSecurityInvestigation'` value "for
   completeness."
   - **Resolution:** Rejected during drafting — no Microsoft Learn page states this value. The script
     relies on `-Operations` alone, which `Search-UnifiedAuditLog` supports without `-RecordType`,
     and the gap is flagged as a VERIFY in the script's `.NOTES`, README.md §11, and `design.md` §5
     rather than guessed.
4. **Ingestion latency caveat was missing from the operational section.** The initial draft's
   Validation section mentioned audit latency but Operations & Tuning (§8) — where an on-call
   responder would actually look — did not.
   - **Resolution:** Added to README.md §8 explicitly, cross-referenced to §7.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **"Not pausable" needed to be a cost-control headline, not a footnote.** Unlike several other
   Purview pay-as-you-go capabilities in this library's licensing matrix that can be paused, DSI
   cannot — a fact with real budget-control implications during a large, prolonged investigation.
   - **Resolution:** Called out explicitly in both README.md §10 (Cost & licensing) and §8
     (Operations & tuning, storage/compute burn-rate monitoring), not buried in a comparison table.
2. **Regulatory narrative grounded in Microsoft's own worked examples, not generic "helps with
   compliance" language.** §2 cites the specific breach-notification-timeline mechanics (GDPR 72-hour,
   state breach laws, SEC disclosure) DSI's triage speed actually helps with, using Microsoft's own
   documented common-scenario examples rather than paraphrased marketing copy.
3. **Honest about what's NOT delivered.** This scenario does not claim to automate incident response —
   §1/§3/design.md §3 all make clear the *governance layer* is what's built and scriptable; the
   investigation itself remains a human-in-the-loop, portal-driven, AI-assisted process. A buyer
   evaluating this scenario against "does this automate breach response" would be correctly told: no,
   it governs and audits the tool that assists a human doing that.
4. **Would I fund this?** Yes, specifically for an organization already invested in Defender XDR
   and/or Insider Risk Management with real breach/insider-leak exposure and no dedicated DSI RBAC/
   audit discipline yet — the marginal cost of this scenario's own scripts is near-zero (no dedicated
   license required, §10) against a real gap (ungoverned purge-capable access during a live incident).
   Not a strong stand-alone purchase for an org with no Defender XDR/IRM/DSPM investment, since DSI's
   value depends heavily on those upstream signal sources — README.md §1 scopes the buyer correctly.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Role group names and permission matrix reproduced verbatim, not paraphrased.** The three
   dedicated role-group names, the four role groups with implicit access, and the full
   Admins/Investigators/Reviewers permission-by-action matrix in README.md §6 are copied directly from
   Microsoft's own permissions reference table — not reconstructed from a general description.
2. **Correct, current terminology for the DSI-vs-eDiscovery relationship.** `design.md` §7
   distinguishes this scenario from this library's existing eDiscovery search-and-purge scenarios by
   the actual product difference (known-query manual search vs. AI-assisted triage from an unknown
   blast radius) rather than presenting DSI as a superior replacement — matches Microsoft's own
   positioning of DSI as complementary, not a Purview eDiscovery successor.
3. **Not reinventing native capability, and not overreaching into it either.** This scenario
   deliberately does not attempt to script the investigation/search/AI-analysis/purge workflow itself
   once grounding confirmed no write API exists (`design.md` §3) — an earlier internal draft
   considered wrapping the Graph Security audit-record schema into a pseudo-management client, which
   would have misrepresented a read-only resource as a control surface. Caught and corrected before
   this file was finalized.
4. **Correctly scoped Preview-vs-GA boundaries.** README.md §12's closing note and `design.md` §6 both
   flag that adjacent features surfaced during grounding (Data Security Posture agent, endpoint DLP
   evidence collection integration, DSPM proactive-AI-insights) are Preview and explicitly out of this
   fragment's scope, rather than blending Preview and GA capability into one undifferentiated
   description.
5. **One VERIFY recorded honestly rather than guessed:** the `Search-UnifiedAuditLog` RecordType value
   for DSI records — flagged inline in the script, README.md §11, and `design.md` §5.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (Reviewer-role exposure surfaced; stale-purge-query risk promoted; RBAC-script default confirmed safe by design; no purge-capable automation surface exists) | Closed |
| 🔵 Blue Team | Fix | 4 (purge-start detection made unmissable; job-status gap accepted as a documented limitation; guessed RecordType rejected during drafting; latency caveat added to Operations section) | Closed |
| 🎩 CISO | Fix | 1 ("not pausable" promoted to a cost-control headline); Pass on regulatory narrative, honest scoping, funding case | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (an early pseudo-management-client draft around the read-only Graph audit-record schema, caught and removed); 1 VERIFY recorded, not guessed; 3 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DsiRoleGroupAssignments.ps1`, `deploy/Export-DsiActivityAuditTrail.ps1`,
`deploy/policy/dsi-role-assignments.sample.json`, `deploy/policy/empty-role-assignments.json`,
`validate/Test-DsiRoleGroupAssignments.ps1`, and `rollback.md`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9, with one open VERIFY recorded rather than
guessed, per `AGENTS.md` §4.

---

## Addendum (2026-09-10) — `-NdjsonOutDir` SIEM companion feed

A follow-up fragment (tracked in `PROGRESS.md`) closed the "Landing the audit-trail CSV in a SIEM"
non-goal partially: `Export-DsiActivityAuditTrail.ps1` gained an optional `-NdjsonOutDir` parameter
that writes new records as NDJSON using `audit/streaming-to-sentinel-or-management-api`'s own
per-run-file convention, so both scenarios can share one downstream forwarder. Mini four-lens
check on this addition only (the original round above is otherwise unchanged):

- 🔴 **Red Team** — does an optional output path introduce a new risk? No new write surface against
  the tenant (still read-only against `Search-UnifiedAuditLog`); the only new side effect is a local
  file write, gated behind the same `ShouldProcess` check as the CSV merge. The NDJSON file inherits
  the same sensitive-content profile as the CSV (`UserIds`/`AuditData` for every DSI action,
  including purges) — README.md §8 and §11 both call this out rather than treating the new output
  as lower-sensitivity just because it's a companion feed. **Verdict: Pass.**
- 🔵 **Blue Team** — does this create a detection gap or a duplicate-alert risk? No: `-NdjsonOutDir`
  only ever writes `$rowsToAdd` (already de-duplicated against the CSV), so a scheduled run with an
  overlapping window can't emit the same `DSIPurgeStarted` event twice into a SIEM that's alerting
  on the NDJSON feed. The console `Write-Warning` on every purge-start row is unchanged and remains
  the primary real-time signal regardless of whether `-NdjsonOutDir` is used. **Verdict: Pass.**
- 🟦 **Microsoft Product Owner** — does the "DSI-Activity" label misrepresent this as a real Office
  365 Management Activity API content type? Deliberately avoided: the label is hyphenated (not
  dot-separated like this API's genuine content types — `Audit.Exchange`, `DLP.All`), and both
  README.md §11 and the script's own `.PARAMETER` doc state explicitly that DSI records reach this
  feed via `Search-UnifiedAuditLog`, not the Management Activity API, and are not subject to that
  API's 24-hour/7-day window limits. **Verdict: Pass.**
- 🎩 **CISO** — is this worth shipping as opt-in rather than the new default? Yes: the CSV remains
  the primary, always-on record; `-NdjsonOutDir` is a zero-cost convenience for a buyer who already
  deployed `audit/streaming-to-sentinel-or-management-api`'s Path B collector, with no new license
  or infrastructure requirement of its own. **Verdict: Pass.**

No Fix/Fail raised by this addendum. `design.md` §6 (non-goals) and §5 (key decisions) updated to
reflect the new parameter; a new `design.md` §8 in `audit/streaming-to-sentinel-or-management-api`
(plus its README.md §8) cross-links back to it.
