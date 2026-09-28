---
part: "runbook"
parent: "information-protection/auto-label-confidential-exchange"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the **Confidential** label's scope includes **Emails** (Purview portal → Information
   Protection → Labels → select **Confidential** → Edit → confirm **Emails** is checked under
   scope). If it only covers Files & other data assets today, add Emails to its scope before
   continuing.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Information Protection** → **Policies** → **Auto-labeling policies** → **+ Create
   auto-labeling policy** → **Automatically apply label only**.
3. Category: **Custom** → **Custom policy** → **Next**.
4. Name: `Confidentiality - Auto-Label PII in Exchange Email`.
5. **Choose a label to auto-apply**: select the existing **Confidential** label.
6. **Choose locations**: select **Exchange email** only (leave SharePoint/OneDrive unselected -
   those are covered by the sibling scenario's own policy). Keep **All** included and **None**
   excluded if the policy must evaluate incoming mail from outside your organization; otherwise
   exclude the nominated legal/eDiscovery mailbox under **Excluded**.
7. **Set up common or advanced rules** → **Common rules** → add condition **Content contains** →
   **Sensitive info types** → add **U.S. Social Security Number (SSN)** and **Credit Card
   Number**, minimum count **1** each, combined with **Any of these** (logical OR).
8. **Additional label settings**: leave default (don't force-override higher-priority labels).
9. **Decide if you want to test out the policy now or later**: select **Run policy in simulation
   mode**; do **not** enable "turn on automatically after 7 days" - same deliberate-enable
   standard as the sibling scenario.
10. **Submit** → **Done**.
11. **While simulation is running, send and receive representative test messages.** Unlike the
    SharePoint/OneDrive sibling scenario, Exchange simulation does not scan existing mailbox
    content - it only evaluates live traffic during the simulation window. A simulation run with no test traffic during the window
    will show zero matches even for a correctly configured rule.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-ConfidentialAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) - then send/receive test mail while it runs
./deploy/New-ConfidentialAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com'

# 4. After a review window with real test traffic, enforce
./deploy/New-ConfidentialAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-ConfidentialAutoLabelExchangePolicy.ps1 -LabelName 'Confidential'
```

The deploy script uses Security & Compliance PowerShell (`New-AutoSensitivityLabelPolicy`,
`New-AutoSensitivityLabelRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), the
same surface the sibling scenario uses.

## Configuration reference

| Setting | Rule: `AutoLabel-Confidential-PII-Exchange` |
|---|---|
| `Workload` | `Exchange` |
| Sensitive info types | U.S. Social Security Number (SSN), Credit Card Number - `mincount = 1` each, OR-combined (same conditions as the sibling scenario) |
| `Policy` | `Confidentiality - Auto-Label PII in Exchange Email` |

| Policy-level setting | Value |
|---|---|
| `ApplySensitivityLabel` | `<LabelName>` (default `Confidential`) - must reference an existing, published, non-parent label whose scope includes **Emails** |
| `ExchangeLocation` | `All` |
| `ExchangeSenderException` | `<ExcludedMailboxSmtpAddress>` (optional; one or more SMTP addresses) - excludes that mailbox's **outbound** mail only, not mail sent to it |
| `OverwriteLabel` | `$true` - same semantics as the sibling scenario: overrides a lower-priority auto-applied/default label only, never a manual one |
| `ExternalMailRightsManagementOwner` | Not set (optional; see the known limitations) |
| `Mode` | `TestWithNotifications` (deploy default) → `Enable` after review |

Full cmdlet parameter grounding: `deploy/New-ConfidentialAutoLabelExchangePolicy.ps1` inline
comments and its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence**: Off → simulation mode (with test traffic sent/received during the window,
the implementation steps and the validation steps) → review for at least a business cycle (7+ days) → Enable. Same deliberate-enable standard
as the sibling scenario and this library's standards - do not accept the portal's "auto-turn-on after 7 days"
option.

**KPIs to watch (first 30-60 days):**
- **Activity Explorer "Sensitivity label applied" volume for Exchange**, filtered to this label and
  a How-applied value of automatic. This is the closest Exchange equivalent to the sibling
  scenario's Labeled-items count, with the caveat that it aggregates every auto-labeling policy
  applying this label, not just this one, if more than one exists.
- **Items-to-review match volume during any future re-simulation** (e.g., after a rule change) -
  remember this only reflects traffic sent during that specific window, so a "zero matches"
  result after a rule change needs fresh test traffic before it can be trusted.
- **False-positive rate on the SSN SIT** - same tuning guidance as the sibling scenario: nine-digit
  numbers that aren't SSNs are the most common false-positive source; watch for user-reported
  "why was my email suddenly Confidential/encrypted" tickets as the practical detection signal,
  since there is no per-item failure dashboard for email the way there is for files.

