# Four-Lens Review - Communication Compliance: Financial Regulatory Supervision

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The evidence-of-review CSV, read alone, is weaker evidence than it looks.** Its
   `ContentReference` field is honestly labeled as a reference to the review *action*, not the
   reviewed message's own content - but the original draft only stated this fact in §11 (Known
   limitations) without connecting it to the risk that a firm might treat the CSV as sufficient,
   stand-alone Rule 3110(b)(4) evidence in an examination. A red-teamer probing "how would this
   control fail to actually protect the firm" would specifically flag: this CSV proves *someone
   reviewed something on a date*, not *they reviewed the right thing* - a firm that discards the
   native alert record while keeping only this CSV could not answer a follow-up examiner question
   about what was actually in the reviewed message.
   - **Resolution:** Added an explicit warning to `README.md` §7 (Validation) stating the CSV must
     never be relied on alone, and that a complete evidence package needs both this CSV and the
     retained native alert record for the same period.
2. **Restricted-list/watch-list confidentiality was correctly identified and closed during
   drafting** - the custom keyword dictionary (`deploy/policy/finra-supervision-evasion-phrases.txt`)
   deliberately contains only concealment/evasion phrasing, never actual tickers or issuer names, and
   `README.md` §11/`design.md` §5 both state explicitly why loading a real restricted list into a
   keyword dictionary this repo publishes openly would be actively harmful. Confirmed correct on
   review; no further change needed.
3. **Off-channel communications (personal phone/WhatsApp/SMS) are entirely outside this control's
   visibility, and this is precisely the failure mode that produced the SEC/CFTC's $3+ billion
   enforcement sweep since 2021** - already correctly identified and given prominent placement in
   `README.md` §2 and §11 (not buried as a minor footnote), including the specific figures
   (JPMorgan's $125M, the 16-firm $1.1B settlement, the 13-firm $549M settlement) that make the risk
   concrete rather than abstract. Confirmed correct on review; no further change needed.
4. **Custom keyword dictionary evasion-phrase list is a reasonable, non-exhaustive starting point,
   not a complete evasion taxonomy** - already disclosed implicitly by the classifiers' own documented
   "limited support for evasive typing" limitation (§11); no additional finding beyond what the
   product itself already discloses.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The `ActionTaken` fallback originally duplicated the entire raw `AuditData` JSON payload a
   second time, inside a column of the same row that already has its own `AuditData` column.** For
   every event where none of the script's candidate action-property names matched, this bloated the
   row and complicated downstream SIEM ingestion for no benefit - the exact same content would already
   be present in the row's own `AuditData` column.
   - **Resolution:** Changed `deploy/Export-FinraSupervisionEvidence.ps1`'s fallback text to point at
     "this row's own `AuditData` column" instead of re-embedding the raw JSON string a second time.
2. **Reviewer-registration drift is a real, ongoing operational risk the original draft only
   addressed as a one-time onboarding gate ("confirm before go-live"), not as a recurring control.** A
   reviewer who held a valid FINRA registration when first assigned to Investigators can later leave
   the firm, transfer roles, or have their registration suspended - and nothing in Purview's own RBAC
   model surfaces that drift, since Communication Compliance has no concept of FINRA registration
   status at all (`design.md` §6).
   - **Resolution:** Added a **quarterly reconciliation of Investigators role-group membership against
     the firm's current FINRA registration roster** to `README.md` §8's review cadence, framed
     explicitly as an ongoing operational control, not a one-time check.
3. **Incident-response runbook correctly differentiates classifier urgency** (Stock
   manipulation/Money laundering escalated immediately vs. routine triage for lower-severity matches)
   - already present in the original draft (`README.md` §8); confirmed this meets the bar for an
   operable, severity-differentiated response process.
4. **SIEM integration scoped correctly**, matching the harassment sibling's own established boundary
   (document the native Sentinel/`OfficeActivity` path and the CSV's SIEM-ingestible shape; don't
   build a Sentinel workbook as part of this fragment) - no change needed.

No remaining Fail. Detection, logging, the runbook, and both fixes above meet the bar for an operable
control.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The board-level risk narrative is unusually strong and concrete for this module** - grounding
   the regulatory driver in the SEC/CFTC's actual, quantified enforcement history ($3+ billion since
   2021) rather than an abstract "FINRA requires supervision" statement gives a CISO a real number to
   put in front of a board or audit committee. This is exactly the kind of specific, non-generic
   framing `AGENTS.md` §5 calls for. Confirmed correct on review.
2. **Population scoping to the registered-representative group (not All users) is the right cost/risk
   trade-off** - it keeps licensing and alert volume proportionate to the actual regulatory obligation
   (`design.md` §3), rather than over-scoping the way a less careful build might by copying the
   harassment sibling's all-users pattern without re-examining whether it fits this driver. Confirmed
   correct on review.
