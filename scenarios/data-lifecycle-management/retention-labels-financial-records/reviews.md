# Four-Lens Review — Regulatory Retention Labels for Financial Records

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Over-scoping an irreversible label is a self-inflicted denial-of-deletion.** The single most
   dangerous failure mode: a broad auto-apply query stamps regulatory (immutable) retention onto vast
   amounts of the wrong content, which then can't be deleted for years — a storage-and-compliance
   landmine, and a plausible sabotage vector for a malicious insider with the role.
   - **Resolution:** The whole scenario is built around this: `-DryRun` by intent, a **narrow** default
     match query, loud irreversibility warnings in `README.md` §2/§11 and the deploy banner, a
     lab-test-first + Records/Legal-sign-off instruction, and a design note that precision beats recall
     here. The config's `_ruleNote` warns explicitly against broad queries.
2. **Choosing regulatory when a lesser control suffices.** Defaulting everyone to maximum immutability
   could trap content unnecessarily.
   - **Resolution:** `design.md` §3 lays out the retention-strength ladder (retention → record →
     regulatory) and tells teams to pick the **least-restrictive** control that meets the obligation;
     `README.md` §11 repeats it. Regulatory is the default only because the scenario targets 17a-4-class
     WORM obligations.
3. **Privileged misuse / no take-backs.** The role that creates these labels is powerful and the action
   is irreversible.
   - **Resolution:** Idempotency is **create-or-report** (never silent auto-update of a retention
     object); rollback **refuses** to force-remove records and says why; `README.md` §8 frames any
     change as a controlled, reviewed action. The scenario doesn't hand anyone a "release records"
     button because none can exist.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Silent deployment mistakes.** Without a working dry-run, an operator could create an immutable
   label from a typo.
   - **Resolution:** The scripts implement a real `-DryRun` (S&C `-WhatIf` is non-functional) that
     prints the exact `New-ComplianceTag`/policy/rule cmdlets; `README.md` §5 makes dry-run the first
     step.
2. **"Did it actually label anything?"** Auto-apply is asynchronous (up to 7 days) and can silently
   stall (Off (Error)).
   - **Resolution:** `README.md` §7/§8 document the 7-day latency, the **DistributionStatus** signal,
     and `Set-RetentionCompliancePolicy -RetryDistribution` for stuck policies; the validate script
     surfaces distribution status.
3. **Operability of validation.** Need a fast, safe pre-flight.
   - **Resolution:** `validate/Test-FinancialRecordsRetention.ps1` read-only-checks label
     action/duration/record flags, policy enabled + locations, and the rule's applied label; exits
     non-zero for CI.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Regulatory defensibility.** Auditors/regulators want proof the WORM control is real and
   reproducible.
   - **Resolution:** The regulatory record label provides admin-proof immutability, and the config file
     is the version-controlled, diffable record of what was deployed and why; `README.md` §2 maps to
     17a-4/FINRA/SOX/MiFID II.
2. **Risk vs. cost:** the control is cheap (E5 entitlement, no meter) but carries a **storage-growth and
   irreversibility** cost — honestly stated in §10 (7-year+ growth, over-scoping is the expensive
   mistake) rather than glossed.
3. **Board/records-committee narrative:** "financial records are retained immutably for the required
   term, applied automatically from a reviewed, reproducible definition, with immutability even admins
   can't override" — exactly what a records committee wants to hear.
4. **Change management:** the irreversibility is treated as a governance gate (lab test, sign-off,
   controlled changes), not an engineering afterthought.
5. **Would I fund this?** Yes — it directly satisfies a hard regulatory obligation, with guardrails
   proportional to the risk.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets and the PowerShell-only reality.** `New-ComplianceTag` (incl.
   `-Regulatory`/`-IsRecordLabel`/`-RetentionAction`/`-RetentionDuration`/`-RetentionType`),
   `New-RetentionCompliancePolicy`, and `New-RetentionComplianceRule -ApplyComplianceTag` are
   reproduced from their references; the scenario correctly states that **regulatory records are
   PowerShell-only** (portal hides the option) — an accurate, product-aligned reason to automate.
