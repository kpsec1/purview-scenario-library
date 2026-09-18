---
part: "design"
parent: "dlp/defender-device-control-usb-allowlist-wpd-coverage"
---
## 1. Problem statement

[`dlp/defender-device-control-usb-allowlist`](/scenarios/dlp/defender-device-control-usb-allowlist/) deploys a default-deny allowlist scoped to
`SecuredDevicesConfiguration = RemovableMediaDevices` — the device family that creates a disk
letter in Windows. Microsoft's own device control documentation is explicit that this is a
narrower definition than "any USB device": a device that instead enumerates as a **Windows
Portable Device (WPD)** — the family covering most phones, tablets, and cameras connected via MTP
or PTP — is a structurally different device family, and "when device types are configured, device
control in Defender for Endpoint ignores requests to other device families"
(`device-control-policies#controlling-default-behavior`). A `RemovableMediaDevices`-only policy
does not deny WPD devices; it does not see them at all. That was flagged as a confirmed Red Team
finding in the parent scenario's own review (`reviews.md`, finding 1) and tracked as a follow-up
in this repo's `PROGRESS.md` rather than left silently undocumented.

This fragment closes that specific gap by widening the parent's existing policy object to also
cover the `WpdDevices` family, using the identical default-deny/named-allowlist/audited-both-paths
shape the parent already established — not a new design, an extension of the proven one.

## 2. Design goals

1. **Extend, don't duplicate.** `SecuredDevicesConfiguration` is a single setting on a single
   Intune device configuration object; two competing objects both trying to set it would be a
   genuine deployment conflict, not two independent controls. This fragment PATCHes the parent
   object in place rather than creating a second profile.
2. **Preserve the parent's coverage exactly.** The deploy script never touches the parent's
   `DeviceControlEnabled`, `DefaultEnforcement`, `ApprovedBackupDrives` group, `AllRemovableStorage`
   group, or either `RemovableMediaDevices` rule — only the scope string and the four new WPD
   entries are added or changed. `validate/Test-WpdDeviceControlCoverage.ps1` explicitly checks
   that the parent's original settings survive unmodified.
3. **Mirror the parent's mutually-exclusive rule shape.** One approved-WPD group, one WPD catch-all
   group, one allow rule (included = approved), one deny rule (included = catch-all, excluded =
   approved) — a device matches exactly one WPD rule by construction, identical to the parent's own
   `RemovableMediaDevices` pair.
4. **Both paths audited, not just the deny path** — same principle as the parent (`design.md` §2
   there), extended to WPD.
