---
title: "Microsoft Purview, Automation Surface (Graph + PowerShell/EXO/S&C)"
name: "Automation surface"
---
> **Cross-cutting reference.** Every scenario's `deploy/` and `validate/` scripts in this library
> follow the connection, authentication, and error-handling patterns documented here instead of
> restating them per scenario. Read this once to know **which module or API to reach for**,
> **how to authenticate unattended**, and **how to survive throttling at scale**.
>
> **Verify before you script against production.** Module versions, cmdlet support, and API
> surfaces change frequently. This is a practitioner's summary grounded in Microsoft Learn,
> current as of **2026-09-08**. Sources are linked at the bottom; re-check them before building
> a production pipeline.

---

## 1. Five automation surfaces, not one (read this first)

Purview automation spans **five distinct connection surfaces**, layered on top of the four RBAC
systems in `rbac-model.md` §1. Picking the wrong one is the second most common cause of "why
doesn't this cmdlet exist" tickets (the first is RBAC, see `rbac-model.md`).

| # | Surface | Module / endpoint | Typical use in this library |
|---|---|---|---|
| **1** | **Exchange Online PowerShell** | `ExchangeOnlineManagement` module, `Connect-ExchangeOnline` | Mail flow rules (transport rules), recipient/mailbox config, `Search-UnifiedAuditLog` |
| **2** | **Security & Compliance PowerShell** | Same `ExchangeOnlineManagement` module, `Connect-IPPSSession` (different endpoint) | DLP policies/rules, retention (DLM) policies & labels, sensitivity labels & auto-labeling policies, IRM policy config (partial), Communication Compliance, Records Management, some eDiscovery cmdlets |
| **3** | **Microsoft Graph** | `Microsoft.Graph` PowerShell SDK (`Connect-MgGraph`) or raw REST (`https://graph.microsoft.com`) | eDiscovery cases/holds/review-sets (`Microsoft.Graph.Security` namespace), Teams DLP real-time evaluation & export, Audit Search Graph API, subject rights requests, DSPM-for-AI protection-scope/process-content APIs, Entra administrative units, Conditional Access policies (`Microsoft.Graph.Identity.SignIns` namespace, e.g. the Adaptive Protection Conditional Access Insider Risk scenario) |
| **4** | **Microsoft Purview Data Map / Data Governance REST API** | `https://{account}.purview.azure.com` (data-plane) + `https://api.purview-service.microsoft.com` (audit) | Data Map scans, sources, collections; Data Map lineage (custom relationships); Unified Catalog governance domains, data products, data assets, glossary; Data Map history/audit query |
| **5** | **SharePoint Online Management Shell** | `Microsoft.Online.SharePoint.PowerShell` module, `Connect-SPOService` (a separate tenant-admin endpoint from surfaces 1/2 and from site-level SharePoint/PnP automation) | Tenant-wide SharePoint/OneDrive **prerequisite toggles** that gate Information Protection scenarios, enabling sensitivity-label processing (`Set-SPOTenant -EnableAIPIntegration`), and the PDF/video (MP4) file-type extensions to that support. Also: enabling Information Barriers for SharePoint/OneDrive (`Set-SPOTenant -InformationBarriersSuspension`) and a **per-site segment-association loop** (`Set-SPOSite -AddInformationSegment`/`-RemoveInformationSegment`), see the note below on the latter as a second usage pattern |

