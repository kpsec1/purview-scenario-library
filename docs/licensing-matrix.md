# Microsoft Purview — Licensing & Prerequisites Matrix

> **Cross-cutting reference.** Every scenario in this library links here instead of restating
> licensing. Read this once to understand *which* subscription unlocks *which* capability.
>
> **Verify before you quote a customer.** Licensing changes frequently. The Microsoft
> **Product Terms** and the **Purview service description** are the only authoritative sources —
> this matrix is a practitioner's summary grounded in Microsoft Learn, current as of
> **2026-09-02**. Sources are linked at the bottom; re-check them before a sales commitment.

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
equivalents unless noted — always confirm against Product Terms for GCC/GCC-High/DoD.

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
| **Data Map** | Scan & classify into Data Map | Azure subscription | No scan charge once on Unified Catalog PAYG or Enterprise tier |
| **Unified Catalog** | Curate/govern technical assets | **PAYG only** | Metered: **unique governed assets/day** |
| **Data Quality / Health** | DQ rules, scorecards, health mgmt | **PAYG only** | Metered: **Data Governance Processing Units (DGPU)**; Basic/Standard/Advanced SKUs |
| **Data Estate Insights** | Classification/coverage reporting | Per governance tier | Classic pricing vs Unified Catalog — confirm tier |
| **Data Lineage** | Lineage capture & validation | Part of Data Map/Catalog | Follows Data Map / Unified Catalog billing |
| **Compliance Manager** | Assessments & improvement actions | **E3** (base) / **E5** (premium templates) | Premium assessment templates need E5/Suite |
| **Communication Compliance** | Policy detection & review | **E5**, Suite, or E5 add-on | Non-M365 indicators → **PAYG** |
| **eDiscovery (Standard)** | Holds, search, export | **E3** | |
| **eDiscovery (Premium)** | Review sets, analytics, custodians | **E5**, Suite, or **E5 eDiscovery & Audit** add-on | |
| **Audit (Standard)** | Baseline audit log | **E3** | |
| **Audit (Premium)** | Long retention, high-value events, Audit API | **E5**, Suite, or **E5 eDiscovery & Audit** add-on | |
| **Data Lifecycle Management** | Basic org/location retention | **E3 / Business Premium / Office 365 E3+** | Broadest license coverage of any module |
| Data Lifecycle Management | Adaptive scopes, auto-apply, trainable-classifier retention | **E5** (or IP&G add-on) | |
| **Records Management** | Records declaration, disposition, file plan | **E5** (or IP&G add-on) | |
| **Information Barriers** | Segment communication between groups | **E5**, Suite, or E5 add-on | Requires supported workloads (Teams, SPO, OneDrive, Exchange) |

> **Underlying-workload licenses also grant rights.** For retention specifically, the *location*
> matters: Exchange mailbox retention is also covered by Exchange Plan 2 / Exchange Online
> Archiving; SharePoint/OneDrive by SharePoint Plan 2; Teams chat retention >30 days by a wide set
> of E/F/Business plans. See the service description for the exact per-location list.

---

## 3. Add-on SKUs that unlock E5-tier Purview without full E5

Buyers on E3 frequently license Purview via targeted add-ons rather than upgrading to full E5:

- **Microsoft Purview Suite** (formerly Microsoft 365 E5 Compliance) — the broad compliance bundle.
- **Microsoft 365 E5 Information Protection & Governance (IP&G)** — labeling, DLP-advanced, DLM, Records.
- **Microsoft 365 E5 Insider Risk Management** — IRM (and underpins Adaptive Protection + Comms Compliance for some scenarios).
- **Microsoft 365 E5 eDiscovery and Audit** — eDiscovery Premium + Audit Premium.
- **Microsoft Defender + Purview Suite (FLW)** — frontline-worker combined bundle.

> When a scenario says "requires E5," it almost always means **"E5 *or* the matching add-on above."**
> Each scenario README states the cheapest qualifying SKU.

---

## 4. Common cross-module prerequisites

- **Microsoft Entra ID P1/P2** — required for **administrative units** (delegated RBAC scoping) in
  Purview, on top of an E5-tier Purview license.
- **Azure subscription + resource group** in the *same tenant* — required for **any PAYG**
  capability (data governance, non-M365 data security).
- **Microsoft Purview portal** access (`purview.microsoft.com`) — the modern portal; some classic
  data-governance flows still live in the classic governance portal.
- **Data residency / CMK** — Purview metadata is encrypted at rest; customer-managed keys
  (Customer Key) are a separate opt-in.

---

## 5. Trials (for POCs and vendor demos)

- **Microsoft Purview Suite trial** — 90 days, self-serve from the Purview portal; provisions
  **25 Purview Suite licenses** automatically. Eligibility: tenants with **M365 E3**, *or*
  **Office 365 E3 + EMS E3**, that don't already have an E5 package. **Not** available to M365
  Government tenants.
- **Microsoft 365 E5 trial** — for Information Protection / non-M365 labeling POCs.

---

## 6. How scenarios should cite licensing

Each scenario README's **Prerequisites** section must state:
1. The **cheapest qualifying entitlement** (e.g. "E5, or the E5 Insider Risk Management add-on").
2. Whether **PAYG** applies, and the **unit of measure** (e.g. "governed assets/day", "DGPU/run").
3. Any **cross-prerequisite** (Entra P1/P2, Azure subscription, supported workload).
4. A one-line **"verify as of <date>"** pointer back to this matrix.

---

## Sources (Microsoft Learn — re-verify before quoting)

- Microsoft Purview service description — <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
- Microsoft Purview billing models (PAYG) — <https://learn.microsoft.com/purview/purview-billing-models>
- Data governance billing (Unified Catalog / DGPU) — <https://learn.microsoft.com/purview/data-governance-billing>
- Purview Suite trial — <https://learn.microsoft.com/purview/purview-trial>
- Administrative units prerequisites — <https://learn.microsoft.com/purview/purview-admin-units>
- Sensitivity labels in Data Map (licensing FAQ) — <https://learn.microsoft.com/purview/data-map-sensitivity-labels-faq>
- Purview pricing calculators — <https://azure.microsoft.com/pricing/details/purview/>
- Microsoft Product Terms (authoritative) — <https://www.microsoft.com/licensing/terms/product/ForOnlineServices/EAEAS>

> **Disclaimer:** SKU names, tiers, and PAYG meters change. Nothing here is a licensing guarantee.
> Validate every entitlement against Product Terms and the service description for the customer's
> cloud (Commercial / GCC / GCC-High / DoD) before contractual commitments.
