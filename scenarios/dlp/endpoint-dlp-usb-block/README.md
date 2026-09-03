# DLP — Endpoint DLP: Block USB Removable Media Exfiltration

## 1. Scenario summary

Blocks copying of files containing U.S. Social Security Numbers or credit card numbers from
onboarded Windows/macOS endpoints to USB removable storage, using Microsoft Purview Endpoint Data
Loss Prevention (Endpoint DLP). A named exception path (audit-only, not blocked) is carved out for
the IT Data Custodians group, who perform legitimate offline backup/imaging work that a hard block
would otherwise break. This is the same classify-then-control pattern as
`scenarios/information-protection/auto-label-confidential-sharepoint/`, extended from "label it
Confidential" to "stop it leaving via USB" using the same sensitive-content definition.

**Who it's for:** any organization with Windows or macOS laptops/desktops in scope for data-loss
prevention that needs a real-time, content-aware control against regulated data being copied to a
USB flash drive or external disk — a channel that email-, SharePoint-, or Teams-scoped DLP cannot
see because the file has already left the cloud-inspectable path.

## 2. Business/regulatory driver

Removable media is one of the oldest and least monitored data-exfiltration channels: a departing
or malicious employee, or simply careless handling, can move gigabytes of regulated data off a
managed endpoint in seconds, with no email, chat, or cloud-sharing trail at all. This is a control
area referenced across nearly every regulatory framework this repo's buyers face — GDPR Article 32
("appropriate technical measures" against unauthorized disclosure), HIPAA Security Rule technical
safeguards (45 CFR §164.312, media controls), PCI DSS Requirement 3 (protect stored cardholder
data) and SOC 2 CC6 (logical access controls) — without any one of them mandating this specific
technical control by name. Buyers typically deploy this as a baseline data-loss-prevention control
alongside, not instead of, the classification work in `auto-label-confidential-sharepoint` and the
external-sharing controls in `pci-teams-exfil-block`.

Two secondary drivers this control also supports:
- **Audit/incident-response evidence** — every block and every IT Data Custodian copy is logged
  (alert, incident report, Activity explorer event), giving an investigator or auditor a record of
  what left the organization via removable media and when.
