# Four-Lens Review - Publish Retention Labels for Manual Application

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Human-dependent coverage is a hard limit, and for a regulatory record it's the *only*
   mechanism.** A user who forgets, or deliberately declines, to apply the label leaves sensitive
   financial content completely unretained - and unlike the auto-apply sibling, there is no
   fallback query that eventually catches it, because Microsoft doesn't offer one for regulatory
   records.
   - **Resolution:** `README.md` §8/§10/§11 state this plainly ("the cost is human, not technical")
     rather than implying the policy alone provides coverage, and recommend a periodic content-
     search spot-check (query for known financial-record signals in the scoped locations, cross-
     reference against labeled items) plus operator/user training as the compensating control. For
     any label that *isn't* a regulatory record, `README.md` §11 and `design.md` §7 explicitly
     recommend pairing this scenario with the sibling's auto-apply policy rather than relying on
     publishing alone.
2. **Coverage gap by location, not just by user behavior.** Retention labels - published or
   auto-applied - aren't supported at all for Exchange public folders, Skype for Business, Teams
   chat/channel messages, or Viva Engage messages [[7]](#references). A financial record discussed
   only in Teams chat text (not as a file) can never be reached by this scenario.
   - **Resolution:** `README.md` §11 now states this location boundary explicitly rather than
     leaving it implicit in the locations table; organizations with that exposure need a retention
     *policy* (not a label) for those workloads - a separate, already-out-of-scope control.
3. **A disabled/removed publish policy is silent - no alert tells anyone the label stopped being
   offered.**
   - **Resolution:** `README.md` §8 names **DistributionStatus** as the signal to monitor and
     `validate/Test-PublishRetentionLabelPolicy.ps1` surfaces it and the policy's `Enabled` state on
     every run, so a CI-style pre-flight catches an unexpected disable before it's discovered the
     hard way (a user reporting the label is gone).

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **"Is the label actually reaching users?"** Distribution can silently stall (Off (Error)), the
   same failure mode the auto-apply sibling has, but here it means *nobody* can select the label at
   all, not just that new content misses auto-labeling.
   - **Resolution:** `README.md` §7/§8 document `Set-RetentionCompliancePolicy -RetryDistribution`
     for a stuck policy; `validate/Test-PublishRetentionLabelPolicy.ps1` surfaces `DistributionStatus`
     on every run.
2. **Operability of validation given this scenario touches no label data.** Need a fast, safe
   pre-flight that doesn't overreach into checking the label itself (out of scope by design).
   - **Resolution:** `validate/Test-PublishRetentionLabelPolicy.ps1` checks label *existence* only
     (never its settings - that's the sibling's validate script's job), then policy/rule health;
     read-only, exits non-zero for CI.
3. **Silent deployment mistakes.** Without a working dry-run, a typo in the label name could create
   a policy/rule that silently never publishes anything usable (a rule with a `-PublishComplianceTag`
   value that doesn't match any label would either fail at creation or reference nothing real).
   - **Resolution:** The deploy script implements a real `-DryRun`; more importantly, it calls
     `Get-ComplianceTag` first and **throws** immediately if the named label doesn't exist, rather
     than attempting to create a rule against a name that might not resolve.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Pass**

1. **This closes a real compliance gap, not a nice-to-have.** For the regulatory-record case, this
   scenario is the *only* Microsoft-supported way to make the label usable at all - funding it isn't
   optional if the underlying regulatory obligation (SEC 17a-4-class WORM) is real.
2. **Risk vs. cost:** zero incremental licensing; the residual risk is operational (human coverage,
   §11) - honestly disclosed rather than glossed over, and it's the same residual risk the
   regulatory obligation always carried, not one this scenario introduces.
3. **Board/records-committee narrative:** "the regulatory label can be immediately, manually applied
   by the people who create the record - and that's not a compromise, it's how Microsoft designed
   regulatory records to work. Auto-apply was never a supported option for this class of label."
4. **Change management:** low-risk relative to the sibling - publishing/unpublishing never touches
   already-labeled content, unlike the sibling's irreversible auto-apply action.
5. **Would I fund this?** Yes, and it should have shipped alongside the sibling scenario originally -
   without it, the sibling's regulatory-record claim had no supported way to actually reach content.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, current cmdlets, precisely scoped.** `New-RetentionComplianceRule -PublishComplianceTag`
   is reproduced exactly from its reference (mandatory, mutually exclusive with `-ApplyComplianceTag`/
   `-Name`, no content-match parameters); `New-RetentionCompliancePolicy`'s location parameters match
   the documented publish-supported locations.
2. **Right feature for the obligation, and the one Microsoft actually requires here.** This finding
   is the review working as intended: the sibling scenario's original auto-apply-a-regulatory-label
   design was **not** aligned with Microsoft's documented product behavior; this scenario, and the
   correction backported into the sibling, bring the pair in line with the actual, current product
   constraint rather than an assumed one.
3. **Accurate behavior notes.** Publish timing (SharePoint/OneDrive ~1 day, up to 7; Exchange up to 7
   days, ≥10 MB), `RetryDistribution`, one-rule-per-policy, and "a label can be in multiple label
   policies" are all stated per the docs, not inferred.
4. **Accurate licensing.** No new SKU beyond what the label itself already required.
5. **Not reinventing native capability.** Pure native cmdlet usage; the scenario's only value-add is
   making the *correct* mechanism reproducible and safe to re-run, not building around a gap.

No Fail raised.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (human-coverage limit + compensating controls; unsupported-location boundary disclosed; DistributionStatus monitoring) | Closed |
| 🔵 Blue Team | Fix | 3 (RetryDistribution + DistributionStatus signal; label-existence-only validation scope; fail-fast on a missing label) | Closed |
| 🎩 CISO | Pass | Confirms this scenario is required, not optional, for the regulatory-record case; residual risk honestly disclosed | - |
| 🟦 Microsoft Product Owner | Pass | Confirms correct, current cmdlets; confirms the review process itself caught the sibling's product-alignment gap | - |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-PublishRetentionLabelPolicy.ps1`, `deploy/Remove-PublishRetentionLabelPolicy.ps1`,
`deploy/config/publish-financial-records-label.sample.json`, and
`validate/Test-PublishRetentionLabelPolicy.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented
cmdlets), and the auto-apply/regulatory-record incompatibility this build surfaced is backported
into the sibling `retention-labels-financial-records` scenario's own `reviews.md` as a correction
addendum rather than left standing uncorrected.

## References

Same source set as `README.md` §12; the load-bearing citations for this review are [[4]](#references)
("isn't supported for regulatory records... require a published retention label policy"),
[[5]](#references) ("for labels that mark items as records (but not regulatory records), auto-apply
those labels"), and [[7]](#references) (unsupported locations; "a single retention label can be
included in multiple retention label policies").
