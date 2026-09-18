---
part: "rollback"
parent: "data-security-investigations/post-breach-investigation-and-purge"
---
This scenario's own footprint is small and reversible (role-group membership, a local audit-trail
CSV), but it governs access to a solution that can take genuinely irreversible actions (hard purge),
so the two are documented separately: what this scenario's automation can undo, and what it never
could in the first place.

## 1. Role group membership

**Script path (matches how it was deployed):**
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.com

# Preview
./deploy/New-DsiRoleGroupAssignments.ps1 -ConfigPath ./deploy/policy/empty-role-assignments.json -RemoveExtraMembers -WhatIf

# Apply - reconciles every DSI role group to empty (or to an updated, smaller config)
./deploy/New-DsiRoleGroupAssignments.ps1 -ConfigPath ./deploy/policy/empty-role-assignments.json -RemoveExtraMembers
```
Point `-ConfigPath` at a config whose `roleGroups` object lists each role group with an empty array
(or simply omits it) to remove everyone this scenario added; `-RemoveExtraMembers` is required for
the script to actually remove members (its default is additive-only, `design.md` §5).

**Portal path:** **Purview portal** → **Settings** → **Roles and groups** → **Role groups** → select
each of **Data Security Investigations Admins** / **Investigators** / **Reviewers** → **Edit** →
remove members.

**What this does NOT do:** it does not delete the role groups themselves (they're Microsoft-managed
and this scenario never created them, `design.md` §2), and it does not touch the four role groups
that carry DSI access implicitly (Compliance Administrator, Organization Management, Data Security
Management, Insider Risk Management), those are shared with other Purview solutions and are
explicitly out of this scenario's scope (README.md §3).

## 2. Audit-trail export pipeline

- **Stop the scheduled run** (disable whatever Task Scheduler entry / cron job / Azure Automation
 runbook was calling `Export-DsiActivityAuditTrail.ps1`).
- **Secure or dispose of the exported CSV(s)** per your data-handling policy. The CSV itself does not
 contain investigated content (README.md §11's "does NOT read investigation content" note), but it
 does contain `UserIds` and `AuditData` for every logged DSI action, including who ran every purge, 
 treat it with the same handling discipline as this library's other audit-export scripts
 (`audit/premium-audit-investigation/rollback.md`).
- **If `-NdjsonOutDir` was used**, secure or dispose of the `DSI-Activity-*.ndjson` files the same
 way, same fields, same sensitivity, just a different location (README.md §8). If that directory is
 shared with `audit/streaming-to-sentinel-or-management-api`'s own Path B output, only remove this
 scenario's `DSI-Activity-*.ndjson` files, leave that scenario's own `<contentType>-*.ndjson` files
 alone; its own `rollback.md` covers those.
- Nothing about the unified audit log itself is affected, this script only reads from it.

## 3. What this rollback does NOT and CANNOT undo

- **A completed hard purge.** Hard purge is permanent and irreversible by Microsoft's own design
 (README.md §6), there is no rollback for it, from this scenario's scripts, the Purview portal, or
 Microsoft support. This is the single most important fact to communicate to a buyer before they
 grant Investigator/Admin access: revoking role-group membership after the fact does not undo
 anything already purged.
- **A completed soft purge**, past its retention window. Soft-purged items sit in Recoverable Items
 and are restorable *only* within the configured retention period (README.md §6), restoring one is
 a source-mailbox operation (e.g. `Search-Mailbox`/the Recoverable Items folder in Outlook/OWA), not
 something this scenario's scripts do or need to, since neither script ever calls the purge API
 itself.
- **Data already copied into DSI's investigation scope.** Purging a source item does not remove the
 copy already stored in DSI's own Azure storage (README.md §11), that copy is only removed by
 **deleting the investigation itself**, a portal-only action (`purview.microsoft.com/dsi` →
 **Investigations** → select → **Delete**), which also stops that investigation's ongoing storage
 billing (README.md §10).
- **Billing/AI capacity configuration.** Resetting the compute-unit maximum or processing location is
 a portal-only setting; no script in this scenario touches it, and none is provided to reset it,
 since there's no documented API to do so (`design.md` §6).

## Verification

Re-run `./validate/Test-DsiRoleGroupAssignments.ps1` after removing role-group membership: the
membership-matches-config check should now report `[PASS]` against an empty desired list (i.e. the
role groups are confirmed empty), and the "Admins group has at least one member" check will correctly
report `[FAIL]`, expected once every Admin has been deliberately removed, not a regression. Confirm
in the portal that removed users can no longer see **Data Security Investigations** in their Purview
portal navigation (allow up to 30 minutes for propagation, README.md §11).
