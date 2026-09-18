---
title: "Microsoft Purview, Glossary of Canonical Terms"
name: "Glossary"
---
> **Cross-cutting reference.** Every scenario in this library uses the terms defined here with
> **exactly this meaning**, do not redefine a term locally in a scenario README. If a scenario
> needs a term not listed here, add it to this file in the same fragment rather than inventing a
> one-off definition.
>
> **Verify before you quote a customer.** Product terminology shifts as Purview ships updates
> (Unified Catalog superseding classic Data Catalog concepts is the biggest current example).
> This glossary is a practitioner's summary grounded in Microsoft Learn, current as of
> **2026-09-03**. Sources are linked at the bottom; re-check them before using a term in a
> contractual document (SOW, DPA, compliance attestation).

---

## 1. How to use this glossary

Each entry is tagged with the module(s) it belongs to, using the legend below. A term used
identically across modules (e.g. **sensitivity label**) is defined once under its primary module
and cross-referenced elsewhere. Terms that are really about **licensing** or **RBAC** are kept
short here and point to `licensing-matrix.md` / `rbac-model.md` for the full treatment, this file
is the dictionary, those are the reference manuals.

**Module legend**

| Tag | Module |
|---|---|
| **DG** | Data Governance, Data Map, Unified Catalog, Data Quality, Lineage, Data Estate Insights |
| **IP** | Information Protection (sensitivity labels, auto-labeling, encryption) |
| **DLP** | Data Loss Prevention |
| **IRM** | Insider Risk Management |
| **AP** | Adaptive Protection |
| **DSPM** | Data Security Posture Management for AI |
| **CM** | Compliance Manager |
| **CC** | Communication Compliance |
| **eDisc** | eDiscovery (Standard + Premium) |
| **Audit** | Audit (Standard + Premium) |
| **DLM** | Data Lifecycle Management (retention) |
| **RM** | Records Management |
| **IB** | Information Barriers |
| **XC** | Cross-cutting, licensing, RBAC, automation, billing |

---

## 2. Glossary A, Z

### A

| Term | Module | Definition |
|---|---|---|
| **Activation window** | IRM | The rolling period (30 days by default, configurable) after a *triggering event* during which a user's risk score continues to be calculated. Risk calculation itself is retrospective and can look back up to 90 days of prior activity from the triggering event. |
| **Adaptive Protection** | AP | The Purview solution that dynamically raises or lowers DLP/label enforcement for a specific user based on their live Insider Risk Management risk level (e.g. auto-creating a DLP rule that blocks external sharing only for users at "elevated" risk). Inherits IRM + DLP prerequisites; no separate license SKU. |
| **Adaptive scope** | DLM, CC | A dynamic, query-based membership definition for a retention policy, retention label auto-apply policy, or Communication Compliance policy. The query re-runs daily against Microsoft Entra attributes/properties, so membership updates automatically as users join, leave, or change department, no manual list maintenance. Contrast with a **static scope** (fixed list of locations/users, "org-wide" or explicit include/exclude). Not supported for Skype for Business or Exchange public folders. |
| **Administrative unit (AU)** | XC | An Entra ID container that scopes a Purview role-group assignment to a subset of users, policies, and alert data, turning an unrestricted admin into a restricted one. Requires Entra ID P1/P2 on top of E5-tier Purview licensing. Full treatment: `rbac-model.md` §7. |
| **Advanced indexing** | eDisc | The reprocessing step that runs when custodial or non-custodial data sources are added to an eDiscovery (Premium) case, ensuring any partially indexed content becomes fully searchable before collection. |
| **Advanced resource sets** | DG | An opt-in Purview-instance-level feature that enriches resource-set assets with extra computed aggregations (partition counts, total size, schema counts) and resource-set pattern rules. Not offered in the current Unified Catalog billing model (the meter is zeroed out). |
| **Annotation** | DG | Metadata, glossary terms, classifications, associated with a Data Map asset. Annotations feed search relevance and aid discovery once applied. |
| **App-only authentication** | XC | The unattended-automation auth pattern (Entra app registration + certificate or managed identity, `-AppId`/`-CertificateThumbprint`) used by every `deploy/`/`validate/` script in this library to connect to Exchange Online / Security & Compliance PowerShell or Graph, instead of an interactive admin credential. Full treatment: `automation-surface.md`. |
| **Asset** | DG | Any single object stored in the Data Map or Unified Catalog (a table, file, Power BI report, or a **resource set** representing many partition files as one asset). For PAYG billing, a **governed asset** is an asset that has been explicitly linked to a business concept (data product, critical data element), an asset merely sitting in Data Map, unlinked, isn't billed. |
| **Audit (Standard / Premium)** | Audit | Standard = baseline unified audit log search (`Search-UnifiedAuditLog`), 180-day default retention. Premium = longer/configurable retention, high-value crucial events (mailbox access, search, etc.), and faster Office 365 Management Activity API access for forensic investigations. Requires an **Exchange Online RBAC role in addition to** a Purview Audit role group, see `rbac-model.md` §6. |
| **Auto-labeling** | IP | Policy-based automatic application of a sensitivity label (or a retention label, see **auto-apply retention label** under RM) when content matches defined conditions (SIT, trainable classifier, keyword). Can run in **simulation mode** (a `-WhatIf`-equivalent) before enforcement. Requires E5 (or IP&G add-on); PAYG applies for non-M365 sources. |

