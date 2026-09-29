---
part: "runbook"
parent: "dlp/pci-teams-exfil-block-part2-obfuscation-mitigation"
---
## Implementation steps

### Step 1 - Confirm Part 1 and Adaptive Protection are already deployed

This fragment extends, rather than replaces, *PCI Teams Card-Data Exfiltration Block*'s policy.
Confirm it exists and Adaptive Protection is already enabled (per `dynamic-risk-dlp-enforcement/
the implementation steps Steps 1-3, 5) before continuing.

### Step 2 - Enable the Communication Compliance SIT indicator (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Settings** → **Policy indicators** →
**Communication Compliance indicators (preview)** → under **Detect messages matching specific
trainable classifiers (preview)**, select **Create policy**. Then, in the **Policy indicators**
setting, select the sensitive-information-type detection option and choose **Credit Card
Number**. This is the one documented mechanism that extends IRM coverage to
Microsoft Teams messages - see the known limitations for why the more obvious "wire the Teams DLP policy directly"
approach does not work.

### Step 3 - Create the feeder Insider Risk Management policy (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Policies** → **Create policy** → template
**Data leaks**. Use `deploy/policy/irm-drip-exfiltration-config-manifest.json` as the
checklist/reference while doing this:
- **Users/groups:** same population as Part 1's DLP policy scope.
- **Triggering event:** **User performs an exfiltration activity** (built-in Office exfiltration
  indicators) - not the DLP-policy-match trigger, which excludes Teams.
- **Indicators:** the Communication Compliance indicator from Step 2 (Credit Card Number), plus
  the default built-in Office exfiltration indicators.
- **Cumulative exfiltration detection:** leave **ON** (default for this template).
- **Prioritize content:** sensitive information types → Credit Card Number.

### Step 4 - Add the feeder policy to Adaptive Protection's scope (portal, not scriptable)

Purview portal → **Insider Risk Management** → **Adaptive protection** → **Insider risk levels**
→ confirm the new policy from Step 3 is included, alongside any existing feeder policy (e.g.
*Departing Employee Data Theft*). Insider risk levels are tenant-wide and
computed from every in-scope feeder policy - see *Dynamic Risk-Based DLP Enforcement* (the known limitations).

### Step 5 - Deploy the new DLP rule (scripted, dry-run capable)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# Dry run - shows exactly what would change, makes no changes
./deploy/New-PciElevatedRiskTeamsBlock.ps1 -AdminNotificationEmail 'soc@contoso.com' -WhatIf

# Deploy: re-prioritizes Part 1's three rules to 1/2/3, adds the new rule at priority 0
./deploy/New-PciElevatedRiskTeamsBlock.ps1 -AdminNotificationEmail 'soc@contoso.com'

# Validate
./validate/Test-PciElevatedRiskTeamsBlock.ps1
```

The new rule's block action takes effect as soon as the parent policy is in `Enable` mode (Part
1's own deploy/rollout cadence governs that, unchanged by this fragment) - there is no separate
simulation toggle for one rule within an already-live policy. If Part 1's policy is still in
`TestWithNotifications`, this rule will also only simulate.

## Configuration reference

| Setting | `PCI-ElevatedRisk-Block-AllExternal` (this fragment) |
|---|---|
| Priority | **0** (Part 1's `PCI-CardOps-Override-External`, `PCI-Block-External-AllUsers`, `PCI-Audit-Internal-AllUsers` shift to 1/2/3) |
| Condition | `SharedByIRMUserRisk = FCB9FA93-6269-4ACF-A756-832E79B36A2A` (Elevated) AND `AccessScope = NotInOrganization` |
| Content/SIT condition | **None** - fires on any Teams message content, matching or not matching Credit Card Number |
| `BlockAccess` | `$true` |
| Override allowed | **No** - even for Card Operations group members |
| `StopPolicyProcessing` | `$true` |
| `ReportSeverityLevel` | High |

Full cmdlet parameter grounding: `deploy/New-PciElevatedRiskTeamsBlock.ps1` inline comments and
its `.NOTES` block. Portal-only prerequisite configuration (IRM policy, Communication Compliance
indicator, Adaptive Protection scope): `deploy/policy/irm-drip-exfiltration-config-manifest.json`.

## Operations and tuning

**KPIs to watch (first 90 days), in addition to Part 1's own and *Dynamic Risk-Based DLP Enforcement*'s
own KPI sets:**
- **Time from a user's first card-data-adjacent Teams activity to Elevated-risk assignment** -
  measures how long the exposure window actually is for this control, given the ~daily
  cumulative-exfiltration-detection cadence and up-to-36-hour Adaptive Protection propagation. If this is consistently multiple days, the compensating control is closing the channel
  too late to matter for a fast, deliberate exfiltration attempt - a finding to escalate to CISO
  review, not something to silently tune around.
- **`PCI-ElevatedRisk-Block-AllExternal` match volume vs. Part 1's Rule 1/Rule 2 volume** - a
  rule 0 match with no preceding Rule 2 (internal audit) match for the same user in recent
  history suggests the Elevated-risk assignment came from a *different* IRM indicator entirely
  (e.g., SharePoint/OneDrive exfiltration, not Teams card-data activity at all) - investigate via
  the feeder policy's own alert before assuming a Teams-specific pattern.

**Coordinate with HR/Legal before broad enforcement rollout**, same as
*Dynamic Risk-Based DLP Enforcement* (operations and tuning) already requires for its own Elevated-block rule -
this fragment's rule is an *additional*, PCI-specific enforcement point driven by the same
ML-computed, opaque risk score, and removes even the Card Ops override path Part 1 otherwise
guarantees. Treat it as the same class of HR/Legal-notified change, not a purely technical
deployment step.

**Incident-response runbook (this rule's block event):**
1. **Triage** - same first step as *Dynamic Risk-Based DLP Enforcement* (operations and tuning): open the DLP
   Alerts dashboard/Defender incident, confirm the rule name and sender.
2. **Cross-reference the feeder IRM policy's alert** by user and timestamp (manual - no shared
   correlation ID, the validation steps) **and confirm which indicator actually drove the Elevated assignment** -
   the Credit Card Number Communication Compliance indicator, or an unrelated exfiltration
   indicator. Don't assume a card-data link without checking.
3. **Classify** - is the Elevated risk level a true or false positive? Same guidance as
   *Dynamic Risk-Based DLP Enforcement* (operations and tuning) - fix the *feeder policy's* tuning if it's a false
   positive, not this rule.
4. **If true positive:** treat as a live PCI-scoped incident - this user has already been blocked
   from further external Teams sharing; escalate per the org's incident-response process and
   consider a full account review, not just DLP-alert closure, given the drip-feed evasion
   pattern this control exists to catch.

**Review cadence:** quarterly, aligned with Part 1's own review cadence and
*Dynamic Risk-Based DLP Enforcement*'s.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-PciElevatedRiskTeamsBlock.ps1` switches the
rule to audit-only (reversible); `-Purge` permanently removes it and restores Part 1's original
0/1/2 rule priorities. Neither action touches Part 1's own three rules' content or
*Dynamic Risk-Based DLP Enforcement*'s separate policy.

## References

1. Configure policy indicators in Insider Risk Management - Communication Compliance indicators
   (Teams/Exchange/Viva Engage/Copilot coverage, SIT detection) - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
2. Create and manage Insider Risk Management policies - Cumulative exfiltration detection (daily
   evaluation, 30-day comparison window, enabled-by-default templates) - <https://learn.microsoft.com/purview/insider-risk-management-policies#cumulative-exfiltration-detection>
3. Create and manage Insider Risk Management policies - Immediately start scoring user activity
   ("Start scoring activity for users") - <https://learn.microsoft.com/purview/insider-risk-management-policies#immediately-start-scoring-user-activity>
4. Configure policy indicators in Insider Risk Management - Data loss prevention alerts
   indicators, supported DLP workloads (Teams explicitly excluded, "by design") - <https://learn.microsoft.com/purview/insider-risk-management-settings-policy-indicators#built-in-indicators-vs-custom-indicators>
5. Learn about Insider Risk Management policy templates - policy template prerequisites and
   triggering events - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-template-prerequisites-and-triggering-events>
6. Help dynamically mitigate risks with Adaptive Protection - 36-hour propagation delay - <https://learn.microsoft.com/purview/insider-risk-management-adaptive-protection>
7. New-DlpComplianceRule / Set-DlpComplianceRule reference (`SharedByIRMUserRisk`, `Priority`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>, <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
8. Remove-DlpComplianceRule reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
9. *PCI Teams Card-Data Exfiltration Block* (the known limitations and the references) - the original Red Team finding and
   Part 1's own citation list (Credit Card Number SIT, DLP-for-Teams licensing/scoping).
10. *Dynamic Risk-Based DLP Enforcement* (the prerequisites and the architecture and the implementation steps and the configuration reference and the known limitations and the references) - the
    `SharedByIRMUserRisk` grounding and Adaptive Protection prerequisites this fragment reuses
    without re-deriving.

> Re-verify all links and product behavior against current Microsoft Learn before a
> customer-facing assessment or sale - Insider Risk Management and Adaptive Protection are
> comparatively new capabilities that change faster than most in the Purview portfolio.