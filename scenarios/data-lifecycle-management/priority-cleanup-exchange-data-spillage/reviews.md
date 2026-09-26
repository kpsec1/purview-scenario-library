# Four-Lens Review - Priority Cleanup for Exchange Data Spillage

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This is a documented evidence-destruction / spoliation tool, and the scenario has to say so in
   those terms, not just "irreversible."** A malicious or compromised insider under active litigation
   hold has a direct motive to get their own content deleted before opposing counsel or investigators
   see it. The feature is explicitly designed to bypass the hold that would normally prevent exactly
   that.
   - **Resolution:** `README.md` §2 states the spoliation risk explicitly and quotes Microsoft's own
     advice that regulated organizations using Preservation Lock may prefer the tenant-wide toggle
     **off**. `design.md` §1 frames the control as "more dangerous than everything else in this
     repo's Data Lifecycle Management coverage."
2. **The 3-approver requirement is only as strong as its role-assignment hygiene.** If the same
   individual can hold, say, both a "Retention Management"-tier role and later be added as the
   "eDiscovery admin" approver on the same policy (nothing in the documented role tables structurally
   prevents one person from qualifying for multiple stages), the two-/three-person rule collapses
   toward a rubber stamp.
   - **Resolution:** `README.md` §3 states the requirement for 3 **distinct individual users**;
     `README.md` §8 recommends this as an operational control (verify approver distinctness as part
     of deployment review), and flags it as a design gap this scenario's scripts cannot enforce
     themselves - the platform, not this scenario's code, is the only place this could be structurally
     prevented, and Microsoft's own docs don't state that it is.
3. **An over-broad `ContentMatchQuery` is a one-way door with no recourse** - unlike a mis-scoped
   retention *policy* (which can be caught and reversed before the retention clock runs out), a
   mis-scoped priority cleanup query destroys content the moment approvals complete.
   - **Resolution:** The deploy script requires an explicit `-Simulate`/`-Enabled`/`-DryRun` choice
     (never a silent default), the sample config's `_ruleNote` warns against broad queries, and
     `README.md` §8/§10 name query scope as the single highest-leverage control and the "expensive
     mistake" respectively.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The two priority-cleanup-specific audit operations have no friendly names in the portal.**
   `PriorityCleanupTagApplied`/`PriorityCleanupDelete` must be searched by raw operation name - easy
   to miss if a SOC's Sentinel/SIEM rules are built only from the portal's friendly-name picker.
   - **Resolution:** `README.md` §7/§8 name both operations explicitly and recommend forwarding them
     to Sentinel/SIEM given their severity; `validate/Test-PriorityCleanupExchangePolicy.ps1` prints a
     reminder to search by Cleanup ID rather than relying on friendly names.
2. **No API-level visibility into the approval queue.** A SOC cannot programmatically monitor "how
   many items are pending disposition right now" or alert on a stalled approval without the portal.
   - **Resolution:** Disclosed as a hard platform limitation, not glossed over - `README.md` §7/§11
     and `design.md` §3 state plainly that this scenario's scripts stop at provisioning/validation and
     cannot observe the approval workflow. §8 notes the one available compensating signal (weekly
     email reminders to approvers) as a partial mitigation, not a fix.
3. **Operability of validation given the object-classification uncertainty.** Guessing an unconfirmed
   boolean property (e.g. "IsPriorityCleanup") on the returned label/policy/rule object would produce
   a validate script that silently reports `False` forever if the property name is wrong.
   - **Resolution:** `validate/Test-PriorityCleanupExchangePolicy.ps1` uses the officially documented
     `-PriorityCleanup` **filter switch** on each `Get-*` cmdlet instead - a mechanism confirmed
     directly in Microsoft's own syntax reference, not inferred from an unconfirmed property.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **This control needs a governance gate the scenario's code cannot itself provide** - a documented,
   Legal-approved, per-incident justification, not a standing capability anyone with the role can
   invoke.
   - **Resolution:** `README.md` §2's callout requires Legal sign-off per use and explicitly says
     "never a standing policy"; §8 recommends disabling/deleting the deployed objects once the
     specific incident is closed rather than leaving them live.
