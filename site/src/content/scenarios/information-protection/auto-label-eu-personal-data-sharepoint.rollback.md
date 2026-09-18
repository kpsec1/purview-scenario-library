---
part: "rollback"
parent: "information-protection/auto-label-eu-personal-data-sharepoint"
---
## Recommended sequence

Auto-labeling changes affect live content classification, so roll back in stages rather than
deleting outright. Identical staged model to the sibling scenario
(`scenarios/information-protection/auto-label-confidential-sharepoint/rollback.md`), only the
policy name differs.

### Stage 1, Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
./deploy/Remove-EuPersonalDataAutoLabelPolicy.ps1
```

This runs `Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label EU Personal Data
in SharePoint and OneDrive" -Mode Disable`. The policy and its two rules remain defined (visible in
the Purview portal under **Information Protection > Auto-labeling policies**) but stop evaluating
content. Re-enable instantly:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive" -Mode Enable
```

Use this stage for: a false-positive wave that needs immediate relief while you tune the SIT
conditions (e.g. narrowing from the full EU-wide bundle down to specific member states, see
`README.md` §6), a change freeze, or a temporary business exception that doesn't warrant deleting
the control.

### Stage 2, Simulation (partial rollback, keeps visibility)

If a full disable is too blunt (you still want to know what *would* have been labeled), step back
to simulation instead of fully disabling:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive" -Mode TestWithNotifications
```

Nothing is labeled going forward; simulation results still populate the Labeled items dashboard.
This is the same mode the deploy script defaults to on first run.

### Stage 3, Permanent removal (not reversible)

```powershell
./deploy/Remove-EuPersonalDataAutoLabelPolicy.ps1 -Purge
```

This runs `Remove-AutoSensitivityLabelPolicy`, which deletes the policy **and its two rules** in
one call. There is no "undo", re-establishing the control means re-running
`deploy/New-EuPersonalDataAutoLabelPolicy.ps1` from scratch. Only do this when the control is
being permanently retired (e.g., merged into a broader multi-region policy, or superseded by a
per-country-scoped replacement).

## What rollback does **not** undo

- **Labels already applied to files.** This scenario's controls (disable, simulation, or purge)
  stop the policy from applying *new* labels going forward. They do **not** retroactively remove
  the `Confidential` label from files the policy already labeled.
- **Encryption, if the label applies it.** Same as the sibling scenario, encryption is a property
  of the label assignment on the file, not of this policy.
- **The `Confidential` label itself.** This scenario never created the label, it's a prerequisite
  dependency (see `design.md` §8). Removing this policy has no effect on the label's existence,
  definition, or publication to users.
- **The `Set-SPOTenant -EnableAIPIntegration` tenant toggle.** A separate, tenant-wide setting
  outside this policy's lifecycle (see `README.md` §3, §11), shared with, and not re-toggled
  independently for, the sibling U.S.-SIT scenario if both are deployed in the same tenant.

## Interaction with the sibling scenario

If both this scenario and `auto-label-confidential-sharepoint` are deployed in the same tenant,
they are **independent policies** with independent Mode/lifecycle, rolling back one has no effect
on the other. A file matching both policies' SIT conditions (e.g. it contains both a U.S. SSN and
an EU national ID number) is evaluated by both; the `Confidential` label is applied once regardless
of which policy's rule matched first (labels are not stacked or duplicated).

## Verification after rollback

Run the validation script and confirm it reports the policy `Mode` as `Disable` (Stage 1) or that
`Get-AutoSensitivityLabelPolicy -Identity "..."` returns nothing (Stage 3):

```powershell
Get-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive" | Select-Object Name, Mode
```
