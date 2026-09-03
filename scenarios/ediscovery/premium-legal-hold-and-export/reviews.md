# Four-Lens Review — eDiscovery (Premium) Legal Hold, Collection & Export

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Automation that deletes evidence or releases a hold is a spoliation weapon.** A careless (or
   malicious) run that disabled a hold or deleted a search/case could destroy preservation and expose
   the org to sanctions — the highest-stakes failure mode in this whole library.
   - **Resolution:** Both scripts use `ConfirmImpact = High`; deletion is opt-in (`-Delete`), export
     is opt-in (`-Export`), and the remove script **releases** (disables) a hold rather than deleting
     it by default and never deletes collected content/review sets/exports. `rollback.md` opens with a
     legal warning; `README.md` §11 states hold release is a legal act. Case close + custodian release
     are deliberately **not** scripted (portal, governed).
2. **Over-narrow hold = under-preservation.** Letting an operator drop a KQL query into the hold could
   silently preserve too little.
   - **Resolution:** The sample hold `contentQuery` is **empty** (preserve everything) and documented
     as the defensible default; narrowing is called out as a legal decision requiring sign-off
     (`design.md` §6, `README.md` §11), not a tuning knob.
3. **Exported data is sensitive by definition.** Exports contain the very PII/privileged content under
   dispute and leave the service.
   - **Resolution:** `README.md` §10/§11 flag export data-handling explicitly (download/Azure blob,
     PII/privilege), and export is opt-in and E5/PAYG-gated — not automatic.
4. **App-only automation over-privilege.** `eDiscovery.ReadWrite.All` app-only is a powerful,
   tenant-wide grant.
   - **Resolution:** Validation uses the read scope (`eDiscovery.Read.All`); the write scope is only
     for deploy/remove; `README.md` §3 notes app-only is E5-gated and points at Microsoft's app-auth
     setup, and delegated auth (scoped to the signed-in eDiscovery Manager's own cases) is the default.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Preservation gaps must be detectable.** A custodian whose hold silently didn't apply is a real
   risk; a validate script that only checked object existence would miss it.
   - **Resolution:** `validate/Test-EdiscoveryHoldAndCollect.ps1` reports each custodian's
     `holdStatus` and hard-checks that the legal hold `isEnabled` is true; §8 makes custodian hold
     status and collection statistics operational KPIs.
2. **Async operations look "done" too early.** Search runs and exports are asynchronous (`202` +
   operation); a naive script could imply completion.
   - **Resolution:** The deploy explicitly reports the export as async ("poll the case operations /
     portal") and does not claim completion; `README.md` §7/§8 tell the operator to track the export
     operation to completion.
3. **Idempotency on a legal object matters.** Re-running must never create a second hold/case.
   - **Resolution:** Get-then-create by natural key with `@odata.nextLink` paging; §7 includes an
     idempotency proof (re-run shows `exists`, no duplicates).

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Defensibility is the whole point.** Legal will ask how holds/collections were scoped and whether
   the process is reproducible.
   - **Resolution:** The definition file is the version-controlled, diffable record of each matter's
     scope; `README.md` §2/§8 frame reproducibility as the defensibility argument and point at the
     Purview audit log for the activity trail.
2. **Risk reduction vs. cost:** strong. Automating setup cuts spoliation risk (fast, consistent
   preservation) and labor, while the dominant cost (attorney review, export storage) is unchanged —
   honestly stated in §10 rather than over-promised.
3. **Board/GC narrative:** "we preserve and collect for every matter from a reviewed, reproducible
   definition, with an auditable record, and keep hold-scope and release decisions with Legal" —
   defensible and specific.
4. **Change-management / segregation of duties:** the scenario respects the Legal-vs-IT boundary — IT
   automates mechanics, Legal owns scope and release (surfaced throughout).
5. **Would I fund this?** Yes — reduces a high-severity legal risk with bounded cost and clear
   guardrails.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Right surface for the job.** Using the Graph eDiscovery API (Premium object model, working
   `-WhatIf`, app-only auth) rather than the classic S&C PowerShell content-search path is aligned
   with product direction; the classic path is noted as an alternative, not ignored (`design.md` §3).
2. **Correct, current endpoints and bodies.** Case, custodian, userSource, legalHold, search, and
   review-set export are reproduced from their v1.0 `security`-namespace reference pages (bodies,
   enums like `dataSourceScopes` and `exportStructure`), not paraphrased.
3. **Honest about the review-set commit gap.** `addToReviewSet` (prerequisite for export) is
   documented and flagged VERIFY rather than fabricated — per `AGENTS.md` §4.
4. **Accurate licensing/auth tiers.** E3 (delegated, standard ops, PAYG export) vs. E5/Premium
   (review sets, app-only, export) is stated per the API overview, and legal hold vs. retention hold
   is explicitly distinguished.
5. **Not reinventing native capability.** Uses the native API and points at the portal for review/
   export review steps; adds value only in reproducible, as-code matter setup.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (spoliation guardrails; preserve-everything default; export-data handling; least-privilege auth) | Closed |
| 🔵 Blue Team | Fix | 3 (hold-status detection; async honesty; idempotency proof) | Closed |
| 🎩 CISO | Fix | 1 (defensibility/audit foregrounded); Pass on cost/narrative/SoD | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (addToReviewSet gap flagged VERIFY); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-EdiscoveryHoldAndCollect.ps1`, `deploy/Remove-EdiscoveryHoldAndCollect.ps1`,
`deploy/config/legal-hold-case.sample.json`, and `validate/Test-EdiscoveryHoldAndCollect.ps1`. No
Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9, with the
review-set-commit prerequisite recorded as an explicit VERIFY (not fabricated) per `AGENTS.md` §4.
