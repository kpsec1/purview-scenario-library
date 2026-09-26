# Four-Lens Review - Defender for Endpoint Device Control: USB Default-Deny Allowlist

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Windows Portable Device (WPD)-classified hardware is completely invisible to this control,
   not merely unrestricted.** `SecuredDevicesConfiguration` scopes enforcement to
   `RemovableMediaDevices` only. Many phones, tablets, and cameras present as WPD (MTP/PTP) rather
   than a mass-storage disk - a user exfiltrating data via a phone in that mode generates **no**
   audit event and **no** block, which is a materially different (and worse) gap than "this
   activity type isn't restricted": it's a silent, undetectable bypass of the scenario's own
   stated goal ("no unapproved USB device, period").
   - **Resolution:** Added an explicit, dedicated bullet to `README.md` §11 (distinct from the
     general non-goals list) naming this as a bypass, citing the `WpdDevices` `PrimaryId` family
     and the `-EndpointDlpRestrictions`-style multi-value OMA-URI syntax needed to close it, and
     explaining why closing it wasn't bundled into this fragment (different device-matching
     properties available for WPD - no `SerialNumberId`/`VID_PID`). Tracked as a follow-up in
     `PROGRESS.md`.
2. **`VID_PID`-only allowlist entries approve an entire product line, not one physical drive.** A
   red-teamer who buys the identical make/model of an approved drive gets full read/write access.
   - **Resolution:** Already called out in the original draft (`README.md` §11, `design.md` §7)
     with `SerialNumberId` recommended as the stronger per-unit alternative; confirmed this
     framing is honest (not presented as "solved") and the sample config defaults to
     `serialNumberId` - no further change needed.
