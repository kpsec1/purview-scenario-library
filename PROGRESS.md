# PROGRESS — build state & backlog

**This file is the single source of truth for what to do next.** Every loop turn: read this
first → pick the top unblocked `TODO` → do exactly one fragment → update this file → commit.

## Backlog policy
- Order: cross-cutting → Data Governance → Data Security → Risk & Compliance.
- **One fragment per turn.** A fragment = one scenario reaching definition-of-done (docs + code +
  four-lens review), or one scoped sub-task below. Split large scenarios into `-part1/-part2/-part3`.
- **Commit before ending the turn.** Nothing is "done" until committed.
- Ground all product facts in Microsoft Learn. Author-only code; never run against a live tenant.
- Definition of done: see `AGENTS.md` §9.

## In progress
- (none)

## TODO (ordered)

### Risk & Compliance
- (none — every module now has a starter scenario; remaining work is the follow-up expansion backlog below)

> After the starter scenario per module lands, expand each module across the AGENTS.md §3 axes
> (lifecycle, deployment posture, regulatory driver, failure/abuse, scale). Add those fragments
> here as they're scoped.

### Follow-ups discovered while building the IRM case-escalation-to-eDiscovery scenario
- [x] Consider a Power Automate flow (or Graph webhook-driven trigger...) that automatically runs
  `Confirm-EdiscoveryEscalationLink.ps1` right after escalation — **grounded and closed, not built**
  (see DONE below): the dedicated grounding pass this item asked for found no automatic/event-driven
  trigger exists. Power Automate's IRM case trigger is manually selected/run from the same dashboard
  toolbar (not fired by the escalation event), none of its five documented connector actions can
  invoke an external script, and the separate Insider Risk Management audit log that does record
  escalations has no documented Graph/REST query API (`Search-UnifiedAuditLog` doesn't cover it
  either). `irm-case-escalation-to-ediscovery/README.md` §8/§11 and `design.md` §4/§5 corrected in
  place; a scheduled poll remains the only unattended option. Re-open this item if Microsoft ever
  ships either a documented event-driven IRM trigger or a Graph/REST endpoint for the IRM audit log.
- [ ] VERIFY (pilot tenant): the exact format of the "Case ID" the Insider Risk Management Cases
  dashboard displays (numeric, GUID, or another scheme) — not documented by Microsoft beyond "The
  ID of the case." `irm-case-escalation-to-ediscovery`'s naming convention and scripts treat it as
  an opaque string throughout; confirming the format could enable format validation instead.
- [ ] VERIFY (pilot tenant): whether the portal's "Escalate for investigation" flow automatically
  adds the flagged user as a custodian with a hold applied, or leaves the new case empty — not
  documented either way by Microsoft. `irm-case-escalation-to-ediscovery/deploy/
  Confirm-EdiscoveryEscalationLink.ps1` doesn't assume an answer (design.md §3 explains why
  unconditional reconciliation is safe regardless), but confirming this would let the scenario's
  docs state the actual portal behavior instead of "unknown."

### Follow-ups discovered while building the eDiscovery Premium legal-hold-and-export scenario
- [x] Ground the exact `RecordType`/`Operations` values for eDiscovery hold-apply/hold-release/
  case-close/case-delete events in `Search-UnifiedAuditLog`, then add a dedicated
  `Export-EdiscoveryAuditTrail.ps1` to `premium-legal-hold-and-export/deploy/` — **built** (see
  DONE below): `RecordType Discovery` with `CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/
  `CaseRemoved` (case lifecycle) and `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` (hold-**policy** lifecycle), both grounded verbatim against
  Microsoft's "Audit log activities" eDiscovery reference. One genuine gap carried forward rather
  than resolved by guessing — see the new VERIFY item immediately below.
- [ ] VERIFY (pilot tenant): whether the `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` operations `Export-EdiscoveryAuditTrail.ps1` queries (confirmed for
  the case-level `ediscoveryHoldPolicy` object) also fire for `premium-legal-hold-and-export`'s own
  custodian-scoped `ediscoveryCustodian: applyHold`/`release` calls — a different object model. One
  Microsoft Learn page claims custodian holds are internally modeled as a "custodian hold policy"
  (suggesting yes); the only page describing a dedicated per-custodian audit search UI, and that
  "custodian hold policy" page itself, both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic eDiscovery experience's August 2025 retirement
  everywhere else — neither is confirmed for the current, non-legacy experience this scenario
  targets. Flagged inline in `deploy/Export-EdiscoveryAuditTrail.ps1`'s `.NOTES`,
  `README.md` §8, and `design.md` §8 rather than resolved by guessing, per `AGENTS.md` §4.
- [x] `scenarios/ediscovery/legal-hold-notifications/` — **investigated, not built** (see DONE
  below): the Premium custodian-communication workflow this item originally scoped was
  **permanently retired by Microsoft on August 31, 2025** and isn't available in the current
  eDiscovery experience — not merely unautomatable. `premium-legal-hold-and-export/README.md` §11
  and `design.md` §7 corrected in place instead of a companion scenario being built on the original
  (now-superseded) assumption.
- [ ] VERIFY (pilot tenant, before production reliance): whether the custodian `userSource`
  `includedSources` property accepts the combined string `"mailbox, site"` (Microsoft's own worked
  *beta*-namespace example) on the current *v1.0* `POST .../custodians/{id}/userSources` endpoint,
  whose own v1.0 worked example shows only a single value (`"mailbox"`) — flagged inline in
  `premium-legal-hold-and-export/README.md` §11 and `deploy/New-EdiscoveryPremiumLegalHold.ps1`'s
  `.NOTES` rather than resolved by guessing a JSON-array shape neither reference confirms.
- [x] Once `scenarios/insider-risk/` has a scenario producing an escalatable Insider Risk
  Management case, wire the documented IRM-case → eDiscovery (Premium) case escalation integration
  — **built** as `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` (see DONE below).

### Follow-ups discovered while building the eDiscovery location-scoped-legal-hold scenario
- [ ] VERIFY (pilot tenant, before pointing this at a distribution list you haven't already
  tested): whether a distribution list's own SMTP address is accepted as a `userSource.email`
  value on the v1.0 `ediscoveryHoldPolicy` endpoint and expanded server-side to member mailboxes.
  Corroborated by Microsoft's beta custodian-context userSource reference ("or the SMTP address of
  the group mailbox") and by the "Distribution group has too many members" (>1,000) error
  reference, but the v1.0, non-beta endpoint this scenario actually calls documents `email` only
  as "SMTP address of the user" — flagged inline in `location-scoped-legal-hold/README.md` §11,
  `design.md` §3, and `deploy/New-EdiscoveryLocationHold.ps1`'s `.NOTES`.
- [ ] VERIFY (pilot tenant): whether the `siteSource` list/create v1.0 response ever exposes a
  stable, directly comparable URL (rather than only `displayName`, the site's title) — if
  Microsoft adds one, replace `location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`'s
  and `validate/Test-EdiscoveryLocationHold.ps1`'s URL-slug-vs-title matching (the disclosed weak
  point in `design.md` §6) with a direct comparison instead.
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` — **built** (see DONE below): script
  resolving a Microsoft Teams/Microsoft 365 Group's own mailbox + SharePoint site
  (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` in Exchange Online PowerShell) into the userSource/
  siteSource pair `location-scoped-legal-hold`'s scripts already accept.
- [x] Reconcile the group-expansion member-cap discrepancy this build surfaced — **investigated and
  re-grounded, not merged into one figure** (see DONE below): both the 100-member and >1,000-member
  pages are current, non-legacy Microsoft Learn articles (the ">1,000" figure is not from an older
  page as originally suspected); Microsoft never states they're the same limit, so both scenarios now
  cite both figures explicitly and treat 100 as the conservative planning threshold, with the
  cross-code-path question kept as an open pilot-tenant VERIFY per `AGENTS.md` §4.
- [x] `scenarios/ediscovery/roster-to-hold-locations/` — **built** (see DONE below): scripts the
  hand-off `teams-group-hold-resolution/design.md` §7 left manual — reads that scenario's
  `-ResolveMembers` roster CSV plus a human-authored `-SelectionPath` decision record, and appends
  the selected members' mailbox addresses as new `userSources[]` entries in a
  `location-hold-definition.json`-shaped file, with an optional `-AddToHold` stage that reconciles
  them directly onto a live hold policy.
- [x] Re-check whether `ediscoveryHoldPolicy: enablePolicy`/`disablePolicy` have been promoted from
  beta to v1.0 — **re-verified, not promoted** (see DONE below). Re-open this item again in a future
  pass if Microsoft ever lists either action under `?view=graph-rest-1.0`.

### Follow-ups discovered while building the DLP template scenario
- [x] `scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/` — **built** (see DONE
  below): a behavioral compensating control (not a full fix — no Microsoft capability performs
  cross-message content reconstruction) for the split-PAN evasion gap flagged in `reviews.md`
  (Red Team) for the Teams template scenario. Wires a dedicated Insider Risk Management "Data
  leaks" policy + the Communication Compliance SIT-in-messages indicator (the *only* documented
  path that extends IRM coverage to Microsoft Teams — Teams DLP alerts are explicitly excluded
  from IRM's own DLP-alerts trigger, confirmed during this build's grounding pass) + Cumulative
  Exfiltration Detection into Adaptive Protection, which drives a new priority-0
  `-SharedByIRMUserRisk` rule added to Part 1's own named DLP policy that hard-blocks all further
  external Teams sharing from an Elevated-risk sender, no override. Explicitly documented residual
  gap: zero detectable signal against a maximally disciplined single-digit-per-message attacker
  who generates no other exfiltration-type activity — see that scenario's `README.md` §11.
- [x] `scenarios/compliance-manager/pci-dss-assessment/` — **built** (see DONE below): Compliance
  Manager PCI DSS v4.0 premium-template assessment scenario referenced from
  `scenarios/dlp/pci-teams-exfil-block/README.md` §2 as the assessment-side companion to this
  technical control (that README updated in place to point at the real path instead of "planned").

### Follow-ups discovered while building the Endpoint DLP USB-block scenario
- [x] `scenarios/dlp/removable-usb-device-groups-allowlist/` (or fold into a future Endpoint DLP
  hardening pass) — script/document the **Removable USB device groups** portal feature
  (`Set-PolicyConfig -DlpRemovableMediaGroups`) to allow specific IT-issued encrypted backup
  drives by device identity, complementing the group-based (user) exception in
  `scenarios/dlp/endpoint-dlp-usb-block/`. Flagged as out of scope there because the per-rule
  PowerShell syntax for referencing an authorization group inside `-EndpointDlpRestrictions`
  is not documented anywhere found during that scenario's build — needs a fresh grounding pass —
  **investigated, not built** (see DONE below): the fresh grounding pass confirmed the portal
  workflow end-to-end (create the device group in Endpoint DLP settings by Vendor ID/Product
  ID/Instance ID, then add it as an exclusion in a rule's actions/exceptions) but found the
  PowerShell layer more thoroughly undocumented than originally scoped — not just the per-rule
  reference syntax, but `Set-PolicyConfig -DlpRemovableMediaGroups`'s own hashtable shape, and the
  same for all four sibling device-group parameters (`-DlpPrinterGroups`/`-DlpNetworkShareGroups`/
  `-DlpAppGroups`/`-DlpExtensionGroups`): every one of their descriptions and the cmdlet's entire
  `EXAMPLES` section are unpublished placeholder text in Microsoft's official reference, and
  `New-DlpComplianceRule`/`Set-DlpComplianceRule` expose no parameter at all for referencing a
  device group as a rule condition/exception. Scripting either half would mean fabricating an
  unconfirmed hashtable shape, which this repo's grounding standard (`AGENTS.md` §4) does not
  permit. `scenarios/dlp/endpoint-dlp-usb-block/README.md` §11/§12 and `design.md` §6–7 updated in
  place with the full finding and new citations, rather than a new scenario folder being built on
  an unscriptable feature. Re-open if Microsoft ever publishes the hashtable shape or adds a
  rule-level device-group parameter.
- [x] Consider a companion `scenarios/dlp/defender-device-control-usb-allowlist/` (Microsoft
  Defender for Endpoint device control, not Purview DLP) — `endpoint-dlp-usb-block/README.md`
  §11 notes Endpoint DLP is content-aware but not device-identity-aware, and a buyer wanting "no
  unapproved USB devices, period" needs device control in addition, not instead — **built** (see
  DONE below): default-deny for `RemovableMediaDevices`, one named `ApprovedBackupDrives`
  allowlist group (matched by `SerialNumberId`/`VID_PID`), both the allow and deny paths audited,
  deployed via Microsoft Graph (`windows10CustomConfiguration` Custom OMA-URI) since no confirmed
  Graph schema exists yet for the native Intune "Device Control profile" template (`design.md`
  §4). Genuine Red-Team finding resolved by documentation, not by scope creep: a device presenting
  as a Windows Portable Device (phones/cameras in MTP mode) is completely invisible to this
  control, tracked as a follow-up below rather than silently left undocumented.
- [x] Verify (against a pilot tenant or an official Microsoft Learn source, not just the Tech
  Community blog cited in `scenarios/dlp/endpoint-dlp-usb-block/README.md` §11) the exact
  `-EndpointDlpRestrictions` `Setting`/`Value` strings this scenario's deploy script uses
  (`RemovableMedia` / `Block` / `Audit`) — **grounded and closed** (see DONE below): both the
  official `New-DlpComplianceRule` and `Set-DlpComplianceRule` Learn reference pages were fetched
  in full this run and confirm the exact shape directly ("The available values for `<Value>` are:
  Audit, Block, Ignore, or Warn," with a worked `RemovableMedia`/`Block` example), superseding the
  Tech Community blog as the primary citation.

### Follow-ups discovered while building the Defender for Endpoint device control USB allowlist scenario
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage/` — extend
  `SecuredDevicesConfiguration` to also cover `WpdDevices` (Windows Portable Devices —
  phones/cameras in MTP/PTP mode), which this scenario's initial build confirmed are **completely
  invisible** to a `RemovableMediaDevices`-scoped policy, not merely unrestricted (a real,
  undetected bypass, flagged as a Red Team finding in `reviews.md` and `README.md` §11) — **built**
  (see DONE below). This build's own grounding pass could **not** confirm this item's original
  premise that "WPD groups only support `FriendlyNameId`/`PrimaryId` matching (no
  `SerialNumberId`/`VID_PID`)" — Microsoft's general Windows-devices property-support table lists
  `SerialNumberId`/`VID_PID` without breaking it down per `PrimaryId` family, and no worked example
  was found either confirming or excluding them for `WpdDevices` specifically. The new scenario
  states this as a genuinely open VERIFY in both directions rather than repeating the stronger,
  unsubstantiated exclusion claim — see its `README.md` §11.
- [x] Add a **Defender for Endpoint + Intune** licensing row/section to `docs/licensing-matrix.md`
  — **built** (see DONE below): new §7, cross-linked from `defender-device-control-usb-allowlist/
  README.md` §3.
- [x] Cross-reference Intune RBAC (**Policy and Profile manager** role, and the
  `DeviceManagementConfiguration.ReadWrite.All` Graph application permission for app-only access)
  into `docs/rbac-model.md`, which currently only documents Purview/Exchange role groups and
  Entra directory roles, not Intune's own RBAC model — **built** (see DONE below): new §9
  (renumbering the old §9 "How scenarios should cite RBAC" to §10), cross-linked from
  `defender-device-control-usb-allowlist/README.md`'s Prerequisites table in place of the
  "not yet cross-referenced" note. The still-open Organization Configuration/Audit Manager
  backport under the Audit retention-policy follow-ups remains a separate, not-yet-built item.
- [ ] VERIFY (pilot tenant, before relying on `-Force` to remove a revoked drive from the
  allowlist): whether `PATCH /deviceManagement/deviceConfigurations/{id}` fully replaces the
  `omaSettings` collection or merges/appends — Microsoft's `Update windows10CustomConfiguration`
  reference documents `omaSettings` as updatable but is silent on replace-vs-merge semantics.
  Flagged inline in `defender-device-control-usb-allowlist/README.md` §11 and the deploy script's
  `.NOTES` rather than assumed.
