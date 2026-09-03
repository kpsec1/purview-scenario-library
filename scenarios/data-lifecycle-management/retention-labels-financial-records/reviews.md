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
   retention policy — and the ladder to lesser controls is documented so buyers don't over-reach.
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
