---
part: "runbook"
parent: "data-map/verify-purview-entra-graph-prerequisites"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Microsoft Entra admin center → **Identity** → **Roles & administrators** → **Directory Readers**
   → **Assignments**. Confirm each Managed-Instance-backed Purview source's managed identity is
   listed. This is the same view the sibling scenario's validation steps check 4 already points at for
   a single instance - this scenario's script automates checking it across every instance in the
   inventory at once, plus the drift check the portal view doesn't do for you.
2. For each managed instance, obtain its managed identity's object ID (needed for step 4's CSV):
   ```powershell
   (Get-AzSqlInstance -ResourceGroupName 'rg-contoso-data' -Name 'mi-contoso-prod').Identity.PrincipalId
   ```
3. If a FAIL is found (an instance's identity is missing), remediate per the sibling scenario's own
   the implementation steps step 3 - either the Entra ID pane banner on the instance, or Microsoft's own
   published PowerShell script for this grant (cited in that scenario's the references reference 3) -
   both require a **Privileged Role Administrator**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 0. One-time: Connect to Microsoft Graph with the least-privileged permission
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
# App registration must hold the RoleManagement.Read.Directory application permission, admin-consented.

# 1. Build (or update) the inventory CSV - one row per Managed-Instance-backed Purview source
@'
InstanceName,ResourceGroupName,PurviewDataSourceName,PrincipalObjectId
mi-contoso-prod,rg-contoso-data,mi-contoso-prod-customerdb,<paste from step 5.2>
mi-contoso-eu,rg-contoso-data-eu,mi-contoso-eu-customerdb,<paste from step 5.2>
'@ | Set-Content -Path './managed-instances.csv'

# 2. Dry run - reports every finding, writes nothing
./deploy/Confirm-DirectoryReadersMembership.ps1 `
    -ManagedInstanceInventoryPath './managed-instances.csv' `
    -ReportPath './out/directory-readers-membership-report.json' `
    -WhatIf

# 3. Run for real - same findings, plus writes the JSON report
./deploy/Confirm-DirectoryReadersMembership.ps1 `
    -ManagedInstanceInventoryPath './managed-instances.csv' `
    -ReportPath './out/directory-readers-membership-report.json'

# 4. Validate the inputs/outputs (offline, no tenant connection needed)
./validate/Test-DirectoryReadersMembershipInputs.ps1 `
    -ManagedInstanceInventoryPath './managed-instances.csv' `
    -ReportPath './out/directory-readers-membership-report.json'
```

The deploy script uses the **Microsoft Graph PowerShell SDK** - automation surface 3 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). Step 1 (building the CSV) is a one-time, out-of-band step this
script does not perform - see the design notes.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Directory role monitored | `Directory Readers` (built-in Entra role) | The specific role *Scan Azure SQL Managed Instance and Classify Sensitive Columns* (the prerequisites) documents as required |
| Role lookup call | `Get-MgDirectoryRole -Filter "displayName eq 'Directory Readers'"` | Only returns roles *activated* at least once in the tenant - see section 11 |
| Membership lookup call | `Get-MgDirectoryRoleMember -DirectoryRoleId <id> -All` | Returns member `Id` + `@odata.type` only; no display name - resolved best-effort for the drift report only |
| Least-privileged Graph permission | `RoleManagement.Read.Directory` (application) | Confirmed for both cmdlets above - the references |
| Inventory CSV required columns | `InstanceName`, `PrincipalObjectId` | `ResourceGroupName`, `PurviewDataSourceName` optional, carried through into the report for readability only |
| Per-row verdict | `PASS` (current member) / `FAIL` (not a current member) | `FAIL` also raised for every row if the role has never been activated in the tenant - see the known limitations |
| Drift verdict | `WARN` per current member not present in the inventory | Never fails the run - a shared, tenant-wide-flavored role legitimately has members this inventory doesn't know about |
| Report format | JSON (`-ReportPath`), gated by `ShouldProcess`/`-WhatIf` | Only mutating side effect this script has - see the design notes |
| Exit code | Non-zero if any inventory row is `FAIL` | Drift (`WARN`) alone does not affect exit code - safe for a CI-style pre-flight gate |

Full cmdlet/permission grounding: `deploy/Confirm-DirectoryReadersMembership.ps1`'s inline comments
and its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**Recommended cadence:** daily or weekly, scheduled alongside (or just before) the sibling
scenario's own recurring scan trigger - catching a revoked Directory Readers grant *before* the next
scheduled scan run is strictly more useful than discovering it from a failed scan afterward.
Directory Readers membership changes far less often than, say, a DLP policy, so a daily/weekly
cadence (not hourly) is proportionate.

**KPIs / signal to watch:**
- **FAIL count trend.** Should be `0` in steady state. A new, unexpected `FAIL` is a near-immediate
  actionable signal - the affected instance's Purview scan (and any other Entra-authenticated
  connection to it) is now broken tenant-wide, not just for this scenario.
