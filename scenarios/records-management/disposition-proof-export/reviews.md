# Four-Lens Review - Disposition Proof Export

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A record deleted outside the reviewed disposition process entirely would still pass this
   scenario's own "evidence found" check, and nothing in the initial draft would let a reviewer
   distinguish it from a properly reviewed disposal.** A record must be unlocked (`UnlockRecord`,
   requiring at least contributor permission) before a user can delete it. The initial draft queried
   only the four disposition-review Operations plus `RecordDelete` - it never captured
   `UnlockRecord`, so an attacker (or a careless admin) who unlocks a record and deletes it directly,
   bypassing the disposition-review workflow entirely, would produce a `RecordDelete` event
   indistinguishable in this scenario's own output from a properly reviewed disposal reaching its
   final `ApproveDisposal` stage.
   - **Resolution:** `deploy/Export-DispositionProofEvidence.ps1` and `validate/
     Test-DispositionProofExport.ps1` now also query `LockRecord`/`UnlockRecord`. `README.md` §6/§8
     and `design.md` §2 item 6/§6 document the specific reconciliation pattern (an `UnlockRecord`
     shortly before a `RecordDelete` with no corresponding final-stage `ApproveDisposal` in between)
     an analyst should watch for. This scenario surfaces the raw events for that reconciliation; it
     does not itself compute or alert on the pattern - stated explicitly rather than implied.
2. **The rolling evidence CSV has no tamper-evidence of its own**, and the initial draft didn't say
   so. Composite-key de-duplication prevents accidental duplicate rows across overlapping scheduled
   runs - it is not an integrity or signing mechanism. Anyone with write access to `-OutputCsvPath`
   could edit or delete rows undetected by this scenario's own tooling, which would be a serious
   problem if the file is ever relied on as genuine evidence in an examination or litigation.
   - **Resolution:** `README.md` §11 now states this explicitly and recommends immutable/WORM
     storage or a signed-commit source-control repository for the CSV when it needs to hold up as
     evidence - not a general-purpose file share. Also carried into `rollback.md` §2's guidance on
     handling already-produced evidence files.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No operability guidance connected the new lock/unlock context (Red Team finding 1) to an actual
   on-call action.** Surfacing raw events without a stated reconciliation heuristic leaves an analyst
   to reinvent the pattern themselves under time pressure.
   - **Resolution:** `README.md` §8 adds an explicit "Out-of-process-deletion pattern" subsection
     naming the exact event sequence to watch for and cross-linking
     `scenarios/audit/streaming-to-sentinel-or-management-api/` for continuous, alerting-grade
     monitoring at scale rather than relying on a scheduled CSV pull alone.
2. **The initial draft didn't address Microsoft's own stated preference for the Management Activity
   API over `Search-UnifiedAuditLog` for production automation** - a real operability consideration
   for an organization deciding how to run this at scale, not just a documentation nicety.
   - **Resolution:** `README.md` §11 now quotes Microsoft's own guidance directly, explains why this
     scenario still uses `Search-UnifiedAuditLog` (consistent with every other audit-trail script in
     this library, no separate webhook/subscription setup needed for a scheduled pull), and
     cross-links the dedicated streaming scenario as the recommended path at higher volume/lower
     latency requirements.
3. **Zero-row-window messaging is correctly conservative** (`[INCONCLUSIVE]`, never `[FAIL]`),
   matching this repo's established precedent (`adaptive-protection-deleted-content-preservation`'s
   own validator) - confirmed correct, no change needed.
4. **The CSV structural-integrity checks are appropriately strict** (`[PASS]`/`[FAIL]`, not
   `[INCONCLUSIVE]`) since they validate this scenario's own deterministic output rather than tenant
   activity - confirmed correct, no change needed.

No remaining Fail. The Fixes close a real gap between "evidence is collected" and "an analyst knows
what to do with it."

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The single most important finding from a funding standpoint: an evidence artifact with a weaker
   chain of custody than the records it documents defeats the entire purpose of buying this
   scenario.** The initial draft treated the CSV's storage location as an operational afterthought
   rather than the crux of whether this scenario actually delivers what a CISO is funding it for -
   defensible proof of disposition.
   - **Resolution:** Same fix as Red Team finding 2, elevated to a CISO framing: `README.md` §11
     states this is "a CISO-level consideration, not a cosmetic detail" and ties the storage
     recommendation directly to the scenario's own value proposition (§1), not left as a generic
     security best-practice footnote.
