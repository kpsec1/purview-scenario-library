# Rollback — Auto-Label Confidential PII in Exchange Email

## Recommended sequence

Auto-labeling changes affect live mail classification, so roll back in stages rather than deleting
outright.

### Stage 1 — Disable (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-ConfidentialExchangeAutoLabelPolicy.ps1
```

Runs `Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email"
-Mode Disable`. The policy and its rule remain defined (visible under **Information Protection →
Auto-labeling**) but stop evaluating mail. Re-enable instantly:

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" -Mode Enable
```

Use this for: a false-positive wave that needs immediate relief while you tune SIT conditions, a
change freeze, or an unexpected inbound-external-mail encryption problem.

### Stage 2 — Simulation (partial rollback, keeps visibility)

```powershell
Set-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" -Mode TestWithNotifications
```

Nothing is labeled going forward; the **Items to review** dashboard still populates from mail that
flows during simulation. Same mode the deploy script defaults to on first run.

### Stage 3 — Permanent removal (not reversible)

```powershell
./deploy/Remove-ConfidentialExchangeAutoLabelPolicy.ps1 -Purge
```

Runs `Remove-AutoSensitivityLabelPolicy`, which deletes the policy **and its rule** in one call.
There is no undo — re-establishing the control means re-running the deploy script. Only do this when
the control is being permanently retired (e.g. replaced by a broader policy).

## What rollback does **not** undo

- **Labels already applied to email.** Disable, simulation, and purge all stop the policy from
  labeling *new* mail going forward. They do **not** retroactively remove the `Confidential` label
  from messages the policy already labeled while enabled.
- **Encryption, if the label applies it.** If `Confidential` encrypts, disabling or removing this
  policy has no effect on mail already encrypted under that label — the encryption is a property of
  the label applied to the message, not of this policy. This is the reason to prefer the staged
  disable-first sequence over an immediate purge.
- **The `Confidential` label itself.** This scenario never created the label — it's a prerequisite
  dependency (`design.md` §7). Removing this policy has no effect on the label's existence,
  definition, or publication.

> Note: unlike the SharePoint/OneDrive sibling, there is **no** `Set-SPOTenant -EnableAIPIntegration`
> tenant toggle in this scenario's lifecycle — Exchange auto-labeling is service-side and has no
> equivalent tenant integration switch to leave behind.

## Verification after rollback

```powershell
Get-AutoSensitivityLabelPolicy -Identity "Confidentiality - Auto-Label PII in Exchange Email" | Select-Object Name, Mode
```

Confirm `Mode` is `Disable` (Stage 1) or that the command returns nothing (Stage 3). The validation
script also reports the mode.