### B

| Term | Module | Definition |
|---|---|---|
| **Business concept** | DG | Collective term for the five Unified Catalog objects that provide business context: **governance domains**, **data products**, **glossary terms**, **critical data elements**, and **OKRs**. |

### C

| Term | Module | Definition |
|---|---|---|
| **Case** | eDisc | The central organizing unit of the eDiscovery workflow (both Standard and Premium). A case holds members, holds, searches, collections, and, in Premium, custodians and review sets. |
| **Classifier** | DG, IP | Umbrella term for the technology Purview uses to identify and categorize content: a **sensitive information type (SIT)** (pattern-based), a **trainable classifier** (example-based, ML), or an **EDM classifier** (exact-value lookup against a hashed reference table). |
| **Collection** | DG | An organization-defined grouping of Data Map assets, sources, and scans that provides a security boundary and a least-privilege access-control unit. The classic (pre-Unified Catalog) organizing structure; Unified Catalog's equivalent concept is the **governance domain**. |
| **Collection policy** | DSPM, DLP | An event-collection and filtering tool that ingests and classifies activity from apps and locations inside and outside the org's trust boundary (including AI-app prompts/responses) so downstream Purview solutions, Activity Explorer, IRM, eDiscovery, DLM, can act on it. Not to be confused with a Data Map **collection**. |
| **Communication Compliance** | CC | The Purview module that detects and helps remediate policy violations (harassment, threats, sensitive-info sharing, regulatory conduct such as FINRA 3110) across email, Teams, Copilot, Viva Engage, and select third-party channels. Built privacy-by-design: usernames are pseudonymized by default. |
| **Compliance boundary** | eDisc | An eDiscovery (Premium) configuration that restricts which content locations and cases a given eDiscovery Manager/Administrator can see and search. No separate license beyond eDiscovery Premium. |
| **Compliance Manager** | CM | The Purview module providing 360+ prebuilt **regulatory templates**, **assessments**, risk-based **compliance score**, and **improvement actions** to track and evidence an organization's compliance posture. Available on Office 365/M365 licenses including Business Premium and GCC/GCC-High/DoD; premium templates need E5/Suite. |
| **Compliance score** | CM | A risk-based percentage reflecting progress completing an assessment's improvement actions, weighted by points per action. |
| **Control** | CM | A requirement of a regulation/standard defining how system configuration, process, and people are assessed and managed to meet a specific regulatory obligation. Assessments group controls; improvement actions help satisfy them. |
| **Critical data element (CDE)** | DG | A logical grouping of important columns across sources that map to a single governed concept (e.g. mapping `CustID` and `CID` to one "Customer ID" CDE) requiring elevated governance attention. Currently in preview. |
| **Custodian** | eDisc | In eDiscovery (Premium), the individual whose content (mailbox, OneDrive, Teams data) is subject to search, hold, or review as part of a case. Distinct from the eDiscovery Manager/Administrator performing the investigation. |