- [ ] Once Microsoft publishes a confirmed Microsoft Graph resource/schema for the native Intune
  "Device Control profile" template (Endpoint security → Attack Surface Reduction), re-evaluate
  migrating `defender-device-control-usb-allowlist` off the current Custom-OMA-URI/hand-built-XML
  mechanism onto it — deferred in this build because no such schema was found during this
  fragment's grounding pass (`design.md` §4); the current mechanism is fully grounded and stable,
  just lower-level than the newer portal experience.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos/` — the macOS sibling (separate
  JSON/`mobileconfig` authoring path via Intune, `mac-device-control-overview`), explicitly out of
  scope for the Windows-only, XML-OMA-URI-based initial fragment (`design.md` §8) — **built** (see
  DONE below): same default-deny/named-allowlist/both-paths-audited shape, deployed as a
  `macOSCustomConfiguration` Graph v1.0 object (a native, fully-documented type — no OMA-URI-style
  workaround needed on this platform). Matches approved devices by `serialNumber` only (the
  stronger of the Windows sibling's two options); `vendorId`/`productId` compound matching and
  Portable/Apple/Bluetooth device coverage are tracked as follow-ups below, the same honest,
  disclosed-not-hidden scope boundary this repo already uses for the Windows sibling's own WPD gap.
- [ ] Consider a **BitLocker-encryption-state** variant/extension (`DeviceEncryptionStateId` group
  property — "approve any BitLocker-encrypted drive," not just a fixed serial-number list) once
  that capability moves out of Microsoft-labeled Preview — explicitly deferred as a non-goal in
  `design.md` §8.

### Follow-ups discovered while building the Defender for Endpoint device control WPD coverage scenario
- [ ] VERIFY (pilot tenant): whether `SerialNumberId`/`VID_PID` group-matching properties are
  honored for `WpdDevices`-classified hardware, or silently ignored/rejected. Microsoft's "Device
  control policies" reference lists both as supported generic "Windows devices" properties without
  breaking the table down per `PrimaryId` family, and this build found no worked example pairing
  either property with a `WpdDevices`-scoped group. `defender-device-control-usb-allowlist-wpd-
  coverage/deploy/Add-WpdDeviceControlCoverage.ps1` accepts both properties per config entry and
  `validate/Test-WpdDeviceControlCoverage.ps1` checks them as `[WARN]` (not `[PASS]`/`[FAIL]`)
  pending this confirmation — see that scenario's `README.md` §11. Resolving this would let a
  future revision recommend a true per-unit WPD identifier instead of the weaker, user-editable
  `FriendlyNameId` default.
- [ ] Once the item above is resolved and a per-unit WPD identifier is confirmed, revisit
  `defender-device-control-usb-allowlist-wpd-coverage/README.md` §11's Red-Team-flagged
  friendly-name-spoofing risk (a device's advertised name is typically user-editable, so an
  attacker who learns an approved name can rename their own device to match it) — a confirmed
  `SerialNumberId`/`VID_PID` path would let this scenario recommend a materially stronger
  allowlist identifier for at least some WPD hardware, the same way the parent scenario already
  prefers `SerialNumberId` over `VID_PID` for removable media.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` — now that
  `scenarios/dlp/defender-device-control-usb-allowlist-macos/` is built (see DONE below), extend it
  to cover macOS's `portable_devices`/`apple_devices`/`bluetooth_devices` `primaryId` families —
  confirmed completely invisible to that scenario's `removable_media_devices`-scoped policy, the
  direct macOS analog of the Windows WPD gap (flagged as a Red Team finding in that scenario's
  `reviews.md` and `README.md` §11) — **built** (see DONE below): widens the parent's shared
  `.mobileconfig` payload (not a second profile — macOS's `com.microsoft.wdav`-typed policy is one
  document across all four families) with three new `settings.features` enables, three catch-all
  groups, two optional `serialNumber`-matched allowlists (Apple/Portable — confirmed via
  Microsoft's own `audit_all_apple_devices_except_serial_numbers.json` sample for Apple; unconfirmed
  by a direct worked example for Portable, tracked as a VERIFY below), and five deny/allow rule
  pairs. Bluetooth ships default-deny-only in v1 (no allowlist) — Microsoft's own worked sample for
  that family uses a structurally different `vendorId`+`productId` single-device match, not the
  OR'd-`serialNumber` shape used for the other two; a Bluetooth allowlist is a new follow-up below.
  Since the underlying policy JSON schema is identical across the Intune and JAMF macOS deployment
  paths, this build also closes the equivalent JAMF-sibling follow-up tracked immediately below
  without a second build (per that item's own note).
- [ ] Consider a Blue Team-flagged WPD-spoofing incident-response playbook once the `SerialNumberId`/
  `VID_PID`-for-WPD VERIFY above is resolved — deferred in this build (`reviews.md`, Blue Team
  finding 2) because a "cross-check the secondary identifier" runbook step has nothing confirmed to
  cross-check against yet.

### Follow-ups discovered while building the Defender for Endpoint device control macOS Apple/Portable/Bluetooth coverage scenario
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/` — adds a
  `vendorId`+`productId`-matched Bluetooth approved-device exception (single device in v1, matching
  the exact shape Microsoft's own `deny_all_bluetooth_devices_except_samsung.json` sample
  demonstrates, fetched directly during this build), closing the "Bluetooth is always default-deny,
  no exceptions" scope boundary — **built** (see DONE below).
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/GitHub-samples pass): a directly-confirmed
  worked example pairing the `serialNumber` clause with a `portable_devices`-scoped group —
  `defender-device-control-usb-allowlist-macos-portable-device-coverage`'s grounding pass confirmed
  this pattern only for `apple_devices` (via `audit_all_apple_devices_except_serial_numbers.json`);
  Microsoft's Clause reference table is unscoped by device family (a stronger starting position than
  the Windows WPD-coverage sibling's own equivalent VERIFY), but this is not the same as a worked
  example. `validate/Test-MacPortableDeviceCoverage.ps1` checks this as `[WARN]`, not `[PASS]`,
  pending confirmation — see that scenario's `README.md` §11.
- [x] Consider `vendorId`/`productId` compound matching for the Apple and Portable families too (not
  just Bluetooth, above) once the per-device, dynamic-sub-group `groupId`-clause-nesting idempotency
  model is independently verified against a pilot tenant — same deferred complexity already tracked
  under `defender-device-control-usb-allowlist-macos-vendor-product-matching/` for the parent's own
  `removable_media_devices` family; this fragment's two new `serialNumber`-based allowlists carry
  the identical limitation, not a new one — **built** (see DONE below) as
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`:
  the same RFC 4122 §4.3 UUIDv5 deterministic-sub-group technique the removable-media sibling already
  proved, applied independently to both the Apple and Portable families in one fragment (family
  folded into the hash input so the two families' sub-groups can never collide), with no new rule
  needed. Deliberately requires each family's `ApprovedAppleDevices`/`ApprovedPortableDevices` group
  to already have ≥1 `serialNumber` device configured (this fragment never builds that group/its
  Allow rule from a zero-`serialNumber` starting state — a disclosed scope boundary, see the new
  follow-up immediately below) and inherits a more severe version of the Bluetooth sibling's own
  disclosed cross-fragment ordering hazard (`Add-MacPortableDeviceCoverage.ps1 -Force` can silently
  drop or fully orphan this fragment's additions) — disclosed and detected, not silently engineered
  around, the same precedent the Bluetooth fragment already established.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-portable-device-coverage/` —
  tracked above (under the WPD-coverage-scenario follow-ups) — **closed**, see that entry above for
  details.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/` — **built**
  (see DONE below): closes the deferred `vendorId`/`productId` compound-matching gap via the
  per-device sub-group + `groupId`-clause nesting technique `design.md` §5 (parent scenario)
  describes. The "stable, deterministic GUID-per-device scheme" blocker is resolved with an RFC 4122
  §4.3 version-5 (SHA-1, name-based) UUID derived from each device's `vendorId:productId` pair —
  verified during the build against Python's `uuid.uuid5()` reference implementation. No new rule
  needed (extends the parent's existing `ApprovedBackupDrives` group directly); multi-device, unlike
  the Bluetooth sibling's v1 single-device cap.
- [ ] VERIFY (pilot tenant): whether `macOSCustomConfiguration`'s `payload` PATCH fully replaces the
  prior `.mobileconfig` or merges/appends at the plist level — Microsoft's `Update
  macOSCustomConfiguration` reference documents `payload` as updatable but is silent on
  replace-vs-merge semantics, the same open question the Windows sibling's `omaSettings` PATCH
  already carries. Flagged inline in `defender-device-control-usb-allowlist-macos/README.md` §11
  and the deploy script's `.NOTES` rather than assumed.
- [ ] VERIFY (pilot tenant, ideally one already running other Defender for Endpoint on macOS
  configuration): whether a pre-existing, independently-deployed `com.microsoft.wdav` preferences
  profile (e.g. one only configuring cloud-delivered protection settings) conflicts with, silently
  merges with, or is overwritten by `defender-device-control-usb-allowlist-macos`'s own
  same-`PayloadIdentifier` profile — Apple's MDM profile-merge behavior for two profiles sharing a
  `PayloadIdentifier` from different sources is not addressed by Microsoft's device control
  documentation. Flagged as a Red Team finding in that scenario's `reviews.md` and as a VERIFY in
  `README.md` §11 rather than resolved by guessing.
- [ ] Once a Defender for Endpoint device-health or compliance signal exposing a Mac's Full Disk
  Access grant status for `com.microsoft.dlp.daemon` remotely (not just via local `mdatp health`)
  is independently grounded, extend `defender-device-control-usb-allowlist-macos/validate/
  Test-MacDeviceControlUsbAllowlistPolicy.ps1` to check it at scale — flagged as a Blue Team gap in
  that scenario's `reviews.md` (no remote, at-scale check exists today; this build declined to
  fabricate one per `AGENTS.md` §4).
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/` — the JAMF-managed
  deployment path (`mac-device-control-jamf`) for organizations whose Mac fleet is JAMF-managed
  rather than Intune-managed, explicitly out of scope in
  `defender-device-control-usb-allowlist-macos/design.md` §8 (Intune-only, matching the rest of
  this repo's Windows device-control scenario) — **built** (see DONE below): identical policy
  content (same groups/rules/settings JSON, same fixed GUIDs) as the Intune sibling, but a
  materially different deploy shape — `deploy/New-JamfDeviceControlPolicyJson.ps1` generates and
  optionally locally schema-validates (`mdatp device-control policy validate`) the policy JSON,
  since Microsoft's own `mac-device-control-jamf` procedure has no documented API for the JAMF Pro
  "Device Control Policy" custom-schema property — that step (and enabling `DC_in_dlp`) stays a
  precisely-documented manual JAMF-console action in `README.md` §5, not fabricated. `developer.
  jamf.com` was unreachable in this build's network environment, so a JAMF Pro API for this
  specific property type could not be independently ruled in or out — tracked as a fresh VERIFY
  below rather than guessed either way.

### Follow-ups discovered while building the Defender for Endpoint device control macOS USB allowlist (JAMF) scenario
- [ ] VERIFY (`developer.jamf.com`, or a pilot JAMF Pro tenant): whether a documented JAMF Pro
  REST/Classic API request body exists for programmatically setting a Custom-Schema-sourced
  Application & Custom Settings property's value (the mechanism `mac-device-control-jamf` uses for
  the Device Control Policy property) — as opposed to uploading a plain `.plist` file, a different,
  simpler mechanism JAMF also supports for other Defender for Endpoint preferences. `developer.
  jamf.com` was unreachable from this build's network environment, so this could not be checked
  directly. If found, `defender-device-control-usb-allowlist-macos-jamf`'s Steps 2–4 (`README.md`
  §5) could be automated end-to-end instead of staying JAMF-console-only — see that scenario's
  `README.md` §11 and `design.md` §3.
- [ ] Once the item above is resolved and a JAMF Pro API path is confirmed, revisit
  `defender-device-control-usb-allowlist-macos-jamf/reviews.md`'s Red-Team/Blue-Team findings on
  the undetectable-drift risk of a manual JAMF-console-only deployment (no way to confirm the
  pasted JSON matches the intended artifact, or that a JAMF admin hasn't silently altered it) — an
  API-based reconcile-and-verify script would close both findings the same way the Intune sibling's
  own Graph-based script already does.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching/` —
  **built** (see DONE below): the JAMF-managed sibling of
  `defender-device-control-usb-allowlist-macos-vendor-product-matching/` (Intune). Unlike the Intune
  sibling (an incremental Graph PATCH against a live object), this fragment is a **superset
  generator** — JAMF has no documented API to patch, so it reads one combined config
  (`approvedDevices` + `vendorProductDevices`) and regenerates the complete policy JSON, reusing the
  Intune sibling's exact deterministic RFC 4122 §4.3 UUIDv5 scheme and namespace constant so the same
  `vendorId`+`productId` pair yields the identical sub-group id on both deployment paths (one policy
  identity across a hybrid Intune+JAMF fleet). The "unverified-dynamic-GUID-sub-group" blocker this
  item originally cited was resolved when the Intune sibling itself shipped (its own GUID scheme
  independently verified against Python's `uuid.uuid5()` reference implementation, not a pilot-tenant
  dependency) — ported here rather than re-derived.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-portable-device-coverage/` (or
  fold into a future macOS device-control hardening pass) — same Portable-Device/Apple-device/
  Bluetooth-media coverage gap already tracked for the Intune sibling (and for
  `defender-device-control-usb-allowlist-macos-portable-device-coverage` above); applies identically
  here since the underlying policy JSON is shared between both deployment paths — closing it for one
  sibling's policy shape closes it for both — **closed by**
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` (see DONE
  below): that fragment's `design.md` §8 documents explicitly that its policy JSON shape applies
  identically to the JAMF-deployed sibling, so no separate JAMF-specific build was needed.

### Follow-ups discovered while building the Information Protection auto-labeling scenario
- [x] Extend `docs/automation-surface.md` with a fifth automation surface: **SharePoint Online
  Management Shell** (`Connect-SPOService` / `Microsoft.Online.SharePoint.PowerShell`) — **built**
  (see DONE below).
- [x] `scenarios/information-protection/auto-label-confidential-exchange/` — Exchange-location
  companion to `auto-label-confidential-sharepoint` — **built** (see DONE below).
- [x] Content-based Exchange DLP rule (not label-conditioned) that blocks or forces encryption on
  outbound SSN/Credit-Card-Number mail to external recipients, closing the Red-Team-flagged gap in
  `auto-label-confidential-exchange/README.md` §11 — **built** (see DONE below) as
  `scenarios/dlp/exchange-pii-exfil-block/`, not under `information-protection/` as originally
  sketched here: the finished scenario is purely content-based DLP with no dependency on the
  auto-labeling scenario's label (`design.md` §3 explains why), so it belongs alongside this
  library's other DLP scenarios (`pci-teams-exfil-block`, `endpoint-dlp-usb-block`) by module
  taxonomy (`AGENTS.md` §2) rather than under Information Protection. Cross-linked back into
  `auto-label-confidential-exchange/README.md` §11 in place of the "planned" note.
- [ ] VERIFY (pilot tenant): whether a PDF attachment on a message that an Exchange auto-labeling
  policy encrypts (via the applied label) ends up protected as part of the overall encrypted
  message envelope, or left effectively in the clear alongside a protected email body — Microsoft's
  documentation confirms this behavior for unencrypted Office (Word/PowerPoint/Excel) attachments
  specifically but doesn't state the PDF case with the same confidence. Flagged inline in
  `auto-label-confidential-exchange/README.md` §11 rather than resolved by guessing.
- [x] Consider a `scenarios/information-protection/` sub-scenario (or a cross-cutting note) on
  **localizing sensitive information type selection by data-residency/jurisdiction** — flagged as
  a Red Team/CISO finding in `auto-label-confidential-sharepoint/reviews.md`: the SSN + Credit
  Card Number starter set is U.S.-centric and should not be presented as GDPR-complete personal-
  data coverage for an EU/UK-only tenant without swapping in the relevant regional SITs. — **built**
  (see DONE below) as `scenarios/information-protection/auto-label-eu-personal-data-sharepoint/`:
  the direct EU/UK sibling, defaulting to Microsoft's built-in EU-wide bundle SITs (EU national
  identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number)
  with a `-SensitiveInfoTypeName` parameter for narrowing to specific member states — the actual
  scripted localization mechanism this item asked for, not just README prose. Cross-linked back
  into `auto-label-confidential-sharepoint/README.md` §2.

### Follow-ups discovered while building the EU/UK personal data auto-labeling scenario
- [ ] VERIFY (pilot tenant, before production reliance): the exact, byte-precise capitalization of
  the three default SIT names (`EU national identification number`, `EU Social Security Number
  (SSN) or Equivalent ID`, `EU debit card number`) as required by `Get-DlpSensitiveInformationType`/
  the portal SIT picker — Microsoft's own Learn pages render the same SIT with inconsistent casing
  across pages, and this build found no single byte-exact authoritative source. Mitigated at
  runtime (the deploy script resolves every name against the tenant's live SIT catalog and fails
  clearly on a mismatch rather than silently deploying a zero-match rule) but not resolved with
  certainty — see `auto-label-eu-personal-data-sharepoint/design.md` §4 and `README.md` §11.
- [ ] VERIFY (pilot tenant): `Get-AutoSensitivityLabelRule`'s read-back property casing for
  `ContentContainsSensitiveInformation` (`name` vs. `Name`) — the documented *write* shape uses
  lowercase `name`/`mincount` (confirmed against `New-DlpComplianceRule`'s own reference examples),
  but no worked example found during this build's grounding pass shows the corresponding `Get-*`
  read-back shape. `auto-label-eu-personal-data-sharepoint/validate/
  Test-EuPersonalDataAutoLabelPolicy.ps1` checks both defensively rather than assuming one.
- [x] `scenarios/information-protection/auto-label-eu-personal-data-exchange/` — the Exchange
  (email) companion to this SharePoint/OneDrive scenario, the same location-split pattern already
  used for the U.S.-SIT sibling (`auto-label-confidential-sharepoint/` → `auto-label-confidential-
  exchange/`) — **built** (see DONE below): combines the Exchange location/exclusion/encryption
  mechanics from `auto-label-confidential-exchange` with the EU/UK SIT set and
  `-SensitiveInfoTypeName` localization mechanism from this scenario, unchanged from both sources.
  Four-lens review surfaced two findings specific to the three-scenario combination not visible
  from either sibling alone: independent SIT-list localization drift between this scenario and the
  new Exchange sibling (no shared config store ties the two scripts together), and a policy-name
  disambiguation risk across the now four sibling-family auto-labeling policies during incident
  response — both resolved with README additions (a standing review-cadence check and a
  disambiguation table), not new code. Cross-linked back into this scenario's own `README.md` §11
  and `design.md` §8.
- [x] Consider a per-country checksum-strength reference table (which EU national ID bundle members
  are checksum-validated vs. pattern-only) as either a cross-cutting doc addition or an expanded
  `README.md` §11 table — flagged as a Red Team finding (`auto-label-eu-personal-data-sharepoint/
  reviews.md`) but only individual examples (France CNI: no checksum; Belgium National Number: yes)
  were grounded in this build, not a full 26-country table. — **built** (see DONE below): all 26
  members of the "EU national identification number" bundle fetched individually from their own
  Microsoft Learn entity-definition pages and tabled in `auto-label-eu-personal-data-sharepoint/
  design.md` §4 — 19 are checksum-validated, 7 are pattern-only (Austria, Croatia, Cyprus, France,
  Greece, Malta, U.K.), with Germany flagged as checksum-validated on its post-2010 format only.
  `README.md` §8/§11 in both the SharePoint/OneDrive and Exchange EU-personal-data siblings updated
  from vague "several others" prose to the exact counts, cross-linking the new table instead of
  duplicating it.
- [x] Consider adding `EU passport number` and `EU driver's license number` as an opt-in bundle
  (not a new default) for a buyer whose SharePoint/OneDrive estate is travel-document- or
  HR-record-heavy — **built** (see DONE below): `-IncludeTravelDocumentSits` switch added to
  `auto-label-eu-personal-data-sharepoint/deploy/New-EuPersonalDataAutoLabelPolicy.ps1` and its
  validate script, appending both SITs to whatever `-SensitiveInfoTypeName` set is already in
  effect. A dedicated grounding pass (fetching both bundles' own Microsoft Learn index pages
  directly) surfaced a real gotcha not previously documented anywhere in this repo: the "EU
  passport number" bundle has no standalone U.K. entity — U.K. coverage is merged into a single
  combined "U.S./U.K. passport number" entity, so this switch also enables U.S. passport detection
  as an inseparable side effect. The three EU-wide bundles this scenario can reference also don't
  share identical member-state coverage (26/26/28 entities respectively, different countries
  missing from each) — full membership tables added to `design.md` §4, cross-referenced from
  `README.md` §6/§11, with a new `reviews.md` round 2 four-lens review specific to this change.

### Follow-ups discovered while building the opt-in travel-document bundle switch
- [ ] VERIFY (pilot tenant): whether `"EU driver's license number"` (the spelling used in this
  repo's prose since the scenario's original build) or `"EU drivers license number"` (the literal,
  no-apostrophe title on the SIT's own Microsoft Learn bundle-index page, fetched directly during
  this round) is the byte-exact name `Get-DlpSensitiveInformationType`/the portal SIT picker
  actually require — joins the existing open SIT-name-casing VERIFY for this scenario
  (`README.md` §11) rather than a new, separate uncertainty. The deploy script's existing
  `Resolve-SensitiveInfoTypeNames` name-resolution check already fails clearly (listing
  near-matches) if the hardcoded default is wrong, rather than silently deploying a zero-match
  rule, so this doesn't block use — it would only let a future revision state the default with
  certainty.

### Follow-ups discovered while building the Exchange PII exfiltration block (DLP) scenario
- [ ] VERIFY (pilot tenant): the exact `Name` value `Get-RMSTemplate` returns for the auto-created
  **Encrypt-Only** RMS template in a real tenant — Microsoft's documentation confirms the template
  exists automatically once Message Encryption is active but never publishes a canonical, byte-
  exact string. `exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1` checks for it at
  runtime rather than assuming (fails clearly, listing available templates, if no match), but a
  first Encrypt-mode deploy in a new tenant should confirm the default `-EncryptTemplateName
  'Encrypt-Only'` actually matches before scripting around it unattended. Flagged inline in
  `README.md` §11 and the deploy script's `.NOTES`.
- [ ] VERIFY (pilot tenant, before production reliance): run the full functional test suite in
  `exchange-pii-exfil-block/README.md` §7 to confirm `-AccessScope NotInOrganization` combined with
  `BlockAccess`/`EncryptRMSTemplate` behaves as designed for the SSN/Credit Card Number SIT pair —
  every individual parameter is grounded from official Microsoft Learn references, but no worked
  example combines them for this exact case, the same class of gap already flagged (and still open)
  for `pci-teams-exfil-block`'s own `BlockAccess`/Teams combination.
- [x] `scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/` — **built** (see DONE
  below): a single additive, low-severity, non-blocking `PII-Exchange-Audit-Encrypt-Exception` rule
  added to the parent scenario's existing policy, scoped to `FromMemberOf` the same
  `-ExceptionGroupEmail` group + `AccessScope NotInOrganization` + the same SIT pair, closing the
  visibility (not prevention) gap in `exchange-pii-exfil-block/README.md` §11. Four-lens review
  (Blue Team) flagged the initial hardcoded `Low` severity as a under-triage risk for a
  high-risk exception group; resolved by adding a `-ReportSeverityLevel` deploy parameter
  (`Low`/`Medium`/`High`) threaded through to both the deploy and validate scripts.
- [x] Once `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/`'s pattern is extended to
  new content-pattern-based DLP scenarios (already tracked as a follow-up under the PCI Teams Part
  2 section above), consider adding the same risk-based `-SharedByIRMUserRisk` compensating-control
  rule to `exchange-pii-exfil-block`'s own named policy — the same split-content/behavioral blind
  spot `pci-teams-exfil-block-part2-obfuscation-mitigation` addresses for Teams applies equally to
  Exchange (SSN/PAN fragments split across separate emails to the same or different recipients) —
  **built** as `scenarios/dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation/` (see DONE
  below).

### Follow-ups discovered while building the Insider Risk Management departing-employee scenario
- [x] Consider scripting the HR-connector Entra app registration itself (Microsoft Graph
  `New-MgApplication`/`New-MgServicePrincipal`/app-password creation) instead of leaving it a
  manual portal prerequisite (`scenarios/insider-risk/departing-employee-data-theft/README.md`
  §5 step 2) — **built** (see DONE below): a follow-up grounding pass found that no
  HR-connector-*specific* cmdlet was ever needed — Microsoft's own guide names only the generic
  app-registration quickstart, because Step 2's requirement is a plain, permission-free app
  registration. `deploy/Register-HrConnectorApp.ps1` (idempotent, `-WhatIf`-capable,
  `-RotateSecret` for the ~90-day rotation cadence) and
  `validate/Test-HrConnectorAppRegistration.ps1` (checks existence, service principal, unexpired
  secret, and — the load-bearing hygiene check — that no Graph API permission has been granted)
  ship this without inventing anything; `docs/rbac-model.md` §11 (new) documents the
  Entra-role/Graph-scope prerequisite for running it, and reviews.md carries an addendum
  four-lens pass on the new capability.

### Follow-ups discovered while building the HR-connector app-registration automation
- [x] Consider a `-RemoveExpired` (or standalone `Remove-HrConnectorAppSecret.ps1`) option that
  calls `Remove-MgApplicationPassword` to delete a superseded secret by `KeyId` after
  `Register-HrConnectorApp.ps1 -RotateSecret` adds a new one, rather than leaving cleanup as a
  fully manual step (`README.md` §11) — **built** (see DONE below) as the standalone
  `deploy/Remove-HrConnectorAppSecret.ps1`, with a default `-RemoveExpired` mode (deletes only
  already-dead credentials, so it can never reduce the app's working-secret count) and a
  narrower `-KeyId`/`-Force` mode for force-retiring a still-valid secret. `Remove-
  MgApplicationPassword`'s exact parameter set was freshly re-verified this session against its
  own Microsoft Learn reference page rather than assumed by symmetry with
  `Add-MgApplicationPassword` — including the non-obvious detail that its `-KeyId` parameter's
  documented type is `System.String`, not `System.Guid`, despite the underlying Graph resource
  property's Edm type being `Guid`; this script's own `-KeyId` parameter matches that (typed
  `[string]` with a GUID-format `ValidatePattern`, not `[guid]`).
- [x] `scenarios/insider-risk/security-policy-violations-by-departing-users/` — the related but
  distinct IRM template requiring Microsoft Defender for Endpoint integration, explicitly called
  out as a non-goal in `departing-employee-data-theft/design.md` §7 — **built** (see DONE below):
  reuses (does not duplicate) the sibling scenario's HR connector/`Send-HrTerminationRecord.ps1`,
  documents the two new portal-only prerequisites (Defender for Endpoint's "Share endpoint alerts
  with Microsoft Compliance Center" advanced feature; Intelligent detections' alert-triage-status
  selection), and ships `deploy/Export-SecurityViolationInsiderRiskAlerts.ps1` — a new,
  scenario-specific capability (not a copy of the sibling's export script) that best-effort-joins
  the resulting IRM alert to its correlated Defender for Endpoint alert by `IncidentId`. Both the
  overall template family and its Defender for Endpoint indicator category are Microsoft-labeled
  **preview** — flagged prominently, not just once, per the four-lens review's CISO finding.
- [ ] VERIFY (pilot tenant, before any customer relies on the daily-schedule pattern in
  `departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`): whether re-uploading an
  unchanged resignation CSV on a subsequent scheduled run is a safe no-op or creates a duplicate
  signal — undocumented by Microsoft as of this build (flagged inline in the script's `.NOTES`
  and `README.md` §11).

### Follow-ups discovered while building the Security Policy Violations by Departing Users scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether this template's specific
  Defender for Endpoint indicators (malware/harmful-app install, security-control bypass) require
  Defender for Endpoint **Plan 2**'s EDR sensor, or whether Plan 1's next-gen antivirus/tamper-
  protection alerting already satisfies them — Microsoft's own prerequisite table for this
  template names only "an active Defender for Endpoint subscription" with no plan qualifier, and
  no page found during this build resolves it either way. `README.md` §3.
- [ ] VERIFY (pilot tenant): whether a Defender for Endpoint alert and the Insider Risk
  Management alert it triggers under this template actually share one `incidentId` — the core
  assumption behind `deploy/Export-SecurityViolationInsiderRiskAlerts.ps1`'s join. Microsoft
  documents general cross-product alert correlation into a shared incident and separately
  documents that IRM alert data reaches the same unified alert queue, but no worked example
  confirming this specific pairing was found. The script degrades gracefully (exports the IRM
  alert with an empty `RelatedDefenderAlerts` array) when the join doesn't fire, so this doesn't
  block production use — it would only let a future revision state the join's reliability with
  confidence instead of "best effort." `README.md` §11; `design.md` §2 goal 5/§5.
- [x] Cross-reference a Microsoft Defender for Endpoint role capable of managing advanced features
  (e.g., **Security Administrator**) into `docs/rbac-model.md` — that doc currently covers Purview,
  Entra directory, and Intune RBAC (§9) but not the Defender for Endpoint role needed for this
  scenario's §5 Step 2 (enabling "Share endpoint alerts with Microsoft Compliance Center").
  `security-policy-violations-by-departing-users/README.md` §3 notes this gap inline rather than
  guessing at a role name beyond the one Microsoft's own advanced-features documentation implies —
  **built** (see DONE below): new §12 covers basic permissions (Security Administrator/Security
  Reader), the legacy granular **Manage security settings in Security Center** permission, and its
  Defender-unified-RBAC (URBAC) equivalent **Core security settings (Manage)**.
- [x] `scenarios/insider-risk/security-policy-violations/` (the base template) — **built** (see
  DONE below): the base "Security policy violations" template's own triggering event *is* the
  Defender for Endpoint security alert (no HR/departure trigger, no priority-user-group
  requirement, confirmed directly against Microsoft's policy-templates reference during this
  build). Correction to this item's own original framing: "scores every onboarded user
  continuously" is not achievable at enterprise scale — Microsoft caps this specific template at
  **1,000** actively-scored users tenant-wide (identical to the priority-users sibling's own cap,
  smaller than departing-users' 15,000 and risky-users' 7,500), so the scenario ships a new,
  genuinely scenario-specific `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` (resolves a
  chosen Entra group's transitive user membership via `Get-MgGroupTransitiveMemberAsUser`, dedupes,
  filters to enabled accounts, checks against the cap) rather than defaulting to an "all users"
  scope. Reuses the departing-users sibling's `Export-SecurityViolationInsiderRiskAlerts.ps1`
  unmodified (that script has no policy-specific filter, so shipping a copy would be pure
  duplication). Four-lens review surfaced and resolved one real gap: whether an IRM policy's scope
  tracks a directly-added group's live membership isn't documented by Microsoft either way, so a
  newly added privileged-group member could sit unmonitored under a calendar-only review cadence —
  `README.md` §8 now ties re-scoping to the group-membership-change event itself, with a quarterly
  review as a backstop, not the primary mechanism. `design.md` §3/§6 for the full grounding.
  `…-by-priority-users/` and `…-by-risky-users/` remain open follow-ups below — each has its own
  materially different trigger/scoping model and wasn't bundled into this fragment per
  `AGENTS.md` §6's one-fragment-per-turn discipline.
- [ ] `scenarios/insider-risk/security-policy-violations-by-priority-users/` — the priority-users
  variant of this template family: triggering event is "Defense evasion of security controls or
  unwanted software detected by Microsoft Defender for Endpoint" (same as the base template just
  built) but additionally requires a formal **priority user group** (Insider Risk Management
  settings → Priority user groups, up to 10,000 members per group) assigned to the policy. Same
  1,000-user template-wide cap as the base template — confirm during that build whether the
  priority-user-group's own 10,000-member ceiling and this template's 1,000-actively-scored ceiling
  interact in a way worth documenting (e.g., does Microsoft warn if the group exceeds the
  template's scoring cap). `insider-risk-management-policy-templates#security-policy-violations-by-priority-users`.
- [ ] `scenarios/insider-risk/security-policy-violations-by-risky-users/` — the risky-users variant:
  triggering events are HR performance-indicator signals (performance improvement / poor review /
  job-level change, via the HR connector — reusable from `departing-employee-data-theft` per this
  library's established reuse pattern) and/or Communication Compliance risk-signal integration,
  **plus** an active Defender for Endpoint subscription (a three-way AND/OR prerequisite shape none
  of this template family's other three members have). 7,500-user template-wide cap.
  `insider-risk-management-policy-templates#security-policy-violations-by-risky-users`.
- [ ] VERIFY (pilot tenant): whether adding an Entra security group directly to an Insider Risk
  Management policy's "Users and groups" scope keeps the in-scope population in sync with the
  group's future membership changes, or captures membership as a snapshot at add-time — not stated
  either way by Microsoft's own policy-configuration documentation. Surfaced while building
  `scenarios/insider-risk/security-policy-violations/` (the base template) but is a general IRM
  policy-scoping question, not specific to that one scenario — flagged inline in that scenario's
  `README.md` §5 Step 4 and §11, and in `design.md` §6, rather than assumed either way. Resolving
  this would let every Insider Risk Management scenario in this library that scopes a policy by
  group (not just this one) state its re-scoping cadence guidance with more precision.

### Follow-ups discovered while building the Adaptive Protection dynamic-risk-DLP scenario
- [ ] `scenarios/dlp/endpoint-dlp-usb-block-adaptive-protection/` (or fold into a future Endpoint
  DLP hardening pass) — script the **Devices** half of Adaptive Protection (risk-based
  clipboard/USB/print/network-share/restricted-app restrictions via `-SharedByIRMUserRisk` +
  `-EndpointDlpRestrictions`), deferred from `dynamic-risk-dlp-enforcement` because
  `-EndpointDlpRestrictions`'s exact `Setting`/`Value` strings already carry an open VERIFY from
  `scenarios/dlp/endpoint-dlp-usb-block/` — needs that VERIFY closed first (ideally via a pilot
  tenant) rather than compounding a second unverified use of the same parameter. Also requires
  either Advanced classification scanning and protection enabled, or an explicit File Type
  condition, per Microsoft's documented Devices-policy prerequisite.
- [x] `scenarios/adaptive-protection/conditional-access-insider-risk-block/` — script/document
  the Conditional Access "Insider risk" condition integration (Microsoft Entra admin center,
  requires **Microsoft Entra ID P2**), deferred from `dynamic-risk-dlp-enforcement` because it's
  a different admin surface (Entra, not Purview/EXO) with its own license prerequisite this
  scenario's DLP-only design doesn't otherwise require. Still a Microsoft-labeled **preview**
  integration as of this build — re-check GA status before scoping. — **built** (see DONE below):
  the GA re-check this item asked for found the integration is **no longer preview** — corrects
  the stale claim, see the new DONE entry and `design.md` §8 in the built scenario.
- [ ] Consider a cross-cutting or Data Lifecycle Management-module scenario covering the
  120-day deleted-content preservation policy Adaptive Protection can auto-create for
  Elevated-risk users — deferred from `dynamic-risk-dlp-enforcement` as a separate opt-in with
  its own retention-policy implications, better scoped alongside this library's future Data
  Lifecycle Management module scenarios (still TODO below) than bundled into the DLP scenario.
- VERIFY (pilot tenant, before a customer relies on it in production): whether representing the
  portal's compound "Content is shared from Microsoft 365 with people outside my organization"
  condition using `-AccessScope NotInOrganization` alone (this scenario's and
  `pci-teams-exfil-block`'s shared pattern) is a byte-for-byte match to the portal-rendered rule,
  or whether a separate `-ContentIsShared` boolean condition is also required — flagged inline in
  `dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1`'s `.NOTES` and
  `README.md` §11.

### Follow-ups discovered while building the Conditional Access insider-risk-block scenario
- [ ] Backport the GA-status correction (`conditional-access-insider-risk-block/design.md` §8)
  into `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/design.md` §7 and `README.md`
  §11 — both currently state the Conditional Access integration is "still labeled preview," which
  this build's fresh grounding pass found is no longer accurate (no preview label on Microsoft's
  current "Block access for users with elevated insider risk" guide or the Graph v1.0
  `conditionalAccessConditionSet.insiderRiskLevels` resource property). Small, doc-only backport
  scoped to a single follow-up fragment per `AGENTS.md` §6 — deliberately not done inside this
  build to avoid reopening an already-reviewed sibling scenario's files for an unrelated fragment.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn licensing-enforcement pass): what actually
  happens at sign-in for a user in a Conditional Access policy's scope who lacks the required
  Entra ID P2 license for the Insider Risk condition specifically — silently exempted, blocked
  outright, or another behavior. Flagged inline as VERIFY in `docs/licensing-matrix.md` §8 and
  `conditional-access-insider-risk-block/README.md` §11 rather than assumed.
- [ ] Script Graph's `conditions.users.excludeGuestsOrExternalUsers` nested condition (the
  "exclude B2B direct connect / service providers / other external" categories Microsoft's own
  documented procedure also recommends) once its exact shape is confirmed against a worked
  example — deferred in this build's v1 script, which only scripts `excludeUsers`/`excludeGroups`.
  See `conditional-access-insider-risk-block/design.md` §7 and `README.md` §11.
- [ ] VERIFY (pilot tenant): Microsoft Quick Setup's exact auto-generated Conditional Access
  policy display name, so `conditional-access-insider-risk-block`'s own `(Custom)`-suffixed name
  can be independently confirmed not to collide, the same confirmation the DLP sibling scenario
  already has for its own Quick-Setup-generated DLP policy name. Not confirmed during this build
  — see `README.md` §11.
- [ ] Consider a second Conditional Access policy variant applying a softer grant control (e.g.
  require MFA / require compliant device, rather than block) scoped to Moderate/Minor risk levels
  — the Conditional-Access-side analog of the DLP sibling's own Elevated-block/Moderate-Minor-
  audit split, which this scenario's single-policy v1 does not replicate (Conditional Access grant
  controls apply per-policy, not per-condition-value — see `design.md` §6).
- [ ] Consider scripting a companion "block legacy authentication" Conditional Access policy (or
  documenting/verifying one already exists) as a prerequisite hardening step for this scenario —
  flagged as a Red Team finding in `conditional-access-insider-risk-block/reviews.md` (legacy auth
  clients may not fully honor the Insider Risk condition) but not built in this fragment, since it
  is a general Conditional Access hardening practice outside this scenario's specific scope.

### Follow-ups discovered while building the Data Map Azure SQL scan-and-classify scenario
- [ ] VERIFY (pilot tenant or the Purview OpenAPI spec, before production use): the exact REST
  request body shapes for the **Data Sources - Create Or Update**, **Triggers - Create Or
  Replace**, and **Scan Result - Run Scan** operations used by
  `scenarios/data-map/scan-azure-sql-and-classify/deploy/New-AzureSqlDataMapScan.ps1`. Their
  canonical Microsoft Learn REST reference pages returned fetch errors in this build environment;
  the shapes used are reconstructed from the confirmed sibling **Scans - Create Or Replace**
  endpoint (direct-fetched, API version `2023-09-01`), the official
  `@azure-rest/purview-scanning` JS SDK type definitions, and the `Az.Purview` PowerShell module's
  parameter signatures — three converging but indirect sources. Flagged inline in that scenario's
  `README.md` §11 and the deploy script's `.NOTES`.
- [x] `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/` — script a **custom, PII-only
  scan rule set** (excluding all system classifications except U.S. Social Security Number and
  Credit Card Number by default) — **built** (see DONE below): the "Scan Rulesets - Create Or
  Replace"/"- Get" REST reference pages were direct-fetched in full this build, closing the VERIFY
  this item was waiting on (the exclusion list itself is derived live from the tenant's Types API
  rather than a hard-coded snapshot — the `data-map-classification-supported-list` page turned out
  to list classifications by name only, with no exact `MICROSOFT.*` identifiers anywhere on it).
- [ ] Consider scripting **credential-object creation** (Key Vault-backed, for the
  `AzureSqlDatabaseCredential` scan kind — SQL authentication or service principal) once a
  documented REST endpoint for it is found; deferred from `scan-azure-sql-and-classify` because no
  such endpoint was located during that build (Microsoft's own docs show credential creation only
  via the portal UI). Needed for any buyer whose target SQL Server can't use SAMI (e.g. reachable
  only via a self-hosted integration runtime, which doesn't support managed-identity auth).
- [x] Sibling Data Map scan scenarios for **Azure SQL Managed Instance**, **Azure Synapse
  Analytics** (dedicated + serverless SQL pools), and **on-premises SQL Server** (via self-hosted
  IR) — each has its own registration/authentication nuances Microsoft documents separately;
  explicitly called out as a non-goal in `scan-azure-sql-and-classify/design.md` §7 — **all three
  built** (see DONE below): `scenarios/data-map/scan-azure-sql-managed-instance-and-classify/`,
  `scenarios/data-map/scan-azure-synapse-and-classify/`, `scenarios/data-map/
  scan-on-premises-sql-server-and-classify/`. This item was left unchecked when those three
  fragments landed; corrected during the `docs/automation-surface.md` §4 Unified Catalog/Data Map
  lineage routing-table fragment's PROGRESS.md pass.
- [ ] `scenarios/data-map/scan-azure-sql-and-classify/` also assumes downstream scenarios will
  consume its classification output — once `scenarios/data-estate-insights/
  classification-coverage-report/` (already TODO below) is built, cross-link it back into this
  scenario's §8 "Downstream use" note.

### Follow-ups discovered while building the DSPM for AI Copilot sensitive-data-exposure scenario
- [ ] VERIFY (pilot tenant): whether a `{"Type":"Group","Identity":"..."}` `Inclusions` entry in
  the Copilot-location `-Locations` JSON works for `New-DlpCompliancePolicy`/`New-DlpComplianceRule`
  the same way a group inclusion is documented for the *collection*-policy cmdlets
  (`New-/Set-FeatureConfiguration`) — needed before this repo can promise a group-scoped pilot
  rollout of `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` instead of tenant-wide
  `TestWithNotifications` simulation as the only pre-enforcement pilot mechanism. Flagged inline in
  that scenario's `README.md` §11 and `reviews.md` (Red Team).
- [ ] `scenarios/dspm-for-ai/copilot-prompt-full-block/` (or fold into a future DSPM-for-AI pass) —
  script the "Prevent Copilot from processing content > Processing prompts" action (full response
  block on a sensitive-information-type match in the prompt itself), deferred from
  `copilot-sensitive-data-exposure` because it is a preview feature with no published Microsoft
  PowerShell worked example as of this build (only the label-exclusion and web-grounding-
  restriction actions have one) — needs a fresh grounding pass once Microsoft publishes an example
  or the feature reaches GA.
- [ ] `scenarios/dspm-for-ai/third-party-ai-site-adaptive-block/` — the Adaptive-Protection-driven,
  risk-based DLP policies for **third-party** generative AI sites accessed via a browser
  (`DSPM for AI - Block sensitive info from AI sites`, `DSPM for AI - Block elevated risk users
  from submitting prompts to AI apps in Microsoft Edge`), explicitly called out as a non-goal in
  `copilot-sensitive-data-exposure/design.md` §7 — a different policy location/enforcement plane
  from the first-party Microsoft 365 Copilot location that scenario covers, and a natural extension
  of `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/`'s existing pattern.
- [ ] Consider updating `docs/licensing-matrix.md` to add the DLP-for-Copilot licensing-tier split
  (label-exclusion rule requires E5-tier; prompt-safeguard/web-grounding rule is available at all
  Copilot licensing tiers) as its own row/footnote — currently only cited inline in
  `copilot-sensitive-data-exposure/README.md` §3, not surfaced in the cross-cutting matrix.

### Follow-ups discovered while building the Unified Catalog business-glossary scenario
- [x] `scenarios/unified-catalog/link-glossary-terms-to-data-products/` — **superseded by**
  `scenarios/unified-catalog/manage-data-products/` (see DONE below), which creates a data
  product, wraps a `scan-azure-sql-and-classify`-scanned asset as a Unified Catalog data asset,
  and links both that asset and this scenario's `Customer`/`Customer ID` terms to it via the
  `Data Products - Create Relationship` operation.
- [x] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row (currently
  "evolving surface — VERIFY exact endpoint names per release") with the confirmed exact
  operation groups/paths grounded in `curate-business-glossary` (`Terms` and `Business Domain`
  operation groups, `POST/PUT/DELETE/GET /datagovernance/catalog/terms(|/{id})`,
  `.../businessdomains(|/{id})`, `.../terms/{id}/relationships`, API version
  `2026-03-20-preview`) — closes that cross-cutting doc's open VERIFY for this one surface —
  **built** (see DONE below).
- [ ] VERIFY (pilot tenant, before production reliance): the Unified Catalog `Terms - Query`
  `nameKeyword` filter's exact match semantics (substring/prefix/tokenized) are undocumented;
  `curate-business-glossary`'s idempotency design always re-checks for an exact client-side name
  match rather than trusting the filter, but a domain with more than one page of name-matching
  terms could in principle need pagination the deploy script doesn't yet implement — flagged
  inline in `README.md` §11 and the deploy script's `.NOTES`.
- [ ] VERIFY (pilot tenant): the Unified Catalog `Business Domain - Create`/`Update` REST
  reference marks `systemData`/`thumbnail`/`domains`/`managedAttributes` as required request-body
  fields in a way that contradicts Microsoft's own worked examples and ordinary REST semantics;
  `curate-business-glossary`'s deploy script sends a minimal practical body instead and flags this
  discrepancy rather than fabricating placeholder values for those fields — confirm the minimal
  body is accepted (or find the correct minimal shape) against a pilot tenant.
- [ ] Consider a `scenarios/unified-catalog/governance-domain-hierarchy/` (or fold into a future
  Unified Catalog pass) covering multi-domain parent/child governance hierarchies, custom
  attribute groups, and data estate mappings to Data Map collections — explicitly out of scope in
  `curate-business-glossary/design.md` §6–7, which models a single standalone domain.

### Follow-ups discovered while building the Unified Catalog manage-data-products scenario
- [ ] VERIFY (pilot tenant or the Swagger spec linked from the Unified Catalog API overview page):
  the exact `Data Products - Create Relationship` request body per `entityType` — the REST
  reference's only worked example (`entityType=CRITICALDATACOLUMN`) includes an `assetId` field
  this scenario's `DATAASSET`/`TERM` calls omit. Flagged inline in `manage-data-products/README.md`
  §11, `design.md` §3, and `deploy/New-DataProduct.ps1`'s `.NOTES` rather than resolved by
  guessing. Closing this would also let `scenarios/unified-catalog/link-glossary-terms-to-data-
  products/`-style critical-data-element/column linking be added with confidence.
- [ ] VERIFY (pilot tenant): whether the Unified Catalog `Data Products - Update` REST operation
  enforces the portal's "must configure a data access policy before Publish" business rule
  server-side, or whether that is a portal-UX-only guardrail this scenario's direct `PUT` call
  bypasses — flagged as a Red Team/CISO finding in `manage-data-products/reviews.md` and as a
  gating prerequisite in `README.md` §3, with a `Write-Warning` as the interim compensating
  control. No REST operation for configuring a data product access policy itself was found during
  this build's grounding pass (`design.md` §5) — that stays a portal-only manual step.
- [ ] `scenarios/unified-catalog/manage-critical-data-elements/` — script the `Critical Data
  Elements` operation group (create a CDE, map asset columns to it, the auto-linking-to-data-
  products behavior Microsoft documents) — explicitly out of scope in `manage-data-products/
  design.md` §6, which links only `DATAASSET` and `TERM` entity types.
- [ ] `scenarios/unified-catalog/manage-okrs/` — script the `Okr`/`Key Result` operation groups and
  link them to data products, closing the last `EntityCategory` gap `manage-data-products/design.md`
  §6 leaves open (OKR linking).
- [x] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row with the
  confirmed `Data Products` and `Data Assets` operation groups/paths grounded in
  `manage-data-products` (`POST/PUT/DELETE/GET /datagovernance/catalog/dataProducts(|/{id})`,
  `.../dataProducts/{id}/relationships`, `.../dataAssets(|/{id})`, `.../dataAssets/query`, API
  version `2026-03-20-preview`) — same pattern `curate-business-glossary`'s and
  `end-to-end-lineage-validation`'s own automation-surface.md follow-ups already established of
  tracking doc extensions separately rather than bundling them into a scenario fragment —
  **built** (see DONE below).
- [ ] Once `scenarios/compliance-manager/` or a future access-governance scenario needs it,
  consider scripting **data product access policy** configuration if Microsoft publishes a REST
  surface for it — confirmed not to exist as of this build (`manage-data-products/design.md` §5);
  the REST API's own `Policies` operation group is a different feature (the RBAC authorization-
  policy engine), not the consumer-facing access-request workflow.

### Follow-ups discovered while building the Data Lineage end-to-end-lineage-validation scenario
- [x] `scenarios/data-lineage/custom-process-lineage/` (or fold into a future Data Lineage
  hardening pass) — script the richer DataSet -> Process -> DataSet lineage shape (a custom
  Process-typed entity representing the transform itself, not just a direct dataset-to-dataset
  edge), once a REST-documented body for creating a *custom* Process entity type is independently
  grounded — **built** (see DONE below): a fresh grounding pass on this run found and directly
  confirmed the previously-missing body in Microsoft's own "Create and get lineage relationships
  using the REST API" tutorial (Example 1: create a Process entity via Entity - Bulk Create Or
  Update, then `dataset_process_inputs`/`process_dataset_outputs` relationships; "Create New Custom
  Types": the custom-Process-type body). Composable with, not a replacement for, this scenario's
  own `direct_lineage_dataset_dataset` edge — see the new scenario's `design.md` §6.
- [ ] Generalize `scenarios/data-lineage/end-to-end-lineage-validation/validate/
  Test-EndToEndLineage.ps1`'s column-mapping check ("Check 2") to match each `customLineageLinks`
  entry against its own declared upstream node rather than always the origin asset — needed before
  that scenario's definition file can correctly model a multi-hop chain with a custom link further
  downstream than the origin's immediate output. Currently correct only for the shipped
  single-hop example; flagged inline in the script and in `design.md` §7.
- [ ] VERIFY (pilot tenant): the exact qualifiedName string format Purview assigns to an
  `azure_sql_table` asset (e.g. whether it follows an `mssql://...` scheme) — not found during this
  build's grounding pass; `end-to-end-lineage-validation`'s definition file currently requires the
  operator to copy the value from the portal rather than having either script construct it. Closing
  this would let a future scenario auto-resolve qualifiedNames instead of requiring manual copy.
- [ ] VERIFY (pilot tenant): whether `Relationship - Create` rejects, no-ops, or duplicates a
  second POST of an identical relationship — this build's grounding pass confirmed the operation's
  request/response shape directly from Microsoft's REST reference but not this specific behavior;
  `end-to-end-lineage-validation`'s own existence-check design makes its idempotency independent of
  the answer, but a production integration bypassing that check should confirm it first.
- [x] Extend `docs/automation-surface.md` §4's routing table with a row for Data Map lineage
  (`entity/bulk`, `relationship`, `lineage/uniqueAttribute/type/{typeName}` — surface 4,
  `datamap/api/atlas/v2/...`, API version `2023-09-01`) — not added in this build to keep the
  fragment scoped to one scenario; `scan-azure-sql-and-classify`'s and
  `curate-business-glossary`'s own automation-surface.md follow-ups set the same precedent of
  tracking doc extensions separately rather than bundling them into a scenario fragment —
  **built** (see DONE below).

### Follow-ups discovered while building the Data Quality rules-and-scorecards scenario
- [ ] `scenarios/data-quality/connection-and-scorecard-alerts/` (or fold into a future Data Quality
  hardening pass) — script the DQ data-source connection (`Create Data Source`) and score-threshold
  alerts (`Get Alerts`/`Update Alert`), both deferred from `rules-and-scorecards` because
  `Create Data Source`'s `computeId` field has no documented provisioning endpoint this build could
  find, and the Alerts operations weren't independently fetched/grounded in this build — see that
  scenario's `README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the Data Quality Schedule object's
  trigger `type` values beyond the confirmed `RunOnce` shape — a `Recurrence` type with frequency/
  interval fields almost certainly exists (the portal's own Scheduled scans wizard supports daily/
  weekly/monthly recurrence) but wasn't found in this build's REST reference fetch. Needed before
  `rules-and-scorecards` (or a follow-up) can script an ongoing scan cadence instead of a one-time
  `RunOnce` schedule.
- [ ] VERIFY (pilot tenant): the exact mechanism by which a `TypeMatch` (Data type match) rule's
  `typeProperties` specifies the target type a column is checked against — the confirmed REST
  `TypeProperties` schema has no field name for it despite Microsoft's conceptual documentation
  describing the behavior. Flagged inline in `rules-and-scorecards/deploy/
  New-DataQualityRulesAndSchedule.ps1`'s `.NOTES` and `README.md` §11.
- [x] A Unified Catalog **data products** scenario (create/manage a data product, add data assets to
  it) is a shared, still-unbuilt dependency both `curate-business-glossary`'s and
  `rules-and-scorecards`' non-goals point to — **built** as
  `scenarios/unified-catalog/manage-data-products/` (see DONE below). `rules-and-scorecards`'s own
  `Create Data Source`/`computeId`-provisioning gap (above) is a separate, still-open item.

### Follow-ups discovered while building the Data Estate Insights classification-coverage-report scenario
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — extends
  `classification-coverage-report`'s exact pattern (paginated `Discovery - Query`, client-side tally,
  replace-by-`RunId` trend log) to the `label` field on the same `SearchResultValue` schema — **built**
  (see DONE below).
- [ ] `scenarios/data-estate-insights/glossary-curation-coverage-report/` — the native "Glossary
  insights"/"Data stewardship" dashboards (term-to-asset attachment rates, active-user counts) use
  different underlying data than `Discovery - Query`'s per-asset `classification`/`label` fields and
  would need a different REST primitive (likely the Unified Catalog Terms operation group this
  repo's `scenarios/unified-catalog/curate-business-glossary/` already grounds) — explicitly scoped
  out of `classification-coverage-report/design.md` §7 as a different data source, not a copy-paste
  extension of this fragment's pattern.
- [ ] VERIFY (pilot tenant, before production reliance): `classification-coverage-report/deploy/
  Export-ClassificationCoverageReport.ps1`'s `Get-FullBreakdown` warns (but does not fail) when the
  number of records actually paged via `continuationToken` doesn't match the response's own
  `@search.count` — Microsoft's Discovery - Query REST reference doesn't document whether this
  mismatch is expected (e.g. due to near-real-time index changes mid-page-through) or a sign of a
  client-side pagination bug. Confirm against a pilot tenant with a large, stable (non-changing)
  asset population before treating a persistent mismatch as benign.
- [ ] Note for a future Data Lineage follow-up: this build's `Discovery_Query_Collection` worked
  example response (Microsoft's own REST reference page for Discovery - Query) shows a real
  `azure_sql_table` `qualifiedName` value —
  `mssql://exampleserver.database.windows.net/examplesqldb/examplepath/exampledata1` — which
  directly bears on the open VERIFY in `scenarios/data-lineage/end-to-end-lineage-validation/
  README.md` §11 ("the exact qualifiedName string format Purview assigns to an azure_sql_table
  asset"). Not applied retroactively to that already-DONE fragment in this build (out of scope for
  this turn), but the next pass on that scenario (or a dedicated Data Map/Data Lineage grounding
  fragment) should confirm this `mssql://` scheme against a pilot tenant and, if confirmed, update
  that scenario's README/design.md to close the VERIFY instead of requiring manual portal copy.

### Follow-ups discovered while building the Compliance Manager ISO 27001 assessment scenario
- [ ] `scenarios/compliance-manager/entra-privileged-role-monitoring/` (or fold into a future
  cross-cutting RBAC-hardening pass) — script monitoring of Entra directory role-assignment changes
  for Global Administrator/Compliance Administrator/Compliance Data Administrator/Security
  Administrator, the four Entra roles that grant implicit Compliance Manager Administration-
  equivalent access invisibly to `assess-against-iso27001`'s audit-trail script (flagged as a Red
  Team finding in that scenario's `reviews.md` and `README.md` §11) — via Microsoft Graph's Entra
  directory audit log / `auditLogs/directoryAudits`, not the Compliance-Manager-specific
  `Search-UnifiedAuditLog` operations this scenario already covers.
- [ ] VERIFY (pilot tenant, before production reliance): the internal JSON shape of the `AuditData`
  payload for `ComplianceManagerRolesChange`/`ComplianceManagerAutomationLevelChange`/
  `ComplianceManagerAutomationChange` audit records — not published in Microsoft's
  `audit-log-activities` reference. `assess-against-iso27001/deploy/
  Export-ComplianceManagerAuditTrail.ps1`'s `Get-BestEffortTargetObjectId` function assumes an
  `ObjectId` property *might* exist inside that JSON (best-effort, non-blocking) but does not rely
  on it for correctness — the script's real de-duplication key hashes the full raw payload instead.
  Confirming the actual shape would let a future revision surface richer, grounded columns (e.g.
  which specific improvement action or role was changed) instead of the current opaque JSON blob.
- [ ] **ISO/IEC 27001:2022 premium template is now confirmed to exist** — found while grounding the
  `pci-dss-assessment` sibling scenario: Compliance Manager's current `compliance-manager-
  regulations-list` premium-regulations catalog lists both "ISO/IEC 27001:2013" and "ISO/IEC
  27001:2022" as separate templates (2022 is the edition organizations now actually certify
  against). `assess-against-iso27001/README.md` §11's original VERIFY ("only :2013 was found") is
  now out of date. Update that scenario's `README.md`/`design.md` to acknowledge the :2022 template
  exists and either switch the recommended template to it or explicitly justify staying on :2013 —
  not done in this turn to keep this fragment scoped to `pci-dss-assessment` alone.
- [x] `scenarios/compliance-manager/pci-dss-assessment/` (already tracked above, under the DLP
  PCI Teams follow-ups) — **built** (see DONE below), and cross-linked back into
  `assess-against-iso27001`'s manifest as a sibling assessment in the same `Security & Compliance
  Assessments` group. That manifest's group note was also corrected in place: Microsoft's group
  behavior only shares **nontechnical** improvement actions within a group — technical actions
  already sync tenant-wide regardless of group — a distinction the original note didn't draw.
- [ ] Once Compliance Manager's **Export actions** Excel file has been inspected against a real
  tenant, ground the "Action Update" tab's exact column schema and revisit the non-goal recorded in
  `assess-against-iso27001/design.md` §7 — a schema-accurate generator script would be a genuine,
  higher-value addition to this scenario that this build deliberately declined to fabricate.

### Follow-ups discovered while building the Communication Compliance harassment-and-code-of-conduct scenario
- [ ] `scenarios/communication-compliance/financial-regulatory-supervision/` (or similar) — the
  FINRA/SEC-oriented "Regulatory compliance" policy template (Customer complaints, Gifts &
  entertainment, Money laundering, Regulatory collusion, Stock manipulation, Unauthorized
  disclosure classifiers) — a different regulatory driver (broker-dealer supervision) from
  `harassment-and-code-of-conduct`'s HR/code-of-conduct focus; explicitly called out as a non-goal
  in that scenario's `design.md` §7.
- [ ] Consider a `scenarios/insider-risk/` or `scenarios/adaptive-protection/` follow-up wiring the
  documented Communication Compliance → Insider Risk Management integration (the auto-created
  "Insider risk trigger" policy using the Threat/Harassment/Discrimination classifiers) — deferred
  from `harassment-and-code-of-conduct/design.md` §6 as a separate, deliberate opt-in rather than
  bundled into a standalone Communication Compliance policy.
- [ ] `scenarios/dspm-for-ai/` or `scenarios/communication-compliance/` — the "Detect Microsoft 365
  Copilot and Microsoft 365 Copilot Chat interactions" policy template (Prompt Shields/Protected
  material classifiers) and the preview LLM-based content-safety classifiers (Hate/Sexual/Violence/
  Self-harm, Teams/Viva Engage/Copilot-only) — both explicitly out of scope in
  `harassment-and-code-of-conduct/design.md` §4/§7 since this scenario's Exchange-inclusive scope
  needs the trainable-classifier family for full location coverage; the content-safety classifiers
  are candidates for a higher-accuracy, Teams/Viva-Engage-specific follow-up.
- [ ] VERIFY (portal, at deploy time, before a customer-facing deployment): the exact current-UI
  label for the "Harassment"/"Targeted harassment" trainable classifier — Microsoft's own docs use
  both names for what reads as the same classifier across different pages
  (`harassment-and-code-of-conduct/README.md` §11, `design.md` §4). Not resolved by guessing in
  this build per `AGENTS.md` §4.
- [ ] VERIFY (employment counsel, jurisdiction-by-jurisdiction): monitoring-notice/consent
  obligations for the Investigator-role full-content-visibility design in
  `harassment-and-code-of-conduct` — flagged as a gating prerequisite in that scenario's `README.md`
  §3/§11 (CISO lens finding in `reviews.md`) but is a legal determination outside this repo's
  grounding scope, not something this build can resolve.
- [ ] Re-check the EEOC's sub-regulatory harassment-guidance status before any customer-facing use
  of `harassment-and-code-of-conduct`'s regulatory-driver narrative (`README.md` §2/§11) — the 2024
  EEOC Enforcement Guidance on Harassment in the Workplace was rescinded by a 2–1 Commission vote on
  January 23, 2026, mid-way through this build's own grounding pass; the scenario's driver rests on
  the underlying Title VII statute and *Faragher*/*Ellerth* case law instead, but this area is
  actively moving and should be re-verified before every future sale referencing it.

### Follow-ups discovered while building the Audit premium-audit-investigation scenario
- [x] `scenarios/audit/retention-policy-management/` — script **audit log retention policies** (a
  Premium feature: create/manage custom retention durations per record type/user via SCC PowerShell
  `New-/Set-UnifiedAuditLogRetentionPolicy`), the configuration counterpart to this read-only
  investigation scenario — **built** (see DONE below).
- [ ] `scenarios/audit/streaming-to-sentinel-or-management-api/` — continuous audit streaming via the
  Office 365 Management Activity API (or a Sentinel connector) for real-time detection, contrasted
  with this on-demand investigation in `audit/premium-audit-investigation/design.md` §7.
- [ ] VERIFY (pilot tenant): the exact `auditLogQueryStatus` terminal values (the runner polls
  defensively and flags this in `audit/premium-audit-investigation/README.md` §11), and the current
  crucial-events list / operation names for the compromise preset.
- [ ] Consider an **incident-response (mutating) companion** scenario — disable account, revoke
  sessions, remove malicious inbox rules — the deliberate response workflow this read-only
  investigation explicitly scopes out (`audit/premium-audit-investigation/design.md` §7).

### Follow-ups discovered while building the Audit retention-policy-management scenario
- [ ] Backport the **Organization Configuration vs. Audit Manager** role distinction into
  `docs/rbac-model.md`'s existing Audit row (currently "Audit Reader (View-Only Audit Logs) →
  Audit Manager (configure + search + export)", which doesn't mention retention-policy management
  at all). Confirmed this build: creating/editing audit log retention policies requires the
  **Organization Configuration** role (per `audit-log-retention-policies`), which is included by
  default in the **Compliance Data Administrator** Purview role group — a *different* grant from
  the Audit Manager role group `rbac-model.md` already documents for search/export configuration.
  Deferred from `retention-policy-management/README.md` §3/§11 (which carries the finding inline)
  to avoid re-opening the cross-cutting doc mid-fragment, consistent with this repo's established
  precedent (e.g. the `auto-label-confidential-exchange` role-prerequisite backport, still open
  above).
- [ ] VERIFY (pilot tenant): the retroactive-vs-forward-only behavior of editing a live retention
  policy's `RetentionDuration` — Microsoft's own `audit-log-retention-policies` page states both
  that a change "changes the expiration time of the audit data after updating" and, in the same
  paragraph, that such changes "don't update any previously committed items," without reconciling
  the two. `retention-policy-management/README.md` §11 and `design.md` §6 flag this rather than
  asserting either reading — resolving it would let a future revision give concrete guidance on
  whether shortening a policy is safe to use for cost/noise control without risking early
  expiry of records a buyer still needs.
- [ ] VERIFY (pilot tenant): whether passing `$null` to `-RecordTypes`/`-Operations` on
  `Set-UnifiedAuditLogRetentionPolicy` clears a previously-set value, the same way Microsoft's own
  worked example confirms for `-UserIds`. `retention-policy-management/deploy/
  New-AuditRetentionPolicy.ps1` extrapolates the same convention to all three MultiValuedProperty
  parameters by analogy (flagged inline in its `.NOTES` and `README.md` §11) rather than assuming
  it's confirmed.
- [ ] Once Microsoft documents a REST/Graph surface for `UnifiedAuditLogRetentionPolicy` objects
  (none was found during this build's grounding pass — Security & Compliance PowerShell is
  currently the only automation surface), reconsider whether `retention-policy-management` should
  add a Graph-based path alongside the PowerShell one, consistent with how other Purview objects
  in this library are moving toward Graph coverage.

### Re-verification pass on the DLP `removable-usb-device-groups-allowlist` follow-up (endpoint-dlp-usb-block)
- Ran a fresh grounding pass on this open item (below, under "Follow-ups discovered while building
  the Endpoint DLP USB-block scenario") before picking a different fragment for this turn — **still
  blocked**, but with two genuine improvements to record:
  1. **Upgraded, not just re-confirmed:** `endpoint-dlp-usb-block/README.md` §11's existing VERIFY
     for `-EndpointDlpRestrictions` `Setting='RemovableMedia'`/`Value='Block'`/`'Audit'` was
     previously sourced only from a Tech Community blog walkthrough. This build independently
     re-confirmed the exact same `Setting`/`Value` hashtable shape directly from Microsoft's
     **official** `New-DlpComplianceRule` reference page (fetched in full), which also reveals two
     additional valid `-Value` strings beyond Block/Audit: **`Ignore`** and **`Warn`** — `Warn`
     plausibly maps to the portal's "Block with override" option that `endpoint-dlp-usb-block/
     design.md` §6 previously declined to use for exactly this reason (no confirmed enum value).
     Filed below as a task to backport this stronger citation and re-evaluate the `Warn` mapping —
     not done in this turn to keep this fragment scoped to `retention-policy-management` alone.
  2. **Confirmed the tenant-wide group-*creation* cmdlets exist, but their body shape is still
     genuinely undocumented.** `Set-PolicyConfig -DlpRemovableMediaGroups`/`-DlpPrinterGroups`
     (both typed `PswsHashtable`) are real, current parameters — confirmed via the official
     `Set-PolicyConfig` reference page. However, both parameters' description sections are
     Microsoft-side placeholder stubs ("`{{ Fill ... Description }}`") with **no example hashtable
     shape**, confirmed empty even in the raw GitHub Markdown source
     (`MicrosoftDocs/office-docs-powershell/.../Set-PolicyConfig.md`) — ruling out a rendering
     artifact. Separately, the *per-rule* group-reference key inside a `New-DlpComplianceRule`
     `-EndpointDlpRestrictions` entry (the mechanism behind the portal's "Choose different
     removable storage restrictions" per-rule override) has no documented key name anywhere in the
     official `New-DlpComplianceRule` reference either. **This item remains blocked** on the same
     core gap it already carried — Microsoft has not published either shape as of this build.
- [x] Backport the official-source confirmation of `EndpointDlpRestrictions` `Setting`/`Value`
  strings (including the newly-found `Ignore`/`Warn` values) into
  `endpoint-dlp-usb-block/README.md` §11 and `deploy/New-EndpointDlpUsbBlockPolicy.ps1`'s
  `.NOTES`, upgrading the citation from the Tech Community blog to the official
  `New-DlpComplianceRule` reference page, and re-evaluate whether `Warn` should replace `Audit` as
  the IT Data Custodians exception action per `design.md` §6's own stated reasoning — **built**
  (see DONE below): citation upgraded across `README.md` (§6, §11, §12), `design.md` (§6, §7),
  `deploy/New-EndpointDlpUsbBlockPolicy.ps1` (`.NOTES` and a new `-ITExceptionAction` parameter),
  `validate/Test-EndpointDlpUsbBlockPolicy.ps1`, and the reference policy JSON. Re-evaluation
  outcome: `Audit` stays the **default** (no behavior change for an existing deployment), but
  `Warn` is now a documented, one-flag opt-in (`-ITExceptionAction Warn`) for a buyer who wants the
  IT Data Custodians path justification-gated instead of silently logged — not a forced switch,
  since the `Warn`-to-portal's-"Block with override" mapping is corroborated, not literally
  confirmed (see the new VERIFY below).
- [ ] VERIFY (pilot tenant, before describing `-ITExceptionAction Warn` to a customer as "Block
  with override" by name): whether the portal's "Block with override" `EndpointDlpRestrictions`
  activity option is in fact the `Warn` enum value. Microsoft's official `New-DlpComplianceRule`/
  `Set-DlpComplianceRule` reference confirms `Warn` exists and groups it with `Block` via a shared
  `-NotifyUser` requirement, but never states the portal-name mapping explicitly — flagged inline
  in `endpoint-dlp-usb-block/README.md` §11 and the deploy script's `.NOTES` rather than asserted.
- [ ] VERIFY (pilot tenant, before relying on `-Force` to switch `endpoint-dlp-usb-block`'s
  `-ITExceptionAction` from `Warn` back to `Audit`): whether `Set-DlpComplianceRule` clears a
  previously-set `NotifyUser`/`NotifyPolicyTipCustomText` value when a later call omits it, or
  leaves it stale on the live rule — undocumented by Microsoft either way. Flagged inline in
  `README.md` §11 and the deploy script's `.PARAMETER Force`/`.NOTES`.
- [ ] Periodically re-check whether Microsoft has filled in the `Set-PolicyConfig`
  `-DlpRemovableMediaGroups`/`-DlpPrinterGroups` reference page's placeholder description sections
  (currently literal `{{ Fill ... Description }}` stub text) or published a worked example — this
  is the blocking gap for `scenarios/dlp/removable-usb-device-groups-allowlist/` (below). Since the
  page itself is an acknowledged stub (not just sparse), it is a reasonable candidate for Microsoft
  to complete in a future documentation pass, unlike a gap where no reference page exists at all.

### Follow-ups discovered while building the DLM retention-labels-financial-records scenario
- [ ] `scenarios/data-lifecycle-management/event-based-retention-and-disposition/` — event-based
  retention (`New-ComplianceTag -EventType`), `KeepAndDelete` with disposition review
  (`-ReviewerEmail`, multi-stage), and the disposition workflow — powerful RM features layered on the
  same cmdlets, non-goals of this starter (`design.md` §7). Overlaps the records-management starter.
- [ ] `scenarios/data-lifecycle-management/publish-labels-for-manual-application/` — a **publish**
  label policy (`New-RetentionComplianceRule -PublishComplianceTag`) so users can manually apply the
  financial-records label, complementing this scenario's auto-apply.
- [ ] `scenarios/data-lifecycle-management/adaptive-scope-retention/` — auto-apply/retention scoped by
  an **adaptive scope** (attribute-driven) instead of static locations, for large/dynamic estates
  (noted as out of scope here).
- [ ] Consider **file plan descriptors** (`-FilePlanProperty`: categories, citations, authorities,
  provisions) for a formal records file plan, and bulk label/policy creation via the documented CSV
  script (`bulk-create-publish-labels-using-powershell`).

### Follow-ups discovered while building the Information Barriers segregate-trading-and-research scenario
- [ ] `scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/` — enable IB
  for SharePoint/OneDrive (`Set-SPOTenant`) and associate segments to sites, the file-level half beyond
  the Teams wall (noted as an extension in this scenario's `design.md` §6 / `README.md` §11).
- [ ] `scenarios/information-barriers/allow-list-and-control-room-exceptions/` — model allow-list
  topologies (`-SegmentsAllowed`) and a control-room/compliance segment that must see both sides, the
  exception pattern real deployments need (non-goal here).
- [ ] Consider a multi-segment-mode migration note/scenario (Legacy → SingleSegment/MultiSegment) and
  address-book-policy / GAL segmentation as companions.

### Follow-ups discovered while building the Records Management regulatory-records-disposition scenario
- [ ] `scenarios/records-management/file-plan-bulk-import/` — bulk create a full file plan (retention
  schedule with citations, departments, authorities across many record classes) via the documented CSV
  import, the multi-class complement to this single representative class (non-goal here).
- [ ] `scenarios/records-management/multi-stage-disposition-review/` — model a multi-stage disposition
  panel (up to 5 stages / 10 reviewers each) using `-MultiStageReviewProperty` /
  `-ComplianceTagForNextStage`, for sign-off chains where one approver isn't enough (noted as a non-goal
  in this scenario's `design.md` §7).
- [x] `scenarios/records-management/graph-event-automation/` — **built** (see DONE): fire retention
  events from a business system via the Microsoft Graph records-management APIs
  (`retentionEvent`/`retentionEventType`, the modern path since the REST event API was deprecated), the
  automation complement to the PowerShell `New-ComplianceRetentionEvent` scenario (surface 2/3).
- [ ] `scenarios/records-management/disposition-proof-export/` — export proof-of-disposition and the
  disposition views for audit (Records Management → Disposition filter/export), closing the evidence
  loop this scenario's §7 references.
- [ ] Consider an adaptive-scope variant of the publish policy for large/dynamic estates (a cross-module
  follow-up shared with the DLM scenarios), and a records-vs-regulatory decision note linking this
  scenario with the DLM `retention-labels-financial-records` sibling.

### Follow-ups discovered while building the Data Map Azure SQL Managed Instance scenario
- [x] **Backport two corrected REST shapes into `scenarios/data-map/scan-azure-sql-and-classify/`.**
  — **built**, see DONE below.
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` — the next explicitly-flagged sibling in
  `scan-azure-sql-and-classify/design.md` §7's original list (Azure Synapse Analytics dedicated +
  serverless SQL pools) — **built** (see DONE below): reuses the proven object model, documents the
  genuine `kind`/auth/network differences Microsoft's own docs describe (registration per workspace
  with two optional SQL endpoints, a three-part serverless enumeration-authentication story, the
  distinct system scan rule set `AzureSynapseSQL`).
- [x] `scenarios/data-map/scan-on-premises-sql-server-and-classify/` — the third sibling (on-premises
  SQL Server via self-hosted integration runtime), deferred from both this fragment and the original
  sibling scenario's non-goals — a materially different registration/auth story (no managed identity
  path at all; self-hosted IR is mandatory) worth its own careful grounding pass — **built** (see
  DONE below): also scripts the self-hosted integration runtime *resource* and its auth-key retrieval
  via two directly-confirmed REST operations (`Integration Runtimes - Create Or Replace` and
  `- Regenerate Auth Key`) — a first for this repo's Data Map scenarios, none of which had scripted
  even that much of the portal-only credential/SHIR setup story before this build.
- [ ] `scenarios/data-map/verify-purview-entra-graph-prerequisites/` (or fold into a future Data Map
  hardening pass) — a Microsoft Graph-permissioned checker script confirming Directory Readers (or
  equivalent fine-grained Graph permission) membership for every Managed-Instance-backed Purview
  data source's managed identity, deferred from this scenario's `validate/
  Test-AzureSqlManagedInstanceDataMapScan.ps1` because that script's own auth surface (the Purview
  Data Map data-plane token) has no reason to also hold Graph directory-read permissions — flagged
  as a Blue Team finding in this scenario's `reviews.md`.
- [ ] VERIFY (pilot tenant): the exact TCP port a newly registered managed instance's public endpoint
  listens on. This scenario defaults `-Port` to `3342` (Microsoft's own worked *registration*
  example), but the actual port depends on the instance's connection-policy configuration
  (Redirect vs. Proxy) — flagged inline in `README.md` §11 and the deploy script's parameter help.
- [ ] Consider scripting `Set-AzSqlInstanceActiveDirectoryAdministrator` and the Directory Readers
  Microsoft Graph role-assignment step (the PowerShell pattern Microsoft publishes for it) instead
  of leaving both as manual portal/PowerShell prerequisites (`README.md` §5 steps 2–3) — deferred in
  this build to keep the fragment scoped to the Data Map REST surface itself, consistent with this
  repo's existing precedent of not automating rare, high-privilege, one-time setup steps that sit
  outside the automation identity's own Purview/Azure IAM role scope (see `design.md` §8).

### Follow-ups discovered while building the Data Map on-premises SQL Server scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the literal system scan rule set name
  for the `SqlServerDatabase` data source `kind` — this build inferred `'SqlServerDatabase'` from the
  "system ruleset name == data source kind" pattern every prior Data Map sibling scenario confirmed
  via its own worked example, but found only a distinct `SqlServerDatabaseSystemScanRuleset` SDK type
  (confirming a system ruleset exists) rather than a worked example pairing the name with
  `scanRulesetType: "System"`. Flagged inline in `scan-on-premises-sql-server-and-classify/README.md`
  §11 and the deploy script's `.NOTES` rather than resolved by guessing.
- [ ] VERIFY (pilot tenant): which `CredentialType` REST enum value corresponds to "Windows
  Authentication" in the portal for the `SqlServerDatabaseCredential` scan kind — Microsoft's portal
  documents Windows Authentication as a supported method for this source type, but the confirmed
  enum (`AccountKey`/`ServicePrincipal`/`BasicAuth`/`SqlAuth`/`AmazonARN`/`ConsumerKeyAuth`/
  `DelegatedAuth`/`ManagedIdentity`) has no value independently confirmed to map to it.
  `scan-on-premises-sql-server-and-classify`'s deploy script offers `'BasicAuth'` as an unconfirmed
  best-effort alternative to the confirmed `'SqlAuth'` default — see that scenario's `README.md` §11.
- [ ] `scenarios/data-map/scan-on-premises-sql-server-and-classify-kubernetes-shir/` (or fold into a
  future Data Map hardening pass) — the Kubernetes-based, containerized self-hosted *data* integration
  runtime Microsoft documents as a separate, newer capability (SQL Server and Oracle only,
  SQL-authentication-only) from the classic Windows-host SHIR `scan-on-premises-sql-server-and-
  classify` scripts — explicitly out of scope there (`design.md` §8) as a materially different
  deployment model.
- [ ] Consider scripting Microsoft Graph-based monitoring of the self-hosted integration runtime's
  auth-key rotation history or last-check-in time, closing part of the Blue-Team-flagged gap in
  `scan-on-premises-sql-server-and-classify/reviews.md` that the Data Map REST API's Integration
  Runtimes - Get operation returns the resource definition, not live node health — no such monitoring
  endpoint was independently grounded during this build; would need a fresh grounding pass.
- [ ] Once a documented REST endpoint for Purview credential-object creation is found (the same open
  gap every Data Map sibling scenario in this repo already carries, most recently re-confirmed absent
  by Microsoft's own disaster-recovery/migration best-practices article — "there's no API to extract
  credentials"), revisit whether it can also *create* one, not just document/extract, and close this
  gap across every Data Map scenario in this repo at once rather than scenario-by-scenario.

### Follow-ups discovered while building the Data Estate Insights sensitivity-label-coverage-report scenario
- [ ] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — add a source-type-support
  check to `deploy/Export-SensitivityLabelCoverageReport.ps1`/`validate/
  Test-SensitivityLabelCoverageReport.ps1` that flags when a scoped `-CollectionId`/`-ObjectTypes`
  combination is outside Microsoft's documented Data Map sensitivity-label source-type list (Azure
  Blob Storage, ADLS Gen1/Gen2, SQL Server, Azure SQL Database, Azure SQL Managed Instance, Amazon S3,
  Amazon RDS (preview), Power BI), so a `0% labeled` reading for an unsupported source type isn't
  mistaken for a real governance gap — deferred from that scenario's build (flagged as a Red Team/Blue
  Team finding in `reviews.md`, and as a non-goal in `design.md` §7) because this build did not
  independently re-verify that supported-source list is complete/current enough to hard-code as a
  validation rule; needs a fresh grounding pass specifically on that list before encoding it.
- [ ] Once Microsoft's "Extend sensitivity labels to Data Map" capability reaches GA (it is Public
  Preview as of this build — `sensitivity-label-coverage-report/README.md` §3/§11), re-verify the
  `label` field/facet semantics on Discovery - Query still hold and drop the preview callout.
