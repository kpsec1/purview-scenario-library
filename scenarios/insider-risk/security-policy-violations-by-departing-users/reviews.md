# Four-Lens Review — Insider Risk Management: Security Policy Violations by Departing Users

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This control is completely blind to an offline or physical attack on the endpoint.** Every
   indicator this template scores originates from the Defender for Endpoint sensor running on a
   live, online session. A departing user sophisticated enough to boot the device from external
   media, pull the drive, or otherwise work outside the running OS defeats this control entirely
   — and the original draft didn't state this as a structural boundary, only implicitly assumed
   it through the architecture diagram.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming this as a structural
     limit of any EDR-sourced signal (not a configuration gap this scenario can close) and
     recommending it be paired with physical/device-encryption controls, not a tighter IRM
     policy.
2. **The Defender for Endpoint → Purview alert-sharing toggle is tenant-wide, not scoped to this
   policy — the original draft mentioned this only as a rollback consideration, not as an
   ambient risk during unrelated administration.** Someone troubleshooting a different Defender
   for Endpoint integration could flip this toggle off for an unrelated reason and silently stop
   this specific policy from receiving new alerts, with no error or notification pointing back
   at *this* scenario.
   - **Resolution:** Added an explicit bullet to `README.md` §11 (cross-referencing the existing
     `rollback.md` Stage 2 note) framing this as an unintended-side-effect risk during unrelated
     Defender for Endpoint administration, not only an intentional-rollback consideration.
