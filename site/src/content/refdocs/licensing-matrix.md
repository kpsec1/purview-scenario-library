---
title: "Microsoft Purview, Licensing & Prerequisites Matrix"
name: "Licensing matrix"
---
> **Cross-cutting reference.** Every scenario in this library links here instead of restating
> licensing. Read this once to understand *which* subscription unlocks *which* capability.
>
> **Verify before you quote a customer.** Licensing changes frequently. The Microsoft
> **Product Terms** and the **Purview service description** are the only authoritative sources, 
> this matrix is a practitioner's summary grounded in Microsoft Learn, current as of
> **2026-09-10**. Sources are linked at the bottom; re-check them before a sales commitment.

---

## 1. The two billing models (read this first)

Microsoft Purview is licensed through **two models that operate side by side**. Most real
deployments touch both.

| | **Per-user entitlement** | **Pay-as-you-go (PAYG)** |
|---|---|---|
| **What it is** | A subscription/add-on assigned to a user (E5, E3, Purview Suite, etc.) | Azure consumption billing, metered monthly |
| **Covers** | Purview features acting on **Microsoft 365 + Windows/macOS** data | Purview features acting on **non-M365** sources (AWS, Azure SQL, Box, Dropbox, Google Drive, Fabric, Entra) and data-governance/health compute |
| **Billing mechanism** | Microsoft 365 licensing | Requires the M365 tenant associated with an **active Azure subscription** + resource group |
| **Examples** | Sensitivity labels on Exchange/SharePoint; DLP for Teams; IRM on M365 activity | Auto-labeling non-M365 assets; Unified Catalog governed assets/day; Data Quality DGPUs; Data Security Investigations |

**Key dates & facts**
- PAYG took effect for Microsoft Purview on **January 6, 2025**.
- Some solutions are per-user only; some require the per-user license to be *enabled first*, then
 bill PAYG for out-of-scope sources; some (e.g. Data Governance Unified Catalog) are PAYG-only.
- **"Microsoft Purview Suite"** is the current name for the former **Microsoft 365 E5 Compliance**
 add-on.

### Who needs a per-user license?
> Rule of thumb: **any user who benefits from the service.** That includes users with a Purview
> role in the portal; owners/members of a mailbox, OneDrive, Team, SharePoint site, or M365 Group
> where a Purview policy applies. **Visitor / view-only** users on shared locations do **not** need
> a license. **Inactive mailboxes** don't require a usage license.

---

## 2. Master capability → license matrix

Legend: **E3** = Microsoft 365 E3 tier · **E5** = Microsoft 365 E5 tier · **Suite** = Microsoft
Purview Suite (ex-"E5 Compliance") · **PAYG** = Azure pay-as-you-go meter also applies.
Government (G3/G5), Academic (A3/A5), and Frontline (F5) SKUs generally mirror their E-tier
equivalents unless noted, always confirm against Product Terms for GCC/GCC-High/DoD.