3. **Group Policy silently overrides Intune device control if both target the same machine**
   (Microsoft's own FAQ). A red-teamer (or a stale legacy GPO) could neutralize this scenario's
   policy without any error surfacing in Intune.
   - **Resolution:** Already called out in the original draft (`README.md` §11, citing the FAQ
     directly) as a pre-flight check before troubleshooting; confirmed this is adequate - no
     further change needed, since detecting/removing a conflicting GPO is an environment-specific
     cleanup task outside this scenario's deploy surface.
4. **A drive reformatted or reflashed to spoof an approved `VID_PID`** (firmware-level vendor/
   product ID spoofing tools exist for some flash controllers) would pass the `VID_PID` match.
   - **Resolution:** This is the same underlying weakness as finding 2, not a separate bypass -
     folded into the existing `SerialNumberId`-preferred guidance rather than treated as a new
     finding; a spoofed serial number is a materially harder attack than a spoofed `VID_PID`
     against commodity tooling, which is exactly why the README recommends it as the stronger
     option.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`ActionType` ambiguity between this control and Windows device installation restrictions.**
   The original draft's Advanced Hunting query (§7 step 5) queried
   `RemovableStoragePolicyTriggered` correctly, but nothing warned an analyst that a *different*
   Microsoft control (device installation restrictions) emits a same-sounding but distinct
   `PnPDeviceBlocked` event for a related-but-different enforcement point - an analyst querying
   the wrong table would see zero results and could wrongly conclude the policy isn't firing.
   - **Resolution:** Added an explicit callout directly under the query in `README.md` §7
     distinguishing the two `ActionType` values and which control produces each.
2. **No per-device profile-sync validation, same acceptable scope boundary as
   `endpoint-dlp-usb-block`.** The validation script can confirm the Graph-side object and its
   settings are correct, but cannot confirm a specific pilot device has actually applied the
   profile.
   - **Resolution:** No code change needed - this was already documented as an explicit,
     acknowledged scope boundary in the original draft (`README.md` §7 intro, `validate/
     Test-DeviceControlUsbAllowlistPolicy.ps1`'s `.DESCRIPTION`), matching the sibling scenario's
     identical, already-accepted precedent for the same class of limitation.
3. **Incident-response runbook** was present in the initial draft (unlike the sibling scenario's
   first draft, which needed one added during its own review) - confirmed it covers triage,
   classification, an explicit "remove a lost/decommissioned drive immediately" step unique to
   this scenario's allowlist model, and an evidence-retention step. No gap found.
4. **Alert-routing citation accuracy.** The original draft's alert-routing paragraph used an
   invented product name ("Microsoft Defender XDR Streaming API") that doesn't match Microsoft's
   actual current naming.
   - **Resolution:** Corrected to the actual product name (**Microsoft Defender Streaming API**)
     and added a second, independently-grounded citation for the Microsoft Defender XDR
     connector's "Connect events" `DeviceEvents`-table ingestion path into Microsoft Sentinel -
     both added to `README.md` §8 and §12 (references 16-17).

No remaining Fail. Detection, logging, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate and additive - this scenario closes a gap
  (device-identity awareness) that the sibling content-based control structurally cannot close,
  at a licensing cost of zero incremental spend for a tenant already at Defender for Endpoint
  Plan 1/Microsoft 365 E3 for other reasons. The one real new cost line - Intune, if not already
  present - is called out explicitly in §10 rather than assumed away.
- **Change-management impact:** the audited-allow (not silently trusted) design for the approved
  drives, and the staged pilot-group-then-tenant-wide rollout, follow the same change-management
  discipline this repo has already established works (`pci-teams-exfil-block`'s Card Ops override,
  `endpoint-dlp-usb-block`'s IT Data Custodians exception) - a device-identity control that
  blocked a legitimate drive on day one with no staged rollout would get disabled by business
  pushback exactly as those precedents warn.
- **Board-level narrative:** "we maintain a closed, auditable list of every physical drive with
  write access to any in-scope endpoint, we log every use of an approved drive (not just denials),
  and the one bypass we know about (phones/cameras in portable-device mode) is documented as an
  explicit residual risk with a scoped path to close it" is a defensible, specific narrative - not
  an overclaim.
- **Compliance mapping:** correctly scoped as a general media-controls reinforcement referenced
  across GDPR/HIPAA/PCI/SOC2 rather than claiming a single named requirement, consistent with how
  the sibling scenario frames the same regulatory landscape.
- **Would I fund this?** Yes - paired with `endpoint-dlp-usb-block` as the two-layer removable-
  media posture this repo's §2 explicitly recommends, not as a standalone purchase; the README is
  upfront that neither scenario alone is a complete answer.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Why raw OMA-URI instead of the native "Device Control profile" template?** A reviewer
   familiar with the current Intune UI would expect this scenario to use the purpose-built Device
   Control profile / reusable-settings-groups experience, not hand-built XML.
   - **Resolution:** `design.md` §4 explains the decision directly: no independently-grounded
     Graph resource schema for the native profile *type* was found during this build's grounding
     pass, whereas the Custom OMA-URI mechanism is fully documented at both the CSP and Graph
     layers and is presented by Microsoft's own docs as the API-equivalent path. Flagged as a
     revisit-when-Microsoft-documents-it follow-up rather than guessed.
2. **Licensing citation accuracy** - checked "Overview of Microsoft Defender for Endpoint Plan 1"
   directly: device control is confirmed listed as a Plan 1 attack-surface-reduction capability,
   and Plan 1 is confirmed bundled in Microsoft 365 E3. Correctly distinguished from this
   repository's Purview-licensed scenarios (§3 explicitly notes `docs/licensing-matrix.md` doesn't
   yet cover this product family, rather than silently presenting it as covered).
3. **`New-MgDeviceManagementDeviceConfiguration` and sibling cmdlets are v1.0, not beta** -
   confirmed directly against the official cmdlet reference page (not the
   `New-MgBetaDeviceManagementDeviceConfiguration` variant), consistent with
   `docs/automation-surface.md` §2's guidance to avoid `Microsoft.Graph.Beta.*` in shipped
   automation. The deploy script correctly uses `Invoke-MgGraphRequest` against the `v1.0` base
   URI, not `/beta`.
4. **PATCH replace-vs-merge semantics for `omaSettings` are not confirmed** - Microsoft's `Update
   windows10CustomConfiguration` reference documents the property as updatable but is silent on
   whether a PATCH replaces or merges the collection, which matters specifically for the
   *removal* case (dropping a revoked drive from the allowlist).
   - **Resolution:** Flagged as an explicit `VERIFY` in `README.md` §11 and the deploy script's
     `.NOTES`, directing a pilot-tenant confirmation before relying on `-Force` to remove an
     entry, rather than asserting either behavior as confirmed.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (1 closed with new documentation, 2 confirmed already correctly scoped, 1 folded into an existing finding) | Closed |
| 🔵 Blue Team | Fix | 4 (2 closed, 2 confirmed already correctly scoped/present) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 4 (1 closed with a VERIFY tag, 3 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-DeviceControlUsbAllowlistPolicy.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.