- [ ] Consider a `scenarios/information-protection/` or cross-cutting follow-up scripting the "extend
  sensitivity labels to Data Map" enablement itself (turning on the capability, scoping a label to
  "Files & other data assets") — left as a manual portal prerequisite in
  `sensitivity-label-coverage-report/README.md` §5 step 1/`design.md` §7, since this scenario only
  reads labels already applied, consistent with `classification-coverage-report`'s own non-goal of not
  building the scan it reports on.

### Follow-ups discovered while building the Data Map Azure Synapse Analytics scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/SDK grounding pass): the exact JSON shape of the
  `AzureSynapseWorkspaceMsiScan` object's optional `resourceTypes` property (seen only as an opaque
  `-ResourceType` parameter on the Az.Purview PowerShell module's `New-AzPurviewAzureSynapseWorkspaceMsiScanObject`
  cmdlet, with no worked example of its value) — `scan-azure-synapse-and-classify/deploy/
  New-AzureSynapseDataMapScan.ps1` omits the property entirely rather than guess a shape that could
  silently mis-scope the scan between dedicated and serverless pools. Flagged inline in the deploy
  script's `.NOTES`, `README.md` §6/§11, and `design.md` §5/§7.
- [ ] `scenarios/data-map/bulk-grant-synapse-serverless-access/` (or fold into a future Data Map
  hardening pass) — script to bulk-apply the per-serverless-database `CREATE LOGIN`/`CREATE USER`/
  `db_datareader` grants across every database in a workspace (e.g. iterating `sys.databases` via
  `Invoke-Sqlcmd`), closing the CISO-flagged per-database prerequisite-cost scaling noted in
  `scan-azure-synapse-and-classify/README.md` §3 and `reviews.md`.
- [ ] `scenarios/data-map/verify-synapse-serverless-enumeration-grants/` (or combine with the Managed
  Instance sibling's already-tracked `verify-purview-entra-graph-prerequisites/` follow-up into one
  broader SQL/Graph-permissioned checker) — a SQL-permissioned checker script confirming the serverless
  `CREATE LOGIN` and `db_datareader` grants exist per database, deferred from `scan-azure-synapse-and-
  classify/validate/Test-AzureSynapseDataMapScan.ps1` because that script's own auth surface (the
  Purview Data Map data-plane token) has no reason to also hold a SQL connection to the serverless
  endpoint — flagged as a Blue Team finding in that scenario's `reviews.md`.
- [ ] Consider scripting the **REST API + SQL Auth fallback** for a Synapse workspace whose "Allow
  Azure services and resources to access this workspace" firewall control cannot be enabled — deferred
  from `scan-azure-synapse-and-classify/design.md` §8 as a materially different auth/credential story
  (a Key Vault-backed SQL credential object, the same open portal-only credential-object gap both
  sibling Data Map scenarios already carry).

### Follow-ups discovered while building the PCI Teams Part 2 (drip-exfiltration) scenario
- [ ] VERIFY (pilot tenant): run the full end-to-end composition this fragment designs but does
  not independently confirm against a live tenant — Communication Compliance SIT indicator →
  feeder IRM "Data leaks" policy → Cumulative Exfiltration Detection → Adaptive Protection →
  `PCI-ElevatedRisk-Block-AllExternal` rule — per `design.md` §6b. Every individual piece is
  grounded; the combination as a working end-to-end chain is not yet pilot-confirmed.
- [ ] Once Microsoft documents a faster-than-daily Cumulative Exfiltration Detection evaluation
  cadence, or a lower-latency Adaptive Protection propagation path, revisit the "one to two days"
  exposure-window estimate in `pci-teams-exfil-block-part2-obfuscation-mitigation/README.md` §11
  and its KPI in §8.
- [ ] Consider generalizing this fragment's pattern — a new, narrowly-scoped
  `-SharedByIRMUserRisk` rule added directly to a scenario's *own* named DLP policy (rather than
  routing through `dynamic-risk-dlp-enforcement`'s general-purpose Exchange+Teams policy) — as a
  reusable template for other content-pattern-based DLP scenarios in this library that want an
  Adaptive-Protection behavioral compensating control for the same per-message blind spot (e.g. a
  future Communication Compliance or DSPM-for-AI scenario facing the same split-content evasion
  shape).
- [ ] `scenarios/communication-compliance/` — the Communication Compliance policy this fragment's
  Step 2 creates via the Insider Risk Management "Create policy" shortcut is a real, named
  Communication Compliance policy (auto-named `Insider risk SIT indicator <timestamp>`) that
  currently has no dedicated audit-trail/export script pointed at it, unlike
  `scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/
  Export-CommunicationComplianceAuditTrail.ps1`. Consider whether that existing script generalizes
  to cover this auto-created policy too, once a buyer actually deploys this fragment.

### Follow-ups discovered while building the Compliance Manager PCI DSS v4.0 assessment scenario
- [ ] Update `scenarios/compliance-manager/assess-against-iso27001/` for the now-confirmed
  ISO/IEC 27001:2022 premium template (tracked above, under the ISO 27001 assessment follow-ups) —
  deliberately not done in this turn to keep this fragment scoped to `pci-dss-assessment` alone.
- [ ] VERIFY (pilot tenant): the PCI DSS Requirement 12.4 formal-compliance-program review-cadence
  obligation was deliberately left unspecified/parameterized rather than hard-coded in this
  scenario's tooling (no specific interval is asserted) — see `pci-dss-assessment/README.md` §8/§11.
  If a future build needs a concrete default cadence for a specific merchant/service-provider level,
  ground it against the official PCI DSS v4.0.1 standard (not this library's own inference) before
  adding it.
- [ ] VERIFY (pilot tenant): the technical-vs-nontechnical improvement-action group-sharing
  distinction this scenario's `design.md` §6 documents (grounded from Microsoft's
  `compliance-manager-assessments` "Groups for assessments" reference) is stated correctly, but the
  scenario's own "Group-sharing functional test" (`README.md` §7 item 4) has not been run against a
  live tenant during this build. Confirm before telling a customer the group-placement decision is
  paying off in practice.
- [ ] Consider whether Compliance Manager's PCI DSS v3.2.1 template has been fully removed from new
  tenants' regulation catalogs (vs. still selectable but flagged legacy) — this build confirmed both
  v3.2.1 and v4.0 are currently listed side by side in the public `compliance-manager-regulations-
  list` documentation, but a pilot-tenant check would confirm what the live **Regulations** page
  actually offers today.
- [ ] `scenarios/compliance-manager/soc2-assessment/` or a similar SOC 2 Type II premium-template
  scenario — SOC 2 is a common companion ask alongside PCI DSS for a SaaS/fintech buyer and is
  already listed as a Compliance Manager premium template (`compliance-manager-regulations-list`);
  not built in this turn to keep the backlog breadth-first across modules per `AGENTS.md` §3.

### Follow-ups discovered while building the Data Lineage custom-process-lineage scenario
- [ ] VERIFY (pilot tenant): whether a relationship end's `typeName` must be the entity's own
  concrete custom subtype (`PurviewScenarioLibraryEtlProcess`) or may be the literal ancestor type
  (`Process`) when resolving by `uniqueAttributes.qualifiedName` on `Relationship - Create`.
  `custom-process-lineage`'s deploy script uses the literal `Process` for both relationship ends
  referencing the Process entity, exactly matching Microsoft's own worked example — but that
  example's concrete entity type was a **built-in** subtype (`hive_view_query`), not a custom one.
  Flagged inline in `custom-process-lineage/README.md` §11 and the deploy script's `.NOTES` rather
  than assumed; a one-line fix if wrong.
- [ ] VERIFY (pilot tenant or Microsoft Learn): the exact permission required to create a custom
  **entity type definition** via `Type - Bulk Create` — this build confirmed collection-level Data
  Curator is sufficient for the closely related "create a custom classification" action but found
  no equally explicit statement for entity-type creation specifically. `custom-process-lineage/
  README.md` §3 documents the residual tenant-wide-blast-radius risk either way this resolves.
- [ ] VERIFY (pilot tenant): the exact REST path and in-use-type deletion behavior of `Type -
  Delete` — confirmed to exist only via the .NET SDK's `TypeDefinition.Delete(name)` method
  signature, not an independently fetched canonical REST reference page. Blocks
  `custom-process-lineage/rollback.md` from scripting deletion of the custom Process type
  definition it creates; that file documents the deliberate decision to leave the type in place by
  default and describes the manual, reviewed alternative.
- [ ] VERIFY (pilot tenant): the not-found HTTP status code for `Type - Get Entity Def By Name` —
  its reference page documents only a 200 OK success shape, so `custom-process-lineage`'s
  existence-check treats any non-success response as "does not exist yet" rather than assuming 404
  specifically. Functionally safe either way (see `README.md` §11) but not confirmed.
- [ ] `scenarios/data-lineage/custom-process-lineage-multi-job-catalog/` (or fold into a future
  Data Lineage hardening pass) — extend the single custom Process type this scenario ships
  (`PurviewScenarioLibraryEtlProcess`, two attributes) into a richer, multi-job catalog: additional
  attributes (owning team, source-code repository URL, last-run status) and a pattern for modeling
  many jobs sharing one type without qualifiedName collisions — explicitly deferred as a non-goal
  in `custom-process-lineage/design.md` §8 to keep this fragment scoped.
- [ ] Once a documented REST/Graph way to enumerate live entity counts by type exists (needed to
  safely confirm "zero remaining entities of this type" before a human deletes the custom Process
  type definition entirely), reference it from `custom-process-lineage/rollback.md`'s manual
  decommission guidance instead of pointing at the Data Map portal search/browse UI as the only
  option.

### Follow-ups discovered while building the Defender for Endpoint device control macOS Bluetooth approved-device allowlist scenario
- [ ] `scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist-multi-device/`
  (or fold into a future macOS device-control hardening pass) — support more than one approved
  Bluetooth device. Needs either a separate allow/exception rule pair per device (config-driven,
  deterministic-GUID-per-index loop) or the per-device sub-group + `groupId`-clause-nesting
  technique this repo's sibling scenarios already defer as unverified complexity
  (`defender-device-control-usb-allowlist-macos-vendor-product-matching/`,
  `defender-device-control-usb-allowlist-macos-portable-device-coverage/design.md` §5) — deferred in
  this build (`design.md` §5) because there was no concrete second-device requirement to design
  against, not because either approach is blocked on an open VERIFY.
- [ ] VERIFY (pilot tenant): the exact `AdditionalFields` property names for a Bluetooth device's
  `vendorId`/`productId` on a `RemovableStoragePolicyTriggered` deny event (used in this scenario's
  `README.md` §7 step 6 worked query to help an operator find an unapproved device's identifiers) —
  not independently confirmed by a Microsoft worked example; this build's query is an extension of
  the same cross-platform `DeviceEvents` schema assumption the parent and portable-device-coverage
  fragments already establish for other fields, not a directly confirmed field name for these two
  specifically. Flagged inline in `README.md` §11 rather than resolved by guessing.
- [ ] Once the ordering-hazard root cause is resolved some other way (e.g. if Microsoft ever
  documents a merge-not-replace PATCH semantics for `payload`, or if a future refactor of the
  portable-device-coverage fragment's own script becomes independently warranted for an unrelated
  reason), reconsider whether `defender-device-control-usb-allowlist-macos-bluetooth-allowlist`'s
  disclosed-and-detected mitigation (`design.md` §8) should be upgraded to a structural fix instead —
  deliberately not attempted in this build to avoid reopening an already-reviewed, unrelated
  fragment's script for a coupling change (`design.md` §8 explains the trade-off considered).

### Follow-ups discovered while building the Data Map PII-only scan rule set (Azure SQL Database) scenario
- [ ] VERIFY (pilot tenant): whether `GET .../types/typedefs?type=CLASSIFICATION` paginates once a
  tenant has an unusually large number of custom classification rules layered on top of the ~200
  system ones — no continuation-token field is documented on the response shape, and
  `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging. Flagged inline in the script's
  `.NOTES` and `README.md` §11.
- [ ] `scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/`,
  `scenarios/data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset/`, and
  `scenarios/data-map/scan-on-premises-sql-server-and-classify-pii-ruleset/` — the same PII-only
  custom scan rule set pattern for this repo's three sibling Data Map source types, each with its
  own `*ScanRuleset` `kind` (`AzureSynapse`/`AzureSqlDatabaseManagedInstance`/`SqlServerDatabase`,
  all confirmed to exist in the Scan Rulesets - Create Or Replace body-shape table this build
  direct-fetched) — not built this round to keep the fragment scoped to one source type.
- [ ] Consider a **credential-object creation** follow-up (Key Vault-backed, for the
  `AzureSqlDatabaseCredential` scan kind) becoming unblocked by the same Types/Scan-Rulesets REST
  grounding pass this build did — not investigated this round; the base scenario's `README.md` §11
  VERIFY on this point was left as-is (out of scope for a scan-rule-set-focused fragment).

### Follow-ups discovered while building the Defender for Endpoint device control macOS Apple/Portable vendorId/productId compound-matching scenario
- [ ] Build the Apple/Portable `ApprovedAppleDevices`/`ApprovedPortableDevices` group + its
  `Allow-Approved*Devices` rule from a zero-`serialNumber` starting state, removing this fragment's
  own disclosed prerequisite ("at least one `serialNumber` device must already be configured for a
  family before a `vendorId`/`productId` device can be added to it" — `design.md` §3,
  `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/README.md`
  §3/§11). Deliberately deferred in this build to avoid this fragment also owning
  `Allow-Approved*Devices` rule creation/teardown and `Deny-AllOther*Devices`'s `excludeGroups`
  reconciliation — object ownership that belongs to
  `defender-device-control-usb-allowlist-macos-portable-device-coverage`'s own script today.
- [ ] Consider backporting an ordering-hazard-awareness change into
  `defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
  Add-MacPortableDeviceCoverage.ps1` itself (e.g. preserving any `groupId` clause it doesn't own
  when rebuilding `ApprovedAppleDevices`/`ApprovedPortableDevices`, the same "preserve, don't
  blind-rebuild" fix that would also close this fragment's own disclosed ordering hazard at the
  root) — deliberately not attempted in this build, the same "don't reopen an already-reviewed
  foundational script for an optional extension's benefit" reasoning the Bluetooth allowlist
  fragment's own `design.md` §8 already applied to its own analogous, less severe hazard. Re-open if
  a future, unrelated reason to revise that script's own reconcile logic ever comes up.
- [ ] Extend the Bluetooth family's own single-device `vendorId`/`productId` allowlist
  (`defender-device-control-usb-allowlist-macos-bluetooth-allowlist/`) to multi-device using this
  fragment's now twice-proven per-device sub-group + deterministic-UUIDv5 + `groupId`-clause
  technique — tracked separately as
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist-multi-device/`
  already in this backlog; this build's own family-scoped hash-input pattern (folding a family tag
  into the UUIDv5 name string) is directly reusable there without modification once picked up.

