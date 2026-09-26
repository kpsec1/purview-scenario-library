# Four-Lens Review — Communication Compliance: Workplace Harassment & Code of Conduct

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Publishing the exact custom keyword dictionary undermines it.** A keyword-based condition only
   works while its exact contents stay unknown to the people it's meant to catch. The original
   draft shipped `code-of-conduct-evasion-phrases.txt` with no caveat about treating a real
   deployment's dictionary as sensitive.
   - **Resolution:** Added an explicit `README.md` §11 limitation instructing the deploying organization to treat a
     real tenant's deployed dictionary (especially once extended) as sensitive, not for broad
     internal/external publication — distinct from this repo's own reference copy, which is
     published deliberately for transparency.
2. **Non-transcribed Teams meetings (audio/video) are a distinct, narrower gap than "off-platform"
   harassment**, and the original draft's Known Limitations conflated the two. A harasser using
   Teams meeting audio rather than chat is invisible to this control unless transcription is
   enabled and Teams is an in-scope location — worth calling out on its own, since an organization reading
   only the general "off-platform" bullet could reasonably (and wrongly) assume Teams meetings are
   covered because "Teams" is a selected location.
   - **Resolution:** Added a separate `README.md` §11 bullet distinguishing this gap from the
     general off-platform limitation.
3. **Storage-limit auto-deactivation is a silent-failure attack surface** — not an intentional
   bypass technique, but a real path to the same outcome (the control silently stops working) that
   a red-teamer probing for detection gaps would specifically look for. The original draft
   mentioned the storage limit as a fact but didn't frame it as an operational risk requiring active
   monitoring.
   - **Resolution:** Elevated to an explicit KPI in `README.md` §8 ("Storage-limit indicator") and a
     named limitation in §11, both stating plainly that notification emails go only to the
     Communication Compliance/Communication Compliance Admins role groups and that "no alerts"
     cannot be assumed to mean "no problems" without active monitoring.
4. **Evasive typing / adversarial input** — already correctly flagged in the original draft as a
   documented Microsoft limitation ("basic" coverage, not solved); no further change needed.
5. **Off-platform harassment (personal devices, in-person)** — already correctly flagged in the
   original draft as a fundamental scope boundary of any M365-native control; no further change
   needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **All-users + 100% review percentage risks day-one alert-fatigue for a first-time deployment,**
   with no explicit guidance on how to validate signal-to-noise before going tenant-wide. The
   original draft correctly cited Microsoft's own alert-volume-reduction levers (sentiment,
   combine-classifiers, lower review %) but only as reactive tuning *after* a volume problem
   surfaces, not as a proactive rollout strategy.
   - **Resolution:** Added an explicit phased-pilot recommendation to `README.md` §8 — scope to
     **Select users** (one business unit) for 2–4 weeks before expanding to **All users** — framed
     as a deliberate, time-boxed, documented exception to the target end state (§3/§6), not a
     contradiction of Microsoft's own all-users guidance.
2. **Incident-response runbook correctly distinguishes Threat-classifier urgency from routine
   Profanity/Discrimination triage** — already present in the original draft (`README.md` §8, step
   1); confirmed this meets the bar for an operable, severity-differentiated response process.
3. **SIEM integration scoped correctly** — the scenario documents the native Sentinel/
   `OfficeActivity` integration path and the audit-trail CSV as SIEM-ingestible, without overclaiming
   a built Sentinel workbook as delivered — matches this repo's established scope boundary
   (`scenarios/dlp/pci-teams-exfil-block/`); no change needed.
4. **Cross-policy resolution (preview) awareness** — already flagged in the original draft
   (`README.md` §8) so reviewers don't misread an auto-resolved cross-policy match count as
   independently-reviewed volume; no change needed.

No remaining Fail. Detection, logging, the runbook, and the phased-rollout addition meet the bar
for an operable control.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Employee-monitoring notice/consent obligations were flagged only as a Known Limitations
   VERIFY item, with no corresponding operational prerequisite forcing the conversation before
   go-live.** A legal exposure this material — reading employee message content across a
   potentially global user population — needs to be a gating prerequisite a deployment team sees
   in §3, not something discoverable only by reading all the way to §11.
   - **Resolution:** Added an explicit prerequisite row to `README.md` §3: employment-counsel review
     of monitoring-notice/consent obligations and an updated, communicated acceptable-use/
     monitoring policy, cross-referenced to the existing §11 VERIFY for the legal-determination
     boundary this scenario's technical grounding correctly declines to cross.