| Module | Capability | Minimum entitlement | Notes / PAYG |
|---|---|---|---|
| **Information Protection** | Manually apply a sensitivity label | **E3** | Also EMS E3/E5, Office 365 E5, AIP P1/P2 |
| Information Protection | Scanner-based on-prem discovery | **E3** | RMS connector for on-prem workloads |
| Information Protection | **Automatic / policy-based labeling** | **E5** (or IP&G add-on) | Non-M365 sources → **PAYG** per asset/day |
| Information Protection | Content Explorer / Activity Explorer | **E5** | Data *aggregation* continues for E3 tenants |
| Information Protection | Label-based control in Teams chat | **E5** | |
| **DLP** | DLP for Exchange / SharePoint / OneDrive | **E3** (basic) | Advanced classification & Teams → **E5** |
| DLP | Endpoint DLP (Windows/macOS) | **E5** | Non-M365 egress coverage → **PAYG** |
| DLP | DLP posture reports | **E5** | Purview portal → DLP > Reports |
| **Insider Risk Management** | All IRM policies | **E5**, Suite, or **E5 Insider Risk Management** add-on | Cloud/GenAI indicators on non-M365 → **PAYG** (Data Security processing unit/day) |
| **Adaptive Protection** | Risk-based dynamic DLP/label enforcement | **E5** / Suite (built on IRM + DLP) | Inherits IRM + DLP prerequisites |
| **DSPM for AI** | Copilot & GenAI data-security posture | See `ai-microsoft-purview-considerations` | Audit of Copilot activity included in **E5**; broader protections may bill **PAYG** |
| DSPM for AI | DLP for Microsoft Copilot, restrict **files & emails** (label-exclusion rule) | **E5**, Microsoft 365/Office 365 E5/A5, **Microsoft Purview Suite/EDU/FLW**, or **Microsoft 365/A5/F5 Information Protection and Governance** | Listed **No** on Business Basic/Standard/Premium and the E3/A3/A1/G3/F3/F1 tiers |
| DSPM for AI | DLP for Microsoft Copilot, safeguard **prompts** (SIT-based web-grounding / full-block rule) | **All Microsoft 365 Copilot and Copilot Chat licenses**, any underlying M365 tier | Listed **Yes*** for every Copilot-licensed tier, do not over-quote E5 for this half of the policy |
| **Data Map** | Scan & classify into Data Map | Azure subscription | No scan charge once on Unified Catalog PAYG or Enterprise tier |
| **Unified Catalog** | Curate/govern technical assets | **PAYG only** | Metered: **unique governed assets/day** |
| **Data Quality / Health** | DQ rules, scorecards, health mgmt | **PAYG only** | Metered: **Data Governance Processing Units (DGPU)**; Basic/Standard/Advanced SKUs |
| **Data Estate Insights** | Classification/coverage reporting | Per governance tier | Classic pricing vs Unified Catalog, confirm tier |
| **Data Lineage** | Lineage capture & validation | Part of Data Map/Catalog | Follows Data Map / Unified Catalog billing |
| **Compliance Manager** | Assessments & improvement actions | **E3** (base) / **E5** (premium templates) | Premium assessment templates need E5/Suite |
| **Communication Compliance** | Policy detection & review | **E5**, Suite, or E5 add-on | Non-M365 indicators → **PAYG** |
| **eDiscovery (Standard)** | Holds, search, export | **E3** | |
| **eDiscovery (Premium)** | Review sets, analytics, custodians | **E5**, Suite, or **E5 eDiscovery & Audit** add-on | |
| **Audit (Standard)** | Baseline audit log | **E3** | |
| **Audit (Premium)** | Long retention, high-value events, Audit API | **E5**, Suite, or **E5 eDiscovery & Audit** add-on | |
| **Data Lifecycle Management** | Basic org/location retention | **E3 / Business Premium / Office 365 E3+** | Broadest license coverage of any module |
| Data Lifecycle Management | Adaptive scopes, auto-apply, trainable-classifier retention | **E5** (or IP&G add-on) | |
| Data Lifecycle Management | **Priority cleanup** (delete content, overriding retention/holds/Preservation Lock, Exchange: permanent; SharePoint/OneDrive: to the second-stage Recycle Bin by default, or permanently with the separate permanent-deletion sub-option) | **E5** (or IP&G add-on) | Preview; confirmed on its own line in the service description, same tier as Records Management; one shared tenant-wide toggle covers both workloads, `scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/`, `scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/`. SharePoint/OneDrive **permanent deletion** is a separately-gated public preview (rollout begins 2026-08-24), same licensing tier, no separate meter, `scenarios/data-lifecycle-management/priority-cleanup-permanent-deletion/` |
| **Records Management** | Records declaration, disposition, file plan | **E5** (or IP&G add-on) | |
| **Information Barriers** | Segment communication between groups | **E5**, Suite, or E5 add-on | Requires supported workloads (Teams, SPO, OneDrive, Exchange) |
| **Data Security Investigations** | AI-assisted post-breach/insider-leak investigation, triage, and purge | **PAYG only**, no dedicated per-user license | Metered: **data storage** (GB/month across all investigations) **+ Data Security Investigations compute units** (AI processing); **not pausable** in the Usage center, unlike several other PAYG capabilities above. A Defender XDR/Insider Risk Management/DSPM license unlocks those specific investigation-creation entry points, not DSI itself, `scenarios/data-security-investigations/post-breach-investigation-and-purge/README.md` §3/§10 |

