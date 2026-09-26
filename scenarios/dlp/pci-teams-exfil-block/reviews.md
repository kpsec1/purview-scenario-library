# Four-Lens Review - PCI Teams Card-Data Exfiltration Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Split/obfuscated PAN evasion.** The Credit Card Number SIT matches within a single message's
   proximity window. Splitting a 16-digit PAN across two Teams messages, or spelling digits as
   words, defeats every rule in this policy - none of the three rules correlate across messages
   or time. This is the single most obvious bypass a red-teamer would try first, and the original
   draft didn't call it out.
   - **Resolution:** Added to `README.md` §11 (Known limitations) as an explicit, unmitigated
     residual risk, with a pointer to the planned Adaptive Protection / IRM scenarios that would
     add cumulative, cross-message behavioral detection. Not fixable within a single-message DLP
     rule's design space - documenting it is the correct fix, not pretending it's closed.
2. **Card Ops override path is the highest-value target.** A compromised or coerced Card Ops
   credential can exfiltrate a real PAN externally with one click-through of the justification
   dialog; the only control is after-the-fact log review, and the original draft only reviewed
   that log quarterly.
   - **Resolution:** `README.md` §8 now specifies a **weekly** Advanced Hunting review of Rule 0
     override volume per user, separate from the quarterly full-control review, plus an explicit
     incident-response runbook step for escalating an override that doesn't match the group's
     known workflow.
3. **Guest-initiated thread asymmetry.** Microsoft's documentation states the *tenant* must be
   the chat/thread initiator for the external-block scenario to apply as described; behavior when
   a guest initiates isn't fully enumerated in the source doc.
   - **Resolution:** Left as an explicit `VERIFY` item in `README.md` §11 rather than asserting
     coverage either way - correctly flagged as unverified rather than fabricated.
4. **Image/screenshot exfiltration** (a photo of a card, or a screenshotted spreadsheet) bypasses
   text-pattern DLP entirely.
   - **Resolution:** Already called out in the original draft's Known limitations with a pointer
     to endpoint DLP as the complementary control; no further change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No incident-response runbook.** The original draft had strong detection (alerts, incident
   reports, Activity Explorer, audit-log override justification) but no documented "what does an
   analyst actually do when this fires" procedure - a scenario that ships detection without a
   runbook pushes the operational burden onto whichever analyst is on call the day it matters.
   - **Resolution:** Added a five-step incident-response runbook to `README.md` §8 covering
     triage, true/false-positive classification, and separate handling paths for a Rule 1 hard
     block vs. a Rule 0 override.
2. **Alert routing described but not wired.** The scenario correctly states that alerts land in
   the DLP Alerts dashboard / Defender portal and should be routed to a SIEM, but stops short of
   showing how - acceptable, since building a Sentinel connector is a platform-level action
   outside a single scenario's scope, but worth being explicit that this scenario's deliverable
   ends at the native Purview alert surfaces.
   - **Resolution:** No code change needed; confirmed `README.md` §8 already scopes this
     correctly ("see `docs/automation-surface.md` §4 ... if building a custom pipeline") and
     doesn't overclaim SIEM integration as delivered.
3. **Signal-to-noise on Rule 2 (internal audit).** In a large org, Low-severity alerts on every
   internal card-number mention (including help-desk staff quoting the last 4 digits in normal
   support conversation, which the SIT's checksum will not always distinguish from a full PAN if
   truncation still passes Luhn on a similarly-shaped number) could produce enough volume to be
   ignored.
   - **Resolution:** Not changed - this is a known, accepted tradeoff of audit-first rollout
     (see `design.md` §6, "Internal sharing" decision row) and the KPI section already directs
     tuning based on observed Activity Explorer volume rather than a fixed threshold. Flagging
     here for visibility rather than as an unresolved Fix.

No remaining Fail. Detection, logging, and now the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** clear and proportionate. The control maps to a named, numbered PCI
  DSS requirement (4.2) an assessor will explicitly test; licensing cost is bounded to users who
  already need E5-tier Purview for other controls in a typical enterprise organization, and the scenario
  is explicit in §10 that this is not an incremental Azure/PAYG cost.
