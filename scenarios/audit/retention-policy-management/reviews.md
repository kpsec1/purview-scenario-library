# Four-Lens Review — Audit-Log Retention Policy Management

One round of findings; all **Fix** items applied before finalizing. No **Fail** items raised.

## 🔴 Red Team — Fix (resolved)
1. **Silent shortening destroys evidence.** Removing or shortening a policy quietly reverts a scope to
   the default window, erasing future evidence an investigation relies on. → Rollback opens with a
   Security/Legal warning; removal is documented as reverting to default (not deleting records); an
   "edit instead of remove" alternative is given; deploy never silently mutates an existing policy.
2. **Retention as a cover / tamper vector.** An attacker who can shorten audit retention blinds
   investigators. → Role requirement (Organization Configuration) documented; the config is the
   versioned, diffable record of intended retention so drift is detectable.
3. **Blanket over-retention.** Retaining everything for 10 years is its own risk (cost, data-min
   conflict). → §2/§10 push narrow, obligation-driven scopes; priority banding keeps overrides
   intentional.

## 🔵 Blue Team — Fix (resolved)
1. **`Get` has no `-Identity` and hides the default.** Naive idempotency would misfire. → Scripts list
   all custom policies and match by `Name` client-side; README/design state the default is unlisted.
2. **Is it actually in effect?** Create/remove have latency. → Validate checks duration+priority and
   reports the custom-policy count; §7/§9 document the ~30-min removal latency and the behavioral (lab)
   proof.
3. **Working dry-run.** `-WhatIf` is non-functional in S&C PowerShell. → Custom `-DryRun` on both
   scripts; README §5 makes it step 1.

## 🎩 CISO — Fix (resolved)
1. **Defensible retention schedule.** Auditors ask how long which records are kept and why. → The config
   is the evidence; §2 maps to SOX/PCI/financial record rules; §8 frames changes as reviewed governance.
2. **Cost honesty.** §10 states the 10-year add-on and storage growth plainly. Pass on narrative and
   change-management (reviewed edits, versioned config).

## 🟦 Microsoft Product Owner — Fix (resolved)
1. **Correct cmdlets/params.** `New-/Set-/Get-/Remove-UnifiedAuditLogRetentionPolicy` with mandatory
   `-Priority` (1–10000, lower=higher) and `-RetentionDuration` (documented 5-value enum), `-RecordTypes
   /-Operations/-UserIds`, `-ForceDeletion` — reproduced from Learn; `Get` filter-only / no default
   noted.
2. **Right feature.** Native Audit (Premium) retention policies, not a home-grown export-and-archive.
3. **Honest doc gap.** The portal-shows-more-durations-than-the-enum discrepancy is an explicit VERIFY,
   not a guessed value (`AGENTS.md` §4). 50-policy cap, default-policy behavior, 10-year add-on, and
   Organization Configuration role stated per docs.

## Summary

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (evidence-loss guardrails, tamper/role, over-retention) | Closed |
| 🔵 Blue Team | Fix | 3 (Get/Name idempotency, effect+latency, `-DryRun`) | Closed |
| 🎩 CISO | Fix | 1 (defensible schedule); Pass on cost/narrative | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (enum VERIFY); cmdlets/limits confirmed | Closed |

All Fix items resolved across `README.md`, `design.md`, `deploy/New-AuditRetentionPolicy.ps1`,
`deploy/Remove-AuditRetentionPolicy.ps1`, `deploy/config/audit-retention-policies.sample.json`, and
`validate/Test-AuditRetentionPolicy.ps1`. Meets `AGENTS.md` §9; grounded in Microsoft Learn with the
one duration-enum discrepancy carried as an explicit VERIFY rather than fabricated.