> **Underlying-workload licenses also grant rights.** For retention specifically, the *location*
> matters: Exchange mailbox retention is also covered by Exchange Plan 2 / Exchange Online
> Archiving; SharePoint/OneDrive by SharePoint Plan 2; Teams chat retention >30 days by a wide set
> of E/F/Business plans. See the service description for the exact per-location list.

---

## 3. Add-on SKUs that unlock E5-tier Purview without full E5

Buyers on E3 frequently license Purview via targeted add-ons rather than upgrading to full E5:

- **Microsoft Purview Suite** (formerly Microsoft 365 E5 Compliance), the broad compliance bundle.
- **Microsoft 365 E5 Information Protection & Governance (IP&G)**, labeling, DLP-advanced, DLM, Records.
- **Microsoft 365 E5 Insider Risk Management**, IRM (and underpins Adaptive Protection + Comms Compliance for some scenarios).
- **Microsoft 365 E5 eDiscovery and Audit**, eDiscovery Premium + Audit Premium.
- **Microsoft Defender + Purview Suite (FLW)**, frontline-worker combined bundle.

> When a scenario says "requires E5," it almost always means **"E5 *or* the matching add-on above."**
> Each scenario README states the cheapest qualifying SKU.

---

## 4. Common cross-module prerequisites

- **Microsoft Entra ID P1/P2**, required for **administrative units** (delegated RBAC scoping) in
 Purview, on top of an E5-tier Purview license.
- **Azure subscription + resource group** in the *same tenant*, required for **any PAYG**
 capability (data governance, non-M365 data security).
- **Microsoft Purview portal** access (`purview.microsoft.com`), the modern portal; some classic
 data-governance flows still live in the classic governance portal.
- **Data residency / CMK**, Purview metadata is encrypted at rest; customer-managed keys
 (Customer Key) are a separate opt-in.
- **Exchange Online Authentication Policies, the `SmtpClientAuthenticationDisabled` transport
 setting, and per-mailbox `CASMailbox` overrides**, core Exchange Online administration
 surfaces, included in any plan that includes Exchange Online. **No incremental license**, 
 unlike this library's Conditional-Access-based scenarios (§8, §9), which need Entra ID P1/P2. See
 `scenarios/adaptive-protection/exchange-legacy-auth-block/README.md` §3.

---

## 5. Trials (for POCs and vendor demos)

- **Microsoft Purview Suite trial**, 90 days, self-serve from the Purview portal; provisions
 **25 Purview Suite licenses** automatically. Eligibility: tenants with **M365 E3**, *or*
 **Office 365 E3 + EMS E3**, that don't already have an E5 package. **Not** available to M365
 Government tenants.
- **Microsoft 365 E5 trial**, for Information Protection / non-M365 labeling POCs.

---

## 6. How scenarios should cite licensing

Each scenario README's **Prerequisites** section must state:
1. The **cheapest qualifying entitlement** (e.g. "E5, or the E5 Insider Risk Management add-on").
2. Whether **PAYG** applies, and the **unit of measure** (e.g. "governed assets/day", "DGPU/run").
3. Any **cross-prerequisite** (Entra P1/P2, Azure subscription, supported workload).
4. A one-line **"verify as of <date>"** pointer back to this matrix.

---

## 7. Adjacent product family: Microsoft Defender for Endpoint + Intune (device-control scenarios)

Two scenarios in this library, `scenarios/dlp/defender-device-control-usb-allowlist/` and its
`-wpd-coverage/` sibling, are **not** built on a Purview policy object. They close a gap Endpoint
DLP (content-aware only) can't: device-*identity* control on removable storage and Windows
Portable Devices. That means their licensing sits outside the rest of this matrix, on **Microsoft
Defender for Endpoint** + **Microsoft Intune** instead. Documented here rather than folded into
the table in §2, which is scoped to Purview modules.