3. **The FINRA-registration gating prerequisite (§3) was correctly promoted to a named prerequisite
   the deployment team sees before go-live, not buried in Known limitations** - matching the same
   discipline `harassment-and-code-of-conduct/reviews.md`'s own CISO lens required for its
   employment-counsel prerequisite. The Blue Team's registration-drift finding above (now resolved)
   extends this from a one-time gate to an ongoing control, which is the more complete answer to "would
   I fund this" - a control that only checks registration status once, at deployment, is materially
   weaker than one that keeps checking.
4. **Licensing cost is proportionate and clearly bounded** (§10) - scoped to the registered-rep
   population at E5-tier, with third-party connector licensing explicitly called out as a separate
   decision if the firm needs those channels too. No overclaiming of what a single Purview E5 uplift
   buys.
5. **Would I fund this?** Yes - conditional on both the initial registration-status gate and the new
   quarterly reconciliation control (Blue Team finding, now resolved) actually being operated, and on
   the firm treating this as one half of a two-part control alongside
   `retention-labels-financial-records` for the retention obligation, not a complete regulatory
   posture on its own.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Classifier-naming uncertainty (the collusion classifier's exact current label) was disclosed
   honestly rather than guessed**, matching the harassment sibling's own "Harassment"/"Targeted
   harassment" precedent - `README.md` §11, `design.md` §5, and the manifest all flagged this
   consistently as a VERIFY item rather than asserting a single name with false confidence. Confirmed
   correct on review. **Maintenance update (2026-09-27):** a direct Microsoft Learn MCP fetch closed
   this VERIFY - the confirmed current portal-UI label is "Regulatory collusion"
   (`learn.microsoft.com/purview/trainable-classifiers-definitions#regulatory-collusion`); "Workplace
   collusion" does not appear on any canonical Microsoft Learn page. `README.md`, `design.md`, the
   manifest, and the validation script have been updated accordingly.
2. **Correctly declined to guess which built-in template ("Detect financial regulatory compliance" vs.
   "Detect conflict of interest") bundles which classifiers**, and sidesteps the question entirely by
   building a custom policy that names all seven classifiers explicitly (`design.md` §5) - a
   materially better answer than either guessing a bundling or omitting classifiers because their
   template mapping was unclear. This is the same "don't guess, build around the gap" discipline
   `AGENTS.md` §4 requires. **Maintenance update (2026-09-28):** a direct Microsoft Learn MCP fetch
   closed this VERIFY - "Detect financial regulatory compliance" bundles six of the seven classifiers
   (all but Corporate sabotage) at a 10% review percentage, and "Detect conflict of interest" carries no
   classifier conditions at all. The custom-policy decision is confirmed correct, not merely undecided;
   `README.md`, `design.md`, and this file have been updated accordingly.
3. **No-write-API claim correctly reused from the sibling scenario's own double-sourced grounding**
   rather than re-asserting it from a single source - `design.md` §2 cites the identical two-page
   verbatim quote the harassment sibling already established, consistent with this repo's existing
   grounding for this module.
4. **Correctly chose Communication Compliance over DLP/Insider Risk Management for this control**,
   with the same reasoning structure `pci-teams-exfil-block/design.md` §3 and the harassment
   sibling's own §3 already established for this repo - reused, not re-invented, and reused
   correctly (`design.md` §4).
5. **Licensing citation accuracy** - checked against `docs/licensing-matrix.md`'s existing
   Communication Compliance row (E5/Suite/E5-add-on, PAYG scoped to non-M365 AI data only); no
   discrepancy found, no changes needed to that cross-cutting doc for this scenario.
6. **Reviewer role-group naming matches `docs/rbac-model.md`'s existing Communication Compliance row**
   exactly (Investigators, full content) - no invented role name. The FINRA-registration requirement
   layered on top is correctly scoped as an organizational requirement *outside* Purview's own RBAC
   model, not miscast as a Purview role or permission that doesn't exist.
7. **Cross-link to `retention-labels-financial-records` is accurate and non-duplicative** - this
   scenario's own README/design correctly describe that sibling as the SEC 17a-4/FINRA 4511 retention
   control and do not attempt to re-build or restate its regulatory-record-label mechanics here.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 closed with a new stand-alone-evidence warning, 3 already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 4 (2 closed - a script fix and a new recurring-reconciliation control, 2 already correctly scoped) | Closed |
| 🎩 CISO | Fix | 5 (1 closed by extending a one-time gate into an ongoing control via the Blue Team fix, 4 confirmed sound) | Closed |
| 🟦 Microsoft Product Owner | Fix | 7 (all confirmed correct; no changes required from this lens) | Closed |

All Fix items from this round are resolved in the current state of `README.md`,
`deploy/Export-FinraSupervisionEvidence.ps1`, and this file. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.
