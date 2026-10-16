---
part: "runbook"
parent: "adaptive-protection/direct-send-anonymous-relay-hardening"
---
## Implementation steps

### Step 1 - Assign permissions

Add the operating administrator (or the automation app's service principal) to the **Organization
Management** Exchange Online role group - [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap).

### Step 2 - Deploy the audit-mode detection rule and connector audit (no live impact)

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain
./deploy/New-DirectSendHardening.ps1 -WhatIf
./deploy/New-DirectSendHardening.ps1
```

Creates (or reconciles) the `Direct Send Detection (Audit)` transport rule at `-Mode Audit`
 - this **never blocks or modifies mail**, it only tags matching messages and logs
a rule match, which appears in message trace and the rule's own audit report. In the same pass, it
reads every `InboundConnector` and prints a WARN for each one configured with
`-RestrictDomainsToIPAddresses $true` whose `SenderIPAddresses` CIDR range is wider than
`-MaxIpRangeCidrBits` (default `/24`, a disclosed heuristic - not a Microsoft-published threshold,
see the design notes).

Let this stage run for at least the 7-14 days Microsoft's own message trace retention comfortably
covers before moving to Step 3 - this is this scenario's evidence-gathering window, the same
"inventory before enforcing" discipline *Exchange-Side Legacy Authentication Block* (the implementation steps) Step 2 uses for
SMTP AUTH.

### Step 3 - Review the evidence

```powershell
./validate/Test-DirectSendHardening.ps1
```

Read the flagged connectors and cross-reference the audit rule's matches (Exchange admin center →
**Mail flow** → **Rules** → the rule's own report, or a message trace filtered for the
`X-DirectSendHardening-Detected` header this scenario's rule adds) against your Step 1 inventory.
Confirm every legitimate Direct Send sender and every legitimate IP-based relay connector is
accounted for before enforcing.

### Step 4 - Migrate legitimate senders to a governed, certificate-based relay connector (opt-in, per sender)

```powershell
./deploy/New-DirectSendHardening.ps1 -CreateCertBasedRelayConnector `
    -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' `
    -RelaySenderDomains '*.contoso.com' `
    -RelayCertificateSubjectDomain 'contoso.com' -WhatIf
./deploy/New-DirectSendHardening.ps1 -CreateCertBasedRelayConnector `
    -RelayConnectorName 'Contoso Scan-to-Email (Certificate)' `
    -RelaySenderDomains '*.contoso.com' `
    -RelayCertificateSubjectDomain 'contoso.com'
```

Creates a certificate-authenticated `InboundConnector` -
Microsoft's own documented, stronger alternative to both Direct Send and an IP-based relay
connector, since it authenticates the sender by a TLS certificate whose Subject/SAN matches an
accepted domain rather than by source IP address, and does not require a static, unshared IP. Run once per distinct sending application/device family that needs to keep
sending unauthenticated mail after Step 5. Each device/app must then present the matching client
certificate - device/app-specific configuration outside this script's scope.

### Step 5 - Enforce: reject unauthenticated Direct Send tenant-wide (live-impact stage, opt-in)

```powershell
./deploy/New-DirectSendHardening.ps1 -RejectDirectSendTenantWide -WhatIf
./deploy/New-DirectSendHardening.ps1 -RejectDirectSendTenantWide
```

Sets `Set-OrganizationConfig -RejectDirectSend $true` - Exchange Online rejects
unauthenticated messages sent via the Direct Send path tenant-wide. Devices/apps migrated in Step 4
are unaffected (they now authenticate via the certificate-based connector, a materially different
path Microsoft's own comparison table distinguishes from Direct Send). Any
device/app **not** migrated and still depending on Direct Send starts failing at this step - confirm
Step 3's review found none before proceeding.

### Step 6 - Validate

```powershell
./validate/Test-DirectSendHardening.ps1 -ExpectRejectDirectSend
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Audit rule name | `Direct Send Detection (Audit)` | `-Mode Audit` - never blocks; tags matches with `X-DirectSendHardening-Detected: True`. |
| Audit rule condition | `-HeaderContainsMessageHeader 'X-MS-Exchange-Organization-AuthAs' -HeaderContainsWords 'Anonymous' -SentToScope InOrganization` | `AuthAs: Anonymous` is Microsoft's own documented header value for a message the service could not authenticate; `SentToScope InOrganization` scopes detection to internal recipients, matching Direct Send's own internal-only delivery scope. |
| Connector risk heuristic | `-RestrictDomainsToIPAddresses $true` AND CIDR prefix shorter than `-MaxIpRangeCidrBits` (default `/24`, i.e. 256+ addresses) | This scenario's own disclosed heuristic - not a Microsoft-published threshold. A `/24` allows 256 source addresses to relay as the connector's `SenderDomains`; a shared cloud-provider range at that width or wider is a real, documented risk category Microsoft's own guidance warns against generally. |
| Certificate-based relay connector | `New-InboundConnector -RestrictDomainsToCertificate $true -TlsSenderCertificateName <domain>` | - the governed exception path for Step 4. |
| Tenant-wide enforcement | `Set-OrganizationConfig -RejectDirectSend $true` | - confirmed, documented parameter with a full behavioral description; default value and any future default-disable rollout date remain unpublished, see the known limitations. |

## Operations and tuning

**KPIs to watch (first 90 days):** count of messages tagged by the audit rule before enforcement
(should trend toward zero as legitimate senders are migrated), count of rejected Direct Send attempts
after enforcement (`Search-UnifiedAuditLog` mail-flow/connector events or the SMTP gateway's own
logs - this scenario's config read-backs confirm state, not events, the same class of gap
*Exchange-Side Legacy Authentication Block* (operations and tuning) discloses for its own SMTP AUTH KPIs), and count of
connectors still flagged WARN by the risk heuristic (should shrink as relay is migrated to
certificate-based).

**Important monitoring blind spot after Step 5:** transport rules (including this scenario's audit
rule) evaluate only messages that have already been accepted into the transport pipeline. Once
`RejectDirectSend` is `$true`, a Direct Send attempt is rejected at the SMTP session itself -
**before** the transport pipeline runs - so the audit rule stops seeing rejected attempts entirely.
Its evidence-gathering value is front-loaded into the Step 2-3 pre-enforcement window; ongoing
post-enforcement monitoring for rejection volume requires `Search-UnifiedAuditLog` mail-flow events
or the SMTP gateway's own logs, the same event-level gap named above. Don't rely on the audit rule's
match count as a post-enforcement KPI - it will read near-zero regardless of actual rejection volume.

**Tuning:** if a legitimate high-volume sender is identified after Step 5 causes a delivery failure,
migrate it to the certificate-based relay connector (Step 4) rather than reverting
`RejectDirectSend` tenant-wide - a single missed sender doesn't justify reopening the whole path.

**Incident-response runbook (a legitimate device/app is unexpectedly blocked after Step 5):**
1. **Triage** - confirm the failure is a Direct Send rejection specifically (message trace shows the
   inbound connection was rejected at the MX endpoint with no authentication presented), not an
   unrelated mail-flow or spam-filtering issue.
2. **Determine intent** - a single affected device shortly after Step 5 is expected if Step 3's
   review missed it; a burst of rejected attempts from many previously-unseen source IPs may
   indicate a spoofing/BEC campaign that has now lost its easiest path in.
3. **Remediate** - migrate the legitimate device/app to the certificate-based relay connector (Step
   4) as a tracked, named exception rather than disabling `RejectDirectSend` tenant-wide.

**Review cadence:** quarterly - re-run the connector audit (new connectors may have been added since
the last review) and confirm the audit rule's match count for internal recipients stays near zero.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable tenant-wide rejection → remove the audit
rule → remove certificate-based relay connectors → full teardown). Rolling back this scenario has
**no effect** on *Exchange-Side Legacy Authentication Block* or *Block Legacy Authentication* - independent,
complementary controls covering different abuse surfaces.

