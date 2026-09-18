---
part: "design"
parent: "dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching"
---
## 1. Problem statement

`scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` matches
approved Apple and Portable devices by `serialNumber` only (that scenario's own `README.md` §11 and
`design.md` §6). `scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/`
already closed the identical gap for the `removable_media_devices` family, resolving the "stable,
deterministic GUID per config-file device entry" blocker its own parent scenario had deferred
(`defender-device-control-usb-allowlist-macos/design.md` §5) with an RFC 4122 §4.3 version-5 UUID
scheme. This fragment closes the same gap a second time, for the Apple and Portable families, by
applying the identical technique, not a new design, a second application of an already-proven one.

**Why now, not when the portable-device-coverage fragment itself was built:** that fragment's own
`design.md` §5 explicitly deferred `vendorId`/`productId` compound matching for Apple/Portable
because the per-device, dynamic-`groupId`-clause-nesting idempotency model was, at that point,
unverified complexity with no concrete implementation to point to. The vendor-product-matching
fragment has since built, shipped, and four-lens-reviewed exactly that model for removable media, 
the blocker this fragment's `PROGRESS.md` follow-up (`### Follow-ups discovered while building the
Defender for Endpoint device control macOS Apple/Portable/Bluetooth coverage scenario`) named as the
condition for revisiting this item is now satisfied.

## 2. Design goals

1. **Extend, don't replace.** `ApprovedAppleDevices`/`ApprovedPortableDevices`'s existing
 `serialNumber`-based clauses stay fully intact; this fragment adds vendorId/productId-matched
 devices as additional OR-branches of the *same* groups, per family, independently.
2. **No new rule, per family.** `Allow-ApprovedAppleDevices`/`Allow-ApprovedPortableDevices` and
 `Deny-AllOtherAppleDevices`/`Deny-AllOtherPortableDevices` all key off their family's Approved
 group's **id**, not its internal clause contents (portable-device-coverage's own
 `design.md`/README table), the identical "extend the group, not the rule" reasoning the
 vendor-product-matching fragment already established (its own `design.md` §2).
3. **Two independent families, one fragment, one config file.** A tenant can configure
 vendorId/productId devices for Apple only, Portable only, both, or neither in one run, mirrors
 how portable-device-coverage itself handles Apple and Portable as two independent, optionally
 populated lists in one script.
4. **A materially narrower prerequisite than the removable-media sibling: the buyer must already
 have at least one `serialNumber`-approved device configured for a family before this fragment can
 add a vendorId/productId device to it** (§3 below), a deliberate scope boundary, not an oversight.
5. **Idempotent and re-runnable per family**, including self-healing drift and clean removal of a
 device no longer in the config file.
6. **Disclose the cross-fragment ordering hazard this fragment inherits (a more severe version of
 the one the Bluetooth sibling fragment already disclosed and detected), rather than silently
 engineer around it by modifying an already-reviewed prerequisite script** (§7 below).

## 3. Why this fragment requires the Approved group to already exist (a deliberate, narrower scope than the removable-media sibling)

The removable-media vendor-product-matching fragment's `ApprovedBackupDrives` group is **mandatory**
, `defender-device-control-usb-allowlist-macos/deploy/New-MacDeviceControlUsbAllowlistPolicy.ps1`
refuses to build a policy at all without at least one `serialNumber` device
(`Get-DeviceControlPolicyJson`: `"approvedDevices must contain at least one entry with a
serialNumber"`), so that group and its Allow rule always exist once the parent scenario is deployed.

`ApprovedAppleDevices`/`ApprovedPortableDevices` are different: portable-device-coverage's own
`Add-MacPortableDeviceCoverage.ps1` creates each group and its Allow rule **conditionally**, only if
`-ConfigPath`'s `approvedAppleDevices`/`approvedPortableDevices` array has at least one entry; with
zero entries, that family gets a bare `Deny-All{Family}Devices` rule (no `excludeGroups`, no Approved
group at all).

This fragment could, in principle, build the missing group + rule from scratch when a family has
zero `serialNumber` devices but the buyer wants a vendorId/productId one, the same shape
portable-device-coverage's own conditional branch already produces. This fragment deliberately does
**not** attempt that:

- It would require this fragment's script to also own creating and, on removal, tearing down an
 `Allow-Approved{Family}Devices` rule and reconciling `Deny-AllOtherOrPortableDevices`'s
 `excludeGroups` in place, object ownership that belongs to portable-device-coverage's own script
 today, not this fragment's.
- It would double this fragment's own state space (four possible starting states per family, group
 absent/present × rule absent/present, instead of the two the current design handles) without a
 concrete buyer requirement to design that expansion against.
- This repository already has a direct precedent for refusing rather than silently building a missing
 prerequisite object: the removable-media vendor-product-matching fragment itself refuses to run if
 `ApprovedBackupDrives` is absent (impossible in practice there, since it's mandatory, but the same
 refusal-not-fabrication principle applies), and the Bluetooth sibling fragment refuses to run if
 `AllBluetoothDevices`/`Deny-AllBluetoothDevices` are absent.

