---
part: "design"
parent: "dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage"
---
## 1. Problem statement

`scenarios/dlp/defender-device-control-usb-allowlist-macos/` deploys a default-deny, named-
allowlist removable-storage control for macOS, scoped to `primaryId: removable_media_devices`
only. Microsoft's own device control documentation is explicit that macOS device control also
manages three further, independent device families — `apple_devices`, `portable_devices`, and
`bluetooth_devices` — each with its own enable switch, its own group/rule matching, and its own
access-type vocabulary [[1]](#references). A `removable_media_devices`-only policy does not deny
these devices; it does not see them at all, exactly the same "different device family, not a
narrower rule" structure the Windows sibling's own WPD-coverage fragment closed for
`WpdDevices`. This was flagged as a confirmed Red Team finding in the parent scenario's own review
(`reviews.md`, finding 1) and tracked as a follow-up in this repo's `PROGRESS.md`.

This fragment closes that gap by widening the parent's existing policy object to also cover all
three families, reusing the parent's proven default-deny/audited-both-paths shape.

## 2. Design goals

1. **Extend, don't duplicate.** The parent's `deviceControl.policy` JSON is a single embedded
   string inside one `macOSCustomConfiguration` object's `.mobileconfig` payload — a second,
   competing profile targeting the same devices would conflict, not layer (§3 below). This fragment
   PATCHes the parent object's payload in place.
2. **Preserve the parent's coverage exactly.** The deploy script never touches the parent's
   `removableMedia` feature flag, `AllRemovableStorage`/`ApprovedBackupDrives` groups, or either
   `RemovableMediaDevices`-scoped rule — it identifies and reconciles only the groups/rules/feature
   flags it owns (by fixed GUID / fixed feature key), passing everything else through untouched.
   `validate/Test-MacPortableDeviceCoverage.ps1` explicitly checks the parent's original settings
   survive unmodified.
3. **Mirror the parent's mutually-exclusive rule shape, per family.** For Apple and Portable
   devices: one approved group (optional), one catch-all group, one allow rule (included =
   approved), one deny rule (included = catch-all, excluded = approved when configured) — a device
   matches exactly one rule per family by construction. Bluetooth is catch-all-deny-only in this
   fragment (§5).
4. **Both allow and deny paths are audited, not just the deny path** — same principle as the parent
   (`design.md` §2 there) and the Windows WPD-coverage sibling, extended to all three new families.
5. **Prefer a directly-confirmed worked example over a prose reference table wherever the two seem
   to disagree.** The Learn page's entry-`$type` property table renders one family as
   `PortableDevice` (capitalized), inconsistent with every other row in that same table and with
   the page's own separate Access Types table below it (lowercase `portableDevice`). Rather than
   guess which rendering is authoritative, this fragment's grounding pass fetched three of
   Microsoft's own published GitHub sample policies and found all three use the lowercase form with
   zero worked examples using the capitalized one — treated as a documentation table rendering
   inconsistency, not a second valid casing (§6).
6. **State genuinely open gaps honestly rather than resolve them by guessing** — the
   `portable_devices`-`serialNumber` VERIFY and the deliberate Bluetooth-has-no-allowlist scope
   decision (§5) are both disclosed in `README.md` §11, not silently assumed.

## 3. Why widen the parent's payload instead of a second Custom profile

Microsoft's macOS device control model has exactly one policy object per Mac's assigned
configuration — `deviceControl.policy` inside one `.mobileconfig` — carrying every family's
groups/rules/settings together as one JSON document [[1]](#references)[[2]](#references)
(`PayloadIdentifier: com.microsoft.wdav`, a fixed, singular identifier). Two Intune macOS Custom
profiles both delivering a `com.microsoft.wdav`-typed payload to the same Mac would be a genuine
MDM profile-merge conflict — the same open, undocumented-by-Apple risk the parent scenario's own
`reviews.md` (Red Team finding 3) already flags for an *independently-authored* `com.microsoft.wdav`
profile, which this fragment must not compound by deliberately creating a second one itself. Given
that, extracting the parent's live `deviceControl.policy` JSON, merging in this fragment's
additions, and PATCHing the whole payload back is the only conflict-free way to add coverage to
devices already assigned the parent policy.

This mirrors this repository's own precedent for "add to, don't duplicate, an existing policy
object" companions — `scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage/` (the
direct Windows analog of this fragment), `scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-
audit-companion/`, and `scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/` all add
to a parent scenario's existing object rather than standing up a second, overlapping one.

## 4. Policy architecture (delta from the parent)

| # | Object | Purpose | Status |
|---|---|---|---|
| — | `settings.features.removableMedia` | Parent's own enable flag | **Unchanged** — read from the live object and passed through untouched |
| — | `groups[]`/`rules[]` for `AllRemovableStorage`/`ApprovedBackupDrives` | Parent's own removable-media coverage | **Unchanged** |
| 1–3 | `settings.features.appleDevice` / `.portableDevice` / `.bluetoothDevice`, each `{"disable": false}` | Enable enforcement for the three new families — each is disabled by default even once the top-level `DC_in_dlp` engine switch is on [[1]](#references) | **New** |
| 4 | Group `AllAppleDevices` | `primaryId: apple_devices` catch-all | **New** |
| 5 | Group `ApprovedAppleDevices` (optional) | `serialNumber` OR'd allowlist, from `-ConfigPath` | **New, conditional** |
| 6 | Group `AllPortableDevices` | `primaryId: portable_devices` catch-all | **New** |
| 7 | Group `ApprovedPortableDevices` (optional) | `serialNumber` OR'd allowlist, from `-ConfigPath` | **New, conditional** |
| 8 | Group `AllBluetoothDevices` | `primaryId: bluetooth_devices` catch-all | **New** |
| 9 | Rule `Allow-ApprovedAppleDevices` (if configured) | `appleDevice` entries: `allow` + `auditAllow`, `access` = the 5 documented `appleDevice` access strings | **New, conditional** |
| 10 | Rule `Deny-All(Other)AppleDevices` | `appleDevice` entries: `deny` + `auditDeny`, same access list | **New** |
| 11 | Rule `Allow-ApprovedPortableDevices` (if configured) | `portableDevice` entries: `allow` + `auditAllow`, `access` = the 4 documented `portableDevice` access strings | **New, conditional** |
| 12 | Rule `Deny-All(Other)PortableDevices` | `portableDevice` entries: `deny` + `auditDeny`, same access list | **New** |
| 13 | Rule `Deny-AllBluetoothDevices` | `bluetoothDevice` entries: `deny` + `auditDeny`, `access` = the 2 documented `bluetoothDevice` access strings; no `excludeGroups` | **New** |

Every access-string list above is the family's **full** documented set (not Microsoft's own
"generic access types" best-practice shortcut) — chosen to mirror the parent scenario's and the
Windows WPD-coverage sibling's own precedent of enumerating a family's specific access set
explicitly rather than using the `generic` entry `$type`, and because all three of the worked
GitHub samples this fragment grounds against do the same (`audit_all_apple_devices.json`,
`deny_mobile_devices.json`, `deny_all_bluetooth_devices_except_samsung.json` all use family-typed
entries with explicit access arrays, never `$type: generic`) [[2]](#references).

## 5. Why Bluetooth has no approved-device allowlist in v1

Apple and Portable devices reuse the parent's proven `serialNumber`/`or`-clause, OR'd-multi-device
group shape — directly confirmed for `apple_devices` via Microsoft's own
`audit_all_apple_devices_except_serial_numbers.json` sample [[2]](#references). Bluetooth is
different: Microsoft's own worked exception-group sample for this family
(`deny_all_bluetooth_devices_except_samsung.json`) matches a **single** device by ANDing
`primaryId` + `vendorId` + `productId` in one group query, not by OR'ing `serialNumber` values
across several [[2]](#references) — the same structural reason the parent macOS scenario's own
`design.md` §5 already gives for deferring `vendorId`/`productId` compound matching for removable
media: representing **more than one** AND'd vendor+product pair inside one allowlist requires a
per-device sub-group referenced via a `groupId` clause, a materially more complex, dynamic-GUID
idempotency model this fragment's four-fixed-GUID-per-family design does not attempt.

Rather than build a second, differently-shaped config schema and idempotency model for exactly one
family in an already-multi-family fragment, this fragment ships Bluetooth as **default-deny-only,
no exceptions** — a fully grounded, simpler posture that still closes the invisibility gap (the
core ask this fragment exists to address) without guessing at an unverified multi-device
vendor+product allowlist shape. A `vendorId`+`productId`-matched Bluetooth allowlist (single device
in v1, matching Microsoft's own sample shape) is tracked as a follow-up in `PROGRESS.md`.

## 6. Why `serialNumber` for Portable devices is a VERIFY, not a confirmed default

Microsoft's Clause reference presents `serialNumber`, `vendorId`, `productId`, etc. as one flat,
family-unscoped table — a materially stronger starting position than the Windows sibling's own
WPD-coverage fragment had to work with, where the equivalent Windows property-support table was
also unscoped by device family but the *page's structure itself* left open whether
`SerialNumberId`/`VID_PID` extend to `WpdDevices` at all. Here, no Microsoft documentation
suggests `serialNumber` is *excluded* for `portable_devices`. However, this build's grounding pass
found a directly-confirmed worked example only for `apple_devices`
(`audit_all_apple_devices_except_serial_numbers.json`) — none was found pairing `serialNumber` with
a `portable_devices`-scoped group specifically. Per `AGENTS.md` §4, this fragment uses
`serialNumber` for Portable devices (consistent with the flat, unscoped clause table and with this
scenario's own Apple-device precedent) but flags it as an open `VERIFY` in `README.md` §11 and
checks it as `[WARN]` in `validate/Test-MacPortableDeviceCoverage.ps1`, rather than asserting it as
confirmed.

## 7. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Deploy surface | Same as parent — Microsoft Graph (`Connect-MgGraph`, app-only certificate), `Invoke-MgGraphRequest` against `v1.0` | Consistency; this fragment PATCHes the same object the parent created. |
| Target object | The parent's existing `macOSCustomConfiguration`, located by `parentPolicyDisplayName` | §3 above — a second `com.microsoft.wdav`-typed profile risks an undocumented MDM profile-merge conflict, not a clean layer. |
| Extraction mechanism | Regex over the known, fixed `<key>policy</key><string>...</string>` shape the parent script always produces | The parent scenario's own `validate` script already accepts this exact trade-off over a strict `[xml]` plist parse (`defender-device-control-usb-allowlist-macos/reviews.md`, Blue Team finding 2) — this fragment's *deploy* script extends the same accepted precedent to a *write* path, substituting only the matched `<string>` node's content and leaving every other plist key untouched. |
| Update strategy | Whole-payload replacement on every reconcile (PATCH with the freshly rebuilt `.mobileconfig`) | Matches the parent's own update strategy and its documented open VERIFY on `payload` PATCH replace-vs-merge semantics (`README.md` §11 there) — this fragment's PATCH calls carry the identical, not a new, risk. |
| Approved-device matching (Apple/Portable) | `serialNumber`, OR'd, optional (empty = pure default-deny) | §6 above; consistent with the parent's own removable-media default. |
| Approved-device matching (Bluetooth) | None in v1 — always default-deny | §5 above. |
| Access-string lists | Each family's full documented set, not Microsoft's `generic` entry-`$type` shortcut | §4 above — matches all three grounding worked samples and this repo's existing sibling scenarios' own precedent of explicit, family-typed entries. |
| GUIDs | Ten new fixed, source-controlled GUIDs (five groups, five rules), distinct from the parent's six | Same idempotent-reconcile rationale as the parent and the Windows WPD-coverage sibling (`design.md` §7 there) — every re-run targets the same ten nodes. |
| Rollback granularity | A dedicated `Remove-MacPortableDeviceCoverage.ps1` that reverts only this fragment's delta, not the whole policy | The parent's own `Remove-MacDeviceControlUsbAllowlistPolicy.ps1` (unassign or `-Purge`) remains the tool for removing the entire control; this fragment needs a narrower "turn off just these three families" lever, since all four families now share one payload. |

## 8. Non-goals

- This scenario does not create a new Intune device configuration object, a new assignment, or
  change the parent policy's assignment scope — it only widens the shared object's payload.
- This scenario does not build a Bluetooth approved-device allowlist (§5) or resolve the
  `portable_devices`-`serialNumber` VERIFY (§6) — both deliberately left open per `AGENTS.md` §4
  rather than guessed, and trackable in `PROGRESS.md`.
- This scenario does not implement `vendorId`/`productId` compound matching for Apple or Portable
  devices — the same per-device, dynamic-sub-group idempotency complexity the parent macOS
  scenario's own `design.md` §5 already defers for removable media, not re-litigated here.
- This scenario does not deploy via JAMF — Intune only, matching the parent's own scope boundary.
  Because the underlying `deviceControl.policy` JSON schema is identical across both deployment
  paths, the same groups/rules/settings shape this fragment grounds applies equally to
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/`'s JAMF-managed sibling — closing
  this fragment for the Intune path closes the equivalent PROGRESS.md follow-up tracked for JAMF
  too, without a second build.
- This scenario does not address the `encryption: apfs` clause or the `mediaSerialNumber`/
  `mediaProductName`/`mediaApplicationId` (Secure Digital card) clauses — out of scope, matching the
  parent scenario's own non-goals.

## References

See `README.md` §12 for the full citation list. Every product fact in this document is grounded
directly against Microsoft Learn and Microsoft's own published GitHub sample policies, fetched
during this fragment's own build (not carried over unverified from the parent scenario or the
Windows WPD-coverage sibling).