| Requirement | Minimum entitlement | Notes |
|---|---|---|
| Device control (the capability itself) | **Microsoft Defender for Endpoint Plan 1**, standalone, or bundled in **Microsoft 365 E3/A3/G3** | Device control ships in P1: Microsoft's own Defender service description lists it alongside next-gen anti-malware, attack surface reduction, endpoint firewall, and application control as a **Plan 1** capability. **Plan 2 is not required**, a real cost advantage over the E5-gated Purview DLP/IRM scenarios elsewhere in this library. Plan 2 (bundled in Microsoft 365 E5/A5/G5, or standalone) is still worth having for EDR/automated investigation, but device control alone doesn't justify the upgrade. |
| Policy authoring/deployment surface | **Microsoft Intune Plan 1** (the base plan), bundled in Microsoft 365 E3/E5, or standalone | Both scenarios deploy via an Intune **Custom device configuration profile** (`windows10CustomConfiguration`, OMA-URI). Device configuration profiles are core Plan 1 functionality. Intune Plan 2 / Intune Suite add unrelated advanced capabilities (Remote Help, Advanced Analytics, Endpoint Privilege Management, Cloud PKI) that device control does not need. |
| Device enrollment (not just Defender onboarding) | Devices must be **Intune-enrolled (MDM)**, in addition to being onboarded to Defender for Endpoint | A device onboarded to Defender for Endpoint but managed only through **Security settings management** (the agentless path for devices not enrolled in Intune) does **not** receive Intune-deployed device control policy, Microsoft's own device-control-vs-Intune capability table states this explicitly. This is a real deployment trap: "already onboarded to Defender" is not sufficient by itself. |
| Anti-malware client version | `4.18.2103.3`+ (base removable-media/CD-ROM/printer control); `4.18.2107`+ for **Windows Portable Device** coverage (phones/cameras in MTP/PTP mode) | A software-version gate, not a license, included here because it blocks the same two scenarios and is easy to miss when only licensing is checked. |
| Supported platform | Windows 10/11 client only | Device control is **not supported on Windows Server**. macOS device control uses a separate JSON/`mobileconfig` authoring path via Intune or Jamf, out of scope for these two Windows-only scenarios. |

**Cost note for a CISO conversation:** because Microsoft 365 E3 now includes Defender for
Endpoint Plan 1 outright, a customer already on plain E3, with **no** Purview E5 add-on, can
deploy both device-control scenarios today. That's a materially cheaper entry point than nearly
every other DLP/IRM scenario in this library, which needs E5 or a matching add-on (§2). It's a
useful low-cost first step to recommend before a customer commits to the E5-gated content-aware
controls.