A buyer with zero `serialNumber`-matched devices for a family who wants only a vendorId/productId
exception must first configure at least one `serialNumber` device for that family via
`Add-MacPortableDeviceCoverage.ps1`. Building "create the Approved group and Allow rule from a
zero-serialNumber starting state" is tracked as a follow-up in `PROGRESS.md` rather than attempted
here without a concrete requirement to validate the design against (the same "don't build ahead of a
concrete need" discipline the Bluetooth sibling fragment's own `design.md` §5 already applies to its
own deferred multi-device support).

## 4. Deterministic per-device sub-group id, a second application of an already-proven scheme, with family-scoped hash input

Same RFC 4122 §4.3 version-5 (name-based, SHA-1) UUID technique as the vendor-product-matching
fragment (`design.md` §4 there), copied implementation, **new namespace constant**
(`c7e21a4f9d3b4e6a8c1f2b3d4e5f6071`) unique to this fragment, every fragment in this device-control
family that mints deterministic ids uses its own namespace constant, never a shared or reused one.

The hash input string includes the family (`apple` or `portable`), not just the vendorId+productId
pair: `mac-apple-portable-vendor-product-match/v1/<family>/<vendorId>:<productId>`. This guarantees
an Apple device and a Portable device that happen to share the same vendorId+productId pair (an
edge case Microsoft's documentation neither confirms nor rules out, vendor/product identifiers are
assigned per USB-IF member, not per device-control family) always derive **different** sub-group
ids, so the two families' sub-groups can never collide even in that edge case. This is a strictly
more defensive input than the removable-media sibling needed (a single-family fragment has no
cross-family collision risk to guard against).

## 5. Policy architecture

No new top-level Intune profile, no new `settings` keys, no new rules. Per family, per
`-ConfigPath` device entry, this fragment adds:

| # | Object | Purpose |
|---|---|---|
| 1 | `groups[]` entry, `"AppleVendorProductMatch-<label>"` / `"PortableVendorProductMatch-<label>"` | `$type: "device"`, `id` = deterministic UUIDv5(namespace, `<family>/vendorId:productId`), `query: {"$type":"and","clauses":[{"$type":"primaryId","value":"apple_devices"⎮"portable_devices"},{"$type":"vendorId","value":"<hex>"},{"$type":"productId","value":"<hex>"}]}` |
| 2 | `ApprovedAppleDevices`/`ApprovedPortableDevices` clause edit | One `{"$type":"groupId","value":"<sub-group id>"}` clause appended per configured device, alongside the group's pre-existing `serialNumber` clauses. `query.$type` is read from the live object and reproduced unchanged (this fragment does not assume `or` vs. `any`, see §6). |

Ordering constraint (Microsoft's Clause reference: "The group must be defined within the policy
before the clause"): every sub-group this fragment adds is inserted into the `groups` array
**immediately before** its family's Approved group, leaving every other group's relative position
unchanged.

## 6. Why this fragment never assumes the Approved group's `query.$type` value

Two of this repository's own already-shipped fragments disagree on the literal `$type` string used
for an OR-semantics query: the removable-media parent's `ApprovedBackupDrives` uses `"any"`
(`defender-device-control-usb-allowlist-macos/design.md` §7), while portable-device-coverage's own
`Get-SerialNumberGroup` helper emits `"or"` for `ApprovedAppleDevices`/`ApprovedPortableDevices`.
Microsoft's own Query reference table documents both as valid, synonymous forms ("`any`... `or`: is
equivalent to `any`", re-confirmed by direct fetch of the current "Device Control for macOS" page
during this fragment's own build). Rather than hard-code an assumed value (which would drift from
whichever synonym the prerequisite fragment's script actually wrote), this fragment's deploy and
validate scripts always read `query.'$type'` from the live object and reproduce it unchanged, the
same "never guess a value you can read" discipline already applied elsewhere in this repository
(e.g. the vendor-product-matching fragment reads, rather than assumes, `ApprovedBackupDrives`'
`query.$type`, even though in that case it happens to always be `"any"`).

## 7. The inherited ordering hazard, more severe than the Bluetooth sibling's, disclosed the same way

The Bluetooth allowlist fragment's own `design.md` §8 already documents and accepts a cross-fragment
ordering hazard: `Add-MacPortableDeviceCoverage.ps1` has no awareness of any fragment built on top of
it, and unconditionally rebuilds the objects it owns from its own `-ConfigPath` on every reconcile.
This fragment inherits the identical hazard, in a **more severe form**:

- **Bluetooth's hazard:** a rerun nulls `Deny-AllBluetoothDevices`'s `excludeGroups`, the Bluetooth
 sibling fragment's own group/rule survive untouched; only the cross-reference is dropped.
- **This fragment's hazard:** `Add-MacPortableDeviceCoverage.ps1`'s `Get-SerialNumberGroup` helper
 *fully rebuilds* `ApprovedAppleDevices`/`ApprovedPortableDevices`'s `query.clauses` from that
 script's own `serialNumber` list only (never preserving a `groupId` clause it didn't itself write)
 on every reconcile where that family has ≥1 `serialNumber` device, silently dropping this
 fragment's `groupId` clauses. Worse, if that family's `serialNumber` list is rerun down to **zero**
 entries, `Add-MacPortableDeviceCoverage.ps1` takes its own "else" branch and removes the Approved
 group **and** its Allow rule entirely, orphaning this fragment's sub-groups completely (they
 remain in the policy JSON, referenced by nothing).