### Follow-ups discovered while building the Exchange PII exfil Part 2 (elevated-risk compensating control) scenario
- [ ] VERIFY (pilot tenant): rule priority compaction behavior — same undocumented
  auto-shift-on-collision question already open for the Teams sibling fragment, applied here to
  `deploy/New-ExchangePiiElevatedRiskBlock.ps1`'s name-agnostic compaction algorithm (design.md §6).
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): no single Microsoft-published example
  validates the exact end-to-end composition this fragment designs (named DLP policy High-severity
  alerts → Data-leaks direct trigger → Cumulative exfiltration scoring → Adaptive Protection → a
  rule on that same named policy) — see `design.md` §6b.
- [ ] Consider whether `scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion` should
  offer a documented, opt-in way to raise its rule to `-ReportSeverityLevel High` specifically when
  a buyer also deploys this Part 2 fragment, closing the exception-group-in-Encrypt-mode blind spot
  this build's Red Team review surfaced (`exchange-pii-exfil-block-part2-obfuscation-mitigation/
  README.md` §11) — not built this run since it would require touching a different, already-shipped
  scenario's default rather than staying scoped to this fragment.
- [ ] Once the Teams sibling fragment's own open VERIFY items (design.md §6b composition validation,
  pilot-tenant priority-reordering confirmation) are resolved against a real tenant, re-run the
  equivalent pilot-tenant checks for this fragment too — the two fragments share the same class of
  unconfirmed end-to-end behavior but are independent deployments and could resolve on different
  timelines.

## DONE
- [x] **`departing-employee-data-theft` — script HR-connector app-secret cleanup** — commit
  `81fee1d` — 2026-09-09 — resolved the follow-up (discovered while building
  `Register-HrConnectorApp.ps1`) asking for a scripted way to delete the superseded secret that
  `-RotateSecret` leaves behind, since Microsoft Entra applications support multiple concurrent
  client secrets by design and nothing deletes the old one automatically. Added the standalone
  `deploy/Remove-HrConnectorAppSecret.ps1`: a default `-RemoveExpired` mode that only ever
  deletes already-dead credentials (safe by construction — can never reduce the app's working-
  secret count) and a narrower `-KeyId`/`-Force` mode for force-retiring a still-valid secret
  (refuses without `-Force` if it's the application's only unexpired secret). Idempotent,
  `-WhatIf`-capable, never logs `SecretText`. Grounded via the Microsoft Learn MCP server
  (available this run, same as the prior fragment, contrary to this task's stored instructions):
  independently re-verified `Remove-MgApplicationPassword`'s full parameter set (not assumed by
  symmetry with `Add-MgApplicationPassword`) and caught a non-obvious mismatch before it shipped —
  its `-KeyId` parameter's documented type is `System.String`, not `System.Guid`, despite the
  underlying `passwordCredential.keyId` Graph resource property's Edm type being `Guid` — so this
  script's own `-KeyId` parameter is typed `[string]` with a GUID-format `ValidatePattern`, not
  `[guid]`. Also confirmed `application: removePassword`'s REST reference documents object-ID
  addressing only (no dual `id`/`appId` addressing the way `addPassword` documents), so the
  script's `.NOTES` doesn't claim that flexibility exists. Added a matching WARN check to
  `validate/Test-HrConnectorAppRegistration.ps1` (already-expired secrets still present — not a
  hard failure, a hygiene nudge). Updated `README.md` (Step 2 code block, §11, §12 reference 22),
  `design.md` (§4 component table row, §6 new key-decision row), and `rollback.md` (Stage 3 now
  offers secret-only revocation via the new script as an alternative to full app deletion). Added
  a reviews.md addendum (mini four-lens pass on the new capability only — Pass, no Fix/Fail): Red
  Team confirmed the default mode can't break the live integration and no secret plaintext is
  ever handled; Blue Team confirmed the cleanup gap is now caught by the validate script's new
  WARN, not just fixable; CISO confirmed near-zero incremental cost; Microsoft Product Owner
  confirmed the cmdlet/REST grounding above.
- [x] **`departing-employee-data-theft` — script the HR-connector Entra app registration** —
  commit `12d1932` — 2026-09-09 — resolved the follow-up asking whether app-registration
  creation could be scripted instead of left as a manual Entra admin center task. Grounded via
  the Microsoft Learn MCP server (available this run, contrary to this task's stored
  instructions) rather than WebFetch, which is proxy-blocked for `learn.microsoft.com` in this
  environment: `import-hr-data` Step 2 needs only a plain, permission-free app registration, so
  no HR-connector-specific cmdlet is required — generic `Microsoft.Graph.Applications` cmdlets
  cover it completely. Added `deploy/Register-HrConnectorApp.ps1` (idempotent by display-name
  lookup, `-WhatIf`-capable, `-RotateSecret` for the README-recommended ~90-day rotation
  cadence; deliberately grants the created app **no** Microsoft Graph API permission) and
  `validate/Test-HrConnectorAppRegistration.ps1` (existence, service principal, unexpired
  secret, and — the load-bearing check — that no permission has been granted). Updated
  `README.md` (§3, Step 2, §7, §11, §12 references), `design.md` (§2, §4, §6), `rollback.md`
  (scripted equivalent for Stage 3), and added a reviews.md addendum (mini four-lens pass, all
  Pass, no Fix/Fail). Added `docs/rbac-model.md` §11 "Microsoft Entra app registration RBAC — a
  seventh system" (grounded: self-service app registration is on by default; **Application
  Developer** is the narrowest role if it's been disabled, ahead of the broader **Cloud
  Application Administrator**/**Application Administrator**), renumbering the old §11 ("How
  scenarios should cite RBAC") to §12 and updating its checklist item 1 — verified no other file
  in the repo cross-referenced the old §11 by number. All cmdlets (`New-MgApplication`,
  `Get-MgApplication`, `New-MgServicePrincipal`, `Add-MgApplicationPassword`,
  `Remove-MgApplication`, `Remove-MgServicePrincipal`) independently verified against their own
  Microsoft Learn reference pages, including the easy-to-get-wrong detail that
  `Add-MgApplicationPassword -ApplicationId` takes the object ID (aliased `ObjectId`), not the
  `AppId`. Also discovered and fixed, in the same commit: this session's `main` branch was
  detached from `origin/main` at session start with 34 prior fragments' commits sitting
  unpushed on a detached HEAD from an earlier run in this same session — fast-forwarded and
  confirmed already in sync with `origin/main` (no data loss; documented here per §6 discipline
  since it affected repo state before this fragment started, even though no separate push was
  needed).
- [x] **`auto-label-eu-personal-data-sharepoint` — full per-country checksum/confidence table for
  both opt-in travel-document bundles** — commit `b0012e0` — 2026-09-09 — closed the
  `PROGRESS.md` follow-up asking for the same per-country grounding depth already built for the
  default "EU national identification number" bundle. Fetched all 26 "EU passport number" and all
  28 "EU driver's license number" member entity-definition pages directly from Microsoft Learn (54
  pages total) and tabled Format/Checksum/Confidence for each in `design.md` §4. Headline finding:
  only **2 of 26 passport-bundle entities (8%)** are checksum-validated (Germany, Poland) and only
  **3 of 28 driver's-license-bundle entities (11%)** are (Germany, Spain, U.K.) — versus 73% for
  the default national-ID bundle; the driver's-license bundle additionally caps at Medium (75)
  confidence for 25 of its 28 members (no High-confidence tier exists for its non-checksum
  countries). `README.md` §8/§11 updated with the numeric finding; the Exchange sibling
  (`auto-label-eu-personal-data-exchange/README.md` §11 and `design.md` §5) updated from "not
  tabled" to reference the now-built table rather than duplicate it. `reviews.md` round 3
  four-lens review added (all four lenses Pass — this round closes a previously-disclosed gap
  rather than introducing new risk). No new VERIFY items opened; the existing driver's-license
  apostrophe-casing VERIFY and byte-exact-casing VERIFY are unchanged.
- [x] **`auto-label-eu-personal-data-exchange` — port `-IncludeTravelDocumentSits` for parity with
  the SharePoint/OneDrive EU sibling** — commit `9302c57` — 2026-09-09 — added the same opt-in
  switch to `deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1` and `validate/
  Test-EuPersonalDataAutoLabelExchangePolicy.ps1`, appending `EU passport number` and `EU driver's
  license number` to whatever `-SensitiveInfoTypeName` set is already in effect, so the Exchange
  channel isn't left one switch behind its file-scoped sibling. Both bundle memberships (25-state
  EU passport bundle + combined "U.S./U.K. passport number" entity; 27-state + standalone U.K. EU
  driver's-license bundle) re-fetched directly from Microsoft Learn during this fragment and
  confirmed unchanged from the sibling's original 2026-09-09 grounding — no drift. `README.md`
  §5/§6/§7/§11 and `design.md` §5/§7/References updated; `reviews.md` round 2 four-lens review
  added (all four lenses Pass — the gotcha was already disclosed by the ported switch, and two
  Exchange-specific angles — encryption-side-effect interaction, cross-scenario SIT-list drift —
  were checked and confirmed not to be new risks). No new VERIFY items opened; the existing
  driver's-license apostrophe-casing VERIFY (already tracked for this scenario) now explicitly
  covers the ported name too.
- [x] **`auto-label-eu-personal-data-sharepoint` — opt-in travel-document SIT bundle
  (`-IncludeTravelDocumentSits`)** — commit `6db12ca` — 2026-09-09 — added the switch to
  `deploy/New-EuPersonalDataAutoLabelPolicy.ps1` and `validate/Test-EuPersonalDataAutoLabelPolicy.ps1`,
  appending `EU passport number` and `EU driver's license number` to whatever
  `-SensitiveInfoTypeName` set is already in effect. Grounding pass (fetching both bundles' own
  Microsoft Learn index pages directly) found the "EU passport number" bundle has no standalone
  U.K. entity — U.K. coverage is merged into a single "U.S./U.K. passport number" entity — and that
  the three EU-wide bundles this scenario references don't share identical member-state coverage.
  Both facts documented in `design.md` §4 (new membership tables) and `README.md` §6/§11, with a
  `reviews.md` round 2 four-lens review (2 Red Team findings, both resolved; Blue/CISO/Product
  Owner all Pass). Three follow-ups recorded above (port to the Exchange sibling; full per-country
  checksum table for the two new bundles; the driver's-license apostrophe-casing VERIFY).
- [x] **EU national ID bundle — full 26-country checksum-strength reference table** — commit
  `8243578` — 2026-09-09 — `auto-label-eu-personal-data-sharepoint/design.md` §4 now tables all 26
  members of the "EU national identification number" bundle (Austria through U.K.), each grounded
  directly against its own Microsoft Learn entity-definition page: 19 checksum-validated, 7
  pattern-only (Austria, Croatia, Cyprus, France, Greece, Malta, U.K.), with Germany's checksum
  scoped to its post-2010 format only. Resolves the Red Team finding in that scenario's `reviews.md`
  (finding 1), which the original build had only backed with two representative examples. `README.md`
  §8/§11 in both the SharePoint/OneDrive and Exchange EU-personal-data siblings updated to cite the
  exact counts and the new table instead of "several others documented as pattern-only." 26 new
  citations added to `design.md`'s reference list.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`**
  — commit `5410ea0` — 2026-09-09 — extends
  `defender-device-control-usb-allowlist-macos-portable-device-coverage`'s `serialNumber`-only Apple
  and Portable device allowlists with `vendorId`/`productId` compound matching, the same RFC 4122
  §4.3 UUIDv5 deterministic-sub-group + `groupId`-clause technique
  `defender-device-control-usb-allowlist-macos-vendor-product-matching` already proved once for
  removable media — applied independently to both families in one fragment, with a family tag folded
  into the hash input so the two families' sub-groups can never collide. Both new Learn/GitHub facts
  (the current Query `any`/`or` synonymy; confirmation that no published sample pairs `vendorId`/
  `productId` with `apple_devices`/`portable_devices`) were re-fetched directly during this build, not
  carried over unverified. Requires each family's Approved group to already have ≥1 `serialNumber`
  device configured — deliberately does not build that group/its Allow rule from a
  zero-`serialNumber` starting state (tracked as a follow-up above) — and inherits a more severe
  version of the Bluetooth sibling fragment's own disclosed cross-fragment ordering hazard against
  `Add-MacPortableDeviceCoverage.ps1`, disclosed and detected (not silently engineered around) the
  same way. Four-lens review caught and fixed one real defect before closing: an unvalidated
  `query.$type` pass-through on the Approved group that could have silently written a corrupted or
  `null` value into a live Intune policy.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching/`**
  — commit `ed22e8a` — 2026-09-08 — the JAMF-managed sibling of
  `defender-device-control-usb-allowlist-macos-vendor-product-matching` (Intune), closing the same
  vendorId/productId compound-matching gap for JAMF-managed macOS fleets. Because JAMF's device
  control deployment has no documented API (the base JAMF scenario's own already-disclosed gap),
  this fragment is a **superset generator** rather than an incremental patcher: one script reads a
  combined config (`approvedDevices` + `vendorProductDevices`) and regenerates the complete policy
  JSON in one artifact — a materially simpler idempotency model than the Intune sibling's live-object
  diff/reconcile, since JAMF's own "regenerate whole, paste whole" mechanism has no live state to
  diff against. Reuses the Intune sibling's exact deterministic RFC 4122 §4.3 UUIDv5 scheme, fixed
  namespace constant, and hash-input format verbatim (not re-derived) so the identical
  `vendorId`+`productId` pair produces the identical sub-group id on both deployment paths — the
  concrete mechanism for "one policy identity across a hybrid Intune+JAMF fleet." Output is
  byte-identical to the base JAMF scenario's own script when `vendorProductDevices` is empty (a
  strict superset, not a divergent reimplementation), and the deploy script is designed to supersede
  (not run alongside) the base scenario's `New-JamfDeviceControlPolicyJson.ps1` once vendor/product
  matching is needed. Re-grounded the `groupId`/`vendorId`/`productId` clause semantics and the
  JAMF-has-no-documented-API finding directly against Microsoft Learn during this build (word-for-
  word match with the earlier builds' citations) rather than assuming they still held. Four-lens
  review carried forward the Intune sibling's own inherited VERIFY (no worked Microsoft example pairs
  a `groupId` clause with more than one sibling sub-group in one query) and the base JAMF scenario's
  own inherited VERIFY (no documented JAMF Pro API) rather than re-resolving either by guessing; no
  new VERIFY introduced. This closes the `PROGRESS.md` follow-up item whose original "deferred for
  the same unverified-dynamic-GUID-sub-group reason" blocker was actually resolved when the Intune
  sibling itself shipped with an independently-verified (Python `uuid.uuid5()`) UUID scheme, not a
  pilot-tenant dependency.
- [x] **`scenarios/information-protection/auto-label-eu-personal-data-sharepoint/`** — commit
  `a725941` — 2026-09-08 — the EU/UK-region sibling of `auto-label-confidential-sharepoint/`,
  resolving that scenario's own deferred "localize the SIT selection by jurisdiction" follow-up.
  Same auto-labeling policy family and staged-rollout/override model, re-pointed at Microsoft's
  built-in EU-wide bundle SITs (EU national identification number, EU Social Security Number
  (SSN) or Equivalent ID, EU debit card number — grounded via the Microsoft Learn MCP tool, which
  was available and used directly despite this run's initial instructions stating it would not
  be) instead of U.S. SSN + Credit Card Number. Ships a genuine design differentiator beyond a
  copy-paste: `-SensitiveInfoTypeName` is a real deploy-script parameter (resolved against
  `Get-DlpSensitiveInformationType` at runtime, failing clearly on a near-miss rather than
  silently deploying a zero-match rule), letting a buyer narrow from the full 26-country default
  bundle down to only the member states they actually operate in for tighter false-positive
  control. Four-lens review surfaced and closed: checksum-strength variance across the EU
  national-ID bundle (documented, plus a new per-country-match-distribution KPI), an
  unconfirmed `Get-AutoSensitivityLabelRule` read-back property-casing assumption in the
  validation script (fixed defensively), and the "EU" bundle name's inclusion of the
  (non-EU-member, post-Brexit) U.K. NINO entity (documented). Two VERIFY items and one Exchange-
  companion follow-up carried to TODO rather than guessed at — see "Follow-ups discovered while
  building the EU/UK personal data auto-labeling scenario" above.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/`** —
  commit `f0907e1` — 2026-09-08 — extends `defender-device-control-usb-allowlist-macos`'s
  `serialNumber`-only `ApprovedBackupDrives` group with vendorId+productId compound matching, for
  approved drives with no readable serial number. Closes the gap that scenario's own `design.md` §5
  deliberately deferred: macOS's schema can only AND vendorId+productId via a per-device sub-group
  referenced by a `groupId` clause, which needs a stable id per config-file entry — resolved here
  with a deterministic RFC 4122 §4.3 version-5 (SHA-1) UUID keyed on `vendorId:productId` (not
  `label`, so a cosmetic rename never orphans a group), independently cross-checked against Python's
  `uuid.uuid5()` reference implementation for the same input during the build. No new Intune profile
  and no new/edited rule — both of the parent's existing rules already key off `ApprovedBackupDrives`'
  group id, so a device newly matched via either mechanism is automatically covered. Supports any
  number of devices (the Bluetooth sibling fragment capped at one because it lacked this id scheme).
  `groupId`/`vendorId`/`productId` clause syntax and the "group must be defined before the clause"
  ordering rule grounded directly against Microsoft's Device Control for macOS Clause reference table
  (direct fetch); the per-device AND-clause shape cross-checked against two raw GitHub sample
  policies (`deny_all_bluetooth_devices_except_samsung.json`,
  `deny_removable_media_except_kingston.json`) fetched during the build. Four-lens review caught and
  fixed two real defects before closing: a vendorId+productId pair collision that would have produced
  two policy groups sharing one id, and a PowerShell empty-array-coercion bug
  (`@($cfg.vendorProductDevices)` on an omitted config key) that misfired the validation error
  message. One VERIFY carried forward, not resolved by guessing: no Microsoft worked sample pairs a
  `groupId` clause with more than one sibling sub-group inside one query, so the N-devices-in-one-OR-
  query composition is this repo's own application of the documented primitive, not itself a directly
  worked example (`README.md` §11).
- [x] **`scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/`** — commit `0a3e752` — 2026-09-08 — custom, PII-only Data Map
  scan rule set for Azure SQL Database, extending `scan-azure-sql-and-classify`. Closes that
  scenario's carried-forward VERIFY ("the exact REST JSON body for the 'Scan Rulesets - Create Or
  Update' operation was not independently confirmed") via a direct fetch of the canonical **Scan
  Rulesets - Create Or Replace**/**- Get** Microsoft Learn REST reference pages (not reconstructed
  from adjacent evidence). Full deliverable: `README.md` (12-section skeleton), `design.md` (6
  design goals, including deriving the ~200-entry exclusion list live from the tenant's own Types
  API — `GET .../types/typedefs?type=CLASSIFICATION` — rather than a hard-coded snapshot, since the
  `data-map-classification-supported-list` page turned out to list classifications by
  human-readable name only, no exact `MICROSOFT.*` identifiers anywhere on it),
  `deploy/New-PiiOnlyScanRuleset.ps1` (idempotent, `-WhatIf`-capable; GETs the tenant's live
  classification defs, computes the exclusion list, creates/updates the Custom ruleset, then GETs
  and reconciles the existing scan onto it preserving every other scan property),
  `deploy/Remove-PiiOnlyScanRuleset.ps1` (staged rollback: revert scan to System ruleset, then
  optionally delete the custom ruleset), `validate/Test-PiiOnlyScanRuleset.ps1`, `rollback.md`, and
  `reviews.md` (four-lens review — Red Team flagged a scan-kind-mismatch risk from a
  `-ScanName`/`-DataSourceName` typo and a silent-clobber risk on the account-wide ruleset object
  when two teams share a default name, both fixed with new guard checks in the deploy script; Blue
  Team flagged missing detectability guidance for a classification-scope-narrowing change, resolved
  by grounding and citing the Management-category "Scan rule set: Create/Update/Delete" audit event
  and the `PurviewDataMapOperation` Graph audit record type; CISO and Product Owner both passed
  without required changes — no Fail). Three sibling-source-type follow-ups and one pagination
  VERIFY opened (see "Follow-ups discovered while building the Data Map PII-only scan rule set
  (Azure SQL Database) scenario" above).
- [x] **`scenarios/adaptive-protection/conditional-access-insider-risk-block/`** — Conditional
  Access "Insider Risk" condition scenario, deferred from `dynamic-risk-dlp-enforcement` as its
  own follow-up fragment (different admin surface — Microsoft Entra, not Purview/EXO — with its
  own Entra ID P2 license prerequisite). Full deliverable: `README.md` (12-section skeleton),
  `design.md` (including a §8 correction to the DLP sibling's now-stale "still preview" claim —
  this build's fresh grounding pass confirmed the integration is GA: no preview label on
  Microsoft's current "Block access for users with elevated insider risk" guide or the Graph v1.0
  `conditionalAccessConditionSet.insiderRiskLevels` resource property, independent reporting
  places GA at June 2024), `deploy/New-InsiderRiskConditionalAccessPolicy.ps1` (idempotent,
  `-WhatIf`-capable, `-Mode ReportOnly|Enabled|Disabled`, Graph
  `New-/Update-MgIdentityConditionalAccessPolicy`), `deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1`
  (staged rollback: disable / step-back-to-Report-only / `-Purge`),
  `validate/Test-InsiderRiskConditionalAccessPolicy.ps1`, `rollback.md`, and `reviews.md`
  (four-lens review — Red Team flagged an existing-session/CAE bypass window and a legacy-
  authentication gap, Blue Team flagged an undocumented second propagation delay distinct from
  Adaptive Protection's 36-hour window, CISO flagged the sign-in-block's larger business-
  continuity impact needing service-desk readiness alongside HR/Legal coordination, Product Owner
  flagged the DLP sibling's stale preview claim — all four Fix items resolved in place, no Fail).
  Also backported: `docs/rbac-model.md` new §10 (Microsoft Entra Conditional Access — a sixth RBAC
  system; old §10 renumbered to §11) and Sources; `docs/licensing-matrix.md` new §8 (Entra ID P2
  for the Conditional Access Insider Risk condition specifically, distinct from the broader P1/P2
  administrative-units prerequisite in §4) and Sources; `docs/automation-surface.md` surface 3's
  "Typical use" column extended to mention Conditional Access policies
  (`Microsoft.Graph.Identity.SignIns`). Grounded via direct fetch of the Microsoft Learn/Graph
  docs source repos (`MicrosoftDocs/entra-docs`, `microsoftgraph/microsoft-graph-docs-contrib`)
  since the Microsoft Learn MCP tool and direct `learn.microsoft.com` fetches were both
  unavailable in this run's network environment (egress-proxy-blocked) — cited URLs are the
  canonical `learn.microsoft.com` pages those source files render to. Five follow-ups opened
  (see "Follow-ups discovered while building the Conditional Access insider-risk-block scenario"
  above): the DLP-sibling preview-claim backport, a P2-partial-licensing-enforcement VERIFY, the
  `excludeGuestsOrExternalUsers` scripting gap, a Quick-Setup-collision-name VERIFY, and a
  softer-grant-control Moderate/Minor variant. — `8f261bb` — 2026-09-08
- [x] **Backport: Compliance Administrator/Compliance Data Administrator turn-on-policy
  prerequisite** — added to `scenarios/information-protection/auto-label-confidential-sharepoint/
  README.md` §3 (new prerequisites row + reference [15]), closing the doc-only gap the sibling
  Exchange scenario (`auto-label-confidential-exchange`) surfaced: turning on an auto-labeling
  policy after simulation requires Compliance Administrator or Compliance Data Administrator, not
  just Information Protection Admin, which is sufficient only to author/simulate. Citation:
  "Automatically apply a sensitivity label to Microsoft 365 data" §"Before you begin" —
  <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin> —
  the same source already cited by the sibling scenario, verified consistent, no new grounding
  pass needed. Doc-only scoped sub-task per `AGENTS.md` §6; no code/design/reviews changes
  required (no other file in the scenario referenced the stale role list). — `ad6e0d6` — 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/`** — adds a
  single `vendorId`+`productId`-matched approved-device exception to the
  `defender-device-control-usb-allowlist-macos-portable-device-coverage` fragment's unconditional
  `Deny-AllBluetoothDevices` rule, closing that fragment's deliberately deferred "Bluetooth is
  always default-deny, no exceptions" scope boundary. Full per-scenario deliverable: `README.md`,
  `design.md`, `deploy/Add-MacBluetoothDeviceAllowlist.ps1`, `deploy/
  Remove-MacBluetoothDeviceAllowlist.ps1`, `deploy/config/mac-bluetooth-device-allowlist.sample.json`,
  `validate/Test-MacBluetoothDeviceAllowlist.ps1`, `rollback.md`, `reviews.md`. Grounded by directly
  fetching Microsoft's own `deny_all_bluetooth_devices_except_samsung.json` sample policy (raw
  GitHub content) and the official "Device Control for macOS" reference tables (via the Microsoft
  Learn MCP tool, which — despite this run's own standing instruction that it is unavailable in this
  cloud environment — was reachable and used as the primary grounding source once `learn.microsoft.com`
  direct fetches were blocked by network egress policy; WebFetch against the GitHub raw-content host
  worked directly). Confirms directly from Microsoft's reference (not inferred) that `includeGroups`
  combines multiple groups with AND semantics and `excludeGroups` with OR semantics — the specific
  fact scoping this fragment to exactly one approved device in v1 (more would need a per-device
  sub-group + `groupId`-clause-nesting technique this repo's sibling scenarios already defer as
  unverified complexity). Deliberately diverges from Microsoft's own sample in one respect: adds an
  explicit `allow` entry (not just `auditAllow`) because this shared policy's inherited
  `settings.global.defaultEnforcement = "deny"` (fail-closed, set by the root parent scenario) means
  excluding a device from the deny rule alone is insufficient to grant it access, unlike the sample's
  own `defaultEnforcement = "allow"` policy. Four-lens review caught and fixed one genuine
  correctness defect before finalizing (not merely flagged): the initial draft's deploy/remove
  scripts replaced the shared `Deny-AllBluetoothDevices` rule's `excludeGroups` array wholesale,
  which would have silently clobbered any exclusion an admin added independently outside this
  fragment — both scripts now preserve every entry they don't own. Also strengthened the
  `vendorId`/`productId`-is-a-model-not-a-unit disclosure beyond the initial draft's framing (it is
  weaker than this control's `serialNumber`-based allowlists, not merely a variant of the same risk,
  since no forgery is even required to pass a second unit of the same model, and Bluetooth
  vendor/product identifiers are commonly software-configurable on inexpensive BLE dev hardware) and
  added an Operations & tuning KPI recommendation (allowed-device count/volume vs. physically-issued
  units) as the practical triage signal for that residual gap. Documents, rather than silently fixes
  by editing the already-reviewed prerequisite fragment's script, a genuine cross-fragment ordering
  hazard: re-running that fragment's own `-Force` reconcile after this one silently drops the
  exclusion; this fragment's own `validate` script detects and names that exact drift condition with
  its remediation, distinct from "never configured." — `6472287` — 2026-09-08
- [x] **`scenarios/data-lineage/custom-process-lineage/`** — models a custom nightly transform job
  as a custom Process-typed Microsoft Purview Data Map entity (`PurviewScenarioLibraryEtlProcess`,
  `superTypes: ["Process"]`) and links it into the lineage graph via `dataset_process_inputs`/
  `process_dataset_outputs` relationships, upgrading `end-to-end-lineage-validation`'s single
  unattributed `direct_lineage_dataset_dataset` edge into the full DataSet -> Process -> DataSet
  shape that scenario's own `design.md` §7 deliberately deferred. Fresh grounding pass found and
  directly confirmed the previously-missing custom-Process-entity-creation body (Microsoft's
  "Create and get lineage relationships using the REST API" tutorial, Example 1 + "Create New
  Custom Types"). Also confirmed a stronger idempotency pattern than the sibling scenario's own:
  `Entity - Bulk Create Or Update`'s reference page directly documents upsert-by-qualifiedName
  semantics, so the Process entity needs no separate existence check (unlike the type definition
  and the two relationships, whose duplicate-POST/recreate behavior remains unconfirmed and so use
  the sibling's existing existence-check idiom). Four-lens review raised two Fix findings, both
  resolved: (1) Red Team — the tenant-wide blast-radius risk of type-definition creation now stated
  explicitly in `README.md` §3 regardless of how the underlying permission-scope VERIFY resolves;
  (2) Blue Team/Product Owner — `validate/Test-ProcessLineage.ps1` originally only checked whether
  the custom type *existed*, not whether its live attribute schema still matched the definition
  file; added a dedicated schema-drift check (detection-only, not auto-remediating, consistent with
  this repo's no-unconfirmed-update-body discipline). `docs/automation-surface.md` §4's lineage
  routing-table row split in two and extended with the newly-exercised Entity/Type operation
  groups. — `66faec0` — 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/`** —
  extends the macOS Defender for Endpoint device control USB allowlist scenario to also cover the
  `apple_devices`, `portable_devices`, and `bluetooth_devices` `primaryId` families, the direct
  macOS analog of the Windows WPD-coverage sibling. Full per-scenario deliverable: `README.md`,
  `design.md`, `deploy/Add-MacPortableDeviceCoverage.ps1`, `deploy/
  Remove-MacPortableDeviceCoverage.ps1`, `deploy/config/mac-portable-device-coverage.sample.json`,
  `validate/Test-MacPortableDeviceCoverage.ps1`, `rollback.md`, `reviews.md`. Widens the parent's
  shared `.mobileconfig` payload in place (macOS device control has one `com.microsoft.wdav`-typed
  policy document per Mac, not one profile per family, confirmed via Microsoft's own reference) with
  three new `settings.features` enables, three catch-all groups, two optional `serialNumber`-matched
  allowlists (Apple/Portable), and five deny/allow rule pairs — grounded directly against Microsoft
  Learn's "Device Control for macOS" reference and cross-checked against four of Microsoft's own
  published GitHub sample policy JSON files, which also resolved a genuine documentation ambiguity
  (the Learn page's entry-`$type` table renders `PortableDevice` capitalized in one cell,
  inconsistent with its own Access Types table and every worked sample — resolved as a rendering
  defect, not a second valid casing, on the strength of the worked examples). Bluetooth ships
  default-deny-only in v1 (no allowlist) — a deliberate, disclosed scope decision, since Microsoft's
  own worked Bluetooth exception sample uses a structurally different `vendorId`+`productId`
  single-device match rather than the OR'd-`serialNumber` shape used for the other two families.
  Four-lens review caught and fixed one genuine grounding defect before finalizing: an initial-draft
  Advanced Hunting query referenced a fabricated `PolicyName` field, corrected to the real,
  Microsoft-confirmed `RemovableStoragePolicy` field. Since the underlying policy JSON schema is
  identical across the Intune and JAMF macOS deployment paths, this build also closes the equivalent
  JAMF-sibling follow-up without a second build. — `7516333` — 2026-09-08
- [x] **`docs/automation-surface.md` §4 — Unified Catalog + Data Map lineage routing-table
  fragment** — closed three separately-tracked doc-extension follow-ups from the Unified Catalog
  business-glossary, manage-data-products, and Data Lineage end-to-end-lineage-validation builds
  by backporting their already-confirmed REST facts into the cross-cutting automation-surface
  reference, without any new external grounding (every fact was already direct-fetched and cited
  in the scenarios that discovered it). Replaced the single "evolving surface — VERIFY exact
  endpoint names per release" Unified Catalog row with three precise rows: **Data Map — custom
  lineage relationships (Atlas v2)** (`Relationship`/`Lineage`/`Entity` operation groups,
  `datamap/api/atlas/v2/...`, API version `2023-09-01`), **Unified Catalog — glossary (business
  domains, terms)** (`Business Domain`/`Terms` operation groups, `datagovernance/catalog/...`, API
  version `2026-03-20-preview`), and **Unified Catalog — data products, data assets** (`Data
  Products`/`Data Assets` operation groups, same API version, carrying forward
  `manage-data-products`'s own open relationship-body-shape VERIFY rather than resolving it by
  guessing). Also added the surface-4 description note for lineage in §1's five-surfaces table and
  eight new Learn citations to the Sources section (four Atlas v2 REST references, four Unified
  Catalog REST references). Corrected one stale, already-completed backlog item in passing: the
  Azure SQL Managed Instance/Synapse/on-premises-SQL-Server "sibling scan scenarios" item (left
  unchecked after all three were actually built in earlier turns) is now marked done and
  cross-referenced. — `0435984` — 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/`** — the JAMF-managed
  deployment path for macOS Defender for Endpoint device control, closing the follow-up the Intune-
  managed macOS sibling's own build logged. Full per-scenario deliverable: `README.md`, `design.md`,
  `deploy/New-JamfDeviceControlPolicyJson.ps1`, `deploy/config/
  mac-device-control-usb-allowlist-jamf.sample.json`, `validate/
  Test-JamfDeviceControlPolicyJson.ps1`, `rollback.md`, `reviews.md`. Byte-identical policy content
  (same `groups`/`rules`/`settings` JSON, same fixed group/rule GUIDs) to the Intune sibling, so a
  hybrid Intune+JAMF Mac fleet enforces one identical policy identity — but a materially different
  deploy shape: Microsoft's own `mac-device-control-jamf` procedure documents JSON authoring and
  local `mdatp device-control policy validate` as scriptable (both automated by this scenario's
  deploy script), but has **no documented API** for the JAMF Pro "Device Control Policy"
  custom-schema property or the `DC_in_dlp` preferences-schema toggle — both stay precise, numbered
  manual JAMF-console steps in `README.md` §5 rather than a fabricated API call, consistent with
  this repo's grounding standard and its own "Removable USB device groups" precedent. `developer.
  jamf.com` was unreachable from this build's network environment, so a JAMF Pro API for this
  property type could not be independently ruled in or out either way — recorded as a fresh VERIFY
  rather than guessed. Grounded via the Microsoft Learn MCP tool (`microsoft_docs_search`/
  `microsoft_docs_fetch` — reachable and used for every citation, the same tool this session's own
  scheduled-task instructions incorrectly claimed was unavailable in this environment) across four
  pages: `mac-device-control-jamf` (the four-step JAMF procedure itself), `mac-device-control-
  overview` (shared policy schema, the `com.microsoft.dlp.daemon` Full Disk Access requirement, and
  the separate `DC_in_dlp` toggle), `mac-jamfpro-policies` (Preference Domain must be exactly
  `com.microsoft.wdav`; the Full Disk Access PPPC/`fulldisk.mobileconfig` procedure), and the
  Purview-specific `device-onboarding-offboarding-macos-jamfpro-mde` (confirming the same
  `fulldisk.mobileconfig`/`schema.json` update procedure applies to the DLP/device-control daemon,
  not just the general EDR sensor). Four-lens review (`reviews.md`): Red Team found 3 (the
  manual-JAMF-console-only deployment path is itself an undetectable-drift/insider-bypass surface —
  newly identified and disclosed as the scenario's primary, most prominent limitation, not buried;
  2 gaps confirmed already correctly shared with the Intune sibling); Blue Team found 3 (no way to
  confirm the console paste step was performed or performed correctly — disclosed with a
  compensating manual-recheck process, not fabricated away; no audit trail beyond JAMF Pro's own
  profile history — disclosed as a real change-management cost; runbook/KPI/alerting confirmed
  correctly shared); CISO found 1 (initial board-narrative wording implied audit parity with the
  Intune sibling that doesn't hold — reworded to state the manual change-management story plainly);
  Product Owner found 5 (1 clarified the Full Disk Access prerequisite uses the same
  `fulldisk.mobileconfig` mechanism as general MDE-on-JAMF setup rather than implying a second
  profile type, rest confirmed correct). Four new follow-ups recorded above (a JAMF Pro API VERIFY,
  a revisit-once-resolved item, and the vendor/product-matching and portable-device-coverage gaps
  already tracked for the Intune sibling, cross-referenced rather than duplicated) rather than
  silently dropped. Commit: `8cec510`. Date: 2026-09-08.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos/`** — the macOS sibling of
  `scenarios/dlp/defender-device-control-usb-allowlist/`, closing the follow-up that Windows-only
  scenario's own build logged. Full per-scenario deliverable: `README.md`, `design.md`, `deploy/
  New-MacDeviceControlUsbAllowlistPolicy.ps1`, `deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1`,
  `deploy/config/mac-device-control-usb-allowlist.sample.json`, `validate/
  Test-MacDeviceControlUsbAllowlistPolicy.ps1`, `rollback.md`, `reviews.md`. Same default-deny,
  named-allowlist, both-paths-audited shape as the Windows sibling, deployed as a
  `macOSCustomConfiguration` Microsoft Graph v1.0 object (a native, fully-documented type for
  macOS — a `.mobileconfig` payload containing the `DC_in_dlp` engine-enable flag plus an embedded
  JSON `groups`/`rules`/`settings` device-control policy; no OMA-URI-style workaround needed, unlike
  the Windows sibling's own "no confirmed native profile schema" tradeoff). Matches approved
  devices by `serialNumber` only (deliberately not `vendorId`/`productId` — macOS's schema requires
  a per-device sub-group to AND a vendor+product pair, a materially more complex idempotency model
  than this fragment's four-fixed-GUID design; deferred as a follow-up rather than built with an
  unstable per-entry GUID scheme). Grounded via the Microsoft Learn MCP tool (`microsoft_docs_search`/
  `microsoft_docs_fetch`, contrary to this session's own instructions claiming that tool is
  unavailable — it was in fact reachable and used for every product-fact citation below) plus one
  direct fetch of Microsoft's own published `demo.mobileconfig` (via WebFetch against the raw GitHub
  URL, since Microsoft's own docs point to it as the authoritative worked example) to confirm the
  exact plist key path (`PayloadContent[0].dlp.features` / `PayloadContent[0].deviceControl.policy`,
  `PayloadType`/`PayloadIdentifier` = `com.microsoft.wdav`) byte-for-byte rather than guessing it
  from the docs' prose description alone. Four-lens review (`reviews.md`): Red Team found 3
  (Portable/Apple/Bluetooth device invisibility — the macOS analog of the Windows WPD gap, closed
  with documentation; `serialNumber`-only scope boundary — confirmed already honestly framed;
  possible conflict with a pre-existing separate `com.microsoft.wdav` profile — closed with a new
  VERIFY, not resolved by guessing); Blue Team found 4 (no remote Full Disk Access check at scale —
  closed as an acknowledged scope boundary; validation script's regex-based JSON extraction —
  confirmed an accepted trade-off; incident-response runbook and alert-routing citations — confirmed
  already correct); CISO passed with no findings; Product Owner found 5, all closed by
  clarifying documentation (no incorrect facts). Cross-linked back into the Windows sibling's
  `README.md` §3 (Supported OS row) and `design.md` §8 (non-goals) in place of "a natural,
  separately-scoped follow-up." Five new follow-ups recorded above (vendorId/productId matching,
  Portable/Apple/Bluetooth device coverage, two VERIFYs, JAMF deployment path) rather than silently
  dropped. Commit: `e36d988`. Date: 2026-09-05.
- [x] **Upgrade `scenarios/dlp/endpoint-dlp-usb-block/`'s `EndpointDlpRestrictions` grounding from
  a Tech Community blog to Microsoft's official cmdlet reference, and add an `-ITExceptionAction`
  opt-in** — a scoped sub-task (not a new scenario), closing the open VERIFY carried since that
  scenario's initial build and the backport this run's own re-verification pass deferred. Fetched
  both the `New-DlpComplianceRule` and `Set-DlpComplianceRule` Microsoft Learn reference pages in
  full (both reachable this run) and confirmed, verbatim and identically on both pages: "The
  available values for `<Value>` are: Audit, Block, Ignore, or Warn," with a worked example
  `@{"Setting"="RemovableMedia"; "Value"="Block";}` matching this scenario's Rule 0 exactly, plus
  confirmed `Setting` names `Print`/`CopyPaste`/`ScreenCapture`/`RemovableMedia`/`NetworkShare`/
  `UnallowedApps`, and the requirement that `Block`/`Warn` values need `-NotifyUser`. Changes:
  `README.md` (§6 config table, §11 limitations, §12 references — inserted `Set-DlpComplianceRule`
  as its own citation, renumbering 10→18), `design.md` (§6 key-decisions row, §7 non-goals),
  `deploy/New-EndpointDlpUsbBlockPolicy.ps1` (rewritten `.NOTES`; new `-ITExceptionAction`
  `Audit`/`Warn` parameter, default `Audit` — no behavior change for an existing deployment; sets
  `-NotifyUser`/`-NotifyPolicyTipCustomText` automatically only when `Warn` is chosen, per the
  official `-NotifyUser` requirement), `validate/Test-EndpointDlpUsbBlockPolicy.ps1` (new
  `-ExpectedITExceptionAction` parameter; checks the rule's restriction value matches it, not just
  "not Block"; checks `NotifyUser` is set when `Warn` is expected), and the reference policy JSON's
  `$comment`. Four-lens addendum in `reviews.md` (not a full re-review — an addendum to the
  existing one): Product Owner's original finding #1 closed (Pass, was Fix); Red Team mini-check on
  the new `Warn` option found no new bypass (Pass) since `Warn` is strictly not weaker than `Audit`
  and the default is unchanged. Two new, narrower VERIFY items recorded above rather than resolved
  by guessing: whether `Warn` is in fact the portal's "Block with override" option (grouped with
  `Block` via the shared `-NotifyUser` requirement, but not stated by name in Microsoft's
  reference), and whether `Set-DlpComplianceRule -Force` clears or leaves stale a `NotifyUser`/
  `NotifyPolicyTipCustomText` value when switching `-ITExceptionAction` from `Warn` back to
  `Audit` (undocumented either way). Grounded via the Microsoft Learn MCP tool (`microsoft_docs_fetch`
  against both cmdlet reference pages, fetched in full this run). Commit: `1321bcf`. Date: 2026-09-05.
- [x] **Extend `docs/rbac-model.md` with a new §9: Microsoft Intune RBAC — a fifth system, for
  Intune-deployed scenarios** — a scoped cross-cutting-doc fragment (not a new scenario), closing
  the follow-up logged during the `defender-device-control-usb-allowlist` build: that scenario and
  its `-wpd-coverage` sibling are the first two fragments in this library governed by Intune's own
  RBAC model instead of a Purview role group, and the cross-cutting RBAC doc didn't cover Intune at
  all. New §9 documents: the built-in **Policy and Profile Manager** role (confirmed as the
  narrowest built-in role whose permission set includes Device configurations Create/Read/Update/
  Delete/Assign — what both device-control scenarios' Custom OMA-URI profiles need), the other
  built-in Intune roles for context, the documented Microsoft Entra-role-to-Intune-access subset
  table (Global Administrator/Intune Administrator = read/write; Security Administrator/Operator/
  Reader, Compliance Administrator/Compliance Data Administrator, Global Reader, Helpdesk
  Administrator, Reports Reader = various read-only or audit-only; Conditional Access
  Administrator = none), and the exact Microsoft Graph application permission
  (`DeviceManagementConfiguration.ReadWrite.All`, admin-consent required) both scenarios'
  app-only deploy scripts need — confirmed directly from Microsoft Graph's own
  `Update-MgDeviceManagement`/`Get-MgDeviceManagementDeviceConfiguration` PowerShell reference
  pages rather than assumed from the permission's name alone. Old §9 ("How scenarios should cite
  RBAC") renumbered to §10, with a new point 1 caveat for Intune-deployed scenarios. Cross-linked
  back into `defender-device-control-usb-allowlist/README.md`'s Prerequisites table in place of the
  "not yet cross-referenced" note. No VERIFY items needed — every fact came from an official
  Microsoft Learn/Graph reference page fetched or searched this run, not recalled from memory.
  Four-lens self-review (no dedicated `reviews.md` — a doc fragment, not a scenario folder, same
  precedent as the licensing-matrix Defender+Intune addition immediately below): Red Team — no new
  attack surface; correctly flags Global Administrator/Intune Administrator as over-privileged for
  routine use, consistent with least-privilege guidance elsewhere in this doc (Pass); Blue Team —
  n/a, a reference doc not an operational control (Pass); CISO — closes a real gap (a buyer's admin
  previously had no cross-cutting answer for "which Intune role deploys this control," only a
  scenario-local, admittedly-incomplete note) (Pass); Product Owner — every role/permission name
  and the Entra-subset table traced to an official Microsoft Learn/Graph page fetched this run
  (Pass). Grounded via the Microsoft Learn MCP tool: "Role-based access control (RBAC) with
  Microsoft Intune" (built-in roles list, full Entra-role-to-Intune-access table, the
  Global-Administrator/Intune-Administrator least-privilege caution); "Built-in role permissions
  for Microsoft Intune" (Policy and Profile Manager's exact permission table, confirming Device
  configurations Create/Read/Update/Delete/Assign); Microsoft Graph permissions reference and the
  `Update-MgDeviceManagement`/`Get-MgDeviceManagementDeviceConfiguration` PowerShell reference
  pages (confirming `DeviceManagementConfiguration.ReadWrite.All` as the exact application
  permission, with its sibling `.Read.All` and the unrelated `DeviceManagementServiceConfig.*`/
  `DeviceManagementApps.*` permission families correctly excluded). Commit: `9f30fb6`.
  Date: 2026-09-05.
- [x] **Extend `docs/licensing-matrix.md` with a new §7: Microsoft Defender for Endpoint + Intune
  (device-control scenarios)** — a scoped cross-cutting-doc fragment (not a new scenario), closing
  the follow-up logged during the `defender-device-control-usb-allowlist` build: that scenario and
  its `-wpd-coverage` sibling are the first two fragments in this library licensed on Defender for
  Endpoint + Intune rather than a Purview policy object, and the cross-cutting matrix didn't cover
  that product family yet. Added a 5-row table (device control itself, the Intune policy-authoring
  surface, the Intune-**enrollment**-vs-Defender-onboarding-only distinction, the anti-malware
  client version gate, and the Windows-only platform scope) plus a CISO-facing cost note: because
  Microsoft 365 E3 now bundles Defender for Endpoint **Plan 1** (which already includes device
  control — Plan 2 is not required), a plain-E3 tenant with no Purview E5 add-on can deploy both
  device-control scenarios today, a materially cheaper entry point than almost every other
  DLP/IRM scenario in this library. Cross-linked back into
  `defender-device-control-usb-allowlist/README.md` §3 in place of the "not yet covered" note.

  Grounded via the Microsoft Learn MCP tool (available this run, contrary to this run's own
  initial task instructions claiming it would not be), fetched/searched directly against: the
  Microsoft Defender service description (confirms device control ships in Defender for Endpoint
  **Plan 1**, alongside next-gen anti-malware/ASR/firewall/application control, and that Plan 1 is
  bundled in Microsoft 365 E3/A3/G3 while Plan 2 is bundled in E5/A5/G5); "Device control in
  Microsoft Defender for Endpoint" (the anti-malware client version gate — `4.18.2103.3`+ base,
  `4.18.2107`+ for Windows Portable Device coverage — and the no-server-support statement);
  "Manage endpoint security policies in Microsoft Defender for Endpoint" (the footnote confirming
  device control policies deployed via Intune apply **only** to Intune-**enrolled** devices, not
  to devices managed solely through Defender's agentless Security settings management — a genuine
  deployment trap not previously called out this explicitly in either scenario's docs); "Manage
  device security with endpoint security policies in Microsoft Intune" (Defender integration
  prerequisites, confirming Defender for Endpoint P1-or-greater as the licensing floor for the
  integration generally); and "Microsoft Intune licensing" (the three-plan structure — Plan 1 base
  service, Plan 2 additive, Intune Suite additive — confirming device configuration profiles, the
  mechanism both device-control scenarios deploy through, are core Plan 1 functionality with no
  Plan 2/Suite dependency). One genuinely new finding surfaced during this grounding pass and
  written into §7 rather than left implicit: the Intune-enrollment-vs-Defender-onboarding-only
  distinction is a real, previously-undocumented-in-this-library deployment gotcha, not merely a
  restatement of what `defender-device-control-usb-allowlist/README.md` §3 already said (that
  table listed Intune enrollment as a prerequisite but didn't state what happens if it's skipped —
  the policy silently doesn't apply). No VERIFY items needed — every fact in §7 came from an
  official Microsoft Learn service-description or product-documentation page with an unambiguous
  statement, not an inference. Four-lens self-review (no dedicated `reviews.md` — a doc fragment,
  not a scenario folder, consistent with this repo's established precedent for cross-cutting-doc
  fragments, e.g. the SharePoint Online Management Shell automation-surface addition): Red Team —
  no new attack surface; the enrollment-vs-onboarding gotcha is itself a defensive finding, not a
  risk introduced by this doc (Pass); Blue Team — n/a beyond the gotcha itself, which is actionable
  operational guidance (Pass); CISO — the E3-covers-both-scenarios cost note is genuinely
  decision-relevant, not filler (Pass); Product Owner — every claim traced to an official Microsoft
  Learn page fetched this run, not recalled from memory or copied from the flagging scenario's own
  unverified note (Pass). Commit: `f41f178`. Date: 2026-09-05.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage/`** — closes the
  confirmed Red Team finding in the parent `defender-device-control-usb-allowlist` scenario's own
  review: a device that enumerates as a **Windows Portable Device (WPD)** — most phones, tablets,
  and cameras in MTP/PTP mode — is completely invisible to a `SecuredDevicesConfiguration =
  RemovableMediaDevices`-scoped policy, not merely unrestricted (no block, no audit event). This
  fragment widens the parent's existing Intune device configuration object in place — from 7 to 11
  `omaSettings` entries — rather than standing up a second, competing policy object (`design.md`
  §3 explains why two objects would conflict on `SecuredDevicesConfiguration`, not layer): changes
  the scope string to the documented pipe-separated multi-value form
  `RemovableMediaDevices|WpdDevices`, and mirrors the parent's default-deny/named-allowlist/
  audited-both-paths shape with a new `ApprovedWpdDevices` group, an `AllWpdDevices` catch-all
  group, and an `Allow-ApprovedWpdDevices`/`Deny-AllOtherWpd` rule pair (identical `AccessMask=63`
  semantics — confirmed identical across `CdRomDevices`/`RemovableMediaDevices`/`WpdDevices`).
  Full deliverable per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/Add-WpdDeviceControlCoverage.ps1` (idempotent — refuses to run if the parent policy
  doesn't already exist, reconciles a partial/interrupted prior state rather than misreporting it
  as complete, `-WhatIf` throughout), `deploy/Remove-WpdDeviceControlCoverage.ps1` (surgical
  rollback of only the WPD delta, leaving the parent's `RemovableMediaDevices` coverage/assignment/
  object identity untouched), `deploy/config/wpd-device-control-coverage.sample.json`,
  `validate/Test-WpdDeviceControlCoverage.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix
  items resolved, no Fail — including a genuine idempotency-detection bug caught and fixed during
  the Blue Team review pass itself: the initial draft treated any one of the four expected WPD
  `omaSettings` nodes as proof the whole set was present, which could have left a partially-applied
  policy — e.g. a deny rule live with no matching approved-devices group — permanently
  unreconciled without an operator noticing and passing `-Force`).

  Grounded via the Microsoft Learn MCP tool this run (available and used, despite the run's own
  initial task instructions stating it would not be), fetched directly against official reference
  pages: "Device control policies" (the `PrimaryId` family list including `WpdDevices`, the full
  `DescriptorIdList` properties table, the "Understand mask access (Windows)" section confirming
  the identical `AccessMask` bit scheme applies to `CdRomDevices`/`RemovableMediaDevices`/
  `WpdDevices`, the Windows-Device-Manager-to-`FriendlyNameId` mapping, and the Intune reusable-
  settings-groups table showing only two device group *types* — Printer device and Removable
  storage, confirming no purpose-built portal authoring surface exists for WPD groups at all) and
  "Deploy and manage device control with Intune" (the `SecuredDevicesConfiguration` OMA-URI's
  documented pipe-separated multi-value syntax and its "must be all one word with no spaces"
  warning) and "Device control in Microsoft Defender for Endpoint" (WPD support added in anti-
  malware client `4.18.2107`+, a stricter prerequisite than the parent's base `4.18.2103.3`+; the
  "grant access for all entries associated with the physical device" guidance for devices that
  dual-enumerate as both a removable-media and a WPD entry; the disk-letter definition
  distinguishing the two families). One genuine, deliberately unresolved gap: this build's own
  grounding pass could **not** substantiate an earlier, unconfirmed `PROGRESS.md` note claiming
  "WPD groups support only `FriendlyNameId`/`PrimaryId` matching (no `SerialNumberId`/`VID_PID`)"
  — the general property-support table lists those properties for "Windows devices" without a
  per-`PrimaryId`-family breakdown, and no worked example was found confirming or excluding them
  for `WpdDevices`. Rather than repeat the stronger, unsubstantiated exclusion claim, this
  scenario states the gap as genuinely open in both directions (`README.md` §11, `design.md` §2/§6)
  and flags a Red-Team-confirmed, more serious finding instead: on most platforms a device's
  advertised name is user-editable, making the one confirmed matching property
  (`FriendlyNameId`) a spoofable identifier, not just a coarse one — mitigated by documented
  guidance (small, IT-managed approved population; non-default device names) rather than
  overclaimed as solved.
  Commit: `54d1007`. Date: 2026-09-05.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist/`** — a device-identity (not
  content-based) USB removable-storage control on **Microsoft Defender for Endpoint device
  control**, the companion this repo's `endpoint-dlp-usb-block/README.md` §11 flagged as needed
  for a buyer wanting "no unapproved USB devices, period": default-deny for all
  `RemovableMediaDevices`, one named `ApprovedBackupDrives` allowlist group matched by
  `SerialNumberId`/`VID_PID`, both the allow and deny paths audited (not a silent trust), deployed
  via a staged pilot-group-then-tenant-wide assignment (the equivalent of a "simulation mode" for
  a policy type with none). First scenario in this library built on Defender for Endpoint + Intune
  rather than a Purview policy object — deployed through Microsoft Graph
  (`windows10CustomConfiguration` Custom OMA-URI, `Invoke-MgGraphRequest`, automation surface 3)
  because no confirmed Graph schema exists yet for the native Intune "Device Control profile"
  template (`design.md` §4 explains the grounded reasoning for that choice). Full deliverable per
  `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`, `deploy/
  New-DeviceControlUsbAllowlistPolicy.ps1` (idempotent — fixed, source-controlled group/rule
  GUIDs so re-runs reconcile in place rather than accumulating orphans — `-WhatIf` throughout, a
  companion JSON config for the approved-device list and assignment target),
  `deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1` (staged unassign vs. `-Purge`),
  `validate/Test-DeviceControlUsbAllowlistPolicy.ps1`, `rollback.md`, `reviews.md` (four-lens, all
  Fix items resolved, no Fail — including a genuine Red Team finding that a device presenting as a
  Windows Portable Device, e.g. a phone in MTP mode, is completely invisible to this control, not
  merely unrestricted, since `SecuredDevicesConfiguration` scopes enforcement to
  `RemovableMediaDevices` only; documented as an explicit residual gap and tracked as a follow-up
  rather than silently left out). Every product fact grounded directly against Microsoft Learn
  (device control policy/group/rule/entry XML schema, OMA-URI paths, the `windows10CustomConfiguration`/
  `omaSetting*` Graph v1.0 resources, the `New-/Update-/Remove-MgDeviceManagementDeviceConfiguration`
  cmdlet references, and Defender for Endpoint Plan 1 licensing) — see `README.md` §12 for the full
  citation list; one VERIFY tagged rather than guessed (PATCH replace-vs-merge semantics for
  `omaSettings` — README.md §11).
  Commit: `0e572bf`. Date: 2026-09-05.
- [x] **`scenarios/dlp/exchange-pii-exfil-block/`** — a content-based (not label-conditioned)
  Microsoft Purview DLP policy that blocks or forces encryption on outbound Exchange Online email
  containing SSN/Credit Card Number addressed to external recipients, closing the Red-Team-flagged
  gap in `scenarios/information-protection/auto-label-confidential-exchange/README.md` §11 (that
  scenario's auto-labeling policy leaves external mail in cleartext by default). Full deliverable
  per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md` (including a new §3a
  justifying a named custom policy over Microsoft's overlapping built-in **U.S. Patriot Act**
  template), `deploy/New-ExchangePiiDlpPolicy.ps1` (idempotent, `-Action Block`/`Encrypt` mode
  switch, optional business-exception group with a logged block-with-justification override in
  Block mode, `-WhatIf` throughout, a runtime `Get-RMSTemplate` pre-flight check before Encrypt
  mode rather than trusting a hardcoded template name), `deploy/Remove-ExchangePiiDlpPolicy.ps1`,
  `validate/Test-ExchangePiiDlpPolicy.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix items
  resolved, no Fail — including two genuine Red Team findings: Encrypt mode's exception-group path
  is a silent, unlogged bypass rather than Block mode's logged override, and the default
  Encrypt-Only RMS template doesn't restrict what a legitimate recipient does after decrypting).
  Cross-linked back into `auto-label-confidential-exchange/README.md` §11 in place of the earlier
  "pair this scenario with a content-based Exchange DLP rule" placeholder note. Deployed under
  `scenarios/dlp/` rather than `scenarios/information-protection/` as this backlog item originally
  sketched — see the corresponding (now-closed) TODO entry above for why.

  Grounded via the Microsoft Learn MCP tool this run (available and used, despite the run's own
  initial task instructions stating it would not be), fetched directly against official reference
  pages: `New-`/`Set-`/`Remove-DlpComplianceRule` and `New-`/`Set-DlpCompliancePolicy` (confirmed
  `AccessScope`'s `InOrganization`/`NotInOrganization` values apply generically, not just to
  SharePoint/OneDrive/Teams; confirmed `EncryptRMSTemplate`/`RemoveRMSTemplate`/`BlockAccess`
  parameter shapes with a worked `BlockAccess` example for an SSN rule), `Get-RMSTemplate`
  reference, the "Data loss prevention Exchange conditions and actions reference" and "Data Loss
  Prevention policy reference" conceptual pages (confirmed the Exchange action table, halting vs.
  non-halting behavior, and the "Block only people outside your organization" bifurcation
  behavior), the Exchange "Bifurcation" reference page (per-recipient forking, independent DLP
  rule/incident-report evaluation per fork — directly grounds `design.md` §5), the Message
  Encryption FAQ and Microsoft Purview service description (confirmed `-Action Encrypt` needs no
  license beyond base E3/E5, a genuine cost advantage over this library's E5-only DLP scenarios),
  "How to disable the Encrypt-Only feature in Outlook" (confirms Encrypt-Only is a real ad-hoc
  template with no forward/print restriction), and "What the DLP policy templates include"
  (confirmed the built-in **U.S. Patriot Act** and **U.S. PII Data** templates' exact conditions/
  actions, grounding `design.md` §3a). One genuine gap flagged rather than resolved by guessing:
  Get-RMSTemplate's exact `Name` value for the auto-created Encrypt-Only template isn't published
  as a canonical string — the deploy script checks for it at runtime instead of assuming (see
  `README.md` §11 VERIFY).
  Commit: `899c984`. Date: 2026-09-04.
- [x] **`scenarios/audit/retention-policy-management/`** — the configuration counterpart to
  `scenarios/audit/premium-audit-investigation/`: creates and reconciles custom Microsoft Purview
  **audit log retention policies** (`New-`/`Set-`/`Get-`/`Remove-UnifiedAuditLogRetentionPolicy`,
  Security & Compliance PowerShell) as a version-controlled, idempotently-applied set, closing the
  gap where Audit (Premium)'s automatic one-year default only covers Entra ID/Exchange/OneDrive/
  SharePoint (Teams and every other workload fall back to 180 days unless a custom policy extends
  them). Full deliverable per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/New-AuditRetentionPolicy.ps1` (idempotent get-or-create-or-update reconciliation over a
  JSON policy-set config, `-WhatIf` throughout, full pre-flight validation before any write),
  `deploy/Remove-AuditRetentionPolicy.ps1`, `deploy/config/audit-retention-policies.sample.json`
  (three entries directly adapted from Microsoft's own worked examples), `validate/
  Test-AuditRetentionPolicy.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix items resolved,
  no Fail).

  Key grounding, all fetched via the Microsoft Learn MCP tool this run (available and used,
  despite the run's own initial task instructions stating it would not be) directly against the
  official `New-`/`Set-`/`Remove-`/`Get-UnifiedAuditLogRetentionPolicy` reference pages and
  "Manage audit log retention policies": (1) the PowerShell `-RetentionDuration` enum
  (`ThreeMonths`/`SixMonths`/`NineMonths`/`TwelveMonths`/`TenYears`) is narrower than the portal's
  nine-option duration picker (also offers `7 Days`/`30 Days`/`3 Years`/`5 Years`/`7 Years`) — a
  real, sourced cmdlet-vs-portal gap confirmed by directly comparing two official pages against
  each other, not a guess; the deploy script rejects any config entry requesting a portal-only
  duration rather than silently misbehaving; (2) audit log retention policies have **no
  enable/disable/simulation mode** — unlike this library's DLP/DLM scenarios, the only lifecycle
  actions are create/edit/delete, so `rollback.md` treats deletion as the sole "off" switch;
  (3) two hard tenant-wide constraints — a **50-policy cap** and **globally-unique Priority**
  (1–10000) across every policy in the org, not just a script's own config — are enforced
  pre-flight against a live `Get-UnifiedAuditLogRetentionPolicy` snapshot before any write is
  attempted, so a single invalid or colliding config entry stops the whole run rather than
  partially applying it; (4) creating/editing retention policies requires the **Organization
  Configuration** role, confirmed (via the `scc-permissions` role-groups reference) to be included
  by default in the **Compliance Data Administrator** Purview role group — a distinct grant from
  the **Audit Manager** role group `docs/rbac-model.md`'s existing Audit row already documents for
  search/export, filed as a backport follow-up rather than silently assumed already covered;
  (5) a policy authored via PowerShell for a `RecordTypes`/`Operations` combination the portal's
  own creation wizard doesn't offer becomes portal **view-and-delete-only** — a genuine
  operational trap for a buyer who scripts a policy and later expects portal-based tuning,
  documented explicitly in `README.md` §8/§11.

  Two items intentionally left as explicit VERIFY rather than resolved by guessing, per
  `AGENTS.md` §4: whether editing a live policy's `RetentionDuration` retroactively affects
  already-committed records' expiration (Microsoft's own conceptual page states this both ways in
  the same paragraph without reconciling them — flagged in `README.md` §11/`design.md` §6, with
  Red Team framing it as the specific mechanism a buyer must understand before using retention
  *shortening* for cost/noise control); and whether `$null`-clearing a `Set-` call's
  `-RecordTypes`/`-Operations` (extrapolated by this script from Microsoft's own worked
  `-UserIds $null` example) behaves identically for those two parameters. Four-lens review raised
  and resolved three Red Team findings around misuse-of-shortening framing, role-assignment
  governance boundaries, and a priority-collision denial-of-service risk — all addressed via
  explicit documentation/scoping rather than an invented technical mitigation Microsoft's own
  priority model doesn't provide. New follow-ups filed above under "Follow-ups discovered while
  building the Audit retention-policy-management scenario."

  This turn also ran a fresh grounding pass on the still-open
  `scenarios/dlp/removable-usb-device-groups-allowlist/` item (below) before picking this
  fragment instead — confirmed the tenant-wide `Set-PolicyConfig -DlpRemovableMediaGroups`/
  `-DlpPrinterGroups` cmdlet parameters genuinely exist (official reference), but both remain
  Microsoft-side documentation stubs with no example hashtable shape, confirmed empty even in the
  raw GitHub Markdown source — and the separate per-rule group-reference key inside
  `-EndpointDlpRestrictions` has no documented key name anywhere in the official
  `New-DlpComplianceRule` reference. That item **remains blocked** on the same core gap; two new
  follow-ups filed above capture the incidental discovery of official-source confirmation for
  `endpoint-dlp-usb-block`'s own `EndpointDlpRestrictions` `Setting`/`Value` strings (plus two
  previously-unknown valid values, `Ignore`/`Warn`) made during that same re-grounding pass.
  Commit: `2746a99`. Date: 2026-09-04.
- [x] **`scenarios/data-map/scan-on-premises-sql-server-and-classify/`** — the third and final
  explicitly-flagged sibling of `scenarios/data-map/scan-azure-sql-and-classify/` (alongside the
  already-built Managed Instance and Azure Synapse Analytics siblings), covering the one Data Map
  source `kind` in this list with no Azure resource behind it at all: on-premises SQL Server via a
  mandatory self-hosted integration runtime (SHIR) and a stored SQL/Windows credential — no
  managed-identity authentication path exists for this source type. Full deliverable per `AGENTS.md`
  §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/New-OnPremisesSqlServerDataMapScan.ps1` (idempotent, parameterized, `-WhatIf` throughout),
  `deploy/Remove-OnPremisesSqlServerDataMapScan.ps1`,
  `validate/Test-OnPremisesSqlServerDataMapScan.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix
  items resolved, no Fail).

  Genuine improvement over all three Azure siblings, not just a fourth repetition of their pattern:
  this build independently confirmed (by direct fetch of Microsoft's own canonical REST reference
  pages) that the self-hosted integration runtime *resource* and its auth-key retrieval both have
  documented REST operations (`Integration Runtimes - Create Or Replace` and `- Regenerate Auth Key`,
  API version `2023-09-01`, both with full worked HTTP examples) — so this scenario's deploy script
  scripts that provisioning step end-to-end via REST, something none of the three Azure sibling
  scenarios managed to automate for their own portal-only credential/SHIR setup steps. Installing the
  SHIR software on a host and pasting in the retrieved key remains a manual, physical step no REST
  API can perform; the Purview credential-object creation step remains the one open gap this build
  shares with every sibling (Microsoft's own disaster-recovery/migration best-practices article
  independently corroborates "there's no API to extract credentials").

  Key grounding, all confirmed via the Microsoft Learn MCP tool (available this run, contrary to this
  run's own initial task instructions claiming it would not be) against direct fetches of
  `register-scan-on-premises-sql-server`, the `Data Sources`/`Scans`/`Integration Runtimes` REST
  reference pages (Create Or Replace + Regenerate Auth Key), the `ConnectedVia`/`CredentialReference`/
  `CredentialType` shared REST definitions, the `New-AzPurviewSqlServerDatabaseDataSourceObject` and
  `New-AzPurviewSqlServerDatabaseCredentialScanObject` Az.Purview worked PowerShell examples (which
  independently corroborate the REST body shape end-to-end, including that no Azure resource fields
  are populated for this source type), and Microsoft's own disaster-recovery/migration best-practices
  article. Two items intentionally not resolved by guessing and flagged as explicit VERIFY instead,
  per `AGENTS.md` §4: the literal system scan rule set name for `SqlServerDatabase` (no worked example
  found pairing it with `scanRulesetType: "System"`, unlike every sibling's own confirmed name), and
  which `CredentialType` enum value represents "Windows Authentication" in the portal (the enum has no
  value independently confirmed for it). Four-lens review added two real findings beyond what any
  sibling's review caught: the printed SHIR auth key is a live registration secret that must never be
  persisted to logs/pipeline output (Red Team, resolved via explicit warnings in both the script and
  README), and a compromised shared SHIR host's blast radius extends to every data source wired to it
  (Red Team/CISO, resolved via a README §8 recommendation to dedicate separate SHIR hosts per
  sensitivity tier) — `dc5488a` — 2026-09-04

- [x] **`scenarios/information-protection/auto-label-confidential-exchange/`** — Exchange-location
  companion to `scenarios/information-protection/auto-label-confidential-sharepoint/`, closing the
  non-goal that scenario's `design.md` §7 explicitly deferred ("this scenario does not cover
  Exchange (email) auto-labeling, even though the same policy family supports it"). Full
  deliverable per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/New-ConfidentialAutoLabelExchangePolicy.ps1` (idempotent, parameterized, `-WhatIf`
  throughout, one rule for the single `Exchange` workload — no multi-rule split needed, unlike the
  sibling scenario's SharePoint+OneDrive pair), `deploy/Remove-ConfidentialAutoLabelExchangePolicy.ps1`,
  `validate/Test-ConfidentialAutoLabelExchangePolicy.ps1`, `rollback.md`, `reviews.md` (four-lens,
  all Fix items resolved, no Fail). Reuses the same `Confidential` label and the same SSN/Credit
  Card Number SIT pair as the sibling scenario — same classification pattern, new location, not a
  new pattern.

  Key grounding/design findings, all confirmed via the Microsoft Learn MCP tool (available this
  run) against `apply-sensitivity-label-automatically` (direct-fetched in full), the
  `New-AutoSensitivityLabelPolicy`/`New-AutoSensitivityLabelRule` parameter references, and
  `auto-label-insights-tab`: (1) Exchange auto-labeling evaluates mail **in transit**, not at
  rest in mailboxes — no backlog coverage, and simulation only sees live traffic sent/received
  during the simulation run, a materially different model from the sibling scenario's ongoing
  backlog scan; (2) there is **no `-ExchangeLocationException` parameter** — confirmed by fetching
  the complete `New-AutoSensitivityLabelPolicy` parameter syntax — so this scenario's exclusion
  mechanism is `-ExchangeSenderException` (sender-based, asymmetric: protects only the excluded
  mailbox's outbound mail) rather than a location-URL exclusion like the sibling scenario's;
  (3) Exchange has **no "Labeled items" dashboard or policy-level Insights enforcement metrics** —
  Activity Explorer (60–90 minute delay, doesn't identify which policy/rule applied a label) is
  the only documented verification path, and this scenario's `README.md` §7/§8 and `validate/`
  script are built around that constraint rather than assuming SharePoint/OneDrive-equivalent
  observability; (4) the target label's required scope is **Emails**, not "Files & other data
  assets"; (5) encryption permission-model and external-recipient defaults differ materially from
  the sibling scenario (Assign-permissions-now is not required for Exchange-only policies;
  external-recipient mail is labeled but **not encrypted by default** unless
  `-ExternalMailRightsManagementOwner` is configured); (6) turning a policy on (not just
  authoring/simulating it) requires **Compliance Administrator or Compliance Data Administrator**,
  a role-split finding that also applies to the sibling scenario but wasn't previously documented
  there (backport filed as a new follow-up rather than reopening that finished fragment).

  Four-lens review caught and fixed two genuine Red Team findings the initial draft underplayed as
  neutral configuration differences rather than real risks: the sender-based exclusion is a
  standing, control-free exfiltration path if the excluded mailbox is ever compromised or
  repurposed (not just an under-protection nuance for the custodian), and the external-recipient
  encryption default leaves SSN/card-number content in **cleartext** on exactly the direction of
  travel (data leaving the tenant) that matters most for breach-notification exposure — both
  rewritten in `README.md` §11 as explicit risks with concrete mitigations (monitor the exclusion
  list; configure `-ExternalMailRightsManagementOwner` or pair with a content-based DLP rule for
  external send) rather than left as passive documentation. A third finding — an overconfident
  claim about PDF attachments being left unprotected by label-driven encryption — was softened to
  an explicit VERIFY rather than asserting unconfirmed behavior, per `AGENTS.md` §4. Both new
  Red Team findings and the PDF VERIFY are filed as new `PROGRESS.md` follow-ups (a companion
  content-based Exchange DLP scenario, and the PDF-encryption pilot-tenant verification) rather
  than resolved by guessing or scope-expanding this fragment. Commit: `ed4ddd2`.
  Date: 2026-09-04.
- [x] **Extend `docs/automation-surface.md` with a fifth automation surface: SharePoint Online
  Management Shell** — a scoped cross-cutting-doc fragment (not a new scenario), closing the item
  logged during the `auto-label-confidential-sharepoint` build: `Set-SPOTenant
  -EnableAIPIntegration`/`-EnableSensitivityLabelforPDF`/`-EnableSensitivityLabelForVideoFiles`
  (the tenant-wide prerequisite toggles that gate SharePoint/OneDrive sensitivity-label
  auto-labeling) run over `Connect-SPOService`/`Microsoft.Online.SharePoint.PowerShell`, a
  connection surface distinct from the four the doc already covered. Grounded via the Microsoft
  Learn MCP tool (available this run) directly against the `Connect-SPOService` reference (full
  parameter-set fetch: confirmed certificate app-only — `-ClientId`/`-TenantId`/`-Certificate`/
  `-CertificateThumbprint`/`-CertificatePath`/`-CertificatePassword` — **and** a managed-identity
  parameter set — `-ManagedIdentity`/`-ManagedIdentityType`/`-ManagedIdentityClientId` — plus the
  documented "must be a SharePoint Administrator or SharePoint Embedded Administrator" requirement),
  the "Enable sensitivity labels for files in SharePoint and OneDrive" reference (exact cmdlet/
  parameter names and the PDF parameter's minimum module version 16.0.24211.12000), and "Get started
  with SharePoint Online Management Shell" (module install, and the material finding that the
  module is Windows PowerShell 5.1-native — running it under PowerShell 7 requires
  `-UseWindowsPowerShell`, a Windows-only compatibility layer, so **surface 5 has no documented
  cross-platform CI/CD path**, unlike surfaces 1 and 3). Updated `docs/automation-surface.md` §1
  (five-surface table + rule-of-thumb), §2 (module install row), §3 (auth-pattern table + app-only
  setup steps + connection examples), §4 (routing-table rows for the three `Set-SPOTenant`
  toggles), §5 (propagation-delay note instead of a batching pattern), §6 (Windows-runner CI/CD
  requirement — the most consequential new fact for a buyer planning automation), §7, and Sources.
  One genuine gap **not** resolved by guessing, per `AGENTS.md` §4: Microsoft's official
  `Connect-SPOService` reference doesn't separately name an Entra **API permission** for this
  tenant-admin surface (as distinct from the SharePoint resource's documented `Sites.FullControl.All`
  for site-level CSOM/PnP automation) — flagged inline as VERIFY in §3, with the documented
  SharePoint Administrator Entra-role requirement recorded as the controlling access check in the
  meantime. Four-lens self-review (no dedicated `reviews.md` — this is a doc fragment, not a
  scenario folder, consistent with this repo's precedent for cross-cutting-doc-only fragments):
  Red Team — no new attack surface, the pattern reinforces cert-only/managed-identity auth, no
  secrets introduced (Pass); Blue Team — n/a for a reference doc beyond the added propagation-delay
  operational note, which is itself actionable guidance for `validate/` scripts (Pass); CISO — the
  Windows-runner CI/CD constraint is genuinely decision-relevant for a buyer scoping a pipeline
  around this surface, not filler (Pass); Product Owner — every cmdlet/parameter name was
  independently fetched from the live Microsoft Learn reference pages, not recalled from memory or
  copied from the flagging scenario's unverified note (Pass). Closed the two cross-references in
  `scenarios/information-protection/auto-label-confidential-sharepoint/README.md` §3/§11 and
  `design.md` §5 that had called this out as an uncataloged surface. Commit: `9350bc7`.
  Date: 2026-09-04.
- [x] **`scenarios/compliance-manager/pci-dss-assessment/`** — Compliance Manager PCI DSS v4.0
  premium-template assessment scenario, the assessment-side companion to `scenarios/dlp/
  pci-teams-exfil-block/` referenced from that scenario's `README.md` §2 (now updated in place from
  "planned" to the real path). Full deliverable per `AGENTS.md` §4: `README.md`, `design.md`,
  `deploy/policy/pci-dss-assessment-manifest.json`, `deploy/Export-ComplianceManagerAuditTrail.ps1`,
  `validate/Test-ComplianceManagerAuditTrail.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix
  items resolved, no Fail). Key grounding/design decisions: (1) Compliance Manager's regulation
  catalog lists PCI DSS v4.0 and a retired PCI DSS v3.2.1 as two separate premium templates —
  documented prominently so a buyer doesn't burn a license slot on the wrong one; (2) the
  audit-trail script is **deliberately reused, not duplicated**, from `assess-against-iso27001/
  deploy/Export-ComplianceManagerAuditTrail.ps1` — its 3 monitored operations
  (`ComplianceManagerRolesChange`/`ComplianceManagerAutomationLevelChange`/
  `ComplianceManagerAutomationChange`) are tenant-wide, not assessment-scoped, so a second copy
  would be pure duplication; (3) a control crosswalk (`deploy/policy/pci-dss-assessment-manifest.
  json`'s `controlCrosswalk`) maps PCI DSS v4.0's 6 goals to this library's own PCI-relevant
  scenarios, explicitly labeled as this library's own correlation, not Microsoft's published
  mapping; (4) group-placement guidance corrects an easy misreading of Microsoft's own
  documentation — **technical** improvement actions already sync tenant-wide regardless of group,
  while only **nontechnical** ones sync within a shared group, which is the actual, narrower
  benefit of joining `assess-against-iso27001`'s group (that scenario's own manifest note was
  corrected in place to stop overclaiming); (5) prominently states, in `README.md` §2 (not buried
  in limitations), that this assessment is not a substitute for a PCI DSS SAQ or QSA Report on
  Compliance. Grounded via the Microsoft Learn MCP tool (available this run) against
  `offering-pci-dss`, `compliance-manager-regulations-list`, `compliance-manager-assessments`
  (including its precise "Groups for assessments" technical-vs-nontechnical sync rule), and
  `compliance-manager-improvement-actions`. New follow-ups (ISO/IEC 27001:2022 template now
  confirmed to exist; PCI DSS Requirement 12.4 cadence left unspecified rather than guessed; the
  group-sharing behavior not yet pilot-confirmed; a possible SOC 2 sibling scenario) filed above
  under "Follow-ups discovered while building the Compliance Manager PCI DSS v4.0 assessment
  scenario" and in the ISO 27001 section. Commit: `7104997`. Date: 2026-09-04.
- [x] **Re-check `ediscoveryHoldPolicy: enablePolicy`/`disablePolicy` beta-to-v1.0 promotion status
  (`scenarios/ediscovery/location-scoped-legal-hold/`)** — a correctness re-verification fragment,
  not a new scenario, closing the periodic-recheck item logged when this scenario was originally
  built: as of that build, `enablePolicy`/`disablePolicy` existed only in the Graph `/beta`
  namespace, which is why `Remove-EdiscoveryLocationHold.ps1` has no reversible "pause" rollback
  stage (only delete-one-source or delete-the-whole-policy). Re-grounded via the Microsoft Learn
  MCP tool (available this run, contrary to this run's own initial assumption): a fresh direct
  fetch of the v1.0 `ediscoveryHoldPolicy` resource page's method table still lists no enable/
  disable action (List/Create/Get/Update/Delete/`retryPolicy`/site sources/user sources only); a
  search for `ediscoveryHoldPolicy enablePolicy disablePolicy v1.0` returns only
  `?view=graph-rest-beta` pages, each still carrying the standard beta-instability banner; the v1.0
  Update operation's documented property set is still `contentQuery`/`description` only, ruling out
  a PATCH-based `isEnabled` workaround as an alternate v1.0 path. **No promotion has occurred** —
  the scenario's existing "no reversible pause on v1.0" disclosure was already correct and required
  no functional/code correction, only a re-verification timestamp and two new supporting citations.
  Updated `design.md` §4 (re-verification paragraph + new reference R9b), `README.md` §11/§12
  (re-verified-2026-09-04 callouts), and `reviews.md` (a short follow-up four-lens round — all four
  lenses Pass, no Fix/Fail, consistent with this library's established pattern for a confirmation
  that changes no capability or risk surface). No code changed: there is still no v1.0 path to a
  reversible on/off toggle, so `Remove-EdiscoveryLocationHold.ps1`'s two-stage (delete-source /
  delete-policy) rollback design stands unmodified. Re-open this item again only if a future pass
  finds either action listed under `?view=graph-rest-1.0`. Commit: `9eb87a6`. Date: 2026-09-04.
- [x] **`scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/`** — behavioral
  compensating control for the split/obfuscated-PAN evasion gap `pci-teams-exfil-block/reviews.md`
  (Red Team) flagged and deliberately left open. Grounding pass found and had to design around a
  material constraint: Microsoft Teams DLP policy matches are explicitly **not** a supported
  workload for Insider Risk Management's "High Severity DLP Alert" indicator ("This is by
  design" — only Exchange Online/SharePoint Online/OneDrive for Business are supported), so the
  originally-assumed "wire the Teams DLP rule as an IRM trigger" approach was discarded once
  confirmed and rebuilt around the one path that *does* cover Teams: the Communication Compliance
  "detect messages matching SITs" indicator integration (Credit Card Number), feeding a dedicated
  IRM "Data leaks" policy with Cumulative Exfiltration Detection enabled, driving Adaptive
  Protection's already-grounded `-SharedByIRMUserRisk` condition on a new priority-0 rule added to
  Part 1's own named DLP policy — hard-blocks all further external Teams sharing from an
  Elevated-risk sender, no override even for Card Ops members. Ships `README.md`, `design.md`,
  `deploy/New-PciElevatedRiskTeamsBlock.ps1` (idempotent, dry-run, explicitly re-prioritizes Part
  1's three rules rather than relying on undocumented auto-shift behavior),
  `deploy/Remove-PciElevatedRiskTeamsBlock.ps1`, `deploy/policy/
  irm-drip-exfiltration-config-manifest.json` (portal-only prerequisite checklist),
  `validate/Test-PciElevatedRiskTeamsBlock.ps1`, `rollback.md`, `reviews.md`. Four-lens review
  surfaced and resolved three real findings: (1) explicitly documented the control's actual
  bound — zero detectable signal against a maximally disciplined single-digit-per-message
  attacker who generates no other exfiltration-type activity; (2) flagged that Elevated risk (and
  this rule's block) can be reached from activity unrelated to card data, strengthening the
  incident-response runbook to confirm the actual triggering indicator; (3) added an explicit
  VERIFY that no single Microsoft-published example validates this exact end-to-end composition,
  even though every individual piece is independently grounded. Commit: `fd42f22` — 2026-09-04.
- [x] **`scenarios/ediscovery/roster-to-hold-locations/`** — thirteenth full scenario fragment
  (eDiscovery), closing the hand-off `teams-group-hold-resolution/design.md` §7 explicitly deferred:
  "Once a human uses `-ResolveMembers`'s roster output to decide individual members also need
  preservation, feeding those resolved mailbox addresses into the sibling scenario's own
  `userSources[]` array is currently a manual step." Ships `deploy/
  Merge-RosterIntoHoldDefinition.ps1` (reads a roster CSV + a human-authored `-SelectionPath`
  decision record, cross-validates every selected email actually appears in the roster — a hard
  error if not, never a silent skip — then appends new `userSources[]` entries to a
  `location-hold-definition.json`-shaped file, with an optional `-AddToHold` stage reconciling
  directly onto a live hold policy via the already-grounded `ediscoveryHoldPolicy` v1.0 Graph
  endpoints), `validate/Test-RosterHoldDefinitionMerge.ps1`, `design.md`, `README.md`,
  `rollback.md`, and `reviews.md`. Introduces no new Microsoft Learn citations — every product fact
  it depends on was already grounded in `teams-group-hold-resolution` and `location-scoped-legal-
  hold`'s own README §12 sections; this fragment is pure orchestration between the two. Four-lens
  review caught and fixed two real correctness bugs before finalizing: (1) the initial draft's
  `-AddToHold` stage only reconciled emails newly written to the definition file that run, silently
  skipping reconciliation for a member merged into the file in an earlier run but never actually
  applied to the live hold — fixed to reconcile every selected email via the same idempotent
  find-or-create pattern; (2) a `Set-StrictMode -Version Latest` crash risk on a malformed selection
  file missing the `selectedEmails` key entirely, present independently in both `deploy/` and
  `validate/` — fixed with the same property-presence-check pattern
  `teams-group-hold-resolution/reviews.md` had already established for an analogous gap.
  Commit: `3ebfd4e`. Date: 2026-09-04.
- [x] **Reconcile the eDiscovery group-expansion member-cap discrepancy (100 vs. >1,000 members)**
  — twelfth **follow-up expansion** fragment (eDiscovery), a correctness/grounding correction rather
  than a new scenario, closing the item logged during the `teams-group-hold-resolution` build:
  "Microsoft's current 'Create holds in eDiscovery' page states... 100 members... a smaller... figure
  than the '>1,000 members' cap `location-scoped-legal-hold/design.md` §3 cites (from the older
  'Manage hold status errors' reference page)... Determine whether these describe the same underlying
  limit." Re-fetching both pages directly (`edisc-hold-create` and `edisc-hold-manage`) found the
  original premise wrong in one respect: the ">1,000" figure is **not** from an older or separate
  page — it lives in a still-current table ("Manage hold status errors") on the same, current, non-
  legacy "Manage holds in eDiscovery" article. Both figures are live simultaneously. Read literally,
  they describe two different pipeline moments: the **100-member** figure is the portal's own
  interactive data-source picker (checkbox enumeration of group members), documented for "every
  supported group type"; the **>1,000-member** figure is a **hold-application/retry** error
  ("Distribution group has too many members") surfaced on the Hold policy Details tab after a hold is
  applied, documented specifically for distribution groups. Microsoft's text never cross-references
  the two or states they're the same limit measured twice — so this was **not** resolved by picking
  one as "the current figure" (neither superseded the other). Instead: `location-scoped-legal-hold/
  design.md` §3 was rewritten with the full re-grounded analysis and a new reference (R11, the
  `edisc-hold-create` "Create a hold" section); `README.md` §8 and §11 now cite both figures
  side-by-side, name **100 members** as the conservative KPI/planning threshold (the smaller number,
  tied to "every supported group type"), and keep the >1,000-member error string as the specific
  documented failure condition to watch for by name; the deploy script's `.NOTES` and the sample
  `location-hold-definition.json`'s inline comment were updated to match.
  `teams-group-hold-resolution/README.md` §11/§12, `design.md` §6, and `deploy/
  Resolve-TeamsGroupHoldLocations.ps1`'s `.NOTES` were updated in step, including a new reference
  ([[10]], the "Manage hold status errors" page) that scenario's citation list was previously missing.
  Both scenarios' `reviews.md` got a short follow-up four-lens round (all four lenses Pass, no
  Fix/Fail — a precision improvement to already-disclosed content, not a new capability or risk
  surface). The underlying question — which limit, if either, governs this scenario's own
  REST-driven `userSources` expansion path (neither the portal picker nor confirmed to be the same
  code path as the documented error) — remains an explicit, open pilot-tenant VERIFY in both
  scenarios rather than resolved by guessing, per `AGENTS.md` §4. Grounded via the Microsoft Learn
  MCP tool (direct fetch of `purview/edisc-hold-create` and `purview/edisc-hold-manage`,
  2026-09-04) — no cmdlet, endpoint, or product behavior was fabricated to close this gap. —
  2026-09-04
- [x] **Investigate and correct: automatic Power Automate/webhook trigger for IRM case escalation**
  — eleventh **follow-up expansion** fragment (Insider Risk Management / eDiscovery), a correctness
  correction rather than a new scenario, closing the item logged during the original
  `irm-case-escalation-to-ediscovery` build ("consider a Power Automate flow … that automatically
  runs `Confirm-EdiscoveryEscalationLink.ps1` right after an investigator completes … 'Escalate for
  investigation' … deferred because [it] wasn't independently grounded"). Grounding this pass found
  the original README.md §8 wording ("a Power Automate flow triggered on escalation") overstated
  what Microsoft documents: the custom-flow "For a selected Insider Risk Management case" trigger is
  manually selected and run from the same Cases-dashboard **Automate** toolbar the investigator just
  used to escalate — not an event-driven subscription — and none of the five documented Purview-
  connector actions available to a custom IRM flow (Get alert/case/user/alerts-for-case, Add case
  note) can invoke an external script; doing so would need a generic, non-Purview HTTP/Azure-
  Automation action on top, which Microsoft's own docs flag as potentially needing extra Power
  Automate licensing. The other plausible automation path — polling the dedicated **Insider Risk
  Management audit log** instead of the case itself — was also checked and is not available either:
  Microsoft states that log "isn't associated with the Microsoft 365 audit log," is portal-view/CSV-
  export only, and has no documented Graph/REST endpoint (`Search-UnifiedAuditLog` doesn't cover it).
  Corrected `irm-case-escalation-to-ediscovery/README.md` §8 (rewrote the KPI bullet to present the
  scheduled poll as the only unattended option and the Power Automate path as a manually-invoked,
  one-click convenience rather than automatic, with the premium-connector licensing caveat), §11 (new
  Known Limitations bullet), and §12 (two new citations); `design.md` (new §5 documenting the
  finding, a new §4 non-goal, two new references); `reviews.md` (a follow-up four-lens round — Red
  Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail — confirming the correction itself is
  sound). No code changed — there was nothing to build once the "automatic trigger" premise the
  original item was scoped around didn't hold up under grounding; writing a Power Automate flow
  anyway would have shipped a control that doesn't do what its name implies, which is exactly the
  failure mode this correction exists to prevent. Grounded via the Microsoft Learn MCP tool
  (`insider-risk-management-cases#case-actions` for the toolbar-invocation walkthrough;
  `insider-risk-management-settings-power-automate` for the custom-flow trigger/action/licensing
  detail; `insider-risk-management-audit-log` for the IRM audit log's independence from the unified
  audit log and its portal-only access) — per `AGENTS.md` §4, no cmdlet, endpoint, or product
  behavior was fabricated to fill the gap this item originally left open. — 2026-09-04
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` — tenth **follow-up expansion** fragment
  (eDiscovery), closing the item logged during the `location-scoped-legal-hold` build: "resolving
  *which* group/site pair to use from a Team name is a distinct, separately scoped lookup this
  fragment doesn't automate." Full README (12-section skeleton), design.md (grounds the surface
  split — Exchange Online PowerShell for resolution, Microsoft Graph only for the optional
  reconciliation stage — against this library's existing EXO-primary-script precedent rather than
  the Graph-only sibling scenario's pattern; explicit non-goals for member expansion, private
  channels, and DL resolution), deploy/ (`Resolve-TeamsGroupHoldLocations.ps1` — Stage 1 always
  runs: idempotent/parameterized `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` resolution (Exchange
  Online PowerShell, surface 1; caller must already be connected, matching
  `premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`'s convention) writing a
  `userSources[]`/`siteSources[]` JSON fragment in the exact shape
  `location-scoped-legal-hold/deploy/policy/location-hold-definition.json` uses, plus an optional
  member-roster CSV (informational only, never auto-added to a hold); Stage 2 (`-AddToHold`,
  opt-in) self-connects to Microsoft Graph (surface 3) and idempotently reconciles each resolved
  location onto an existing hold policy, duplicating (not dot-sourcing) the sibling scenario's own
  `Confirm-UserSource`/`Confirm-SiteSource` find-or-create logic, `$PSCmdlet.ShouldProcess()`-gated
  throughout for a true `-WhatIf`), validate/ (`Test-TeamsGroupHoldLocations.ps1` — read-only
  group-drift check always, plus an optional hold-reconciliation check scoped to just this
  scenario's own resolved groups), rollback.md (Stage 1: delete two local files, no tenant effect;
  Stage 2: defers entirely to the sibling scenario's own `Remove-EdiscoveryLocationHold.ps1` rather
  than duplicating a second removal implementation), four-lens reviews.md (Red Team Fix round
  resolved — a missing-SharePoint-site rollup warning so the gap is visible without reading
  interleaved per-group output, a `deploy/out/` default output directory instead of the tracked
  `deploy/config/` to keep a real run's resolved values and the PII-bearing member roster out of
  git history, and a real `Set-StrictMode`-under-optional-JSON-property bug caught and fixed during
  review (`$groupDef.resolveMembers` would have thrown for any config that omitted the documented-
  optional key) — two further items confirmed already correctly scoped, not changed; Blue Team Fix
  round resolved — same code changes as the Red Team detectability findings; CISO Pass — the
  asymmetric over-preserve/under-preserve risk reasoning for why this scenario needs no removal-side
  counsel gate of its own; Product Owner Pass — confirmed leaner Graph module dependency than the
  sibling scenario (no typed `Microsoft.Graph.Security` cmdlet needed for attach-only reconciliation
  against an already-existing case/hold), confirmed the EXO/Graph connection-pattern split is
  deliberate and documented rather than an unexplained inconsistency) — grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` Exchange PowerShell
  reference pages for exact syntax/role requirements; "Create holds in eDiscovery" direct-fetched in
  full for the "Preserve content in Microsoft Teams"/"Microsoft 365 groups" worked example, the
  group-membership point-in-time-snapshot behavior, and the 100-member group-expansion cap; "Manage
  holds in eDiscovery" for the hold-management-context restatement of the same Teams/group guidance;
  "Microsoft 365 Group behaviors and provisioning options" for the confirmed `ProvisionSiteOnDemand`
  site-provisioning-deferral option) — two items recorded as explicit VERIFY rather than resolved by
  guessing (no canonical SLA for `SharePointSiteUrl` populating after group creation; the 100-vs-
  >1,000-member cap discrepancy against the sibling scenario's own citation, logged above as a new
  follow-up to reconcile), per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` — third scenario in this repo's
  Azure-SQL-family Data Map series (after `scan-azure-sql-and-classify` and
  `scan-azure-sql-managed-instance-and-classify`), closing the explicitly-flagged sibling item from
  the Managed Instance scenario's own follow-up backlog. Registers an Azure Synapse Analytics
  **workspace** (not a single database) as a Purview Data Map source, with the dedicated and/or
  serverless SQL pool endpoints as two optional properties on one `AzureSynapseWorkspace` data source
  object, and configures an `AzureSynapseWorkspaceMsi` SAMI-authenticated scan against it using the
  system default `AzureSynapseSQL` scan rule set. Full README (12-section skeleton, an up-front callout
  distinguishing this workspace-based data source from Microsoft's separate, older standalone
  "dedicated SQL pool (formerly SQL DW)" source), design.md (a `design.md` §4 diff table against both
  sibling scenarios covering the three-part serverless enumeration-authentication story, the
  firewall-or-SQL-Auth-fallback distinction, and the portal's single "SQL Database" scan Type), deploy/
  (`New-AzureSynapseDataMapScan.ps1` / `Remove-AzureSynapseDataMapScan.ps1` — idempotent, parameterized,
  `-WhatIf` throughout, reusing the generic Data Sources/Scans/Triggers/Scan Result REST call shapes the
  Managed Instance sibling scenario already confirmed by direct fetch, with Synapse-specific `kind`/body
  properties independently confirmed via the Az.Purview PowerShell module's own worked examples),
  validate/ script, four-lens reviews.md (Red Team Fix round resolved — Storage Blob Data Reader
  over-scoping risk and the silent external-table coverage gap; Blue Team Fix round resolved — the
  serverless-enumeration-login validate-script gap explained rather than left silent; CISO Fix round
  resolved — per-database prerequisite cost scales with workspace database count, unlike either sibling
  scenario's fixed one-time cost; Product Owner Fix round resolved — distinguished this scenario's
  workspace-based data source from Microsoft's separate, older standalone dedicated-SQL-pool source) —
  grounded in Microsoft Learn (`register-scan-synapse-workspace`'s full registration/scan/permissions
  workflow, fetched via a verified byte-for-byte mirror after direct `learn.microsoft.com` fetches
  returned `EGRESS_BLOCKED` throughout this build; the Az.Purview PowerShell module's
  `New-AzPurviewAzureSynapseWorkspaceDataSourceObject`/`-MsiScanObject` cmdlet references, fetched via
  GitHub raw source, for the `kind` and property names; `register-scan-azure-synapse-analytics` and
  `data-governance-private-endpoints-managed-virtual-network` for the two Product Owner/limitations
  citations). One property (the scan object's optional `resourceTypes`) could not be independently
  confirmed to an exact JSON shape and is deliberately omitted rather than guessed — flagged as an
  explicit VERIFY in `README.md` §11 and `design.md` §5, with three new follow-ups recorded below
  rather than resolved by guessing, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` — ninth **follow-up
  expansion** fragment (Data Estate Insights), closing the item logged during the
  `classification-coverage-report` build: extend that scenario's exact pattern (paginated Discovery -
  Query, client-side tally, replace-by-`RunId` trend log) to the `label` field on the same
  `SearchResultValue` schema. Full README (12-section skeleton, Public Preview callout up front per
  this repo's established pattern for the upstream "extend sensitivity labels to Data Map" preview
  dependency), design.md (five design goals mirroring the sibling scenario's own, plus a fifth,
  label-specific consideration — labels surfaced through this extension are metadata-only, not
  enforced protection), deploy/ (`Export-SensitivityLabelCoverageReport.ps1` — idempotent/
  parameterized Purview Data Map Discovery - Query REST automation (surface 4, API version
  `2023-09-01`, independently re-confirmed via direct fetch for this build) applying the sibling
  scenario's already-reviewed client-side-tally design to the `label` field/facet instead of
  `classification`; `-Mode Full`/`-Mode Facets`, replace-by-`RunId` trend log, manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf`), validate/ script (identical file-integrity + optional
  live-reconciliation check structure, `label`-specific column names), four-lens reviews.md (Red Team
  Fix round resolved — found and flagged a genuine new risk the sibling scenario didn't have: a
  `0% labeled` reading is ambiguous between "unprotected" and "source type doesn't support Data Map
  labeling at all," closed via README/design additions rather than a guessed validation rule; Blue
  Team Fix round resolved — operability guidance for the same ambiguity, a self-contained incident-
  response runbook, and explicit file-naming non-collision with the sibling scenario; CISO Fix round
  resolved — the review's most consequential finding: sensitivity labels surfaced via this Data Map
  extension are metadata-only per Microsoft's own FAQ (no encryption, no content marking, no DLP), so
  a high `PercentLabeled` must never be presented as "this data is protected" — added as an explicit
  callout in README §2/§11 and design.md §1 before this scenario's output could be handed to a board
  without risk of a false-assurance narrative; Product Owner Fix round resolved — corrected the native
  report's name from `PROGRESS.md`'s own loose paraphrase ("Labeling insights") to Microsoft's actual
  current name, "Classic sensitivity labels" report) — grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (a direct fetch of the Discovery - Query REST reference confirming the `label`
  response field (`string[]`) and the `label` facet as one of exactly four documented facets, and
  confirming no worked exact-value `label` filter example exists (only `classification` does);
  Understand the classic sensitivity labels report in Unified Catalog; Understand the classic assets
  report; Access control in Data Estate Insights within Microsoft Purview; Learn about sensitivity
  labels in Data Map (preview) and its FAQ, including the licensing-tier list and the metadata-only/
  no-encryption/no-DLP confirmations; Understand the Microsoft Purview Data Estate Insights
  application) — one gap (the source-type-support check) recorded as a follow-up rather than resolved
  by guessing, per `AGENTS.md` §4 — 2026-09-04

- [x] `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` — eighth **follow-up expansion**
  fragment (Insider Risk Management / eDiscovery), closing the item logged during the
  `premium-legal-hold-and-export` build: "once `scenarios/insider-risk/` has a scenario producing
  an escalatable IRM case [it now does — `departing-employee-data-theft`], wire the documented
  IRM-case → eDiscovery (Premium) case escalation integration." Full README (12-section skeleton),
  design.md (grounds why the escalation trigger itself has no Graph/PowerShell API — portal-only,
  same shape as several other no-write-API Purview surfaces this library documents — and why the
  `ediscoveryCase` resource's `description` field, its only free-text property, is the correct,
  non-fabricated place to stamp a provenance link back to the source IRM case/alerts, since the
  resource has no source/origin field of any kind), deploy/
  (`Confirm-EdiscoveryEscalationLink.ps1` — idempotent/parameterized Microsoft Graph automation
  (surface 3) that finds the already-escalated eDiscoveryCase by a documented naming convention
  (`IRM-<Case ID>-<UPN local part>`, this repo's own convention, not Microsoft's), best-effort
  resolves declared IRM alert IDs via `Get-MgSecurityAlertV2 -AlertId` for a human-readable
  record, stamps a delimited, idempotent provenance block onto the case description via
  `Update-MgSecurityCaseEdiscoveryCase`, and unconditionally reconciles the flagged user as a
  custodian with a mailbox+OneDrive hold using the identical find-or-create/`applyHold` pattern as
  the sibling `premium-legal-hold-and-export` scenario (duplicated, not dot-sourced, per this
  repo's self-contained-deploy-tree convention); `Remove-EdiscoveryEscalationLink.ps1` — staged
  rollback (strip the provenance block → optionally release the hold, counsel-gated, identical to
  the sibling scenario's own gate) that never closes/deletes the case itself, deferring to the
  sibling scenario's own rollback script for that; a JSON escalation-link definition file), validate/
  (`Test-EdiscoveryEscalationLink.ps1` — read-only PASS/WARN/FAIL checks of case existence,
  provenance-block presence *and* content match against the definition file, custodian/userSource/
  hold state, and best-effort alert resolution), four-lens reviews.md (Red Team Fix round resolved
  — found and fixed a real idempotency gap during review: the initial draft treated "a provenance
  block already exists" as "done," which would have silently left a *different* escalation's
  provenance stamped on a case whose name was accidentally reused; fixed by comparing the existing
  block's IRM case ID/user against the current run before skipping, throwing on a mismatch unless
  a new `-Force` switch is passed, and even then appending rather than overwriting so no prior
  provenance record is ever destroyed; Blue Team Fix round resolved — added an explicit
  escalation-to-automation trigger gap callout (README §8) and severity discipline to the validate
  script's alert-resolution check; CISO Pass; Product Owner Fix round resolved — reworded several
  passages that had implied a stronger native Microsoft linkage than is actually documented) —
  grounded in Microsoft Learn via the Microsoft Learn MCP tool (`insider-risk-management-cases`'s
  full "Escalate for investigation" portal walkthrough and system-generated-note behavior, the
  `ediscovery` legacy-solutions page's IRM-integration summary, the `ediscoveryCase` resource type
  and its Update operation directly fetched to confirm `description` is the only writable
  free-text field and that no source/origin field exists, and `Get-MgSecurityAlertV2`'s PowerShell
  reference directly fetched to confirm the `-AlertId` get-by-ID parameter set before using it) —
  three items recorded as explicit VERIFY rather than resolved by guessing (the IRM "Case ID"
  dashboard field's exact format; whether the portal escalation flow auto-provisions a
  custodian/hold; alert-metadata staleness after re-triage), per `AGENTS.md` §4 — 2026-09-04
- [x] **Investigate `scenarios/ediscovery/legal-hold-notifications/` — closed without building a
  scenario** — seventh **follow-up expansion** fragment (eDiscovery), a correctness correction
  rather than a new scenario. The original follow-up (logged during the
  `premium-legal-hold-and-export` build) assumed the Premium custodian-communication workflow
  (initial notice, reminders, escalations, acknowledgment tracking) was a live, portal-driven-only
  Purview feature with no Graph write API — the same shape as several other no-write-API surfaces
  this library already documents (Communication Compliance, Compliance Manager). Re-grounding for
  this fragment found something different: Microsoft's current, non-legacy-banner "Manage hold
  notifications" page states in an `Important` callout that legal hold custodian communications
  were **permanently retired on August 31, 2025** and aren't available in the new eDiscovery
  experience. The two walkthrough pages this follow-up would otherwise have built a portal runbook
  from ("Create a legal hold notice," "Work with communications in eDiscovery (Premium)") both
  carry the classic-experience/21Vianet-China-only caution banner rather than current guidance — a
  detail easy to miss if only the feature-comparison table on the legacy `ediscovery` overview page
  is checked, since the *current* `edisc-permissions` RBAC page still lists a "Communication" role
  for eDiscovery Manager/Administrator (stale documentation debt, not evidence the feature survived
  — the explicit retirement callout on the more specific, current "Manage hold notifications" page
  is the higher-confidence source and the one this correction relies on). No companion scenario was
  built, since there is no current-experience feature left to document or automate. Instead:
  corrected `premium-legal-hold-and-export/README.md` §11 (replaced the "portal-driven, no API"
  characterization with the retirement finding, the concrete consequence that
  `ediscoveryCustodian.acknowledgedDateTime`/`releasedDateTime` should be expected to stay null in
  the current experience rather than read as a live signal, and a recommendation to treat
  notice-and-acknowledgment as an external, non-Purview process until Microsoft ships a
  replacement) and its `.NOTES`-equivalent §12 reference list (added reference 28);
  `design.md` §7's non-goal bullet and References (added R12); a short follow-up four-lens review
  round in `reviews.md` (Red Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail) confirming the
  correction is itself sound rather than a new unverified claim. Grounded via the Microsoft Learn
  MCP tool (`ediscovery-manage-hold-notifications`'s retirement callout — the decisive source;
  `ediscovery-create-hold-notification` and `ediscovery-managing-custodian-communications` for the
  now-legacy workflow's own shape, both banner-flagged; the current, non-legacy `edisc` feature-
  comparison table, which has no "legal hold notifications" row at all, corroborating the
  retirement; the current, non-legacy `edisc-permissions` RBAC table, whose still-present
  "Communication" role was deliberately *not* treated as evidence to the contrary). No code written
  — there was nothing left to script once the underlying feature was confirmed retired, and writing
  a scenario anyway would have violated `AGENTS.md` §4's no-fabrication rule by presenting a dead
  feature as current guidance — 2026-09-04
- [x] **Backport: corrected Run Scan / List Scan History REST shapes into
  `scenarios/data-map/scan-azure-sql-and-classify/`** — sixth **follow-up expansion** fragment
  (Data Map, Data Governance), a correctness fix rather than a new scenario, per the item the
  `scan-azure-sql-managed-instance-and-classify` build logged: that sibling build independently
  direct-fetched the canonical Microsoft Learn **Scan Result - Run Scan** and **Scan Result - List
  Scan History** REST reference pages this scenario's own build could not reach, and found both of
  this scenario's reconstructed shapes were genuinely wrong, not just unverified. Corrected both:
  (1) `deploy/New-AzureSqlDataMapScan.ps1`'s `-RunNow` path now sends the confirmed action-style
  `POST {endpoint}/scan/datasources/{ds}/scans/{scan}:run?runId={guid}&scanLevel={level}&
  api-version=...` instead of the unconfirmed resource-style `PUT .../runs/{runId}` it previously
  sent (verb changed from `Put` to `Post`, URI changed to the colon-suffixed action form); (2)
  `validate/Test-AzureSqlDataMapScan.ps1`'s scan-history check now reads the confirmed nested
  `discoveryExecutionDetails.statistics.assets.discovered`/`.classified` fields instead of the
  unconfirmed flat `.assetsDiscovered`/`.assetsClassified` properties it previously read. Updated
  `design.md` (§5 sequence diagram + prose narrowing the still-open VERIFY to Data Sources/Triggers
  only), `README.md` (§6 config-reference row, §11 — replaced the three-way Data
  Sources/Triggers/Run-Scan VERIFY with a RESOLVED entry for the two corrected shapes plus a
  narrower two-item VERIFY for Data Sources/Triggers alone, §12 added reference 17, footer VERIFY
  count corrected from three to two), and `reviews.md` (a targeted four-lens follow-up pass on the
  correction itself — Red Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail, explicitly
  noting the Blue Team's original review-round mitigation for the *unconfirmed* shape now becomes a
  true error-handler rather than a shape-guess mask). No code executed against a live tenant
  (author-only reference code per `AGENTS.md` §5); both scripts hand-verified line-by-line against
  the sibling scenario's independently-confirmed shapes rather than executed, since `pwsh` is not
  available in this build environment. Two narrower VERIFY items remain open on this scenario (Data
  Sources/Triggers body shapes for the `AzureSqlDatabase` kind; the unrelated custom-scan-rule-set
  and credential-object REST-creation gaps, unchanged) — not resolved by this fragment and not
  claimed to be, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`
  — fifth **follow-up expansion** fragment (eDiscovery), closing the item that scenario's `README.md`
  §8/`reviews.md` (Red Team finding 1) tracked from its original build: no independent audit trail
  for who released a hold or closed/deleted a case. Grounded (Microsoft Learn MCP tool + WebSearch)
  the exact `RecordType`/`Operations` values rather than fabricating them: `RecordType Discovery`
  with two confirmed `Operation` sets from Microsoft's own "Audit log activities" eDiscovery
  reference — case lifecycle (`CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/`CaseRemoved`)
  and hold-**policy** lifecycle (`HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync`). Added `deploy/Export-EdiscoveryAuditTrail.ps1` (idempotent,
  parameterized Exchange Online PowerShell automation, surface 1 — rolling CSV merge de-duplicated
  by a composite key hashing the full `AuditData` JSON payload, same mechanism as
  `scenarios/compliance-manager/assess-against-iso27001/`'s and
  `scenarios/communication-compliance/harassment-and-code-of-conduct/`'s own audit-trail scripts;
  optional `-CaseName` client-side filter parsed from each record's `AuditData` JSON to scope a
  tenant-wide trail to one matter; `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still
  runs the read-only queries; `Write-Warning` on `CaseRemoved`/`HoldRemoved` rows) and
  `validate/Test-EdiscoveryAuditTrail.ps1` (automated CSV schema/de-duplication/operation-value/
  sort-order checks needing no tenant connection). Updated `README.md` §5 (script-path step 7), §6
  (configuration reference row), §8 (rewrote the "Audit visibility" subsection from "not grounded,
  tracked as a follow-up" to the grounded design plus the one genuine remaining gap), and §12
  (three new citations); `design.md` (new §8, plus three new `R9`–`R11` references) and `reviews.md`
  (a follow-up four-lens pass on the addition itself: Red Team/Blue Team/CISO/Product Owner all
  Pass, no Fix/Fail) and `rollback.md` (audit-log-entries note updated to name the new script).
  **One real gap deliberately not resolved by guessing** — whether those hold-policy `Operation`
  values also cover this scenario's own custodian-scoped `applyHold`/`release` calls (a different
  object from the case-level `ediscoveryHoldPolicy` the operations are documented against) is
  unconfirmed for the current, non-legacy eDiscovery experience: the one Microsoft Learn page
  describing per-custodian audit search, and the page claiming custodian holds are internally
  modeled as a "custodian hold policy," both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic experience's August 2025 retirement everywhere else
  — recorded as an explicit pilot-tenant VERIFY in this file (above), the script's own `.NOTES`,
  `README.md` §8, and `design.md` §8, per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/data-map/scan-azure-sql-managed-instance-and-classify/` — fourth **follow-up
  expansion** fragment (Data Map, Data Governance), closing one of the three sibling-scan-scenario
  items `scan-azure-sql-and-classify/design.md` §7 explicitly scoped out (Azure SQL Managed
  Instance, Azure Synapse Analytics, on-premises SQL Server): full README (12-section skeleton,
  every delta from the sibling scenario's prerequisites/config/architecture called out explicitly
  rather than silently re-derived), design.md (§3 grounds why this is a separate scenario rather
  than a `-SourceKind` flag on the sibling script; §4 is a single source-of-truth diff table; §5
  documents this build's own grounding-quality improvement over the sibling — direct fetches of all
  four canonical REST reference pages succeeded where three of the sibling's four failed at build
  time, surfacing two real, previously-unconfirmed shape corrections), deploy/
  (`New-AzureSqlManagedInstanceDataMapScan.ps1` — idempotent/parameterized Purview Data Map REST
  automation (surface 4) reusing the sibling's create-or-replace pattern for the
  `AzureSqlDatabaseManagedInstance` data source and `AzureSqlDatabaseManagedInstanceMsi`
  SAMI-authenticated scan (distinct `kind` values, a `tcp:<fqdn>,<port>` server-endpoint format, and
  a different system scan-rule-set name from the sibling scenario), optional recurring trigger,
  `-WhatIf` throughout; `Remove-AzureSqlManagedInstanceDataMapScan.ps1` — staged trigger/scan/
  data-source removal mirroring the sibling's rollback shape; `deploy/policy/
  azure-sql-mi-datamap-scan.json` — reference copy of all four REST bodies, each body's `$comment`
  flagging where its shape came from a direct fetch this build performed itself), validate/
  (`Test-AzureSqlManagedInstanceDataMapScan.ps1` — read-only config + scan-history check reading the
  corrected nested asset-count fields), rollback.md (the sibling's three-stage procedure plus a
  fourth, Managed-Instance-specific stage for the tenant-wide Directory Readers role grant, framed as
  a deliberately-manual, Privileged-Role-Administrator-gated step outside this scenario's own
  automation), four-lens reviews.md (Red Team Fix round resolved — the public endpoint's larger
  network exposure than the sibling's firewall toggle made explicit with a private-endpoint
  recommendation, and a Directory Readers membership-drift monitoring gap closed; Blue Team Fix
  round resolved — explained why Directory Readers membership isn't part of the automated validate
  script (a different auth surface than the rest of the script needs) rather than leaving it an
  unexplained gap, and added two Managed-Instance-specific incident-response causes; CISO Fix round
  resolved — the Privileged-Role-Administrator cross-team coordination cost made explicit as a
  distinct adoption-friction dimension from the sibling scenario's own three same-team
  prerequisites; Product Owner Fix round resolved — separated the registration `-Port` parameter
  from the NSG network-path port requirement, citing Microsoft's October 2025 Redirect-becomes-
  default-inside-Azure connection-policy change) — grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (register-scan-azure-sql-managed-instance's full register/scan/prerequisites
  sections including the public-endpoint and Directory-Readers requirements; the Entra
  authentication configuration guide's Managed-Instance-specific admin/Directory-Readers/contained-
  user sections, `CREATE USER ... FROM EXTERNAL PROVIDER` syntax quoted directly; the Azure SQL
  Managed Instance connection-types and connectivity-architecture articles for the October 2025
  Redirect-default change and the Proxy/Redirect NSG port tables; the data-source-readiness-
  checklist article's AzureSQLMI-specific network/RBAC checklist; and — the headline grounding
  improvement over the sibling scenario — direct fetches of all four canonical REST reference pages
  (Data Sources - Create Or Replace, Scans - Create Or Replace, Triggers - Create Or Replace, Scan
  Result - Run Scan / List Scan History) at API version `2023-09-01`, which the sibling scenario's
  own build could not reach for three of the four and had reconstructed from SDK/PowerShell
  signatures instead — two of those reconstructed shapes turned out to not match the confirmed
  contract (Run Scan's action-style POST; List Scan History's nested asset-count fields), corrected
  here and logged as a backport follow-up rather than silently repeated) — two items recorded as
  explicit VERIFY rather than resolved by guessing (the default public-endpoint port; the
  `AzureSqlDatabaseManagedInstanceCredential` credential-object REST creation gap, carried over
  unchanged from the sibling scenario), per `AGENTS.md` §4 — 2026-09-04
- [x] `scenarios/ediscovery/location-scoped-legal-hold/` — third **follow-up expansion** fragment
  (eDiscovery), closing the item `premium-legal-hold-and-export/design.md` §3/§7 explicitly scoped
  out: the `ediscoveryHoldPolicy` (`POST .../legalHolds`) path for a hold organized around a
  *location* (a shared departmental mailbox, a regulatory-sweep distribution list, a SharePoint
  site) rather than a named custodian. Full README (12-section skeleton), design.md (grounds why
  this is a genuinely separate v1.0 object model — narrower `userSource` shape (`mailbox`-only,
  siteSources split out as their own collection, unlike the custodian shape's combined `"mailbox,
  site"` string), the distribution-list-expansion evidence trail (a beta reference documenting
  group-mailbox support + the "Distribution group has too many members" >1,000 error, vs. the v1.0
  endpoint's own narrower "SMTP address of the user" wording), and the headline finding that
  `enablePolicy`/`disablePolicy` exist only in the beta namespace — v1.0 has no reversible
  "turn off and keep for later," only delete-one-source or delete-the-whole-policy, both
  Microsoft-documented as capable of **permanently deleting content currently being preserved**),
  deploy/ (`New-EdiscoveryLocationHold.ps1` — reuses the sibling scenario's typed
  `New-MgSecurityCaseEdiscoveryCase` cmdlet for the case, then `Invoke-MgGraphRequest` against the
  v1.0 REST endpoints directly for the hold policy/userSources/siteSources/retryPolicy, since no
  v1.0 typed cmdlet exists for any of them (only `Microsoft.Graph.Beta.Security` has one); a
  hand-rolled `$PSCmdlet.ShouldProcess()` gate around every write for a true `-WhatIf`; an optional
  `-Retry` that calls `retryPolicy` only when the policy reports errors or an unhealthy source; an
  optional `-WaitForApplied` poll switch (added during Blue Team review to mirror the sibling
  scenario's `-WaitForHold`); a loud `Write-Warning` when `contentQuery` is left blank (added
  during Red Team review — an unfiltered hold on every location's content); `Remove-
  EdiscoveryLocationHold.ps1` — release one or more named userSources/siteSources, or `-DeleteHold`
  for the entire policy, both paths carrying Microsoft's own permanent-deletion warning quoted
  verbatim rather than softened; `deploy/policy/location-hold-definition.json` — a Payments-team
  shared mailbox + compliance distribution list + SharePoint site, `contentQuery` scoped to a CID
  date range), validate/ (`Test-EdiscoveryLocationHold.ps1` — read-only checks of the case, hold
  policy, every declared userSource/siteSource's `holdStatus`, the policy's own `errors`
  collection, and a `WARN` on a blank `contentQuery`), rollback.md (the two-stage release-one/
  delete-all procedure with the counsel-confirmation gate promoted to a `README.md` §3 gating
  prerequisite from the outset, applying the precedent the sibling scenario's own CISO review round
  established), four-lens reviews.md (Red Team Fix round resolved — sharpened the
  distribution-list-expansion VERIFY with a concrete pilot-tenant verification step rather than a
  generic caveat, added the blank-`contentQuery` warning, confirmed the `siteSource`
  title-matching weak point never risks holding the *wrong* site's content, only an idempotency
  false-positive/negative on this scenario's own bookkeeping; Blue Team Fix round resolved — added
  `-WaitForApplied` and the blank-`contentQuery` `WARN`, confirmed `retryPolicy`'s
  restamp-everything behavior was already correctly disclosed as a deliberate, human-triggered
  action; CISO Pass — confirmed the counsel-confirmation gate and the higher-stakes
  no-reversible-pause framing were both already applied proactively in the initial draft; Product
  Owner Pass — independently re-confirmed the beta-only enable/disable finding via direct fetches
  of the v1.0 resource/update references and both beta action pages, and called out the
  `mailbox`-only `userSource` finding as *more* directly grounded than the sibling scenario's own
  open VERIFY on the same property family) — grounded in Microsoft Learn via the Microsoft Learn
  MCP tool (`ediscoveryHoldPolicy` v1.0 resource/create/update/delete/retryPolicy references;
  `userSource`/`siteSource` v1.0 resource + create + delete references for the `legalHolds`
  context specifically, distinct from the custodian-context ones the sibling scenario cites; the
  beta `enablePolicy`/`disablePolicy` action pages confirming no v1.0 equivalent exists; the beta
  custodian-context `userSource` create reference for the group-mailbox-email corroboration; and
  "Manage holds in eDiscovery" for the portal-side hold-policy-states, retry/turn-off/delete
  procedures with their permanent-deletion warnings quoted verbatim, the full "Manage hold status
  errors" table, and the Teams/Microsoft 365 Group hold-placement guidance) — two real gaps
  (distribution-list expansion on the exact v1.0 endpoint; `siteSource` URL-vs-title matching)
  recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md` §4.
  (2026-09-04)
- [x] `scenarios/unified-catalog/manage-data-products/` — second **follow-up expansion** fragment
  (Unified Catalog, Data Governance), closing the shared "Data Products scenario doesn't exist yet"
  dependency both `curate-business-glossary`'s and `data-quality/rules-and-scorecards`'s non-goals
  pointed to: full README (12-section skeleton), design.md (grounds the choice of the newly-added
  2026-03-20-preview `Data Assets` operation group over the raw Data Map/Atlas entity API, and the
  distinction between the REST API's `Policies` operation group — the RBAC authorization-policy
  engine — and the portal's unrelated "data product access policy" feature), deploy/
  (`New-DataProduct.ps1` — idempotent/parameterized Purview Unified Catalog REST automation
  (surface 4) plus a Microsoft Graph owner-resolution call (surface 3, reusing
  `curate-business-glossary`'s UPN→Entra-object-ID pattern) that create-or-updates a "Customer
  Master Data" data product in an existing governance domain, wraps the `scan-azure-sql-and-
  classify`-scanned `customerdb.dbo.Customers` Data Map asset as a Unified Catalog data asset
  (`POST dataAssets` with `source.assetId`, idempotent via the `sourceAssetIds` Query filter), and
  links both that asset and the `Customer`/`Customer ID` glossary terms to the product via `Data
  Products - Create Relationship`, list-before-create idempotent; `-Publish` gate with a loud
  pre-publish warning naming the portal-only data-product-access-policy prerequisite Microsoft's
  own docs require before Publish; `Remove-DataProduct.ps1` — staged unpublish (default) →
  `-RemoveLinks` (delete both relationships, never the shared asset wrapper or terms) →
  `-Purge` (delete the data product; `-DeleteDataAssetWrapper` opt-in and explicitly unchecked
  against orphaning another product's link); `deploy/config/
  customer-master-data-product.sample.json`), validate/ (`Test-DataProduct.ps1` — read-only checks
  of the product's fields/status, the data asset wrapper (reporting its Data-Map-sourced
  classifications as a live cross-check into `scan-azure-sql-and-classify`'s own output), and both
  relationships), four-lens reviews.md (Red Team Fix round resolved — publish-gate-bypass risk
  elevated to a loud warning + README gating prerequisite, orphan-wrapper-deletion risk confirmed
  unfixable in tooling and documented instead, domain-scoped-role risk inherited by reference from
  `curate-business-glossary`; Blue Team Fix round resolved — classification-report and
  access-request-backlog scope boundaries clarified as portal-only, not scripting gaps; CISO Fix
  round resolved — PAYG cost-activation contrast stated locally in §10, access-governance narrative
  sharpened, publish-gate VERIFY promoted to a tracked finding; Product Owner Fix round resolved —
  closed a near-miss conflation of the REST `Policies` group with the portal's access-policy
  feature before it shipped, documented the portal-vs-REST `type` enum label mismatch, independently
  confirmed the newer Data Assets surface and the bulk-import-avoidance reasoning) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (Unified Catalog API overview + release notes
  confirming Data Assets/Data Columns as newly added in `2026-03-20-preview`; the Data Products and
  Data Assets REST operation groups directly fetched — Create/Update/Delete/Get/List/Query/Create
  Relationship/List Relationships/Delete Relationship for both, plus Data Assets' `sourceAssetIds`
  Query filter; Create and manage data products, incl. the exact Publish-gating prerequisite
  quote; Manage data product access policies; Master data management in Microsoft Purview's
  five-step register→create→link→curate flow this scenario automates; Data governance roles and
  permissions for Data Product Owner; data governance billing + FAQ for the per-governed-asset PAYG
  trigger; the `Policies - List` operation's own worked example, directly inspected to rule out
  conflating it with the portal's access-policy feature) — the Create Relationship body-shape
  ambiguity and the publish-gate server-side-enforcement question both recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4. (2026-09-04)
- [x] `scenarios/records-management/graph-event-automation/` — first **follow-up expansion** fragment
  (Records Management, Microsoft Graph surface 2/3), the automation complement to the PowerShell
  regulatory-records-disposition scenario: full README (12-section skeleton), design.md, deploy/
  (`New-GraphRetentionEvent.ps1` — `Invoke-MgGraphRequest` against the v1.0 records-management API that
  ensures a retention **event type** exists via GET/POST `/security/triggerTypes/retentionEventTypes`
  (create-or-report by displayName, `@odata.nextLink` paging) and — **double-gated** behind `-FireEvent`
  **and** config `event.fire=true`, always through `$PSCmdlet.ShouldProcess` (real `-WhatIf`) — fires a
  retention **event** via POST `/security/triggers/retentionEvents` (`eventQuery` files/messages +
  AssetID/keywords, `eventTriggerDateTime`, `retentionEventType@odata.bind`), reporting Graph-native
  `eventStatus`/`eventPropagationResults`; `Remove-GraphRetentionEvent.ps1` — deletes matching event
  records and, with `-DeleteEventType`, the event type, with the loud note that deleting an event does
  NOT stop retention already started; `deploy/config/graph-event-automation.sample.json` — Contract
  Expiration event type + asset-ID-scoped event with `fire=false`), validate/
  (`Test-GraphRetentionEvent.ps1` — read-only GET checks of the event type + report of fired events and
  per-workload propagation), four-lens reviews.md (Red Team Fix round resolved — scoped events,
  double-gated + ShouldProcess fire, high-privilege app identity, deletion-isn't-undo; Blue Team Fix
  round resolved — per-workload propagation reporting, nextLink paging, real `-WhatIf`; CISO Fix round
  resolved — auditable automated triggering; Product Owner Fix round resolved — doc quirks
  (`@odata.bind` singular/plural, `eventQuery`/`eventQueries`) flagged) — grounded in Microsoft Learn
  (records-management API overview, create retentionEvent/retentionEventType, eventQuery, permission
  `RecordsManagement.ReadWrite.All`, typed cmdlets `New-MgSecurityTriggerTypeRetentionEventType` /
  `New-MgSecurityTriggerRetentionEvent` verified); uses Microsoft's supported path (REST event API
  deprecated), a fired event is treated as irreversible. (2026-09-04)
- [x] `scenarios/records-management/regulatory-records-disposition/` — seventh Risk & Compliance
  scenario (Records Management), a genuinely distinct records-management lifecycle vs. the DLM sibling:
  full README (12-section skeleton), design.md, deploy/ (`New-RecordsDisposition.ps1` — SCC PowerShell
  (surface 1) that builds the *event-anchored* disposition lifecycle: `New-ComplianceRetentionEventType`
  → `New-ComplianceTag -RetentionType EventAgeInDays -RetentionAction KeepAndDelete -EventType
  -ReviewerEmail -IsRecordLabel` (event-based record label ending in a **disposition review**, not
  auto-delete) → `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule -PublishComplianceTag`
  (**publish**, not auto-apply) → **gated** `New-ComplianceRetentionEvent` created only with
  `-TriggerEvent` **and** config `event.create=true` because a triggered event is irreversible;
  create-or-report idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud
  warnings on the two irreversible edges (triggered event can't be cancelled; applied record label
  can't be deleted) and on un-scoped events / missing reviewer; `Remove-RecordsDisposition.ps1` —
  disable publish policy by default, `-Delete` removes policy/rule and *attempts* (reports, never
  forces via `-ForceDeletion`) label + event-type removal; `deploy/config/records-disposition.sample.json`
  — Contract Expiration event type + event-based record label + publish policy + asset-ID-scoped event
  with `create=false`), validate/ (`Test-RecordsDisposition.ps1` — read-only Get-* checks of event
  type, label action/type/event-binding/record-flag/reviewer, publish policy enabled + locations, rule
  `PublishComplianceTag`, and an informational report of already-triggered events), four-lens reviews.md
  (Red Team Fix round resolved — asset-ID-scoped events, gated irreversible trigger, reviewer-required
  disposition, governed teardown; Blue Team Fix round resolved — event-triggered reporting, separate
  Disposition Management RBAC, working `-DryRun`; CISO Fix round resolved — examiner-grade schedule
  reproducibility; Product Owner Fix round resolved — limits/latency/immutability documented) — grounded
  in Microsoft Learn (event-driven-retention, disposition, New-ComplianceTag/-ComplianceRetentionEventType/
  -ComplianceRetentionEvent with Get/Remove `-Identity` verified, `-PublishComplianceTag`); this
  **completes a starter scenario for every Purview module** — remaining work is the follow-up expansion
  backlog above. (2026-09-04)
- [x] `scenarios/information-barriers/segregate-trading-and-research/` — sixth Risk & Compliance
  scenario (Information Barriers), and the last remaining Risk & Compliance **starter** (every module
  now has a starter scenario): full README (12-section skeleton), design.md, deploy/
  (`New-TradingResearchBarrier.ps1` — SCC PowerShell (surface 1) that builds an ethical wall:
  `New-OrganizationSegment` per side from an Entra attribute filter + two one-way
  `New-InformationBarrierPolicy -SegmentsBlocked` policies created **-State Inactive**, and — only with
  `-Activate` — `Set-InformationBarrierPolicy -State Active` + `Start-InformationBarrierPoliciesApplication`;
  safe-by-default (staged inactive, no user impact until explicit activation); create-or-report
  idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud live-communication-impact
  warnings; `Remove-TradingResearchBarrier.ps1` — staged deactivate → `-Apply` to lift the wall →
  `-Delete` policies + segments, with the deactivation-needs-application trap called out;
  `deploy/config/trading-research-barrier.sample.json` — Trading/Research segments + both block pairs),
  validate/ (`Test-TradingResearchBarrier.ps1` — read-only Get-* checks of both segments, both block
  policies + assignment + Active state (`-RequireActive`), and application status), four-lens reviews.md
  (Red Team Fix round resolved — both-direction + mutually-exclusive-segment wall, safe-by-default
  activation + no-collateral test, app-only/non-IB edges, governed deletion; Blue Team Fix round
  resolved — application-status detection + `-RequireActive`, deactivation-needs-apply trap, working
  `-DryRun`; CISO Fix round resolved — examiner-grade reproducibility; Product Owner Fix round resolved
  — IB modes/timings documented) — grounded in Microsoft Learn (Get started with Information Barriers:
  segments/block-policies/apply + one-policy-per-segment + two-one-way-policies pattern, multi-segment
  IB modes and limits, New-OrganizationSegment / New-InformationBarrierPolicy /
  Start-InformationBarrierPoliciesApplication references, IB attributes, SharePoint IB enablement + 24h
  propagation, Teams block behavior, troubleshooting) — no invented cmdlets; activation's
  live-communication impact treated as a first-class safety constraint, per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/data-lifecycle-management/retention-labels-financial-records/` — fifth Risk &
  Compliance scenario (Data Lifecycle / Records Management): full README (12-section skeleton),
  design.md, deploy/ (`New-FinancialRecordsRetention.ps1` — SCC PowerShell (surface 1) that creates a
  **regulatory record** retention label (`New-ComplianceTag -Regulatory $true -RetentionAction Keep
  -RetentionDuration 2555 -RetentionType CreationAgeInDays` — SEC 17a-4-style WORM immutability, a
  PowerShell-only capability the portal hides), an **auto-apply** label policy
  (`New-RetentionCompliancePolicy` with finance SharePoint location), and the rule binding them
  (`New-RetentionComplianceRule -ApplyComplianceTag -ContentMatchQuery`); **create-or-report**
  idempotency via Get-* (never silently mutates high-consequence retention objects); custom `-DryRun`
  (S&C `-WhatIf` non-functional); loud irreversibility warnings; `Remove-FinancialRecordsRetention.ps1`
  — staged disable → `-Delete` policy/rule, and `-TryRemoveLabel` that reports the expected refusal for
  a regulatory record in use rather than forcing it; `deploy/config/
  financial-records-retention.sample.json`), validate/ (`Test-FinancialRecordsRetention.ps1` —
  read-only Get-* checks of label action/duration/record flags, policy enabled + locations +
  distribution status, and the rule's applied label), four-lens reviews.md (Red Team Fix round
  resolved — over-scoping guardrails (dry-run, narrow query, lab-test + Records/Legal sign-off),
  least-restrictive-control ladder, create-or-report + no force-release of records; Blue Team Fix round
  resolved — working `-DryRun`, auto-apply latency/RetryDistribution/DistributionStatus, validate
  pre-flight; CISO Fix round resolved — irreversibility as a governance gate; Product Owner Fix round
  resolved — PowerShell-only regulatory records + the retention-strength ladder documented) — grounded
  in Microsoft Learn (New-ComplianceTag / New-RetentionCompliancePolicy / New-RetentionComplianceRule
  references incl. -Regulatory/-IsRecordLabel/-RetentionAction/-RetentionType/-ApplyComplianceTag,
  records-management immutability semantics, auto-apply latency/limits, retention cmdlets overview) —
  a deliberately conservative scenario given regulatory records are irreversible; no invented cmdlets,
  per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/audit/premium-audit-investigation/` — fourth Risk & Compliance scenario (Audit
  Premium), a **read-only forensic investigation** built on the **Microsoft Graph Audit Search API**
  (v1.0 `security` namespace, surface 3): full README (12-section skeleton), design.md, deploy/
  (`Invoke-AuditInvestigation.ps1` — an async investigation runner via `Invoke-MgGraphRequest`:
  `POST /security/auditLog/queries` to create the search job from a JSON config (target UPNs, time
  window via `lookbackDays` or explicit ISO dates, a crucial-events `operationFilters` preset,
  optional record-type/keyword/IP filters), polls `GET .../queries/{id}` until a terminal status
  (defensive running-set exclusion + `succeeded`-like check, bounded `-PollTimeoutMinutes`),
  retrieves `GET .../queries/{id}/records` with `@odata.nextLink` paging, and exports CSV (key
  fields) + JSON (full `auditData`) with a top-operations summary; `-WhatIf` previews the query body
  without creating the job; read-only — no tenant mutation; `deploy/config/
  audit-investigation.sample.json` — an account-compromise crucial-events preset (MailItemsAccessed
  [Premium], Send/SendAs, New-/Set-InboxRule, Add-MailboxPermission, FileDownloaded,
  AnonymousLinkCreated, UserLoggedIn/UserLoginFailed, role/user changes)), validate/
  (`Test-AuditInvestigation.ps1` — Graph connectivity + `AuditLogsQuery*` scope + config validation
  + a live 1-hour probe query proving API/permission/audit availability), rollback.md (read-only:
  no tenant state to undo — focuses on securing/disposing the exported evidence and the 30-day
  auto-retained job), four-lens reviews.md (Red Team Fix round resolved — export-as-evidence
  handling, least-privilege service-scoped permissions, read-only/no-tamper posture, ingestion-lag
  false-negative warning; Blue Team Fix round resolved — async polling + paging, triage
  summary/runbook, live readiness probe; CISO Fix round resolved — defensibility/breach-clock
  foregrounded; Product Owner Fix round resolved — Graph async API over classic
  Search-UnifiedAuditLog, status-enum VERIFY) — grounded in Microsoft Learn (auditing solutions
  overview + Standard-vs-Premium capability comparison + service description for crucial events and
  retention tiers, the Audit Search Graph API create/get/list-records references incl. body filters
  and the recordType enum and AuditLogsQuery permission set, audit-search ingestion-latency/job
  limits, and the classic Search-UnifiedAuditLog caps) — the `auditLogQueryStatus` terminal values
  and current crucial-events list recorded as explicit VERIFY items rather than fabricated, per
  `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/ediscovery/premium-legal-hold-and-export/` — first eDiscovery-module scenario,
  and the first Risk & Compliance scenario in this repo built against a Purview surface with a
  **rich, fully app-only-supported write API** (the opposite grounding challenge from
  `assess-against-iso27001`/`harassment-and-code-of-conduct`, which had none): full README
  (12-section skeleton; a promoted §3 gating prerequisite requiring counsel confirmation before
  any hold release, added during the CISO review round), design.md (grounds the mandatory
  Graph-not-S&C-PowerShell choice across Microsoft's own "app-only auth for eDiscovery cmdlets is
  unsupported" statement, explains the two-separate-API authoring-vs-download architecture, and
  documents the deliberate choice of custodian-scoped `applyHold` over the sibling
  `ediscoveryHoldPolicy` location-scoped hold object), deploy/ (`New-EdiscoveryPremiumLegalHold.ps1`
  — idempotent/parameterized Microsoft Graph automation (surface 3, `microsoft.graph.security`
  v1.0 namespace) that finds-or-creates an eDiscovery (Premium) case, custodians, and their
  mailbox+OneDrive userSources, then applies hold, using every Graph SDK cmdlet's native
  `SupportsShouldProcess` for a true `-WhatIf` dry run rather than a hand-rolled one;
  `New-EdiscoverySearchReviewSetExport.ps1` — finds-or-creates a case-custodian-scoped search,
  commits it to a review set via the asynchronous `addToReviewSet` `caseOperation`, and starts an
  export, polling both long-running operations against the exact v1.0 `caseOperationStatus` enum
  rather than assuming synchronous completion or reusing beta-namespace casing;
  `Get-EdiscoveryExportPackage.ps1` — a parameterized, idempotent (skip-if-already-downloaded)
  adaptation of Microsoft's own published `DownloadExportUsingAppCert.ps1` reference script for
  the *separate*, non-Graph Purview eDiscovery download API and its own `MSAL.PS` token;
  `Remove-EdiscoveryPremiumLegalHold.ps1` — staged rollback (release named custodian(s) → close
  case → delete case, each stage behind its own explicit switch) using the confirmed v1.0
  `ediscoveryCustodian: release` action and `caseStatus` enum; a JSON case/custodian/search/
  reviewSet/export definition file all four scripts share as the single source of truth), validate/
  script (`Test-EdiscoveryPremiumCaseSetup.ps1` — read-only, `eDiscovery.Read.All`-only checks of
  case/custodian/hold-status/userSource/search/review-set state, plus an opt-in export-age check
  against the documented 30-day download window), rollback.md (four explicit stages from
  targeted-custodian release through permanent case deletion, with an up-front warning that
  releasing a hold before the preservation duty lapses can itself be a spoliation event), four-lens
  reviews.md (Red Team Fix round resolved — added an audit-visibility subsection to README.md §8
  naming the gap in per-actor hold-release/case-lifecycle history and pointing to
  `Search-UnifiedAuditLog` as the correct channel rather than fabricating the exact eDiscovery
  audit RecordType/Operations values, and flagged that a custodian's mailbox+OneDrive hold does
  not cover Teams channel messages without an added non-custodial data source; Blue Team
  clarifications — confirmed the weekly validate-script review cadence and the download-step's own
  status check already mitigate the async-timeout risk raised; CISO Fix round resolved — promoted
  the legal-counsel-confirmation-before-hold-release requirement from `rollback.md` alone to a
  gating README §3 prerequisite; Product Owner Pass — independently re-confirmed the
  Graph-not-S&C-PowerShell finding, verified the one cmdlet name inferred by naming-pattern analogy
  (`New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource`) actually exists before citing it, and
  confirmed strict v1.0-vs-beta namespace discipline throughout) — grounded in Microsoft Learn via
  the Microsoft Learn MCP tool (`edisc-hold-create`, `edisc-settings-cases`/`-general`,
  `edisc-permissions` including its app-only-auth-unsupported section,
  `edisc-ref-api-guide`/`security-ediscovery-appauthsetup` for the full two-API app-only setup
  sequence and the published PowerShell download-script examples this repo's
  `Get-EdiscoveryExportPackage.ps1` adapts, `edisc-cases-manage`, `edisc-search-add-to-review-set`,
  `edisc-review-set-export` (including the official-not-just-community-sourced 30-day download-
  window statement), `edisc-hold-report`, `edisc-ref-limits`, `edisc-billing`, `ediscovery`'s
  Standard/Premium capability comparison, and eleven-plus REST/PowerShell reference pages directly
  fetched at v1.0 — `ediscoveryCase`, `ediscoveryCustodian` (including its `applyHold`/`release`/
  `activate` action set), `ediscoveryHoldPolicy`, `ediscoverySearch`, `ediscoveryReviewSet`
  (`addToReviewSet`/`export`), `caseOperation` (confirming the exact `caseOperationStatus` enum
  distinct from beta's casing/shape), and the `New-`/`Get-`/`Add-`/`Export-`/`Update-`/`Remove-`
  `MgSecurityCaseEdiscoveryCase*` PowerShell cmdlet family) — one REST-shape ambiguity (the
  `userSource.includedSources` combined-string form) recorded as an explicit VERIFY rather than
  resolved by guessing, per `AGENTS.md` §4 — 2026-09-04

- [x] `scenarios/communication-compliance/harassment-and-code-of-conduct/` — first Communication
  Compliance-module scenario, and the second scenario in this repo (after
  `scenarios/compliance-manager/assess-against-iso27001/`) built against a Purview surface with
  **no write API** — Microsoft's own docs state "PowerShell isn't supported for creating and
  managing Communication Compliance policies" verbatim on two independently-fetched pages: full
  README (12-section skeleton, an up-front scope note explaining why this scenario's shape differs
  from the DLP/Information Protection scenarios, a promoted gating prerequisite for
  employment-counsel monitoring-notice review), design.md (grounds the no-write-API finding across
  two independently-fetched Microsoft Learn pages plus the legacy `New-SupervisoryReviewPolicyV2`
  cmdlet's continued-but-unsupported presence in the module reference, explains the Investigators-
  vs-Analysts reviewer-role choice, and documents why a custom keyword dictionary was scoped to
  evasion/concealment phrases rather than duplicating classifier-covered profanity/slurs), deploy/
  (a reference-only, explicitly non-executable `communication-compliance-policy-manifest.json` for
  the portal-driven policy-creation runbook — the same pattern `assess-against-iso27001` and
  `departing-employee-data-theft` already established for other no-write-API Purview surfaces —
  plus a genuinely uploadable `code-of-conduct-evasion-phrases.txt` custom keyword dictionary, and
  the one genuinely scriptable piece: `Export-CommunicationComplianceAuditTrail.ps1`, idempotent/
  parameterized Exchange Online PowerShell automation (surface 1) that runs three separate
  `Search-UnifiedAuditLog` queries mirroring Microsoft's own three distinct worked-example
  RecordType/Operations shapes — `SupervisionRuleMatch` alone, `RecordType Discovery` +
  `SupervisionPolicyCreated`/`Updated`/`Deleted`, and `RecordType AeD` + `SupervisoryReviewTag` —
  rather than guessing a single unified query covers all five operation values, merging into a
  rolling CSV de-duplicated by a composite key hashing the full `AuditData` JSON payload;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only queries and
  reports would-be merge counts), validate/ script (`Test-CommunicationComplianceAuditTrail.ps1` —
  automated CSV schema/de-duplication/category/operation/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the policy's existence/scope/classifiers/
  reviewers/anonymization/notice-template/storage-limit health, none of which have a read API
  either), rollback.md (staged pause → revoke access → delete for the portal-only policy, a
  dedicated note on the separate, non-deletable User-reported messages system policy, and the
  audit-trail script's independent schedule/CSV/role rollback), four-lens reviews.md (Red Team Fix
  round resolved — flagged that publishing a real tenant's exact keyword-dictionary contents
  undermines it, distinguished the non-transcribed-Teams-meeting gap from the general off-platform
  limitation, and elevated storage-limit auto-deactivation to an actively-monitored KPI rather than
  a background fact; Blue Team Fix round resolved — added an explicit phased-pilot-before-All-users
  rollout recommendation; CISO Fix round resolved — promoted the monitoring-notice/consent VERIFY
  item from a Known Limitations footnote to a gating README §3 prerequisite; Product Owner Fix round
  resolved — re-confirmed the Harassment/Targeted-harassment naming inconsistency, the correct
  exclusion of preview content-safety classifiers for Exchange coverage, and the correct exclusion of
  custom trainable classifiers, which Communication Compliance doesn't support) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (communication-compliance-solution-overview,
  -policies, -plan, -configure, -permissions, -investigate-remediate, -siem, -reports-audits,
  -alerts-best-practices, audit-log-activities' Communication compliance activities table,
  Search-UnifiedAuditLog and New-SupervisoryReviewPolicyV2 reference pages, and the Microsoft
  Purview service description's Communications Compliance licensing table) plus WebSearch grounding
  for the regulatory driver (Title VII/*Faragher*/*Ellerth* case-law framework, and — caught mid-
  build — the EEOC's January 23, 2026 rescission of its 2024 sub-regulatory harassment guidance,
  which changed this scenario's citation from "current EEOC guidance" to "rescinded guidance;
  statute and case law still stand," tagged VERIFY per `AGENTS.md` §4 rather than left stale) —
  2026-09-04

- [x] `scenarios/compliance-manager/assess-against-iso27001/` — first Risk & Compliance-module
  scenario, and the first scenario in this repo built against a Purview surface with **no write
  API**: full README (12-section skeleton, explicit up-front note on why this scenario's shape
  differs from every prior one), design.md (grounds the no-write-API finding across three
  independently-fetched Microsoft Learn articles plus this repo's own `docs/automation-surface.md`
  routing-table gap, explains why a dedicated assessment beats extending the default Data
  Protection Baseline, and documents the built-in-automation evidence-feed mechanism without
  fabricating Microsoft's proprietary per-control mapping), deploy/ (a reference-only, explicitly
  non-executable `iso27001-assessment-manifest.json` for the portal-driven assessment-creation
  runbook — the same pattern `scenarios/insider-risk/departing-employee-data-theft/` already
  established for another no-write-API Purview surface — plus the one genuinely scriptable piece:
  `Export-ComplianceManagerAuditTrail.ps1`, idempotent/parameterized Exchange Online PowerShell
  automation (surface 1) that pulls the exactly three Compliance-Manager-specific operations
  Microsoft's audit log documents (`ComplianceManagerRolesChange`,
  `ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange`), merging into a
  rolling CSV de-duplicated by a composite key that deliberately avoids assuming an unconfirmed
  flat `ObjectId` output property exists — instead hashing the full `AuditData` JSON payload —
  with a best-effort, non-authoritative `ObjectId` extraction surfaced only as a display column;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only query and
  reports would-be merge counts), validate/ script (`Test-ComplianceManagerAuditTrail.ps1` —
  automated CSV schema/de-duplication/operation-value/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the assessment's existence/scope/group/role
  assignments, none of which have a read API either), rollback.md (the first in this repo to
  separate a portal-only object's rollback — staged scope-down/access-revocation/deletion, all
  manual — from a scripted artifact's rollback — schedule + role removal — as two independent
  procedures), four-lens reviews.md (Red Team Fix round resolved — flagged that the audit-trail
  script is blind to Compliance Manager access granted implicitly via the Global Administrator/
  Compliance Administrator/Compliance Data Administrator/Security Administrator Entra roles, none
  of which trigger a `ComplianceManagerRolesChange` event, and that the native Reports page's
  6-month history isn't durably preserved by this scenario — both closed with documented
  operational mitigations rather than fabricated code fixes; Blue Team clarifications — confirmed
  the manual-checklist and alert-routing scope boundaries match this repo's own established
  precedent in `departing-employee-data-theft`/`pci-teams-exfil-block`; CISO Pass; Product Owner
  Fix round resolved — independently re-confirmed the no-write-API finding, flagged a VERIFY on
  ISO 27001:2013-vs-2022 template currency, and confirmed Compliance Manager role-name/role-group
  naming accuracy) — grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (`compliance-manager-assessments`, `compliance-manager-update-actions`,
  `compliance-manager-setup`, `compliance-manager-improvement-actions`,
  `compliance-manager-regulations`/`-regulations-list`, `compliance-manager-faq`, the ISO 27001
  regulatory-offering page, `audit-log-activities`'s Compliance Manager activities table,
  `Search-UnifiedAuditLog`'s own reference page plus two independent worked-example pages, and
  `audit-log-retention-policies` for the 180-day/1-year/10-year retention tiers) — three real bugs
  caught and fixed during a post-draft self-review before this fragment was finalized: an
  unconfirmed flat `ObjectId` property assumed on `Search-UnifiedAuditLog` output (replaced with a
  hash-of-`AuditData` composite-key component plus a clearly-labeled best-effort display column), a
  process-randomized `[string]::GetHashCode()`-style hash that would have silently broken
  cross-run de-duplication (replaced with `MD5.ComputeHash`), and a single-object-vs-array paging
  loop that could misbehave when a page returned exactly one record (fixed by wrapping in `@()`
  before checking `.Count`) — 2026-09-03