### D

| Term | Module | Definition |
|---|---|---|
| **Data curator** | DG | The classic Data Map RBAC role granting create/read/modify/move/delete on assets and the ability to apply annotations and set up glossary terms. Unified Catalog's nearer equivalent is **Data Steward** (domain-scoped). |
| **Data governance processing unit (DGPU)** | XC | The PAYG compute meter for Unified Catalog **data quality** and **data health management** actions. One DGPU = 60 minutes of compute (Basic/Standard/Advanced performance tiers); consumption varies by rule complexity, data volume, and source type. See `licensing-matrix.md` §1-2. |
| **Data Map** | DG | The metadata repository/graph, populated via **scans**, that is the foundation of Purview data governance: asset descriptions, lineage, classifications, and technical/semantic relationships. Exposed via the Purview portal or Apache Atlas 2.2 APIs. |
| **Data product** | DG | A curated grouping of data assets (tables, files, Power BI reports) packaged with a defined business use case, ownership, and governance context, for discovery and controlled access. Lives inside a **governance domain**; the governed-asset PAYG meter is driven by assets linked into data products. |
| **Data reader** | DG | The classic Data Map RBAC role granting read-only access to assets, classifications, classification rules, collections, and glossary terms. |
| **Data risk assessment** | DSPM | An automated or custom scan (part of Data Security Posture Management) that identifies data-oversharing risk, primarily for SharePoint sites and Fabric workspaces. Default assessments run weekly against the top 100 sites by usage; results drive remediation (label-based restriction, auto-labeling, retention). |
| **Data security processing unit** | XC | The PAYG compute meter for processing non-M365 signals in Insider Risk Management and related Data Security solutions (distinct from the DGPU, which is Data Governance-specific). |
| **Data source admin** | DG | The classic Data Map RBAC role that can register/manage data sources and scans but has **no** Purview portal access on its own, combine with Data Reader or Data Curator at a collection scope for portal access. |
| **Data steward** | DG | The Unified Catalog governance-domain-scoped role responsible for curating assets, glossary terms, and relationships within a domain; required to create/edit/manage glossary terms. |
| **Disposition** | RM, DLM | The permanent-deletion event (or, when a reviewer is configured, the **disposition review** stage that precedes it) that occurs when a retention label's retention period expires with a `Delete` or `KeepAndDelete` action. Disposition can be exported for an auditable proof-of-deletion record. |
| **DLP policy / DLP rule** | DLP | A **DLP policy** defines where to monitor (locations) and what to protect (via included **DLP rules**, each specifying match conditions, SITs, labels, trainable classifiers, and protective actions: audit, policy tip, block-with-override, block, quarantine). DLP uses deep content analysis (regex, keyword proximity, function validation, ML), not simple text search. |

### E

| Term | Module | Definition |
|---|---|---|
| **eDiscovery (Standard)** | eDisc | Case management, search, export, and legal hold on top of Content Search. Requires E3 minimum. |
| **eDiscovery (Premium)** | eDisc | Adds custodian management, legal-hold notification workflow, advanced indexing, review sets, analytics (near-duplicate/theme detection, redaction), and predictive coding. Requires E5, Suite, or the E5 eDiscovery & Audit add-on. |
| **EDM (Exact Data Match) classifier** | IP, DLP | A custom sensitive information type that matches **exact values** from an uploaded, hashed (salted) reference table (up to 100M rows, refreshable daily) instead of matching a generic pattern, dramatically fewer false positives for structured data like customer/employee IDs. Composed of a primary element (mapped to a base SIT) plus optional supporting elements scored by proximity into a confidence level. |
| **Event-based retention** | DLM, RM | A retention label configuration where the retention clock starts on a defined event (e.g. "employee last day," "contract expiration") rather than on content creation, last-modified, or label-applied date. |

