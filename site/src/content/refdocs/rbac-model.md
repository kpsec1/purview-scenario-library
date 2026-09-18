---
title: "Microsoft Purview, RBAC / Roles & Permissions Model"
name: "RBAC model"
---
> **Cross-cutting reference.** Every scenario in this library links here instead of restating
> permissions. Read this once to understand *which* role unlocks *which* task, and which of the
> **four separate RBAC systems** a given Purview capability actually uses.
>
> **Verify before you provision access.** Role names, default assignments, and role-group
> membership change frequently. This matrix is a practitioner's summary grounded in Microsoft
> Learn, current as of **2026-09-16**. Sources are linked at the bottom; re-check them before
> granting production access.

---

## 1. Four RBAC systems, not one (read this first)

A Purview deployment touches **four distinct permission models**. Confusing them is the single
biggest cause of "why can't this user do X" tickets.

| # | System | Where it's managed | Governs |
|---|---|---|---|
| **1** | **Microsoft Entra ID roles** | Entra admin center / `Microsoft Graph` | Tenant-wide admin roles (Global Administrator, Compliance Administrator, Security Administrator, AI Administrator...). Several map automatically into Purview role groups (§3). |
| **2** | **Microsoft Purview role-based access control (RBAC)**, role groups & roles | Purview portal → **Settings → Roles and scopes** (`purview.microsoft.com`), or Security & Compliance PowerShell (`Get-RoleGroup`/`New-RoleGroupMember`) | Data security (DLP, Information Protection, Insider Risk, Communication Compliance, DSPM for AI), risk & compliance (eDiscovery, Audit, Compliance Manager, Records Management, Information Barriers, Data Lifecycle Management). This is the model covered in most of §2, §4 below. |
| **3** | **Data Map / Unified Catalog governance roles** | Purview portal → governance domain **Roles** tab, or the classic governance portal's **Collections** | Data Governance: Data Map collections, Unified Catalog governance domains, data products, glossary, data health. A **separate** role model from #2, see §5. |
| **4** | **Exchange Online RBAC** | Exchange admin center / Exchange Online PowerShell (`Get-ManagementRoleAssignment`) | Workload-level actions Purview doesn't cover: mail flow rules (transport rules), mailbox permissions, and, critically, **audit log search requires an Exchange Online role**, not just a Purview one (see §6 note). |

