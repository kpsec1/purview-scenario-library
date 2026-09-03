# Four-Lens Review — Auto-Label Confidential PII in SharePoint & OneDrive

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Manual-label-first bypass.** Because manual labels are never overridden regardless of
   priority (the documented, intended override behavior), a file manually labeled something
   innocuous and *then* edited to add sensitive content keeps its manual label forever — this
   control never touches it. This is the single most direct way to defeat the whole scenario,
   accidentally (an early-life template label) or deliberately, and the original draft didn't
   call it out as a bypass, only as background override behavior.
   - **Resolution:** Added to `README.md` §11 as an explicit, unmitigated residual risk, with a
     pointer to pairing this control with content-based DLP conditions (matching the SIT directly,
     not the label) for cases where movement-blocking matters — same pattern already established
     in `scenarios/dlp/pci-teams-exfil-block/`.
2. **Exclusion list as a permanent blind spot.** `-ExcludedSharePointSiteUrl` is a location-level
   exclusion with no time bound or hold-status awareness — content moved into an excluded site is
   invisible to this control whether or not it's genuinely under an active legal hold at the time.
   - **Resolution:** Added to `README.md` §11 with a recommendation to treat the exclusion list as
     a monitored asset and consider an audit-log-based compensating control, since this scenario
     doesn't build one.
3. **Scan-cadence lag as a detection gap, not just a testing inconvenience.** The original draft
   mentioned the lag only as something to account for when testing; a red-teamer's actual interest
   is that any label-conditioned control elsewhere (e.g., DLP) has zero protection during the
   window between upload and the next auto-labeling pass.
   - **Resolution:** Reframed in `README.md` §11 as a residual-risk item, explicitly tied to the
     same class of gap flagged in the DLP template scenario's split-PAN evasion finding, with the
     same resolution direction (content-based conditions, not label-based, for time-sensitive
     control).
4. **U.S.-centric SIT choice weakens the GDPR/CCPA framing for a non-U.S. tenant.** SSN is a
   U.S.-specific identifier; a tenant whose regulated population is EU/UK-only would get much
   weaker real-world coverage from this scenario's default condition set than the GDPR framing in
   §2 implies.
   - **Resolution:** Added an explicit scope note to `README.md` §2 clarifying the two SITs are a
     representative starter set, not jurisdiction-complete personal-data coverage, and pointed to
     where to swap in EU-specific SITs. This is a Product Owner-adjacent finding but the Red Team
     raised it first as "this control is weaker than it sounds for a non-U.S. buyer."

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Config validation reads as match validation.** The original `validate/` script description
   didn't make clear that a fully green run proves the policy is *shaped* correctly, not that it's
   *actually labeling anything* — a correctly-configured-but-effectively-idle policy (e.g., wrong
   region, `EnableAIPIntegration` never turned on) would pass every automated check.
   - **Resolution:** Added an explicit caveat to the validate script's `.DESCRIPTION`, and a new
     `README.md` §11 item ("Config validation is not match validation") directing operators to the
     Overview/Labeled items dashboard for real match-volume confirmation before trusting a green
     validation run.
2. **No native alerting, and the original draft didn't say what to do about it beyond "use
   Activity Explorer."** Auto-labeling has no DLP-style incident-report email; an operator used to
   the DLP template scenario's alert-driven runbook would reasonably ask "so how do I know this is
   working without logging into the portal daily?"
   - **Resolution:** `README.md` §8 already pointed to Activity Explorer and the
     `docs/automation-surface.md` §4 Audit Search/Graph pull pattern for SIEM integration; no
     further code change needed — confirmed this is the correct, honestly-scoped answer for a
     feature that genuinely has no native alert feed, rather than a gap to paper over.
3. **Runbook step 4 (the `EnableAIPIntegration` reset scenario) is the single most likely
   "everything looks fine but nothing is labeled" failure mode, and it depends on a PowerShell
   surface (SharePoint Online Management Shell) this script doesn't touch.** Confirmed this is
   already correctly flagged as a cross-reference to §3/§11 rather than silently assumed — no
   change needed, but worth recording that this was checked deliberately given how easy it would
   be to omit.