2. **Right feature for the obligation.** Regulatory records (Records Management) for WORM, not a plain
   retention policy — and the ladder to lesser controls is documented so organizations don't over-reach.
3. **Accurate behavior notes.** 7-day auto-apply latency, classifier age/size limits (noted as not
   applying to the KQL match path used here), one-rule-per-policy, RetryDistribution, and the
   immutability semantics are stated per the docs.
4. **Accurate licensing.** E3 for retention labels/policies; E5/E5 Compliance/Purview Suite for records
   management (regulatory records, auto-apply, disposition).
5. **Not reinventing native capability.** Uses the native cmdlets and points at the portal for
   visibility; adds value in reproducible, guarded, as-code deployment of an irreversible control.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (over-scoping guardrails; least-restrictive-control guidance; create-or-report + no force-release) | Closed |
| 🔵 Blue Team | Fix | 3 (working `-DryRun`; auto-apply latency/RetryDistribution; validate pre-flight) | Closed |
| 🎩 CISO | Fix | 1 (irreversibility as a governance gate); Pass on defensibility/cost/narrative | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (PowerShell-only regulatory records + ladder documented); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-FinancialRecordsRetention.ps1`, `deploy/Remove-FinancialRecordsRetention.ps1`,
`deploy/config/financial-records-retention.sample.json`, and
`validate/Test-FinancialRecordsRetention.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets) and the irreversibility of regulatory records is treated as a first-class safety constraint.

---

## Correction addendum (2026-09-10)

While building the sibling scenario `scenarios/data-lifecycle-management/
publish-labels-for-manual-application/`, a fresh, dedicated Microsoft Learn grounding pass (direct
`microsoft_docs_search`/`microsoft_docs_fetch`, not carried over from this scenario's original
citations) found a page-level note this scenario's original draft had not accounted for:

> "This scenario isn't supported for regulatory records or default labels for an organizing
> structure... These scenarios require a published retention label policy." — "Automatically apply a
> retention label to retain or delete content"

Independently corroborated by "Declare records by using retention labels" ("...for labels that mark
items as records (**but not regulatory records**), auto-apply those labels...") and by the "Will a
label be overridden?" table in "Learn about retention policies and retention labels" (**Applied with
auto-apply retention label policy** is **"Not applicable"** for labels marking regulatory records).

