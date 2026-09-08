# Microsoft Purview — RBAC / Roles & Permissions Model

> **Cross-cutting reference.** Every scenario in this library links here instead of restating
> permissions. Read this once to understand *which* role unlocks *which* task, and which of the
> **four separate RBAC systems** a given Purview capability actually uses.
>
> **Verify before you provision access.** Role names, default assignments, and role-group
> membership change frequently. This matrix is a practitioner's summary grounded in Microsoft
> Learn, current as of **2026-09-05**. Sources are linked at the bottom; re-check them before
> granting production access.

---

## 1. Four RBAC systems, not one (read this first)

A Purview deployment touches **four distinct permission models**. Confusing them is the single
biggest cause of "why can't this user do X" tickets.

| # | System | Where it's managed | Governs |
|---|---|---|---|
| **1** | **Microsoft Entra ID roles** | Entra admin center / `Microsoft Graph` | Tenant-wide admin roles (Global Administrator, Compliance Administrator, Security Administrator, AI Administrator...). Several map automatically into Purview role groups (§3). |
| **2** | **Microsoft Purview role-based access control (RBAC)** — role groups & roles | Purview portal → **Settings → Roles and scopes** (`purview.microsoft.com`), or Security & Compliance PowerShell (`Get-RoleGroup`/`New-RoleGroupMember`) | Data security (DLP, Information Protection, Insider Risk, Communication Compliance, DSPM for AI), risk & compliance (eDiscovery, Audit, Compliance Manager, Records Management, Information Barriers, Data Lifecycle Management). This is the model covered in most of §2–§4 below. |
| **3** | **Data Map / Unified Catalog governance roles** | Purview portal → governance domain **Roles** tab, or the classic governance portal's **Collections** | Data Governance: Data Map collections, Unified Catalog governance domains, data products, glossary, data health. A **separate** role model from #2 — see §5. |
| **4** | **Exchange Online RBAC** | Exchange admin center / Exchange Online PowerShell (`Get-ManagementRoleAssignment`) | Workload-level actions Purview doesn't cover: mail flow rules (transport rules), mailbox permissions, and — critically — **audit log search requires an Exchange Online role**, not just a Purview one (see §6 note). |