3. **A red-teamer aware that indicator names aren't documented might assume the coverage gap is
   larger than it is (e.g., assuming no antivirus-tampering coverage at all because the specific
   toggle isn't named).**
   - **Not a new finding requiring a fix** — the scenario already states plainly, in both
     `README.md` §5 Step 5 and §11, that indicator names aren't enumerated and that the live
     portal should be checked at deploy time, rather than either overclaiming specific coverage
     or omitting the category description Microsoft does publish (installing malware/harmful
     apps, disabling security features). No change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A policy can be created with zero triggering events enabled, and nothing surfaces that at
   creation time.** Unlike the sibling scenario (HR connector primary, Entra deletion as an
   explicit fallback), this template's own prerequisite table lists both as equally optional —
   meaning an operator could click through policy creation without enabling either, and the only
   downstream signal is Microsoft's own "Policy isn't assigning risk scores to activity" health
   message, which requires someone to go looking for it. The original draft documented both
   triggers as optional but didn't call out the zero-enabled failure mode explicitly.
   - **Resolution:** Added an explicit callout to `README.md` §8 and a corresponding checklist
     item to `validate/Test-SecurityViolationIrmSetup.ps1`'s manual verification list, naming
     this as a deployment-time check, not something to discover later via a health-message scan.
2. **`Export-SecurityViolationInsiderRiskAlerts.ps1`'s IncidentId join could give a false sense
   of completeness if `RelatedDefenderAlerts` is empty and nobody notices.**
   - **Reviewed, no structural change needed:** the script always exports the IRM alert
     regardless of join success (never drops an alert for lack of a join), color-codes its
     console summary based on join rate, and a downstream SIEM can already compute "how many
     alerts have an empty `RelatedDefenderAlerts` array" from the exported JSON itself without
     needing a separate summary object — adding one would be scope creep per `AGENTS.md`'s
     no-unneeded-abstraction guidance. The `.NOTES` and README §11 already disclose that the join
     is best-effort. No change made.
3. **Multiple IRM activity records per underlying Defender alert (if more than one triage status
   is selected in Intelligent detections) — does the export script's dedupe guidance actually
   apply to this specific cause, or just restate the sibling's unrelated cause?**
   - **Reviewed, correctly scoped:** `README.md` §11 explicitly names this template's specific
     cause (triage-status transitions generating separate activity records) before pointing to
     the sibling's `Id`-based dedupe mitigation, rather than implying the causes are identical.
     No change needed.

No remaining Fail. Detection, export, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **Preview status needs a rollout-pacing recommendation, not just a documentation footnote.**
   The original draft flagged preview status prominently (a banner at the top of `README.md`,
   repeated in §11) but stopped short of translating that into a concrete recommendation for how
   an organization should actually roll this out — leaving a gap between "here's the risk disclosure" and
   "here's what to do about it" that a CISO reading this for a funding decision would have to fill
   in themselves.
   - **Resolution:** Added an explicit recommendation to `README.md` §8: pilot against a narrow
     user scope for at least one full 30-day activation-window cycle before committing to this as
     a permanent, tenant-wide control in a customer-facing narrative.
- **Risk reduction vs. cost:** proportionate and honestly scoped. For a tenant already on full
  Microsoft 365 E5, this is genuinely incremental-cost-free (Defender for Endpoint Plan 2 already
  bundled); for a tenant that reached IRM entitlement via the narrower add-on, the scenario states
  the real incremental cost plainly rather than assuming it away (§10).
- **Board-level narrative:** "we also detect device-tampering by employees who are leaving, not
  just data downloads" is a clear, complementary narrative to the sibling scenario's — and, post-
  fix, one that correctly sets expectations about preview-feature risk rather than presenting this
  as equivalent in maturity to the GA sibling.
- **Compliance mapping:** correctly scoped as endpoint-integrity assurance evidence, not tied to a
  named regulatory requirement — same honest framing precedent as the sibling scenario.
- **Would I fund this?** Yes, as a pilot alongside the already-funded sibling scenario for a
  tenant that already runs Defender for Endpoint — the incremental cost is bounded (often zero)
  and the risk it closes (device tampering during the notice period) is real and currently
  uncovered by anything else in this library. Would not yet recommend it as the sole or primary
  departing-employee control given its preview status.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Template name, prerequisite table, and preview status are all verified against current
   Microsoft Learn, not assumed.** The policy-template prerequisites table
   (`insider-risk-management-policy-templates`), the "(preview)" designation on both the overall
   scenario family and the Defender for Endpoint indicator category
   (`insider-risk-management-settings-policy-indicators`), and the 15,000-user scope limit
   (`insider-risk-management-limits`) were all fetched directly during this build, not carried
   forward from memory or inferred from the sibling scenario.
2. **The HR-connector-reuse design decision is grounded, not assumed for convenience.** Microsoft's
   own policy-health reference groups this template with the sibling Data theft template and two
   others as sharing the same class of HR-connector dependency — checked directly rather than
   guessed at to justify not shipping a second script.
3. **No fabricated API for either new prerequisite (the Defender advanced-features toggle or the
   Intelligent detections triage-status selector).** Both were checked against Microsoft's own
   "Configure advanced features in Defender for Endpoint" and "Configure intelligent detections"
   pages and confirmed portal-only; the scenario doesn't fabricate a cmdlet or Graph call for
   either, consistent with `docs/automation-surface.md` §6 and this library's grounding standard.
4. **The Defender for Endpoint Plan 1/Plan 2 licensing nuance is correctly hedged, not
   overclaimed.** Microsoft's own prerequisite table for this template names only "an active
   Defender for Endpoint subscription" with no plan qualifier; the README states the confirmed
   bundling fact (E5/E5 Security includes Plan 2) as a cost-planning note without asserting which
   plan the underlying security-violation detections technically require — flagged as an open
   VERIFY rather than guessed.
5. **`alertPolicyId`/`incidentId`/`detectionSource` field usage in the export script matches the
   Graph `security-alert` resource's actual documented schema**, including the correct, narrower
   claim that Microsoft doesn't document a way to map `alertPolicyId` back to a named Purview
   policy — checked against the resource reference directly rather than assumed by analogy with
   the sibling scenario's simpler single-`detectionSource` filter.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with README additions, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with README + validate-script changes, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a README addition; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 (all confirmed correct/well-grounded, no changes required) | — |

All Fix items from this round are resolved in the current state of `README.md` and
`validate/Test-SecurityViolationIrmSetup.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
