# Four-Lens Review — Defender for Endpoint Device Control (macOS): Apple/Portable/Bluetooth Coverage

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`serialNumber` is presented as a strong identifier without the spoofing caveat the parent
   scenario already carries for the same property.** The initial draft's §11 stated only that a
   device without a serial number can't be allowlisted — it didn't restate the parent scenario's
   own accepted risk (`reviews.md` there, Red Team finding 2) that a reported serial number is
   firmware-level metadata an attacker can rewrite with commodity tooling. Given this fragment
   introduces **two more** allowlists using the identical property, omitting the caveat here would
   read as a stronger, unqualified claim than the parent scenario itself makes for the same
   mechanism.
   - **Resolution:** Added a dedicated bullet to `README.md` §11 restating the spoofability risk
     explicitly for the Apple/Portable allowlists, with the same "compensating control, not a
     cryptographic identity boundary, keep it small and IT-managed" framing the parent scenario and
     the Windows WPD-coverage sibling already use.
2. **The Bluetooth deny rule's actual restriction scope was not stated precisely enough to prevent
   overclaiming.** The initial draft's Configuration Reference table listed the two `bluetoothDevice`
   access strings but didn't call out, in the limitations section, that this is a file-transfer-only
   restriction — an organization or a less careful implementer could read "Bluetooth coverage" as "Bluetooth
   is blocked" and be surprised that Bluetooth audio, HID peripherals, tethering, and pairing all
   continue working normally.
   - **Resolution:** Added an explicit bullet to `README.md` §11 stating the restriction is scoped
     to `download_files_from_device`/`send_files_to_device` only, with an instruction not to
     describe the control as "Bluetooth is disabled" to an organization.
3. **No approved-device allowlist for Bluetooth at all — is an organization with a legitimate Bluetooth
   file-transfer use case (e.g. an approved barcode scanner) left with only "block everything or
   nothing"?** Confirmed as a real, disclosed scope limit, not an oversight: Microsoft's own worked
   sample for this family uses a structurally different (vendorId+productId, single-device)
   exception mechanism than the OR'd-serialNumber pattern used for the other two families in this
   fragment (`design.md` §5).
   - **Resolution:** Already called out as a deliberate, cited scope decision in the initial draft
     (`README.md` §11 first bullet, `design.md` §5, deploy script `.NOTES`) rather than a silent
     gap — confirmed this framing is adequate (names the exact mechanism Microsoft documents, cites
     the worked sample, tracks the follow-up in `PROGRESS.md`) and does not need further change.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Fabricated Advanced Hunting field found during this review, not by an external persona: the
   initial draft's §7 step 8 worked query referenced a `PolicyName` `AdditionalFields` property that
   was never confirmed against any Microsoft source** — a genuine grounding violation of `AGENTS.md`
   §4 (this repo's own no-invented-field-names rule), not merely an unconfirmed VERIFY-tagged
   assumption. The field was invented to serve the query's own stated purpose (distinguishing which
   rule/family triggered an event) without being checked first.
   - **Resolution:** Re-grounded against Microsoft's own worked Windows-side Advanced Hunting
     example (`device-control-overview`, "Control access to removable media using device control"),
     which confirms the actual field name is `RemovableStoragePolicy` (populated from
     `parsed.RemovableStoragePolicy`, the rule name). `README.md` §7 step 8's query was rewritten to
     use the confirmed field (aliased `PolicyRule` for readability) and a new reference was added to
     §12. The query now also explicitly states it relies on the macOS parent scenario's own already-
     established cross-platform `DeviceEvents` schema assumption for this specific field, since the
     worked example that confirms it is Windows-side, not macOS-side — the same honest sourcing
     chain the parent scenario's own §7 query already uses for `Verdict`/`SerialNumberId`.
2. **Idempotency-detection edge case: does switching an already-deployed family's config from
   "has an allowlist" to "empty allowlist" (or vice versa) actually reconcile correctly, or does the
   stale allow rule / approved group linger?** Traced through `deploy/
   Add-MacPortableDeviceCoverage.ps1`'s merge logic: `$keptGroups`/`$keptRules` filter out **every**
   ID in this fragment's own fixed-GUID set before re-adding only what the current `-ConfigPath` run
   calls for — so a family that loses its allowlist correctly drops both the approved group and the
   allow rule on the next `-Force` reconcile, not just skips adding a new one.
   - **Resolution:** Confirmed correct by code inspection; no change needed. Documented explicitly
     in `deploy/Add-MacPortableDeviceCoverage.ps1`'s inline comments (the "filter-then-readd"
     pattern) so this isn't left to inference by a future maintainer.
