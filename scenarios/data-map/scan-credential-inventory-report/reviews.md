# Four-Lens Review — Scan Credential Inventory & Drift Report

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`-FailOnDrift` alone does not catch a wholly new, unauthorized credential.** A credential that
   is entirely new — not a re-point of one already in the expected-state file — is reported as
   `Status = NotTracked`, and the validate script's original draft treated `NotTracked` as purely
   informational, never a failure. An attacker who creates a **brand-new** rogue credential (rather
   than rewriting an existing tracked one) would pass the drift gate silently, defeating the very
   purpose of this scenario for that specific attack shape.
   - **Resolution:** added an independent `-FailOnUntracked` switch to `validate/
     Test-CredentialInventoryReport.ps1`, kept separate from `-FailOnDrift` because the two answer
     different questions (an existing credential changed, vs. an unreviewed one exists at all) and a
     tenant with frequent legitimate onboarding needs to disable the second without losing the
     first. `README.md` §6/§11 and `design.md` §6 document the gap and the resolution explicitly
     rather than silently patching the script.
2. **The expected-state file is only as trustworthy as the review process around changes to it.** If
   the same actor who can re-point a live credential can also edit the checked-in expected-state
   file without independent review, a malicious re-point plus a matching expected-state edit in the
   same commit defeats the entire control — the drift report shows `Match` because "expected" was
   updated to agree with the tampering. Nothing inside Purview or inside this script can detect that.
   - **Resolution:** this is a process gap, not a code gap, and is documented as such rather than
     papered over. `README.md` §3 adds an explicit prerequisite — an approver for the expected-state
     file distinct from whoever can deploy credential changes — and §11 states the finding and the
     git-history-as-audit-trail mitigation plainly, including in the runbook's own wording ("a
     deliberate, reviewed commit — not a silent edit," §8 step 2).
3. **The trend-log CSV and drift-report JSON are themselves a reconnaissance-value artifact** — Key
   Vault secret *names* and connection names for every scan credential in the estate, in one place,
   even though no secret *value* ever appears. Same category of finding
   `classification-coverage-report/reviews.md` raised for its own report output.
   - **Resolution:** `README.md` §11 states this explicitly as the first bullet, and `rollback.md`
     §3 carries the same handling discipline into the decommission path — consistent with, not
     weaker than, the sibling scenario's own treatment.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The two failure severities (`-FailOnDrift` vs. `-FailOnUntracked`) needed to be clearly
   distinguishable in a pipeline's alerting, not just in the script's help text**, or an operator
   would reasonably treat every non-`[PASS]` line identically and lose the point of having two
   independently-toggleable gates.
   - **Resolution:** `README.md` §8's runbook opens by distinguishing what each status means before
     giving remediation steps, matching the precedent `classification-coverage-report/README.md` §8
     already set for its own two-severity model (file-integrity vs. live-reconciliation there;
     `Drift`/`Missing` vs. `NotTracked` here).
2. **`NotTracked` count trending upward silently is itself a signal worth watching**, even when
   `-FailOnUntracked` is deliberately left off (the common case) — a growing gap between "what's live"
   and "what's reviewed" is an erosion of the control's own effectiveness over time, not just cosmetic
   noise.
   - **Resolution:** `README.md` §8's KPI table adds `NotTracked` count trend as its own row with an
     explicit "act when" threshold, rather than leaving it implicit in the status-value table alone.
3. **No SIEM/Sentinel-specific sink or detection rule** — correctly out of scope, matching the
   established precedent from `classification-coverage-report/design.md` §7 and
   `sensitivity-label-coverage-report`'s own non-goals list.
   - **Resolution:** No change needed; confirmed as correctly scoped, and `design.md` §7 states this
     as a deliberate non-goal rather than an oversight.
4. **The live-reconciliation check (validate script check 2) only compares credential *count* and
   *name set*, not fingerprint values, against live data** — it does not independently re-verify that
   the trend log's recorded fingerprint still matches the live one.
   - **Resolution:** confirmed as intentional, not a gap: re-deriving every credential's full
     fingerprint inside `validate/` would duplicate `deploy/`'s own extraction logic in a second
     script that could drift from it independently. The deploy script computes fresh fingerprints on
     every scheduled run; the drift comparison happens there, once, against the expected-state file
     — that is the load-bearing check. The live-reconciliation check's actual job is narrower and
     correctly scoped: catching a *stale* report (a credential added/removed since the last export),
     the same "staleness vs. wrongness" distinction `classification-coverage-report/README.md` §7
     already draws for its own live-reconciliation check. `design.md` §2 goal 1 states this scoping
     explicitly.

