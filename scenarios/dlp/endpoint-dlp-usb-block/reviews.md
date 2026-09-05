# Four-Lens Review — Endpoint DLP: Block USB Removable Media Exfiltration

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Password-protected/encrypted archive bypass.** Endpoint DLP cannot open and classify an
   encrypted or password-protected file, so zipping a sensitive file with a password before
   copying it to USB defeats both rules entirely — this is the single most obvious bypass a
   red-teamer would try after the SIT match itself, and the original draft didn't call it out.
   - **Resolution:** Added to `README.md` §11 (Known limitations) as an explicit, unmitigated
     residual risk, with a citation to Microsoft's own guidance for files Endpoint DLP can't scan
     and a pointer to pair this scenario with that control if encrypted-archive exfiltration is a
     realistic threat.
2. **IT Data Custodians audit path is the highest-value target.** A compromised or malicious
   custodian credential can move real regulated data onto removable media with zero blocking —
   the only control is after-the-fact log review, and the original draft only reviewed that log
   quarterly, same gap the Card Ops override had in `pci-teams-exfil-block` before that review's
   fix.
   - **Resolution:** `README.md` §8 now specifies a **weekly** review of Rule 1 audit volume per
     user, separate from the quarterly full-control review, plus an explicit incident-response
     runbook step for escalating audit activity that doesn't match the custodian's known
     schedule/device.
3. **Unsupported/unscanned file type and photograph-of-screen bypasses** are not mitigated by
   text-pattern content DLP.
   - **Resolution:** Already called out in the original draft's Known limitations, cross-
     referencing the same limitation documented in `pci-teams-exfil-block/README.md` §11; no
     further change needed.
4. **Renaming a file extension to something Endpoint DLP doesn't parse** could plausibly evade
   classification depending on how the client handles unrecognized types.
   - **Resolution:** Folded into finding 1's citation to `dlp-create-policy-files-edlp-doesnt-scan`
     — Microsoft's own guidance treats "files DLP doesn't scan" as one category covering both
     unsupported types and unreadable (encrypted) content, so a single Known-limitations entry with
     that citation covers both without overstating either as separately "fixed."

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No incident-response runbook.** The original draft had detection (alerts, incident reports,
   Activity explorer) but no documented "what does an analyst actually do" procedure.
   - **Resolution:** Added a five-step incident-response runbook to `README.md` §8, covering
     triage, true/false-positive classification, and separate handling paths for a Rule 0 block
     vs. a Rule 1 custodian audit event.
2. **Device onboarding/policy-sync status is not part of the validation story.** The original
   draft's validation script only checked policy *configuration*, which can pass while a specific
   test device silently isn't enforcing anything because it never onboarded or never synced —
   an analyst chasing a "why didn't this block" report needs that ruled out first, not last.
   - **Resolution:** Added an explicit device onboarding/policy-sync check as its own numbered
     step in `README.md` §7 (before the functional tests), and added an explicit docstring caveat
     to `validate/Test-EndpointDlpUsbBlockPolicy.ps1` stating it cannot confirm per-device sync
     status.
3. **Alert routing described but not wired**, same acceptable scope boundary as
   `pci-teams-exfil-block`.
   - **Resolution:** No code change needed; confirmed `README.md` §8 already scopes this
     correctly ("see `docs/automation-surface.md` §4") and doesn't overclaim SIEM integration as
     delivered.

No remaining Fail. Detection, logging, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** clear and proportionate. Removable media is a well-understood,
  high-impact exfiltration channel with no other control in this repo covering it (Teams DLP and
  auto-labeling both stop at the cloud/collaboration boundary); licensing cost is bounded to
  endpoint users who already need E5-tier Purview for other controls in a typical enterprise
  buyer, and §10 is explicit this is not an incremental Azure/PAYG cost.
- **Change-management impact:** the audit-first IT Data Custodians exception and the staged
  simulation-mode-first rollout are the right call — the same lesson `pci-teams-exfil-block`
  already established in this repo (a control that blocks a legitimate operational workflow on
  day one gets disabled by business pushback), applied here to a different team and channel.
- **Board-level narrative:** "we stop regulated data leaving on a USB drive, we give the one team
  that legitimately needs removable media a watched-not-blocked path, and the encrypted-archive
  and unscanned-file gaps are documented residual risks, not silent ones" is a defensible,
  one-paragraph narrative for an audit committee.
- **Compliance mapping:** correctly scoped as a general-purpose data-loss control referenced
  across GDPR/HIPAA/PCI/SOC2 rather than over-claiming a single named requirement it satisfies —
  §2 is explicit that no single framework mandates this exact control by name, which is honest and
  avoids a buyer over-representing this scenario to an assessor.
