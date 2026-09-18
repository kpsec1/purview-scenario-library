---
part: "rollback"
parent: "adaptive-protection/exchange-legacy-auth-block"
---
This scenario deploys up to three artifacts: a baseline `AuthenticationPolicy`, its optional
tenant-default assignment, the optional tenant-wide SMTP AUTH transport gate, and an optional
shared exception `AuthenticationPolicy` with per-mailbox `CASMailbox` overrides. Roll back in
stages, disabling SMTP AUTH tenant-wide or clearing the org default has real, immediate effect on
live mail flow, the same reasoning this library's other policy-based scenarios' rollback docs
apply.

**This procedure never touches** `block-legacy-authentication`'s own Conditional Access policy or
any Microsoft-managed Conditional Access policy, fully independent controls (`design.md` §6).

## Recommended sequence

### Stage 1, Clear the tenant default assignment (reversible, seconds)

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
./deploy/Remove-ExchangeLegacyAuthBlock.ps1 -UnsetOrgDefault
```

Sets `Set-OrganizationConfig -DefaultAuthenticationPolicy $null` [[1]](#references). Every user
without an explicit per-user `AuthenticationPolicy` assignment reverts to no assigned policy
(legacy-protocol behavior for them then follows whatever tenant-wide platform defaults and
`SmtpClientAuthenticationDisabled` settings remain in place, most legacy protocols stay
permanently blocked at the platform level regardless, per `design.md` §3). Re-enable instantly with
`deploy/New-ExchangeLegacyAuthBlock.ps1 -SetAsOrgDefault`.

Use this stage for: a legitimate tenant-wide impact discovered after enforcement, a change freeze,
or investigating whether this policy assignment is the cause of a reported issue.

### Stage 2, Re-enable Authenticated SMTP tenant-wide (reversible, seconds)

```powershell
./deploy/Remove-ExchangeLegacyAuthBlock.ps1 -ReenableSmtpAuthTenantWide
```

Sets `Set-TransportConfig -SmtpClientAuthenticationDisabled $false` tenant-wide
[[2]](#references). Independent of Stage 1, can be run alone if only the SMTP transport gate is
the concern. Per-mailbox `CASMailbox` overrides (exception mailboxes) are **not** touched by this
stage. Re-enable the block with `deploy/New-ExchangeLegacyAuthBlock.ps1
-DisableSmtpAuthTenantWide`.

### Stage 3, Permanent removal of the policy objects (not reversible)

```powershell
./deploy/Remove-ExchangeLegacyAuthBlock.ps1 -UnsetOrgDefault -ReenableSmtpAuthTenantWide -Purge -Force
```

Calls `Remove-AuthenticationPolicy` [[3]](#references) for both the baseline and exception policy
objects. There is no "undo", re-establishing the control means re-running
`deploy/New-ExchangeLegacyAuthBlock.ps1` from scratch. The script refuses to purge a policy that is
still the tenant default or still assigned to any user unless `-Force` is also passed (clears the
assignment first), see the script's own `.NOTES` for why (Microsoft doesn't document
`Remove-AuthenticationPolicy`'s behavior against a still-assigned policy, so this script doesn't
rely on Exchange to reject it safely).

Only do this when the control is being permanently retired.

## What rollback does **not** undo

- **The eight legacy-authentication protocols Microsoft has already permanently disabled tenant-
  wide** (Exchange ActiveSync, POP, IMAP, Remote PowerShell, Exchange Web Services, Offline Address
  Book, Autodiscover, Outlook for Windows/Mac) [[4]](#references), those are platform-level
  changes with no re-enable path, completely independent of this scenario's own policy objects.
  Rolling back this scenario has **zero** effect on them.
- **The Conditional Access sibling scenario's own custom policy, or a Microsoft-managed Conditional
  Access policy**, different system entirely (`design.md` §6).
- **Per-mailbox `CASMailbox.SmtpClientAuthenticationDisabled` overrides** set for exception
  mailboxes, Stage 2 only changes the tenant-wide transport setting, not individual mailbox
  overrides. Clear those individually with `Set-CASMailbox -Identity <mailbox>
  -SmtpClientAuthenticationDisabled $null` if a full reset to "follow the org setting" is intended.
- **A rejected authentication attempt.** An authentication that was rejected while the block was in
  effect was not granted; rolling back afterward does not retroactively grant it. The client must
  retry.

## Verification after rollback

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
Get-OrganizationConfig | Select-Object DefaultAuthenticationPolicy
Get-TransportConfig | Select-Object SmtpClientAuthenticationDisabled
Get-AuthenticationPolicy -Identity 'Block Legacy Authentication (Exchange)' -ErrorAction SilentlyContinue
```

Confirm `DefaultAuthenticationPolicy`/`SmtpClientAuthenticationDisabled` report the expected
post-rollback values, or that `Get-AuthenticationPolicy` returns nothing (Stage 3, policy
deleted). Then run `validate/Test-ExchangeLegacyAuthBlock.ps1` to confirm the resulting state
end-to-end.

## References

1. Set-OrganizationConfig (`-DefaultAuthenticationPolicy`), <https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps>
2. Set-TransportConfig (`-SmtpClientAuthenticationDisabled`), <https://learn.microsoft.com/powershell/module/exchangepowershell/set-transportconfig?view=exchange-ps>
3. Remove-AuthenticationPolicy, <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-authenticationpolicy?view=exchange-ps>
4. Disable Basic authentication in Exchange Online (already-permanently-disabled protocol list), <https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/disable-basic-authentication-in-exchange-online>
