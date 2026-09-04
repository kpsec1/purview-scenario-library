# Four-Lens Review — Auto-Label Confidential PII in Exchange Email

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The sender-based exclusion is a standing exfiltration path, not just an under-protection
   gap.** The initial draft documented `-ExchangeSenderException` only from the angle of "this
   custodian's inbound mail isn't covered" — it didn't call out the more consequential direction:
   any mail the excluded mailbox *sends* is completely unlabeled and unencrypted by this control,
   by design. A compromised or repurposed excluded mailbox is a clean, permanent bypass for exactly
   the data class this scenario protects.
   - **Resolution:** Rewrote `README.md` §11 to state this plainly as a standing exfiltration
     risk, not a coverage nuance, and to recommend treating the exclusion list as a monitored
     asset — same posture the sibling scenario already takes toward its excluded SharePoint site.
2. **The external-recipient encryption default is weaker in exactly the direction that matters
   most, and the original draft framed it as a neutral configuration difference rather than a
   real risk.** Out of the box, a message containing an SSN or card number sent to an external
   recipient is labeled but not encrypted, because `-ExternalMailRightsManagementOwner` isn't
   configured by default. That's the data-leaving-the-tenant case — the one GDPR/CCPA
   breach-notification exposure actually turns on — left in cleartext while the less risky
   internal-only case is protected automatically.
   - **Resolution:** Rewrote `README.md` §11 to state the risk directly ("leaves the tenant in
     cleartext") and to give two concrete mitigations: configure
     `-ExternalMailRightsManagementOwner` deliberately, or pair this scenario with a content-based
     DLP rule for external send — consistent with this library's established "don't rely on the
     label alone for real-time protection" pattern.
3. **The PDF-attachment encryption claim in the original draft was stated with more confidence
   than the source supports.** Microsoft's documentation confirms Office attachments are
   separately encrypted to match an encrypting label; it does not state what happens to a PDF
   attachment on the same message in as much detail, and the original draft implied PDFs are left
   "unprotected" as a settled fact.
   - **Resolution:** Softened to an explicit **VERIFY** in `README.md` §11 rather than asserting
     an unconfirmed behavior either way, per `AGENTS.md` §4.
4. **Manual-label-first bypass and scan-cadence-style gaps are inherited from the sibling
   scenario's own already-reviewed findings, not new to this one.** Confirmed the same bypass class
   (a manually labeled draft later completed with sensitive content) applies here and is already
   documented in `README.md` §11 with the same content-based-DLP mitigation pointer as the sibling
   scenario. No new finding — correctly inherited, not overlooked.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The complete absence of a "Labeled items" dashboard for Exchange was described in the
   original draft, but the runbook didn't give an operator a clear alternative path when Activity
   Explorer itself can't disambiguate which policy applied a label.** If a tenant ever runs more
   than one auto-labeling policy against the same label (plausible once both this scenario and a
   future Exchange DLP scenario target the same `Confidential` label), an operator troubleshooting
   "why was this labeled" has no automated way to attribute it to this specific policy via Activity
   Explorer alone.
   - **Resolution:** `README.md` §7 step 4 and §8 KPI section already flag this explicitly
     ("does not identify which specific auto-labeling policy or rule applied it") — confirmed this
     is the correct, honestly-scoped answer for a real product limitation rather than a gap to
     paper over; no further code or doc change possible since no attribution API exists.
2. **The rule-load-failure runbook item (§8, step 5) is the single most consequential
   "everything looks fine but nothing is labeled" failure mode for this scenario, more so than for
   the sibling scenario, because there is no item-level failure surface at all to fall back on
   for Exchange (unlike SharePoint/OneDrive's per-file failure reasons).** Confirmed this was
   already correctly ordered last in the runbook (after ruling out the simulation-window and
   exclusion-list explanations first, which are more common) and cross-referenced to the automated
   config check — no change needed, but worth recording this was checked deliberately.
3. **Support-ticket-as-detection-signal guidance (§8, "Alert routing") is a real, if informal,
   operational answer given this feature has no native alert feed** — confirmed as an honestly
   scoped answer, not a gap. Added no new code; this is a documentation-only operability surface,
   same conclusion as the sibling scenario's Blue Team review reached for its own alerting gap.

No remaining Fail. The operational surface (Activity Explorer with its documented delay and
attribution limits, Items to review during simulation, and now an explicit compromised-exclusion
and external-encryption risk framing) is honestly represented as genuinely thinner than the
sibling scenario's, not hidden behind reused language that would overstate Exchange's
observability.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate, and the two Red Team findings materially improve the
  honesty of this scenario's pitch — a CISO now sees explicitly that the default configuration
  protects internal mail but not external mail by default, which is exactly the distinction that
  matters for breach-notification risk. Presenting this as a deliberate configuration decision
  with a documented mitigation path (external RM owner, or a paired DLP rule) is a materially more
  fundable position than a scenario that implied uniform protection across both directions.
- **Board-level narrative:** "we extend the same PII classification standard already applied to
  SharePoint/OneDrive to email, our highest-volume channel, while being explicit about where this
  control's protection is currently weaker (external-bound mail) so that gap can be a scoped,
  budgeted next decision rather than an unknown" is honest and defensible — more so after the Red
  Team findings turned an implicit assumption into a stated, resourced decision point.
- **Compliance mapping:** same ISO 27001 Annex A.5.12/A.8.2 framing as the sibling scenario,
  correctly not overclaiming GDPR/CCPA-complete coverage for the same reason (starter SIT set).
- **Change-management impact:** the encryption side-effect on internal mail (§8, "Alert routing")
  is the most likely source of user-facing friction ("why can't my recipient forward this email")
  and is already routed to the right team in the runbook rather than left as a support-desk
  mystery.
- **Would I fund this?** Yes — this closes a real, high-volume gap in the same classification
  program the sibling scenario already funded, reuses the same label and license entitlement (no
  incremental licensing decision), and the residual-risk section (external-recipient encryption
  default, exclusion-list-as-standing-bypass) gives a concrete, scoped basis for the next
  investment decision rather than a vague "there might be gaps" caveat.

No Fix/Fail items from this lens — it benefited directly from the Red Team's two findings.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The claim that no `-ExchangeLocationException` parameter exists (a load-bearing design
   decision in `design.md` §3) needed to be checked against the complete parameter syntax, not
   inferred from documentation prose alone.** Verified directly against
   `New-AutoSensitivityLabelPolicy`'s full parameter list: `-SharePointLocationException` and
   `-OneDriveLocationException` are real parameters; no `-ExchangeLocationException` appears
   anywhere in the syntax. The Exchange-specific parameters are `-ExchangeSender`/
   `-ExchangeSenderException`/`-ExchangeSenderMemberOf`/`-ExchangeSenderMemberOfException` — a
   genuinely different (sender-based, not location-based) shape, not a naming inconsistency this
   scenario invented.
   - **Resolution:** No change needed — the claim was already correct; recorded the direct
     parameter-syntax verification as the citation basis (`README.md`/`design.md` reference 9)
     rather than resting on prose interpretation alone.
2. **The "Compliance Administrator / Compliance Data Administrator required to turn on a policy"
   finding is new information this build surfaced that isn't reflected in the sibling scenario's
   own prerequisites, even though it applies there too.** The sibling scenario's `README.md` §3
   only names the Information Protection Admin role group for the whole lifecycle; Microsoft's
   pre-flight checklist actually requires a *different* role specifically to flip a policy from
   "Ready to turn on" to "On."
   - **Resolution:** Added as its own prerequisite row in this scenario's `README.md` §3, with an
     explicit note that it applies to the sibling scenario too. Not backported into that
     already-DONE fragment in this turn (consistent with this library's established precedent of
     tracking such doc-extension backports as separate `PROGRESS.md` follow-ups rather than
     re-opening a finished fragment); filed as a new follow-up in `PROGRESS.md`.
3. **`-RuleErrorAction` deliberately left unset, consistent with the sibling scenario's own,
   already-reviewed rationale** (uncertain processing-error semantics, not asserted rather than
   guessed) — confirmed as the right call again here, not an oversight carried over by accident.
4. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`: this scenario
   correctly reuses the sibling scenario's E5-tier/IP&G row rather than introducing a separate,
   unverified licensing claim for Exchange auto-labeling specifically (Microsoft's own
   documentation confirms both service-side auto-labeling surfaces share the same entitlement
   tier).
5. **No deprecated cmdlets or invented parameters found.** `-ExchangeLocation`,
   `-ExchangeSenderException`, and `-ExternalMailRightsManagementOwner` are all confirmed current,
   real parameters on `New-AutoSensitivityLabelPolicy`; `-Workload Exchange` is a confirmed,
   current accepted value on `New-AutoSensitivityLabelRule`.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 substantially rewritten as concrete risk framing, 1 softened to VERIFY, 1 confirmed correctly inherited) | Closed |
| 🔵 Blue Team | Fix | 3 (confirmed already correctly and honestly scoped; no further code/doc change possible for a real product limitation) | Closed |
| 🎩 CISO | Pass | 0 (benefited directly from the Red Team's two findings) | — |
| 🟦 Microsoft Product Owner | Fix | 5 (1 closed with a new prerequisite + follow-up filed, 4 confirmed correct/deliberate) | Closed |

All Fix items from this round are resolved in the current state of `README.md` and `design.md`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