### F

| Term | Module | Definition |
|---|---|---|
| **File plan** | RM | The bulk-manageable view of retention labels used by Records Management, adding optional descriptors (citation name/URL, department, category/subcategory, authority type, reference ID) to track the regulatory or business justification behind each label. Supports CSV import/export for offline review. |
| **Full scan / Incremental scan** | DG | A **full scan** processes all in-scope assets at a source; an **incremental scan** (requires a prior full scan) processes only assets created, modified, or deleted since the last successful scan. |

### G

| Term | Module | Definition |
|---|---|---|
| **Governance domain** | DG | A boundary, Unified Catalog's core organizing construct, that enables common governance, ownership, and discovery of data products and other business concepts (glossary terms, OKRs, critical data elements). Types include functional-unit, line-of-business, data-domain, regulatory, and project domains. |

### H

| Term | Module | Definition |
|---|---|---|
| **Hold (legal hold)** | eDisc | Preservation of content in the locations associated with a case, preventing deletion/modification during an investigation. Can target specific content locations or be **query-based** (preserve only items matching a hold query). Optional but recommended immediately after case creation. |

### I

| Term | Module | Definition |
|---|---|---|
| **Improvement action** | CM | A recommended, individually assignable compliance activity, with implementation guidance, evidence storage, and (for Microsoft-managed actions) automatic testing, that contributes points toward completing a **control** inside an **assessment**. |
| **Information Barriers (IB)** | IB | The module that restricts two-way communication/collaboration (chat, calls, file access, people-picker visibility) between defined **segments** of users in Teams, SharePoint, and OneDrive, via **Block** or **Allow** policies. Primarily driven by FINRA-style conflict-of-interest requirements in financial services, but used across regulated industries. Does not restrict email (use Exchange mail flow rules for that). |
| **Insider Risk Management (IRM)** | IRM | The module that correlates Microsoft 365 and Microsoft Graph signals (plus optional third-party indicators) into a per-user **risk score**, driven by **risk indicators** and **risk factors**, to identify and act on potentially malicious or inadvertent insider activity (data theft, leaks, security-policy violations). Privacy-by-design: pseudonymized identities until an investigator is explicitly granted unmasking rights. |
| **Integration runtime** | DG | The compute infrastructure that executes a Data Map scan against a source: Azure-hosted, Managed Virtual Network, or **self-hosted integration runtime** (installed on-prem/in a private network for sources not reachable from Azure). |

### L

| Term | Module | Definition |
|---|---|---|
| **Label policy** | IP, RM, DLM | The publishing construct that makes a sensitivity label or retention label available to specified users/locations, or auto-applies it based on match conditions. Not to be confused with the label itself. |
| **Legal hold notification** | eDisc | The eDiscovery (Premium) workflow for communicating a hold to case **custodians**, initial notice, reminders, and escalations, with tracked acknowledgment status. |
| **Lineage** | DG | The captured history of how data transforms and flows from origin to destination across the data estate, surfaced in Data Map/Unified Catalog to support impact analysis and troubleshooting. |

### O

| Term | Module | Definition |
|---|---|---|
| **OKR (Objectives and Key Results)** | DG | A Unified Catalog business concept attached to a governance domain that expresses the measurable business value/goals of that domain's data products. |

### P

| Term | Module | Definition |
|---|---|---|
| **Pay-as-you-go (PAYG)** | XC | The Azure-consumption-metered billing model that extends Purview data security/governance capabilities beyond Microsoft 365 to non-M365 sources (AWS, Azure SQL, Box, Dropbox, Google Drive, Fabric) and to data-governance compute (DGPU). Took effect January 6, 2025. Full treatment: `licensing-matrix.md`. |
| **Priority content / priority user group** | IRM | **Risk factors** used by IRM policies: content explicitly designated as high-value/sensitive (priority content) and users explicitly designated as elevated-scrutiny (e.g. departing employees, executives) via a priority user group. Both increase a triggering event's contribution to risk score. |
| **Purview role group** | XC | A bundle of Purview RBAC roles assigned together for a job function (e.g. *Insider Risk Management Investigators*). The unit you assign membership to, you almost never assign individual roles directly. Full treatment: `rbac-model.md` §2-4. |