- [x] `scenarios/data-estate-insights/classification-coverage-report/` — first Data Estate
  Insights-module scenario: full README (12-section skeleton), design.md, deploy/
  (`Export-ClassificationCoverageReport.ps1` — idempotent/parameterized Purview Data Map Discovery
  REST automation (surface 4, API version `2023-09-01`) that reproduces the native "Classic
  classifications" report's headline KPIs — total/classified/unclassified asset counts and a full
  classification-value histogram, per object type — via two modes: `-Mode Full` (paginated,
  `continuationToken`, page size 1000, tallies each record's `classification[]` array client-side
  since no "has any classification" filter is documented) and `-Mode Facets` (a single faceted query,
  cheaper but top-N-truncated and double-counting, mirroring the native "Top classifications" chart's
  own behavior); requires only the **Data Reader** role — deliberately narrower than the native
  report's own Data-Curator-only "Export to CSV" gate; idempotent via replace-by-`-RunId` in a
  trend-log CSV rather than a create/skip check, since this scenario creates no Purview object to
  check existence against; `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` reports
  computed KPIs without touching disk), validate/ script (`Test-ClassificationCoverageReport.ps1` —
  read-only file-integrity checks (schema, no duplicate RunId+ObjectType rows, per-row arithmetic)
  runnable with no tenant credentials, plus an optional live-reconciliation check against current
  `@search.count`), rollback.md (the first in this repo describing a scenario with **no Purview
  object** to roll back — decommissioning is stopping the schedule, removing the Data Reader role
  assignment, and deciding the fate of already-produced report files), four-lens reviews.md (Red Team
  Fix round resolved — flagged the trend-log/breakdown files themselves as a sensitive artifact
  requiring the same protection as the classifications they summarize, and the `-Mode Facets`
  top-N-truncation as a silent-gap risk; Blue Team Fix round resolved — warning-stream capture
  guidance for unattended runs, and severity-mapping clarity between file-integrity `[FAIL]` and
  live-reconciliation `[WARN]`; CISO Pass; Product Owner Fix round resolved — tightened the
  "Unclassified assets" KPI citation to the specific classic-assets-report page and its exact quoted
  definition) — grounded in Microsoft Learn via the Microsoft Learn MCP tool (the Data Estate
  Insights application overview, classic classifications/assets reports, the Data Estate Insights
  access-control page confirming Data Reader can view but not export while only Data Curator can,
  the "Disable Data Estate Insights" page's weekly-refresh/no-separate-billing notes, the Data
  governance glossary, the data-plane API authentication tutorial, and the Discovery - Query REST
  reference directly fetched at API version `2023-09-01` — request/response shape, `@search.count`
  semantics, `continuationToken` pagination, facets, and worked filter examples including the
  documented `objectType`/`collectionId`/exact-value-`classification` filter shapes) plus a Microsoft
  Q&A thread corroborating (not as primary evidence) that no broader classification-existence filter
  is exposed — one design choice (computing classified/unclassified by client-side pagination rather
  than an invented filter) recorded and justified rather than guessed, per `AGENTS.md` §4; also
  caught and fixed a citation-numbering bug during a post-draft self-review (four `design.md`
  cross-references pointed at the wrong `README.md` reference number) and a scoping bug (an unused,
  fully-redundant `Get-TotalCount` helper function) — 2026-09-03