- **Drift (`WARN`) list membership.** Review each new entry once, confirm it's an authorized
  workload, and either add it to the inventory (if it's expected to be there going forward) or
  escalate to the identity/IAM team (if it isn't) - same Blue Team finding this scenario exists to
  close for the sibling scenario, generalized.

**Alerting note - exit code alone under-reports.** The script's exit code is non-zero only for a
`FAIL` (a missing expected member); a new `WARN` drift entry - someone else being added to a
tenant-wide, security-sensitive role - does **not** flip the exit code, by design (section 6: drift is
informational, not fatal). A pipeline that gates only on exit code will silently miss new drift.
Wire your scheduler to also inspect the JSON report's `DriftMemberCount` (or diff the `DriftMembers`
array against the previous run) and alert a human on any increase, not just on a non-zero exit.

**Report history - timestamp `-ReportPath` per run.** Unlike this library's rolling audit-trail export
scripts (e.g. *Entra Privileged Role Monitoring*), this script's
report is a **point-in-time snapshot** that overwrites whatever is at `-ReportPath` - it does not
merge or accumulate history itself. To trend the FAIL-count KPI above over time,
have the calling scheduler pass a date-stamped path each run (e.g.
`./out/directory-readers-membership-report-$(Get-Date -Format 'yyyy-MM-dd').json`) and retain the
series, rather than relying on a single overwritten file to answer "since when."

**Incident-response runbook:**
1. A new `FAIL` appears → confirm via the portal cross-check that it's real, not a stale
   inventory row (wrong `PrincipalObjectId`).
2. If real, escalate to a **Privileged Role Administrator** to re-grant Directory Readers to the
   affected instance's managed identity (the sibling scenario's implementation steps step 3).
3. Re-run this scenario's deploy script to confirm `PASS`, then independently re-run the sibling
   scenario's own `validate/Test-AzureSqlManagedInstanceDataMapScan.ps1` and trigger a fresh scan run
   to confirm end-to-end recovery - a Directory Readers `PASS` alone does not, by itself, prove the
   scan is healthy again (e.g. `db_datareader` or network-path prerequisites could independently be
   broken at the same time).

**Downstream use:** purely a health/pre-flight signal for *Scan Azure SQL Managed Instance and Classify Sensitive Columns*
and any future Managed-Instance-backed Purview source this library adds - this scenario does not feed
classification, labeling, or DLP scenarios directly.

## Rollback and decommission

This scenario creates no tenant state - see the rollback runbook for the full (short) procedure: stop the
schedule, decide the fate of any retained `-ReportPath` JSON files, and revoke the
`RoleManagement.Read.Directory` Graph permission grant from the automation app registration.

## References

1. *Scan Azure SQL Managed Instance and Classify Sensitive Columns* - the sibling scenario this
   fragment protects; see its the prerequisites and the validation steps and operations and tuning and the Blue Team review (finding 1) for the
   original gap this scenario closes.
2. Get-MgDirectoryRole (Microsoft.Graph.Identity.DirectoryManagement module, `-Filter` parameter) - <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgdirectoryrole>
3. Get-MgDirectoryRoleMember (Microsoft.Graph.Identity.DirectoryManagement module, `-DirectoryRoleId`/`-All` parameters; `RoleManagement.Read.Directory` least-privileged application permission) - <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgdirectoryrolemember>
4. List directoryRoles (Microsoft Graph REST reference - confirms the operation "lists the directory roles that are activated in the tenant," the basis for this scenario's role-not-found handling) - <https://learn.microsoft.com/graph/api/directoryrole-list>
5. List members of a directory role (Microsoft Graph REST reference, `RoleManagement.Read.Directory` least-privileged permission) - <https://learn.microsoft.com/graph/api/directoryrole-list-members>
6. directoryRole resource type (`id`, `displayName`, `roleTemplateId` properties) - <https://learn.microsoft.com/graph/api/resources/directoryrole>
7. Directory Readers role in Microsoft Entra ID for Azure SQL (why Managed Instance needs it) - <https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-directory-readers-role>
8. Assign Directory Readers role to a Microsoft Entra group and manage role assignments (the Managed-Instance-specific grant tutorial, same page the sibling scenario's own the references reference 3 cites) - <https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-directory-readers-role-tutorial>
9. Managed Identity in Microsoft Entra for Azure SQL (`Get-AzSqlInstance`/`Identity.PrincipalId` pattern this scenario's inventory-building step uses) - <https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity>
10. Microsoft Graph PowerShell SDK authentication and throttling guidance - [Automation surface, sections 3 and 5](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended).
11. Check Azure data sources to register and scan in Microsoft Purview - Microsoft's own broader, one-time readiness checklist for the Purview account's managed identity (Reader/`db_datareader`/network/firewall/Entra-authentication-enabled checks); complementary to, not overlapping with, this scenario's Directory Readers-specific, ongoing check - see the prerequisites callout above - <https://learn.microsoft.com/purview/data-map-data-sources-check-azure-readiness>

> Re-verify all links and the least-privilege permission claim against current Microsoft Learn
> before a customer-facing deployment. **Grounding note:** this scenario's environment could not
> directly fetch `learn.microsoft.com` pages (egress-blocked in this build -
> "Blocked / needs user"); all citations above are grounded via Microsoft Learn-hosted search
> results (URL + synthesized excerpt), corroborated across at least two independent queries per
> fact, not a verbatim page fetch. Re-verify with a direct fetch or the Microsoft Learn MCP tool
> when either is available before a customer-facing deployment.