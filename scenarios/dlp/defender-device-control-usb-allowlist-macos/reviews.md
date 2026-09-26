# Four-Lens Review — Defender for Endpoint Device Control (macOS): USB Default-Deny Allowlist

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Portable Devices (cameras, phones in PTP-analogous modes), Apple (iOS/iPadOS) devices, and
   Bluetooth media are completely invisible to this control, not merely unrestricted.** The
   policy's groups scope enforcement to `primaryId: removable_media_devices` only. A user who
   exfiltrates data via a phone connected as a portable device (rather than a USB mass-storage
   drive) or an iPhone in backup/sync mode generates **no** audit event and **no** block — the
   direct macOS analog of the Windows sibling's undetected Windows Portable Device (WPD) bypass.
   - **Resolution:** Added a dedicated, first-listed bullet to `README.md` §11 naming this as a
     bypass (not folded into the generic non-goals list), citing the `primaryId` family split and
     explaining why closing it wasn't bundled into this fragment. Tracked as a follow-up in
     `PROGRESS.md`, the same treatment the Windows sibling's WPD gap already received.
2. **`serialNumber`-only matching means a device without a readable/reportable serial number, or
   one whose serial number is spoofed via firmware tooling, is either unusable as an approved
   device or a viable (if harder-than-`VID_PID`) bypass target.** Commodity USB-controller
   firmware-spoofing tools that rewrite a reported serial number exist, the direct macOS analog of
   the Windows sibling's `VID_PID`-spoofing concern.
   - **Resolution:** Already called out honestly in the original draft (`README.md` §11) as a
     scope boundary rather than a solved problem — a device lacking a serial number cannot use
     this scenario as-is. Confirmed this framing is adequate: `serialNumber` is still the
     *strongest* standalone identifier this schema supports (Microsoft's own docs note it "doesn't
     match if the device doesn't have a serial number," i.e. it's a hard, not probabilistic,
     match), and the Windows sibling's own README recommends the equivalent (`SerialNumberId`) as
     its stronger default for exactly this reason — no further change needed.
3. **An already-existing, independently-deployed `com.microsoft.wdav` preferences profile
   (e.g. one only configuring cloud-delivered protection settings) could silently conflict with,
   merge unpredictably with, or be overwritten by this scenario's own same-`PayloadIdentifier`
   profile** — a way to neuter or leave gaps in this control without touching this scenario's own
   Graph object at all, and Apple's cross-profile merge semantics for this specific case are not
   documented by Microsoft.
   - **Resolution:** Added as an explicit `VERIFY` in `README.md` §11 (not resolved by guessing
     either direction) rather than asserting the profile is safe to deploy alongside any existing
     macOS MDE configuration. This is a materially different risk class from the Windows sibling's
     GPO-vs-Intune precedence finding (that one has a documented answer; this one does not) — kept
     as its own, separately-flagged item rather than conflated with it.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Full Disk Access grant status (`v2_full_disk_access`) has no remote, at-scale check** — the
   only confirmed way to observe it is `mdatp health --details device_control` run locally on each
   Mac's Terminal. A fleet-wide rollout with dozens of pilot Macs has no scripted way to confirm
   Full Disk Access was actually granted on all of them before assuming the policy is enforcing.
   - **Resolution:** Documented as an explicit, acknowledged scope boundary in `README.md` §7 step
     4 and the incident-response runbook addition in §8, rather than fabricating an unconfirmed
     remote-query mechanism. A candidate follow-up (a Defender for Endpoint device-health/
     compliance-signal check surfacing this remotely) is worth scoping once independently
     grounded — not invented here per `AGENTS.md` §4.
2. **Validation script extracts the embedded policy JSON via regex, not a full plist parse.** A
   future Microsoft change to `.mobileconfig` whitespace/escaping conventions inside the
   `<string>` payload could break the extraction silently (a false negative on an otherwise-healthy
   deployment).
   - **Resolution:** Confirmed this is an accepted, documented trade-off (the script's own inline
     comment explains the choice — a regex extraction is more robust than a strict `[xml]` parse
     for a read-only check, since a full XML round-trip would fail entirely on any encoding quirk
     rather than degrade gracefully), consistent with the repo's existing precedent for
     validation-script robustness trade-offs. No code change needed.