2. **Cost story is honest and low-risk.** No separate licensing meter (§10); the real cost driver is
   the audit-retention tier already in play for the tenant, correctly disclosed as a limitation of
   this scenario's script rather than glossed over (§10/§11: a Standard-only tenant needs a shorter
   export cadence, and Premium's 10-year add-on is the licensed answer for genuinely long evidentiary
   horizons, not a workaround this scenario invents).
3. **Compliance mapping is concrete and correctly scoped**: DoD 5015.02, SEC 17a-4/FINRA 4511,
   GDPR/CCPA storage-limitation (§2) - matches the parent `regulatory-records-disposition` scenario's
   own drivers rather than inventing new ones, appropriate for a companion evidence scenario.
4. **Change-management impact: none.** Read-only against every Purview object; no policy, label, or
   user-facing behavior is touched (§9) - correctly scoped and stated plainly in rollback.md.
5. **Would I fund this, after the Fix above?** Yes - a low-cost, read-only companion that closes a
   real evidentiary gap the parent disposition scenarios left open, conditional on the storage
   guidance in §11 actually being followed rather than treated as optional.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Strong, primary-sourced grounding**, directly fetched this build rather than inferred: the
   `disposition` reference page in full (portal mechanics, timelines, RBAC, audit-enablement
   prerequisite), the "Disposition review activities" and "File and page activities" tables from
   `audit-log-activities` (all five original Operations plus the two added during this review), and
   the Graph `auditLogRecordType` enum (confirming `RecordsManagement`/`MultiStageDisposition` as
   real members without overclaiming a confirmed worked-example pairing).
2. **Honest, non-overclaiming treatment of the `RecordType` gap** (`design.md` §2 item 3): states
   what Microsoft's enum confirms (the members exist, with plausible names) distinctly from what it
   doesn't confirm (a worked example pairing either with these Operations) - the same discipline this
   repo already established for the AdaptiveProtection preservation-evidence scenario's identical
   class of gap, correctly cited as precedent rather than re-derived from scratch.
3. **No deprecated cmdlets or endpoints.** `Search-UnifiedAuditLog` is current and actively
   documented; the older REST event API deprecation noted elsewhere in this repo
   (`regulatory-records-disposition`) is unrelated to this scenario's own automation surface.
4. **Not reinventing a native capability** - correctly scoped as a complement to the portal's
   Filter+Export workflow, not a reimplementation of it (`design.md` §2 item 4, §7 Non-goals);
   confirmed no `security.dispositionReview*` Graph resource exposes a queryable disposition-item
   collection that this scenario should have used instead.
5. **One completeness gap in the initial draft, raised in this review:** the scenario didn't mention
   Microsoft's own stated production-automation recommendation (Management Activity API over
   `Search-UnifiedAuditLog`), which an organization evaluating this against Microsoft's own guidance would
   reasonably expect addressed.
   - **Resolution:** Same fix as Blue Team finding 2 - `README.md` §11 quotes the recommendation
     directly and cross-links the dedicated streaming scenario rather than silently diverging from
     Microsoft's stated guidance.
6. **Licensing citations correctly scoped** - Records Management and Audit (Standard/Premium) tiers
   both cited to their own current Microsoft Learn pages (§3/§10), not inferred from a sibling
   scenario's already-established claims.

No remaining Fail after resolution.

**Addendum (2026-09-26 maintenance pass):** the `RecordType` gap noted in finding 2 above is now
closed, not merely honestly disclosed. A full-page fetch of the Office 365 Management Activity API
schema's `AuditLogRecordType` enum table - the value source `Search-UnifiedAuditLog -RecordType`
documents itself against - confirms neither `RecordsManagement` nor `MultiStageDisposition` appears
on that page; both are members only of the separate Graph `microsoft.graph.security.auditLogRecordType`
enum. Neither is valid `-RecordType` input for this cmdlet, so omitting `-RecordType` is confirmed
correct rather than just the conservative default. See `README.md` §6/§11 and `design.md` §2 item 3.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (out-of-process-deletion blind spot closed by adding `LockRecord`/`UnlockRecord` to both scripts; CSV tamper-evidence gap closed by README/rollback storage guidance) | Closed |
| 🔵 Blue Team | Fix | 2 new (operability guidance for the lock/unlock pattern; Management Activity API disclosure) closed via README additions; 2 confirmed correct | Closed |
| 🎩 CISO | Fix | 1 major finding (chain-of-custody framing) closed via README additions; 4 confirmed correct | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (Management Activity API disclosure); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-DispositionProofEvidence.ps1`, and `validate/Test-DispositionProofExport.ps1`. No
Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
