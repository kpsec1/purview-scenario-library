---
part: "runbook"
parent: "compliance-manager/entra-privileged-role-monitoring"
---
## Implementation steps

### App registration and permission grant (one-time)

1. Register (or reuse) an Entra app registration for unattended automation - see
   [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended)'s "App-only setup" steps.
2. Grant it the **`AuditLog.Read.All`** Microsoft Graph **Application** permission (both scripts)
   plus, if running `Export-RoleAssignableGroupMembershipAuditTrail.ps1`, **`Group.Read.All`** and
   **`RoleManagement.Read.Directory`**, and complete tenant-wide admin consent. No Exchange/Purview role group
   assignment is needed for either script - unlike surfaces 1/2 in this library, surface 3's app-only
   calls are governed purely by the consented Graph permission(s) ([RBAC model, section 8](/docs/rbac-model/#8-powershell--graph-automation---connecting-with-the-right-role)).
3. Generate and attach a certificate per [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended) (CBA is this library's
   default pattern; a client secret is acceptable only for a quick POC).

### Script path - the audit-trail export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Dry run - queries the last 24 hours, reports what would be merged, writes nothing
./deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 -OutputCsvPath './out/entra-privileged-role-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the tenant's actual retention window
# (30 days shown; use 7 on Entra ID Free - see Section 11)
./deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) `
    -OutputCsvPath './out/entra-privileged-role-audit-trail.csv'

# 4. Recurring run - schedule DAILY, not weekly (Section 8 explains why this cadence differs
# from the Compliance Manager sibling script's weekly-safe default)
./deploy/Export-EntraPrivilegedRoleAuditTrail.ps1 -OutputCsvPath './out/entra-privileged-role-audit-trail.csv'

# 5. Validate
./validate/Test-EntraPrivilegedRoleAuditTrail.ps1 -AuditTrailCsvPath './out/entra-privileged-role-audit-trail.csv'
```

The script uses the Microsoft Graph PowerShell SDK's `Microsoft.Graph.Reports` module -
automation surface 3 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - because Entra ID's own directory audit
log has no Exchange/Security & Compliance PowerShell surface; it is exclusively a Graph resource.
Throttling: the script calls the SDK cmdlet directly (never a raw REST call), so it inherits the
SDK's automatic retry-with-backoff on `Retry-After` per [Automation surface, section 5](/docs/automation-surface/#5-throttling-scale-and-resilience-patterns) without
needing its own 429-handling - expected daily event volume for a 4-role population is low enough
that this is a defense-in-depth note, not an anticipated real bottleneck.

### Companion script path - role-assignable-group membership

Run alongside (not instead of) the script above - same daily cadence, same certificate/app
registration (with the two additional permissions from the prerequisites):

```powershell
# 1. Connect (same app registration, now also holding Group.Read.All and RoleManagement.Read.Directory)
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 2. Dry run - discovers the current monitored group set, queries the last 24 hours, reports what
# would be merged, writes nothing
./deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1 -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the tenant's actual retention window
./deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) `
    -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv'

# 4. Recurring run - schedule DAILY, same reasoning as the sibling script (Section 8)
./deploy/Export-RoleAssignableGroupMembershipAuditTrail.ps1 -OutputCsvPath './out/role-assignable-group-membership-audit-trail.csv'

# 5. Validate
./validate/Test-RoleAssignableGroupMembershipAuditTrail.ps1 -AuditTrailCsvPath './out/role-assignable-group-membership-audit-trail.csv'
```

This script additionally uses `Microsoft.Graph.Groups` (`Get-MgGroup`) and
`Microsoft.Graph.Identity.Governance` (`Get-MgRoleManagementDirectoryRoleDefinition`,
`Get-MgRoleManagementDirectoryRoleAssignment`) for its Phase 1 discovery, on top of the same
`Microsoft.Graph.Reports` call the sibling script uses for Phase 2. All calls go through SDK
cmdlets - same throttling note as above applies to all three.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Graph resource | `/auditLogs/directoryAudits` (`Get-MgAuditLogDirectoryAudit`) | the design notes |
| Server-side filter | `category eq 'RoleManagement' and activityDateTime ge <start> and activityDateTime le <end>` | the design notes - the one compound-`and` shape grounded against a Microsoft worked example |
| Monitored activities (client-side filter) | `Add member to role`, `Add member to role scoped over Restricted Management Administrative Unit`, `Add scoped member to role`, `Add member to role outside of PIM (permanent)`, `Remove member from role`, `Remove member from role scoped over Restricted Management Administrative Unit`, `Remove scoped member from role` | Core Directory category plus one PIM-service out-of-PIM detection activity, the design notesa; the rest of PIM-mediated activation remains out of scope, the design notes |
| Monitored roles (`-PrivilegedRoleDisplayNames`) | `Global Administrator`, `Compliance Administrator`, `Compliance Data Administrator`, `Security Administrator` | Matches [RBAC model, section 3](/docs/rbac-model/#3-microsoft-entra-roles-that-map-into-purview)'s mapping table; parameterized, override for a different role population |
| Default lookback window | 24 hours (`-StartDate`/`-EndDate`) | Shorter than the Compliance Manager sibling's 7-day default - matches this log's shorter worst-case retention, the design notes |
| Idempotency | De-duplicate by the record's own documented `Id` (GUID) on every merge | Simpler than the Compliance Manager sibling's composite-hash key - the design notes |

Full cmdlet parameter grounding: `deploy/Export-EntraPrivilegedRoleAuditTrail.ps1`'s inline comments
and its `.NOTES` block cite the exact Microsoft Learn reference pages.

**`Export-RoleAssignableGroupMembershipAuditTrail.ps1` (companion script):**

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Phase 1 discovery filters | `isAssignableToRole eq true` (`Get-MgGroup`); `DisplayName eq '<role>'` (`Get-MgRoleManagementDirectoryRoleDefinition`); `roleDefinitionId eq '<id>'` (`Get-MgRoleManagementDirectoryRoleAssignment`) | All three directly confirmed by Microsoft worked examples - the design notes |
| Phase 2 Graph resource | `/auditLogs/directoryAudits` (`Get-MgAuditLogDirectoryAudit`) - same resource as the sibling script | the design notes |
| Phase 2 server-side filter | `category eq 'GroupManagement' and activityDateTime ge <start> and activityDateTime le <end>` | Same grounded shape as the sibling script's own filter, applied to a different category |
| Monitored activities (client-side filter) | `Add member to group`, `Remove member from group` (Core Directory), `Bulk import group members - finished (bulk)`, `Bulk remove group members - finished (bulk)` (Microsoft Entra (AAD) Management UX) | All four are confirmed real `GroupManagement`-category activity names, the design notes; the bulk pair's `targetResources` shape is a disclosed open VERIFY - the known limitations |
| Monitored roles (`-PrivilegedRoleDisplayNames`) | Same 4 roles as the sibling script | Keep the two scripts' role lists in sync if customized |
| Default lookback window | 24 hours (`-StartDate`/`-EndDate`) | Same reasoning as the sibling script |
| Idempotency | De-duplicate by the record's own documented `Id` (GUID) on every merge | Same model as the sibling script - the design notes |
| Discovery caching | **None** - Phase 1 re-runs on every invocation | A group added to or removed from a monitored role between runs is picked up automatically on the next run |

## Operations and tuning

**Review cadence:** run this script **daily** - not weekly, unlike the Compliance Manager sibling
- because the underlying Entra directory audit log's own retention can be as short as **7 days**
on Microsoft Entra ID Free; a weekly cadence risks a missed prior run silently losing events
forever, not just delaying their discovery. Overlapping-window de-duplication (by `Id`) makes daily
runs safe even when nothing changed. **Immediately** (not on the daily cadence) review any
`Write-Warning` the script emits - every matched row is, by construction, a change to one of the
four most powerful role assignments in the tenant. Treat **any** Global Administrator role change
as a near-zero-tolerance signal per the script's own differentiated warning severity.

**KPIs to watch:**
- **Event volume outside a planned onboarding/offboarding/access-review window** - the primary
  signal this script exists to produce. A tenant with disciplined change management should see
  this CSV grow rarely and predictably.
- **Any row this scenario surfaces with no corresponding `ComplianceManagerRolesChange` row in
  *Assess Against ISO/IEC 27001:2022*'s own audit trail for the same principal/window** - direct proof of
  the blind spot this scenario closes; investigate every such row as a genuine "who granted
  themselves audit-evidence access without Compliance Manager knowing" event.
- **Gaps in the CSV's own coverage** - if the daily schedule itself fails to run (e.g. certificate
  expiry, a Graph API throttling response), the script produces no output at all for that day,
  which is silent unless the schedule's own job-failure alerting is wired up separately.
  **Wire this up from day one** - whatever scheduler runs this daily (Azure Automation runbook,
  Task Scheduler, a CI pipeline's scheduled trigger) should alert a human on job failure, not just
  on the script's own `Write-Warning` output; a run that never happened produces no warning either.

**Incident-response runbook (unplanned privileged-role change detected):**
1. **Triage** - pull the full row (`InitiatedBy`, `ActivityDateTime`, `Result`, `ResultReason`,
   `CorrelationId`) to see exactly who made the change, when, and whether Entra itself reports it
   as successful.
2. **Classify** - does this match a documented onboarding/offboarding/access-review event, or is it
   unplanned?
3. **Planned:** document the change and its business justification in whatever change-management
   record the organization already keeps for privileged access - this scenario's CSV is evidence
   of *when* the change happened, not a substitute for a change-approval record.
4. **Unplanned:** escalate immediately to whoever owns Entra ID Global Administrator/Privileged Role
   Administrator oversight. Check whether the same principal also appears in
   *Assess Against ISO/IEC 27001:2022*'s own audit trail around the same time (a coordinated attempt to both
   gain and cover implicit Compliance Manager access). Consider whether the initiating account
   itself needs its access reviewed or suspended pending investigation.
5. **Document** - every reviewed event, planned or not, is retained in this CSV as evidence; do not
   delete rows from it.

**`Export-RoleAssignableGroupMembershipAuditTrail.ps1` operations note:** run on the **same daily
schedule** as the sibling script - they share the same underlying log and retention constraints.
Its console `Write-Warning` output includes **two** distinct signal types worth distinguishing in
an on-call runbook: a `"Monitored group discovered"` warning (Phase 1 - informational; a group is
now in scope, not itself an incident) and a `"Monitored-group membership change detected"` warning
(Phase 2 - the actual signal this script exists to produce, follow the same incident-response
runbook above). A tenant with **zero** role-assignable groups holding any of the four roles will
never see either warning - that is the expected, healthy state for most tenants.

## Rollback and decommission

See the rollback runbook for the full procedure - there is no portal object to roll back for either script
in this scenario (both are read-only); decommissioning means stopping the schedule(s), deciding the
CSVs' retention fate, and revoking the app registration's Graph permission grants.

## References

1. Microsoft Purview Compliance Manager - assess-against-iso27001 (the sibling scenario this one
   closes a Red Team finding for) - *Assess Against ISO/IEC 27001:2022*
2. Get started with Compliance Manager (role types, and users with implicit access via Entra roles
   not appearing on the User access settings page) - <https://learn.microsoft.com/purview/compliance-manager-setup>
3. directoryAudit resource type (`id`, `activityDisplayName`, `category`, `targetResources`,
   `initiatedBy` properties) - <https://learn.microsoft.com/graph/api/resources/directoryaudit>
4. List directoryAudits (permissions table: `AuditLog.Read.All` least-privileged; delegated-access
   role requirement: Reports Reader / Security Administrator / Security Reader) - <https://learn.microsoft.com/graph/api/directoryaudit-list>
5. Get-MgAuditLogDirectoryAudit reference (`-Filter`/`-All`/`-PageSize` parameters,
   `Microsoft.Graph.Reports` module) - <https://learn.microsoft.com/powershell/module/microsoft.graph.reports/get-mgauditlogdirectoryaudit>
6. Microsoft Entra data retention (7 days Free / 30 days P1-P2 for audit logs) - <https://learn.microsoft.com/entra/identity/monitoring-health/reference-reports-data-retention>
7. Microsoft Entra audit log categories and activities (Core Directory RoleManagement: "Add member
   to role" / "Remove member from role"; PIM RoleManagement: "Add member to role outside of PIM
   (permanent)", confirmed distinct from the Core Directory activities - the source resolving
   reference 13's discrepancy) - <https://learn.microsoft.com/entra/identity/monitoring-health/reference-audit-activities>
8. Manage audit log retention policies (Purview Audit (Premium) default 1-year retention for the
   `AzureActiveDirectory` workload) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
9. targetResource resource type (`type`/`displayName` per target, including `Role`) - <https://learn.microsoft.com/graph/api/resources/targetresource>
10. How to investigate the Conditional Access block policy alert (worked example combining `eq` and
    `ge` with `and` directly against `/auditLogs/directoryAudits`, grounding this scenario's filter
    composition) - <https://learn.microsoft.com/entra/identity/monitoring-health/scenario-health-conditional-access-block-policy>
11. Assign Microsoft Entra roles in Privileged Identity Management (PIM time-bound/eligible
    assignment model, cited for this scenario's Non-goals) - <https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user>
12. Configure security alerts for Microsoft Entra roles in Privileged Identity Management (the
    native "Roles are being assigned outside of Privileged Identity Management" High-severity
    alert, and the P2/Governance licensing gate on it) - <https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-how-to-configure-security-alerts>
13. Security operations for privileged accounts in Microsoft Entra ID (the differently-suffixed
    "Add member to role (permanent)" detection guidance, grounded against reference 7 as the same
    activity as "Add member to role outside of PIM (permanent)" and now included in
    `$monitoredActivities`) - <https://learn.microsoft.com/entra/architecture/security-operations-privileged-accounts>
14. Use Microsoft Entra groups to manage role assignments (role-assignable groups; membership
    governance is expected to happen at the group level; 500 role-assignable group maximum per
    tenant - grounds the companion script's discovery design) - <https://learn.microsoft.com/entra/identity/role-based-access-control/groups-concept>
15. Get-MgGroup reference (Application permissions table, listing `Group.Read.All`) - <https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggroup>
16. Get-MgRoleManagementDirectoryRoleAssignment reference (permissions table: `RoleManagement.Read.Directory`
    least-privileged application permission) - <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.governance/get-mgrolemanagementdirectoryroleassignment>
17. List Microsoft Entra role assignments (worked PowerShell examples: `Get-MgRoleManagementDirectoryRoleAssignment
    -Filter "PrincipalId eq '<group id>'"` for a group; role-definition-then-assignment pattern) - <https://learn.microsoft.com/entra/identity/role-based-access-control/view-assignments>
18. Use the `$filter` query parameter (worked example: `~/groups?$filter=isAssignableToRole eq true`
    as a default, non-advanced-query `eq` filter) - <https://learn.microsoft.com/graph/filter-query-parameter>
19. Advanced query capabilities on Microsoft Entra ID objects (`eq` filters work by default; `ne`/
    `not`/`endswith` require `ConsistencyLevel: eventual` + `$count`) - <https://learn.microsoft.com/graph/aad-advanced-queries>
20. Get-EntraAuditDirectoryLog reference, Example 9 (worked filter confirming the `targetResources`
    `Group`-type entry's `id` property for "Add member to group" events) - <https://learn.microsoft.com/powershell/module/microsoft.entra.reports/get-entraauditdirectorylog>

> Re-verify all links and the retention/licensing figures against current Microsoft Learn before a
> customer-facing deployment - Entra ID's audit-log retention model is tied to licensing tier and
> has changed before, and can change again.