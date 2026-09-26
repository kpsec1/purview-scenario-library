# PROGRESS - build state & backlog

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
- (none - every module now has a starter scenario; remaining work is the follow-up expansion backlog below)

> After the starter scenario per module lands, expand each module across the AGENTS.md §3 axes
> (lifecycle, deployment posture, regulatory driver, failure/abuse, scale). Add those fragments
> here as they're scoped.

### Follow-ups discovered while building the IRM case-escalation-to-eDiscovery scenario
- [x] Consider a Power Automate flow (or Graph webhook-driven trigger...) that automatically runs
  `Confirm-EdiscoveryEscalationLink.ps1` right after escalation - **grounded and closed, not built**
  (see DONE below): the dedicated grounding pass this item asked for found no automatic/event-driven
  trigger exists. Power Automate's IRM case trigger is manually selected/run from the same dashboard
  toolbar (not fired by the escalation event), none of its five documented connector actions can
  invoke an external script, and the separate Insider Risk Management audit log that does record
  escalations has no documented Graph/REST query API (`Search-UnifiedAuditLog` doesn't cover it
  either). `irm-case-escalation-to-ediscovery/README.md` §8/§11 and `design.md` §4/§5 corrected in
  place; a scheduled poll remains the only unattended option. Re-open this item if Microsoft ever
  ships either a documented event-driven IRM trigger or a Graph/REST endpoint for the IRM audit log.
- [ ] VERIFY (pilot tenant): the exact format of the "Case ID" the Insider Risk Management Cases
  dashboard displays (numeric, GUID, or another scheme) - not documented by Microsoft beyond "The
  ID of the case." `irm-case-escalation-to-ediscovery`'s naming convention and scripts treat it as
  an opaque string throughout; confirming the format could enable format validation instead.
- [ ] VERIFY (pilot tenant): whether the portal's "Escalate for investigation" flow automatically
  adds the flagged user as a custodian with a hold applied, or leaves the new case empty - not
  documented either way by Microsoft. `irm-case-escalation-to-ediscovery/deploy/
  Confirm-EdiscoveryEscalationLink.ps1` doesn't assume an answer (design.md §3 explains why
  unconditional reconciliation is safe regardless), but confirming this would let the scenario's
  docs state the actual portal behavior instead of "unknown."

### Follow-ups discovered while building the eDiscovery Premium legal-hold-and-export scenario
- [x] Ground the exact `RecordType`/`Operations` values for eDiscovery hold-apply/hold-release/
  case-close/case-delete events in `Search-UnifiedAuditLog`, then add a dedicated
  `Export-EdiscoveryAuditTrail.ps1` to `premium-legal-hold-and-export/deploy/` - **built** (see
  DONE below): `RecordType Discovery` with `CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/
  `CaseRemoved` (case lifecycle) and `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` (hold-**policy** lifecycle), both grounded verbatim against
  Microsoft's "Audit log activities" eDiscovery reference. One genuine gap carried forward rather
  than resolved by guessing - see the new VERIFY item immediately below.
- [ ] VERIFY (pilot tenant): whether the `HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync` operations `Export-EdiscoveryAuditTrail.ps1` queries (confirmed for
  the case-level `ediscoveryHoldPolicy` object) also fire for `premium-legal-hold-and-export`'s own
  custodian-scoped `ediscoveryCustodian: applyHold`/`release` calls - a different object model. One
  Microsoft Learn page claims custodian holds are internally modeled as a "custodian hold policy"
  (suggesting yes); the only page describing a dedicated per-custodian audit search UI, and that
  "custodian hold policy" page itself, both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic eDiscovery experience's August 2025 retirement
  everywhere else - neither is confirmed for the current, non-legacy experience this scenario
  targets. Flagged inline in `deploy/Export-EdiscoveryAuditTrail.ps1`'s `.NOTES`,
  `README.md` §8, and `design.md` §8 rather than resolved by guessing, per `AGENTS.md` §4.
- [x] `scenarios/ediscovery/legal-hold-notifications/` - **investigated, not built** (see DONE
  below): the Premium custodian-communication workflow this item originally scoped was
  **permanently retired by Microsoft on August 31, 2025** and isn't available in the current
  eDiscovery experience - not merely unautomatable. `premium-legal-hold-and-export/README.md` §11
  and `design.md` §7 corrected in place instead of a companion scenario being built on the original
  (now-superseded) assumption.
- [ ] VERIFY (pilot tenant, before production reliance): whether the custodian `userSource`
  `includedSources` property accepts the combined string `"mailbox, site"` (Microsoft's own worked
  *beta*-namespace example) on the current *v1.0* `POST .../custodians/{id}/userSources` endpoint,
  whose own v1.0 worked example shows only a single value (`"mailbox"`) - flagged inline in
  `premium-legal-hold-and-export/README.md` §11 and `deploy/New-EdiscoveryPremiumLegalHold.ps1`'s
  `.NOTES` rather than resolved by guessing a JSON-array shape neither reference confirms.
- [x] Once `scenarios/insider-risk/` has a scenario producing an escalatable Insider Risk
  Management case, wire the documented IRM-case → eDiscovery (Premium) case escalation integration
  - **built** as `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` (see DONE below).

### Follow-ups discovered while building the eDiscovery location-scoped-legal-hold scenario
- [ ] VERIFY (pilot tenant, before pointing this at a distribution list you haven't already
  tested): whether a distribution list's own SMTP address is accepted as a `userSource.email`
  value on the v1.0 `ediscoveryHoldPolicy` endpoint and expanded server-side to member mailboxes.
  Corroborated by Microsoft's beta custodian-context userSource reference ("or the SMTP address of
  the group mailbox") and by the "Distribution group has too many members" (>1,000) error
  reference, but the v1.0, non-beta endpoint this scenario actually calls documents `email` only
  as "SMTP address of the user" - flagged inline in `location-scoped-legal-hold/README.md` §11,
  `design.md` §3, and `deploy/New-EdiscoveryLocationHold.ps1`'s `.NOTES`.
- [ ] VERIFY (pilot tenant): whether the `siteSource` list/create v1.0 response ever exposes a
  stable, directly comparable URL (rather than only `displayName`, the site's title) - if
  Microsoft adds one, replace `location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`'s
  and `validate/Test-EdiscoveryLocationHold.ps1`'s URL-slug-vs-title matching (the disclosed weak
  point in `design.md` §6) with a direct comparison instead.
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` - **built** (see DONE below): script
  resolving a Microsoft Teams/Microsoft 365 Group's own mailbox + SharePoint site
  (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` in Exchange Online PowerShell) into the userSource/
  siteSource pair `location-scoped-legal-hold`'s scripts already accept.
- [x] Reconcile the group-expansion member-cap discrepancy this build surfaced - **investigated and
  re-grounded, not merged into one figure** (see DONE below): both the 100-member and >1,000-member
  pages are current, non-legacy Microsoft Learn articles (the ">1,000" figure is not from an older
  page as originally suspected); Microsoft never states they're the same limit, so both scenarios now
  cite both figures explicitly and treat 100 as the conservative planning threshold, with the
  cross-code-path question kept as an open pilot-tenant VERIFY per `AGENTS.md` §4.
- [x] `scenarios/ediscovery/roster-to-hold-locations/` - **built** (see DONE below): scripts the
  hand-off `teams-group-hold-resolution/design.md` §7 left manual - reads that scenario's
  `-ResolveMembers` roster CSV plus a human-authored `-SelectionPath` decision record, and appends
  the selected members' mailbox addresses as new `userSources[]` entries in a
  `location-hold-definition.json`-shaped file, with an optional `-AddToHold` stage that reconciles
  them directly onto a live hold policy.
- [x] Re-check whether `ediscoveryHoldPolicy: enablePolicy`/`disablePolicy` have been promoted from
  beta to v1.0 - **re-verified, not promoted** (see DONE below). Re-open this item again in a future
  pass if Microsoft ever lists either action under `?view=graph-rest-1.0`.

### Follow-ups discovered while building the DLP template scenario
- [x] `scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/` - **built** (see DONE
  below): a behavioral compensating control (not a full fix - no Microsoft capability performs
  cross-message content reconstruction) for the split-PAN evasion gap flagged in `reviews.md`
  (Red Team) for the Teams template scenario. Wires a dedicated Insider Risk Management "Data
  leaks" policy + the Communication Compliance SIT-in-messages indicator (the *only* documented
  path that extends IRM coverage to Microsoft Teams - Teams DLP alerts are explicitly excluded
  from IRM's own DLP-alerts trigger, confirmed during this build's grounding pass) + Cumulative
  Exfiltration Detection into Adaptive Protection, which drives a new priority-0
  `-SharedByIRMUserRisk` rule added to Part 1's own named DLP policy that hard-blocks all further
  external Teams sharing from an Elevated-risk sender, no override. Explicitly documented residual
  gap: zero detectable signal against a maximally disciplined single-digit-per-message attacker
  who generates no other exfiltration-type activity - see that scenario's `README.md` §11.
- [x] `scenarios/compliance-manager/pci-dss-assessment/` - **built** (see DONE below): Compliance
  Manager PCI DSS v4.0 premium-template assessment scenario referenced from
  `scenarios/dlp/pci-teams-exfil-block/README.md` §2 as the assessment-side companion to this
  technical control (that README updated in place to point at the real path instead of "planned").

### Follow-ups discovered while building the Endpoint DLP USB-block scenario
- [x] `scenarios/dlp/removable-usb-device-groups-allowlist/` (or fold into a future Endpoint DLP
  hardening pass) - script/document the **Removable USB device groups** portal feature
  (`Set-PolicyConfig -DlpRemovableMediaGroups`) to allow specific IT-issued encrypted backup
  drives by device identity, complementing the group-based (user) exception in
  `scenarios/dlp/endpoint-dlp-usb-block/`. Flagged as out of scope there because the per-rule
  PowerShell syntax for referencing an authorization group inside `-EndpointDlpRestrictions`
  is not documented anywhere found during that scenario's build - needs a fresh grounding pass -
  **investigated, not built** (see DONE below): the fresh grounding pass confirmed the portal
  workflow end-to-end (create the device group in Endpoint DLP settings by Vendor ID/Product
  ID/Instance ID, then add it as an exclusion in a rule's actions/exceptions) but found the
  PowerShell layer more thoroughly undocumented than originally scoped - not just the per-rule
  reference syntax, but `Set-PolicyConfig -DlpRemovableMediaGroups`'s own hashtable shape, and the
  same for all four sibling device-group parameters (`-DlpPrinterGroups`/`-DlpNetworkShareGroups`/
  `-DlpAppGroups`/`-DlpExtensionGroups`): every one of their descriptions and the cmdlet's entire
  `EXAMPLES` section are unpublished placeholder text in Microsoft's official reference, and
  `New-DlpComplianceRule`/`Set-DlpComplianceRule` expose no parameter at all for referencing a
  device group as a rule condition/exception. Scripting either half would mean fabricating an
  unconfirmed hashtable shape, which this repo's grounding standard (`AGENTS.md` §4) does not
  permit. `scenarios/dlp/endpoint-dlp-usb-block/README.md` §11/§12 and `design.md` §6-7 updated in
  place with the full finding and new citations, rather than a new scenario folder being built on
  an unscriptable feature. Re-open if Microsoft ever publishes the hashtable shape or adds a
  rule-level device-group parameter.
- [x] Consider a companion `scenarios/dlp/defender-device-control-usb-allowlist/` (Microsoft
  Defender for Endpoint device control, not Purview DLP) - `endpoint-dlp-usb-block/README.md`
  §11 notes Endpoint DLP is content-aware but not device-identity-aware, and an organization wanting "no
  unapproved USB devices, period" needs device control in addition, not instead - **built** (see
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
  (`RemovableMedia` / `Block` / `Audit`) - **grounded and closed** (see DONE below): both the
  official `New-DlpComplianceRule` and `Set-DlpComplianceRule` Learn reference pages were fetched
  in full this run and confirm the exact shape directly ("The available values for `<Value>` are:
  Audit, Block, Ignore, or Warn," with a worked `RemovableMedia`/`Block` example), superseding the
  Tech Community blog as the primary citation.

### Follow-ups discovered while building the Defender for Endpoint device control USB allowlist scenario
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage/` - extend
  `SecuredDevicesConfiguration` to also cover `WpdDevices` (Windows Portable Devices -
  phones/cameras in MTP/PTP mode), which this scenario's initial build confirmed are **completely
  invisible** to a `RemovableMediaDevices`-scoped policy, not merely unrestricted (a real,
  undetected bypass, flagged as a Red Team finding in `reviews.md` and `README.md` §11) - **built**
  (see DONE below). This build's own grounding pass could **not** confirm this item's original
  premise that "WPD groups only support `FriendlyNameId`/`PrimaryId` matching (no
  `SerialNumberId`/`VID_PID`)" - Microsoft's general Windows-devices property-support table lists
  `SerialNumberId`/`VID_PID` without breaking it down per `PrimaryId` family, and no worked example
  was found either confirming or excluding them for `WpdDevices` specifically. The new scenario
  states this as a genuinely open VERIFY in both directions rather than repeating the stronger,
  unsubstantiated exclusion claim - see its `README.md` §11.
- [x] Add a **Defender for Endpoint + Intune** licensing row/section to `docs/licensing-matrix.md`
  - **built** (see DONE below): new §7, cross-linked from `defender-device-control-usb-allowlist/
  README.md` §3.
- [x] Cross-reference Intune RBAC (**Policy and Profile manager** role, and the
  `DeviceManagementConfiguration.ReadWrite.All` Graph application permission for app-only access)
  into `docs/rbac-model.md`, which currently only documents Purview/Exchange role groups and
  Entra directory roles, not Intune's own RBAC model - **built** (see DONE below): new §9
  (renumbering the old §9 "How scenarios should cite RBAC" to §10), cross-linked from
  `defender-device-control-usb-allowlist/README.md`'s Prerequisites table in place of the
  "not yet cross-referenced" note. The still-open Organization Configuration/Audit Manager
  backport under the Audit retention-policy follow-ups remains a separate, not-yet-built item.
- [ ] VERIFY (pilot tenant, before relying on `-Force` to remove a revoked drive from the
  allowlist): whether `PATCH /deviceManagement/deviceConfigurations/{id}` fully replaces the
  `omaSettings` collection or merges/appends - Microsoft's `Update windows10CustomConfiguration`
  reference documents `omaSettings` as updatable but is silent on replace-vs-merge semantics.
  Flagged inline in `defender-device-control-usb-allowlist/README.md` §11 and the deploy script's
  `.NOTES` rather than assumed.
- [ ] Once Microsoft publishes a confirmed Microsoft Graph resource/schema for the native Intune
  "Device Control profile" template (Endpoint security → Attack Surface Reduction), re-evaluate
  migrating `defender-device-control-usb-allowlist` off the current Custom-OMA-URI/hand-built-XML
  mechanism onto it - deferred in this build because no such schema was found during this
  fragment's grounding pass (`design.md` §4); the current mechanism is fully grounded and stable,
  just lower-level than the newer portal experience.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos/` - the macOS sibling (separate
  JSON/`mobileconfig` authoring path via Intune, `mac-device-control-overview`), explicitly out of
  scope for the Windows-only, XML-OMA-URI-based initial fragment (`design.md` §8) - **built** (see
  DONE below): same default-deny/named-allowlist/both-paths-audited shape, deployed as a
  `macOSCustomConfiguration` Graph v1.0 object (a native, fully-documented type - no OMA-URI-style
  workaround needed on this platform). Matches approved devices by `serialNumber` only (the
  stronger of the Windows sibling's two options); `vendorId`/`productId` compound matching and
  Portable/Apple/Bluetooth device coverage are tracked as follow-ups below, the same honest,
  disclosed-not-hidden scope boundary this repo already uses for the Windows sibling's own WPD gap.
- [ ] Consider a **BitLocker-encryption-state** variant/extension (`DeviceEncryptionStateId` group
  property - "approve any BitLocker-encrypted drive," not just a fixed serial-number list) once
  that capability moves out of Microsoft-labeled Preview - explicitly deferred as a non-goal in
  `design.md` §8.

### Follow-ups discovered while building the Defender for Endpoint device control WPD coverage scenario
- [ ] VERIFY (pilot tenant): whether `SerialNumberId`/`VID_PID` group-matching properties are
  honored for `WpdDevices`-classified hardware, or silently ignored/rejected. Microsoft's "Device
  control policies" reference lists both as supported generic "Windows devices" properties without
  breaking the table down per `PrimaryId` family, and this build found no worked example pairing
  either property with a `WpdDevices`-scoped group. `defender-device-control-usb-allowlist-wpd-
  coverage/deploy/Add-WpdDeviceControlCoverage.ps1` accepts both properties per config entry and
  `validate/Test-WpdDeviceControlCoverage.ps1` checks them as `[WARN]` (not `[PASS]`/`[FAIL]`)
  pending this confirmation - see that scenario's `README.md` §11. Resolving this would let a
  future revision recommend a true per-unit WPD identifier instead of the weaker, user-editable
  `FriendlyNameId` default.
- [ ] Once the item above is resolved and a per-unit WPD identifier is confirmed, revisit
  `defender-device-control-usb-allowlist-wpd-coverage/README.md` §11's Red-Team-flagged
  friendly-name-spoofing risk (a device's advertised name is typically user-editable, so an
  attacker who learns an approved name can rename their own device to match it) - a confirmed
  `SerialNumberId`/`VID_PID` path would let this scenario recommend a materially stronger
  allowlist identifier for at least some WPD hardware, the same way the parent scenario already
  prefers `SerialNumberId` over `VID_PID` for removable media.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` - now that
  `scenarios/dlp/defender-device-control-usb-allowlist-macos/` is built (see DONE below), extend it
  to cover macOS's `portable_devices`/`apple_devices`/`bluetooth_devices` `primaryId` families -
  confirmed completely invisible to that scenario's `removable_media_devices`-scoped policy, the
  direct macOS analog of the Windows WPD gap (flagged as a Red Team finding in that scenario's
  `reviews.md` and `README.md` §11) - **built** (see DONE below): widens the parent's shared
  `.mobileconfig` payload (not a second profile - macOS's `com.microsoft.wdav`-typed policy is one
  document across all four families) with three new `settings.features` enables, three catch-all
  groups, two optional `serialNumber`-matched allowlists (Apple/Portable - confirmed via
  Microsoft's own `audit_all_apple_devices_except_serial_numbers.json` sample for Apple; unconfirmed
  by a direct worked example for Portable, tracked as a VERIFY below), and five deny/allow rule
  pairs. Bluetooth ships default-deny-only in v1 (no allowlist) - Microsoft's own worked sample for
  that family uses a structurally different `vendorId`+`productId` single-device match, not the
  OR'd-`serialNumber` shape used for the other two; a Bluetooth allowlist is a new follow-up below.
  Since the underlying policy JSON schema is identical across the Intune and JAMF macOS deployment
  paths, this build also closes the equivalent JAMF-sibling follow-up tracked immediately below
  without a second build (per that item's own note).
- [ ] Consider a Blue Team-flagged WPD-spoofing incident-response playbook once the `SerialNumberId`/
  `VID_PID`-for-WPD VERIFY above is resolved - deferred in this build (`reviews.md`, Blue Team
  finding 2) because a "cross-check the secondary identifier" runbook step has nothing confirmed to
  cross-check against yet.

### Follow-ups discovered while building the Defender for Endpoint device control macOS Apple/Portable/Bluetooth coverage scenario
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/` - adds a
  `vendorId`+`productId`-matched Bluetooth approved-device exception (single device in v1, matching
  the exact shape Microsoft's own `deny_all_bluetooth_devices_except_samsung.json` sample
  demonstrates, fetched directly during this build), closing the "Bluetooth is always default-deny,
  no exceptions" scope boundary - **built** (see DONE below).
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/GitHub-samples pass): a directly-confirmed
  worked example pairing the `serialNumber` clause with a `portable_devices`-scoped group -
  `defender-device-control-usb-allowlist-macos-portable-device-coverage`'s grounding pass confirmed
  this pattern only for `apple_devices` (via `audit_all_apple_devices_except_serial_numbers.json`);
  Microsoft's Clause reference table is unscoped by device family (a stronger starting position than
  the Windows WPD-coverage sibling's own equivalent VERIFY), but this is not the same as a worked
  example. `validate/Test-MacPortableDeviceCoverage.ps1` checks this as `[WARN]`, not `[PASS]`,
  pending confirmation - see that scenario's `README.md` §11.
- [x] Consider `vendorId`/`productId` compound matching for the Apple and Portable families too (not
  just Bluetooth, above) once the per-device, dynamic-sub-group `groupId`-clause-nesting idempotency
  model is independently verified against a pilot tenant - same deferred complexity already tracked
  under `defender-device-control-usb-allowlist-macos-vendor-product-matching/` for the parent's own
  `removable_media_devices` family; this fragment's two new `serialNumber`-based allowlists carry
  the identical limitation, not a new one - **built** (see DONE below) as
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`:
  the same RFC 4122 §4.3 UUIDv5 deterministic-sub-group technique the removable-media sibling already
  proved, applied independently to both the Apple and Portable families in one fragment (family
  folded into the hash input so the two families' sub-groups can never collide), with no new rule
  needed. Deliberately requires each family's `ApprovedAppleDevices`/`ApprovedPortableDevices` group
  to already have ≥1 `serialNumber` device configured (this fragment never builds that group/its
  Allow rule from a zero-`serialNumber` starting state - a disclosed scope boundary, see the new
  follow-up immediately below) and inherits a more severe version of the Bluetooth sibling's own
  disclosed cross-fragment ordering hazard (`Add-MacPortableDeviceCoverage.ps1 -Force` can silently
  drop or fully orphan this fragment's additions) - disclosed and detected, not silently engineered
  around, the same precedent the Bluetooth fragment already established.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-portable-device-coverage/` -
  tracked above (under the WPD-coverage-scenario follow-ups) - **closed**, see that entry above for
  details.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/` - **built**
  (see DONE below): closes the deferred `vendorId`/`productId` compound-matching gap via the
  per-device sub-group + `groupId`-clause nesting technique `design.md` §5 (parent scenario)
  describes. The "stable, deterministic GUID-per-device scheme" blocker is resolved with an RFC 4122
  §4.3 version-5 (SHA-1, name-based) UUID derived from each device's `vendorId:productId` pair -
  verified during the build against Python's `uuid.uuid5()` reference implementation. No new rule
  needed (extends the parent's existing `ApprovedBackupDrives` group directly); multi-device, unlike
  the Bluetooth sibling's v1 single-device cap.
- [ ] VERIFY (pilot tenant): whether `macOSCustomConfiguration`'s `payload` PATCH fully replaces the
  prior `.mobileconfig` or merges/appends at the plist level - Microsoft's `Update
  macOSCustomConfiguration` reference documents `payload` as updatable but is silent on
  replace-vs-merge semantics, the same open question the Windows sibling's `omaSettings` PATCH
  already carries. Flagged inline in `defender-device-control-usb-allowlist-macos/README.md` §11
  and the deploy script's `.NOTES` rather than assumed.
- [ ] VERIFY (pilot tenant, ideally one already running other Defender for Endpoint on macOS
  configuration): whether a pre-existing, independently-deployed `com.microsoft.wdav` preferences
  profile (e.g. one only configuring cloud-delivered protection settings) conflicts with, silently
  merges with, or is overwritten by `defender-device-control-usb-allowlist-macos`'s own
  same-`PayloadIdentifier` profile - Apple's MDM profile-merge behavior for two profiles sharing a
  `PayloadIdentifier` from different sources is not addressed by Microsoft's device control
  documentation. Flagged as a Red Team finding in that scenario's `reviews.md` and as a VERIFY in
  `README.md` §11 rather than resolved by guessing.
- [ ] Once a Defender for Endpoint device-health or compliance signal exposing a Mac's Full Disk
  Access grant status for `com.microsoft.dlp.daemon` remotely (not just via local `mdatp health`)
  is independently grounded, extend `defender-device-control-usb-allowlist-macos/validate/
  Test-MacDeviceControlUsbAllowlistPolicy.ps1` to check it at scale - flagged as a Blue Team gap in
  that scenario's `reviews.md` (no remote, at-scale check exists today; this build declined to
  fabricate one per `AGENTS.md` §4).
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/` - the JAMF-managed
  deployment path (`mac-device-control-jamf`) for organizations whose Mac fleet is JAMF-managed
  rather than Intune-managed, explicitly out of scope in
  `defender-device-control-usb-allowlist-macos/design.md` §8 (Intune-only, matching the rest of
  this repo's Windows device-control scenario) - **built** (see DONE below): identical policy
  content (same groups/rules/settings JSON, same fixed GUIDs) as the Intune sibling, but a
  materially different deploy shape - `deploy/New-JamfDeviceControlPolicyJson.ps1` generates and
  optionally locally schema-validates (`mdatp device-control policy validate`) the policy JSON,
  since Microsoft's own `mac-device-control-jamf` procedure has no documented API for the JAMF Pro
  "Device Control Policy" custom-schema property - that step (and enabling `DC_in_dlp`) stays a
  precisely-documented manual JAMF-console action in `README.md` §5, not fabricated. `developer.
  jamf.com` was unreachable in this build's network environment, so a JAMF Pro API for this
  specific property type could not be independently ruled in or out - tracked as a fresh VERIFY
  below rather than guessed either way.

### Follow-ups discovered while building the Defender for Endpoint device control macOS USB allowlist (JAMF) scenario
- [ ] VERIFY (`developer.jamf.com`, or a pilot JAMF Pro tenant): whether a documented JAMF Pro
  REST/Classic API request body exists for programmatically setting a Custom-Schema-sourced
  Application & Custom Settings property's value (the mechanism `mac-device-control-jamf` uses for
  the Device Control Policy property) - as opposed to uploading a plain `.plist` file, a different,
  simpler mechanism JAMF also supports for other Defender for Endpoint preferences. `developer.
  jamf.com` was unreachable from this build's network environment, so this could not be checked
  directly. If found, `defender-device-control-usb-allowlist-macos-jamf`'s Steps 2-4 (`README.md`
  §5) could be automated end-to-end instead of staying JAMF-console-only - see that scenario's
  `README.md` §11 and `design.md` §3.
- [ ] Once the item above is resolved and a JAMF Pro API path is confirmed, revisit
  `defender-device-control-usb-allowlist-macos-jamf/reviews.md`'s Red-Team/Blue-Team findings on
  the undetectable-drift risk of a manual JAMF-console-only deployment (no way to confirm the
  pasted JSON matches the intended artifact, or that a JAMF admin hasn't silently altered it) - an
  API-based reconcile-and-verify script would close both findings the same way the Intune sibling's
  own Graph-based script already does.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching/` -
  **built** (see DONE below): the JAMF-managed sibling of
  `defender-device-control-usb-allowlist-macos-vendor-product-matching/` (Intune). Unlike the Intune
  sibling (an incremental Graph PATCH against a live object), this fragment is a **superset
  generator** - JAMF has no documented API to patch, so it reads one combined config
  (`approvedDevices` + `vendorProductDevices`) and regenerates the complete policy JSON, reusing the
  Intune sibling's exact deterministic RFC 4122 §4.3 UUIDv5 scheme and namespace constant so the same
  `vendorId`+`productId` pair yields the identical sub-group id on both deployment paths (one policy
  identity across a hybrid Intune+JAMF fleet). The "unverified-dynamic-GUID-sub-group" blocker this
  item originally cited was resolved when the Intune sibling itself shipped (its own GUID scheme
  independently verified against Python's `uuid.uuid5()` reference implementation, not a pilot-tenant
  dependency) - ported here rather than re-derived.
- [x] `scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-portable-device-coverage/` (or
  fold into a future macOS device-control hardening pass) - same Portable-Device/Apple-device/
  Bluetooth-media coverage gap already tracked for the Intune sibling (and for
  `defender-device-control-usb-allowlist-macos-portable-device-coverage` above); applies identically
  here since the underlying policy JSON is shared between both deployment paths - closing it for one
  sibling's policy shape closes it for both - **closed by**
  `scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/` (see DONE
  below): that fragment's `design.md` §8 documents explicitly that its policy JSON shape applies
  identically to the JAMF-deployed sibling, so no separate JAMF-specific build was needed.

### Follow-ups discovered while building the Information Protection auto-labeling scenario
- [x] Extend `docs/automation-surface.md` with a fifth automation surface: **SharePoint Online
  Management Shell** (`Connect-SPOService` / `Microsoft.Online.SharePoint.PowerShell`) - **built**
  (see DONE below).
- [x] `scenarios/information-protection/auto-label-confidential-exchange/` - Exchange-location
  companion to `auto-label-confidential-sharepoint` - **built** (see DONE below).
- [x] Content-based Exchange DLP rule (not label-conditioned) that blocks or forces encryption on
  outbound SSN/Credit-Card-Number mail to external recipients, closing the Red-Team-flagged gap in
  `auto-label-confidential-exchange/README.md` §11 - **built** (see DONE below) as
  `scenarios/dlp/exchange-pii-exfil-block/`, not under `information-protection/` as originally
  sketched here: the finished scenario is purely content-based DLP with no dependency on the
  auto-labeling scenario's label (`design.md` §3 explains why), so it belongs alongside this
  library's other DLP scenarios (`pci-teams-exfil-block`, `endpoint-dlp-usb-block`) by module
  taxonomy (`AGENTS.md` §2) rather than under Information Protection. Cross-linked back into
  `auto-label-confidential-exchange/README.md` §11 in place of the "planned" note.
- [ ] VERIFY (pilot tenant): whether a PDF attachment on a message that an Exchange auto-labeling
  policy encrypts (via the applied label) ends up protected as part of the overall encrypted
  message envelope, or left effectively in the clear alongside a protected email body - Microsoft's
  documentation confirms this behavior for unencrypted Office (Word/PowerPoint/Excel) attachments
  specifically but doesn't state the PDF case with the same confidence. Flagged inline in
  `auto-label-confidential-exchange/README.md` §11 rather than resolved by guessing.
- [x] Consider a `scenarios/information-protection/` sub-scenario (or a cross-cutting note) on
  **localizing sensitive information type selection by data-residency/jurisdiction** - flagged as
  a Red Team/CISO finding in `auto-label-confidential-sharepoint/reviews.md`: the SSN + Credit
  Card Number starter set is U.S.-centric and should not be presented as GDPR-complete personal-
  data coverage for an EU/UK-only tenant without swapping in the relevant regional SITs. - **built**
  (see DONE below) as `scenarios/information-protection/auto-label-eu-personal-data-sharepoint/`:
  the direct EU/UK sibling, defaulting to Microsoft's built-in EU-wide bundle SITs (EU national
  identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number)
  with a `-SensitiveInfoTypeName` parameter for narrowing to specific member states - the actual
  scripted localization mechanism this item asked for, not just README prose. Cross-linked back
  into `auto-label-confidential-sharepoint/README.md` §2.

### Follow-ups discovered while building the EU/UK personal data auto-labeling scenario
- [ ] VERIFY (pilot tenant, before production reliance): the exact, byte-precise capitalization of
  the three default SIT names (`EU national identification number`, `EU Social Security Number
  (SSN) or Equivalent ID`, `EU debit card number`) as required by `Get-DlpSensitiveInformationType`/
  the portal SIT picker - Microsoft's own Learn pages render the same SIT with inconsistent casing
  across pages, and this build found no single byte-exact authoritative source. Mitigated at
  runtime (the deploy script resolves every name against the tenant's live SIT catalog and fails
  clearly on a mismatch rather than silently deploying a zero-match rule) but not resolved with
  certainty - see `auto-label-eu-personal-data-sharepoint/design.md` §4 and `README.md` §11.
- [ ] VERIFY (pilot tenant): `Get-AutoSensitivityLabelRule`'s read-back property casing for
  `ContentContainsSensitiveInformation` (`name` vs. `Name`) - the documented *write* shape uses
  lowercase `name`/`mincount` (confirmed against `New-DlpComplianceRule`'s own reference examples),
  but no worked example found during this build's grounding pass shows the corresponding `Get-*`
  read-back shape. `auto-label-eu-personal-data-sharepoint/validate/
  Test-EuPersonalDataAutoLabelPolicy.ps1` checks both defensively rather than assuming one.
- [x] `scenarios/information-protection/auto-label-eu-personal-data-exchange/` - the Exchange
  (email) companion to this SharePoint/OneDrive scenario, the same location-split pattern already
  used for the U.S.-SIT sibling (`auto-label-confidential-sharepoint/` → `auto-label-confidential-
  exchange/`) - **built** (see DONE below): combines the Exchange location/exclusion/encryption
  mechanics from `auto-label-confidential-exchange` with the EU/UK SIT set and
  `-SensitiveInfoTypeName` localization mechanism from this scenario, unchanged from both sources.
  Four-lens review surfaced two findings specific to the three-scenario combination not visible
  from either sibling alone: independent SIT-list localization drift between this scenario and the
  new Exchange sibling (no shared config store ties the two scripts together), and a policy-name
  disambiguation risk across the now four sibling-family auto-labeling policies during incident
  response - both resolved with README additions (a standing review-cadence check and a
  disambiguation table), not new code. Cross-linked back into this scenario's own `README.md` §11
  and `design.md` §8.
- [x] Consider a per-country checksum-strength reference table (which EU national ID bundle members
  are checksum-validated vs. pattern-only) as either a cross-cutting doc addition or an expanded
  `README.md` §11 table - flagged as a Red Team finding (`auto-label-eu-personal-data-sharepoint/
  reviews.md`) but only individual examples (France CNI: no checksum; Belgium National Number: yes)
  were grounded in this build, not a full 26-country table. - **built** (see DONE below): all 26
  members of the "EU national identification number" bundle fetched individually from their own
  Microsoft Learn entity-definition pages and tabled in `auto-label-eu-personal-data-sharepoint/
  design.md` §4 - 19 are checksum-validated, 7 are pattern-only (Austria, Croatia, Cyprus, France,
  Greece, Malta, U.K.), with Germany flagged as checksum-validated on its post-2010 format only.
  `README.md` §8/§11 in both the SharePoint/OneDrive and Exchange EU-personal-data siblings updated
  from vague "several others" prose to the exact counts, cross-linking the new table instead of
  duplicating it.
- [x] Consider adding `EU passport number` and `EU driver's license number` as an opt-in bundle
  (not a new default) for an organization whose SharePoint/OneDrive estate is travel-document- or
  HR-record-heavy - **built** (see DONE below): `-IncludeTravelDocumentSits` switch added to
  `auto-label-eu-personal-data-sharepoint/deploy/New-EuPersonalDataAutoLabelPolicy.ps1` and its
  validate script, appending both SITs to whatever `-SensitiveInfoTypeName` set is already in
  effect. A dedicated grounding pass (fetching both bundles' own Microsoft Learn index pages
  directly) surfaced a real gotcha not previously documented anywhere in this repo: the "EU
  passport number" bundle has no standalone U.K. entity - U.K. coverage is merged into a single
  combined "U.S./U.K. passport number" entity, so this switch also enables U.S. passport detection
  as an inseparable side effect. The three EU-wide bundles this scenario can reference also don't
  share identical member-state coverage (26/26/28 entities respectively, different countries
  missing from each) - full membership tables added to `design.md` §4, cross-referenced from
  `README.md` §6/§11, with a new `reviews.md` round 2 four-lens review specific to this change.

### Follow-ups discovered while building the opt-in travel-document bundle switch
- [ ] VERIFY (pilot tenant): whether `"EU driver's license number"` (the spelling used in this
  repo's prose since the scenario's original build) or `"EU drivers license number"` (the literal,
  no-apostrophe title on the SIT's own Microsoft Learn bundle-index page, fetched directly during
  this round) is the byte-exact name `Get-DlpSensitiveInformationType`/the portal SIT picker
  actually require - joins the existing open SIT-name-casing VERIFY for this scenario
  (`README.md` §11) rather than a new, separate uncertainty. The deploy script's existing
  `Resolve-SensitiveInfoTypeNames` name-resolution check already fails clearly (listing
  near-matches) if the hardcoded default is wrong, rather than silently deploying a zero-match
  rule, so this doesn't block use - it would only let a future revision state the default with
  certainty.

### Follow-ups discovered while building the Exchange PII exfiltration block (DLP) scenario
- [ ] VERIFY (pilot tenant): the exact `Name` value `Get-RMSTemplate` returns for the auto-created
  **Encrypt-Only** RMS template in a real tenant - Microsoft's documentation confirms the template
  exists automatically once Message Encryption is active but never publishes a canonical, byte-
  exact string. `exchange-pii-exfil-block/deploy/New-ExchangePiiDlpPolicy.ps1` checks for it at
  runtime rather than assuming (fails clearly, listing available templates, if no match), but a
  first Encrypt-mode deploy in a new tenant should confirm the default `-EncryptTemplateName
  'Encrypt-Only'` actually matches before scripting around it unattended. Flagged inline in
  `README.md` §11 and the deploy script's `.NOTES`.
- [ ] VERIFY (pilot tenant, before production reliance): run the full functional test suite in
  `exchange-pii-exfil-block/README.md` §7 to confirm `-AccessScope NotInOrganization` combined with
  `BlockAccess`/`EncryptRMSTemplate` behaves as designed for the SSN/Credit Card Number SIT pair -
  every individual parameter is grounded from official Microsoft Learn references, but no worked
  example combines them for this exact case, the same class of gap already flagged (and still open)
  for `pci-teams-exfil-block`'s own `BlockAccess`/Teams combination.
- [x] `scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/` - **built** (see DONE
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
  rule to `exchange-pii-exfil-block`'s own named policy - the same split-content/behavioral blind
  spot `pci-teams-exfil-block-part2-obfuscation-mitigation` addresses for Teams applies equally to
  Exchange (SSN/PAN fragments split across separate emails to the same or different recipients) -
  **built** as `scenarios/dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation/` (see DONE
  below).

### Follow-ups discovered while building the Insider Risk Management departing-employee scenario
- [x] Consider scripting the HR-connector Entra app registration itself (Microsoft Graph
  `New-MgApplication`/`New-MgServicePrincipal`/app-password creation) instead of leaving it a
  manual portal prerequisite (`scenarios/insider-risk/departing-employee-data-theft/README.md`
  §5 step 2) - **built** (see DONE below): a follow-up grounding pass found that no
  HR-connector-*specific* cmdlet was ever needed - Microsoft's own guide names only the generic
  app-registration quickstart, because Step 2's requirement is a plain, permission-free app
  registration. `deploy/Register-HrConnectorApp.ps1` (idempotent, `-WhatIf`-capable,
  `-RotateSecret` for the ~90-day rotation cadence) and
  `validate/Test-HrConnectorAppRegistration.ps1` (checks existence, service principal, unexpired
  secret, and - the load-bearing hygiene check - that no Graph API permission has been granted)
  ship this without inventing anything; `docs/rbac-model.md` §11 (new) documents the
  Entra-role/Graph-scope prerequisite for running it, and reviews.md carries an addendum
  four-lens pass on the new capability.

### Follow-ups discovered while building the HR-connector app-registration automation
- [x] Consider a `-RemoveExpired` (or standalone `Remove-HrConnectorAppSecret.ps1`) option that
  calls `Remove-MgApplicationPassword` to delete a superseded secret by `KeyId` after
  `Register-HrConnectorApp.ps1 -RotateSecret` adds a new one, rather than leaving cleanup as a
  fully manual step (`README.md` §11) - **built** (see DONE below) as the standalone
  `deploy/Remove-HrConnectorAppSecret.ps1`, with a default `-RemoveExpired` mode (deletes only
  already-dead credentials, so it can never reduce the app's working-secret count) and a
  narrower `-KeyId`/`-Force` mode for force-retiring a still-valid secret. `Remove-
  MgApplicationPassword`'s exact parameter set was freshly re-verified this session against its
  own Microsoft Learn reference page rather than assumed by symmetry with
  `Add-MgApplicationPassword` - including the non-obvious detail that its `-KeyId` parameter's
  documented type is `System.String`, not `System.Guid`, despite the underlying Graph resource
  property's Edm type being `Guid`; this script's own `-KeyId` parameter matches that (typed
  `[string]` with a GUID-format `ValidatePattern`, not `[guid]`).
- [x] `scenarios/insider-risk/security-policy-violations-by-departing-users/` - the related but
  distinct IRM template requiring Microsoft Defender for Endpoint integration, explicitly called
  out as a non-goal in `departing-employee-data-theft/design.md` §7 - **built** (see DONE below):
  reuses (does not duplicate) the sibling scenario's HR connector/`Send-HrTerminationRecord.ps1`,
  documents the two new portal-only prerequisites (Defender for Endpoint's "Share endpoint alerts
  with Microsoft Compliance Center" advanced feature; Intelligent detections' alert-triage-status
  selection), and ships `deploy/Export-SecurityViolationInsiderRiskAlerts.ps1` - a new,
  scenario-specific capability (not a copy of the sibling's export script) that best-effort-joins
  the resulting IRM alert to its correlated Defender for Endpoint alert by `IncidentId`. Both the
  overall template family and its Defender for Endpoint indicator category are Microsoft-labeled
  **preview** - flagged prominently, not just once, per the four-lens review's CISO finding.
- [ ] VERIFY (pilot tenant, before any customer relies on the daily-schedule pattern in
  `departing-employee-data-theft/deploy/Send-HrTerminationRecord.ps1`): whether re-uploading an
  unchanged resignation CSV on a subsequent scheduled run is a safe no-op or creates a duplicate
  signal - undocumented by Microsoft as of this build (flagged inline in the script's `.NOTES`
  and `README.md` §11).

### Follow-ups discovered while building the Security Policy Violations by Departing Users scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether this template's specific
  Defender for Endpoint indicators (malware/harmful-app install, security-control bypass) require
  Defender for Endpoint **Plan 2**'s EDR sensor, or whether Plan 1's next-gen antivirus/tamper-
  protection alerting already satisfies them - Microsoft's own prerequisite table for this
  template names only "an active Defender for Endpoint subscription" with no plan qualifier, and
  no page found during this build resolves it either way. `README.md` §3.
- [ ] VERIFY (pilot tenant): whether a Defender for Endpoint alert and the Insider Risk
  Management alert it triggers under this template actually share one `incidentId` - the core
  assumption behind `deploy/Export-SecurityViolationInsiderRiskAlerts.ps1`'s join. Microsoft
  documents general cross-product alert correlation into a shared incident and separately
  documents that IRM alert data reaches the same unified alert queue, but no worked example
  confirming this specific pairing was found. The script degrades gracefully (exports the IRM
  alert with an empty `RelatedDefenderAlerts` array) when the join doesn't fire, so this doesn't
  block production use - it would only let a future revision state the join's reliability with
  confidence instead of "best effort." `README.md` §11; `design.md` §2 goal 5/§5.
- [x] Cross-reference a Microsoft Defender for Endpoint role capable of managing advanced features
  (e.g., **Security Administrator**) into `docs/rbac-model.md` - that doc currently covers Purview,
  Entra directory, and Intune RBAC (§9) but not the Defender for Endpoint role needed for this
  scenario's §5 Step 2 (enabling "Share endpoint alerts with Microsoft Compliance Center").
  `security-policy-violations-by-departing-users/README.md` §3 notes this gap inline rather than
  guessing at a role name beyond the one Microsoft's own advanced-features documentation implies -
  **built** (see DONE below): new §12 covers basic permissions (Security Administrator/Security
  Reader), the legacy granular **Manage security settings in Security Center** permission, and its
  Defender-unified-RBAC (URBAC) equivalent **Core security settings (Manage)**.
- [x] `scenarios/insider-risk/security-policy-violations/` (the base template) - **built** (see
  DONE below): the base "Security policy violations" template's own triggering event *is* the
  Defender for Endpoint security alert (no HR/departure trigger, no priority-user-group
  requirement, confirmed directly against Microsoft's policy-templates reference during this
  build). Correction to this item's own original framing: "scores every onboarded user
  continuously" is not achievable at enterprise scale - Microsoft caps this specific template at
  **1,000** actively-scored users tenant-wide (identical to the priority-users sibling's own cap,
  smaller than departing-users' 15,000 and risky-users' 7,500), so the scenario ships a new,
  genuinely scenario-specific `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` (resolves a
  chosen Entra group's transitive user membership via `Get-MgGroupTransitiveMemberAsUser`, dedupes,
  filters to enabled accounts, checks against the cap) rather than defaulting to an "all users"
  scope. Reuses the departing-users sibling's `Export-SecurityViolationInsiderRiskAlerts.ps1`
  unmodified (that script has no policy-specific filter, so shipping a copy would be pure
  duplication). Four-lens review surfaced and resolved one real gap: whether an IRM policy's scope
  tracks a directly-added group's live membership isn't documented by Microsoft either way, so a
  newly added privileged-group member could sit unmonitored under a calendar-only review cadence -
  `README.md` §8 now ties re-scoping to the group-membership-change event itself, with a quarterly
  review as a backstop, not the primary mechanism. `design.md` §3/§6 for the full grounding.
  `…-by-priority-users/` and `…-by-risky-users/` remain open follow-ups below - each has its own
  materially different trigger/scoping model and wasn't bundled into this fragment per
  `AGENTS.md` §6's one-fragment-per-turn discipline.
- [x] `scenarios/insider-risk/security-policy-violations-by-priority-users/` - **built** (see DONE
  below): the priority-users variant of this template family. Same triggering event as the base
  template (Defender for Endpoint security-violation alert, no HR/Entra-deletion trigger), scored
  against a **priority user group** (Settings → Priority user groups; up to 10,000 members;
  populated via portal search/select or a `user principal name`-headed CSV bulk upload - no
  Graph/PowerShell write API found for this object) instead of a plain Entra group. New
  `deploy/Get-PriorityUserGroupScopeCandidates.ps1` resolves an Entra group's transitive membership
  into upload-ready CSV and sizes it against **both** documented caps independently (10,000-member
  group cap and the 1,000-actively-scored template cap, cumulative with the base template per the
  same Microsoft limits reference). The interaction between those two caps - this item's own
  originating question - has **no confirmed answer**: no Microsoft Learn page states what happens
  when a priority user group exceeds the template's actively-scored cap once assigned to a policy.
  Documented as an explicit, unresolved VERIFY throughout (`design.md` §3, `README.md` §3/§6/§11)
  rather than guessed at. Alert export reused unmodified from the departing-users sibling, same
  reuse pattern as the base template. Four-lens review caught and fixed one overclaim (README §5
  originally asserted the "Users and groups" step accepts *only* the priority group, not also
  additional scope - softened to an open VERIFY, no worked example found either way) and one
  disclosure gap (no-`mail`-attribute candidates flagged `[WARN]` but the original draft didn't
  say what to do about it - added explicit guidance not to silently drop guest/service accounts
  from the priority population). **Grounding note:** this build's network access could not reach
  learn.microsoft.com directly (proxy-blocked) - all facts were grounded via WebSearch against the
  same official Microsoft Learn URLs (corroborated by more than one independent source where a
  direct quote was needed, e.g. the CSV column header and the 10,000-member cap) rather than a
  direct page fetch; flagged in `README.md`'s closing reference note. Re-verify directly against
  the live pages before a customer-facing commitment.
- [x] `scenarios/insider-risk/security-policy-violations-by-risky-users/` - the risky-users variant
  - **built** (see DONE below): the fourth and final member of the "Security policy violations…"
  template family. Triggering events are HR risk-indicator signals (job level change / performance
  review / performance improvement plan, via a **new, dedicated** HR connector - not reused from
  `departing-employee-data-theft`, whose connector is scoped to Resignation data only) AND/OR
  Communication Compliance risk-signal integration, both requiring the shared Defender for Endpoint
  prerequisite every sibling has. 7,500-user template-wide cap, confirmed directly via the
  Microsoft Learn MCP tool (available this run, contrary to this task's stored instructions).
- [ ] VERIFY (pilot tenant): whether adding an Entra security group directly to an Insider Risk
  Management policy's "Users and groups" scope keeps the in-scope population in sync with the
  group's future membership changes, or captures membership as a snapshot at add-time - not stated
  either way by Microsoft's own policy-configuration documentation. Surfaced while building
  `scenarios/insider-risk/security-policy-violations/` (the base template) but is a general IRM
  policy-scoping question, not specific to that one scenario - flagged inline in that scenario's
  `README.md` §5 Step 4 and §11, and in `design.md` §6, rather than assumed either way. Resolving
  this would let every Insider Risk Management scenario in this library that scopes a policy by
  group (not just this one) state its re-scoping cadence guidance with more precision.

- [x] `scenarios/dlp/endpoint-dlp-usb-block-adaptive-protection/` (or fold into a future Endpoint
  DLP hardening pass) - script the **Devices** half of Adaptive Protection (risk-based
  clipboard/USB/print/network-share/restricted-app restrictions via `-SharedByIRMUserRisk` +
  `-EndpointDlpRestrictions`), deferred from `dynamic-risk-dlp-enforcement` because
  `-EndpointDlpRestrictions`'s exact `Setting`/`Value` strings already carry an open VERIFY from
  `scenarios/dlp/endpoint-dlp-usb-block/` - needs that VERIFY closed first (ideally via a pilot
  tenant) rather than compounding a second unverified use of the same parameter. Also requires
  either Advanced classification scanning and protection enabled, or an explicit File Type
  condition, per Microsoft's documented Devices-policy prerequisite. - **built** (see DONE below):
  this item's own stated blocker was actually already closed by `endpoint-dlp-usb-block`'s own
  later grounding pass (Print/CopyPaste/ScreenCapture/RemovableMedia/NetworkShare/UnallowedApps
  Setting names and the Audit/Block/Ignore/Warn enum, confirmed on both `New-`/`Set-
  DlpComplianceRule`'s official reference pages) - this build re-confirmed that directly via a
  fresh fetch of both pages rather than trusting the stale PROGRESS.md wording, then scripted the
  4 of 6 Quick-Setup Devices actions with a fully-grounded `-EndpointDlpRestrictions` shape
  (RemovableMedia/CopyPaste/NetworkShare/Print). The remaining 2 actions ("Access by restricted
  apps," cloud/browser-domain upload restriction) remain genuinely unscriptable - Microsoft's own
  reference documents `UnallowedApps` only as an app-declaration mechanism (not an action), and no
  Setting name for the cloud/browser restriction is documented anywhere - disclosed precisely as a
  4-of-6 scope boundary rather than fabricated, per `AGENTS.md` §4. The Devices-only prerequisite
  is satisfied via Advanced classification scanning and protection (portal-only toggle, confirmed
  no PowerShell/Graph surface exists), not a File Type condition, because
  `-ContentFileTypeMatches`'s value syntax is itself unpublished placeholder text on both cmdlet
  reference pages - a second, related undocumented-parameter finding this build surfaced and
  disclosed rather than guessed around.
- [x] `scenarios/adaptive-protection/conditional-access-insider-risk-block/` - script/document
  the Conditional Access "Insider risk" condition integration (Microsoft Entra admin center,
  requires **Microsoft Entra ID P2**), deferred from `dynamic-risk-dlp-enforcement` because it's
  a different admin surface (Entra, not Purview/EXO) with its own license prerequisite this
  scenario's DLP-only design doesn't otherwise require. Still a Microsoft-labeled **preview**
  integration as of this build - re-check GA status before scoping. - **built** (see DONE below):
  the GA re-check this item asked for found the integration is **no longer preview** - corrects
  the stale claim, see the new DONE entry and `design.md` §8 in the built scenario.
- [x] `scenarios/data-lifecycle-management/adaptive-protection-deleted-content-preservation/` -
  **built** (see DONE below): the 120-day deleted-content preservation policy Adaptive Protection
  can auto-create for Elevated-risk users, deferred from `dynamic-risk-dlp-enforcement` as a
  separate opt-in with its own retention-policy implications.
- VERIFY (pilot tenant, before a customer relies on it in production): whether representing the
  portal's compound "Content is shared from Microsoft 365 with people outside my organization"
  condition using `-AccessScope NotInOrganization` alone (this scenario's and
  `pci-teams-exfil-block`'s shared pattern) is a byte-for-byte match to the portal-rendered rule,
  or whether a separate `-ContentIsShared` boolean condition is also required - flagged inline in
  `dynamic-risk-dlp-enforcement/deploy/New-AdaptiveProtectionDlpPolicy.ps1`'s `.NOTES` and
  `README.md` §11.

### Follow-ups discovered while building the Adaptive Protection Devices Endpoint DLP scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/GitHub-samples pass): whether a documented
  `-EndpointDlpRestrictions` rule-level action shape for "Access by restricted apps" or "Upload to
  a restricted cloud service domain or access from unallowed browsers" has since been published.
  `endpoint-dlp-usb-block-adaptive-protection`'s scripted rules cover only 4 of Microsoft's 6
  documented Devices Quick Setup actions because `UnallowedApps`'s only documented example
  declares an app (not an action), and no Setting name for the cloud/browser restriction is
  documented anywhere this build found - see that scenario's `README.md` §11 and `design.md`
  §2/§6/§7. If either is resolved, extend `deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1`'s
  two rules to the full 6-action Quick Setup shape.
- [ ] VERIFY (pilot tenant): `-ContentFileTypeMatches`'s value syntax and valid strings - both
  `New-DlpComplianceRule` and `Set-DlpComplianceRule`'s official reference pages carry unpublished
  placeholder text for this parameter as of this writing. `endpoint-dlp-usb-block-adaptive-
  protection` avoided it entirely (Advanced-classification-scanning prerequisite path instead -
  see that scenario's `design.md` §4/§6), but resolving this would let a future revision add
  Microsoft's own file-type-scoped condition and close the file-type-scope divergence disclosed in
  that scenario's `README.md` §6/§11.
- [ ] VERIFY (pilot tenant): the disclosed `NotifyUser`/Block tension in
  `endpoint-dlp-usb-block-adaptive-protection`'s Elevated-block rule - Microsoft's cmdlet reference
  states Block/Warn values require `NotifyUser`, but the same documented Devices Quick Setup rule
  table shows "User Notification: Off" for this exact rule. Confirm what a user actually sees
  (toast/notification present or absent) before describing this rule's user-facing behavior to a
  customer - see that scenario's `README.md` §11 and `deploy/
  New-AdaptiveProtectionDevicesDlpPolicy.ps1`'s `.NOTES`.
- [ ] **CORRECTION (re-grounded, not built):** Consider a cross-cutting follow-up scripting
  `Set-PolicyConfig -EndpointDlpGlobalSettings` as its own scenario or companion script - this
  defines the tenant-wide restricted-apps/browsers/domains **lists** Endpoint DLP rules reference,
  distinct from (and not blocked by) the per-rule action-shape gap above. Deferred here because it's
  shared, tenant-wide state not specific to Adaptive Protection - see
  `endpoint-dlp-usb-block-adaptive-protection/design.md` §7. **This item's original framing was
  wrong**: a fresh grounding pass (direct Microsoft Learn search + fetch, not WebSearch) found the
  `Set-PolicyConfig`/`Get-PolicyConfig` reference pages carry only placeholder (`{{ Add example code
  here }}`) examples for `-EndpointDlpGlobalSettings` - **no worked example exists** for the
  `UnallowedApp`/`UnallowedBrowser`/`CloudAppRestrictions`/`CloudAppRestrictionList`/`PathExclusion`
  hashtable keys this item previously claimed were "genuinely documented with worked examples." The
  portal-only "Configure endpoint data loss prevention settings" page documents these same settings
  by UI name (Restricted apps, Unallowed browsers, Service domains, Path exclusions) but never
  states the `-EndpointDlpGlobalSettings` PowerShell hashtable's exact `Setting`/`Value` key names.
  Building this as a scenario now would mean inventing hashtable keys Microsoft hasn't published -
  against `AGENTS.md` §4's "never invent cmdlets" rule. Re-open only once a Microsoft Learn page
  (or a `Get-PolicyConfig` pilot-tenant read-back showing the live property shape) actually shows the
  hashtable's key names in use.

### Follow-ups discovered while building the Adaptive Protection deleted-content-preservation scenario
- [ ] VERIFY (pilot tenant): whether the Data Lifecycle Management/Records Management Purview role
  group is *also* accepted for the "Adaptive protection in Data Lifecycle Management" toggle
  itself (it surfaces under the Data Lifecycle Management solution settings UI, not the Insider
  Risk Management app), or whether only the Insider Risk Management/Insider Risk Management Admins
  role group Microsoft's own page links to actually works. Flagged inline in
  `adaptive-protection-deleted-content-preservation/README.md` §3/§11 rather than assumed.
- [ ] VERIFY (pilot tenant): the exact `AuditData` JSON field names populated for the
  `SharePointDataProactivelyPreserved`/`ExchangeDataProactivelyPreserved` audit Operations -
  `deploy/Export-AdaptiveProtectionPreservationEvidence.ps1` extracts `Workload`/`ObjectId`/
  `SourceFileName` best-effort from the general Search-UnifiedAuditLog schema, not a worked
  Microsoft example for these two Operations specifically. The raw `AuditData` JSON column is
  always preserved regardless.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether disabling the "Adaptive
  protection in Data Lifecycle Management" toggle (or any other admin action on it) is captured in
  Insider Risk Management's own internal audit log (viewable by the Insider Risk Management
  Auditors role) - not confirmed either way, and that log has no documented Graph/REST query API
  this library has found (the same gap already tracked for a different scenario - see the
  `irm-case-escalation-to-ediscovery` follow-ups near the top of this file). Resolving either half
  would let `adaptive-protection-deleted-content-preservation/README.md` §11's self-sabotage
  finding state a concrete detection mechanism instead of an open gap.
- [x] Consider a Data Lifecycle Management follow-up scenario for **Priority Cleanup** - a
  different DLM feature that also applies retention labels internally and can override holds to
  reclaim disk space or permanently delete sensitive information - explicitly out of scope for
  this fragment (`design.md` §7) since it's unrelated to Adaptive Protection. - **built** (see
  DONE below) as `scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/`:
  the Exchange, data-spillage variant (Microsoft's own lead use case and richest, 3-stage approval
  model). Grounded directly against the official `-PriorityCleanup` parameter set Microsoft ships
  on `New-ComplianceTag`/`New-RetentionCompliancePolicy`/`New-RetentionComplianceRule` - a real,
  documented automation surface, not a fabricated one. Two genuine construction gaps disclosed as
  VERIFY rather than guessed: the `-MultiStageReviewProperty` 3-stage JSON shape (mandatory on the
  label, but no Microsoft worked example ties it to priority cleanup's specific 3-approver model),
  and the `RetentionDuration`/`RetentionType` value that maps to the portal's "delete as soon as
  possible" choice. Confirmed no PowerShell/Graph cmdlet exists for approving pending priority
  cleanup items or for the tenant-wide on/off toggle - both stated as portal-only gaps, not
  invented. The SharePoint/OneDrive variant (different, single-eDiscovery-admin approver model,
  mandatory simulation, and a separate public-preview permanent-deletion sub-feature) is a
  follow-up below, per `AGENTS.md` §6's one-fragment-per-turn discipline.

### Follow-ups discovered while building the Priority Cleanup Exchange data-spillage scenario
- [x] `scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/` - the
  SharePoint/OneDrive sibling: different approver model (eDiscovery admin only, vs. Exchange's
  3-stage priority-cleanup-admin/retention-manager/eDiscovery-admin chain), **mandatory**
  simulation before every enable (vs. recommended-only for Exchange), and typical continual use
  (stale Teams meeting recordings/transcripts, Preservation Hold library cleanup after a user
  leaves) rather than Exchange's rare, incident-driven use - **built** (see DONE below): full
  README/design/deploy/validate/rollback/reviews, cross-linking `docs/licensing-matrix.md` §7 and
  `docs/rbac-model.md` §4 (both updated to state the two workloads' different approver-role tables
  and shared tenant-wide toggle), and backporting a "see the sibling" cross-link into the Exchange
  scenario's own `README.md`/`design.md` in place of the old "tracked as a follow-up" language.
- [x] `scenarios/data-lifecycle-management/priority-cleanup-permanent-deletion/` - **built** (see
  DONE below): the separate SharePoint/OneDrive **permanent deletion** sub-feature (bypasses the
  second-stage Recycle Bin entirely). Public preview rollout (2026-08-24) had begun by this build's
  date (2026-09-09), so the deferral no longer applied. Central finding: no confirmed PowerShell/
  Graph parameter selects "Delete data permanently" (the portal-only differentiator step) -
  `New-ComplianceTag -RetentionAction` was directly confirmed to accept only
  `Delete`/`Keep`/`KeepAndDelete`, no fourth value. Scripts the shared, confirmed base
  label/policy/rule objects and discloses the manual step + read-back gap rather than guessing;
  post-hoc confirmation via the new `PriorityCleanupFileDeleted` audit operation is fully scripted.
- [ ] VERIFY (pilot tenant, before production reliance): whether the `-MultiStageReviewProperty`
  JSON's `StageName` values and array order are meaningful to the platform (e.g. must match a
  fixed priority-cleanup-admin → retention-manager → eDiscovery-admin sequence) or are purely a
  display label with role membership alone driving approval order - no Microsoft worked example
  ties this parameter to priority cleanup specifically, only its general multi-stage-disposition-
  review shape. Flagged inline in `priority-cleanup-exchange-data-spillage/design.md` §4,
  `README.md` §6/§11, and the deploy script's `.NOTES`/config `_labelNote` rather than guessed.
- [ ] VERIFY (pilot tenant): the exact `RetentionDuration`/`RetentionType` value the portal's
  "delete matched items as soon as possible" choice actually issues - this scenario defaults to
  `RetentionDuration 0` / `RetentionType TaggedAgeInDays` as the closest literal reading, loosely
  corroborated by the end-user-facing `(-1 days)` countdown Microsoft's docs describe for this
  mode, but no cmdlet-level worked example confirms it. `priority-cleanup-exchange-data-spillage/
  design.md` §4 and `README.md` §6/§11.
- [ ] Once a documented PowerShell/Graph cmdlet exists for the priority-cleanup tenant-wide
  on/off toggle (the "Priority cleanup settings" portal page), or for the "Pending cleanups"
  approval queue, extend `priority-cleanup-exchange-data-spillage`'s scripts to cover it - neither
  was found during this build's grounding pass across official Microsoft Learn sources; both are
  disclosed as portal-only gaps rather than fabricated cmdlets (`README.md` §11, `design.md` §7).
- [x] Consider a companion scenario chaining eDiscovery search-and-purge (soft-delete) with this
  scenario's priority cleanup policy, matching Microsoft's own documented workflow for avoiding
  the end-user-visible "Retention: ... (-1 days)" message bar in Outlook - deferred here
  (`design.md` §7) since no eDiscovery search-and-purge scenario exists yet in this repo to chain
  onto. **Built** (see DONE below) as `scenarios/ediscovery/search-and-purge-data-spillage/`.

### Follow-ups discovered while building the eDiscovery search-and-purge-data-spillage scenario
- [ ] VERIFY (pilot tenant): whether a mailbox on litigation hold behaves identically for the Graph
  `purgeData` action as Microsoft's FAQ documents for the PowerShell `New-ComplianceSearchAction
  -Purge` path (items only hidden from view, not deleted, regardless of `purgeType`) - both paths
  share the same underlying eDiscovery search/purge engine, but no Microsoft Learn page
  independently confirms the hold behavior specifically for `purgeData`. `search-and-purge-data-
  spillage/README.md` §11 and `design.md` §2 goal 5/§6.
- [ ] VERIFY: how long a `purgeData` job report's `reportFileMetadata.downloadUrl` remains valid
  before expiring - not stated on the `ediscoveryPurgeDataOperation` Graph reference page.
  `search-and-purge-data-spillage/README.md` §11.
- [x] `scenarios/ediscovery/search-and-purge-teams-messages/` - **built** (see DONE below): the
  `purgeAreas: teamsMessages` half of the same `purgeData` Graph action. Re-grounding this item found
  the original follow-up's own premise was **backwards**: current Microsoft Learn states that for
  `purgeAreas: teamsMessages`, either `purgeType` value permanently deletes the Teams *user-visible*
  message immediately (not just the compliance copy) - the compliance-copy-only behavior applies only
  to the legacy, cmdlet-based purge path Microsoft's own current guidance says to avoid for Teams.
  `search-and-purge-data-spillage/README.md` §6/§11 and `design.md` §7/§8 corrected in place rather
  than left standing next to a scenario that contradicts them.

### Follow-ups discovered while building the eDiscovery Teams search-and-purge scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): reconcile the private-channel
  compliance-copy storage model - "Find and delete Microsoft Teams chat messages in eDiscovery"
  states "a dedicated mailbox for each private channel," while "Finding content in Microsoft Teams
  in eDiscovery" states private-channel messages are "stored in the Exchange Online mailboxes of all
  members of the private channel." This build found no page reconciling the two.
  `search-and-purge-teams-messages/README.md` §11 and `design.md` §4.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/SDK pass): the typed Microsoft.Graph.Security
  v1.0 PowerShell cmdlet name for binding an existing `ediscoveryNoncustodialDataSource` onto a
  search via `POST .../searches/{id}/noncustodialSources/$ref` - this build found no page confirming
  it, so `deploy/New-TeamsMessagePurgeSearch.ps1` calls the confirmed raw HTTP shape via
  `Invoke-MgGraphRequest` instead of guessing. `search-and-purge-teams-messages/design.md` §6.
- [ ] VERIFY (pilot tenant): how a case-level `ediscoveryNoncustodialDataSource`'s `DisplayName` is
  populated for a `userSource` (mailbox) - only a `siteSource` worked example was found. The deploy
  script's find-or-create idempotency check matches on `DisplayName` as a best-effort heuristic.
  `search-and-purge-teams-messages/design.md` §6.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether `-PurgeType` still meaningfully
  affects the Teams **compliance copy's** own retention/hold-interaction timing, even though it no
  longer gates the user-copy outcome (both values delete the user copy immediately). No Microsoft
  Learn page found during this build confirms either way. `search-and-purge-teams-messages/README.md`
  §11.
- [x] Consider a cross-cutting follow-up scripting the Teams-purge hold-removal/reapplication
  sequence (identify holds on target mailboxes via Top Locations, remove, purge, reapply) that
  `search-and-purge-teams-messages` deliberately left manual (`design.md` §3 goal 5) - a genuinely
  separate, larger scope (hold lifecycle management) than this fragment's own search-and-purge focus.
  - **built** (see DONE below) as `scenarios/ediscovery/teams-purge-hold-lifecycle-management/`.
- [x] Consider grounding Microsoft's newer **Data Security Investigations** purge-queue workflow
  (referenced as an alternative entry point on the "Find and delete Microsoft Teams chat messages"
  page) as its own future fragment - a different product surface this build didn't ground.
  `search-and-purge-teams-messages/design.md` §9. - **built** (see DONE below) as
  `scenarios/data-security-investigations/post-breach-investigation-and-purge/`: a new top-level
  module (first DSI scenario in this library). Grounded that DSI's investigation/search/AI-analysis/
  purge workflow has no documented write API (portal-only) - scripted the two genuinely automatable
  surfaces instead: least-privilege RBAC for the three dedicated DSI role groups, and a
  Search-UnifiedAuditLog-based audit trail covering all 28 documented DSI Operations, with
  `DSIPurgeStarted` flagged as the scenario's highest-priority Blue Team signal. New follow-ups
  recorded immediately below under their own section rather than duplicated here.

### Follow-ups discovered while building the Data Security Investigations post-breach-investigation-and-purge scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the `Search-UnifiedAuditLog`
  `RecordType` enum value for Data Security Investigations records - Microsoft's audit-log-activities
  reference lists all 28 `DSI*` Operations but never states the RecordType that carries them.
  `deploy/Export-DsiActivityAuditTrail.ps1` queries by `-Operations` alone rather than guessing one;
  see the script's `.NOTES`, `README.md` §11, and `design.md` §5.
- [ ] Once the **Data Security Posture agent (preview)** - a related but separately-enabled DSI
  feature surfaced during this fragment's grounding pass - reaches a more stable/GA state, consider
  its own dedicated fragment; explicitly out of scope here (`design.md` §6).
- [ ] Once a documented PowerShell/Graph configuration surface exists for DSI billing/AI-capacity
  settings (compute-unit maximum, processing location) or the DSPM (preview) proactive-AI-insights
  auto-investigation toggle, extend `deploy/New-DsiRoleGroupAssignments.ps1` or add a sibling script -
  both are currently portal-only with no API found (`design.md` §6).
- [x] Consider wiring `deploy/Export-DsiActivityAuditTrail.ps1`'s CSV output into
  `scenarios/audit/streaming-to-sentinel-or-management-api/` as a documented companion feed (the same
  NDJSON/CSV-to-SIEM hand-off pattern that scenario already establishes) rather than leaving the two
  scenarios' outputs unconnected - **built** (see DONE below): a new opt-in `-NdjsonOutDir` parameter
  writes new records using that scenario's exact per-run-file NDJSON convention into its own `-OutDir`,
  so one downstream forwarder can pick up both feeds without a second pipeline.
- [ ] Once Microsoft documents a job-status API for an AI-analysis job's completion or a purge job's
  outcome (success/failure/partial), extend `validate/Test-DsiRoleGroupAssignments.ps1` (or a new
  script) to check it - today the portal's per-investigation Activities tab is the only authoritative
  source (`README.md` §7/§11).

- [ ] Once `Get-MgSecurityCaseEdiscoveryCaseOperation`/`caseOperation` documents a way to identify
  which `ediscoverySearch` a completed `purgeData` (or `addToReviewSet`/export) operation targeted
  without an undocumented expand, revisit both `search-and-purge-data-spillage/deploy/
  Invoke-DataSpillagePurge.ps1`'s `Get-PriorPurgeOperations` and `premium-legal-hold-and-export/
  deploy/New-EdiscoverySearchReviewSetExport.ps1`'s equivalent case-wide (not search-specific)
  operation-listing limitation - the same underlying Graph gap affects both scenarios.

### Follow-ups discovered while building the eDiscovery Teams-Purge Hold Lifecycle Management scenario
- [ ] VERIFY (pilot tenant): whether `Set-RetentionCompliancePolicy -RemoveExchangeLocation`/
  `-AddExchangeLocation` (the mailbox-scoped-policy add/remove path) carries the same up-to-24-hour
  synchronization delay Microsoft documents explicitly for the org-wide `-AddExchangeLocationException`
  path - no equivalent explicit statement was found for the mailbox-scoped path during this build.
  `teams-purge-hold-lifecycle-management/README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): a confirmed `InPlaceHolds` notation for a
  **Group-location exclusion** (the `grp`-prefixed equivalent of `-mbx<guid>` for Exchange-location
  exclusions) - none was found during this build's grounding pass, so
  `Restore-TeamsPurgeMailboxHolds.ps1` cannot pre-check whether a Group-kind org-wide exception is
  already removed before calling `-RemoveModernGroupLocationException`, and `validate/
  Test-TeamsPurgeMailboxHoldLifecycle.ps1` reports it as `[WARN]` ("cannot verify"), never
  `[PASS]`/`[FAIL]`. `teams-purge-hold-lifecycle-management/design.md` §8.
- [ ] VERIFY (pilot tenant): whether `-RemoveDelayHoldApplied`/`-RemoveDelayReleaseHoldApplied` behave
  identically when called defensively (before a delay hold has actually appeared) vs. the documented
  case of an already-present delay hold from a prior removal cycle - this scenario only calls it in the
  latter case, matching documented usage, but the former was not independently tested.
  `teams-purge-hold-lifecycle-management/README.md` §11.
- [ ] Once Microsoft publishes a documented, per-mailbox applicability check for
  `*-AppRetentionCompliancePolicy`-governed newer-location policies (Teams chats, Teams private
  channel messages, Copilot, etc. - currently only checkable via the portal's Policy Lookup feature),
  extend `Get-TeamsPurgeMailboxHoldState.ps1`'s currently tenant-wide-only informational listing into a
  real per-mailbox match. `teams-purge-hold-lifecycle-management/design.md` §7.
- [x] Consider a companion script resolving the mailbox-scoped-vs-Group-location ambiguity this build
  deliberately left disclosed rather than solved: whether a mailbox-scoped (non-org-wide) retention
  policy on a Group/team mailbox is actually reachable via `-RemoveExchangeLocation`/
  `-AddExchangeLocation` (as this scenario assumes, matching the documented `mbx`/`skp`-prefix
  convention regardless of mailbox type) or needs the `-ModernGroupLocation` parameter family instead
  - no Microsoft Learn page directly addresses this specific combination.
  `teams-purge-hold-lifecycle-management/design.md` §8. - **built** (see DONE below): resolved, not by
  a separate companion script but by fixing the existing scenario's own four scripts in place, which is
  where the ambiguity actually lived. Two Microsoft Learn pages fetched in full this round confirm the
  Exchange-mailboxes location (org-wide **or** specific-location) categorically rejects a Microsoft 365
  Group mailbox (`retention-settings.md`'s "RemoteGroupMailbox isn't a valid selection" save-time
  error), and the specific-location `InPlaceHolds` prefix table documents only `mbx`/`skp`, never `grp`
  (`edisc-hold-types-mailboxes.md`). `ConvertTo-ParsedInPlaceHolds` now parses `grp` separately in all
  four scripts; a mailbox-scoped Group-location policy on a confirmed group/team mailbox is now removed/
  restored via `-RemoveModernGroupLocation`/`-AddModernGroupLocation` (confirmed real
  `Set-RetentionCompliancePolicy` parameters) instead of the Exchange-location pair that could never
  have applied to it; the same org-wide-Exchange-applicability gating bug (not gated on
  `-not $isGroupMailbox`, unlike its already-correct Group-side counterpart) was fixed alongside it. One
  new VERIFY carried forward, not guessed away: the exact `InPlaceHolds` notation this mechanism stamps
  for the non-org-wide case isn't explicitly confirmed by Microsoft. `design.md` §8.1 (new),
  `README.md` §6/§11/§12, and `reviews.md` Round 2 record the full grounding and fix.

### Follow-ups discovered while fixing the Teams-Purge Hold Lifecycle Management mailbox-scoped/Group-location conflation
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the exact `InPlaceHolds` notation a
  mailbox-scoped (non-org-wide) Group-location retention policy stamps on a group/team mailbox -
  `-AddModernGroupLocation`/`-RemoveModernGroupLocation` are confirmed real `Set-RetentionCompliancePolicy`
  parameters, but no Microsoft Learn page states what, if anything, shows up in `InPlaceHolds` for this
  specific case (as opposed to the org-wide `grp<guid>:n` notation, which Microsoft's own
  `Get-OrganizationConfig` reference does confirm). `teams-purge-hold-lifecycle-management/design.md`
  §8.1, `README.md` §11.
- [ ] If a Microsoft Learn source or pilot-tenant test ever surfaces a real, confirmed case of a `grp`-
  prefixed, non-org-wide `InPlaceHolds` entry on a mailbox that is genuinely NOT a group/team mailbox
  (the `UnrecognizedPolicyGuids`/`unrecognizedPolicyGuidsNotRemoved` bucket
  `teams-purge-hold-lifecycle-management`'s scripts currently only identify and never act on), ground
  what produced it and extend the scripts' removal logic accordingly - deliberately left unactioned in
  this round because no citation explains that combination (`design.md` §8.1).

### Follow-ups discovered while building the Conditional Access insider-risk-block scenario
- [x] Backport the GA-status correction (`conditional-access-insider-risk-block/design.md` §8)
  into `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/design.md` §7 and `README.md`
  §11 - both currently state the Conditional Access integration is "still labeled preview," which
  this build's fresh grounding pass found is no longer accurate (no preview label on Microsoft's
  current "Block access for users with elevated insider risk" guide or the Graph v1.0
  `conditionalAccessConditionSet.insiderRiskLevels` resource property). Small, doc-only backport
  scoped to a single follow-up fragment per `AGENTS.md` §6 - deliberately not done inside this
  build to avoid reopening an already-reviewed sibling scenario's files for an unrelated fragment.
  - **built** (see DONE below): both files corrected in place, both sources independently
  re-fetched (via the Microsoft Learn MCP tool, available this run) rather than trusting the
  sibling's own citation, and a correction addendum recorded in `reviews.md` per this repo's
  no-guessing grounding standard.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn licensing-enforcement pass): what actually
  happens at sign-in for a user in a Conditional Access policy's scope who lacks the required
  Entra ID P2 license for the Insider Risk condition specifically - silently exempted, blocked
  outright, or another behavior. Flagged inline as VERIFY in `docs/licensing-matrix.md` §8 and
  `conditional-access-insider-risk-block/README.md` §11 rather than assumed.
- [x] Script Graph's `conditions.users.excludeGuestsOrExternalUsers` nested condition (the
  "exclude B2B direct connect / service providers / other external" categories Microsoft's own
  documented procedure also recommends) - **built** (see DONE below): the resource shape
  (`conditionalAccessUsers.excludeGuestsOrExternalUsers` → `conditionalAccessGuestsOrExternalUsers`
  → `guestOrExternalUserTypes`/`externalTenants`) is independently confirmed on Microsoft Learn,
  and Microsoft's own "Block access for users with insider risk" guide's Users step names the
  exact three categories to exclude (`b2bDirectConnectUser`, `serviceProvider`,
  `otherExternalUser`) - now the new `-ExcludeGuestOrExternalUserTypes` parameter's default on
  `conditional-access-insider-risk-block/deploy/New-InsiderRiskConditionalAccessPolicy.ps1`, with
  a matching automated check added to `validate/Test-InsiderRiskConditionalAccessPolicy.ps1`. One
  narrower VERIFY carried forward rather than resolved by guessing - see the new item immediately
  below. The `externalTenants` sibling property remains a deliberate non-goal (design.md §7):
  Microsoft's own guide doesn't scope this exclusion by tenant either.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/worked-example pass): the exact separator
  Microsoft Graph uses between multiple `guestOrExternalUserTypes` flag values on the wire (this
  scenario's script assumes a bare comma, e.g. `"b2bDirectConnectUser,serviceProvider"`) and
  whether the Microsoft Graph PowerShell SDK's typed `Get-MgIdentityConditionalAccessPolicy`
  read-back returns that same raw string or an already-split collection for this specific nested
  property. Affects only this script's own local idempotency/drift detection, not the deployed
  policy's actual enforcement behavior (Graph is the source of truth for how the condition
  evaluates) - flagged inline in `conditional-access-insider-risk-block/deploy/
  New-InsiderRiskConditionalAccessPolicy.ps1`'s `.NOTES` and `README.md` §11 rather than guessed.
- [ ] VERIFY (pilot tenant): Microsoft Quick Setup's exact auto-generated Conditional Access
  policy display name, so `conditional-access-insider-risk-block`'s own `(Custom)`-suffixed name
  can be independently confirmed not to collide, the same confirmation the DLP sibling scenario
  already has for its own Quick-Setup-generated DLP policy name. Not confirmed during this build
  - see `README.md` §11.
- [x] Consider a second Conditional Access policy variant applying a softer grant control scoped
  to Moderate/Minor risk levels - **built** as
  `scenarios/adaptive-protection/conditional-access-insider-risk-step-up-auth/` (see DONE below).
  This build's grounding pass found the naive "require MFA / require compliant device" idea this
  item originally suggested was an unverified guess; Microsoft's own "Adaptive Protection
  configuration guide" documents a specific, different pairing instead - Terms of Use acceptance
  scoped to Microsoft Admin Portals (Moderate) and a permanently Report-only visibility policy
  (Minor) - reproduced exactly rather than the guessed alternative. See the new scenario's
  `design.md` §3 for the rejected-alternative rationale.
- [x] Consider scripting a companion "block legacy authentication" Conditional Access policy (or
  documenting/verifying one already exists) as a prerequisite hardening step for this scenario -
  flagged as a Red Team finding in `conditional-access-insider-risk-block/reviews.md` (legacy auth
  clients may not fully honor the Insider Risk condition) but not built in this fragment, since it
  is a general Conditional Access hardening practice outside this scenario's specific scope. -
  **built** (see DONE below) as `scenarios/adaptive-protection/block-legacy-authentication/`.
  Central grounding finding: Microsoft now auto-deploys a **Microsoft-managed** "Block legacy
  authentication" Conditional Access policy to Entra ID P2/Microsoft 365 Business Premium-eligible
  tenants (Report-only, auto-enabling no less than 30 days later) - the deploy script checks for
  this first (best-effort, by the confirmed `Microsoft-managed:` displayName-prefix convention)
  and reports its state rather than blindly deploying a duplicate, only proceeding to its own
  custom policy (`clientAppTypes = ['exchangeActiveSync','other']`, matching Microsoft's exact
  documented portal procedure) when no Microsoft-managed equivalent is found or
  `-SkipManagedPolicyCheck` is passed. Also the library's first Conditional-Access-based scenario
  confirmed to need only **Microsoft Entra ID P1** (not P2, unlike its two CA siblings) -
  `docs/licensing-matrix.md` new §9, `docs/rbac-model.md` §10 updated to cross-link it and
  disclose the P1/P2 split. Four-lens review caught and fixed a real validate-script logic gap
  (Blue Team finding 1): a *disabled* Microsoft-managed policy with no custom policy deployed was
  originally scored WARN, not FAIL, even though that combination means zero actual legacy-auth
  coverage - corrected before this fragment was marked done.

### Follow-ups discovered while building the Block Legacy Authentication scenario
- [ ] VERIFY (pilot tenant): the exact, byte-precise remainder of a Microsoft-managed policy's
  displayName beyond the confirmed `Microsoft-managed:` prefix (e.g. whether it is exactly
  `Microsoft-managed: Block legacy authentication`) - not independently confirmed word-for-word
  during this build. `block-legacy-authentication/deploy/New-BlockLegacyAuthenticationPolicy.ps1`'s
  detection regex is deliberately tolerant (prefix + `legacy` substring match) rather than an
  exact-string comparison specifically because of this open question - see `README.md` §11.
- [ ] VERIFY (pilot tenant, before relying on Graph to manage a Microsoft-managed policy
  directly): whether `Update-MgIdentityConditionalAccessPolicy`/
  `Remove-MgIdentityConditionalAccessPolicy` actually accept a PATCH (state/exclusions) or reject
  a DELETE against a Microsoft-managed policy's `id` the same way the portal UI restricts
  renaming/deletion - not independently tested during this build. This scenario's own scripts
  never attempt either against a Microsoft-managed policy regardless of the answer
  (`design.md` §7), so this doesn't block use - it would only let a future revision offer a
  scripted "manage the Microsoft-managed policy's exclusions" path instead of directing the
  operator to the portal.
- [x] Consider a companion scenario scripting Exchange-side legacy-authentication blocking
  (`New-AuthenticationPolicy -BlockLegacyAuth*` / `Set-User -AuthenticationPolicy`, or the
  Exchange 2019 hybrid authentication-policy mechanism) - `design.md` §7 notes this is a separate,
  workload-specific control surface that acts *before* first-factor authentication completes,
  materially more effective against the credential-stuffing/password-spray lockout scenario
  Conditional Access's own documented Q&A guidance says it cannot stop (`design.md` §8). Deferred
  from this fragment as a different admin surface (Exchange Online PowerShell, not Entra/Graph). -
  **built** (see DONE below) as `scenarios/adaptive-protection/exchange-legacy-auth-block/`.
  Correction to this item's own original framing: `-BlockLegacyAuth*` is an **on-premises-only**
  parameter family (Exchange 2019 CU2+/CU13+), not usable against Exchange Online at all - the
  cloud-relevant mechanism is the `-AllowBasicAuth*` switch family on `New-/Set-AuthenticationPolicy`
  (default-blocked per protocol), which this build uses instead.
- [ ] Once Microsoft's `excludeGuestsOrExternalUsers` nested Users condition shape is confirmed
  against a worked example (the same open item already tracked near the top of this file for
  `conditional-access-insider-risk-block`), also add it to
  `block-legacy-authentication/deploy/New-BlockLegacyAuthenticationPolicy.ps1` - not a new,
  separate uncertainty, just a second consumer of the same unresolved VERIFY.

### Follow-ups discovered while building the Exchange-side legacy authentication block scenario
- [x] Once the exact `Search-UnifiedAuditLog` `RecordType`/`Operations` values for a rejected SMTP
  AUTH (Authenticated SMTP) attempt are grounded, add a dedicated `Export-*` companion script to
  `scenarios/adaptive-protection/exchange-legacy-auth-block/deploy/` - the current scenario
  validates *configuration* (is the gate closed) but has no event-level export for *who actually
  got rejected and how often*, flagged as a Blue Team gap in that scenario's `reviews.md` (finding
  1) and `README.md` §8, which points to `Search-UnifiedAuditLog` mail-flow/connector events and
  the SMTP gateway's own logs as the actual (unscripted) event source in the meantime. -
  **grounded and closed, not built** (see DONE below): dedicated grounding pass against Microsoft
  Learn found no `Search-UnifiedAuditLog` RecordType/Operations pair exists for a rejected
  authentication attempt of any protocol, and confirmed Entra ID sign-in logs can't substitute
  either - this scenario's own blocking gates reject the connection at the pre-authentication step,
  before Entra ID ever sees it. `reviews.md` (Blue Team finding 1 + new follow-up round),
  `README.md` §8/§11/§12, and `design.md` §9 corrected in place with the grounded "no" and the
  realistic substitute (the device/app's own logs or a synthetic canary probe). Re-open only if
  Microsoft ever documents a RecordType/Operations pair or a rejection-specific report.
- [x] Consider a Direct Send / anonymous-relay hardening scenario (mail flow connector
  configuration that accepts unauthenticated relay, a materially different abuse surface from the
  authenticated legacy protocols `exchange-legacy-auth-block` covers) - flagged as a Red Team
  finding in that scenario's `reviews.md` (finding 3): closing SMTP AUTH doesn't reduce the value
  of a misconfigured connector that accepts anonymous relay from an allowed IP range, and a
  determined attacker/legacy integration could be pushed toward that surface instead. No scenario
  in this repo covers Direct Send today - explicitly out of scope for `exchange-legacy-auth-block`
  (`design.md` §7). - **built** (see DONE below) as
  `scenarios/adaptive-protection/direct-send-anonymous-relay-hardening/`.

### Follow-ups discovered while building the Data Map Azure SQL scan-and-classify scenario
- [ ] VERIFY (pilot tenant or the Purview OpenAPI spec, before production use): the exact REST
  request body shapes for the **Data Sources - Create Or Update**, **Triggers - Create Or
  Replace**, and **Scan Result - Run Scan** operations used by
  `scenarios/data-map/scan-azure-sql-and-classify/deploy/New-AzureSqlDataMapScan.ps1`. Their
  canonical Microsoft Learn REST reference pages returned fetch errors in this build environment;
  the shapes used are reconstructed from the confirmed sibling **Scans - Create Or Replace**
  endpoint (direct-fetched, API version `2023-09-01`), the official
  `@azure-rest/purview-scanning` JS SDK type definitions, and the `Az.Purview` PowerShell module's
  parameter signatures - three converging but indirect sources. Flagged inline in that scenario's
  `README.md` §11 and the deploy script's `.NOTES`.
- [x] `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/` - script a **custom, PII-only
  scan rule set** (excluding all system classifications except U.S. Social Security Number and
  Credit Card Number by default) - **built** (see DONE below): the "Scan Rulesets - Create Or
  Replace"/"- Get" REST reference pages were direct-fetched in full this build, closing the VERIFY
  this item was waiting on (the exclusion list itself is derived live from the tenant's Types API
  rather than a hard-coded snapshot - the `data-map-classification-supported-list` page turned out
  to list classifications by name only, with no exact `MICROSOFT.*` identifiers anywhere on it).
- [x] Consider scripting **credential-object creation** (Key Vault-backed, for the
  `AzureSqlDatabaseCredential` scan kind - SQL authentication or service principal) once a
  documented REST endpoint for it is found; deferred from `scan-azure-sql-and-classify` because no
  such endpoint was located during that build (Microsoft's own docs show credential creation only
  via the portal UI). Needed for any organization whose target SQL Server can't use SAMI (e.g. reachable
  only via a self-hosted integration runtime, which doesn't support managed-identity auth) -
  **built** (see DONE below) as `scenarios/data-map/scan-credential-key-vault-backed/`. **The
  precondition this item was waiting on turned out to already be satisfied, and the original
  premise was wrong:** the Purview **Scanning data plane** documents **Credential**
  (`PUT /scan/credentials/{credentialName}`) and **Key Vault Connections**
  (`PUT /scan/azureKeyVaults/{azureKeyVaultName}`) as first-class operation groups at
  `api-version=2023-09-01`, both direct-fetched in full this run via the Microsoft Learn MCP tool.
  The earlier builds' "portal-only" conclusion came partly from over-reading Microsoft's
  disaster-recovery statement that "there's no API to extract credentials" - that is about
  **exporting existing secret material** (true, and by design: a credential object only ever holds
  a *reference*), not about **creating the object**. Both affected scenarios corrected in place
  (`scan-azure-sql-and-classify` README §6/§11 + `design.md` §7;
  `scan-on-premises-sql-server-and-classify` README §3/§11 + its deploy script's `.NOTES`/
  `.PARAMETER`), dated rather than quietly rewritten.
- [x] Sibling Data Map scan scenarios for **Azure SQL Managed Instance**, **Azure Synapse
  Analytics** (dedicated + serverless SQL pools), and **on-premises SQL Server** (via self-hosted
  IR) - each has its own registration/authentication nuances Microsoft documents separately;
  explicitly called out as a non-goal in `scan-azure-sql-and-classify/design.md` §7 - **all three
  built** (see DONE below): `scenarios/data-map/scan-azure-sql-managed-instance-and-classify/`,
  `scenarios/data-map/scan-azure-synapse-and-classify/`, `scenarios/data-map/
  scan-on-premises-sql-server-and-classify/`. This item was left unchecked when those three
  fragments landed; corrected during the `docs/automation-surface.md` §4 Unified Catalog/Data Map
  lineage routing-table fragment's PROGRESS.md pass.
- [x] `scenarios/data-map/scan-azure-sql-and-classify/` also assumes downstream scenarios will
  consume its classification output - once `scenarios/data-estate-insights/
  classification-coverage-report/` (already TODO below) is built, cross-link it back into this
  scenario's §8 "Downstream use" note - **built** (see DONE below): `classification-coverage-report`
  landed some time ago (it already links back to this scenario throughout its own README), but this
  scenario's own §8 note still said "any future Data Estate Insights/classification-coverage
  reporting fragment in this library." Replaced with a direct
  `scenarios/data-estate-insights/classification-coverage-report/` cross-link in
  `scan-azure-sql-and-classify/README.md` §8.

### Follow-ups discovered while building the Key Vault-backed scan credential scenario
- [ ] VERIFY (pilot tenant - the single cheapest, highest-value check in this scenario): the two
  `KeyVaultSecret` discriminator literals `type` and `store.type` in a Purview credential body.
  Microsoft's Credential reference defines `KeyVaultSecret` as
  `{ secretName, secretVersion, store: { referenceName, type }, type }` but types **both** `type`
  fields as an open `string` with no enumerated values, and its **only** worked request example is a
  `BasicAuth` credential carrying `description` alone - **no populated secret reference appears
  anywhere in the Purview documentation set**. Three candidate sources were checked and eliminated
  this build: the `@azure-rest/purview-scanning` SDK types both as `string`; `Az.Purview` ships no
  credential-object cmdlet at all (only *scan* objects); no Learn article shows the JSON.
  `scan-credential-key-vault-backed` defaults to `AzureKeyVaultSecret` / `LinkedServiceReference`,
  derived from Data Factory's identically-shaped `AzureKeyVaultSecretReference` plus Purview's own
  Key Vault Connections worked *response* returning an `id` ending in `/linkedservices/...`
  (converging but indirect). Both ship as **parameters** (`-SecretReferenceType` /
  `-SecretStoreReferenceType`), and `validate/` reports a mismatch as `[WARN]` while printing the
  observed values. **To close: create one credential in the portal, `GET /scan/credentials/{name}`,
  record the two values.** That single read settles it permanently.
- [ ] VERIFY (pilot tenant): whether omitting `secretVersion` in a Purview credential resolves to
  the Key Vault secret's latest version. Microsoft's Purview reference documents the property but
  never states the omitted-version behavior; the Data Factory equivalent is documented as defaulting
  to latest, and Purview's own troubleshooting page says to use "the right secret name **and
  version**" without saying whether the version is optional. `scan-credential-key-vault-backed`
  README §8's rotation guidance (omit the version → rotation needs no Purview change) depends on
  this.
- [ ] VERIFY (pilot tenant): whether the `PurviewSecurityLogs` diagnostic-log category emits an
  event for credential-object create/replace/delete despite not being documented to. Microsoft's
  enumerated Purview audit-event category table covers Collections, Role assignments, Scan rule
  sets, Classification rules, Scans, and Data sources - **credentials and Key Vault connections are
  absent** - and the `Security` category's own description is scoped to role assignments and
  collection create/delete. This leaves the silent-credential-re-point attack in
  `scan-credential-key-vault-backed/README.md` §11 (Red Team finding 1) with no documented Purview
  detective control. Two honest caveats kept this from being asserted as impossible: that category
  table is on a page written for the *classic* governance portal, and it states more categories
  "will be added." If an event does exist, that scenario's §8 monitoring table should recommend it
  over the current scheduled-`validate/` compensating control.
- [x] Consider scripting the remaining five documented credential kinds - `AccountKey`,
  `AmazonARN`, `ConsumerKeyAuth`, `DelegatedAuth`, and `ManagedIdentity` (user-assigned) - as a
  second fragment or an extension. `scan-credential-key-vault-backed` deliberately scopes to the
  three the SQL-family scan kinds in this repo consume. Note these are **not** a parameter tweak:
  `ManagedIdentity`'s `typeProperties` (`principalId`, `resourceId`, `tenantId`) carries **no Key
  Vault reference at all**, and `ConsumerKeyAuth`'s carries *two* secret references
  (`consumerSecret` **and** `password`) - both are structurally different bodies. - **built** (see
  DONE below) as `scenarios/data-map/scan-credential-remaining-kinds/`: one `-CredentialType`-
  dispatched deploy script covering all five kinds, grounded directly against the Scanning-data-
  plane REST reference (fetched live via the Microsoft Learn MCP tool - available this run, contrary
  to this repo's usual `EGRESS_BLOCKED` default) and cross-checked against
  `scan-credential-inventory-report`'s independently-built fingerprint table, which reached
  identical shapes from the read side. Each kind's real-world source pairing confirmed against a
  dedicated Microsoft Learn connector page rather than inferred from the schema alone: `AccountKey`
  → Azure Blob/ADLS Gen1+2/Azure Files/Cosmos DB, `AmazonARN` → Amazon S3 (its *only* documented
  auth method), `ConsumerKeyAuth` → Salesforce (also its only documented method), `DelegatedAuth` →
  Microsoft Fabric/Power BI, `ManagedIdentity` → six source types incl. three this repo already
  scans (Azure SQL DB/MI, Synapse dedicated pools) - a directly actionable future pairing, not
  built here. Reuses the parent scenario's `Remove-PurviewScanCredential.ps1` unmodified for
  deletion (confirmed kind-agnostic). Four-lens review surfaced and fixed two real issues: (1) a
  `-WhatIf -Verbose` dry run could have printed `ConsumerKeyAuth`'s plain-text `consumerKey` to a
  console/log - fixed with a redacted log-body path in `Invoke-PurviewPut`; (2) `AmazonARN`/
  `ManagedIdentity` have **no** Key Vault-side detective backstop at all (unlike the three
  secret-bearing kinds), since they hold no secret to audit - `README.md` §8 now states this
  plainly and recommends a daily inventory-report cadence for tenants relying on either. Corrected
  the parent scenario's now-stale "five credential kinds are out of scope" §11 bullet in place
  (the same Product-Owner-Fail pattern the parent's own review applied to its siblings), with
  cross-links added in both directions plus from `scan-credential-inventory-report`. Two new
  VERIFYs recorded below rather than guessed at.

### Follow-ups discovered while building the scan-credential-remaining-kinds scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether any documented REST endpoint
  returns the Microsoft account ID / external ID pair a Role ARN credential's AWS-side IAM role must
  trust. Microsoft's Amazon S3 connector walkthrough shows both values surfacing only in the
  **portal's** "New credential" pane; `RoleARNCredentialTypeProperties` itself contains only
  `roleARN` (confirmed directly from the Scanning-data-plane reference). Until this is resolved, a
  fully scripted Amazon S3 onboarding still requires at least one portal visit upstream of
  `scenarios/data-map/scan-credential-remaining-kinds/deploy/New-PurviewScanCredentialExtended.ps1`
  - flagged inline in that scenario's `README.md` §3/§11 and `design.md` §4 rather than guessed at.
- [ ] Periodically re-check the GA/preview status of the `ManagedIdentity` (user-assigned) credential
  kind. Microsoft's "Credentials for source authentication" page currently labels it "(preview)";
  the Scanning-data-plane REST reference carries no preview annotation of its own for the same kind.
  `scenarios/data-map/scan-credential-remaining-kinds/README.md` §3/§10/§11 and the deploy script's
  runtime `Write-Warning` all disclose this; re-open only if Microsoft's documentation changes.
- [x] Make `scenarios/data-map/scan-credential-remaining-kinds/validate/
  Test-PurviewScanCredentialExtended.ps1`'s `-CheckKeyVaultSecret` vault-name derivation
  authoritative - **built** (see DONE below): it previously assumed the Purview Key Vault
  **connection** name equals the Azure Key Vault's own name (common, not guaranteed); the parent
  scenario's equivalent check instead `GET`s the connection object first and derives the vault name
  from its `baseUrl`. Fixed by duplicating that same GET-then-derive sequence here via a new
  `Get-KeyVaultNameForConnection` helper (cached per connection name so `ConsumerKeyAuth`'s two
  secret references only trigger one GET each), issued only for the three secret-bearing kinds
  (`AccountKey`/`ConsumerKeyAuth`/`DelegatedAuth`) - `AmazonARN`/`ManagedIdentity` still never call
  it, since neither carries a Key Vault secret. `reviews.md` Blue Team finding 2 and the round-summary
  table updated in place to reflect the resolution.
- [x] `ManagedIdentity` (UAMI) variant of `scan-azure-sql-and-classify` - **built** (see DONE below)
  as `scenarios/data-map/scan-azure-sql-and-classify-managed-identity-credential/`: reconciles the
  base scenario's existing scan from SAMI onto a UAMI credential built via
  `scan-credential-remaining-kinds`. Confirmed the most directly actionable of the four candidate
  follow-ups this item originally listed, per its own reasoning (target scan scenario already
  existed; Microsoft's credential priority order ranks UAMI above the service-principal/SQL-auth
  paths those scenarios document as their non-SAMI fallback).
- [x] `ManagedIdentity` (UAMI) variant of `scan-azure-sql-managed-instance-and-classify` - **built**
  (see DONE below) as `scenarios/data-map/scan-azure-sql-managed-instance-and-classify-managed-
  identity-credential/`: same reconciliation pattern as the Azure SQL Database sibling, ported (not
  copy-pasted) to Managed Instance's own distinct scan `kind`
  (`AzureSqlDatabaseManagedInstanceCredential`) and REST properties shape, both independently
  confirmed via direct fetch. Also corrected two more stale "portal-only credential" claims found in
  `scan-azure-sql-managed-instance-and-classify/README.md` §6/§11 while there (the same correction
  already applied to the Database sibling on 2026-09-16, missed on this sibling until now).
- [x] `ManagedIdentity` (UAMI) variant of `scan-azure-synapse-and-classify` - **built** (see DONE
  below) as `scenarios/data-map/scan-azure-synapse-and-classify-managed-identity-credential/`: the
  third and last sibling named in `scan-credential-remaining-kinds/README.md` §6, closing that
  backlog item completely. Found the strongest direct grounding of the three siblings - a worked
  JSON example on the base scenario's own canonical page explicitly confirms `ManagedIdentity` as a
  valid `credentialType` for the `AzureSynapseWorkspaceCredential` scan `kind`. Also updated the base
  scenario's own stale `resourceTypes` VERIFY and two more stale "portal-only credential" claims
  found in passing.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether the Azure IAM Reader
  role-assignment portal walkthrough ("Select box accepts your Microsoft Purview account name or
  UAMI") - directly confirmed only on the Azure SQL Database page - also appears verbatim on the
  Azure SQL Managed Instance or Azure Synapse workspace pages, or is a documentation-page omission on
  an otherwise-identical Azure RBAC mechanism. Flagged inline in both
  `scan-azure-sql-managed-instance-and-classify-managed-identity-credential/README.md` §3/§5/§11 and
  `scan-azure-synapse-and-classify-managed-identity-credential/README.md` §3/§11 rather than assumed
  identical.
- [ ] **CORRECTION (re-grounded, not built):** A follow-up-to-the-follow-up grounding pass found the
  `-ResourceNames`-style scoping parameter item below was less settled than originally framed. The
  worked JSON example's `resourceTypes.AzureSynapseServerlessSql.resourceNameFilter.resources[]` key
  name does not appear anywhere in the formal `AzureSynapseWorkspaceCredentialScanProperties`
  REST reference's own `resourceTypes` type (`ExpandingResourceScanPropertiesResourceTypes`), whose
  documented keys are a different, generic camelCase per-source-kind set
  (`azureSqlDatabase`/`azureSynapseWorkspace`/etc., used by "expanding" multi-resource scan kinds like
  `AzureResourceGroup`/`AzureSubscription`) with no Synapse-serverless-specific entry. The nested
  *sub-object* shape independently matches the formal `ResourceTypeFilter` type, which is reassuring
  but doesn't resolve the key-name conflict. Likely a shared/reused schema type whose full valid key
  set isn't fully enumerated for every scan kind that references it (a common auto-generated-API-doc
  pattern), but that is an inference, not a confirmation - flagged inline in
  `scan-azure-synapse-and-classify/README.md` §11 as a VERIFY rather than built on an unresolved
  conflict, per `AGENTS.md` §4. Re-open only once confirmed against a pilot tenant or a more specific
  Synapse-only REST reference page.
- [ ] Amazon S3 (`AmazonARN`), Salesforce (`ConsumerKeyAuth`), and Microsoft Fabric/Power BI
  (`DelegatedAuth`) still have no scan scenario of any kind in this library - each would need its own
  new base scan scenario (data source + scan, not just a credential variant of an existing one), a
  bigger fragment than the UAMI wiring above. `AccountKey`'s four source types (Azure Blob Storage,
  ADLS Gen1, ADLS Gen2, Azure Files) are in the same position.
- [ ] **Amazon S3 scan scenario attempted, deliberately not built - genuine REST-schema conflict
  found, not resolved by guessing.** A grounding pass direct-fetched the Scans/Data Sources - Create
  Or Replace REST references for the two candidate scan kinds and found real ambiguity: `AmazonS3` and
  `AmazonAccount` data source `properties` both carry a `roleARN` string field directly, in addition
  to (and separately from) the `credential: CredentialReference` field both `AmazonS3RoleARNScan` and
  `AmazonS3CredentialScan` scan kinds also carry - two different scan kinds, each with both a direct
  `roleARN` property AND a credential reference, and no worked example (portal or REST) found
  anywhere distinguishing when to use which or whether both should be set. The portal-documented flow
  (`register-scan-amazon-s3`) only ever describes creating a Purview credential object with a Role
  ARN and selecting it during scan setup - consistent with `AmazonS3CredentialScan`'s `credential`
  field and this repo's already-built `AmazonARN` credential kind (`scan-credential-remaining-kinds`)
  - but does not explain the data-source-level `roleARN` field or the sibling `AmazonS3RoleARNScan`
  kind at all. Building a deploy script would mean guessing which of four plausible combinations
  (data-source `roleARN` set or not, crossed with which scan kind) is actually correct - against
  `AGENTS.md` §4. Re-open once a worked REST example, Az.Purview module worked example, or pilot
  tenant read-back resolves which fields/kind combination Microsoft's own tooling actually uses.

- [x] Consider a small **credential inventory/drift report** companion (`GET /scan/credentials`,
  paged via `{ count, nextLink, value[] }`) that reconciles a tenant's live credential set against a
  checked-in parameter file - the same shape as `data-estate-insights`'
  `classification-coverage-report`/`sensitivity-label-coverage-report`. Would generalize
  `scan-credential-key-vault-backed/validate/`'s per-credential `-Expected*` assertions into an
  estate-wide control, and is currently the only detective mechanism available for the
  silent-re-point risk above. - **built** (see DONE below) as
  `scenarios/data-map/scan-credential-inventory-report/`: full per-kind fingerprint extraction for
  all eight documented `CredentialType` kinds (not just the three `scan-credential-key-vault-backed`
  creates), a generic kind-agnostic diff engine against a checked-in expected-state JSON file, and a
  `Match`/`Drift`/`Missing`/`NotTracked` status model. `scan-credential-key-vault-backed/README.md`
  §8/§11 updated in place to point at this scenario as the estate-wide version of its own
  single-credential `-Expected*` check. Two Red Team findings surfaced and resolved during this
  build's own four-lens review (see that scenario's `reviews.md`): (1) a wholly new, unauthorized
  credential only ever shows as `NotTracked`, which the drift gate ignores by default - resolved
  with a new, independent `-FailOnUntracked` validate-script switch; (2) the expected-state file's
  own trustworthiness depends on a review process this scenario cannot enforce from inside Purview or
  the script - resolved by documentation (a named prerequisite: a distinct approver for changes to
  that file), not by code, since no code-only fix exists.
- [ ] Once a documented reverse lookup from a credential to the scans that reference it exists (none
  today), replace `scan-credential-key-vault-backed/rollback.md`'s **Stage 0** manual
  enumerate-data-sources-then-scans procedure - and the matching disclosed limitation in
  `Remove-PurviewScanCredential.ps1`'s `.NOTES` and README §11 - with a real consumer check inside
  the removal script.
- [ ] Re-check the Key Vault grant scope question in a future pass: whether Microsoft ever adds
  per-secret scoping for the Purview managed identity's vault access. Today both supported models
  (access-policy Get/List on secrets, and the **Key Vault Secrets User** role) are **vault-wide over
  secrets**, which is why `scan-credential-key-vault-backed` README §3/§5/§11 recommends a
  *dedicated* scan-credential Key Vault (Red Team finding 2). If per-secret scoping appears, that
  recommendation can be softened to a narrower grant instead.
- [x] RESOLVED (2026-09-25, commit `4f041bb`): Cross-cutting: `docs/automation-surface.md`
  surface 4 (Purview data-plane REST) did not mention the Scanning plane's **Credential**, **Key
  Vault Connections**, **Scan Rulesets**, or **Triggers** operation groups, and
  `docs/rbac-model.md` §5 did not state which Data Map collection role is required to create a
  credential. Backported: `automation-surface.md` §4's Data Map row now cites all four operation
  groups with their confirmed REST paths (also fixed a latent inaccuracy - the original row was
  missing the `/scan/` path segment on `/datasources/{name}`). `rbac-model.md` §5 now has a new
  paragraph stating the Data Source Administrator-by-analogy assumption explicitly, flagged
  **VERIFY (pilot tenant)** rather than resolved (the analogy was never independently confirmed),
  plus the confirmed account-wide/no-collection-role fact for Scan Ruleset objects.

### Follow-ups discovered while building the DSPM for AI Copilot sensitive-data-exposure scenario
- [ ] VERIFY (pilot tenant): whether a `{"Type":"Group","Identity":"..."}` `Inclusions` entry in
  the Copilot-location `-Locations` JSON works for `New-DlpCompliancePolicy`/`New-DlpComplianceRule`
  the same way a group inclusion is documented for the *collection*-policy cmdlets
  (`New-/Set-FeatureConfiguration`) - needed before this repo can promise a group-scoped pilot
  rollout of `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` instead of tenant-wide
  `TestWithNotifications` simulation as the only pre-enforcement pilot mechanism. Flagged inline in
  that scenario's `README.md` §11 and `reviews.md` (Red Team).
- [x] `scenarios/dspm-for-ai/copilot-prompt-full-block/` - **built** (see DONE below): the fresh
  grounding pass this item asked for found Microsoft has since published a fuller worked use case
  for the "Prevent Copilot from processing content > Processing prompts" action (Contoso / Canada
  physical addresses / EU debit card numbers example, and a clearer supported-conditions-and-actions
  table), though the feature remains preview and Microsoft still has not published a worked
  PowerShell example combining a CCSI condition with `-RestrictAccess` for this specific action. Built
  as a rule added to the parent scenario's existing policy (`Add-CopilotPromptFullBlockRule.ps1`),
  using the only confirmed `-RestrictAccess` setting/value pair for this location
  (`ExcludeContentProcessing`/`Block`, otherwise documented only for the label-exclusion condition) as
  a reasoned, explicitly-disclosed inference rather than an invented one - see that scenario's
  `design.md` §5 for the full reasoning and `README.md` §5/§11 for the carried-forward VERIFY. Parent
  scenario's `README.md`, `design.md`, and deploy script `.NOTES` cross-linked to the new scenario in
  place of the old "not scripted" callouts.
- [ ] VERIFY (pilot tenant, or a future Microsoft-published PowerShell worked example): whether
  `-RestrictAccess @(@{setting='ExcludeContentProcessing';value='Block'})` is in fact what the portal
  emits for a `ContentContainsSensitiveInformation`-conditioned rule using the "Processing prompts"
  full-block action on the Microsoft 365 Copilot location, as opposed to a different, undocumented
  setting string specific to that condition/action combination. Flagged inline in
  `copilot-prompt-full-block/README.md` §5/§11, `design.md` §5, the deploy script's `.NOTES`, and
  checked as `[WARN]` (not `[FAIL]`) by `validate/Test-CopilotPromptFullBlockRule.ps1`.
- [x] `scenarios/dspm-for-ai/copilot-external-email-block/` - script the fourth documented
  Copilot-location action, "Block external email from being processed" (preview; `Email is received
  from > External users` condition), explicitly left out of scope by
  `copilot-prompt-full-block/design.md` §7 and `copilot-sensitive-data-exposure/design.md` §7 to keep
  those fragments focused on the problems they were named for - **built** (see DONE below).
- [x] `scenarios/dspm-for-ai/third-party-ai-site-adaptive-block/` - the Adaptive-Protection-driven,
  risk-based DLP policies for **third-party** generative AI sites accessed via a browser
  (`DSPM for AI - Block sensitive info from AI sites`, `DSPM for AI - Block elevated risk users
  from submitting prompts to AI apps in Microsoft Edge`) - **investigated, not built** (see DONE
  below): this item's own premise ("a natural extension of `dynamic-risk-dlp-enforcement`'s
  existing pattern") did not survive a dedicated grounding pass. Neither one-click policy has a
  Microsoft-published PowerShell/Graph worked example as of this pass; `copilot-sensitive-data-
  exposure/design.md` §7's non-goal note (which originally pointed here) corrected in place.
  Re-open once Microsoft publishes a PowerShell/Graph cmdlet for either the "Inline web traffic" /
  Adaptive app scopes location, or for referencing a Sensitive Service Domain Group inside
  `New-DlpComplianceRule -EndpointDlpRestrictions`.
- [x] Consider updating `docs/licensing-matrix.md` to add the DLP-for-Copilot licensing-tier split
  (label-exclusion rule requires E5-tier; prompt-safeguard/web-grounding rule is available at all
  Copilot licensing tiers) as its own row/footnote - **built** (see DONE below).

### Follow-ups discovered while building the Copilot External Email Block scenario
- [ ] VERIFY (pilot tenant, or a future Microsoft-published PowerShell worked example): whether the
  Microsoft 365 Copilot and Copilot Chat DLP-location honors `-FromScope NotInOrganization` as a
  rule condition at all - the parameter and its two allowed values are independently confirmed to
  exist in `New-DlpComplianceRule`'s shared syntax, and its semantics match the Copilot-location
  page's own prose description of "Email is received from > External users," but no Microsoft-
  published example combines `-FromScope` with the `CopilotExperiences` enforcement plane for any
  location. Flagged inline in `copilot-external-email-block/README.md` §5/§11 and `design.md` §4,
  and checked as `[WARN]` (not `[FAIL]`) by `validate/Test-CopilotExternalEmailBlockRule.ps1`.
- [ ] VERIFY (pilot tenant): whether `PATCH`-style reconciliation of this rule via `Set-
  DlpComplianceRule -Force` (as `copilot-external-email-block/deploy/
  Add-CopilotExternalEmailBlockRule.ps1` performs) correctly updates an already-live `FromScope`
  condition, or silently no-ops it - the same class of replace-vs-merge uncertainty this repo has
  already flagged for other PATCH-style reconciliation paths (e.g. the Intune device-control
  scenarios' `omaSettings`/`payload` PATCH). Not independently tested during this build.
- [x] Consider a companion Blue Team-flagged control: an accepted-domains hygiene check script that
  cross-references `Get-AcceptedDomain` against a known-partner-domains allowlist and flags any
  legitimate partner domain missing accepted-domain status (a false-positive-exclusion risk for
  `copilot-external-email-block`) or, in the other direction, any newly-added accepted domain that
  doesn't match a known-partner-domains allowlist (a potential silent-bypass risk if an attacker or
  a misconfiguration adds an external-controlled domain as accepted) - flagged as a Red Team finding
  in `copilot-external-email-block/reviews.md` - **built** (see DONE below) as
  `scenarios/dlp/accepted-domains-hygiene-check/`, a standalone scenario rather than nested under
  `dspm-for-ai`, since the risk applies to every `FromScope`-consuming rule in a tenant, not just this
  one. Checks both directions plus a `DomainType`-level trust-boundary model (Authoritative/
  InternalRelay = in-organization, ExternalRelay = not) and a baseline/drift log for
  Added/Removed/DomainTypeChanged/DefaultChanged/MatchSubDomainsChanged detection since the previous
  run. Cross-linked back into `copilot-external-email-block/README.md` §3/§11 and `reviews.md`.

### Follow-ups discovered while building the Accepted-Domains Hygiene Check scenario
- [x] Backport the `ExternalRelay`-is-on-premises-only correction into
  `copilot-external-email-block/design.md` §4 - **built** (see DONE below): `design.md` §4 now states
  explicitly that `ExternalRelay` is on-premises-Exchange-only (Microsoft's `Set-AcceptedDomain`
  reference, re-cited), that a pure Exchange Online tenant can only reach `Authoritative`/
  `InternalRelay` (both in-organization), and that the external-relay clause matters only for a hybrid
  tenant whose on-premises domains this scenario's tooling can't see. `reviews.md` carries a matching
  correction addendum, doc-only per `AGENTS.md` §6, no new four-lens round run.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/GitHub-samples pass): whether `Set-
  AcceptedDomain` is independently confirmed to appear under `Search-UnifiedAuditLog`'s `RecordType
  ExchangeAdmin` / `Operations 'Set-AcceptedDomain'` - this build found the general documented
  default (Exchange admin cmdlet executions are logged this way) but no worked example naming this
  specific cmdlet. `accepted-domains-hygiene-check/deploy/Export-AcceptedDomainsHygieneReport.ps1`'s
  `-IncludeAuditAttribution` switch is flagged `VERIFY` in its own `.NOTES` and `README.md` §11
  rather than assumed correct.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether Microsoft Entra ID's `Add
  verified domain`/`Remove verified domain`/`Add unverified domain`/`Remove unverified domain`
  `DirectoryManagement`-category audit activities (confirmed to exist by name in Microsoft's
  audit-activity reference) surface through `Search-UnifiedAuditLog -RecordType
  AzureActiveDirectory` with an `Operations` value matching those names verbatim. Resolving this
  would let `accepted-domains-hygiene-check` attribute a `DomainAddedSincePreviousRun`/
  `DomainRemovedSincePreviousRun` finding to a specific admin action and timestamp - currently a
  disclosed, unbuilt gap (`design.md` §5, `README.md` §11) because Exchange Online has no
  `New-`/`Remove-AcceptedDomain` cmdlet to audit for the domain-addition/removal event itself.
- [x] Consider an on-premises Exchange companion check for `accepted-domains-hygiene-check`, for a
  hybrid Exchange Online/on-premises tenant whose on-premises accepted domains (including any
  genuine `ExternalRelay` domain) are invisible to the current Exchange-Online-only script - **built**
  (see DONE below) as `scenarios/dlp/accepted-domains-hygiene-check-on-premises/`: reuses the parent's
  `KnownDomains.json` and mirrors its detection categories against an on-premises Exchange remote
  PowerShell session, plus a new `CrossEnvironmentMismatch` category (optional `-CloudBaselinePath`,
  a file read only - never a live combined session, since `Connect-ExchangeOnline` and the
  on-premises `Import-PSSession` pattern both export a colliding `Get-AcceptedDomain` proxy cmdlet).
  Also closes part of the parent's own disclosed attribution gap: `New-`/`Remove-AcceptedDomain` are
  real, on-premises-auditable cmdlets (`Search-AdminAuditLog`), unlike Exchange Online which has
  neither cmdlet to audit in the first place.

### Follow-ups discovered while building the on-premises Accepted-Domains Hygiene Check companion
- [ ] VERIFY (pilot on-premises Exchange server, or a future Microsoft Learn pass): the exact
  *default* value of `-AdminAuditLogCmdlets` (which cmdlets a fresh on-premises install audits without
  explicit configuration) - this build confirmed `-AdminAuditLogEnabled` defaults to `$true` and
  `-AdminAuditLogAgeLimit` defaults to 90 days from `Set-AdminAuditLogConfig`'s own reference page, but
  that page's fetched content did not state a default for `-AdminAuditLogCmdlets` itself (only that
  `*` audits everything). `accepted-domains-hygiene-check-on-premises/deploy/
  Export-OnPremisesAcceptedDomainsHygieneReport.ps1`'s `-IncludeAuditAttribution` switch tells the
  organization to confirm coverage via `Get-AdminAuditLogConfig` rather than assuming the common `*`-default
  belief is correct - see that scenario's `design.md` §2 and `README.md` §11.
- [x] Re-verify the parent `accepted-domains-hygiene-check/deploy/KnownDomains.sample.json`'s
  `hybrid.contoso.com` entry (`expectedDomainType: InternalRelay`) against a primary, authoritative
  Microsoft Learn conceptual page - **re-grounded and closed, sample confirmed correct, not changed**
  (see DONE below): a `WebSearch` pass (direct `WebFetch` to `learn.microsoft.com` still blocked by
  this session's egress policy) found three authoritative Microsoft Learn conceptual pages - not the
  secondary community/Q&A guidance the original build relied on - showing `InternalRelay` is exactly
  the documented shared-namespace hybrid case, and that `Authoritative`+Directory-Based-Edge-Blocking
  is a domain's later, post-full-migration state, not a contradiction of an active coexistence
  domain. `accepted-domains-hygiene-check-on-premises/design.md` §4, `README.md` §11/§12, and
  `reviews.md` (correction addendum) updated in place; `KnownDomains.sample.json`'s `owner` comment
  annotated with the confirmation rather than left silent.
- [x] Cross-reference on-premises Exchange RBAC (role groups like `Organization Management`, which
  share a name but not an identity with their Exchange Online counterparts) into `docs/rbac-model.md`
  - **built** (see DONE below): new §13 ("Exchange Server on-premises RBAC - a ninth system"),
  renumbering the old §13 "How scenarios should cite RBAC" to §14.
- [x] Consider extending `CrossEnvironmentMismatch` (`accepted-domains-hygiene-check-on-premises/
  deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1`) to also reconcile `MatchSubDomains`/
  `Default` flags across environments, not just `DomainType` - explicitly deferred as a non-goal in
  that scenario's `design.md` §9 pending a concrete organization need, matching this repo's incremental-
  scoping discipline - **built** (see DONE below): two new sibling finding categories,
  `CrossEnvironmentMatchSubDomainsMismatch`/`CrossEnvironmentDefaultMismatch`, not additional rows
  under the existing category name, after direct functional testing caught a real drift-log
  `(RunId, Category, DomainName)` row-collision bug in a single-category first draft.

### Follow-ups discovered while building the Unified Catalog business-glossary scenario
- [x] `scenarios/unified-catalog/link-glossary-terms-to-data-products/` - **superseded by**
  `scenarios/unified-catalog/manage-data-products/` (see DONE below), which creates a data
  product, wraps a `scan-azure-sql-and-classify`-scanned asset as a Unified Catalog data asset,
  and links both that asset and this scenario's `Customer`/`Customer ID` terms to it via the
  `Data Products - Create Relationship` operation.
- [x] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row (currently
  "evolving surface - VERIFY exact endpoint names per release") with the confirmed exact
  operation groups/paths grounded in `curate-business-glossary` (`Terms` and `Business Domain`
  operation groups, `POST/PUT/DELETE/GET /datagovernance/catalog/terms(|/{id})`,
  `.../businessdomains(|/{id})`, `.../terms/{id}/relationships`, API version
  `2026-03-20-preview`) - closes that cross-cutting doc's open VERIFY for this one surface -
  **built** (see DONE below).
- [ ] VERIFY (pilot tenant, before production reliance): the Unified Catalog `Terms - Query`
  `nameKeyword` filter's exact match semantics (substring/prefix/tokenized) are undocumented;
  `curate-business-glossary`'s idempotency design always re-checks for an exact client-side name
  match rather than trusting the filter, but a domain with more than one page of name-matching
  terms could in principle need pagination the deploy script doesn't yet implement - flagged
  inline in `README.md` §11 and the deploy script's `.NOTES`.
- [ ] VERIFY (pilot tenant): the Unified Catalog `Business Domain - Create`/`Update` REST
  reference marks `systemData`/`thumbnail`/`domains`/`managedAttributes` as required request-body
  fields in a way that contradicts Microsoft's own worked examples and ordinary REST semantics;
  `curate-business-glossary`'s deploy script sends a minimal practical body instead and flags this
  discrepancy rather than fabricating placeholder values for those fields - confirm the minimal
  body is accepted (or find the correct minimal shape) against a pilot tenant.
- [x] Consider a `scenarios/unified-catalog/governance-domain-hierarchy/` (or fold into a future
  Unified Catalog pass) covering multi-domain parent/child governance hierarchies, custom
  attribute groups, and data estate mappings to Data Map collections - explicitly out of scope in
  `curate-business-glossary/design.md` §6-7, which models a single standalone domain. - **built**
  (see DONE below): a `Corporate → Sales (→ Sales - EMEA) / Marketing` tree, idempotent by
  `(name, parentId)` matching (Business Domain has no name-filter Query op, unlike Terms - one full
  paginated `Enumerate` pass instead), business-concept attribute *values* set per domain (creating
  the attribute *definitions* themselves confirmed portal-only), and an opt-in data estate mapping
  whose exact `relatedCollections`/`parentCollection.refName` semantics are flagged VERIFY rather
  than guessed (Microsoft's own worked examples for that one nested object use meaningless
  placeholder strings, unlike the rest of the same request body). Four-lens review caught and fixed
  a real full-replace-PUT bug (`isRestricted` wasn't seeded from the live object like
  `managedAttributes`/`domains` were, so it would have been silently cleared on a re-run) and added
  a missing **Governance Domain Owner** row to `docs/rbac-model.md` §5.

### Follow-ups discovered while building the Unified Catalog manage-data-products scenario
- [ ] VERIFY (pilot tenant or the Swagger spec linked from the Unified Catalog API overview page):
  the exact `Data Products - Create Relationship` request body per `entityType` - the REST
  reference's only worked example (`entityType=CRITICALDATACOLUMN`) includes an `assetId` field
  this scenario's `DATAASSET`/`TERM` calls omit. Flagged inline in `manage-data-products/README.md`
  §11, `design.md` §3, and `deploy/New-DataProduct.ps1`'s `.NOTES` rather than resolved by
  guessing. Closing this would also let `scenarios/unified-catalog/link-glossary-terms-to-data-
  products/`-style critical-data-element/column linking be added with confidence.
- [ ] VERIFY (pilot tenant): whether the Unified Catalog `Data Products - Update` REST operation
  enforces the portal's "must configure a data access policy before Publish" business rule
  server-side, or whether that is a portal-UX-only guardrail this scenario's direct `PUT` call
  bypasses - flagged as a Red Team/CISO finding in `manage-data-products/reviews.md` and as a
  gating prerequisite in `README.md` §3, with a `Write-Warning` as the interim compensating
  control. No REST operation for configuring a data product access policy itself was found during
  this build's grounding pass (`design.md` §5) - that stays a portal-only manual step.
- [x] `scenarios/unified-catalog/manage-critical-data-elements/` - script the `Critical Data
  Elements` operation group (create a CDE, map asset columns to it, the auto-linking-to-data-
  products behavior Microsoft documents) - explicitly out of scope in `manage-data-products/
  design.md` §6, which links only `DATAASSET` and `TERM` entity types - **built** (see DONE
  below).
- [x] `scenarios/unified-catalog/manage-okrs/` - script the `Okr`/`Key Result` operation groups and
  link them to data products, closing the last `EntityCategory` gap `manage-data-products/design.md`
  §6 leaves open (OKR linking) - **built** (see DONE below): full README/design/deploy/validate/
  rollback/reviews. Grounding pass found the Okr operation group has **no relationship operation
  of its own** (confirmed by fetching all thirteen of its operations) - the link is instead
  created from the **Data Products** side, whose `Create/List/Delete Relationship` operations'
  shared `EntityCategory` enum documents `OBJECTIVE`/`KEYRESULT` as valid values (fetched
  directly). Also corrects a pre-existing `docs/automation-surface.md` §4 inaccuracy (an informal
  "OKR" paraphrase where the real enum values are `OBJECTIVE`/`KEYRESULT`) and adds a dedicated
  Okr operation-group routing-table row.
- [x] Extend `docs/automation-surface.md` §4's Unified Catalog REST routing-table row with the
  confirmed `Data Products` and `Data Assets` operation groups/paths grounded in
  `manage-data-products` (`POST/PUT/DELETE/GET /datagovernance/catalog/dataProducts(|/{id})`,
  `.../dataProducts/{id}/relationships`, `.../dataAssets(|/{id})`, `.../dataAssets/query`, API
  version `2026-03-20-preview`) - same pattern `curate-business-glossary`'s and
  `end-to-end-lineage-validation`'s own automation-surface.md follow-ups already established of
  tracking doc extensions separately rather than bundling them into a scenario fragment -
  **built** (see DONE below).
- [ ] Once `scenarios/compliance-manager/` or a future access-governance scenario needs it,
  consider scripting **data product access policy** configuration if Microsoft publishes a REST
  surface for it - confirmed not to exist as of this build (`manage-data-products/design.md` §5);
  the REST API's own `Policies` operation group is a different feature (the RBAC authorization-
  policy engine), not the consumer-facing access-request workflow.

### Follow-ups discovered while building the Unified Catalog manage-critical-data-elements scenario
- [ ] VERIFY (pilot tenant): whether `entityType=DATACOLUMN` (the value this scenario's scripts
  send, matching the formally-documented `EntityCategory` enum) or `entityType=CRITICALDATACOLUMN`
  (the value every worked example on the Critical Data Elements Create/List/Delete Relationship
  reference pages actually uses) is the real, accepted value for mapping a column to a critical
  data element. This is a genuine, three-page-consistent discrepancy in Microsoft's own REST
  reference, not a gap this build failed to research - see `manage-critical-data-elements/
  design.md` §6 and `README.md` §11. Resolving this would let this scenario and
  `docs/automation-surface.md`'s new routing-table row drop the hedge and state one confirmed
  value.
- [x] `scenarios/unified-catalog/manage-critical-data-elements-related-terms/` - script the
  "Manage related terms" action Microsoft's critical data elements portal exposes - **built** (see
  DONE below): links an existing CDE to one or more existing glossary terms via
  `entityType=TERM` on the same **Create Relationship** operation the sibling scenario already
  uses for `DATACOLUMN`. Two new, genuine open questions surfaced and disclosed rather than
  guessed: (1) whether linking a *published* term is accepted, given Microsoft's docs state a
  Draft-state requirement only for the reciprocal term-side flow, not this CDE-side one; (2)
  whether Data Steward alone (without Data Product Owner) is really sufficient for this specific
  action, given the source page's silence on this one procedure vs. its explicit dual-role
  requirement for CDE creation. Both flagged as VERIFY in the new scenario's `README.md` §11 and
  `design.md` §4-5 rather than resolved by guessing.
- [ ] VERIFY (pilot tenant): whether Microsoft's critical-data-element **access policies** (the
  portal's **Manage policies** action on a CDE's details page) have any REST surface distinct from
  the RBAC-authorization-policy `Policies` operation group - `manage-data-products/design.md` §5
  already confirmed the identical two-concepts trap for data products; this build's grounding pass
  did not re-run that same check specifically for critical data elements (deferred as a non-goal,
  `manage-critical-data-elements/design.md` §7) and should before this feature is presented as
  fully API-manageable end to end.
- [ ] VERIFY (pilot tenant): whether the Critical Data Elements `Query` `nameKeyword` filter's
  exact match semantics (substring/prefix/tokenized) match the same open question already tracked
  for `curate-business-glossary`'s Query Terms and `manage-data-products`' Query Data Products - no
  new evidence either way was found for this third instance of the same undocumented filter.
- [ ] Once a documented REST endpoint exists for **Critical Data Elements - Get Facets** and
  **Count** (both listed in the operation group but not fetched/grounded in this build, since
  neither was needed for create/map/observe), consider a small companion reporting scenario (or
  fold into `data-estate-insights`) that surfaces CDE coverage the same way
  `classification-coverage-report`/`sensitivity-label-coverage-report` do for classifications and
  labels.

### Follow-ups discovered while building the Data Lineage end-to-end-lineage-validation scenario
- [x] `scenarios/data-lineage/custom-process-lineage/` (or fold into a future Data Lineage
  hardening pass) - script the richer DataSet -> Process -> DataSet lineage shape (a custom
  Process-typed entity representing the transform itself, not just a direct dataset-to-dataset
  edge), once a REST-documented body for creating a *custom* Process entity type is independently
  grounded - **built** (see DONE below): a fresh grounding pass on this run found and directly
  confirmed the previously-missing body in Microsoft's own "Create and get lineage relationships
  using the REST API" tutorial (Example 1: create a Process entity via Entity - Bulk Create Or
  Update, then `dataset_process_inputs`/`process_dataset_outputs` relationships; "Create New Custom
  Types": the custom-Process-type body). Composable with, not a replacement for, this scenario's
  own `direct_lineage_dataset_dataset` edge - see the new scenario's `design.md` §6.
- [ ] VERIFY (pilot tenant): the exact qualifiedName string format Purview assigns to an
  `azure_sql_table` asset (e.g. whether it follows an `mssql://...` scheme) - not found during this
  build's grounding pass; `end-to-end-lineage-validation`'s definition file currently requires the
  operator to copy the value from the portal rather than having either script construct it. Closing
  this would let a future scenario auto-resolve qualifiedNames instead of requiring manual copy.
- [ ] VERIFY (pilot tenant): whether `Relationship - Create` rejects, no-ops, or duplicates a
  second POST of an identical relationship - this build's grounding pass confirmed the operation's
  request/response shape directly from Microsoft's REST reference but not this specific behavior;
  `end-to-end-lineage-validation`'s own existence-check design makes its idempotency independent of
  the answer, but a production integration bypassing that check should confirm it first.
- [x] Extend `docs/automation-surface.md` §4's routing table with a row for Data Map lineage
  (`entity/bulk`, `relationship`, `lineage/uniqueAttribute/type/{typeName}` - surface 4,
  `datamap/api/atlas/v2/...`, API version `2023-09-01`) - not added in this build to keep the
  fragment scoped to one scenario; `scan-azure-sql-and-classify`'s and
  `curate-business-glossary`'s own automation-surface.md follow-ups set the same precedent of
  tracking doc extensions separately rather than bundling them into a scenario fragment -
  **built** (see DONE below).

### Follow-ups discovered while building the Data Quality rules-and-scorecards scenario
- [x] `scenarios/data-quality/connection-and-scorecard-alerts/` (or fold into a future Data Quality
  hardening pass) - script the DQ data-source connection (`Create Data Source`) and score-threshold
  alerts (`Get Alerts`/`Update Alert`), both deferred from `rules-and-scorecards` because
  `Create Data Source`'s `computeId` field has no documented provisioning endpoint this build could
  find, and the Alerts operations weren't independently fetched/grounded in this build - **built**
  (see DONE below): re-fetching Create/Get/Update Data Source directly found `computeId` present
  only in the (VNet-enabled) Create example and absent from the non-VNet Get/Update examples,
  narrowing the blocker to the managed-VNet path only; the non-VNet path is fully scripted with no
  unconfirmed fields. Alerts (`Get Alert`/`Get Alerts`/`Update Alert`/`Update Alert Status`/
  `Delete Alert`) were independently fetched and grounded this run.

### Follow-ups discovered while building the Data Quality connection-and-scorecard-alerts scenario
- [ ] VERIFY (pilot tenant): whether `computeId` is truly optional (not merely absent from the one
  confirmed non-VNet worked example) for a non-VNet `Create Data Source` call - Microsoft's request-
  body property table doesn't mark any field required/optional explicitly, unlike its URI-parameter
  table, which does. `connection-and-scorecard-alerts/README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): Create Data Source's create-vs-replace
  semantics against an already-existing `dataSourceId`, and Update Data Source's PATCH partial-
  merge-vs-full-replace semantics. Doesn't affect `New-DataQualityConnection.ps1`'s idempotency (it
  always `GET`s first and picks PUT/PATCH accordingly), but a direct caller of the raw API should
  confirm both. Same open-question class as `rules-and-scorecards`' own Create Rules PUT-semantics
  VERIFY.
- [ ] VERIFY (pilot tenant): whether Data Quality Alert `receivers` accepts a raw SMTP address/UPN
  string in addition to a Microsoft Entra object ID - every worked example in Microsoft's Alert REST
  reference pages shows only GUIDs, but the portal's own conceptual doc calls the field a "recipient
  alias" without stating the resolved type. `connection-and-scorecard-alerts/README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): `Update Alert`'s PUT semantics against
  an already-existing `alertId` - its reference page states only "Creates an alert," with no
  explicit create-vs-replace statement. Doesn't affect this scenario's idempotency (the ID is always
  caller-chosen), but a direct caller should confirm.
- [x] Ground `Search-UnifiedAuditLog` `RecordType`/`Operations` coverage (if any) for Data Quality
  connection/alert `Create`/`Update`/`Delete` actions, then add a dedicated audit-trail export
  script to `connection-and-scorecard-alerts/deploy/` - **grounded and closed, not built** (see
  DONE below): the dedicated grounding pass this item asked for found no such coverage exists to
  ground. Three independent findings: (1) Microsoft's "Audit log activities" reference has no
  Unified Catalog/Data Quality/governance-domain section - its only Purview record type,
  `PurviewDataMapOperation`, is the classic Data Map API's own; (2) the classic Data Map's
  data-plane Audit - Query REST API covers Atlas-model Data Map entities, and a Data Quality
  connection is a separate Unified Catalog object, not a Data Map Atlas entity; (3) an independent
  third-party analysis (March 2026) states plainly that comprehensive Unified Catalog audit
  logging "does not exist today." `connection-and-scorecard-alerts/README.md` §11, `design.md`'s
  Non-goals, and `reviews.md`'s Blue Team finding 1 corrected in place instead of a script being
  built against unconfirmed/non-existent endpoints. This build's environment blocked a direct
  Microsoft Learn fetch (same limitation logged under "Blocked / needs user" on 2026-09-09); the
  three findings rest on `WebSearch` snippets, not verbatim fetches - re-verify with a direct fetch
  or the Microsoft Learn MCP tool when either is available, and re-open this item if Microsoft ever
  ships a `RecordType`/`Operations` pair or dedicated audit endpoint for these objects.
- [x] Consider a companion example in `connection-and-scorecard-alerts/deploy/alerts/` demonstrating
  the product-level (not just asset-level) `AlertScope` this build confirmed is supported (omit
  `dataAssetId`) but didn't use in the shipped example - `README.md` §11 - **built** (see DONE
  below): new `deploy/alerts/customer-360-product-score-alert.json` (one alert, `dataProductId`
  only). No script change needed - `New-DataQualityAlert.ps1`'s scope-construction logic already
  built this shape whenever `dataAssetId` is absent; live-exercised in this build (PowerShell 7.4.6)
  to confirm the exact resulting REST body has a `scopes[0]` with only `dataProduct`, no `dataAsset`
  key at all. Re-fetched `Update Alert`'s own REST reference directly this round: its worked example
  still only shows the combined `dataProduct`+`dataAsset` (asset-level) shape, so the product-only
  shape remains inferred-from-schema-and-corroborated, not pilot-tenant-confirmed - stated that way
  in the new file's own header comment, `README.md` §11, and `design.md`, not upgraded to a firm
  claim just because a file now ships it.
- [ ] Once the Schedule object's recurring-trigger-type VERIFY immediately below is closed, revisit
  whether a recurring scan schedule changes any of this scenario's alert-cadence assumptions
  (currently alerts fire per completed scan, whatever triggers it).

- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the Data Quality Schedule object's
  trigger `type` values beyond the confirmed `RunOnce` shape - a `Recurrence` type with frequency/
  interval fields almost certainly exists (the portal's own Scheduled scans wizard supports daily/
  weekly/monthly recurrence) but wasn't found in this build's REST reference fetch. Needed before
  `rules-and-scorecards` (or a follow-up) can script an ongoing scan cadence instead of a one-time
  `RunOnce` schedule.
- [ ] VERIFY (pilot tenant): the exact mechanism by which a `TypeMatch` (Data type match) rule's
  `typeProperties` specifies the target type a column is checked against - the confirmed REST
  `TypeProperties` schema has no field name for it despite Microsoft's conceptual documentation
  describing the behavior. Flagged inline in `rules-and-scorecards/deploy/
  New-DataQualityRulesAndSchedule.ps1`'s `.NOTES` and `README.md` §11.
- [x] A Unified Catalog **data products** scenario (create/manage a data product, add data assets to
  it) is a shared, still-unbuilt dependency both `curate-business-glossary`'s and
  `rules-and-scorecards`' non-goals point to - **built** as
  `scenarios/unified-catalog/manage-data-products/` (see DONE below). `rules-and-scorecards`'s own
  `Create Data Source`/`computeId`-provisioning gap (above) was a separate item, since resolved for
  the non-VNet path by `scenarios/data-quality/connection-and-scorecard-alerts/` (see DONE below).

### Follow-ups discovered while building the Data Estate Insights classification-coverage-report scenario
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` - extends
  `classification-coverage-report`'s exact pattern (paginated `Discovery - Query`, client-side tally,
  replace-by-`RunId` trend log) to the `label` field on the same `SearchResultValue` schema - **built**
  (see DONE below).
- [x] `scenarios/data-estate-insights/glossary-curation-coverage-report/` - the native "Glossary
  insights"/"Data stewardship" dashboards (term-to-asset attachment rates, active-user counts) use
  different underlying data than `Discovery - Query`'s per-asset `classification`/`label` fields and
  would need a different REST primitive (likely the Unified Catalog Terms operation group this
  repo's `scenarios/unified-catalog/curate-business-glossary/` already grounds) - explicitly scoped
  out of `classification-coverage-report/design.md` §7 as a different data source, not a copy-paste
  extension of this fragment's pattern - **built** (see DONE below): confirms the Terms operation
  group (`List`, `List Related Entities`) is the right primitive for term-to-asset attachment and
  status/completeness KPIs, but also found the classic glossary report targets a *different* term
  model (classic, Atlas-based) from the one this repo's own `curate-business-glossary` writes to
  (current Unified Catalog Terms API) - the two are not interchangeable, and the new scenario's
  KPIs are the Unified-Catalog-model equivalent, not a literal reproduction of the classic report.
  Active-user/search-telemetry counts remain out of scope: no documented REST operation on any
  Unified Catalog operation group exposes that data - confirmed, not merely assumed, by this build.
- [ ] VERIFY (pilot tenant, before production reliance): `classification-coverage-report/deploy/
  Export-ClassificationCoverageReport.ps1`'s `Get-FullBreakdown` warns (but does not fail) when the
  number of records actually paged via `continuationToken` doesn't match the response's own
  `@search.count` - Microsoft's Discovery - Query REST reference doesn't document whether this
  mismatch is expected (e.g. due to near-real-time index changes mid-page-through) or a sign of a
  client-side pagination bug. Confirm against a pilot tenant with a large, stable (non-changing)
  asset population before treating a persistent mismatch as benign.
- [ ] Note for a future Data Lineage follow-up: this build's `Discovery_Query_Collection` worked
  example response (Microsoft's own REST reference page for Discovery - Query) shows a real
  `azure_sql_table` `qualifiedName` value -
  `mssql://exampleserver.database.windows.net/examplesqldb/examplepath/exampledata1` - which
  directly bears on the open VERIFY in `scenarios/data-lineage/end-to-end-lineage-validation/
  README.md` §11 ("the exact qualifiedName string format Purview assigns to an azure_sql_table
  asset"). Not applied retroactively to that already-DONE fragment in this build (out of scope for
  this turn), but the next pass on that scenario (or a dedicated Data Map/Data Lineage grounding
  fragment) should confirm this `mssql://` scheme against a pilot tenant and, if confirmed, update
  that scenario's README/design.md to close the VERIFY instead of requiring manual portal copy.

### Follow-ups discovered while building the Data Estate Insights glossary-curation-coverage-report scenario
- [ ] VERIFY (pilot tenant): whether `Global Catalog Reader`/`Local Catalog Reader` can see
  `EXPIRED`-status terms (documented only as "read published artifacts"), or whether `EXPIRED` is
  treated as no-longer-published and hidden the same way `DRAFT` is. `-PublishedOnly` mode currently
  treats both Draft and Expired counts as unmeasurable or unset for a reader-only credential;
  confirming Expired visibility could let a future revision report it without Data Steward.
  `glossary-curation-coverage-report/README.md` §11 and `design.md` §2 goal 2.
- [ ] VERIFY (pilot tenant): the actual server-side maximum for `Terms - List`'s `top` query
  parameter - Microsoft's reference documents the parameter but not a ceiling. This scenario
  defaults `-PageSize` to a conservative 100 and always follows `nextLink`, so an unconfirmed cap
  cannot cause silent truncation, but confirming the real maximum would let a future revision tune
  the default for fewer round-trips at scale. `glossary-curation-coverage-report/deploy/
  Export-GlossaryCurationCoverageReport.ps1`'s `.NOTES`.
- [ ] Once Microsoft enumerates valid `Terms - Get Facets` `facets[].name` values beyond the single
  worked `owner` example, revisit whether a `status`-facet (or similar) request could replace this
  scenario's per-page client-side status tally with a single aggregate call - see `design.md` §6.
- [ ] Consider a companion reconciliation script (or an extension to this scenario's own deploy
  script) that cross-references a tenant still on the **classic, Atlas-based Data Catalog glossary**
  against Unified Catalog Terms, to help an organization mid-migration understand which of their two
  glossaries this report - and which the native classic glossary report - actually covers. Not built
  here because no Microsoft-documented migration-status API was located during this build; flagged
  as a real, disclosed gap in `README.md` §11 rather than assumed away.
- [ ] Once a Data Products or Critical Data Elements scenario in this repo needs "which terms are
  linked to which data products" (as opposed to this scenario's "which terms are linked to any data
  asset"), extend the same `List Related Entities` pattern with `entityType=DATAPRODUCT` - the
  `EntityCategory` enum already documents that value; not built here to keep this fragment scoped to
  the glossary-health question it was tracked for.

### Follow-ups discovered while building the Compliance Manager ISO 27001 assessment scenario
- [x] `scenarios/compliance-manager/entra-privileged-role-monitoring/` - **built** (see DONE
  below): scripts monitoring of Entra directory role-assignment changes for Global Administrator/
  Compliance Administrator/Compliance Data Administrator/Security Administrator via Microsoft
  Graph's Entra directory audit log (`Get-MgAuditLogDirectoryAudit` / `auditLogs/directoryAudits`),
  closing the Red Team finding in `assess-against-iso27001/reviews.md` and cross-linked back into
  that scenario's `README.md` §8/§11 and `design.md` §4.
- [ ] VERIFY (pilot tenant, before production reliance): the internal JSON shape of the `AuditData`
  payload for `ComplianceManagerRolesChange`/`ComplianceManagerAutomationLevelChange`/
  `ComplianceManagerAutomationChange` audit records - not published in Microsoft's
  `audit-log-activities` reference. `assess-against-iso27001/deploy/
  Export-ComplianceManagerAuditTrail.ps1`'s `Get-BestEffortTargetObjectId` function assumes an
  `ObjectId` property *might* exist inside that JSON (best-effort, non-blocking) but does not rely
  on it for correctness - the script's real de-duplication key hashes the full raw payload instead.
  Confirming the actual shape would let a future revision surface richer, grounded columns (e.g.
  which specific improvement action or role was changed) instead of the current opaque JSON blob.
- [x] **ISO/IEC 27001:2022 premium template is now confirmed to exist** - found while grounding the
  `pci-dss-assessment` sibling scenario: Compliance Manager's current `compliance-manager-
  regulations-list` premium-regulations catalog lists both "ISO/IEC 27001:2013" and "ISO/IEC
  27001:2022" as separate templates (2022 is the edition organizations now actually certify
  against). `assess-against-iso27001/README.md` §11's original VERIFY ("only :2013 was found") is
  now out of date. Update that scenario's `README.md`/`design.md` to acknowledge the :2022 template
  exists and either switch the recommended template to it or explicitly justify staying on :2013 -
  **closed** (see DONE below): re-fetched `compliance-manager-regulations-list` directly (confirming
  both templates are still live), then independently grounded the industry-wide IAF MD 26
  :2013→:2022 certification transition (initial/recertification audits to :2013 stopped April 30,
  2024; all :2013 certificates had to expire or be reissued against :2022 by October 31, 2025 - both
  now in the past) and confirmed Microsoft's own M365/O365 ISO 27001 certificate is itself now the
  "2022 Certificate (2024-2027)" cycle. `assess-against-iso27001`'s `README.md`, `design.md` (new
  §5b), `reviews.md` (MPO finding 2 resolution updated, correction addendum added), `rollback.md`,
  its deploy manifest, and its validate script were all switched from :2013 to **ISO/IEC 27001:2022**
  as the recommended/scripted template, closing the VERIFY with a decision rather than re-deferring
  it. Stale `27001:2013` cross-references in the two sibling scenarios that name this assessment
  (`pci-dss-assessment`'s group-pairing docs/manifest, `entra-privileged-role-monitoring`'s
  compliance-mapping citations) were corrected in the same pass - the latter also needed the Annex A
  clause number itself fixed (2013's separate "A.9 Access Control" domain doesn't carry over to
  2022's consolidated 4-theme/93-control structure; access control now sits under Organizational
  Controls, A.5), not just a 2013→2022 text substitution, since ISO's 2022 revision renumbered and
  merged Annex A rather than just re-dating it.
- [x] `scenarios/compliance-manager/pci-dss-assessment/` (already tracked above, under the DLP
  PCI Teams follow-ups) - **built** (see DONE below), and cross-linked back into
  `assess-against-iso27001`'s manifest as a sibling assessment in the same `Security & Compliance
  Assessments` group. That manifest's group note was also corrected in place: Microsoft's group
  behavior only shares **nontechnical** improvement actions within a group - technical actions
  already sync tenant-wide regardless of group - a distinction the original note didn't draw.
- [ ] Once Compliance Manager's **Export actions** Excel file has been inspected against a real
  tenant, ground the "Action Update" tab's exact column schema and revisit the non-goal recorded in
  `assess-against-iso27001/design.md` §7 - a schema-accurate generator script would be a genuine,
  higher-value addition to this scenario that this build deliberately declined to fabricate.

### Follow-ups discovered while building the Entra Privileged Role Monitoring scenario
- [x] Extend (or add a companion script to) `entra-privileged-role-monitoring/deploy/
  Export-EntraPrivilegedRoleAuditTrail.ps1` to close its own disclosed Red Team gap: a role
  assigned to an Entra ID P1/P2 **role-assignable group** grants access via a `GroupManagement`
  "Add member to group" audit event, not a `RoleManagement` "Add member to role" event - invisible
  to the current script - **built** (see DONE below) as a companion script,
  `deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1`, in the same scenario folder. Two
  phases: (1) enumerate role-assignable groups (`Get-MgGroup -Filter "isAssignableToRole eq
  true"`, confirmed to work without `ConsistencyLevel`/`$count` advanced-query headers) cross-
  referenced against which of the four monitored roles each currently holds
  (`Get-MgRoleManagementDirectoryRoleAssignment -Filter "roleDefinitionId eq '<id>'"`), then (2)
  monitor `GroupManagement`-category membership events (`Add member to group`/`Remove member from
  group`, confirmed activity names) for exactly that discovered group set, matching by the
  `Group`-typed `targetResources` entry's `id` - a stronger match key than the sibling script's own
  `displayName`-only matching, confirmed via a Microsoft worked `Get-EntraAuditDirectoryLog`
  example. `design.md` §4b/§10, `README.md`, `rollback.md`, and `reviews.md` (round 2, four-lens)
  all updated. Two new residual gaps disclosed rather than silently accepted - see the two new
  VERIFY/follow-up items below.
- [x] Ground the exact `targetResources` audit-log shape for the **bulk import group members**
  activity - **partially closed, not fully resolved by guessing** (see DONE below): a direct fetch
  of Microsoft's `reference-audit-activities.md` docs source (learn.microsoft.com itself returns
  `EGRESS_BLOCKED` in this build environment) confirmed `"Bulk import group members - finished
  (bulk)"` and `"Bulk remove group members - finished (bulk)"` as real, distinct
  `GroupManagement`-category activity names, so both are now in
  `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s `$monitoredActivities` list. The source page
  does **not** document these two activities' `targetResources` shape, and no Microsoft worked
  example was found confirming it - that half remains an open VERIFY (see immediately below), left
  unresolved rather than guessed at (`AGENTS.md` §4). `entra-privileged-role-monitoring/README.md`
  §11, `design.md`, and `reviews.md` round 3 updated.
- [ ] VERIFY (pilot tenant, via a throwaway bulk add/remove on a non-privileged role-assignable
  group): whether a `"Bulk import group members - finished (bulk)"`/`"Bulk remove group members -
  finished (bulk)"` audit record actually carries a `Group`-typed `targetResources` entry (this
  script's match key) at all, and if so how many `User`-typed entries it carries (one per affected
  member, or some other shape). `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s
  `Get-GroupTargetFromTargetResources` fails soft (skips the record) if the assumed shape doesn't
  hold, so a bulk-added privileged-group member could still go undetected until this is confirmed -
  see the deploy script's `.NOTES`, `README.md` §11, and `validate/
  Test-RoleAssignableGroupMembershipAuditTrail.ps1`'s new manual-checklist item.
- [ ] VERIFY (pilot tenant): whether a `Get-MgAuditLogDirectoryAudit`-specific (not just
  `Get-EntraAuditDirectoryLog`-specific) worked example exists for combining `activityDisplayName
  eq` with two `targetResources/any(...)` lambda clauses in one server-side `$filter` - if
  confirmed, both `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s group-match narrowing and
  the sibling script's own `Role`-typed narrowing could move from client-side to server-side,
  reducing the amount of data pulled per run on a high-churn tenant.
  `entra-privileged-role-monitoring/design.md` §10.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether the "Add member to role
  (permanent)" activity name Microsoft's own "Security operations for privileged accounts"
  out-of-PIM detection guidance cites (tagged `Service = PIM`) is the same underlying event as the
  plain "Add member to role" (Core Directory service) `Export-EntraPrivilegedRoleAuditTrail.ps1`
  currently filters on, or a genuinely distinct event this script's filter would miss. Flagged
  inline in `entra-privileged-role-monitoring/README.md` §11, `design.md` §4a, and the deploy
  script's `.NOTES` rather than resolved by guessing (`AGENTS.md` §4).
- [ ] Once the item above is resolved, revisit whether `$monitoredActivities` in
  `Export-EntraPrivilegedRoleAuditTrail.ps1` needs the `(permanent)`-suffixed activity name added,
  or whether it's confirmed to be a duplicate label for an event already covered.

### Follow-ups discovered while building the Communication Compliance harassment-and-code-of-conduct scenario
- [x] `scenarios/communication-compliance/financial-regulatory-supervision/` - **built** (see DONE
  below): the FINRA/SEC-oriented "Regulatory compliance" classifier family (Corporate sabotage,
  Customer complaints, Gifts & entertainment, Money laundering, [Workplace/Regulatory] collusion,
  Stock manipulation, Unauthorized disclosure), scoped to the firm's FINRA-registered-representative
  population rather than "All users" - a deliberate departure from this scenario's own all-users
  scoping, justified in the new fragment's `design.md` §3.
- [x] Consider a `scenarios/insider-risk/` or `scenarios/adaptive-protection/` follow-up wiring the
  documented Communication Compliance → Insider Risk Management integration (the auto-created
  "Insider risk trigger" policy using the Threat/Harassment/Discrimination classifiers) - **already
  covered, not a separate fragment** (checked during the 2026-09-15 session): `scenarios/
  insider-risk/security-policy-violations-by-risky-users/README.md`/`design.md` (built earlier, see
  DONE) already document this exact integration mechanism in full depth - the auto-created "Insider
  risk trigger"/"Detect inappropriate text" dedicated policy, Threat/Harassment/Discrimination
  classifiers, 5+ messages/24h in-scope threshold, up to 48h latency, automatic IRM Investigators
  reviewer assignment - as an alternate/combined triggering event for that template. The underlying
  CC→IRM mechanism this item asked to "wire up" is the same regardless of which IRM template
  triggers it, so no separate fragment is needed for the generic integration itself. (A
  template-specific gap - e.g. the distinct "Data leaks by risky users" IRM template, not yet built
  in this repo at all - would be its own future fragment; not what this item asked for.)
- [x] `scenarios/communication-compliance/copilot-interaction-detection/` - the "Detect Microsoft
  365 Copilot and Microsoft 365 Copilot Chat interactions" policy template (Prompt Shields/
  Protected material classifiers) - **built** (see DONE below): deployed as a template-based policy
  (not custom, unlike the parent scenario - the template's fixed defaults already match this
  scenario's target), with a reused, adapted `Export-CopilotInteractionAuditTrail.ps1` audit-trail
  script (same 3-query `Search-UnifiedAuditLog` shape as the parent, plus a client-side
  `-PolicyNameFilter` and a best-effort `CopilotContext` column). The preview LLM-based
  content-safety classifiers (Hate/Sexual/Violence/Self-harm, Teams/Viva Engage/Copilot-only) remain
  a separate, not-yet-built follow-up - tracked immediately below.
- [x] The preview LLM-based content-safety classifiers (Hate/Sexual/Violence/Self-harm,
  Teams/Viva Engage/Copilot-only, via the built-in "Detect inappropriate content" template or as
  conditions on a custom policy) - explicitly out of scope for both
  `harassment-and-code-of-conduct` (needs Exchange, which these classifiers don't cover) and
  `copilot-interaction-detection` (a distinct classifier family from Prompt Shields/Protected
  material - `copilot-interaction-detection/design.md` §8). A candidate for its own
  Teams/Viva-Engage/Copilot-specific fragment. - **built** (see DONE below) as
  `scenarios/communication-compliance/teams-viva-engage-content-safety/`: deployed via the built-in
  "Detect inappropriate content" template (Teams + Viva Engage locations, the template's fixed
  location list - adding Copilot as a third location is documented as an optional, undeployed edit,
  not the default), with a deliberate operational emphasis on the Self-harm classifier (the one risk
  category no other scenario in this repo detects) via a documented duty-of-care escalation runbook,
  since Communication Compliance itself has no capability to route a Self-harm match differently
  from a Hate/Sexual/Violence match.
### Follow-ups discovered while building the Data leaks by risky users scenario
- [ ] VERIFY (live policy-creation workflow, at deploy time): whether the optional cloud storage/
  cloud service indicator category (Box, Dropbox, Google Drive, Amazon S3, Azure) is actually
  offered when the **Data leaks by risky users** template is selected. Microsoft's per-template
  description text names "cloud indicators" explicitly for `Data theft by departing users` and the
  base `Data leaks` template, but not, in the same descriptive paragraph, for this template - while
  the general cloud-apps configuration article makes no template-specific restriction either way.
  Flagged inline in `data-leaks-by-risky-users/README.md` §5 Step 6/§6/§11 and `design.md` §2 goal
  5/§6 rather than resolved by guessing.
- [x] `scenarios/insider-risk/data-leaks/` (base template) - **built** (see DONE below): a
  general-purpose DLP-policy-as-trigger scenario (Exchange Online/SharePoint Online/OneDrive for
  Business `High` severity alerts), distinct from every "risky/priority users" variant this repo
  already covers, and the "no trigger-count gate" compensating control
  `data-leaks-by-risky-users/README.md` §8/§11 repeatedly cross-references. New contribution:
  `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1` (read-only readiness check for an arbitrary,
  operator-chosen parent DLP policy). Follow-up VERIFY items discovered during this build are
  tracked immediately below.
- [x] `scenarios/insider-risk/data-leaks-by-priority-users/` - **built** (see DONE below): the
  third and last member of the `Data leaks…` template family. Distinct population mechanism
  (priority user groups, required for this template) combined with the base template's own
  two-trigger-option shape (DLP-policy match or exfiltration activity) - a materially different
  shape from the `security-policy-violations-by-priority-users` sibling's fixed, single-trigger
  template. Reused three existing scripts from two different siblings unmodified; wrote zero new
  `deploy/` scripts, only a scenario-specific `validate/` script.

### Follow-ups discovered while building the Data leaks (base template) scenario
- [x] VERIFY (portal or a direct Microsoft Learn fetch): the base `Data leaks` template's own
  actively-scored-user cap - **resolved during the `data-leaks-by-priority-users` build's direct
  Microsoft Learn MCP grounding pass**: the Limits in Insider Risk Management table gives `Data
  leaks` its own row at **15,000** (distinct from `Data leaks by priority users` at 1,000 and
  `Data leaks by risky users` at 7,500) -
  <https://learn.microsoft.com/purview/insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template>.
  Not yet propagated into `data-leaks/README.md` §3/§6/§10/§11 or `design.md` §2 goal 7, or into
  either script's `-MaxUsers` default - tracked as a new follow-up immediately below rather than
  edited directly in this fragment (`AGENTS.md` §6 one-fragment-per-turn discipline).
- [ ] VERIFY (pilot tenant): whether a parent DLP policy left in `TestWithNotifications`/
  `TestWithoutNotifications` mode still generates the High-severity alerts the "DLP alerts" IRM
  indicator consumes, or whether `Mode` must be `Enable`. Found during this fragment's own
  four-lens review (`data-leaks/reviews.md`, Red Team/Blue Team findings) - not stated either way
  by Microsoft in this build's WebSearch-only grounding. `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1` WARNs (not FAILs) on `Mode -ne 'Enable'` rather than
  guessing; `data-leaks/README.md` §5 Step 2/§11 and `design.md` §2 goal 6 flag this explicitly.
- [x] VERIFY (portal, at deploy time): whether a DLP policy that mixes a supported workload
  (Exchange/SharePoint/OneDrive) with an unsupported one (e.g. Teams) on the SAME policy still has
  its supported-workload rules' High-severity alerts processed correctly by the IRM indicator -
  **resolved** (see DONE below): confirmed via a direct Microsoft Learn fetch of "Configure policy
  indicators in Insider Risk Management" §Supported DLP workloads, which states verbatim "If your
  DLP policy spans multiple workloads (for example, Exchange + Endpoint), only the alerts from the
  supported workloads... are processed." `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`'s WARN for
  this combination is now informational (confirmed-safe), not an open question.
- [ ] VERIFY (portal or a direct Microsoft Learn fetch): whether the base `Data leaks` template's
  two triggering-event options ("User matches a DLP policy" and "User performs an exfiltration
  activity") can be enabled simultaneously on one policy, the way the risky/priority-users
  family's HR-connector/Communication-Compliance triggers have an explicit documented AND/OR
  prerequisite. `data-leaks/design.md` §6 discloses this as unresolved rather than assuming
  symmetry with that sibling.
- [x] Now that the base `Data leaks` template's max-users cap is confirmed (above), consider
  building a second worked example for the "User performs an exfiltration activity" triggering
  event - `data-leaks/design.md` §3/§7 deliberately scoped this fragment to the DLP-policy trigger
  only, documenting the exfiltration-activity path as a configuration reference without a full
  end-to-end implementation. `data-leaks-by-priority-users` inherited and repeated the same scope
  decision rather than resolving it. - **built** (see DONE below) as
  `scenarios/insider-risk/data-leaks-exfiltration-activity-trigger/`: full worked example for the
  same base `Data leaks` template's alternative trigger, grounded via a direct Microsoft Learn
  fetch that also surfaced a previously-undocumented distinction in this library - the
  trigger-indicator threshold (brings a user into scope) and the policy/scoring-indicator threshold
  (scores an already-in-scope user) are two separate decisions in the same policy-creation
  workflow, not one. New follow-ups this build discovered are tracked immediately below.
- [x] Propagate the confirmed 15,000-user cap (above) into `data-leaks/README.md` §3/§6/§10/§11 and
  `design.md` §2 goal 7, and give both scripts' `-MaxUsers` parameters a default of 15000 instead
  of the current no-default VERIFY posture - **done** (see DONE below).
- [x] Add the newly-confirmed Microsoft 365 Copilot entry to `data-leaks/README.md` §6/§11's
  DLP-alerts-indicator unsupported-workload list (currently: Endpoint DLP, Teams, on-premises
  scanner, Power BI, third-party app locations) - `data-leaks-by-priority-users/README.md` §6's own
  list, grounded via a direct Microsoft Learn fetch during that build, additionally confirms
  Microsoft 365 Copilot as excluded - **done** (see DONE below). Also added a new, narrower
  best-effort `EnforcementPlanes`-based Copilot-scoping detection check to `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1`, itself carrying a new VERIFY (below).
- [ ] VERIFY (pilot tenant, at deploy time): whether `Get-DlpCompliancePolicy`'s returned object
  exposes `EnforcementPlanes` as a readable property with the same values `New-`/
  `Set-DlpCompliancePolicy` accept for it on write - this fragment's grounding confirmed
  `EnforcementPlanes` as a write parameter (Microsoft's own worked example:
  `-EnforcementPlanes @('CopilotExperiences')`) but found no dedicated `Get-DlpCompliancePolicy`
  reference page confirming its exact shape on read. `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1`'s new Copilot-scoping check (step 2a) WARNs rather than
  FAILs for this reason - flagged inline in the script's `.NOTES` and `data-leaks/README.md` §11.

### Follow-ups discovered while building the Data leaks exfiltration-activity-trigger scenario
- [ ] VERIFY (portal): the specific numeric default threshold values behind "Use default thresholds
  (Recommended)" for each built-in trigger/scoring indicator - Microsoft's own documentation gives
  only one fully worked *custom*-threshold example (SharePoint downloads, 10+/20+/30+ events per
  day for low/medium/high) and states it's illustrative, not a universal default.
  `data-leaks-exfiltration-activity-trigger/README.md` §6/§11 and the deploy manifest flag this
  rather than guessing a number.
- [x] Re-open and re-check `data-leaks/design.md` §6 and `README.md` §6/§11's own combinability
  VERIFY (whether the DLP-policy trigger and the exfiltration-activity trigger can be enabled on
  one policy simultaneously) against this fragment's own stronger - but still not conclusive -
  direct-fetch finding: the "Get started" page's Step 6 phrases the two options as alternative "if
  you select X... if you select Y..." branches - **applied** (see DONE below): `data-leaks/
  design.md` §6 and `README.md` §11 now cross-link the sibling's stronger single-select signal
  in place of the original weaker "no equivalent explicit statement found" framing, still
  disclosed as an open VERIFY rather than resolved (Microsoft never publishes an explicit
  "cannot combine" statement either way).
- [ ] Once Microsoft documents a Graph/PowerShell read API for a policy's configured trigger
  indicators, trigger threshold mode, or scoring indicator threshold mode, add an automated check
  to `data-leaks-exfiltration-activity-trigger/validate/
  Test-DataLeaksExfiltrationActivityTriggerSetup.ps1` in place of the current manual checklist
  items for those two independent decisions.
- [x] Consider a companion scenario or script using the **Insider Risk Indicators (preview)**
  connector to bring a non-Microsoft-workload detection (e.g. a third-party DLP or CASB alert) in
  as a custom trigger for this same base `Data leaks` template - explicitly out of scope for this
  fragment (`design.md` §7); a materially different building block (a new data connector) from
  either existing worked example (DLP-policy trigger, built-in exfiltration-activity trigger) -
  **built** (see DONE below) as `scenarios/insider-risk/data-leaks-custom-indicator-trigger/`:
  the third documented trigger mechanism for this template, worked end to end using Microsoft's
  own Salesforce+Dropbox multi-indicator example, with a new upload script
  (`deploy/Send-InsiderRiskIndicatorRecord.ps1`) that fails closed on two documented silent-
  failure modes (duplicate UPN+timestamp silent-drop; source-column value mismatch) and reuses
  the HR-connector sibling's app-registration scripts unmodified after independently confirming
  (direct GitHub fetch of the actual ingestion sample script) the underlying OAuth/webhook
  mechanics are identical. New follow-ups from this build are filed immediately below.

### Follow-ups discovered while building the Data leaks custom-indicator (third-party-connector) trigger scenario
- [ ] VERIFY (portal): whether custom indicators can actually be added to `Data leaks by priority
  users` and/or `Data leaks by risky users` (not just the base `Data leaks` template this fragment
  scoped itself to) - Microsoft's own wording ("any *Data theft* or *Data leaks* policies") is not
  precise enough to confirm either direction. `data-leaks-custom-indicator-trigger/design.md` §2
  goal 7/`README.md` §11 flag this rather than guessing. If confirmed, extend this scenario's
  pattern to those sibling templates as a new fragment rather than editing this one.
- [ ] VERIFY (portal): whether Source-column value matching for the Insider Risk Indicators
  connector is case-sensitive - `data-leaks-custom-indicator-trigger/deploy/
  Send-InsiderRiskIndicatorRecord.ps1` assumes case-sensitive matching (the stricter, fail-safer
  assumption) but Microsoft's own documentation doesn't state either way.
- [ ] VERIFY (pilot tenant): re-ingestion/de-duplication behavior for an unchanged CSV re-uploaded
  on a subsequent scheduled run of `data-leaks-custom-indicator-trigger/deploy/
  Send-InsiderRiskIndicatorRecord.ps1` - the same open question already tracked for the
  HR-connector sibling's own webhook, now also open for this connector.
- [ ] VERIFY (pilot tenant): end-to-end pipeline latency (third-party detection → CSV export →
  upload → sync → scoring → alert) for `data-leaks-custom-indicator-trigger/` - not independently
  measured in this build; no specific figure is asserted in `README.md` §7/§11 pending this.
- [ ] Consider a Power Automate-based upload trigger for
  `data-leaks-custom-indicator-trigger/` (Microsoft's own optional Step 7 in
  `import-insider-risk-indicators`, triggered on new-file-in-OneDrive/SharePoint) as an alternative
  to the scheduled-script pattern this fragment reused from the HR-connector sibling - explicitly
  deferred as a non-goal in `design.md` §7.
- [ ] Consider whether the partial-chunk-upload-failure behavior this build disclosed for
  `data-leaks-custom-indicator-trigger/deploy/Send-InsiderRiskIndicatorRecord.ps1` (README.md §11 -
  no all-or-nothing transaction, no automatic resume, relies on the duplicate-detection rule to
  make a full re-run safe) also applies to `../departing-employee-data-theft/deploy/
  Send-HrTerminationRecord.ps1`, which shares the same sequential-chunk-upload structure but never
  had this consequence stated explicitly in its own docs - a documentation-only backport if
  confirmed, not a code change.

### Follow-ups discovered while building the Data leaks by priority users scenario
- [x] Correct `security-policy-violations-by-priority-users/README.md` §10's claim that its
  1,000-actively-scored-user cap "is shared with the base template as well" - **built** (see DONE
  below): re-verified with a direct Microsoft Learn fetch (this fragment had fetch access; the
  original build did not) of `insider-risk-management-policy-templates#policy-template-limits`,
  confirming Microsoft's own text - "These maximum limits apply to users across all policies using
  a given policy template" - and that the Limits table lists each template as its own row. The cap
  is corrected in `README.md` §4 (diagram)/§6/§10/§11 and `design.md` §2 goal 3/§3/§4 (diagram) to
  state it as its own, independently-tracked pool, **not** shared with the base template despite
  the identical number (1,000). `reviews.md`'s Microsoft Product Owner finding 3 (which had
  endorsed the now-corrected claim) and its Addendum record the correction rather than silently
  rewriting the original review.
- [x] Add the newly-confirmed **"Add or edit priority user groups"** step name and the
  **"User is a member of a priority user group"** risk score booster to
  `security-policy-violations-by-priority-users/README.md` §5 Step 5 and §6 - **investigated, built
  differently than originally scoped** (see DONE below): this item's own premise did not survive a
  direct Microsoft Learn fetch of the Step 6 workflow guide during this fragment. Microsoft's text
  states the "Add or edit priority user groups" option "appears only if you choose the *Data leaks
  by priority users* template" - the opposite of "applies identically" to this sibling template, not
  a confirmation of it. Rather than propagate the incorrect generalization, `README.md` §5 Step 3
  and §6 were sharpened with the verbatim Microsoft quote as a *more specific* open VERIFY (this
  template's own "Users and groups" control name is unconfirmed, not assumed to match the sibling's
  confirmed name). Likewise, the risk score booster is documented generically by Microsoft (not
  scoped to one template), but the same Step 6 guide ties booster availability to selecting "at
  least one Office or Device indicator" - a condition this template's sole indicator category
  (Microsoft Defender for Endpoint indicators (preview), a third, separately-documented category)
  doesn't obviously satisfy. `README.md` §5 Step 5 and §6 flag this as a new, unresolved VERIFY
  rather than asserting the booster applies automatically. New references 13-14 added to
  `README.md` §12.
- [ ] VERIFY (live policy-creation workflow, at deploy time): the actual control name/label shown
  on `security-policy-violations-by-priority-users`'s own "Users and groups" page for assigning a
  priority user group - Microsoft's "Get started" guide names "Add or edit priority user groups"
  only for the `Data leaks by priority users` sibling, and does not name an equivalent control for
  this template. `README.md` §5 Step 3 and §6 flag this rather than assuming the sibling's label
  carries over.
- [ ] VERIFY (live policy-creation workflow, at deploy time): whether the "Risk score boosters"
  section - specifically "User is a member of a priority user group" - is offered at all for a
  `security-policy-violations-by-priority-users` policy, whose only selectable indicator category
  is Microsoft Defender for Endpoint indicators (preview). Microsoft's "Get started" guide ties
  Risk score booster availability to selecting "at least one Office or Device indicator," neither
  of which this template's indicator category is. `README.md` §5 Step 5 and §6 flag this as open
  rather than assuming the priority-group scoring boost (§6) is automatically active.
- [ ] VERIFY (pilot tenant): what happens when a priority user group larger than 1,000 members is
  assigned to a policy built from the `Data leaks by priority users` template specifically - not
  documented either way by Microsoft. `data-leaks-by-priority-users/design.md` §3 and `README.md`
  §11 disclose this as open rather than assuming the same (also unconfirmed) behavior as the
  `security-policy-violations-by-priority-users` sibling.
- [ ] VERIFY (live policy-creation workflow, at deploy time): whether the optional cloud storage/
  cloud service indicator category (Box, Dropbox, Google Drive, Amazon S3, Azure) is offered when
  the **Data leaks by priority users** template is selected - Microsoft's per-template description
  text does not name "cloud indicators" for this template the way it does for the base `Data leaks`
  template. `data-leaks-by-priority-users/README.md` §5 Step 5/§6/§11 flag this rather than
  guessing, the same open question `data-leaks-by-risky-users` already carries for itself.
- [ ] Once the base `Data leaks` template's "User performs an exfiltration activity" triggering
  event gets a full worked example (tracked above), consider whether
  `data-leaks-by-priority-users` should get the equivalent - this fragment repeated the base
  template's own scope decision (DLP-policy trigger only) rather than resolving it independently.

### Follow-ups discovered while building the Communication Compliance teams-viva-engage-content-safety scenario
- [x] `scenarios/insider-risk/data-leaks-by-risky-users/` - **built** (see DONE below): the
  distinct **Data leaks by risky users** Insider Risk Management policy template, sharing the
  `security-policy-violations-by-risky-users` sibling's HR-connector/Communication-Compliance
  trigger mechanism but scoring a materially different indicator set (built-in Office exfiltration
  indicators + cumulative exfiltration detection, default-on, plus optional Communication
  Compliance content/generative-AI/cloud indicators) with **no Microsoft Defender for Endpoint
  dependency** - grounded directly against `insider-risk-management-policy-templates`,
  `communication-compliance-policies`, `insider-risk-management-policies`, and
  `insider-risk-management-configure` via the Microsoft Learn MCP tool. Reuses the sibling's
  `Send-HrRiskIndicatorRecord.ps1` (already generalized for both templates), the base template's
  scope-candidate script, and the departing-employee-data-theft sibling's plain (non-MDE-joining)
  alert-export script - no new PowerShell was needed beyond a new policy manifest and validate
  script. One open VERIFY carried into the scenario's own docs rather than guessed: whether the
  optional cloud-indicator category is actually offered for this specific template in the live
  policy-creation workflow (`data-leaks-by-risky-users/README.md` §5 Step 6/§6/§11).
- [x] Companion follow-up scripting/documenting a compensating custom keyword dictionary for
  `teams-viva-engage-content-safety` targeting known short-form crisis/threat phrasing - **built**
  (see DONE below): `deploy/policy/short-form-crisis-threat-phrases.txt`, wired in as an optional
  (`applied: false` by default) `customKeywordDictionaryOption` in the scenario's policy manifest,
  matching `harassment-and-code-of-conduct`'s established evasion-dictionary pattern and content
  discipline.
- [ ] VERIFY (pilot tenant): the exact `AuditData` JSON shape for a `SupervisionRuleMatch` event
  specific to the Hate/Sexual/Violence/Self-harm classifier pairing (needed to confirm or replace
  `teams-viva-engage-content-safety/deploy/Export-ContentSafetyAuditTrail.ps1`'s best-effort
  `ContentSafetyContext`/`SeverityHint` derived columns) - same disclosed-gap pattern as
  `copilot-interaction-detection/README.md` §11's unconfirmed `CopilotContext` parse.
- [ ] VERIFY (portal, at deploy time): whether Microsoft's live `communication-compliance-policies`
  page's two conflicting minimum-word-count figures for the content-safety classifier family
  ("three or more words" vs. "five or more words," both present verbatim on the same current page as
  of this build) have since been reconciled to a single figure -
  `teams-viva-engage-content-safety/README.md` §6/§11 currently documents both rather than guessing.
- [ ] VERIFY (jurisdiction-specific, employment counsel): the applicable duty-of-care/psychosocial-
  hazard obligations for employer self-harm-risk-signal handling that
  `teams-viva-engage-content-safety/README.md` §2 flags as needing confirmation before a
  customer-facing legal claim - same category of gap `harassment-and-code-of-conduct/README.md` §11
  already carries for its own EEOC-guidance currency risk.

- [ ] VERIFY (portal, at deploy time, before a customer-facing deployment): the exact current-UI
  label for the "Harassment"/"Targeted harassment" trainable classifier - Microsoft's own docs use
  both names for what reads as the same classifier across different pages
  (`harassment-and-code-of-conduct/README.md` §11, `design.md` §4). Not resolved by guessing in
  this build per `AGENTS.md` §4.
- [ ] VERIFY (employment counsel, jurisdiction-by-jurisdiction): monitoring-notice/consent
  obligations for the Investigator-role full-content-visibility design in
  `harassment-and-code-of-conduct` - flagged as a gating prerequisite in that scenario's `README.md`
  §3/§11 (CISO lens finding in `reviews.md`) but is a legal determination outside this repo's
  grounding scope, not something this build can resolve.
- [ ] Re-check the EEOC's sub-regulatory harassment-guidance status before any customer-facing use
  of `harassment-and-code-of-conduct`'s regulatory-driver narrative (`README.md` §2/§11) - the 2024
  EEOC Enforcement Guidance on Harassment in the Workplace was rescinded by a 2-1 Commission vote on
  January 23, 2026, mid-way through this build's own grounding pass; the scenario's driver rests on
  the underlying Title VII statute and *Faragher*/*Ellerth* case law instead, but this area is
  actively moving and should be re-verified before every future sale referencing it.

### Follow-ups discovered while building the Communication Compliance copilot-interaction-detection scenario
- [ ] VERIFY: whether this scenario's fixed template location ("Microsoft 365 Copilot and Microsoft
  365 Copilot Chat") also reaches Copilot Studio-built or Microsoft Foundry agent interactions, or
  only the core Microsoft 365 Copilot/Copilot Chat experience - Microsoft's general
  channel-detection overview describes a same-sounding "Microsoft Copilot experiences" location as
  covering Copilot Studio agents too, but no worked example in this build's grounding pass confirmed
  the two phrasings denote the same underlying location. `copilot-interaction-detection/README.md`
  §11 and `design.md` §8 flag this rather than asserting either way.
- [ ] VERIFY (pilot tenant): the exact `AuditData` JSON shape for a `SupervisionRuleMatch` event
  specific to the Prompt Shields/Protected material classifier pairing, to confirm or replace
  `copilot-interaction-detection/deploy/Export-CopilotInteractionAuditTrail.ps1`'s best-effort
  `CopilotContext` derived column (currently a non-blocking, string-match-based guess - see that
  script's `.NOTES` and `README.md` §11).
- [ ] Once `scenarios/insider-risk/` builds a Risky AI usage or Risky Agents policy template
  scenario, wire the documented Communication Compliance → Insider Risk Management generative-AI
  policy-indicators integration (Prompt Shields/Protected material feeding IRM risk scoring) -
  deferred from `copilot-interaction-detection/design.md` §8 as a separate, deliberate opt-in,
  matching the same pattern already deferred for `harassment-and-code-of-conduct`'s own IRM
  integration above.
- [ ] Consider a companion note or short script helper for the documented "add a generative AI app
  as a location for an existing policy" alternative (`copilot-interaction-detection/README.md` §8) -
  currently only documented as a manual portal edit; no script needed today since it's a one-time,
  rarely-repeated configuration change, but revisit if a future scenario needs to audit which
  existing policies have Copilot enabled as a location.
- [ ] VERIFY (jurisdiction-specific, outside this build's grounding scope): confirm which specific
  AI-governance regulatory obligations (EU AI Act deployer duties, sector-specific AI guidance, etc.)
  actually apply before citing `copilot-interaction-detection` as satisfying a named regulatory
  requirement in a customer-facing narrative (`README.md` §2/§11) - the Responsible-AI and IP
  drivers are well-grounded; a specific regulatory citation needs counsel review.

### Follow-ups discovered while building the Audit premium-audit-investigation scenario
- [x] `scenarios/audit/retention-policy-management/` - script **audit log retention policies** (a
  Premium feature: create/manage custom retention durations per record type/user via SCC PowerShell
  `New-/Set-UnifiedAuditLogRetentionPolicy`), the configuration counterpart to this read-only
  investigation scenario - **built** (see DONE below).
- [x] `scenarios/audit/streaming-to-sentinel-or-management-api/` - continuous audit streaming via the
  Office 365 Management Activity API (or a Sentinel connector) for real-time detection, contrasted
  with this on-demand investigation in `audit/premium-audit-investigation/design.md` §7 - **built**
  (see DONE below): two contrasted paths - (A) the native Sentinel `Office365`-kind data connector
  (Bicep IaC, `OfficeActivity` table, free, Exchange/SharePoint/Teams only) and (B) a
  subscribe-and-poll pipeline against the raw Management Activity API (idempotent subscription
  script + a checkpointed, retry-hardened poll/export script) for non-Sentinel SIEMs and the
  `DLP.All`/Entra-audit coverage Path A doesn't carry.
- [ ] VERIFY (pilot tenant): the exact `auditLogQueryStatus` terminal values (the runner polls
  defensively and flags this in `audit/premium-audit-investigation/README.md` §11), and the current
  crucial-events list / operation names for the compromise preset.
- [x] Consider an **incident-response (mutating) companion** scenario - disable account, revoke
  sessions, remove malicious inbox rules - the deliberate response workflow this read-only
  investigation explicitly scopes out (`audit/premium-audit-investigation/design.md` §7) - **built**
  (see DONE below) as `scenarios/audit/compromised-account-incident-response/`: automates Steps 1/2/6
  of Microsoft's own "Respond to a compromised cloud email account" playbook (disable, revoke
  sessions, reset password, clear forwarding, remove Inbox rules incl. hidden), plus a
  delegate-permission (FullAccess/SendAs) cleanup this new scenario adds on top. Pre-removal state is
  backed up to timestamped JSON before any removal. Follow-ups this build discovered are tracked
  immediately below.

### Follow-ups discovered while building the Compromised Account Incident Response scenario
- [ ] VERIFY (your tenant): the exact Exchange Online RBAC role for `Remove-InboxRule`/`Set-Mailbox`/
  `Remove-MailboxPermission`/`Remove-RecipientPermission` - none of these cmdlets' own Microsoft Learn
  reference pages name a specific role, only "you need to be assigned permissions." This scenario's
  `README.md` §3/§11 names **Mail Recipients** (Recipient Management/Organization Management role
  groups) as the documented least-privilege candidate based on that role's general "modify existing
  mail users and mail contacts" description, not a per-cmdlet confirmation, and gives the
  `Get-ManagementRoleEntry "*\<CmdletName>"` command to confirm directly against a tenant.
- [ ] Consider scripting Microsoft's documented Steps 3-5 (MFA-registered-device review, OAuth app
  consent review, admin-role review) once a safe, non-judgment-call automation shape is found for at
  least the *detection* half (e.g., list an account's registered auth methods/app consents/admin
  roles for the investigator to review, without auto-removing any of them) - explicitly deferred as a
  non-goal in `compromised-account-incident-response/design.md` §8 because *deciding* which
  device/app/role is attacker-added is a human judgment call, but a read-only enumeration script
  would still speed up that human review the same way this scenario's own detection-before-backup
  step does for mailbox artifacts.
- [ ] Consider a full-fidelity Inbox-rule backup (`Get-InboxRule -IncludeHidden | Select-Object *`
  instead of the current name/enabled/redirect-forward-only fields) so `rollback.md`'s restoration
  path can recreate a removed rule's complete condition/action set, not just its forwarding behavior -
  explicitly disclosed as a known gap in `compromised-account-incident-response/rollback.md` §4 rather
  than silently accepted; not built this run to keep the fragment scoped to detecting the
  attacker-relevant fields Microsoft's own detection guidance names.
- [ ] Consider an organization-wide mail-flow persistence companion (tenant-wide transport rules,
  inbound connectors) for a compromise that reaches beyond one mailbox - explicitly out of scope for
  `compromised-account-incident-response` (`design.md` §8, `README.md` §11), which points at this
  library's existing connector-hardening scenarios (`dlp/`, `adaptive-protection/`) for that surface
  without building a dedicated cross-reference or companion this run.

### Follow-ups discovered while building the Audit retention-policy-management scenario
- [x] Backport the **Organization Configuration vs. Audit Manager** role distinction into
  `docs/rbac-model.md`'s existing Audit row - **built** (see DONE below).
- [ ] VERIFY (pilot tenant): the retroactive-vs-forward-only behavior of editing a live retention
  policy's `RetentionDuration` - Microsoft's own `audit-log-retention-policies` page states both
  that a change "changes the expiration time of the audit data after updating" and, in the same
  paragraph, that such changes "don't update any previously committed items," without reconciling
  the two. `retention-policy-management/README.md` §11 and `design.md` §6 flag this rather than
  asserting either reading - resolving it would let a future revision give concrete guidance on
  whether shortening a policy is safe to use for cost/noise control without risking early
  expiry of records an organization still needs.
- [ ] VERIFY (pilot tenant): whether passing `$null` to `-RecordTypes`/`-Operations` on
  `Set-UnifiedAuditLogRetentionPolicy` clears a previously-set value, the same way Microsoft's own
  worked example confirms for `-UserIds`. `retention-policy-management/deploy/
  New-AuditRetentionPolicy.ps1` extrapolates the same convention to all three MultiValuedProperty
  parameters by analogy (flagged inline in its `.NOTES` and `README.md` §11) rather than assuming
  it's confirmed.
- [ ] Once Microsoft documents a REST/Graph surface for `UnifiedAuditLogRetentionPolicy` objects
  (none was found during this build's grounding pass - Security & Compliance PowerShell is
  currently the only automation surface), reconsider whether `retention-policy-management` should
  add a Graph-based path alongside the PowerShell one, consistent with how other Purview objects
  in this library are moving toward Graph coverage.

### Re-verification pass on the DLP `removable-usb-device-groups-allowlist` follow-up (endpoint-dlp-usb-block)
- Ran a fresh grounding pass on this open item (below, under "Follow-ups discovered while building
  the Endpoint DLP USB-block scenario") before picking a different fragment for this turn - **still
  blocked**, but with two genuine improvements to record:
  1. **Upgraded, not just re-confirmed:** `endpoint-dlp-usb-block/README.md` §11's existing VERIFY
     for `-EndpointDlpRestrictions` `Setting='RemovableMedia'`/`Value='Block'`/`'Audit'` was
     previously sourced only from a Tech Community blog walkthrough. This build independently
     re-confirmed the exact same `Setting`/`Value` hashtable shape directly from Microsoft's
     **official** `New-DlpComplianceRule` reference page (fetched in full), which also reveals two
     additional valid `-Value` strings beyond Block/Audit: **`Ignore`** and **`Warn`** - `Warn`
     plausibly maps to the portal's "Block with override" option that `endpoint-dlp-usb-block/
     design.md` §6 previously declined to use for exactly this reason (no confirmed enum value).
     Filed below as a task to backport this stronger citation and re-evaluate the `Warn` mapping -
     not done in this turn to keep this fragment scoped to `retention-policy-management` alone.
  2. **Confirmed the tenant-wide group-*creation* cmdlets exist, but their body shape is still
     genuinely undocumented.** `Set-PolicyConfig -DlpRemovableMediaGroups`/`-DlpPrinterGroups`
     (both typed `PswsHashtable`) are real, current parameters - confirmed via the official
     `Set-PolicyConfig` reference page. However, both parameters' description sections are
     Microsoft-side placeholder stubs ("`{{ Fill ... Description }}`") with **no example hashtable
     shape**, confirmed empty even in the raw GitHub Markdown source
     (`MicrosoftDocs/office-docs-powershell/.../Set-PolicyConfig.md`) - ruling out a rendering
     artifact. Separately, the *per-rule* group-reference key inside a `New-DlpComplianceRule`
     `-EndpointDlpRestrictions` entry (the mechanism behind the portal's "Choose different
     removable storage restrictions" per-rule override) has no documented key name anywhere in the
     official `New-DlpComplianceRule` reference either. **This item remains blocked** on the same
     core gap it already carried - Microsoft has not published either shape as of this build.
- [x] Backport the official-source confirmation of `EndpointDlpRestrictions` `Setting`/`Value`
  strings (including the newly-found `Ignore`/`Warn` values) into
  `endpoint-dlp-usb-block/README.md` §11 and `deploy/New-EndpointDlpUsbBlockPolicy.ps1`'s
  `.NOTES`, upgrading the citation from the Tech Community blog to the official
  `New-DlpComplianceRule` reference page, and re-evaluate whether `Warn` should replace `Audit` as
  the IT Data Custodians exception action per `design.md` §6's own stated reasoning - **built**
  (see DONE below): citation upgraded across `README.md` (§6, §11, §12), `design.md` (§6, §7),
  `deploy/New-EndpointDlpUsbBlockPolicy.ps1` (`.NOTES` and a new `-ITExceptionAction` parameter),
  `validate/Test-EndpointDlpUsbBlockPolicy.ps1`, and the reference policy JSON. Re-evaluation
  outcome: `Audit` stays the **default** (no behavior change for an existing deployment), but
  `Warn` is now a documented, one-flag opt-in (`-ITExceptionAction Warn`) for an organization that wants the
  IT Data Custodians path justification-gated instead of silently logged - not a forced switch,
  since the `Warn`-to-portal's-"Block with override" mapping is corroborated, not literally
  confirmed (see the new VERIFY below).
- [ ] VERIFY (pilot tenant, before describing `-ITExceptionAction Warn` to a customer as "Block
  with override" by name): whether the portal's "Block with override" `EndpointDlpRestrictions`
  activity option is in fact the `Warn` enum value. Microsoft's official `New-DlpComplianceRule`/
  `Set-DlpComplianceRule` reference confirms `Warn` exists and groups it with `Block` via a shared
  `-NotifyUser` requirement, but never states the portal-name mapping explicitly - flagged inline
  in `endpoint-dlp-usb-block/README.md` §11 and the deploy script's `.NOTES` rather than asserted.
- [ ] VERIFY (pilot tenant, before relying on `-Force` to switch `endpoint-dlp-usb-block`'s
  `-ITExceptionAction` from `Warn` back to `Audit`): whether `Set-DlpComplianceRule` clears a
  previously-set `NotifyUser`/`NotifyPolicyTipCustomText` value when a later call omits it, or
  leaves it stale on the live rule - undocumented by Microsoft either way. Flagged inline in
  `README.md` §11 and the deploy script's `.PARAMETER Force`/`.NOTES`.
- [ ] Periodically re-check whether Microsoft has filled in the `Set-PolicyConfig`
  `-DlpRemovableMediaGroups`/`-DlpPrinterGroups` reference page's placeholder description sections
  (currently literal `{{ Fill ... Description }}` stub text) or published a worked example - this
  is the blocking gap for `scenarios/dlp/removable-usb-device-groups-allowlist/` (below). Since the
  page itself is an acknowledged stub (not just sparse), it is a reasonable candidate for Microsoft
  to complete in a future documentation pass, unlike a gap where no reference page exists at all.

### Follow-ups discovered while building the DLM retention-labels-financial-records scenario
- [x] `scenarios/data-lifecycle-management/event-based-retention-and-disposition/` - event-based
  retention (`New-ComplianceTag -EventType`), `KeepAndDelete` with disposition review
  (`-ReviewerEmail`, multi-stage), and the disposition workflow - powerful RM features layered on the
  same cmdlets, non-goals of this starter (`design.md` §7). Overlaps the records-management starter.
  - **built** (see DONE below): event type + event-based label (`KeepAndDelete`, two-stage
  `MultiStageReviewProperty`) + publish policy/rule, plus a separate per-employee
  `New-RetentionTriggerEvent.ps1` that fires `New-ComplianceRetentionEvent` scoped to one employee's
  `ComplianceAssetID`.
- [x] `scenarios/data-lifecycle-management/publish-labels-for-manual-application/` - a **publish**
  label policy (`New-RetentionComplianceRule -PublishComplianceTag`) so users can manually apply the
  financial-records label, complementing this scenario's auto-apply. - **built** (see DONE below):
  full README/design/deploy/validate/rollback/reviews. This item's own framing ("complementing...
  auto-apply") turned out to be incomplete - a fresh grounding pass found Microsoft's auto-apply
  retention label policies do **not** support regulatory records at all ("This scenario isn't
  supported for regulatory records... require a published retention label policy"), corroborated by
  "Declare records by using retention labels" and the "Will a label be overridden?" table in "Learn
  about retention policies and retention labels" (auto-apply is "Not applicable" for regulatory
  records). This scenario is therefore the *required*, only-supported distribution mechanism for the
  regulatory-record case, not merely an optional complement. **Correction backported into the sibling**
  `retention-labels-financial-records` in the same build (see its `reviews.md` correction addendum and
  the new DONE entry below): that scenario's sample config now defaults to a plain **record** label
  (`regulatory: false`/`isRecordLabel: true`, renamed `Financial Records - 7yr Record`) for its
  auto-apply path, and its deploy script now creates a regulatory record label if configured but
  **skips** auto-apply policy/rule creation for it (a hard product-constraint guard, not merely a
  warning), pointing to this new scenario instead. `README.md`/`design.md`/`rollback.md`/
  `validate/Test-FinancialRecordsRetention.ps1` in that sibling all updated to match; its README §3
  automation-surface citation ("surface 1" → surface 2) was also corrected as a low-risk side effect of
  already being in the file (the broader repo-wide "surface N" drift sweep below remains separately
  tracked and unresolved).
- [x] `scenarios/data-lifecycle-management/adaptive-scope-retention/` - auto-apply/retention scoped by
  an **adaptive scope** (attribute-driven) instead of static locations, for large/dynamic estates
  (noted as out of scope here). - **built** (see DONE below): full README/design/deploy/validate/
  rollback/reviews, modeling Microsoft's own documented "retain executives' content longer, via the
  Title attribute" adaptive-scope example. Genuine gap disclosed rather than guessed: which of an
  adaptive scope's covered locations a `New-RetentionCompliancePolicy -AdaptiveScopeLocation` policy
  actually applies to isn't exposed as a documented parameter on that cmdlet (no `-ExchangeLocation`/
  `-OneDriveLocation` equivalent in that parameter set) - flagged `VERIFY (pilot tenant)` in
  `README.md` §11 and `design.md` §4 rather than assumed. New follow-ups recorded below.
- [x] Consider **file plan descriptors** (`-FilePlanProperty`: categories, citations, authorities,
  provisions) for a formal records file plan, and bulk label/policy creation via the documented CSV
  script (`bulk-create-publish-labels-using-powershell`) - **already resolved, cross-links added**:
  found that `scenarios/records-management/file-plan-bulk-import/` (built 2026-09-15, commit
  `b17faf9`) already fully covers this exact need - `New-ComplianceTag -FilePlanProperty` plus the
  six `New-FilePlanProperty*` descriptor cmdlets, driven by a versioned CSV schedule for bulk
  multi-class creation - but had never been cross-linked back to this scenario, the same "a new
  folder does not retract an old assertion" gap this repo's reviews keep catching. Corrected in
  place: `retention-labels-financial-records/design.md` §7's stale "out of scope for the starter"
  non-goal bullet now points at the resolving scenario, and `file-plan-bulk-import/README.md` §1
  gained a reciprocal "how it differs from" paragraph. No new scenario needed.

### Follow-ups discovered while building the DLM adaptive-scope-retention scenario
- [ ] VERIFY (pilot tenant): whether a `New-RetentionCompliancePolicy -AdaptiveScopeLocation` policy
  applies to **all** locations the referenced adaptive scope's `LocationType` covers (e.g., for a
  `User`-type scope: Exchange mailboxes, OneDrive, Teams chats, Copilot experiences, Enterprise/Other
  AI apps, Teams call logs) by default, or whether some undocumented mechanism narrows it - no
  `-ExchangeLocation`/`-OneDriveLocation`-equivalent parameter was found on this cmdlet's
  `AdaptiveScopeLocation` parameter set, unlike the portal's own "choose locations" step in the
  adaptive-policy creation flow. `adaptive-scope-retention/README.md` §11 and `design.md` §4 disclose
  this rather than guessing an answer.
- [ ] VERIFY: the property name(s) `Get-AdaptiveScopeMembers`'s first (metadata) returned element
  actually exposes (total count, page size, more-pages flag, watermark) - Microsoft's reference
  describes them in prose but doesn't name them. `adaptive-scope-retention/validate/
  Test-AdaptiveScopeRetention.ps1` prints the metadata object generically (`Format-List`) rather than
  guessing a property name like `TotalMemberCount`.
- [x] `scenarios/data-lifecycle-management/adaptive-scope-auto-apply-label/` - the auto-apply
  retention **label** variant of the same pattern (`New-RetentionComplianceRule -ApplyComplianceTag`
  instead of `-RetentionComplianceAction`, same `-AdaptiveScopeLocation` policy), noted as a non-goal
  in `adaptive-scope-retention/design.md` §7 - **built** (see DONE below): reuses the Keep-only
  sibling's adaptive scope by name (shared object), adds a `New-ComplianceTag` record label (not
  regulatory - auto-apply doesn't support that), and the same `-AdaptiveScopeLocation` policy pattern
  with an `-ApplyComplianceTag` rule. Grounding this fragment surfaced a real defect in the sibling
  `retention-labels-financial-records` script - see the new follow-up immediately below.

### Follow-up discovered while building the adaptive-scope-auto-apply-label scenario
- [x] **Fix a grounding defect in `scenarios/data-lifecycle-management/retention-labels-financial-
  records/deploy/New-FinancialRecordsRetention.ps1`:** its `New-RetentionComplianceRule` call passes
  both `-Name` and `-ApplyComplianceTag` in the same `$ruleParams` hashtable - **fixed** (see DONE
  below): `Name = "$($cfg.policy.name) - Rule"` removed from `$ruleParams`; `.NOTES`, `README.md`
  §6/§11, `design.md` §4, and `reviews.md` (new correction addendum, targeted Microsoft Product Owner
  re-check) all updated in place. Source:
  <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
- [ ] Consider `-LocationType Site` and `-LocationType Group` adaptive-scope variants (SharePoint site
  properties / KeyQL, and Microsoft 365 Group attributes respectively) as companions to this
  scenario's `User`-type example - `adaptive-scope-retention/design.md` §7.
- [ ] Ground the exact `Search-UnifiedAuditLog` `-RecordType` value (if any is required alongside
  `-Operations`) for the adaptive-scope/retention-policy audit operations
  (`NewAdaptiveScope`/`SetAdaptiveScope`/`RemoveAdaptiveScope`/`ApplicableAdaptiveScopeChange` and the
  `*RetentionCompliancePolicy`/`*RetentionComplianceRule` operations) cited in
  `adaptive-scope-retention/README.md` §8 - not resolved in this build; the README's guidance uses
  `-Operations` alone rather than asserting an unconfirmed `-RecordType`.

### Follow-ups discovered while building the DLM publish-labels-for-manual-application scenario
- [ ] VERIFY (pilot tenant): `Get-RetentionComplianceRule`'s `PublishComplianceTag` read-back property
  name - Microsoft's reference lists only Name/Disabled/Mode/Comment as documented default-display
  properties for this cmdlet. This repo already reads the parallel `ApplyComplianceTag` property
  unhedged in the auto-apply sibling's own validate script; `publish-labels-for-manual-application/
  validate/Test-PublishRetentionLabelPolicy.ps1` follows the same established convention for
  `PublishComplianceTag` rather than introducing an inconsistent hedge - flagged in `README.md` §11.
- [ ] Once a documented PowerShell/Graph cmdlet exists for setting a **default retention label** for a
  SharePoint library/folder or Outlook folder (the related, portal-only capability layered on top of a
  published label - `create-apply-retention-labels#default-labels-for-sharepoint-and-outlook`), add it
  as a companion script here - none was found during this build's grounding pass; disclosed as a
  portal-only gap in `README.md` §11 and `design.md` §7 rather than fabricated.
- [ ] Consider a periodic content-search spot-check script (query known financial-record signals in
  the scoped locations, cross-reference against labeled items) as the concrete tooling for the
  compensating control `reviews.md`'s Red Team finding 1 recommends for this scenario's inherent
  human-dependent coverage gap - not built in this fragment; the finding names the control but this
  repo has no existing content-search automation pattern to adapt from yet.
- [ ] Reconcile the private-channel-style location-support ambiguity for **Microsoft 365 Groups**
  publish targeting once a Data Lifecycle Management scenario needs to distinguish "Group:Exchange" vs
  "Group:SharePoint" `-Applications` scoping (`New-RetentionCompliancePolicy` parameter, documented but
  not exercised by this scenario's `-ModernGroupLocation`-only worked example).

### Follow-ups discovered while building the DLM event-based-retention-and-disposition scenario
- [ ] Build an HR-feed connector (or a scheduled reconciliation script) for
  `event-based-retention-and-disposition` that compares an HR termination export against fired
  `Get-ComplianceRetentionEvent` events and reports departed employees with no matching event -
  explicitly scoped out of the built fragment (`design.md` §7) as a distinct integration/reporting
  problem, not a retention-policy one.
- [ ] Build a dedicated `Export-EventBasedRetentionAuditTrail.ps1` for this scenario (the
  `Search-UnifiedAuditLog` audit-trail pattern several other scenarios in this repo already use) once
  the exact `RecordType`/`Operations` values for retention-event creation, label application, and
  disposition-review decisions are grounded - not found/verified during this build; flagged in
  `event-based-retention-and-disposition/README.md` §11 rather than fabricated.
- [ ] VERIFY (pilot tenant): `-AutoApprovalPeriod` on `New-ComplianceTag` - the parameter's own
  description on the official reference page is an unfilled Microsoft documentation stub; the 7-365
  day range / 14-day default cited in `event-based-retention-and-disposition/README.md` §6/§11 come
  from the separate conceptual disposition-review article, not a confirmed mapping to this exact
  cmdlet parameter. Left disabled (`null`) in the sample config for this reason.
- [ ] VERIFY (pilot tenant): the read-back property name/shape for `-MultiStageReviewProperty` and
  `-ReviewerEmail` on `Get-ComplianceTag` - undocumented (no output-property list published for this
  cmdlet); `validate/Test-EventBasedRetentionAndDisposition.ps1` checks for either being non-null and
  reports `[WARN]`, not `[FAIL]`, rather than asserting an unconfirmed shape.
- [ ] VERIFY (pilot tenant): whether `-ReviewerEmail` and `-MultiStageReviewProperty` can be set
  together on the same label, or are mutually exclusive - undocumented either way. This scenario
  always uses exactly one, never both, for this reason.
- [ ] VERIFY (pilot tenant): whether firing a second `New-ComplianceRetentionEvent` under a
  different `-Name` for an employee who already has a fired event causes any adverse effect beyond
  redundancy (e.g., duplicate disposition-review notifications) - `New-RetentionTriggerEvent.ps1` can
  only detect a duplicate by exact `-Name` match (no documented query-by-Asset-ID cmdlet was found).
- [x] RESOLVED (2026-09-25, commit `443aa7c`): **Cross-cutting doc-drift, fixed.** Ran the
  dedicated grep pass this item asked for (`grep -rniE "surface [0-9]" scenarios/*/*/README.md`
  and the same against every `design.md`) against every scenario's `README.md`/`design.md`/
  `deploy/*.ps1` in the repo, cross-checked against the current `docs/automation-surface.md`
  numbering (1 = Exchange Online PowerShell, 2 = Security & Compliance PowerShell, 3 = Microsoft
  Graph - unified SDK/REST, 4 = Purview Data Map/Data Governance REST, 5 = SharePoint Online
  Management Shell). Found and fixed four drifted citations, all in the two files this item named:
  `regulatory-records-disposition/README.md` §3 ("surface 1" → "surface 2" - Security & Compliance
  PowerShell) and its `deploy/New-RecordsDisposition.ps1` `.NOTES` (same fix);
  `graph-event-automation/README.md` §1 ("surface 2/3" → "surface 3") and §3 ("surface 2 -
  Microsoft Graph PowerShell SDK; surface 3 - Graph REST" → "surface 3 - Microsoft Graph, both the
  PowerShell SDK and raw REST are the same unified surface"). Note:
  `retention-labels-financial-records/README.md`, the other file this item originally named, was
  found already correct (already cites "surface 2") - apparently fixed in an earlier, unlogged
  edit; left unchanged. No other drift found anywhere else in the repo - every other "surface N"
  citation checked (audit, communication-compliance, compliance-manager, data-estate-insights,
  data-lineage, data-map, data-quality, ediscovery, information-barriers, information-protection,
  insider-risk, unified-catalog) already matches the current numbering.

### Follow-ups discovered while building the Information Barriers segregate-trading-and-research scenario
- [x] `scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/` - **built**
  (see DONE below): tenant-wide `Set-SPOTenant -InformationBarriersSuspension` enablement plus a
  per-site `Set-SPOSite -AddInformationSegment`/`-RemoveInformationSegment` reconciliation script for
  standalone (non-Teams-connected) sites, closing the file-level gap this scenario's `design.md` §6 /
  `README.md` §11 flagged. Two genuine documentation gaps carried forward as VERIFY rather than
  resolved by guessing: whether `Get-SPOTenant` exposes `InformationBarriersSuspension` on read-back,
  and whether `Get-OrganizationSegment` exposes `EXOSegmentId` (Microsoft's own SharePoint-association
  worked example) or `.Guid` (this scenario's own S&C PowerShell scripts) for the same object - the new
  scripts try both rather than assuming one. `docs/automation-surface.md` §1/§5 updated in the same
  fragment to describe the new per-site surface-5 usage pattern.
- [x] `scenarios/information-barriers/allow-list-and-control-room-exceptions/` - **built** (see DONE
  below): allow-list (`-SegmentsAllowed`) topologies as a companion to the Block-type wall - a
  `ComplianceControlRoom` segment that sees both `Trading` and `Research`, plus a narrower, one-sided
  `Legal` example (Research only) proving the pattern generalizes. Genuine grounding find along the
  way, not merely executed as scoped: Legacy IB mode + an Allow policy hides ALL non-IB users/groups
  from the assigned segment's members (not just unlisted segments) - SingleSegment/MultiSegment mode
  don't have this restriction. Required SingleSegment mode explicitly and added a live
  `Get-PolicyConfig` check to both the deploy and validate scripts rather than shipping the
  originally-scoped "Legacy or SingleSegment" guidance uncorrected.
- [ ] Consider a multi-segment-mode migration note/scenario (Legacy → SingleSegment/MultiSegment) and
  address-book-policy / GAL segmentation as companions.

### Follow-ups discovered while building the allow-list-and-control-room-exceptions scenario
- [ ] VERIFY (pilot tenant): the exact property name/values `Get-PolicyConfig` returns for
  `InformationBarrierMode`. Grounded via the GitHub-mirrored `MicrosoftDocs/office-docs-powershell`
  source for `Get-PolicyConfig`/`Set-PolicyConfig` (`Legacy`/`SingleSegment`/`MultiSegment`), not a
  live tenant - `deploy/New-ControlRoomAllowException.ps1` and
  `validate/Test-ControlRoomAllowException.ps1` both read the property defensively
  (`PSObject.Properties['InformationBarrierMode']`) and degrade to a non-fatal `[WARN]` rather than
  erroring if it's absent or differently named, but confirm the real property name/values before
  relying on the Legacy-mode CAUTION firing correctly in production.
- [ ] Consider an **audit-trail export** for allow-list membership changes (who was added to
  `ComplianceControlRoom`/`Legal`'s allowed-segments list and when) - the same open item as
  `segregate-trading-and-research`'s own untracked IB audit trail; ground the
  `Search-UnifiedAuditLog` `RecordType`/`Operations` values for `New-`/`Set-InformationBarrierPolicy`
  and `New-OrganizationSegment` before building.
- [ ] Consider a **SharePoint/OneDrive site-association companion** for the exception segments (this
  scenario's `ComplianceControlRoom`/`Legal`), mirroring
  `sharepoint-onedrive-enablement-and-site-association`'s per-site `Set-SPOSite
  -AddInformationSegment` pattern - not built here since that scenario only associates
  `Trading`/`Research`.
- [ ] Consider the **all-Allow-policy / MultiSegment rebuild** this scenario's `design.md` §6
  documents as a non-goal: converting `Trading`/`Research` themselves to Allow-type policies so the
  tenant can move to MultiSegment mode and let a person genuinely belong to more than one segment
  (e.g. a person who is both a control-room analyst and, some days, embedded with Trading) - a
  rebuild of the base scenario's policy types, not an extension of it, so scoped as its own fragment.

### Follow-ups discovered while building the Records Management regulatory-records-disposition scenario
- [x] `scenarios/records-management/file-plan-bulk-import/` - bulk create a full file plan (retention
  schedule with citations, departments, authorities across many record classes) via the documented CSV
  import, the multi-class complement to this single representative class - **built** (see DONE below).
- [x] `scenarios/records-management/multi-stage-disposition-review/` - **built** (see DONE below):
  employee-separation records requiring a 3-stage HR → Employment Counsel → Records Management sign-off
  chain via `-MultiStageReviewProperty`, instead of this scenario's single-reviewer `-ReviewerEmail`.
- [x] `scenarios/records-management/graph-event-automation/` - **built** (see DONE): fire retention
  events from a business system via the Microsoft Graph records-management APIs
  (`retentionEvent`/`retentionEventType`, the modern path since the REST event API was deprecated), the
  automation complement to the PowerShell `New-ComplianceRetentionEvent` scenario (surface 2/3).
- [ ] Consider an adaptive-scope variant of the publish policy for large/dynamic estates (a cross-module
  follow-up shared with the DLM scenarios), and a records-vs-regulatory decision note linking this
  scenario with the DLM `retention-labels-financial-records` sibling.

### Follow-ups discovered while building the disposition-proof-export scenario
- [ ] VERIFY (pilot tenant): the `AuditData` JSON field that distinguishes a manually-approved
  `ApproveDisposal` event from an autoapproved one. Microsoft states autoapproval reuses the same
  event ("there's no new auditing event for autoapproval - instead, use the details in the existing
  Approved disposal auditing event") without naming the field. `disposition-proof-export/deploy/
  Export-DispositionProofEvidence.ps1` preserves the full `AuditData` JSON in every exported row so
  this can be extracted from already-collected evidence once the field is identified, without a
  re-query - flagged inline in the script's `.NOTES` and `README.md` §11.
- [ ] VERIFY (pilot tenant): the `AuditData` JSON property name that carries the retention label's
  display name on the disposition-review/`RecordDelete`/`LockRecord`/`UnlockRecord` Operations -
  no worked Microsoft example was found. `-RetentionLabelName` on `Export-DispositionProofEvidence.ps1`
  performs a best-effort scan of every top-level string property rather than asserting one property
  name; resolving this would let a future revision target the exact property directly.
- [ ] Once the manual-vs-autoapproval `AuditData` field above is identified, extend
  `disposition-proof-export/validate/Test-DispositionProofExport.ps1` to report the two counts
  separately rather than only as a combined `ApproveDisposal` total.
- [ ] Consider wiring `disposition-proof-export`'s `-Operations` list (`AddReviewer`/
  `ApproveDisposal`/`ExtendRetention`/`RelabelItem`/`RecordDelete`/`LockRecord`/`UnlockRecord`) into
  `scenarios/audit/streaming-to-sentinel-or-management-api/` as a named, documented example
  configuration - `disposition-proof-export/README.md` §8/§11 already recommends that scenario for
  continuous, alerting-grade monitoring of the out-of-process-deletion pattern, but the streaming
  scenario itself doesn't yet ship a disposition-specific worked example.

### Follow-ups discovered while building the multi-stage-disposition-review scenario
- [ ] VERIFY (pilot tenant): `Get-ComplianceTag`'s read-back property name/shape for a label's multi-stage
  reviewer chain. `MultiStageReviewerMetadata` (with `StageId`/`StageName`/`Reviewers`) is corroborated by
  third-party worked examples of real `Get-ComplianceTag` output, not by Microsoft's own published
  parameter reference, which doesn't document output properties for this feature at all.
  `multi-stage-disposition-review/validate/Test-MultiStageDispositionReview.ps1` reads it defensively via
  `PSObject.Properties[...]` and reports every check touching it as `[WARN]`, never `[FAIL]` - see that
  scenario's `README.md` §11.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): `-ComplianceTagForNextStage`'s actual
  behavior. Both `New-ComplianceTag` and `Set-ComplianceTag`'s own published parameter reference leave
  its description as an unfilled placeholder. The Microsoft Graph records-management `retentionLabel`
  resource's `labelToBeApplied` property ("the replacement label to be applied automatically after the
  retention period of the current label ends") is the closest documented analog, cited as context only -
  `multi-stage-disposition-review`'s deploy script passes the parameter through only if explicitly
  configured (off by default) rather than assuming this behavior. See that scenario's `README.md` §11.
- [ ] Ground the exact `Search-UnifiedAuditLog` `RecordType`/`Operations` values for
  `New-ComplianceTag`/`Set-ComplianceTag` activity, then add a monitoring recommendation (or a dedicated
  export/alerting script) to `multi-stage-disposition-review/deploy/` - a Red-Team-flagged gap: nothing
  in that scenario detects a reviewer chain being altered outside its own scripts (e.g. `Set-ComplianceTag`
  called directly to shorten `AutoApprovalPeriod` or repoint reviewers). Currently only a README §8
  recommendation to restrict the config role and monitor audit logs, without a grounded `RecordType`.
- [ ] Once Microsoft documents a PowerShell/Graph way to query **per-stage** disposition-review backlog
  (pending-item count per stage, not just per label), add it to
  `multi-stage-disposition-review/validate/Test-MultiStageDispositionReview.ps1` - no such surface was
  found during this build's grounding pass; today it's a portal-only check (Records Management >
  Disposition). See that scenario's `README.md` §8/§11.
- [ ] Consider a companion scenario that deliberately **retrofits** a multi-stage reviewer chain onto an
  existing, already-deployed single-reviewer label via `Set-ComplianceTag` (a real, documented, supported
  operation) - explicitly out of scope for `multi-stage-disposition-review`'s own deploy script, which is
  create-or-report only by this repo's records-object convention (`design.md` §7).

### Follow-ups discovered while building the Records Management file-plan-bulk-import scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the exact `Search-UnifiedAuditLog`
  `RecordType`/`Operations` values for a retention-label **definition/creation** event (as distinct
  from the already-documented label **application** events, `Changed retention label for a file` /
  `Labeled message as a record`). Not found during this build; an `Export-*` audit-trail companion
  for bulk-creation events is a genuine follow-up once grounded, not guessed.
- [ ] VERIFY (pilot tenant): the property name(s) `Get-ComplianceTag` exposes for file-plan-descriptor
  read-back (Department/Category/SubCategory/Citation/ReferenceId/Authority) - undocumented;
  `file-plan-bulk-import/validate/Test-FilePlanBulkImport.ps1` reports them informationally rather
  than asserting on a guessed property name.
- [ ] VERIFY (pilot tenant): exact column order/header spelling of the live "Download a blank
  template" file plan import template - a portal-generated artifact with no linked, fetchable copy
  on Microsoft Learn; `file-plan-bulk-import`'s column set is grounded against the documented
  property table but order is unconfirmed against a real download.
- [ ] Once a documented way to set a file-plan citation's `CitationUrl`/`CitationJurisdiction` via
  PowerShell exists (`New-FilePlanPropertyCitation`'s current syntax takes only `-Name`), extend
  `file-plan-bulk-import/deploy/New-FilePlanBulkLabels.ps1` to set them instead of warning and
  requiring the portal for that part.
- [ ] Consider round-tripping an existing tenant's file plan **Export** back into this scenario's CSV
  schema (a different shape than the Import template) - not built; a reconciliation/migration
  follow-up.

### Follow-ups discovered while building the Data Map Azure SQL Managed Instance scenario
- [x] **Backport two corrected REST shapes into `scenarios/data-map/scan-azure-sql-and-classify/`.**
  - **built**, see DONE below.
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` - the next explicitly-flagged sibling in
  `scan-azure-sql-and-classify/design.md` §7's original list (Azure Synapse Analytics dedicated +
  serverless SQL pools) - **built** (see DONE below): reuses the proven object model, documents the
  genuine `kind`/auth/network differences Microsoft's own docs describe (registration per workspace
  with two optional SQL endpoints, a three-part serverless enumeration-authentication story, the
  distinct system scan rule set `AzureSynapseSQL`).
- [x] `scenarios/data-map/scan-on-premises-sql-server-and-classify/` - the third sibling (on-premises
  SQL Server via self-hosted integration runtime), deferred from both this fragment and the original
  sibling scenario's non-goals - a materially different registration/auth story (no managed identity
  path at all; self-hosted IR is mandatory) worth its own careful grounding pass - **built** (see
  DONE below): also scripts the self-hosted integration runtime *resource* and its auth-key retrieval
  via two directly-confirmed REST operations (`Integration Runtimes - Create Or Replace` and
  `- Regenerate Auth Key`) - a first for this repo's Data Map scenarios, none of which had scripted
  even that much of the portal-only credential/SHIR setup story before this build.
- [x] `scenarios/data-map/verify-purview-entra-graph-prerequisites/` - **built** (see DONE below):
  a Microsoft Graph-permissioned checker (`Get-MgDirectoryRole`/`Get-MgDirectoryRoleMember`,
  `RoleManagement.Read.Directory`) confirming Directory Readers membership for every
  Managed-Instance-backed Purview data source's managed identity, taking a CSV inventory so it
  scales to every instance in one run, plus drift detection (any *other* current Directory Readers
  member not in the inventory, reported as non-fatal `WARN`) - closing the Blue Team finding this
  item originally tracked, generalized beyond the single instance that finding was raised against.
- [ ] VERIFY (pilot tenant): the exact TCP port a newly registered managed instance's public endpoint
  listens on. This scenario defaults `-Port` to `3342` (Microsoft's own worked *registration*
  example), but the actual port depends on the instance's connection-policy configuration
  (Redirect vs. Proxy) - flagged inline in `README.md` §11 and the deploy script's parameter help.
- [ ] Consider scripting `Set-AzSqlInstanceActiveDirectoryAdministrator` and the Directory Readers
  Microsoft Graph role-assignment step (the PowerShell pattern Microsoft publishes for it) instead
  of leaving both as manual portal/PowerShell prerequisites (`README.md` §5 steps 2-3) - deferred in
  this build to keep the fragment scoped to the Data Map REST surface itself, consistent with this
  repo's existing precedent of not automating rare, high-privilege, one-time setup steps that sit
  outside the automation identity's own Purview/Azure IAM role scope (see `design.md` §8).

### Follow-ups discovered while building the verify-purview-entra-graph-prerequisites scenario
- [ ] VERIFY (pilot tenant): whether `Get-MgDirectoryRoleMember` returns users and groups (not just
  service principals) as current members of the Directory Readers role in practice - this build's
  grounding pass found only the generic, multi-type `directoryObject` schema for the cmdlet, no
  worked example specific to *this* role confirming all three principal types actually coexist as
  members. The drift-resolution logic in `verify-purview-entra-graph-prerequisites/deploy/
  Confirm-DirectoryReadersMembership.ps1` handles all three regardless - flagged inline in
  `README.md` §11 as a documentation/expectation gap, not a functional one.
- [ ] Once `scenarios/data-map/verify-synapse-serverless-enumeration-grants/` (tracked below under
  the Azure Synapse Analytics follow-ups) is built, decide whether to fold it into
  `verify-purview-entra-graph-prerequisites` as a second check mode or keep it a fully separate
  script - this build deliberately kept the new scenario Graph-only and Directory-Readers-scoped
  (`design.md` §2 goal 1: auth-surface minimalism), so a SQL-permissioned serverless-grant checker
  (a materially different auth surface - a live SQL connection, not Microsoft Graph) remains a
  distinct, not-yet-built fragment rather than being pre-emptively merged in.
- [ ] Consider a `-Remediate` switch (or a fully separate, explicitly higher-privilege companion
  script) that calls `New-MgRoleManagementDirectoryRoleAssignment` to grant Directory Readers to a
  FAILing instance's managed identity automatically - deliberately rejected as a non-goal in this
  build (`design.md` §10) to stay consistent with this repo's established convention against
  automating rare, high-privilege, one-time directory grants; re-open only if a future organization
  conversation specifically asks for it, since it's a deliberate scope boundary, not an oversight.

### Follow-ups discovered while building the Data Map on-premises SQL Server scenario
- [x] VERIFY (pilot tenant or a future Microsoft Learn pass): the literal system scan rule set name
  for the `SqlServerDatabase` data source `kind` - **closed 2026-09-26**. The Microsoft Learn
  "System Scan Rulesets - Get" REST reference (`https://learn.microsoft.com/rest/api/purview/scanningdataplane/system-scan-rulesets/get`)
  publishes its own worked example for `kind: "AzureStorage"`, returning `{"kind": "AzureStorage",
  "scanRulesetType": "System", "id": "systemscanrulesets/AzureStorage", "name": "AzureStorage"}` -
  directly confirming that a system scan ruleset's `name` is always identical to its `kind`, and that
  `SqlServerDatabase` is a documented `kind`/`DataSourceType` value in that same schema. Corrected
  from VERIFY to confirmed in `scan-on-premises-sql-server-and-classify/README.md` (§6 table, §11,
  §12 ref [14]), `design.md` (§4, §5, §7), and the deploy script's `.PARAMETER`/`.NOTES` blocks;
  `reviews.md` carries a maintenance addendum. The sibling `CredentialType`/Windows Authentication
  VERIFY (next item below) remains open and untouched by this pass.
- [ ] VERIFY (pilot tenant): which `CredentialType` REST enum value corresponds to "Windows
  Authentication" in the portal for the `SqlServerDatabaseCredential` scan kind - Microsoft's portal
  documents Windows Authentication as a supported method for this source type, but the confirmed
  enum (`AccountKey`/`ServicePrincipal`/`BasicAuth`/`SqlAuth`/`AmazonARN`/`ConsumerKeyAuth`/
  `DelegatedAuth`/`ManagedIdentity`) has no value independently confirmed to map to it.
  `scan-on-premises-sql-server-and-classify`'s deploy script offers `'BasicAuth'` as an unconfirmed
  best-effort alternative to the confirmed `'SqlAuth'` default - see that scenario's `README.md` §11.
- [ ] `scenarios/data-map/scan-on-premises-sql-server-and-classify-kubernetes-shir/` (or fold into a
  future Data Map hardening pass) - the Kubernetes-based, containerized self-hosted *data* integration
  runtime Microsoft documents as a separate, newer capability (SQL Server and Oracle only,
  SQL-authentication-only) from the classic Windows-host SHIR `scan-on-premises-sql-server-and-
  classify` scripts - explicitly out of scope there (`design.md` §8) as a materially different
  deployment model.
- [ ] Consider scripting Microsoft Graph-based monitoring of the self-hosted integration runtime's
  auth-key rotation history or last-check-in time, closing part of the Blue-Team-flagged gap in
  `scan-on-premises-sql-server-and-classify/reviews.md` that the Data Map REST API's Integration
  Runtimes - Get operation returns the resource definition, not live node health - no such monitoring
  endpoint was independently grounded during this build; would need a fresh grounding pass.
- [ ] Once a documented REST endpoint for Purview credential-object creation is found (the same open
  gap every Data Map sibling scenario in this repo already carries, most recently re-confirmed absent
  by Microsoft's own disaster-recovery/migration best-practices article - "there's no API to extract
  credentials"), revisit whether it can also *create* one, not just document/extract, and close this
  gap across every Data Map scenario in this repo at once rather than scenario-by-scenario.

### Follow-ups discovered while building the Data Estate Insights sensitivity-label-coverage-report scenario
- [ ] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` - add a source-type-support
  check to `deploy/Export-SensitivityLabelCoverageReport.ps1`/`validate/
  Test-SensitivityLabelCoverageReport.ps1` that flags when a scoped `-CollectionId`/`-ObjectTypes`
  combination is outside Microsoft's documented Data Map sensitivity-label source-type list (Azure
  Blob Storage, ADLS Gen1/Gen2, SQL Server, Azure SQL Database, Azure SQL Managed Instance, Amazon S3,
  Amazon RDS (preview), Power BI), so a `0% labeled` reading for an unsupported source type isn't
  mistaken for a real governance gap - deferred from that scenario's build (flagged as a Red Team/Blue
  Team finding in `reviews.md`, and as a non-goal in `design.md` §7) because this build did not
  independently re-verify that supported-source list is complete/current enough to hard-code as a
  validation rule; needs a fresh grounding pass specifically on that list before encoding it.
- [ ] Once Microsoft's "Extend sensitivity labels to Data Map" capability reaches GA (it is Public
  Preview as of this build - `sensitivity-label-coverage-report/README.md` §3/§11), re-verify the
  `label` field/facet semantics on Discovery - Query still hold and drop the preview callout.
- [ ] Consider a `scenarios/information-protection/` or cross-cutting follow-up scripting the "extend
  sensitivity labels to Data Map" enablement itself (turning on the capability, scoping a label to
  "Files & other data assets") - left as a manual portal prerequisite in
  `sensitivity-label-coverage-report/README.md` §5 step 1/`design.md` §7, since this scenario only
  reads labels already applied, consistent with `classification-coverage-report`'s own non-goal of not
  building the scan it reports on.

### Follow-ups discovered while building the Data Map Azure Synapse Analytics scenario
- [ ] VERIFY (pilot tenant or a future Microsoft Learn/SDK grounding pass): the exact JSON shape of the
  `AzureSynapseWorkspaceMsiScan` object's optional `resourceTypes` property (seen only as an opaque
  `-ResourceType` parameter on the Az.Purview PowerShell module's `New-AzPurviewAzureSynapseWorkspaceMsiScanObject`
  cmdlet, with no worked example of its value) - `scan-azure-synapse-and-classify/deploy/
  New-AzureSynapseDataMapScan.ps1` omits the property entirely rather than guess a shape that could
  silently mis-scope the scan between dedicated and serverless pools. Flagged inline in the deploy
  script's `.NOTES`, `README.md` §6/§11, and `design.md` §5/§7.
- [x] `scenarios/data-map/bulk-grant-synapse-serverless-access/` (or fold into a future Data Map
  hardening pass) - script to bulk-apply the per-serverless-database `CREATE LOGIN`/`CREATE USER`/
  `db_datareader` grants across every database in a workspace (e.g. iterating `sys.databases` via
  `Invoke-Sqlcmd`), closing the CISO-flagged per-database prerequisite-cost scaling noted in
  `scan-azure-synapse-and-classify/README.md` §3 and `reviews.md`. - **built** (see DONE below):
  `deploy/Grant-SynapseServerlessDatabaseAccess.ps1` enumerates serverless databases via
  `sys.databases` and idempotently reconciles the login/user/role-membership grants, continuing past
  a single database's failure rather than aborting the batch. This build's own deeper grounding pass
  (two independent, directly-fetched Microsoft Learn pages) found the parent scenario's "repeat
  `CREATE LOGIN` for every serverless database" framing overstates the actual requirement - it is a
  server-scoped statement, run once against `master`, not once per database (see this new scenario's
  `design.md` §4). Implemented correctly here; **not** backported into the parent scenario's own
  README/design in this fragment - tracked as a fresh follow-up immediately below. Also closes the
  `verify-synapse-serverless-enumeration-grants` item immediately below in the same build (its own
  `validate/Test-SynapseServerlessDatabaseAccess.ps1`), and surfaced two cross-cutting doc gaps
  (also tracked below) rather than silently assuming coverage.
- [x] `scenarios/data-map/verify-synapse-serverless-enumeration-grants/` (or combine with the Managed
  Instance sibling's already-tracked `verify-purview-entra-graph-prerequisites/` follow-up into one
  broader SQL/Graph-permissioned checker) - a SQL-permissioned checker script confirming the serverless
  `CREATE LOGIN` and `db_datareader` grants exist per database, deferred from `scan-azure-synapse-and-
  classify/validate/Test-AzureSynapseDataMapScan.ps1` because that script's own auth surface (the
  Purview Data Map data-plane token) has no reason to also hold a SQL connection to the serverless
  endpoint - flagged as a Blue Team finding in that scenario's `reviews.md`. - **closed by**
  `scenarios/data-map/bulk-grant-synapse-serverless-access/validate/
  Test-SynapseServerlessDatabaseAccess.ps1` (see DONE below): a dedicated, lower-privileged,
  read-only SQL-permissioned checker confirming the server-level login and per-database
  user/`db_datareader` membership, built as part of the same fragment as the bulk-grant script above
  rather than as a separate turn (the two are one cohesive deliverable - a script and its own
  validation script, per `AGENTS.md` §4 - not two fragments).
- [ ] Consider scripting the **REST API + SQL Auth fallback** for a Synapse workspace whose "Allow
  Azure services and resources to access this workspace" firewall control cannot be enabled - deferred
  from `scan-azure-synapse-and-classify/design.md` §8 as a materially different auth/credential story
  (a Key Vault-backed SQL credential object, the same open portal-only credential-object gap both
  sibling Data Map scenarios already carry).

### Follow-ups discovered while building the bulk-grant Synapse serverless access scenario
- [x] RESOLVED (2026-09-25, commit `165d740`): Backported the server-scoped-vs-per-database
  `CREATE LOGIN` correction (see `bulk-grant-synapse-serverless-access/design.md` §4) into
  `scan-azure-synapse-and-classify/README.md` and `design.md`, which described it as a
  per-database step. Fixed in `README.md`: §3 prerequisites table row, §5 step 3c (now explains
  the server-scoped grounding and that the portal's "per database" framing is a Synapse Studio
  navigation artifact, not a real per-database repetition), §8's incident-response cause (e) and
  review-cadence paragraph (both previously implied a database restore/recreate could drop the
  server-scoped login - corrected to attribute that risk only to the genuinely per-database
  `CREATE USER`/`db_datareader` grant). Fixed in `design.md` §4's comparison table row (relabeled
  "database-level" → "server-scoped," corrected the "each serverless SQL database" claim to
  "once, against `master`"). Mermaid diagram and §5 step 4's serverless T-SQL block needed no
  change - neither claimed per-database `CREATE LOGIN` repetition.
- [ ] Add a **sixth automation surface** to `docs/automation-surface.md` - direct T-SQL/Azure SQL
  connections via `Invoke-Sqlcmd -AccessToken` (resource `https://database.windows.net/`), the surface
  `bulk-grant-synapse-serverless-access/deploy/Grant-SynapseServerlessDatabaseAccess.ps1` introduces
  and none of the existing five surfaces cover. Follows the same precedent as this doc's own surface-5
  (SharePoint Online Management Shell) addition.
- [ ] Add a **tenth system** to `docs/rbac-model.md` - Azure Synapse Analytics workspace RBAC (Synapse
  Administrator / Synapse SQL Administrator / SQL Active Directory Admin), the role system
  `bulk-grant-synapse-serverless-access/README.md` §3 depends on and none of the doc's existing nine
  systems cover.
- [ ] Consider an estate-wide login/grant inventory-drift report for Azure Synapse serverless SQL pools
  (which external logins exist, which databases they're members of `db_datareader` in) - the same
  estate-wide shape `scenarios/data-map/scan-credential-inventory-report/` already applies to Data Map
  credentials - deferred here because `bulk-grant-synapse-serverless-access/validate/` only checks the
  one named `-PrincipalName`, not a full inventory; flagged as a Blue Team finding in that scenario's
  `reviews.md`.
- [ ] Consider a scenario scripting/documenting Azure SQL/Synapse workspace **SQL auditing** (diagnostic
  logs) as the durable, tamper-evident record of `CREATE LOGIN`/`CREATE USER`/`ALTER ROLE` changes this
  repo's Synapse scenarios don't otherwise capture - flagged as a Blue Team finding in
  `bulk-grant-synapse-serverless-access/reviews.md` and as a gap in that scenario's own `README.md` §8.

### Follow-ups discovered while building the PCI Teams Part 2 (drip-exfiltration) scenario
- [ ] VERIFY (pilot tenant): run the full end-to-end composition this fragment designs but does
  not independently confirm against a live tenant - Communication Compliance SIT indicator →
  feeder IRM "Data leaks" policy → Cumulative Exfiltration Detection → Adaptive Protection →
  `PCI-ElevatedRisk-Block-AllExternal` rule - per `design.md` §6b. Every individual piece is
  grounded; the combination as a working end-to-end chain is not yet pilot-confirmed.
- [ ] Once Microsoft documents a faster-than-daily Cumulative Exfiltration Detection evaluation
  cadence, or a lower-latency Adaptive Protection propagation path, revisit the "one to two days"
  exposure-window estimate in `pci-teams-exfil-block-part2-obfuscation-mitigation/README.md` §11
  and its KPI in §8.
- [ ] Consider generalizing this fragment's pattern - a new, narrowly-scoped
  `-SharedByIRMUserRisk` rule added directly to a scenario's *own* named DLP policy (rather than
  routing through `dynamic-risk-dlp-enforcement`'s general-purpose Exchange+Teams policy) - as a
  reusable template for other content-pattern-based DLP scenarios in this library that want an
  Adaptive-Protection behavioral compensating control for the same per-message blind spot (e.g. a
  future Communication Compliance or DSPM-for-AI scenario facing the same split-content evasion
  shape).
- [ ] `scenarios/communication-compliance/` - the Communication Compliance policy this fragment's
  Step 2 creates via the Insider Risk Management "Create policy" shortcut is a real, named
  Communication Compliance policy (auto-named `Insider risk SIT indicator <timestamp>`) that
  currently has no dedicated audit-trail/export script pointed at it, unlike
  `scenarios/communication-compliance/harassment-and-code-of-conduct/deploy/
  Export-CommunicationComplianceAuditTrail.ps1`. Consider whether that existing script generalizes
  to cover this auto-created policy too, once an organization actually deploys this fragment.

### Follow-ups discovered while building the Compliance Manager PCI DSS v4.0 assessment scenario
- [x] Already resolved by a separate, already-committed fragment: `scenarios/compliance-manager/
  assess-against-iso27001/` was switched to the ISO/IEC 27001:2022 premium template in commit
  `984fa9e` (2026-09-10, see DONE below) - this duplicate reference marked closed on inspection
  (2026-09-25), no new work needed.
- [ ] VERIFY (pilot tenant): the PCI DSS Requirement 12.4 formal-compliance-program review-cadence
  obligation was deliberately left unspecified/parameterized rather than hard-coded in this
  scenario's tooling (no specific interval is asserted) - see `pci-dss-assessment/README.md` §8/§11.
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
  tenants' regulation catalogs (vs. still selectable but flagged legacy) - this build confirmed both
  v3.2.1 and v4.0 are currently listed side by side in the public `compliance-manager-regulations-
  list` documentation, but a pilot-tenant check would confirm what the live **Regulations** page
  actually offers today.
- [x] `scenarios/compliance-manager/soc2-assessment/` or a similar SOC 2 Type II premium-template
  scenario - **built** (see DONE below): full deliverable mirroring `assess-against-iso27001/` and
  `pci-dss-assessment/`'s shape, with a 5-category AICPA Trust Services Criteria crosswalk (not a
  6-numbered-goal one - SOC 2's own published structure is categorical) and explicit Type I/Type II
  operational guidance neither sibling scenario needed.

### Follow-ups discovered while building the Compliance Manager SOC 2 assessment scenario
- [ ] VERIFY (pilot tenant): whether Compliance Manager's Controls/Improvement actions views let you
  filter or tag improvement actions by AICPA Trust Services Criteria category (Security/
  Availability/Processing Integrity/Confidentiality/Privacy) after assessment creation - no
  documented wizard step or worked example surfaced during this build's WebSearch/Microsoft Learn
  MCP grounding pass. `soc2-assessment/README.md` §11 flags this as an open item rather than
  assuming the capability exists or doesn't.
- [ ] Once a live tenant is available: run the "Group-sharing functional test" across all three
  Compliance Manager scenarios now sharing the `Security & Compliance Assessments` group
  (`assess-against-iso27001`, `pci-dss-assessment`, `soc2-assessment`) simultaneously, not just
  pairwise - `soc2-assessment/README.md` §7 item 4 only describes a pairwise spot-check.
- [x] Consider a fourth Compliance Manager scenario for a regulation this library hasn't covered yet
  (e.g. HIPAA/HITECH or GDPR, both explicitly named in `AGENTS.md` §3's regulatory-driver axis and
  both listed in Compliance Manager's premium regulations catalog) - **built** (see DONE below):
  `scenarios/compliance-manager/hipaa-hitech-assessment/`, picked over GDPR per this item's own
  tie-break rule (a common enterprise/regulatory driver pairing naturally with the existing PCI
  DSS + SOC 2 + ISO 27001 trio) after confirming both HIPAA/HITECH and GDPR are real, currently
  listed premium templates. Crosswalk uses HIPAA/HITECH's own published rule structure (Privacy
  Rule, Security Rule's 3 safeguard categories, Breach Notification Rule) rather than a numbered-
  goal or Trust-Services-Criteria shape, plus a HIPAA-specific "addressable ≠ optional" structural
  flag with no analog in the other three siblings' crosswalks.

### Follow-ups discovered while building the Compliance Manager HIPAA/HITECH assessment scenario
- [x] Consider a fifth Compliance Manager scenario for **GDPR** (the regulation this item's own
  tie-break rule deferred in favor of HIPAA/HITECH) - **built** (see DONE below):
  `scenarios/compliance-manager/gdpr-assessment/`, mirroring `assess-against-iso27001/`,
  `pci-dss-assessment/`, `soc2-assessment/`, and `hipaa-hitech-assessment/`'s shape, with its own
  6-category crosswalk matching GDPR's own published structure (Data Subject Rights, Data Processing
  Principles, Breach Notification, Data Protection Impact Assessment, Cross-Border Data Transfers,
  Accountability & Governance) rather than a copy of any sibling's shape - genuinely different from
  a numbered-goal (PCI DSS), Trust-Services-Criteria (SOC 2), Annex A (ISO 27001), or
  rule-with-safeguard-categories (HIPAA/HITECH) structure. Also grounded and documented three
  GDPR-specific wrinkles no sibling scenario needed: the December 2022 licensing change's specific
  effect on GDPR (moved from included-by-default to counting against the 3-free-premium-template
  allotment, alongside NIST 800-53 and ISO 27001), GDPR's Article 37 *conditional* (not blanket) DPO
  designation requirement, and GDPR's own Article 42/43 certification mechanism being real but
  fragmented (a third distinct "what this assessment is not" shape, alongside HIPAA's "none exists"
  and SOC 2/ISO 27001's "a mature one exists").
- [ ] Consider a dedicated PHI-classification/DLP scenario using Microsoft Purview's built-in
  "U.S. Health Insurance Act (HIPAA) Enhanced" DLP policy template (confirmed via
  `dlp-policy-templates-include` during this build: SSN + DEA Number + U.S. Physical Addresses +
  All Full Names sensitive information types AND ICD-9-CM/ICD-10-CM keyword terms AND the
  Healthcare/Health-Medical-Forms trainable classifiers, scoped to Exchange/SharePoint/OneDrive/
  Teams/Devices/on-premises repositories) - `hipaa-hitech-assessment/README.md` §11 and its
  manifest's Privacy Rule `coverage` field disclose this as an unbuilt gap rather than claiming
  coverage that doesn't exist; this would be the natural scenario to close it, and would also give
  the HIPAA/HITECH assessment's Privacy Rule crosswalk row genuine technical coverage it currently
  lacks.
- [ ] VERIFY (pilot tenant): whether Compliance Manager's Controls/Improvement actions views expose
  which specific improvement actions correspond to "required" vs. "addressable" HIPAA Security Rule
  implementation specifications anywhere in the UI itself (only the underlying 45 CFR rule text was
  confirmed during this build's grounding pass, via `entra/standards/hipaa-configure-for-
  compliance`) - would materially help a Contributor/Assessor prioritize evidence-quality review on
  the addressable specifications this scenario's manifest and validate script flag as
  not-optional-despite-the-name (`hipaa-hitech-assessment/README.md` §11).
- [ ] Once a live tenant is available: run the "Group-sharing functional test" across all four
  Compliance Manager scenarios now sharing the `Security & Compliance Assessments` group
  (`assess-against-iso27001`, `pci-dss-assessment`, `soc2-assessment`, `hipaa-hitech-assessment`)
  simultaneously, not just pairwise - extends the identical open item `soc2-assessment` left behind
  for its own three-way case.

### Follow-ups discovered while building the Compliance Manager EU GDPR assessment scenario
- [x] A dedicated **GDPR Data Subject Request (DSR) fulfillment** scenario - the closest existing
  technical building block, `scenarios/ediscovery/search-and-purge-data-spillage/`, was built for
  inadvertent data-spillage remediation, not purpose-built DSR case management: it has no
  request-tracking, no per-request SLA timer against GDPR's own Article 12(3) one-month (extendable
  by two further months) response deadline, and no rectification/restriction workflow (only
  discovery/export/deletion). `gdpr-assessment/README.md` §11, `design.md` §7, and `reviews.md` Red
  Team finding 4 all disclose this gap rather than overclaim DSR coverage that doesn't exist. -
  **built** (see DONE below) as `scenarios/ediscovery/gdpr-dsr-fulfillment/`: custodian-scoped
  eDiscovery case/search per data subject (not a tenant-wide sweep), an Article 12(3) SLA ledger,
  and a hand-off (not a duplicate) to `premium-legal-hold-and-export` (Access/Portability) and
  `search-and-purge-data-spillage` (Erasure). Rectification/Restriction/Objection remain
  ledger-tracked only - no Purview-native technical control exists for any of the three (that
  scenario's `design.md` §6). `gdpr-assessment/README.md` §8/§11, `design.md` §7, and the manifest's
  `controlCrosswalk` updated in place to point at the new scenario instead of repeating the gap.
- [ ] A **cross-border data transfer / data residency** scenario scoping Standard Contractual
  Clauses-relevant technical controls (e.g. Data Map/Purview data-residency-aware scanning or
  storage-location reporting) for GDPR Article 46 purposes - `gdpr-assessment/deploy/policy/
  gdpr-assessment-manifest.json`'s `controlCrosswalk` states this category has little to no direct
  technical coverage from this library today; also relevant to the AGENTS.md §3 "multi-geo data
  residency" scale axis more broadly, not just GDPR.
- [ ] VERIFY (pilot tenant): whether Compliance Manager's Controls/Improvement actions views let you
  filter or tag improvement actions by GDPR compliance area (Data Subject Requests / Breach
  Notification / DPIA / processing principles) after assessment creation - no documented wizard step
  or worked example surfaced during this build's Microsoft Learn MCP grounding pass.
  `gdpr-assessment/README.md` §11 flags this as an open item rather than assuming the capability
  exists or doesn't.
- [ ] Once a live tenant is available: run the "Group-sharing functional test" across all five
  Compliance Manager scenarios now sharing the `Security & Compliance Assessments` group
  (`assess-against-iso27001`, `pci-dss-assessment`, `soc2-assessment`, `hipaa-hitech-assessment`,
  `gdpr-assessment`) simultaneously, not just pairwise - extends the identical open item
  `hipaa-hitech-assessment` left behind for its own four-way case.
- [ ] VERIFY (pilot tenant): whether an organization that adopted Compliance Manager's GDPR template
  before the December 2022 licensing change is shown any distinct migration/grandfathering signal on
  the Regulations page, or simply sees it counted against the 3-free-premium-template allotment with
  no further notice - `gdpr-assessment/README.md` §3/§10 states the current model but this
  transition-period UX detail wasn't independently confirmed.

### Follow-ups discovered while building the GDPR DSR fulfillment scenario
- [ ] VERIFY (pilot tenant): whether the `IncludedSources: 'mailbox, site'` combined-string form
  `Confirm-SubjectUserSource` sends is accepted by the current v1.0 `custodians/{id}/userSources`
  endpoint, or only a single value at a time - inherited unresolved from
  `premium-legal-hold-and-export`'s own open VERIFY on the same call shape; no new evidence surfaced
  during this build's grounding pass either way.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether `dataSourceScopes` accepts a
  comma-combined value (the way `IncludedSources` does) or requires one call per scope - this
  scenario's script only ever passes a single value (`allCaseCustodians` or, separately,
  `allTenantMailboxes`) and was never tested against a combined-scope request.
- [ ] No KQL property equivalent to `participants:` was found for "SharePoint/OneDrive content
  *about* a person who isn't its author/owner" - `-IncludeParticipantSearch` (built this fragment)
  closes the analogous Exchange-side gap but SharePoint/OneDrive content mentioning a data subject
  without their authorship remains invisible to both of this scenario's searches. Re-open if
  Microsoft documents a workable property (`referencedUsers`-style or similar) for this.
- [ ] Consider a lightweight file-lock (or a documented "one writer at a time" operational
  convention beyond the README's own disclosure) for `dsr-ledger.json` if a pilot deployment's DSR
  volume grows enough that concurrent `New-DsrRequest.ps1` runs become realistic - deferred as
  out of scope for the low-to-moderate volume this fragment is sized for (`README.md` §10/§11).
- [ ] VERIFY (portal or Microsoft Learn): confirm whether Microsoft Purview eDiscovery's review-set
  export can be configured to produce a CSV/JSON metadata companion (not just PST/native files) that
  would more comfortably satisfy Article 20's "structured, commonly used, machine-readable format"
  wording for a Portability request - `README.md` §11 currently just flags the PST/native-format gap
  without a confirmed alternative.
- [ ] Once `scenarios/compliance-manager/gdpr-assessment/`'s own still-open follow-up (a
  cross-border data transfer / data residency scenario, immediately above) is built, cross-check
  whether it should link back to this scenario's ledger for any DSR that also triggers a
  cross-border-transfer question (e.g., an Access request where the data resides outside the
  data subject's own region) - not evaluated in this build.

### Follow-ups discovered while building the Data Lineage custom-process-lineage scenario
- [ ] VERIFY (pilot tenant): whether a relationship end's `typeName` must be the entity's own
  concrete custom subtype (`PurviewScenarioLibraryEtlProcess`) or may be the literal ancestor type
  (`Process`) when resolving by `uniqueAttributes.qualifiedName` on `Relationship - Create`.
  `custom-process-lineage`'s deploy script uses the literal `Process` for both relationship ends
  referencing the Process entity, exactly matching Microsoft's own worked example - but that
  example's concrete entity type was a **built-in** subtype (`hive_view_query`), not a custom one.
  Flagged inline in `custom-process-lineage/README.md` §11 and the deploy script's `.NOTES` rather
  than assumed; a one-line fix if wrong.
- [ ] VERIFY (pilot tenant or Microsoft Learn): the exact permission required to create a custom
  **entity type definition** via `Type - Bulk Create` - this build confirmed collection-level Data
  Curator is sufficient for the closely related "create a custom classification" action but found
  no equally explicit statement for entity-type creation specifically. `custom-process-lineage/
  README.md` §3 documents the residual tenant-wide-blast-radius risk either way this resolves.
- [ ] VERIFY (pilot tenant): the exact REST path and in-use-type deletion behavior of `Type -
  Delete` - confirmed to exist only via the .NET SDK's `TypeDefinition.Delete(name)` method
  signature, not an independently fetched canonical REST reference page. Blocks
  `custom-process-lineage/rollback.md` from scripting deletion of the custom Process type
  definition it creates; that file documents the deliberate decision to leave the type in place by
  default and describes the manual, reviewed alternative.
- [ ] VERIFY (pilot tenant): the not-found HTTP status code for `Type - Get Entity Def By Name` -
  its reference page documents only a 200 OK success shape, so `custom-process-lineage`'s
  existence-check treats any non-success response as "does not exist yet" rather than assuming 404
  specifically. Functionally safe either way (see `README.md` §11) but not confirmed.
- [ ] `scenarios/data-lineage/custom-process-lineage-multi-job-catalog/` (or fold into a future
  Data Lineage hardening pass) - extend the single custom Process type this scenario ships
  (`PurviewScenarioLibraryEtlProcess`, two attributes) into a richer, multi-job catalog: additional
  attributes (owning team, source-code repository URL, last-run status) and a pattern for modeling
  many jobs sharing one type without qualifiedName collisions - explicitly deferred as a non-goal
  in `custom-process-lineage/design.md` §8 to keep this fragment scoped.
- [ ] Once a documented REST/Graph way to enumerate live entity counts by type exists (needed to
  safely confirm "zero remaining entities of this type" before a human deletes the custom Process
  type definition entirely), reference it from `custom-process-lineage/rollback.md`'s manual
  decommission guidance instead of pointing at the Data Map portal search/browse UI as the only
  option.

### Follow-ups discovered while building the Defender for Endpoint device control macOS Bluetooth approved-device allowlist scenario
- [x] Support more than one approved Bluetooth device - **built in place** (see DONE below), folded
  into `defender-device-control-usb-allowlist-macos-bluetooth-allowlist/` as v2 rather than a
  separate `-multi-device` sibling folder (a cardinality generalization of the same object, not a
  different data source/scan kind - the pattern the three-sibling Data Map UAMI wiring used, which
  doesn't apply here). Resolved by reusing the per-device sub-group + `groupId`-clause-nesting
  technique `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`
  independently built and validated for the identical AND-then-OR problem after this scenario's v1
  shipped - the "unverified complexity" deferral this item originally cited no longer applied by the
  time this fragment was picked up.
- [ ] VERIFY (pilot tenant): the exact `AdditionalFields` property names for a Bluetooth device's
  `vendorId`/`productId` on a `RemovableStoragePolicyTriggered` deny event (used in this scenario's
  `README.md` §7 step 6 worked query to help an operator find an unapproved device's identifiers) -
  not independently confirmed by a Microsoft worked example; this build's query is an extension of
  the same cross-platform `DeviceEvents` schema assumption the parent and portable-device-coverage
  fragments already establish for other fields, not a directly confirmed field name for these two
  specifically. Flagged inline in `README.md` §11 rather than resolved by guessing.
- [ ] Once the ordering-hazard root cause is resolved some other way (e.g. if Microsoft ever
  documents a merge-not-replace PATCH semantics for `payload`, or if a future refactor of the
  portable-device-coverage fragment's own script becomes independently warranted for an unrelated
  reason), reconsider whether `defender-device-control-usb-allowlist-macos-bluetooth-allowlist`'s
  disclosed-and-detected mitigation (`design.md` §8) should be upgraded to a structural fix instead -
  deliberately not attempted in this build to avoid reopening an already-reviewed, unrelated
  fragment's script for a coupling change (`design.md` §8 explains the trade-off considered).

### Follow-ups discovered while building the Data Map PII-only scan rule set (Azure SQL Database) scenario
- [ ] VERIFY (pilot tenant): whether `GET .../types/typedefs?type=CLASSIFICATION` paginates once a
  tenant has an unusually large number of custom classification rules layered on top of the ~200
  system ones - no continuation-token field is documented on the response shape, and
  `deploy/New-PiiOnlyScanRuleset.ps1` does not implement paging. Flagged inline in the script's
  `.NOTES` and `README.md` §11.
- [x] `scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/` - **built** (see DONE
  below): the same PII-only custom scan rule set pattern applied to Azure Synapse Analytics. This
  build's own grounding pass (Az.Purview module GitHub source, `learn.microsoft.com` still
  `EGRESS_BLOCKED` in this environment) found the actual ruleset `kind` is `AzureSynapseWorkspace`,
  **not** the `AzureSynapse` shorthand this item originally guessed - corrected in place rather
  than propagated. It also surfaced a genuine naming trap this source type has and the Azure SQL
  Database sibling does not: the System default ruleset's **name** (`AzureSynapseSQL`) is a
  different string from the custom ruleset's **kind** (`AzureSynapseWorkspace`), unlike the sibling
  where both are the identical `AzureSqlDatabase` string - caught by this build's own Red Team pass
  before shipping (`reviews.md` Red Team finding 1) rather than left as a latent rollback bug.
- [x] `scenarios/data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset/` - **built**
  (see DONE below): the same PII-only custom scan rule set pattern applied to Azure SQL Managed
  Instance. Independently direct-fetched `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject`
  per this item's own instruction rather than assuming either prior sibling's name-vs-kind pattern -
  found the custom ruleset `kind` (`AzureSqlDatabaseManagedInstance`) is the IDENTICAL string to the
  System default ruleset's own name (the Azure SQL Database sibling's simpler pattern, not the
  Synapse sibling's naming trap), and disclosed that finding as independently confirmed rather than
  inherited, with an explicit warning not to assume it forward onto the still-unbuilt
  `SqlServerDatabase` sibling below.
- [x] `scenarios/data-map/scan-on-premises-sql-server-and-classify-pii-ruleset/` - **built** (see
  DONE below): the same PII-only custom scan rule set pattern applied to on-premises SQL Server -
  the fourth and last of this repo's Data Map PII-ruleset sibling scenarios. Per this item's own
  instruction, independently grounded the ruleset `kind` rather than assuming either prior
  sibling's name-vs-kind pattern - and, with `learn.microsoft.com` directly reachable in this
  build's environment (unlike the Synapse/Managed Instance builds), confirmed it via THREE
  converging first-party sources (Az.Purview PowerShell reference, Scan Rulesets - Get REST
  reference, `@azure-rest/purview-scanning` JS SDK) rather than one: the custom ruleset `kind` is
  the literal string `SqlServerDatabase` - identical to the base scenario's own already-shipped
  `-ScanRulesetName` default and to the data source `kind` itself (the Azure SQL Database/Managed
  Instance siblings' simpler pattern, not the Synapse naming trap). This build deliberately did
  NOT over-claim: the base scenario's own separate, already-open VERIFY on the System ruleset's
  literal resource *name* (as opposed to its `kind`) could not be closed by this grounding pass
  either - no worked example was found pairing `scanRulesetName: "SqlServerDatabase"` with
  `scanRulesetType: "System"` - and stays open, flagged inline rather than silently treated as
  resolved just because the related `kind` question was.
- [x] Consider a **credential-object creation** follow-up (Key Vault-backed, for the
  `AzureSqlDatabaseCredential` scan kind) becoming unblocked by the same Types/Scan-Rulesets REST
  grounding pass this build did - not investigated this round; the base scenario's `README.md` §11
  VERIFY on this point was left as-is (out of scope for a scan-rule-set-focused fragment).
  **STALE - already closed by `scenarios/data-map/scan-credential-key-vault-backed/`** (extended by
  `scan-credential-remaining-kinds/` and `scan-credential-inventory-report/`); confirmed via
  `grep -rl AzureSqlDatabaseCredential scenarios/data-map/scan-credential-key-vault-backed/`.

### Follow-ups discovered while building the Data Map on-premises SQL Server PII-only scan rule set scenario
- [ ] VERIFY (pilot tenant, or a future pass): the on-premises SQL Server System default scan rule
  set's literal resource **`name`** (as opposed to its `kind`, which this build confirmed is
  `SqlServerDatabase` via three converging Microsoft sources). No worked example was found anywhere
  - despite this build specifically searching for one - pairing a literal `scanRulesetName:
  "SqlServerDatabase"` with `scanRulesetType: "System"` in a live scan object; the one worked scan
  example found (`New-AzPurviewSqlServerDatabaseCredentialScanObject`) uses an arbitrary custom
  ruleset name, `'SqlServer'`, not the System default. This is the same VERIFY the base scenario
  (`scan-on-premises-sql-server-and-classify/README.md` §11) already carried - this build could not
  close it, only narrow what remains unconfirmed. Flagged inline in this scenario's
  `deploy/Remove-PiiOnlyScanRuleset.ps1` `.NOTES`, `README.md` §11, and `rollback.md` Stage 1.
- [x] RESOLVED (2026-09-25, commit `3abedf3`): a later build reached `learn.microsoft.com` directly
  (Microsoft Learn MCP tool, no `EGRESS_BLOCKED`) and fetched the Scan Rulesets - Create Or Replace
  REST reference page in full
  (`https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace`,
  api-version `2023-09-01`). It documents `AzureSqlDatabaseManagedInstanceScanRulesetProperties` and
  `AzureSynapseWorkspaceScanRulesetProperties` directly, both containing exactly `createdAt`
  (read-only), `description`, `excludedSystemClassifications` (`string[]`),
  `includedCustomClassificationRuleNames` (`string[]`), `lastModifiedAt` (read-only) - matching what
  both scenarios' `deploy/New-PiiOnlyScanRuleset.ps1` scripts already send, no discrepancy found, no
  code change required. Closed both siblings' carried-forward VERIFYs: `README.md` §11 (both
  scenarios), the `.NOTES` block in both `deploy/New-PiiOnlyScanRuleset.ps1` scripts, and each
  README's closing "VERIFYs remain open" summary paragraph.
- [x] This closes the last item in this repo's "apply the PII-only custom scan rule set pattern to
  Data Map source type X" follow-up chain - all four Data Map source types with a base scan
  scenario in this repo (Azure SQL Database, Azure Synapse Analytics, Azure SQL Managed Instance,
  on-premises SQL Server) now have a PII-only companion scenario. No further fragment of this exact
  shape remains to pick up; a future Data Map source type (e.g. a new connector Microsoft ships) that
  gets a base scan scenario added to this repo would be the next natural candidate for the same
  pattern, but none is currently tracked.

### Follow-ups discovered while building the Defender for Endpoint device control macOS Apple/Portable vendorId/productId compound-matching scenario
- [x] RE-SCOPED, NOT BUILT (2026-09-26, commit `dd02495`): investigated building the Apple/Portable
  `ApprovedAppleDevices`/`ApprovedPortableDevices` group + its `Allow-Approved*Devices` rule from a
  zero-`serialNumber` starting state. Grounding found this is not a one-line guard relaxation:
  Microsoft's own `device_control_policy_schema.json` (same `microsoft/mdatp-devicecontrol` GitHub
  repo this fragment's other citations use) declares a group's `query.clauses` array
  `"minItems": 1` - an empty Approved group is schema-invalid, not merely unbuilt, and none of
  Microsoft's own sample policies use a zero-clause group either. A correct implementation needs
  the group to always carry at least one clause from *either* matching mechanism (serialNumber
  or vendorId/productId), which means a real fix is a cross-fragment ownership/sequencing redesign
  (whichever script runs first creates the group, conditioned on the combined device count across
  both fragments) - not the simple "relax `-gt 0`" fix originally imagined. Documented this finding
  in `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/design.md`
  §3 and `README.md` §11 rather than attempting an implementation against a design that would
  produce an invalid policy. **Still not built - a future fragment doing the real ownership
  redesign remains open, now correctly scoped instead of vaguely described.**
- [ ] Consider backporting an ordering-hazard-awareness change into
  `defender-device-control-usb-allowlist-macos-portable-device-coverage/deploy/
  Add-MacPortableDeviceCoverage.ps1` itself (e.g. preserving any `groupId` clause it doesn't own
  when rebuilding `ApprovedAppleDevices`/`ApprovedPortableDevices`, the same "preserve, don't
  blind-rebuild" fix that would also close this fragment's own disclosed ordering hazard at the
  root) - deliberately not attempted in this build, the same "don't reopen an already-reviewed
  foundational script for an optional extension's benefit" reasoning the Bluetooth allowlist
  fragment's own `design.md` §8 already applied to its own analogous, less severe hazard. Re-open if
  a future, unrelated reason to revise that script's own reconcile logic ever comes up.
- [x] Extend the Bluetooth family's own single-device `vendorId`/`productId` allowlist
  (`defender-device-control-usb-allowlist-macos-bluetooth-allowlist/`) to multi-device using this
  fragment's now twice-proven per-device sub-group + deterministic-UUIDv5 + `groupId`-clause
  technique - **built** (see DONE below, 2026-09-25): shipped as v2 of that scenario in place,
  reusing this exact technique (the family-scoped hash-input pattern this item anticipated was
  indeed directly reusable without modification).

### Follow-ups discovered while building the Priority Cleanup SharePoint/OneDrive scenario
- [ ] VERIFY (pilot tenant): whether the label's `-MultiStageReviewProperty` for this workload
  needs a `PriorityCleanupAdmin` stage entry in addition to the `EDiscoveryAdmin` stage this
  scenario's config uses, for the documented pre-turn-on "second Priority Cleanup Admin reviews
  simulation and turns the policy on" check to register correctly - no Microsoft worked example
  ties this parameter to priority cleanup for SharePoint/OneDrive specifically. Flagged inline in
  `priority-cleanup-sharepoint-onedrive/design.md` §4, `README.md` §6/§11, and the config's
  `_labelNote` rather than guessed.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether the Exchange-specific KeyQL
  exclusions (`SenderAuthor`, `SubjectTitle`, `(c:c)`, `(c:s)` unsupported in a priority cleanup
  `ContentMatchQuery`) also apply to SharePoint/OneDrive priority cleanup queries - Microsoft's
  SharePoint/OneDrive-specific page neither repeats nor contradicts that Exchange-page-only list.
  `priority-cleanup-sharepoint-onedrive/README.md` §11.
- [ ] Consider a small scheduled-task helper script that periodically reviews/re-simulates a
  continual priority-cleanup rule's query - the KeyQL surface this scenario grounds has no
  confirmed relative-date ("older than N days") operator, so a "stale content" query as documented
  here matches ALL matching content indefinitely, not just old items, unless an admin manually
  narrows it on a cadence. Explicitly deferred as a distinct fragment in
  `priority-cleanup-sharepoint-onedrive/design.md` §7 rather than bolted onto that scenario's
  one-shot create-or-report deploy script.
- [ ] Once a documented PowerShell/Graph cmdlet exists for the priority-cleanup tenant-wide on/off
  toggle (shared by both the Exchange and SharePoint/OneDrive scenarios - same open gap noted
  under the Exchange sibling's own follow-ups above), extend both scenarios' scripts to cover it.

### Follow-ups discovered while building the Exchange PII exfil Part 2 (elevated-risk compensating control) scenario
- [ ] VERIFY (pilot tenant): rule priority compaction behavior - same undocumented
  auto-shift-on-collision question already open for the Teams sibling fragment, applied here to
  `deploy/New-ExchangePiiElevatedRiskBlock.ps1`'s name-agnostic compaction algorithm (design.md §6).
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): no single Microsoft-published example
  validates the exact end-to-end composition this fragment designs (named DLP policy High-severity
  alerts → Data-leaks direct trigger → Cumulative exfiltration scoring → Adaptive Protection → a
  rule on that same named policy) - see `design.md` §6b.
- [ ] Consider whether `scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion` should
  offer a documented, opt-in way to raise its rule to `-ReportSeverityLevel High` specifically when
  an organization also deploys this Part 2 fragment, closing the exception-group-in-Encrypt-mode blind spot
  this build's Red Team review surfaced (`exchange-pii-exfil-block-part2-obfuscation-mitigation/
  README.md` §11) - not built this run since it would require touching a different, already-shipped
  scenario's default rather than staying scoped to this fragment.
- [ ] Once the Teams sibling fragment's own open VERIFY items (design.md §6b composition validation,
  pilot-tenant priority-reordering confirmation) are resolved against a real tenant, re-run the
  equivalent pilot-tenant checks for this fragment too - the two fragments share the same class of
  unconfirmed end-to-end behavior but are independent deployments and could resolve on different
  timelines.

### Follow-ups discovered while building the Unified Catalog manage-okrs scenario
- [ ] VERIFY (pilot tenant): whether the `Okr - Update`/`Okr - Create` `additionalProperties`
  request-field shape inconsistency (an object of computed roll-up fields on Create/Get vs. an
  `OkrSharedEntityStatus` enum on Update, per Microsoft's own REST reference pages for the same
  field name on the same resource) is a documentation defect or reflects two genuinely different
  server-side behaviors. `manage-okrs/deploy/New-Okr.ps1` never sends this field on either call -
  design.md §6 - so this is not blocking, but the underlying discrepancy is unresolved.
- [ ] VERIFY (pilot tenant): whether a key result's own `domainId` is validated against its parent
  objective's `domain`, silently ignored, or independently enforced - `manage-okrs/design.md` §5.
- [ ] VERIFY (pilot tenant): the `assetId`-omission question already open for
  `manage-data-products`' own `DATAASSET`/`TERM` relationship calls, now also open for this
  scenario's `entityType=OBJECTIVE` call to the same `Data Products - Create Relationship`
  operation - `manage-okrs/README.md` §11.
- [ ] Once Microsoft documents a portal action or REST caller for `entityType=KEYRESULT` on the
  Data Products relationship operations (a documented enum value with no discoverable portal
  action as of this build), extend `manage-okrs` to script it - `design.md` §4/§7.
- [x] Consider a small scheduled companion script that re-runs `validate/Test-Okr.ps1` on a cadence
  and diffs its output against a prior run, as the only unattended staleness-detection workaround
  for a key result's `progress` value (`manage-okrs/README.md` §8, Blue Team finding 2 in
  `reviews.md`) - not built this run to keep this fragment scoped to the create/link capability
  `PROGRESS.md` asked for. **Built** (see DONE below): `deploy/Export-OkrProgressTrend.ps1` +
  `validate/Test-OkrProgressTrend.ps1` - a structured run-over-run progress/status diff, not a
  literal text-diff of `Test-Okr.ps1`'s own console output (design.md §8 explains why).

### Follow-ups discovered while building the Priority Cleanup Permanent Deletion scenario
- [ ] VERIFY (pilot tenant): whether a policy provisioned via
  `priority-cleanup-permanent-deletion/deploy/New-PriorityCleanupPermanentDeletionPolicy.ps1` (the
  shared `-PriorityCleanup` label/policy/rule shape) is a valid starting point for the Purview
  portal's "Choose what to do with the content > Delete data permanently" wizard step, or whether
  permanent-deletion policies must be created end-to-end through the portal wizard instead -
  `design.md` §4 states both readings as open; neither is confirmed by Microsoft's published
  documentation.
- [ ] VERIFY (pilot tenant, or a future Microsoft Learn pass): current permanent-deletion
  availability by cloud environment. This build's own date (2026-09-09) is after the cited
  2026-08-24 Worldwide multi-tenant public-preview rollout start, but GCC/GCC High/DoD timing is
  not stated on the official Learn page this scenario cites - `README.md` §11 flags this rather
  than assuming parity with Worldwide multi-tenant.
- [ ] Once Microsoft publishes a PowerShell/Graph parameter or worked example for selecting
  "Delete data permanently" (closing this scenario's central disclosed gap - `design.md` §4), script
  it directly in `New-PriorityCleanupPermanentDeletionPolicy.ps1` instead of the current
  print-and-stop manual step, and add a matching read-back check to `validate/
  Test-PriorityCleanupPermanentDeletionPolicy.ps1`.
- [ ] Consider a companion scenario chaining eDiscovery search-and-purge (soft-delete) with either
  priority-cleanup workload, matching Microsoft's own documented workflow for avoiding the
  end-user-visible "Retention: ... (-1 days)" message bar in Outlook - same deferral already tracked
  under the Priority Cleanup Exchange data-spillage follow-ups above (not duplicated here; both
  priority-cleanup scenarios could eventually chain to it once it exists).

### Follow-ups discovered while building the Conditional Access step-up-auth scenario
- [ ] VERIFY (pilot tenant, before production reliance): whether a user who has already accepted
  the Moderate policy's Terms of Use agreement's current version is re-prompted on every
  subsequent sign-in the policy evaluates, or only once per acceptance/version. Not independently
  confirmed during this build - flagged inline in
  `conditional-access-insider-risk-step-up-auth/README.md` §11.
- [ ] VERIFY (pilot tenant): whether Entra sign-in logs distinguish a "Terms of Use declined"
  outcome from a "Terms of Use pending/not yet presented" outcome for this scenario's Moderate
  policy specifically - relevant for the help-desk runbook in `README.md` §8 when triaging a user
  who reports being unable to complete sign-in. Not independently confirmed during this build.
- [ ] Consider scripting Microsoft's additional documented "exclude guests/external users" nested
  Users condition for this scenario's two policies once the shared open item on this (tracked
  under the Conditional Access insider-risk-block follow-ups above) is resolved - same deferred
  shape, not duplicated here.
- [ ] Once a documented Graph endpoint or PowerShell cmdlet exists that supports **application**
  (app-only) permissions for Terms of Use agreement creation (`identityGovernance/termsOfUse/
  agreements`, currently delegated-permission-only per the `Create agreement` reference), extend
  `deploy/New-InsiderRiskStepUpPolicies.ps1` to optionally create the agreement itself instead of
  requiring a pre-created `-AgreementId` - closing the one genuine automation gap this scenario's
  `design.md` §2/§7 discloses rather than works around.

### Follow-ups discovered while building the Direct Send and Anonymous Relay Hardening scenario
- [x] VERIFY (Microsoft Learn or a pilot tenant, before a customer-facing commitment): the exact
  default value, rollout wave, and full behavioral description of `Set-OrganizationConfig
  -RejectDirectSend` - **grounded 2026-09-26, partially resolved** (see DONE below): Microsoft Learn's
  `Set-OrganizationConfig` reference page now publishes a full descriptive paragraph for this
  parameter (it apparently didn't at original build time) - `$true` blocks Direct Send only when the
  sender matches no inbound connector *and* the `MAIL FROM` domain is an accepted domain, `$false`
  doesn't block it. The **default value** (still listed as `None`, not `$true`/`$false`) and any
  rollout wave/date for Microsoft's stated plan to disable Direct Send by default remain
  unpublished - re-open only if Microsoft documents either. `direct-send-anonymous-relay-hardening/
  README.md` §11, `design.md` §9, and `reviews.md`'s Microsoft Product Owner lens corrected in place.
- [ ] Once the exact `Search-UnifiedAuditLog` `RecordType`/`Operations` values for a rejected Direct
  Send attempt are grounded, add a dedicated `Export-*` companion script to
  `scenarios/adaptive-protection/direct-send-anonymous-relay-hardening/deploy/` - same class of
  event-level gap this library's `exchange-legacy-auth-block` sibling already discloses for SMTP
  AUTH rejections (`reviews.md` Blue Team finding 2).
- [ ] The `techcommunity.microsoft.com` "What is Direct Send and how to secure it" Exchange Team
  blog post (referenced by name in a Microsoft Q&A accepted answer) returned a fetch error from this
  build's network environment - re-fetch it in a future pass and cross-check it against this
  scenario's README/design for any additional detail not present in the Microsoft Learn reference
  pages this build used instead (`README.md` §11).
- [ ] Consider extending the connector risk audit to also flag `InboundConnector` objects with
  neither `-RestrictDomainsToIPAddresses` nor `-RestrictDomainsToCertificate` set (i.e. connectors
  authenticating by neither mechanism, if that combination is even possible/meaningful) - not
  investigated this build; the current heuristic only scores IP-based connectors that are already
  IP-restricted.

### Follow-ups discovered while building the Communication Compliance financial-regulatory-supervision scenario
- [ ] Third-party financial messaging connectors (Bloomberg Message/Mail, ICE Chat, Reuters Eikon
  Messenger, Symphony, and the other Microsoft-documented native data connectors for Communication
  Compliance) - explicitly out of scope for this scenario (`design.md` §7); each connector has its own
  distinct setup workflow and deserves its own scoped fragment. Candidate name:
  `scenarios/communication-compliance/financial-connector-onboarding/` or split per connector.
- [ ] An HR/registration-connector-style reconciliation script deriving/reconciling the firm's
  FINRA-registered-representative population (this scenario's `usersInScope` group) against the
  firm's own broker-dealer registration system (e.g. FINRA BrokerCheck/CRD) - explicitly out of scope
  this build (`design.md` §7); the same class of gap `scenarios/insider-risk/
  departing-employee-data-theft/`'s own HR-connector follow-up tracks for a different population.
- [ ] The built-in **"Detect conflict of interest"** Communication Compliance policy template, as its
  own standalone scenario - deferred as a non-goal in `financial-regulatory-supervision/design.md` §5/
  §7 pending confirmation of its exact classifier bundling (see the VERIFY item below).
- [ ] A preventive DLP companion scoped to a firm's actual restricted-list/watch-list tickers (real-time
  blocking, not just detective review) - deferred as a non-goal in `financial-regulatory-supervision/
  design.md` §7; natural complement to `scenarios/information-barriers/segregate-trading-and-research/`.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): whether Microsoft's built-in "Detect
  financial regulatory compliance" and "Detect conflict of interest" policy templates bundle Corporate
  sabotage, Customer complaints, Gifts & entertainment, Money laundering, [Workplace/Regulatory]
  collusion, Stock manipulation, and Unauthorized disclosure identically to how
  `financial-regulatory-supervision`'s custom policy selects all seven explicitly - this build's
  WebSearch-only grounding (no direct `learn.microsoft.com` fetch available) could not confirm the
  per-template classifier split. `financial-regulatory-supervision/design.md` §5/§8 and `README.md`
  §11 flag this rather than guessing.
- [ ] VERIFY (pilot tenant or a future Microsoft Learn pass): the current portal-UI label for the
  collusion-related Regulatory-compliance classifier - this build's WebSearch-only grounding found it
  referred to as both "Regulatory collusion" and "Workplace collusion" across independent secondary
  sources, without a direct canonical-page fetch to resolve which is current. `financial-regulatory-
  supervision/README.md` §11, `design.md` §5, and the deploy manifest all flag this rather than
  picking one silently.
- [ ] VERIFY (pilot tenant): the exact `AuditData` JSON property name Microsoft populates with the
  remediation action taken on a `SupervisoryReviewTag` event. `financial-regulatory-supervision/
  deploy/Export-FinraSupervisionEvidence.ps1` tries a short list of plausible candidate property names
  (`$actionPropertyCandidates`) and falls back to pointing at the row's own raw `AuditData` rather than
  guessing - update that list once the real property name is confirmed. `README.md` §11 and the
  script's own `.NOTES`/`validate/Test-FinraSupervisionEvidence.ps1` both flag this as an open item.

### Follow-ups discovered while building the Audit continuous-streaming-to-a-SIEM scenario
- [ ] Land Path B's NDJSON output (specifically the `DLP.All`/`Audit.AzureActiveDirectory` coverage
  Path A's native Sentinel connector doesn't carry) into Sentinel itself via the **Log Analytics
  Logs Ingestion API** + a Data Collection Rule/custom table - deliberately not built in this
  fragment (`streaming-to-sentinel-or-management-api/design.md` §7, a documented non-goal): it needs
  a Data Collection Endpoint/Rule and a destination-table-schema decision (custom table vs. Auxiliary
  Logs) that belongs in a dedicated follow-up once a concrete organization target is chosen.
- [ ] Consider a dedicated **Microsoft Purview Information Protection (Preview)** Sentinel-connector
  scenario - noted only for disambiguation in `streaming-to-sentinel-or-management-api/design.md` §3
  and `README.md` §11 (a different connector, different destination table
  `MicrosoftPurviewInformationProtection`, label/protection-event-specific, with documented
  duplication against `OfficeActivity` and unpopulated label names) - not built here.
- [ ] VERIFY (pilot tenant): the exact naming contract for a `Microsoft.SecurityInsights/
  dataConnectors` resource of `kind: Office365` - Microsoft's ARM/Bicep reference page for this kind
  doesn't state whether `name` must be a GUID (as several other connector kinds' samples use) or
  accepts an arbitrary string. `streaming-to-sentinel-or-management-api/deploy/
  office365-connector.bicep` defaults to a deterministic `guid()`-derived name so re-deployments
  target the same resource regardless of the answer, flagged inline in the template's header comment
  and `README.md` §11.
- [ ] VERIFY (pilot tenant): the exact wall-clock enforcement of the Office 365 Management Activity
  API's 15-minute cooldown between `/subscriptions/start` calls for the same content type - whether
  it's measured from the previous call regardless of outcome, or only from a successful one.
  `deploy/Enable-ManagementActivitySubscriptions.ps1` sidesteps the ambiguity (skips `/start`
  whenever `/subscriptions/list` already shows `enabled`) rather than resolving it - see the script's
  `.NOTES` and `README.md` §11.
- [ ] Consider an **incident-response (mutating) companion** scenario wired to Path B's `DLP.All`/
  `Audit.AzureActiveDirectory` stream (auto-disable account, revoke sessions on a detected pattern) -
  the same deliberate non-goal already tracked above for `premium-audit-investigation`, now with a
  continuous trigger source available once this scenario's pipeline is deployed.

## DONE
- [x] **Closed the `disposition-proof-export` RecordType VERIFY** - commit `a0221c5` - 2026-09-26.
  Maintenance pass: closed the open VERIFY asking whether Graph's `RecordsManagement` or
  `MultiStageDisposition` `auditLogRecordType` member is the correct narrower `-RecordType` for the
  seven disposition/record-deletion Operations this scenario's `Search-UnifiedAuditLog` query
  covers. Grounded via a full-page fetch of the Office 365 Management Activity API schema's
  `AuditLogRecordType` enum table - the value source `-RecordType`'s own documentation points to -
  which contains neither member name anywhere on the page; both are members only of the separate
  Graph `microsoft.graph.security.auditLogRecordType` enum, not valid input for this Exchange
  PowerShell cmdlet at all. This confirms (rather than merely leaves as an unconfirmed guess-
  avoidance) that omitting `-RecordType` from the query is correct. Updated `deploy/
  Export-DispositionProofEvidence.ps1` (`.DESCRIPTION` and `.NOTES`), `design.md` §2 item 3,
  `README.md` §6/§11/§12, and `reviews.md` (Microsoft Product Owner addendum). No code behavior
  changed - the script already omitted `-RecordType`. This scenario's separate, still-open VERIFYs
  (the `AuditData` label-property name and the manual-vs-autoapproval distinguishing field) are
  untouched by this pass.
- [x] **Ground RejectDirectSend behavioral description (direct-send-anonymous-relay-hardening)** -
  commit `cab808b` - 2026-09-26. Maintenance pass: closed the open VERIFY on
  `Set-OrganizationConfig -RejectDirectSend`'s behavior by re-fetching its Microsoft Learn
  reference page, which now carries a full descriptive paragraph the original build didn't find.
  Confirmed `$true` blocks Direct Send only when the sender matches no inbound connector and the
  `MAIL FROM` domain is an accepted domain; `$false` doesn't block it. Corrected `README.md` §11,
  `design.md` §9, and `reviews.md`'s Microsoft Product Owner lens in place. The parameter's default
  value (still `None` on the reference page) and any rollout date for Microsoft's stated
  default-disable plan remain genuinely unpublished and are left disclosed, not guessed.
- [x] **Repo-wide em/en dash to plain hyphen rewrite** - commit `0654d66` - 2026-09-26. User-directed
  pass ahead of publishing: no long dashes anywhere, cleaner plain-text presentation. Replaced every
  em dash (18,727 occurrences) and en dash (278 occurrences, mostly numeric/section ranges like
  "Steps 1-4") with a plain hyphen across all 452 files that contained either character (every
  scenario's README/design/reviews/rollback.md, docs/*.md, docs/homepage.html, AGENTS.md, README.md,
  and PROGRESS.md itself). Pure glyph substitution, not a rewording - verified the diff is exactly
  balanced (17,720 insertions / 17,720 deletions, meaning every changed line is a like-for-like
  character swap, nothing added/removed/restructured) and zero em/en dashes remain anywhere in the
  repo. No code files were touched since none contained either character.
- [x] **Repo-wide "buyer" -> "organization" terminology rewrite** - commit `9010a44` (merged at
  `a5fbec8`) - 2026-09-26. User-directed pass ahead of publishing the repo publicly (see this
  session's decision log): the MIT/public pivot (§10, 2026-09-25) updated the README, homepage,
  LICENSE, and CONTRIBUTING to free/open framing but explicitly left scenario content alone,
  leaving "buyer" language (518 occurrences, 202 markdown files, plus comment-based help in 35
  `.ps1`/`.json` files) scattered across every scenario. Replaced with grammar-aware substitutions
  (not a blind find-replace): "a buyer" -> "an organization", "the buyer" -> "the deploying
  organization", "buyer's"/"buyers" -> "organization's"/"organizations", "buyer-X" hyphenated
  adjectives -> "organization-X", "buyer(s) who" -> "organization(s) that" (organizations aren't
  people). Also applied to this file's own still-open TODO section for consistency; deliberately
  left the DONE section and one Blocked/needs-user historical note untouched, since those describe
  what was actually decided/reviewed at past dates and rewriting them would misrepresent the
  record. Verified zero remaining "buyer" occurrences outside that history, all touched JSON files
  still parse, and no code identifiers (only prose/comments) were affected. Pure terminology
  cleanup - no scenario behavior, facts, or grounding changed.
- [x] **Closed the `scan-on-premises-sql-server-and-classify` system scan rule set name VERIFY** -
  commit `76976c0` - 2026-09-26. Maintenance fragment: grounded the previously-unconfirmed
  `-ScanRulesetName` default (`'SqlServerDatabase'`, `scanRulesetType: 'System'`) against the
  Microsoft Learn "System Scan Rulesets - Get" REST reference, whose own worked example
  (`kind: "AzureStorage"` → `name: "AzureStorage"`) directly confirms a system scan ruleset's `name`
  always equals its `kind`. Updated `README.md` (§6, §11, §12), `design.md` (§4, §5, §7), the deploy
  script's `.PARAMETER ScanRulesetName`/`.NOTES` blocks, and `reviews.md` (addendum) from VERIFY to
  confirmed. The scenario's separate Windows Authentication `CredentialType` VERIFY is untouched.
- [x] **Re-scoped (not built) the Apple/Portable zero-`serialNumber` Approved-group follow-up with a
  concrete schema-validity finding** - commit `dd02495` - 2026-09-26. Sub-task fragment:
  investigated the open backlog item asking to remove the "at least one `serialNumber` device
  first" prerequisite on
  `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching`. Grounding
  (Microsoft's own `device_control_policy_schema.json` in the `microsoft/mdatp-devicecontrol`
  GitHub repo) found a device-control group's `query.clauses` array is schema-constrained to
  `minItems: 1` - so an empty `ApprovedAppleDevices`/`ApprovedPortableDevices` group is invalid,
  not just unbuilt, and the fix originally imagined (relaxing a `-gt 0` guard in the prerequisite
  fragment's script) would produce a policy that fails Microsoft's own validation tooling. Recorded
  this finding and the real fix's actual shape (a cross-fragment group-ownership/sequencing
  redesign) in the vendor-product-matching fragment's `design.md` §3 and `README.md` §11. Not
  built - re-scoped correctly for whoever picks it up next, per this repo's "ground the fact, then
  build correctly or document the honest gap" discipline (`AGENTS.md` §4).
- [x] **Backported the server-scoped-vs-per-database `CREATE LOGIN` correction into
  `scan-azure-synapse-and-classify`** - commit `165d740` - 2026-09-25. Sub-task fragment: the
  sibling `bulk-grant-synapse-serverless-access` scenario's own grounding pass had found, via two
  directly-fetched Microsoft Learn pages, that the serverless enumeration login
  (`CREATE LOGIN ... FROM EXTERNAL PROVIDER`) is a server-scoped statement run once against
  `master` - not a per-database step, despite Microsoft's portal walkthrough appearing to repeat
  it because Synapse Studio's script entry point is reached from inside a database's own context.
  That correction was deliberately left unbackported at the time (one fragment per turn). This
  fragment ported it into the base scenario's `README.md` (prerequisites table, §5 step 3c,
  §8 incident-response cause and review cadence - the latter two previously implied a database
  restore/recreate could drop the login itself, corrected to attribute that risk only to the
  genuinely per-database `CREATE USER`/`db_datareader` grant) and `design.md` (§4 comparison
  table). Pure documentation correction - no scan behavior or script logic changed (the scenario's
  scripts never scripted this manual portal step in the first place).
- [x] **Fixed drifted "surface N" citations across the repo (automation-surface.md renumbering
  cleanup)** - commit `443aa7c` - 2026-09-25. Sub-task fragment: `docs/automation-surface.md` was
  renumbered at some point (Exchange Online PowerShell=1, Security & Compliance PowerShell=2,
  unified Microsoft Graph=3, Purview Data Map/Data Governance REST=4, SharePoint Online Management
  Shell=5) but two scenarios' docs/scripts still cited the old numbering. Ran a repo-wide grep for
  every "surface N" citation in `README.md`/`design.md`/`deploy/*.ps1` and cross-checked each
  against the current table. Fixed: `regulatory-records-disposition/README.md` §3 and
  `deploy/New-RecordsDisposition.ps1` `.NOTES` (both "surface 1" → "surface 2");
  `graph-event-automation/README.md` §1 and §3 (both an incorrect "surface 2/surface 2-and-3" split
  that pre-dated the unified single-Graph-surface numbering → "surface 3"). Confirmed
  `retention-labels-financial-records/README.md` (the item's third named file) was already correct.
  No other drift found in the remaining ~40 "surface N" citations across the rest of the repo - all
  already match. Pure documentation correction, no scenario behavior changed.
- [x] **Backported Scanning data-plane operation groups (Credential, Key Vault Connections, Scan
  Rulesets, Triggers) into `docs/automation-surface.md` and `docs/rbac-model.md`** - commit
  `4f041bb` - 2026-09-25. Sub-task fragment closing a cross-cutting follow-up left open since the
  `scan-credential-key-vault-backed` scenario shipped: the shared docs never caught up with what
  that scenario (and the later `scan-credential-remaining-kinds`/`*-pii-ruleset` scenarios) had
  already grounded. `automation-surface.md` §4's single Data Map REST row is now split: the
  original row keeps data source/scan/collection registration (path corrected to include the
  missing `/scan/` segment, confirmed against `scan-azure-sql-and-classify`'s own script), and a
  new row documents the Credential, Key Vault Connections, Scan Rulesets, and Triggers operation
  groups with their exact REST paths, citing this build's own direct-fetched Scan Rulesets
  reference page and the worked scenarios. `rbac-model.md` §5 gained a new paragraph making the
  Data Source Administrator-by-analogy assumption for Credential/Key Vault Connection creation
  explicit and flagged **VERIFY (pilot tenant)** - the analogy itself is not newly confirmed, only
  now stated instead of left undocumented - plus a confirmed, non-VERIFY fact that Scan Ruleset
  objects are account-wide with no collection role applying at all (grounded via this build's own
  direct REST schema fetch showing no `collection` property). No scenario code changed; pure
  cross-cutting documentation backport, per AGENTS.md §6 ("one clearly-scoped sub-task from the
  backlog").
- [x] **Re-verified Synapse/Managed Instance PII-ruleset REST body shapes against direct
  `learn.microsoft.com` access** - commit `3abedf3` - 2026-09-25. Sub-task fragment (not a new
  scenario) closing a low-priority follow-up: with `learn.microsoft.com` directly reachable via the
  Microsoft Learn MCP tool in this build, fetched
  `https://learn.microsoft.com/rest/api/purview/scanningdataplane/scan-rulesets/create-or-replace`
  (api-version `2023-09-01`) in full and confirmed it documents both
  `AzureSqlDatabaseManagedInstanceScanRulesetProperties` and `AzureSynapseWorkspaceScanRulesetProperties`
  directly - each with exactly `createdAt` (read-only), `description`,
  `excludedSystemClassifications` (`string[]`), `includedCustomClassificationRuleNames` (`string[]`),
  `lastModifiedAt` (read-only) - matching, with no discrepancy, what
  `scan-azure-sql-managed-instance-and-classify-pii-ruleset/deploy/New-PiiOnlyScanRuleset.ps1` and
  `scan-azure-synapse-and-classify-pii-ruleset/deploy/New-PiiOnlyScanRuleset.ps1` already send
  (`kind`/`scanRulesetType`/`properties.description`/`.excludedSystemClassifications`/
  `.includedCustomClassificationRuleNames`). No code change required in either script - this was a
  citation-strength upgrade, not a bug fix. Updated both scenarios' `README.md` §11 (VERIFY →
  RESOLVED, with the direct REST reference link replacing the `raw.githubusercontent.com`-only
  citation) and closing summary paragraph, and both `deploy/New-PiiOnlyScanRuleset.ps1` `.NOTES`
  blocks. Continues this repo's established pattern (see the Synapse `resourceTypes` self-correction
  in an earlier DONE entry) of treating Microsoft Learn access as environment-dependent and
  re-verifying citations opportunistically when access is confirmed, rather than assuming an earlier
  build's access restriction still holds.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/` (v2:
  multi-device)** - commit `1cc566e` - 2026-09-25. Generalized the scenario's approved-Bluetooth-
  device support from exactly 0-or-1 device (v1) to any number of devices (v2), in place rather than
  as a separate sibling scenario. Ported the per-device sub-group + `groupId`-clause-nesting
  technique (parent group `$type: "or"`, clauses referencing per-device `$type: "and"` sub-groups,
  each with a deterministic RFC 4122 v5 UUID derived from its `vendorId:productId` pair) from
  `defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`, which had
  independently built and four-lens-reviewed the identical technique for the same AND-then-OR
  problem after this scenario's v1 shipped - confirmed by direct code read
  (`Get-DeterministicSubGroupId`, byte-for-byte identical algorithm, new namespace constant) rather
  than re-derived from scratch. The rule-level mechanics (`Allow-ApprovedBluetoothDevice`'s
  `includeGroups`, `Deny-AllBluetoothDevices`'s `excludeGroups`) needed no change at all, since both
  already referenced only the parent group's id - only the parent group's own internal shape moved
  from a flat single-device AND-group to an OR-group of sub-groups. Updated
  `deploy/Add-MacBluetoothDeviceAllowlist.ps1`, `deploy/Remove-MacBluetoothDeviceAllowlist.ps1`,
  `validate/Test-MacBluetoothDeviceAllowlist.ps1`, the config sample (now shows 2 devices),
  `README.md`, `design.md` (new §5 "v1's deferral and v2's resolution" history), and `reviews.md`
  (new targeted four-lens follow-up round confirming: the OR-group-from-scratch pattern is already
  proven elsewhere in this repo's own `portable-device-coverage` script, not a new risk; the
  validate script's per-device matching can't false-PASS via label-prefix collision; no new residual
  risk category; the ported UUID-derivation function is a verified byte-for-byte port). Old v1
  single-device state upgrades automatically on the next reconcile run (the fixed parent-group GUID
  is unchanged across v1/v2, and the deploy script recognizes and rebuilds a legacy `and`-shaped
  parent group). No new Microsoft Learn grounding needed - pure reuse of an already-grounded,
  already-reviewed sibling technique.
- [x] **`scenarios/data-lifecycle-management/retention-labels-financial-records/` /
  `scenarios/records-management/file-plan-bulk-import/` (cross-link correction)** - commit `4756040`
  - 2026-09-25. A backlog item asking for file plan descriptors and bulk label creation as a
  follow-up to `retention-labels-financial-records` turned out to already be fully built -
  `scenarios/records-management/file-plan-bulk-import/` (commit `b17faf9`, 2026-09-15) - just never
  cross-linked back. Corrected `retention-labels-financial-records/design.md` §7's stale "out of
  scope for the starter" non-goal bullet to point at the resolving scenario, and added a reciprocal
  "how it differs from" paragraph to `file-plan-bulk-import/README.md` §1. No new scenario or code
  needed - a pure repo-consistency fix, the same "a new folder does not retract an old assertion"
  pattern this repo's four-lens reviews keep catching across sibling scenarios.
- [x] **`scenarios/communication-compliance/teams-viva-engage-content-safety/` (follow-up)** -
  commit `f750c21` - 2026-09-25. Closed the Red Team finding 1 follow-up from this scenario's own
  four-lens review: added `deploy/policy/short-form-crisis-threat-phrases.txt`, a ready-to-import
  compensating custom keyword dictionary targeting short-form self-harm-ideation and terse-threat
  phrasing that the classifier family's disclosed 3-or-5-word minimum can let through undetected -
  the same evasion-dictionary pattern `harassment-and-code-of-conduct/deploy/policy/
  code-of-conduct-evasion-phrases.txt` already established, content-disciplined the same way
  (clinical, non-graphic, illustrative rather than exhaustive, not a slur/profanity duplicate). Wired
  in as an explicitly **optional**, not-applied-by-default `customKeywordDictionaryOption` block in
  `content-safety-policy-manifest.json` (JSON validated), requiring both an explicit **Customize
  policy** action and HR/Legal reviewer review/extension before use - never silently applied to the
  scenario's default template-based deployment. `README.md` §5 step 7, §6 (new configuration-table
  row), and §8 updated to point at the concrete file instead of only describing the pattern
  conceptually; `design.md` §2 and `reviews.md` finding 1 updated to record the resolution. No new
  Microsoft Learn grounding needed - pure content/wiring work reusing an already-grounded pattern.
  Along the way, attempted to also ground and build the `-ResourceNames` scoping parameter follow-up
  recorded during the Synapse UAMI fragment, and a new Amazon S3 base scan scenario - both found to
  have genuine REST-schema ambiguities during grounding (conflicting `resourceTypes` key
  enumerations; `AmazonS3`'s two competing scan kinds each carrying both a direct `roleARN` field and
  a separate credential reference, with no worked example resolving which combination is correct) -
  neither built on the unresolved conflict; both corrected/recorded as accurate VERIFY items in
  `scan-azure-synapse-and-classify/README.md` §11 and `PROGRESS.md` respectively, per `AGENTS.md` §4.
- [x] **`scenarios/data-map/scan-azure-synapse-and-classify-managed-identity-credential/`** -
  commit `ecb2f26` - 2026-09-25. Full scenario (README.md, design.md,
  deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1,
  deploy/Remove-AzureSynapseManagedIdentityCredentialScan.ps1,
  validate/Test-AzureSynapseManagedIdentityCredentialScan.ps1, rollback.md, reviews.md) - the third
  and last sibling of the two Azure SQL `-managed-identity-credential` scenarios, wiring
  `scan-credential-remaining-kinds`'s `ManagedIdentity` (UAMI) credential kind into
  `scan-azure-synapse-and-classify`'s existing scan and closing that backlog item completely. Found
  the strongest direct grounding of the three siblings: a worked JSON example on the base scenario's
  own canonical `register-scan-synapse-workspace` page explicitly shows
  `"credentialType":"SqlAuth | ServicePrincipal | ManagedIdentity (if UAMI authentication)"` against
  `"kind":"AzureSynapseWorkspaceCredential"` - confirmed via the Microsoft Learn MCP tool, direct
  fetch of the exact page the base scenario is itself grounded against, not inferred from a separate
  generic "supported sources" list as both prior siblings had to be. Also direct-fetched
  `AzureSynapseWorkspaceCredentialScanProperties` and confirmed it carries no `databaseName`/
  `serverEndpoint` fields at all (both pool endpoints live on the data source object instead) - a
  genuine structural difference from both siblings, reflected correctly in the reconciliation script
  rather than copy-pasted. Four-lens review's two findings: (Red Team, Fix) the three-part serverless
  grant model's partial-grant failure mode was understated for this specific SAMI-to-UAMI transition,
  where an operator is most likely to grant Reader but forget the two serverless-specific grants -
  resolved by disclosure (no code fix possible, no Purview API exposes grant state); (Product Owner,
  Fix) the base scenario's own IAM/T-SQL grant-assignment step wording was initially cited as equally
  UAMI-confirmed as the core REST claim, when only the REST claim is page-confirmed - resolved by
  distinguishing the two explicitly and adding a new VERIFY. Also updated the base scenario's own
  README: closed its `resourceTypes` VERIFY with the newly-found worked example (without adopting the
  scoping behavior itself - tracked as a separate follow-up below) and corrected two more stale
  "portal-only credential" claims and a mislabeled scan-kind string, the same corrections both prior
  siblings' base scenarios already received. `scan-credential-remaining-kinds/README.md` §6/"Related
  scenarios" updated to mark all three siblings resolved.
- [x] **`scenarios/data-map/scan-azure-sql-managed-instance-and-classify-managed-identity-
  credential/`** - commit `6f38b57` - 2026-09-25. Full scenario (README.md, design.md,
  deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1,
  deploy/Remove-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1,
  validate/Test-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1, rollback.md, reviews.md) -
  the Managed Instance sibling of `scan-azure-sql-and-classify-managed-identity-credential/`, wiring
  `scan-credential-remaining-kinds`'s `ManagedIdentity` (UAMI) credential kind into
  `scan-azure-sql-managed-instance-and-classify`'s existing scan. Ported the Database sibling's
  reconciliation pattern and its own Red-Team-fixed credential-precheck severity split (hard stop on
  a confirmed kind mismatch, warn only on an ambiguous 404) from the first draft rather than
  reintroducing the pre-fix behavior. Grounded live via the Microsoft Learn MCP tool: direct-fetched
  `AzureSqlDatabaseManagedInstanceCredentialScanProperties` to confirm it is its own distinct schema
  (not assumed identical to the Database sibling's by naming convention) sharing the same field names
  and the same `CredentialType` enum. Four-lens review's one finding (Microsoft Product Owner, Fix):
  the draft had cited the Azure IAM Reader role-assignment portal walkthrough ("Select box accepts
  SAMI or UAMI") as equally page-confirmed for Managed Instance as for the Database sibling, when a
  targeted grounding pass found that exact wording only on the Database page - corrected to state
  plainly what's directly confirmed (UAMI is a supported identity; the permission requirement) versus
  mechanism-inferred (the click-path), flagged as a new VERIFY rather than silently assumed identical.
  Also fixed two more stale "portal-only credential" claims found in passing in
  `scan-azure-sql-managed-instance-and-classify/README.md` §6/§11 (the same correction already
  applied to the Database sibling on 2026-09-16, missed on this sibling until now) and updated
  `scan-credential-remaining-kinds/README.md` §6/"Related scenarios" to mark both Database and
  Managed Instance siblings resolved, Synapse still open.
- [x] **`scenarios/data-map/scan-azure-sql-and-classify-managed-identity-credential/`** - commit
  `5db4ab2` - 2026-09-25. Full scenario (README.md, design.md,
  deploy/New-AzureSqlManagedIdentityCredentialScan.ps1,
  deploy/Remove-AzureSqlManagedIdentityCredentialScan.ps1,
  validate/Test-AzureSqlManagedIdentityCredentialScan.ps1, rollback.md, reviews.md) wiring
  `scan-credential-remaining-kinds`'s `ManagedIdentity` (UAMI) credential kind into
  `scan-azure-sql-and-classify`'s existing scan as a per-source-scoped alternative to Purview's
  shared SAMI - the "most directly actionable" follow-up that scenario's own backlog entry
  identified. Reconciles (GET-then-PUT) the base scenario's already-registered scan from
  `AzureSqlDatabaseMsi` onto `AzureSqlDatabaseCredential` with `credential: { ManagedIdentity,
  <name> }`, preserving every other scan property unchanged - the same reconciliation idiom
  `scan-azure-sql-and-classify-pii-ruleset` established, applied to authentication instead of the
  scan rule set. Grounded live via the Microsoft Learn MCP tool (available this run): direct-fetched
  the Scans - Create Or Replace REST reference to confirm `CredentialType`'s enum includes
  `ManagedIdentity` alongside `SqlAuth`/`ServicePrincipal`, and the "Configure authentication for a
  scan" page's Managed identity tab for the UAMI-specific T-SQL grant/Azure IAM Reader steps (a
  different principal than the base scenario's SAMI grant, same grant pattern). Four-lens review
  resolved two real findings: (Red Team) a confirmed credential-kind mismatch on
  `-CredentialReferenceName` was originally only a `[WARN]`, the same severity as an ambiguous 404 -
  fixed by hard-stopping (unless `-Force`) on the deterministic case while leaving the genuinely
  ambiguous 404 case as a warning; (Product Owner, Fail) `scan-credential-remaining-kinds/README.md`
  §6 and `scan-azure-sql-and-classify/README.md` §6 both still asserted this wiring was "not built
  here" - corrected in place with bidirectional cross-links, the same stale-claim pattern this
  repo's reviews keep catching across sibling scenarios. Two new follow-ups recorded above rather
  than resolved by guessing: the same UAMI wiring for the Azure SQL Managed Instance and Azure
  Synapse siblings (not blocked on anything, just not yet built), and the three source types
  (`AmazonARN`/`ConsumerKeyAuth`/`DelegatedAuth`) that still have no base scan scenario at all.
- [x] **`scenarios/data-map/scan-credential-remaining-kinds/` (follow-up fix)** - commit `232dc37` -
  2026-09-16. Closed the Blue Team finding 2 follow-up from this scenario's own four-lens review:
  made `validate/Test-PurviewScanCredentialExtended.ps1`'s `-CheckKeyVaultSecret` Azure Key Vault
  name derivation authoritative instead of assuming the Purview Key Vault connection name equals the
  vault's own name. Added a `Get-KeyVaultNameForConnection` helper that duplicates the parent
  scenario (`scan-credential-key-vault-backed`)'s `Test-PurviewScanCredential.ps1` check-1 sequence
  exactly - `GET /scan/azureKeyVaults/{connectionName}`, then derive the vault name from the response
  `properties.baseUrl` - cached per connection name (`$script:KeyVaultConnectionCache`) so
  `ConsumerKeyAuth`'s two independent secret references only trigger one GET each when they share a
  connection. `Test-KeyVaultSecretReference` gained `-Endpoint`/`-Token`/`-ApiVersion` parameters to
  support the lookup; all four call sites (`AccountKey`, `ConsumerKeyAuth` x2, `DelegatedAuth`)
  updated. If the connection can't be found or carries no `baseUrl`, the check now skips with an
  explicit `[WARN]` naming the connection rather than guessing. No Purview REST surface change beyond
  reusing the already-grounded Key Vault Connections - Get endpoint
  (https://learn.microsoft.com/rest/api/purview/scanningdataplane/key-vault-connections), which the
  parent scenario's script already cites and calls for the identical purpose - no new grounding
  needed. Updated `reviews.md` (Blue Team finding 2's Resolution, the round-summary table, and the
  carried-forward-follow-ups paragraph) and `README.md` §7 to describe the new behavior; `design.md`
  required no change (it never described the old assumption). Read-only/idempotent property
  preserved: the new code issues only GET requests, same as every other check in this script.
- [x] **`scenarios/data-map/scan-credential-remaining-kinds/`** - commit `7257a26` - 2026-09-16.
  Full scenario (README.md, design.md, deploy/New-PurviewScanCredentialExtended.ps1,
  deploy/policy/scan-credential-extended-definitions.json,
  validate/Test-PurviewScanCredentialExtended.ps1, rollback.md, reviews.md) extending
  `scan-credential-key-vault-backed` to the five `CredentialType` kinds it left out - `AccountKey`,
  `AmazonARN`, `ConsumerKeyAuth`, `DelegatedAuth`, `ManagedIdentity` (user-assigned) - completing
  all eight documented kinds. Grounded live against the Scanning-data-plane REST reference via the
  Microsoft Learn MCP tool (available this run, contrary to this repo's usual `EGRESS_BLOCKED`
  default noted elsewhere in this file) and cross-checked against
  `scan-credential-inventory-report`'s independently-built fingerprint table, which reached
  identical shapes from the read side - no discrepancy found. Each kind's real-world source pairing
  confirmed against a dedicated Microsoft Learn connector page (Azure Storage/Cosmos DB, Amazon S3,
  Salesforce, Microsoft Fabric/Power BI, six UAMI-eligible sources incl. three already scanned by
  this repo). Reuses `Remove-PurviewScanCredential.ps1` unmodified for deletion after confirming it
  is genuinely kind-agnostic. Four-lens review resolved two real Red/Blue Team findings (a
  `-WhatIf -Verbose` plaintext-leak risk for `ConsumerKeyAuth`'s `consumerKey`, fixed with a
  redacted log-body path; the total absence of a Key Vault-side detective control for
  `AmazonARN`/`ManagedIdentity`, disclosed with a revised monitoring cadence) and one Product-Owner
  Fail (the parent scenario's stale "out of scope" claim, corrected in place with bidirectional
  cross-links). Four new follow-ups recorded above rather than resolved by guessing: the `AmazonARN`
  account-ID/external-ID REST-source VERIFY, `ManagedIdentity`'s preview-status recheck, the
  `-CheckKeyVaultSecret` vault-name-derivation gap, and the four natural consumer-scan fragments
  this build identified but did not build.
- [x] **`scenarios/data-map/bulk-grant-synapse-serverless-access/`** - commit `18e4248` -
  2026-09-16. Full scenario (README.md, design.md, deploy/Grant-SynapseServerlessDatabaseAccess.ps1,
  validate/Test-SynapseServerlessDatabaseAccess.ps1, rollback.md, reviews.md) automating the
  per-serverless-database `CREATE LOGIN`/`CREATE USER`/`db_datareader` grants
  `scan-azure-synapse-and-classify/`'s serverless scanning path needs, closing that scenario's own
  CISO-flagged per-database prerequisite-cost-scaling gap. Grounded via the Microsoft Learn MCP
  documentation tool, which was directly reachable this run (both search and full-page fetch, no
  `EGRESS_BLOCKED`) - every T-SQL statement and catalog query is confirmed against a directly-fetched
  Microsoft Learn page, not inferred. Notable correction surfaced during grounding: the parent
  scenario's own README/design describe the serverless `CREATE LOGIN` step as per-database (following
  Microsoft's portal walkthrough literally); two independently-fetched Microsoft Learn pages confirm
  it is actually a server-scoped statement, run once against `master` - implemented correctly here
  (see this scenario's `design.md` §4), not backported into the parent scenario in this same fragment
  (`AGENTS.md` §6). Four-lens review surfaced and resolved: a Red Team blast-radius concern (bulk
  automation removes the manual walkthrough's natural per-database review friction - resolved with
  explicit `-WhatIf`-first/`-Database`-allow-list guidance), a Red Team name-collision idempotency
  edge case (disclosed, not fixed - no stable-identifier pinning mechanism is documented), a Blue Team
  audit-trail gap (resolved by naming Azure SQL/Synapse's own auditing as the actual detective control,
  not built here), and a CISO change-management fit note (resolved with guidance to treat a `-WhatIf`
  preview as the change-approval artifact). Also closes the separately-tracked
  `verify-synapse-serverless-enumeration-grants` follow-up via this scenario's own `validate/` script.
  Surfaced two cross-cutting doc gaps (a sixth `docs/automation-surface.md` surface for direct T-SQL
  connections; a tenth `docs/rbac-model.md` system for Azure Synapse workspace RBAC) - recorded as
  follow-ups rather than edited into those docs in this same fragment.
- [x] **Backport: Organization Configuration vs. Audit Manager role distinction into
  `docs/rbac-model.md`'s Audit row** - doc-only correction fragment (not a new scenario), commit
  `c7c146b` - 2026-09-16. `docs/rbac-model.md` §4's Audit row
  previously read "Audit Reader (View-Only Audit Logs) → **Audit Manager** (configure + search +
  export)" with no mention of retention-policy management. Added: creating/editing an audit log
  retention policy needs the **Organization Configuration** role, not Audit Manager - independently
  re-confirmed this run (not just carried over from the source scenario's citation) via a direct
  fetch of the raw `defender-docs` GitHub source behind
  `learn.microsoft.com/defender-office-365/scc-permissions` (direct `WebFetch` to `learn.microsoft.com`
  itself was egress-blocked again this run, the same blocker several earlier fragments logged),
  which lists **Organization Configuration** among the Compliance Data Administrator role group's
  default roles and confirms Audit Manager's default roles are limited to Audit Logs/View-Only
  Audit Logs - and via `WebSearch` corroboration that the Organization Configuration role is what
  `audit-log-retention-policies` itself names as the requirement. Also bumped the doc's "current as
  of" date to 2026-09-16, added the `audit-log-retention-policies` URL to the Sources list (appended
  at the end, not inserted mid-list, to avoid breaking the existing ordinal `source N`/`sources
  27-35` cross-references in §13), and closed the loop in
  `scenarios/audit/retention-policy-management/README.md` §3/§11, which had deferred this backport
  rather than re-opening the cross-cutting doc mid-fragment.
- [x] **`scenarios/data-map/scan-credential-key-vault-backed/`** - commit 21d17d0 - 2026-09-16.
  Scripts the Azure **Key Vault connection** (`PUT /scan/azureKeyVaults/{azureKeyVaultName}`) and
  the Key Vault-backed **credential object** (`PUT /scan/credentials/{credentialName}`, kinds
  `SqlAuth`/`BasicAuth`/`ServicePrincipal`) that every credential-authenticated Data Map scan
  requires - closing the long-standing follow-up that had been waiting on "a documented REST
  endpoint for credential-object creation." **That endpoint already existed**: the Purview Scanning
  data plane documents **Credential** and **Key Vault Connections** as first-class operation groups
  at `api-version=2023-09-01`, both direct-fetched in full this run (see the Blocked/needs-user note
  below - the Microsoft Learn MCP tool *was* available this session, unlike what this loop's
  scheduled instructions assumed). Two earlier scenarios had asserted the opposite; the Product
  Owner lens raised that self-contradiction as this build's only **Fail**, resolved by correcting
  both **in place**, dated: `scan-azure-sql-and-classify` (README §6/§11, `design.md` §7) and
  `scan-on-premises-sql-server-and-classify` (README §3/§11, deploy script `.NOTES`/`.PARAMETER`).
  The original error was partly an over-read of Microsoft's disaster-recovery line that "there's no
  API to extract credentials" - that concerns **exporting existing secret material** (true, and by
  design), not **creating the object**.
  Central design property: the deploy script is *structurally* incapable of leaking a scan secret -
  it takes no plaintext/SecureString parameter for the target data source at all, only Key Vault
  coordinates, because a credential object stores only a *reference*. That keeps three trust
  boundaries separate (Purview Data Source Administrator / Key Vault Secrets Officer / Purview
  managed identity), which `design.md` §3 documents as the reason a "convenient" one-script version
  that also writes the secret and grants vault access was rejected.
  Four-lens review produced three Red Team fixes (silent credential **re-point** with no documented
  Purview detective control - Microsoft's own enumerated audit-event category table omits
  credentials entirely; the Key Vault grant being **vault-wide over secrets** with no per-secret
  scoping, hence a dedicated-vault recommendation; and the unpinned-`secretVersion` tradeoff), three
  Blue Team fixes (404 meaning "absent **or** not visible to this identity" - the most likely
  first-run failure, whose original message pointed away from the cause; scheduled validation plus a
  five-step runbook; and a `rollback.md` **Stage 0** consumer inventory compensating for the absent
  credential→scan reverse lookup), and one CISO fix (the unstated org-change cost of the separation
  of duties). Four honest VERIFYs carried rather than guessed - most importantly the two
  `KeyVaultSecret` discriminator literals (`type`, `store.type`), which **no** Purview source pins:
  the reference types both as open `string`, its only worked example is a `BasicAuth` credential
  with a description and no `typeProperties`, the JS SDK types them as `string`, and `Az.Purview`
  has no credential cmdlet at all. Shipped as **parameters** with defaults derived from Data
  Factory's identically-shaped `AzureKeyVaultSecretReference` plus Purview's own Key Vault
  connection response `id` ending in `/linkedservices/...`, with `validate/` reporting a mismatch as
  `[WARN]` (never `[FAIL]`) and printing the observed values - one pilot-tenant
  portal-create-then-`GET` closes it permanently.
- [x] **`scenarios/insider-risk/data-leaks-custom-indicator-trigger/`** - commit b2f70e6 - 2026-09-16.
  Third and final documented triggering-event mechanism for the base `Data leaks` Insider Risk
  Management policy template (siblings: `data-leaks/` - DLP-policy trigger;
  `data-leaks-exfiltration-activity-trigger/` - built-in-indicator trigger), closing the follow-up
  filed while building the latter. Uses the **Insider Risk Indicators (preview)** connector to import
  pre-aggregated, non-Microsoft-workload detections (Microsoft's own worked example: Salesforce +
  Dropbox activity via a Source-column-routed CSV) as custom indicators, used as the policy's
  trigger and/or scoring indicator with a mandatory custom threshold (no default exists for a custom
  indicator). New deploy script `Send-InsiderRiskIndicatorRecord.ps1` takes the CSV's column names as
  parameters (Microsoft documents this connector's schema as genuinely flexible, unlike the
  HR-connector sibling's fixed schema) and fails closed on two Microsoft-documented silent-failure
  modes: duplicate UPN+event-time combinations (silently dropped by the service) and source-column
  values not matching the connector's configured allow-list (hard connector-side failure). Grounded
  via the Microsoft Learn MCP tool (`microsoft_docs_fetch`, found available and used directly in this
  build despite the scheduled task's own instructions assuming it would not be) against
  `import-insider-risk-indicators`, `insider-risk-management-settings-policy-indicators`,
  `insider-risk-management-policy-templates`, and `insider-risk-management-configure`, plus an
  independent direct GitHub fetch of the actual `sample_script.ps1` ingestion sample script, which
  confirmed the OAuth token endpoint, fixed resource ID, and webhook URL are identical to the
  already-grounded HR-connector sibling's own script (and confirmed a different default chunk size,
  5,000 vs. that sibling's page-documented 500) - reused `Register-HrConnectorApp.ps1`/
  `Test-HrConnectorAppRegistration.ps1` unmodified on that basis rather than forking them. Full
  deliverable: README.md (12-section skeleton), design.md, deploy/ (new upload/validation script +
  policy-config manifest), validate/, rollback.md, and a four-lens reviews.md - two Fix items (Red
  Team: the third-party CSV pipeline validates shape, not provenance, a new trust boundary; Blue
  Team: partial-chunk-upload failure has no automatic resume) both resolved by disclosure in
  `README.md` §8/§11 before this fragment was marked done. Six new follow-ups (template-scope
  ambiguity, source-column case-sensitivity, re-ingestion idempotency, end-to-end latency, a
  Power Automate upload-trigger alternative, and a possible documentation backport to the
  HR-connector sibling) filed under "Follow-ups discovered while building the Data leaks
  custom-indicator (third-party-connector) trigger scenario" above.
- [x] **`scenarios/data-lifecycle-management/retention-labels-financial-records/` - grounding-defect
  fix fragment** - commit PENDING - 2026-09-16. Fixed the `New-RetentionComplianceRule -Name` +
  `-ApplyComplianceTag` invalid-parameter-combination defect flagged under "Follow-up discovered while
  building the adaptive-scope-auto-apply-label scenario" above: Microsoft's current
  `New-RetentionComplianceRule` reference documents `-Name` as mutually exclusive with
  `-ApplyComplianceTag`/`-PublishComplianceTag` (confirmed via WebSearch against the Learn reference
  page - direct `learn.microsoft.com` fetch is blocked by this environment's network egress proxy, so
  WebSearch-derived quotes were used instead, consistent with this repo's established fallback when the
  Microsoft Learn MCP tool isn't available). `deploy/New-FinancialRecordsRetention.ps1`'s `$ruleParams`
  no longer sets `Name`; `.NOTES`, `README.md` §6 (config-reference row) and §11 (new known-limitations
  entry with full provenance), `design.md` §4, and `reviews.md` (new targeted correction addendum,
  Microsoft Product Owner lens re-check only - no other lens affected since the fix changes no
  behavior, only makes the call resolve at runtime) all updated in place. No live-tenant access was
  used or attempted. No new follow-ups discovered; this closes the item cleanly.
- [x] **`scenarios/compliance-manager/gdpr-assessment/`** - commit 271a877 - 2026-09-16. Fifth Compliance Manager scenario: full
  deliverable (README.md, design.md, deploy/policy manifest, reused audit-trail export script,
  validate script, rollback.md, reviews.md) mirroring `assess-against-iso27001/`,
  `pci-dss-assessment/`, `soc2-assessment/`, and `hipaa-hitech-assessment/`'s shape. Grounded via the
  Microsoft Learn MCP tool (`microsoft_docs_search`/`microsoft_docs_fetch`, available and used
  directly this run) plus WebSearch for GDPR's own primary-text articles (37, 42, 12) not hosted on
  learn.microsoft.com. Own 6-category crosswalk (Data Subject Rights, Data Processing Principles,
  Breach Notification, DPIA, Cross-Border Data Transfers, Accountability & Governance) - a genuinely
  different shape from all four sibling crosswalks, not a relabeled copy. Four-lens review completed
  with 4 Red Team / 4 Blue Team / 8 Product Owner findings, all resolved (0 Fail); CISO lens Pass.
  Five new follow-ups recorded above (DSR-fulfillment scenario, cross-border-transfer scenario, and
  three VERIFY items) rather than expanded inline to keep this fragment scoped.
- [x] **`scenarios/insider-risk/security-policy-violations-by-priority-users/` - re-verification
  fragment** - commit c6945ae - 2026-09-16. Closed the two top TODO items under "Follow-ups
  discovered while building the Data leaks by priority users scenario". This fragment had direct
  Microsoft Learn fetch access (`mcp__Microsoft_Learn__microsoft_docs_fetch`), which the scenario's
  original build did not, and used it to fetch `insider-risk-management-policy-templates` and
  `insider-risk-management-configure` verbatim. Two outcomes:
  1. **Confirmed and fixed** the mis-stated claim that the 1,000-actively-scored-user cap "is
     shared with the base template as well" - Microsoft's own Policy template limits text
     ("These maximum limits apply to users across all policies using a given policy template")
     confirms the cap is its own, independently-tracked pool per exact template. Corrected in
     `README.md` §4 (Mermaid diagram)/§6/§10/§11 and `design.md` §2 goal 3/§3/§4 (Mermaid diagram).
  2. **Found the second item's own premise wrong on re-grounding, and built a more accurate fix
     instead of the one originally scoped.** The follow-up item assumed the "Add or edit priority
     user groups" UI option name (confirmed for the `data-leaks-by-priority-users` sibling)
     "applies identically" to this template - but the same Microsoft Step 6 workflow guide states,
     verbatim, that the option "appears only if you choose the *Data leaks by priority users*
     template," directly contradicting that generalization. Rather than propagate the error,
     `README.md` §5 Step 3/§6 now carry the verbatim Microsoft quote as a sharper, more specific
     open VERIFY (this template's own control name is unconfirmed, not assumed). Similarly, the
     "User is a member of a priority user group" risk score booster is documented generically by
     Microsoft (not template-scoped), but the same guide ties booster-section availability to
     selecting "at least one Office or Device indicator" - a condition this template's sole
     indicator category (Microsoft Defender for Endpoint indicators (preview), a separately
     documented third category) doesn't obviously meet. Flagged as a new, unresolved VERIFY in
     `README.md` §5 Step 5/§6 rather than asserting the booster applies automatically.
  `reviews.md` Microsoft Product Owner finding 3 (which had endorsed the now-corrected "shared cap"
  claim) is corrected in place with an inline note, plus a new "Addendum - re-verification pass"
  section recording both outcomes and their Pass/Fix disposition, per `AGENTS.md` §5's rule that
  reviews cite specifics and any Fix feeds back into the scenario. New references 13-14 added to
  `README.md` §12. No new script/deploy/validate changes were needed - this was a docs-accuracy
  fragment, not a new capability. Two new VERIFY items (this template's actual "Users and groups"
  control name; Risk-score-booster availability for a Defender-for-Endpoint-only indicator
  selection) added to TODO below as follow-ups discovered by this fragment.
- [x] **`scenarios/compliance-manager/hipaa-hitech-assessment/`** - commit ca749a2 - 2026-09-16.
  Fourth Compliance Manager assessment scenario (alongside `assess-against-iso27001/`, `pci-dss-
  assessment/`, and `soc2-assessment/`), against the HIPAA/HITECH premium template. Closes the
  `### Follow-ups discovered while building the Compliance Manager SOC 2 assessment scenario` item
  "Consider a fourth Compliance Manager scenario for a regulation this library hasn't covered yet."
  Before building, ran a quick WebSearch/Microsoft Learn MCP pass against `compliance-manager-
  regulations-list` to confirm both HIPAA/HITECH and GDPR are real, currently-listed premium
  templates (HIPAA/HITECH under the US Government category with its own `offering-hipaa-hitech`
  page; GDPR under EMEA with its own `compliance/regulatory/gdpr` page) before picking HIPAA/HITECH
  per the follow-up item's own stated tie-break rule (a common enterprise/regulatory driver pairing
  naturally with the existing PCI DSS + SOC 2 + ISO 27001 trio) - GDPR is tracked as a new
  follow-up below rather than also built in this fragment (`AGENTS.md` §6, one fragment per turn).
  Full deliverable per `AGENTS.md` §4 (`README.md`, `design.md`, `deploy/policy/
  hipaa-hitech-assessment-manifest.json`, `deploy/Export-ComplianceManagerAuditTrail.ps1` - reused,
  not duplicated, from `assess-against-iso27001/` - `validate/Test-ComplianceManagerAuditTrail.ps1`,
  `rollback.md`, `reviews.md`). Grounded via the Microsoft Learn MCP tool (available and used
  directly in this session, same as the four most recent prior Compliance Manager fragments,
  despite this scenario's own standing instructions assuming otherwise) directly against
  `compliance-manager-regulations-list` (confirmed "HIPAA/HITECH" as the exact current catalog name,
  distinct from the separately-listed "HITRUST" template), `offering-hipaa-hitech` (three-rule
  structure - Privacy Rule/Security Rule/Breach Notification Rule; Microsoft's own explicit FAQ
  statement that no HHS-approved HIPAA certification standard exists for anyone), `azure/compliance/
  offerings/offering-hipaa-us`, `entra/standards/hipaa-configure-for-compliance` (45 CFR
  §164.308/164.310/164.312 safeguard structure; the "addressable is not optional" Security Rule
  distinction, quoted verbatim rather than paraphrased), `dlp-policy-templates-include` (confirmed
  the built-in "U.S. Health Insurance Act (HIPAA) Enhanced" DLP policy template exists, cited as a
  disclosed gap rather than claimed as built), and eCFR §164.316 (six-year Security Rule
  documentation-retention requirement, cited to motivate this scenario's operations guidance).
  Crosswalk uses HIPAA/HITECH's own 5-part rule structure (Privacy Rule; Administrative, Physical,
  and Technical Safeguards; Breach Notification Rule) rather than PCI DSS's numbered goals or
  SOC 2's Trust Services Criteria categories - a structurally different manifest shape the validate
  script's manifest checks were written to match, plus a new `hasAddressableSpecifications`
  structural flag on the three Security Rule categories with no analog in any sibling scenario's
  crosswalk. One VERIFY carried forward rather than guessed: whether Compliance Manager's UI exposes
  a per-improvement-action required-vs-addressable indicator (only the underlying 45 CFR rule text
  was confirmed). Four-lens review found and closed 4 Red Team, 4 Blue Team, and 7 Microsoft
  Product Owner findings (0 from CISO) - see `reviews.md`.
- [x] **`scenarios/audit/compromised-account-incident-response/`** - commit a52d3a4 - 2026-09-16.
  The mutating incident-response companion `audit/premium-audit-investigation/design.md` §7
  explicitly scoped out. Automates Steps 1, 2, and 6 of Microsoft's own "Respond to a compromised
  cloud email account" playbook - disable the Entra ID account (`Update-MgUser -AccountEnabled
  $false`), revoke all sign-in sessions (`Revoke-MgUserSignInSession`), reset the password
  (generated, printed once, never persisted), clear mailbox forwarding, and remove Inbox rules
  including hidden ones (`Get-InboxRule -IncludeHidden`/`Remove-InboxRule`) - plus a
  delegate-permission (`FullAccess`/`SendAs`) cleanup this scenario adds on top of Microsoft's own
  documented steps (grounded independently, labeled as an extension, not misattributed to
  Microsoft's Step 6). Every mutating action is idempotent (reads current state first) and gated by
  `-WhatIf`/`ShouldProcess`; a timestamped JSON backup of pre-removal state is written before any
  removal, doubling as evidence and the rollback input. Two automation surfaces (Microsoft Graph +
  Exchange Online PowerShell) in one script - a first for this library's `audit/` module. Full
  deliverable per `AGENTS.md` §4 (`README.md`, `design.md`, `deploy/
  Invoke-CompromisedAccountResponse.ps1`, `deploy/config/compromised-account-response.sample.json`,
  `validate/Test-CompromisedAccountResponse.ps1`, `rollback.md`, `reviews.md`). Grounded via the
  Microsoft Learn MCP tool (available and used directly in this session, same as the two most
  recent prior fragments, despite this scenario's own standing instructions assuming otherwise)
  directly against Microsoft's `responding-to-a-compromised-email-account` playbook page (the
  primary source for the whole scenario shape) plus the `user-update`, `user-revokesigninsessions`,
  `remove-inboxrule`, `set-mailbox`, `remove-mailboxpermission`/`manage-permissions-for-recipients`,
  `remove-recipientpermission`, `permissions-exo`, `privileged-roles-permissions`, and
  `concept-identity-protection-policies` reference pages. Four-lens review found and closed 4 Red
  Team, 1 Blue Team (plus 2 confirmed-correct), 1 CISO (plus 4 confirmed-correct/pass), and 1
  Microsoft Product Owner (plus 3 confirmed-correct) finding - see `reviews.md`. One VERIFY carried
  forward rather than guessed: the exact Exchange Online RBAC role for the mailbox cmdlets, since none
  of their own reference pages name one.
- [x] **`scenarios/compliance-manager/soc2-assessment/`** - commit 70e15fd - 2026-09-16. Third
  Compliance Manager assessment scenario (alongside `assess-against-iso27001/` and
  `pci-dss-assessment/`), against the SOC 2 premium template. Full deliverable per `AGENTS.md` §4
  (`README.md`, `design.md`, `deploy/policy/soc2-assessment-manifest.json`, `deploy/
  Export-ComplianceManagerAuditTrail.ps1` - reused, not duplicated, from `assess-against-iso27001/`
  - `validate/Test-ComplianceManagerAuditTrail.ps1`, `rollback.md`, `reviews.md`). Grounded via the
  Microsoft Learn MCP tool (available and used directly in this session despite this scenario's own
  standing instructions assuming otherwise) against `compliance-manager-regulations-list` (confirmed
  "System and Organization Controls (SOC) 2" as the exact current catalog name, distinct from the
  sibling "SOC 1" template) and `offering-soc-2` (Trust Services Criteria, Type I vs. Type II, AICPA
  SSAE 18 basis). Crosswalk uses the AICPA's 5 Trust Services Criteria categories (Security flagged
  mandatory) rather than PCI DSS's 6 numbered goals - a structurally different manifest shape the
  validate script's manifest checks were written to match rather than reusing PCI's goal-numbering
  check as-is. Four-lens review found and closed 3 Red Team, 4 Blue Team, and 6 Microsoft Product
  Owner findings (0 from CISO) - see `reviews.md`.
- [x] **`scenarios/insider-risk/data-leaks-exfiltration-activity-trigger/`** - commit 333f18d -
  2026-09-16. Second full worked example for the base `Data leaks` policy template - the "User
  performs an exfiltration activity" triggering event, `data-leaks/design.md` §7's own disclosed
  non-goal. Full deliverable per `AGENTS.md` §4 (`README.md`, `design.md`, `deploy/policy/
  data-leaks-exfiltration-activity-trigger-policy-manifest.json`, `validate/
  Test-DataLeaksExfiltrationActivityTriggerSetup.ps1`, `rollback.md`, `reviews.md`). Grounded via a
  direct Microsoft Learn MCP fetch (this session's network environment did not block it), which
  surfaced a previously-undocumented mechanic in this library: the trigger-indicator threshold
  (brings a user into scope) and the policy/scoring-indicator threshold (scores an already-in-scope
  user) are two independent decisions in the same policy-creation workflow, not one - and a
  Microsoft-published worked example (SharePoint downloads, 10+/20+/30+ events/day →
  low/medium/high) for the latter, explicitly illustrative rather than a stated default. Reuses the
  base template's scope-candidate and alert-export scripts unmodified (same 15,000-user cap,
  shared cumulatively with the `data-leaks/` DLP-trigger sibling); no DLP-readiness-style script was
  needed since this trigger path has no DLP-policy dependency. Four-lens review found and resolved
  two Fix items (Red Team: a channel scored but not selected as a trigger indicator never brings a
  user into scope; Blue Team: a trigger indicator disabled tenant-wide by another team silently
  breaks this policy) via `README.md` §8/§11 doc additions - no code fix needed since the one new
  script is read-only by design. New follow-ups tracked above under "Follow-ups discovered while
  building the Data leaks exfiltration-activity-trigger scenario."
- [x] **`scenarios/insider-risk/data-leaks/` (confirmed max-users cap, Copilot workload exclusion,
  mixed-workload grounding)** - commit 695b4b1 - 2026-09-16. Follow-up grounding/propagation
  fragment (not a new scenario): re-confirmed three previously-open VERIFY items via a direct
  Microsoft Learn fetch (this session's network environment did not block it, unlike the original
  build's) and propagated the results into the scenario's docs and scripts. (1) The base `Data
  leaks` template's actively-scored-user cap is **15,000**
  (`insider-risk-management-limits#maximum-number-of-users-in-scope-for-a-policy-template`) -
  `README.md` §3/§6/§10/§11, `design.md` §2 goal 7/§6, and both `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1`-adjacent (`-MaxUsers` call sites) and
  `validate/Test-DataLeaksIrmSetup.ps1` (`-MaxUsers` now defaults to 15000 instead of no default)
  updated. (2) A DLP policy mixing a supported and an unsupported workload on the SAME policy is
  **confirmed safe** - Microsoft states directly that only the supported-workload rules' alerts
  are processed (`insider-risk-management-settings-policy-indicators#supported-dlp-workloads`);
  the readiness script's `[WARN]` for this combination is now informational, not an open question.
  (3) **Microsoft 365 Copilot** is newly confirmed as an additional unsupported workload for this
  indicator (not previously disclosed) - added to `README.md` §6/§11, and a new best-effort
  `EnforcementPlanes`-based Copilot-scoping detection check (step 2a) added to `deploy/
  Test-DlpPolicyIrmTriggerReadiness.ps1`, grounded against `New-`/`Set-DlpCompliancePolicy`'s
  `-EnforcementPlanes`/`-Locations` parameters and the dedicated Copilot-DLP-location Learn
  article (Copilot has no `...Location`-style array parameter analogous to `TeamsLocation` etc.).
  This new check itself carries a new, narrower VERIFY (whether `Get-DlpCompliancePolicy` exposes
  `EnforcementPlanes` on read the same way `New-`/`Set-` accept it on write) rather than asserting
  read-shape parity by guess. `reviews.md` given a short addendum recording this follow-up
  resolution rather than rewriting the original four-lens round's historical text.
- [x] **`scenarios/ediscovery/teams-purge-hold-lifecycle-management/` (mailbox-scoped Exchange-vs-Group-
  location conflation fix)** - commit dff04ae - 2026-09-16. Fixed a real remediation-accuracy bug this
  scenario's own PROGRESS.md follow-up flagged as an open ambiguity: `ConvertTo-ParsedInPlaceHolds` in
  all four scripts (`Get-/Remove-/Restore-TeamsPurgeMailboxHolds.ps1`,
  `validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1`) treated any `mbx`/`skp`/`grp`-prefixed
  mailbox-scoped `InPlaceHolds` entry as interchangeable, always routing removal/restore through
  `-RemoveExchangeLocation`/`-AddExchangeLocation`. Two Microsoft Learn pages fetched in full this run
  prove that's wrong for a group/team mailbox target: `purview/retention-settings` states the
  Exchange-mailboxes location (org-wide or specific-location) flatly rejects a Microsoft 365 Group
  mailbox ("RemoteGroupMailbox isn't a valid selection" at save time), and `purview/
  edisc-hold-types-mailboxes` documents the `Get-Mailbox`-visible specific-location prefix table as
  `mbx`/`skp` only - never `grp`. A `grp`-prefixed, non-org-wide entry is now routed through
  `-RemoveModernGroupLocation`/`-AddModernGroupLocation` (confirmed real `Set-RetentionCompliancePolicy`
  parameters) when the target is a confirmed group/team mailbox, or reported as an unrecognized,
  never-acted-on anomaly otherwise; the sibling bug this surfaced (org-wide Exchange-policy
  applicability not gated on `-not $isGroupMailbox`, unlike its already-correct Group-side counterpart)
  was fixed alongside it. One VERIFY carried forward rather than guessed: the exact `InPlaceHolds`
  notation this mechanism stamps for the non-org-wide Group case isn't explicitly confirmed by
  Microsoft. `design.md` §8.1 (new), `README.md` §6/§11/§12, and `reviews.md` Round 2 record the full
  grounding and four-lens review of the fix.
- [x] **`scenarios/compliance-manager/entra-privileged-role-monitoring/` (bulk group-membership-import
  follow-up)** - commit bafcbd2 - 2026-09-15. Closed the "not monitored at all" half of `reviews.md`
  round 2 Red Team finding 3: grounded `"Bulk import group members - finished (bulk)"`/`"Bulk remove
  group members - finished (bulk)"` as real, distinct `GroupManagement`-category activity names via a
  direct fetch of Microsoft's `reference-audit-activities.md` docs source (`learn.microsoft.com`
  itself returned `EGRESS_BLOCKED` in this build environment, consistent with prior builds' notes),
  and added both to `Export-RoleAssignableGroupMembershipAuditTrail.ps1`'s `$monitoredActivities`.
  Safe by construction: the script's existing `Get-GroupTargetFromTargetResources` already fails soft
  (skips a record with no `Group`-typed target) rather than assuming a shape, so the addition can only
  gain coverage, never fabricate a match. Also widened `Get-PrincipalDisplayNameFromTargetResources`
  to collect every `User`-typed target instead of only the first, since a bulk record may legitimately
  affect more than one member. The `targetResources` shape for the two bulk activities specifically
  (does a bulk record actually carry a `Group`-typed entry, and how many `User`-typed entries) is
  **not** confirmed by any Microsoft worked example - left as an explicit, disclosed VERIFY (new item
  above) rather than resolved by guessing, per `AGENTS.md` §4. `README.md` (§6 config table, §11),
  `design.md`, `validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1` (4-activity allowlist, new
  manual-checklist item), and `reviews.md` (new Round 3, all four lenses) updated; Round 3 Red Team
  finding closed, no Fail raised by any lens.
- [x] **`scenarios/data-map/scan-azure-synapse-and-classify-pii-ruleset/`** - commit abb8afe -
  2026-09-15. New full scenario (README, design, deploy, validate, rollback, four-lens review)
  extending `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/`'s proven PII-only custom
  scan rule set pattern to Azure Synapse Analytics - the second of the three sibling source types
  that scenario's own follow-ups tracked. `deploy/New-PiiOnlyScanRuleset.ps1` reads the tenant's
  live classification type definitions (Types API, tenant-wide/source-type-agnostic, reused
  unchanged), computes an exclusion list, creates a Custom `AzureSynapseWorkspaceScanRuleset`
  object, and reconciles `scan-azure-synapse-and-classify`'s existing scan onto it, preserving its
  dedicated/serverless SQL pool endpoints and other properties untouched. `deploy/
  Remove-PiiOnlyScanRuleset.ps1` reverts to the System default and optionally deletes the custom
  ruleset. `learn.microsoft.com` REST reference pages returned `EGRESS_BLOCKED` in this build
  environment (same restriction the base Synapse scenario's own build hit); grounded instead via
  direct `raw.githubusercontent.com` fetch of the Az.Purview PowerShell module's own
  `New-AzPurviewAzureSynapseWorkspaceScanRulesetObject.md` and
  `New-AzPurviewAzureSynapseWorkspaceCredentialScanObject.md` source files, confirming the exact
  `Kind` values verbatim rather than guessing by analogy. That grounding pass surfaced a genuine,
  previously-undocumented naming trap this source type has and the Azure SQL Database sibling does
  not: the System default ruleset's **name** (`AzureSynapseSQL`) and the custom ruleset's **kind**
  (`AzureSynapseWorkspace`) are different strings - for the SQL Database sibling both are the
  identical `AzureSqlDatabase` string, an easy pattern to over-generalize. Caught by this build's
  own Red Team review (`reviews.md` finding 1) and fixed before shipping by hard-coding
  `Remove-PiiOnlyScanRuleset.ps1`'s `-RevertToRulesetName` default to the independently-confirmed
  correct value rather than deriving it from the ruleset-kind constant. Two VERIFYs remain open
  (an independent direct fetch of the REST reference page itself once `learn.microsoft.com` is
  reachable; Types API pagination behavior at scale, inherited unchanged from the sibling) - see
  `README.md` §11. `PROGRESS.md`'s TODO backlog entry corrected in place: the original shorthand
  guess (`AzureSynapse`) is now the confirmed `AzureSynapseWorkspace`, and the remaining two
  sibling scenarios (Azure SQL Managed Instance, on-premises SQL Server) carry a note to ground
  their own `kind` strings independently rather than assume the same shortcut.
- [x] **`scenarios/data-map/verify-purview-entra-graph-prerequisites/`** - commit 7ba5661 -
  2026-09-15. New full scenario (README, design, deploy, validate, rollback, four-lens review)
  closing the Blue Team gap `scan-azure-sql-managed-instance-and-classify/reviews.md` flagged: that
  scenario's own `validate/Test-AzureSqlManagedInstanceDataMapScan.ps1` authenticates against the
  Purview Data Map data-plane API and has no reason to also hold a Microsoft Graph directory-read
  permission, so it could not check the one Microsoft Entra prerequisite (Directory Readers
  membership for the instance's own managed identity) that scenario documents as required before
  Microsoft Entra authentication works at all. This scenario is a standalone, Graph-only checker
  (`Get-MgDirectoryRole`/`Get-MgDirectoryRoleMember`, least-privileged `RoleManagement.Read.Directory`
  application permission - corroborated across independent search results for both the PowerShell
  cmdlet references and their REST equivalents) that takes a CSV inventory so it scales to every
  Managed-Instance-backed Purview source in one run, reports PASS/FAIL per instance, and separately
  reports membership **drift** (any other current Directory Readers member not in the inventory) as
  a non-fatal WARN - closing a second, related Red Team finding from the sibling scenario's own
  review about undetected role-membership drift. Explicitly checked and documented as *not*
  duplicating Microsoft's own broader `data-map-data-sources-check-azure-readiness` readiness
  checklist script (a different identity, a different, narrower check, at a different cadence - see
  `design.md` §8) - a genuine "reinventing a native capability" risk this build investigated rather
  than assumed away. Read-only by design (never grants/revokes the role itself - `design.md` §10
  Non-goal, consistent with this repo's established convention for high-privilege one-time directory
  grants). Both scripts were parse-checked (PowerShell 7.4.6, installed temporarily in this session)
  and functionally exercised, not just statically reviewed: the validate script against a clean
  2-row CSV (all pass) and a deliberately malformed one (correctly produced 3 failures - empty
  InstanceName, a duplicate PrincipalObjectId, and two non-GUID values - with a non-zero exit); the
  deploy script's core logic against a mocked Microsoft Graph session covering all three real
  branches (mixed pass/fail/drift with report-file generation; `-WhatIf` correctly suppressing the
  report write while still reporting findings; the Directory-Readers-role-never-activated tenant
  edge case correctly failing every row with an explicit warning rather than a false "0 members,
  nothing wrong" pass). Four-lens review raised and resolved 7 Fix findings across all four lenses
  (Red Team: the JSON report itself discloses privileged-role membership and needs access-control
  discipline; the inventory CSV is an unguarded trust boundary for the drift check; Blue Team: exit
  code alone under-reports new drift, and the report has no built-in history/trending; CISO: the
  `RoleManagement.Read.Directory` permission name reads as higher-privilege than it is, risking a
  slower security approval than warranted; Microsoft Product Owner: the native-capability overlap
  above) - no Fail. The originating sibling scenario's `README.md` §7/§8 and `reviews.md` were also
  updated in place to point at this new scenario instead of citing it as an open `PROGRESS.md`
  follow-up. One VERIFY carried forward rather than guessed: whether `Get-MgDirectoryRoleMember`'s
  documented multi-type (user/service principal/group) member schema is actually exercised by the
  Directory Readers role specifically (see the new TODO item immediately above this entry).
- [x] **`scenarios/dlp/accepted-domains-hygiene-check-on-premises/` (extension)** - commit
  d64f0ce - 2026-09-15. Closed the `design.md` §9 non-goal deferring
  cross-environment reconciliation of `MatchSubDomains`/`Default` (only `DomainType` was checked
  before). Added two new finding categories to `deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1`'s
  cross-environment check - `CrossEnvironmentMatchSubDomainsMismatch` (`FAIL` if either environment has
  `MatchSubDomains=$true` where the other doesn't - an asymmetric subdomain-mail-acceptance attack
  surface) and `CrossEnvironmentDefaultMismatch` (always `WARN` - each hybrid side computes its own
  default accepted domain independently) - grounded against `Set-AcceptedDomain`'s reference, fetched
  from the canonical MicrosoftDocs GitHub source since `learn.microsoft.com` was blocked again from
  this build's network egress. Deliberately shipped as two **separate** categories, not additional rows
  under the existing `CrossEnvironmentMismatch` name: the first draft used one shared category, and a
  functional test this build ran directly (PowerShell 7.4.6 installed temporarily, a mocked
  `Get-AcceptedDomain` session with a domain diverging on both new fields at once) caught a real bug -
  the drift-log CSV's `(RunId, Category, DomainName)` uniqueness key collided, and
  `validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`'s own duplicate-row check correctly flagged
  it as `[FAIL]`. Fixed by mirroring this scenario's own baseline-diff block's existing per-field-category
  convention instead. Re-tested after the fix (4 distinct findings across 2 domains, zero duplicate-key
  failures, `-CheckLive -CloudBaselinePath` symmetric reconciliation all `[PASS]`) and confirmed
  replace-by-`RunId` idempotency held on a same-`RunId` re-run (5 rows before, 5 after). `validate/`
  script extended to reconcile both new categories independently, matching how the original
  `CrossEnvironmentMismatch` category was already validated. Full follow-up four-lens review appended to
  `reviews.md` (not a doc-only correction addendum, since this shipped new detection logic); one Fix
  found and closed (the row-collision bug above), no Fail. One VERIFY carried forward rather than
  guessed: whether `Set-AcceptedDomain -MakeDefault $true` on one domain provably clears `Default` from
  whichever domain previously held it - Microsoft's reference states what the parameter does but not
  this side effect (`README.md` §8/§11/§12, `design.md` §4).
- [x] **`scenarios/records-management/disposition-proof-export/`** - commit a006888 - 2026-09-15.
  Full scenario (README, design, deploy, validate, rollback, four-lens review) closing the
  "proof of disposition" evidence loop `regulatory-records-disposition/README.md` §7 referenced.
  Documents the portal-native Records Management → Disposition page's Filter+Export `.csv`
  workflow (grounded via a direct Microsoft Learn MCP fetch of the `disposition` reference page -
  confirmed no PowerShell/Graph equivalent exists for that export) and adds a scriptable,
  schedulable companion, `Export-DispositionProofEvidence.ps1`, built around
  `Search-UnifiedAuditLog` against the four "Disposition review activities" Operations
  (`AddReviewer`/`ApproveDisposal`/`ExtendRetention`/`RelabelItem`) plus `RecordDelete` - all five
  confirmed verbatim against Microsoft's "Audit log activities" reference. Deliberately queries with
  no `-RecordType` filter: Microsoft Graph's `auditLogRecordType` enum confirms plausibly-relevant
  `RecordsManagement`/`MultiStageDisposition` members by name, but no worked example pairs either
  with these Operations, and `RecordDelete` itself carries an unresolved cross-workload
  (SharePoint-table vs. "documents and emails") ambiguity - the same class of gap, and the same
  resolution (`-Operations` only), already established in this repo for
  `adaptive-protection-deleted-content-preservation`'s own audit-trail script. Four-lens review (Red
  Team) found a real blind spot in the initial draft - a record deleted outside the disposition
  process entirely (unlock + direct delete) would have been indistinguishable from a properly
  reviewed disposal - closed by adding `LockRecord`/`UnlockRecord` to both the deploy and validate
  scripts' query set (not just documented as a limitation) plus an explicit out-of-process-deletion
  reconciliation pattern in README §8. Also closed via review: the rolling CSV's lack of
  tamper-evidence (CISO/Red Team finding - README §11 now states this plainly and recommends
  immutable/access-controlled storage) and a disclosure of Microsoft's own stated preference for the
  Management Activity API over `Search-UnifiedAuditLog` in production automation, cross-linking
  `scenarios/audit/streaming-to-sentinel-or-management-api/` for that scale. Three genuine VERIFY
  gaps disclosed rather than guessed: the `AuditData` field distinguishing manual vs. autoapproved
  `ApproveDisposal`, the `AuditData` property carrying the retention-label name (handled defensively
  via a best-effort property scan), and the `RecordType` question above.
- [x] **`scenarios/insider-risk/data-leaks-by-priority-users/`** - commit e8105d8 - 2026-09-15.
  Full scenario (README, design, deploy/policy manifest, validate,
  rollback, four-lens review) for the third and last member of the **Data leaks…** template
  family. Grounded via direct Microsoft Learn MCP fetch/search (not WebSearch-only), which
  confirmed this template combines the base `Data leaks` template's own two-trigger-option shape
  (DLP-policy match, up to 20 policies, or exfiltration activity) with the
  `security-policy-violations-by-priority-users` sibling's priority-user-group population
  mechanism - a materially different shape from that sibling's own fixed, single-trigger template.
  Also confirmed and grounded: the template's own independently-documented 1,000-actively-scored
  cap is a **separate, per-exact-template** ceiling (not shared with the numerically-identical
  `security-policy-violations-by-priority-users` cap, correcting an overstatement in that sibling's
  own README); a distinct **"Add or edit priority user groups"** scope-page option confirmed by
  name; and a separately-selectable **"User is a member of a priority user group"** risk score
  booster required for the scoring boost to actually apply (not automatic from population
  assignment alone) - this build's own four-lens review named this its most operationally
  significant finding. Wrote **zero new `deploy/` scripts** - reused
  `../data-leaks/deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`,
  `../security-policy-violations-by-priority-users/deploy/Get-PriorityUserGroupScopeCandidates.ps1`,
  and `../departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1` unmodified; the only
  new artifact is a scenario-specific `validate/` script. Four-lens review found and resolved two
  genuine gaps: reviewer-permission scoping is a property of the priority user group (shared across
  every policy referencing it, not per-policy), and the validation script's DLP-related manual
  checklist was split into three separately-trackable items to match the base template scenario's
  own granularity. Several corrections/additions for sibling scenarios discovered during this
  build's grounding pass were deliberately not applied to those scenarios directly (fragment
  discipline) - tracked under "Follow-ups discovered while building the Data leaks by priority
  users scenario" above.
- [x] **`scenarios/insider-risk/data-leaks/`** - commit b9ee808 - 2026-09-15. Full scenario (README, design, deploy/policy manifest, validate, rollback,
  four-lens review) for the base **Data leaks** Insider Risk Management policy template - the
  "no employment-stressor or message-count gate" compensating control `data-leaks-by-risky-users/
  README.md` §11's own Red Team finding names as needed. Worked example uses the DLP-policy
  triggering event (Exchange/SharePoint/OneDrive, High severity, up to 20 policies); the
  exfiltration-activity triggering event is documented as a valid alternative but not given a
  second full implementation. New contribution: `deploy/Test-DlpPolicyIrmTriggerReadiness.ps1`, a
  read-only readiness check for an arbitrary, operator-chosen parent DLP policy (workload support,
  High-severity rule presence, the 20-policy ceiling, and - added during this fragment's own
  four-lens review - the parent policy's `Mode`, since a Test-mode policy's ability to still
  trigger this indicator is unconfirmed). Reuses `Get-SecurityPolicyViolationsScopeCandidates.ps1`
  and `Export-InsiderRiskAlerts.ps1` unmodified. Grounded via WebSearch only - this session's
  network environment returned `EGRESS_BLOCKED` for every direct URL fetch attempted (not only
  `learn.microsoft.com`); the base template's own actively-scored-user cap could not be retrieved
  and is disclosed as an open VERIFY rather than borrowed from a sibling template. Follow-up VERIFY
  items recorded above under "Follow-ups discovered while building the Data leaks (base template)
  scenario."
- [x] **`scenarios/insider-risk/data-leaks-by-risky-users/`** - commit 18db32f - 2026-09-15. Full scenario (README, design, deploy/policy manifest, validate,
  rollback, four-lens review) for the **Data leaks by risky users** Insider Risk Management policy
  template. Shares its HR-connector/Communication-Compliance trigger mechanism with the already-
  built `security-policy-violations-by-risky-users` sibling but scores built-in Office exfiltration
  indicators + cumulative exfiltration detection (default-on) instead of a Defender for Endpoint
  signal - no Defender for Endpoint dependency at all, the scenario's key differentiator. Reuses
  three existing scripts unmodified (`Send-HrRiskIndicatorRecord.ps1`,
  `Get-SecurityPolicyViolationsScopeCandidates.ps1`, `Export-InsiderRiskAlerts.ps1`) rather than
  forking any of them. Four-lens review raised and closed 3 Fix findings (Red Team: channel-
  coverage and cumulative-exfiltration-baseline evasion vectors; Blue Team: an operator-error risk
  now that three near-identical HR-connector upload invocations exist in this library, closed with
  a new validate-script checklist item; CISO: template-overlap cost/complexity guidance). Follow-up
  items discovered while building this fragment are filed under "Follow-ups discovered while
  building the Data leaks by risky users scenario" below.
- [x] **Ground Data Quality connection/alert `Search-UnifiedAuditLog` coverage** (follow-up from
  `connection-and-scorecard-alerts`) - commit 462851b - 2026-09-15. Grounded and closed, not built:
  found no audit-log or REST audit-endpoint coverage exists today for Unified Catalog Data Quality
  connection/alert lifecycle events (three independent, corroborating findings - see the TODO
  entry above for the full citation trail). `connection-and-scorecard-alerts/README.md` §8/§11,
  `design.md`'s Non-goals, and `reviews.md`'s Blue Team finding 1 corrected in place instead of a
  script being built against unconfirmed or non-existent endpoints, matching this repo's existing
  "investigated, not built" precedent (e.g. the IRM → eDiscovery Power Automate follow-up). This
  build's environment again blocked a direct Microsoft Learn fetch (same limitation as
  2026-09-09's "Blocked / needs user" entry) - grounded via `WebSearch` snippets of Microsoft Learn
  pages plus one independent third-party analysis, not a verbatim fetch; flagged inline for
  re-verification when a direct-fetch capability is available.
- [x] **`scenarios/communication-compliance/teams-viva-engage-content-safety/`** - commit
  f95b240 - 2026-09-15. New scenario: deploys the built-in **Detect inappropriate content** policy
  template (Hate/Sexual/Violence/Self-harm Azure AI Content Safety LLM classifiers, preview; Teams +
  Viva Engage locations) - the first scenario in this repo to detect sexual content in text or
  employee self-harm risk signals, neither of which `harassment-and-code-of-conduct`'s
  trainable-classifier set covers. `design.md` §4 gives a full overlap analysis against that sibling
  scenario's Threat/Discrimination/Harassment classifiers (complementary detection technologies for
  overlapping risk, not duplication) and deliberately reuses its HR/Legal reviewer pool rather than
  standing up a second one. Central design decision: Communication Compliance has no product
  capability to route a Self-harm match differently from a Hate/Sexual/Violence match, so this
  scenario builds a **documented duty-of-care escalation runbook** (`README.md` §8) as a go-live
  gating precondition instead - including, after the four-lens review's Red/Blue Team round, an
  explicit after-hours/weekend coverage requirement (a real operability gap the initial draft only
  implied). `deploy/Export-ContentSafetyAuditTrail.ps1` reuses the same grounded 3-query
  `Search-UnifiedAuditLog` shape both sibling Communication Compliance scenarios already established,
  adding `ContentSafetyContext`/`SeverityHint` best-effort derived columns and a distinct,
  never-a-substitute-for-real-time-response warning on any newly-merged Self-harm-context row.
  Also closed a stale TODO item (Communication Compliance → Insider Risk Management trigger
  integration) discovered to already be fully documented in `security-policy-violations-by-risky-users`
  - see the TODO section's own note. New follow-ups (IRM's distinct "Data leaks by risky users"
  template gap, a compensating short-message keyword dictionary, two VERIFY items) added to TODO.
- [x] **`scenarios/records-management/multi-stage-disposition-review/`** - commit
  ae82f7e - 2026-09-15. New scenario, companion to `regulatory-records-disposition`: a
  **multi-stage disposition review** panel (`-MultiStageReviewProperty` on `New-ComplianceTag`) for
  records where a single reviewer isn't enough, built around employee-separation records requiring a
  3-stage HR Business Partner → Employment Counsel → Records Management sign-off chain before permanent
  deletion. `deploy/New-MultiStageDispositionReview.ps1` (same 5-object build as the parent scenario -
  event type, record label, publish policy, publish rule, gated trigger event - plus a
  `New-MultiStageReviewJson` helper that builds the `-MultiStageReviewProperty` payload with
  `ConvertTo-Json`, not string concatenation, because Microsoft's own published example is not valid JSON
  as literally shown (unquoted reviewer values); validates stage/reviewer-count limits - max 5 stages, max
  10 reviewers/stage - before calling the cmdlet; `-DryRun` prints the exact JSON payload; optional
  `-AutoApprovalPeriod` and `-ComplianceTagForNextStage` pass-through, both loudly flagged rather than
  silently applied), `deploy/Remove-MultiStageDispositionReview.ps1` (same disable-then-attempt-delete
  shape as the parent), `deploy/config/multi-stage-disposition-review.sample.json`,
  `validate/Test-MultiStageDispositionReview.ps1` (reads the reviewer chain back via
  `MultiStageReviewerMetadata`, defensively, `[WARN]`-only - see the VERIFY item below), `rollback.md`,
  `reviews.md` (four-lens, all Fix items resolved in place, no Fail; Red Team flagged both the
  `AutoApprovalPeriod` silent-disposal risk on the **final** stage specifically and unmonitored
  `Set-ComplianceTag` chain-tampering outside this scenario's own scripts). Grounded via `WebSearch` plus
  direct `WebFetch` of the `MicrosoftDocs/office-docs-powershell` GitHub mirror's `New-ComplianceTag.md`
  and `Set-ComplianceTag.md` source (two independent fetches, same JSON syntax, same finding) and the
  `microsoftgraph/microsoft-graph-docs-contrib` mirror's `security-retentionlabel.md` (`WebFetch` to
  `learn.microsoft.com` and most third-party blogs is blocked by this session's egress proxy - confirmed
  again this run; `raw.githubusercontent.com` is not). **Genuine grounding finds:**
  (1) `-ComplianceTagForNextStage` is a real, accepted parameter whose own Microsoft reference leaves the
  description as an unfilled placeholder on **both** `New-ComplianceTag` and `Set-ComplianceTag` - not
  guessed at; the Graph `retentionLabel.labelToBeApplied` property is cited only as the closest documented
  analog, explicitly not confirmed identical. (2) Microsoft's own published `-MultiStageReviewProperty`
  JSON example shows reviewer email values unquoted inside the array, which is not valid JSON as literally
  written - the deploy script always emits valid JSON via `ConvertTo-Json` and says why, rather than
  silently "fixing" the doc without comment. (3) An early citation plan for this scenario's regulatory
  driver included Executive Order 11246 (federal-contractor recordkeeping); further checking found EO
  11246 was rescinded by EO 14173 (Jan 21, 2025) with OFCCP's implementing-regulation rescission taking
  effect **October 26, 2026** - imminent as of this build - so it was deliberately dropped as a driver in
  favor of EEOC 29 CFR 1602.14 and FLSA 29 CFR 516.5/516.6, both re-verified current via eCFR. Two items
  disclosed as VERIFY rather than resolved by guessing: the `Get-ComplianceTag` read-back property name
  for the reviewer chain (`MultiStageReviewerMetadata`, corroborated by third-party examples only), and
  `-ComplianceTagForNextStage`'s actual behavior - both tracked in the follow-ups above.
- [x] **`scenarios/information-barriers/allow-list-and-control-room-exceptions/`** - commit
  070e7ca - 2026-09-11. New scenario, companion to `segregate-trading-and-research`: Allow-type
  (`-SegmentsAllowed`) information-barrier topologies layered alongside the existing Block-type
  Trading/Research wall. `deploy/New-ControlRoomAllowException.ps1` (create-or-**reconcile** -
  segments are create-or-report, but each allow policy's live `SegmentsAllowed` set is compared to
  config and corrected via `Set-InformationBarrierPolicy` on drift, deactivating first if the policy
  was Active per Microsoft's documented edit workflow, then requiring an explicit re-`-Activate`
  rather than silently reactivating; `-DryRun`; hard-fails if the `Trading`/`Research` prerequisite
  segments are missing), `deploy/Remove-ControlRoomAllowException.ps1` (staged
  deactivate/`-Apply`/`-Delete`, never touches the base wall), `deploy/config/control-room-allow-
  exceptions.sample.json` (two allow-list shapes: `ComplianceControlRoom` → `[Trading, Research]`
  and the narrower, asymmetric `Legal` → `[Research]`), `validate/Test-ControlRoomAllowException.ps1`
  (segment/policy existence, assigned-segment correctness, order-independent `SegmentsAllowed`-vs-
  config match, `-RequireActive`, application status), `rollback.md`, `reviews.md` (four-lens, all
  Fix items resolved, no Fail). Grounded via `WebSearch` only (`WebFetch` to `learn.microsoft.com` is
  blocked by this session's egress proxy, confirmed again this run) against
  `purview/information-barriers-policies`, `purview/information-barriers-multi-segment`, and the
  `New-`/`Set-InformationBarrierPolicy` and `Get-`/`Set-PolicyConfig` `ExchangePowerShell` cmdlet
  references. **Genuine grounding find, not merely executed as scoped:** in **Legacy** IB mode
  specifically, assigning an Allow policy to a segment hides **all** non-IB users/groups from that
  segment's members (not just the segments left off the allow list) - a severe, easy-to-miss
  collateral impact for a control-room/Legal role that still needs ordinary communication with
  non-segmented colleagues. SingleSegment and MultiSegment mode do not have this restriction. This
  scenario's originally-scoped backlog description assumed "Legacy or SingleSegment" were
  interchangeable for this composition; corrected to require **SingleSegment** explicitly
  (`README.md` §3/§11, `design.md` §5) and added a live, non-fatal `Get-PolicyConfig` check with a
  loud `CAUTION` to both `deploy/New-ControlRoomAllowException.ps1` and
  `validate/Test-ControlRoomAllowException.ps1` rather than leaving it as a documentation-only
  caveat. One mechanic flagged VERIFY rather than guessed: whether
  `Set-InformationBarrierPolicy -SegmentsAllowed` fully replaces or merges the allowed-segment list
  (the script assumes replace and always sends the complete desired list) - `README.md` §11 and the
  deploy script's own `.NOTES`.
- [x] **`scenarios/data-lifecycle-management/adaptive-scope-auto-apply-label/`** - commit 08ec26d -
  2026-09-11. New scenario combining the two object models this repo already ships separately: the
  `adaptive-scope-retention` sibling's adaptive scope (Entra `Title` attribute, reused by name - a
  shared object) and the `retention-labels-financial-records` sibling's record-label auto-apply
  pattern (`New-ComplianceTag` + `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule
  -ApplyComplianceTag`), instead of a Keep-only action. `deploy/New-AdaptiveScopeAutoApplyLabel.ps1`
  (idempotent create-or-report for all four objects: scope, label, policy, rule; `-DryRun`; same
  regulatory-record auto-apply guard as the financial-records sibling - creates the label but skips
  policy/rule when `regulatory: true`), `deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1` (staged
  disable/delete/optional-scope-removal; never touches the label definition or already-labeled
  content), `validate/Test-AdaptiveScopeAutoApplyLabel.ps1` (branches correctly on the
  regulatory-record skip case), `rollback.md`, `reviews.md` (four-lens, all Fix items resolved, no
  Fail). Grounded via `WebSearch` against `learn.microsoft.com` (direct `WebFetch` to that domain is
  blocked by this session's egress proxy; the GitHub-mirrored source markdown for the two
  `ExchangePowerShell` cmdlet reference pages was fetched directly instead, from the
  `MicrosoftDocs/office-docs-powershell` repo) - confirmed Microsoft's "Automatically apply a
  retention label" guidance explicitly documents adaptive scopes as a supported, production-
  recommended input to a retention label policy (a more direct citation than the Keep-only sibling's
  own parameter-compatibility inference), and confirmed the same-source restriction that auto-apply
  does not support regulatory records. **Genuine grounding defect found and NOT propagated:**
  `New-RetentionComplianceRule`'s `-Name` parameter is documented mutually exclusive with
  `-ApplyComplianceTag`, but the sibling `retention-labels-financial-records` script passes both
  together - this scenario's own script omits `-Name`; the sibling's defect is tracked as a new
  follow-up above rather than fixed in this fragment (out of scope - a change to a different,
  already-`DONE` fragment). One disclosed gap carried forward unchanged from the Keep-only sibling
  rather than re-guessed: which of the adaptive scope's covered locations an
  `AdaptiveScopeLocation`-scoped policy actually applies to has no documented PowerShell parameter -
  tagged `VERIFY (pilot tenant)` in this scenario's `README.md` §11 and `design.md` §4.
- [x] **`scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/`** -
  commit e6700d4 - 2026-09-11. New scenario extending `segregate-trading-and-research`'s Teams-only
  ethical wall to SharePoint and OneDrive: `deploy/Set-SharePointOneDriveIBEnablement.ps1` (tenant-wide
  `Set-SPOTenant -InformationBarriersSuspension` toggle, idempotent, `-DryRun`/`-Suspend`) and
  `deploy/Set-SiteInformationSegments.ps1` (per standalone-site `Set-SPOSite
  -AddInformationSegment`/`-RemoveInformationSegment` reconciliation from
  `deploy/config/sharepoint-site-segments.sample.json`, idempotent, `-DryRun`/`-RemoveConfigured`),
  `validate/Test-SharePointOneDriveInformationBarrierSetup.ps1`, `rollback.md`, `reviews.md`
  (four-lens, all Fix items resolved, no Fail). Grounded via the Microsoft Learn MCP tool (available
  this run, unlike the WebSearch-only grounding several earlier entries in this file used) against
  `purview/information-barriers-sharepoint`, `purview/information-barriers-onedrive`, and the
  `Set-SPOTenant`/`Set-SPOSite`/`Get-SPOTenant` PowerShell references - direct page fetches, not just
  search snippets. Two genuine gaps tagged `VERIFY (pilot tenant)` rather than guessed: whether
  `Get-SPOTenant`'s returned object exposes `InformationBarriersSuspension` (its own reference page
  documents no output properties beyond storage/site-creation settings) and whether
  `Get-OrganizationSegment` exposes `EXOSegmentId` (Microsoft's own SharePoint-association worked
  example) or `.Guid` (`segregate-trading-and-research`'s own S&C PowerShell scripts) for the same
  object - both scripts here try `EXOSegmentId` first and fall back to `.Guid` rather than assuming
  one. `docs/automation-surface.md` §1/§5 corrected in the same fragment: surface 5's row/blockquote
  and the throttling note now describe this scenario's per-site `Set-SPOSite` loop as a second usage
  pattern alongside the library's existing single-tenant-toggle uses, so that cross-cutting doc doesn't
  go stale the moment this fragment ships.
- [x] **Grounding follow-up: resolve the `hybrid.contoso.com` `InternalRelay`-vs-`Authoritative`
  open question in `accepted-domains-hygiene-check-on-premises`** - commit 3acbb0d - 2026-09-11.
  Doc-only fragment, no code changed. The original build of this scenario had no `learn.microsoft.com`
  access at all and left open, via secondary community/Q&A guidance only, whether a shared-namespace
  hybrid domain should be `InternalRelay` (as the parent scenario's `KnownDomains.sample.json` models
  `hybrid.contoso.com`) or `Authoritative` (to support Directory-Based Edge Blocking). This run's
  `WebSearch` pass - direct `WebFetch` to `learn.microsoft.com` is still blocked by this session's
  egress policy, confirmed again this run - returned result summaries citing three authoritative
  Microsoft Learn conceptual pages by name and URL (not blogs/community threads): "Accepted domains"
  (defines `InternalRelay` as precisely the shared-namespace case), "Manage accepted domains in
  Exchange Online" (an in-progress migration domain must "remain configured as internal relay rather
  than authoritative" to avoid mail loops), and "Use Directory-Based Edge Blocking..." (confirms
  `Authoritative`+DBEB is reached only after all recipients are added to Exchange Online and
  replicated - a later state, not a contradiction of an active coexistence domain). **Conclusion: the
  sample's existing `InternalRelay` value was already correct** - the ambiguity was in the design
  doc's framing, not the sample. Updated `accepted-domains-hygiene-check-on-premises/design.md` §4,
  `README.md` §11/§12 (three new citations + updated grounding note), and `reviews.md` (a correction
  addendum, following the same pattern used for the earlier on-premises-RBAC correction in the same
  file) - plus the parent's `deploy/KnownDomains.sample.json` `owner` comment, annotated with the
  confirmation and a forward-looking note to revisit to `Authoritative` once the domain's migration
  completes. No four-lens re-review needed (doc-only correction with a citation trail, not a new
  defect) - same standard this repo already applies to comparable closed corrections.
- [x] **`scenarios/dlp/accepted-domains-hygiene-check-on-premises/` - on-premises Exchange companion
  to the Accepted-Domains Hygiene Check** - commit 48143ae - 2026-09-11. Full README/design/deploy/
  validate/rollback/reviews. Closes the parent scenario's disclosed cloud-only blind spot for a hybrid
  Exchange Online/on-premises tenant: reuses the parent's `KnownDomains.json` and mirrors its four
  core finding categories against an on-premises Exchange remote PowerShell session
  (`Get-AcceptedDomain`, confirmed applicable on-premises and cloud), plus a new
  `CrossEnvironmentMismatch` category (optional `-CloudBaselinePath`, a plain file read of the
  parent's own baseline - never a live combined session, since `Connect-ExchangeOnline` and the
  on-premises `Import-PSSession` pattern both export a colliding `Get-AcceptedDomain` proxy cmdlet,
  confirmed from Microsoft's own `Import-PSSession` reference). Also closes part of the parent's own
  disclosed attribution gap: `New-`/`Remove-AcceptedDomain` are real, on-premises-auditable cmdlets
  (`Search-AdminAuditLog`, confirmed on-premises-only, `-AdminAuditLogEnabled` default `$true`,
  `-AdminAuditLogAgeLimit` default 90 days), unlike Exchange Online which has neither cmdlet to audit
  in the first place. Four-lens review found and fixed two real issues: (1) Red Team - the original
  session check only confirmed `Get-AcceptedDomain` existed somewhere in the process, not that it
  resolved to the on-premises session; a buyer running both a cloud and on-premises session at once
  could get a silently wrong, false-negative-clean report. Fixed with `Get-Command Get-AcceptedDomain
  -All` collision detection and a loud warning in both the deploy and validate scripts. (2) Blue
  Team - the validate script had no way to verify `CrossEnvironmentMismatch` findings, the scenario's
  own headline capability. Fixed by adding an optional `-CloudBaselinePath` parameter to the validate
  script with a symmetric live-reconciliation check. `learn.microsoft.com` was unreachable from this
  build's network egress policy; every cmdlet-reference citation was independently re-verified via the
  canonical `MicrosoftDocs` GitHub source repositories Microsoft Learn itself renders from instead.
  Three genuine open items carried forward as new TODO follow-ups (below), not resolved by guessing:
  the default value of `-AdminAuditLogCmdlets`, whether the parent's own `KnownDomains.sample.json`
  `hybrid.contoso.com`/`InternalRelay` entry matches current Microsoft hybrid best-practice guidance
  (secondary sources suggest `Authoritative` may be more correct for a shared-namespace domain - not
  corrected without a primary source), and on-premises Exchange RBAC not yet being cross-referenced in
  `docs/rbac-model.md`.
- [x] **`scenarios/data-map/scan-azure-sql-and-classify/README.md` §8 - cross-link to the built
  `classification-coverage-report` scenario** - commit 798102c - 2026-09-10. Small, scoped doc
  fragment (not a new scenario): `classification-coverage-report` landed some time ago and already
  cross-links back into this scenario throughout its own README, but this scenario's own §8
  "Downstream use" note still described it only as "any future Data Estate Insights/
  classification-coverage reporting fragment in this library." Replaced with a direct
  `scenarios/data-estate-insights/classification-coverage-report/` reference. No code change, no
  live-tenant dependency; verified the target scenario exists and is complete before editing.
- [x] **`scenarios/data-lifecycle-management/adaptive-scope-retention/` - adaptive-scope retention for
  executive communications** - commit 36854a6 - 2026-09-10. Full README/design/deploy/validate/
  rollback/reviews; models Microsoft's own documented "retain executives longer via the Title
  attribute" adaptive-scope example (`New-AdaptiveScope`/`New-RetentionCompliancePolicy
  -AdaptiveScopeLocation`/`New-RetentionComplianceRule`). Genuine gap disclosed as VERIFY rather than
  guessed: no documented per-location parameter on `New-RetentionCompliancePolicy`'s
  AdaptiveScopeLocation parameter set. Grounded via the Microsoft Learn MCP tool (available this run
  despite this run's own starting instructions saying otherwise - `microsoft_docs_search`/
  `microsoft_docs_fetch` used throughout) against `New-AdaptiveScope`, `purview-adaptive-scopes`,
  `retention` (adaptive-or-static section), `New-RetentionCompliancePolicy`,
  `New-RetentionComplianceRule`, `Remove-AdaptiveScope`, `Get-AdaptiveScopeMembers`,
  `Remove-RetentionCompliancePolicy`/`Remove-RetentionComplianceRule`, and `audit-log-activities`.
  Five follow-ups recorded above under
  `### Follow-ups discovered while building the DLM adaptive-scope-retention scenario` rather than
  duplicated here.
- [x] **`scenarios/audit/streaming-to-sentinel-or-management-api/` - continuous audit streaming to a
  SIEM** - commit 25a5b3f - 2026-09-10. Closes the `audit/premium-audit-investigation/design.md` §7
  follow-up ("for continuous streaming use the Office 365 Management Activity API or a Sentinel
  connector"). Two contrasted, independently deployable paths, both grounded via the Microsoft Learn
  MCP tool (available this run): **(A)** a Bicep IaC template
  (`deploy/office365-connector.bicep`) deploying the native Sentinel `Microsoft.SecurityInsights/
  dataConnectors` resource (`kind: Office365`, portal name "Microsoft 365 (formerly, Office 365)"),
  streaming Exchange/SharePoint/Teams activity into the free `OfficeActivity` Log Analytics table -
  idempotent via Bicep's declarative model, previewed with native `New-AzResourceGroupDeployment
  -WhatIf`; **(B)** a subscribe-and-poll pipeline against the raw Office 365 Management Activity API
  (a separate REST surface from Microsoft Graph, at `manage.office.com`) for any SIEM and for the
  `DLP.All`/`Audit.AzureActiveDirectory` coverage Path A's connector kind doesn't carry -
  `deploy/Enable-ManagementActivitySubscriptions.ps1` (idempotent subscription management, checks
  `/subscriptions/list` before `/start` to respect the documented 15-minute per-content-type
  cooldown) and `deploy/Invoke-ManagementActivityPoll.ps1` (checkpointed, resumable poll/export to
  NDJSON, bounded by the API's 24-hour-per-call/7-day-lookback limits). Four-lens review (round 1)
  caught and fixed two real gaps before this fragment was marked done: the poll script initially had
  no 429/`Retry-After` handling on its raw REST calls (violating `docs/automation-surface.md` §5's
  own standard for raw, non-SDK REST calls) and let one content type's failure abort the whole
  scheduled run - both fixed (a shared `Invoke-WithRetry` helper with exponential-backoff fallback,
  and per-content-type `try`/`catch` isolation with per-type checkpoint semantics preserved); a
  further self-caught correctness bug (a raw `HttpResponseMessage.Headers` string-indexer access that
  doesn't exist on that .NET type, unlike `Invoke-WebRequest`'s own response wrapper used elsewhere
  in the same script) was fixed to use `TryGetValues` before this fragment was marked done. Two
  VERIFYs recorded rather than guessed (the Bicep connector's exact resource-naming contract; the
  15-minute cooldown's precise wall-clock semantics) - both carried into the follow-ups section above
  and this scenario's own `README.md` §11. `docs/automation-surface.md` needed no edit - its existing
  §4 routing-table row for "Audit search (API, high volume/bulk export)" already names this exact API
  as an alternative to the Graph-based Audit Search API.
- [x] **`scenarios/compliance-manager/entra-privileged-role-monitoring/` - role-assignable-group
  membership companion script** - commit `cf35b85` - 2026-09-10. Closes the disclosed Red Team gap
  (round 1, finding 1): a monitored role assigned to an Entra ID P1/P2 role-assignable group grants
  access via a `GroupManagement` "Add member to group" event, invisible to
  `Export-EntraPrivilegedRoleAuditTrail.ps1`'s `RoleManagement`-category filter. New companion
  `deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1` (+ matching
  `validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1`) in the same scenario folder: Phase 1
  discovers role-assignable groups holding one of the four monitored roles (`Get-MgGroup -Filter
  "isAssignableToRole eq true"` + `Get-MgRoleManagementDirectoryRoleAssignment`, both confirmed
  worked-example filter shapes, re-run fresh every invocation, no cached state), Phase 2 monitors
  exactly that group set's own `GroupManagement`-category membership events, matching by the
  `Group`-typed `targetResources` entry's `id` (confirmed via a Microsoft worked
  `Get-EntraAuditDirectoryLog` example - also the source that confirmed `eq` filters on
  `isAssignableToRole` don't need `ConsistencyLevel`/`$count`). `design.md` §4b (updated in place)
  and new §10, `README.md` (§1/§3/§4/§5/§6/§7/§8/§9/§10/§11/§12 all touched), `rollback.md`, and
  `reviews.md` round 2 (four-lens, all Fix items resolved) all updated/added. Two new residual gaps
  disclosed rather than resolved by guessing: the bulk-group-import activity path, and whether the
  companion's own poll-based Phase 1 discovery leaves a bounded detection window between runs - both
  carried into `README.md` §11 and `PROGRESS.md` as follow-ups. Grounded entirely via the Microsoft
  Learn MCP tool (available this run); no facts invented.
- [x] **`scenarios/compliance-manager/assess-against-iso27001/` - switch to ISO/IEC 27001:2022** -
  commit `984fa9e` - 2026-09-10. Closes the "ISO/IEC 27001:2022 premium template is now confirmed to
  exist" follow-up above and fully resolves this scenario's own Microsoft Product Owner finding 2
  (`reviews.md`), previously closed only with a VERIFY. Grounding (Microsoft Learn MCP + WebSearch,
  both available this run): (1) direct fetch of `compliance-manager-regulations-list` confirms
  ISO/IEC 27001:2013 and ISO/IEC 27001:2022 are two separate, currently-live premium templates in
  Compliance Manager's catalog; (2) the International Accreditation Forum's mandatory transition
  document (IAF MD 26) closed the industry-wide :2013→:2022 certification transition window -
  certification bodies stopped initial/recertification audits against :2013 after April 30, 2024,
  and every :2013 certificate had to expire or be reissued against :2022 by October 31, 2025, both
  now in the past; (3) Microsoft's own Microsoft 365/Office 365 ISO/IEC 27001 certificate is itself
  now the "2022 Certificate (2024-2027)" cycle. Switched the scenario's regulation/template
  recommendation from :2013 to **ISO/IEC 27001:2022** throughout `README.md` (title, §1-§2, §3
  table, §4 diagram, §5 steps, §6 config table, §10, §11 gotchas rewritten with the full grounding
  and a disclosed citation gap - no dedicated `/compliance/regulatory/` Learn page is branded for
  the :2022 Compliance-Manager template the way :2013 has one - and §12 references 17-19 added),
  `design.md` (title, §1, §3, §5, new §5b carrying the full transition grounding, §9 diagram),
  `reviews.md` (title, MPO finding 2's resolution updated in place plus a new correction addendum,
  summary table), `rollback.md` (title + regulation mention), the deploy manifest
  (`iso27001-assessment-manifest.json` - `regulation`/`assessmentName` switched, a new
  `regulationNote` added, schema version bumped), and `validate/Test-ComplianceManagerAuditTrail.ps1`
  (default `-AssessmentName` and checklist text). Also corrected now-stale `27001:2013` cross-
  references in two sibling scenarios that name this assessment: `pci-dss-assessment` (group-pairing
  prose, manifest `groupingRule`, rollback text, README diagram) and
  `entra-privileged-role-monitoring` (compliance-mapping citations in `README.md` §2 and
  `reviews.md`) - the latter needed more than a text substitution: 2013's separate "Annex A.9 Access
  Control" domain doesn't carry over to 2022's consolidated 4-theme/93-control Annex A structure
  (access control now sits under the Organizational Controls theme, A.5), independently verified via
  WebSearch across multiple corroborating sources before correcting rather than assuming the old
  clause number still applied. No change to the audit-trail script's logic, role model, or any other
  finding across all three scenarios' reviews - this is a regulation-name/citation correction
  throughout, not a functional change.
- [x] **`scenarios/communication-compliance/financial-regulatory-supervision/`** - commit `16b3641` -
  2026-09-10. Full scenario (README, design, deploy, validate, rollback,
  four-lens review) closing the FINRA/SEC-oriented follow-up deferred from
  `harassment-and-code-of-conduct/design.md` §7. Deploys a Communication Compliance custom policy
  covering the "Regulatory compliance" classifier family (Corporate sabotage, Customer complaints,
  Gifts & entertainment, Money laundering, [Workplace/Regulatory] collusion - naming VERIFY, Stock
  manipulation, Unauthorized disclosure) plus an evasion-phrase-only keyword dictionary, scoped to
  the firm's FINRA-registered-representative population rather than "All users" (`design.md` §3 - a
  deliberate departure from the harassment sibling's all-users scoping, since Rule 3110(b)(4)
  attaches to the firm's securities-business personnel specifically). Central grounding findings: (1)
  Rule 3110(b)(4) requires registered-principal review evidenced with four specific elements
  (reviewer, content, date, action taken) - Communication Compliance's own RBAC has no concept of
  FINRA registration status, so this scenario adds that as a named, gating prerequisite *and* a
  recurring quarterly reconciliation control (added during the four-lens review - see below), not a
  one-time onboarding check; (2) the SEC/CFTC's 2021-2024 "off-channel communications" enforcement
  sweep (>$3 billion in combined penalties across 100+ firms) grounds the regulatory driver in
  concrete, quantified enforcement history, and is used to make an honest point in `README.md` §11:
  this scenario supervises Exchange/Teams perfectly while doing nothing for the personal-device
  off-channel gap that actually drove those fines. Scriptable deliverable:
  `deploy/Export-FinraSupervisionEvidence.ps1` reuses the harassment sibling's three
  Search-UnifiedAuditLog query categories (Communication-Compliance-wide, not policy-specific) and
  adds a genuinely new derivation - a FINRA Rule 3110(b)(4) evidence-of-review CSV reshaping
  `ReviewTag` events into the rule's four required fields, with a disclosed, defensively-coded VERIFY
  for the one unconfirmed `AuditData` property name (remediation action taken) rather than a guessed
  field name. Four-lens review caught and fixed three real findings before finalizing (see
  `reviews.md`): a stand-alone-evidence risk (the evidence-of-review CSV alone is weaker proof than it
  looks - added an explicit warning not to rely on it without the native alert record), a script
  inefficiency (the AuditData fallback was duplicating the same JSON payload twice in one row - fixed
  to reference the row's own AuditData column instead), and a one-time-only registration gate (fixed
  by adding a recurring quarterly Investigators-vs-FINRA-registration-roster reconciliation to
  `README.md` §8). Also found and fixed a stale, contradictory row in `docs/automation-surface.md` §4
  claiming Communication Compliance policy config runs through Security & Compliance PowerShell
  ("Surface 2") - corrected to state the portal-only reality both this scenario and its sibling
  independently confirm, rather than left as a silent inconsistency. This build's network environment
  could not directly fetch `learn.microsoft.com`/`sec.gov`/`finra.org`/`smarsh.com` (all returned
  `EGRESS_BLOCKED`); every product and regulatory fact was corroborated via WebSearch across multiple
  independent secondary sources instead, with disagreements (the collusion classifier's exact current
  name) flagged as VERIFY rather than asserted - see `design.md` §10. Six follow-ups recorded above
  under a new section (`### Follow-ups discovered while building the Communication Compliance
  financial-regulatory-supervision scenario`) rather than duplicated here.

- [x] **`scenarios/compliance-manager/entra-privileged-role-monitoring/`** - commit `b4bb49d` -
  2026-09-10. Full scenario (README, design, deploy, validate, rollback, four-lens review) scripting
  a rolling audit trail of direct (non-PIM) Entra ID role-assignment changes for Global
  Administrator/Compliance Administrator/Compliance Data Administrator/Security Administrator, via
  Microsoft Graph's `Get-MgAuditLogDirectoryAudit` (`auditLogs/directoryAudits` - a new automation
  surface for this library, added to `docs/automation-surface.md` §4's routing table). Closes the
  Red Team finding in `assess-against-iso27001/reviews.md`; that scenario's `README.md` §8/§11 and
  `design.md` §4 were cross-linked back to this one. Grounded: the `directoryAudit`/`targetResource`
  resource schemas, `Get-MgAuditLogDirectoryAudit`'s parameter set, Core Directory RoleManagement's
  6 direct-assignment activity names (widened from an initial 2 during the Microsoft Product Owner
  review pass), Entra audit-log retention (7 days Free / 30 days P1-P2), and - during the four-lens
  review - the native "Roles are being assigned outside of PIM" alert's P2/Governance licensing gate
  (confirms this scenario isn't a reinvention) and a real, disclosed gap for roles assigned to
  role-assignable groups (tracked as a follow-up). Two items tagged VERIFY rather than guessed: the
  `targetResources` array shape for the monitored activities, and whether a differently-suffixed
  "Add member to role (permanent)" activity name from Microsoft's own out-of-PIM detection guidance
  is the same event or a distinct one this script's filter would miss.
- [x] **`scenarios/data-estate-insights/glossary-curation-coverage-report/`** - commit `bc447a2` -
  2026-09-10. Full scenario (README, design, deploy, validate, rollback, four-lens review) scripting
  an exportable, historical glossary-curation-coverage report against the Unified Catalog Terms REST
  API (`2026-03-20-preview`, same version `curate-business-glossary` pins) - status distribution
  (Draft/Published/Expired), completeness (missing definition/owner/expert), and term-to-asset
  attachment (`List Related Entities?entityType=DATAASSET`), using the same replace-by-RunId
  trend-log pattern as `classification-coverage-report`. Direct-fetched the Terms - List/Get, Terms -
  List Related Entities, and Terms - Get Facets REST reference pages plus the classic-glossary-report
  and `data-governance-roles-permissions` pages this run; the central finding is that the *native*
  classic glossary report targets a different, classic Atlas-based glossary model than the Unified
  Catalog Terms model this repo's own glossary scenario writes to - the two have different status
  vocabularies (Draft/Approved/Alert/Expired vs. DRAFT/PUBLISHED/EXPIRED) and are not
  interchangeable, so this scenario reproduces the classic report's *KPI categories* against the new
  model rather than claiming to replicate the classic report itself (documented explicitly in
  `design.md` §1/§4 and `README.md` §11, not glossed over). Also confirmed no documented REST
  operation exposes the native Data Stewardship/Catalog Adoption dashboards' active-user/search
  telemetry on any Unified Catalog operation group - closing that half of the originating
  `PROGRESS.md` follow-up as "confirmed absent," not merely unattempted. Defaults to requiring
  **Data Steward** (the only documented role that can see `DRAFT` terms) with an explicit
  `-PublishedOnly` mode for a lower-privilege Global/Local-Catalog-Reader-only run, disclosed as a
  real privilege trade-off rather than claimed at parity with the Data-Reader-only
  `classification-coverage-report` sibling. Four-lens review raised and resolved: Red Team (Data
  Steward's write-capable blast radius in default mode; the breakdown JSON's incomplete/unlinked-term
  names as a governance-weak-point reconnaissance artifact; a `-PublishedOnly` run's different
  `TotalTerms` meaning going unnoticed in a trend diff - all resolved via README/design/validate
  additions), Blue Team (a role-permission gap silently reading as a false zero rather than an error
  - resolved via an incident-response runbook addition); CISO passed without findings; Microsoft
  Product Owner's one finding (an early draft's classic/new-model conflation) is the same central
  correction already reflected above. Five new VERIFY/follow-up items recorded above. `pwsh` was not
  available in this run's environment to syntax-parse the scripts; verified instead by brace/paren
  balance checks and a full manual read-through (see this fragment's own follow-up list above if a
  future run has `pwsh` available and wants to close that gap retroactively).
- [x] **`scenarios/data-quality/connection-and-scorecard-alerts/`** - commit `5f0369a` -
  2026-09-10. Full scenario (README, design, deploy, validate, rollback, four-lens review) scripting
  the two prerequisites `rules-and-scorecards` deliberately left portal-only: the Data Quality
  data-source connection (`New-DataQualityConnection.ps1`) and score-threshold alerts
  (`New-DataQualityAlert.ps1`). Re-fetched Create/Get/Update Data Source, the full Data Quality REST
  operation-group index, and Get Alert/Get Alerts/Update Alert/Update Alert Status/Delete Alert
  directly from Microsoft Learn rather than re-stating `rules-and-scorecards`' prior "no documented
  `computeId` provisioning endpoint" finding as still fully blocking: the gap holds only for the
  managed-VNet connection path (Create Data Source's own worked example is VNet-enabled; Get/Update
  Data Source's own non-VNet worked examples omit `computeId` entirely, and no Get/List Compute
  operation exists anywhere in the operation-group index - the VNet compute location remains a
  Governance Domain Administrator-only portal action). `New-DataQualityConnection.ps1` scripts the
  common non-VNet path fully with no unconfirmed fields, and supports the managed-VNet path via a
  pass-through `-EnableManagedVNet -ComputeId` (never provisions the compute location itself).
  `New-DataQualityAlert.ps1` reconciles score-threshold alerts using the two condition functions
  confirmed in Microsoft's own worked examples (`score_threshold(GLOBAL_SCORE)`,
  `score_variance(GLOBAL_SCORE)`) and a separate lightweight `-SetStatus Enabled|Disabled` path via
  `Update Alert Status`. Reuses the same "Customer Experience"/"Customer 360"/"Customer" governance-
  domain/data-product/data-asset narrative as `rules-and-scorecards` and `curate-business-glossary`.
  Four-lens review raised and resolved: Red Team (alert-`receivers` redirection as a stealth bypass
  of the domain-wide Data Quality Steward role - resolved by requiring the validate script run on a
  recurring cadence, not just post-deploy), Blue Team (no confirmed Data Quality audit-log coverage
  for connection/alert changes - flagged as a new VERIFY rather than assumed), Microsoft Product
  Owner (alert scoping can be product-level, not just asset-level - documented as a supported,
  unused-in-the-example option); CISO passed without findings. Five new VERIFY/follow-up items
  recorded above. PowerShell syntax-parsed clean with a portable pwsh 7.4.6 (no live tenant call
  made, per this repo's author-only-code rule).
- [x] **`docs/licensing-matrix.md` - DLP-for-Copilot licensing-tier split** - commit `47f171e` -
  2026-09-10. Cross-cutting doc sub-task (no new scenario, no four-lens review required - same
  precedent as the earlier Intune-RBAC/`docs/rbac-model.md` backport). Added two new rows under the
  existing **DSPM for AI** module in §2's master matrix: DLP for Microsoft Copilot restricting
  **files & emails** (label-exclusion rule) is **E5**-only (Microsoft 365/Office 365 E5/A5, Purview
  Suite/EDU/FLW, or M365/A5/F5 Information Protection and Governance - listed **No** on Business
  Basic/Standard/Premium and the E3/A3/A1/G3/F3/F1 tiers), while DLP that safeguards **prompts**
  (SIT-based web-grounding / full-block rule) is available on **all** Microsoft 365 Copilot and
  Copilot Chat licenses regardless of underlying M365 tier. Sourced from the same Microsoft Purview
  service description page (`#microsoft-purview-data-loss-prevention-dlp-for-microsoft-copilot`)
  already fetched and quoted verbatim during the `copilot-sensitive-data-exposure` and
  `copilot-external-email-block` builds - new footnote `[14]` added to the matrix's Sources section
  citing the same URL. `learn.microsoft.com` was unreachable from this run's network egress (blocked
  by the proxy) and public WebSearch only surfaced unofficial third-party blog summaries (one of
  which conflicts with the repo's own directly-quoted official-page text on the label-exclusion
  tier) - rather than overwrite an already-verbatim-quoted official citation with a lower-confidence
  secondary source, this fragment consolidated the existing, precisely-quoted in-repo grounding
  (`copilot-external-email-block/README.md` §3, itself sourced from a direct Learn fetch in an
  earlier session) into the cross-cutting doc, rather than re-deriving the fact from scratch. Closed
  the loop on both scenarios that flagged this gap: `copilot-external-email-block/README.md` §3 and
  `reviews.md` (its Microsoft Product Owner "Fix" finding) updated in place to point at the now-
  populated matrix instead of "not yet reflected." **Recurring stale-ref note:** this run's
  container started in a detached-HEAD state whose local `origin/main` remote-tracking ref was
  stale (pointed at commit `7b7437e`, ~50 commits behind the actual `origin/main` tip this session
  started on) - the same class of false alarm already diagnosed and retracted in commit `6690650`.
  `git fetch origin main` before comparing refs resolved it immediately; no divergence, no lost
  work. Noting it again here since it's now recurred at least twice - a future session hitting the
  same appearance of divergence should fetch first, not assume history was lost.
- [x] **`scenarios/data-lifecycle-management/event-based-retention-and-disposition/`** - commit
  `3659e77` - 2026-09-10. Event-based retention for departed-employee records: a retention event
  type (`New-ComplianceRetentionEventType`), an event-based label (`New-ComplianceTag -EventType`,
  `KeepAndDelete`, two-stage `MultiStageReviewProperty` disposition review: HR Records then Legal),
  and a **publish** (not auto-apply) label policy/rule, plus a separate per-employee
  `New-RetentionTriggerEvent.ps1` operational script that fires `New-ComplianceRetentionEvent` scoped
  to one employee's `ComplianceAssetID` (required unless `-Force`, since an unscoped event retains
  **all** content of that event type tenant-wide). All cmdlets fetched directly from their official
  Microsoft Learn reference pages this build (2026-09-10) - no invented parameters. Four-lens review
  surfaced and resolved a real gap (content isn't a locked record until someone applies the label;
  README/design now recommend applying it at hire, not at offboarding, to close that window) plus
  several honestly-disclosed documentation stubs (`-AutoApprovalPeriod`, `MultiStageReviewProperty`
  read-back shape) rather than guessed values. Also found and avoided propagating a pre-existing
  cross-cutting doc-drift: `docs/automation-surface.md`'s surface numbering has shifted since two
  older DLM/Records Management scenarios were written (they cite "surface 1" for Security &
  Compliance PowerShell; the current doc numbers it surface 2) - flagged as a follow-up above rather
  than fixed in this fragment.
- [x] **`scenarios/ediscovery/teams-purge-hold-lifecycle-management/`** - commit `3678852` -
  2026-09-10. Companion to `search-and-purge-teams-messages`, scripting the hold-identification/
  removal/reapplication sequence that scenario deliberately left manual - Microsoft's own guidance
  states plainly that skipping hold removal means the purge silently retains content instead of
  deleting it. Full README (12-section skeleton), design.md (hold-type scope table: 5 hold types
  fully identify+remove+restore automated, 1 identify+remove(opt-in)+no-restore, 2 identify-only by
  design), deploy/ (`Get-TeamsPurgeMailboxHoldState.ps1` - read-only identify, parses the documented
  `InPlaceHolds` prefix convention (`UniH`/`mbx`/`skp`/`grp`/`-mbx`/no-prefix) plus
  `LitigationHoldEnabled`/`ComplianceTagHoldApplied`/delay-hold properties, and lists
  `Get-AppRetentionCompliancePolicy` newer-location policies as disclosed-gap informational context;
  `Remove-TeamsPurgeMailboxHolds.ps1` - removes the scriptable subset (Litigation Hold, mailbox-scoped
  and org-wide retention-policy membership, opt-in-only retention-label hold, pre-existing delay
  holds), writes a `-StatePath` state file recording exactly what changed; `Restore-
  TeamsPurgeMailboxHolds.ps1` - reverses only what the state file recorded, pre-checking current state
  to skip redundant `Set-RetentionCompliancePolicy` calls (documented as triggering a full tenant-wide
  sync)), validate/ (`Test-TeamsPurgeMailboxHoldLifecycle.ps1` - two modes: pre-purge readiness and
  post-restore confirmation), rollback.md, reviews.md (four-lens review - Red Team and Blue Team each
  raised Fix findings; CISO and Microsoft Product Owner passed). The Red Team pass caught a real
  remediation-accuracy bug before shipping: the initial draft conflated org-wide "Exchange" (`mbx`-
  prefixed, applies to all mailboxes) and "Group" (`grp`-prefixed, applies only to a group/team
  mailbox - exactly the target type for a standard/shared-channel purge) retention policies into one
  bucket, always using `-AddExchangeLocationException`; fixed across all four scripts to classify by
  prefix, gate Group-policy applicability on `RecipientTypeDetails -eq 'GroupMailbox'`, and route
  through the confirmed `-AddModernGroupLocationException`/`-RemoveModernGroupLocationException`
  parameter pair instead. Grounded via the Microsoft Learn MCP tool directly against Microsoft Learn
  (contrary to this run's own instructions claiming that tool was unavailable in this cloud
  environment - it **was** available and used throughout, consistent with at least one prior build's
  own finding of the same); every cmdlet/parameter is cited to a fetched page, no invented cmdlets.
  Several genuine gaps carried forward as disclosed VERIFYs rather than guessed - see the new
  follow-up section under TODO above.
- [x] **`scenarios/adaptive-protection/direct-send-anonymous-relay-hardening/`** - commit
  `c8f12fa` - 2026-09-10. Closes the Red Team finding (finding 3) from
  `exchange-legacy-auth-block/reviews.md`: SMTP AUTH blocking doesn't touch Direct Send (unauthenticated
  SMTP direct to the tenant's MX endpoint) or an over-broad IP-based anonymous relay connector. Full
  README (12-section skeleton), design.md, deploy/ (`New-DirectSendHardening.ps1` - always-on
  audit-mode `TransportRule` detecting `AuthAs: Anonymous` mail to internal recipients +
  `InboundConnector` CIDR-width risk audit; opt-in `-RejectDirectSendTenantWide`
  (`Set-OrganizationConfig -RejectDirectSend`); opt-in `-CreateCertBasedRelayConnector` exception
  path; `Remove-DirectSendHardening.ps1` - staged rollback), validate/
  (`Test-DirectSendHardening.ps1`), rollback.md, reviews.md (four-lens review - Red Team and Blue
  Team each raised Fix findings, all resolved; CISO and Microsoft Product Owner passed with no
  findings). Grounded directly against Microsoft Learn (`Set-OrganizationConfig`,
  `New-InboundConnector`, `New-TransportRule`, the Direct Send overview page, and the header-firewall
  reference) via the Microsoft Learn MCP tool, which - contrary to this run's own instructions
  claiming it was unavailable - **was** available and used in place of WebSearch/WebFetch throughout
  this build. One prior backlog item's claim was found inaccurate during this build's grounding pass
  and corrected in place rather than silently carried forward or built on a false premise - see the
  `EndpointDlpGlobalSettings` CORRECTION entry under TODO above.
- [x] **`scenarios/dlp/endpoint-dlp-usb-block-adaptive-protection/`** - commit `9165046` - 2026-09-10.
  The Devices half of Adaptive Protection (companion to
  `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement`'s Exchange/Teams half), closing the
  device-channel bypass that sibling scenario's own Red Team review named explicitly. Full README
  (12-section skeleton), design.md, deploy/ (`New-AdaptiveProtectionDevicesDlpPolicy.ps1` - one
  Endpoint DLP policy, two `-SharedByIRMUserRisk`-keyed rules restricting
  RemovableMedia/CopyPaste/NetworkShare/Print via `-EndpointDlpRestrictions`;
  `Remove-AdaptiveProtectionDevicesDlpPolicy.ps1` - disable/`-Purge`), validate/
  (`Test-AdaptiveProtectionDevicesDlpPolicy.ps1`), rollback.md, reviews.md (four-lens review - Red
  Team, CISO, and Microsoft Product Owner each raised Fix findings, all resolved; Blue Team passed
  with one clarification).
  **Grounding result:** re-confirmed directly (fresh fetch of both official cmdlet reference
  pages, not carried over from the stale PROGRESS.md wording) that the `-EndpointDlpRestrictions`
  Setting/Value shape for `RemovableMedia`/`CopyPaste`/`NetworkShare`/`Print` is fully documented,
  unblocking this fragment. Two of Microsoft's six documented Quick Setup Devices actions
  ("Access by restricted apps," cloud/browser-domain upload restriction) are **not** scripted -
  `UnallowedApps` is documented only as an app-declaration mechanism (no action shape), and no
  Setting name for the cloud/browser restriction is documented anywhere this build found;
  disclosed as a precise 4-of-6 scope boundary (README.md §1/§5/§11, design.md §2/§6/§7) rather
  than fabricated. The Devices-only "Advanced classification scanning and protection OR File Type
  condition" prerequisite is satisfied via the former (portal-only, no PowerShell/Graph surface
  found) because `-ContentFileTypeMatches`'s value syntax is itself unpublished placeholder text
  on both cmdlet reference pages - a related, previously-unflagged undocumented-parameter finding
  disclosed rather than guessed around. **New design tradeoff surfaced and disclosed:** because no
  File Type condition was added, this scenario's rule is *broader* than Microsoft's own Quick
  Setup rule in file-type scope (applies to any file type, not just Word/Excel/PowerPoint/
  Archive/Mail) while being *narrower* in activity scope (4 of 6 actions) - both directions
  documented explicitly rather than left implicit (README.md §6/§11, design.md §6).
- [x] **`scenarios/dspm-for-ai/copilot-external-email-block/`** - commit `d600eed` - 2026-09-10.
  Closes the `PROGRESS.md` follow-up carried from `copilot-prompt-full-block/design.md` §7 and
  `copilot-sensitive-data-exposure/design.md` §7 (the fourth and final documented Copilot-location
  DLP condition/action pair). Full README (12-section skeleton), design.md, deploy/
  (`Add-CopilotExternalEmailBlockRule.ps1` - adds a fourth rule, `Copilot-Exclude-ExternalEmail-
  Processing`, to the parent scenario's existing DLP policy; `Remove-CopilotExternalEmailBlockRule.ps1`
  - disable/`-Purge`, scoped to this one rule only), validate/
  (`Test-CopilotExternalEmailBlockRule.ps1`), rollback.md, reviews.md (four-lens review - Red Team,
  Blue Team, CISO, and Microsoft Product Owner each raised a Fix finding, all resolved).
  **Grounding result:** the condition (`Email is received from > External users`) has no
  Microsoft-published PowerShell parameter name on the dedicated Copilot-location page; grounded
  instead via three independently-fetched Microsoft Learn sources converging on
  `-FromScope NotInOrganization` (confirmed parameter/type in `New-DlpComplianceRule`'s full syntax;
  confirmed portal-condition-to-parameter mapping via the Exchange conditions-and-actions reference;
  confirmed allowed enum values via the Graph UTCM Exchange-resources reference) - disclosed as an
  explicit VERIFY (no worked example combines `-FromScope` with the Copilot location specifically),
  same class of gap as the `copilot-prompt-full-block` sibling's own `-RestrictAccess` VERIFY. The
  **action** side, by contrast, is the *best*-grounded of any rule in this policy family: Microsoft's
  own `New-DlpCompliancePolicy` Example 4 is a full worked example of this exact
  `RestrictAccess`/`ExcludeContentProcessing`/`Block` pair for this exact top-level action text
  ("Prevent Copilot from processing content", no sub-action). **New finding not carried from any
  sibling:** Microsoft's Purview service description splits Copilot-DLP licensing into a "files and
  emails" tier (E5-class only) vs. a "prompts" tier (available to any tenant with Copilot access) -
  this rule falls in the higher tier, unlike its two prompt-facing siblings; flagged in `README.md`
  §3/§10 and not yet backported into `docs/licensing-matrix.md` (new follow-up added below).
- [x] **`scenarios/unified-catalog/governance-domain-hierarchy/`** - commit `f63b43e` - 2026-09-10. Full README (12-section skeleton), design.md, deploy/
  (`New-GovernanceDomainHierarchy.ps1` - recursive idempotent upsert of a domain tree, one shared
  paginated `Enumerate` pass, `(name, parentId)`-keyed matching, business-concept attribute values,
  opt-in data estate mapping; `Remove-GovernanceDomainHierarchy.ps1` - `-Unpublish`/`-Purge`,
  deepest-first per Microsoft's documented subdomains-before-parent delete ordering), validate/
  (`Test-GovernanceDomainHierarchy.ps1`), rollback.md, reviews.md (four-lens review - Red Team,
  Blue Team, CISO, and Microsoft Product Owner each raised a Fix finding, all resolved). Grounded
  directly against the Business Domain REST reference (Create/Update/Enumerate/Delete), the
  governance-domains and business-concept-attributes portal docs, and Microsoft's own
  Corporate→Sales sample data-governance walkthrough (full citation list in README.md §12).
  **Real bug caught and fixed by the four-lens review, not just a documentation gap:** the first
  draft only sent `isRestricted` when the definition file declared it, which - under this API's
  full-replace-PUT semantics (already flagged once before in `curate-business-glossary/README.md`
  §11) - would have silently cleared a portal-set restriction on any re-run whose file omitted the
  field; fixed by seeding it from the live `Enumerate` snapshot like every other field. Also added
  a missing **Governance Domain Owner** row to `docs/rbac-model.md` §5 (the role this scenario's
  own Prerequisites table needed to cite, confirmed via Microsoft Learn but not previously listed).
  **Explicitly deferred as VERIFY, not guessed:** the data estate mapping's
  `domains[].relatedCollections[].parentCollection.refName` construction - this build's own
  inference from field names/nesting, since Microsoft's REST reference gives that one nested
  object no prose description and its worked examples use meaningless placeholder strings unlike
  the rest of the same request body (design.md §5); the deploy script defaults to attempting it but
  ships a `-SkipDataEstateMapping` switch and recommends it for a first pilot-tenant run.
- [x] **`scenarios/dspm-for-ai/copilot-prompt-full-block/`** - commit `5e1548a` - 2026-09-10. Closes
  the `PROGRESS.md` follow-up carried from `copilot-sensitive-data-exposure/design.md` §6 ("needs a
  fresh grounding pass once Microsoft publishes an example or the feature reaches GA"). Full README
  (12-section skeleton), design.md, deploy/ (`Add-CopilotPromptFullBlockRule.ps1` - adds a third rule,
  `Copilot-Block-SensitivePrompts-FullResponse`, to the parent scenario's existing DLP policy;
  `Remove-CopilotPromptFullBlockRule.ps1` - disable/`-Purge`, scoped to this one rule only),
  validate/ (`Test-CopilotPromptFullBlockRule.ps1`), rollback.md, reviews.md (four-lens review - Red
  Team, Blue Team, and CISO each raised a Fix finding, all resolved). **Grounding result:** Microsoft
  has published a fuller worked use case for the "Prevent/Restrict Copilot from processing content >
  Processing prompts" action since the parent scenario's build (Contoso / Canada physical addresses /
  EU debit card numbers example, a clearer supported-conditions-and-actions table), but the feature
  remains preview and Microsoft still has not published a worked PowerShell example combining a
  `ContentContainsSensitiveInformation` condition with `-RestrictAccess` for this specific action -
  the exact `setting` string is not independently confirmed. Built anyway, using the only confirmed
  `-RestrictAccess` value pair for this location (`ExcludeContentProcessing`/`Block`, otherwise
  documented only for a sensitivity-label condition) as a reasoned, disclosed inference - not a
  fabricated parameter - per `AGENTS.md` §4; see `design.md` §5 for the full reasoning and the new
  VERIFY item above for the still-open half. Parent scenario's `README.md`, `design.md`, deploy
  script `.NOTES`, and `reviews.md` (new follow-up review round) cross-linked to this scenario in
  place of the old "not scripted, portal-only" callouts.
- [x] **`scenarios/ediscovery/search-and-purge-teams-messages/`** - commit `d95d1e2` - 2026-09-10.
  Closes the `PROGRESS.md` follow-up raised in `search-and-purge-data-spillage/design.md` §8 (the
  `purgeAreas: teamsMessages` half of the same `purgeData` Graph action, scoped out of that mailbox-
  focused fragment). Full README (12-section skeleton), design.md, deploy/
  (`New-TeamsMessagePurgeSearch.ps1` - find-or-create case/search, binds each declared target mailbox
  as a case-level `ediscoveryNoncustodialDataSource` and attaches it to the search via
  `noncustodialSources@odata.bind`/`$ref`; `Invoke-TeamsMessagePurge.ps1` - the destructive
  `purgeAreas: teamsMessages` purge), validate/ (`Test-TeamsMessagePurgeSearchAndPurge.ps1`),
  rollback.md, reviews.md (four-lens review - Red Team and Blue Team both raised Fix findings,
  resolved). **Central grounding finding, and a genuine correction to the sibling scenario's own
  prior text:** re-grounding `purgeAreas: teamsMessages` directly against current Microsoft Learn
  (the `purgeData` Graph reference and "Find and delete Microsoft Teams chat messages in eDiscovery")
  found the original follow-up's premise was backwards - for this Graph action, **either**
  `purgeType` value (`recoverable` or `permanentlyDelete`) permanently deletes the Teams
  **user-visible** message immediately; only the legacy, cmdlet-based purge path (which Microsoft's
  own current guidance says to avoid for Teams) is compliance-copy-only. Because there is no
  reversible mode at all for Teams, `Invoke-TeamsMessagePurge.ps1` requires `-ConfirmPermanentDelete`
  **unconditionally** for both `-PurgeType` values - a deliberate, disclosed deviation from the
  mailbox sibling's pattern (which only gates `PermanentlyDelete`). `search-and-purge-data-spillage/
  README.md` §6/§11 and `design.md` §7/§8 corrected in place to match. Four VERIFY items and two
  follow-up fragment ideas recorded above (private-channel storage-model conflict between two current
  Microsoft Learn pages; unconfirmed `$ref`-bind SDK cmdlet name; unconfirmed
  `noncustodialDataSource.DisplayName` shape for a mailbox source; unconfirmed effect of `purgeType`
  on the compliance copy's own timing; a hold-lifecycle-automation follow-up; grounding the newer
  Data Security Investigations purge-queue surface). Environment note: the Microsoft Learn MCP tool
  was available and used directly for all grounding this run (multiple `microsoft_docs_fetch`/
  `microsoft_docs_search` calls against `learn.microsoft.com/graph/api/...` and
  `learn.microsoft.com/purview/...`), not WebSearch-only - a better grounding posture than the prior
  run's environment-note entry under Blocked/needs user.
- [x] **`scenarios/adaptive-protection/block-legacy-authentication/`** - commit
  `d8d0c01` - 2026-09-09. Closes the `PROGRESS.md` follow-up
  originally raised in `conditional-access-insider-risk-block/reviews.md` (Red Team: legacy-auth
  clients may not fully honor the Insider Risk condition). Full README (12-section skeleton),
  design.md, deploy/ (`New-BlockLegacyAuthenticationPolicy.ps1` - checks first, best-effort, for
  an existing Microsoft-managed "Block legacy authentication" policy by its confirmed
  `Microsoft-managed:` displayName-prefix convention, and only proceeds to create/reconcile its
  own custom Conditional Access policy - `clientAppTypes = ['exchangeActiveSync','other']`,
  matching Microsoft's exact documented portal procedure - when none is found or
  `-SkipManagedPolicyCheck` is passed; `Remove-BlockLegacyAuthenticationPolicy.ps1` for staged
  rollback), validate/ (`Test-BlockLegacyAuthenticationPolicy.ps1`), rollback.md, reviews.md
  (four-lens review - Red Team and Blue Team both raised Fix findings, resolved: (1) added an
  explicit disclosure, with citation, that Conditional Access is a post-first-factor-
  authentication control and does not stop a credential-stuffing/password-spray attempt from
  confirming valid credentials; (2) fixed a genuine validate-script logic gap where a *disabled*
  Microsoft-managed policy with no custom policy deployed was scored WARN instead of FAIL, even
  though that combination is zero actual coverage). Central grounding finding, independently
  confirmed via the Microsoft Learn MCP tool (available this run): Microsoft now auto-deploys this
  exact control as a Microsoft-managed policy to Entra ID P2/Microsoft 365 Business Premium-
  eligible tenants, auto-enabling it no less than 30 days after first appearing - this scenario is
  designed around detecting that rather than blindly duplicating it, and is independently
  confirmed as the library's first Conditional-Access-based scenario needing only **Microsoft
  Entra ID P1** (not P2). `docs/licensing-matrix.md` new §9 and `docs/rbac-model.md` §10 updated
  to cross-link it and disclose the P1/P2 split so a reader doesn't assume every
  Conditional-Access-based scenario in this library needs P2. Four new follow-ups recorded (two
  pilot-tenant VERIFYs, an Exchange-side-blocking companion-scenario idea, and a shared-VERIFY
  cross-reference) under a new "Follow-ups discovered while building the Block Legacy
  Authentication scenario" section.
- [x] **`scenarios/unified-catalog/manage-critical-data-elements-related-terms/`** - commit
  `c4b8019` - 2026-09-09. Closes the `PROGRESS.md` follow-up
  `manage-critical-data-elements/design.md` §7 deferred as a non-goal. Full README (12-section
  skeleton), design.md, deploy/ (`Add-CdeRelatedTerm.ps1` - idempotent link-only script: resolves
  an already-existing governance domain, critical data element, and glossary term(s) strictly by
  name, then creates `entityType=TERM` Critical Data Elements relationships via the identical
  list-before-create idempotency guard the sibling scenario already uses for `DATACOLUMN`;
  `Remove-CdeRelatedTerm.ps1` - targeted, selective, or full unlink), validate/
  (`Test-CdeRelatedTerms.ps1`), rollback.md (documents the interaction with the sibling's own
  `-Purge`, which predates this scenario and does not remove TERM links), reviews.md (four-lens
  review - Red Team and Microsoft Product Owner both raised Fix findings, resolved: (1) unlinking
  a term now carries an explicit warning that it can loosen an inherited access-policy aggregation
  on downstream data products, not just tidy up metadata; (2) the "Data Steward alone is
  sufficient" role claim was corrected from asserted fact to a disclosed inference from
  documentation silence, with a fallback instruction). Grounded via fresh direct Microsoft Learn
  MCP fetches (available this run) of the Critical Data Elements Create/List/Delete Relationship
  reference pages (confirming `TERM` is a clean, non-ambiguous `EntityCategory` value - no
  enum-vs-worked-example discrepancy the way the sibling's `DATACOLUMN` choice has) and the
  critical-data-elements/glossary-terms concept pages (the "Manage related terms" procedure and
  the reciprocal flow's Draft-state requirement). Two VERIFY items recorded above rather than
  resolved by guessing; no cross-cutting doc changes needed (docs/automation-surface.md's existing
  Unified Catalog row already describes the Critical Data Elements relationship operation
  generically enough to cover this).
- [x] **`scenarios/adaptive-protection/conditional-access-insider-risk-step-up-auth/`** - commit
  `6e39ee9` - 2026-09-09. Companion to `conditional-access-insider-risk-block` closing the
  PROGRESS.md follow-up for a graduated Moderate/Minor Conditional Access response. Full README
  (12-section skeleton), design.md, deploy/ (`New-InsiderRiskStepUpPolicies.ps1` - creates/
  reconciles two policies: Moderate risk → Terms of Use requirement scoped to
  `MicrosoftAdminPortals`; Minor risk → permanently Report-only visibility policy with no
  `Enabled` state reachable via the script; `Remove-InsiderRiskStepUpPolicies.ps1`), validate/
  (`Test-InsiderRiskStepUpPolicies.ps1`), rollback.md, reviews.md (four-lens review - caught and
  fixed a fail-safe defect: the Minor policy's grant-control payload container was originally
  `block`, changed to `mfa` so an out-of-band state change to `enabled` degrades to an MFA prompt
  rather than a tenant-wide lockout). Grounded against Microsoft's "Adaptive Protection
  configuration guide" (rejecting an earlier, unverified "require MFA/compliant device" idea in
  favor of Microsoft's own documented Terms of Use + Report-only pairing), the dedicated
  "Require terms of use... Microsoft Admin Portals" how-to, the `conditionalAccessGrantControls`/
  `conditionalAccessApplications` Graph v1.0 resource references, and the `Create agreement` Graph
  reference (confirming agreement creation is delegated-permission-only, not app-only-automatable
  - disclosed as a genuine automation gap rather than worked around). `docs/licensing-matrix.md`
  §8 updated to reference both Conditional Access scenarios and the Terms of Use feature's own
  lower Entra ID P1 floor. Two VERIFY items and a scoped follow-up recorded above.
- [x] **`scenarios/data-lifecycle-management/priority-cleanup-permanent-deletion/`** - commit
  `176c5fa` - 2026-09-09. Full README (12-section skeleton), design.md, deploy/
  (`New-PriorityCleanupPermanentDeletionPolicy.ps1` - provisions the same confirmed
  `-PriorityCleanup` label/policy/rule shape as the `priority-cleanup-sharepoint-onedrive` sibling,
  then prints a mandatory manual portal step rather than guessing at an unconfirmed CLI parameter;
  `Remove-PriorityCleanupPermanentDeletionPolicy.ps1`), validate/
  (`Test-PriorityCleanupPermanentDeletionPolicy.ps1` - confirms shared base objects, explicitly
  cannot confirm permanent-deletion mode, directs to audit search instead), rollback.md (documents
  there is NO Recycle Bin recourse, unlike the sibling), reviews.md (four-lens, all Fix resolved).
  Central grounded finding: `New-ComplianceTag -RetentionAction` confirmed to accept only
  `Delete`/`Keep`/`KeepAndDelete` (no "permanent" value) - corroborates the feature's own
  portal-only procedure page rather than merely citing its silence. New audit operation
  `PriorityCleanupFileDeleted` (distinct from the sibling's `PriorityCleanupFileRecycled`) is the
  scenario's sole scriptable, reliable confirmation path. Cross-linked from
  `docs/licensing-matrix.md` §7 and backported into the sibling's `README.md`/`design.md` (removed
  "tracked as a follow-up" language, now a direct sibling-scenario link).
- [x] **`scenarios/unified-catalog/manage-okrs/`** - commit
  `e47e8be` - 2026-09-09. Full README (12-section skeleton),
  design.md, deploy/ (`New-Okr.ps1` - idempotent create-or-update of an objective and its key
  results via the `Okr` operation group, then links the objective to one or more already-existing
  data products via the **Data Products** operation group's own `Create Relationship` operation
  with `entityType=OBJECTIVE`; `Remove-Okr.ps1` - staged unpublish/unlink/delete rollback),
  validate/ script (`Test-Okr.ps1`), rollback.md, and a four-lens reviews.md (all Fix items
  resolved; no Fail). Grounded via the Microsoft Learn MCP tool by fetching the `Okr` operation
  group's full operation list directly (confirming it has **no relationship operation of its
  own** - a genuine, confirmed API asymmetry, not a gap this build failed to research) and the
  **Data Products - Create/List/Delete Relationship** operations' shared `EntityCategory` enum
  directly (confirming `OBJECTIVE`/`KEYRESULT` as real, documented values there). Because
  Microsoft's own docs state OKR names are explicitly allowed to duplicate, this scenario departs
  from every other Unified Catalog scenario in this repo's name-based idempotency pattern in
  favor of a caller-generated, pre-pinned `id` per objective/key result (design.md §3) - a
  deliberate, documented design choice, not an oversight. Corrects a pre-existing
  `docs/automation-surface.md` §4 inaccuracy (an informal "OKR" paraphrase of the real
  `OBJECTIVE`/`KEYRESULT` enum values) and adds a dedicated Okr operation-group routing-table row.
  Five follow-ups added above (four VERIFY items requiring a pilot tenant; one deferred
  KEYRESULT-linking/staleness-detection scope item) - none blocking.
- [x] **`scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/`** -
  commit `115f0f0` - 2026-09-09. Full README (12-section
  skeleton), design.md, deploy/ (`New-PriorityCleanupSharePointOneDrivePolicy.ps1` - idempotent
  create-or-report of a priority cleanup label/policy/rule via the official `-PriorityCleanup`
  parameter set, targeting `-OneDriveLocation`/`-SharePointLocation` instead of the Exchange
  sibling's `-ExchangeLocation`; unlike the sibling, has **no** `-Enabled`-at-creation path at all
  - only `-Simulate` then `-EnforceSimulation` - because Microsoft documents simulation as
  mandatory, not optional, for this workload; `Remove-PriorityCleanupSharePointOneDrivePolicy.ps1`
  - disable/delete rollback that states the materially softer Recycle-Bin-recovery story rather
  than reusing the Exchange sibling's "cannot be undone" language), validate/ script
  (`Test-PriorityCleanupSharePointOneDrivePolicy.ps1` - classification via the `-PriorityCleanup`
  filter switch; explicitly treats `Enabled:$false`/`Mode: In simulation` as the expected baseline
  state for this workload, unlike the Exchange sibling), rollback.md, and a four-lens reviews.md
  (all Fix items resolved; no Fail). Grounded via the Microsoft Learn MCP tool (available and
  working in this session, unlike the prior run's environment) directly against
  `priority-cleanup-onedrive-sharepoint`, `priority-cleanup-exchange` (for the cross-workload
  comparison table), `priority-cleanup-permanent-deletion`, and the `New-ComplianceTag`/
  `New-RetentionCompliancePolicy`/`New-RetentionComplianceRule` cmdlet reference pages - confirmed
  `-OneDriveLocation`/`-SharePointLocation` support under the same `-PriorityCleanup`-bearing
  parameter set, and the `ProgID:Media AND ProgID:Meeting` query verbatim from Microsoft's own
  worked example (no construction needed there, unlike the Exchange sibling's hand-built query).
  Two genuine construction gaps disclosed as VERIFY rather than guessed: the single-stage
  `-MultiStageReviewProperty` shape for this workload's reduced approver model, and whether
  Exchange's documented KeyQL exclusions also apply here. Backported cross-links into the Exchange
  sibling's `README.md`/`design.md` (replacing "tracked as a follow-up" with a direct pointer to
  this now-built scenario) and into `docs/licensing-matrix.md` §7 / `docs/rbac-model.md` §4 (the
  latter corrected to show the two workloads' different approver-role tables, not just Exchange's).
- [x] **`scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/`** - full
  README (12-section skeleton), design.md, deploy/ (`New-PriorityCleanupExchangePolicy.ps1` -
  idempotent create-or-report of a priority cleanup label/policy/rule via the official
  `-PriorityCleanup` parameter set on `New-ComplianceTag`/`New-RetentionCompliancePolicy`/
  `New-RetentionComplianceRule`, refuses to deploy without an explicit `-Simulate`/`-Enabled`/
  `-DryRun` choice, `-EnforceSimulation` mode for the second-admin turn-on step;
  `Remove-PriorityCleanupExchangePolicy.ps1` - disable/delete rollback that never force-removes
  the label and warns explicitly that a completed approval can't be recalled), validate/ script
  (`Test-PriorityCleanupExchangePolicy.ps1` - classification via the documented `-PriorityCleanup`
  filter switch on each `Get-*` cmdlet rather than an assumed boolean property), rollback.md
  (staged: portal-only decline-pending-items step first, then disable, then delete, then optional
  label removal), four-lens reviews.md (Red Team Fix round resolved - spoliation framing,
  approver-distinctness gap disclosed, query-scope as the one-way door; Blue Team Fix round
  resolved - unfriendly audit-op names, no approval-queue API disclosed rather than hidden,
  documented-filter-switch classification; CISO Fix round resolved - governance-gate framing,
  confirmed on preview-status prominence and funding recommendation; Product Owner Fix round
  resolved - two construction gaps flagged as VERIFY rather than fabricated). Grounded directly
  via the Microsoft Learn MCP tool (`microsoft_docs_search`/`microsoft_docs_fetch`, available this
  run): fetched the full `priority-cleanup-exchange`/`priority-cleanup-onedrive-sharepoint`/
  `priority-cleanup-permanent-deletion` pages and the complete PowerShell reference for
  `New-ComplianceTag`, `New-/Set-/Get-RetentionCompliancePolicy`, `New-/Set-/Get-
  RetentionComplianceRule`, and `Get-ComplianceTag` - confirming the official `-PriorityCleanup`
  parameter set/filter switch is real and documented (not the fabricated `New-
  PriorityCleanupPolicy`/`Set-PriorityCleanupSetting` cmdlet names an initial WebSearch AI summary
  surfaced and this build explicitly rejected after finding no Microsoft Learn page naming
  either). Confirmed licensing directly against the Purview service description's dedicated
  priority-cleanup licensing line (same E5-tier family as Records Management); backported a row
  into `docs/licensing-matrix.md` §2 and a cross-reference into `docs/rbac-model.md` §4's Data
  Lifecycle Management row for the 3-stage approver role requirement. Two genuine construction
  gaps (the `-MultiStageReviewProperty` 3-stage JSON shape; the `RetentionDuration`/`RetentionType`
  mapping for "delete as soon as possible") disclosed as VERIFY per `AGENTS.md` §4 rather than
  guessed with false confidence - tracked as follow-ups above. - 2026-09-09
- [x] **`scenarios/data-lifecycle-management/adaptive-protection-deleted-content-preservation/` -
  Adaptive Protection Deleted-Content Preservation scenario** - built the Data Lifecycle
  Management half of Adaptive Protection this library had deferred since
  `dynamic-risk-dlp-enforcement`'s own build: the 120-day auto-preservation of content an
  Elevated-risk user deletes from SharePoint/OneDrive/Exchange. Grounded directly via the
  Microsoft Learn MCP tool (`microsoft_docs_search`/`microsoft_docs_fetch`, available this run):
  confirmed there is genuinely **no** `Get-`/`New-`/`Set-` cmdlet or Graph resource for the
  underlying toggle or its auto-created retention label/policy - Microsoft states outright that
  "you don't need to create or manage" it and that it "aren't visible in the Microsoft Purview
  portal." Rather than force a fabricated deploy script into existence (`AGENTS.md` §4), this
  fragment documents the exact portal-only enablement path precisely and ships code for what
  genuinely is scriptable: `deploy/Export-AdaptiveProtectionPreservationEvidence.ps1` (a rolling,
  de-duplicated `Search-UnifiedAuditLog` export for the two documented audit Operations -
  `SharePointDataProactivelyPreserved`/`ExchangeDataProactivelyPreserved` - reusing this library's
  proven audit-trail-export pattern from `Export-EdiscoveryAuditTrail.ps1`) and `validate/
  Test-AdaptiveProtectionDlmPreservation.ps1` (a health check that deliberately reports
  `[INCONCLUSIVE]`, never `[FAIL]`, on a zero-row result, since no status cmdlet exists to
  distinguish "off" from "on but not yet triggered"). Directly re-confirmed via `microsoft_docs_
  fetch` against the live page (not a cached snippet) that this integration is **still
  Microsoft-labeled preview**, unlike the Conditional Access insider-risk integration this library
  already re-verified as GA. Four-lens review raised and resolved three Red Team findings before
  commit: (1) the scenario only preserves deletions, not exfiltration, and only covers three
  locations - now stated plainly rather than implied; (2) a privileged Elevated-risk user (anyone
  holding the Insider Risk Management/Insider Risk Management Admins role group) can destroy their
  own evidence by disabling the toggle, since doing so releases **everything** currently preserved
  immediately and tenant-wide, per Microsoft's own documented behavior - added explicit role-
  hygiene guidance and disclosed that this configuration change isn't confirmed to be captured
  anywhere this library's own audit script can query; (3) no real-time alert fires on a
  preservation event - added a SIEM-forwarding recommendation. CISO lens added one Fix: explicit
  guidance not to treat this as a substitute for a real eDiscovery hold once an investigation is
  actually opened. Cross-linked back into `scenarios/adaptive-protection/
  dynamic-risk-dlp-enforcement/README.md` §11 and `design.md` §7 (previously "deferred/out of
  scope," now pointing at the built sibling), matching this library's established
  cross-referencing convention. Three follow-up VERIFY items and one possible future fragment
  (Priority Cleanup) recorded above rather than resolved by guessing. Commit: `a8710e8`.
  Date: 2026-09-09.
- [x] **Backport GA-status correction into `scenarios/adaptive-protection/dynamic-risk-dlp-
  enforcement/`** - doc-only correction fragment (not a new scenario). Corrected two stale
  "Microsoft-labeled preview" claims about the Conditional Access "Insider risk" condition
  integration in `design.md` §2 and §7 (Non-goals) and `README.md` §11 (Known limitations),
  left over from this scenario's original build before the sibling
  `scenarios/adaptive-protection/conditional-access-insider-risk-block/` scenario existed and
  re-grounded GA status. Independently re-verified both sources this run (not just carried over
  from the sibling's own citation) via the Microsoft Learn MCP tool (`microsoft_docs_fetch`,
  available this run): no preview label on "Block access for users with insider risk"
  (<https://learn.microsoft.com/entra/identity/conditional-access/policy-risk-based-insider-block>)
  or on the Graph v1.0 `conditionalAccessConditionSet` resource
  (<https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset>). Both non-goal
  bullets also updated to point at the now-built sibling scenario instead of "tracked as a
  follow-up fragment." Data Lifecycle Management's own preview label was deliberately left
  untouched - out of scope for this correction, no fresh grounding pass was done on it. Added two
  new numbered references (14, 15) to `README.md` §12 and a correction addendum to `reviews.md`
  documenting the fix; no code changed, so no new four-lens review round was run, per `AGENTS.md`
  §6. Commit: `6142d66`. Date: 2026-09-09.
- [x] **Investigate and correct: `scenarios/dspm-for-ai/third-party-ai-site-adaptive-block/`
  (Adaptive-Protection-driven DLP for third-party generative AI sites)** - a correctness
  correction rather than a new scenario, closing the backlog item logged during the
  `copilot-sensitive-data-exposure` build ("a natural extension of `dynamic-risk-dlp-enforcement`'s
  existing pattern"). A dedicated grounding pass found that premise did not hold up: DSPM for AI's
  "Fortify your data security" recommendation creates **three** one-click policies covering
  third-party AI sites, split across two structurally different, currently non-scriptable
  mechanisms - not one directly extensible Adaptive Protection DLP pattern.
  - **`DSPM for AI - Block sensitive info from AI sites`** is an **Endpoint DLP (`Devices`
    location)** policy against the built-in, non-editable **"Generative AI Websites"** sensitive
    service domain group (confirmed via `dlp-configure-endpoint-settings#browser-and-domain-
    restrictions-to-sensitive-data`: "The Generative AI Websites group... is used for default
    policies within Data Security Posture Management for AI and can't be edited or deleted"),
    combined with Adaptive Protection (`SharedByIRMUserRisk` = Elevated) for a block-with-override
    action. This is the same family as the already-tracked, still-open
    `endpoint-dlp-usb-block-adaptive-protection` follow-up above - `New-DlpComplianceRule
    -EndpointDlpRestrictions`'s exact `Setting`/`Value` strings remain an unconfirmed VERIFY
    (`scenarios/dlp/endpoint-dlp-usb-block/README.md` §11), and no worked PowerShell example
    referencing a sensitive service domain group (built-in or custom) by ID inside that parameter,
    or a cmdlet for creating/listing such groups at all, was found in `Set-PolicyConfig`'s
    published parameter list (`set-policyconfig?view=exchange-ps` - no
    `-DlpSensitiveServiceDomainGroups`-shaped parameter present) or elsewhere.
  - **`DSPM for AI - Block elevated risk users from submitting prompts to AI apps in Microsoft
    Edge`** and **`DSPM for AI - Block sensitive info from AI apps in Edge`** use a newer,
    structurally distinct **"Inline web traffic"** policy location enforced through **Edge for
    Business**, scoped via an **"Adaptive app scopes" → "All unmanaged AI apps"** cloud-app
    construct (`dlp-browser-dlp-learn`, `dlp-create-policy-block-to-ai-via-edge`) - a portal-wizard
    flow that automatically provisions Microsoft Edge configuration policies and Microsoft Intune
    policies outside of Purview. `New-DlpCompliancePolicy`'s full published parameter syntax
    (`new-dlpcompliancepolicy?view=exchange-ps`) has no `Locations`/`EnforcementPlanes` value, and
    `New-DlpComplianceRule`'s full published parameter syntax
    (`new-dlpcompliancerule?view=exchange-ps`) has no action parameter, for "Inline web traffic" /
    "Adaptive app scopes" / "Restrict browser and network activities" - this location is
    documented as portal/wizard-only as of this pass, with per-policy pay-as-you-go billing
    (`dlp-browser-dlp-learn#licensing`) layered on top.
  - Per `AGENTS.md` §4, this repo does not fabricate the missing `-EndpointDlpRestrictions`
    setting/value pair, the sensitive-service-domain-group reference mechanism, or an "Inline web
    traffic" location/action parameter set to force a deploy script into existence. Corrected
    `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/design.md` §7 (the non-goal note that
    originally pointed here, rewritten to state the actual finding instead of implying a
    straightforward extension) and added a follow-up four-lens round to that scenario's
    `reviews.md` (all four lenses Pass, no Fix/Fail - confirming the correction itself is sound).
    No new scenario folder created; no code changed. Grounded via the Microsoft Learn MCP tool
    (`microsoft_docs_search`/`microsoft_docs_fetch`, available this run despite this task's stored
    instructions claiming otherwise): `dspm-for-ai-considerations#one-click-policies-from-data-
    security-posture-management-for-ai` (the three policies' exact names/descriptions and their
    shared "Fortify your data security" source), `dlp-browser-dlp-learn` and
    `dlp-create-policy-block-to-ai-via-edge` (Inline web traffic / Edge for Business / Adaptive app
    scopes mechanics, PAYG billing, no PowerShell surface), `dlp-configure-endpoint-settings`
    (Generative AI Websites sensitive service domain group), `ai-microsoft-purview-permissions`
    (DSPM for AI role groups), and the full published parameter syntax of `New-DlpCompliancePolicy`,
    `New-DlpComplianceRule`, and `Set-PolicyConfig` (`?view=exchange-ps` reference pages) -
    confirming by omission that no cmdlet/parameter for either mechanism exists in Microsoft's own
    published reference. Re-open per the corrected `TODO` note above once Microsoft documents one.
  - commit `54002a7` - 2026-09-09
- [x] **`scenarios/insider-risk/security-policy-violations-by-risky-users/` - Security Policy
  Violations by Risky Users scenario** - commit `61992b3` - 2026-09-09 - built the fourth and final
  member of the "Security policy violations…" Insider Risk Management template family (base,
  …by departing users, …by priority users already shipped). Grounded directly via the Microsoft
  Learn MCP tool (`microsoft_docs_fetch`/`microsoft_docs_search`, available this run despite this
  task's stored instructions claiming otherwise): fetched
  `insider-risk-management-policy-templates` (confirming the AND/OR trigger-path prerequisite
  shape - HR connector risk indicators AND/OR Communication Compliance integration, both requiring
  an independent active Defender for Endpoint subscription), `insider-risk-management-limits`
  (confirming the 7,500-user template cap), `import-hr-data` (all three risk-indicator HR CSV
  schemas - Job level change, Performance review, Performance improvement plan - and the
  `HRScenario` multi-scenario CSV pattern), and the Communication Compliance policies page's
  Insider Risk Management integration section (5+ risky-messages/24h in-scope threshold, up to 48h
  latency, auto-created dedicated "Detect inappropriate text" policy, explicit "PowerShell isn't
  supported for Communication Compliance policy management" statement). Shipped a genuinely new
  script, `deploy/Send-HrRiskIndicatorRecord.ps1`, generalizing the departing-users sibling's
  single-schema resignation uploader for this template's three-schema, `HRScenario`-tagged HR data
  requirement - reused the base template's scope-candidate script (`-MaxUsers 7500`) and the
  departing-users sibling's alert-export script unmodified rather than duplicating either. Disclosed
  two genuine open questions rather than guessing: whether an existing single-scenario HR connector
  can be edited in the portal to add new scenarios (this scenario provisions a new, dedicated
  connector instead), and a Microsoft-side documentation inconsistency in the Performance
  improvement plan CSV column names (worked example vs. column-description table). Four-lens review
  found and resolved one Red Team finding (the Communication Compliance 5-messages/24h threshold as
  a structural, disclosed evasion vector) and one CISO finding (this is the only IRM scenario in the
  library whose trigger draws on performance-management HR data - added an explicit HR/Legal
  sign-off governance recommendation to README.md §2/§8 and design.md §6, not just a technical
  prerequisite). Blue Team and Microsoft Product Owner passed with findings confirmed already
  correctly scoped. No Fail items.
- [x] **`departing-employee-data-theft` - script HR-connector app-secret cleanup** - commit
  `81fee1d` - 2026-09-09 - resolved the follow-up (discovered while building
  `Register-HrConnectorApp.ps1`) asking for a scripted way to delete the superseded secret that
  `-RotateSecret` leaves behind, since Microsoft Entra applications support multiple concurrent
  client secrets by design and nothing deletes the old one automatically. Added the standalone
  `deploy/Remove-HrConnectorAppSecret.ps1`: a default `-RemoveExpired` mode that only ever
  deletes already-dead credentials (safe by construction - can never reduce the app's working-
  secret count) and a narrower `-KeyId`/`-Force` mode for force-retiring a still-valid secret
  (refuses without `-Force` if it's the application's only unexpired secret). Idempotent,
  `-WhatIf`-capable, never logs `SecretText`. Grounded via the Microsoft Learn MCP server
  (available this run, same as the prior fragment, contrary to this task's stored instructions):
  independently re-verified `Remove-MgApplicationPassword`'s full parameter set (not assumed by
  symmetry with `Add-MgApplicationPassword`) and caught a non-obvious mismatch before it shipped -
  its `-KeyId` parameter's documented type is `System.String`, not `System.Guid`, despite the
  underlying `passwordCredential.keyId` Graph resource property's Edm type being `Guid` - so this
  script's own `-KeyId` parameter is typed `[string]` with a GUID-format `ValidatePattern`, not
  `[guid]`. Also confirmed `application: removePassword`'s REST reference documents object-ID
  addressing only (no dual `id`/`appId` addressing the way `addPassword` documents), so the
  script's `.NOTES` doesn't claim that flexibility exists. Added a matching WARN check to
  `validate/Test-HrConnectorAppRegistration.ps1` (already-expired secrets still present - not a
  hard failure, a hygiene nudge). Updated `README.md` (Step 2 code block, §11, §12 reference 22),
  `design.md` (§4 component table row, §6 new key-decision row), and `rollback.md` (Stage 3 now
  offers secret-only revocation via the new script as an alternative to full app deletion). Added
  a reviews.md addendum (mini four-lens pass on the new capability only - Pass, no Fix/Fail): Red
  Team confirmed the default mode can't break the live integration and no secret plaintext is
  ever handled; Blue Team confirmed the cleanup gap is now caught by the validate script's new
  WARN, not just fixable; CISO confirmed near-zero incremental cost; Microsoft Product Owner
  confirmed the cmdlet/REST grounding above.
- [x] **`departing-employee-data-theft` - script the HR-connector Entra app registration** -
  commit `12d1932` - 2026-09-09 - resolved the follow-up asking whether app-registration
  creation could be scripted instead of left as a manual Entra admin center task. Grounded via
  the Microsoft Learn MCP server (available this run, contrary to this task's stored
  instructions) rather than WebFetch, which is proxy-blocked for `learn.microsoft.com` in this
  environment: `import-hr-data` Step 2 needs only a plain, permission-free app registration, so
  no HR-connector-specific cmdlet is required - generic `Microsoft.Graph.Applications` cmdlets
  cover it completely. Added `deploy/Register-HrConnectorApp.ps1` (idempotent by display-name
  lookup, `-WhatIf`-capable, `-RotateSecret` for the README-recommended ~90-day rotation
  cadence; deliberately grants the created app **no** Microsoft Graph API permission) and
  `validate/Test-HrConnectorAppRegistration.ps1` (existence, service principal, unexpired
  secret, and - the load-bearing check - that no permission has been granted). Updated
  `README.md` (§3, Step 2, §7, §11, §12 references), `design.md` (§2, §4, §6), `rollback.md`
  (scripted equivalent for Stage 3), and added a reviews.md addendum (mini four-lens pass, all
  Pass, no Fix/Fail). Added `docs/rbac-model.md` §11 "Microsoft Entra app registration RBAC - a
  seventh system" (grounded: self-service app registration is on by default; **Application
  Developer** is the narrowest role if it's been disabled, ahead of the broader **Cloud
  Application Administrator**/**Application Administrator**), renumbering the old §11 ("How
  scenarios should cite RBAC") to §12 and updating its checklist item 1 - verified no other file
  in the repo cross-referenced the old §11 by number. All cmdlets (`New-MgApplication`,
  `Get-MgApplication`, `New-MgServicePrincipal`, `Add-MgApplicationPassword`,
  `Remove-MgApplication`, `Remove-MgServicePrincipal`) independently verified against their own
  Microsoft Learn reference pages, including the easy-to-get-wrong detail that
  `Add-MgApplicationPassword -ApplicationId` takes the object ID (aliased `ObjectId`), not the
  `AppId`. Also discovered and fixed, in the same commit: this session's `main` branch was
  detached from `origin/main` at session start with 34 prior fragments' commits sitting
  unpushed on a detached HEAD from an earlier run in this same session - fast-forwarded and
  confirmed already in sync with `origin/main` (no data loss; documented here per §6 discipline
  since it affected repo state before this fragment started, even though no separate push was
  needed).
- [x] **`auto-label-eu-personal-data-sharepoint` - full per-country checksum/confidence table for
  both opt-in travel-document bundles** - commit `b0012e0` - 2026-09-09 - closed the
  `PROGRESS.md` follow-up asking for the same per-country grounding depth already built for the
  default "EU national identification number" bundle. Fetched all 26 "EU passport number" and all
  28 "EU driver's license number" member entity-definition pages directly from Microsoft Learn (54
  pages total) and tabled Format/Checksum/Confidence for each in `design.md` §4. Headline finding:
  only **2 of 26 passport-bundle entities (8%)** are checksum-validated (Germany, Poland) and only
  **3 of 28 driver's-license-bundle entities (11%)** are (Germany, Spain, U.K.) - versus 73% for
  the default national-ID bundle; the driver's-license bundle additionally caps at Medium (75)
  confidence for 25 of its 28 members (no High-confidence tier exists for its non-checksum
  countries). `README.md` §8/§11 updated with the numeric finding; the Exchange sibling
  (`auto-label-eu-personal-data-exchange/README.md` §11 and `design.md` §5) updated from "not
  tabled" to reference the now-built table rather than duplicate it. `reviews.md` round 3
  four-lens review added (all four lenses Pass - this round closes a previously-disclosed gap
  rather than introducing new risk). No new VERIFY items opened; the existing driver's-license
  apostrophe-casing VERIFY and byte-exact-casing VERIFY are unchanged.
- [x] **`auto-label-eu-personal-data-exchange` - port `-IncludeTravelDocumentSits` for parity with
  the SharePoint/OneDrive EU sibling** - commit `9302c57` - 2026-09-09 - added the same opt-in
  switch to `deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1` and `validate/
  Test-EuPersonalDataAutoLabelExchangePolicy.ps1`, appending `EU passport number` and `EU driver's
  license number` to whatever `-SensitiveInfoTypeName` set is already in effect, so the Exchange
  channel isn't left one switch behind its file-scoped sibling. Both bundle memberships (25-state
  EU passport bundle + combined "U.S./U.K. passport number" entity; 27-state + standalone U.K. EU
  driver's-license bundle) re-fetched directly from Microsoft Learn during this fragment and
  confirmed unchanged from the sibling's original 2026-09-09 grounding - no drift. `README.md`
  §5/§6/§7/§11 and `design.md` §5/§7/References updated; `reviews.md` round 2 four-lens review
  added (all four lenses Pass - the gotcha was already disclosed by the ported switch, and two
  Exchange-specific angles - encryption-side-effect interaction, cross-scenario SIT-list drift -
  were checked and confirmed not to be new risks). No new VERIFY items opened; the existing
  driver's-license apostrophe-casing VERIFY (already tracked for this scenario) now explicitly
  covers the ported name too.
- [x] **`auto-label-eu-personal-data-sharepoint` - opt-in travel-document SIT bundle
  (`-IncludeTravelDocumentSits`)** - commit `6db12ca` - 2026-09-09 - added the switch to
  `deploy/New-EuPersonalDataAutoLabelPolicy.ps1` and `validate/Test-EuPersonalDataAutoLabelPolicy.ps1`,
  appending `EU passport number` and `EU driver's license number` to whatever
  `-SensitiveInfoTypeName` set is already in effect. Grounding pass (fetching both bundles' own
  Microsoft Learn index pages directly) found the "EU passport number" bundle has no standalone
  U.K. entity - U.K. coverage is merged into a single "U.S./U.K. passport number" entity - and that
  the three EU-wide bundles this scenario references don't share identical member-state coverage.
  Both facts documented in `design.md` §4 (new membership tables) and `README.md` §6/§11, with a
  `reviews.md` round 2 four-lens review (2 Red Team findings, both resolved; Blue/CISO/Product
  Owner all Pass). Three follow-ups recorded above (port to the Exchange sibling; full per-country
  checksum table for the two new bundles; the driver's-license apostrophe-casing VERIFY).
- [x] **EU national ID bundle - full 26-country checksum-strength reference table** - commit
  `8243578` - 2026-09-09 - `auto-label-eu-personal-data-sharepoint/design.md` §4 now tables all 26
  members of the "EU national identification number" bundle (Austria through U.K.), each grounded
  directly against its own Microsoft Learn entity-definition page: 19 checksum-validated, 7
  pattern-only (Austria, Croatia, Cyprus, France, Greece, Malta, U.K.), with Germany's checksum
  scoped to its post-2010 format only. Resolves the Red Team finding in that scenario's `reviews.md`
  (finding 1), which the original build had only backed with two representative examples. `README.md`
  §8/§11 in both the SharePoint/OneDrive and Exchange EU-personal-data siblings updated to cite the
  exact counts and the new table instead of "several others documented as pattern-only." 26 new
  citations added to `design.md`'s reference list.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-apple-portable-vendor-product-matching/`**
  - commit `5410ea0` - 2026-09-09 - extends
  `defender-device-control-usb-allowlist-macos-portable-device-coverage`'s `serialNumber`-only Apple
  and Portable device allowlists with `vendorId`/`productId` compound matching, the same RFC 4122
  §4.3 UUIDv5 deterministic-sub-group + `groupId`-clause technique
  `defender-device-control-usb-allowlist-macos-vendor-product-matching` already proved once for
  removable media - applied independently to both families in one fragment, with a family tag folded
  into the hash input so the two families' sub-groups can never collide. Both new Learn/GitHub facts
  (the current Query `any`/`or` synonymy; confirmation that no published sample pairs `vendorId`/
  `productId` with `apple_devices`/`portable_devices`) were re-fetched directly during this build, not
  carried over unverified. Requires each family's Approved group to already have ≥1 `serialNumber`
  device configured - deliberately does not build that group/its Allow rule from a
  zero-`serialNumber` starting state (tracked as a follow-up above) - and inherits a more severe
  version of the Bluetooth sibling fragment's own disclosed cross-fragment ordering hazard against
  `Add-MacPortableDeviceCoverage.ps1`, disclosed and detected (not silently engineered around) the
  same way. Four-lens review caught and fixed one real defect before closing: an unvalidated
  `query.$type` pass-through on the Approved group that could have silently written a corrupted or
  `null` value into a live Intune policy.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf-vendor-product-matching/`**
  - commit `ed22e8a` - 2026-09-08 - the JAMF-managed sibling of
  `defender-device-control-usb-allowlist-macos-vendor-product-matching` (Intune), closing the same
  vendorId/productId compound-matching gap for JAMF-managed macOS fleets. Because JAMF's device
  control deployment has no documented API (the base JAMF scenario's own already-disclosed gap),
  this fragment is a **superset generator** rather than an incremental patcher: one script reads a
  combined config (`approvedDevices` + `vendorProductDevices`) and regenerates the complete policy
  JSON in one artifact - a materially simpler idempotency model than the Intune sibling's live-object
  diff/reconcile, since JAMF's own "regenerate whole, paste whole" mechanism has no live state to
  diff against. Reuses the Intune sibling's exact deterministic RFC 4122 §4.3 UUIDv5 scheme, fixed
  namespace constant, and hash-input format verbatim (not re-derived) so the identical
  `vendorId`+`productId` pair produces the identical sub-group id on both deployment paths - the
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
- [x] **`scenarios/information-protection/auto-label-eu-personal-data-sharepoint/`** - commit
  `a725941` - 2026-09-08 - the EU/UK-region sibling of `auto-label-confidential-sharepoint/`,
  resolving that scenario's own deferred "localize the SIT selection by jurisdiction" follow-up.
  Same auto-labeling policy family and staged-rollout/override model, re-pointed at Microsoft's
  built-in EU-wide bundle SITs (EU national identification number, EU Social Security Number
  (SSN) or Equivalent ID, EU debit card number - grounded via the Microsoft Learn MCP tool, which
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
  companion follow-up carried to TODO rather than guessed at - see "Follow-ups discovered while
  building the EU/UK personal data auto-labeling scenario" above.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-vendor-product-matching/`** -
  commit `f0907e1` - 2026-09-08 - extends `defender-device-control-usb-allowlist-macos`'s
  `serialNumber`-only `ApprovedBackupDrives` group with vendorId+productId compound matching, for
  approved drives with no readable serial number. Closes the gap that scenario's own `design.md` §5
  deliberately deferred: macOS's schema can only AND vendorId+productId via a per-device sub-group
  referenced by a `groupId` clause, which needs a stable id per config-file entry - resolved here
  with a deterministic RFC 4122 §4.3 version-5 (SHA-1) UUID keyed on `vendorId:productId` (not
  `label`, so a cosmetic rename never orphans a group), independently cross-checked against Python's
  `uuid.uuid5()` reference implementation for the same input during the build. No new Intune profile
  and no new/edited rule - both of the parent's existing rules already key off `ApprovedBackupDrives`'
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
- [x] **`scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/`** - commit `0a3e752` - 2026-09-08 - custom, PII-only Data Map
  scan rule set for Azure SQL Database, extending `scan-azure-sql-and-classify`. Closes that
  scenario's carried-forward VERIFY ("the exact REST JSON body for the 'Scan Rulesets - Create Or
  Update' operation was not independently confirmed") via a direct fetch of the canonical **Scan
  Rulesets - Create Or Replace**/**- Get** Microsoft Learn REST reference pages (not reconstructed
  from adjacent evidence). Full deliverable: `README.md` (12-section skeleton), `design.md` (6
  design goals, including deriving the ~200-entry exclusion list live from the tenant's own Types
  API - `GET .../types/typedefs?type=CLASSIFICATION` - rather than a hard-coded snapshot, since the
  `data-map-classification-supported-list` page turned out to list classifications by
  human-readable name only, no exact `MICROSOFT.*` identifiers anywhere on it),
  `deploy/New-PiiOnlyScanRuleset.ps1` (idempotent, `-WhatIf`-capable; GETs the tenant's live
  classification defs, computes the exclusion list, creates/updates the Custom ruleset, then GETs
  and reconciles the existing scan onto it preserving every other scan property),
  `deploy/Remove-PiiOnlyScanRuleset.ps1` (staged rollback: revert scan to System ruleset, then
  optionally delete the custom ruleset), `validate/Test-PiiOnlyScanRuleset.ps1`, `rollback.md`, and
  `reviews.md` (four-lens review - Red Team flagged a scan-kind-mismatch risk from a
  `-ScanName`/`-DataSourceName` typo and a silent-clobber risk on the account-wide ruleset object
  when two teams share a default name, both fixed with new guard checks in the deploy script; Blue
  Team flagged missing detectability guidance for a classification-scope-narrowing change, resolved
  by grounding and citing the Management-category "Scan rule set: Create/Update/Delete" audit event
  and the `PurviewDataMapOperation` Graph audit record type; CISO and Product Owner both passed
  without required changes - no Fail). Three sibling-source-type follow-ups and one pagination
  VERIFY opened (see "Follow-ups discovered while building the Data Map PII-only scan rule set
  (Azure SQL Database) scenario" above).
- [x] **`scenarios/adaptive-protection/conditional-access-insider-risk-block/`** - Conditional
  Access "Insider Risk" condition scenario, deferred from `dynamic-risk-dlp-enforcement` as its
  own follow-up fragment (different admin surface - Microsoft Entra, not Purview/EXO - with its
  own Entra ID P2 license prerequisite). Full deliverable: `README.md` (12-section skeleton),
  `design.md` (including a §8 correction to the DLP sibling's now-stale "still preview" claim -
  this build's fresh grounding pass confirmed the integration is GA: no preview label on
  Microsoft's current "Block access for users with elevated insider risk" guide or the Graph v1.0
  `conditionalAccessConditionSet.insiderRiskLevels` resource property, independent reporting
  places GA at June 2024), `deploy/New-InsiderRiskConditionalAccessPolicy.ps1` (idempotent,
  `-WhatIf`-capable, `-Mode ReportOnly|Enabled|Disabled`, Graph
  `New-/Update-MgIdentityConditionalAccessPolicy`), `deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1`
  (staged rollback: disable / step-back-to-Report-only / `-Purge`),
  `validate/Test-InsiderRiskConditionalAccessPolicy.ps1`, `rollback.md`, and `reviews.md`
  (four-lens review - Red Team flagged an existing-session/CAE bypass window and a legacy-
  authentication gap, Blue Team flagged an undocumented second propagation delay distinct from
  Adaptive Protection's 36-hour window, CISO flagged the sign-in-block's larger business-
  continuity impact needing service-desk readiness alongside HR/Legal coordination, Product Owner
  flagged the DLP sibling's stale preview claim - all four Fix items resolved in place, no Fail).
  Also backported: `docs/rbac-model.md` new §10 (Microsoft Entra Conditional Access - a sixth RBAC
  system; old §10 renumbered to §11) and Sources; `docs/licensing-matrix.md` new §8 (Entra ID P2
  for the Conditional Access Insider Risk condition specifically, distinct from the broader P1/P2
  administrative-units prerequisite in §4) and Sources; `docs/automation-surface.md` surface 3's
  "Typical use" column extended to mention Conditional Access policies
  (`Microsoft.Graph.Identity.SignIns`). Grounded via direct fetch of the Microsoft Learn/Graph
  docs source repos (`MicrosoftDocs/entra-docs`, `microsoftgraph/microsoft-graph-docs-contrib`)
  since the Microsoft Learn MCP tool and direct `learn.microsoft.com` fetches were both
  unavailable in this run's network environment (egress-proxy-blocked) - cited URLs are the
  canonical `learn.microsoft.com` pages those source files render to. Five follow-ups opened
  (see "Follow-ups discovered while building the Conditional Access insider-risk-block scenario"
  above): the DLP-sibling preview-claim backport, a P2-partial-licensing-enforcement VERIFY, the
  `excludeGuestsOrExternalUsers` scripting gap, a Quick-Setup-collision-name VERIFY, and a
  softer-grant-control Moderate/Minor variant. - `8f261bb` - 2026-09-08
- [x] **Backport: Compliance Administrator/Compliance Data Administrator turn-on-policy
  prerequisite** - added to `scenarios/information-protection/auto-label-confidential-sharepoint/
  README.md` §3 (new prerequisites row + reference [15]), closing the doc-only gap the sibling
  Exchange scenario (`auto-label-confidential-exchange`) surfaced: turning on an auto-labeling
  policy after simulation requires Compliance Administrator or Compliance Data Administrator, not
  just Information Protection Admin, which is sufficient only to author/simulate. Citation:
  "Automatically apply a sensitivity label to Microsoft 365 data" §"Before you begin" -
  <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin> -
  the same source already cited by the sibling scenario, verified consistent, no new grounding
  pass needed. Doc-only scoped sub-task per `AGENTS.md` §6; no code/design/reviews changes
  required (no other file in the scenario referenced the stale role list). - `ad6e0d6` - 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-bluetooth-allowlist/`** - adds a
  single `vendorId`+`productId`-matched approved-device exception to the
  `defender-device-control-usb-allowlist-macos-portable-device-coverage` fragment's unconditional
  `Deny-AllBluetoothDevices` rule, closing that fragment's deliberately deferred "Bluetooth is
  always default-deny, no exceptions" scope boundary. Full per-scenario deliverable: `README.md`,
  `design.md`, `deploy/Add-MacBluetoothDeviceAllowlist.ps1`, `deploy/
  Remove-MacBluetoothDeviceAllowlist.ps1`, `deploy/config/mac-bluetooth-device-allowlist.sample.json`,
  `validate/Test-MacBluetoothDeviceAllowlist.ps1`, `rollback.md`, `reviews.md`. Grounded by directly
  fetching Microsoft's own `deny_all_bluetooth_devices_except_samsung.json` sample policy (raw
  GitHub content) and the official "Device Control for macOS" reference tables (via the Microsoft
  Learn MCP tool, which - despite this run's own standing instruction that it is unavailable in this
  cloud environment - was reachable and used as the primary grounding source once `learn.microsoft.com`
  direct fetches were blocked by network egress policy; WebFetch against the GitHub raw-content host
  worked directly). Confirms directly from Microsoft's reference (not inferred) that `includeGroups`
  combines multiple groups with AND semantics and `excludeGroups` with OR semantics - the specific
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
  fragment - both scripts now preserve every entry they don't own. Also strengthened the
  `vendorId`/`productId`-is-a-model-not-a-unit disclosure beyond the initial draft's framing (it is
  weaker than this control's `serialNumber`-based allowlists, not merely a variant of the same risk,
  since no forgery is even required to pass a second unit of the same model, and Bluetooth
  vendor/product identifiers are commonly software-configurable on inexpensive BLE dev hardware) and
  added an Operations & tuning KPI recommendation (allowed-device count/volume vs. physically-issued
  units) as the practical triage signal for that residual gap. Documents, rather than silently fixes
  by editing the already-reviewed prerequisite fragment's script, a genuine cross-fragment ordering
  hazard: re-running that fragment's own `-Force` reconcile after this one silently drops the
  exclusion; this fragment's own `validate` script detects and names that exact drift condition with
  its remediation, distinct from "never configured." - `6472287` - 2026-09-08
- [x] **`scenarios/data-lineage/custom-process-lineage/`** - models a custom nightly transform job
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
  resolved: (1) Red Team - the tenant-wide blast-radius risk of type-definition creation now stated
  explicitly in `README.md` §3 regardless of how the underlying permission-scope VERIFY resolves;
  (2) Blue Team/Product Owner - `validate/Test-ProcessLineage.ps1` originally only checked whether
  the custom type *existed*, not whether its live attribute schema still matched the definition
  file; added a dedicated schema-drift check (detection-only, not auto-remediating, consistent with
  this repo's no-unconfirmed-update-body discipline). `docs/automation-surface.md` §4's lineage
  routing-table row split in two and extended with the newly-exercised Entity/Type operation
  groups. - `66faec0` - 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-portable-device-coverage/`** -
  extends the macOS Defender for Endpoint device control USB allowlist scenario to also cover the
  `apple_devices`, `portable_devices`, and `bluetooth_devices` `primaryId` families, the direct
  macOS analog of the Windows WPD-coverage sibling. Full per-scenario deliverable: `README.md`,
  `design.md`, `deploy/Add-MacPortableDeviceCoverage.ps1`, `deploy/
  Remove-MacPortableDeviceCoverage.ps1`, `deploy/config/mac-portable-device-coverage.sample.json`,
  `validate/Test-MacPortableDeviceCoverage.ps1`, `rollback.md`, `reviews.md`. Widens the parent's
  shared `.mobileconfig` payload in place (macOS device control has one `com.microsoft.wdav`-typed
  policy document per Mac, not one profile per family, confirmed via Microsoft's own reference) with
  three new `settings.features` enables, three catch-all groups, two optional `serialNumber`-matched
  allowlists (Apple/Portable), and five deny/allow rule pairs - grounded directly against Microsoft
  Learn's "Device Control for macOS" reference and cross-checked against four of Microsoft's own
  published GitHub sample policy JSON files, which also resolved a genuine documentation ambiguity
  (the Learn page's entry-`$type` table renders `PortableDevice` capitalized in one cell,
  inconsistent with its own Access Types table and every worked sample - resolved as a rendering
  defect, not a second valid casing, on the strength of the worked examples). Bluetooth ships
  default-deny-only in v1 (no allowlist) - a deliberate, disclosed scope decision, since Microsoft's
  own worked Bluetooth exception sample uses a structurally different `vendorId`+`productId`
  single-device match rather than the OR'd-`serialNumber` shape used for the other two families.
  Four-lens review caught and fixed one genuine grounding defect before finalizing: an initial-draft
  Advanced Hunting query referenced a fabricated `PolicyName` field, corrected to the real,
  Microsoft-confirmed `RemovableStoragePolicy` field. Since the underlying policy JSON schema is
  identical across the Intune and JAMF macOS deployment paths, this build also closes the equivalent
  JAMF-sibling follow-up without a second build. - `7516333` - 2026-09-08
- [x] **`docs/automation-surface.md` §4 - Unified Catalog + Data Map lineage routing-table
  fragment** - closed three separately-tracked doc-extension follow-ups from the Unified Catalog
  business-glossary, manage-data-products, and Data Lineage end-to-end-lineage-validation builds
  by backporting their already-confirmed REST facts into the cross-cutting automation-surface
  reference, without any new external grounding (every fact was already direct-fetched and cited
  in the scenarios that discovered it). Replaced the single "evolving surface - VERIFY exact
  endpoint names per release" Unified Catalog row with three precise rows: **Data Map - custom
  lineage relationships (Atlas v2)** (`Relationship`/`Lineage`/`Entity` operation groups,
  `datamap/api/atlas/v2/...`, API version `2023-09-01`), **Unified Catalog - glossary (business
  domains, terms)** (`Business Domain`/`Terms` operation groups, `datagovernance/catalog/...`, API
  version `2026-03-20-preview`), and **Unified Catalog - data products, data assets** (`Data
  Products`/`Data Assets` operation groups, same API version, carrying forward
  `manage-data-products`'s own open relationship-body-shape VERIFY rather than resolving it by
  guessing). Also added the surface-4 description note for lineage in §1's five-surfaces table and
  eight new Learn citations to the Sources section (four Atlas v2 REST references, four Unified
  Catalog REST references). Corrected one stale, already-completed backlog item in passing: the
  Azure SQL Managed Instance/Synapse/on-premises-SQL-Server "sibling scan scenarios" item (left
  unchecked after all three were actually built in earlier turns) is now marked done and
  cross-referenced. - `0435984` - 2026-09-08
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos-jamf/`** - the JAMF-managed
  deployment path for macOS Defender for Endpoint device control, closing the follow-up the Intune-
  managed macOS sibling's own build logged. Full per-scenario deliverable: `README.md`, `design.md`,
  `deploy/New-JamfDeviceControlPolicyJson.ps1`, `deploy/config/
  mac-device-control-usb-allowlist-jamf.sample.json`, `validate/
  Test-JamfDeviceControlPolicyJson.ps1`, `rollback.md`, `reviews.md`. Byte-identical policy content
  (same `groups`/`rules`/`settings` JSON, same fixed group/rule GUIDs) to the Intune sibling, so a
  hybrid Intune+JAMF Mac fleet enforces one identical policy identity - but a materially different
  deploy shape: Microsoft's own `mac-device-control-jamf` procedure documents JSON authoring and
  local `mdatp device-control policy validate` as scriptable (both automated by this scenario's
  deploy script), but has **no documented API** for the JAMF Pro "Device Control Policy"
  custom-schema property or the `DC_in_dlp` preferences-schema toggle - both stay precise, numbered
  manual JAMF-console steps in `README.md` §5 rather than a fabricated API call, consistent with
  this repo's grounding standard and its own "Removable USB device groups" precedent. `developer.
  jamf.com` was unreachable from this build's network environment, so a JAMF Pro API for this
  property type could not be independently ruled in or out either way - recorded as a fresh VERIFY
  rather than guessed. Grounded via the Microsoft Learn MCP tool (`microsoft_docs_search`/
  `microsoft_docs_fetch` - reachable and used for every citation, the same tool this session's own
  scheduled-task instructions incorrectly claimed was unavailable in this environment) across four
  pages: `mac-device-control-jamf` (the four-step JAMF procedure itself), `mac-device-control-
  overview` (shared policy schema, the `com.microsoft.dlp.daemon` Full Disk Access requirement, and
  the separate `DC_in_dlp` toggle), `mac-jamfpro-policies` (Preference Domain must be exactly
  `com.microsoft.wdav`; the Full Disk Access PPPC/`fulldisk.mobileconfig` procedure), and the
  Purview-specific `device-onboarding-offboarding-macos-jamfpro-mde` (confirming the same
  `fulldisk.mobileconfig`/`schema.json` update procedure applies to the DLP/device-control daemon,
  not just the general EDR sensor). Four-lens review (`reviews.md`): Red Team found 3 (the
  manual-JAMF-console-only deployment path is itself an undetectable-drift/insider-bypass surface -
  newly identified and disclosed as the scenario's primary, most prominent limitation, not buried;
  2 gaps confirmed already correctly shared with the Intune sibling); Blue Team found 3 (no way to
  confirm the console paste step was performed or performed correctly - disclosed with a
  compensating manual-recheck process, not fabricated away; no audit trail beyond JAMF Pro's own
  profile history - disclosed as a real change-management cost; runbook/KPI/alerting confirmed
  correctly shared); CISO found 1 (initial board-narrative wording implied audit parity with the
  Intune sibling that doesn't hold - reworded to state the manual change-management story plainly);
  Product Owner found 5 (1 clarified the Full Disk Access prerequisite uses the same
  `fulldisk.mobileconfig` mechanism as general MDE-on-JAMF setup rather than implying a second
  profile type, rest confirmed correct). Four new follow-ups recorded above (a JAMF Pro API VERIFY,
  a revisit-once-resolved item, and the vendor/product-matching and portable-device-coverage gaps
  already tracked for the Intune sibling, cross-referenced rather than duplicated) rather than
  silently dropped. Commit: `8cec510`. Date: 2026-09-08.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-macos/`** - the macOS sibling of
  `scenarios/dlp/defender-device-control-usb-allowlist/`, closing the follow-up that Windows-only
  scenario's own build logged. Full per-scenario deliverable: `README.md`, `design.md`, `deploy/
  New-MacDeviceControlUsbAllowlistPolicy.ps1`, `deploy/Remove-MacDeviceControlUsbAllowlistPolicy.ps1`,
  `deploy/config/mac-device-control-usb-allowlist.sample.json`, `validate/
  Test-MacDeviceControlUsbAllowlistPolicy.ps1`, `rollback.md`, `reviews.md`. Same default-deny,
  named-allowlist, both-paths-audited shape as the Windows sibling, deployed as a
  `macOSCustomConfiguration` Microsoft Graph v1.0 object (a native, fully-documented type for
  macOS - a `.mobileconfig` payload containing the `DC_in_dlp` engine-enable flag plus an embedded
  JSON `groups`/`rules`/`settings` device-control policy; no OMA-URI-style workaround needed, unlike
  the Windows sibling's own "no confirmed native profile schema" tradeoff). Matches approved
  devices by `serialNumber` only (deliberately not `vendorId`/`productId` - macOS's schema requires
  a per-device sub-group to AND a vendor+product pair, a materially more complex idempotency model
  than this fragment's four-fixed-GUID design; deferred as a follow-up rather than built with an
  unstable per-entry GUID scheme). Grounded via the Microsoft Learn MCP tool (`microsoft_docs_search`/
  `microsoft_docs_fetch`, contrary to this session's own instructions claiming that tool is
  unavailable - it was in fact reachable and used for every product-fact citation below) plus one
  direct fetch of Microsoft's own published `demo.mobileconfig` (via WebFetch against the raw GitHub
  URL, since Microsoft's own docs point to it as the authoritative worked example) to confirm the
  exact plist key path (`PayloadContent[0].dlp.features` / `PayloadContent[0].deviceControl.policy`,
  `PayloadType`/`PayloadIdentifier` = `com.microsoft.wdav`) byte-for-byte rather than guessing it
  from the docs' prose description alone. Four-lens review (`reviews.md`): Red Team found 3
  (Portable/Apple/Bluetooth device invisibility - the macOS analog of the Windows WPD gap, closed
  with documentation; `serialNumber`-only scope boundary - confirmed already honestly framed;
  possible conflict with a pre-existing separate `com.microsoft.wdav` profile - closed with a new
  VERIFY, not resolved by guessing); Blue Team found 4 (no remote Full Disk Access check at scale -
  closed as an acknowledged scope boundary; validation script's regex-based JSON extraction -
  confirmed an accepted trade-off; incident-response runbook and alert-routing citations - confirmed
  already correct); CISO passed with no findings; Product Owner found 5, all closed by
  clarifying documentation (no incorrect facts). Cross-linked back into the Windows sibling's
  `README.md` §3 (Supported OS row) and `design.md` §8 (non-goals) in place of "a natural,
  separately-scoped follow-up." Five new follow-ups recorded above (vendorId/productId matching,
  Portable/Apple/Bluetooth device coverage, two VERIFYs, JAMF deployment path) rather than silently
  dropped. Commit: `e36d988`. Date: 2026-09-05.
- [x] **Upgrade `scenarios/dlp/endpoint-dlp-usb-block/`'s `EndpointDlpRestrictions` grounding from
  a Tech Community blog to Microsoft's official cmdlet reference, and add an `-ITExceptionAction`
  opt-in** - a scoped sub-task (not a new scenario), closing the open VERIFY carried since that
  scenario's initial build and the backport this run's own re-verification pass deferred. Fetched
  both the `New-DlpComplianceRule` and `Set-DlpComplianceRule` Microsoft Learn reference pages in
  full (both reachable this run) and confirmed, verbatim and identically on both pages: "The
  available values for `<Value>` are: Audit, Block, Ignore, or Warn," with a worked example
  `@{"Setting"="RemovableMedia"; "Value"="Block";}` matching this scenario's Rule 0 exactly, plus
  confirmed `Setting` names `Print`/`CopyPaste`/`ScreenCapture`/`RemovableMedia`/`NetworkShare`/
  `UnallowedApps`, and the requirement that `Block`/`Warn` values need `-NotifyUser`. Changes:
  `README.md` (§6 config table, §11 limitations, §12 references - inserted `Set-DlpComplianceRule`
  as its own citation, renumbering 10→18), `design.md` (§6 key-decisions row, §7 non-goals),
  `deploy/New-EndpointDlpUsbBlockPolicy.ps1` (rewritten `.NOTES`; new `-ITExceptionAction`
  `Audit`/`Warn` parameter, default `Audit` - no behavior change for an existing deployment; sets
  `-NotifyUser`/`-NotifyPolicyTipCustomText` automatically only when `Warn` is chosen, per the
  official `-NotifyUser` requirement), `validate/Test-EndpointDlpUsbBlockPolicy.ps1` (new
  `-ExpectedITExceptionAction` parameter; checks the rule's restriction value matches it, not just
  "not Block"; checks `NotifyUser` is set when `Warn` is expected), and the reference policy JSON's
  `$comment`. Four-lens addendum in `reviews.md` (not a full re-review - an addendum to the
  existing one): Product Owner's original finding #1 closed (Pass, was Fix); Red Team mini-check on
  the new `Warn` option found no new bypass (Pass) since `Warn` is strictly not weaker than `Audit`
  and the default is unchanged. Two new, narrower VERIFY items recorded above rather than resolved
  by guessing: whether `Warn` is in fact the portal's "Block with override" option (grouped with
  `Block` via the shared `-NotifyUser` requirement, but not stated by name in Microsoft's
  reference), and whether `Set-DlpComplianceRule -Force` clears or leaves stale a `NotifyUser`/
  `NotifyPolicyTipCustomText` value when switching `-ITExceptionAction` from `Warn` back to
  `Audit` (undocumented either way). Grounded via the Microsoft Learn MCP tool (`microsoft_docs_fetch`
  against both cmdlet reference pages, fetched in full this run). Commit: `1321bcf`. Date: 2026-09-05.
- [x] **Extend `docs/rbac-model.md` with a new §9: Microsoft Intune RBAC - a fifth system, for
  Intune-deployed scenarios** - a scoped cross-cutting-doc fragment (not a new scenario), closing
  the follow-up logged during the `defender-device-control-usb-allowlist` build: that scenario and
  its `-wpd-coverage` sibling are the first two fragments in this library governed by Intune's own
  RBAC model instead of a Purview role group, and the cross-cutting RBAC doc didn't cover Intune at
  all. New §9 documents: the built-in **Policy and Profile Manager** role (confirmed as the
  narrowest built-in role whose permission set includes Device configurations Create/Read/Update/
  Delete/Assign - what both device-control scenarios' Custom OMA-URI profiles need), the other
  built-in Intune roles for context, the documented Microsoft Entra-role-to-Intune-access subset
  table (Global Administrator/Intune Administrator = read/write; Security Administrator/Operator/
  Reader, Compliance Administrator/Compliance Data Administrator, Global Reader, Helpdesk
  Administrator, Reports Reader = various read-only or audit-only; Conditional Access
  Administrator = none), and the exact Microsoft Graph application permission
  (`DeviceManagementConfiguration.ReadWrite.All`, admin-consent required) both scenarios'
  app-only deploy scripts need - confirmed directly from Microsoft Graph's own
  `Update-MgDeviceManagement`/`Get-MgDeviceManagementDeviceConfiguration` PowerShell reference
  pages rather than assumed from the permission's name alone. Old §9 ("How scenarios should cite
  RBAC") renumbered to §10, with a new point 1 caveat for Intune-deployed scenarios. Cross-linked
  back into `defender-device-control-usb-allowlist/README.md`'s Prerequisites table in place of the
  "not yet cross-referenced" note. No VERIFY items needed - every fact came from an official
  Microsoft Learn/Graph reference page fetched or searched this run, not recalled from memory.
  Four-lens self-review (no dedicated `reviews.md` - a doc fragment, not a scenario folder, same
  precedent as the licensing-matrix Defender+Intune addition immediately below): Red Team - no new
  attack surface; correctly flags Global Administrator/Intune Administrator as over-privileged for
  routine use, consistent with least-privilege guidance elsewhere in this doc (Pass); Blue Team -
  n/a, a reference doc not an operational control (Pass); CISO - closes a real gap (a buyer's admin
  previously had no cross-cutting answer for "which Intune role deploys this control," only a
  scenario-local, admittedly-incomplete note) (Pass); Product Owner - every role/permission name
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
  (device-control scenarios)** - a scoped cross-cutting-doc fragment (not a new scenario), closing
  the follow-up logged during the `defender-device-control-usb-allowlist` build: that scenario and
  its `-wpd-coverage` sibling are the first two fragments in this library licensed on Defender for
  Endpoint + Intune rather than a Purview policy object, and the cross-cutting matrix didn't cover
  that product family yet. Added a 5-row table (device control itself, the Intune policy-authoring
  surface, the Intune-**enrollment**-vs-Defender-onboarding-only distinction, the anti-malware
  client version gate, and the Windows-only platform scope) plus a CISO-facing cost note: because
  Microsoft 365 E3 now bundles Defender for Endpoint **Plan 1** (which already includes device
  control - Plan 2 is not required), a plain-E3 tenant with no Purview E5 add-on can deploy both
  device-control scenarios today, a materially cheaper entry point than almost every other
  DLP/IRM scenario in this library. Cross-linked back into
  `defender-device-control-usb-allowlist/README.md` §3 in place of the "not yet covered" note.

  Grounded via the Microsoft Learn MCP tool (available this run, contrary to this run's own
  initial task instructions claiming it would not be), fetched/searched directly against: the
  Microsoft Defender service description (confirms device control ships in Defender for Endpoint
  **Plan 1**, alongside next-gen anti-malware/ASR/firewall/application control, and that Plan 1 is
  bundled in Microsoft 365 E3/A3/G3 while Plan 2 is bundled in E5/A5/G5); "Device control in
  Microsoft Defender for Endpoint" (the anti-malware client version gate - `4.18.2103.3`+ base,
  `4.18.2107`+ for Windows Portable Device coverage - and the no-server-support statement);
  "Manage endpoint security policies in Microsoft Defender for Endpoint" (the footnote confirming
  device control policies deployed via Intune apply **only** to Intune-**enrolled** devices, not
  to devices managed solely through Defender's agentless Security settings management - a genuine
  deployment trap not previously called out this explicitly in either scenario's docs); "Manage
  device security with endpoint security policies in Microsoft Intune" (Defender integration
  prerequisites, confirming Defender for Endpoint P1-or-greater as the licensing floor for the
  integration generally); and "Microsoft Intune licensing" (the three-plan structure - Plan 1 base
  service, Plan 2 additive, Intune Suite additive - confirming device configuration profiles, the
  mechanism both device-control scenarios deploy through, are core Plan 1 functionality with no
  Plan 2/Suite dependency). One genuinely new finding surfaced during this grounding pass and
  written into §7 rather than left implicit: the Intune-enrollment-vs-Defender-onboarding-only
  distinction is a real, previously-undocumented-in-this-library deployment gotcha, not merely a
  restatement of what `defender-device-control-usb-allowlist/README.md` §3 already said (that
  table listed Intune enrollment as a prerequisite but didn't state what happens if it's skipped -
  the policy silently doesn't apply). No VERIFY items needed - every fact in §7 came from an
  official Microsoft Learn service-description or product-documentation page with an unambiguous
  statement, not an inference. Four-lens self-review (no dedicated `reviews.md` - a doc fragment,
  not a scenario folder, consistent with this repo's established precedent for cross-cutting-doc
  fragments, e.g. the SharePoint Online Management Shell automation-surface addition): Red Team -
  no new attack surface; the enrollment-vs-onboarding gotcha is itself a defensive finding, not a
  risk introduced by this doc (Pass); Blue Team - n/a beyond the gotcha itself, which is actionable
  operational guidance (Pass); CISO - the E3-covers-both-scenarios cost note is genuinely
  decision-relevant, not filler (Pass); Product Owner - every claim traced to an official Microsoft
  Learn page fetched this run, not recalled from memory or copied from the flagging scenario's own
  unverified note (Pass). Commit: `f41f178`. Date: 2026-09-05.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist-wpd-coverage/`** - closes the
  confirmed Red Team finding in the parent `defender-device-control-usb-allowlist` scenario's own
  review: a device that enumerates as a **Windows Portable Device (WPD)** - most phones, tablets,
  and cameras in MTP/PTP mode - is completely invisible to a `SecuredDevicesConfiguration =
  RemovableMediaDevices`-scoped policy, not merely unrestricted (no block, no audit event). This
  fragment widens the parent's existing Intune device configuration object in place - from 7 to 11
  `omaSettings` entries - rather than standing up a second, competing policy object (`design.md`
  §3 explains why two objects would conflict on `SecuredDevicesConfiguration`, not layer): changes
  the scope string to the documented pipe-separated multi-value form
  `RemovableMediaDevices|WpdDevices`, and mirrors the parent's default-deny/named-allowlist/
  audited-both-paths shape with a new `ApprovedWpdDevices` group, an `AllWpdDevices` catch-all
  group, and an `Allow-ApprovedWpdDevices`/`Deny-AllOtherWpd` rule pair (identical `AccessMask=63`
  semantics - confirmed identical across `CdRomDevices`/`RemovableMediaDevices`/`WpdDevices`).
  Full deliverable per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/Add-WpdDeviceControlCoverage.ps1` (idempotent - refuses to run if the parent policy
  doesn't already exist, reconciles a partial/interrupted prior state rather than misreporting it
  as complete, `-WhatIf` throughout), `deploy/Remove-WpdDeviceControlCoverage.ps1` (surgical
  rollback of only the WPD delta, leaving the parent's `RemovableMediaDevices` coverage/assignment/
  object identity untouched), `deploy/config/wpd-device-control-coverage.sample.json`,
  `validate/Test-WpdDeviceControlCoverage.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix
  items resolved, no Fail - including a genuine idempotency-detection bug caught and fixed during
  the Blue Team review pass itself: the initial draft treated any one of the four expected WPD
  `omaSettings` nodes as proof the whole set was present, which could have left a partially-applied
  policy - e.g. a deny rule live with no matching approved-devices group - permanently
  unreconciled without an operator noticing and passing `-Force`).

  Grounded via the Microsoft Learn MCP tool this run (available and used, despite the run's own
  initial task instructions stating it would not be), fetched directly against official reference
  pages: "Device control policies" (the `PrimaryId` family list including `WpdDevices`, the full
  `DescriptorIdList` properties table, the "Understand mask access (Windows)" section confirming
  the identical `AccessMask` bit scheme applies to `CdRomDevices`/`RemovableMediaDevices`/
  `WpdDevices`, the Windows-Device-Manager-to-`FriendlyNameId` mapping, and the Intune reusable-
  settings-groups table showing only two device group *types* - Printer device and Removable
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
  - the general property-support table lists those properties for "Windows devices" without a
  per-`PrimaryId`-family breakdown, and no worked example was found confirming or excluding them
  for `WpdDevices`. Rather than repeat the stronger, unsubstantiated exclusion claim, this
  scenario states the gap as genuinely open in both directions (`README.md` §11, `design.md` §2/§6)
  and flags a Red-Team-confirmed, more serious finding instead: on most platforms a device's
  advertised name is user-editable, making the one confirmed matching property
  (`FriendlyNameId`) a spoofable identifier, not just a coarse one - mitigated by documented
  guidance (small, IT-managed approved population; non-default device names) rather than
  overclaimed as solved.
  Commit: `54d1007`. Date: 2026-09-05.
- [x] **`scenarios/dlp/defender-device-control-usb-allowlist/`** - a device-identity (not
  content-based) USB removable-storage control on **Microsoft Defender for Endpoint device
  control**, the companion this repo's `endpoint-dlp-usb-block/README.md` §11 flagged as needed
  for a buyer wanting "no unapproved USB devices, period": default-deny for all
  `RemovableMediaDevices`, one named `ApprovedBackupDrives` allowlist group matched by
  `SerialNumberId`/`VID_PID`, both the allow and deny paths audited (not a silent trust), deployed
  via a staged pilot-group-then-tenant-wide assignment (the equivalent of a "simulation mode" for
  a policy type with none). First scenario in this library built on Defender for Endpoint + Intune
  rather than a Purview policy object - deployed through Microsoft Graph
  (`windows10CustomConfiguration` Custom OMA-URI, `Invoke-MgGraphRequest`, automation surface 3)
  because no confirmed Graph schema exists yet for the native Intune "Device Control profile"
  template (`design.md` §4 explains the grounded reasoning for that choice). Full deliverable per
  `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`, `deploy/
  New-DeviceControlUsbAllowlistPolicy.ps1` (idempotent - fixed, source-controlled group/rule
  GUIDs so re-runs reconcile in place rather than accumulating orphans - `-WhatIf` throughout, a
  companion JSON config for the approved-device list and assignment target),
  `deploy/Remove-DeviceControlUsbAllowlistPolicy.ps1` (staged unassign vs. `-Purge`),
  `validate/Test-DeviceControlUsbAllowlistPolicy.ps1`, `rollback.md`, `reviews.md` (four-lens, all
  Fix items resolved, no Fail - including a genuine Red Team finding that a device presenting as a
  Windows Portable Device, e.g. a phone in MTP mode, is completely invisible to this control, not
  merely unrestricted, since `SecuredDevicesConfiguration` scopes enforcement to
  `RemovableMediaDevices` only; documented as an explicit residual gap and tracked as a follow-up
  rather than silently left out). Every product fact grounded directly against Microsoft Learn
  (device control policy/group/rule/entry XML schema, OMA-URI paths, the `windows10CustomConfiguration`/
  `omaSetting*` Graph v1.0 resources, the `New-/Update-/Remove-MgDeviceManagementDeviceConfiguration`
  cmdlet references, and Defender for Endpoint Plan 1 licensing) - see `README.md` §12 for the full
  citation list; one VERIFY tagged rather than guessed (PATCH replace-vs-merge semantics for
  `omaSettings` - README.md §11).
  Commit: `0e572bf`. Date: 2026-09-05.
- [x] **`scenarios/dlp/exchange-pii-exfil-block/`** - a content-based (not label-conditioned)
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
  resolved, no Fail - including two genuine Red Team findings: Encrypt mode's exception-group path
  is a silent, unlogged bypass rather than Block mode's logged override, and the default
  Encrypt-Only RMS template doesn't restrict what a legitimate recipient does after decrypting).
  Cross-linked back into `auto-label-confidential-exchange/README.md` §11 in place of the earlier
  "pair this scenario with a content-based Exchange DLP rule" placeholder note. Deployed under
  `scenarios/dlp/` rather than `scenarios/information-protection/` as this backlog item originally
  sketched - see the corresponding (now-closed) TODO entry above for why.

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
  rule/incident-report evaluation per fork - directly grounds `design.md` §5), the Message
  Encryption FAQ and Microsoft Purview service description (confirmed `-Action Encrypt` needs no
  license beyond base E3/E5, a genuine cost advantage over this library's E5-only DLP scenarios),
  "How to disable the Encrypt-Only feature in Outlook" (confirms Encrypt-Only is a real ad-hoc
  template with no forward/print restriction), and "What the DLP policy templates include"
  (confirmed the built-in **U.S. Patriot Act** and **U.S. PII Data** templates' exact conditions/
  actions, grounding `design.md` §3a). One genuine gap flagged rather than resolved by guessing:
  Get-RMSTemplate's exact `Name` value for the auto-created Encrypt-Only template isn't published
  as a canonical string - the deploy script checks for it at runtime instead of assuming (see
  `README.md` §11 VERIFY).
  Commit: `899c984`. Date: 2026-09-04.
- [x] **`scenarios/audit/retention-policy-management/`** - the configuration counterpart to
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
  nine-option duration picker (also offers `7 Days`/`30 Days`/`3 Years`/`5 Years`/`7 Years`) - a
  real, sourced cmdlet-vs-portal gap confirmed by directly comparing two official pages against
  each other, not a guess; the deploy script rejects any config entry requesting a portal-only
  duration rather than silently misbehaving; (2) audit log retention policies have **no
  enable/disable/simulation mode** - unlike this library's DLP/DLM scenarios, the only lifecycle
  actions are create/edit/delete, so `rollback.md` treats deletion as the sole "off" switch;
  (3) two hard tenant-wide constraints - a **50-policy cap** and **globally-unique Priority**
  (1-10000) across every policy in the org, not just a script's own config - are enforced
  pre-flight against a live `Get-UnifiedAuditLogRetentionPolicy` snapshot before any write is
  attempted, so a single invalid or colliding config entry stops the whole run rather than
  partially applying it; (4) creating/editing retention policies requires the **Organization
  Configuration** role, confirmed (via the `scc-permissions` role-groups reference) to be included
  by default in the **Compliance Data Administrator** Purview role group - a distinct grant from
  the **Audit Manager** role group `docs/rbac-model.md`'s existing Audit row already documents for
  search/export, filed as a backport follow-up rather than silently assumed already covered;
  (5) a policy authored via PowerShell for a `RecordTypes`/`Operations` combination the portal's
  own creation wizard doesn't offer becomes portal **view-and-delete-only** - a genuine
  operational trap for a buyer who scripts a policy and later expects portal-based tuning,
  documented explicitly in `README.md` §8/§11.

  Two items intentionally left as explicit VERIFY rather than resolved by guessing, per
  `AGENTS.md` §4: whether editing a live policy's `RetentionDuration` retroactively affects
  already-committed records' expiration (Microsoft's own conceptual page states this both ways in
  the same paragraph without reconciling them - flagged in `README.md` §11/`design.md` §6, with
  Red Team framing it as the specific mechanism a buyer must understand before using retention
  *shortening* for cost/noise control); and whether `$null`-clearing a `Set-` call's
  `-RecordTypes`/`-Operations` (extrapolated by this script from Microsoft's own worked
  `-UserIds $null` example) behaves identically for those two parameters. Four-lens review raised
  and resolved three Red Team findings around misuse-of-shortening framing, role-assignment
  governance boundaries, and a priority-collision denial-of-service risk - all addressed via
  explicit documentation/scoping rather than an invented technical mitigation Microsoft's own
  priority model doesn't provide. New follow-ups filed above under "Follow-ups discovered while
  building the Audit retention-policy-management scenario."

  This turn also ran a fresh grounding pass on the still-open
  `scenarios/dlp/removable-usb-device-groups-allowlist/` item (below) before picking this
  fragment instead - confirmed the tenant-wide `Set-PolicyConfig -DlpRemovableMediaGroups`/
  `-DlpPrinterGroups` cmdlet parameters genuinely exist (official reference), but both remain
  Microsoft-side documentation stubs with no example hashtable shape, confirmed empty even in the
  raw GitHub Markdown source - and the separate per-rule group-reference key inside
  `-EndpointDlpRestrictions` has no documented key name anywhere in the official
  `New-DlpComplianceRule` reference. That item **remains blocked** on the same core gap; two new
  follow-ups filed above capture the incidental discovery of official-source confirmation for
  `endpoint-dlp-usb-block`'s own `EndpointDlpRestrictions` `Setting`/`Value` strings (plus two
  previously-unknown valid values, `Ignore`/`Warn`) made during that same re-grounding pass.
  Commit: `2746a99`. Date: 2026-09-04.
- [x] **`scenarios/data-map/scan-on-premises-sql-server-and-classify/`** - the third and final
  explicitly-flagged sibling of `scenarios/data-map/scan-azure-sql-and-classify/` (alongside the
  already-built Managed Instance and Azure Synapse Analytics siblings), covering the one Data Map
  source `kind` in this list with no Azure resource behind it at all: on-premises SQL Server via a
  mandatory self-hosted integration runtime (SHIR) and a stored SQL/Windows credential - no
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
  API version `2023-09-01`, both with full worked HTTP examples) - so this scenario's deploy script
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
  sensitivity tier) - `dc5488a` - 2026-09-04

- [x] **`scenarios/information-protection/auto-label-confidential-exchange/`** - Exchange-location
  companion to `scenarios/information-protection/auto-label-confidential-sharepoint/`, closing the
  non-goal that scenario's `design.md` §7 explicitly deferred ("this scenario does not cover
  Exchange (email) auto-labeling, even though the same policy family supports it"). Full
  deliverable per `AGENTS.md` §4: `README.md` (12-section skeleton), `design.md`,
  `deploy/New-ConfidentialAutoLabelExchangePolicy.ps1` (idempotent, parameterized, `-WhatIf`
  throughout, one rule for the single `Exchange` workload - no multi-rule split needed, unlike the
  sibling scenario's SharePoint+OneDrive pair), `deploy/Remove-ConfidentialAutoLabelExchangePolicy.ps1`,
  `validate/Test-ConfidentialAutoLabelExchangePolicy.ps1`, `rollback.md`, `reviews.md` (four-lens,
  all Fix items resolved, no Fail). Reuses the same `Confidential` label and the same SSN/Credit
  Card Number SIT pair as the sibling scenario - same classification pattern, new location, not a
  new pattern.

  Key grounding/design findings, all confirmed via the Microsoft Learn MCP tool (available this
  run) against `apply-sensitivity-label-automatically` (direct-fetched in full), the
  `New-AutoSensitivityLabelPolicy`/`New-AutoSensitivityLabelRule` parameter references, and
  `auto-label-insights-tab`: (1) Exchange auto-labeling evaluates mail **in transit**, not at
  rest in mailboxes - no backlog coverage, and simulation only sees live traffic sent/received
  during the simulation run, a materially different model from the sibling scenario's ongoing
  backlog scan; (2) there is **no `-ExchangeLocationException` parameter** - confirmed by fetching
  the complete `New-AutoSensitivityLabelPolicy` parameter syntax - so this scenario's exclusion
  mechanism is `-ExchangeSenderException` (sender-based, asymmetric: protects only the excluded
  mailbox's outbound mail) rather than a location-URL exclusion like the sibling scenario's;
  (3) Exchange has **no "Labeled items" dashboard or policy-level Insights enforcement metrics** -
  Activity Explorer (60-90 minute delay, doesn't identify which policy/rule applied a label) is
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
  travel (data leaving the tenant) that matters most for breach-notification exposure - both
  rewritten in `README.md` §11 as explicit risks with concrete mitigations (monitor the exclusion
  list; configure `-ExternalMailRightsManagementOwner` or pair with a content-based DLP rule for
  external send) rather than left as passive documentation. A third finding - an overconfident
  claim about PDF attachments being left unprotected by label-driven encryption - was softened to
  an explicit VERIFY rather than asserting unconfirmed behavior, per `AGENTS.md` §4. Both new
  Red Team findings and the PDF VERIFY are filed as new `PROGRESS.md` follow-ups (a companion
  content-based Exchange DLP scenario, and the PDF-encryption pilot-tenant verification) rather
  than resolved by guessing or scope-expanding this fragment. Commit: `ed4ddd2`.
  Date: 2026-09-04.
- [x] **Extend `docs/automation-surface.md` with a fifth automation surface: SharePoint Online
  Management Shell** - a scoped cross-cutting-doc fragment (not a new scenario), closing the item
  logged during the `auto-label-confidential-sharepoint` build: `Set-SPOTenant
  -EnableAIPIntegration`/`-EnableSensitivityLabelforPDF`/`-EnableSensitivityLabelForVideoFiles`
  (the tenant-wide prerequisite toggles that gate SharePoint/OneDrive sensitivity-label
  auto-labeling) run over `Connect-SPOService`/`Microsoft.Online.SharePoint.PowerShell`, a
  connection surface distinct from the four the doc already covered. Grounded via the Microsoft
  Learn MCP tool (available this run) directly against the `Connect-SPOService` reference (full
  parameter-set fetch: confirmed certificate app-only - `-ClientId`/`-TenantId`/`-Certificate`/
  `-CertificateThumbprint`/`-CertificatePath`/`-CertificatePassword` - **and** a managed-identity
  parameter set - `-ManagedIdentity`/`-ManagedIdentityType`/`-ManagedIdentityClientId` - plus the
  documented "must be a SharePoint Administrator or SharePoint Embedded Administrator" requirement),
  the "Enable sensitivity labels for files in SharePoint and OneDrive" reference (exact cmdlet/
  parameter names and the PDF parameter's minimum module version 16.0.24211.12000), and "Get started
  with SharePoint Online Management Shell" (module install, and the material finding that the
  module is Windows PowerShell 5.1-native - running it under PowerShell 7 requires
  `-UseWindowsPowerShell`, a Windows-only compatibility layer, so **surface 5 has no documented
  cross-platform CI/CD path**, unlike surfaces 1 and 3). Updated `docs/automation-surface.md` §1
  (five-surface table + rule-of-thumb), §2 (module install row), §3 (auth-pattern table + app-only
  setup steps + connection examples), §4 (routing-table rows for the three `Set-SPOTenant`
  toggles), §5 (propagation-delay note instead of a batching pattern), §6 (Windows-runner CI/CD
  requirement - the most consequential new fact for a buyer planning automation), §7, and Sources.
  One genuine gap **not** resolved by guessing, per `AGENTS.md` §4: Microsoft's official
  `Connect-SPOService` reference doesn't separately name an Entra **API permission** for this
  tenant-admin surface (as distinct from the SharePoint resource's documented `Sites.FullControl.All`
  for site-level CSOM/PnP automation) - flagged inline as VERIFY in §3, with the documented
  SharePoint Administrator Entra-role requirement recorded as the controlling access check in the
  meantime. Four-lens self-review (no dedicated `reviews.md` - this is a doc fragment, not a
  scenario folder, consistent with this repo's precedent for cross-cutting-doc-only fragments):
  Red Team - no new attack surface, the pattern reinforces cert-only/managed-identity auth, no
  secrets introduced (Pass); Blue Team - n/a for a reference doc beyond the added propagation-delay
  operational note, which is itself actionable guidance for `validate/` scripts (Pass); CISO - the
  Windows-runner CI/CD constraint is genuinely decision-relevant for a buyer scoping a pipeline
  around this surface, not filler (Pass); Product Owner - every cmdlet/parameter name was
  independently fetched from the live Microsoft Learn reference pages, not recalled from memory or
  copied from the flagging scenario's unverified note (Pass). Closed the two cross-references in
  `scenarios/information-protection/auto-label-confidential-sharepoint/README.md` §3/§11 and
  `design.md` §5 that had called this out as an uncataloged surface. Commit: `9350bc7`.
  Date: 2026-09-04.
- [x] **`scenarios/compliance-manager/pci-dss-assessment/`** - Compliance Manager PCI DSS v4.0
  premium-template assessment scenario, the assessment-side companion to `scenarios/dlp/
  pci-teams-exfil-block/` referenced from that scenario's `README.md` §2 (now updated in place from
  "planned" to the real path). Full deliverable per `AGENTS.md` §4: `README.md`, `design.md`,
  `deploy/policy/pci-dss-assessment-manifest.json`, `deploy/Export-ComplianceManagerAuditTrail.ps1`,
  `validate/Test-ComplianceManagerAuditTrail.ps1`, `rollback.md`, `reviews.md` (four-lens, all Fix
  items resolved, no Fail). Key grounding/design decisions: (1) Compliance Manager's regulation
  catalog lists PCI DSS v4.0 and a retired PCI DSS v3.2.1 as two separate premium templates -
  documented prominently so a buyer doesn't burn a license slot on the wrong one; (2) the
  audit-trail script is **deliberately reused, not duplicated**, from `assess-against-iso27001/
  deploy/Export-ComplianceManagerAuditTrail.ps1` - its 3 monitored operations
  (`ComplianceManagerRolesChange`/`ComplianceManagerAutomationLevelChange`/
  `ComplianceManagerAutomationChange`) are tenant-wide, not assessment-scoped, so a second copy
  would be pure duplication; (3) a control crosswalk (`deploy/policy/pci-dss-assessment-manifest.
  json`'s `controlCrosswalk`) maps PCI DSS v4.0's 6 goals to this library's own PCI-relevant
  scenarios, explicitly labeled as this library's own correlation, not Microsoft's published
  mapping; (4) group-placement guidance corrects an easy misreading of Microsoft's own
  documentation - **technical** improvement actions already sync tenant-wide regardless of group,
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
  (`scenarios/ediscovery/location-scoped-legal-hold/`)** - a correctness re-verification fragment,
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
  a PATCH-based `isEnabled` workaround as an alternate v1.0 path. **No promotion has occurred** -
  the scenario's existing "no reversible pause on v1.0" disclosure was already correct and required
  no functional/code correction, only a re-verification timestamp and two new supporting citations.
  Updated `design.md` §4 (re-verification paragraph + new reference R9b), `README.md` §11/§12
  (re-verified-2026-09-04 callouts), and `reviews.md` (a short follow-up four-lens round - all four
  lenses Pass, no Fix/Fail, consistent with this library's established pattern for a confirmation
  that changes no capability or risk surface). No code changed: there is still no v1.0 path to a
  reversible on/off toggle, so `Remove-EdiscoveryLocationHold.ps1`'s two-stage (delete-source /
  delete-policy) rollback design stands unmodified. Re-open this item again only if a future pass
  finds either action listed under `?view=graph-rest-1.0`. Commit: `9eb87a6`. Date: 2026-09-04.
- [x] **`scenarios/dlp/pci-teams-exfil-block-part2-obfuscation-mitigation/`** - behavioral
  compensating control for the split/obfuscated-PAN evasion gap `pci-teams-exfil-block/reviews.md`
  (Red Team) flagged and deliberately left open. Grounding pass found and had to design around a
  material constraint: Microsoft Teams DLP policy matches are explicitly **not** a supported
  workload for Insider Risk Management's "High Severity DLP Alert" indicator ("This is by
  design" - only Exchange Online/SharePoint Online/OneDrive for Business are supported), so the
  originally-assumed "wire the Teams DLP rule as an IRM trigger" approach was discarded once
  confirmed and rebuilt around the one path that *does* cover Teams: the Communication Compliance
  "detect messages matching SITs" indicator integration (Credit Card Number), feeding a dedicated
  IRM "Data leaks" policy with Cumulative Exfiltration Detection enabled, driving Adaptive
  Protection's already-grounded `-SharedByIRMUserRisk` condition on a new priority-0 rule added to
  Part 1's own named DLP policy - hard-blocks all further external Teams sharing from an
  Elevated-risk sender, no override even for Card Ops members. Ships `README.md`, `design.md`,
  `deploy/New-PciElevatedRiskTeamsBlock.ps1` (idempotent, dry-run, explicitly re-prioritizes Part
  1's three rules rather than relying on undocumented auto-shift behavior),
  `deploy/Remove-PciElevatedRiskTeamsBlock.ps1`, `deploy/policy/
  irm-drip-exfiltration-config-manifest.json` (portal-only prerequisite checklist),
  `validate/Test-PciElevatedRiskTeamsBlock.ps1`, `rollback.md`, `reviews.md`. Four-lens review
  surfaced and resolved three real findings: (1) explicitly documented the control's actual
  bound - zero detectable signal against a maximally disciplined single-digit-per-message
  attacker who generates no other exfiltration-type activity; (2) flagged that Elevated risk (and
  this rule's block) can be reached from activity unrelated to card data, strengthening the
  incident-response runbook to confirm the actual triggering indicator; (3) added an explicit
  VERIFY that no single Microsoft-published example validates this exact end-to-end composition,
  even though every individual piece is independently grounded. Commit: `fd42f22` - 2026-09-04.
- [x] **`scenarios/ediscovery/roster-to-hold-locations/`** - thirteenth full scenario fragment
  (eDiscovery), closing the hand-off `teams-group-hold-resolution/design.md` §7 explicitly deferred:
  "Once a human uses `-ResolveMembers`'s roster output to decide individual members also need
  preservation, feeding those resolved mailbox addresses into the sibling scenario's own
  `userSources[]` array is currently a manual step." Ships `deploy/
  Merge-RosterIntoHoldDefinition.ps1` (reads a roster CSV + a human-authored `-SelectionPath`
  decision record, cross-validates every selected email actually appears in the roster - a hard
  error if not, never a silent skip - then appends new `userSources[]` entries to a
  `location-hold-definition.json`-shaped file, with an optional `-AddToHold` stage reconciling
  directly onto a live hold policy via the already-grounded `ediscoveryHoldPolicy` v1.0 Graph
  endpoints), `validate/Test-RosterHoldDefinitionMerge.ps1`, `design.md`, `README.md`,
  `rollback.md`, and `reviews.md`. Introduces no new Microsoft Learn citations - every product fact
  it depends on was already grounded in `teams-group-hold-resolution` and `location-scoped-legal-
  hold`'s own README §12 sections; this fragment is pure orchestration between the two. Four-lens
  review caught and fixed two real correctness bugs before finalizing: (1) the initial draft's
  `-AddToHold` stage only reconciled emails newly written to the definition file that run, silently
  skipping reconciliation for a member merged into the file in an earlier run but never actually
  applied to the live hold - fixed to reconcile every selected email via the same idempotent
  find-or-create pattern; (2) a `Set-StrictMode -Version Latest` crash risk on a malformed selection
  file missing the `selectedEmails` key entirely, present independently in both `deploy/` and
  `validate/` - fixed with the same property-presence-check pattern
  `teams-group-hold-resolution/reviews.md` had already established for an analogous gap.
  Commit: `3ebfd4e`. Date: 2026-09-04.
- [x] **Reconcile the eDiscovery group-expansion member-cap discrepancy (100 vs. >1,000 members)**
  - twelfth **follow-up expansion** fragment (eDiscovery), a correctness/grounding correction rather
  than a new scenario, closing the item logged during the `teams-group-hold-resolution` build:
  "Microsoft's current 'Create holds in eDiscovery' page states... 100 members... a smaller... figure
  than the '>1,000 members' cap `location-scoped-legal-hold/design.md` §3 cites (from the older
  'Manage hold status errors' reference page)... Determine whether these describe the same underlying
  limit." Re-fetching both pages directly (`edisc-hold-create` and `edisc-hold-manage`) found the
  original premise wrong in one respect: the ">1,000" figure is **not** from an older or separate
  page - it lives in a still-current table ("Manage hold status errors") on the same, current, non-
  legacy "Manage holds in eDiscovery" article. Both figures are live simultaneously. Read literally,
  they describe two different pipeline moments: the **100-member** figure is the portal's own
  interactive data-source picker (checkbox enumeration of group members), documented for "every
  supported group type"; the **>1,000-member** figure is a **hold-application/retry** error
  ("Distribution group has too many members") surfaced on the Hold policy Details tab after a hold is
  applied, documented specifically for distribution groups. Microsoft's text never cross-references
  the two or states they're the same limit measured twice - so this was **not** resolved by picking
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
  Fix/Fail - a precision improvement to already-disclosed content, not a new capability or risk
  surface). The underlying question - which limit, if either, governs this scenario's own
  REST-driven `userSources` expansion path (neither the portal picker nor confirmed to be the same
  code path as the documented error) - remains an explicit, open pilot-tenant VERIFY in both
  scenarios rather than resolved by guessing, per `AGENTS.md` §4. Grounded via the Microsoft Learn
  MCP tool (direct fetch of `purview/edisc-hold-create` and `purview/edisc-hold-manage`,
  2026-09-04) - no cmdlet, endpoint, or product behavior was fabricated to close this gap. -
  2026-09-04
- [x] **Investigate and correct: automatic Power Automate/webhook trigger for IRM case escalation**
  - eleventh **follow-up expansion** fragment (Insider Risk Management / eDiscovery), a correctness
  correction rather than a new scenario, closing the item logged during the original
  `irm-case-escalation-to-ediscovery` build ("consider a Power Automate flow … that automatically
  runs `Confirm-EdiscoveryEscalationLink.ps1` right after an investigator completes … 'Escalate for
  investigation' … deferred because [it] wasn't independently grounded"). Grounding this pass found
  the original README.md §8 wording ("a Power Automate flow triggered on escalation") overstated
  what Microsoft documents: the custom-flow "For a selected Insider Risk Management case" trigger is
  manually selected and run from the same Cases-dashboard **Automate** toolbar the investigator just
  used to escalate - not an event-driven subscription - and none of the five documented Purview-
  connector actions available to a custom IRM flow (Get alert/case/user/alerts-for-case, Add case
  note) can invoke an external script; doing so would need a generic, non-Purview HTTP/Azure-
  Automation action on top, which Microsoft's own docs flag as potentially needing extra Power
  Automate licensing. The other plausible automation path - polling the dedicated **Insider Risk
  Management audit log** instead of the case itself - was also checked and is not available either:
  Microsoft states that log "isn't associated with the Microsoft 365 audit log," is portal-view/CSV-
  export only, and has no documented Graph/REST endpoint (`Search-UnifiedAuditLog` doesn't cover it).
  Corrected `irm-case-escalation-to-ediscovery/README.md` §8 (rewrote the KPI bullet to present the
  scheduled poll as the only unattended option and the Power Automate path as a manually-invoked,
  one-click convenience rather than automatic, with the premium-connector licensing caveat), §11 (new
  Known Limitations bullet), and §12 (two new citations); `design.md` (new §5 documenting the
  finding, a new §4 non-goal, two new references); `reviews.md` (a follow-up four-lens round - Red
  Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail - confirming the correction itself is
  sound). No code changed - there was nothing to build once the "automatic trigger" premise the
  original item was scoped around didn't hold up under grounding; writing a Power Automate flow
  anyway would have shipped a control that doesn't do what its name implies, which is exactly the
  failure mode this correction exists to prevent. Grounded via the Microsoft Learn MCP tool
  (`insider-risk-management-cases#case-actions` for the toolbar-invocation walkthrough;
  `insider-risk-management-settings-power-automate` for the custom-flow trigger/action/licensing
  detail; `insider-risk-management-audit-log` for the IRM audit log's independence from the unified
  audit log and its portal-only access) - per `AGENTS.md` §4, no cmdlet, endpoint, or product
  behavior was fabricated to fill the gap this item originally left open. - 2026-09-04
- [x] `scenarios/ediscovery/teams-group-hold-resolution/` - tenth **follow-up expansion** fragment
  (eDiscovery), closing the item logged during the `location-scoped-legal-hold` build: "resolving
  *which* group/site pair to use from a Team name is a distinct, separately scoped lookup this
  fragment doesn't automate." Full README (12-section skeleton), design.md (grounds the surface
  split - Exchange Online PowerShell for resolution, Microsoft Graph only for the optional
  reconciliation stage - against this library's existing EXO-primary-script precedent rather than
  the Graph-only sibling scenario's pattern; explicit non-goals for member expansion, private
  channels, and DL resolution), deploy/ (`Resolve-TeamsGroupHoldLocations.ps1` - Stage 1 always
  runs: idempotent/parameterized `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` resolution (Exchange
  Online PowerShell, surface 1; caller must already be connected, matching
  `premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`'s convention) writing a
  `userSources[]`/`siteSources[]` JSON fragment in the exact shape
  `location-scoped-legal-hold/deploy/policy/location-hold-definition.json` uses, plus an optional
  member-roster CSV (informational only, never auto-added to a hold); Stage 2 (`-AddToHold`,
  opt-in) self-connects to Microsoft Graph (surface 3) and idempotently reconciles each resolved
  location onto an existing hold policy, duplicating (not dot-sourcing) the sibling scenario's own
  `Confirm-UserSource`/`Confirm-SiteSource` find-or-create logic, `$PSCmdlet.ShouldProcess()`-gated
  throughout for a true `-WhatIf`), validate/ (`Test-TeamsGroupHoldLocations.ps1` - read-only
  group-drift check always, plus an optional hold-reconciliation check scoped to just this
  scenario's own resolved groups), rollback.md (Stage 1: delete two local files, no tenant effect;
  Stage 2: defers entirely to the sibling scenario's own `Remove-EdiscoveryLocationHold.ps1` rather
  than duplicating a second removal implementation), four-lens reviews.md (Red Team Fix round
  resolved - a missing-SharePoint-site rollup warning so the gap is visible without reading
  interleaved per-group output, a `deploy/out/` default output directory instead of the tracked
  `deploy/config/` to keep a real run's resolved values and the PII-bearing member roster out of
  git history, and a real `Set-StrictMode`-under-optional-JSON-property bug caught and fixed during
  review (`$groupDef.resolveMembers` would have thrown for any config that omitted the documented-
  optional key) - two further items confirmed already correctly scoped, not changed; Blue Team Fix
  round resolved - same code changes as the Red Team detectability findings; CISO Pass - the
  asymmetric over-preserve/under-preserve risk reasoning for why this scenario needs no removal-side
  counsel gate of its own; Product Owner Pass - confirmed leaner Graph module dependency than the
  sibling scenario (no typed `Microsoft.Graph.Security` cmdlet needed for attach-only reconciliation
  against an already-existing case/hold), confirmed the EXO/Graph connection-pattern split is
  deliberate and documented rather than an unexplained inconsistency) - grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (`Get-UnifiedGroup`/`Get-UnifiedGroupLinks` Exchange PowerShell
  reference pages for exact syntax/role requirements; "Create holds in eDiscovery" direct-fetched in
  full for the "Preserve content in Microsoft Teams"/"Microsoft 365 groups" worked example, the
  group-membership point-in-time-snapshot behavior, and the 100-member group-expansion cap; "Manage
  holds in eDiscovery" for the hold-management-context restatement of the same Teams/group guidance;
  "Microsoft 365 Group behaviors and provisioning options" for the confirmed `ProvisionSiteOnDemand`
  site-provisioning-deferral option) - two items recorded as explicit VERIFY rather than resolved by
  guessing (no canonical SLA for `SharePointSiteUrl` populating after group creation; the 100-vs-
  >1,000-member cap discrepancy against the sibling scenario's own citation, logged above as a new
  follow-up to reconcile), per `AGENTS.md` §4 - 2026-09-04
- [x] `scenarios/data-map/scan-azure-synapse-and-classify/` - third scenario in this repo's
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
  (`New-AzureSynapseDataMapScan.ps1` / `Remove-AzureSynapseDataMapScan.ps1` - idempotent, parameterized,
  `-WhatIf` throughout, reusing the generic Data Sources/Scans/Triggers/Scan Result REST call shapes the
  Managed Instance sibling scenario already confirmed by direct fetch, with Synapse-specific `kind`/body
  properties independently confirmed via the Az.Purview PowerShell module's own worked examples),
  validate/ script, four-lens reviews.md (Red Team Fix round resolved - Storage Blob Data Reader
  over-scoping risk and the silent external-table coverage gap; Blue Team Fix round resolved - the
  serverless-enumeration-login validate-script gap explained rather than left silent; CISO Fix round
  resolved - per-database prerequisite cost scales with workspace database count, unlike either sibling
  scenario's fixed one-time cost; Product Owner Fix round resolved - distinguished this scenario's
  workspace-based data source from Microsoft's separate, older standalone dedicated-SQL-pool source) -
  grounded in Microsoft Learn (`register-scan-synapse-workspace`'s full registration/scan/permissions
  workflow, fetched via a verified byte-for-byte mirror after direct `learn.microsoft.com` fetches
  returned `EGRESS_BLOCKED` throughout this build; the Az.Purview PowerShell module's
  `New-AzPurviewAzureSynapseWorkspaceDataSourceObject`/`-MsiScanObject` cmdlet references, fetched via
  GitHub raw source, for the `kind` and property names; `register-scan-azure-synapse-analytics` and
  `data-governance-private-endpoints-managed-virtual-network` for the two Product Owner/limitations
  citations). One property (the scan object's optional `resourceTypes`) could not be independently
  confirmed to an exact JSON shape and is deliberately omitted rather than guessed - flagged as an
  explicit VERIFY in `README.md` §11 and `design.md` §5, with three new follow-ups recorded below
  rather than resolved by guessing, per `AGENTS.md` §4 - 2026-09-04
- [x] `scenarios/data-estate-insights/sensitivity-label-coverage-report/` - ninth **follow-up
  expansion** fragment (Data Estate Insights), closing the item logged during the
  `classification-coverage-report` build: extend that scenario's exact pattern (paginated Discovery -
  Query, client-side tally, replace-by-`RunId` trend log) to the `label` field on the same
  `SearchResultValue` schema. Full README (12-section skeleton, Public Preview callout up front per
  this repo's established pattern for the upstream "extend sensitivity labels to Data Map" preview
  dependency), design.md (five design goals mirroring the sibling scenario's own, plus a fifth,
  label-specific consideration - labels surfaced through this extension are metadata-only, not
  enforced protection), deploy/ (`Export-SensitivityLabelCoverageReport.ps1` - idempotent/
  parameterized Purview Data Map Discovery - Query REST automation (surface 4, API version
  `2023-09-01`, independently re-confirmed via direct fetch for this build) applying the sibling
  scenario's already-reviewed client-side-tally design to the `label` field/facet instead of
  `classification`; `-Mode Full`/`-Mode Facets`, replace-by-`RunId` trend log, manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf`), validate/ script (identical file-integrity + optional
  live-reconciliation check structure, `label`-specific column names), four-lens reviews.md (Red Team
  Fix round resolved - found and flagged a genuine new risk the sibling scenario didn't have: a
  `0% labeled` reading is ambiguous between "unprotected" and "source type doesn't support Data Map
  labeling at all," closed via README/design additions rather than a guessed validation rule; Blue
  Team Fix round resolved - operability guidance for the same ambiguity, a self-contained incident-
  response runbook, and explicit file-naming non-collision with the sibling scenario; CISO Fix round
  resolved - the review's most consequential finding: sensitivity labels surfaced via this Data Map
  extension are metadata-only per Microsoft's own FAQ (no encryption, no content marking, no DLP), so
  a high `PercentLabeled` must never be presented as "this data is protected" - added as an explicit
  callout in README §2/§11 and design.md §1 before this scenario's output could be handed to a board
  without risk of a false-assurance narrative; Product Owner Fix round resolved - corrected the native
  report's name from `PROGRESS.md`'s own loose paraphrase ("Labeling insights") to Microsoft's actual
  current name, "Classic sensitivity labels" report) - grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (a direct fetch of the Discovery - Query REST reference confirming the `label`
  response field (`string[]`) and the `label` facet as one of exactly four documented facets, and
  confirming no worked exact-value `label` filter example exists (only `classification` does);
  Understand the classic sensitivity labels report in Unified Catalog; Understand the classic assets
  report; Access control in Data Estate Insights within Microsoft Purview; Learn about sensitivity
  labels in Data Map (preview) and its FAQ, including the licensing-tier list and the metadata-only/
  no-encryption/no-DLP confirmations; Understand the Microsoft Purview Data Estate Insights
  application) - one gap (the source-type-support check) recorded as a follow-up rather than resolved
  by guessing, per `AGENTS.md` §4 - 2026-09-04

- [x] `scenarios/insider-risk/irm-case-escalation-to-ediscovery/` - eighth **follow-up expansion**
  fragment (Insider Risk Management / eDiscovery), closing the item logged during the
  `premium-legal-hold-and-export` build: "once `scenarios/insider-risk/` has a scenario producing
  an escalatable IRM case [it now does - `departing-employee-data-theft`], wire the documented
  IRM-case → eDiscovery (Premium) case escalation integration." Full README (12-section skeleton),
  design.md (grounds why the escalation trigger itself has no Graph/PowerShell API - portal-only,
  same shape as several other no-write-API Purview surfaces this library documents - and why the
  `ediscoveryCase` resource's `description` field, its only free-text property, is the correct,
  non-fabricated place to stamp a provenance link back to the source IRM case/alerts, since the
  resource has no source/origin field of any kind), deploy/
  (`Confirm-EdiscoveryEscalationLink.ps1` - idempotent/parameterized Microsoft Graph automation
  (surface 3) that finds the already-escalated eDiscoveryCase by a documented naming convention
  (`IRM-<Case ID>-<UPN local part>`, this repo's own convention, not Microsoft's), best-effort
  resolves declared IRM alert IDs via `Get-MgSecurityAlertV2 -AlertId` for a human-readable
  record, stamps a delimited, idempotent provenance block onto the case description via
  `Update-MgSecurityCaseEdiscoveryCase`, and unconditionally reconciles the flagged user as a
  custodian with a mailbox+OneDrive hold using the identical find-or-create/`applyHold` pattern as
  the sibling `premium-legal-hold-and-export` scenario (duplicated, not dot-sourced, per this
  repo's self-contained-deploy-tree convention); `Remove-EdiscoveryEscalationLink.ps1` - staged
  rollback (strip the provenance block → optionally release the hold, counsel-gated, identical to
  the sibling scenario's own gate) that never closes/deletes the case itself, deferring to the
  sibling scenario's own rollback script for that; a JSON escalation-link definition file), validate/
  (`Test-EdiscoveryEscalationLink.ps1` - read-only PASS/WARN/FAIL checks of case existence,
  provenance-block presence *and* content match against the definition file, custodian/userSource/
  hold state, and best-effort alert resolution), four-lens reviews.md (Red Team Fix round resolved
  - found and fixed a real idempotency gap during review: the initial draft treated "a provenance
  block already exists" as "done," which would have silently left a *different* escalation's
  provenance stamped on a case whose name was accidentally reused; fixed by comparing the existing
  block's IRM case ID/user against the current run before skipping, throwing on a mismatch unless
  a new `-Force` switch is passed, and even then appending rather than overwriting so no prior
  provenance record is ever destroyed; Blue Team Fix round resolved - added an explicit
  escalation-to-automation trigger gap callout (README §8) and severity discipline to the validate
  script's alert-resolution check; CISO Pass; Product Owner Fix round resolved - reworded several
  passages that had implied a stronger native Microsoft linkage than is actually documented) -
  grounded in Microsoft Learn via the Microsoft Learn MCP tool (`insider-risk-management-cases`'s
  full "Escalate for investigation" portal walkthrough and system-generated-note behavior, the
  `ediscovery` legacy-solutions page's IRM-integration summary, the `ediscoveryCase` resource type
  and its Update operation directly fetched to confirm `description` is the only writable
  free-text field and that no source/origin field exists, and `Get-MgSecurityAlertV2`'s PowerShell
  reference directly fetched to confirm the `-AlertId` get-by-ID parameter set before using it) -
  three items recorded as explicit VERIFY rather than resolved by guessing (the IRM "Case ID"
  dashboard field's exact format; whether the portal escalation flow auto-provisions a
  custodian/hold; alert-metadata staleness after re-triage), per `AGENTS.md` §4 - 2026-09-04
- [x] **Investigate `scenarios/ediscovery/legal-hold-notifications/` - closed without building a
  scenario** - seventh **follow-up expansion** fragment (eDiscovery), a correctness correction
  rather than a new scenario. The original follow-up (logged during the
  `premium-legal-hold-and-export` build) assumed the Premium custodian-communication workflow
  (initial notice, reminders, escalations, acknowledgment tracking) was a live, portal-driven-only
  Purview feature with no Graph write API - the same shape as several other no-write-API surfaces
  this library already documents (Communication Compliance, Compliance Manager). Re-grounding for
  this fragment found something different: Microsoft's current, non-legacy-banner "Manage hold
  notifications" page states in an `Important` callout that legal hold custodian communications
  were **permanently retired on August 31, 2025** and aren't available in the new eDiscovery
  experience. The two walkthrough pages this follow-up would otherwise have built a portal runbook
  from ("Create a legal hold notice," "Work with communications in eDiscovery (Premium)") both
  carry the classic-experience/21Vianet-China-only caution banner rather than current guidance - a
  detail easy to miss if only the feature-comparison table on the legacy `ediscovery` overview page
  is checked, since the *current* `edisc-permissions` RBAC page still lists a "Communication" role
  for eDiscovery Manager/Administrator (stale documentation debt, not evidence the feature survived
  - the explicit retirement callout on the more specific, current "Manage hold notifications" page
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
  MCP tool (`ediscovery-manage-hold-notifications`'s retirement callout - the decisive source;
  `ediscovery-create-hold-notification` and `ediscovery-managing-custodian-communications` for the
  now-legacy workflow's own shape, both banner-flagged; the current, non-legacy `edisc` feature-
  comparison table, which has no "legal hold notifications" row at all, corroborating the
  retirement; the current, non-legacy `edisc-permissions` RBAC table, whose still-present
  "Communication" role was deliberately *not* treated as evidence to the contrary). No code written
  - there was nothing left to script once the underlying feature was confirmed retired, and writing
  a scenario anyway would have violated `AGENTS.md` §4's no-fabrication rule by presenting a dead
  feature as current guidance - 2026-09-04
- [x] **Backport: corrected Run Scan / List Scan History REST shapes into
  `scenarios/data-map/scan-azure-sql-and-classify/`** - sixth **follow-up expansion** fragment
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
  only), `README.md` (§6 config-reference row, §11 - replaced the three-way Data
  Sources/Triggers/Run-Scan VERIFY with a RESOLVED entry for the two corrected shapes plus a
  narrower two-item VERIFY for Data Sources/Triggers alone, §12 added reference 17, footer VERIFY
  count corrected from three to two), and `reviews.md` (a targeted four-lens follow-up pass on the
  correction itself - Red Team/Blue Team/CISO/Product Owner all Pass, no Fix/Fail, explicitly
  noting the Blue Team's original review-round mitigation for the *unconfirmed* shape now becomes a
  true error-handler rather than a shape-guess mask). No code executed against a live tenant
  (author-only reference code per `AGENTS.md` §5); both scripts hand-verified line-by-line against
  the sibling scenario's independently-confirmed shapes rather than executed, since `pwsh` is not
  available in this build environment. Two narrower VERIFY items remain open on this scenario (Data
  Sources/Triggers body shapes for the `AzureSqlDatabase` kind; the unrelated custom-scan-rule-set
  and credential-object REST-creation gaps, unchanged) - not resolved by this fragment and not
  claimed to be, per `AGENTS.md` §4 - 2026-09-04
- [x] `scenarios/ediscovery/premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`
  - fifth **follow-up expansion** fragment (eDiscovery), closing the item that scenario's `README.md`
  §8/`reviews.md` (Red Team finding 1) tracked from its original build: no independent audit trail
  for who released a hold or closed/deleted a case. Grounded (Microsoft Learn MCP tool + WebSearch)
  the exact `RecordType`/`Operations` values rather than fabricating them: `RecordType Discovery`
  with two confirmed `Operation` sets from Microsoft's own "Audit log activities" eDiscovery
  reference - case lifecycle (`CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/`CaseRemoved`)
  and hold-**policy** lifecycle (`HoldCreated`/`HoldUpdated`/`HoldRemoved`/
  `HoldRetryDistributionSync`). Added `deploy/Export-EdiscoveryAuditTrail.ps1` (idempotent,
  parameterized Exchange Online PowerShell automation, surface 1 - rolling CSV merge de-duplicated
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
  (three new citations); `design.md` (new §8, plus three new `R9`-`R11` references) and `reviews.md`
  (a follow-up four-lens pass on the addition itself: Red Team/Blue Team/CISO/Product Owner all
  Pass, no Fix/Fail) and `rollback.md` (audit-log-entries note updated to name the new script).
  **One real gap deliberately not resolved by guessing** - whether those hold-policy `Operation`
  values also cover this scenario's own custodian-scoped `applyHold`/`release` calls (a different
  object from the case-level `ediscoveryHoldPolicy` the operations are documented against) is
  unconfirmed for the current, non-legacy eDiscovery experience: the one Microsoft Learn page
  describing per-custodian audit search, and the page claiming custodian holds are internally
  modeled as a "custodian hold policy," both carry a caution banner limiting them to organizations
  hosted by 21Vianet (China) after the classic experience's August 2025 retirement everywhere else
  - recorded as an explicit pilot-tenant VERIFY in this file (above), the script's own `.NOTES`,
  `README.md` §8, and `design.md` §8, per `AGENTS.md` §4 - 2026-09-04
- [x] `scenarios/data-map/scan-azure-sql-managed-instance-and-classify/` - fourth **follow-up
  expansion** fragment (Data Map, Data Governance), closing one of the three sibling-scan-scenario
  items `scan-azure-sql-and-classify/design.md` §7 explicitly scoped out (Azure SQL Managed
  Instance, Azure Synapse Analytics, on-premises SQL Server): full README (12-section skeleton,
  every delta from the sibling scenario's prerequisites/config/architecture called out explicitly
  rather than silently re-derived), design.md (§3 grounds why this is a separate scenario rather
  than a `-SourceKind` flag on the sibling script; §4 is a single source-of-truth diff table; §5
  documents this build's own grounding-quality improvement over the sibling - direct fetches of all
  four canonical REST reference pages succeeded where three of the sibling's four failed at build
  time, surfacing two real, previously-unconfirmed shape corrections), deploy/
  (`New-AzureSqlManagedInstanceDataMapScan.ps1` - idempotent/parameterized Purview Data Map REST
  automation (surface 4) reusing the sibling's create-or-replace pattern for the
  `AzureSqlDatabaseManagedInstance` data source and `AzureSqlDatabaseManagedInstanceMsi`
  SAMI-authenticated scan (distinct `kind` values, a `tcp:<fqdn>,<port>` server-endpoint format, and
  a different system scan-rule-set name from the sibling scenario), optional recurring trigger,
  `-WhatIf` throughout; `Remove-AzureSqlManagedInstanceDataMapScan.ps1` - staged trigger/scan/
  data-source removal mirroring the sibling's rollback shape; `deploy/policy/
  azure-sql-mi-datamap-scan.json` - reference copy of all four REST bodies, each body's `$comment`
  flagging where its shape came from a direct fetch this build performed itself), validate/
  (`Test-AzureSqlManagedInstanceDataMapScan.ps1` - read-only config + scan-history check reading the
  corrected nested asset-count fields), rollback.md (the sibling's three-stage procedure plus a
  fourth, Managed-Instance-specific stage for the tenant-wide Directory Readers role grant, framed as
  a deliberately-manual, Privileged-Role-Administrator-gated step outside this scenario's own
  automation), four-lens reviews.md (Red Team Fix round resolved - the public endpoint's larger
  network exposure than the sibling's firewall toggle made explicit with a private-endpoint
  recommendation, and a Directory Readers membership-drift monitoring gap closed; Blue Team Fix
  round resolved - explained why Directory Readers membership isn't part of the automated validate
  script (a different auth surface than the rest of the script needs) rather than leaving it an
  unexplained gap, and added two Managed-Instance-specific incident-response causes; CISO Fix round
  resolved - the Privileged-Role-Administrator cross-team coordination cost made explicit as a
  distinct adoption-friction dimension from the sibling scenario's own three same-team
  prerequisites; Product Owner Fix round resolved - separated the registration `-Port` parameter
  from the NSG network-path port requirement, citing Microsoft's October 2025 Redirect-becomes-
  default-inside-Azure connection-policy change) - grounded in Microsoft Learn via the Microsoft
  Learn MCP tool (register-scan-azure-sql-managed-instance's full register/scan/prerequisites
  sections including the public-endpoint and Directory-Readers requirements; the Entra
  authentication configuration guide's Managed-Instance-specific admin/Directory-Readers/contained-
  user sections, `CREATE USER ... FROM EXTERNAL PROVIDER` syntax quoted directly; the Azure SQL
  Managed Instance connection-types and connectivity-architecture articles for the October 2025
  Redirect-default change and the Proxy/Redirect NSG port tables; the data-source-readiness-
  checklist article's AzureSQLMI-specific network/RBAC checklist; and - the headline grounding
  improvement over the sibling scenario - direct fetches of all four canonical REST reference pages
  (Data Sources - Create Or Replace, Scans - Create Or Replace, Triggers - Create Or Replace, Scan
  Result - Run Scan / List Scan History) at API version `2023-09-01`, which the sibling scenario's
  own build could not reach for three of the four and had reconstructed from SDK/PowerShell
  signatures instead - two of those reconstructed shapes turned out to not match the confirmed
  contract (Run Scan's action-style POST; List Scan History's nested asset-count fields), corrected
  here and logged as a backport follow-up rather than silently repeated) - two items recorded as
  explicit VERIFY rather than resolved by guessing (the default public-endpoint port; the
  `AzureSqlDatabaseManagedInstanceCredential` credential-object REST creation gap, carried over
  unchanged from the sibling scenario), per `AGENTS.md` §4 - 2026-09-04
- [x] `scenarios/ediscovery/location-scoped-legal-hold/` - third **follow-up expansion** fragment
  (eDiscovery), closing the item `premium-legal-hold-and-export/design.md` §3/§7 explicitly scoped
  out: the `ediscoveryHoldPolicy` (`POST .../legalHolds`) path for a hold organized around a
  *location* (a shared departmental mailbox, a regulatory-sweep distribution list, a SharePoint
  site) rather than a named custodian. Full README (12-section skeleton), design.md (grounds why
  this is a genuinely separate v1.0 object model - narrower `userSource` shape (`mailbox`-only,
  siteSources split out as their own collection, unlike the custodian shape's combined `"mailbox,
  site"` string), the distribution-list-expansion evidence trail (a beta reference documenting
  group-mailbox support + the "Distribution group has too many members" >1,000 error, vs. the v1.0
  endpoint's own narrower "SMTP address of the user" wording), and the headline finding that
  `enablePolicy`/`disablePolicy` exist only in the beta namespace - v1.0 has no reversible
  "turn off and keep for later," only delete-one-source or delete-the-whole-policy, both
  Microsoft-documented as capable of **permanently deleting content currently being preserved**),
  deploy/ (`New-EdiscoveryLocationHold.ps1` - reuses the sibling scenario's typed
  `New-MgSecurityCaseEdiscoveryCase` cmdlet for the case, then `Invoke-MgGraphRequest` against the
  v1.0 REST endpoints directly for the hold policy/userSources/siteSources/retryPolicy, since no
  v1.0 typed cmdlet exists for any of them (only `Microsoft.Graph.Beta.Security` has one); a
  hand-rolled `$PSCmdlet.ShouldProcess()` gate around every write for a true `-WhatIf`; an optional
  `-Retry` that calls `retryPolicy` only when the policy reports errors or an unhealthy source; an
  optional `-WaitForApplied` poll switch (added during Blue Team review to mirror the sibling
  scenario's `-WaitForHold`); a loud `Write-Warning` when `contentQuery` is left blank (added
  during Red Team review - an unfiltered hold on every location's content); `Remove-
  EdiscoveryLocationHold.ps1` - release one or more named userSources/siteSources, or `-DeleteHold`
  for the entire policy, both paths carrying Microsoft's own permanent-deletion warning quoted
  verbatim rather than softened; `deploy/policy/location-hold-definition.json` - a Payments-team
  shared mailbox + compliance distribution list + SharePoint site, `contentQuery` scoped to a CID
  date range), validate/ (`Test-EdiscoveryLocationHold.ps1` - read-only checks of the case, hold
  policy, every declared userSource/siteSource's `holdStatus`, the policy's own `errors`
  collection, and a `WARN` on a blank `contentQuery`), rollback.md (the two-stage release-one/
  delete-all procedure with the counsel-confirmation gate promoted to a `README.md` §3 gating
  prerequisite from the outset, applying the precedent the sibling scenario's own CISO review round
  established), four-lens reviews.md (Red Team Fix round resolved - sharpened the
  distribution-list-expansion VERIFY with a concrete pilot-tenant verification step rather than a
  generic caveat, added the blank-`contentQuery` warning, confirmed the `siteSource`
  title-matching weak point never risks holding the *wrong* site's content, only an idempotency
  false-positive/negative on this scenario's own bookkeeping; Blue Team Fix round resolved - added
  `-WaitForApplied` and the blank-`contentQuery` `WARN`, confirmed `retryPolicy`'s
  restamp-everything behavior was already correctly disclosed as a deliberate, human-triggered
  action; CISO Pass - confirmed the counsel-confirmation gate and the higher-stakes
  no-reversible-pause framing were both already applied proactively in the initial draft; Product
  Owner Pass - independently re-confirmed the beta-only enable/disable finding via direct fetches
  of the v1.0 resource/update references and both beta action pages, and called out the
  `mailbox`-only `userSource` finding as *more* directly grounded than the sibling scenario's own
  open VERIFY on the same property family) - grounded in Microsoft Learn via the Microsoft Learn
  MCP tool (`ediscoveryHoldPolicy` v1.0 resource/create/update/delete/retryPolicy references;
  `userSource`/`siteSource` v1.0 resource + create + delete references for the `legalHolds`
  context specifically, distinct from the custodian-context ones the sibling scenario cites; the
  beta `enablePolicy`/`disablePolicy` action pages confirming no v1.0 equivalent exists; the beta
  custodian-context `userSource` create reference for the group-mailbox-email corroboration; and
  "Manage holds in eDiscovery" for the portal-side hold-policy-states, retry/turn-off/delete
  procedures with their permanent-deletion warnings quoted verbatim, the full "Manage hold status
  errors" table, and the Teams/Microsoft 365 Group hold-placement guidance) - two real gaps
  (distribution-list expansion on the exact v1.0 endpoint; `siteSource` URL-vs-title matching)
  recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md` §4.
  (2026-09-04)
- [x] `scenarios/unified-catalog/manage-data-products/` - second **follow-up expansion** fragment
  (Unified Catalog, Data Governance), closing the shared "Data Products scenario doesn't exist yet"
  dependency both `curate-business-glossary`'s and `data-quality/rules-and-scorecards`'s non-goals
  pointed to: full README (12-section skeleton), design.md (grounds the choice of the newly-added
  2026-03-20-preview `Data Assets` operation group over the raw Data Map/Atlas entity API, and the
  distinction between the REST API's `Policies` operation group - the RBAC authorization-policy
  engine - and the portal's unrelated "data product access policy" feature), deploy/
  (`New-DataProduct.ps1` - idempotent/parameterized Purview Unified Catalog REST automation
  (surface 4) plus a Microsoft Graph owner-resolution call (surface 3, reusing
  `curate-business-glossary`'s UPN→Entra-object-ID pattern) that create-or-updates a "Customer
  Master Data" data product in an existing governance domain, wraps the `scan-azure-sql-and-
  classify`-scanned `customerdb.dbo.Customers` Data Map asset as a Unified Catalog data asset
  (`POST dataAssets` with `source.assetId`, idempotent via the `sourceAssetIds` Query filter), and
  links both that asset and the `Customer`/`Customer ID` glossary terms to the product via `Data
  Products - Create Relationship`, list-before-create idempotent; `-Publish` gate with a loud
  pre-publish warning naming the portal-only data-product-access-policy prerequisite Microsoft's
  own docs require before Publish; `Remove-DataProduct.ps1` - staged unpublish (default) →
  `-RemoveLinks` (delete both relationships, never the shared asset wrapper or terms) →
  `-Purge` (delete the data product; `-DeleteDataAssetWrapper` opt-in and explicitly unchecked
  against orphaning another product's link); `deploy/config/
  customer-master-data-product.sample.json`), validate/ (`Test-DataProduct.ps1` - read-only checks
  of the product's fields/status, the data asset wrapper (reporting its Data-Map-sourced
  classifications as a live cross-check into `scan-azure-sql-and-classify`'s own output), and both
  relationships), four-lens reviews.md (Red Team Fix round resolved - publish-gate-bypass risk
  elevated to a loud warning + README gating prerequisite, orphan-wrapper-deletion risk confirmed
  unfixable in tooling and documented instead, domain-scoped-role risk inherited by reference from
  `curate-business-glossary`; Blue Team Fix round resolved - classification-report and
  access-request-backlog scope boundaries clarified as portal-only, not scripting gaps; CISO Fix
  round resolved - PAYG cost-activation contrast stated locally in §10, access-governance narrative
  sharpened, publish-gate VERIFY promoted to a tracked finding; Product Owner Fix round resolved -
  closed a near-miss conflation of the REST `Policies` group with the portal's access-policy
  feature before it shipped, documented the portal-vs-REST `type` enum label mismatch, independently
  confirmed the newer Data Assets surface and the bulk-import-avoidance reasoning) - grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (Unified Catalog API overview + release notes
  confirming Data Assets/Data Columns as newly added in `2026-03-20-preview`; the Data Products and
  Data Assets REST operation groups directly fetched - Create/Update/Delete/Get/List/Query/Create
  Relationship/List Relationships/Delete Relationship for both, plus Data Assets' `sourceAssetIds`
  Query filter; Create and manage data products, incl. the exact Publish-gating prerequisite
  quote; Manage data product access policies; Master data management in Microsoft Purview's
  five-step register→create→link→curate flow this scenario automates; Data governance roles and
  permissions for Data Product Owner; data governance billing + FAQ for the per-governed-asset PAYG
  trigger; the `Policies - List` operation's own worked example, directly inspected to rule out
  conflating it with the portal's access-policy feature) - the Create Relationship body-shape
  ambiguity and the publish-gate server-side-enforcement question both recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4. (2026-09-04)
- [x] `scenarios/records-management/graph-event-automation/` - first **follow-up expansion** fragment
  (Records Management, Microsoft Graph surface 2/3), the automation complement to the PowerShell
  regulatory-records-disposition scenario: full README (12-section skeleton), design.md, deploy/
  (`New-GraphRetentionEvent.ps1` - `Invoke-MgGraphRequest` against the v1.0 records-management API that
  ensures a retention **event type** exists via GET/POST `/security/triggerTypes/retentionEventTypes`
  (create-or-report by displayName, `@odata.nextLink` paging) and - **double-gated** behind `-FireEvent`
  **and** config `event.fire=true`, always through `$PSCmdlet.ShouldProcess` (real `-WhatIf`) - fires a
  retention **event** via POST `/security/triggers/retentionEvents` (`eventQuery` files/messages +
  AssetID/keywords, `eventTriggerDateTime`, `retentionEventType@odata.bind`), reporting Graph-native
  `eventStatus`/`eventPropagationResults`; `Remove-GraphRetentionEvent.ps1` - deletes matching event
  records and, with `-DeleteEventType`, the event type, with the loud note that deleting an event does
  NOT stop retention already started; `deploy/config/graph-event-automation.sample.json` - Contract
  Expiration event type + asset-ID-scoped event with `fire=false`), validate/
  (`Test-GraphRetentionEvent.ps1` - read-only GET checks of the event type + report of fired events and
  per-workload propagation), four-lens reviews.md (Red Team Fix round resolved - scoped events,
  double-gated + ShouldProcess fire, high-privilege app identity, deletion-isn't-undo; Blue Team Fix
  round resolved - per-workload propagation reporting, nextLink paging, real `-WhatIf`; CISO Fix round
  resolved - auditable automated triggering; Product Owner Fix round resolved - doc quirks
  (`@odata.bind` singular/plural, `eventQuery`/`eventQueries`) flagged) - grounded in Microsoft Learn
  (records-management API overview, create retentionEvent/retentionEventType, eventQuery, permission
  `RecordsManagement.ReadWrite.All`, typed cmdlets `New-MgSecurityTriggerTypeRetentionEventType` /
  `New-MgSecurityTriggerRetentionEvent` verified); uses Microsoft's supported path (REST event API
  deprecated), a fired event is treated as irreversible. (2026-09-04)
- [x] `scenarios/records-management/regulatory-records-disposition/` - seventh Risk & Compliance
  scenario (Records Management), a genuinely distinct records-management lifecycle vs. the DLM sibling:
  full README (12-section skeleton), design.md, deploy/ (`New-RecordsDisposition.ps1` - SCC PowerShell
  (surface 1) that builds the *event-anchored* disposition lifecycle: `New-ComplianceRetentionEventType`
  → `New-ComplianceTag -RetentionType EventAgeInDays -RetentionAction KeepAndDelete -EventType
  -ReviewerEmail -IsRecordLabel` (event-based record label ending in a **disposition review**, not
  auto-delete) → `New-RetentionCompliancePolicy` + `New-RetentionComplianceRule -PublishComplianceTag`
  (**publish**, not auto-apply) → **gated** `New-ComplianceRetentionEvent` created only with
  `-TriggerEvent` **and** config `event.create=true` because a triggered event is irreversible;
  create-or-report idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud
  warnings on the two irreversible edges (triggered event can't be cancelled; applied record label
  can't be deleted) and on un-scoped events / missing reviewer; `Remove-RecordsDisposition.ps1` -
  disable publish policy by default, `-Delete` removes policy/rule and *attempts* (reports, never
  forces via `-ForceDeletion`) label + event-type removal; `deploy/config/records-disposition.sample.json`
  - Contract Expiration event type + event-based record label + publish policy + asset-ID-scoped event
  with `create=false`), validate/ (`Test-RecordsDisposition.ps1` - read-only Get-* checks of event
  type, label action/type/event-binding/record-flag/reviewer, publish policy enabled + locations, rule
  `PublishComplianceTag`, and an informational report of already-triggered events), four-lens reviews.md
  (Red Team Fix round resolved - asset-ID-scoped events, gated irreversible trigger, reviewer-required
  disposition, governed teardown; Blue Team Fix round resolved - event-triggered reporting, separate
  Disposition Management RBAC, working `-DryRun`; CISO Fix round resolved - examiner-grade schedule
  reproducibility; Product Owner Fix round resolved - limits/latency/immutability documented) - grounded
  in Microsoft Learn (event-driven-retention, disposition, New-ComplianceTag/-ComplianceRetentionEventType/
  -ComplianceRetentionEvent with Get/Remove `-Identity` verified, `-PublishComplianceTag`); this
  **completes a starter scenario for every Purview module** - remaining work is the follow-up expansion
  backlog above. (2026-09-04)
- [x] `scenarios/information-barriers/segregate-trading-and-research/` - sixth Risk & Compliance
  scenario (Information Barriers), and the last remaining Risk & Compliance **starter** (every module
  now has a starter scenario): full README (12-section skeleton), design.md, deploy/
  (`New-TradingResearchBarrier.ps1` - SCC PowerShell (surface 1) that builds an ethical wall:
  `New-OrganizationSegment` per side from an Entra attribute filter + two one-way
  `New-InformationBarrierPolicy -SegmentsBlocked` policies created **-State Inactive**, and - only with
  `-Activate` - `Set-InformationBarrierPolicy -State Active` + `Start-InformationBarrierPoliciesApplication`;
  safe-by-default (staged inactive, no user impact until explicit activation); create-or-report
  idempotency via Get-*; custom `-DryRun` (S&C `-WhatIf` non-functional); loud live-communication-impact
  warnings; `Remove-TradingResearchBarrier.ps1` - staged deactivate → `-Apply` to lift the wall →
  `-Delete` policies + segments, with the deactivation-needs-application trap called out;
  `deploy/config/trading-research-barrier.sample.json` - Trading/Research segments + both block pairs),
  validate/ (`Test-TradingResearchBarrier.ps1` - read-only Get-* checks of both segments, both block
  policies + assignment + Active state (`-RequireActive`), and application status), four-lens reviews.md
  (Red Team Fix round resolved - both-direction + mutually-exclusive-segment wall, safe-by-default
  activation + no-collateral test, app-only/non-IB edges, governed deletion; Blue Team Fix round
  resolved - application-status detection + `-RequireActive`, deactivation-needs-apply trap, working
  `-DryRun`; CISO Fix round resolved - examiner-grade reproducibility; Product Owner Fix round resolved
  - IB modes/timings documented) - grounded in Microsoft Learn (Get started with Information Barriers:
  segments/block-policies/apply + one-policy-per-segment + two-one-way-policies pattern, multi-segment
  IB modes and limits, New-OrganizationSegment / New-InformationBarrierPolicy /
  Start-InformationBarrierPoliciesApplication references, IB attributes, SharePoint IB enablement + 24h
  propagation, Teams block behavior, troubleshooting) - no invented cmdlets; activation's
  live-communication impact treated as a first-class safety constraint, per `AGENTS.md` §4 - 2026-09-03

- [x] `scenarios/data-lifecycle-management/retention-labels-financial-records/` - fifth Risk &
  Compliance scenario (Data Lifecycle / Records Management): full README (12-section skeleton),
  design.md, deploy/ (`New-FinancialRecordsRetention.ps1` - SCC PowerShell (surface 1) that creates a
  **regulatory record** retention label (`New-ComplianceTag -Regulatory $true -RetentionAction Keep
  -RetentionDuration 2555 -RetentionType CreationAgeInDays` - SEC 17a-4-style WORM immutability, a
  PowerShell-only capability the portal hides), an **auto-apply** label policy
  (`New-RetentionCompliancePolicy` with finance SharePoint location), and the rule binding them
  (`New-RetentionComplianceRule -ApplyComplianceTag -ContentMatchQuery`); **create-or-report**
  idempotency via Get-* (never silently mutates high-consequence retention objects); custom `-DryRun`
  (S&C `-WhatIf` non-functional); loud irreversibility warnings; `Remove-FinancialRecordsRetention.ps1`
  - staged disable → `-Delete` policy/rule, and `-TryRemoveLabel` that reports the expected refusal for
  a regulatory record in use rather than forcing it; `deploy/config/
  financial-records-retention.sample.json`), validate/ (`Test-FinancialRecordsRetention.ps1` -
  read-only Get-* checks of label action/duration/record flags, policy enabled + locations +
  distribution status, and the rule's applied label), four-lens reviews.md (Red Team Fix round
  resolved - over-scoping guardrails (dry-run, narrow query, lab-test + Records/Legal sign-off),
  least-restrictive-control ladder, create-or-report + no force-release of records; Blue Team Fix round
  resolved - working `-DryRun`, auto-apply latency/RetryDistribution/DistributionStatus, validate
  pre-flight; CISO Fix round resolved - irreversibility as a governance gate; Product Owner Fix round
  resolved - PowerShell-only regulatory records + the retention-strength ladder documented) - grounded
  in Microsoft Learn (New-ComplianceTag / New-RetentionCompliancePolicy / New-RetentionComplianceRule
  references incl. -Regulatory/-IsRecordLabel/-RetentionAction/-RetentionType/-ApplyComplianceTag,
  records-management immutability semantics, auto-apply latency/limits, retention cmdlets overview) -
  a deliberately conservative scenario given regulatory records are irreversible; no invented cmdlets,
  per `AGENTS.md` §4 - 2026-09-03

- [x] `scenarios/audit/premium-audit-investigation/` - fourth Risk & Compliance scenario (Audit
  Premium), a **read-only forensic investigation** built on the **Microsoft Graph Audit Search API**
  (v1.0 `security` namespace, surface 3): full README (12-section skeleton), design.md, deploy/
  (`Invoke-AuditInvestigation.ps1` - an async investigation runner via `Invoke-MgGraphRequest`:
  `POST /security/auditLog/queries` to create the search job from a JSON config (target UPNs, time
  window via `lookbackDays` or explicit ISO dates, a crucial-events `operationFilters` preset,
  optional record-type/keyword/IP filters), polls `GET .../queries/{id}` until a terminal status
  (defensive running-set exclusion + `succeeded`-like check, bounded `-PollTimeoutMinutes`),
  retrieves `GET .../queries/{id}/records` with `@odata.nextLink` paging, and exports CSV (key
  fields) + JSON (full `auditData`) with a top-operations summary; `-WhatIf` previews the query body
  without creating the job; read-only - no tenant mutation; `deploy/config/
  audit-investigation.sample.json` - an account-compromise crucial-events preset (MailItemsAccessed
  [Premium], Send/SendAs, New-/Set-InboxRule, Add-MailboxPermission, FileDownloaded,
  AnonymousLinkCreated, UserLoggedIn/UserLoginFailed, role/user changes)), validate/
  (`Test-AuditInvestigation.ps1` - Graph connectivity + `AuditLogsQuery*` scope + config validation
  + a live 1-hour probe query proving API/permission/audit availability), rollback.md (read-only:
  no tenant state to undo - focuses on securing/disposing the exported evidence and the 30-day
  auto-retained job), four-lens reviews.md (Red Team Fix round resolved - export-as-evidence
  handling, least-privilege service-scoped permissions, read-only/no-tamper posture, ingestion-lag
  false-negative warning; Blue Team Fix round resolved - async polling + paging, triage
  summary/runbook, live readiness probe; CISO Fix round resolved - defensibility/breach-clock
  foregrounded; Product Owner Fix round resolved - Graph async API over classic
  Search-UnifiedAuditLog, status-enum VERIFY) - grounded in Microsoft Learn (auditing solutions
  overview + Standard-vs-Premium capability comparison + service description for crucial events and
  retention tiers, the Audit Search Graph API create/get/list-records references incl. body filters
  and the recordType enum and AuditLogsQuery permission set, audit-search ingestion-latency/job
  limits, and the classic Search-UnifiedAuditLog caps) - the `auditLogQueryStatus` terminal values
  and current crucial-events list recorded as explicit VERIFY items rather than fabricated, per
  `AGENTS.md` §4 - 2026-09-03

- [x] `scenarios/ediscovery/premium-legal-hold-and-export/` - first eDiscovery-module scenario,
  and the first Risk & Compliance scenario in this repo built against a Purview surface with a
  **rich, fully app-only-supported write API** (the opposite grounding challenge from
  `assess-against-iso27001`/`harassment-and-code-of-conduct`, which had none): full README
  (12-section skeleton; a promoted §3 gating prerequisite requiring counsel confirmation before
  any hold release, added during the CISO review round), design.md (grounds the mandatory
  Graph-not-S&C-PowerShell choice across Microsoft's own "app-only auth for eDiscovery cmdlets is
  unsupported" statement, explains the two-separate-API authoring-vs-download architecture, and
  documents the deliberate choice of custodian-scoped `applyHold` over the sibling
  `ediscoveryHoldPolicy` location-scoped hold object), deploy/ (`New-EdiscoveryPremiumLegalHold.ps1`
  - idempotent/parameterized Microsoft Graph automation (surface 3, `microsoft.graph.security`
  v1.0 namespace) that finds-or-creates an eDiscovery (Premium) case, custodians, and their
  mailbox+OneDrive userSources, then applies hold, using every Graph SDK cmdlet's native
  `SupportsShouldProcess` for a true `-WhatIf` dry run rather than a hand-rolled one;
  `New-EdiscoverySearchReviewSetExport.ps1` - finds-or-creates a case-custodian-scoped search,
  commits it to a review set via the asynchronous `addToReviewSet` `caseOperation`, and starts an
  export, polling both long-running operations against the exact v1.0 `caseOperationStatus` enum
  rather than assuming synchronous completion or reusing beta-namespace casing;
  `Get-EdiscoveryExportPackage.ps1` - a parameterized, idempotent (skip-if-already-downloaded)
  adaptation of Microsoft's own published `DownloadExportUsingAppCert.ps1` reference script for
  the *separate*, non-Graph Purview eDiscovery download API and its own `MSAL.PS` token;
  `Remove-EdiscoveryPremiumLegalHold.ps1` - staged rollback (release named custodian(s) → close
  case → delete case, each stage behind its own explicit switch) using the confirmed v1.0
  `ediscoveryCustodian: release` action and `caseStatus` enum; a JSON case/custodian/search/
  reviewSet/export definition file all four scripts share as the single source of truth), validate/
  script (`Test-EdiscoveryPremiumCaseSetup.ps1` - read-only, `eDiscovery.Read.All`-only checks of
  case/custodian/hold-status/userSource/search/review-set state, plus an opt-in export-age check
  against the documented 30-day download window), rollback.md (four explicit stages from
  targeted-custodian release through permanent case deletion, with an up-front warning that
  releasing a hold before the preservation duty lapses can itself be a spoliation event), four-lens
  reviews.md (Red Team Fix round resolved - added an audit-visibility subsection to README.md §8
  naming the gap in per-actor hold-release/case-lifecycle history and pointing to
  `Search-UnifiedAuditLog` as the correct channel rather than fabricating the exact eDiscovery
  audit RecordType/Operations values, and flagged that a custodian's mailbox+OneDrive hold does
  not cover Teams channel messages without an added non-custodial data source; Blue Team
  clarifications - confirmed the weekly validate-script review cadence and the download-step's own
  status check already mitigate the async-timeout risk raised; CISO Fix round resolved - promoted
  the legal-counsel-confirmation-before-hold-release requirement from `rollback.md` alone to a
  gating README §3 prerequisite; Product Owner Pass - independently re-confirmed the
  Graph-not-S&C-PowerShell finding, verified the one cmdlet name inferred by naming-pattern analogy
  (`New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource`) actually exists before citing it, and
  confirmed strict v1.0-vs-beta namespace discipline throughout) - grounded in Microsoft Learn via
  the Microsoft Learn MCP tool (`edisc-hold-create`, `edisc-settings-cases`/`-general`,
  `edisc-permissions` including its app-only-auth-unsupported section,
  `edisc-ref-api-guide`/`security-ediscovery-appauthsetup` for the full two-API app-only setup
  sequence and the published PowerShell download-script examples this repo's
  `Get-EdiscoveryExportPackage.ps1` adapts, `edisc-cases-manage`, `edisc-search-add-to-review-set`,
  `edisc-review-set-export` (including the official-not-just-community-sourced 30-day download-
  window statement), `edisc-hold-report`, `edisc-ref-limits`, `edisc-billing`, `ediscovery`'s
  Standard/Premium capability comparison, and eleven-plus REST/PowerShell reference pages directly
  fetched at v1.0 - `ediscoveryCase`, `ediscoveryCustodian` (including its `applyHold`/`release`/
  `activate` action set), `ediscoveryHoldPolicy`, `ediscoverySearch`, `ediscoveryReviewSet`
  (`addToReviewSet`/`export`), `caseOperation` (confirming the exact `caseOperationStatus` enum
  distinct from beta's casing/shape), and the `New-`/`Get-`/`Add-`/`Export-`/`Update-`/`Remove-`
  `MgSecurityCaseEdiscoveryCase*` PowerShell cmdlet family) - one REST-shape ambiguity (the
  `userSource.includedSources` combined-string form) recorded as an explicit VERIFY rather than
  resolved by guessing, per `AGENTS.md` §4 - 2026-09-04

- [x] `scenarios/communication-compliance/harassment-and-code-of-conduct/` - first Communication
  Compliance-module scenario, and the second scenario in this repo (after
  `scenarios/compliance-manager/assess-against-iso27001/`) built against a Purview surface with
  **no write API** - Microsoft's own docs state "PowerShell isn't supported for creating and
  managing Communication Compliance policies" verbatim on two independently-fetched pages: full
  README (12-section skeleton, an up-front scope note explaining why this scenario's shape differs
  from the DLP/Information Protection scenarios, a promoted gating prerequisite for
  employment-counsel monitoring-notice review), design.md (grounds the no-write-API finding across
  two independently-fetched Microsoft Learn pages plus the legacy `New-SupervisoryReviewPolicyV2`
  cmdlet's continued-but-unsupported presence in the module reference, explains the Investigators-
  vs-Analysts reviewer-role choice, and documents why a custom keyword dictionary was scoped to
  evasion/concealment phrases rather than duplicating classifier-covered profanity/slurs), deploy/
  (a reference-only, explicitly non-executable `communication-compliance-policy-manifest.json` for
  the portal-driven policy-creation runbook - the same pattern `assess-against-iso27001` and
  `departing-employee-data-theft` already established for other no-write-API Purview surfaces -
  plus a genuinely uploadable `code-of-conduct-evasion-phrases.txt` custom keyword dictionary, and
  the one genuinely scriptable piece: `Export-CommunicationComplianceAuditTrail.ps1`, idempotent/
  parameterized Exchange Online PowerShell automation (surface 1) that runs three separate
  `Search-UnifiedAuditLog` queries mirroring Microsoft's own three distinct worked-example
  RecordType/Operations shapes - `SupervisionRuleMatch` alone, `RecordType Discovery` +
  `SupervisionPolicyCreated`/`Updated`/`Deleted`, and `RecordType AeD` + `SupervisoryReviewTag` -
  rather than guessing a single unified query covers all five operation values, merging into a
  rolling CSV de-duplicated by a composite key hashing the full `AuditData` JSON payload;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only queries and
  reports would-be merge counts), validate/ script (`Test-CommunicationComplianceAuditTrail.ps1` -
  automated CSV schema/de-duplication/category/operation/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the policy's existence/scope/classifiers/
  reviewers/anonymization/notice-template/storage-limit health, none of which have a read API
  either), rollback.md (staged pause → revoke access → delete for the portal-only policy, a
  dedicated note on the separate, non-deletable User-reported messages system policy, and the
  audit-trail script's independent schedule/CSV/role rollback), four-lens reviews.md (Red Team Fix
  round resolved - flagged that publishing a real tenant's exact keyword-dictionary contents
  undermines it, distinguished the non-transcribed-Teams-meeting gap from the general off-platform
  limitation, and elevated storage-limit auto-deactivation to an actively-monitored KPI rather than
  a background fact; Blue Team Fix round resolved - added an explicit phased-pilot-before-All-users
  rollout recommendation; CISO Fix round resolved - promoted the monitoring-notice/consent VERIFY
  item from a Known Limitations footnote to a gating README §3 prerequisite; Product Owner Fix round
  resolved - re-confirmed the Harassment/Targeted-harassment naming inconsistency, the correct
  exclusion of preview content-safety classifiers for Exchange coverage, and the correct exclusion of
  custom trainable classifiers, which Communication Compliance doesn't support) - grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (communication-compliance-solution-overview,
  -policies, -plan, -configure, -permissions, -investigate-remediate, -siem, -reports-audits,
  -alerts-best-practices, audit-log-activities' Communication compliance activities table,
  Search-UnifiedAuditLog and New-SupervisoryReviewPolicyV2 reference pages, and the Microsoft
  Purview service description's Communications Compliance licensing table) plus WebSearch grounding
  for the regulatory driver (Title VII/*Faragher*/*Ellerth* case-law framework, and - caught mid-
  build - the EEOC's January 23, 2026 rescission of its 2024 sub-regulatory harassment guidance,
  which changed this scenario's citation from "current EEOC guidance" to "rescinded guidance;
  statute and case law still stand," tagged VERIFY per `AGENTS.md` §4 rather than left stale) -
  2026-09-04

- [x] `scenarios/compliance-manager/assess-against-iso27001/` - first Risk & Compliance-module
  scenario, and the first scenario in this repo built against a Purview surface with **no write
  API**: full README (12-section skeleton, explicit up-front note on why this scenario's shape
  differs from every prior one), design.md (grounds the no-write-API finding across three
  independently-fetched Microsoft Learn articles plus this repo's own `docs/automation-surface.md`
  routing-table gap, explains why a dedicated assessment beats extending the default Data
  Protection Baseline, and documents the built-in-automation evidence-feed mechanism without
  fabricating Microsoft's proprietary per-control mapping), deploy/ (a reference-only, explicitly
  non-executable `iso27001-assessment-manifest.json` for the portal-driven assessment-creation
  runbook - the same pattern `scenarios/insider-risk/departing-employee-data-theft/` already
  established for another no-write-API Purview surface - plus the one genuinely scriptable piece:
  `Export-ComplianceManagerAuditTrail.ps1`, idempotent/parameterized Exchange Online PowerShell
  automation (surface 1) that pulls the exactly three Compliance-Manager-specific operations
  Microsoft's audit log documents (`ComplianceManagerRolesChange`,
  `ComplianceManagerAutomationLevelChange`, `ComplianceManagerAutomationChange`), merging into a
  rolling CSV de-duplicated by a composite key that deliberately avoids assuming an unconfirmed
  flat `ObjectId` output property exists - instead hashing the full `AuditData` JSON payload -
  with a best-effort, non-authoritative `ObjectId` extraction surfaced only as a display column;
  `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` still runs the read-only query and
  reports would-be merge counts), validate/ script (`Test-ComplianceManagerAuditTrail.ps1` -
  automated CSV schema/de-duplication/operation-value/sort-order checks needing no tenant
  connection, plus a manual verification checklist for the assessment's existence/scope/group/role
  assignments, none of which have a read API either), rollback.md (the first in this repo to
  separate a portal-only object's rollback - staged scope-down/access-revocation/deletion, all
  manual - from a scripted artifact's rollback - schedule + role removal - as two independent
  procedures), four-lens reviews.md (Red Team Fix round resolved - flagged that the audit-trail
  script is blind to Compliance Manager access granted implicitly via the Global Administrator/
  Compliance Administrator/Compliance Data Administrator/Security Administrator Entra roles, none
  of which trigger a `ComplianceManagerRolesChange` event, and that the native Reports page's
  6-month history isn't durably preserved by this scenario - both closed with documented
  operational mitigations rather than fabricated code fixes; Blue Team clarifications - confirmed
  the manual-checklist and alert-routing scope boundaries match this repo's own established
  precedent in `departing-employee-data-theft`/`pci-teams-exfil-block`; CISO Pass; Product Owner
  Fix round resolved - independently re-confirmed the no-write-API finding, flagged a VERIFY on
  ISO 27001:2013-vs-2022 template currency, and confirmed Compliance Manager role-name/role-group
  naming accuracy) - grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (`compliance-manager-assessments`, `compliance-manager-update-actions`,
  `compliance-manager-setup`, `compliance-manager-improvement-actions`,
  `compliance-manager-regulations`/`-regulations-list`, `compliance-manager-faq`, the ISO 27001
  regulatory-offering page, `audit-log-activities`'s Compliance Manager activities table,
  `Search-UnifiedAuditLog`'s own reference page plus two independent worked-example pages, and
  `audit-log-retention-policies` for the 180-day/1-year/10-year retention tiers) - three real bugs
  caught and fixed during a post-draft self-review before this fragment was finalized: an
  unconfirmed flat `ObjectId` property assumed on `Search-UnifiedAuditLog` output (replaced with a
  hash-of-`AuditData` composite-key component plus a clearly-labeled best-effort display column), a
  process-randomized `[string]::GetHashCode()`-style hash that would have silently broken
  cross-run de-duplication (replaced with `MD5.ComputeHash`), and a single-object-vs-array paging
  loop that could misbehave when a page returned exactly one record (fixed by wrapping in `@()`
  before checking `.Count`) - 2026-09-03

- [x] `scenarios/data-estate-insights/classification-coverage-report/` - first Data Estate
  Insights-module scenario: full README (12-section skeleton), design.md, deploy/
  (`Export-ClassificationCoverageReport.ps1` - idempotent/parameterized Purview Data Map Discovery
  REST automation (surface 4, API version `2023-09-01`) that reproduces the native "Classic
  classifications" report's headline KPIs - total/classified/unclassified asset counts and a full
  classification-value histogram, per object type - via two modes: `-Mode Full` (paginated,
  `continuationToken`, page size 1000, tallies each record's `classification[]` array client-side
  since no "has any classification" filter is documented) and `-Mode Facets` (a single faceted query,
  cheaper but top-N-truncated and double-counting, mirroring the native "Top classifications" chart's
  own behavior); requires only the **Data Reader** role - deliberately narrower than the native
  report's own Data-Curator-only "Export to CSV" gate; idempotent via replace-by-`-RunId` in a
  trend-log CSV rather than a create/skip check, since this scenario creates no Purview object to
  check existence against; `$PSCmdlet.ShouldProcess()`-gated file writes so `-WhatIf` reports
  computed KPIs without touching disk), validate/ script (`Test-ClassificationCoverageReport.ps1` -
  read-only file-integrity checks (schema, no duplicate RunId+ObjectType rows, per-row arithmetic)
  runnable with no tenant credentials, plus an optional live-reconciliation check against current
  `@search.count`), rollback.md (the first in this repo describing a scenario with **no Purview
  object** to roll back - decommissioning is stopping the schedule, removing the Data Reader role
  assignment, and deciding the fate of already-produced report files), four-lens reviews.md (Red Team
  Fix round resolved - flagged the trend-log/breakdown files themselves as a sensitive artifact
  requiring the same protection as the classifications they summarize, and the `-Mode Facets`
  top-N-truncation as a silent-gap risk; Blue Team Fix round resolved - warning-stream capture
  guidance for unattended runs, and severity-mapping clarity between file-integrity `[FAIL]` and
  live-reconciliation `[WARN]`; CISO Pass; Product Owner Fix round resolved - tightened the
  "Unclassified assets" KPI citation to the specific classic-assets-report page and its exact quoted
  definition) - grounded in Microsoft Learn via the Microsoft Learn MCP tool (the Data Estate
  Insights application overview, classic classifications/assets reports, the Data Estate Insights
  access-control page confirming Data Reader can view but not export while only Data Curator can,
  the "Disable Data Estate Insights" page's weekly-refresh/no-separate-billing notes, the Data
  governance glossary, the data-plane API authentication tutorial, and the Discovery - Query REST
  reference directly fetched at API version `2023-09-01` - request/response shape, `@search.count`
  semantics, `continuationToken` pagination, facets, and worked filter examples including the
  documented `objectType`/`collectionId`/exact-value-`classification` filter shapes) plus a Microsoft
  Q&A thread corroborating (not as primary evidence) that no broader classification-existence filter
  is exposed - one design choice (computing classified/unclassified by client-side pagination rather
  than an invented filter) recorded and justified rather than guessed, per `AGENTS.md` §4; also
  caught and fixed a citation-numbering bug during a post-draft self-review (four `design.md`
  cross-references pointed at the wrong `README.md` reference number) and a scoping bug (an unused,
  fully-redundant `Get-TotalCount` helper function) - 2026-09-03

- [x] `scenarios/data-lineage/end-to-end-lineage-validation/` - first Data Lineage-module
  scenario: full README (12-section skeleton), design.md, deploy/ (`New-CustomLineageRelationship.ps1`
  - idempotent/parameterized Purview Data Map/Atlas v2 REST automation (surface 4, API version
  `2023-09-01`) that creates a `direct_lineage_dataset_dataset` custom lineage relationship (with a
  JSON-encoded `columnMapping` attribute) between two already-scanned `azure_sql_table` assets to
  close a gap left by a non-auto-lineage-integrated custom transform job, existence-checked via
  `Lineage - Get By Unique Attribute` before every `Relationship - Create` POST so idempotency
  doesn't depend on that operation's unconfirmed duplicate-POST behavior; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-CustomLineageRelationship.ps1` -
  looks up each relationship's GUID via the same lineage call and deletes it via the (directly
  confirmed) `Relationship - Delete` operation; a JSON lineage-definition file continuing this
  repo's Customer/customerdb narrative), validate/ script (`Test-EndToEndLineage.ps1` - the
  "end-to-end" half of the scenario's name: walks the full reachable lineage graph from an origin
  asset via a breadth-first traversal of the `Lineage - Get By Unique Attribute` response and
  proves every asset in an independently-declared expected chain is both present *and* connected
  by a walkable path, not merely co-listed; read-only, Data Reader role), rollback.md, four-lens
  reviews.md (Red Team Fix round resolved - documented the Data Curator role's collection-wide
  blast radius, and added an explicit "custom lineage is asserted, not verified" evidentiary-
  honesty note for any compliance narrative built on this graph; Blue Team Fix round resolved -
  sharpened the ambiguous "asset not found" failure mode to name `-MaxDepth` as a possible cause
  alongside a deleted link or stale qualifiedName, and documented the column-mapping check's
  single-hop-from-origin scope assumption as a tracked limitation rather than a silent gap; CISO
  Pass; Product Owner Fix round resolved - clarified that the "classic Data Catalog" citations
  ground lineage *concepts* only, while the REST surface this scenario calls is the current,
  non-deprecated Data Map/Atlas API also read by Unified Catalog's own Lineage tab) - grounded in
  Microsoft Learn via the Microsoft Learn MCP tool (the current, non-legacy "Create and get lineage
  relationships using the REST API" tutorial and its worked Bulk Create/Create Relationship/Get
  Lineage examples; the classic Data Catalog lineage overview/user-guide articles for concepts and
  the auto-lineage-integrated-systems table; the Cloud Adoption Framework's explicit "close gaps
  manually where required" recommendation; the `data-gov-api-custom-types` tutorial confirming the
  `azure_sql_table` type name; the `data-gov-api-rest-data-plane` tutorial confirming Data
  Curator/Data Reader as the Catalog Data plane roles; and four REST operations - Relationship -
  Create, Relationship - Delete, Lineage - Get, Lineage - Get By Unique Attribute - all directly
  fetched from their own canonical REST reference pages at a consistent API version `2023-09-01`,
  a stronger grounding bar than this repo's average scenario) - two items recorded as explicit
  VERIFY rather than resolved by guessing (the exact `azure_sql_table` qualifiedName string format;
  `Relationship - Create`'s duplicate-POST behavior), per `AGENTS.md` §4 - 2026-09-03

- [x] `scenarios/data-quality/rules-and-scorecards/` - first Data Quality-module scenario: full
  README (12-section skeleton, Public Preview callout up front per Product Owner fix), design.md
  (declarative JSON rule definitions, idempotency design independent of Create Rules' unconfirmed
  create-vs-replace semantics, type-agnostic typeProperties pass-through so no rule-type shape is
  fabricated), deploy/ (`New-DataQualityRulesAndSchedule.ps1` - idempotent/parameterized Purview
  Data Quality REST automation (surface 4, API version `2026-01-12-preview`) that reconciles five
  rules (NotNull/Unique/TypeMatch/Duplicate/CustomTruth, deliberately omitting the Azure-SQL-
  unsupported Freshness rule) against an already-governed "Customer" data asset shared with
  `scan-azure-sql-and-classify`/`curate-business-glossary`'s narrative, plus a one-time (`RunOnce`)
  scan schedule; `-RuleStatus Draft`/`-CreateSchedule:$false` review-first path; manual
  `$PSCmdlet.ShouldProcess()` `-WhatIf` throughout; `Remove-DataQualityRulesAndSchedule.ps1` -
  staged schedule-only vs. schedule+rules rollback; a JSON rules definition file), validate/ script
  (rule/status/schedule/score checks with a sharpened ambiguous-failure-mode warning), four-lens
  reviews.md (Red Team Fix round resolved - documented the Data Quality Steward role's domain-wide
  blast radius, a Draft-status "quality theater" drift risk, and the example custom rule's weak
  regex; Blue Team Fix round resolved - made portal alert configuration an explicit go-live gate and
  recommended wiring the validate script into a recurring pipeline check; CISO Fix round resolved -
  funding conditionality made explicit via the Blue Team fix; Product Owner Fix round resolved -
  sharpened Public Preview prominence to the README's opening section) - grounded in Microsoft Learn
  via the Microsoft Learn MCP tool (Data Quality overview/rules/scan/scores/alerts/roles-permissions
  articles, the incremental-scan cost rationale, and the Purview Data Quality REST API's Create
  Rules/Get Rules/Create Schedule/Get Schedule/Get Asset Scores For Asset DQ/Create Data Source/
  Delete Rule/Delete Schedule operations directly fetched at API version `2026-01-12-preview`) - four
  gaps (TypeMatch's target-type field, Create Rules' create-vs-replace semantics, the Schedule
  object's recurring-trigger shape, and the unfetched Alerts operations) recorded as explicit VERIFY
  items rather than resolved by guessing, per `AGENTS.md` §4; also caught and fixed two real bugs
  during a post-draft self-review (a missing `api-version` query parameter on two "list existing
  rules" GET calls that would have 400'd against the live API) - 2026-09-03

- [x] `scenarios/unified-catalog/curate-business-glossary/` - first Unified Catalog-module
  scenario: full README (12-section skeleton), design.md (idempotency design against a
  name-less-unique API, the CSV-bulk-import-can't-update rationale for using REST instead,
  UPN-to-Entra-object-ID owner resolution design), deploy/ (`New-BusinessGlossary.ps1` -
  idempotent/parameterized Unified Catalog REST automation (surface 4) plus a Microsoft Graph
  call (surface 3) to resolve owner/expert UPNs to Entra object IDs; resolves-or-creates a
  governance domain, upserts a small parent/child term hierarchy with acronyms/resources/related-
  term links from a declarative JSON file, `-Publish` gate, manual `$PSCmdlet.ShouldProcess()`
  `-WhatIf` throughout with an explicit `-ReadOnly` bypass for the read-only Query Terms lookup so
  dry-run create-vs-update detection stays accurate; `Remove-BusinessGlossary.ps1` - unpublish
  (reversible, reuses the server's own current fields via GET so it can't clobber a portal-made
  edit) and `-Purge` (permanent delete) rollback; a JSON glossary definition example modeling
  Microsoft's own CAF-recommended Customer/Revenue-style term set), validate/ script (read-only
  content/hierarchy/relationship/publish-status checks), four-lens reviews.md (Red Team Fix round
  resolved - added `User.Read.All` blast-radius compensating controls and stale/departed-owner
  review guidance; Blue Team Fix round resolved - added `systemData` attribution and scheduled-
  validation drift-detection guidance; CISO Pass; Product Owner Fix round resolved - sharpened
  preview-API-surface prominence) - grounded in Microsoft Learn via the Microsoft Learn MCP tool
  (Unified Catalog glossary-terms/governance-domains/roles-permissions/billing/CAF-baseline
  guidance pages, and the Purview Unified Catalog REST API's Terms and Business Domain operation
  groups directly fetched at API version `2026-03-20-preview` - Create/Update/Delete/Get/List/
  Query/AddRelatedEntity/ListRelatedEntities for Terms, Create/Update/Delete/Enumerate for
  Business Domain - plus the Microsoft identity platform client-credentials flow and Graph
  `Get a user`/`User.Read.All` reference for the owner-resolution design) - two REST-schema
  discrepancies recorded as explicit VERIFY items rather than resolved by guessing, per `AGENTS.md`
  §4 - 2026-09-03

- [x] `scenarios/data-map/scan-azure-sql-and-classify/` - first Data Governance-module scenario:
  full README (12-section skeleton), design.md, deploy/ (`New-AzureSqlDataMapScan.ps1` -
  idempotent/parameterized Purview Data Map REST automation (surface 4), registers an
  `AzureSqlDatabase` data source and an `AzureSqlDatabaseMsi` (SAMI-authenticated, credential-free)
  scan against Microsoft's system default scan rule set, with optional recurring trigger and
  `-RunNow`, manual `$PSCmdlet.ShouldProcess()`-wrapped `-WhatIf` throughout since
  `Invoke-RestMethod` has no native ShouldProcess integration; `Remove-AzureSqlDataMapScan.ps1` -
  staged trigger/scan/data-source removal, idempotent on 404; a JSON reference manifest of the
  three REST bodies), validate/ script (read-only config + scan-history check), four-lens
  reviews.md (Red Team Fix round resolved - narrowed the recommended Azure IAM `Reader` scope to
  the SQL Server resource itself instead of resource group/subscription, and flagged the broad
  "Allow Azure services" firewall toggle's tradeoff explicitly; Blue Team Fix round resolved -
  added a four-step incident-response runbook for non-`Succeeded` scan runs and hardened the
  validate script's ambiguous-failure-mode warning; CISO Fix round resolved - added an explicit
  Azure Cost Management budget/alert recommendation given PAYG's uncapped cost-growth model;
  Product Owner Fix round resolved - dropped an unverified custom "PII-only" scan-rule-set default
  in favor of Microsoft's confirmed system default rule set, which already includes the SSN/Credit
  Card Number pair this repo standardizes on) - grounded in Microsoft Learn (Azure SQL Database
  registration/firewall/authentication-options/scan-setup walkthrough and its four supported
  authentication methods' exact T-SQL grants, the Scans - Create Or Replace REST reference
  directly fetched at API version `2023-09-01` with its full `AzureSqlDatabaseMsiScanProperties`
  schema, the Data Map data-plane API-authentication tutorial's service-principal/role-assignment/
  token-acquisition flow, scan run monitoring and 90-day history retention, scan rule set and
  classification-best-practices guidance) plus the `@azure-rest/purview-scanning` JS SDK's type
  definitions and the `Az.Purview` PowerShell module's confirmed cmdlet/parameter surface as
  corroborating (not primary) sources for the three REST operations whose own canonical reference
  pages could not be fetched in this build environment - those three gaps recorded as explicit
  VERIFY items rather than fabricated, per `AGENTS.md` §4 - 2026-09-03

- [x] `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/` - full README (12-section skeleton),
  design.md, deploy/ (`New-CopilotSensitiveDataProtectionPolicy.ps1` - idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule DLP policy on the Microsoft 365 Copilot and
  Copilot Chat location: Rule 0 excludes Confidential/Highly Confidential-labeled content from
  Copilot processing via the `-AdvancedRule`/`-RestrictAccess ExcludeContentProcessing` pattern
  reproduced from Microsoft's own `New-DlpCompliancePolicy` reference Example 4, Rule 1 restricts
  external web-search grounding for SSN/Credit-Card-Number-bearing prompts via `-RestrictWebGrounding`;
  cert app-only, `-WhatIf` throughout; `Remove-CopilotSensitiveDataProtectionPolicy.ps1` -
  disable/purge rollback; a policy JSON reference manifest), validate/ script (automated
  policy/rule/alert-wiring checks), four-lens reviews.md (Red Team Fix round resolved - added an
  explicit VERIFY + follow-up on unconfirmed group-scoped pilot rollout rather than implying it
  works; Blue Team Fix round resolved - added missing `GenerateAlert` checks to the validate
  script; CISO Fix round resolved - added an explicit remediation-ownership note so the DLP policy
  isn't mistakenly reported as "oversharing solved"; Product Owner Pass, with the grounding-strength
  distinction between the two rules recorded) - grounded in Microsoft Learn (DSPM for AI classic
  overview and permissions, the DLP-for-Microsoft-365-Copilot-and-Copilot-Chat location's full
  conditions/actions table and licensing tiers, the exact Copilot location GUID and
  `-AdvancedRule`/`-RestrictAccess`/`-RestrictWebGrounding` PowerShell patterns from
  `New-DlpCompliancePolicy`/`New-DlpComplianceRule`'s own published examples, and DSPM for AI's
  one-click-policy catalog) - deliberately declined to script the preview-only "Processing prompts"
  full-block action for lack of a published PowerShell example (flagged VERIFY/follow-up instead)
  - 2026-09-03

- [x] `scenarios/adaptive-protection/dynamic-risk-dlp-enforcement/` - full README (12-section
  skeleton), design.md, deploy/ (`New-AdaptiveProtectionDlpPolicy.ps1` - idempotent/parameterized
  Security & Compliance PowerShell deploying a two-rule Exchange+Teams DLP policy keyed on the
  `-SharedByIRMUserRisk` condition, Elevated=block/Moderate+Minor=audit, cert app-only, `-WhatIf`
  throughout, mirrors Microsoft's own documented Quick Setup rule values via the custom-setup
  path; `Remove-AdaptiveProtectionDlpPolicy.ps1` - disable/purge rollback; a portal-configuration
  reference manifest for the non-scriptable Adaptive Protection enablement/insider-risk-level
  steps), validate/ script (automated policy/rule/condition checks plus a manual checklist for
  the portal-only pieces), four-lens reviews.md (Red Team Fix round resolved - removed a
  policy-tip wording that would have tipped off a flagged insider mid-investigation, and
  sharpened the Known Limitations section to name the Endpoint-DLP/Conditional-Access/DLM bypass
  gap explicitly rather than as a scoping footnote; Blue Team clarification - manual DLP-to-IRM-
  alert correlation documented in the runbook; CISO Fix round resolved - added a
  feeder-policy-baseline-first recommendation and an HR/Legal-coordination note before broad
  enforcement rollout; Product Owner Fix round resolved - removed an unverified `-ContentIsShared`
  condition in favor of this library's already-grounded `-AccessScope`-only pattern, added
  "(preview)" labels for the Conditional Access/Data Lifecycle Management integrations) -
  grounded in Microsoft Learn (Adaptive Protection overview/configuration/permissions/36-hour
  propagation delay, the documented Quick-Setup DLP rule values for Teams+Exchange this scenario
  reproduces, the Adaptive-Protection-guide's recommended insider-risk-level definitions, and
  independently confirming `New-/Set-DlpComplianceRule -SharedByIRMUserRisk` and its three fixed
  risk-level GUIDs on both cmdlets' own parameter references) - 2026-09-03

- [x] `scenarios/insider-risk/departing-employee-data-theft/` - full README (12-section
  skeleton), design.md, deploy/ (`Send-HrTerminationRecord.ps1` - parameterized/idempotent HR
  resignation-CSV upload via the documented HR-connector ingestion webhook, chunked at the
  500-row limit, SecureString secret handling, `-WhatIf`; `Export-InsiderRiskAlerts.ps1` -
  read-only Graph Security API alert pull with a correctly-grounded client-side
  `detectionSource` filter after discovering `serviceSource` has no IRM enum member; a portal-
  configuration reference manifest, explicitly labeled as non-executable since IRM policy
  authoring has no PowerShell/Graph write API), validate/ script (automated Graph-permission +
  CSV-schema checks plus an explicit manual-verification checklist for the portal-only pieces),
  four-lens reviews.md (Red Team Fix round resolved - 90-day retrospective-lookback boundary and
  HR-connector app-registration scoping/rotation; Blue Team Fix round resolved - alert-export
  dedup/cursor caveat; CISO Fix round resolved - HR-process-dependency visibility gap; Product
  Owner Pass) - grounded in Microsoft Learn (policy templates and triggering-event prerequisites,
  HR connector CSV schema/webhook/auth flow, priority user groups, role groups and Data Connector
  Admin inclusion, Graph security API alert/detectionSource/serviceSource resource definitions,
  SecurityAlert.Read.All permission, insider-risk-to-Defender-portal integration path) plus two
  PowerShell correctness bugs caught and fixed during a syntax self-review (a single-chunk-CSV
  array-unwrapping bug, and a backslash-vs-backtick string-escaping bug) - 2026-09-03


- [x] repo scaffold - AGENTS.md, README, PROGRESS, LICENSE, .gitignore, CONTRIBUTING - 4a79558 - 2026-09-02
- [x] `docs/licensing-matrix.md` - two-model (per-user + PAYG) licensing matrix, grounded in MS Learn - 2026-09-02
- [x] `docs/rbac-model.md` - four-RBAC-system model (Entra, Purview role groups, Data Governance, Exchange Online) + admin units + PowerShell/Graph auth patterns, grounded in MS Learn - 2026-09-03
- [x] `docs/automation-surface.md` - four automation surfaces (EXO/S&C PowerShell, Graph, Data Map REST), module install, app-only auth setup, task-routing table, throttling/CI-CD patterns, grounded in MS Learn - 2026-09-03
- [x] `docs/glossary.md` - canonical A-Z term list spanning all 14 modules (module-tagged, cross-referencing licensing-matrix.md and rbac-model.md), grounded in MS Learn (incl. the official Purview data-governance and Compliance Manager glossaries) - 2026-09-03
- [x] `scenarios/dlp/pci-teams-exfil-block/` - TEMPLATE scenario: full README (12-section skeleton), design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell, cert app-only pattern, -WhatIf throughout), validate script, four-lens reviews.md (Red/Blue Fix rounds resolved; CISO Pass; Product Owner Fix round resolved) - grounded in MS Learn (DLP-for-Teams scoping/licensing, New-/Set-/Remove-DlpCompliancePolicy/Rule reference, Credit Card Number SIT, PCI DSS v4.0.1 Requirement 4.2) - 2026-09-03

- [x] `scenarios/information-protection/auto-label-confidential-sharepoint/` - TEMPLATE-pattern
  scenario: full README (12-section skeleton with a scope note on U.S.-centric SIT coverage),
  design.md, idempotent/parameterized deploy + rollback PowerShell (Security & Compliance
  PowerShell, two rules - one per workload per the `-Workload` cmdlet constraint, cert app-only
  pattern, `-WhatIf` throughout), validate script (explicit config-vs-match-validation caveat),
  four-lens reviews.md (Red Team Fix round resolved - manual-label-first bypass, exclusion-list
  blind spot, and scan-cadence detection gap documented as residual risks; Blue Team Fix round
  resolved; CISO Pass; Product Owner Fix round resolved - added the `EnableSensitivityLabelforPDF`
  prerequisite) - grounded in MS Learn (apply-sensitivity-label-automatically prerequisites and
  override-behavior tables, New-/Set-/Remove-AutoSensitivityLabelPolicy and
  -AutoSensitivityLabelRule reference, DLP policy reference condition-group OR/AND semantics,
  Set-SPOTenant EnableAIPIntegration) - 2026-09-03

- [x] `scenarios/dlp/endpoint-dlp-usb-block/` - full README (12-section skeleton with an
  explicit VERIFY callout on `EndpointDlpRestrictions` Setting/Value strings), design.md,
  idempotent/parameterized deploy + rollback PowerShell (Security & Compliance PowerShell,
  `EndpointDlpLocation`/`EndpointDlpRestrictions`, group-based IT Data Custodians audit-only
  exception mirroring the Card Ops pattern, cert app-only, `-WhatIf` throughout), validate script
  (explicit device-onboarding/policy-sync caveat), four-lens reviews.md (Red/Blue Fix rounds
  resolved; CISO Pass; Product Owner Fix round resolved) - grounded in MS Learn (Endpoint DLP
  licensing/service description, device onboarding overview and permissions, DLP policy reference
  device-restriction action semantics, New-/Set-/Remove-DlpCompliancePolicy/Rule reference,
  reuses the SSN + Credit Card Number SIT pair from `auto-label-confidential-sharepoint`) plus a
  Microsoft Security Blog Tech Community PowerShell walkthrough (not independently fetchable in
  this environment - network egress to techcommunity.microsoft.com blocked - corroborated via two
  independent search-tool summaries and tagged VERIFY for pilot-tenant confirmation) - 2026-09-03
- [x] **`scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/`** - a single
  additive, low-severity, non-blocking `PII-Exchange-Audit-Encrypt-Exception` rule added to
  `exchange-pii-exfil-block`'s existing policy, closing the Red-Team-flagged visibility gap in that
  scenario's `README.md` §11: in Encrypt mode, the nominated business-exception group is silently
  excluded from the encrypt rule with no override concept, so its matching external mail leaves the
  tenant in cleartext with zero alert, incident report, or override record. This companion doesn't
  change that outcome - it makes it visible. Full deliverable per `AGENTS.md` §4: `README.md`
  (12-section skeleton), `design.md` (justifies adding one rule to the parent's existing policy
  rather than a new policy or reopening the parent scenario), `deploy/
  New-ExchangePiiEncryptModeAuditCompanion.ps1` (idempotent, requires the parent policy to already
  exist, computes an explicit non-colliding `-Priority` rather than relying on portal creation-order
  defaults, drift-checks the parent's own exclusion rule, `-WhatIf` throughout),
  `deploy/Remove-ExchangePiiEncryptModeAuditCompanion.ps1`, `validate/
  Test-ExchangePiiEncryptModeAuditCompanion.ps1`, `rollback.md`, `reviews.md` (four-lens; Blue Team
  Fix resolved by adding a `-ReportSeverityLevel` parameter - Low/Medium/High - after the initial
  draft hardcoded `Low`, which risked under-triage for a high-risk exception-group population; Red
  Team, CISO, and Product Owner all Pass). Grounded via `microsoft_docs_search` this run: confirmed
  the "hosted service locations... priority in order created" and "matches for all... rules are
  recorded... even though only the most restrictive rule is applied" behavior directly from the
  official Data Loss Prevention policy reference - new grounding not previously cited by the parent
  scenario, now feeding this fragment's explicit-priority-computation design decision. No new
  cmdlets or parameters beyond what the parent scenario already grounded.
  Commit: `04191a9`. Date: 2026-09-05.
- [x] Removable USB device groups grounding pass (`scenarios/dlp/endpoint-dlp-usb-block/` §11/§12,
  `design.md` §6-7) - **investigated, not built**: confirmed the portal workflow end-to-end
  (create the device group in Endpoint DLP settings by Vendor ID/Product ID/Instance ID, add an
  alias, then reference it as an exclusion in a rule's actions/exceptions) via the official
  `dlp-configure-endpoint-settings` reference and a Microsoft Q&A answer describing the same
  rule-level exclusion step. Found the PowerShell layer more thoroughly undocumented than the
  original backlog item scoped: not just the per-rule reference syntax, but `Set-PolicyConfig
  -DlpRemovableMediaGroups`'s own hashtable shape, and the same for all four sibling device-group
  parameters (`-DlpPrinterGroups`/`-DlpNetworkShareGroups`/`-DlpAppGroups`/`-DlpExtensionGroups`)
  - every one of their descriptions and the cmdlet's entire `EXAMPLES` section are unpublished
  placeholder text in Microsoft's own reference (confirmed by direct fetch of the underlying
  `office-docs-powershell` source, since `learn.microsoft.com` itself is blocked by this
  environment's egress proxy for direct fetches - WebSearch's summarized snippets and GitHub's
  raw-content mirror of the same official docs were used instead). Also confirmed
  `New-DlpComplianceRule`/`Set-DlpComplianceRule` expose no parameter at all for referencing a
  device group as a rule condition/exception. Scripting either half would mean fabricating an
  unconfirmed hashtable shape, which `AGENTS.md` §4 does not permit, so no new scenario folder was
  built - the finding was folded into `endpoint-dlp-usb-block`'s existing docs instead, with three
  new citations (Microsoft's `dlp-configure-endpoint-settings` page, the Microsoft Q&A thread, and
  the `Set-PolicyConfig` reference). Commit: `2783842`. Date: 2026-09-08.
- [x] `scenarios/information-protection/auto-label-eu-personal-data-exchange/` - the Exchange
  (email) companion to `auto-label-eu-personal-data-sharepoint`, combining its EU/UK SIT set and
  `-SensitiveInfoTypeName` localization mechanism with `auto-label-confidential-exchange`'s
  Exchange location/sender-exclusion/encryption mechanics - both inherited unchanged and verified
  directly against their source scripts, not re-derived. Four-lens review surfaced two findings
  specific to running all three (now four, counting the U.S.-SIT SharePoint original) sibling
  policies together: independent SIT-list localization drift between this scenario and its
  SharePoint/OneDrive EU counterpart (no shared config store ties the two scripts' parameters
  together), and a policy-name disambiguation risk during incident response across four
  similarly-named auto-labeling policies - both resolved with README additions (a standing
  review-cadence check; a disambiguation table naming all four policies, locations, and SIT sets)
  rather than new code. Cross-linked back into `auto-label-eu-personal-data-sharepoint/README.md`
  §11 and `design.md` §8. Commit: `943d23f`. Date: 2026-09-08.
- [x] `scenarios/insider-risk/security-policy-violations-by-departing-users/` - full scenario
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
  triggering events enabled and no error, unlike the sibling scenario - added a deployment-time
  checklist item), and one CISO finding (preview status needed a concrete pilot-first rollout
  recommendation, not just a disclosure banner) - all closed with README/validate-script
  additions, no Fail items. One implementation bug caught and fixed before commit: the export
  script's `foreach`/`ForEach-Object` results needed explicit `@()` array-wrapping to avoid
  PowerShell silently unwrapping single-item or empty results to scalars/`$null`, which would have
  broken `.Count` checks and produced a JSON scalar instead of an array on export. Three follow-ups
  and one RBAC cross-reference gap recorded above rather than resolved by guessing (Defender for
  Endpoint Plan 1 vs. Plan 2 sufficiency; whether the `incidentId` join is actually reliable;
  Security Administrator role not yet in `docs/rbac-model.md`; the three sibling "Security policy
  violations…" templates left as separate candidate fragments). Commit: `3d61f9b`. Date: 2026-09-09.
- [x] **Extend `docs/rbac-model.md` with a new §12: Microsoft Defender for Endpoint portal RBAC -
  an eighth system, for scenarios that configure Defender for Endpoint tenant-wide settings** -
  commit `b126d27` - 2026-09-09 - a scoped cross-cutting-doc fragment (not a new scenario),
  closing the follow-up logged during the Security Policy Violations by Departing Users build:
  that scenario's §5 Step 2 requires toggling "Share endpoint alerts with Microsoft Compliance
  Center" on the Microsoft Defender portal's Advanced features page, a Defender-portal RBAC
  surface `docs/rbac-model.md` didn't cover. New §12 documents three grounded access paths: (1)
  basic permissions - Microsoft Entra **Security Administrator** (full access)/**Security Reader**
  (read-only); (2) granular legacy Defender for Endpoint RBAC - the **Manage security settings in
  Security Center** permission, evidenced not by symmetry but by Microsoft's own companion
  procedure for the adjacent Intune-connection toggle on the *same* settings page, which names this
  exact permission as the non-Entra-role alternative to Security Administrator; (3) its Defender
  **unified RBAC (URBAC)** equivalent - **Core security settings (Manage)** (+ **Detection tuning
  (Manage)**) per Microsoft's own legacy-to-unified permission mapping table, mandatory for every
  tenant provisioned on/after February 16, 2025. Also notes the toggle has no documented
  Graph/PowerShell surface (consistent with the parent scenario's own finding) and that this
  role/permission grants no Purview access, the same separation-of-concerns point §9-§11 already
  make for Intune/Conditional Access/app-registration RBAC. Old §12 ("How scenarios should cite
  RBAC") renumbered to §13, with a new point 1 caveat for Defender-for-Endpoint-configuring
  scenarios. Cross-linked back into
  `security-policy-violations-by-departing-users/README.md`'s Prerequisites table and §5 Step 1 in
  place of the "not yet cross-referenced" note. No VERIFY items needed - every fact came from an
  official Microsoft Learn page fetched in full this run (`defender-endpoint/advanced-features`,
  `defender-endpoint/rbac`, `defender-endpoint/user-roles`, `defender-xdr/manage-rbac`,
  `defender-xdr/compare-rbac-roles`, `intune/device-security/microsoft-defender/configure-
  integration`), not inferred or fabricated.
- [x] **`scenarios/dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation/`** - commit
  `8f24b6e` - 2026-09-09 - full scenario (README.md, design.md, deploy/,
  validate/, rollback.md, reviews.md) extending `exchange-pii-exfil-block` with the same
  `-SharedByIRMUserRisk`-based Adaptive Protection compensating control
  `pci-teams-exfil-block-part2-obfuscation-mitigation` already built for the Teams DLP scenario,
  applied here to Exchange. Grounded via Microsoft Learn (fetched in full this run) that Exchange
  Online - unlike Microsoft Teams - is a natively supported "High Severity DLP Alert" indicator
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
  feeder trigger entirely - traced to the exact rule wiring, documented in `README.md` §11 with a
  concrete buyer-facing mitigation, not silently left for a reviewer to discover. Three VERIFY
  items and one cross-scenario follow-up recorded above rather than resolved by guessing (rule
  priority auto-shift behavior, end-to-end composition validation, and whether the Encrypt-mode
  audit companion should get an opt-in higher severity default).
- [x] **`scenarios/insider-risk/security-policy-violations/`** - full scenario (README.md,
  design.md, deploy/, validate/, rollback.md, reviews.md) deploying Insider Risk Management's base
  **Security policy violations** template - the sibling of `security-policy-violations-by-
  departing-users` with no HR/departure trigger and no priority-user-group requirement; its own
  triggering event is the Defender for Endpoint security-violation alert itself, confirmed directly
  against Microsoft's policy-templates prerequisites table. Corrects this fragment's own
  originating backlog framing ("scores every onboarded user continuously"): Microsoft caps this
  specific template at **1,000** actively-scored users tenant-wide (identical to the
  priority-users sibling's own cap despite requiring no priority-group object; smaller than
  departing-users' 15,000 and risky-users' 7,500) - an all-users scope is infeasible above roughly
  that headcount (`design.md` §3). Ships one new, genuinely scenario-specific capability,
  `deploy/Get-SecurityPolicyViolationsScopeCandidates.ps1` - resolves an operator-chosen Entra
  group's (or groups') transitive user membership via `Get-MgGroupTransitiveMemberAsUser` (the
  `microsoft.graph.user` OData cast, confirmed to require the `ConsistencyLevel: eventual` header
  directly from both the cmdlet and Graph REST references), dedupes across groups, filters to
  enabled accounts, and pre-flight-checks the count against the 1,000-user cap. Reuses the
  departing-users sibling's `Export-SecurityViolationInsiderRiskAlerts.ps1` unmodified rather than
  duplicating it - that script applies no policy-specific filter, so it already works against this
  scenario's own alerts (`AGENTS.md`'s no-unneeded-abstraction guidance). Four-lens review raised
  and resolved one substantive finding, independently flagged by both Red Team and Blue Team:
  whether an IRM policy's scope tracks a directly-added group's live membership isn't documented by
  Microsoft either way, so a newly added privileged-group member could sit unmonitored under a
  calendar-only review cadence - `README.md` §8 now ties re-scoping to the group-membership-change
  event itself (quarterly review demoted to a backstop), and both `README.md` §11 and `design.md`
  §6 state the underlying VERIFY explicitly rather than assuming either behavior. One
  implementation bug caught and fixed before commit: `SourceGroupIds += $gid` against a
  `List[string]` (no `+` operator defined for that type) corrected to `.Add($gid)`. Two follow-up
  fragments recorded above (`…-by-priority-users/`, `…-by-risky-users/`) rather than bundled into
  this one, per `AGENTS.md` §6's one-fragment-per-turn discipline, plus one general (not
  scenario-specific) VERIFY on group-scope live-sync behavior. Commit: `f23a07a`. Date: 2026-09-09.
- [x] `scenarios/insider-risk/security-policy-violations-by-priority-users/` - priority-users
  variant of the Security Policy Violations template family, scored against a formal **priority
  user group** (up to 10,000 members; portal-only, CSV-bulk-upload-capable, no Graph/PowerShell
  write API) instead of the base template's plain Entra group. New `deploy/
  Get-PriorityUserGroupScopeCandidates.ps1` resolves an Entra group into an upload-ready
  `user principal name` CSV and sizes it against both the group's 10,000-member cap and the
  template's 1,000-actively-scored cap (cumulative with the base template) independently - the
  interaction between the two is undocumented by Microsoft and left as an explicit, unresolved
  VERIFY (`design.md` §3) rather than guessed at, directly answering this item's own originating
  question. Alert export reused unmodified from the departing-users sibling. Four-lens review
  caught and fixed two issues: an overclaim in README §5 (asserted the priority group is the
  *only* accepted policy scope input - softened to VERIFY, no worked example found either way,
  independently flagged by both Blue Team and Microsoft Product Owner) and a Red Team disclosure
  gap (candidates with no Graph `mail` attribute - plausible guest/service accounts - flagged
  `[WARN]` by the script with no guidance on not silently dropping them from the priority
  population; added explicit README §11 guidance). Grounding note: this cloud environment's
  network access could not reach learn.microsoft.com directly (egress-proxy-blocked, confirmed via
  `/root/.ccr/README.md` diagnostics) - all product facts were grounded via WebSearch against the
  same official Microsoft Learn URLs, corroborated by more than one independent source for facts
  needing a verbatim quote (the CSV column header, the 10,000-member cap), rather than a direct
  page fetch; disclosed in `README.md`'s closing reference note rather than presented as
  first-party-verified. Commit: `e167f52`. Date: 2026-09-09.
- [x] `scenarios/unified-catalog/manage-critical-data-elements/` - **Manage a Critical Data
  Element scenario** - scripts the Critical Data Elements operation group Microsoft's
  `2026-03-20-preview` Unified Catalog API introduced: idempotent create/update of a critical data
  element, resolution and mapping of Data Map columns to it, and observation (never creation) of
  Microsoft's automatically-computed "associated data products" rollup as a live cross-check
  against `manage-data-products`. First scenario in this repo to bridge the Unified Catalog API
  and the Data Map/Atlas Entity API for the same object graph - `Resolve-DataMapColumnId` derives
  a column's own Data Map GUID from its parent table's GUID plus its display name (`GET
  .../datamap/api/atlas/v2/entity/guid/{tableGuid}`, matching
  `relationshipAttributes.columns[].displayText`), grounded directly against Microsoft's own
  `azure_sql_table` type-definition tutorial (its `columns` relationshipAttributeDefs entry) -
  not assumed from a generic Atlas pattern. Fully grounded via the Microsoft Learn MCP tool
  (`microsoft_docs_search`/`microsoft_docs_fetch`, available and used directly this run, contrary
  to this task's stored instructions that it would be unavailable): Critical Data Elements
  Count/Create/Create Relationship/Delete/Delete Relationship/Get/Get Facets/List/List
  Relationships/Query/Update and Data Columns Add Related Entity/Delete Related/Get/Ingest/List
  Related Entities/Query operation groups all directly fetched, plus the `unified-catalog-critical-
  data-elements` concept page, the billing FAQ's data-product/CDE governed-asset dedup answer, and
  the Data Map/Atlas Entity - Get REST reference. One genuine, three-page-consistent Microsoft
  Learn documentation defect found and disclosed rather than silently resolved: every worked
  example for the CDE relationship operations uses `entityType=CRITICALDATACOLUMN`, but the
  formally-documented `EntityCategory` enum on those same pages has no such value and lists
  `DATACOLUMN` instead - this build's scripts send `DATACOLUMN` (the enum-conformant choice) and
  flag the discrepancy as an explicit VERIFY (new follow-up above) rather than guessing silently.
  Four-lens review caught and fixed three findings before finalizing (see `reviews.md`): a
  silent-column-skip false-confidence risk (resolved via a named "run validate after every deploy"
  operational discipline in `README.md` §8, since the deploy script tolerates an unresolved column
  as a non-fatal warning by design), a case-sensitive column-name-matching footgun (documented
  as a named gotcha rather than loosened, to avoid a worse wrong-column-match ambiguity), and the
  domain-scoped-role over-breadth risk already tracked for this repo's other Unified Catalog
  scenarios (inherited by reference into `README.md` §3 rather than re-argued). `docs/
  automation-surface.md` §4 extended with new routing-table rows for the Critical Data Elements/
  Data Columns operation groups and the Data Map Entity-Get column-resolution pattern. Four new
  follow-ups recorded above (a DATACOLUMN/CRITICALDATACOLUMN VERIFY, a deferred related-terms
  companion, a deferred CDE-access-policy REST-surface re-check, and a deferred Get
  Facets/Count-based coverage-reporting companion). Commit: `d7e8860`. Date: 2026-09-09.

- [x] **`scenarios/adaptive-protection/exchange-legacy-auth-block/`** - Exchange-side legacy
  authentication block, the companion to `block-legacy-authentication` deferred from that
  scenario's own `design.md` §7/`reviews.md` (Red Team: Conditional Access is a
  post-first-factor-authentication control; Exchange-side authentication policies act earlier and
  are materially more effective against credential-stuffing/password-spray lockouts). Full README
  (12-section skeleton), design.md, deploy/ (`New-ExchangeLegacyAuthBlock.ps1` - creates a
  fully-blocked baseline `AuthenticationPolicy`, with two separate opt-in live-impact stages,
  `-SetAsOrgDefault` and `-DisableSmtpAuthTenantWide`, since Authentication Policies have no native
  Report-only mode the way Conditional Access does; `Remove-ExchangeLegacyAuthBlock.ps1` for staged
  rollback), validate/ (`Test-ExchangeLegacyAuthBlock.ps1`), rollback.md, reviews.md. Central
  grounding finding: Microsoft has already **permanently** disabled Basic authentication
  tenant-wide, with no re-enable option, for Exchange ActiveSync, POP, IMAP, Remote PowerShell,
  Exchange Web Services, Offline Address Book, Autodiscover, and Outlook for Windows/Mac -
  Authenticated SMTP (SMTP AUTH) is the one protocol Microsoft has deliberately left
  admin-controlled, on an updated deprecation timeline (default-disable for existing tenants
  scheduled end of December 2026, final removal date to be announced 2027 H2 - not yet in effect as
  of this build's date, 2026-09-09), so this scenario's design and KPIs center on SMTP AUTH rather
  than overselling coverage of protocols Microsoft has already closed for free. Also corrects an
  inaccuracy in this item's own original `PROGRESS.md` framing: `-BlockLegacyAuth*` is
  on-premises-only, not usable against Exchange Online - the cloud mechanism is `-AllowBasicAuth*`.
  Found and grounded a second, undocumented-precedence gap: two independent SMTP AUTH gates exist
  (the `AuthenticationPolicy`'s own `AllowBasicAuthSmtp` vs. the separate
  `SmtpClientAuthenticationDisabled` transport setting) with no Microsoft page stating which wins if
  only one is opened - this scenario's exception path closes both together rather than guessing.
  Four-lens review caught and fixed a real script-safety bug before finalizing (see `reviews.md`,
  Red Team finding 1 / Blue Team finding 2): the rollback script's `-Purge` safety check originally
  used an unconfirmed `Get-User -Filter "AuthenticationPolicy -eq '...'"` OPATH expression that
  could silently under-match and fail open; replaced with an unfiltered fetch plus a client-side
  property comparison. `docs/licensing-matrix.md` §4 and `docs/rbac-model.md` §6 both updated with
  a short cross-reference (no incremental license; Organization Management role group, with the
  narrower least-privilege role name left an open VERIFY); `block-legacy-authentication/README.md`
  §11 and `design.md` §7 backported to point at this new companion instead of the old
  "tracked as a follow-up" language. Grounding note: `learn.microsoft.com` and
  `techcommunity.microsoft.com` were not directly fetchable from this build's network environment;
  cmdlet syntax was grounded via direct fetches of the equivalent pages mirrored in the public
  `MicrosoftDocs/office-docs-powershell` GitHub repository, and the SMTP AUTH deprecation timeline
  via WebSearch corroborated across multiple independent secondary sources. Two follow-ups
  recorded above under a new section (`### Follow-ups discovered while building the Exchange-side
  legacy authentication block scenario`) rather than duplicated here. Commit: `a9f29e7`. Date:
  2026-09-10.

- [x] **`scenarios/ediscovery/search-and-purge-data-spillage/`** - closes the long-standing
  follow-up under "Follow-ups discovered while building the Priority Cleanup Exchange
  data-spillage scenario" (deferred there since no eDiscovery search-and-purge scenario existed
  yet to chain onto). Full README (12-section skeleton), design.md, deploy/
  (`New-DataSpillageSearch.ps1` - find-or-create an eDiscovery case + search, run
  `estimateStatistics`, report `indexedItemCount`/`mailboxCount` for review before purging;
  `Invoke-DataSpillagePurge.ps1` - the destructive stage, `-PurgeType Recoverable` (default,
  soft-delete-equivalent) or `PermanentlyDelete` (requires a second, independent
  `-ConfirmPermanentDelete` switch)), validate/ (`Test-DataSpillageSearchAndPurge.ps1`),
  rollback.md, reviews.md. Built entirely on **Microsoft Graph** (`ediscoveryCase`/
  `ediscoverySearch`/`purgeData`, v1.0), not the S&C PowerShell `New-ComplianceSearchAction
  -Purge` path Microsoft's own current docs still show for interactive use - `docs/
  automation-surface.md` §3 already documents (from the `premium-legal-hold-and-export` sibling)
  that app-only auth for eDiscovery S&C PowerShell cmdlets is unsupported by Microsoft, and this
  build confirmed a fully-documented, fully-supported Graph equivalent exists
  (`ediscoverySearch: purgeData`, Application permission `eDiscovery.ReadWrite.All`) rather than
  reopening that unsupported path. Central grounding finding: the classic "Data spillage scenario:
  Search and purge" walkthrough this item's own follow-up note pointed at, and the classic
  Content Search overview page, are **both retired** (2025-08-31, now 21Vianet/China-only) - this
  scenario re-derives the same workflow shape (search → validate → purge → verify) from that
  retired page's *concept* only, grounding every cmdlet/API call in current, non-retired
  references instead (the "Find and delete email messages in eDiscovery" guide, and the Graph
  `ediscoverySearch`/`purgeData`/`estimateStatistics` reference pages). Confirmed a Graph-created
  case is Premium-tier (100 items/mailbox/run, not Standard's 10), and that `purgeData` does
  **not** override a litigation hold (Microsoft's FAQ: held mailboxes only have items hidden from
  view) - closing the gap this scenario's own README §5 step 4 now documents explicitly by
  chaining to the already-built `priority-cleanup-exchange-data-spillage` sibling for held
  content, matching Microsoft's own documented "search-and-purge first, then priority cleanup"
  tip. `docs/rbac-model.md` §4 updated with the granular Compliance Search/Search And Purge role
  detail; `priority-cleanup-exchange-data-spillage/design.md` §7 backported to point at this new
  scenario instead of "candidate follow-up" language. Four-lens review caught and fixed a real
  correctness bug before finalizing (see `reviews.md`, Blue Team finding 3): both deploy scripts
  originally assumed one async-operation `Location` header URL style by analogy with the
  `premium-legal-hold-and-export` sibling's own script, when Microsoft's own published example for
  this action family uses a different (OData-canonical) style - replaced with a shared helper that
  handles both rather than guessing one. Four follow-ups recorded above under a new section
  (`### Follow-ups discovered while building the eDiscovery search-and-purge-data-spillage
  scenario`) rather than duplicated here. Commit: `fe612a9`. Date: 2026-09-10.
- [x] **`scenarios/data-lifecycle-management/publish-labels-for-manual-application/`** - commit
  `e6e7848` - 2026-09-10. Full README/design/deploy/validate/rollback/reviews. Publishes an
  *existing* retention label (`New-RetentionCompliancePolicy` + `New-RetentionComplianceRule
  -PublishComplianceTag`) so admins/users can manually apply it in Outlook/SharePoint/OneDrive/Teams -
  never creates or edits the label itself. Central grounding finding, made while researching this
  fragment: Microsoft's auto-apply retention label policies do **not** support regulatory records at
  all ("This scenario isn't supported for regulatory records... require a published retention label
  policy," corroborated by "Declare records by using retention labels" and the "Will a label be
  overridden?" table in "Learn about retention policies and retention labels" - auto-apply is "Not
  applicable" for regulatory records). This makes the new scenario the *required*, only-supported
  distribution mechanism for a regulatory record label, not merely a nice-to-have complement to
  auto-apply as originally framed in the TODO item. **Backported a correction into the sibling**
  `scenarios/data-lifecycle-management/retention-labels-financial-records/` in the same build (its
  original draft auto-applied a regulatory record label by default - a configuration Microsoft
  doesn't support): that scenario's sample config now defaults to a plain **record** label
  (`regulatory: false`/`isRecordLabel: true`, renamed `Financial Records - 7yr Record`); its deploy
  script still creates a regulatory record label if configured (a valid, standalone
  `New-ComplianceTag -Regulatory $true` call) but now **skips** auto-apply policy/rule creation for
  it with a clear message pointing to this new scenario, instead of silently building an unsupported
  configuration; its validate script skips policy/rule checks for that case; `README.md`, `design.md`,
  and `rollback.md` all corrected in place; `reviews.md` gained a correction addendum (targeted
  lens re-check, not a full new four-lens round, since the object model/safety posture were
  unaffected - only which objects get created for which config). That sibling's `README.md` §3
  automation-surface citation ("surface 1" → surface 2) was also fixed as a low-risk side effect of
  already editing the file - the broader repo-wide "surface N" drift sweep tracked elsewhere in this
  file remains separately open. Four new follow-ups recorded above under
  `### Follow-ups discovered while building the DLM publish-labels-for-manual-application scenario`
  rather than duplicated here. Grounded via the Microsoft Learn MCP tool (available this run, contrary
  to this run's own starting instructions - `microsoft_docs_search`/`microsoft_docs_fetch` used
  throughout, not WebSearch/WebFetch) against `create-apply-retention-labels`,
  `apply-retention-labels-automatically`, `declare-records`, `retention`,
  `new-retentioncompliancerule`, `new-retentioncompliancepolicy`, and `get-retentioncompliancerule`.
  One genuine gap disclosed as VERIFY rather than guessed (see follow-ups): the exact
  `PublishComplianceTag` read-back property name on `Get-RetentionComplianceRule` is not in Microsoft's
  documented default-display property list, though this repo's own established convention (the
  auto-apply sibling's unhedged `ApplyComplianceTag` read) is followed for consistency rather than
  introducing a one-off hedge.
- [x] **`scenarios/data-security-investigations/post-breach-investigation-and-purge/`** - commit
  `6ac858a` - 2026-09-10. First scenario in a new top-level module: **Data Security Investigations**
  (DSI), Microsoft's AI-assisted post-breach/insider-leak investigation and purge workspace. Full
  README/design/deploy/validate/rollback/reviews. Grounded via the Microsoft Learn MCP tool
  (available this run, contrary to this run's own starting instructions -
  `microsoft_docs_search`/`microsoft_docs_fetch` used throughout, not WebSearch/WebFetch, though a
  WebSearch pass confirmed DSI is real/current before committing to the fragment) against the full
  `data-security-investigations-*` documentation set (overview, workflow, get-started, permissions,
  billing, mitigation-actions, scope, ai-analysis, search, application-card), the
  `audit-log-activities#data-security-investigations-activities` table (all 28 `DSI*` Operations,
  reproduced verbatim), and the `dataSecurityInvestigationAuditRecord` Graph resource (confirmed
  read-only - no management methods). Central finding: DSI's investigation/search/AI-analysis/
  mitigation/purge workflow is entirely Microsoft Purview portal-only - no documented write API
  exists (same shape as this library's prior Communication Compliance and IRM case-escalation
  findings) - so rather than inventing one, this fragment scripts the two things that ARE genuinely
  automatable: least-privilege RBAC for the three dedicated DSI role groups
  (`deploy/New-DsiRoleGroupAssignments.ps1`, additive-safe by default, native `-WhatIf`) and a
  rolling `Search-UnifiedAuditLog`-based audit trail (`deploy/Export-DsiActivityAuditTrail.ps1`,
  `-Operations`-only - RecordType unconfirmed, flagged as VERIFY rather than guessed) that flags
  every `DSIPurgeStarted` event, since hard purge is genuinely irreversible. Cross-cutting docs
  updated in the same build: `docs/rbac-model.md` §4 (corrected the pre-existing placeholder DSI row
  with the real, verbatim role-group names and permission matrix) and its Sources list; root
  `README.md`'s module-coverage line; `AGENTS.md` §2's Data Security module list;
  `docs/licensing-matrix.md` §2 (new PAYG-only, not-pausable row) and its Sources list. Five new
  follow-ups recorded above under
  `### Follow-ups discovered while building the Data Security Investigations
  post-breach-investigation-and-purge scenario` rather than duplicated here.
- [x] **DSI audit-trail → audit-streaming SIEM companion feed** - commit `a8a594a` - 2026-09-10.
  Scoped follow-up (not a new scenario) closing the item tracked under `### Follow-ups discovered
  while building the Data Security Investigations post-breach-investigation-and-purge scenario`.
  `scenarios/data-security-investigations/post-breach-investigation-and-purge/deploy/
  Export-DsiActivityAuditTrail.ps1` gained an optional `-NdjsonOutDir` parameter: when supplied, each
  run's already-de-duplicated new records (`$rowsToAdd`) are also written as
  `DSI-Activity-<runStamp>.ndjson` - the identical per-run-file convention
  `scenarios/audit/streaming-to-sentinel-or-management-api/deploy/Invoke-ManagementActivityPoll.ps1`
  already uses for its own Path B `<contentType>-<runStamp>.ndjson` exports - so both scenarios can
  point at one shared `-OutDir`/`-NdjsonOutDir` and one downstream forwarder picks up both feeds with
  no new infrastructure. The label is deliberately hyphenated (`DSI-Activity`, not dot-separated) to
  avoid implying DSI records pass through the Management Activity API (they come from
  `Search-UnifiedAuditLog` directly and are not subject to that API's 24h/7-day window limits) -
  disclosed explicitly rather than left ambiguous. Updated in the same fragment: DSI scenario's
  `README.md` (§4 diagram, §5 script path, §6 config-reference row, §7 validation steps, §8 ops note,
  §11 limitation), `design.md` (§5 key-decisions row, §6 non-goal reworded from "out of scope" to
  "partially built," §4 sequence-diagram note), and `reviews.md` (a mini four-lens addendum - all four
  lenses Pass, no Fix/Fail); the audit-streaming scenario's own `README.md` §8 and a new `design.md`
  §8 cross-link back to it. No product facts needed re-grounding - this is pure repo-internal wiring
  between two already-grounded scenarios, not a new Microsoft capability claim.
- [x] **`scenarios/dlp/accepted-domains-hygiene-check/` - accepted-domains hygiene check** - commit
  ba00f40 - 2026-09-10. Full README/design/deploy/validate/rollback/reviews. Standalone,
  read-only, scheduled compensating control for the accepted-domains trust boundary every
  `FromScope`/`ExceptIfFromScope`-consuming DLP rule in this repo silently depends on - the follow-up
  scoped from `copilot-external-email-block/reviews.md` Red Team finding 1. Cross-references live
  `Get-AcceptedDomain` state against a buyer-curated known-domains config and the previous run's
  baseline, checking both directions of hygiene risk (a reviewed domain silently excluded from trust;
  an unreviewed domain silently granted it) plus a `DomainType`-based trust-boundary model
  (Authoritative/InternalRelay = in-organization, ExternalRelay = not). New grounding this build
  contributes to the repo, not carried over from any sibling scenario: `ExternalRelay` is documented
  as on-premises-Exchange-only (confirmed via direct fetches of `Set-`/`New-AcceptedDomain` reference
  pages), as are `New-`/`Remove-AcceptedDomain` themselves - meaning Exchange Online has no cmdlet to
  add or remove an accepted domain at all, a real, disclosed limit on this scenario's own audit-log
  attribution (`design.md` §5, `README.md` §11). Four-lens review caught and fixed a genuine detection
  gap in the first draft (`MatchSubDomains` drift wasn't checked at all, and a related `elseif`-chain
  bug would have silently dropped simultaneous multi-field changes on the same domain) before this
  fragment was marked done - see `reviews.md` (Red Team finding 1). Cross-linked back into
  `copilot-external-email-block/README.md` §3/§11 and `reviews.md`. Three follow-ups (an `ExternalRelay`
  backport into `copilot-external-email-block/design.md` §4, two audit-log-attribution VERIFYs, and an
  on-premises companion-check idea) added to TODO above rather than resolved by guessing.

- [x] **`scenarios/data-lineage/end-to-end-lineage-validation/validate/Test-EndToEndLineage.ps1` -
  generalize the Check 2 column-mapping check to a multi-hop chain** - commit `a032957` -
  2026-09-11. Scoped follow-up (not a new scenario) closing the item tracked under `### Follow-ups
  discovered while building the Data Lineage end-to-end-lineage-validation scenario`, and formally
  the same limitation this scenario's own `reviews.md` recorded as Blue Team finding 4 (disclosed,
  not fixed, in the original build round). Check 2 previously assumed every `customLineageLinks`
  entry's upstream node was the origin asset (`baseEntityGuid`) - correct only for the shipped
  single-hop example. It now resolves each link's relation edge against its own declared
  `upstreamQualifiedName`: the origin-asset case still resolves directly to the already-known
  `baseEntityGuid` (no behavior change, no new API assumption), and any other upstream node is
  resolved by matching `guidEntityMap` on `qualifiedName` - the identical pattern Check 1 already
  uses for `expectedDownstreamChain` entries, so no new REST assumption was introduced. A clear
  `[FAIL]` + guidance line was added for the new case where the declared upstream node itself isn't
  present in the traversed graph (too-shallow `-MaxDepth` or a stale `upstreamQualifiedName`).
  `design.md` §7's non-goal bullet rewritten to record the generalization instead of the now-closed
  limitation; `reviews.md` gained a correction addendum documenting Blue Team finding 4 as resolved.
  Pure repo-internal logic fix - no new Microsoft product fact needed grounding, so no Microsoft
  Learn/WebSearch citations were added or changed. Authoring an actual multi-hop example definition
  file remains a separate, not-yet-built follow-up (not added back to TODO - no open question left,
  just unbuilt example content, consistent with this repo's treatment of similar "the code supports
  it, nobody's written a second example yet" gaps elsewhere).

- [x] **`scenarios/dspm-for-ai/copilot-external-email-block/design.md` §4 - backport the
  `ExternalRelay`-is-on-premises-only correction** - commit `9b4f1b8` - 2026-09-11. Scoped doc-only
  follow-up (not a new scenario) closing the item tracked under `### Follow-ups discovered while
  building the Accepted-Domains Hygiene Check scenario`. `design.md` §4 previously cited the general
  Exchange 2013 mail-flow-rule predicate definition of "outside the organization" (not-in-an-accepted-
  domain, OR configured as an external relay domain) without noting that the external-relay clause is
  on-premises-Exchange-only - a reader could have concluded `ExternalRelay` was a live concern for the
  pure Exchange Online tenant this scenario targets. Added a corrective paragraph re-grounded against
  Microsoft's `Set-AcceptedDomain` reference (independently re-confirmed via WebSearch this run - the
  Microsoft Learn MCP tool and direct `learn.microsoft.com` fetches were both unavailable/blocked in
  this run's environment - not just carried over from the sibling's citation): a pure-cloud tenant can
  only reach `Authoritative`/`InternalRelay` (both in-organization), so `NotInOrganization` there is
  driven by the "not an accepted domain" clause alone; the external-relay clause only matters for a
  hybrid tenant, whose on-premises domains this scenario's Exchange-Online-only tooling can't see
  regardless. `reviews.md` gained a matching correction addendum. No code changed, so no new four-lens
  review round was run; no Microsoft product behavior changed, only this scenario's own doc accuracy.

- [x] **`scenarios/adaptive-protection/conditional-access-insider-risk-block/deploy/
  New-InsiderRiskConditionalAccessPolicy.ps1` - script the `excludeGuestsOrExternalUsers` nested
  Users condition** - commit `8812fb9` - 2026-09-11. Scoped follow-up (not a new scenario) closing
  the item tracked under `### Follow-ups discovered while building the Conditional Access
  insider-risk-block scenario`. Grounded via the Microsoft Learn MCP tool (available this run,
  contrary to this run's own starting instructions) rather than WebSearch: confirmed
  `conditionalAccessUsers.excludeGuestsOrExternalUsers` → `conditionalAccessGuestsOrExternalUsers`
  → `guestOrExternalUserTypes` (a comma-separated flags String on the wire, seven real enum
  members) / `externalTenants` on the current v1.0, non-beta Graph resource references, and
  independently re-fetched Microsoft's "Block access for users with insider risk" guide, whose
  Users step names the exact three categories to exclude - B2B direct connect users, Service
  provider users, Other external users (`b2bDirectConnectUser`/`serviceProvider`/
  `otherExternalUser`) - reproduced as the new `-ExcludeGuestOrExternalUserTypes` parameter's
  default on both the deploy script and `validate/Test-InsiderRiskConditionalAccessPolicy.ps1`'s
  new matching automated check. `design.md` §6/§7, `README.md` §6/§11/§12 updated in place; a
  second, Round 2 four-lens review recorded in `reviews.md` (2 Red Team findings closed with
  documentation clarifications, no code-behavior change needed; Blue Team/CISO/Product Owner all
  Pass). One genuine gap carried forward rather than resolved by guessing: the exact multi-value
  wire separator (this script assumes a bare comma) and whether the Graph PowerShell SDK's typed
  read-back for this specific nested property returns that same raw string or an already-split
  collection - both flagged as a new VERIFY in TODO above and in the deploy script's `.NOTES`,
  disclosed as affecting only this script's own local idempotency/drift detection, not the
  deployed policy's actual enforcement (Graph itself is the source of truth for how the condition
  evaluates). `rollback.md` and `deploy/Remove-InsiderRiskConditionalAccessPolicy.ps1` needed no
  change (rollback only touches the policy's `state`, untouched by this addition).

- [x] **`docs/rbac-model.md` - cross-reference on-premises Exchange RBAC** - commit `26e236e` -
  2026-09-11. Scoped cross-cutting doc follow-up (not a new scenario) closing the item tracked
  under `### Follow-ups discovered while building the on-premises Accepted-Domains Hygiene Check
  companion`. Added new §13 ("Exchange Server on-premises RBAC - a ninth system, for
  hybrid/on-premises scenarios"), renumbering the old §13 "How scenarios should cite RBAC" to §14
  and updating its own point 1 to add the on-premises model as a citable option alongside
  Intune/Conditional Access/app-registration/Defender-for-Endpoint (§9-§12). Documents the same
  role/role-group/role-assignment-policy/scope vocabulary as Exchange Online's own RBAC (§1 #4)
  but a structurally separate object model - on-premises role groups are Active Directory-backed
  Universal Security Groups scoped to one on-premises organization/forest, so a role group sharing
  a name with its Exchange Online counterpart (`Organization Management`, `Compliance Management`,
  `Recipient Management`, `View-Only Organization Management`) is a distinct security principal on
  each side. Confirms `Organization Management` as the sufficient role group already stated by
  `accepted-domains-hygiene-check-on-premises/README.md` §3, and records three narrower candidates
  (`Compliance Management`, `View-Only Organization Management`, `Recipient Management`) as
  explicit, source-cited **VERIFY** leads rather than asserting any one of them as a confirmed
  least-privilege alternative, since no built-in role group narrower than Organization Management
  was independently confirmed to grant both `Get-AcceptedDomain` read and `Search-AdminAuditLog`
  read together. Grounded via `WebSearch` result summaries citing Microsoft Learn URLs (nine new
  Sources, #27-35) - direct `WebFetch` to `learn.microsoft.com` was blocked again in this run's
  network egress policy (confirmed via `/root/.ccr/README.md`'s diagnostic endpoint, same
  recurring blocker `accepted-domains-hygiene-check-on-premises/design.md` §2/§12 already
  disclosed), and the Microsoft Learn MCP tool was not present in this run's tool list either, so
  every fact is cross-corroborated across multiple independently-worded search queries rather than
  confirmed by a single direct page fetch - flagged explicitly in a new grounding note directly
  above the Sources list. `accepted-domains-hygiene-check-on-premises/README.md` §3/§11 updated in
  place to point at the new §13 instead of stating the gap as still open; its own `reviews.md`
  gained a correction addendum (no new four-lens round - no code changed). Also fixed two
  now-stale `docs/rbac-model.md §13` citations in the parent `accepted-domains-hygiene-check/`
  scenario's own `README.md` §12 and `rollback.md` (both meant the old "how scenarios should cite
  RBAC" section) to point at the new §14 instead, so the renumbering doesn't silently break them.
  Also found and fixed one pre-existing, unrelated `docs/rbac-model.md` citation drift while
  sweeping for renumbering fallout: `scenarios/data-map/scan-azure-sql-and-classify-pii-ruleset/
  README.md` §11 cited §10 for the "how scenarios should cite RBAC" pattern, which was never
  correct even before this build's renumbering (§10 has been "Microsoft Entra Conditional Access"
  since that section was added) - corrected to §14 as a trivial, one-line, low-risk fix rather than
  left in place or scoped out as a separate fragment. This is a distinct, smaller issue from the
  already-tracked `docs/automation-surface.md` "surface N" drift sweep elsewhere in this file (a
  different document, different numbering scheme) - not a claim that sweep covers it.

- [x] **`scenarios/communication-compliance/copilot-interaction-detection/` - Microsoft 365 Copilot
  interaction detection (Prompt Shields/Protected material)** - commit `71e98d0` - 2026-09-11. Full new scenario (README, design, deploy manifest + audit-trail script,
  validate script, rollback, four-lens review), closing the "Detect Microsoft 365 Copilot and
  Microsoft 365 Copilot Chat interactions" half of the follow-up tracked under
  `harassment-and-code-of-conduct`'s own backlog (the preview LLM-based content-safety classifiers
  remain open as a separate follow-up, immediately above). Deploys the built-in policy **template**
  unmodified (not a custom policy like the parent scenario) since the template's fixed
  Prompt-Shields/Protected-material pairing already matches this scenario's target - grounded via
  the Microsoft Learn MCP tool (`microsoft_docs_search`/`microsoft_docs_fetch`, available this run)
  against `communication-compliance-copilot`, `communication-compliance-policies` (policy-template
  table, alert-policy threshold defaults, content-safety-classifier severity scoping),
  `trainable-classifiers-definitions#prompt-shields` (Prompt Shields/Protected material scope and
  language), the Azure AI Content Safety `jailbreak-detection`/`protected-material` concept pages,
  `communication-compliance-reports-audits` (identical `Search-UnifiedAuditLog` 3-query shape as the
  parent scenario), and the Insider Risk Management policy-templates page (Risky AI usage/Risky
  Agents). Reused, not duplicated, the parent scenario's grounded audit-trail-script shape - added a
  client-side `-PolicyNameFilter` (no server-side equivalent exists on `Search-UnifiedAuditLog`) and
  a best-effort, non-blocking `CopilotContext` derived column. Four-lens review round 1 raised and
  closed four Fix items across the lenses: a Copilot-Studio/Microsoft-Foundry agent location-scope
  ambiguity (Red Team; new VERIFY), the default 4-activity/60-minute alert-aggregation threshold
  being the wrong default for a security-sensitive Prompt Shields match (Blue Team; added a
  recommendation to lower it to Microsoft's documented minimum of 3), a missing gating
  triage-SLA prerequisite given that a logged-but-ignored jailbreak alert is a worse legal position
  than no detection at all (CISO), and an undisclosed template-naming inconsistency across two
  Microsoft Learn pages mirroring the parent scenario's own "Harassment"/"Targeted harassment"
  precedent (Product Owner). No Fail items. Genuine gaps carried forward as VERIFY rather than
  resolved by guessing, per `AGENTS.md` §4: the Copilot-Studio/Foundry location-scope question above,
  the exact `AuditData` JSON shape for this specific classifier pairing (the `CopilotContext`
  column's basis), a documented English-vs-eight-language discrepancy between the Purview-specific
  classifier-definitions page and the general Azure AI Content Safety API docs for Prompt Shields,
  and (matching the parent scenario's own EEOC-guidance-currency caution) a jurisdiction-specific
  AI-governance regulatory-citation caveat.

- [x] **Ground the rejected-SMTP-AUTH audit-trail follow-up for
  `scenarios/adaptive-protection/exchange-legacy-auth-block/` - grounded and closed, not built.**
  Follow-up expansion fragment (Data Security / Adaptive Protection), a correctness/precision
  correction rather than a new scenario or script, closing the item logged during the original
  `exchange-legacy-auth-block` build ("once the exact `Search-UnifiedAuditLog`
  `RecordType`/`Operations` values for a rejected SMTP AUTH attempt are grounded, add a dedicated
  `Export-*` companion script"). Investigated both plausible Microsoft-side event sources directly
  against Microsoft Learn rather than guessing a RecordType/Operations pair by analogy to this
  repo's other `Export-*.ps1` audit-trail scripts:
  - `Search-UnifiedAuditLog` - Microsoft's "Audit log activities" Exchange mailbox/admin activity
    tables (<https://learn.microsoft.com/purview/audit-log-activities>) list only successful,
    post-authentication activity (`MailItemsAccessed`, `Send`, `MailboxLogin`, etc.); no
    RecordType/Operation exists for a rejected or blocked authentication attempt of any protocol.
  - Microsoft Entra ID sign-in logs - do record legacy-protocol authentication under a documented
    "Authenticated SMTP" client-app filter (`clientAppUsed: SMTP` in the underlying Microsoft Graph
    `signIn` schema), **but** Microsoft's "Disable Basic authentication in Exchange Online"
    reference states a blocked Basic Auth connection "is blocked at the first pre-authentication
    step ... before the request reaches Microsoft Entra ID" - exactly what this scenario's own
    `AuthenticationPolicy`/`SmtpClientAuthenticationDisabled` gates do. A **rejected** attempt
    therefore never creates a sign-in log entry; the sign-in-log legacy-auth workbook is a
    pre-deployment discovery tool, not a post-deployment rejection audit trail.
  - The Exchange admin center's SMTP AUTH Clients report
    (<https://learn.microsoft.com/exchange/monitoring/mail-flow-reports/mfr-smtp-auth-clients-report>)
    is built from actual message volume/TLS usage per sender - successful submissions only, no
    rejection signal either.

  Conclusion: **no Microsoft-side, scriptable audit trail exists for this event** - a structural
  gap (the gates reject pre-authentication, before any Microsoft logging surface sees the attempt),
  not a documentation gap this repo could close by searching harder. No `Export-*.ps1` was built.
  `reviews.md` (Blue Team finding 1 resolution rewritten + a short follow-up four-lens round, all
  four lenses Pass, no new Fix/Fail - a precision improvement to already-disclosed content, not a
  new capability or risk surface), `README.md` §8 (KPIs - names the real substitute: the
  device/app's own logs, or a synthetic canary probe watching for SMTP `535 5.7.139`), §11 (Known
  limitations - new bullet), and §12 (four new references, [[17]]-[[20]]), and `design.md` §9
  (Residual risk - new bullet) all corrected in place. Grounded via WebSearch/WebFetch against
  learn.microsoft.com (the Microsoft Learn MCP tool was unavailable in this cloud run) - every claim
  above traces to a fetched or searched official Microsoft page, none invented. Re-open the
  original `PROGRESS.md` item only if Microsoft ever documents a RecordType/Operations pair or a
  rejection-specific report for this event. - 2026-09-11
- [x] **`scenarios/records-management/file-plan-bulk-import/`** - commit b17faf9 - 2026-09-15. New
  scenario: the multi-class breadth complement to the sibling `regulatory-records-disposition`
  scenario (one event-based class in depth) - builds a **whole file plan** (many retention-label
  record classes across departments/categories/citations) from one versioned CSV schedule. Ships
  two automation paths reading the same source file: (1) `deploy/New-FilePlanImportCsv.ps1` -
  validates/prepares a file for Purview's own documented file-plan **CSV Import**, which is
  portal-only (no API performs the upload itself - confirmed by direct Learn fetch, not assumed);
  offline by default, `-TenantChecks` adds live LabelName-uniqueness/EventType-exists checks; (2)
  `deploy/New-FilePlanBulkLabels.ps1` - a fully-scripted equivalent with no portal step at all
  (`New-ComplianceTag -FilePlanProperty <json>` + the six `New-FilePlanProperty*` descriptor
  cmdlets, all create-or-report, idempotent), plus `deploy/Remove-FilePlanBulkLabels.ps1` (attempts
  removal per row, never forces, never touches shared descriptor objects). Both mutating paths and
  the validator share one dot-sourced rule engine, `deploy/FilePlanRow.Validate.ps1`, reproducing
  every documented import-property rule (required-ness, valid values, group dependencies, max
  lengths, the `LabelName` character set) plus a hardening addition found during this build's own
  Red Team pass: a CSV/formula-injection guard (rejects any free-text column starting with
  `=`/`+`/`-`/`@` or containing a raw control character) since the documented workflow has a human
  open the generated file in a spreadsheet app before uploading it. `deploy/config/file-plan-
  schedule.sample.csv` ships 10 illustrative record classes spanning HR/Finance/Legal/IT/Sales/
  Compliance (record and non-record labels, Keep/Delete/KeepAndDelete, reviewed and unreviewed
  disposition), deliberately avoiding `Regulatory=TRUE` since that setting has an unverifiable
  tenant-configuration prerequisite. `validate/Test-FilePlanBulkImport.ps1` (schema-only when
  disconnected; tenant reconciliation when connected), `rollback.md`, `reviews.md` (four-lens, all
  Fix items resolved, no Fail). **Grounded via the Microsoft Learn MCP tool directly** (available
  and used this run, unlike several recent runs that recorded it as absent/blocked) - every cmdlet
  and parameter (`New-ComplianceTag`'s full parameter set including `-FilePlanProperty`'s exact
  `PSCustomObject`→JSON shape; all six `New-`/`Get-FilePlanProperty*` cmdlets individually) was
  fetched and confirmed against its own Learn page, not assumed from naming convention. **All five
  scripts were also parse-checked and the validator exercised live** (PowerShell 7.4.6, installed
  temporarily in this session) against both the clean 10-row sample (all pass) and a deliberately
  malformed CSV (correctly produced 15 errors across bad characters, missing group-dependency
  fields, an invalid enum, a duplicate name, and the new formula-injection guard, with no file
  written and a non-zero exit) - not just statically reviewed. Three items carried forward as
  VERIFY rather than guessed (RecordType for label-creation audit events; Get-ComplianceTag's
  file-plan-descriptor read-back property names; the live template's exact column order) - see the
  new TODO section immediately above this entry.
- [x] **`scenarios/data-quality/connection-and-scorecard-alerts/` - product-level `AlertScope`
  companion example** - commit 054e9e7 - 2026-09-15. Sub-task fragment (not a new scenario): closes
  the `PROGRESS.md` follow-up asking for a shipped example of the product-level (not just
  asset-level) alert scope this scenario's `New-DataQualityAlert.ps1` already supported but never
  demonstrated. Adds `deploy/alerts/customer-360-product-score-alert.json` (one alert, only
  `dataProductId`, `dataAssetId` omitted) alongside the existing asset-level
  `customer-master-score-alerts.json`. **No script change needed** - the deploy script's
  scope-construction logic already treats `dataProductId`/`dataAssetId` as independently optional;
  confirmed live in this build (PowerShell 7.4.6, temporarily installed) by simulating the script's
  own scope-building logic against the new file and inspecting the resulting REST body: `scopes[0]`
  contains only a `dataProduct` reference, no `dataAsset` key at all. **Grounded via the Microsoft
  Learn MCP tool directly** (available this run): re-fetched `Update Alert`'s REST reference in
  full - its own worked example still only shows the combined `dataProduct`+`dataAsset` shape, so
  the product-only shape stays flagged as inferred-from-schema-and-corroborated (the `AlertScope`
  schema lists both fields as independently optional; the portal's "Set up data quality alerts"
  conceptual doc describes choosing products and assets as distinct Scope-tab selections), not
  pilot-tenant-confirmed - stated that way in the new file's own header comment rather than
  upgraded to a firm claim now that a file ships it. `README.md` §5/§6/§8/§11, `design.md` (Key
  decisions table), `rollback.md`, both scripts' `.EXAMPLE` blocks, and `reviews.md` (new Round 2,
  four-lens: Blue Team raised one Fix - the product-level alert doesn't identify which asset
  regressed - resolved via a new README §8 scope-choice note and §11 trade-off callout; Red Team,
  CISO, and Product Owner all Pass) all updated. All four scripts in the scenario folder
  parse-checked clean (`[System.Management.Automation.Language.Parser]::ParseFile`, zero errors).
  No new VERIFY items introduced beyond the one already tracked (product-only scope shape).
- [x] **`scenarios/insider-risk/data-leaks/` - propagate the stronger single-select signal into the
  combinability VERIFY** - commit f1c2cbe - 2026-09-16. Sub-task fragment (not a new scenario):
  closes the `PROGRESS.md` follow-up asking to re-check `data-leaks/design.md` §6 and `README.md`
  §11's own "can both triggering events be combined on one policy?" VERIFY against the sibling
  `data-leaks-exfiltration-activity-trigger` scenario's own stronger (but still not conclusive)
  direct Microsoft Learn fetch: the "Get started with Insider Risk Management" Step 6 workflow
  words the two triggering-event options ("User matches a DLP policy" vs. "User performs an
  exfiltration activity") as alternative "if you select X... if you select Y..." branches, not an
  explicit "select either or both" statement. Updated `design.md` §6 (Key decisions table) and
  `README.md` §11 (Known limitations) to cross-link the sibling's finding and drop the now-stale
  "no equivalent explicit statement found" framing, while keeping the question disclosed as an open
  VERIFY rather than resolved either way - Microsoft never publishes an explicit "cannot combine"
  statement. No code changes; `reviews.md`'s existing "open questions surfaced as open, not
  resolved by optimistic assumption" framing already covers this item, so it was left unchanged.
  **Also fixed this run (not the fragment itself, but required before any commit could land):**
  this container's working tree was a detached HEAD sitting 37 commits ahead of the local `main`
  branch ref and `origin/main` - a prior session's completed fragments (data-leaks-by-risky-users,
  data-leaks-by-priority-users, the GDPR/HIPAA/SOC 2/compromised-account-incident-response
  fragments, and more) had been committed but never pushed. Fast-forwarded local `main` to that
  HEAD and pushed all 37 commits plus this fragment's own commit to `origin/main` in one push
  (`382bd89..f1c2cbe`) - a plain fast-forward, no rebase or force needed.
- [x] **`scenarios/ediscovery/gdpr-dsr-fulfillment/`** - commit a144028 - 2026-09-16. New scenario closing the
  DSR-fulfillment gap `gdpr-assessment/README.md` §8/§11 and `reviews.md` Red Team finding 4 had
  disclosed. Adds request-intake, an Article 12(3) SLA ledger (`dsr-ledger.json`, upserted by
  `requestId`), and a custodian-scoped (not tenant-wide) eDiscovery case/search per data subject -
  reusing `premium-legal-hold-and-export`'s already-grounded custodian/userSource cmdlet sequence
  rather than re-deriving one. Access/Portability and Erasure fulfillment are hand-offs to
  `premium-legal-hold-and-export` and `search-and-purge-data-spillage` respectively (their own
  cmdlets, reviews, and known-gaps carry over unchanged); Rectification/Restriction/Objection get a
  tracked Discovery search only - `design.md` §6 grounds why no Purview-native technical control
  exists for any of the three, rather than inventing one. Two grounding traps avoided: confirmed the
  classic "User Data Search" DSR case tool was retired/merged into eDiscovery (Standard) on
  **August 30, 2023** (a year before the broader classic-eDiscovery retirement this repo's other
  eDiscovery siblings already found), and confirmed Microsoft Priva Subject Rights Requests - a
  materially different, purpose-built product surface `docs/automation-surface.md` §4 already lists
  as out of scope for this library - is not this scenario's mechanism either. Four-lens review
  (`reviews.md`) found and resolved two real Fix items: (1) the default custodian-scoped search
  cannot see content *about* the data subject sitting in someone else's mailbox - fixed with an
  opt-in `-IncludeParticipantSearch` tenant-wide participant search, disclosed rather than silently
  left as a completeness gap; (2) a populated request-definition file or the ledger could be
  accidentally committed to source control, permanently exposing a real person's DSR history - fixed
  with new root `.gitignore` patterns (verified via `git add -n` that the sample file stays tracked
  and a populated one would not be). `gdpr-assessment/README.md` §8/§11, `design.md` §7, and its
  manifest's `controlCrosswalk` updated in place to point at this new scenario instead of repeating
  the now-closed gap. **Grounding method note:** the Microsoft Learn MCP tool was unavailable in
  this run's execution environment, and `WebFetch` against `learn.microsoft.com` (and every other
  external domain tested) returned `EGRESS_BLOCKED` from this session's network egress proxy - every
  citation in this fragment was grounded via `WebSearch` result excerpts instead (several
  cross-checked against this repo's own already-fetched sibling-scenario grounding for the same
  cmdlets), disclosed explicitly in `README.md` §12 and `reviews.md`'s Product Owner section rather
  than silently presented as equivalent to a direct-fetch grounding pass. No cmdlet, enum value, or
  blade path was invented.
- [x] **`scenarios/data-map/scan-azure-sql-managed-instance-and-classify-pii-ruleset/`** - commit
  916903f - 2026-09-16. New scenario closing the second of the two remaining Data Map PII-only
  scan-rule-set follow-ups tracked under "Follow-ups discovered while building the Data Map Azure
  Synapse Analytics scenario." Applies the proven live-Types-API exclusion-list pattern (already
  shipped for Azure SQL Database and Azure Synapse Analytics) to Azure SQL Managed Instance. Per
  that follow-up's own instruction, independently direct-fetched
  `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md` (via `raw.githubusercontent.com`
  - `learn.microsoft.com` again returned `EGRESS_BLOCKED` in this build environment, the same
  restriction every recent fragment in this log has hit) rather than assuming either prior sibling's
  name-vs-kind relationship: confirmed the custom ruleset `Kind` is the literal string
  `"AzureSqlDatabaseManagedInstance"` - identical to the System default ruleset's own name (the
  Azure SQL Database sibling's simpler pattern), **not** the Azure Synapse Analytics sibling's
  naming trap (where the System ruleset name and the custom `kind` are two different strings).
  `design.md` §2 goal 6 and `README.md` §11 disclose this as independently confirmed for this
  source type specifically, and explicitly warn against assuming it forward onto the one remaining,
  still-unbuilt sibling (`scan-on-premises-sql-server-and-classify-pii-ruleset`, `kind:
  SqlServerDatabase`) without its own direct-fetch check - that item is re-added to TODO above with
  the same warning repeated. Four-lens review (`reviews.md`) found two real Fix items, both resolved
  without code changes (the deploy/validate scripts already carried both sibling scenarios'
  already-reviewed guards - scan-kind compatibility check, shared-object clobber warning - from the
  first draft): (1) Red Team - the original draft's `design.md` didn't yet state clearly enough that
  this scenario's name-vs-kind finding was independently confirmed rather than pattern-matched,
  risking a future copy-paste mistake onto the unbuilt `SqlServerDatabase` sibling; fixed by making
  the independent-verification framing explicit in `design.md`/`README.md`/`rollback.md`. (2) Blue
  Team - the original Prerequisites table didn't disclaim that this scenario assumes the base
  scenario's own unusually long prerequisite list (public endpoint, Microsoft Entra admin, Directory
  Readers role, NSG rule, `db_datareader` grant) is already satisfied; fixed with an explicit
  disclaimer row and a `design.md` §5 non-goals entry. CISO and Product Owner passed without
  required changes. **Grounding method note:** all citations except the one GitHub raw-source fetch
  above are unchanged, already-confirmed references carried forward from the Azure SQL Database and
  Azure Synapse Analytics sibling scenarios' own builds (both direct-fetched in earlier sessions);
  no cmdlet, enum value, or blade path was invented, and every unconfirmed point is flagged inline
  as VERIFY rather than guessed.
- [x] **`scenarios/data-map/scan-on-premises-sql-server-and-classify-pii-ruleset/`** - commit
  29bbd2e - 2026-09-16. New scenario closing the last of the two remaining Data Map
  PII-only scan-rule-set follow-ups tracked under "Follow-ups discovered while building the Data
  Map PII-only scan rule set (Azure SQL Database) scenario" - the fourth and final Data Map source
  type in this repo to receive a PII-only scan rule set companion scenario. Applies the proven
  live-Types-API exclusion-list pattern (already shipped for Azure SQL Database, Azure Synapse
  Analytics, and Azure SQL Managed Instance) to on-premises SQL Server. Per that follow-up's own
  repeated instruction, independently grounded this source type's ruleset `kind` rather than
  assuming either prior sibling's name-vs-kind pattern - and, unlike the Synapse and Managed
  Instance builds (both of which hit `EGRESS_BLOCKED` against `learn.microsoft.com` and fell back
  to `raw.githubusercontent.com`), this build reached `learn.microsoft.com` directly via the
  Microsoft Learn MCP tool with no egress restriction encountered, so the finding rests on THREE
  converging first-party Microsoft sources instead of one: the
  `New-AzPurviewSqlServerDatabaseScanRulesetObject` PowerShell reference's own worked example
  (`Kind: SqlServerDatabase`), the Scan Rulesets - Get REST API reference's
  `SqlServerDatabaseScanRuleset` object definition, and the `@azure-rest/purview-scanning` JS SDK's
  `SqlServerDatabaseScanRuleset`/`SqlServerDatabaseSystemScanRuleset` TypeScript interfaces - all
  three agree the custom ruleset `Kind` is the literal string `"SqlServerDatabase"`, identical to
  the base scenario's own already-shipped (but itself still `VERIFY`-flagged) `-ScanRulesetName`
  default and to the data source `kind` itself: the Azure SQL Database/Managed Instance siblings'
  simpler name-equals-kind pattern, not the Azure Synapse Analytics sibling's naming trap. This
  build deliberately did not over-claim from that finding: the base scenario's own separate,
  already-open VERIFY on the System default ruleset's literal resource **name** (as opposed to its
  `kind`) remains unresolved - no worked example was found anywhere pairing a literal
  `scanRulesetName: "SqlServerDatabase"` with `scanRulesetType: "System"` in a live scan object -
  and `design.md`/`README.md`/`rollback.md` all state that distinction explicitly rather than
  letting the confirmed `kind` finding imply the adjacent, still-open `name` question was also
  resolved. Four-lens review (`reviews.md`) found real Fix items from two lenses, both resolved
  without deploy/validate script logic changes (the scripts already carried every sibling's
  already-reviewed guards - single-kind scan-compatibility check since no managed-identity variant
  exists for this source type, shared-object clobber warning - from the first draft): (1) Red Team
  - the original draft's `kind`-confirmed / `name`-still-open distinction wasn't stated sharply
  enough to stop a skimming reader (or a future automated re-run) from conflating the two; fixed by
  making the distinction explicit everywhere `-RevertToRulesetName`'s default is discussed, plus a
  new finding specific to this source type: a narrowed classification scope compounds with the
  self-hosted integration runtime's own distinctive silent-failure mode (a SHIR node going
  `Disconnected` produces no new classifications at all, a different and easier-to-miss failure
  than "ran but under-classified"), addressed by having `README.md` §8 correlate ruleset-change
  audit events with SHIR node health explicitly, and by having `validate/Test-PiiOnlyScanRuleset.ps1`
  print an explicit reminder that it cannot check SHIR node health even on a fully-passing run. (2)
  Blue Team - the original Prerequisites table didn't disclaim as sharply as it should have that
  this scenario assumes the base scenario's own unusually long on-premises prerequisite list (SHIR
  resource + software install + node registration, SQL/Windows login + grant, Key Vault secret,
  Purview credential object) is already satisfied; fixed with an explicit disclaimer row and a
  `design.md` §6 non-goals entry. CISO and Product Owner passed without required changes, both
  specifically calling out the stronger-than-usual three-source grounding and this build's
  precision about exactly what it did and did not resolve. **Grounding method note (repo-wide
  relevance):** this build's execution environment had direct, unrestricted `learn.microsoft.com`
  access via the Microsoft Learn MCP tool - the first fragment in several sessions' worth of
  `PROGRESS.md` entries not to hit `EGRESS_BLOCKED`; flagged in `README.md` §11 as informational for
  future runs, including the option to re-verify the Synapse/Managed Instance siblings' own
  GitHub-raw-source-only citations against the full REST reference now that access appears
  restored (not attempted in this build - out of scope for a fragment about a different source
  type). No cmdlet, enum value, or blade path was invented; the one point this build could not
  independently confirm (the System ruleset's literal `name`) is flagged inline as VERIFY, inherited
  unresolved from the base scenario, rather than guessed.
- [x] **`scenarios/data-map/scan-credential-inventory-report/`** - commit 948f529 -
  2026-09-16. New scenario closing the "Consider a small credential inventory/drift report
  companion" follow-up tracked under "Follow-ups discovered while building the Key Vault-backed scan
  credential scenario." Generalizes `scan-credential-key-vault-backed/validate/`'s per-credential
  `-Expected*` assertions into an estate-wide, scheduled, checked-in-file-driven detective control -
  the compensating control that scenario's own `README.md` §11 named as the only mitigation available
  for Purview's undocumented credential-re-point audit gap. Grounded directly against the full
  Credential - List and Credential - Create Or Replace REST reference pages (fetched in full this
  build, not summarized) to build a genuine per-kind fingerprint-extraction table covering all eight
  documented `CredentialType` kinds - including the two structurally distinct ones
  (`AmazonARN`/`ManagedIdentity`) that carry no Key Vault secret reference at all, correctly
  preserved rather than forced through an assumed common shape. Four-lens review surfaced and
  resolved two genuine Red Team findings before this fragment was marked done: (1) the original draft
  gated `-FailOnDrift` on `Drift`/`Missing` status only, silently missing a wholly new, unauthorized
  credential (which only ever shows as `NotTracked`) - resolved with an independent
  `-FailOnUntracked` validate-script switch, not folded into the same flag, since the two answer
  different questions and a tenant with routine legitimate onboarding needs to disable only one; (2)
  the expected-state file's own integrity depends on a source-control review process this scenario
  cannot enforce from code - resolved by documentation (a named prerequisite for a distinct approver
  on changes to that file) rather than a false code-only fix. `scan-credential-key-vault-backed/
  README.md` §8/§11/references updated in place to point at this scenario as its estate-wide
  companion. No cmdlet, endpoint, or field shape was invented; the one open point (whether `nextLink`
  behaves as a directly-callable URL for this specific endpoint - no populated multi-page worked
  example exists in Microsoft's reference) is flagged inline as VERIFY rather than guessed.
- [x] **`scenarios/unified-catalog/manage-okrs/` - progress-trend/staleness-detection companion**
  - commit b59902c - 2026-09-16. Companion fragment (not a new scenario folder) closing the
  "Consider a small scheduled companion script that re-runs `validate/Test-Okr.ps1` on a cadence and
  diffs its output against a prior run" follow-up tracked under "Follow-ups discovered while building
  the Unified Catalog manage-okrs scenario" - picked over three other equally-live candidates
  (the Defender for Endpoint macOS Apple/Portable zero-`serialNumber` baseline-group build, an
  eDiscovery-search-and-purge chaining companion, and an `InboundConnector` connector-risk-audit
  extension) as the most concretely scoped and least VERIFY-shaped of the four, and by this repo's
  own cross-cutting → Data Governance → Data Security → Risk & Compliance backlog-order tiebreaker
  (Data Governance ranks above the other three candidates' Data Security/Risk & Compliance modules).
  Adds `deploy/Export-OkrProgressTrend.ps1` (read-only against Purview - calls only `Okr - Get`/
  `Okr - Get Key Result`, no Graph token needed unlike `New-Okr.ps1`) and
  `validate/Test-OkrProgressTrend.ps1` (file-integrity + `-FailOnStale` gate + optional live
  reconciliation, mirroring `scan-credential-inventory-report/validate/
  Test-CredentialInventoryReport.ps1`'s own two-script shape). Deliberately does **not** implement
  the follow-up's literal wording (re-invoking `Test-Okr.ps1` and text-diffing its console output):
  design.md §8 explains why - an in-process `&` call would be killed by `Test-Okr.ps1`'s own `exit 1`
  on failure before any diff logic ran, and an out-of-process child invocation would require
  serializing the `SecureString` `-ClientSecret` to plaintext on a command line. Instead the new
  script re-derives structured objective/key-result fields itself and diffs those, run-over-run,
  against each entity's own most recent prior row in a local trend-log CSV (not a checked-in
  expected-state file - a deliberately different drift model from `scan-credential-inventory-report`'s
  own, since an OKR's `progress` is *expected* to change over its lifetime; the question is only
  whether anyone has updated it lately). Caught and fixed one genuine correctness bug before it ever
  reached review: mixing Objective rows (no `progress`/`goal`/`max`) and KeyResult rows (all three)
  in one `Export-Csv` call would have silently truncated those three columns from **every** row in
  the file (`Export-Csv` derives its header from the first pipeline object only) - fixed by giving
  every row the identical field set, blank where inapplicable. **Grounded via the Microsoft Learn
  MCP tool directly** (available and used this run): re-confirmed the `Okr - Get`/`Get Key Result`
  operations this companion calls, and searched the "Audit log activities" reference's own
  "Microsoft Purview governance activities" category fresh (new grounding, not carried forward) -
  found no Objective/KeyResult/OKR-specific operation there, corroborating but not conclusively
  proving Round 1's existing "no notification surface" finding, since that audit category describes
  the older, classic Atlas-based entity model rather than the Unified Catalog OKR REST API this
  scenario actually calls; stated with that precision in `README.md` §11/design.md §8 rather than
  upgraded to a flat "confirmed" claim. Four-lens review (`reviews.md` Round 2) found and resolved
  five real Fix items across Red Team (2: trend-log-loss silently resets staleness history with no
  warning, documented in `rollback.md`/`README.md` §11 rather than fixed with an unfounded redundant
  backup; unattended-credential threat model confirmed already covered by the script's own
  least-privilege Graph-free scoping) and Blue Team (3: the CSV-truncation bug above, confirmed
  already fixed at design time and independently re-derived by the review rather than trusted from
  the inline comment alone; a numeric string-format comparison-sensitivity gap added as a new VERIFY;
  the live-reconciliation check's scope confirmed intentional, not a gap) - CISO and Product Owner
  both Pass with no findings. No cmdlet, endpoint, or field shape was invented; the numeric
  string-format VERIFY above is the only new open item this fragment adds.

## Blocked / needs user
- **Positioning note (2026-09-25, not a blocker - informational for future runs):** the repo's
  mission changed from a vendor-sellable product to a free, open community resource (part of
  Krunal Patel's Microsoft MVP-in-Security case). `AGENTS.md` §1 and §10 now reflect this as
  settled, not an open question: **license is MIT** (was proprietary/all-rights-reserved), the
  repo is meant to be **public** (owner needs to flip GitHub visibility manually - no tool in
  this session's toolset changes repo visibility), Priva stays out of scope, code stays
  author-only/no-live-tenant, and there is no vendor packaging. `README.md`, `docs/homepage.html`,
  `CONTRIBUTING.md`, and `LICENSE` were updated to match (MIT text, "your own tenant" instead of
  "the buyer's tenant", free/open framing instead of sales framing). This does **not** change any
  build mechanics - one fragment per turn, four-lens review, grounding discipline, `PROGRESS.md`
  as the resume brain - only the sales-facing wording and the license file. No scenario content
  was touched by this fragment.
- **Git note (2026-09-16, not a blocker - a distinct variant of the 2026-09-09 incident below,
  recorded so the next run recognizes it in seconds instead of misdiagnosing it):** this session
  started on a **detached HEAD** ("HEAD detached from refs/heads/main") while the **local `main`
  branch ref was stale at `18273e0`, 49 commits behind `origin/main`**. Committing work put it on
  the detached HEAD, not on `main` - so `git push origin main` pushed the *stale local `main`
  branch* and was rejected with **"Updates were rejected because a pushed branch tip is behind its
  remote counterpart."** Note this is **not** the usual non-fast-forward "remote has work you don't
  have" message, and it is **not** the 2026-09-09 stale-remote-tracking-ref false alarm either: here
  `origin/main` was genuinely current and correctly fetched, and the new work was a clean descendant
  of it. The wrong *local ref* was being pushed. **Diagnosis in one command:** `git branch -vv` -
  if it shows `* (HEAD detached ...)` plus a `main` marked `[origin/main: behind N]`, this is it.
  **Fix (safe, and what this run did):** verify containment first -
  `git merge-base --is-ancestor <stale-local-main> HEAD` (confirms the stale branch has no unique
  commits to lose) and `git merge-base --is-ancestor origin/main HEAD` (confirms a clean
  fast-forward) - then `git branch -f main HEAD && git checkout main && git push origin main`. No
  force-push, no rebase, no branch/PR detour needed. **Do not** interpret this rejection as
  divergence or as another run having pushed over you; check which ref you are actually on first.
- **Environment note (2026-09-16, second run of the day - PARTIALLY SUPERSEDES the note immediately
  below):** in *this* run's environment the two grounding capabilities came apart, and the
  difference mattered enough to record. `WebFetch` to `learn.microsoft.com` is **still**
  `EGRESS_BLOCKED` (re-tested directly this run). But the **Microsoft Learn MCP tool
  (`mcp__Microsoft_Learn__microsoft_docs_search` / `microsoft_docs_fetch`) WAS available** - it is
  surfaced as a *deferred* tool that must first be loaded with `ToolSearch`
  (`select:mcp__Microsoft_Learn__microsoft_docs_search,...`), which is presumably why earlier runs
  concluded it was "not present in this session's tool list." **Future runs: always try
  `ToolSearch` for the Learn MCP tools before falling back to WebSearch-only grounding.** It works
  even while `WebFetch` is blocked, and it is the difference between a search-snippet citation and
  a verbatim full-page fetch. Concretely, this run used it to direct-fetch the Purview Scanning
  data plane's Credential and Key Vault Connections reference pages in full - which overturned a
  "no documented REST endpoint exists" conclusion that two prior scenarios had shipped and that had
  blocked a backlog item for several builds. Worth a targeted re-verification pass over any
  remaining WebSearch-only citations (notably `scenarios/ediscovery/gdpr-dsr-fulfillment/`) and over
  other "no documented endpoint/API was found" claims elsewhere in this repo, which may be similarly
  wrong rather than merely unconfirmed.
- **Environment note (2026-09-16, not a question needing a user decision - informational for future
  runs of this loop):** in this run's execution environment, `WebFetch` returned `EGRESS_BLOCKED`
  for **every** domain tested (`learn.microsoft.com`, `docs.azure.cn`, `techcommunity.microsoft.com`,
  even `example.com`) - a session-wide network-egress-proxy restriction, not a Microsoft-Learn-
  specific block. The Microsoft Learn MCP tool was also unavailable, matching this loop's own
  instructions. Only `WebSearch` worked. A future run in an environment where `WebFetch` or the
  Microsoft Learn MCP tool *is* available should prefer those for grounding (direct-fetch is
  stronger evidence than a search-result excerpt) and, time permitting, re-verify this run's
  WebSearch-only citations (`scenarios/ediscovery/gdpr-dsr-fulfillment/`) against the full source
  pages. No action needed if this is just how this loop's environment is normally configured.
- **CORRECTED, false alarm (2026-09-09) - retracting an earlier entry from this same run.**
  Earlier in this run, this session found local `origin/main` (a remote-tracking ref last fetched
  before this session started, hash `7b7437e`) shared no common ancestor with the detached `HEAD`
  it was committing to, and wrongly concluded `origin/main` was genuinely ~a day and ~15 scenarios
  behind. Acting on that (incorrect) belief, it avoided pushing to `main`, instead pushed a new
  branch `claude/continue-from-detached-2026-09-09` to `origin`, and opened draft PR #4. **Root
  cause of the false alarm: a stale local remote-tracking ref, never re-fetched during this
  session.** A subsequent `git fetch origin main` showed `origin/main` had *already* been
  force-updated to `904d697` (this session's actual starting commit) by something outside this
  session, before this session began - i.e. `main` was already fully current; there was no
  divergence, no lost day of work, and no lineage split. `git merge-base --is-ancestor 904d697
  origin/main` confirms `904d697` is a real ancestor of the true `origin/main`.
  **Resolution taken:** fast-forward-merged `claude/continue-from-detached-2026-09-09` into a
  freshly-reset local `main` (clean fast-forward, no conflicts) and pushed `main` directly -
  see the commit log. PR #4 was closed (superseded by the direct push) rather than merged, to
  avoid an unnecessary merge commit for what was always a clean fast-forward. The
  `claude/continue-from-detached-2026-09-09` branch can be deleted whenever convenient; it's fully
  contained in `main` now. **Lesson for future runs:** always run `git fetch origin main` (or
  equivalent) before concluding `origin/main` is behind or diverged from local state - do not
  trust an unrefreshed local remote-tracking ref for that judgment, especially at the start of a
  fresh session. A false "repo integrity crisis" costs a wasted branch/PR/notification cycle, as
  this one did; apologies for the noise if you saw the earlier notification before this
  correction landed.
- **Environment note, not a scenario blocker:** as of this run (2026-09-09), this cloud execution
  environment's egress proxy blocks direct WebFetch access to `learn.microsoft.com` (confirmed via
  `/root/.ccr/README.md`'s diagnostic endpoint - "destination host is not allowed by your
  organization's egress policy for this session"), and the Microsoft Learn MCP tool
  (`mcp__Microsoft_Learn__*`) is not present in this session's tool list either. WebSearch still
  works and returns Microsoft Learn URLs plus synthesized snippets, so grounding remained possible
  but weaker than a direct page fetch (no verbatim-quote confirmation without corroboration from
  more than one independent secondary source). If a future run has either capability restored,
  prefer it over WebSearch-only grounding, and consider re-verifying this run's WebSearch-grounded
  facts (flagged inline in the fragment above and its own `README.md` §11/closing note) against a
  direct fetch.
