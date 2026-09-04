# Four-Lens Review — Segregate Trading and Research (Ethical Wall)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized. No **Fail** items were
raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A porous wall is worse than none — it creates false assurance.** The classic IB failure: only one
   direction is blocked, or a user sits in both segments, so the "wall" leaks while everyone believes
   it's solid.
   - **Resolution:** The config encodes **both** one-way block policies (`blockPairs` = Trading→Research
     and Research→Trading); `README.md` §6/§11 and `design.md` §2/§5 state that a full wall needs both
     directions and that segments must be **mutually exclusive**, with §8 requiring a source-attribute
     audit. The validate script checks both policies exist and are assigned to the right segment.
2. **Accidental blast radius on activation.** Activating with a mis-scoped attribute could wall off the
   wrong people (or everyone), disrupting the business.
   - **Resolution:** Safe-by-default — objects are created **Inactive** and **not applied**; `-Activate`
     is explicit and gated behind `-DryRun` and Compliance/Legal sign-off; `README.md` §7 includes a
     **no-collateral test** (users within a side, and non-IB users, still communicate).
3. **Bypass via app-only apps / non-IB groups.** Apps in app-only mode and non-M365 groups can sidestep
   IB if not accounted for.
   - **Resolution:** `README.md` §11 notes IB supports M365 Groups only (DLs/SGs are non-IB) and points
     at the SharePoint app-only bypass consideration, so operators know the edges rather than assuming
     total coverage.
4. **Insider using the wall as cover / removing it quietly.** Deletion of a compliance wall must not be
   casual.
   - **Resolution:** Rollback opens with a Compliance/Legal warning, is staged, and requires explicit
     `-Apply`/`-Delete`; the deploy is create-or-report (no silent mutation). Lifting the wall is framed
     as a governed decision, not an ops convenience.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **"Is it actually enforced?" is non-obvious.** Application is async and delayed; a policy can be
   Active but not yet applied, or application can error.
   - **Resolution:** The validate script reports `Get-InformationBarrierPoliciesApplicationStatus` and,
     with `-RequireActive`, hard-checks Active state; `README.md` §8 makes application status the key
     operational signal and documents the ~30-min/5,000-per-hour/24-h timings so operators don't
     mistake latency for failure.
2. **Deactivation that doesn't take effect.** Setting a policy Inactive without re-applying leaves users
   still blocked — a subtle rollback trap.
   - **Resolution:** `Remove-...ps1` warns that deactivation needs an application run and provides
     `-Apply`; `rollback.md` calls this out explicitly as a two-part act.
3. **Working dry-run.** `-WhatIf` doesn't function in S&C PowerShell.
   - **Resolution:** Both scripts implement `-DryRun` printing the exact cmdlets; `README.md` §5 makes
     dry-run the first step.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Examiner-grade reproducibility.** Regulators probe how the wall is defined and whether it's
   consistently enforced.
   - **Resolution:** The config file is the versioned, diffable definition; `README.md` §2 maps to
     FINRA 2241 / SEC Reg AC / MiFID II / MAR, and §8 frames the config as the audit artifact.
2. **Risk vs. cost:** the control is E5-entitlement (no meter); the real cost is keeping segmentation
   accurate and handling exceptions — stated honestly in §10, with exceptions modeled as their own
   segments rather than bypasses.
3. **Board/compliance narrative:** "research and trading are segregated in our collaboration tools by
   an enforced, reproducible information barrier, with a controlled activation and audit trail" — a
   strong, specific position.
4. **Change-management:** activation removes people from conversations, so it's treated as a
   communicated, signed-off change with a staged off-ramp.
5. **Would I fund this?** Yes — it directly satisfies a mandatory conflict-of-interest control with
   guardrails proportional to its live-communication impact.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets and flow.** `New-OrganizationSegment`, `New-InformationBarrierPolicy`
   (`-AssignedSegment`/`-SegmentsBlocked`/`-State`), `Set-InformationBarrierPolicy`, and
   `Start-InformationBarrierPoliciesApplication` are reproduced from Microsoft's own worked examples,
   including the two-one-way-policies pattern and one-policy-per-segment rule.
2. **Right tool for the obligation.** IB (not permissions or DLP) for a communication wall, with block
   policies (Microsoft's recommended default) — product-idiomatic.
3. **Accurate behavior + IB modes.** Async application timings, 24-h SharePoint propagation, M365-Groups-
   only, and the Legacy/SingleSegment/MultiSegment mode differences (segment limits, multi-segment
   membership) are stated per the docs, with the caveat to confirm tenant mode.
4. **Accurate licensing.** E5 / E5 Compliance / IRM / IB add-on.
5. **Not reinventing native capability.** Uses the native cmdlets and points at the portal + SharePoint
   IB enablement for the pieces beyond the Teams wall; adds value in reproducible, staged, as-code
   deployment.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (both-direction + exclusive-segment wall; safe-by-default activation + no-collateral test; app-only/non-IB edges; governed deletion) | Closed |
| 🔵 Blue Team | Fix | 3 (application-status detection + `-RequireActive`; deactivation-needs-apply trap; working `-DryRun`) | Closed |
| 🎩 CISO | Fix | 1 (examiner-grade reproducibility); Pass on cost/narrative/change-mgmt | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (IB modes/timings documented); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-TradingResearchBarrier.ps1`, `deploy/Remove-TradingResearchBarrier.ps1`,
`deploy/config/trading-research-barrier.sample.json`, and
`validate/Test-TradingResearchBarrier.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets) and the live-communication impact of activation is treated as a first-class safety constraint.
