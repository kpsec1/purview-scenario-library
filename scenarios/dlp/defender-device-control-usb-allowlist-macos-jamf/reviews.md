# Four-Lens Review — Defender for Endpoint Device Control (macOS, JAMF-managed): USB Default-Deny Allowlist

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The manual, JAMF-console-only deployment path (Steps 3–4) is itself a bypass surface.** Any
   JAMF Pro administrator with Configuration Profile edit rights can clear or alter the Device
   Control Policy text box, disable `DC_in_dlp`, or unscope the profile at any time, and — unlike
   the Intune sibling — this scenario's own tooling has **no way to detect that drift**
   (`validate/Test-JamfDeviceControlPolicyJson.ps1` checks the local file only, never the live JAMF
   Pro state). An insider with JAMF admin rights (a materially different, and in some orgs less
   tightly controlled, privilege boundary than Intune/Entra RBAC) can silently disable this control
   fleet-wide.
   - **Resolution:** Added as the **first**, most prominent bullet in `README.md` §11 (not buried
     among the platform-parity gaps shared with the Intune sibling), explicitly named as a
     structural consequence of the no-API design decision (`design.md` §3), with a recommended
     compensating control (periodic manual console re-check, §8/§9) rather than an unfounded claim
     of equivalence with the Intune sibling's API-enforced state.
2. **Portable Devices, Apple (iOS/iPadOS) devices, and Bluetooth media are completely invisible to
   this control** — the same `primaryId`-family gap as the Intune sibling, since the policy JSON is
   identical.
   - **Resolution:** Already disclosed with equal weight in `README.md` §11 (second bullet),
     cross-referencing the Intune sibling's own tracked follow-up rather than re-describing it as a
     JAMF-specific issue — it isn't one.
3. **`serialNumber`-only matching** — same spoofing/no-serial-number bypass class as the Intune
   sibling.
   - **Resolution:** Same treatment as the Intune sibling's own already-accepted framing
     (`README.md` §11) — `serialNumber` remains the strongest standalone identifier this schema
     supports; no further change needed beyond the disclosure already present.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No remote or local way to confirm the JAMF-console paste step (§5 Step 3) was actually
   performed, or performed correctly** — `validate/Test-JamfDeviceControlPolicyJson.ps1` validates
   the local artifact only; a stale or partially-pasted JSON in JAMF Pro produces no detectable
   signal from this scenario's own tooling.
   - **Resolution:** Documented explicitly as this scenario's primary, disclosed detection gap in
     `README.md` §11 and §7 (check 3 — the manual JAMF-console visual confirmation step), and
     surfaced again in the operations runbook (§8) as a required step before trusting a
     "remediated" incident. Not fabricated away with an invented API-based check.
2. **No audit trail for JAMF-console changes beyond JAMF Pro's own configuration-profile history**
   — a materially weaker change-management story than the Intune sibling's Graph-API-driven,
   scriptable (and therefore change-ticket-attachable) deploy/reconcile flow.
   - **Resolution:** Called out in `README.md` §8 ("Change management is manual for this deployment
     path") with a concrete recommendation (route JAMF profile edits through the org's existing
     change-management process) rather than silently omitted or overstated as equivalent to the
     Intune sibling's audit story.
3. **Incident-response runbook, KPIs, and alert routing** — confirmed `DeviceEvents` is a single,
   OS- and MDM-agnostic Advanced Hunting table, so the runbook/KPI/alerting content is correctly
   shared verbatim with both siblings (`README.md` §7 query, §8) rather than needing independent
   re-grounding. The one JAMF-specific runbook addition (confirm the console change was actually
   applied before assuming remediation, §8) directly closes finding 1 above operationally.

No remaining Fail. The detection/audit-trail gap (finding 1–2) is an honestly-scoped, structural
consequence of the no-API design decision — not a fabricated fix, but not silently accepted either;
a concrete compensating process (manual console re-check on a fixed cadence) is documented.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

- **Risk reduction vs. cost:** closes a real gap for any buyer whose macOS fleet is JAMF-managed —
  without this scenario, such a buyer has **zero** device-identity USB control on every JAMF-managed
  Mac, since neither the Windows nor the Intune-managed-macOS sibling applies. Zero incremental
  Microsoft licensing cost for a tenant already at Defender for Endpoint Plan 1 / Microsoft 365 E3;
  JAMF Pro itself is a pre-existing cost this scenario assumes, not adds.
