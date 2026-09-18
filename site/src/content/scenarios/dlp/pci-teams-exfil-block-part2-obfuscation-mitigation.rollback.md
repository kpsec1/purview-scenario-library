---
part: "rollback"
parent: "dlp/pci-teams-exfil-block-part2-obfuscation-mitigation"
---
## Recommended sequence

This fragment adds one rule to an existing policy, roll back the rule, not the parent policy.
Rolling back Part 1's policy itself is `scenarios/dlp/pci-teams-exfil-block/rollback.md`'s job,
not this file's.

### Stage 1, Audit-only (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-PciElevatedRiskTeamsBlock.ps1
```

This runs `Set-DlpComplianceRule -Identity "PCI-ElevatedRisk-Block-AllExternal" -BlockAccess
$false`. The rule stays defined at priority 0 and still generates an alert/incident report on a
match, but no longer blocks the message. Restore blocking instantly:

```powershell
./deploy/New-PciElevatedRiskTeamsBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -Force
```

Use this stage for: a false-positive Elevated-risk assignment causing business disruption, a
change freeze, or while re-tuning the feeder IRM policy's thresholds.

### Stage 2, Permanent removal (not reversible)

```powershell
./deploy/Remove-PciElevatedRiskTeamsBlock.ps1 -Purge
```

This runs `Remove-DlpComplianceRule` on `PCI-ElevatedRisk-Block-AllExternal`, then restores Part
1's three original rules to their original priorities (0/1/2). There is no "undo" beyond
re-running `deploy/New-PciElevatedRiskTeamsBlock.ps1` from scratch. Only do this when this
compensating control is being permanently retired (e.g., a future Microsoft capability makes it
obsolete, or the buyer decides the residual coverage isn't worth the operational overhead
documented in `README.md` §8).

## What rollback does **not** undo

- **Part 1's own three rules, the parent policy, or `dynamic-risk-dlp-enforcement`'s separate
  policy.** All untouched by either rollback stage here.
- **The feeder Insider Risk Management policy, the Communication Compliance indicator, or
  Adaptive Protection's scope configuration.** All portal-only prerequisites this fragment's
  scripts never created, rolling back the DLP rule has no effect on them. To fully decommission
  this fragment, also disable/delete the feeder IRM policy and remove it from Adaptive
  Protection's scope via the portal (see `README.md` §5, Steps 2-4, in reverse).
- **Audit log / alert history.** Retained per the same retention windows Part 1's `rollback.md`
  already documents, regardless of this rule's state.
- **A user's current insider risk level.** Computed by Adaptive Protection independently of this
  rule's existence, removing the rule does not reset anyone's Elevated/Moderate/Minor
  assignment.

## Verification after rollback

```powershell
Get-DlpComplianceRule -Identity 'PCI-ElevatedRisk-Block-AllExternal' | Select-Object Name, Priority, BlockAccess
```

Confirm `BlockAccess` is `False` (Stage 1) or that the command returns nothing (Stage 2). After
Stage 2, also confirm Part 1's rules are back at priorities 0/1/2:

```powershell
Get-DlpComplianceRule -Policy 'PCI DSS - Teams Card Data Exfiltration Block' | Select-Object Name, Priority | Sort-Object Priority
```