- **Consistency with the tenant's existing "sensitive" definition** — this scenario deliberately
  reuses the exact SIT pair `auto-label-confidential-sharepoint` uses to apply the Confidential
  label, so a buyer running both scenarios has one coherent definition of "sensitive," not two
  independently tuned ones that can drift apart.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md`. Summary for this scenario:

| Requirement | Minimum | Notes |
|---|---|---|
| Endpoint Data Loss Prevention (DLP) | **Microsoft 365 E5/A5/G5**, **Microsoft Purview Suite/EDU/GOV/FLW**, **Microsoft Defender + Purview Suite FLW**, or **Microsoft 365 E5/A5/F5/G5 Information Protection & Governance** | Confirmed per-user for every endpoint user covered by the policy [[1]](#references) |
| Device onboarding | Devices must be onboarded to Microsoft Purview device management (shared onboarding with Microsoft Defender for Endpoint) and actively reporting into Activity explorer | Onboarding is a package deployment (local script up to 10 machines, Group Policy, Configuration Manager, or Intune) — **not** something this scenario's deploy script performs. See §5 and `design.md` §5 [[2]](#references) |
| Supported OS | Windows 10/11 (specific builds per KB), Windows Server 2019+ (opt-in), or macOS (three latest released major versions) | Full current build matrix: `device-onboarding-overview` [[2]](#references) |
| Role to onboard devices / manage device monitoring | **Security Administrator**, **Compliance Administrator**, or **Global Administrator** (Microsoft Entra role) | Device management currently supports **only** Entra roles — Purview role groups (including DLP Compliance Management) do **not** grant onboarding or device-monitoring rights, even though they do grant policy-authoring rights (next row) [[2]](#references) |
| Role to author/edit DLP policies | **DLP Compliance Management** role (built into the *Compliance Administrator* / custom S&C role group) | See `docs/rbac-model.md` §3 (Purview role groups). Note this is a **separate** permission from device onboarding above — a buyer's DLP author may not be able to onboard devices, and vice versa |
| Automation identity | App registration with **Exchange Online Protection → `Exchange.ManageAsApp`** application permission, granted the DLP-authoring role group | Certificate-based app-only auth — see `docs/automation-surface.md` §3. Does not cover device onboarding, which has no PowerShell/Graph automation surface documented as of this writing (VERIFY at deploy time) |
| Dependency (not deployed by this scenario) | A mail-enabled security group or Microsoft 365 group for **IT Data Custodians** | Must exist before running `deploy/New-EndpointDlpUsbBlockPolicy.ps1` |

> Verify current entitlement names against `docs/licensing-matrix.md` (dated 2026-09-02) and the
> Product Terms before a sales commitment — SKU names change.

## 4. Architecture

```mermaid
flowchart TD
    A[User attempts to copy a file<br/>to removable USB storage] --> B{Onboarded<br/>device?}
    B -- No --> Z0[Not visible to Endpoint DLP -<br/>no monitoring, no enforcement]
    B -- Yes --> C{Content matches<br/>SSN or Credit Card Number SIT?}
    C -- No --> Z1[Copy proceeds,<br/>no DLP action]
    C -- Yes --> D{User in IT Data<br/>Custodians group?}
    D -- Yes --> E["Rule 1: USB-Audit-ITDataCustodians<br/>Audit only, copy proceeds<br/>Low-severity alert + incident report"]
    D -- No --> F["Rule 0: USB-Block-Sensitive-AllUsers<br/>Block, copy prevented<br/>High-severity alert + incident report"]

    subgraph Admin[" "]
        direction LR
        G[DLP Alerts dashboard /<br/>Microsoft Defender portal]
        H[Admin + SOC mailbox<br/>incident report email]
    end
    E -.alert.-> G
    F -.alert.-> G
    E -.notify.-> H
    F -.notify.-> H
```

One DLP policy (`Endpoint DLP - Block USB Removable Media Exfiltration`), scoped to the
**Devices** (Endpoint DLP) location, containing two priority-ordered rules. Full rule-by-rule
rationale is in `design.md` §4–6. Enforcement happens **locally on the device**, via the
Purview/Defender client, driven by policy synced from Security & Compliance PowerShell.

## 5. Step-by-step implementation

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Onboard devices first** (one-time, not part of this scenario's deploy script). Sign in to the
   [Microsoft Purview portal](https://purview.microsoft.com) → **Settings** → **Device
   onboarding** → **Devices** → **Turn on device onboarding** → **Onboarding**, choose a
   deployment method (local script, Group Policy, Configuration Manager, or Intune), and deploy
   the downloaded package to target endpoints. If devices are already onboarded to Microsoft
   Defender for Endpoint, they already appear in this list — only **Turn on device monitoring** is
   needed [[2]](#references).
2. Go to **Data loss prevention** → **Policies** → **Create policy**.
3. Category: **Custom** → template: **Custom policy** → **Next**.
4. Name: `Endpoint DLP - Block USB Removable Media Exfiltration`. **Policies can't be renamed
   after creation** — confirm the name before continuing [[3]](#references).
5. **Assign admin units**: accept **Full directory** (unless the tenant uses administrative units
   — see `docs/rbac-model.md` §4).
6. **Choose locations**: select **Devices** only; deselect all other locations.
7. **Define policy settings**: choose **Create or customize advanced DLP rules**.
8. Create rule **USB-Block-Sensitive-AllUsers** (priority 0):
   - Conditions: **Content contains** → **Sensitive info types** → **U.S. Social Security Number
     (SSN)** OR **Credit Card Number** (min count 1 each); add **Sender is a member of** with
     **Except if** toggled → the IT Data Custodians group.
   - Actions: **Audit or restrict activities on devices** → **File activities for all apps** →
     **Apply restrictions to specific activity** → set **Copy to a removable USB device** =
     **Block** [[4]](#references).
   - Incident reports: alert **High** severity, send to the SOC/admin mailbox.
9. Create rule **USB-Audit-ITDataCustodians** (priority 1): same content condition, scoped
   (**not** excepted) to the IT Data Custodians group; same activity restriction but set **Copy to
   a removable USB device** = **Audit only**; alert **Low** severity.
10. **Policy mode**: choose **Run the policy in simulation mode** first. Do not turn it on
    immediately — follow the staged rollout in §8 below.
11. **Submit**, then **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only — see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run — reports every change, makes none
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real activity first
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. After a tuning window and a pilot-tenant functional test (see §7, step 1), enforce
./deploy/New-EndpointDlpUsbBlockPolicy.ps1 `
    -ITCustodiansGroupEmail 'it-custodians@contoso.com' `
    -AdminNotificationEmail 'soc@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-EndpointDlpUsbBlockPolicy.ps1 -ITCustodiansGroupEmail 'it-custodians@contoso.com'
```

