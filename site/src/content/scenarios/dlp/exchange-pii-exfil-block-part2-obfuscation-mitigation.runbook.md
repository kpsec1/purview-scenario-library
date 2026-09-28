---
part: "runbook"
parent: "dlp/exchange-pii-exfil-block-part2-obfuscation-mitigation"
---
## Implementation steps

### Step 1 - Confirm Part 1 and Adaptive Protection are already deployed

This fragment extends, rather than replaces, *Exchange PII Exfiltration Block (Block or Encrypt)*'s policy.
Confirm it exists and Adaptive Protection is already enabled (per `dynamic-risk-dlp-enforcement/
the implementation steps Steps 1-3, 5) before continuing.

### Step 2 - Enable the Exchange DLP-alerts indicator (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** → **Built-in
Indicators** tab → **Data loss prevention (DLP) indicators** → **Add DLP policies** → select
**PII DLP - Exchange External Send Control** → **Add** → check **Generating alerts from selected
DLP policies** → **Save**. Confirm the parent policy's
`PII-Exchange-Protect-External` and `PII-Exchange-Override-External` (if configured) rules are
already at `ReportSeverityLevel: High` - the parent scenario's deploy script sets this by default,
so no change should be needed.

### Step 3 - Create the feeder Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy** → template
**Data leaks**. Use `deploy/policy/irm-exchange-drip-exfiltration-config-manifest.json` as the
checklist/reference while doing this:
- **Users/groups:** same population as the parent scenario's DLP policy scope.
- **Triggering event:** on the **Triggers for this policy** page, select **User matches a data
  loss prevention (DLP) policy** and choose **PII DLP - Exchange External Send Control** from the
  dropdown - **not** "User performs an exfiltration activity" (that's the
  correct choice only for the Teams sibling fragment, which has no direct DLP-alert path - see
  the design notesa for why the direct trigger is the better choice here).
- **Cumulative exfiltration detection:** leave **ON** (default for this template).
- **Prioritize content:** sensitive information types → SSN, Credit Card Number.

### Step 4 - Add the feeder policy to Adaptive Protection's scope (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Adaptive protection** → **Insider risk levels** →
confirm the new policy from Step 3 is included, alongside any existing feeder policy (e.g.
*Departing Employee Data Theft* or the Teams sibling fragment's own feeder
policy). Insider risk levels are tenant-wide and computed from every in-scope feeder policy - see
*Dynamic Risk-Based DLP Enforcement* (the known limitations).

### Step 5 - Deploy the new DLP rule (scripted, dry-run capable)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows exactly what would change, makes no changes
./deploy/New-ExchangePiiElevatedRiskBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

# Deploy: compacts every existing rule on the parent policy to start at priority 1,
# adds the new rule at priority 0
./deploy/New-ExchangePiiElevatedRiskBlock.ps1 -AdminNotificationEmail 'soc@contoso.com'

# Validate
./validate/Test-ExchangePiiElevatedRiskBlock.ps1
```

The new rule's block action takes effect as soon as the parent policy is in `Enable` mode (Part
1's own deploy/rollout cadence governs that, unchanged by this fragment) - there is no separate
simulation toggle for one rule within an already-live policy. If Part 1's policy is still in
`TestWithNotifications`, this rule will also only simulate.

## Configuration reference

| Setting | `PII-Exchange-ElevatedRisk-Block-AllExternal` (this fragment) |
|---|---|
| Priority | **0** (every other rule on the parent policy compacts to start at 1, preserving relative order - see the design notes, name-agnostic to how many rules exist) |
| Condition | `SharedByIRMUserRisk = FCB9FA93-6269-4ACF-A756-832E79B36A2A` (Elevated) AND `AccessScope = NotInOrganization` |
| Content/SIT condition | **None** - fires on any Exchange message content, matching or not matching SSN/Credit Card Number |
| `BlockAccess` | `$true` - always, regardless of whether the parent policy is running `-Action Block` or `-Action Encrypt` |
| Override allowed | **No** - even for the parent scenario's `-ExceptionGroupEmail` members |
| `StopPolicyProcessing` | `$true` |
| `ReportSeverityLevel` | High |

Full cmdlet parameter grounding: `deploy/New-ExchangePiiElevatedRiskBlock.ps1` inline comments and
its `.NOTES` block. Portal-only prerequisite configuration (DLP-alerts indicator, feeder IRM
policy, Adaptive Protection scope): `deploy/policy/irm-exchange-drip-exfiltration-config-manifest.json`.

## Operations and tuning

**KPIs to watch (first 90 days), in addition to Part 1's own and *Dynamic Risk-Based DLP Enforcement*'s
own KPI sets:**
- **Time from a user's first qualifying High-severity DLP alert to Elevated-risk assignment** -
  measures how long the exposure window actually is for this control, given Cumulative
  exfiltration detection's ~daily evaluation cadence and up-to-36-hour Adaptive Protection
  propagation. If this is consistently multiple days, the compensating control is closing the
  channel too late to matter for a fast, deliberate exfiltration attempt - a finding to escalate
  to CISO review, not something to silently tune around.
- **`PII-Exchange-ElevatedRisk-Block-AllExternal` match volume vs. the parent policy's
  `PII-Exchange-Protect-External`/`PII-Exchange-Override-External` volume** - a rule-0 match with
  no preceding Protect-External match for the same user in recent history suggests the
  Elevated-risk assignment came from a *different* IRM indicator entirely (e.g., SharePoint/OneDrive
  exfiltration, or the Teams sibling fragment's own feeder policy) - investigate via the feeder
  policy's own alert before assuming an Exchange-specific pattern.

**Coordinate with HR/Legal before broad enforcement rollout**, same as
*Dynamic Risk-Based DLP Enforcement* (operations and tuning) already requires for its own Elevated-block rule - this
fragment's rule is an *additional*, PII-specific enforcement point driven by the same ML-computed,
opaque risk score, and removes even the `-ExceptionGroupEmail` override path Part 1 otherwise
guarantees. Treat it as the same class of HR/Legal-notified change, not a purely technical
deployment step.

**Incident-response runbook (this rule's block event):**
1. **Triage** - same first step as *Dynamic Risk-Based DLP Enforcement* (operations and tuning): open the DLP
   Alerts dashboard/Defender incident, confirm the rule name and sender.
2. **Cross-reference the feeder IRM policy's alert** by user and timestamp (manual - no shared
   correlation ID, the validation steps) **and confirm which indicator actually drove the Elevated assignment** - a
   repeated Exchange PII match, or an unrelated exfiltration indicator (including the Teams sibling
   fragment's own feeder policy, if both are deployed). Don't assume a PII-data link without
   checking.
3. **Classify** - is the Elevated risk level a true or false positive? Same guidance as
   *Dynamic Risk-Based DLP Enforcement* (operations and tuning) - fix the *feeder policy's* tuning if it's a false
   positive, not this rule.
4. **If true positive:** treat as a live incident under the parent scenario's own regulatory
   drivers - this user has already been blocked from further external Exchange sharing; escalate
   per the org's incident-response process and consider a full account review, not just DLP-alert
   closure, given the drip-feed evasion pattern this control exists to catch.

**Review cadence:** quarterly, aligned with the parent scenario's own review cadence and
*Dynamic Risk-Based DLP Enforcement*'s.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-ExchangePiiElevatedRiskBlock.ps1` switches the
rule to audit-only (reversible); `-Purge` permanently removes it and decompacts the parent policy's
remaining rules back to contiguous 0-based priorities in their original relative order. Neither
action touches the parent scenario's own rules' content, the Encrypt-mode audit companion's rule
(if deployed), or *Dynamic Risk-Based DLP Enforcement*'s separate policy.

## References

1. Configure policy indicators in Insider Risk Management - Data loss prevention alerts
   indicators, supported workloads (Exchange Online, SharePoint Online, OneDrive for Business) - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#data-loss-prevention-alerts-indicators>
2. Learn about Insider Risk Management policy templates - Data leaks policy guidelines, the
   Incident-reports-High-severity requirement for the DLP-policy triggering event - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-templates>
3. Get started with Insider Risk Management - Step 6, "Triggers for this policy" page: "User
   matches a data loss prevention (DLP) policy" vs. "User performs an exfiltration activity" - <https://learn.microsoft.com/purview/insider-risk-management-configure#step-6-required-create-an-insider-risk-management-policy>
4. Create and manage Insider Risk Management policies - Cumulative exfiltration detection (daily
   evaluation, 30-day comparison window, enabled-by-default templates) - <https://learn.microsoft.com/purview/insider-risk-management-policies#cumulative-exfiltration-detection>
5. Create and manage Insider Risk Management policies - Immediately start scoring user activity
   ("Start scoring activity for users") - <https://learn.microsoft.com/purview/insider-risk-management-policies#immediately-start-scoring-user-activity>
6. Help dynamically mitigate risks with Adaptive Protection - 36-hour propagation delay - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
7. New-DlpComplianceRule / Set-DlpComplianceRule reference (`SharedByIRMUserRisk`, `Priority`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>, <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
8. Remove-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
9. Learn about Insider Risk Management policy templates - policy template prerequisites and
   triggering events table (Data leaks: DLP policy configured for High severity alerts, Exchange
   Online/SharePoint Online/OneDrive for Business workloads only) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-prerequisites-and-triggering-events>
10. Create and manage Insider Risk Management policies - Policy health notification messages
    ("DLP policy doesn't meet requirements", "DLP policy isn't selected as the triggering event") - <https://learn.microsoft.com/purview/insider-risk-management-policies#policy-health>
11. *Exchange PII Exfiltration Block (Block or Encrypt)* (the known limitations and the references) - the original documented gap and
    Part 1's own citation list (SSN/Credit Card Number SITs, Exchange DLP conditions/actions).
12. *PCI Teams Exfiltration Block, Part 2: Split/Obfuscated PAN Compensating Control* - the sibling scenario this
    one's compensating-control pattern (`-SharedByIRMUserRisk`, no-override, priority-0 rule)
    directly reuses, and the source of the Teams-workload constraint this fragment's the design notes
    contrasts against.
13. *Dynamic Risk-Based DLP Enforcement* (the prerequisites and the architecture and the implementation steps and the configuration reference and the known limitations and the references) - the
    `SharedByIRMUserRisk` grounding and Adaptive Protection prerequisites this fragment reuses
    without re-deriving.

> Re-verify all links and product behavior against current Microsoft Learn before a
> customer-facing assessment or sale - Insider Risk Management and Adaptive Protection are
> comparatively new capabilities that change faster than most in the Purview portfolio.