2. **Preview status is a real go/no-go input for a board-level risk conversation**, not a footnote.
   - **Resolution:** Flagged prominently - in the summary (§1 heading context), the driver section
     (§2's callout), and §11's first bullet - not buried once in a references list.
3. **Would I fund this?** Yes, conditionally: the data-spillage use case (irreversible exposure,
   waiting for a 2-year retention policy to lapse is not acceptable) justifies the capability existing
   and being deployable on demand. But the CISO's actual recommendation, mirrored from Microsoft's own
   guidance, is to leave the tenant-wide toggle **off by default** and turn it on only for the duration
   of an approved incident response - which is exactly the posture `README.md`/`rollback.md` describe
   (deploy, use, then §9 decommission).
4. **Licensing and cost are the least interesting part of this control's risk profile** - same E5 tier
   as Records Management, no separate meter (§10) - the CISO conversation is entirely about process
   risk, not spend.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct, current cmdlets, used as documented.** `New-ComplianceTag`/`New-RetentionCompliancePolicy`/
   `New-RetentionComplianceRule`'s official `-PriorityCleanup` parameter sets are used directly, not
   approximated; `-SkipPriorityCleanupConfirmation`, `-IsSimulation`, `-StartSimulation`,
   `-EnforceSimulationPolicy` are used per their documented purpose.
2. **Two genuine construction gaps, correctly flagged rather than glossed.** The
   `-MultiStageReviewProperty` stage shape and the `RetentionDuration 0`/`TaggedAgeInDays` "as soon as
   possible" mapping are not confirmed by a Microsoft worked example specific to priority cleanup.
   - **Resolution:** Both called out explicitly in `design.md` §4, `README.md` §6/§11, and the config
     file's own `_labelNote` - not asserted as fact. This is the correct posture per `AGENTS.md` §4
     rather than inventing a plausible-looking shape.
3. **Right feature for the job, not a reinvention.** This is materially different from - and does not
   duplicate - this repo's `ediscovery`/`records-management` retention-override coverage: priority
   cleanup is the only control designed to *defeat* a hold, where everything else in this repo is
   designed to *honor* one. `design.md` §7 notes eDiscovery search-and-purge as a complementary (not
   competing) tool for the "avoid the end-user retention message bar" workflow Microsoft's own docs
   describe.
4. **Accurate licensing**, confirmed directly against the Purview service description's dedicated
   priority-cleanup licensing line (same E5-tier family as Records Management), not assumed by
   analogy.
5. **No deprecated paths.** All cited cmdlets and portal locations are current per this build's direct
   fetch of the official Microsoft Learn pages.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (spoliation framing; approver-distinctness gap disclosed; query-scope as the one-way door) | Closed |
| 🔵 Blue Team | Fix | 3 (unfriendly audit op names; no approval-queue API - disclosed, not hidden; classification via documented filter switch, not a guessed property) | Closed |
| 🎩 CISO | Fix | 1 (governance gate framing); confirmed on preview-status prominence, funding recommendation, and licensing simplicity | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 (two construction gaps correctly flagged as VERIFY, not fabricated); confirmed correct on cmdlets, feature choice, and licensing | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-PriorityCleanupExchangePolicy.ps1`, `deploy/Remove-PriorityCleanupExchangePolicy.ps1`,
`deploy/config/priority-cleanup-exchange.sample.json`, `validate/Test-PriorityCleanupExchangePolicy.ps1`,
and `rollback.md`. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9; product facts are grounded in Microsoft Learn (no invented cmdlets - the two genuine
construction gaps are disclosed as VERIFY, not presented as confirmed), and the irreversibility of
priority cleanup is treated as the scenario's central safety constraint throughout.