3. **Incident-response runbook** — confirmed it covers triage (including the macOS-specific Full
   Disk Access cross-check ahead of assuming policy misconfiguration), classification, an
   immediate-removal step for a lost/decommissioned drive, and evidence retention, matching the
   Windows sibling's already-accepted runbook shape. No gap found.
4. **Alert-routing citation accuracy** — confirmed `DeviceEvents` is a single, OS-agnostic Advanced
   Hunting table (not a separate macOS-specific table), so the Windows sibling's Microsoft Defender
   Streaming API / Sentinel "Connect events" citations apply here without needing independent
   re-grounding. Cross-referenced rather than duplicated in `README.md` §8.

No remaining Fail. Detection, logging, and the runbook meet the bar for an operable control, with
one honestly-scoped gap (finding 1) rather than a fabricated fix.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** closes a real, common gap (zero device-identity USB control on
  every Mac in a mixed fleet already running the Windows sibling) at the same zero-incremental-
  licensing-cost profile as the Windows scenario for a tenant already at Defender for Endpoint
  Plan 1 / Microsoft 365 E3.
- **Board-level narrative:** "the same closed, auditable USB allowlist posture we run on Windows
  now also runs on every managed Mac, with the same fail-closed default and the same two known,
  documented residual risks (non-mass-storage device types, and devices without a serial number)"
  is a defensible, platform-complete narrative — not an overclaim, since both residual risks are
  disclosed rather than hidden.
- **Change-management impact:** identical staged-rollout discipline to the Windows sibling
  (pilot-group-then-tenant-wide, both allow and deny paths audited) — the same pattern this repo
  has already shown avoids the "day-one business pushback" failure mode.
- **Compliance mapping:** correctly scoped as the same general media-controls reinforcement
  referenced across GDPR/HIPAA/PCI/SOC2 as the Windows sibling, not claiming a macOS-specific
  named requirement that doesn't exist.
- **Would I fund this?** Yes — as the direct fleet-completeness companion to the Windows sibling,
  not a standalone purchase; an organization running only the Windows scenario across a mixed fleet has an
  honest, disclosed gap this scenario closes.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Confirmed `macOSCustomConfiguration` is the correct, only documented Intune authoring path**
   for macOS device control — checked directly against Microsoft's own Intune deployment guide
   (`mac-device-control-intune`) and the Graph v1.0 resource/create reference. Unlike the Windows
   sibling, there was no competing "native profile template vs. raw mechanism" decision to weigh —
   correctly reflected in `design.md` §3 as "no alternative to weigh," not framed as an artificial
   choice.
2. **`macOSCustomConfiguration`'s Create/Update operations are confirmed v1.0, not beta** —
   checked directly against the official reference pages, consistent with
   `docs/automation-surface.md` §2's guidance to avoid `Microsoft.Graph.Beta.*`/`/beta` endpoints
   in shipped automation.
3. **Licensing citation accuracy** — checked both `mac-device-control-intune` and
   `mac-device-control-jamf` directly: both independently state the Microsoft 365 E3 minimum in
   language matching the Windows product's own licensing page, confirming this scenario's §3/§10
   claims rather than assuming licensing parity across platforms without checking.
4. **The `DC_in_dlp` feature-enable step is a genuinely separate, easy-to-miss prerequisite from
   the device-control policy's own `removableMedia.disable = false` setting** — a reviewer
   unfamiliar with macOS device control's two-step enable model could reasonably assume one
   setting alone is sufficient.
   - **Resolution:** Both steps are explicitly listed as separate rows in `README.md` §6's
     configuration reference table and separately explained in `design.md` §4, rather than
     collapsed into a single "enable device control" bullet the way a less careful writeup might.
5. **PATCH replace-vs-merge semantics for `payload`, and the multi-profile-conflict question, are
   both correctly flagged as open `VERIFY`s rather than asserted** — consistent with `AGENTS.md`
   §4's no-guessing rule and the same rigor the Windows sibling's own open `VERIFY` items already
   established as this repo's house standard.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with new documentation, 1 confirmed already correctly scoped, 1 closed with a new VERIFY) | Closed |
| 🔵 Blue Team | Fix | 4 (1 closed as an acknowledged scope boundary, 1 confirmed an accepted trade-off, 2 confirmed already correctly scoped/present) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 5 (1 clarified in design.md, 1 clarified in README.md's config table, 3 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.
