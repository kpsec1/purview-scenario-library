---
part: "rollback"
parent: "information-protection/auto-label-confidential-sharepoint"
---
## Recommended sequence

Auto-labeling changes affect live content classification, so roll back in stages rather than
deleting outright.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-ConfidentialAutoLabelPolicy.ps1
```

This runs `Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in
SharePoint and OneDrive" -Mode Disable`. The policy and its two rules remain defined (visible in
the Purview portal under **Information Protection > Auto-labeling policies**) but stop evaluating
content. Re-enable instantly:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in SharePoint and OneDrive" -Mode Enable
```

Use this stage for: a false-positive wave that needs immediate relief while you tune the SIT
conditions, a change freeze, or a temporary business exception that doesn't warrant deleting the
control.

### Stage 2, Simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been labeled), step back
to simulation instead of fully disabling:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in SharePoint and OneDrive" -Mode TestWithNotifications
```

Nothing is labeled going forward; simulation results still populate the Labeled items dashboard.
This is the same mode the deploy script defaults to on first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-ConfidentialAutoLabelPolicy.ps1 -Purge
```

This runs `Remove-AutoSensitivityLabelPolicy`, which deletes the policy **and its two rules** in
one call. There is no "undo", re-establishing the control means re-running
`deploy/New-ConfidentialAutoLabelPolicy.ps1` from scratch. Only do this when the control is being
permanently retired (e.g., replaced by a broader policy covering more sensitive information types
or locations).

## What rollback does **not** undo

- **Labels already applied to files.** This scenario's controls (disable, simulation, or purge)
 stop the policy from applying *new* labels going forward. They do **not** retroactively remove
 the `Confidential` label from files the policy already labeled. Removing a label from
 already-labeled content is a separate action (an auto-labeling policy configured to
 **automatically remove a label**, or a manual per-file/library action) and is out of this
 scenario's scope.
- **Encryption, if the label applies it.** If `Confidential` is configured to apply encryption,
 disabling or removing this auto-labeling policy has no effect on files already encrypted under
 that label, the encryption is a property of the label assignment on the file, not of this
 policy.
- **The `Confidential` label itself.** This scenario never created the label, it's a
 prerequisite dependency (see `design.md` §7). Removing this policy has no effect on the label's
 existence, definition, or publication to users.
- **The `Set-SPOTenant -EnableAIPIntegration` tenant toggle.** That is a separate, tenant-wide
 setting outside this policy's lifecycle (see `README.md` §3, §11), this scenario's rollback
 does not touch it.

## Verification after rollback

Run the validation script and confirm it reports the policy `Mode` as `Disable` (Stage 1) or that
`Get-AutoSensitivityLabelPolicy -Identity "..."` returns nothing (Stage 3):

```powershell
Get-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in SharePoint and OneDrive" | Select-Object Name, Mode
```
