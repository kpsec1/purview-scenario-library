---
part: "rollback"
parent: "audit/retention-policy-management"
---
## There is no staged "disable" state, deletion is the only rollback

Unlike this library's DLP, DLM, and records-management scenarios, Microsoft documents no
`-Enabled`/`Mode` parameter for `UnifiedAuditLogRetentionPolicy` objects. A policy is either
**live** (created) or **gone** (deleted), there is no `TestWithNotifications`/`Disable`
intermediate state to fall back to. This is a genuine product constraint, not a gap in this
scenario's scripts, see `design.md` §7.

## 1. Remove specific policies

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Preview
./deploy/Remove-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json -WhatIf

# Remove every policy named in the config
./deploy/Remove-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.sample.json

# Or remove one policy by name
./deploy/Remove-AuditRetentionPolicy.ps1 -Name 'ThreeMonth-SharePointSearchNoise'
```

Removal can take **up to 30 minutes** to fully apply across the tenant, Microsoft's own dashboard
guidance and the `Remove-UnifiedAuditLogRetentionPolicy` reference both state this. Re-run
`validate/Test-AuditRetentionPolicy.ps1` after that window, not immediately, to confirm removal.

## 2. What happens to retention after a policy is removed

Removing a custom policy does **not** delete, shorten, or otherwise touch any audit records
already retained under it, audit records are immutable regardless of the policy that governed
their retention. Going forward, activity that matched the removed policy falls back to whichever
policy is now the next-highest priority match, or to the tenant's **default** audit log retention
policy (one year for Entra/Exchange/OneDrive/SharePoint on E5-family licenses, 180 days otherwise)
if no custom policy remains that matches it.

## 3. The default policy cannot be removed

There is nothing to roll back for the tenant's built-in default retention policy, it isn't
created by this scenario, Microsoft states it can't be modified or deleted, and
`Get-UnifiedAuditLogRetentionPolicy` never even returns it. This scenario's scripts only ever
touch the **custom** policies they created.

## 4. Nothing else is touched

- **Search and export** (`scenarios/audit/premium-audit-investigation/`) are unaffected, removing
  a retention policy changes how long data is *kept*, not whether the Audit Search Graph API or
  `Search-UnifiedAuditLog` can find data that's still within its retention window.
- **Roles and permissions** granted for this scenario (Organization Configuration role, e.g. via
  the Compliance Data Administrator role group) are not changed by these scripts, revoke them
  separately if no longer needed.

## Verification

Re-run `./validate/Test-AuditRetentionPolicy.ps1 -ConfigPath <same config>` after a removal, every
entry that was removed now reports `[FAIL] ... does not exist in the tenant`, which is the expected
post-rollback state (not a script bug). To confirm a fully clean rollback with no unexpected
remaining state, also run `Get-UnifiedAuditLogRetentionPolicy | Where-Object Name -in <removed names>`
directly and confirm it returns nothing once the 30-minute removal window has passed.