Two options were considered, the same two the Bluetooth fragment's own `design.md` §8 already
weighed:

1. **Modify `Add-MacPortableDeviceCoverage.ps1` to be aware of this fragment.** Rejected for the same
 reason the Bluetooth fragment rejected it: it reopens an already-reviewed, finished fragment to add
 coupling to an optional extension built on top of it, out of proportion to this fragment's own
 scope.
2. **Disclose the hazard explicitly and detect it at validation time.** Adopted. This fragment's own
 deploy script always fully reconciles both families' groups on every run (so running it last always
 produces the correct state), and its validate script distinguishes three outcomes per family:
 "never configured" (no Approved group, no owned sub-groups, clean), "correctly reconciled" (every
 check passes), and "drifted because the prerequisite fragment's own reconcile ran afterward and
 the Approved group vanished while this fragment's sub-groups are still present, now orphaned", a
 distinct `[FAIL]` with the exact remediation named, not conflated with "never deployed" (README.md
 §11).

## 8. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Both Apple and Portable families in one fragment | §2, mirrors portable-device-coverage's own "two independent, optionally populated lists in one script" shape; avoids two near-duplicate fragments differing only in a primaryId value string. |
| Prerequisite | Refuse per family if that family's Approved group (and, if devices are configured, its Allow rule) is not already present | §3, this fragment never creates either object from a zero-serialNumber starting state; a deliberate, disclosed scope boundary. |
| Per-device sub-group id | Deterministic RFC 4122 §4.3 UUIDv5(fragment-specific namespace, `<family>/vendorId:productId`) | §4, second application of the vendor-product-matching fragment's own proven scheme, with family folded into the hash input to prevent any cross-family id collision. |
| Approved group's `query.$type` | Read from the live object, reproduced unchanged, never assumed | §6, this repository's own two prerequisite fragments already disagree on the literal synonym used (`any` vs. `or`); this fragment must not silently normalize or assume either. |
| Orphan handling | Detected and removed automatically on every reconcile, no `-Force` required, per family | Same self-heal-without-`-Force` discipline as every sibling fragment. |
| Ordering hazard | Disclosed and detected, not engineered around by modifying the prerequisite fragment's own script | §7, same precedent-following choice the Bluetooth sibling fragment already made, applied to a more severe variant of the same hazard. |
| Update strategy | Whole-payload replacement on every reconcile (PATCH with the freshly rebuilt `.mobileconfig`) | Matches every sibling fragment; same open VERIFY on `payload` PATCH replace-vs-merge semantics inherited from the parent scenario. |

## 9. Non-goals

- This scenario does not create `ApprovedAppleDevices`, `ApprovedPortableDevices`,
 `Allow-ApprovedAppleDevices`, `Allow-ApprovedPortableDevices`, either family's catch-all group, or
 either family's `Deny-AllOtherAppleDevices`/`Deny-AllOtherPortableDevices` rule, all are
 prerequisites owned by `defender-device-control-usb-allowlist-macos-portable-device-coverage`, not
 deployed artifacts of this fragment (§3).
- This scenario does not build the Approved group/Allow rule pair from a zero-`serialNumber`
 starting state for either family (§3), tracked as a follow-up in `PROGRESS.md`.
- This scenario does not extend vendorId/productId matching to the Bluetooth family, that family
 already has its own, single-device vendorId/productId exception
 (`defender-device-control-usb-allowlist-macos-bluetooth-allowlist/`), built on a structurally
 different (no OR'd multi-device sub-groups) model.
- This scenario does not modify `Add-MacPortableDeviceCoverage.ps1` to make it aware of this fragment
 (§7), the ordering hazard is disclosed and detected, not engineered away by coupling the two
 scripts, the same choice the Bluetooth sibling fragment already made for its own analogous hazard.
- This scenario does not deploy via JAMF as a separate build. Because the underlying
 `deviceControl.policy` JSON schema is identical across the Intune and JAMF deployment paths (the
 same reasoning the portable-device-coverage fragment's own `design.md` §8 already establishes), the
 group delta this fragment grounds applies equally to
 `defender-device-control-usb-allowlist-macos-jamf/`'s JAMF-managed sibling.

## References

See `README.md` §12 for the full citation list. The Clause/Query reference facts and the confirmation
that no Microsoft-published sample pairs `vendorId`/`productId` with the `apple_devices` or
`portable_devices` families were both re-verified by direct fetch during this fragment's own build,
not carried over unverified from the vendor-product-matching sibling.