## References

1. How to set up a multifunction device or application to send email using Microsoft 365 or Office
   365 - Direct Send section (features, limitations, setup, "most customers don't need this,"
   default-disable-in-progress statement) - <https://learn.microsoft.com/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365>
2. How to set up a multifunction device or application to send email using Microsoft 365 or Office
   365 - SMTP relay section (certificate-based vs. IP-based connector, static-unshared-IP
   requirement) - same URL as [1], `#smtp-relay-configure-a-connector-to-relay-email-from-your-device-or-application-through-microsoft-365-or-office-365`
3. Set-OrganizationConfig (ExchangePowerShell) - `-RejectDirectSend` parameter - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps>
4. Get-OrganizationConfig (ExchangePowerShell) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-organizationconfig?view=exchange-ps>
5. New-InboundConnector / Get-InboundConnector (ExchangePowerShell) - `-RestrictDomainsToCertificate`,
   `-RestrictDomainsToIPAddresses`, `-SenderIPAddresses`, `-TlsSenderCertificateName` - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-inboundconnector?view=exchange-ps>
6. New-TransportRule / Set-TransportRule / Get-TransportRule (ExchangePowerShell) - `-Mode`
   (`Audit`/`AuditAndNotify`/`Enforce`), `-HeaderContainsMessageHeader`, `-HeaderContainsWords`,
   `-SentToScope`, `-SetHeaderName`, `-SetHeaderValue` - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-transportrule?view=exchange-ps>
7. Header firewall - `X-MS-Exchange-Organization-AuthAs` values (`Anonymous`, `Internal`,
   `External`, `Partner`) - <https://learn.microsoft.com/exchange/header-firewall-exchange-2013-help>
8. Anti-spoofing protection for cloud mailboxes - composite authentication, intra-org spoofing
   (`compauth=fail reason=6xx`) - <https://learn.microsoft.com/defender-office-365/anti-phishing-protection-spoofing-about>
9. Troubleshoot outbound sending limits and blocked users in Exchange Online - Direct Send/SMTP
   relay/SMTP AUTH sending-limit comparison table - <https://learn.microsoft.com/defender-office-365/outbound-spam-sending-limits-troubleshoot>
10. [Automation surface, sections 1 and 3](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - automation surface 1 (Exchange Online PowerShell), app-only
    authentication pattern.
11. [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap) - Exchange Online RBAC dependency.
12. *Exchange-Side Legacy Authentication Block* - the sibling scenario whose Red
    Team review (finding 3) named this exact gap.

> Re-verify all links and exact cmdlet parameter behavior against current Microsoft Learn before a
> customer-facing assessment or sale - Direct Send hardening is an actively-evolving area (Microsoft
> states it is "working on an option to disable Direct Send by default," the known limitations).