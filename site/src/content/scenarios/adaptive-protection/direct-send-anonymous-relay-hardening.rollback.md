---
part: "rollback"
parent: "adaptive-protection/direct-send-anonymous-relay-hardening"
---
This scenario deploys up to three independent artifacts: an audit-mode `TransportRule`, the
tenant-wide `RejectDirectSend` gate, and zero or more certificate-based `InboundConnector` objects.
Roll back in stages, disabling `RejectDirectSend` or removing a still-used relay connector has real,
immediate effect on live mail flow, the same reasoning this library's other policy-based scenarios'
rollback docs apply.

**This procedure never touches** `exchange-legacy-auth-block`'s or `block-legacy-authentication`'s
own policy objects, fully independent controls (`design.md` §8).

## Recommended sequence

### Stage 1, Disable tenant-wide rejection (reversible, seconds)

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
./deploy/Remove-DirectSendHardening.ps1 -UnsetRejectDirectSend
```

Sets `Set-OrganizationConfig -RejectDirectSend $false`. Direct Send traffic is
accepted again tenant-wide. Re-enable instantly with
`deploy/New-DirectSendHardening.ps1 -RejectDirectSendTenantWide`.

Use this stage for: a legitimate sender discovered after enforcement that wasn't caught by Step 3's
evidence review, a change freeze, or investigating whether this gate is the cause of a reported mail
delivery issue.

### Stage 2, Remove the audit-mode detection rule (reversible, seconds; stops evidence-gathering)

```powershell
./deploy/Remove-DirectSendHardening.ps1 -RemoveAuditRule -Force
```

Calls `Remove-TransportRule`. Independent of Stage 1, the rule never blocked
mail, so removing it only stops the tagging/evidence trail, it does not restore or change any mail
flow. Re-create with `deploy/New-DirectSendHardening.ps1`.

### Stage 3, Remove a certificate-based relay connector (not reversible without re-provisioning)

```powershell
./deploy/Remove-DirectSendHardening.ps1 -RemoveRelayConnector `
    -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' -Force
```

Calls `Remove-InboundConnector`. Any device/app still sending through this
connector loses mail flow immediately once removed, confirm no legitimate sender still depends on
it first (the same "review before you remove" discipline this library's other exception-path
rollback docs apply). Re-create with
`deploy/New-DirectSendHardening.ps1 -CreateCertBasedRelayConnector`.

## What rollback does **not** undo

- **`exchange-legacy-auth-block`'s or `block-legacy-authentication`'s own policy objects**, 
 different, independent controls (`design.md` §8).
- **A message that was rejected while `RejectDirectSend` was `$true`.** A rejected Direct Send
 attempt was not delivered; rolling back afterward does not retroactively deliver it. The sender
 must retry.
- **Messages already tagged by the audit rule before it was removed.** The
 `X-DirectSendHardening-Detected` header on already-delivered messages is part of those messages'
 history; removing the rule only stops future tagging.

## Verification after rollback

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
Get-OrganizationConfig | Select-Object RejectDirectSend
Get-TransportRule -Identity 'Direct Send Detection (Audit)' -ErrorAction SilentlyContinue
Get-InboundConnector | Select-Object Name, RestrictDomainsToCertificate
```

Confirm `RejectDirectSend` reports the expected post-rollback value, `Get-TransportRule` returns
nothing (Stage 2, rule deleted) or the expected rule, and any removed relay connector no longer
appears. Then run `validate/Test-DirectSendHardening.ps1` to confirm the resulting state end-to-end.

## References

1. Set-OrganizationConfig (`-RejectDirectSend`), <https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps>
2. Remove-TransportRule, <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-transportrule?view=exchange-ps>
3. Remove-InboundConnector, <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-inboundconnector?view=exchange-ps>