> **Rule of thumb for picking a surface:** if the task is a **policy that ships as a
> Security & Compliance object** (DLP, retention, labels, IRM, records, comms compliance) →
> surface 2. If it's **case-based work with review sets/analytics** (eDiscovery Premium) or
> **Teams message-level DLP** or **subject rights/protection-scope APIs** → surface 3
> (Graph). If it's **Data Map/Unified Catalog metadata** → surface 4. If it's a **SharePoint/
> OneDrive tenant-level setting** (not a Purview policy object at all, it lives in the SharePoint
> admin center's own tenant configuration) → surface 5. Mail-flow rules and
> `Search-UnifiedAuditLog` are the two tasks that only exist on surface 1.
>
> **Surface 5 is a narrow, single-purpose surface in this library.** Unlike surfaces 1-4, it
> isn't used to author Purview policy objects, it only flips tenant-wide SharePoint/OneDrive
> switches that several Information Protection scenarios require as a one-time prerequisite
> before a sensitivity-label auto-labeling policy on those locations can take effect (see
> `scenarios/information-protection/auto-label-confidential-sharepoint/README.md` §5, which
> flagged this as a manual/undocumented prerequisite before this surface was grounded here).
> `scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/` adds a
> second pattern on this same surface: a **per-site loop** over a human-curated site list
> (`Set-SPOSite -AddInformationSegment`), not just a single tenant-wide toggle. §5's "not a
> bulk-iteration surface" guidance below still holds, the site list is small and curated, not a
> scan-and-iterate over thousands of objects, but don't assume every surface-5 script in this
> library is a single `Set-SPOTenant` call going forward.

---

## 2. Module install

| Module | Install | Notes |
|---|---|---|
| **ExchangeOnlineManagement** (covers surfaces 1 + 2) | `Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser` | From PowerShell Gallery. `-Scope AllUsers` needs an elevated session. PowerShell 7.2.0+ (Windows/macOS/Linux) or Windows PowerShell 5.1. **`Connect-IPPSSession` (Security & Compliance PowerShell) is not available in PowerShell 7 on Linux**, Linux automation that needs surface 2 must run on Windows or macOS, or reach the equivalent policy objects through Graph/REST where available. v3.2.0+ uses REST API mode for virtually all cmdlets (no local WinRM/Basic-auth dependency). |
| **Microsoft.Graph** PowerShell SDK (surface 3) | `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser` plus only the specific sub-modules a script needs (e.g. `Microsoft.Graph.Security`, `Microsoft.Graph.Identity.Governance`) | **Do not run `Install-Module Microsoft.Graph`** for automation, it pulls 47+ sub-modules. Install `Microsoft.Graph.Authentication` (installed automatically as a dependency of any sub-module) plus only what's used. PowerShell 7+ recommended on all platforms; Windows PowerShell 5.1 needs.NET Framework 4.7.2+ and `RemoteSigned` (or less restrictive) execution policy. Pin to `v1.0` cmdlets/module (`Microsoft.Graph.*`), avoid `Microsoft.Graph.Beta.*` in shipped automation; beta endpoints can change without notice. |
| **MSAL.PS** (surface 3, for the separate eDiscovery export-download token) | `Install-Module MSAL.PS -Scope CurrentUser` | Only needed for `Get-MSALToken` when downloading eDiscovery Premium export packages via the Purview eDiscovery API, which is authenticated separately from Graph. |
| Purview Data Map / Data Governance REST (surface 4) | No module, plain REST via `Invoke-RestMethod`/`Invoke-WebRequest`, or the Azure SDKs (`azure-purview-*` packages) if scripting outside PowerShell | Token obtained via OAuth2 client-credentials grant against `login.microsoftonline.com`, resource `https://purview.azure.net`. |
| **Microsoft.Online.SharePoint.PowerShell** (surface 5) | `Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser` | From PowerShell Gallery (or the standalone MSI installer). **This module is Windows PowerShell 5.1-native**, running it from a PowerShell 7 console requires `Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell`, which starts a Windows PowerShell 5.1 compatibility-layer process under the hood. That compatibility layer is Windows-only, so **unlike surfaces 1 and 3, surface 5 has no officially documented cross-platform (Linux/macOS) path**, see §6 for the CI/CD implication. The `-EnableSensitivityLabelforPDF` parameter specifically requires module version 16.0.24211.12000 or later. |

**Version pinning:** every script in this library's `deploy/`/`validate/` folders declares
`#Requires -Modules @{ ModuleName='ExchangeOnlineManagement'; ModuleVersion='X.Y.Z' }` (or the
equivalent Graph sub-module) rather than trusting whatever is latest at run time, module updates
have changed cmdlet defaults (e.g. the EXO v3 REST-mode transition) in ways that silently altered
script behavior.

---

## 3. Authentication patterns, interactive vs. unattended

| Pattern | Surfaces | When to use |
|---|---|---|
| **Interactive delegated (modern auth, MFA)** | 1, 2, 3, 5 | Admin running a script by hand at a keyboard. `Connect-ExchangeOnline -UserPrincipalName <admin>`, `Connect-IPPSSession -UserPrincipalName <admin>`, `Connect-MgGraph` (device code / browser), `Connect-SPOService -Url <admin-center-URL>` (prompts for credentials/MFA). Never used inside this library's `deploy/`/`validate/` scripts, those assume unattended execution. |
| **App-only, certificate-based (CBA)** | 1, 2, 3, 5 | **The default pattern for every script in this library.** An Entra app registration authenticates with an X.509 certificate, no password/secret to leak, no interactive prompt, and no dependency on a specific admin's account surviving. Certificate can live in the local cert store (`-CertificateThumbprint`) or be resolved at run time from Key Vault as an in-memory `X509Certificate2` object (`-Certificate`), never write the private key to disk in a pipeline. Surface 5's `Connect-SPOService` takes the same three certificate parameters (`-Certificate`/`-CertificateThumbprint`/`-CertificatePath` + `-CertificatePassword`) alongside `-ClientId`/`-TenantId`. |
| **App-only, client secret** | 3 (Graph SDK `-ClientSecretCredential`), REST (surface 4) | Acceptable when certificate management isn't available (e.g. quick POC), but the secret must come from a vault/pipeline secret store at run time, **never hard-coded or committed**. Prefer certificate or managed identity for anything that ships to a buyer's tenant. **Not available on surface 5**, `Connect-SPOService`'s app-only parameter set is certificate-only (no client-secret parameter), and Microsoft's SharePoint app-only guidance states plainly that certificates are the only supported app-only credential for SharePoint Online. |
| **Managed identity** | 1 (via `Connect-ExchangeOnline -ManagedIdentity -Organization <tenant>.onmicrosoft.com`, from Azure Automation/Functions/VMs with a system- or user-assigned identity), 3 (`Connect-MgGraph -Identity`), 5 (`Connect-SPOService -Url <admin-center-URL> -ManagedIdentity`, with `-ManagedIdentityType`/`-ManagedIdentityClientId` for a user-assigned identity) | Best option when the automation itself runs inside Azure (Azure Automation runbook, Azure Function, Azure VM), no credential material to manage at all. Not usable for scripts that run on a buyer's own workstation outside Azure. |

### App-only setup, the four steps common to every surface

1. **Register the app** in Microsoft Entra ID (`App registrations` → **New registration**).
2. **Assign the exact application permission the surface needs**, grant tenant-wide admin
 consent for each:
 - Surface 1 (`Connect-ExchangeOnline`): **Office 365 Exchange Online** → `Exchange.ManageAsApp`.
 - Surface 2 (`Connect-IPPSSession`): **Microsoft Exchange Online Protection** →
 `Exchange.ManageAsApp` (a separate resource from surface 1's permission, add both if the
 app uses both endpoints).
 - Surface 3 (Graph): the least-privileged **Application** permission for the specific API
 (e.g. `eDiscovery.Read.All`/`eDiscovery.ReadWrite.All`, `SecurityEvents.Read.All`,
 `AuditLogsQuery.Read.All`, VERIFY the exact permission name per Graph resource used, since
 Purview's Graph surface adds new scoped permissions over time).
 - Surface 5 (`Connect-SPOService`): **VERIFY**, Microsoft's official `Connect-SPOService`
 reference documents the certificate/`-ClientId`/`-TenantId` connection parameters but does
 not separately enumerate a named Entra **API permission** for this specific tenant-admin
 cmdlet surface (as distinct from site-level SharePoint/PnP CSOM automation, which documents
 the SharePoint resource's `Sites.FullControl.All` **Application** permission). Until that's
 confirmed, treat step 4's Entra-role grant below as the controlling access check for surface
 5, consistent with `Connect-SPOService`'s own documented requirement that the caller "must be
 a SharePoint Administrator or SharePoint Embedded Administrator."
3. **Generate an X.509 certificate** (self-signed is fine for CBA, Microsoft's guidance treats
 this like generating a password) and attach the public key to the app registration. **CNG
 certificates are not supported for Exchange/S&C app-only auth**, use a CSP key provider.
4. **Grant the app the RBAC it needs on the target system**, because an Entra application
 permission alone does not equal Exchange/Purview RBAC:
 - Surfaces 1/2: assign a built-in Entra role to the app's service principal (e.g. *Compliance
 Administrator*), **or**, for least privilege, register the app as a service principal inside
 Exchange Online and add it to a **custom role group**, 
 `New-ServicePrincipal -AppId <clientId> -ObjectId <enterpriseAppObjectId> -DisplayName "<name>"`
 then `Add-RoleGroupMember -Identity "<custom role group>" -Member <enterpriseAppObjectId>`.
 - Surface 4: assign the app's service principal a **Data Map/Data Governance role**
 (Data Curator, Data Source Administrator, Collection Admin, Policy Author, see
 `rbac-model.md` §5) on the target collection, from **Role assignments** on that collection.
 Only a Collection Admin can grant these.
 - Surface 5: assign the app's service principal the **SharePoint Administrator** (or
 **SharePoint Embedded Administrator**) **Entra directory role**, `Connect-SPOService`
 enforces this role check directly (not a Purview/Exchange role group), mirroring how
 surfaces 1/2 assign a built-in Entra role to the service principal as the simpler
 alternative to a custom role group.

> **eDiscovery is the one documented exception.** App-only authentication for **eDiscovery
> cmdlets in Security & Compliance PowerShell** is explicitly called out by Microsoft as
> **unsupported**, Microsoft's guidance is to migrate eDiscovery automation to the **Graph API**
> (`Microsoft.Graph.Security` eDiscovery cmdlets/endpoints), where app-only access is fully
> supported and is the intended path for case/hold/review-set automation. Any eDiscovery
> `deploy/`/`validate/` script in this library targets Graph, not `Connect-IPPSSession`, for that
> reason. If an existing customer automation still depends on the unsupported S&C PowerShell
> path, `ExchangeOnlineManagement` 3.10.1+ with `Connect-IPPSSession -EnableSearchOnlySession`
> is Microsoft's documented (if still unsupported) best-effort accommodation, do not build new
> automation on it.

### Connection examples used across this library

```powershell
# Surface 1, Exchange Online PowerShell, app-only, certificate thumbprint
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain

# Surface 1, Exchange Online PowerShell, app-only, certificate object (e.g. fetched from Key Vault)
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Surface 2, Security & Compliance PowerShell, app-only, certificate object
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Surface 1, Managed identity (Azure Automation / Functions / a VM with a system-assigned identity)
Connect-ExchangeOnline -ManagedIdentity -Organization $TenantDomain

# Surface 3, Microsoft Graph PowerShell SDK, app-only, certificate
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Surface 3, Microsoft Graph PowerShell SDK, managed identity
Connect-MgGraph -Identity

# Surface 4, Purview Data Map REST, client-credentials token (client secret shown; prefer
# certificate-based client assertion in production, see source 10)
$body = @{
  client_id     = $AppId
  client_secret = $ClientSecret   # resolve from Key Vault at run time, never hard-code
  grant_type    = 'client_credentials'
  resource      = 'https://purview.azure.net'
}
$token = Invoke-RestMethod -Method Post `
  -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $body

# Surface 5, SharePoint Online Management Shell, app-only, certificate thumbprint
# (module is Windows PowerShell 5.1-native, on PowerShell 7 run
# Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell first; see §6)
Connect-SPOService -Url "https://$TenantName-admin.sharepoint.com" `
  -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Surface 5, Managed identity (Azure Automation / Functions / a VM with a system-assigned identity)
Connect-SPOService -Url "https://$TenantName-admin.sharepoint.com" -ManagedIdentity
```

---

## 4. Routing table, which surface for which Purview task

| Task | Surface | Cmdlet / API family |
|---|---|---|
| DLP policy/rule create-update-delete | 2 | `New-/Set-/Remove-DlpCompliancePolicy`, `*-DlpComplianceRule` |
| Teams real-time DLP evaluation, Teams export | 3 (Graph) | Purview DLP Graph APIs for Teams (chat/channel message DLP + export); requires **Microsoft Communications DLP** enabled at the tenant level |
| Sensitivity labels & auto-labeling policies | 2 | `New-/Set-Label`, `New-/Set-LabelPolicy`, `New-/Set-AutoSensitivityLabelPolicy`/`Rule` |
| Retention labels & policies (DLM) | 2 | `New-/Set-RetentionCompliancePolicy`, `*-RetentionComplianceRule`, `New-/Set-ComplianceTag` |
| Records Management (declaration, disposition, file plan) | 2 | `New-/Set-RetentionCompliancePolicy` (records-scoped), Records Management-specific S&C cmdlets |
| Insider Risk Management policy config | 2 (partial) + portal | IRM has limited PowerShell coverage; most policy authoring is portal-driven, **VERIFY** current IRM cmdlet coverage per release before assuming a policy can be scripted end-to-end |
| Communication Compliance policy config | **Portal only, no write API** | Corrected 2026-09-10 (was incorrectly listed as Surface 2): Microsoft's `communication-compliance-policies` and `communication-compliance-configure` articles both state explicitly, verbatim, "PowerShell isn't supported for creating and managing Communication Compliance policies." Policy creation, condition tuning, reviewer assignment, and population scoping are all portal-only. The one genuinely scriptable piece is the module's own audit-log footprint via `Search-UnifiedAuditLog` (Surface 1), see `scenarios/communication-compliance/harassment-and-code-of-conduct/design.md` §2 and `scenarios/communication-compliance/financial-regulatory-supervision/design.md` §2 |
| Information Barriers segment/policy config | 2 | `New-/Set-OrganizationSegment`, `New-/Set-InformationBarrierPolicy`, `Start-InformationBarrierPoliciesApplication` |
| eDiscovery (Standard), case/hold/search, delegated | 1/2 or 3 | Core eDiscovery is supported both via S&C PowerShell cmdlets and Graph (delegated auth) |
| eDiscovery (Premium), review sets, tagging, analytics, export | 3 (Graph, app-only) | `Microsoft.Graph.Security` eDiscovery cmdlets (`Get-/New-MgSecurityCaseEdiscoveryCase*`), app-only supported here, unlike S&C PowerShell |
| eDiscovery export package **download** | Separate Purview eDiscovery API (not Graph) | Authenticate with `MSAL.PS`/`Get-MSALToken`; use `exportFileMetadata.downloadUrl` from the Graph case-operation object |
| Audit search (ad hoc, interactive/scripted) | 1 | `Search-UnifiedAuditLog` (requires an **Exchange Online** RBAC role, see `rbac-model.md` §6) |
| Entra ID's own directory audit log (role assignment changes, etc., a genuinely separate log from the Microsoft 365 unified audit log above) | 3 (Graph) | `Get-MgAuditLogDirectoryAudit` / `GET /auditLogs/directoryAudits` (`Microsoft.Graph.Reports` module); `AuditLog.Read.All` least-privileged Application permission, no separate Entra role needed for app-only calls. Retention is short and licensing-tiered (7 days Free / 30 days P1-P2), materially shorter than Audit (Standard)'s 180 days. See `scenarios/compliance-manager/entra-privileged-role-monitoring/` |
| Audit search (API, high volume/bulk export) | 3 (Graph) or Office 365 Management Activity API | **Audit Search Graph API** (newer, recommended for new automation) or the **Office 365 Management Activity API** (content-type subscription model, `Audit.General`, `DLP.All`, etc.; needs Unified Audit Logging enabled and its own app registration/permissions) |
| Subject Rights Requests (Priva-adjacent, out of default scope, `rbac-model.md` §4) | 3 (Graph) | `/privacy/subjectRightsRequests`, the `/privacy` path is **deprecated** (stopped returning data March 2025); use `/security/subjectRightsRequests` |
| DSPM for AI, protection scopes / process content / sensitivity label lookups for custom apps | 3 (Graph) | `userProtectionScopeContainer.compute` (protection scopes), `processContent` API, `sensitivityLabels` APIs |
| Data Map, register sources, run/schedule scans, manage collections | 4 (REST) | `PUT /datasources/{name}`, `PUT /datasources/{name}/scans/{name}`, `/collections` endpoints |
| Data Map history / audit query | 4 (REST, separate audit endpoint) | `POST https://api.purview-service.microsoft.com/datamap/api/audit/query` |
| Data Map, custom lineage relationships (Atlas v2) | 4 (REST) | **Relationship** operation group: `POST /datamap/api/atlas/v2/relationship` (create, `direct_lineage_dataset_dataset`, `dataset_process_inputs`, `process_dataset_outputs`), `DELETE /datamap/api/atlas/v2/relationship/guid/{guid}` (delete). **Lineage** operation group: `GET /datamap/api/atlas/v2/lineage/uniqueAttribute/type/{typeName}?attr:qualifiedName={qn}` (get by unique attribute, also used to resolve GUIDs before delete). API version pinned: `2023-09-01`, confirmed current by direct fetch of all Microsoft Learn REST reference pages cited below (§`scenarios/data-lineage/end-to-end-lineage-validation`). |
| Data Map, custom Process/DataSet entities and custom entity types (Atlas v2) | 4 (REST) | **Entity** operation group: `POST /datamap/api/atlas/v2/entity/bulk` (bulk create-or-update, confirmed upsert-by-`qualifiedName`), `DELETE /datamap/api/atlas/v2/entity/uniqueAttribute/type/{typeName}?attr:qualifiedName={qn}` (delete by unique attribute, corroborated via SDK method signatures, not an independently fetched canonical REST reference page). **Type** operation group: `POST /datamap/api/atlas/v2/types/typedefs` (bulk create, e.g. a custom type inheriting `superTypes: ["Process"]`; its own reference page warns against recreating existing types), `GET /datamap/api/atlas/v2/types/entitydef/name/{name}` (get entity def by name, used as the existence check before bulk-create). API version pinned: `2023-09-01`, confirmed current by direct fetch (§`scenarios/data-lineage/custom-process-lineage`). |
| Unified Catalog, glossary (business domains, terms) | 4 (REST) | **Business Domain** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/businessdomains(/{id})`. **Terms** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/terms(/{id})`, `POST.../terms/query`, `POST.../terms/{id}/relationships` (term-to-term `Related` links). API version pinned: `2026-03-20-preview` (current public-preview Unified Catalog API version as of this library's `curate-business-glossary` build). Read/list operations grounded separately by `scenarios/data-estate-insights/glossary-curation-coverage-report/`: `GET.../terms?domainId=&skip=&top=&parentId=&keyword=&depth=&orderBy=` (`nextLink`-style pagination, no documented maximum `top`), `GET.../terms/{id}/relationships?entityType=&relationshipType=` (the same relationship path as the term-to-term write above, also the only documented read for "which data assets are linked to this term" via `entityType=DATAASSET`), and `POST.../terms/facets` (**Get Facets**, request accepts `status`/`multiStatus`/`nameKeyword`/`owners`/`acronyms`/`domainIds`/`ids` filters plus an arbitrary `facets[].name`, but Microsoft's reference enumerates no valid facet names beyond a single worked `owner` example, not relied on for status/asset-linkage tallies for that reason, see that scenario's `design.md` §6). |
| Unified Catalog, data products, data assets | 4 (REST) | **Data Products** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/dataProducts(/{id})`, `POST.../dataProducts/query`, `POST/GET/DELETE.../dataProducts/{id}/relationships?entityType=` (the shared `EntityCategory` enum includes `DATAASSET`, `TERM`, `OBJECTIVE`, `KEYRESULT`, `CRITICALDATAELEMENT`, `DATACOLUMN`, and others, corrected here from an earlier informal "OKR" paraphrase once `scenarios/unified-catalog/manage-okrs/` fetched the enum directly; `OBJECTIVE` is the value that links a data product to an Okr-operation-group objective, since the Okr operation group itself has no relationship operation of its own, see that scenario's `design.md` §4). **Data Assets** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/dataAssets(/{id})`, `POST.../dataAssets/query`. Both share the Unified Catalog's `2026-03-20-preview` API version. **VERIFY** (pilot tenant): the exact relationship request-body shape per `entityType`, see `scenarios/unified-catalog/manage-data-products/README.md` §11. |
| Unified Catalog, OKRs (objectives and key results) | 4 (REST) | **Okr** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/objectives(/{id})`, `POST.../objectives/query`, `POST/PUT/DELETE/GET.../objectives/{id}/keyResults(/{id})`. No relationship operation exists on this operation group at all, an objective is linked to a data product via the **Data Products** operation group's own relationship operations instead (`entityType=OBJECTIVE`, row above). Identity for Create/Update is always a caller-generated `id`, unlike this repo's other Unified Catalog scenarios, a name-based existence lookup is unsafe here because Microsoft's own docs state OKR names are explicitly allowed to duplicate (`scenarios/unified-catalog/manage-okrs/design.md` §3). Shares the `2026-03-20-preview` API version; first shipped in the initial `2025-09-15-preview` release. |
| Unified Catalog, critical data elements, data columns | 4 (REST) | **Critical Data Elements** operation group: `POST/PUT/DELETE/GET /datagovernance/catalog/criticalDataElements(/{id})`, `POST.../criticalDataElements/query`, `POST/GET/DELETE.../criticalDataElements/{id}/relationships?entityType=` (links a critical data element to columns/products/terms/etc.). **Data Columns** operation group: `POST /datagovernance/catalog/dataColumns/ingest` (wraps a Data Map column, identified by `dataMapAssetId`+`dataMapColumnId`, as a Unified Catalog data column), `POST.../dataColumns/query` (idempotency check via `sourceAssetId`/`sourceColumnId` filters), `GET.../dataColumns/{id}`. No `Delete` operation exists for a data column as of this API version. Both share the Unified Catalog's `2026-03-20-preview` API version (Data Columns' full operation set and Critical Data Elements' `Count` operation were both added in this exact version). **VERIFY** (pilot tenant): every worked example for the Critical Data Elements relationship operations uses `entityType=CRITICALDATACOLUMN`, but the documented `EntityCategory` enum has no such value, it lists `DATACOLUMN` instead; see `scenarios/unified-catalog/manage-critical-data-elements/README.md` §11. |
| Data Map, resolve a table's column-level GUIDs (Atlas v2) | 4 (REST) | **Entity** operation group: `GET /datamap/api/atlas/v2/entity/guid/{guid}` (get complete entity, including `relationshipAttributes`, for a table type such as `azure_sql_table`, its `columns` relationship attribute array carries each column's own `guid` and `displayText`, confirmed via Microsoft's own `azure_sql_table` type-definition worked example, not assumed generically). API version pinned: `2023-09-01`, consistent with this repo's other Atlas Entity/Relationship/Type work (§`scenarios/unified-catalog/manage-critical-data-elements`, the first scenario in this repo to call both the Unified Catalog API and the Data Map/Atlas API for the same object graph). |
| Administrative units (scoping RBAC) | 3 (Graph) or Entra admin center | `New-MgDirectoryAdministrativeUnit`, `Add-MgDirectoryAdministrativeUnitMember` |
| Enable sensitivity-label processing for SharePoint/OneDrive files (Information Protection prerequisite) | 5 | `Set-SPOTenant -EnableAIPIntegration $true` (also enables Loop component/page labeling; needs a separate step for OneNote) |
| Enable sensitivity labels for uploaded/labeled PDF files in SharePoint/OneDrive | 5 | `Set-SPOTenant -EnableSensitivityLabelforPDF $true` (module ≥ 16.0.24211.12000) |
| Enable sensitivity labels for MP4 video files in SharePoint/OneDrive | 5 | `Set-SPOTenant -EnableSensitivityLabelForVideoFiles $true` (manual-apply only, MP4 doesn't support auto-labeling or default-label inheritance) |

---

## 5. Throttling, scale, and resilience patterns

Every `deploy/`/`validate/` script in this library that iterates over more than a handful of
objects (mailboxes, users, cases, assets) follows these patterns:

- **Exchange Online / Security & Compliance PowerShell (surfaces 1-2):**
 - The v3 module's REST-based cmdlets (`Get-EXOMailbox`, `Get-EXORecipient`, etc.) are the
 default and are more throttle-resistant than legacy RPS cmdlets, prefer the `Get-EXO*`
 family over the classic `Get-Mailbox`/`Get-Recipient` for bulk reads.
 - Request only the properties you need: use `-PropertySets`/explicit `-Properties` on the
 `Get-EXO*` cmdlets rather than pulling every attribute for every object at scale.
 - For large iterations (thousands of objects), batch and pace: process in bounded batches
 (script `param`s expose a `-BatchSize`, default a few hundred) with a short `Start-Sleep`
 between batches, and log/handle throttling responses instead of retrying in a tight loop.
 - Long-running bulk scripts should log via `-LogDirectoryPath`/`-LogLevel All` on
 `Connect-ExchangeOnline`/`Connect-IPPSSession` so a mid-run failure is diagnosable without
 re-running the whole batch.
- **Microsoft Graph (surface 3):**
 - The `Microsoft.Graph` PowerShell SDK and the Graph SDKs generally implement **automatic
 retry with exponential backoff honoring the `Retry-After` header** for non-batched requests, 
 prefer the SDK over raw `Invoke-RestMethod` for exactly this reason.
 - Raw REST calls (`Invoke-RestMethod`/`Invoke-MgGraphRequest`) must implement their own
 429-handling: catch the error, read `Retry-After` from the response headers, wait, retry, 
 never retry immediately in a tight loop.
 - Batch related calls with **JSON batching** to cut request count, but note that a batch's
 individual sub-requests are throttled independently and are **not** auto-retried by the
 SDK, retry only the failed sub-requests using the longest `Retry-After` among them.
 - Use `-All` / `@odata.nextLink` paging rather than assuming a single page contains every
 result; every validation script that lists more than one page of results paginates fully
 before asserting a count.
 - Avoid poll-and-scan patterns (repeatedly re-listing a whole collection to detect changes), 
 use delta queries or change notifications where the target resource supports them.
- **Purview Data Map / Data Governance REST (surface 4):** scan and collection operations are
 asynchronous (create/update returns immediately; poll the returned operation/run status), 
 scripts poll with backoff rather than assuming synchronous completion.
- **SharePoint Online Management Shell (surface 5):** mostly single tenant-wide `Set-SPOTenant`
 toggles in this library, so the batching/pacing patterns above don't usually apply. Microsoft's
 own guidance notes tenant configuration changes on this surface take about 15 minutes to
 propagate, scripts and their paired `validate/` checks should account for that delay (e.g. a
 retry/poll loop against `(Get-SPOTenant).<Property>`) rather than asserting the new value
 immediately after `Set-SPOTenant` returns. The one exception is
 `scenarios/information-barriers/sharepoint-onedrive-enablement-and-site-association/`, which
 loops `Set-SPOSite` over a small, human-curated site list, still not a bulk-iteration surface
 (no throttling/pacing pattern needed at that scale), but a per-object call, not a single toggle.

---

## 6. CI/CD and unattended execution guidance

- **Never commit a client secret or private key.** Store the automation certificate (or client
 secret, if used) in a secret store the pipeline resolves at run time, Azure Key Vault,
 GitHub Actions encrypted secrets, or the equivalent, and pass it into the connect cmdlet as an
 in-memory object (`-Certificate`), not a path checked into the repo.
- **Prefer certificate-based app-only auth over client secrets** for anything shipped to a buyer;
 reserve client secrets for throwaway POC/demo environments.
- **Scope the app registration's role/role-group membership to the narrowest set the script
 needs** (a custom Purview role group, or the narrowest built-in Purview role group, see
 `rbac-model.md` §9), never assign an automation service principal Global Administrator or an
 interactive admin's full role-group membership.
- **Every script exposes a `-WhatIf` (or equivalent `-DryRun`) path** that reports the change it
 would make without calling a mutating cmdlet/endpoint, per this library's code standard
 (`AGENTS.md` §4), this is validated in CI-style dry runs before any script is exercised
 against a real tenant.
- **Azure-hosted runners** (Azure Automation runbooks, Azure Functions, Azure DevOps
 self-hosted agents on an Azure VM) should use a **managed identity** instead of a
 certificate/secret entirely, where the surface supports it (surfaces 1, 3, and 5), this
 removes the credential-rotation problem altogether.
- **GitHub Actions / non-Azure runners** authenticate with the certificate-based app-only pattern
 above, with the certificate stored as a base64-encoded encrypted secret and materialized to an
 in-memory `X509Certificate2` at the start of the job, never written to the runner's disk.
- **Surface 5 needs a Windows runner (or a Windows-based Azure Automation/Function worker).**
 `Microsoft.Online.SharePoint.PowerShell` is a Windows PowerShell 5.1-native module; running it
 under PowerShell 7 requires the `-UseWindowsPowerShell` compatibility layer, which itself only
 runs on Windows. Unlike surfaces 1 and 3, both officially supported on Linux/macOS PowerShell 7
 runners, **this repo has found no officially documented cross-platform path for surface 5**.
 A GitHub Actions workflow or Azure DevOps pipeline that includes a surface-5 step must pin a
 `windows-latest` (or self-hosted Windows) runner for that step, even if every other step in the
 same pipeline runs on Linux.

---

## 7. How scenarios should cite the automation surface

Each scenario's `deploy/` and `validate/` scripts, and the README's **Step-by-step
implementation** section, must state:

1. Which of the **five automation surfaces** (§1) the scenario's code uses, and why (e.g. "Graph,
 because eDiscovery Premium app-only auth on S&C PowerShell is unsupported").
2. The **exact module(s) and minimum version** required, matching the script's `#Requires` line.
3. The **authentication pattern** used (§3), certificate app-only is the default; call out any
 deviation and why.
4. Any **throttling/scale consideration** specific to the scenario's expected object count (§5).
5. A pointer back to `rbac-model.md` for the **role/permission** the automation's service
 principal needs, automation surface and RBAC are documented separately but must always be
 read together.

---

## Sources (Microsoft Learn, re-verify before building a production pipeline)

- About the Exchange Online PowerShell module (install, OS/PowerShell-version support matrix, Linux `Connect-IPPSSession` limitation), <https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2>
- App-only authentication for unattended scripts in Exchange Online PowerShell and Security & Compliance PowerShell, <https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2>
- Connect-IPPSSession reference, <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
- Use Azure managed identities to connect to Exchange Online PowerShell, <https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity>
- Install the Microsoft Graph PowerShell SDK (submodule-scoped install guidance), <https://learn.microsoft.com/powershell/microsoftgraph/installation>
- Authentication module cmdlets / app-only authentication with the Microsoft Graph PowerShell SDK, <https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands> and <https://learn.microsoft.com/powershell/microsoftgraph/app-only>
- Assign permissions in eDiscovery, app-only configuration and its unsupported status, <https://learn.microsoft.com/purview/edisc-permissions#configure-app-only-authentication-for-ediscovery-powershell>
- Set up app-only access for Microsoft Purview eDiscovery (Graph), <https://learn.microsoft.com/graph/security-ediscovery-appauthsetup>
- Use Microsoft Purview APIs for eDiscovery (Graph eDiscovery cmdlets + separate export-download API), <https://learn.microsoft.com/purview/edisc-ref-api-guide>
- Microsoft Purview data security and governance APIs (protection scopes, process content, DSPM-for-AI), <https://learn.microsoft.com/graph/security-datasecurityandgovernance-overview>
- Microsoft Purview Data Loss Prevention Graph APIs for Teams (service description), <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-graph-apis-for-teams-data-loss-prevention-dlp-and-for-teams-export>
- Use the Microsoft Graph subject rights request API (and `/privacy` → `/security` path deprecation), <https://learn.microsoft.com/graph/api/resources/subjectrightsrequest-subjectrightsrequestapioverview> and <https://learn.microsoft.com/graph/api/subjectrightsrequest-get>
- Office 365 Management Activity API reference, <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference>
- Learn about auditing solutions in Microsoft Purview (Audit Search Graph API, `Search-UnifiedAuditLog`, bandwidth by license), <https://learn.microsoft.com/purview/audit-solutions-overview>
- Tutorial: Authenticate for Microsoft Purview data-plane APIs (Data Map REST), <https://learn.microsoft.com/purview/data-gov-api-rest-data-plane>
- Data Map history / audit query REST API, <https://learn.microsoft.com/purview/data-map-history>
- Relationship - Create REST reference (Data Map data-plane, API version 2023-09-01), <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/create>
- Relationship - Delete REST reference (API version 2023-09-01), <https://learn.microsoft.com/rest/api/purview/datamapdataplane/relationship/delete>
- Lineage - Get By Unique Attribute REST reference (API version 2023-09-01), <https://learn.microsoft.com/rest/api/purview/datamapdataplane/lineage/get-by-unique-attribute>
- Entity - Bulk Create Or Update REST reference (API version 2023-09-01), <https://learn.microsoft.com/rest/api/purview/datamapdataplane/entity/bulk-create-or-update>
- Purview Unified Catalog REST API, Terms operation group, <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/terms?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
- Purview Unified Catalog REST API, Business Domain operation group, <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/business-domain?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
- Purview Unified Catalog REST API, Data Products operation group, <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
- Purview Unified Catalog REST API, Data Assets operation group, <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-assets?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
- Unified Catalog API (Public Preview) overview, scope, GA-only coverage, preview API versions, Swagger specification links, <https://learn.microsoft.com/rest/api/purview/unified-catalog-api-overview>
- Purview Unified Catalog REST API, Okr operation group, and the operation-groups index confirming it has no relationship operation (unlike Data Products/Critical Data Elements/Terms), <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/okr?view=rest-purview-purview-unified-catalog-2026-03-20-preview> and <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/operation-groups>
- Purview Unified Catalog REST API, Data Products - Create Relationship, and its shared `EntityCategory` enum confirming `OBJECTIVE`/`KEYRESULT` as valid values, <https://learn.microsoft.com/rest/api/purview/purview-unified-catalog/data-products/create-relationship?view=rest-purview-purview-unified-catalog-2026-03-20-preview>
- Microsoft Graph throttling guidance, <https://learn.microsoft.com/graph/throttling>
- Paging Microsoft Graph data, <https://learn.microsoft.com/graph/paging>
- Why use a Microsoft Graph SDK (built-in retry/backoff behavior), <https://learn.microsoft.com/microsoft-cloud/dev/dev-proxy/concepts/why-use-microsoft-graph-sdk>
- Enable sensitivity labels for files in SharePoint and OneDrive (`Set-SPOTenant -EnableAIPIntegration`/`-EnableSensitivityLabelforPDF`/`-EnableSensitivityLabelForVideoFiles`, module version requirements, ~15-minute propagation), <https://learn.microsoft.com/purview/sensitivity-labels-sharepoint-onedrive-files>
- Connect-SPOService reference (app-only certificate parameter set, managed-identity parameter set, "must be a SharePoint Administrator" requirement), <https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice>
- Get started with SharePoint Online Management Shell (module install, and the `-UseWindowsPowerShell` requirement to run it from a PowerShell 7 console), <https://learn.microsoft.com/powershell/sharepoint/sharepoint-online/connect-sharepoint-online>
- Granting access via Entra ID Application Permissions for SharePoint Online (certificate-only app-only model; the SharePoint resource's `Sites.FullControl.All` Application permission for site-level CSOM/PnP automation, a different, more specific gap than the `Connect-SPOService` tenant-admin surface itself, see §3), <https://learn.microsoft.com/sharepoint/dev/solution-guidance/security-apponly-azuread>

> **Disclaimer:** cmdlet names, supported-platform matrices, and Graph permission names change as
> Purview and the Graph PowerShell SDK ship updates. Validate every cmdlet and endpoint against
> the live module help (`Get-Help <cmdlet> -Online`) and the Graph API reference for the target
> tenant's cloud (Commercial / GCC / GCC-High / DoD) before production use.
