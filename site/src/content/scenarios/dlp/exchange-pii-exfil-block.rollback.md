---
part: "rollback"
parent: "dlp/exchange-pii-exfil-block"
---
## Recommended sequence

DLP policy changes affect live mail flow, so roll back in stages rather than deleting outright.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-ExchangePiiDlpPolicy.ps1
```

This runs `Set-DlpCompliancePolicy -Identity "PII DLP - Exchange External Send Control" -Mode Disable`.
The policy and its rules remain defined (visible in the Purview portal under **Data loss
prevention > Policies**) but stop evaluating traffic. Re-enable instantly:

```powershell
Set-DlpCompliancePolicy -Identity "PII DLP - Exchange External Send Control" -Mode Enable
```

Use this stage for: a false-positive incident that needs immediate relief while you tune the
policy, a change freeze, or a temporary business exception that doesn't warrant deleting the
control.

### Stage 2, Simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been blocked or
encrypted), step back to simulation instead of fully disabling:

```powershell
Set-DlpCompliancePolicy -Identity "PII DLP - Exchange External Send Control" -Mode TestWithNotifications
```

Nothing is blocked or encrypted; policy tips and alerts still fire. This is the same mode the
deploy script defaults to on first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-ExchangePiiDlpPolicy.ps1 -Purge
```

This runs `Remove-DlpCompliancePolicy`, which deletes the policy **and all its rules** in one call
(Microsoft Learn: `remove-dlpcompliancepolicy`). There is no "undo", re-establishing the control
means re-running `deploy/New-ExchangePiiDlpPolicy.ps1` from scratch. Only do this when the control
is being permanently retired (e.g., replaced by a successor policy with a different name).

### Switching `-Action` without a full rollback

Moving between Block and Encrypt mode doesn't require rollback at all, re-run the deploy script
with the new `-Action` and `-Force`:

```powershell
./deploy/New-ExchangePiiDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Action Encrypt -Force
```

The script clears the previous action's parameter (`RemoveRMSTemplate`/`BlockAccess $false`) on
the `PII-Exchange-Protect-External` rule before applying the new one, and removes the
`PII-Exchange-Override-External` rule if it's no longer applicable (Encrypt mode has no override
concept, see `design.md` §6).

## What rollback does **not** undo

- **Audit log / alert history.** Alerts and incident reports already generated (DLP Alerts
  dashboard, Microsoft Defender portal) are retained per their own retention windows regardless of
  policy state.
- **Messages already blocked.** A message a user tried to send externally while a Block-mode rule
  was enforcing was not delivered; disabling or removing the policy afterward does not
  retroactively deliver it. The sender must resend.
- **Messages already encrypted.** A message already encrypted and delivered under Encrypt mode
  stays encrypted for its recipient, rollback has no effect on mail already sent.
- **The business-exception group's membership.** This scenario does not create or manage
  `ExceptionGroupEmail`, it's a dependency, not a deployed artifact. Removing this policy has no
  effect on that group.
- **RMS templates.** This scenario does not create or manage the `Encrypt-Only`/`Do Not Forward`
  templates it references, they are tenant-level Message Encryption artifacts, unaffected by
  policy rollback.

## Verification after rollback

Run the validation script and confirm it reports the policy `Mode` as `Disable` (Stage 1) or that
`Get-DlpCompliancePolicy -Identity "..."` returns nothing (Stage 3):

```powershell
Get-DlpCompliancePolicy -Identity "PII DLP - Exchange External Send Control" | Select-Object Name, Mode
```