> Managing permissions in the Purview portal (#2) does **not** grant Exchange, SharePoint, or
> Entra permissions. Conversely, being a Global Administrator (#1) does not automatically show
> up as a member in `Get-RoleGroupMember` output for Organization Management — Global Admins are
> auto-added but hidden from that view.

---

## 2. Purview RBAC building blocks: members → roles → role groups

- A **role** grants permission to perform a set of tasks (e.g. *DLP Compliance Management* lets
  you view/edit DLP policies; *RecordManagement* lets you configure records management).
- A **role group** is a bundle of roles assigned together for a job function (e.g. *Insider Risk
  Management Investigators*).
- **Members** (users, mail-enabled security groups — commercial cloud only) are added to role
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
> For most scenarios in this library, a **Purview role group** (§4) is the correct grant — reach
> for an Entra admin role only when the task is genuinely tenant-wide identity administration.

---

## 4. Purview role groups by module (representative, not exhaustive)

Legend: role groups shown are the **primary** ones for day-to-day operation of that module. Each
module has narrower variants (Admins / Analysts / Investigators / Viewers / Readers) for
separation of duties — pick the narrowest that covers the task. Full list: §9 source 1.

| Module | Role groups (narrowest → broadest) | Notes |
|---|---|---|
| **Information Protection** (labels, DLP-adjacent classification) | Information Protection Readers → Analysts → Investigators → Admins → **Information Protection** (full control) | *Information Protection Admin* role: create/edit/delete DLP policies, labels, classifiers; manage endpoint DLP and auto-labeling simulation mode |
| **DLP** | Covered by the Information Protection groups above (**DLP Compliance Management** role) | *View-Only DLP Compliance Management* for read-only; policy creation needs *DLP Compliance Management* |
| **Insider Risk Management** | Insider Risk Management Auditors → Analysts → Investigators → Admins → **Insider Risk Management** (all-in-one) | Analysts can't access Content Explorer; Investigators can. *Insider Risk Management Approvers*/*Session Approvers* are narrow, workflow-only groups |
| **Adaptive Protection** | Inherits IRM + Information Protection role groups — no separate role group | Requires both IRM admin/analyst access **and** DLP policy-author access to configure risk-based enforcement |
| **DSPM for AI** | Data Security AI Viewers → Data Security AI Content Viewers (prompt/response) → Data Security AI Admins; broader posture: **AI Administrators**, **Compliance Administrator** role group | *Data Security AI Content Viewer* is the only role that can read prompts/responses — assign narrowly |
| **Communication Compliance** | Communication Compliance Viewers → Analysts → Investigators → Administrators → **Communication Compliance** (all-in-one) | Analysts see metadata only; Investigators see full message content — separation of duties matters here for privacy |
| **eDiscovery (Standard + Premium)** | **eDiscovery Manager** (own/member cases only) vs. **eDiscovery Administrator** (all cases org-wide, same role group with extra scope) → **Reviewer** (review-set-only, no search/case mgmt) | eDiscovery Administrator = eDiscovery Manager member additionally granted org-wide case visibility — not a separate role group |
| **Audit (Standard + Premium)** | Audit Reader (View-Only Audit Logs) → **Audit Manager** (configure + search + export) | See §6: also requires an Exchange Online role to actually run `Search-UnifiedAuditLog` |
| **Data Lifecycle Management** | Priority Cleanup Viewer/Admin (org-wide meta) → **Records Management** role group (Retention Management, Scope Manager roles) | Same role group also governs Records Management (below) — split by task, not by separate group |
| **Records Management** | **Records Management** role group (RecordManagement, Retention Management, Disposition Management, Scope Manager roles) | |
| **Information Barriers** | **Compliance Administrator** / **Compliance Data Administrator** / **Organization Management** / **Security Administrator** (IB Compliance Management role) — no dedicated IB role group | View-only variant: *View-Only IB Compliance Management*, held by the same groups plus Global Reader/Security Reader |
| **Compliance Manager** | Compliance Manager Readers → Contributors → Assessors → **Compliance Manager Administrators** | Template creation/modification needs Administrators; assessment work needs only Contributor/Assessor |
| **Privacy Management / Subject Rights Requests** | Privacy Management Viewers → Analysts → Investigators → Contributors → **Privacy Management Administrators**; **Subject Rights Request Administrators** / **Approvers** | Out of this library's default scope (Priva-adjacent) — see `AGENTS.md` §2 assumption |
| **Data Security Investigations** | Data Security Investigation Reviewers → Investigators → **Data Security Investigation Admins** | New cross-solution investigation workspace spanning DLP/IRM/Communication Compliance evidence |

---

## 5. Data governance roles (Data Map + Unified Catalog) — a separate model

Data Governance does **not** use the role groups in §4. It has its own three-tier model:

| Tier | Role | Grants |
|---|---|---|
| **Tenant** | **Data Governance** role group (Data Governance Administrator role) | Delegates first-level access to create Governance Domain Creators; not itself surfaced inside Unified Catalog UI |
| Tenant | **Data Source Administrators** role group | Manage data sources and scans in Data Map |
| Tenant | **Purview Administrators** role group | Create/edit/delete domains, perform role assignments (Purview Domain Manager + Role Management roles) |
| **Catalog** | **Governance Domain Creator** | Create governance domains; becomes domain owner by default |
| Catalog | **Global Catalog Reader** vs. **Local Catalog Reader** | Global = read published concepts across *all* domains without a local reader override; Local = restricts read access to one domain (use for regulatory/legal segregation — overuse defeats federated governance) |
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
  reports, Defender for Office 365 reports) require an **Exchange Online** role — Global Admins
  get this for free via automatic Organization Management membership in Exchange Online itself;
  everyone else needs an explicit Exchange RBAC role/role group in addition to their Purview one.
- **Compliance Administrator** and **Organization Management** (the Purview role groups) are
  explicitly flagged by Microsoft as **not** sufficient on their own for audit log search or
  Exchange-data reports (footnote ¹ on the role-groups reference, source 1).
- **Mail flow rules (transport rules), mailbox-level permissions** — manage in the Exchange admin
  center (`admin.exchange.microsoft.com`), not the Purview portal.

Every scenario that touches Audit or exports Exchange-sourced report data should call this out
explicitly in its Prerequisites section.

---

## 7. Administrative units — scoping Purview RBAC to a region/department

[Administrative units (AUs)](https://learn.microsoft.com/entra/identity/role-based-access-control/administrative-units)
are an **Entra ID** construct that Purview role groups can be scoped to, turning an
"unrestricted administrator" into a **restricted administrator** who can only see/manage
users, policies, and alert data within their assigned unit(s).

- **Prerequisites:** Entra ID **P1 or P2** licensing, *plus* Purview licensing at E5/A5/G5 tier
  (or the Compliance/IP&G/Insider-Risk-Management add-ons — see `licensing-matrix.md`).
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
  policies invisible to them going forward (the policies keep running — an unrestricted admin can
  still see/edit them). Plan AU rollout as an additive change, not a retrofit onto admins who
  already manage org-wide policies.
- **Required role to assign AUs:** *Role management* role (Organization Management / Purview
  Administrators by default).

---

## 8. PowerShell & Graph automation — connecting with the right role

All PowerShell code in this library authenticates using one of two Exchange-Online-hosted
endpoints, gated by the RBAC systems above — never with a hard-coded credential:

| Endpoint | Module | Cmdlet | What it needs |
|---|---|---|---|
| Exchange Online PowerShell | `ExchangeOnlineManagement` | `Connect-ExchangeOnline` | An Exchange Online RBAC role (mailflow rules, recipients, audit search) |
| Security & Compliance PowerShell | `ExchangeOnlineManagement` (same module, different endpoint) | `Connect-IPPSSession` | A Purview role group with the relevant role (DLP, retention, IRM, eDiscovery, etc.) |

- **Interactive/admin use:** `Connect-ExchangeOnline` / `Connect-IPPSSession` with the signed-in
  user's own MFA-backed credential — RBAC is enforced per-command against that user's role
  assignments.
- **Unattended automation (what this library's `deploy/`/`validate/` scripts assume):**
  **app-only authentication** — register an Entra app registration, assign it either a built-in
  Exchange/Purview role (Entra app role assignment) or a **custom role group** containing only
  the roles the automation needs, then connect with `-AppId`/`-CertificateThumbprint` (or a
  managed identity). Never embed client secrets in scripts — use certificate-based auth or Azure
  Key Vault–resolved credentials, and prefer the narrowest custom role group over inheriting an
  interactive admin's role group membership.
- **Microsoft Graph automation** (Data Map/Unified Catalog scans, Entra AU management, some
  DSPM-for-AI surfaces) uses standard Graph app permissions (least-privilege application
  permissions on the app registration), separate again from Exchange/Purview RBAC — grant only
  the specific Graph scopes a script needs (e.g. `Purview-DataGovernance.*` scopes for Data Map
  API calls; VERIFY: exact Graph permission names per data-governance API endpoint used, as the
  Data Map/governance Graph API surface is evolving).
- Finding the exact permission a given cmdlet needs: `Find-Exchange cmdlet permissions`
  guidance in source 6 below — use it before assuming a role group is broad enough.

---

## 9. Microsoft Intune RBAC — a fifth system, for Intune-deployed scenarios

The four systems in §1 cover every Purview-portal capability, but two scenarios in this library —
`scenarios/dlp/defender-device-control-usb-allowlist/` and its `-wpd-coverage` sibling — don't
create a Purview policy object at all. They deploy Microsoft Defender for Endpoint device control
through an **Intune** device configuration profile (`docs/licensing-matrix.md` §7), which uses a
genuinely separate, fifth RBAC model: managed in the **Intune admin center → Tenant administration
→ Roles**, not the Purview portal's **Settings → Roles and scopes**.

- **Built-in role that covers device control:** **Policy and Profile Manager** — "Manages
  compliance policy, configuration profiles, Apple enrollment, Android Enterprise enrollment
  profiles, corporate device identifiers, and security baselines." Its permission set includes
  **Device configurations: Create / Read / Update / Delete / Assign / View Reports** — the exact
  grant both device-control scenarios' `windows10CustomConfiguration` Custom OMA-URI profiles
  need. Narrower built-in roles (**Read Only Operator**, **Help Desk Operator**) can *read* these
  profiles but not create or update them.
- **Other built-in Intune roles**, for context (Intune doesn't order these narrowest→broadest the
  way Purview role groups are tiered — each is scoped to a different job function): Application
  Manager, Endpoint Privilege Manager/Reader, Endpoint Security Manager, Help Desk Operator,
  **Intune Role Administrator** (the only Intune role that can itself assign permissions to other
  admins), Read Only Operator, School Administrator, plus **Cloud PC Administrator/Reader** in
  tenants with Windows 365. Custom roles can combine any permission for a least-privilege fit
  Microsoft's built-in roles don't cover.
- **Microsoft Entra roles that also carry Intune access** — a documented *subset* relationship
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
  for day-to-day Intune management — both are classified **privileged roles** and exceed what
  almost any routine task needs. Use **Policy and Profile Manager** (or a custom role) instead —
  the same least-privilege principle §3 already states for Entra-role-to-Purview mapping.
- **App-only automation (Microsoft Graph):** both device-control scenarios' `deploy/` scripts
  authenticate as a Graph app registration rather than an interactive admin, and need the
  **`DeviceManagementConfiguration.ReadWrite.All`** application permission (admin consent
  required) to create/update `windows10CustomConfiguration` objects — confirmed as the permission
  Microsoft Graph's own `Update-MgDeviceManagement` / `Get-MgDeviceManagementDeviceConfiguration`
  PowerShell reference pages list for this resource type. Grant only this permission, not the
  similarly-named `DeviceManagementServiceConfig.*` or `DeviceManagementApps.*` permissions, which
  cover different Intune resource families — the same least-privilege rule §8 states for
  Purview/Exchange Graph scopes applies equally here.
- **Licensing is tracked separately:** holding the Graph permission or the Policy and Profile
  Manager role does not itself grant the Intune/Defender for Endpoint license a device needs to be
  managed — see `docs/licensing-matrix.md` §7.

---

## 10. Microsoft Entra Conditional Access — a sixth system, for identity-layer scenarios

`scenarios/adaptive-protection/conditional-access-insider-risk-block/` is the first scenario in
this library that authors a **Microsoft Entra Conditional Access** policy rather than a Purview
policy object or an Intune device configuration profile. Conditional Access is administered
entirely in the **Microsoft Entra admin center**, a genuinely separate, sixth RBAC model from the
four in §1 and from Intune's own model in §9 — not a Purview role group, and not one of the
Intune roles either.

- **Built-in Entra role that covers Conditional Access authoring:** **Conditional Access
  Administrator** — can create, edit, and delete Conditional Access policies. This is the role
  Microsoft's own documented procedure for the Insider Risk condition specifically names as the
  minimum needed to create that policy.
- **Least privilege still applies:** Microsoft explicitly recommends against using **Global
  Administrator** or **Security Administrator** for routine Conditional Access authoring —
  **Conditional Access Administrator** is the narrowest built-in role that covers it, the same
  least-privilege principle §3 and §9 already state for Entra-role and Intune-role assignment.
- **This role does not grant any Purview access.** A Conditional Access Administrator cannot
  configure Adaptive Protection settings or insider risk levels — that remains the **Insider Risk
  Management**/**Insider Risk Management Admins** Purview role group (§4), a deliberately separate
  grant on a separate admin surface, exactly as `conditional-access-insider-risk-block/README.md`
  §3 documents.
- **App-only automation (Microsoft Graph):** the scenario's `deploy/` scripts authenticate as a
  Graph app registration and need the **`Policy.ReadWrite.ConditionalAccess`** and
  **`Policy.Read.All`** application permissions (admin consent required, least-privileged per
  Microsoft's own documented permissions table for creating/updating a `conditionalAccessPolicy`)
  — the same least-privilege rule §8 and §9 already state for Purview/Exchange and Intune Graph
  scopes applies equally here.
- **Licensing is tracked separately, again:** holding the role or the Graph permission does not
  itself grant the **Microsoft Entra ID P2** entitlement every user in a Conditional Access
  policy's scope needs for a premium condition like Insider Risk to apply — see
  `docs/licensing-matrix.md` §8.

---

## 11. How scenarios should cite RBAC

Each scenario README's **Prerequisites** section must state:
1. Which of the **four RBAC systems** (§1) the scenario touches — or, for an Intune-deployed
   scenario, that it uses the separate Intune RBAC model (§9) instead, or, for a Conditional
   Access-deployed scenario, that it uses the separate Entra Conditional Access model (§10).
2. The **narrowest built-in Purview role group** that covers it (name it exactly), or note that
   a **custom role group** is recommended for least privilege.
3. Any **Exchange Online RBAC** dependency (§6) — call it out explicitly if the scenario searches
   audit logs or reads Exchange-sourced reports.
4. Whether **administrative units** are supported/required for the scenario's scope (§7).
5. For automation code: the **app-only auth** pattern used and the exact role(s)/Graph scopes the
   app registration needs — never "give it Global Admin."

---

## Sources (Microsoft Learn — re-verify before provisioning)

- Roles and role groups in Microsoft Defender for Office 365 and Microsoft Purview (canonical role-group ↔ role table) — <https://learn.microsoft.com/microsoft-365/security/office-365-security/scc-permissions>
- Permissions in the Microsoft Purview portal — <https://learn.microsoft.com/purview/purview-permissions>
- Administrative units in Microsoft Purview — <https://learn.microsoft.com/purview/purview-admin-units>
- Data governance roles and permissions in Microsoft Purview (Unified Catalog) — <https://learn.microsoft.com/purview/data-governance-roles-permissions>
- Access control in the classic Microsoft Purview governance portal — <https://learn.microsoft.com/purview/data-gov-classic-permissions>
- Connect to Exchange Online PowerShell — <https://learn.microsoft.com/powershell/exchange/connect-to-exchange-online-powershell>
- Connect to Security & Compliance PowerShell — <https://learn.microsoft.com/powershell/exchange/connect-to-scc-powershell>
- App-only authentication for unattended scripts (Exchange Online / S&C PowerShell) — <https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2>
- Manage role groups in Exchange Online — <https://learn.microsoft.com/exchange/permissions-exo/role-groups>
- Microsoft Entra built-in roles reference — <https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference>
- Microsoft Entra administrative units — <https://learn.microsoft.com/entra/identity/role-based-access-control/administrative-units>
- Role-based access control (RBAC) with Microsoft Intune (built-in roles list, Entra-role-to-Intune access table) — <https://learn.microsoft.com/intune/fundamentals/role-based-access-control/overview>
- Built-in role permissions for Microsoft Intune (Policy and Profile Manager's full permission table) — <https://learn.microsoft.com/intune/fundamentals/role-based-access-control/ref-built-in-roles>
- Microsoft Graph permissions reference (`DeviceManagementConfiguration.ReadWrite.All`) — <https://learn.microsoft.com/graph/permissions-reference>
- Protect your tenant with Insider Risk in Conditional Access (Conditional Access Administrator
  + Insider Risk Management role prerequisites, Entra ID P2 requirement) — <https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition>
- Update conditionalAccessPolicy (`Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`
  least-privileged permissions) — <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>

> **Disclaimer:** role names, default role-group membership, and which system governs a given
> feature change as Purview ships updates (e.g. the ongoing move toward Microsoft Defender
> unified RBAC for email & collaboration). Validate against the live **Roles and scopes** page in
> the target tenant before granting production access.