The deploy script uses Security & Compliance PowerShell (`New-DlpCompliancePolicy`,
`New-DlpComplianceRule`) — automation surface 2 per `docs/automation-surface.md` §1. Device
onboarding itself has no equivalent PowerShell/Graph cmdlet documented as of this writing and must
be performed as in §5 step 1 above, once, before this policy has any effect.

## 6. Configuration reference

| Setting | Rule 0: `USB-Block-Sensitive-AllUsers` | Rule 1: `USB-Audit-ITDataCustodians` |
|---|---|---|
| Priority | 0 | 1 |
| Sender scope | `ExceptIfFromMemberOf` = IT Data Custodians group | `FromMemberOf` = IT Data Custodians group |
| Sensitive content | SSN OR Credit Card Number (min count 1 each) | SSN OR Credit Card Number (min count 1 each) |
| `EndpointDlpRestrictions` | `@{Setting='RemovableMedia'; Value='Block'}` (VERIFY — see §11) | `@{Setting='RemovableMedia'; Value='Audit'}` (VERIFY — see §11) |
| `ReportSeverityLevel` | High | Low |
| `GenerateAlert` / `GenerateIncidentReport` | Admin + SOC mailbox | Admin + SOC mailbox |
| `StopPolicyProcessing` | `$true` | `$false` |
| Policy location | `EndpointDlpLocation = "All"` (both rules share the one policy) | |
| Policy `Mode` | `TestWithNotifications` (deploy default) → `Enable` after tuning | |

Full cmdlet parameter grounding: `deploy/New-EndpointDlpUsbBlockPolicy.ps1` inline comments and
its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## 7. Validation / how to prove it works

1. **Pilot-tenant syntax confirmation (do this before §7.2–4 in any tenant)** — the exact
   `-Value` strings inside `-EndpointDlpRestrictions` are not enumerated in Microsoft's canonical
   cmdlet reference (see §11 VERIFY note). Run `deploy/New-EndpointDlpUsbBlockPolicy.ps1` once
   against a non-production/pilot tenant and confirm it completes without a parameter-validation
   error before relying on it elsewhere.
2. **Automated config check** — `./validate/Test-EndpointDlpUsbBlockPolicy.ps1
   -ITCustodiansGroupEmail 'it-custodians@contoso.com'` confirms the policy and both rules exist
   with the expected scoping, exits non-zero on any hard failure (safe for a CI-style pre-flight).