5. **State the identity-matching gap honestly rather than resolve it by guessing.** The available,
   confirmed group-matching property for WPD-classified hardware is `FriendlyNameId`; whether the
   parent's stronger per-unit properties (`SerialNumberId`/`VID_PID`) also apply to this device
   family is not confirmed by Microsoft's reference documentation either way. This scenario accepts
   both, uses `FriendlyNameId` as the grounded default, and flags the stronger properties as
   unconfirmed rather than asserting they work (or that they don't) — see §6.

## 3. Why widen `SecuredDevicesConfiguration` instead of a second policy

Microsoft's OMA-URI reference for `SecuredDevicesConfiguration` is explicit that it is a
**tenant/device-scope-wide, single-value (pipe-delimited) setting** naming every device family
device control protects on a given assignment target — not a per-policy-object filter
(`device-control-deploy-manage-intune`, "Device types" row). Two Intune Custom device configuration
profiles both targeting the same devices with different `SecuredDevicesConfiguration` values would
be a genuine Intune conflict (a "duplicate setting" scenario Intune profile conflict resolution
does not favor a predictable outcome for), not two independently layered controls. Given that,
widening the parent's existing value to `RemovableMediaDevices|WpdDevices` — the exact pipe-
separated multi-value syntax Microsoft's own reference documents — is the only conflict-free way to
add WPD coverage to devices already assigned the parent policy.

This mirrors this repository's own precedent for "add to, don't duplicate, an existing policy
object" companions — [`dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion`](/scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/) and
[`dlp/pci-teams-exfil-block-part2-obfuscation-mitigation`](/scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/) both add rules to a parent
scenario's existing named policy rather than standing up a second, overlapping one.

## 4. Policy architecture (delta from the parent)

| # | Setting | OMA-URI suffix | Type | Value | Status |
|---|---|---|---|---|---|
| 1–2, 4–7 | (parent's `DeviceControlEnabled`, `DefaultEnforcement`, `ApprovedBackupDrives` group, `AllRemovableStorage` group, and both `RemovableMediaDevices` rules) | — | — | — | **Unchanged** — read from the live object and passed through untouched |
| 3 | Scope | `SecuredDevicesConfiguration` | String | `RemovableMediaDevices` → `RemovableMediaDevices|WpdDevices` | **Changed** |
| 8 | Group: approved WPD devices | `DeviceControl/PolicyGroups/{ApprovedWpdGroupId}/GroupData` | XML | `<Group>` matched by `FriendlyNameId` (confirmed) and optionally `SerialNumberId`/`VID_PID` (unconfirmed for this family — README.md §11) | **New** |
| 9 | Group: all WPD devices (catch-all) | `DeviceControl/PolicyGroups/{AllWpdGroupId}/GroupData` | XML | `<Group>` matched by `PrimaryId = WpdDevices` | **New** |
| 10 | Rule: allow approved WPD devices | `DeviceControl/PolicyRules/{AllowWpdRuleId}/RuleData` | XML | Included = approved WPD group; `Allow` + `AuditAllowed` entries, `AccessMask=63` | **New** |
| 11 | Rule: deny everything else (WPD) | `DeviceControl/PolicyRules/{DenyWpdRuleId}/RuleData` | XML | Included = catch-all WPD group, Excluded = approved WPD group; `Deny` + `AuditDenied` entries, `AccessMask=63` | **New** |

`AccessMask = 63` carries over unchanged from the parent: Microsoft's "Understand mask access
(Windows)" reference states explicitly that the same six access bits (Disk Read/Write/Execute,
File Read/Write/Execute) "are available on `CdRomDevices`, `RemovableMediaDevices`, and
`WpdDevices`" — there is no different access model to design around for this device family
(`device-control-policies#entries`).

## 5. Why this is a companion fragment, not folded into the parent scenario at build time

The parent scenario (already `DONE`, four-lens reviewed, and shipped) explicitly deferred WPD
coverage as a follow-up rather than guessing an unconfirmed device-matching shape mid-build
(`PROGRESS.md`, "Follow-ups discovered while building the Defender for Endpoint device control USB
allowlist scenario"). Building it as a dedicated fragment — rather than re-opening and amending the
already-reviewed parent — follows this repo's own established precedent (the encrypt-mode-audit
companion, the PCI Teams Part 2 obfuscation-mitigation companion): a scoped, independently-reviewed
addition that references the parent rather than duplicating its content.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Deploy surface | Same as parent — Microsoft Graph (`Connect-MgGraph`, app-only certificate), `Invoke-MgGraphRequest` against `v1.0` | Consistency; this fragment PATCHes the same object the parent created. |
| Target object | The parent's existing `windows10CustomConfiguration`, located by `parentPolicyDisplayName` | §3 above — a second object would conflict on `SecuredDevicesConfiguration`, not layer. |
| Update strategy | Whole-object `omaSettings` array rebuild (keep parent's untouched settings + new scope string + 4 new WPD entries), then PATCH | Matches the parent's own update strategy and its documented open VERIFY on PATCH replace-vs-merge semantics (`README.md` §11) — this fragment's PATCH calls carry the identical, not a new, risk. |
| Approved-WPD matching property | `FriendlyNameId` as the grounded default; `SerialNumberId`/`VID_PID` accepted but flagged unconfirmed | §2 goal 5 — Microsoft's reference does not state per-`PrimaryId`-family property support, and no worked example pairs the stronger properties with a `WpdDevices` group. Guessing either way (that they work, or that they're excluded) would violate `AGENTS.md` §4. |
| GUIDs | Four new fixed, source-controlled GUIDs, distinct from the parent's four | Same idempotent-reconcile rationale as the parent (`design.md` §7 there) — every re-run targets the same four new OMA-URI nodes. |
| Rollback granularity | A dedicated `Remove-WpdDeviceControlCoverage.ps1` that reverts only the WPD delta, not the whole policy | The parent's own `Remove-DeviceControlUsbAllowlistPolicy.ps1` (unassign or `-Purge`) remains the tool for removing the entire control; this fragment needs a narrower "turn off just the WPD half" lever, since the two families now share one object. |

## 7. Non-goals

- This scenario does not create a new Intune device configuration object, a new assignment, or
  change the parent policy's assignment scope — it only widens the shared object's `omaSettings`.
- This scenario does not resolve the `SerialNumberId`/`VID_PID`-for-WPD VERIFY (§6) — it is
  deliberately left open per `AGENTS.md` §4 rather than guessed, and is trackable in `PROGRESS.md`
  for a future pilot-tenant confirmation pass.
- This scenario does not cover macOS portable-device control (a separate JSON/`mobileconfig`
  authoring path, `mac-device-control-overview`) — same Windows-only scope boundary as the parent.
- This scenario does not address Bluetooth-connected devices, which Microsoft documents as a
  distinct device control surface again from `WpdDevices` — out of scope here, a candidate for a
  further follow-up fragment.

## 8. References

See `README.md` §12 for the full citation list. Every product fact in this document is grounded
directly against the same Microsoft Learn pages cited there, fetched during this fragment's own
build (not carried over unverified from the parent scenario).