- [x] `scenarios/data-lineage/end-to-end-lineage-validation/` — first Data Lineage-module
  scenario: full README (12-section skeleton), design.md, deploy/ (`New-CustomLineageRelationship.ps1`
  — idempotent/parameterized Purview Data Map/Atlas v2 REST automation (surface 4, API version
  `2023-09-01`) that creates a `direct_lineage_dataset_dataset` custom lineage relationship (with a
  JSON-encoded `columnMapping` attribute) between two already-scanned `azure_sql_table` assets to
  close a gap left by a non-auto-lineage-integrated custom transform job, existence-checked via
  `Lineage - Get By Unique Attribute` before every `Relationship - Create` POST so idempotency
  doesn't depend on that operation's unconfirmed duplicate-POST behavior; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-CustomLineageRelationship.ps1` —
  looks up each relationship's GUID via the same lineage call and deletes it via the (directly
  confirmed) `Relationship - Delete` operation; a JSON lineage-definition file continuing this
  repo's Customer/customerdb narrative), validate/ script (`Test-EndToEndLineage.ps1` — the
  "end-to-end" half of the scenario's name: walks the full reachable lineage graph from an origin
  asset via a breadth-first traversal of the `Lineage - Get By Unique Attribute` response and
  proves every asset in an independently-declared expected chain is both present *and* connected
  by a walkable path, not merely co-listed; read-only, Data Reader role), rollback.md, four-lens
  reviews.md (Red Team Fix round resolved — documented the Data Curator role's collection-wide
  blast radius, and added an explicit "custom lineage is asserted, not verified" evidentiary-
  honesty note for any compliance narrative built on this graph; Blue Team Fix round resolved —
  sharpened the ambiguous "asset not found" failure mode to name `-MaxDepth` as a possible cause
  alongside a deleted link or stale qualifiedName, and documented the column-mapping check's
  single-hop-from-origin scope assumption as a tracked limitation rather than a silent gap; CISO
  Pass; Product Owner Fix round resolved — clarified that the "classic Data Catalog" citations
  ground lineage *concepts* only, while the REST surface this scenario calls is the current,
  non-deprecated Data Map/Atlas API also read by Unified Catalog's own Lineage tab) — grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (the current, non-legacy "Create and get lineage
  relationships using the REST API" tutorial and its worked Bulk Create/Create Relationship/Get
  Lineage examples; the classic Data Catalog lineage overview/user-guide articles for concepts and
  the auto-lineage-integrated-systems table; the Cloud Adoption Framework's explicit "close gaps
  manually where required" recommendation; the `data-gov-api-custom-types` tutorial confirming the
  `azure_sql_table` type name; the `data-gov-api-rest-data-plane` tutorial confirming Data
  Curator/Data Reader as the Catalog Data plane roles; and four REST operations — Relationship -
  Create, Relationship - Delete, Lineage - Get, Lineage - Get By Unique Attribute — all directly
  fetched from their own canonical REST reference pages at a consistent API version `2023-09-01`,
  a stronger grounding bar than this repo's average scenario) — two items recorded as explicit
  VERIFY rather than resolved by guessing (the exact `azure_sql_table` qualifiedName string format;
  `Relationship - Create`'s duplicate-POST behavior), per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/data-quality/rules-and-scorecards/` — first Data Quality-module scenario: full
  README (12-section skeleton, Public Preview callout up front per Product Owner fix), design.md
  (declarative JSON rule definitions, idempotency design independent of Create Rules' unconfirmed
  create-vs-replace semantics, type-agnostic typeProperties pass-through so no rule-type shape is
  fabricated), deploy/ (`New-DataQualityRulesAndSchedule.ps1` — idempotent/parameterized Purview
  Data Quality REST automation (surface 4, API version `2026-01-12-preview`) that reconciles five
  rules (NotNull/Unique/TypeMatch/Duplicate/CustomTruth, deliberately omitting the Azure-SQL-
  unsupported Freshness rule) against an already-governed "Customer" data asset shared with
  `scan-azure-sql-and-classify`/`curate-business-glossary`'s narrative, plus a one-time (`RunOnce`)
  scan schedule; `-RuleStatus Draft`/`-CreateSchedule:$false` review-first path; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-DataQualityRulesAndSchedule.ps1` —
  staged schedule-only vs. schedule+rules rollback; a JSON rules definition file), validate/ script
  (rule/status/schedule/score checks with a sharpened ambiguous-failure-mode warning), four-lens
  reviews.md (Red Team Fix round resolved — documented the Data Quality Steward role's domain-wide
  blast radius, a Draft-status "quality theater" drift risk, and the example custom rule's weak
  regex; Blue Team Fix round resolved — made portal alert configuration an explicit go-live gate and
  recommended wiring the validate script into a recurring pipeline check; CISO Fix round resolved —
  funding conditionality made explicit via the Blue Team fix; Product Owner Fix round resolved —
  sharpened Public Preview prominence to the README's opening section) — grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (Data Quality overview/rules/scan/scores/alerts/roles-permissions
  articles, the incremental-scan cost rationale, and the Purview Data Quality REST API's Create
  Rules/Get Rules/Create Schedule/Get Schedule/Get Asset Scores For Asset DQ/Create Data Source/
  Delete Rule/Delete Schedule operations directly fetched at API version `2026-01-12-preview`) — four
  gaps (TypeMatch's target-type field, Create Rules' create-vs-replace semantics, the Schedule
  object's recurring-trigger shape, and the unfetched Alerts operations) recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4; also caught and fixed two real bugs
  during a post-draft self-review (a missing `api-version` query parameter on two "list existing
  rules" GET calls that would have 400'd against the live API) — 2026-09-03

- [x] `scenarios/unified-catalog/curate-business-glossary/` — first Unified Catalog-module
  scenario: full README (12-section skeleton), design.md (idempotency design against a
  name-less-unique API, the CSV-bulk-import-can't-update rationale for using REST instead,
  UPN-to-Entra-object-ID owner resolution design), deploy/ (`New-BusinessGlossary.ps1` —
  idempotent/parameterized Unified Catalog REST automation (surface 4) plus a Microsoft Graph
  call (surface 3) to resolve owner/expert UPNs to Entra object IDs; resolves-or-creates a
  governance domain, upserts a small parent/child term hierarchy with acronyms/resources/related-
  term links from a declarative JSON file, `-Publish` gate, manual `$PSCmdlet.ShouldProcess()`
  `-WhatIf` throughout with an explicit `-ReadOnly` bypass for the read-only Query Terms lookup so
  dry-run create-vs-update detection stays accurate; `Remove-BusinessGlossary.ps1` — unpublish
  (reversible, reuses the server's own current fields via GET so it can't clobber a portal-made
  edit) and `-Purge` (permanent delete) rollback; a JSON glossary definition example modeling
  Microsoft's own CAF-recommended Customer/Revenue-style term set), validate/ script (read-only
  content/hierarchy/relationship/publish-status checks), four-lens reviews.md (Red Team Fix round
  resolved — added `User.Read.All` blast-radius compensating controls and stale/departed-owner
  review guidance; Blue Team Fix round resolved — added `systemData` attribution and scheduled-
  validation drift-detection guidance; CISO Pass; Product Owner Fix round resolved — sharpened
  preview-API-surface prominence) — grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (Unified Catalog glossary-terms/governance-domains/roles-permissions/billing/CAF-baseline
  guidance pages, and the Purview Unified Catalog REST API's Terms and Business Domain operation
  groups directly fetched at API version `2026-03-20-preview` — Create/Update/Delete/Get/List/
  Query/AddRelatedEntity/ListRelatedEntities for Terms, Create/Update/Delete/Enumerate for
  Business Domain — plus the Microsoft identity platform client-credentials flow and Graph
  `Get a user`/`User.Read.All` reference for the owner-resolution design) — two REST-schema
  discrepancies recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md`
  §4 — 2026-09-03

- [x] `scenarios/data-map/scan-azure-sql-and-classify/` — first Data Governance-module scenario:
  full README (12-section skeleton), design.md, deploy/ (`New-AzureSqlDataMapScan.ps1` —
  idempotent/parameterized Purview Data Map REST automation (surface 4), registers an
  `AzureSqlDatabase` data source and an `AzureSqlDatabaseMsi` (SAMI-authenticated, credential-free)
  scan against Microsoft's system default scan rule set, with optional recurring trigger and
  `-RunNow`, manual `$PSCmdlet.ShouldProcess()`-wrapped `-WhatIf` throughout since
  `Invoke-RestMethod` has no native ShouldProcess integration; `Remove-AzureSqlDataMapScan.ps1` —
  staged trigger/scan/data-source removal, idempotent on 404; a JSON reference manifest of the
  three REST bodies), validate/ script (read-only config + scan-history check), four-lens
  reviews.md (Red Team Fix round resolved — narrowed the recommended Azure IAM `Reader` scope to
  the SQL Server resource itself instead of resource group/subscription, and flagged the broad
  "Allow Azure services" firewall toggle's tradeoff explicitly; Blue Team Fix round resolved —
  added a four-step incident-response runbook for non-`Succeeded` scan runs and hardened the
  validate script's ambiguous-failure-mode warning; CISO Fix round resolved — added an explicit
  Azure Cost Management budget/alert recommendation given PAYG's uncapped cost-growth model;
  Product Owner Fix round resolved — dropped an unverified custom "PII-only" scan-rule-set default
  in favor of Microsoft's confirmed system default rule set, which already includes the SSN/Credit
  Card Number pair this repo standardizes on) — grounded in Microsoft Learn (Azure SQL Database
  registration/firewall/authentication-options/scan-setup walkthrough and its four supported
  authentication methods' exact T-SQL grants, the Scans - Create Or Replace REST reference
  directly fetched at API version `2023-09-01` with its full `AzureSqlDatabaseMsiScanProperties`
  schema, the Data Map data-plane API-authentication tutorial's service-principal/role-assignment/
  token-acquisition flow, scan run monitoring and 90-day history retention, scan rule set and
  classification-best-practices guidance) plus the `@azure-rest/purview-scanning` JS SDK's type
  definitions and the `Az.Purview` PowerShell module's confirmed cmdlet/parameter surface as
  corroborating (not primary) sources for the three REST operations whose own canonical reference
  pages could not be fetched in this build environment — those three gaps recorded as explicit
  VERIFY items rather than fabricated, per `AGENTS.md` §4 — 2026-09-03

- [x] `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` — full README (12-section skeleton),
  design.md, deploy/ (`New-CopilotSensitiveDataProtectionPolicy.ps1` — idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule DLP policy on the Microsoft 365 Copilot and
  Copilot Chat location: Rule 0 excludes Confidential/Highly Confidential-labeled content from
  Copilot processing via the `-AdvancedRule`/`-RestrictAccess ExcludeContentProcessing` pattern
  reproduced from Microsoft's own `New-DlpCompliancePolicy` reference Example 4, Rule 1 restricts
  external web-search grounding for SSN/Credit-Card-Number-bearing prompts via `-RestrictWebGrounding`;
  cert app-only, `-WhatIf` throughout; `Remove-CopilotSensitiveDataProtectionPolicy.ps1` —
  disable/purge rollback; a policy JSON reference manifest), validate/ script (automated
  policy/rule/alert-wiring checks), four-lens reviews.md (Red Team Fix round resolved — added an
  explicit VERIFY + follow-up on unconfirmed group-scoped pilot rollout rather than implying it
  works; Blue Team Fix round resolved — added missing `GenerateAlert` checks to the validate
  script; CISO Fix round resolved — added an explicit remediation-ownership note so the DLP policy
  isn't mistakenly reported as "oversharing solved"; Product Owner Pass, with the grounding-strength
  distinction between the two rules recorded) — grounded in Microsoft Learn (DSPM for AI classic
  overview and permissions, the DLP-for-Microsoft-365-Copilot-and-Copilot-Chat location's full
  conditions/actions table and licensing tiers, the exact Copilot location GUID and
  `-AdvancedRule`/`-RestrictAccess`/`-RestrictWebGrounding` PowerShell patterns from
  `New-DlpCompliancePolicy`/`New-DlpComplianceRule`'s own published examples, and DSPM for AI's
  one-click-policy catalog) — deliberately declined to script the preview-only "Processing prompts"
  full-block action for lack of a published PowerShell example (flagged VERIFY/follow-up instead)
  — 2026-09-03

- [x] `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/` — full README (12-section
  skeleton), design.md, deploy/ (`New-AdaptiveProtectionDlpPolicy.ps1` — idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule Exchange+Teams DLP policy keyed on the
  `-SharedByIRMUserRisk` condition, Elevated=block/Moderate+Minor=audit, cert app-only, `-WhatIf`
  throughout, mirrors Microsoft's own documented Quick Setup rule values via the custom-setup
  path; `Remove-AdaptiveProtectionDlpPolicy.ps1` — disable/purge rollback; a portal-configuration
  reference manifest for the non-scriptable Adaptive Protection enablement/insider-risk-level
  steps), validate/ script (automated policy/rule/condition checks plus a manual checklist for
  the portal-only pieces), four-lens reviews.md (Red Team Fix round resolved — removed a
  policy-tip wording that would have tipped off a flagged insider mid-investigation, and
  sharpened the Known Limitations section to name the Endpoint-DLP/Conditional-Access/DLM bypass
  gap explicitly rather than as a scoping footnote; Blue Team clarification — manual DLP-to-IRM-
  alert correlation documented in the runbook; CISO Fix round resolved — added a
  feeder-policy-baseline-first recommendation and an HR/Legal-coordination note before broad
  enforcement rollout; Product Owner Fix round resolved — removed an unverified `-ContentIsShared`
  condition in favor of this library's already-grounded `-AccessScope`-only pattern, added
  "(preview)" labels for the Conditional Access/Data Lifecycle Management integrations) —
  grounded in Microsoft Learn (Adaptive Protection overview/configuration/permissions/36-hour
  propagation delay, the documented Quick-Setup DLP rule values for Teams+Exchange this scenario
  reproduces, the Adaptive-Protection-guide's recommended insider-risk-level definitions, and
  independently confirming `New-/Set-DlpComplianceRule -SharedByIRMUserRisk` and its three fixed
  risk-level GUIDs on both cmdlets' own parameter references) — 2026-09-03

- [x] `scenarios/insider-risk/departing-employee-data-theft/` — full README (12-section
  skeleton), design.md, deploy/ (`Send-HrTerminationRecord.ps1` — parameterized/idempotent HR
  resignation-CSV upload via the documented HR-connector ingestion webhook, chunked at the
  500-row limit, SecureString secret handling, `-WhatIf`; `Export-InsiderRiskAlerts.ps1` —
  read-only Graph Security API alert pull with a correctly-grounded client-side
  `detectionSource` filter after discovering `serviceSource` has no IRM enum member; a portal-
  configuration reference manifest, explicitly labeled as non-executable since IRM policy
  authoring has no PowerShell/Graph write API), validate/ script (automated Graph-permission +
  CSV-schema checks plus an explicit manual-verification checklist for the portal-only pieces),
  four-lens reviews.md (Red Team Fix round resolved — 90-day retrospective-lookback boundary and
  HR-connector app-registration scoping/rotation; Blue Team Fix round resolved — alert-export
  dedup/cursor caveat; CISO Fix round resolved — HR-process-dependency visibility gap; Product
  Owner Pass) — grounded in Microsoft Learn (policy templates and triggering-event prerequisites,
  HR connector CSV schema/webhook/auth flow, priority user groups, role groups and Data Connector
  Admin inclusion, Graph security API alert/detectionSource/serviceSource resource definitions,
  SecurityAlert.Read.All permission, insider-risk-to-Defender-portal integration path) plus two
  PowerShell correctness bugs caught and fixed during a syntax self-review (a single-chunk-CSV
  array-unwrapping bug, and a backslash-vs-backtick string-escaping bug) — 2026-09-03


- [x] repo scaffold — AGENTS.md, README, PROGRESS, LICENSE, .gitignore, CONTRIBUTING — 4a79558 — 2026-09-02
- [x] `docs/licensing-matrix.md` — two-model (per-user + PAYG) licensing matrix, grounded in MS Learn — 2026-09-02
- [x] `docs/rbac-model.md` — four-RBAC-system model (Entra, Purview role groups, Data Governance, Exchange Online) + admin units + PowerShell/Graph auth patterns, grounded in MS Learn — 2026-09-03
- [x] `docs/automation-surface.md` — four automation surfaces (EXO/S&C PowerShell, Graph, Data Map REST), module install, app-only auth setup, task-routing table, throttling/CI-CD patterns, grounded in MS Learn — 2026-09-03
- [x] `docs/glossary.md` — canonical A-Z term list spanning all 14 modules (module-tagged, cross-referencing licensing-matrix.md and rbac-model.md), grounded in MS Learn (incl. the official Purview data-governance and Compliance Manager glossaries) — 2026-09-03
- [x] `scenarios/dlp/pci-teams-exfil-block/` — TEMPLATE scenario: full README (12-section skeleton), design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell, cert app-only pattern, -WhatIf throughout), validate script, four-lens reviews.md (Red/Blue Fix rounds resolved; CISO Pass; Product Owner Fix round resolved) — grounded in MS Learn (DLP-for-Teams scoping/licensing, New-/Set-/Remove-DlpCompliancePolicy/Rule reference, Credit Card Number SIT, PCI DSS v4.0.1 Requirement 4.2) — 2026-09-03

- [x] `scenarios/information-protection/auto-label-confidential-sharepoint/` — TEMPLATE-pattern
  scenario: full README (12-section skeleton with a scope note on U.S.-centric SIT coverage),
  design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance
  PowerShell, two rules — one per workload per the `-Workload` cmdlet constraint, cert app-only
  pattern, `-WhatIf` throughout), validate script (explicit config-vs-match-validation caveat),
  four-lens reviews.md (Red Team Fix round resolved — manual-label-first bypass, exclusion-list
  blind spot, and scan-cadence detection gap documented as residual risks; Blue Team Fix round
  resolved; CISO Pass; Product Owner Fix round resolved — added the `EnableSensitivityLabelforPDF`
  prerequisite) — grounded in MS Learn (apply-sensitivity-label-automatically prerequisites and
  override-behavior tables, New-/Set-/Remove-AutoSensitivityLabelPolicy and
  -AutoSensitivityLabelRule reference, DLP policy reference condition-group OR/AND semantics,
  Set-SPOTenant EnableAIPIntegration) — 2026-09-03

- [x] `scenarios/dlp/endpoint-dlp-usb-block/` — full README (12-section skeleton with an
  explicit VERIFY callout on `EndpointDlpRestrictions` Setting/Value strings), design.md,
  idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell,
  `EndpointDlpLocation`/`EndpointDlpRestrictions`, group-based IT Data Custodians audit-only
  exception mirroring the Card Ops pattern, cert app-only, `-WhatIf` throughout), validate script
  (explicit device-onboarding/policy-sync caveat), four-lens reviews.md (Red/Blue Fix rounds
  resolved; CISO Pass; Product Owner Fix round resolved) — grounded in MS Learn (Endpoint DLP
  licensing/service description, device onboarding overview and permissions, DLP policy reference
  device-restriction action semantics, New-/Set-/Remove-DlpCompliancePolicy/Rule reference,
  reuses the SSN + Credit Card Number SIT pair from `auto-label-confidential-sharepoint`) plus a
  Microsoft Security Blog Tech Community PowerShell walkthrough (not independently fetchable in
  this environment — network egress to techcommunity.microsoft.com blocked — corroborated via two
  independent search-tool summaries and tagged VERIFY for pilot-tenant confirmation) — 2026-09-03
