# Rollback — Audit-Log Retention Policy Management

## ⚠️ Read first: removal reverts retention to the default, and is a governance decision

Removing a custom retention policy makes future audit records for its scope fall back to the **built-in
default** window (Entra/Exchange/OneDrive/SharePoint = 1 year; everything else = 180 days). If that
scope was being retained for a legal, regulatory, or investigative reason, shortening it can destroy
evidence you are required to keep. Confirm with Security/Legal before removing. Removal does **not**
delete audit records already retained.

## Recommended sequence

### Stage 1 — Preview

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.json -DryRun
```

Lists the `Remove-UnifiedAuditLogRetentionPolicy` calls that would run (only for policies that exist).

### Stage 2 — Remove

```powershell
./deploy/Remove-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.json
# add -Force to pass -ForceDeletion (skip the interactive prompt)
```

Removes the config's policies. Their scope reverts to the default policy. **Deletion can take up to 30
minutes** to take effect.

### Alternative — shorten instead of remove

If the intent is a shorter (but still non-default) window, don't remove — edit the policy in place with
`Set-UnifiedAuditLogRetentionPolicy -Identity '<name>' -RetentionDuration <enum> -Priority <n>`
(both mandatory on `Set`). That keeps the override rather than falling back to the default.

## What rollback does **not** undo

- **Audit records already retained** — removal changes future retention only; captured records remain
  until their own retention lapses.
- **The default policy** — always present; can't be modified or removed.
- **Records already aged out** under a prior (shorter) policy — not recoverable.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-AuditRetentionPolicy.ps1 -ConfigPath ./deploy/config/audit-retention-policies.json
```

Expect the removed policies to `[FAIL]` the existence check (gone). Allow up to ~30 minutes for the
removal to propagate before trusting the result.