### R

| Term | Module | Definition |
|---|---|---|
| **Record / regulatory record** | RM | A **record** is an item marked by a retention label with `IsRecordLabel = TRUE`, which blocks deletion (and most edits) outside the disposition process. A **regulatory record** additionally locks the label itself against removal, downgrade, or shortened retention, used for the strictest legal/regulatory retention obligations. |
| **Regulation** | CM | A rule or requirement imposed by a governing authority (law, industry standard, or framework) that Compliance Manager models as a **template** for building assessments; 360+ are provided out of the box, and custom regulation templates can be authored for unmapped requirements. |
| **Retention label / retention policy** | DLM, RM | A **retention label** is applied at the item level (manually, automatically, or via file plan/event) and carries its own retention duration, disposition action, and optional record declaration. A **retention policy** applies a baseline retention/deletion setting at the location level (mailbox, site, Teams) without per-item labeling. Both support adaptive or static scopes. |
| **Review set** | eDisc | In eDiscovery (Premium), a secure, Microsoft-managed Azure Storage location that holds a static, filterable, taggable copy of content committed from a search/collection, the workspace for analysis, redaction, and export. |
| **Risk factor** | IRM | A signal that contributes to a user's risk score during their **activation window**: *cumulative exfiltration activities*, *activities include priority content*, *sequence activities* (a suspicious ordered pattern, e.g. label-downgrade followed by an external-share attempt), *activities include unallowed domains*, *member of a priority user group*, and *potential high impact user*. |

### S

| Term | Module | Definition |
|---|---|---|
| **Scan / scan rule set** | DG | A **scan** is the Data Map process that connects to a registered source, extracts metadata, captures lineage, and applies classifications. A **scan rule set** determines which file types/classifications a given scan looks for; sources have system default rule sets that can be customized. |
| **Segment** | IB | A named set of users or groups, defined by Entra ID attributes (department, job title, location, team, etc.), that is the unit an Information Barriers policy applies to. Up to 5,000 segments per org (10 per user) outside legacy mode; 250 segments (1 per user) in legacy mode. |
| **Sensitive information type (SIT)** | IP, DLP | A pattern-based classifier, built-in or custom, that detects sensitive content via regular expression, keyword evidence, character proximity, and confidence level (High/Medium/Low). The foundational classifier referenced by DLP rules, auto-labeling conditions, and auto-apply retention conditions. |
| **Sensitivity label** | IP | A label, managed in the Purview portal, that marks an item's confidentiality and can carry enforceable protection (encryption, access restriction, visual marking/watermark, container/site settings). Interacts with DLP (as a match condition), IRM/Adaptive Protection (label-downgrade as a risk signal), and DLM/RM (label-based auto-apply retention). Manual application needs E3; auto-labeling needs E5 or the IP&G add-on. |

### T

| Term | Module | Definition |
|---|---|---|
| **Trainable classifier** | DG, IP | A classifier trained on example content (rather than pattern matching) to recognize what an item *is*, a resume, a source-code file, a contract, even when it lacks a matchable pattern. Usable across DLP, auto-labeling, and auto-apply retention conditions. |

### U

| Term | Module | Definition |
|---|---|---|
| **Unified audit log** | Audit | The central Microsoft 365 activity log searched via the Purview Audit UI or `Search-UnifiedAuditLog`; the data source behind DLP reports, IRM signals, and most compliance investigations. Requires an Exchange Online RBAC role in addition to a Purview Audit role, see `rbac-model.md` §6. |
| **Unified Catalog** | DG | The current Purview data governance experience: a searchable inventory of assets plus a business glossary, organized by governance domains and data products, superseding the classic Data Catalog/Business Glossary experience for new deployments. |

