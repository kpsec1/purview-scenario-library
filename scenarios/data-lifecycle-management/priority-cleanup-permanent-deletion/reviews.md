# Four-Lens Review - Priority Cleanup Permanent Deletion (SharePoint & OneDrive)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Content not under an eDiscovery hold gets zero per-item human review before an IRREVERSIBLE
   action** - same structural gap as the `priority-cleanup-sharepoint-onedrive` sibling's Red Team
   finding #1, but the consequence here is permanent, not Recycle-Bin-recoverable. Once the policy
   is live, the entire safety burden sits on the one-time pre-turn-on simulation review plus the
   undocumented, unverifiable "Delete data permanently" portal step.
   - **Resolution:** `README.md` §8 states this is why the scope must be narrow and incident-specific
     rather than the sibling's broad/continual pattern; `rollback.md`'s "Before you ever reach Stage
     1" section states plainly that the real safeguards are all upstream of deletion, because there
     is no downstream one.
2. **This is a plausible anti-forensics / evidence-destruction vector for a malicious or coerced
   insider holding Priority Cleanup Admin.** A bad actor could act on a specific site/account
   *before* an eDiscovery hold is placed on it, since the review-set exception only protects content
   already copied to a review set - timing that content's deletion ahead of a hold defeats that
   safeguard entirely, and un-held content gets no per-item approval either (finding #1).
   - **Resolution:** `README.md` §3 states the review-set exception explicitly rather than implying
     it's a general safety net; §11 lists "no recovery path whatsoever" as the scenario's highest-
     consequence property; `design.md` §7 frames the driving use case as a *confirmed, already-
     contained* incident (not a general-purpose admin tool) specifically to narrow this risk surface
     in how the scenario is positioned and used.
3. **A bespoke, bad, or malicious `contentMatchQuery` is the single highest-leverage failure mode**,
   more so than either priority-cleanup sibling scenario, because there is no Recycle Bin backstop
   and no Microsoft worked-example query to anchor against (unlike the sibling's verbatim
   `ProgID:Media AND ProgID:Meeting`).
   - **Resolution:** the deploy script refuses to run against the sample config's placeholder query;
     `README.md` §8 requires a second reviewer on the query itself, not just on simulation results;
     the config's `_ruleNote` states there is no generic pattern to fall back on.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A `[PASS]` from `validate/` could be misread as "permanent deletion is configured and working."**
   It only confirms the shared base objects exist - it cannot see whether the portal-only content-
   disposition step was ever completed.
   - **Resolution:** the validate script prints an explicit, high-visibility warning
     (`*** This script CANNOT confirm permanent-deletion mode is active ***`) rather than a quiet
     caveat buried in `.NOTES`; `README.md` §7 states the same limitation as the lead item, not an
     afterthought.
2. **Two near-identical audit operation names one keystroke apart in meaning
   (`PriorityCleanupFileDeleted` vs. the sibling's `PriorityCleanupFileRecycled`) are easy to
   conflate in a detection rule**, and getting it wrong means a SOC either fails to alert on genuine
   permanent deletions or, worse, treats a Recycle-Bin move (the weaker sibling outcome) as if it
   were the high-severity, irreversible event.
   - **Resolution:** `README.md` §6/§7/§8 and the validate script all state both operation names
     side by side with their distinct meanings, rather than documenting only this scenario's own
     operation name in isolation.
3. **No native volume-based circuit breaker.** Microsoft's documentation describes no rate limit,
   anomaly threshold, or pause mechanism if a live (post-turn-on) policy somehow matches and deletes
   far more than the simulation indicated - unlike DLP's incident-based alerting model, there's no
   documented "pause after N deletions" safeguard.
   - **Resolution:** `README.md` §8 recommends treating every `PriorityCleanupFileDeleted` event as
     a SIEM-forwarded, high-severity signal requiring an incident-record entry, as a compensating
     control given the absence of a native platform throttle; not presented as a solved problem.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Asymmetric risk profile versus the sibling scenario demands its own approval gate, not reuse of
   the sibling's sign-off.** A CISO who approved the (recoverable) sibling scenario should not treat
   that approval as covering this one - the downside here is categorically worse if misconfigured.
   - **Resolution:** `README.md` §2's callout states directly that this is not a routine tool and
     names the sibling as the default choice; the scenario's driving use case (§ README.md §1, design
     §1) is framed as "already a confirmed incident," implying a distinct approval trigger, not a
     standing delegation.
2. **Deploying a public-preview feature for an irreversible action compounds two risks that would
   each be manageable alone.** Preview features can change behavior before GA; irreversible actions
   cannot be undone if that change happens mid-flight.
   - **Resolution:** `README.md` §11 states the preview status and rollout-date uncertainty as the
     first bullet, not buried; recommends re-verifying tenant availability before relying on the
     scenario, and flags the GCC/GCC High/DoD timing gap as unconfirmed rather than assumed.
3. **The funding/authorization narrative here is risk-closure on a specific, already-identified
   incident - not a capability to hand out broadly.** Positioning this as a general admin tool
   invites scope creep into routine use, which is precisely the sibling scenario's job.
   - **Resolution:** `README.md` §10 and `design.md` §7 both frame the financial/risk case as
     incident-specific risk-avoidance, explicitly contrasted with the sibling's cost-avoidance
     framing.
4. **Would I fund this?** Yes, narrowly - as an incident-response capability gated behind explicit,
   per-use authorization (not a standing policy), with the two-person rule and audit trail as the
   compensating controls for its irreversibility. I would require the query and scope be reviewed by
   someone other than the incident responder before every use, and I would not authorize it as a
   general storage-reclamation tool - that's what the sibling scenario is for.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct feature, correctly differentiated from both the sibling scenario and from eDiscovery
   search-and-purge.** This is the SharePoint/OneDrive-specific "permanent deletion" sub-feature of
   Priority Cleanup - not a rebuild of eDiscovery's own hard-delete-via-search capability, which
   `design.md` §8 explicitly calls out as a distinct, out-of-scope companion.
2. **The central disclosed gap (no CLI/Graph parameter for the content-disposition step) is
   correctly verified, not assumed.** This build directly fetched `New-ComplianceTag`'s parameter
   reference and confirmed `-RetentionAction` accepts only `Delete`/`Keep`/`KeepAndDelete` - the
   scenario doesn't merely note the feature page is portal-only, it corroborates that with the
   cmdlet reference itself. This is a stronger grounding standard than either priority-cleanup
   sibling needed to meet for its own gaps.
3. **Preview status and rollout date are cited verbatim and correctly**, including the honest
   disclosure that this build's own date (2026-09-09) is after the stated 2026-08-24 rollout start,
   without overclaiming universal or government-cloud availability on that basis.
4. **Accurate, correctly-scoped licensing** - states the shared E5-tier entitlement and toggle
   rather than inventing a separate meter for this sub-feature.
5. **No deprecated paths; all cited Microsoft Learn pages and cmdlet references were fetched
   directly during this build.**

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (no per-item review for un-held content under an irreversible action; anti-forensics/insider-misuse vector; bespoke-query blast radius with no Recycle Bin backstop) | Closed |
| 🔵 Blue Team | Fix | 3 (a validate `[PASS]` could be misread as confirming permanent-deletion mode; audit-operation-name confusion with the sibling; no native volume circuit breaker) | Closed |
| 🎩 CISO | Fix | 3 (asymmetric risk needs its own approval gate; preview status compounds irreversibility risk; funding narrative must stay incident-scoped, not general-purpose); confirmed on funding recommendation | Closed |
| 🟦 Microsoft Product Owner | Fix | 2 (confirmed correct feature differentiation; confirmed the central gap via direct cmdlet-reference verification, not assumption) | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1`,
`deploy/Remove-PriorityCleanupPermanentDeletionPolicy.ps1`,
`deploy/config/priority-cleanup-permanent-deletion.sample.json`,
`validate/Test-PriorityCleanupPermanentDeletionPolicy.ps1`, and `rollback.md`. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are grounded in
Microsoft Learn (no invented cmdlets - the central construction gap, "Delete data permanently" having
no confirmed CLI/Graph parameter, is corroborated directly against the `New-ComplianceTag` cmdlet
reference rather than merely inferred from the feature page's silence), and this scenario's
materially higher-consequence, irreversible outcome is treated as the first-class design constraint
throughout - never softened to match the recoverable sibling scenario's tone.