3. **The deploy/remove scripts extract the embedded policy JSON via a targeted regex over a known,
   fixed `<key>policy</key><string>...</string>` shape rather than a full plist parse — a write path,
   not just the parent's already-accepted read-only validation trade-off.** A future Microsoft
   change to `.mobileconfig` whitespace/escaping conventions could break extraction silently.
   - **Resolution:** Confirmed as an accepted, now-explicitly-documented trade-off consistent with
     the parent scenario's own precedent (`defender-device-control-usb-allowlist-macos/reviews.md`,
     Blue Team finding 2) — `design.md` §7 states this decision and its rationale explicitly rather
     than leaving it implicit. Both scripts also fail loudly (`throw`) rather than silently
     corrupting the payload if the expected `<key>policy</key>` node isn't found or the post-replace
     string is unchanged, so a future Microsoft formatting change surfaces as a hard error on the
     next deploy/remove run, not a silent no-op or corrupted PATCH.

No remaining Fail. The fabricated field found during this review is fixed with a re-grounded
citation, not merely flagged.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate and genuinely additive — this fragment closes three
  confirmed, silent bypasses of the parent control (Apple, Portable, Bluetooth) at zero incremental
  licensing cost (§10). The honest framing in §11 (spoofable serial numbers, file-transfer-only
  Bluetooth scope, no Bluetooth allowlist) is the right level of confidence to sell at.
- **Change-management impact:** widening the parent's existing object (not competing profiles)
  means zero additional assignment/rollout process for an org that has already piloted and widened
  the parent — reuses the parent's proven staged-rollout and KPI-review discipline rather than
  re-deriving it.
- **Board-level narrative:** "we extended our macOS USB device-identity control to also cover
  iPhones/iPads, cameras/portable devices, and Bluetooth file transfer, using the same audited-
  allow/audited-deny model, with three known, disclosed limitations we manage through allowlist
  hygiene and scope-accurate messaging" is specific and defensible — not an overclaim.
- **Compliance mapping:** correctly inherits the parent's general media-controls framing (§2)
  rather than asserting a new, separate regulatory citation for this fragment's delta.
- **Would I fund this?** Yes, for an organization that has already funded and piloted the parent
  scenario — the natural, low-incremental-cost next increment to close three review-confirmed gaps
  at once, not three speculative separate purchases.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is widening the parent's shared payload architecturally correct, versus authoring a second,
   independent Custom profile?** A reviewer might expect one profile per device family as a cleaner
   separation of concerns, mirroring how some other MDM controls are organized.
   - **Resolution:** `design.md` §3 confirms directly from Microsoft's own reference that macOS
     device control's entire policy (all four families) lives in one `deviceControl.policy` JSON
     document inside one fixed-`PayloadIdentifier` (`com.microsoft.wdav`) profile — a second such
     profile risks an undocumented MDM profile-merge conflict, the same open risk the parent
     scenario's own Red Team review already flags for an independently-authored profile of this
     type. Widening the shared payload is the only conflict-free design. No further change needed.
2. **Entry `$type` capitalization correctness — does this fragment use the right casing for
   `portableDevice`?** The Learn page's own entry-property table shows `PortableDevice` (capital P)
   in one cell.
   - **Checked and confirmed correct:** three of Microsoft's own published GitHub sample policies
     (`audit_all_apple_devices.json`, `deny_mobile_devices.json`,
     `deny_all_bluetooth_devices_except_samsung.json`) all use the lowercase `portableDevice`,
     consistent with the same page's separate Access Types table and with `appleDevice`/
     `bluetoothDevice`'s uncontested lowercase-first-letter casing. Treated correctly as a
     documentation table rendering inconsistency, not a second valid casing (`design.md` §2 goal 5,
     `README.md` §6). No change needed.
3. **Access-string list accuracy per family** — a reviewer might assume all four `entry.$type`
   families share one access vocabulary (as `removableMedia`'s `[read, write, execute]` might
   suggest) rather than each having its own enumerated set.
   - **Checked and confirmed correct:** the five-item `appleDevice`, four-item `portableDevice`, and
     two-item `bluetoothDevice` access lists in `README.md` §6 and `design.md` §4 are each the
     family's full documented set from Microsoft's official Access Types table, independently
     cross-checked against all three of the grounding GitHub worked samples — no fabricated or
     assumed access strings. No change needed.
4. **Does `settings.global.defaultEnforcement` (the parent's fail-closed `"deny"` default) survive
   this fragment's merge untouched, or could a reconcile silently reset it to Microsoft's own
   documented `"allow"` default?**
   - **Checked and confirmed correct:** `deploy/Add-MacPortableDeviceCoverage.ps1`'s
     `$desiredSettings` explicitly carries `$parsedPolicy.settings.global` through from the live
     object on every run — it is never reconstructed from a hardcoded default. No change needed.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with new `README.md` §11 disclosures, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed by re-grounding a fabricated field to a real, confirmed one, 2 confirmed correct/accepted by inspection) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 4 (all confirmed correct on inspection) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/Add-MacPortableDeviceCoverage.ps1` — including a genuine fabricated-field grounding defect
(Blue Team finding 1) caught and fixed during this review, not merely documented. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.
