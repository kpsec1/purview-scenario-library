---
part: "runbook"
parent: "audit/retention-policy-management"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to confirm the five extra durations)

1. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) with an account
   holding the **Organization Configuration** role → **Audit** solution card → **Create audit
   retention policy**.
2. Set **Policy name** (unique, ≤64 chars, unchangeable after creation), **Description**
   (≤256 chars), **Users** (blank = all users), **Record type** (blank = all types; selecting one
   type reveals an **Activities** picker), **Duration** (`7 Days`/`30 Days`/`6 Months`/`9 Months`/
   `1 Year`/`3 Years`/`5 Years`/`7 Years`/`10 Years` - the portal's full list, wider than the
   PowerShell enum the configuration reference uses), and **Priority** (1 = highest, 10000 = lowest, globally unique).
3. **Save**. The policy appears in the **Audit retention policies** dashboard.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - validates the config, checks priority/cap constraints, makes no changes
./deploy/New-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json -WhatIf

# 3. Apply - creates missing policies, updates drifted ones, no-ops on already-matching ones
./deploy/New-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json

# 4. Validate
./validate/Test-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json
```

The deploy script uses `New-`/`Set-UnifiedAuditLogRetentionPolicy` (Security & Compliance
PowerShell) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first). **Only** the four
PowerShell-supported durations can be authored this way - see the configuration reference and the known limitations for the five the portal
alone can create.

## Configuration reference

| Setting | PowerShell (`-RetentionDuration`) | Portal-only additions | Notes |
|---|---|---|---|
| Retention duration | `ThreeMonths`, `SixMonths`, `NineMonths`, `TwelveMonths`, `TenYears` | `7 Days`, `30 Days`, `3 Years`, `5 Years`, `7 Years` | Confirmed by directly comparing the official cmdlet reference's enum against the official portal-duration list - a real cmdlet-vs-portal gap, not a VERIFY |
| `Name` | Required, unique, ≤64 chars, **unchangeable after creation** | | Both surfaces |
| `Description` | Optional, ≤256 chars | | |
| `Priority` | Required, `1`-`10000` integer, **globally unique** across every policy in the org (1 = highest) | | Enforced pre-flight by `deploy/New-AuditRetentionPolicy.ps1` against the live tenant, not just the config file |
| `RecordTypes` | Optional; blank = all record types | See [`AuditLogRecordType`](https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype) for the enum | Can't combine with `Operations` if more than one `RecordTypes` value is set |
| `Operations` | Optional; requires **exactly one** `RecordTypes` value | See [Audited activities](https://learn.microsoft.com/purview/audit-log-activities) for the values | |
| `UserIds` | Optional; blank = all users | | |
| Tenant cap | **50** custom policies (default policy not counted) | | Checked pre-flight |
| Lifecycle | Create, edit, delete only - **no** enable/disable/simulation mode | | Unlike this library's DLP/DLM scenarios - see the design notes |

Full cmdlet parameter grounding: `deploy/New-AuditRetentionPolicy.ps1`'s inline comments and
`.NOTES` cite the exact Microsoft Learn reference pages.

## Operations and tuning

**Review cadence:** review this config alongside every other Purview policy in this library on the
same quarterly cadence - a retention duration decided today may need to widen (a new regulatory
driver, a legal hold) or narrow (a workload that turned out to be pure noise) later. Re-run
`validate/Test-AuditRetentionPolicy.ps1` at each review to catch configuration drift (a portal
admin who edited a policy directly, bypassing this scenario's config file).

**Coordinating with *Forensic Investigation of a Compromised Account*:** before scoping any forensic investigation to
a window longer than 180 days, confirm the target user/workload is actually covered by a
qualifying license and/or one of this scenario's custom policies - otherwise the investigation
will come back empty for reasons that have nothing to do with whether the activity happened.

**Priority planning:** reserve a numbering convention up front (e.g., user-scoped narrow policies
in the 1-999 range, workload-wide broad policies in the 1000+ range) so a new policy's priority
doesn't have to be renumbered around existing ones - `New-AuditRetentionPolicy.ps1`'s pre-flight
check will catch a collision, but it can't suggest the "right" number for your organization's
priority scheme.

**KPI to watch:** headroom under the 50-policy cap (`validate/Test-AuditRetentionPolicy.ps1`'s
`[WARN]` at ≤5 remaining) - an organization that hits the cap loses the ability to add any new
targeted retention policy until an existing one is consolidated or removed.

## Rollback and decommission

See the rollback runbook. There is **no staged disable state** for this object type - only create, edit,
and delete. `./deploy/Remove-AuditRetentionPolicy.ps1` deletes named policies (from a config file
or by `-Name`); removal can take up to 30 minutes to fully apply, and never affects already-retained audit records or the tenant's default policy.

## References

1. Microsoft Purview service description - Audit (Premium) (licensing table, default one-year retention scope, add-on licensing) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-audit-premium>
2. Learn about auditing solutions in Microsoft Purview - Audit (Premium) section (10-year retention add-on, non-retroactive on already-generated logs) - <https://learn.microsoft.com/purview/audit-solutions-overview#audit-premium>
3. Manage audit log retention policies (portal walkthrough, PowerShell walkthrough and examples, 50-policy cap, Priority 1-10000 uniqueness rule, Name/Description length limits, Organization Configuration role requirement, dashboard edit-lock behavior for PowerShell-only policies, default-policy behavior) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
4. Roles and role groups in Microsoft Defender for Office 365 and Microsoft Purview - Compliance Data Administrator role group's default roles list (confirms Organization Configuration is included) - <https://learn.microsoft.com/defender-office-365/scc-permissions#role-groups-in-microsoft-defender-for-office-365-and-microsoft-purview>
5. New-UnifiedAuditLogRetentionPolicy reference (full parameter set, RetentionDuration enum, Operations/RecordTypes mutual-exclusivity rule, worked examples) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-unifiedauditlogretentionpolicy>
6. Set-UnifiedAuditLogRetentionPolicy reference (Identity parameter, overwrite semantics for RecordTypes/Operations/UserIds, worked $null-clearing example) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-unifiedauditlogretentionpolicy>
7. Remove-UnifiedAuditLogRetentionPolicy reference (Identity, ForceDeletion, up-to-30-minutes removal behavior) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-unifiedauditlogretentionpolicy>
8. Get-UnifiedAuditLogRetentionPolicy reference and usage (does not return the tenant's default policy) - cited via reference 3's PowerShell section - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-unifiedauditlogretentionpolicy>
9. AuditLogRecordType enum reference (valid RecordTypes values) - <https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype>
10. Audit log activities (valid Operations values) - <https://learn.microsoft.com/purview/audit-log-activities>
11. Search the audit log - before you search (retention windows by license tier, reused for cross-reference with *Forensic Investigation of a Compromised Account*) - <https://learn.microsoft.com/purview/audit-search#before-you-search-the-audit-log>
12. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>

> Re-verify all links, the `-RetentionDuration` enum, the 50-policy cap, and the Organization
> Configuration role mapping against current Microsoft Learn and a pilot tenant before a
> customer-facing deployment - retention behavior on policy edits is explicitly flagged as
> unresolved in the known limitations and should not be asserted to a customer without pilot-tenant confirmation.