No remaining Fail. The four items bring this scenario's operational guidance and gate design to the
standard `scan-credential-key-vault-backed` and `classification-coverage-report` already set.

---

## 🎩 CISO

**Verdict: Pass**

1. **This closes a control gap this repo already named and left open.**
   `scan-credential-key-vault-backed/README.md` §11 explicitly listed "no documented Purview
   detective control" for the silent-re-point risk as an accepted, disclosed limitation with three
   named compensating controls. This scenario is the first of those three to actually ship as
   working automation — a concrete, citable improvement to a risk this repo already put a name to,
   not a speculative addition.
2. **Cost is negligible and clearly stated** (§10) — the real cost this scenario asks an organization
   to bear is process discipline (keeping the expected-state file current, and gating changes to it
   through a separate approver), not Azure spend. That is the correct cost to be honest about for a
   detective control like this.
3. **The two Red Team findings, once resolved, materially strengthen the narrative this scenario can
   be sold on.** "We have a scheduled, diffable inventory of every scan credential, and we know
   exactly which attack shapes it does and doesn't cover" is a stronger, more defensible statement to
   put in front of an auditor than a report that silently has a blind spot its own documentation
   doesn't mention.
4. **Change-management impact is minimal**, same posture as `classification-coverage-report`: a
   pure read/report layer, one new role assignment, one new scheduled job, one new file to keep
   current in source control. Nothing user-facing or M365-control-facing changes.
5. **Would I fund this?** Yes — it is the cheapest possible way to close a documented, previously
   accepted risk this repo's own sibling scenario already flagged, and it reuses infrastructure
   (the reporting-and-trend-log pattern) this repo has already built and reviewed once.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Strong, directly-fetched grounding for the central object model.** Both the Credential - List
   and Credential - Create Or Replace REST reference pages were fetched in full during this
   fragment's build (not summarized from a search snippet), and every one of the eight documented
   `CredentialType` kinds' `typeProperties` shapes in §3/§6's fingerprint table was read directly
   from those pages — not inferred from the three kinds `scan-credential-key-vault-backed` already
   covers, and not assumed to generalize from a single kind's shape.
2. **Correctly identifies and preserves two genuine structural exceptions** (`AmazonARN`'s
   `roleARN` and `ManagedIdentity`'s `principalId`/`resourceId`/`tenantId`, neither of which is a
   `KeyVaultSecret` reference) rather than forcing every kind through an assumed common shape. A
   less careful build could have written a single generic "extract `typeProperties.<secret-like-
   field>`" function and either thrown or silently mis-extracted for these two kinds; this is exactly
   the "no invented cmdlets/shapes" discipline `AGENTS.md` §4 requires.
3. **One citation-precision gap in the initial draft, found and closed in this review round:** the
   claim that `nextLink` pagination "follows the standard convention" was initially stated without
   distinguishing that no *populated, multi-page* worked example exists for this specific endpoint —
   the only worked example in Microsoft's reference returns exactly 2 credentials with
   `nextLink: null`.
   - **Resolution:** `README.md` §11 and the deploy script's own `.NOTES` now state this precisely —
     the pagination *shape* (a `nextLink` field, standard across every other Purview List operation
     in this repo) is documented; a populated example for *this* endpoint specifically is not — so a
     reader can tell exactly what is and isn't confirmed, rather than reading a blanket "this is
     documented" claim.
4. **Correctly does not attempt to script creation of the five credential kinds this repo doesn't
   already build.** `design.md` §7 states this explicitly as a non-goal, distinct from — and not
   blocking — this scenario's ability to *read and report on* any of those kinds if an operator
   created one through a different path. Reading and writing are different scopes, and this fragment
   does not conflate them, consistent with `AGENTS.md` §6's fragment-discipline guidance.
5. **No deprecated cmdlets/endpoints used.** `api-version=2023-09-01` matches every other Purview
   Scanning data-plane script in this repo — no version drift introduced.
6. **Reinventing-a-native-capability check:** Microsoft's own portal offers no credential inventory
   export, trend, or drift view at all (§5) — this scenario fills a genuine, named gap rather than
   rebuilding something the product already provides.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed via new `-FailOnUntracked` switch, 1 mitigated via documented process control, 1 closed via README/rollback additions) | Closed |
| 🔵 Blue Team | Fix | 4 (2 closed via README additions, 2 confirmed correctly scoped) | Closed |
| 🎩 CISO | Pass | — | — |
| 🟦 Microsoft Product Owner | Fix | 1 closed (citation precision on `nextLink`); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-CredentialInventoryReport.ps1`, and `validate/Test-CredentialInventoryReport.ps1`. No
Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