> Intune RBAC (the **Policy and Profile manager** built-in role for human/portal access, and the
> Microsoft Graph application permission `DeviceManagementConfiguration.ReadWrite.All` for this
> library's app-only automation) is not yet cross-referenced in [RBAC model](/docs/rbac-model/), tracked as
> a separate follow-up in `PROGRESS.md`.

---

## 8. Adjacent product family: Microsoft Entra ID P2 (Conditional Access risk-based conditions)

Two scenarios in this library, `scenarios/adaptive-protection/conditional-access-insider-risk-block/`
(Elevated risk) and `scenarios/adaptive-protection/conditional-access-insider-risk-step-up-auth/`
(Moderate/Minor risk), are **not** built on a Purview policy object or an Intune profile. Both
author **Microsoft Entra Conditional Access** policies using the Insider Risk condition, which
requires **Microsoft Entra ID P2** specifically, a materially narrower and more specific
requirement than the general "Entra ID P1/P2 for administrative units" prerequisite already in §4,
which P1 alone also satisfies. Documented here rather than folded into §2, which is scoped to
Purview modules.

> The second scenario's Moderate-risk policy additionally uses Conditional Access's **Terms of
> Use** grant control, whose own feature floor is a lower **Microsoft Entra ID P1**
>, already satisfied by the P2
> requirement below, since P2 is a superset of P1 entitlement. Called out only so a buyer
> evaluating the Terms of Use policy in isolation (without the Insider Risk condition, or without
> the Elevated sibling) knows the *feature's own* floor, not just this table's overall floor.

| Requirement | Minimum entitlement | Notes |
|---|---|---|
| Conditional Access Insider Risk condition | **Microsoft Entra ID P2**, standalone, or bundled in **Microsoft 365 E5** / **Microsoft 365 E5 Security** | Confirmed on Microsoft's own Conditional Access Insider Risk recommendation page. **Entra ID P1 alone is not sufficient** for this specific condition, even though P1 covers Conditional Access generally and administrative units (§4), a buyer who licensed P1 only for administrative-unit scoping is **not** automatically covered for this scenario. |
| Feeder Adaptive Protection signal | Same as the Adaptive Protection row in §2 (E5/Suite, built on IRM + DLP) | Not a new requirement, this scenario consumes the same insider risk level Adaptive Protection already computes for the DLP-based `dynamic-risk-dlp-enforcement` sibling scenario. |
| Population sizing | Every user in the Conditional Access policy's **Users** scope needs Entra ID P2 | Not just admins/security staff, if the policy's `includeUsers` is `All` (this scenario's default, matching Microsoft's own documented procedure), P2 coverage must extend tenant-wide before enabling enforcement. Confirm actual P2 seat count against the policy's real scope before a sales commitment, this is a common licensing-compliance trap when a buyer already has *some* P2 seats (e.g. for Entra ID Protection risk policies) but not full coverage. |

> **VERIFY (pilot tenant or a future Microsoft Learn licensing-enforcement pass):** exactly what
> happens at sign-in for a user in scope of this policy who does **not** hold Entra ID P2, 
> whether Microsoft's licensing-enforcement model exempts that specific user from the Insider Risk
> condition (a silent under-coverage gap), blocks their sign-in outright for lacking the required
> license, or something else. Not independently confirmed during this build; do not assume either
> behavior when sizing a partial-P2-coverage rollout.

**Cost note for a CISO conversation:** unlike the Defender for Endpoint + Intune adjacency in §7
(which can be a materially *cheaper* entry point than E5-gated Purview controls), this adjacency
is typically an **incremental cost**, a tenant already at Microsoft 365 E5 for Adaptive
Protection does not automatically hold Entra ID P2 for every user (E5 licensing bundles vary by
program and vintage; always confirm the specific SKU's inclusions rather than assuming). Budget
this explicitly rather than treating it as already covered by the Purview E5/Suite spend in §2.

---

## 9. Adjacent product family: Microsoft Entra ID P1 (baseline Conditional Access, block legacy authentication)

`scenarios/adaptive-protection/block-legacy-authentication/` is the third scenario in this
library built on **Microsoft Entra Conditional Access** rather than a Purview policy object, but
the **first that needs only Microsoft Entra ID P1**, not the P2 both §8 scenarios require. Its
`clientAppTypes` condition and `block` grant control use no risk-based or premium-only condition,
so Microsoft's own Conditional Access licensing reference confirms the P1 floor applies
, a buyer already at Microsoft 365 E3
(which bundles Entra ID P1) needs **no incremental identity license** for this specific scenario,
unlike either §8 scenario.

| Requirement | Minimum entitlement | Notes |
|---|---|---|
| Custom Conditional Access policy (this scenario's own path) | **Microsoft Entra ID P1**, standalone, or bundled in **Microsoft 365 E3/E5**, **Microsoft 365 Business Premium** | Confirmed on Microsoft's Conditional Access overview and licensing references, no Entra ID P2 needed for this control specifically. |
| Microsoft-managed "Block legacy authentication" policy (auto-deployed, informational, not required to use this scenario) | **Microsoft Entra ID P2** or **Microsoft 365 Business Premium** | A narrower eligibility gate than P1 alone, a P1-only tenant will never receive Microsoft's auto-deployed equivalent and should expect to rely on this scenario's own custom policy instead. |
| No Conditional Access license at all (Entra ID Free) | **Security defaults**, at no cost | A separate, zero-customization mechanism that also blocks legacy authentication, not this scenario's scripted path. |

**Cost note for a CISO conversation:** this is the cheapest Conditional-Access-based adjacency in
this library, for a buyer already licensed at Microsoft 365 E3 or higher (which the large
majority of this library's other Purview scenarios already assume for E5/Suite features, or which
bundles P1 even below E5), this scenario typically adds **zero incremental license cost**, and if
the tenant already holds Entra ID P2 or Microsoft 365 Business Premium, the underlying control may
already be auto-deployed by Microsoft for free (`scenarios/adaptive-protection/
block-legacy-authentication/design.md` §3), confirm with that scenario's own detection check
before budgeting anything at all.

---

## Sources (Microsoft Learn, re-verify before quoting)

- Microsoft Purview service description, <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
- Microsoft Purview billing models (PAYG), <https://learn.microsoft.com/purview/purview-billing-models>
- Data governance billing (Unified Catalog / DGPU), <https://learn.microsoft.com/purview/data-governance-billing>
- Purview Suite trial, <https://learn.microsoft.com/purview/purview-trial>
- Administrative units prerequisites, <https://learn.microsoft.com/purview/purview-admin-units>
- Sensitivity labels in Data Map (licensing FAQ), <https://learn.microsoft.com/purview/data-map-sensitivity-labels-faq>
- Purview pricing calculators, <https://azure.microsoft.com/pricing/details/purview/>
- [8] Protect your tenant with Insider Risk in Conditional Access (Entra ID P2 licensing
 requirement for the Conditional Access Insider Risk condition), <https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition>
- [9] Set up Microsoft Entra terms of use with Conditional Access (Entra ID P1 licensing floor for
 the Terms of Use feature itself), <https://learn.microsoft.com/entra/identity/conditional-access/terms-of-use>
- Microsoft Product Terms (authoritative), <https://www.microsoft.com/licensing/terms/product/ForOnlineServices/EAEAS>
- Microsoft Defender service description (Defender for Endpoint P1/P2 plan contents & bundling), <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-defender-service-description>
- Device control in Microsoft Defender for Endpoint (prerequisites, anti-malware client versions), <https://learn.microsoft.com/defender-endpoint/device-control-overview>
- Manage device security with endpoint security policies in Intune (Defender integration prerequisites), <https://learn.microsoft.com/intune/device-configuration/endpoint-security/manage-policies>
- Manage endpoint security policies in Microsoft Defender for Endpoint (Intune-enrollment-only footnote for device control), <https://learn.microsoft.com/defender-endpoint/endpoint-security-policies-configure>
- Microsoft Intune licensing (Plan 1/Plan 2/Suite), <https://learn.microsoft.com/intune/fundamentals/licensing>
- [10] What is Conditional Access? (License requirements, Microsoft Entra ID P1 floor for
 Conditional Access generally, distinct from the P2 floor risk-based conditions need), <https://learn.microsoft.com/entra/identity/conditional-access/overview>
- [11] Microsoft Entra licensing (Conditional Access requires Entra ID P1), <https://learn.microsoft.com/entra/fundamentals/licensing>
- [12] Microsoft-managed Conditional Access policies (P2/Microsoft 365 Business Premium
 eligibility gate for the auto-deployed policy), <https://learn.microsoft.com/entra/identity/conditional-access/managed-policies>
- [13] Security defaults in Microsoft Entra ID (zero-cost alternative for tenants without Entra ID
 P1/P2), <https://learn.microsoft.com/entra/fundamentals/security-defaults>
- [14] Microsoft Purview service description, Data Loss Prevention (DLP) for Microsoft Copilot
 licensing table (the "files and emails" vs. "prompts" tier split), <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-dlp-for-microsoft-copilot>
- [15] Manage pay-as-you-go and per-user licensing usage (Usage center pausable-features table, 
 Data Security Investigations listed as not pausable, unlike Communication Compliance/Audit/
 Information Protection/Data Lifecycle Management), <https://learn.microsoft.com/purview/purview-billing-usage>

> **Disclaimer:** SKU names, tiers, and PAYG meters change. Nothing here is a licensing guarantee.
> Validate every entitlement against Product Terms and the service description for the customer's
> cloud (Commercial / GCC / GCC-High / DoD) before contractual commitments.
