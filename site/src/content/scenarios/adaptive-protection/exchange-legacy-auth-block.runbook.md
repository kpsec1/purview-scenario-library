---
part: "runbook"
parent: "adaptive-protection/exchange-legacy-auth-block"
---
## Implementation steps

### Step 1 - Assign permissions

Add the operating administrator (or the automation app's service principal) to the **Organization
Management** Exchange Online role group - [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap). See the known limitations for the narrower-role
open question.

### Step 2 - Inventory current SMTP AUTH and legacy-protocol use before changing anything

Before disabling anything tenant-wide:

```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain

# Mailboxes with an explicit SMTP AUTH override already set (True/False, not $null = "follows org default")
Get-CASMailbox -ResultSize Unlimited | Where-Object { $null -ne $_.SmtpClientAuthenticationDisabled } |
    Select-Object DisplayName, PrimarySmtpAddress, SmtpClientAuthenticationDisabled

# Sign-ins/authentications actually using Basic/legacy protocols in the last 90 days - cross-check
# against the Conditional Access sibling's own Step 2 (Entra sign-in logs / legacy-auth workbook),
# which covers the same underlying signal from the identity-platform side.
```

Do this even if you plan to enforce immediately - this is the evidence a change is safe, and the
list of mailboxes that need the step 5 of the implementation steps exception path.

### Step 3 - Create the Authentication Policy (no live impact yet)

```powershell
./deploy/New-ExchangeLegacyAuthBlock.ps1 -WhatIf
./deploy/New-ExchangeLegacyAuthBlock.ps1
```

Creates (or reconciles) one `AuthenticationPolicy` named `Block Legacy Authentication (Exchange)`
with every `AllowBasicAuth*` switch left at its default (blocked) - matching Microsoft's own
documented default behavior for a policy created with no `-AllowBasicAuth*` switches. **Creating this policy alone has zero effect on any user** - an
`AuthenticationPolicy` object only takes effect once assigned (Step 4). This is the scenario's own
safe staging point; Authentication Policies have no native Report-only mode the way Conditional
Access does.

### Step 4 - Assign the policy tenant-wide (live-impact stage, opt-in)

```powershell
./deploy/New-ExchangeLegacyAuthBlock.ps1 -SetAsOrgDefault -WhatIf
./deploy/New-ExchangeLegacyAuthBlock.ps1 -SetAsOrgDefault
```

Sets the policy as the tenant's `DefaultAuthenticationPolicy` - applies to every
user **without an explicit per-user policy assignment already in place**. Run
`./validate/Test-ExchangeLegacyAuthBlock.ps1 -CheckUserOverrides` first to find any user who
already has a conflicting explicit policy - the org default does not override one.

### Step 5 - Disable Authenticated SMTP tenant-wide, with named exceptions (live-impact stage, opt-in)

```powershell
./deploy/New-ExchangeLegacyAuthBlock.ps1 -DisableSmtpAuthTenantWide `
    -ExceptionMailboxes 'scan-to-email@contoso.com','relay-app@contoso.com' -WhatIf
./deploy/New-ExchangeLegacyAuthBlock.ps1 -DisableSmtpAuthTenantWide `
    -ExceptionMailboxes 'scan-to-email@contoso.com','relay-app@contoso.com'
```

Sets `Set-TransportConfig -SmtpClientAuthenticationDisabled $true` tenant-wide -
the second, independent SMTP AUTH gate alongside the policy's own `AllowBasicAuthSmtp`. For each
`-ExceptionMailboxes` entry: assigns a separate, narrowly-scoped `Allow-Smtp-Auth-Exception`
policy (only `AllowBasicAuthSmtp` enabled - every other protocol still blocked) via `Set-User
-AuthenticationPolicy`, **and** sets `Set-CASMailbox -SmtpClientAuthenticationDisabled $false` for
that mailbox - both gates opened deliberately, since Microsoft does not document
how the two interact if only one is opened (the known limitations VERIFY).

### Step 6 - Validate

```powershell
./validate/Test-ExchangeLegacyAuthBlock.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Baseline policy name | `Block Legacy Authentication (Exchange)` | All `AllowBasicAuth*` switches omitted at creation = blocked by default for every protocol. |
| Exception policy name | `Allow-Smtp-Auth-Exception` | Only `-AllowBasicAuthSmtp` set; every other protocol stays blocked. One shared policy object, assigned to as many exception mailboxes as needed. |
| Tenant default assignment | `Set-OrganizationConfig -DefaultAuthenticationPolicy 'Block Legacy Authentication (Exchange)'` | Applies to every user with no explicit per-user override. |
| SMTP AUTH transport-layer gate | `Set-TransportConfig -SmtpClientAuthenticationDisabled $true` (tenant-wide), `$false` per exception mailbox via `Set-CASMailbox` | Independent of the AuthenticationPolicy's own `AllowBasicAuthSmtp` - this scenario closes both gates. |
| Exception mailbox assignment | `Set-User -Identity <mailbox> -AuthenticationPolicy 'Allow-Smtp-Auth-Exception'` |. |
| Staging model | Policy creation (Step 3) is a no-op until assigned; `-SetAsOrgDefault` and `-DisableSmtpAuthTenantWide` are separate, explicit, opt-in switches | No native Report-only concept for Authentication Policies - the design notes explains why this staged-parameter design is the closest equivalent. |

## Operations and tuning

**KPIs to watch (first 90 days):** count of rejected SMTP AUTH attempts, help-desk tickets tied to a
multifunction device or line-of-business app that stopped sending mail, and count of mailboxes on
the `Allow-Smtp-Auth-Exception` policy (should shrink over time as devices/apps migrate to OAuth,
not grow).

**Grounded, no scriptable source exists for the first KPI - read this before building anything
against it.** A dedicated follow-up grounding pass (the Blue Team review, finding 1) confirmed
there is **no PowerShell/Graph-queryable event log for a rejected SMTP AUTH attempt**, for a
disclosed structural reason, not a documentation gap this library could close by trying harder:
- `Search-UnifiedAuditLog` records mailbox/application **activity that happens after
  authentication succeeds** (`MailItemsAccessed`, `Send`, etc.) - Microsoft's own "Audit log
  activities" reference has no RecordType/Operation for a rejected or blocked
  authentication attempt of any protocol.
- Entra ID sign-in logs do record legacy-protocol authentication under a filterable
  **"Authenticated SMTP"** client app (`clientAppUsed: SMTP` in the underlying
  Microsoft Graph `signIn` schema) - but only for attempts that actually reach
  Entra ID. Both of this scenario's blocking mechanisms reject the connection **before** that point:
  Microsoft's "Disable Basic authentication in Exchange Online" reference states blocked Basic Auth
  "is blocked at the first pre-authentication step ... before the request reaches Microsoft Entra
  ID". A **rejected** attempt therefore never creates a sign-in log entry -
  the sign-in-log legacy-authentication workbook is a *pre-deployment discovery* tool (find who
  still uses SMTP AUTH before you block it), not a post-deployment rejection audit trail.
- The Exchange admin center's **SMTP AUTH Clients report** (`Reports > Mail Flow`)
  is built from actual message volume/TLS usage per sender - **successful
  submissions only**; it cannot surface a rejected attempt either.

**The real event source is the SMTP gateway itself.** Your SMTP AUTH-issuing device/app (or the
sending client) will surface the connection failure locally - the wire-level signature is SMTP
error code `535 5.7.139`. Design your rejection-volume monitoring around that
device/app's own logs (or a synthetic canary probe that attempts SMTP AUTH from a known-bad
credential on a schedule and alerts on anything *other* than `535 5.7.139`), not around a
Microsoft-side audit log - none exists for this event.

**Tuning:** if a device/app cannot migrate to OAuth immediately, add it to
`-ExceptionMailboxes` rather than re-enabling SMTP AUTH tenant-wide - narrow, named, mailbox-scoped
exceptions preserve the control's value for everyone else. Review the exception list on the same
quarterly cadence as the Conditional Access sibling scenario (operations and tuning there).

**Incident-response runbook (a legitimate mailbox/app is unexpectedly blocked):**
1. **Triage** - confirm the failure is `535 5.7.139` (SMTP AUTH specifically) or a general Basic
   Auth rejection on another protocol, not an unrelated mail-flow issue.
2. **Determine intent** - a single affected device/app after a planned rollout is expected; a burst
   of rejected authentication attempts across many previously-unaffected mailboxes may indicate a
   credential-stuffing/password-spray campaign that has now lost its easiest path in - cross-reference with the Conditional Access sibling's own Entra sign-in log guidance.
3. **Remediate** - migrate the device/app to OAuth if possible; if not immediately possible,
   add it to `-ExceptionMailboxes` as a temporary, tracked exception rather than disabling the
   tenant-wide control.

**Review cadence:** quarterly, aligned with the Conditional Access sibling scenario - re-run Step
2's inventory and re-validate the exception list is still the minimum necessary.

## Rollback and decommission

See the rollback runbook for the full staged procedure (remove tenant-wide default assignment → re-enable
SMTP AUTH tenant-wide → remove the exception policy → remove the baseline policy). Rolling back
this scenario has **no effect** on *Block Legacy Authentication*'s own Conditional Access policy or
(if present) Microsoft's auto-deployed Microsoft-managed Conditional Access policy - the two
scenarios are independent, complementary controls.

## References

1. New-AuthenticationPolicy (ExchangePowerShell) - default-blocked `AllowBasicAuth*` behavior,
   full switch list - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-authenticationpolicy?view=exchange-ps>
2. Set-AuthenticationPolicy (ExchangePowerShell) - `-AllowBasicAuth*:$false` block syntax - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-authenticationpolicy?view=exchange-ps>
3. Get-AuthenticationPolicy (ExchangePowerShell) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-authenticationpolicy?view=exchange-ps>
4. Remove-AuthenticationPolicy (ExchangePowerShell) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-authenticationpolicy?view=exchange-ps>
5. Set-User (ExchangePowerShell) - `-AuthenticationPolicy` parameter - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-user?view=exchange-ps>
6. Set-OrganizationConfig (ExchangePowerShell) - `-DefaultAuthenticationPolicy` parameter - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-organizationconfig?view=exchange-ps>
7. Set-TransportConfig (ExchangePowerShell) - `-SmtpClientAuthenticationDisabled` parameter - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-transportconfig?view=exchange-ps>
8. Set-CASMailbox (ExchangePowerShell) - mailbox-level `-SmtpClientAuthenticationDisabled` override - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-casmailbox?view=exchange-ps>
9. Enable or disable SMTP AUTH in Exchange Online (org-then-mailbox-override pattern, `535
   5.7.139` error code) - <https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission>
10. Disable Basic authentication in Exchange Online (already-permanently-disabled protocol list) - <https://learn.microsoft.com/exchange/clients-and-mobile-in-exchange-online/disable-basic-authentication-in-exchange-online>
11. Updated Exchange Online SMTP AUTH Basic Authentication Deprecation Timeline (Microsoft
    Community Hub / Exchange Team Blog - December 2026 default-disable date, 2027 H2 final-removal
    announcement) - <https://techcommunity.microsoft.com/blog/exchange/updated-exchange-online-smtp-auth-basic-authentication-deprecation-timeline/4489835>
12. Block legacy authentication in Exchange 2019 hybrid (the on-premises/hybrid-specific
    `-BlockLegacyAuth*`/`-BlockModernAuth*` parameter family - not used by this scenario, which
    targets pure Exchange Online via `-AllowBasicAuth*`) - <https://learn.microsoft.com/exchange/hybrid-deployment/block-legacy-auth-2019-hybrid>
13. Conditional access policy not behaving as expected - Microsoft Q&A (Conditional Access is a
    post-first-factor-authentication control; the reason this scenario exists as a companion, not a
    duplicate) - <https://learn.microsoft.com/answers/a/1903274>
14. [Automation surface, sections 1 and 3](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - automation surface 1 (Exchange Online PowerShell),
    app-only authentication pattern.
15. [RBAC model, section 6](/docs/rbac-model/#6-exchange-online-dependency-the-most-common-permissions-gap) - Exchange Online RBAC dependency.
16. *Block Legacy Authentication* - the Conditional Access sibling
    scenario whose four-lens review and the design notes deferred this fragment.
17. Audit log activities (Microsoft Purview) - the Exchange mailbox/admin activity reference
    confirming no RecordType/Operation exists for a rejected authentication attempt of any protocol
    - <https://learn.microsoft.com/purview/audit-log-activities>
18. Customize and filter activity logs in Microsoft Entra ID - the "Authenticated SMTP" sign-in-log
    client-app filter, documented as a pre-deployment discovery tool for legacy-auth usage -
    <https://learn.microsoft.com/entra/identity/monitoring-health/howto-customize-filter-logs>
19. signIn resource type (Microsoft Graph) - `clientAppUsed` schema (`SMTP` is the underlying value
    behind the portal's "Authenticated SMTP" label) - <https://learn.microsoft.com/graph/api/resources/signin>
20. SMTP AUTH clients report in the new EAC in Exchange Online - message-volume/TLS-usage report
    scoped to successful submissions only, not rejected attempts - <https://learn.microsoft.com/exchange/monitoring/mail-flow-reports/mfr-smtp-auth-clients-report>

> Re-verify all links, exact cmdlet parameter behavior, and the SMTP AUTH deprecation timeline
> against current Microsoft Learn before a customer-facing assessment or sale - this is an
> actively-evolving deprecation with dates that have already shifted once (originally announced for
> September 2025, updated to the December 2026 timeline cited here).