---

## 3. How scenarios should cite this glossary

- Use these terms **verbatim** in every scenario `README.md`/`design.md`, do not introduce a
 synonym (e.g. always "retention label," never "retention tag").
- The first use of a term in a scenario document may link back to the relevant anchor in this
 file (`[Glossary](/docs/glossary/)#<letter>`) instead of re-explaining it inline.
- If a scenario needs a term specific to a single Microsoft Learn page and not yet covered here,
 add it to this file (grounded, with a source) in the same fragment as the scenario, rather than
 defining it locally and risking drift.

---

## Sources (Microsoft Learn, re-verify before quoting)

- Microsoft Purview data governance glossary (official A, Z glossary), <https://learn.microsoft.com/purview/data-governance-glossary>
- Compliance Manager glossary, <https://learn.microsoft.com/purview/compliance-manager-glossary>
- Application card: Microsoft Purview Unified Catalog (key terms), <https://learn.microsoft.com/purview/unified-catalog-application-card>
- Application card: Data Security Posture Management (key terms), <https://learn.microsoft.com/purview/data-security-posture-management-application-card>
- Governance domains in Unified Catalog, <https://learn.microsoft.com/purview/unified-catalog-governance-domains>
- Get started with Microsoft Purview data governance (business concepts), <https://learn.microsoft.com/purview/data-governance-get-started>
- Manage domains and collections in Data Map, <https://learn.microsoft.com/purview/data-map-domains-collections-manage>
- Learn about data loss prevention, <https://learn.microsoft.com/purview/dlp-learn-about-dlp>
- Learn about exact data match based sensitive information types, <https://learn.microsoft.com/purview/sit-learn-about-exact-data-match-based-sits>
- Learn about Insider Risk Management, <https://learn.microsoft.com/purview/insider-risk-management>
- Investigate Insider Risk Management activities (risk factors), <https://learn.microsoft.com/purview/insider-risk-management-activities>
- Managing insider risk for the Australian Government (Adaptive Protection, activation window), <https://learn.microsoft.com/compliance/anz/pspf-insider-risk>
- Learn about eDiscovery / eDiscovery workflow, <https://learn.microsoft.com/purview/edisc>, <https://learn.microsoft.com/purview/edisc-workflow>
- Microsoft Purview eDiscovery legacy solutions (Standard vs. Premium capability comparison), <https://learn.microsoft.com/purview/ediscovery>
- Learn about records management / Use file plan, <https://learn.microsoft.com/purview/records-management>, <https://learn.microsoft.com/purview/file-plan-manager>
- Learn about retention policies and retention labels (adaptive/static scopes), <https://learn.microsoft.com/purview/retention>
- Adaptive scopes, <https://learn.microsoft.com/purview/purview-adaptive-scopes>
- Learn about Information Barriers / Get started with Information Barriers, <https://learn.microsoft.com/purview/information-barriers>, <https://learn.microsoft.com/purview/information-barriers-policies>
- Microsoft Purview Compliance Manager (controls, assessments, regulations, improvement actions), <https://learn.microsoft.com/purview/compliance-manager>
- Microsoft Purview data compliance solutions, <https://learn.microsoft.com/purview/purview-compliance>
- Microsoft Purview data security solutions, <https://learn.microsoft.com/purview/purview-security>
- Learn about Microsoft Purview billing models (PAYG units of measure, DGPU, processing units, assets), <https://learn.microsoft.com/purview/purview-billing-models>
- Learn about data governance billing (DGPU explained, governed assets), <https://learn.microsoft.com/purview/data-governance-billing>
- Microsoft Purview service description, <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>

> **Disclaimer:** terminology evolves as Purview ships updates (the ongoing Unified Catalog /
> classic governance-portal transition is the current example). Validate a term against the live
> Purview portal UI and current Microsoft Learn content before using it in a customer-facing
> deliverable.