- [x] **`scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/`** — a single
  additive, low-severity, non-blocking `PII-Exchange-Audit-Encrypt-Exception` rule added to
  `exchange-pii-exfil-block`'s existing policy, closing the Red-Team-flagged visibility gap in that
  scenario's `README.md` §11: in Encrypt mode, the nominated business-exception group is silently
  excluded from the encrypt rule with no override concept, so its matching external mail leaves the
  tenant in cleartext with zero alert, incident report, or override record. This companion doesn't
  change that outcome — it makes it visible. Full deliverable per `AGENTS.md` §4: `README.md`
  (12-section skeleton), `design.md` (justifies adding one rule to the parent's existing policy
  rather than a new policy or reopening the parent scenario), `deploy/
  New-ExchangePiiEncryptModeAuditCompanion.ps1` (idempotent, requires the parent policy to already
  exist, computes an explicit non-colliding `-Priority` rather than relying on portal creation-order
  defaults, drift-checks the parent's own exclusion rule, `-WhatIf` throughout),
  `deploy/Remove-ExchangePiiEncryptModeAuditCompanion.ps1`, `validate/
  Test-ExchangePiiEncryptModeAuditCompanion.ps1`, `rollback.md`, `reviews.md` (four-lens; Blue Team
  Fix resolved by adding a `-ReportSeverityLevel` parameter — Low/Medium/High — after the initial
  draft hardcoded `Low`, which risked under-triage for a high-risk exception-group population; Red
  Team, CISO, and Product Owner all Pass). Grounded via `microsoft_docs_search` this run: confirmed
  the "hosted service locations... priority in order created" and "matches for all... rules are
  recorded... even though only the most restrictive rule is applied" behavior directly from the
  official Data Loss Prevention policy reference — new grounding not previously cited by the parent
  scenario, now feeding this fragment's explicit-priority-computation design decision. No new
  cmdlets or parameters beyond what the parent scenario already grounded.
  Commit: `04191a9`. Date: 2026-09-05.
- [x] Removable USB device groups grounding pass (`scenarios/dlp/endpoint-dlp-usb-block/` §11/§12,
  `design.md` §6–7) — **investigated, not built**: confirmed the portal workflow end-to-end
  (create the device group in Endpoint DLP settings by Vendor ID/Product ID/Instance ID, add an
  alias, then reference it as an exclusion in a rule's actions/exceptions) via the official
  `dlp-configure-endpoint-settings` reference and a Microsoft Q&A answer describing the same
  rule-level exclusion step. Found the PowerShell layer more thoroughly undocumented than the
  original backlog item scoped: not just the per-rule reference syntax, but `Set-PolicyConfig
  -DlpRemovableMediaGroups`'s own hashtable shape, and the same for all four sibling device-group
  parameters (`-DlpPrinterGroups`/`-DlpNetworkShareGroups`/`-DlpAppGroups`/`-DlpExtensionGroups`)
  — every one of their descriptions and the cmdlet's entire `EXAMPLES` section are unpublished
  placeholder text in Microsoft's own reference (confirmed by direct fetch of the underlying
  `office-docs-powershell` source, since `learn.microsoft.com` itself is blocked by this
  environment's egress proxy for direct fetches — WebSearch's summarized snippets and GitHub's
  raw-content mirror of the same official docs were used instead). Also confirmed
  `New-DlpComplianceRule`/`Set-DlpComplianceRule` expose no parameter at all for referencing a
  device group as a rule condition/exception. Scripting either half would mean fabricating an
  unconfirmed hashtable shape, which `AGENTS.md` §4 does not permit, so no new scenario folder was
  built — the finding was folded into `endpoint-dlp-usb-block`'s existing docs instead, with three
  new citations (Microsoft's `dlp-configure-endpoint-settings` page, the Microsoft Q&A thread, and
  the `Set-PolicyConfig` reference). Commit: `2783842`. Date: 2026-09-08.
- [x] `scenarios/information-protection/auto-label-eu-personal-data-exchange/` — the Exchange
  (email) companion to `auto-label-eu-personal-data-sharepoint`, combining its EU/UK SIT set and
  `-SensitiveInfoTypeName` localization mechanism with `auto-label-confidential-exchange`'s
  Exchange location/sender-exclusion/encryption mechanics — both inherited unchanged and verified
  directly against their source scripts, not re-derived. Four-lens review surfaced two findings
  specific to running all three (now four, counting the U.S.-SIT SharePoint original) sibling
  policies together: independent SIT-list localization drift between this scenario and its
  SharePoint/OneDrive EU counterpart (no shared config store ties the two scripts' parameters
  together), and a policy-name disambiguation risk during incident response across four
  similarly-named auto-labeling policies — both resolved with README additions (a standing
  review-cadence check; a disambiguation table naming all four policies, locations, and SIT sets)
  rather than new code. Cross-linked back into `auto-label-eu-personal-data-sharepoint/README.md`
  §11 and `design.md` §8. Commit: `943d23f`. Date: 2026-09-08.
- [x] `scenarios/insider-risk/security-policy-violations-by-departing-users/` — full scenario
  (README, design, deploy/, validate/, rollback, four-lens review) for Insider Risk Management's
  **Security policy violations by departing users** template, the Defender-for-Endpoint-driven
  sibling of `departing-employee-data-theft` flagged as a non-goal there. Grounded directly
  against Microsoft Learn: the template's own prerequisites/triggering-events table, its
  Microsoft-labeled **preview** status (both the template family and its Defender for Endpoint
  indicator category), the 15,000-user scope limit, the "Share endpoint alerts with Microsoft
  Compliance Center" Defender-portal-only toggle, Intelligent detections' alert-triage-status
  import behavior, and the Graph `security-alert`/`security-detectionsource` resource schemas
  (`incidentId`, `alertPolicyId`, `detectionSource` members) backing the new
  `Export-SecurityViolationInsiderRiskAlerts.ps1` script. Reuses (does not duplicate) the sibling
  scenario's HR connector and `Send-HrTerminationRecord.ps1` per `AGENTS.md`'s no-unneeded-
  abstraction guidance. Four-lens review raised and resolved two Red Team findings (device-
  tampering is invisible to an offline/physical attack on the endpoint; the Defender alert-sharing
  toggle is tenant-wide, not per-policy), one Blue Team finding (a policy can be created with zero
  triggering events enabled and no error, unlike the sibling scenario — added a deployment-time
  checklist item), and one CISO finding (preview status needed a concrete pilot-first rollout
  recommendation, not just a disclosure banner) — all closed with README/validate-script
  additions, no Fail items. One implementation bug caught and fixed before commit: the export
  script's `foreach`/`ForEach-Object` results needed explicit `@()` array-wrapping to avoid
  PowerShell silently unwrapping single-item or empty results to scalars/`$null`, which would have
  broken `.Count` checks and produced a JSON scalar instead of an array on export. Three follow-ups
  and one RBAC cross-reference gap recorded above rather than resolved by guessing (Defender for
  Endpoint Plan 1 vs. Plan 2 sufficiency; whether the `incidentId` join is actually reliable;
  Security Administrator role not yet in `docs/rbac-model.md`; the three sibling "Security policy
  violations…" templates left as separate candidate fragments). Commit: `3d61f9b`. Date: 2026-09-09.
- [x] **Extend `docs/rbac-model.md` with a new §12: Microsoft Defender for Endpoint portal RBAC —
  an eighth system, for scenarios that configure Defender for Endpoint tenant-wide settings** —
  commit `b126d27` — 2026-09-09 — a scoped cross-cutting-doc fragment (not a new scenario),
  closing the follow-up logged during the Security Policy Violations by Departing Users build:
  that scenario's §5 Step 2 requires toggling "Share endpoint alerts with Microsoft Compliance
  Center" on the Microsoft Defender portal's Advanced features page, a Defender-portal RBAC
  surface `docs/rbac-model.md` didn't cover. New §12 documents three grounded access paths: (1)
  basic permissions — Microsoft Entra **Security Administrator** (full access)/**Security Reader**
  (read-only); (2) granular legacy Defender for Endpoint RBAC — the **Manage security settings in
  Security Center** permission, evidenced not by symmetry but by Microsoft's own companion
  procedure for the adjacent Intune-connection toggle on the *same* settings page, which names this
  exact permission as the non-Entra-role alternative to Security Administrator; (3) its Defender
  **unified RBAC (URBAC)** equivalent — **Core security settings (Manage)** (+ **Detection tuning
  (Manage)**) per Microsoft's own legacy-to-unified permission mapping table, mandatory for every
  tenant provisioned on/after February 16, 2025. Also notes the toggle has no documented
  Graph/PowerShell surface (consistent with the parent scenario's own finding) and that this
  role/permission grants no Purview access, the same separation-of-concerns point §9–§11 already
  make for Intune/Conditional Access/app-registration RBAC. Old §12 ("How scenarios should cite
  RBAC") renumbered to §13, with a new point 1 caveat for Defender-for-Endpoint-configuring
  scenarios. Cross-linked back into
  `security-policy-violations-by-departing-users/README.md`'s Prerequisites table and §5 Step 1 in
  place of the "not yet cross-referenced" note. No VERIFY items needed — every fact came from an
  official Microsoft Learn page fetched in full this run (`defender-endpoint/advanced-features`,
  `defender-endpoint/rbac`, `defender-endpoint/user-roles`, `defender-xdr/manage-rbac`,
  `defender-xdr/compare-rbac-roles`, `intune/device-security/microsoft-defender/configure-
  integration`), not inferred or fabricated.
- [x] **`scenarios/dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation/`** — commit
  `8f24b6e` — 2026-09-09 — full scenario (README.md, design.md, deploy/,
  validate/, rollback.md, reviews.md) extending `exchange-pii-exfil-block` with the same
  `-SharedByIRMUserRisk`-based Adaptive Protection compensating control
  `pci-teams-exfil-block-part2-obfuscation-mitigation` already built for the Teams DLP scenario,
  applied here to Exchange. Grounded via Microsoft Learn (fetched in full this run) that Exchange
  Online — unlike Microsoft Teams — is a natively supported "High Severity DLP Alert" indicator
  workload, so the feeder Insider Risk Management policy triggers directly off the parent DLP
  policy ("User matches a data loss prevention (DLP) policy") with no Communication Compliance
  detour, a materially simpler design than the Teams sibling (`design.md` §3/§6a). The deploy
  script's rule-priority reconciliation deliberately generalizes the Teams sibling's hardcoded
  three-rule-name approach into a name-agnostic compaction (read whichever rules currently exist,
  preserve relative order, compact to start at 1) because the parent Exchange scenario has an
  optional exception-group rule and a separately-deployable Encrypt-mode audit companion scenario
  that a fixed rule list would miscount. Four-lens review (Red Team) surfaced and documented a
  genuine, previously-unstated gap: the parent scenario's exception-group population in
  `-Action Encrypt` mode generates no High-severity alert and so is invisible to this fragment's
  feeder trigger entirely — traced to the exact rule wiring, documented in `README.md` §11 with a
  concrete buyer-facing mitigation, not silently left for a reviewer to discover. Three VERIFY
  items and one cross-scenario follow-up recorded above rather than resolved by guessing (rule
  priority auto-shift behavior, end-to-end composition validation, and whether the Encrypt-mode
  audit companion should get an opt-in higher severity default).
- [x] **`scenarios/insider-risk/security-policy-violations/`** — full scenario (README.md,
  design.md, deploy/, validate/, rollback.md, reviews.md) deploying Insider Risk Management's base
  **Security policy violations** template — the sibling of `security-policy-violations-by-
  departing-users` with no HR/departure trigger and no priority-user-group requirement; its own
  triggering event is the Defender for Endpoint security-violation alert itself, confirmed directly
  against Microsoft's policy-templates prerequisites table. Corrects this fragment's own
  originating backlog framing ("scores every onboarded user continuously"): Microsoft caps this
  specific template at **1,000** actively-scored users tenant-wide (identical to the
  priority-users sibling's own cap despite requiring no priority-group object; smaller than
  departing-users' 15,000 and risky-users' 7,500) — an all-users scope is infeasible above roughly
  that headcount (`design.md` §3). Ships one new, genuinely scenario-specific capability,
  `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` — resolves an operator-chosen Entra
  group's (or groups') transitive user membership via `Get-MgGroupTransitiveMemberAsUser` (the
  `microsoft.graph.user` OData cast, confirmed to require the `ConsistencyLevel: eventual` header
  directly from both the cmdlet and Graph REST references), dedupes across groups, filters to
  enabled accounts, and pre-flight-checks the count against the 1,000-user cap. Reuses the
  departing-users sibling's `Export-SecurityViolationInsiderRiskAlerts.ps1` unmodified rather than
  duplicating it — that script applies no policy-specific filter, so it already works against this
  scenario's own alerts (`AGENTS.md`'s no-unneeded-abstraction guidance). Four-lens review raised
  and resolved one substantive finding, independently flagged by both Red Team and Blue Team:
  whether an IRM policy's scope tracks a directly-added group's live membership isn't documented by
  Microsoft either way, so a newly added privileged-group member could sit unmonitored under a
  calendar-only review cadence — `README.md` §8 now ties re-scoping to the group-membership-change
  event itself (quarterly review demoted to a backstop), and both `README.md` §11 and `design.md`
  §6 state the underlying VERIFY explicitly rather than assuming either behavior. One
  implementation bug caught and fixed before commit: `SourceGroupIds += $gid` against a
  `List[string]` (no `+` operator defined for that type) corrected to `.Add($gid)`. Two follow-up
  fragments recorded above (`…-by-priority-users/`, `…-by-risky-users/`) rather than bundled into
  this one, per `AGENTS.md` §6's one-fragment-per-turn discipline, plus one general (not
  scenario-specific) VERIFY on group-scope live-sync behavior. Date: 2026-09-09.

## Blocked / needs user
- (none)
