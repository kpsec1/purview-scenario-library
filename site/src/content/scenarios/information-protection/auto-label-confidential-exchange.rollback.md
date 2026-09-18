---
part: "rollback"
parent: "information-protection/auto-label-confidential-exchange"
---
## Recommended sequence

Auto-labeling changes affect live mail classification and, if the label applies encryption,
delivery behavior, roll back in stages rather than deleting outright, same principle as the
sibling SharePoint/OneDrive scenario.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-ConfidentialAutoLabelExchangePolicy.ps1
```

This runs `Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange
Email" -Mode Disable`. The policy and its rule remain defined (visible in the Purview portal under
**Information Protection > Auto-labeling policies**) but stop evaluating mail in transit. Re-enable
instantly:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" -Mode Enable
```

Use this stage for: a false-positive wave (e.g., an unexpected encryption side effect breaking a
business workflow), a change freeze, or a temporary business exception.

### Stage 2, Simulation (partial rollback, keeps visibility)

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" -Mode TestWithNotifications
```

Nothing is labeled or encrypted going forward; matches on live traffic during any future
simulation window still populate the **Items to review** tab. Remember Exchange simulation only
evaluates mail sent/received while active (`README.md` §5/§7), this stage won't show you anything
about mail that arrives while the policy sits idle between simulation runs.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-ConfidentialAutoLabelExchangePolicy.ps1 -Purge
```

This runs `Remove-AutoSensitivityLabelPolicy`, which deletes the policy **and its rule** in one
call. There is no "undo", re-establishing the control means re-running
`deploy/New-ConfidentialAutoLabelExchangePolicy.ps1` from scratch.

## What rollback does **not** undo

- **Labels and encryption already applied to mail already delivered.** Because Exchange
 auto-labeling only ever acts on mail in transit, "already labeled" here means mail that was
 labeled/encrypted at the moment it passed through the policy while it was active. Disabling or
 removing this policy has no retroactive effect on that mail, recipients who already received an
 encrypted, Confidential-labeled message keep it exactly as delivered.
- **The `Confidential` label itself, or its scope.** This scenario never created or scoped the
 label, it's a prerequisite dependency (see `design.md` §7). Removing this policy has no effect
 on the label's existence, definition, publication, or whether its scope includes Emails.
- **The sibling SharePoint/OneDrive scenario's own policy.** These are two separate policy
 objects (`design.md` §7), rolling back this one has no effect on
 `scenarios/information-protection/auto-label-confidential-sharepoint/`'s policy, and vice versa.
- **Any `-ExternalMailRightsManagementOwner` configuration on a different policy or on the label
 itself**, this scenario's own use of that parameter (if configured) is removed with the policy,
 but the parameter is scoped per-policy, not global.

## Verification after rollback

```powershell
Get-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" | Select-Object Name, Mode
```

Confirm `Mode` reports `Disable` (Stage 1) or that the command returns nothing (Stage 3).
