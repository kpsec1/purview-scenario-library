---
part: "runbook"
parent: "adaptive-protection/block-legacy-authentication"
---
## Implementation steps

### Step 1 - Assign permissions

In the **Microsoft Entra admin center**, assign administrators who will manage this control the
**Conditional Access Administrator** role - [RBAC model, section 10](/docs/rbac-model/#10-microsoft-entra-conditional-access---a-sixth-system-for-identity-layer-scenarios).

### Step 2 - Identify legacy authentication use before changing anything

Before creating or checking any policy, understand current impact:

1. **Entra admin center** → **Monitoring & health** → **Sign-in logs**, add the **Client App**
   column, filter by the legacy authentication protocols, and repeat on the
   **User sign-ins (non-interactive)** tab.
2. Or use the **Sign-ins using legacy authentication workbook**, which
   surfaces the same signal pre-filtered, with up to 90 days of history.

Do this even if a Microsoft-managed policy already exists (Step 3) - the workbook and sign-in logs
are the actual evidence a Report-only policy's impact is safe to promote, regardless of which
policy (Microsoft-managed or custom) is doing the evaluating.

### Step 3 - Check for an existing Microsoft-managed policy (scripted, read-only)

```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Dry run - the check itself makes no changes regardless of -WhatIf, but pass it to preview the
# create/update path this run would otherwise take if no managed policy is found.
./deploy/New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId -WhatIf
```

If a Microsoft-managed policy is found, the script stops here (no duplicate is created) and prints
its current state. Manage it directly in the **Microsoft Entra admin center** (exclude break-glass
accounts, or leave/promote its Report-only state) instead of continuing to Step 4 - unless you have
a specific reason to need an independent custom policy, in which case re-run with
`-SkipManagedPolicyCheck`.

### Step 4 - Identify and exclude break-glass/emergency-access accounts

Before deploying the custom policy path, identify (or create, per Microsoft's documented pattern
) a dedicated **emergency-access** security group, or list individual break-glass
account object IDs, plus any user accounts used as de-facto service accounts still dependent on
legacy protocols pending migration. Note their object ID(s)/group ID(s).

### Step 5 - Deploy the custom Conditional Access policy (scripted, dry-run capable)

```powershell
./deploy/New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId
```

Creates one Conditional Access policy scoped to all applications, all users except the excluded
break-glass group, restricted to `exchangeActiveSync`/`other` client app types, with a `block`
grant control (the configuration reference for the exact configuration) - in Report-only state.

### Step 6 - Pilot, then enforce

Review the policy's Report-only results in **Entra admin center** → **Conditional Access** →
**Insights and reporting**, cross-referenced against Step 2's workbook/log evidence, for at least a
few days of representative traffic before promoting:

```powershell
./deploy/New-BlockLegacyAuthenticationPolicy.ps1 -ExcludeGroupIds $EmergencyAccessGroupId -Mode Enabled -Force
```

### Step 7 - Validate

```powershell
./validate/Test-BlockLegacyAuthenticationPolicy.ps1 -ExpectedState enabled
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy name | `Block Legacy Authentication (Custom)` | Deliberately distinct from a Microsoft-managed policy's own `Microsoft-managed: ...`-prefixed name - see the known limitations. |
| Target resources | `includeApplications = ['All']` | Matches Microsoft's own documented "All resources" step. |
| Users | `includeUsers = ['All']` minus `-ExcludeUserIds`/`-ExcludeGroupIds` | Excludes break-glass accounts/group and any legacy-auth-dependent service accounts. Does **not** script Microsoft's additional documented "exclude guests/external user categories" nested condition - see the known limitations. |
| Client apps condition | `clientAppTypes = ['exchangeActiveSync', 'other']` | Matches Microsoft's documented procedure exactly: check **only** Exchange ActiveSync clients and Other clients - deliberately **not** Browser or Mobile apps and desktop clients, which are modern-auth client types. |
| Grant control | `builtInControls = ['block']`, `operator = 'OR'` | Matches Microsoft's documented "Block access" choice. |
| Initial policy state | `enabledForReportingButNotEnforced` (Report-only) | Matches Microsoft's own documented rollout sequence. |
| Break-glass exclusion | Not enabled by default - must be supplied via `-ExcludeUserIds`/`-ExcludeGroupIds` | The deploy script **warns** (does not refuse) if both are empty while `-Mode Enabled` - see the known limitations. |
| Microsoft-managed policy pre-check | On by default; skip with `-SkipManagedPolicyCheck` | Best-effort detection by `Microsoft-managed:`-prefixed displayName containing "legacy" - see the known limitations. |

## Operations and tuning

**KPIs to watch (first 90 days):** count of blocked legacy-auth sign-in attempts (by user and by
protocol), count of Report-only "would-have-been-blocked" events before promotion, and any
help-desk tickets tied to a legitimate account/device that still needs a legacy-auth exception.

**Tuning:** if a specific account genuinely cannot migrate off a legacy protocol yet (e.g. a
multifunction device that sends email via SMTP), add it to the exclusion group rather than
weakening the policy's `clientAppTypes`/grant-control shape - narrow, named exceptions preserve
the control's value for everyone else.

**Incident-response runbook (block event):**
1. **Triage** - the blocked sign-in appears in **Entra sign-in logs**, flagged with this policy's
   (or the Microsoft-managed policy's) name under **Conditional Access**; the **Client App**
   column names the specific legacy protocol used.
2. **Determine intent** - a single blocked attempt from a known user is usually a
   misconfigured device/client, not an attack; a burst of blocked attempts across many accounts in
   a short window, or from an unfamiliar location, is a credential-stuffing/password-spray
   indicator worth escalating - cross-reference with Entra ID Protection risk signals if licensed.
3. **Remediate** - for a legitimate device/client, migrate it to modern authentication if possible;
   if migration isn't immediately possible, add a narrowly-scoped exclusion rather than
   disabling the policy.

**Review cadence:** quarterly - re-run Step 2's workbook/log review to confirm no new legacy-auth
dependency has appeared, and re-check whether a Microsoft-managed policy has since appeared (e.g.
after a licensing upgrade to P2) that would supersede this scenario's custom policy.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → Report-only → permanent removal) for
this scenario's own **custom** policy. This scenario never modifies a Microsoft-managed policy -
Microsoft's own documentation states organizations can't rename or delete one; managing it (state,
exclusions) is a Microsoft Entra admin center action outside this scenario's scripts.

## References

1. Block legacy authentication with Conditional Access (the exact portal procedure - Users/Target
   resources/Client apps/Grant/Report-only sequence - this scenario's deploy script automates;
   attack-statistics; sign-in-log identification steps) - <https://learn.microsoft.com/entra/identity/conditional-access/policy-block-legacy-authentication>
2. Microsoft-managed Conditional Access policies (auto-deployment, 30-day auto-enable, "Created
   by: Microsoft" / `Microsoft-managed:` naming convention, P2/Business Premium eligibility,
   "duplicate if you need more changes" guidance) - <https://learn.microsoft.com/entra/identity/conditional-access/managed-policies>
3. Conditional Access: Conditions - Client apps (portal client-app categories: Browser, Mobile
   apps and desktop clients, Exchange ActiveSync clients, Other clients) - <https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-conditions>
4. conditionalAccessConditionSet resource type (`clientAppTypes` property, Graph v1.0, values
   all/browser/mobileAppsAndDesktopClients/exchangeActiveSync/easSupported/other) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset>
5. conditionalAccessPolicy resource type (`state` property; no documented Microsoft-managed-policy
   boolean flag) - <https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy>
6. Create / Update conditionalAccessPolicy (least-privileged permission
   `Policy.ReadWrite.ConditionalAccess` + `Policy.Read.All`) - <https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies>, <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update>
7. What is Conditional Access? (License requirements - Microsoft Entra ID P1) - <https://learn.microsoft.com/entra/identity/conditional-access/overview>
8. Security defaults in Microsoft Entra ID (zero-cost alternative for tenants without P1/P2;
   mutual-exclusivity guidance with Conditional Access) - <https://learn.microsoft.com/entra/fundamentals/security-defaults>
9. Block legacy authentication in Exchange 2019 hybrid (a separate, workload-specific,
   earlier-in-the-flow control surface - see the companion scenario
   *Exchange-Side Legacy Authentication Block*, which targets pure Exchange Online
   instead) - <https://learn.microsoft.com/exchange/hybrid-deployment/block-legacy-auth-2019-hybrid>
10. Manage emergency access (break-glass) accounts - <https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access>
11. Sign-ins using legacy authentication workbook - <https://learn.microsoft.com/entra/identity/monitoring-health/workbook-legacy-authentication>
12. New- / Update- / Get- / Remove-MgIdentityConditionalAccessPolicy (Microsoft.Graph.Identity.SignIns
    module) - <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/new-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgidentityconditionalaccesspolicy>, <https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/remove-mgidentityconditionalaccesspolicy>
13. Conditional access policy not behaving as expected - Microsoft Q&A (Conditional Access is a
    post-first-factor-authentication control, does not stop credential-stuffing/lockout attempts
    at the identity layer itself) - <https://learn.microsoft.com/answers/a/1903274>
14. [Licensing matrix, section 9](/docs/licensing-matrix/#9-adjacent-product-family-microsoft-entra-id-p1-baseline-conditional-access---block-legacy-authentication) - Microsoft Entra ID P1 (baseline Conditional Access), new in
    this build.
15. [RBAC model, section 10](/docs/rbac-model/#10-microsoft-entra-conditional-access---a-sixth-system-for-identity-layer-scenarios) - Microsoft Entra Conditional Access (reused unchanged from the
    sibling scenarios).
16. *Conditional Access Insider Risk Block* - the sibling scenario
    whose four-lens review originally flagged this gap.

> Re-verify all links, API behavior, and licensing terms against current Microsoft Learn before a
> customer-facing assessment or sale - Microsoft-managed Conditional Access policies are a
> comparatively new, actively-evolving mechanism that can change tenant eligibility or naming
> conventions faster than most of the Purview portfolio.