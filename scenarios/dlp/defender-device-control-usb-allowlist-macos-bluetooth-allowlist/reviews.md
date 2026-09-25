# Four-Lens Review — Defender for Endpoint Device Control (macOS): Bluetooth Approved-Device Allowlist

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items remain open.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The "model, not unit" caveat undersold how easy `vendorId`+`productId` spoofing actually is
   compared to the `serialNumber` spoofing risk this control's other allowlists already accept.**
   The initial draft's §11 framed this identically to the parent scenario's "firmware-level metadata,
   commodity spoofing tooling exists" caveat for `serialNumber`. That understates the gap: a
   `serialNumber` is at least unique per physical unit and typically requires rewriting
   device-controller firmware to forge. `vendorId`/`productId` are, by design, the same for **every**
   unit of a given model — no forgery is even required to get a second, unapproved unit of the same
   phone/scanner model through the allowlist, and Bluetooth advertisement/HCI vendor and product
   identifiers are commonly software-configurable on inexpensive BLE development boards and some
   commodity dongles, making deliberate impersonation of an approved model plausible for a
   moderately capable attacker without any physical device modification.
   - **Resolution:** Rewrote the relevant `README.md` §11 bullet and `design.md` §6 to state this as
     a **materially weaker** allowlist than this control's `serialNumber`-based exceptions
     (removable media, Apple, Portable) — not a variant of the same risk level — and to recommend
     approving only device *models* with a genuine, narrow business need rather than treating
     approval as unit-specific. No stronger Microsoft-documented Bluetooth identifier exists to
     recommend instead; this is disclosed as a hard product limitation, not an implementation gap.
2. **Does the shared deny rule's `excludeGroups` edit risk silently clobbering an exclusion an admin
   added independently (outside this fragment) for an unrelated reason?** The initial draft's deploy
   and remove scripts unconditionally set/cleared `excludeGroups` as a single-element array, with no
   handling for any other pre-existing entry.
   - **Resolution:** Genuine, real defect — not merely a theoretical concern. Both
     `deploy/Add-MacBluetoothDeviceAllowlist.ps1` and `deploy/Remove-MacBluetoothDeviceAllowlist.ps1`
     were rewritten to filter out only this fragment's own group id and preserve every other entry,
     both when adding and when removing this fragment's exception. Fixed before this review round
     closed, not merely flagged.