> Managing permissions in the Purview portal (#2) does **not** grant Exchange, SharePoint, or
> Entra permissions. Conversely, being a Global Administrator (#1) does not automatically show
> up as a member in `Get-RoleGroupMember` output for Organization Management, Global Admins are
> auto-added but hidden from that view.

---

## 2. Purview RBAC building blocks: members → roles → role groups

- A **role** grants permission to perform a set of tasks (e.g. *DLP Compliance Management* lets
 you view/edit DLP policies; *RecordManagement* lets you configure records management).
- A **role group** is a bundle of roles assigned together for a job function (e.g. *Insider Risk
 Management Investigators*).
- **Members** (users, mail-enabled security groups, commercial cloud only) are added to role
 groups. You almost never assign individual roles directly; you assign the role group.
- Custom role groups can be created for least-privilege combinations not covered by a built-in
 group. **Assign admin units** is available on any custom role group (§7).

**Prerequisite to manage role groups at all:** the *Role Management* role, assigned by default
only to **Organization Management** and **Purview Administrators**.

---

## 3. Microsoft Entra roles that map into Purview

| Entra role | What it unlocks in Purview | Mapped Purview role group(s) |
|---|---|---|
| **Global Administrator** | Full administrative access to all Purview solutions | Data Catalog Curators · Data Estate Insights Readers · Organization Management · Purview Administrators |
| **Compliance Data Administrator** | Track/protect org data, insights into risk issues | Compliance Data Administrator |
| **Global Reader** | Read-only across all Purview settings and reports | Global Reader |
| **Security Administrator** | Security policy management, analytics, reports | Security Administrator |
| **Security Operator** | Investigate/respond to active threats | Security Operator |
| **Security Reader** | Read-only threat investigation | Security Reader |
| **AI Administrator** | Read-only DSPM for AI (classic) + AI Security Dashboard; no prompt/response content | AI Administrators |
| **Compliance Administrator** (Entra) | View/edit compliance feature settings and reports | Compliance Administrator |

> **Least privilege:** Microsoft explicitly recommends minimizing Global Administrator
> assignments and using the narrowest role that covers the job (least-privilege best practice).
> For most scenarios in this library, a **Purview role group** (§4) is the correct grant, reach
> for an Entra admin role only when the task is genuinely tenant-wide identity administration.

---

## 4. Purview role groups by module (representative, not exhaustive)

Legend: role groups shown are the **primary** ones for day-to-day operation of that module. Each
module has narrower variants (Admins / Analysts / Investigators / Viewers / Readers) for
separation of duties, pick the narrowest that covers the task. Full list: §9 source 1.

| Module | Role groups (narrowest → broadest) | Notes |
|---|---|---|
| **Information Protection** (labels, DLP-adjacent classification) | Information Protection Readers → Analysts → Investigators → Admins → **Information Protection** (full control) | *Information Protection Admin* role: create/edit/delete DLP policies, labels, classifiers; manage endpoint DLP and auto-labeling simulation mode |
| **DLP** | Covered by the Information Protection groups above (**DLP Compliance Management** role) | *View-Only DLP Compliance Management* for read-only; policy creation needs *DLP Compliance Management* |
| **Insider Risk Management** | Insider Risk Management Auditors → Analysts → Investigators → Admins → **Insider Risk Management** (all-in-one) | Analysts can't access Content Explorer; Investigators can. *Insider Risk Management Approvers*/*Session Approvers* are narrow, workflow-only groups |
| **Adaptive Protection** | Inherits IRM + Information Protection role groups, no separate role group | Requires both IRM admin/analyst access **and** DLP policy-author access to configure risk-based enforcement |
| **DSPM for AI** | Data Security AI Viewers → Data Security AI Content Viewers (prompt/response) → Data Security AI Admins; broader posture: **AI Administrators**, **Compliance Administrator** role group | *Data Security AI Content Viewer* is the only role that can read prompts/responses, assign narrowly |
| **Communication Compliance** | Communication Compliance Viewers → Analysts → Investigators → Administrators → **Communication Compliance** (all-in-one) | Analysts see metadata only; Investigators see full message content, separation of duties matters here for privacy |
| **eDiscovery (Standard + Premium)** | **eDiscovery Manager** (own/member cases only) vs. **eDiscovery Administrator** (all cases org-wide, same role group with extra scope) → **Reviewer** (review-set-only, no search/case mgmt) | eDiscovery Administrator = eDiscovery Manager member additionally granted org-wide case visibility, not a separate role group. **Two granular roles matter for a least-privilege automation identity**, both already included in eDiscovery Manager/Administrator: **Compliance Search** (create/run a search) and **Search And Purge** (permanently delete matched items, "the least privileged option for purging data," available by default only to **Organization Management** members). A custom role group granting just these two (+ Case Management, to create the case/search) lets a search-and-purge automation service principal run without full case-management or org-wide visibility. See `scenarios/ediscovery/search-and-purge-data-spillage/README.md` §3 |
| **Audit (Standard + Premium)** | Audit Reader (View-Only Audit Logs) → **Audit Manager** (configure + search + export) | See §6: also requires an Exchange Online role to actually run `Search-UnifiedAuditLog`. **Audit log retention policies are a separate grant, not covered by Audit Manager**: creating/editing them needs the **Organization Configuration** role, confirmed included by default in the **Compliance Data Administrator** role group; Audit Manager's own default roles are limited to Audit Logs/View-Only Audit Logs. An org's existing Audit Manager assignees cannot manage retention policies without this additional role. See `scenarios/audit/retention-policy-management/README.md` §3 |
| **Data Lifecycle Management** | Priority Cleanup Viewer/Admin (org-wide meta) → **Records Management** role group (Retention Management, Scope Manager roles) | Same role group also governs Records Management (below), split by task, not by separate group. **Priority cleanup's approver model differs by workload**: Exchange requires three distinct individuals, one per stage (Priority Cleanup Admin+Data Classification Content/List Viewer+Disposition Management; Retention Management+the same 3; Search And Purge+Hold+Review+the same 3); SharePoint/OneDrive requires only a second Priority Cleanup Admin (Priority Cleanup Admin+Data Classification Content/List Viewer+**Retention Management**, note the different third role) plus a conditional eDiscovery Admin approval (Search And Purge+Hold+Review+Data Classification Content/List Viewer+Disposition Management) that's only required if the item is under an eDiscovery hold, no separate retention-manager approver for this workload. Policy creation fails if any named approver lacks their stage's roles. See `scenarios/data-lifecycle-management/priority-cleanup-exchange-data-spillage/README.md` §3 and `scenarios/data-lifecycle-management/priority-cleanup-sharepoint-onedrive/README.md` §3 |
| **Records Management** | **Records Management** role group (RecordManagement, Retention Management, Disposition Management, Scope Manager roles) | |
| **Information Barriers** | **Compliance Administrator** / **Compliance Data Administrator** / **Organization Management** / **Security Administrator** (IB Compliance Management role), no dedicated IB role group | View-only variant: *View-Only IB Compliance Management*, held by the same groups plus Global Reader/Security Reader |
| **Compliance Manager** | Compliance Manager Readers → Contributors → Assessors → **Compliance Manager Administrators** | Template creation/modification needs Administrators; assessment work needs only Contributor/Assessor |
| **Privacy Management / Subject Rights Requests** | Privacy Management Viewers → Analysts → Investigators → Contributors → **Privacy Management Administrators**; **Subject Rights Request Administrators** / **Approvers** | Out of this library's default scope (Priva-adjacent), see `AGENTS.md` §2 assumption |
| **Data Security Investigations** | **Data Security Investigations** Reviewers → Investigators → **Admins** (three dedicated role groups; note the group names are plural "Investigations," distinct from the singular "Data Security Investigation Admin/Contributor" *role* each grants) | AI-assisted post-breach/insider-leak triage spanning Defender XDR, Insider Risk Management, and DSPM-sourced investigations. Compliance Administrator/Organization Management/Data Security Management/Insider Risk Management role groups also carry implicit DSI access, see `scenarios/data-security-investigations/post-breach-investigation-and-purge/README.md` §3 for the full matrix (only Admins/Investigators can purge; Reviewers cannot) |

---

## 5. Data governance roles (Data Map + Unified Catalog), a separate model

Data Governance does **not** use the role groups in §4. It has its own three-tier model:

| Tier | Role | Grants |
|---|---|---|
| **Tenant** | **Data Governance** role group (Data Governance Administrator role) | Delegates first-level access to create Governance Domain Creators; not itself surfaced inside Unified Catalog UI |
| Tenant | **Data Source Administrators** role group | Manage data sources and scans in Data Map |
| Tenant | **Purview Administrators** role group | Create/edit/delete domains, perform role assignments (Purview Domain Manager + Role Management roles) |
| **Catalog** | **Governance Domain Creator** | Create governance domains; becomes domain owner by default |
| **Governance domain** | **Governance Domain Owner** | Edit an existing domain (name, description, status, parent, custom attributes, data estate mapping), required for any *edit*, distinct from the catalog-level Creator role needed to make a *new* domain; assigned automatically to whoever creates the domain, and to anyone added on the domain's **Roles** tab |
| Catalog | **Global Catalog Reader** vs. **Local Catalog Reader** | Global = read published concepts across *all* domains without a local reader override; Local = restricts read access to one domain (use for regulatory/legal segregation, overuse defeats federated governance) |
| Catalog | **Data Health Owner** / **Data Health Reader** | Create/edit vs. read-only on Health management (controls, data quality rules, actions, reports) |
| Catalog | **Global Asset Curator** | Attach published glossary terms to assets/columns across domains |
| **Governance domain** | **Data Product Owner** | Create/update/read data products within their domain only |
| Governance domain | **Data Steward**, domain-scoped roles | Curate assets, glossary terms, relationships within the domain (assigned per-domain on the domain's **Roles** tab) |

**Classic Data Map / governance portal** (pre-Unified Catalog, still used for raw collection
management) uses a *different* role vocabulary again: **Collection administrator**, **Data
curator**, **Data reader**, **Data source administrator**, **Insights reader**, **Policy
author**, **Workflow administrator**. Collection admins assign these per-collection; a
collection admin on the **root collection** also gets Purview governance-portal access.

> **Rule of thumb:** "just need to find/browse data" → Data/Global Catalog Reader or classic
> Data reader. "Need to edit metadata, glossary, or data products" → Data Curator (classic) or
> Data Product Owner/Steward (Unified Catalog). "Need to register sources and run scans" → Data
> Source Administrator (both models use this same role group name).

---

## 6. Exchange Online dependency (the most common permissions gap)

Several Purview-portal actions look complete in the UI but silently fail (or return partial
data) without a matching **Exchange Online** role, because the underlying cmdlet is an Exchange
cmdlet:

- **Audit log search** (`Search-UnifiedAuditLog`) and any report containing Exchange data (DLP
 reports, Defender for Office 365 reports) require an **Exchange Online** role, Global Admins
 get this for free via automatic Organization Management membership in Exchange Online itself;
 everyone else needs an explicit Exchange RBAC role/role group in addition to their Purview one.
- **Compliance Administrator** and **Organization Management** (the Purview role groups) are
 explicitly flagged by Microsoft as **not** sufficient on their own for audit log search or
 Exchange-data reports (footnote ¹ on the role-groups reference, source 1).
- **Mail flow rules (transport rules), mailbox-level permissions**, manage in the Exchange admin
 center (`admin.exchange.microsoft.com`), not the Purview portal.
- **Authentication Policies** (`New-/Set-/Get-/Remove-AuthenticationPolicy`,
 `Set-OrganizationConfig -DefaultAuthenticationPolicy`, `Set-TransportConfig`/`Set-CASMailbox
 -SmtpClientAuthenticationDisabled`), a pure Exchange Online RBAC surface, no Purview role
 involved at all. **Organization Management** is confirmed sufficient; Microsoft's own cmdlet
 reference pages don't name a narrower least-privilege role for this specific surface, see
 `scenarios/adaptive-protection/exchange-legacy-auth-block/README.md` §11.

Every scenario that touches Audit or exports Exchange-sourced report data should call this out
explicitly in its Prerequisites section.

---

## 7. Administrative units, scoping Purview RBAC to a region/department

[Administrative units (AUs)](https://learn.microsoft.com/entra/identity/role-based-access-control/administrative-units)
are an **Entra ID** construct that Purview role groups can be scoped to, turning an
"unrestricted administrator" into a **restricted administrator** who can only see/manage
users, policies, and alert data within their assigned unit(s).

- **Prerequisites:** Entra ID **P1 or P2** licensing, *plus* Purview licensing at E5/A5/G5 tier
 (or the Compliance/IP&G/Insider-Risk-Management add-ons, see `licensing-matrix.md`).
- **Assignable to:** Communication Compliance (+ Admins/Analysts/Investigators), Compliance
 Administrator, Compliance Data Administrators, Global Reader, Information Protection (+
 Admins/Analyst/Investigators/Readers), Insider Risk Management (+ Admins/Analysts/
 Investigators/Approvers), Organization Management, Records Management, Security
 Administrator/Operator/Reader.
- **Flows down to:** DLP alerts, activity explorer, adaptive scopes, audit-log search scoping,
 Communication Compliance policy lookup/config, Data Lifecycle/Records disposition review,
 Insider Risk policy lookup/config/alerts/cases.
- **Supported Purview solutions for full config (not just role scoping):** Data Lifecycle
 Management, DLP, Communication Compliance, Insider Risk Management, Records Management,
 Sensitivity labeling (auto-labeling + label policies). SharePoint sites can now be added as AU
 members (Information Protection auto-labeling and DLP policies only).
- **Gotcha:** assigning an AU to an existing unrestricted admin makes their previously-visible
 policies invisible to them going forward (the policies keep running, an unrestricted admin can
 still see/edit them). Plan AU rollout as an additive change, not a retrofit onto admins who
 already manage org-wide policies.
- **Required role to assign AUs:** *Role management* role (Organization Management / Purview
 Administrators by default).

---

## 8. PowerShell & Graph automation, connecting with the right role

All PowerShell code in this library authenticates using one of two Exchange-Online-hosted
endpoints, gated by the RBAC systems above, never with a hard-coded credential:

| Endpoint | Module | Cmdlet | What it needs |
|---|---|---|---|
| Exchange Online PowerShell | `ExchangeOnlineManagement` | `Connect-ExchangeOnline` | An Exchange Online RBAC role (mailflow rules, recipients, audit search) |
| Security & Compliance PowerShell | `ExchangeOnlineManagement` (same module, different endpoint) | `Connect-IPPSSession` | A Purview role group with the relevant role (DLP, retention, IRM, eDiscovery, etc.) |

- **Interactive/admin use:** `Connect-ExchangeOnline` / `Connect-IPPSSession` with the signed-in
 user's own MFA-backed credential, RBAC is enforced per-command against that user's role
 assignments.
- **Unattended automation (what this library's `deploy/`/`validate/` scripts assume):**
 **app-only authentication**, register an Entra app registration, assign it either a built-in
 Exchange/Purview role (Entra app role assignment) or a **custom role group** containing only
 the roles the automation needs, then connect with `-AppId`/`-CertificateThumbprint` (or a
 managed identity). Never embed client secrets in scripts, use certificate-based auth or Azure
 Key Vault, resolved credentials, and prefer the narrowest custom role group over inheriting an
 interactive admin's role group membership.
- **Microsoft Graph automation** (Data Map/Unified Catalog scans, Entra AU management, some
 DSPM-for-AI surfaces) uses standard Graph app permissions (least-privilege application
 permissions on the app registration), separate again from Exchange/Purview RBAC, grant only
 the specific Graph scopes a script needs (e.g. `Purview-DataGovernance.*` scopes for Data Map
 API calls; VERIFY: exact Graph permission names per data-governance API endpoint used, as the
 Data Map/governance Graph API surface is evolving).
- Finding the exact permission a given cmdlet needs: `Find-Exchange cmdlet permissions`
 guidance in source 6 below, use it before assuming a role group is broad enough.

---

## 9. Microsoft Intune RBAC, a fifth system, for Intune-deployed scenarios

The four systems in §1 cover every Purview-portal capability, but two scenarios in this library, 
`scenarios/dlp/defender-device-control-usb-allowlist/` and its `-wpd-coverage` sibling, don't
create a Purview policy object at all. They deploy Microsoft Defender for Endpoint device control
through an **Intune** device configuration profile ([Licensing matrix §7](/docs/licensing-matrix/#7-adjacent-product-family-microsoft-defender-for-endpoint--intune-device-control-scenarios)), which uses a
genuinely separate, fifth RBAC model: managed in the **Intune admin center → Tenant administration
→ Roles**, not the Purview portal's **Settings → Roles and scopes**.

- **Built-in role that covers device control:** **Policy and Profile Manager**, "Manages
 compliance policy, configuration profiles, Apple enrollment, Android Enterprise enrollment
 profiles, corporate device identifiers, and security baselines." Its permission set includes
 **Device configurations: Create / Read / Update / Delete / Assign / View Reports**, the exact
 grant both device-control scenarios' `windows10CustomConfiguration` Custom OMA-URI profiles
 need. Narrower built-in roles (**Read Only Operator**, **Help Desk Operator**) can *read* these
 profiles but not create or update them.
- **Other built-in Intune roles**, for context (Intune doesn't order these narrowest→broadest the
 way Purview role groups are tiered, each is scoped to a different job function): Application
 Manager, Endpoint Privilege Manager/Reader, Endpoint Security Manager, Help Desk Operator,
 **Intune Role Administrator** (the only Intune role that can itself assign permissions to other
 admins), Read Only Operator, School Administrator, plus **Cloud PC Administrator/Reader** in
 tenants with Windows 365. Custom roles can combine any permission for a least-privilege fit
 Microsoft's built-in roles don't cover.
- **Microsoft Entra roles that also carry Intune access**, a documented *subset* relationship
 (these roles grant Intune permissions in addition to their normal Entra scope; they are not
 additional Intune role assignments):

 | Entra role | All Intune data | Intune audit data |
 |---|---|---|
 | Global Administrator | Read/write | Read/write |
 | Intune Administrator (appears as **Intune Service Administrator** in Graph/PowerShell) | Read/write | Read/write |
 | Security Administrator | Read only (full admin for the Endpoint Security node) | Read only |
 | Security Operator / Security Reader | Read only | Read only |
 | Compliance Administrator / Compliance Data Administrator | None | Read only |
 | Global Reader | Read only | Read only |
 | Helpdesk Administrator (equivalent to the Intune **Help Desk Operator** role) | Read only | Read only |
 | Reports Reader | None | Read only |
 | Conditional Access Administrator | None | None |

 Microsoft explicitly recommends **against** using Global Administrator or Intune Administrator
 for day-to-day Intune management, both are classified **privileged roles** and exceed what
 almost any routine task needs. Use **Policy and Profile Manager** (or a custom role) instead, 
 the same least-privilege principle §3 already states for Entra-role-to-Purview mapping.
- **App-only automation (Microsoft Graph):** both device-control scenarios' `deploy/` scripts
 authenticate as a Graph app registration rather than an interactive admin, and need the
 **`DeviceManagementConfiguration.ReadWrite.All`** application permission (admin consent
 required) to create/update `windows10CustomConfiguration` objects, confirmed as the permission
 Microsoft Graph's own `Update-MgDeviceManagement` / `Get-MgDeviceManagementDeviceConfiguration`
 PowerShell reference pages list for this resource type. Grant only this permission, not the
 similarly-named `DeviceManagementServiceConfig.*` or `DeviceManagementApps.*` permissions, which
 cover different Intune resource families, the same least-privilege rule §8 states for
 Purview/Exchange Graph scopes applies equally here.
- **Licensing is tracked separately:** holding the Graph permission or the Policy and Profile
 Manager role does not itself grant the Intune/Defender for Endpoint license a device needs to be
 managed, see [Licensing matrix §7](/docs/licensing-matrix/#7-adjacent-product-family-microsoft-defender-for-endpoint--intune-device-control-scenarios).

---

## 10. Microsoft Entra Conditional Access, a sixth system, for identity-layer scenarios

`scenarios/adaptive-protection/conditional-access-insider-risk-block/` is the first scenario in
this library that authors a **Microsoft Entra Conditional Access** policy rather than a Purview
policy object or an Intune device configuration profile. Conditional Access is administered
entirely in the **Microsoft Entra admin center**, a genuinely separate, sixth RBAC model from the
four in §1 and from Intune's own model in §9, not a Purview role group, and not one of the
Intune roles either. `scenarios/adaptive-protection/conditional-access-insider-risk-step-up-auth/`
and `scenarios/adaptive-protection/block-legacy-authentication/` reuse this same model
unchanged, the **role** and **Graph permission** requirements below apply identically across all
three; only the **license** each scenario's specific condition needs differs (§8 for the two P2-
gated scenarios, [Licensing matrix §9](/docs/licensing-matrix/#9-adjacent-product-family-microsoft-entra-id-p1-baseline-conditional-access-block-legacy-authentication) for `block-legacy-authentication`'s P1-only floor).

- **Built-in Entra role that covers Conditional Access authoring:** **Conditional Access
 Administrator**, can create, edit, and delete Conditional Access policies. This is the role
 Microsoft's own documented procedure for the Insider Risk condition specifically names as the
 minimum needed to create that policy.
- **Least privilege still applies:** Microsoft explicitly recommends against using **Global
 Administrator** or **Security Administrator** for routine Conditional Access authoring, 
 **Conditional Access Administrator** is the narrowest built-in role that covers it, the same
 least-privilege principle §3 and §9 already state for Entra-role and Intune-role assignment.
- **This role does not grant any Purview access.** A Conditional Access Administrator cannot
 configure Adaptive Protection settings or insider risk levels, that remains the **Insider Risk
 Management**/**Insider Risk Management Admins** Purview role group (§4), a deliberately separate
 grant on a separate admin surface, exactly as `conditional-access-insider-risk-block/README.md`
 §3 documents.
- **App-only automation (Microsoft Graph):** the scenario's `deploy/` scripts authenticate as a
 Graph app registration and need the **`Policy.ReadWrite.ConditionalAccess`** and
 **`Policy.Read.All`** application permissions (admin consent required, least-privileged per
 Microsoft's own documented permissions table for creating/updating a `conditionalAccessPolicy`)
, the same least-privilege rule §8 and §9 already state for Purview/Exchange and Intune Graph
 scopes applies equally here.
- **Licensing is tracked separately, again:** holding the role or the Graph permission does not
 itself grant the license entitlement every user in a Conditional Access policy's scope needs for
 the policy's specific condition to apply, **Microsoft Entra ID P2** for a premium condition
 like Insider Risk ([Licensing matrix §8](/docs/licensing-matrix/#8-adjacent-product-family-microsoft-entra-id-p2-conditional-access-risk-based-conditions)), or the lower **Microsoft Entra ID P1** floor
 for `block-legacy-authentication`'s non-risk-based condition ([Licensing matrix §9](/docs/licensing-matrix/#9-adjacent-product-family-microsoft-entra-id-p1-baseline-conditional-access-block-legacy-authentication)).
 Don't assume every Conditional-Access-based scenario in this library needs P2 just because the
 first two did.

---

## 11. Microsoft Entra app registration RBAC, a seventh system, for scenarios that create their own app registrations

`scenarios/insider-risk/departing-employee-data-theft/deploy/Register-HrConnectorApp.ps1` is the
first scenario in this library whose own script *creates* a Microsoft Entra app registration
(rather than merely authenticating as one that already exists), a genuinely separate concern
from the six systems in §1/§9/§10, which all govern access to an *existing* resource, not the
right to mint a new application identity in the first place.

- **By default, no special role is needed.** Microsoft Entra ID's **Users can register
 applications** tenant setting defaults to **Yes**, every member user can register an app and
 manage every aspect of the apps they create, with no role assignment required. Most tenants
 running this scenario for the first time will hit this default case.
- **If a tenant has locked this down** (`Users can register applications` = **No**, typically
 alongside restricting user consent), the narrowest built-in role that restores the ability is
 **Application Developer**, it can create application registrations independent of that
 setting, and the creator is automatically added as the app's first owner. This is the correct,
 least-privilege choice for a one-off or occasional bootstrap task like
 `Register-HrConnectorApp.ps1`, the same least-privilege principle §3, §9, and §10 already
 state for Entra-role, Intune-role, and Conditional-Access-role assignment.
- **Broader roles exist but are unnecessary here:** **Cloud Application Administrator** and
 **Application Administrator** can create and manage *all* app registrations and enterprise
 apps tenant-wide (the latter also manages Application Proxy), both are privileged roles
 intended for admins who administer every application in the tenant, not for running a single
 scenario's bootstrap script. Neither role is added as an app's owner automatically the way
 **Application Developer** is. Don't reach for either just to run
 `Register-HrConnectorApp.ps1`.
- **The operation itself needs `Application.ReadWrite.All`** (delegated), the Microsoft Graph
 scope `Register-HrConnectorApp.ps1` requests via `Connect-MgGraph -Scopes
 'Application.ReadWrite.All'`, an interactive, human-run session, not a standing app-only
 credential. Microsoft's own permissions tables for `New-MgApplication`,
 `New-MgServicePrincipal`, and `Add-MgApplicationPassword` all name this as their
 least-privileged delegated permission.
- **This role/scope does not itself grant any Purview access**, the same separation-of-concerns
 point §9 and §10 make for Intune and Conditional Access: a user who can register Entra
 applications cannot configure Insider Risk Management policies or the HR connector object
 those applications authenticate, that remains the **Insider Risk Management**/**Insider Risk
 Management Admins** Purview role group and the **Data Connector Admin** role respectively
 (`scenarios/insider-risk/departing-employee-data-theft/README.md` §3).
- **Important caveat Microsoft documents explicitly:** any of these roles/permissions can add
 credentials to *any* application in their scope and use them to impersonate that application's
 identity, if the application has been granted access to a resource, an admin holding one of
 these roles could act through it. This is exactly why
 `scenarios/insider-risk/departing-employee-data-theft/README.md` §3 requires the HR-connector
 app to stay permission-free: there is nothing of value to impersonate into.

## 12. Microsoft Defender for Endpoint portal RBAC, an eighth system, for scenarios that configure Defender for Endpoint tenant-wide settings

`scenarios/insider-risk/security-policy-violations-by-departing-users/README.md` §5 Step 2 requires
toggling **Share endpoint alerts with Microsoft Compliance Center** on the Microsoft Defender
portal's **Settings → Endpoints → Advanced features** page, a tenant-wide Defender for Endpoint
setting, not a Purview policy object, an Intune profile, a Conditional Access policy, or an app
registration. This is a genuinely separate, eighth RBAC model from the seven in §1/§9/§10/§11:
administered entirely in the **Microsoft Defender portal** (`security.microsoft.com`), and itself
split across two RBAC generations depending on when the tenant was provisioned.

- **Basic permissions management (either generation):** the Microsoft Entra **Security
 Administrator** role grants full access to the Microsoft Defender portal, including every
 Advanced features toggle, the same role §9's Intune table already lists as carrying
 full-admin Endpoint Security node access. **Security Reader** grants read-only access (can view
 the current toggle state, cannot change it). This is the simplest, least-friction option for a
 tenant that hasn't opted into granular Defender for Endpoint RBAC, and is what Microsoft's own
 companion procedure for the adjacent **Configure the Microsoft Intune connection** toggle on the
 *same* Advanced features page names explicitly as one of its two supported prerequisites.
- **Granular RBAC, tenants on the legacy (pre-February 2025) Defender for Endpoint permissions
 model:** the **Manage security settings in Security Center** permission, assignable to a custom
 role under **Settings → Endpoints → Roles**. Microsoft's own role-permissions reference doesn't
 enumerate "Advanced features" by name, but the same companion Intune-connection-toggle procedure
 above names this exact permission as the non-Entra-role alternative to Security Administrator for
 configuring that toggle, strong, directly-cited evidence for the sibling toggle on the identical
 settings page, not an assumption by symmetry alone.
- **Granular RBAC, tenants on Microsoft Defender **unified RBAC** (URBAC), mandatory for every
 Defender for Endpoint customer provisioned on or after February 16, 2025:** Microsoft's own
 legacy-to-unified permission mapping table translates **Manage security settings in Security
 Center** to the **Authorization and settings → Security settings → Core security settings
 (Manage)** permission (with **Detection tuning (Manage)** also carried over from the same legacy
 permission), assignable to a custom URBAC role under the same **Settings → Endpoints → Roles**
 page. Existing tenants keep the legacy model above until they migrate; new tenants since that
 date have URBAC only, with no legacy option.
- **This role/permission does not grant any Purview access.** A user who can toggle Defender for
 Endpoint's Advanced features cannot configure Insider Risk Management policies or indicators, 
 that remains the **Insider Risk Management**/**Insider Risk Management Admins** Purview role
 group (§4), the same separation-of-concerns point §9, §11 already make for Intune, Conditional
 Access, and Entra app-registration RBAC.
- **Portal-only setting, no automation surface:** unlike the other seven systems, this toggle has
 no documented Microsoft Graph or PowerShell equivalent, `security-policy-violations-by-departing-
 users/README.md` §3 and §5 already flag this; a human with one of the roles/permissions above
 must set it interactively, and no `deploy/` script in this repo attempts it.

## 13. Exchange Server on-premises RBAC, a ninth system, for hybrid/on-premises scenarios

`scenarios/dlp/accepted-domains-hygiene-check-on-premises/` is the first (and, as of this build,
only) scenario in this library that authenticates to an **on-premises Exchange Server**
organization via remote PowerShell instead of any cloud service ([Automation surface](/docs/automation-surface/)'s
five connection surfaces are all-cloud), a genuinely separate, ninth RBAC model from the eight in
§1/§9/§10/§11/§12.

- **Same vocabulary as Exchange Online's own RBAC (§1 #4), a structurally separate object model.**
 On-premises Exchange RBAC uses the identical role → role-group → role-assignment-policy →
 management-scope concepts Exchange Online's RBAC uses (source 27 below is Microsoft's own
 on-premises role-groups reference; compare to source 9's Exchange Online equivalent). But a role
 group is an **Active Directory-backed Universal Security Group scoped to that one on-premises
 Exchange organization/forest**, a role group that shares a name with its Exchange Online
 counterpart (**Organization Management**, **Compliance Management**, **Recipient Management**,
 **View-Only Organization Management**) is a **distinct security principal on each side**.
 Membership granted on one side grants nothing on the other, a hybrid buyer running both this
 scenario and its Exchange Online-only parent, `scenarios/dlp/accepted-domains-hygiene-check/`,
 must grant both role groups independently, exactly as
 `accepted-domains-hygiene-check-on-premises/README.md` §3 already states for the scenario itself.
- **Organization Management**, the on-premises superset administrative role group, with
 administrative access to virtually the entire organization; also the only role group whose
 members can, by default, add/remove members of *other* role groups (the **Role Management**
 role), the identical least-privilege-gatekeeper pattern §2 above states for the Purview model.
 **Confirmed sufficient** for this scenario's minimum need (`Get-AcceptedDomain` read +
 `Search-AdminAuditLog` read), sources 27, 29.
- **Narrower candidates this build could not fully confirm, recorded as leads, not guessed as
 fact (per `AGENTS.md` §4):**
 - **Compliance Management**, a narrower, compliance-focused role group, confirmed by source 28
 to carry the **Audit Logs**/**View-Only Audit Logs** roles by default (the same two roles
 Organization Management itself carries, per sources 30-31), a plausible least-privilege home
 for the `Search-AdminAuditLog` half of this scenario's need. This build found no confirmation
 that Compliance Management also carries a role granting `Get-AcceptedDomain` read, **VERIFY**.
 - **View-Only Organization Management**, a read-only role group carrying the **View-Only
 Configuration** role (all non-recipient configuration, org-wide, per source 33) and, per
 secondary/search-only corroboration only, **View-Only Audit Logs**, a candidate read-only
 least-privilege fit, **not independently confirmed by a direct Microsoft Learn fetch**: this
 run's network egress policy blocked `learn.microsoft.com` again, the same blocker
 `accepted-domains-hygiene-check-on-premises/design.md` §2/§12 already disclosed for its own
 grounding, **VERIFY** (source 32 is the role group's own reference page, fetched only via
 WebSearch summary, not a direct WebFetch).
 - **Recipient Management**, carries the **Mail Recipients** role (manage/view mailboxes, mail
 users, mail contacts, per sources 34-35). One secondary source (not a direct Microsoft Learn fetch)
 claims its members can read `Get-AcceptedDomain` but not write it, **VERIFY**; a buyer can
 confirm directly against their own tenant with `Get-ManagementRoleEntry "*\Get-AcceptedDomain"`
 (compare the role names returned to a candidate role group's own `Get-RoleGroup | Select
 -ExpandProperty Roles`) rather than trusting this unconfirmed claim.
 - **No single built-in on-premises role group narrower than Organization Management was confirmed
 by this build to grant both halves of this scenario's minimum need together.** A custom role
 group combining a `Get-AcceptedDomain`-capable role with **View-Only Audit Logs** is the
 least-privilege construction worth investigating next, matching the gap
 `accepted-domains-hygiene-check-on-premises/README.md` §11 already discloses ("No
 independently-confirmed least-privilege on-premises role narrower than Organization
 Management").
- **This role/role-group system grants no Exchange Online or Purview access whatsoever**, the same
 separation-of-concerns point §9, §12 make for Intune, Conditional Access, Entra app-registration,
 and Defender for Endpoint portal RBAC. A hybrid buyer running both the Exchange Online-only parent
 scenario (§1 #4) and this on-premises companion needs role assignments on **both** sides
 independently; neither system's role groups are visible to, or usable from, the other.

---

## 14. How scenarios should cite RBAC

Each scenario README's **Prerequisites** section must state:
1. Which of the **four RBAC systems** (§1) the scenario touches, or, for an Intune-deployed
 scenario, that it uses the separate Intune RBAC model (§9) instead, for a Conditional
 Access-deployed scenario, that it uses the separate Entra Conditional Access model (§10), for
 a scenario whose own code creates an app registration, that it uses the separate Entra
 app-registration RBAC model (§11), for a scenario that configures a Defender for Endpoint
 tenant-wide setting, that it uses the separate Defender for Endpoint portal RBAC model (§12),
 or, for a scenario that authenticates to an on-premises Exchange Server organization, that it
 uses the separate on-premises Exchange RBAC model (§13).
2. The **narrowest built-in Purview role group** that covers it (name it exactly), or note that
 a **custom role group** is recommended for least privilege.
3. Any **Exchange Online RBAC** dependency (§6), call it out explicitly if the scenario searches
 audit logs or reads Exchange-sourced reports.
4. Whether **administrative units** are supported/required for the scenario's scope (§7).
5. For automation code: the **app-only auth** pattern used and the exact role(s)/Graph scopes the
 app registration needs, never "give it Global Admin."

---

## Sources (Microsoft Learn, re-verify before provisioning)

- Roles and role groups in Microsoft Defender for Office 365 and Microsoft Purview (canonical role-group ↔ role table), <https://learn.microsoft.com/microsoft-365/security/office-365-security/scc-permissions>
- Permissions in the Microsoft Purview portal, <https://learn.microsoft.com/purview/purview-permissions>
- Administrative units in Microsoft Purview, <https://learn.microsoft.com/purview/purview-admin-units>
- Data governance roles and permissions in Microsoft Purview (Unified Catalog), <https://learn.microsoft.com/purview/data-governance-roles-permissions>
- Access control in the classic Microsoft Purview governance portal, <https://learn.microsoft.com/purview/data-gov-classic-permissions>
- Connect to Exchange Online PowerShell, <https://learn.microsoft.com/powershell/exchange/connect-to-exchange-online-powershell>
- Connect to Security & Compliance PowerShell, <https://learn.microsoft.com/powershell/exchange/connect-to-scc-powershell>
- App-only authentication for unattended scripts (Exchange Online / S&C PowerShell), <https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2>
- Manage role groups in Exchange Online, <https://learn.microsoft.com/exchange/permissions-exo/role-groups>
- Microsoft Entra built-in roles reference, <https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference>
- Microsoft Entra administrative units, <https://learn.microsoft.com/entra/identity/role-based-access-control/administrative-units>
- Role-based access control (RBAC) with Microsoft Intune (built-in roles list, Entra-role-to-Intune access table), <https://learn.microsoft.com/intune/fundamentals/role-based-access-control/overview>
- Built-in role permissions for Microsoft Intune (Policy and Profile Manager's full permission table), <https://learn.microsoft.com/intune/fundamentals/role-based-access-control/ref-built-in-roles>
- Microsoft Graph permissions reference (`DeviceManagementConfiguration.ReadWrite.All`), <https://learn.microsoft.com/graph/permissions-reference>
- Protect your tenant with Insider Risk in Conditional Access (Conditional Access Administrator
 + Insider Risk Management role prerequisites, Entra ID P2 requirement), <https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition>
- Update conditionalAccessPolicy (`Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`
 least-privileged permissions), <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
- Microsoft Entra built-in roles reference, Application Administrator, Application Developer,
 Cloud Application Administrator (permission tables, privileged-role labeling, impersonation
 caveat), <https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference>
- Delegate app registration permissions in Microsoft Entra ID (default "Users can register
 applications" behavior; least-privilege guidance between the three app-registration roles), <https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles>
- New-MgApplication, New-MgServicePrincipal, Add-MgApplicationPassword (Microsoft.Graph.Applications
 least-privileged delegated permissions: `Application.ReadWrite.All`), <https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgapplication>
- Configure advanced features in Defender for Endpoint (Advanced features page, incl. **Share
 endpoint alerts with Microsoft Compliance Center**), <https://learn.microsoft.com/defender-endpoint/advanced-features>
- Manage portal access using role-based access control in Microsoft Defender for Endpoint (legacy
 RBAC model; Security Administrator/Security Reader basic-permissions behavior), <https://learn.microsoft.com/defender-endpoint/rbac>
- Create and manage roles for role-based access control (legacy permission list, incl. **Manage
 security settings in Security Center** and **Manage portal system settings**), <https://learn.microsoft.com/defender-endpoint/user-roles>
- Microsoft Defender unified role-based access control (RBAC) (URBAC, mandatory for tenants
 provisioned on/after Feb 16, 2025), <https://learn.microsoft.com/defender-xdr/manage-rbac>
- Map existing RBAC permissions to Microsoft Defender unified RBAC permissions (legacy **Manage
 security settings in Security Center** → **Core security settings (Manage)** + **Detection
 tuning (Manage)** mapping), <https://learn.microsoft.com/defender-xdr/compare-rbac-roles>
- Configure Microsoft Defender for Endpoint with Intune and onboard devices (names **Security
 Administrator** or **"Manage security settings in Security Center"** as the two supported
 prerequisites for the adjacent Intune-connection toggle on the same Advanced features page), <https://learn.microsoft.com/intune/device-security/microsoft-defender/configure-integration>
- Assign permissions in Data Security Investigations (the three dedicated DSI role group names, the
 full Admins/Investigators/Reviewers permission-by-action matrix, and the four role groups that
 carry implicit DSI access), <https://learn.microsoft.com/purview/data-security-investigations-permissions>
- Manage role groups in Exchange Server (on-premises role-group/role/role-assignment-policy model)
, <https://learn.microsoft.com/exchange/permissions/role-groups>
- Compliance Management (Exchange Server on-premises role group; carries the Audit Logs/View-Only
 Audit Logs roles by default), <https://learn.microsoft.com/exchange/compliance-management-exchange-2013-help>
- Organization Management (Exchange Server on-premises superset role group), <https://learn.microsoft.com/exchange/organization-management-exchange-2013-help>
- Audit Logs role (Exchange Server on-premises, configure administrator audit logging), <https://learn.microsoft.com/exchange/audit-logs-role-exchange-2013-help>
- View-Only Audit Logs role (Exchange Server on-premises, search administrator audit logs), <https://learn.microsoft.com/exchange/view-only-audit-logs-role-exchange-2013-help>
- View-only Organization Management (Exchange Server on-premises read-only role group; fetched via
 WebSearch summary only, `learn.microsoft.com` direct fetch was blocked this run, not independently
 re-confirmed by a direct page fetch), <https://learn.microsoft.com/exchange/view-only-organization-management-exchange-2013-help>
- View-Only Configuration role (Exchange Server on-premises, view all non-recipient configuration,
 org-wide), <https://learn.microsoft.com/exchange/view-only-configuration-role-exchange-2013-help>
- Recipient Management (Exchange Server on-premises role group), <https://learn.microsoft.com/exchange/recipient-management-exchange-2013-help>
- Mail Recipients role (Exchange Server on-premises, manage existing mailboxes, mail users, mail
 contacts), <https://learn.microsoft.com/exchange/mail-recipients-role-exchange-2013-help>
- Manage audit log retention policies (**Organization Configuration** role requirement to create/
 edit an audit log retention policy), <https://learn.microsoft.com/purview/audit-log-retention-policies>

> **Sources 27-35 grounding note:** this run's network egress policy blocked direct `WebFetch`
> access to `learn.microsoft.com` (same blocker `accepted-domains-hygiene-check-on-premises/
> design.md` §2/§12 already disclosed) and the Microsoft Learn MCP tool was not present in this
> session's tool list, every fact in §13 above is grounded via `WebSearch` result summaries citing
> these exact URLs, not a direct page fetch. Each summary independently named the same role/
> role-group facts across multiple, differently-worded queries (cross-corroboration in place of a
> direct fetch), except where §13 explicitly flags a narrower claim as **VERIFY** because only one
> unconfirmed secondary source supported it. Re-verify against a direct fetch of these URLs, or a
> pilot on-premises Exchange server, before relying on the VERIFY-flagged claims for a least-
> privilege role-group decision.

> **Disclaimer:** role names, default role-group membership, and which system governs a given
> feature change as Purview ships updates (e.g. the ongoing move toward Microsoft Defender
> unified RBAC for email & collaboration). Validate against the live **Roles and scopes** page in
> the target tenant before granting production access.
