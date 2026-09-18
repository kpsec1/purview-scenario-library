---
part: "rollback"
parent: "dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation"
---
## Recommended sequence

This fragment adds one rule to an existing policy, roll back the rule, not the parent policy.
Rolling back Part 1's policy itself is `scenarios/dlp/exchange-pii-exfil-block/rollback.md`'s job;
rolling back the separate Encrypt-mode audit companion rule (if deployed) is
`scenarios/dlp/exchange-pii-exfil-block-encrypt-mode-audit-companion/rollback.md`'s job. Neither is
this file's responsibility.

### Stage 1, Audit-only (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-ExchangePiiElevatedRiskBlock.ps1
```

This runs `Set-DlpComplianceRule -Identity "PII-Exchange-ElevatedRisk-Block-AllExternal"
-BlockAccess $false`. The rule stays defined at priority 0 and still generates an alert/incident
report on a match, but no longer blocks the message. Restore blocking instantly:

```powershell
./deploy/New-ExchangePiiElevatedRiskBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -Force
```

Use this stage for: a false-positive Elevated-risk assignment causing business disruption, a
change freeze, or while re-tuning the feeder IRM policy's thresholds.

### Stage 2, Permanent removal (not reversible)

```powershell
./deploy/Remove-ExchangePiiElevatedRiskBlock.ps1 -Purge
```

This runs `Remove-DlpComplianceRule` on `PII-Exchange-ElevatedRisk-Block-AllExternal`, then
decompacts the parent policy's remaining rules back down by one priority slot each, preserving
their relative order (the reverse of `deploy/New-ExchangePiiElevatedRiskBlock.ps1`'s
name-agnostic compaction, see `design.md` §6). There is no "undo" beyond re-running
`deploy/New-ExchangePiiElevatedRiskBlock.ps1` from scratch. Only do this when this compensating
control is being permanently retired (e.g., a future Microsoft capability makes it obsolete, or
the buyer decides the residual coverage isn't worth the operational overhead documented in
`README.md` §8).

## What rollback does **not** undo

- **The parent scenario's own rules, the parent policy, the separate Encrypt-mode audit
  companion's rule, or `dynamic-risk-dlp-enforcement`'s separate policy.** All untouched by either
  rollback stage here (Stage 2's decompaction only ever changes `-Priority`, never any rule's
  conditions or actions).
- **The Exchange DLP-alerts indicator, the feeder Insider Risk Management policy, or Adaptive
  Protection's scope configuration.** All portal-only prerequisites this fragment's scripts never
  created, rolling back the DLP rule has no effect on them. To fully decommission this fragment,
  also disable/delete the feeder IRM policy, remove the parent DLP policy from the DLP-alerts
  indicator's list, and remove the feeder policy from Adaptive Protection's scope via the portal
  (see `README.md` §5, Steps 2-4, in reverse).
- **Audit log / alert history.** Retained per the same retention windows the parent scenario's own
  `rollback.md` already documents, regardless of this rule's state.
- **A user's current insider risk level.** Computed by Adaptive Protection independently of this
  rule's existence, removing the rule does not reset anyone's Elevated/Moderate/Minor assignment.

## Verification after rollback

```powershell
Get-DlpComplianceRule -Identity 'PII-Exchange-ElevatedRisk-Block-AllExternal' | Select-Object Name, Priority, BlockAccess
```

Confirm `BlockAccess` is `False` (Stage 1) or that the command returns nothing (Stage 2). After
Stage 2, also confirm the parent policy's remaining rules occupy unique, contiguous priorities
starting at 0:

```powershell
Get-DlpComplianceRule -Policy 'PII DLP - Exchange External Send Control' | Select-Object Name, Priority | Sort-Object Priority
```