- **Board-level narrative — Finding:** the original draft's narrative language mirrored the Intune
  sibling's "closed, auditable USB allowlist posture" claim without qualification. For this
  scenario specifically, "auditable" is materially weaker (Blue Team findings 1–2) — the policy
  *content* is audited via `DeviceEvents` once deployed, but the *deployment/change* itself is not,
  unlike the Intune sibling.
  - **Resolution:** Reworded framing throughout `README.md` (§1, §8, §11) to state plainly that this
    is a JAMF-console-driven control with a manual change-management story, not an
    equally-automated twin of the Intune sibling presented with the same confidence. A board-level
    narrative built on this scenario should say "the same policy content, deployed and change-
    managed through JAMF Pro's own console process" — not imply parity with the Intune sibling's
    fully API-driven, scriptable deployment.
- **Change-management impact:** materially higher manual-step count than either sibling (§5, four
  JAMF-console steps vs. one script invocation) — correctly disclosed as a real adoption-cost
  difference a buyer comparing the two deployment paths should know upfront, not glossed over to
  make the scenarios look interchangeable.
- **Compliance mapping:** same general media-controls reinforcement as both siblings — no
  JAMF-specific named requirement claimed.
- **Would I fund this?** Yes, for the intended buyer (JAMF-managed fleet with no Intune
  alternative) — but I would fund it with eyes open about the disclosed change-management/audit
  gap versus the Intune sibling, not as a drop-in equivalent.

Fix applied (board-narrative wording); no Fail.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Confirmed the four-step JAMF procedure (author JSON → validate via `mdatp` → update schema →
   add Device Control property) is Microsoft's actual documented workflow**, not a simplification —
   checked directly against `mac-device-control-jamf`. The scenario's own Steps 1–4 map to
   Microsoft's Steps 1–4 one-to-one; no step invented, none skipped.
2. **Confirmed no Microsoft-documented JAMF Pro REST/Classic API exists for this specific
   custom-schema property** — `mac-device-control-jamf` frames JAMF explicitly as a third-party tool
   Microsoft does not provide API-level guidance for, and this build's own attempt to independently
   verify a JAMF Pro API shape (`developer.jamf.com`) was blocked by this build's network
   environment, not skipped by choice.
   - **Resolution:** `design.md` §3's comparison table and `README.md` §11's VERIFY both state this
     precisely — including the specific reason the site couldn't be checked — rather than a vaguer
     "no API found" that could be mistaken for "no API exists."
3. **`Full Disk Access` prerequisite for `com.microsoft.dlp.daemon` correctly identified as a
   separate identifier from the general EDR sensor's own `com.microsoft.wdav`/`com.microsoft.wdav.
   epsext` Full Disk Access grant** (documented separately in `mac-jamfpro-policies` Step 6) —
   confirmed directly against `mac-device-control-overview`'s "Prepare your endpoints" section,
   which explicitly calls `com.microsoft.dlp.daemon` "a new application" requiring its own grant.
   - **Finding:** the initial draft's `README.md` §3 Full Disk Access row didn't make clear this is
     the *same* `fulldisk.mobileconfig`/bundled-profile mechanism as the general EDR sensor's Full
     Disk Access, just requiring the additional identifier — a reader could wrongly conclude a
     second, separate PPPC profile is needed.
   - **Resolution:** Reworded `README.md` §3's Full Disk Access row and §5 Step 0 to cite the same
     `fulldisk.mobileconfig`/`mac-jamfpro-policies` Step 6 mechanism the general MDE-on-JAMF setup
     already uses, consistent with the Purview-JAMF-onboarding guide's own "update the existing
     full disk access profile" framing rather than implying a net-new profile type.
4. **`DC_in_dlp` correctly identified as a separate toggle from the device-control policy JSON
   itself**, living in the schema's DLP/Features section rather than inside the pasted JSON — the
   same two-step-enable-model distinction the Intune sibling's own review already flagged as
   easy to miss.
   - **Resolution:** Explicitly separated into its own numbered step (§5 Step 2) rather than folded
     into the JSON-paste step (§5 Step 3), and called out again in `README.md` §6's configuration
     reference table as "not in this JSON."
5. **Policy content grounding** — confirmed byte-identical to the already-reviewed Intune sibling's
   policy JSON, sourced from the same `mac-device-control-overview` tables; no independent
   re-verification risk introduced by reusing that generation logic.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 newly identified and prominently disclosed, 2 confirmed already correctly scoped from the Intune sibling) | Closed |
| 🔵 Blue Team | Fix | 3 (2 disclosed as structural, honestly-scoped gaps with a compensating process, 1 confirmed correctly shared with both siblings) | Closed |
| 🎩 CISO | Fix | 1 (board-narrative wording corrected to avoid implying parity with the Intune sibling) | Closed |
| 🟦 Microsoft Product Owner | Fix | 5 (1 clarified in README.md's prerequisites row, rest confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-JamfDeviceControlPolicyJson.ps1`, and `validate/Test-JamfDeviceControlPolicyJson.ps1`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