- **Change-management impact:** the audit-first internal rule and the staged
  simulation-mode-first rollout in §8 are the right call - a control that hard-blocks 100% of
  internal PAN mentions on day one is a well-documented way to get a DLP program cancelled by
  business pushback within a month; this design explicitly avoids that failure mode.
- **Board-level narrative:** "we block card numbers leaving the company over chat, we give our
  payments team a logged exception path instead of shutting off business, and we watch everything
  that would otherwise be invisible" is a one-sentence, defensible narrative, and the Red Team
  findings (split-PAN evasion, override-path risk) are now documented residual risks rather than
  silent gaps - which is exactly what a board/audit committee needs to see, not a claim of
  perfect coverage.
- **Compliance mapping:** correctly scoped to Requirement 4.2 as the primary driver and
  Requirement 10 (logging) as a secondary one; doesn't over-claim coverage of requirements this
  control doesn't touch (encryption-in-transit, network segmentation, etc. are explicitly out of
  scope per `design.md` §7).
- **Would I fund this?** Yes - bounded cost, clear regulatory hook, and the residual-risk section
  gives an honest basis for deciding whether follow-on investment (Adaptive Protection, IRM) is
  warranted next.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Why a new policy instead of tuning the tenant's default Teams DLP policy?** The tenant
   already ships a default Teams DLP policy that tracks credit-card numbers. The original draft
   built a parallel policy without explaining why the default wasn't extended instead - reads, on
   first pass, like reinventing a native starting point rather than building on it.
   - **Resolution:** Added `design.md` §3a explaining that the default policy is intentionally
     non-blocking, has no group-based override, and editing it in place would conflate this
     control's PCI-specific logic with whatever else a tenant layers onto "the default policy"
     later, plus the risk of an admin reset silently deleting the customization. This is the
     correct, current-best-practice reason to deploy a named policy, not a deviation from product
     direction.
2. **`BlockAccess` for a `TeamsLocation` rule is asserted without a Teams-specific worked example
   from Microsoft.** The cmdlet reference confirms `BlockAccess` is a real, generic parameter and
   the DLP policy reference confirms "Restrict access or encrypt content in Microsoft 365
   locations" is the one supported action category for Teams, but no published example shows the
   two combined for Teams specifically. Shipping this without flagging the gap risks the deploying organization
   discovering at go-live that the flag behaves differently than assumed.
   - **Resolution:** Added an explicit `VERIFY` note to `README.md` §11 and to the deploy script's
     `.NOTES` block, directing the operator to run the §7 functional tests before relying on
     `-Mode Enable` in production. This matches `AGENTS.md` §9's grounding requirement - tag,
     don't fabricate, when a specific combination isn't directly evidenced.
3. **Licensing citation accuracy** - checked against `docs/licensing-matrix.md` and the Microsoft
   Purview service description: Teams chat DLP correctly requires E5-tier (not E3), matching the
   cross-cutting matrix's existing row. No deprecated cmdlets used (`New-DlpPolicy`/`Remove-DlpPolicy`
   are correctly avoided in favor of the current `*-DlpCompliancePolicy`/`*-DlpComplianceRule`
   family, per the deprecation notice on the older cmdlets' own reference pages).
4. **Sensitive info type choice** - using the built-in Credit Card Number SIT rather than a custom
   regex is the right call: it's Luhn-checksum-validated, Microsoft-maintained, and is the same
   SIT every regional "Financial Data" DLP template and the tenant's own default Teams policy
   already use, so it won't surprise an admin comparing this scenario's alerts to the ones they
   already see.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 unmitigated-by-design, documented; 1 review-cadence gap, closed; 1 correctly flagged VERIFY; 1 already covered) | Closed |
| 🔵 Blue Team | Fix | 3 (1 missing runbook, closed; 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 4 (2 closed with documentation/VERIFY tagging, 2 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-PciTeamsDlpPolicy.ps1`. No Fail items were raised. This fragment meets the definition
of done in `AGENTS.md` §9.