- **Would I fund this?** Yes — the device-onboarding operational cost called out in §10 (separate
  from licensing) is the one line item that needs its own budget line beyond the SKU cost, and
  the scenario is upfront about that rather than burying it.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **`EndpointDlpRestrictions` `-Value` strings are not confirmed against Microsoft's canonical
   cmdlet reference.** The parameter's existence and type (`PswsHashtable[]`) are confirmed on
   Learn, but the reference page enumerates no valid `Setting`/`Value` strings, and the primary
   source for the exact hashtable shape used here (a Microsoft Security Blog Tech Community post)
   could not be fetched directly during this build to quote verbatim (network egress to
   techcommunity.microsoft.com was blocked in this environment) — only corroborated via two
   independent search-tool summaries of that page. Shipping this without flagging the gap risks a
   buyer discovering a parameter-validation error at deploy time.
   - **Resolution:** Added an explicit `VERIFY` note to `README.md` §11 and to the deploy script's
     `.NOTES` block, directing the operator to confirm both strings in a pilot tenant (added as
     §7 step 1, ahead of every other validation step) before relying on `-Mode Enable` in
     production. This matches `AGENTS.md` §9's grounding requirement — tag, don't fabricate, when
     a specific value can't be independently confirmed against a canonical reference.
2. **Why Endpoint DLP and not Microsoft Defender for Endpoint device control?** A reviewer
   familiar with the Defender product family could reasonably ask why this scenario doesn't just
   use device control, which also restricts USB access.
   - **Resolution:** `design.md` §3 explains the content-blind-vs-content-aware distinction and
     `README.md` §11 states explicitly that this scenario complements, not replaces, device
     control — correct positioning of two genuinely different controls rather than reinventing
     one with the other.
3. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md` and the Microsoft
   Purview service description: Endpoint DLP correctly requires E5-tier (or the Information
   Protection & Governance add-on), matching the cross-cutting matrix's existing row. No
   deprecated cmdlets used.
4. **Sensitive-content definition reuse** — reusing the exact SIT pair from
   `auto-label-confidential-sharepoint` rather than defining a third, independently-tuned set is
   the right call for a coherent multi-scenario story, and is called out explicitly in
   `design.md` §2 and §6 rather than left as an unexplained coincidence.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 closed with documentation, 1 folded into another, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed, 1 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 4 (1 closed with VERIFY tagging, 3 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-EndpointDlpUsbBlockPolicy.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.

---

## Addendum (2026-09-05) — `EndpointDlpRestrictions` grounding upgrade + `Warn` opt-in

A follow-up fragment (tracked in `PROGRESS.md`) independently re-fetched Microsoft's official
`New-DlpComplianceRule` and `Set-DlpComplianceRule` cmdlet reference pages in full (both were
reachable this time; the original build could only reach a Tech Community blog for this shape).

- 🟦 **Microsoft Product Owner** — original finding #1 ("`EndpointDlpRestrictions` `-Value`
  strings are not confirmed against Microsoft's canonical cmdlet reference") is now **closed**,
  not just tagged. Both official pages state identically: "The available values for `<Value>` are:
  Audit, Block, Ignore, or Warn," with a worked example
  `@{"Setting"="RemovableMedia"; "Value"="Block";}` matching Rule 0 exactly, plus confirmed
  `Setting` names `Print`/`CopyPaste`/`ScreenCapture`/`RemovableMedia`/`NetworkShare`/
  `UnallowedApps`. **Verdict: Pass.**
- 🔴 **Red Team** (mini-check on the new `-ITExceptionAction Warn` opt-in) — does exposing `Warn`
  introduce a new bypass? No: `Warn` is strictly not weaker than `Audit` — it adds a user-facing
  justification prompt on top of the same alert/incident-report/audit trail, it does not remove
  any existing detection, and the default stays `Audit` (no behavior change for an existing
  deployment that upgrades this script). The one residual point worth naming: a custodian who
  reflexively clicks through a `Warn` prompt gets no more real friction than silent `Audit`, so
  `README.md` §8's existing **weekly** review of Rule 1 activity remains the load-bearing control
  under either action — not a new gap, the same one already flagged in the original Red Team
  round above. **Verdict: Pass, no change required.**

No remaining Fix/Fail. This addendum does not reopen the original four-lens verdicts above; it
records a grounding upgrade and one additive, opt-in, non-default capability reviewed against the
same bar.