3. **Is there a way to detect an unauthorized Bluetooth device presenting a spoofed
   `vendorId`/`productId` after the fact, given finding 1 above?** Confirmed as a real, disclosed
   residual gap, not an oversight: every allowed connection generates an `auditAllow` event (§7 of
   `README.md`), so an analyst reviewing `RemovableStoragePolicyTriggered` allow events for unusual
   volume/frequency/device count against one approved model has *a* signal, but no cryptographic
   distinction between the genuine approved unit and an impersonating one exists in this schema.
   - **Resolution:** Already implicitly coverable via the existing Advanced Hunting query pattern; no
     new script needed. Added an explicit Blue Team-lens recommendation instead (below) rather than
     silently leaving this as purely a Red Team disclosure.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The deploy script gave no distinguishing message for "reconciling a partial/drifted state"
   versus "first deployment" versus "explicit `-Force` re-run of an already-correct state"** — all
   three UX paths existed in the logic but only the "already correct, no `-Force`" and "reconciling"
   end-states printed a message; a partial-state auto-heal (e.g. the group exists but the allow rule
   doesn't, from a manual edit) silently proceeded with the same generic `[plan]` output as a clean
   first deploy, unlike the sibling portable-device-coverage fragment's own deploy script, which
   prints a distinct partial-coverage message.
   - **Resolution:** Added an explicit `[coverage] Partial or drifted Bluetooth allowlist state
     detected...` message to `deploy/Add-MacBluetoothDeviceAllowlist.ps1`, naming which of the three
     owned artifacts (group/allow rule/exclude) are and aren't currently present, matching the
     sibling fragment's own established UX pattern.
2. **Recommend an Advanced Hunting triage addition for Red Team finding 3 above** (unauthorized
   device presenting a spoofed `vendorId`/`productId`): a rule of thumb — a spike in
   `Allow-ApprovedBluetoothDevice` `auditAllow` events from more distinct `DeviceName` values than
   the number of physically-issued approved units is the practical detection signal available in
   this schema, since there is no cryptographic per-unit distinction.
   - **Resolution:** Added to `README.md` §8 (Operations & tuning) as a concrete review-cadence
     recommendation, not left only as a Red Team disclosure with no operational counterpart.
3. **Does the ordering-hazard drift check in `validate/Test-MacBluetoothDeviceAllowlist.ps1` actually
   distinguish the two cases it claims to (never-configured vs. drifted-after-sibling-`-Force`)?**
   Traced through the logic: when `approvedDevices.Count -eq 1`, the script checks `$hasExclude`
   first; if false, it checks whether `$approvedGroup`/`$allowRule` still exist to decide which of
   the two `[FAIL]` messages to emit.
   - **Resolution:** Confirmed correct by code inspection — no change needed. This is exactly the
     distinction the drift-detection design goal (`design.md` §8) requires, and it produces the
     specific, actionable remediation message rather than a generic failure in the drift case.

No remaining Fail after resolution. Two real, non-hypothetical defects (the `excludeGroups` clobber
risk flagged jointly with Red Team, and the missing partial-state message) were caught and fixed in
this round, not merely documented.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate — this fragment converts a "block everything or turn
  off the whole family" operational choice into a small, named, audited exception, at zero
  incremental licensing cost (`README.md` §10). The now-strengthened §11 disclosure (Red Team
  finding 1) sets the right expectation: this specific allowlist is weaker than the rest of this
  control's `serialNumber`-based exceptions, and should be sold and deployed accordingly — model-
  scoped approval for a genuine business need, not a promise of per-unit identity assurance.
- **Change-management impact:** low — widens the same shared object a third time, reuses the
  existing assignment and rollout discipline. The one new operational requirement (§8: re-run this
  fragment's deploy script after any Apple/Portable `-Force` reconcile) is a small, documented
  addition to an existing runbook, not a new process.
- **Board-level narrative:** "we added a documented, audited exception process for specific
  approved Bluetooth peripherals, with an explicit, disclosed limitation that this exception type is
  weaker than our other device allowlists and is reviewed accordingly" is a defensible, accurate
  claim — the kind of specific, non-overclaiming narrative this repository's other fragments already
  establish as the bar.
- **Would I fund this?** Yes, for an organization that has already funded and piloted both fragments
  beneath it and has a genuine, named Bluetooth exception need — a small, low-cost increment that
  removes a real operational blocker to running the existing Bluetooth control in enforce mode at
  all, rather than leaving it disabled fleet-wide to avoid one team's support tickets.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Is reproducing Microsoft's own sample's `$type: "and"` query (rather than `"all"`, used
   elsewhere in this control family for single-clause catch-all groups) correct, or an unexplained
   inconsistency?** A reviewer familiar with the sibling fragments (which use `"all"` throughout)
   might read this as an error.
   - **Resolution:** Confirmed both are documented as equivalent ("`all`: ... **and**: is equivalent
     to *all*") and this fragment deliberately mirrors Microsoft's own sample's literal choice of
     `"and"` for the exception group specifically, since that sample is the only directly-confirmed
     worked reference for this exact clause combination. `design.md` §3 states this explicitly as a
     deliberate choice, not an oversight, and `README.md` §6 documents the exact query shape. No
     further change needed.
2. **Is the explicit `allow` entry addition (diverging from Microsoft's own sample, which uses only
   `auditAllow`) actually correct, or does it risk double-restricting a device the sample's own
   author intended to be unrestricted by default?**
   - **Checked and confirmed correct:** re-verified `settings.global.defaultEnforcement = "deny"` is
     the value actually present in this shared policy (set by the parent scenario, confirmed by
     direct grep against `defender-device-control-usb-allowlist-macos/deploy/
     New-MacDeviceControlUsbAllowlistPolicy.ps1`, not assumed) — under that default, omitting the
     explicit `allow` entry would leave the "approved" device silently denied, the opposite of this
     fragment's purpose. `design.md` §4 documents the exact reasoning. No further change needed.
3. **`includeGroups`-is-AND / `excludeGroups`-is-OR semantics claim (used to justify the "exactly one
   device in v1" scope decision) — is this actually documented by Microsoft, or inferred?**
   - **Checked and confirmed correct:** directly quoted from Microsoft's own "Access policy rule"
     reference table during this fragment's grounding pass ("If multiple groups are in the
     `includeGroups`, it's *AND*"; "If multiple groups are in the excludeGroups, it's *OR*") — not an
     inference. Cited verbatim in `design.md` §3 and `README.md` §11/§12. No further change needed.
4. **Access-string list correctness for the new `Allow-ApprovedBluetoothDevice` rule** — does it use
   the same two-item `bluetoothDevice` access set as the existing deny rule, or a different
   (possibly invented) list?
   - **Checked and confirmed correct:** `$script:BluetoothAccess = @('download_files_from_device',
     'send_files_to_device')` in `deploy/Add-MacBluetoothDeviceAllowlist.ps1` is the identical
     two-item list already used by the prerequisite fragment's own `Deny-AllBluetoothDevices` rule
     and confirmed against Microsoft's official Access Types table — no new or invented access
     string. No further change needed.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 strengthened disclosure, 1 real code defect fixed, 1 closed by cross-referencing a Blue Team addition) | Closed |
| 🔵 Blue Team | Fix | 3 (1 real code defect fixed — shared jointly with Red Team's finding 2, 1 new operational recommendation added, 1 confirmed correct by inspection) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 4 (all confirmed correct on inspection, one against a direct re-check of the live parent script's actual `defaultEnforcement` value rather than an assumption) | Closed |

The `excludeGroups` wholesale-replacement defect (Red Team finding 2 / Blue Team finding 1's shared
root cause) was a genuine correctness bug in the initial draft, not merely an unconfirmed VERIFY —
it is fixed in the current state of `deploy/Add-MacBluetoothDeviceAllowlist.ps1` and
`deploy/Remove-MacBluetoothDeviceAllowlist.ps1`, both of which now preserve any pre-existing
`excludeGroups` entry this fragment doesn't own. All other Fix items are resolved in the current
state of `README.md`, `design.md`, and the deploy script. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.

---

## Follow-up round (v2, 2026-09-25): multi-device support

This fragment's original v1 review round (above) confirmed the `includeGroups`-AND/`excludeGroups`-
OR semantics that justified capping v1 at exactly one approved device (finding 3). v2 closes that
deferred `PROGRESS.md` follow-up by porting the per-device sub-group + `groupId`-clause-nesting
technique `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`
independently built and reviewed after v1 shipped (`design.md` §5). A short, targeted re-check round
rather than a full re-derivation, since the ported technique's own correctness was already
established by that sibling's own four-lens review:

- 🔴 **Red Team** — checked whether creating a brand-new `$type: "or"` group from scratch (not just
  extending a pre-existing one) is actually a validated pattern in this object type, or an
  unverified assumption specific to this fragment. **Confirmed, not assumed:** the prerequisite
  `portable-device-coverage` fragment's own `Get-SerialNumberGroup` function
  (`deploy/Add-MacPortableDeviceCoverage.ps1`) creates its `ApprovedAppleDevices`/
  `ApprovedPortableDevices` groups with `'$type' = 'or'` from scratch using the identical mechanism
  — this repo's own working, previously-reviewed code, not a new risk introduced here.
- 🔵 **Blue Team** — checked that `validate/Test-MacBluetoothDeviceAllowlist.ps1`'s per-device checks
  can't produce a false PASS via name-collision between two devices' sub-group names (e.g. one
  label being a string-prefix of another). **Confirmed safe:** the validate script matches each
  device's sub-group by exact `-eq` equality against `"$SubGroupNamePrefix$($d.label)"`, not a
  `-like` wildcard, so partial-label collisions cannot cause a false match.
- 🎩 **CISO** — no new residual risk introduced beyond what v1's own review already accepted
  (`vendorId`/`productId`-is-a-model-not-a-unit, §6) — multi-device support widens the *number* of
  approved models, not the *kind* of risk each one carries.
- 🟦 **Microsoft Product Owner** — confirmed the deterministic sub-group id derivation
  (`Get-DeterministicSubGroupId`) is a byte-for-byte port of the sibling's own implementation
  (verified by diff), not a re-implementation that could silently diverge in its endianness handling
  — the same function, same RFC 4122 v5 algorithm, only the namespace constant and hashed name
  differ (Bluetooth-specific, to avoid id collisions with the sibling's own sub-groups).

No Fix/Fail from this follow-up round. `README.md` §11's "Exactly one approved device" limitation is
now marked RESOLVED rather than removed silently, and `PROGRESS.md`'s corresponding TODO item is
closed with a pointer to this round.