**Alert routing:** same as the sibling scenario - no DLP-style incident-report email from
auto-labeling itself. For Exchange specifically, also budget for the **encryption side-effect**:
an internal sender whose message matches this rule will see their message encrypted whether or not
the encryption was the intended outcome - an unexpected support ticket
("why is my recipient unable to forward this email") is a plausible early signal worth routing to
the Information Protection team's queue, not just to help desk generic triage.

**Review cadence:** monthly for the first quarter alongside the sibling scenario's own review
cadence (same underlying label, same team, same false-positive tuning conversation), quarterly
thereafter.

**Runbook - an email that should be labeled isn't:**
1. Confirm the message wasn't sent/received outside a simulation window if you're still validating
   in simulation - this is expected, not a bug.
2. Confirm the sender isn't the excluded mailbox - outbound mail from that mailbox is
   never evaluated, by design.
3. Confirm at least 60-90 minutes have passed before checking Activity Explorer
   - a message that hasn't shown up yet may simply not have propagated to the
   activity feed.
4. Confirm the label's scope still includes **Emails** - an edit to the label (e.g., by someone
   working on the sibling scenario's SharePoint/OneDrive use case) that narrows scope back to
   "Files & other data assets only" would silently stop this policy from having any effect, with no
   portal error surfaced (same class of silent-failure risk the sibling scenario documents for its
   own prerequisites).
5. If none of the above explains it, check for a **rule-load failure** - a malformed rule can
   silently stop matching all Exchange traffic with no item-level failure to review, because the
   rule never loaded in the first place. Re-run the automated config check; if
   it reports the rule missing or malformed, recreate it from this scenario's deploy script.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-ConfidentialAutoLabelExchangePolicy.ps1` disables (reversible); add
`-Purge` to permanently delete the policy and its rule.

## References

1. Automatically apply a sensitivity label to Microsoft 365 data - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically>
2. Automatically apply a sensitivity label to Microsoft 365 data - "Auto-labeling for Exchange" behavior (attachment scanning vs. labeling, Message Encryption inheritance, IRM interaction with mail flow rules/DLP, external-sender labeling and encryption defaults) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#compare-auto-labeling-for-office-apps-with-auto-labeling-policies>
3. Automatically apply a sensitivity label to Microsoft 365 data - "How to configure auto-labeling policies for SharePoint, OneDrive, and Exchange" (mass-mailing caution, ExchangeLocation All/None-excluded requirement for external senders, encryption permission-model differences for Exchange-only policies) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#how-to-configure-auto-labeling-policies-for-sharepoint,-onedrive,-and-exchange>
4. Data Loss Prevention policy reference - "Content contains" supports multiple sensitive info types combined with "Any of these" (OR) or "All of these" (AND); same condition-group model underlies auto-labeling rules - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
5. Automatically apply a sensitivity label to Microsoft 365 data - "Will an existing label be overridden?" - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#will-an-existing-label-be-overridden>
6. Automatically apply a sensitivity label to Microsoft 365 data - "Example: Apply a label to Exchange email based on the subject" (live-traffic-only simulation for Exchange, label scope must include Emails) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#example-apply-a-label-to-exchange-email-based-on-the-subject>
7. Use the Insights tab to analyze auto-labeling policies in Microsoft Purview - Exchange email excluded from Labeled items/enforcement metrics; Activity Explorer as the documented alternative, 60-90 minute delay, doesn't identify the specific policy/rule - <https://learn.microsoft.com/purview/auto-label-insights-tab>
8. Use the Insights tab to analyze auto-labeling policies in Microsoft Purview - simulation-mode Insights, Exchange matched-item counts are estimates from sampled data; pre-flight checklist role requirements for turning on a policy (Compliance Administrator / Compliance Data Administrator) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin>
9. New-AutoSensitivityLabelPolicy reference (full parameter syntax - confirms no `-ExchangeLocationException` parameter exists; `-ExchangeSender`/`-ExchangeSenderException`/`-ExchangeSenderMemberOf`/`-ExchangeSenderMemberOfException`/`-ExternalMailRightsManagementOwner`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy>
10. New-AutoSensitivityLabelRule reference (`-Workload` accepted values: Exchange, SharePoint, OneDriveForBusiness; Exchange-only advanced conditions such as `-SubjectMatchesPatterns`, `-SenderIPRanges`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule>
11. Automatically apply a sensitivity label to Microsoft 365 data - "Policy rule fails to load" troubleshooting (rule-load failure has no item-level symptom) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#policy-rule-fails-to-load>
12. Set-AutoSensitivityLabelPolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy>
13. Remove-AutoSensitivityLabelPolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy>
14. Get-Label reference - <https://learn.microsoft.com/powershell/module/exchange/get-label>
15. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
16. Email marking strategies using Microsoft Purview for the Australian Government - `msip_labels` header and x-header-based cross-organization marking (background for the non-goal in the design notes, not implemented by this scenario) - <https://learn.microsoft.com/compliance/anz/pspf-dlp-marking>

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - auto-labeling behavior for Exchange (simulation semantics, Insights tab detail) has
> changed more than once in this feature's history, same caveat as the sibling scenario.