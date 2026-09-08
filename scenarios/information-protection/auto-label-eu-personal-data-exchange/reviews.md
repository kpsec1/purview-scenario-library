# Four-Lens Review — Auto-Label EU/UK Personal Data in Exchange Email

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. This
scenario is a deliberate combination of two already-reviewed siblings
(`auto-label-confidential-exchange` and `auto-label-eu-personal-data-sharepoint`), so this review
focuses on what the *combination* changes, not on re-litigating findings each sibling's own
`reviews.md` already closed. One round of findings below; all **Fix** items were applied before
this file was finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Independent `-SensitiveInfoTypeName` localization across two sibling scenarios creates a
   silent cross-channel coverage gap this scenario's own grounding didn't originally surface.**
   `auto-label-eu-personal-data-sharepoint` and this scenario both accept the same-shaped
   localization parameter and default to the same three-SIT bundle, which invites an operator to
   assume the tenant's "EU personal-data program" is configured consistently across both channels.
   Nothing enforces that: a buyer who narrows one script's SIT list (e.g., to Germany + France
   only) and not the other's ends up with a data class that's caught in one channel and silently
   missed in the other, with neither script erroring or warning. This is a new finding specific to
   this scenario's existence as a combination of two independently-parameterized siblings — neither
   sibling's own review could have found it alone.
   - **Resolution:** Added an explicit new item to `README.md` §11 describing the exact failure
     mode (an Italy Fiscal Code caught in email but not SharePoint, or vice versa) and added a
     standing review-cadence check to §8 ("confirm both scripts' `-SensitiveInfoTypeName` lists
     match") rather than treating this as a one-time deployment step.
2. **The external-recipient encryption default gap, inherited mechanically from
   `auto-label-confidential-exchange`, needed to be reframed rather than just copied — its stakes
   are measurably different here.** The Exchange sibling frames GDPR/CCPA as one of two adjacent
   drivers for a U.S.-format SIT pair; this scenario's entire premise is GDPR-format personal data.
   A first draft that simply repeated the sibling's framing verbatim would understate that, for
   this scenario specifically, the unencrypted-external-mail default is a *direct* GDPR Article
   33/34 breach-notification exposure, not an adjacent-regulation concern.
   - **Resolution:** `README.md` §11 restates this finding with the sharper GDPR-specific framing
     and explicitly recommends treating `-ExternalMailRightsManagementOwner` configuration (or a
     paired content-based DLP rule) as higher-priority for this scenario than for the U.S.-SIT
     sibling — not an equally-optional extension. `design.md` §6 documents this as "the one place
     the two siblings' designs don't combine without an explicit decision."
3. **The compromised/repurposed excluded-mailbox exfiltration path, also inherited from
   `auto-label-confidential-exchange`, carries the same sharper GDPR-specific stakes as finding 2
   and needed the same explicit reframing, not a verbatim copy.**
   - **Resolution:** `README.md` §11 restates the finding with the GDPR-Article-33/34-specific
     framing (a breach through that channel is "a direct GDPR exposure, not a secondary one").
4. **Every other bypass class — manual-label-first, scan-cadence/simulation-window timing, EU
   national-ID checksum variance, the UK-inclusion naming quirk — is inherited correctly, not new
   to this combination, and doesn't need re-derivation.** Confirmed each is already documented in
   `README.md` §11 with an explicit "inherited unchanged from `<sibling>`" pointer rather than a
   second, potentially-drifting copy of the same prose.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Near-identical policy names across four now-deployed Information Protection auto-labeling
   scenarios create a real incident-response risk: disabling the wrong policy under time
   pressure.** `Confidentiality - Auto-Label EU Personal Data in Exchange Email` (this scenario) and
   `Confidentiality - Auto-Label PII in Exchange Email` (`auto-label-confidential-exchange`) differ
   by a few words in the middle of a long string — exactly the kind of name an on-call operator
   skims past during a live encryption-side-effect incident. This wasn't a risk either sibling's own
   review could have caught alone, since it only exists once a tenant has more than one of these
   policies deployed.
   - **Resolution:** Added a "Related auto-labeling policies in this tenant" disambiguation table
     to `README.md` §8, listing all four sibling-family policy names side by side with their
     location and SIT set, specifically for pre-incident reference.
2. **The SIT-list-drift finding (Red Team, above) is also an operability gap, not just a data-loss
   one — there's no automated way to detect the drift, only a documented manual check.** Confirmed
   no realistic automated fix exists within this scenario's scope: the two scripts are independent,
   author-only reference code with no shared state store, and building one would be a
   disproportionate abstraction for a two-script drift check (`AGENTS.md`'s "don't design for
   hypothetical future requirements" principle). A documented, standing manual review step is the
   honestly-scoped answer.
   - **Resolution:** No further code change; confirmed the `README.md` §8/§11 additions from the
     Red Team resolution are also the correct Blue Team answer — recorded here as deliberately
     checked, not overlooked.
3. **Activity Explorer's policy/rule attribution gap is now materially more consequential with a
   third Exchange-targeting policy in play, and this needed to be stated plainly rather than
   inherited by reference alone.** With three sibling-family policies now potentially targeting
   Exchange in the same tenant (this scenario, `auto-label-confidential-exchange`, and — if a buyer
   ever adds — others), Activity Explorer's inability to name which specific policy applied a label
   becomes a real "which of our three policies did this" question, not a hypothetical one.
   - **Resolution:** `README.md` §7 step 4 updated to name the three-policy scenario explicitly
     ("plausible once both this scenario and `auto-label-confidential-exchange` are deployed
     against the same label") rather than leaving the multi-policy case abstract.

No remaining Fail. The operational surface (Activity Explorer's documented delay and attribution
limits, Items to review during simulation, the new policy-disambiguation table, and the SIT-list-
drift review-cadence item) is honestly represented as the point where combining three deployed
scenarios introduces real, if manageable, operational complexity — not hidden behind reused
language that would understate it.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate, and the two Red Team GDPR-sharpening findings
  materially improve the honesty of this scenario's pitch — a CISO now sees explicitly that, for
  this specific EU/UK-formatted data class, the default configuration protects internal mail but
  not external mail by default, and that this is the single case in this library's three-scenario
  auto-labeling family where that gap has the most direct regulatory consequence.
- **Board-level narrative:** "we complete the classification program already funded for
  SharePoint/OneDrive EU/UK data and U.S.-format email, closing the one remaining gap — EU/UK
  personal data in email — while being explicit that this exact combination is where our
  external-mail encryption gap carries the most direct GDPR breach-notification exposure" is a
  stronger, more specific narrative than treating this as a routine third deployment.
- **Compliance mapping:** GDPR Article 32 as the primary driver, correctly not overclaimed as
  Article-4(1)-complete personal-data coverage (§2), with the sharpened Article 33/34 framing in
  §11 giving a concrete, scoped basis for prioritizing the external-encryption follow-up decision.
- **Change-management impact:** identical to both sibling scenarios' own already-reviewed
  change-management profile (staged rollout, encryption side-effect on internal mail) — no new
  change-management risk introduced by combining them, and the new policy-disambiguation table
  directly reduces incident-response risk for the operations team.
- **Would I fund this?** Yes — this is the lowest-incremental-cost fragment in the three-scenario
  family (§10: no additional licensing over either already-funded sibling), it closes a real,
  named gap, and its own review surfaced two genuinely new findings (SIT-list drift, policy-name
  confusion) that only exist once a tenant runs all three — exactly the kind of finding a fourth
  independent review pass should be expected to catch, and did.

No Fix/Fail items from this lens — it benefited directly from the Red Team and Blue Team findings.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

- **Every cmdlet, parameter, and SIT name in this scenario is inherited verbatim from an
  already-grounded sibling, not re-derived or guessed.** Cross-checked directly against both
  source scripts during this build: `-ExchangeLocation`, `-ExchangeSenderException`,
  `-ExternalMailRightsManagementOwner`, and the "no `-ExchangeLocationException` parameter exists"
  claim all match `auto-label-confidential-exchange/deploy/
  New-ConfidentialAutoLabelExchangePolicy.ps1` and its `.NOTES` citations exactly; the three
  default SIT names, the `-SensitiveInfoTypeName` parameter shape, and the
  `Get-DlpSensitiveInformationType`-based resolution pattern all match
  `auto-label-eu-personal-data-sharepoint/deploy/New-EuPersonalDataAutoLabelPolicy.ps1` exactly. No
  new product surface was introduced by this combination — confirming that was the point of this
  check, not assuming it because both sources are "already-reviewed."
- **No deprecated cmdlets, no invented parameters, no reinvented native capability.** This scenario
  is a direct application of `New-AutoSensitivityLabelPolicy`/`New-AutoSensitivityLabelRule`
  against the Exchange workload with an EU/UK SIT condition set — exactly the product-intended use
  of auto-labeling policies, not a workaround for a missing native feature.
- **Licensing citation accuracy** — confirmed no separate or additional licensing applies to this
  scenario versus either sibling; all three draw from the same Information Protection entitlement
  tier in `docs/licensing-matrix.md` §2.
- **The two open VERIFY items (SIT-name byte-exact casing; `Get-AutoSensitivityLabelRule` read-back
  casing) are correctly carried forward as open, not resolved by guessing** — both are the same
  unresolved items the SharePoint/OneDrive EU sibling's own Product Owner review already accepted
  as the correct application of `AGENTS.md` §4 when grounding is genuinely incomplete; re-deriving
  a different (and potentially inconsistent) answer here would be worse than carrying the same
  disclosed uncertainty forward unchanged.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 new to this combination, closed with doc/design edits; 2 inherited findings reframed for sharper GDPR-specific stakes) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a new disambiguation table, 2 confirmed as correctly and honestly scoped) | Closed |
| 🎩 CISO | Pass | 0 (benefited directly from the Red Team's and Blue Team's findings) | — |
| 🟦 Microsoft Product Owner | Pass | 0 (all product-surface claims verified against source scripts; no new claims introduced) | — |

All Fix items from this round are resolved in the current state of `README.md` and `design.md`. No
Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