2. **Risk reduction vs. cost is clear and proportionate.** The control maps to a real, if currently
   contested, regulatory/legal driver (Title VII + *Faragher*/*Ellerth* "reasonable care" doctrine,
   §2) that doesn't depend on the rescinded 2024 EEOC sub-regulatory guidance surviving; licensing
   cost is bounded to E5-tier uplift with no PAYG component (§10).
3. **Board-level narrative is honest, not overclaiming.** "We monitor our own communication
   channels for harassment and code-of-conduct violations, route them to a role-separated HR/Legal
   review process with privacy safeguards, and can show a documented response history" is
   defensible — and the scenario is explicit that this is detective, not preventive (§11), and that
   off-platform conduct remains entirely outside its visibility. That honesty is exactly what a
   board/audit committee needs, not a claim of complete coverage.
4. **The EEOC guidance-rescission finding (§2) is correctly treated as a currency risk to manage,
   not a reason to abandon the control** — the underlying statutory and case-law basis is
   independent of that sub-regulatory guidance's status, and the scenario says so explicitly rather
   than either ignoring the rescission or overreacting to it.
5. **Would I fund this?** Yes, conditional on the monitoring-notice prerequisite (now gating, per
   the fix above) actually being completed before go-live — a compliance control that itself
   creates undisclosed monitoring liability is a net-negative trade a CISO should not accept
   silently.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Classifier naming inconsistency ("Harassment" vs. "Targeted harassment") across Microsoft's
   own documentation was present in the source material this build grounded against** —
   `trainable-classifiers-definitions` and the primary classifier table use "Harassment," while the
   policy-template summary table and the Alerts-page Filters documentation use "Targeted
   harassment" for what reads as the same underlying classifier. Shipping this without flagging it
   risks an organization thinking this scenario picked the wrong classifier name when the portal UI shows
   the other label.
   - **Resolution:** Already caught and documented inline during drafting — `README.md` §6/§11 and
     `design.md` §4 both explicitly flag the inconsistency and instruct verifying the current
     portal-UI label at deploy time, rather than silently picking one name and hoping it matches.
     Re-confirmed correct on review; no further change needed.
2. **Correctly declined to use the preview content-safety (LLM-based) classifiers as the primary
   detection mechanism**, since they don't cover Exchange Online (Teams/Viva Engage/Copilot only)
   and this scenario's location scope explicitly includes email — `design.md` §4 gives the right
   reasoning, not just a preference.
3. **Correctly declined to build a custom trainable classifier** — Communication Compliance
   explicitly doesn't support them; using the fixed classifier catalog plus a keyword dictionary is
   the only available condition surface, and the scenario says so rather than implying a custom-
   classifier option was simply skipped.
4. **No-write-API claim double-sourced and accurately quoted** — `design.md` §2 cites the identical
   "PowerShell isn't supported..." statement from two independent, currently-published Microsoft
   Learn pages rather than a single source, and correctly notes the legacy
   `New-SupervisoryReviewPolicyV2` cmdlet's continued presence in the module reference without
   treating it as a supported alternative path.
5. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`'s existing
   Communication Compliance row (E5/Suite/E5-add-on, PAYG scoped to non-M365 AI data only) and the
   Microsoft Purview service description; consistent, no discrepancy found.
6. **Reviewer role-group naming matches `docs/rbac-model.md`'s existing Communication Compliance
   row** (Viewers → Analysts → Investigators → Administrators → Communication Compliance all-in-one)
   exactly — no invented role name.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 5 (3 closed with new guidance, 2 already correctly covered) | Closed |
| 🔵 Blue Team | Fix | 4 (1 closed with a phased-pilot recommendation, 3 already correctly scoped) | Closed |
| 🎩 CISO | Fix | 5 (1 closed by promoting a VERIFY item to a gating prerequisite, 4 confirmed sound) | Closed |
| 🟦 Microsoft Product Owner | Fix | 6 (1 re-confirmed already correctly flagged, 5 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-CommunicationComplianceAuditTrail.ps1`, and
`deploy/policy/communication-compliance-policy-manifest.json`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9.