**This scenario's original design auto-applied a regulatory record label by default** — a
combination Microsoft's own documentation says isn't supported. This is a genuine correctness gap,
not a stylistic preference: the original build's grounding pass did not independently verify the
*auto-apply* page's own scenario-support note, only the *label creation* (`New-ComplianceTag
-Regulatory`) and *publish* pages' notes.

**Fix applied (re-running the relevant lens checks below, not a full new four-lens round since the
object model and safety posture are unchanged — only which objects get created for which config):**

- `deploy/config/financial-records-retention.sample.json` now defaults to `regulatory: false` /
  `isRecordLabel: true` (label renamed `Financial Records - 7yr Record` to match) — a plain record
  label, which auto-apply fully supports.
- `deploy/New-FinancialRecordsRetention.ps1` now creates the label regardless of the `regulatory`
  flag (a valid, standalone `New-ComplianceTag -Regulatory $true` call), but **skips** auto-apply
  policy/rule creation with a clear warning when `regulatory: true`, rather than building the
  unsupported configuration.
- `validate/Test-FinancialRecordsRetention.ps1` skips its policy/rule checks (neither `[PASS]` nor
  `[FAIL]`) when the label is a regulatory record, since their absence is now expected by design.
- `README.md` (§1/§2/§3/§4/§5/§6/§7/§9/§10/§11/§12) and `design.md` (§3/§4/§6/§7) corrected in place;
  `rollback.md` updated to describe both the record and regulatory-record cases accurately.
- The new sibling scenario, `publish-labels-for-manual-application`, is now the documented, only-
  supported completion for the regulatory-record case.

**Re-checked lenses (targeted, not a full round):**
- 🔴 **Red Team** — the original over-scoping/least-restrictive-control findings still hold and are
  unaffected; the new regulatory-record guard *removes* a risk (an unsupported, silently-wrong
  deployment) rather than introducing one.
- 🔵 **Blue Team** — `validate`'s new skip-with-explanation behavior for the regulatory case is itself
  a Blue Team improvement: previously the script would have attempted (and, per Microsoft's docs,
  potentially failed or produced an unsupported policy) with no distinct signal.
- 🟦 **Microsoft Product Owner** — this correction is exactly what this lens exists to catch; closing
  it brings the scenario in line with Microsoft's actual, current product constraint.
- 🎩 **CISO** — no change to cost/licensing/narrative; the regulatory-record case's compliance
  narrative is, if anything, strengthened (the sibling scenario is now explicit that publishing is
  required, not optional).

Also fixed in the same pass: `README.md` §3's automation-surface citation ("surface 1" →
**surface 2**), correcting drift against the current `docs/automation-surface.md` numbering — a
pre-existing, separately-tracked issue (see `PROGRESS.md`) fixed here as a low-risk side effect of
already editing this file, not a full repo-wide sweep.

---

## Correction addendum (2026-09-16)

While building the sibling scenario `scenarios/data-lifecycle-management/
adaptive-scope-auto-apply-label/`, grounding `New-RetentionComplianceRule`'s current Microsoft Learn
reference surfaced a defect in this scenario's own deploy script:
`deploy/New-FinancialRecordsRetention.ps1`'s `New-RetentionComplianceRule` call passed **both**
`-Name` and `-ApplyComplianceTag` in the same `$ruleParams` hashtable. Microsoft's reference documents
`-Name` as belonging only to the `Default` parameter set and states plainly: **"You can't use this
parameter with the `ApplyComplianceTag` or `PublishComplianceTag` parameters."** The `ComplianceTag`
parameter set `-ApplyComplianceTag` requires does not list `-Name` at all — this combination does not
match any documented parameter set and would not have resolved at runtime.
Source: <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>

**This is a genuine correctness defect, not a stylistic preference:** the original build's grounding
pass confirmed `-ApplyComplianceTag` itself but did not independently check `-Name`'s parameter-set
membership against the same cmdlet reference. The sibling scenario's own rule call never repeated the
defect (it omits `-Name` when calling `-ApplyComplianceTag`), which is how the discrepancy surfaced.

**Fix applied (targeted re-check, not a full new four-lens round — the object model, safety posture,
and every other cmdlet call are unchanged; only the rule call's parameter list is corrected):**

- `deploy/New-FinancialRecordsRetention.ps1`'s `$ruleParams` no longer sets `Name`; a comment at the
  call site and an added `.NOTES` entry cite the correction and source.
- `README.md` §6's "Rule cmdlet" row now states "no `-Name`" explicitly; §11 records the fix as a
  known-limitations entry with full provenance.
- `design.md` §4 records the same correction immediately after the object-model diagram.
- The existing idempotency check (`Get-RetentionComplianceRule -Policy $cfg.policy.name`) already
  locates the rule by policy, not by name, so no other script, the validate script, or `rollback.md`
  depended on the rule having an explicit name — none required changes.

**Re-checked lens (targeted):**
- 🟦 **Microsoft Product Owner** — this is precisely the class of defect this lens exists to catch: an
  invented/incorrect parameter combination that doesn't match the documented cmdlet surface. Closing it
  brings the script in line with Microsoft's actual, current parameter-set constraints. No other lens's
  findings are affected — the fix changes no behavior, risk posture, detectability, or cost; it only
  makes the script resolve at runtime as originally intended.