3. **Device onboarding check** — Purview portal → **Settings** → **Device onboarding** →
   **Devices**; confirm the target test device shows **Configuration status: Updated** and
   **Policy Sync status: Updated** before running a functional test — an unsynced device will not
   enforce the policy regardless of how correct the policy configuration is [[5]](#references).
4. **Functional test (non-Custodian user)** — from a test account **not** in the IT Data
   Custodians group, on an onboarded device, attempt to copy a test file containing a documented
   test SSN or card-brand-issued test card number (never a real person's SSN or a real
   cardholder's PAN) to a USB drive. Expect: copy blocked, a toast notification on the endpoint,
   and a high-severity alert in the DLP Alerts dashboard.
5. **Functional test (IT Data Custodian)** — same test, from an account in the IT Data Custodians
   group. Expect: copy succeeds (not blocked), but a low-severity alert appears in the DLP Alerts
   dashboard.
6. **Functional test (non-sensitive content)** — copy a file with no SSN/card-number content to a
   USB drive from either account. Expect: copy succeeds, no DLP alert.
7. **Activity explorer** — Purview portal → Data loss prevention → Activity explorer → filter by
   policy name to confirm ongoing match volume once in `Enable` mode.

## 8. Operations & tuning

**Deployment sequence** (mirrors Microsoft's documented staged rollout used across every DLP
scenario in this repo): Off → Run in simulation mode → Run in simulation mode + show policy tips
(pilot group) → Turn it on. The deploy script's default `-Mode TestWithNotifications` corresponds
to the simulation stage; pass `-Mode Enable` deliberately once tuning and the §7 functional tests
are complete.

**KPIs to watch (first 30 days):**
- **Rule 0 (all-users block) match count** — a sudden spike after enabling usually means a
  legitimate business process was missed by the IT Data Custodians exception, not a wave of
  attempted exfiltration. Investigate before assuming malice.
- **Rule 1 (IT Data Custodians audit) volume and per-user distribution** — this is the baseline of
  how much sensitive content the custodian team actually copies to removable media as part of its
  job. An unusually high volume from a single custodian account relative to peers is the signal
  worth investigating first.
- **False-positive rate** — SIT false positives (test data, employee IDs that happen to be
  9 digits) show up as user complaints; tune by adjusting the SIT's confidence level or minimum
  count only after confirming the pattern in Activity explorer, not from a single report.

**Alert routing:** both rules generate alerts and incident reports to the SOC/admin mailbox
parameter. Route the DLP alert source into the SIEM (Microsoft Sentinel connector, or the
Microsoft Defender XDR incident queue export) so it lands in existing on-call rotation rather than
living only in the Purview portal — see `docs/automation-surface.md` §4.

**Review cadence:** quarterly at minimum for the overall control; re-run
`validate/Test-EndpointDlpUsbBlockPolicy.ps1` as part of that review to catch configuration drift.
Review **Rule 1 (IT Data Custodians) audit volume** on a **weekly** cadence, not quarterly — this
audit-only group is the one path in this design that can move real regulated data onto removable
media with no block at all, so it is the highest-value target for a compromised or malicious
insider and deserves the same weekly-review discipline as the Card Operations override in
`scenarios/dlp/pci-teams-exfil-block/`.

**Incident-response runbook (Rule 0 block alert, or a Rule 1 audit event that looks anomalous):**
1. **Triage** — open the alert in the DLP Alerts dashboard or Microsoft Defender portal incident
   queue; confirm which rule matched, the user, the device, and that the "Sensitive info types"
   tab shows an actual SSN/PAN-shaped match rather than a false positive.
2. **Classify** — true positive vs. false positive. False positive: no further action beyond
   noting the pattern for a future SIT confidence-threshold tuning pass.
3. **True positive, Rule 0 (block, non-Custodian user)** — the copy never completed; contact the
   user's manager and initiate the org's standard data-handling incident process. Determine
   whether the user needs a legitimate exception path or security-awareness follow-up.
4. **True positive, Rule 1 (IT Data Custodian audit)** — the copy already completed. Confirm the
   activity matches the custodian's known backup/imaging schedule and device. If it doesn't
   (unscheduled, unusual volume, unfamiliar device), escalate as a potential insider-risk event
   and consider temporary removal from the IT Data Custodians group pending investigation.
5. **Document** — every true positive and every custodian audit-event review is retained as
   incident-response evidence; do not delete or edit alert records.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-EndpointDlpUsbBlockPolicy.ps1` disables (reversible); add `-Purge` to
permanently delete the policy and its rules.

## 10. Cost & licensing notes

- **No PAYG component.** Endpoint DLP is a per-user entitlement feature, not billed through
  Purview's Azure consumption model — see `docs/licensing-matrix.md` §1–2. Cost is the marginal
  cost of moving any currently-sub-E5 endpoint users up to a qualifying SKU (§3 above).
- **No additional Azure subscription required** for this control specifically.
- **Device onboarding has no separate license fee** beyond the qualifying per-user SKU, but it
  does carry an operational cost: package deployment to every in-scope endpoint via existing
  device-management tooling (Intune/Configuration Manager/Group Policy), which is real deployment
  effort a buyer should budget for separately from the DLP policy authoring this scenario covers.
- **Sizing note:** license only the users in scope — typically all knowledge-worker endpoints
  handling regulated data, which in the enterprises this repo targets is often already covered by
  an existing E5 estate.

## 11. Known limitations & gotchas

- **VERIFY — exact `EndpointDlpRestrictions` `-Value` strings.** Microsoft's canonical
  `New-DlpComplianceRule` / `Set-DlpComplianceRule` parameter reference documents
  `-EndpointDlpRestrictions` only as an opaque `PswsHashtable[]` with no enumerated values. This
  scenario uses `Setting = 'RemovableMedia'` with `Value = 'Block'` / `'Audit'`, grounded in (a)
  the portal's own action naming for the "Copy to a removable device" activity — Allow / Audit
  only / Block with override / Block [[4]](#references), and (b) a Microsoft Security Blog
  PowerShell walkthrough on Tech Community ("Creating Endpoint DLP Rules using PowerShell -
  Part 1") that shows this exact `Setting`/`Value` hashtable shape for the `RemovableMedia` and
  `Print` activities. Confirm both strings in a pilot tenant (§7, step 1) before production
  reliance — an incorrect string causes the cmdlet to throw at creation time, not a silent
  misconfiguration, so this fails safe.
- **Device onboarding is a separate, non-scripted prerequisite.** This scenario's deploy script
  authors the DLP policy only; it assumes devices are already onboarded (§3, §5 step 1). A policy
  deployed against un-onboarded devices has no effect and generates no error — always confirm
  device onboarding/policy-sync status (§7 step 3) before concluding a functional test failure is
  a policy bug.
- **Encrypted or password-protected files are not scanned.** Endpoint DLP inspects file content;
  a password-protected archive or an encrypted container cannot be opened and classified, so a
  user who zips-with-password a sensitive file before copying it to USB will not trigger either
  rule. Microsoft documents dedicated policies for files it cannot scan
  (`dlp-create-policy-files-edlp-doesnt-scan`) — pair this scenario with that guidance if
  encrypted-archive exfiltration is a realistic threat in the target environment
  [[6]](#references).
- **Unsupported/unscanned file types and photographs of screens are not covered.** As with every
  content-pattern DLP control in this repo (see `pci-teams-exfil-block/README.md` §11), a file
  type Endpoint DLP doesn't parse, or a photo taken of a screen with a phone, bypasses text-pattern
  matching entirely — this is an inherent limitation of content inspection, not a configuration
  gap this scenario can close.
- **This scenario does not restrict Print, clipboard, network share, Bluetooth, or RDP.** Only
  **copy to removable media** is restricted. `design.md` §7 documents how to extend the
  `EndpointDlpRestrictions` array to cover those activities.
- **This scenario does not configure Removable USB device groups** (per-physical-device
  allowlisting of specific IT-issued encrypted backup drives, distinct from the group-based
  IT Data Custodians user exception this scenario does implement). That's a portal-only,
  per-device registration workflow with no PowerShell object this deploy script can create —
  tracked as a follow-up in `PROGRESS.md`. Combining it with this scenario lets a buyer scope the
  IT exception down from "any removable media, watched" to "only these specific backup drives,
  unrestricted."
- **This scenario does not replace Microsoft Defender for Endpoint device control.** Device
  control can deny an unapproved USB device outright regardless of content (content-blind, at the
  driver level); Endpoint DLP is content-aware but requires the device to already be a recognized
  disk. A buyer wanting "no unknown USB devices, period" needs device control in addition to this
  scenario, not instead of it — see `design.md` §3.

## 12. References

1. Microsoft Purview service description — Endpoint Data Loss Prevention (DLP) licensing table — <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-data-loss-prevention-endpoint-data-loss-protection-dlp>
2. Onboard Windows devices into Microsoft 365 overview (onboarding methods, supported OS builds, permissions — device management supports only Entra roles) — <https://learn.microsoft.com/purview/device-onboarding-overview>
3. Learn about the default DLP policy in Microsoft Teams (naming behavior applies to all DLP policies: cannot be renamed after creation) — <https://learn.microsoft.com/purview/dlp-teams-default-policy>
4. Data Loss Prevention policy reference (Audit or restrict activities on devices; Allow/Audit only/Block with override/Block action semantics; Copy to a removable device activity) — <https://learn.microsoft.com/purview/dlp-policy-reference>
5. Troubleshooting endpoint data loss prevention configuration and policy sync — <https://learn.microsoft.com/purview/dlp-edlp-tshoot-sync>
6. Help protect files that Endpoint Data Loss Prevention doesn't scan — <https://learn.microsoft.com/purview/dlp-create-policy-files-edlp-doesnt-scan>
7. Configure endpoint data loss prevention settings (Removable USB device groups, restricted-activity actions) — <https://learn.microsoft.com/purview/dlp-configure-endpoint-settings>
8. New-DlpCompliancePolicy reference (EndpointDlpLocation, Mode) — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
9. New-DlpComplianceRule reference (EndpointDlpRestrictions, ContentContainsSensitiveInformation, FromMemberOf/ExceptIfFromMemberOf, StopPolicyProcessing, ReportSeverityLevel) — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
10. Set-DlpCompliancePolicy reference (Mode: Enable/Disable/TestWithNotifications/TestWithoutNotifications) — <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>
11. Remove-DlpCompliancePolicy reference — <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
12. Get started with Endpoint data loss prevention — <https://learn.microsoft.com/purview/endpoint-dlp-getting-started>
13. Learn about Endpoint data loss prevention (local evaluation, file classification triggers) — <https://learn.microsoft.com/purview/endpoint-dlp-learn-about>
14. Device control in Microsoft Defender for Endpoint (content-blind device-level USB control, complementary to Endpoint DLP) — <https://learn.microsoft.com/defender-endpoint/device-control-overview>
15. Creating Endpoint DLP Rules using PowerShell - Part 1 (Microsoft Security Blog, Tech Community — EndpointDlpRestrictions Setting/Value hashtable example for RemovableMedia and Print) — <https://techcommunity.microsoft.com/blog/microsoft-security-blog/creating-endpoint-dlp-rules-using-powershell---part-1/4286999>
16. Connect-IPPSSession reference (app-only certificate auth) — <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
17. U.S. Social Security Number (SSN) / Credit Card Number sensitive information types — reused from `scenarios/information-protection/auto-label-confidential-sharepoint/` (see that scenario's own references for SIT definition citations).

> Re-verify all links, and especially the item 15 walkthrough and the `EndpointDlpRestrictions`
> Setting/Value strings, against current Microsoft Learn and a pilot tenant before a
> customer-facing assessment or sale — both product behavior and community-blog content change
> over time and are not covered by Microsoft's documentation SLA the way Learn reference pages are.