No remaining Fail. The operational surface (dashboard, Activity Explorer, and now an explicit
"validation isn't proof of labeling" caveat) meets the bar for an operable control, with the
caveat that this control's native observability is genuinely thinner than a DLP policy's — that's
accurately represented, not hidden.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate and correctly scoped once the U.S.-centric SIT caveat
  (Red Team finding 4) was made explicit — the control is real and valuable as a classification
  foundation, but the CISO reading this now understands it's a starter configuration to extend
  against the org's actual data inventory and jurisdiction, not a GDPR-complete claim out of the
  box. That's a materially more honest, and more fundable, pitch than the original draft's
  framing.
- **Change-management impact:** the "never override a manual label" design (§2 goal 2) is the
  right call for user trust in the labeling program — a control that silently downgrades or
  relabels a deliberate human classification decision would poison adoption of manual labeling
  tenant-wide. The simulation-first staged rollout matches the precedent this library has already
  established and avoided over-claiming instant coverage.
- **Board-level narrative:** "we systematically classify personal data across SharePoint and
  OneDrive so downstream controls (DLP, retention, IRM) have something reliable to act on, and we
  extend the pattern to the org's specific data types over time" is honest and defensible — more
  so after the Red Team findings turned unstated assumptions (GDPR-complete, no bypass path) into
  documented residual risks.
- **Compliance mapping:** correctly repositioned to ISO 27001 Annex A.5.12/A.8.2 (information
  classification) as the primary driver this default configuration satisfies as shipped, with
  GDPR/CCPA as the reason the capability matters once extended to jurisdiction-appropriate SITs —
  this is a more defensible claim than the original draft's flatter "this satisfies GDPR Article
  32" framing.
- **Would I fund this?** Yes — this is foundational, low-cost-to-extend infrastructure (no
  incremental Azure/PAYG spend per §10) that every other Information Protection and DLP scenario
  in this library implicitly depends on, and the residual-risk section now gives an honest basis
  for scoping the next SIT-expansion or content-based-DLP-pairing investment.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **PDF support is off by default and wasn't called out as a prerequisite.** Files in PDF format
   are simply not labeled by any auto-labeling policy unless `EnableSensitivityLabelforPDF` is
   separately turned on — a very common source of "why wasn't this file labeled" confusion the
   original draft didn't anticipate, even though it already cited the 100,000-files/day PDF limit
   in passing.
   - **Resolution:** Added an explicit recommended-prerequisite row to `README.md` §3 and cross-
     referenced it from the existing §11 PDF-limit note.
2. **`-Workload` single-valued design correctly reflected as a real cmdlet constraint, not an
   invented one.** Verified directly against the `New-AutoSensitivityLabelRule` parameter
   reference (`Accepted values: Exchange, SharePoint, OneDriveForBusiness`, one value per rule) —
   the two-rules-per-policy design in `deploy/New-ConfidentialAutoLabelPolicy.ps1` is the correct
   way to express a common multi-workload rule set via PowerShell, matching what the portal's
   "Common rules" wizard does behind the scenes. No deprecated cmdlets used (the
   `*-AutoSensitivityLabelPolicy`/`*-AutoSensitivityLabelRule` family is current).
3. **`SharePointLocationException` and `OverwriteLabel` parameter names and semantics checked
   against the live parameter reference** — both real, current parameters with the documented
   behavior this scenario relies on (override applies only to lower-priority auto-applied/default
   labels, never manual ones). No deprecated or invented parameters found.
4. **`RuleErrorAction` deliberately left unset.** The script author considered setting it
   explicitly (`Ignore` vs. `RetryThenBlock`) but could not confirm the exact processing-error
   semantics with confidence from available documentation, and left it at cmdlet default rather
   than assert unverified behavior — correct application of `AGENTS.md` §9's grounding
   requirement (tag or omit, don't fabricate). No change needed; confirmed as the right call, not
   an oversight.
5. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`: automatic/
   policy-based labeling correctly requires E5-tier or the Information Protection & Governance
   add-on, matching the cross-cutting matrix's existing row.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 documented as unmitigated residual risk, 1 reframed as detection gap, 1 closed by scope-note edit) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a caveat + doc edit, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | 0 (benefited directly from the Red Team's SIT-scope finding) | — |
| 🟦 Microsoft Product Owner | Fix | 5 (1 closed with a prerequisite addition, 4 confirmed correct/deliberate) | Closed |

All Fix items from this round are resolved in the current state of `README.md`,
`validate/Test-ConfidentialAutoLabelPolicy.ps1`, and the deploy script's design. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.
