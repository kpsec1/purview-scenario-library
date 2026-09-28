---
part: "runbook"
parent: "adaptive-protection/dynamic-risk-dlp-enforcement"
---
## Implementation steps

This scenario is **portal-first for Adaptive Protection enablement** (section 6 explains why) and
**script-first for the DLP policy itself** - the one piece of Adaptive Protection with a
genuinely scriptable, independently-grounded PowerShell surface.

### Step 1 - Confirm (or deploy) a feeder Insider Risk Management policy

Adaptive Protection needs at least one Insider Risk Management policy already generating
alerts/insights before insider risk levels mean anything. Use
*Departing Employee Data Theft* in this library, or Microsoft's built-in
**Data leaks** template (Purview portal → **Insider Risk Management** → **Policies** → **Create
policy**). Not created by this scenario - see the design notes.

### Step 2 - Assign permissions

Purview portal → **Settings** → **Roles and groups** → **Role groups** → add administrators who
will configure Adaptive Protection to **Insider Risk Management** or **Insider Risk Management
Admins**; add administrators who will manage the DLP policy to **Compliance Administrator**,
**Compliance Data Administrator**, or **DLP Compliance Management**.

### Step 3 - Configure insider risk levels (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Adaptive protection** → **Insider risk
levels**. Select **Edit** for each of **Elevated**, **Moderate**, and **Minor**, and confirm (or
customize) the conditions that assign each level. Use
`deploy/policy/adaptive-protection-config-manifest.json` as the checklist/reference while doing
this - it documents Microsoft's own recommended "minimize false positives" starter configuration, not a fabricated default. Confirm the feeder policy from Step 1 is selected
on this tab.

### Step 4 - Deploy the DLP policy (scripted, dry-run capable)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows exactly what would be created, changes nothing
./deploy/New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

# Deploy in simulation mode (Microsoft's own Quick Setup default posture)
./deploy/New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode TestWithNotifications
```

This creates one DLP policy scoped to Exchange Online and Microsoft Teams, with two rules keyed
off the `SharedByIRMUserRisk` condition (the configuration reference for the exact configuration).

### Step 5 - Turn on Adaptive Protection (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Adaptive protection** → **Adaptive Protection
settings** → toggle **Adaptive Protection** to **On**. Allow up to **36 hours**
 before expecting risk levels to be assigned and this scenario's DLP rules to
actually match a user - see the known limitations.

### Step 6 - Pilot, then enforce

**Before enabling enforcement mode, confirm the feeder IRM policy has already completed at
least one full baseline/tuning cycle** (per that scenario's own operations guidance, e.g.
*Departing Employee Data Theft* (operations and tuning)) - enabling an automatic block on top of a
*newly deployed and still-tuning* detection policy compounds two unknowns (feeder policy
false-positive rate and this scenario's own scoping) into one harder-to-diagnose outcome. Run a
pilot on non-production test accounts while the policy is still in `TestWithNotifications`
mode. Once satisfied:

```powershell
./deploy/New-AdaptiveProtectionDlpPolicy.ps1 -AdminNotificationEmail 'soc@contoso.com' -Mode Enable -Force
```

### Step 7 - Validate

```powershell
./validate/Test-AdaptiveProtectionDlpPolicy.ps1
```

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| DLP policy name | `Adaptive Protection - Teams and Exchange DLP (Custom)` | Deliberately distinct from Microsoft's Quick-Setup-generated name - see the known limitations |
| Policy locations | Exchange Online, Microsoft Teams | Endpoint DLP (Devices) deferred - see the known limitations and the design notes |
| Rule 0: `AdaptiveProtection-Block-Elevated` | `SharedByIRMUserRisk = FCB9FA93-6269-4ACF-A756-832E79B36A2A` (Elevated) AND `AccessScope = NotInOrganization` → `BlockAccess = $true` | Approximates Microsoft's documented Quick Setup block rule (Elevated + shared externally → block) using this library's already-reviewed `AccessScope`-only pattern - see the known limitations VERIFY note |
| Rule 1: `AdaptiveProtection-Audit-ModerateMinor` | `SharedByIRMUserRisk = 797C4446-5C73-484F-8E58-0CCA08D6DF6C, 75A4318B-94A2-4323-BA42-2CA6DB29AAFE` (Moderate, Minor) AND `AccessScope = NotInOrganization` → audit only | Approximates Microsoft's documented Quick Setup audit rule - see the known limitations VERIFY note |
| Policy-tip wording | Generic ("blocked by a data loss prevention policy") - never states the user was flagged as an insider risk | Deliberate: revealing risk-flag status to the user would tip off a genuinely malicious insider mid-investigation - see the Red Team review |
| Initial policy mode | `TestWithNotifications` (simulation) | Matches Microsoft's own Quick Setup default - every rule Microsoft's wizard creates starts this way |
| Incident report severity | `Low` for both rules | Matches Microsoft's documented values |
| User override | Not enabled (default off) | Matches Microsoft's documented values - a flagged-elevated user cannot self-override the block |
| Insider risk level definitions | Elevated = confirmed alert of any severity; Moderate = high-severity alert; Minor = low/medium-severity alert | Microsoft's own "minimize false positives" recommended starting configuration - a starting point, tune per operations and tuning |
| Past activity detection window | 7 days (Microsoft default) | Configurable 5-30 days in Adaptive Protection settings; not overridden by this scenario |
| Insider risk level timeframe (auto-reset) | 7 days (Microsoft default) | How long a level stays assigned before automatically resetting, absent a new qualifying event |
| Adaptive Protection propagation delay | Up to 36 hours after first enabling | Backend processing delay in the Adaptive Protection service itself - not scriptable around |

## Operations and tuning

**KPIs to watch (first 90 days):**
- **Users assigned each risk level vs. block/audit action volume** - the Adaptive Protection
  dashboard (Purview portal → **Insider Risk Management** → **Adaptive protection** →
  **Dashboard**) shows counts by level; cross-reference against how often the Elevated-block
  rule actually fires. A high Elevated-level count with near-zero block events suggests flagged
  users aren't the ones triggering external-share activity - worth investigating whether the
  condition scope (external share only) is too narrow for your risk population.
- **False-positive rate on the Elevated block rule** - every block is, by construction, a
  potential business disruption for a real employee. Track how many blocked attempts, on
  investigation, turn out to be legitimate business activity by a user whose risk level was a
  false positive from the feeder IRM policy - this is a signal to tune the *IRM policy's*
  thresholds, not this scenario's DLP rule.
- **Time from risk-level assignment to first blocked/audited event** - measures how much of the
  detection-to-enforcement gap this scenario is actually closing for a given user.
- **Insider risk level reset rate** - how often a user's Elevated/Moderate/Minor level expires
  (the configuration reference and the validation steps-day default) versus how often it's renewed by a new qualifying event before expiring.
  A level that resets and reassigns repeatedly for the same user may indicate a borderline case
  worth a human decision rather than continued automated cycling.

**Tuning:** if too many or too few users are receiving a risk level, adjust the *insider risk
level conditions* in Adaptive Protection settings - not this scenario's DLP rule, which
should stay matched to Microsoft's own documented reference configuration unless there's a
specific, documented reason to diverge (see the design notes, priority-content scoping row, for
one example of a supported divergence: adding a sensitivity-label condition on top).

**Incident-response runbook (Elevated-block event):**
1. **Triage** - the blocked user receives a policy tip; the SOC receives an incident report. Open the DLP Alerts dashboard or Microsoft Defender portal to see the specific blocked
   activity.
2. **Cross-reference the feeder IRM policy's alert** - the block exists *because* of a specific
   Insider Risk Management alert; open that alert (per
   *Departing Employee Data Theft* (operations and tuning)'s own runbook) to see the
   underlying evidence, not just the fact that a block occurred. **This correlation is manual by
   design** - Microsoft does not document a shared correlation ID linking a DLP incident report
   to the specific IRM alert that produced the triggering risk level, so match them by user and
   timestamp rather than expecting an automated cross-reference.
3. **Classify** - is the Elevated risk level itself a true or false positive? If the underlying
   IRM alert is a false positive, the fix is in the feeder policy's tuning, not this scenario's
   DLP rule (see KPI note above) - do not weaken this scenario's rule to compensate for a
   different policy's tuning problem.
4. **Resolve** - if the IRM alert is confirmed a false positive, resolving/dismissing it resets
   the user's insider risk level, which lifts the block automatically on the next
   evaluation - no manual DLP exception needed. If it's a true positive, escalate per the feeder
   scenario's own incident-response runbook; this scenario's job (blocking the specific
   activity) is already done.

**Review cadence:** review insider risk level definitions and this policy's rule configuration
quarterly, using the KPIs above and the same cadence recommended for the feeder IRM policy.

**Coordinate with HR/Legal before broad enforcement-mode rollout.** Unlike the audit-only DLP
scenarios elsewhere in this library, the Elevated-block rule here automatically restricts a
*specific, identifiable* employee's ability to communicate externally, driven by an opaque
ML-computed risk score rather than a human decision. Treat enabling `-Mode Enable` org-wide as an
HR/Legal-notified change, not a purely technical deployment step - an employee who is blocked
and later disputes the underlying risk assessment is a personnel/employment-relations matter,
not only a DLP support ticket. This is a residual consideration for CISO sign-off, not something
this scenario's code can mitigate on its own - see the CISO review.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent removal).
Quick reference: `./deploy/Remove-AdaptiveProtectionDlpPolicy.ps1` disables the policy
(reversible in seconds); `-Purge` permanently deletes it. Neither action disables Adaptive
Protection itself, the feeder IRM policy, or resets any user's current insider risk level.

## References

1. Help dynamically mitigate risks with Adaptive Protection (insider risk levels, 36-hour/6-hour
   propagation delays, custom setup, disable behavior) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
2. Permissions for Adaptive Protection (role groups per task) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection#permissions-for-adaptive-protection>
3. Learn about Adaptive Protection in Data Loss Prevention (documented Quick Setup rule
   values for Teams/Exchange and Devices policies) - <https://learn.microsoft.com/purview/dlp-adaptive-protection-learn>
4. Adaptive Protection configuration guide (recommended Elevated/Moderate/Minor definitions to
   minimize false positives) - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection-guide>
5. Insider Risk Management policy templates (Data leaks template) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates>
6. New-DlpComplianceRule reference (`-SharedByIRMUserRisk` parameter and GUID values) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
7. Set-DlpComplianceRule reference (`-SharedByIRMUserRisk` parameter) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
8. Managing insider risk for the Australian Government - worked example of an Adaptive
   Protection DLP rule with an added sensitivity-label condition - <https://learn.microsoft.com/compliance/anz/pspf-insider-risk#adaptive-protection>
9. Microsoft Entra recommendation: Protect your tenant with Insider Risk condition in
   Conditional Access policy (Microsoft Entra ID P2 license requirement for the Conditional
   Access integration this scenario does not configure) - <https://learn.microsoft.com/entra/identity/monitoring-health/recommendation-insider-risk-condition>
10. [Licensing matrix, section 2](/docs/licensing-matrix/#2-master-capability--license-matrix) - Adaptive Protection row (E5/Suite, built on IRM + DLP)
11. New-DlpCompliancePolicy / Set-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>, <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancepolicy>
12. Remove-DlpCompliancePolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancepolicy>
13. DLP policy reference - locations table (Exchange, Teams, Devices support for Adaptive
    Protection) - <https://learn.microsoft.com/purview/dlp-policy-reference#locations>
14. Block access for users with insider risk (the how-to guide independently re-fetched during
    this scenario's 2026-09-09 correction pass - carries no preview label) - <https://learn.microsoft.com/entra/identity/conditional-access/policy-risk-based-insider-block>
15. conditionalAccessConditionSet resource type (`insiderRiskLevels` property, Graph v1.0 -
    independently re-fetched during the same correction pass, confirmed current/non-beta) - <https://learn.microsoft.com/graph/api/resources/conditionalaccessconditionset>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - Adaptive Protection is a comparatively new
> capability that changes faster than most in the Purview portfolio.