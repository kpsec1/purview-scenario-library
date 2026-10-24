---
part: "runbook"
parent: "information-protection/auto-label-eu-personal-data-exchange"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the **Confidential** label's scope includes **Emails** (Purview portal → Information
   Protection → Labels → select **Confidential** → Edit → confirm **Emails** is checked under
   scope). If it only covers Files & other data assets today (e.g., because only the SharePoint/
   OneDrive EU sibling has been deployed so far), add Emails to its scope before continuing.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Information Protection** → **Policies** → **Auto-labeling policies** → **+ Create
   auto-labeling policy** → **Automatically apply label only**.
3. Category: **Custom** → **Custom policy** → **Next**.
4. Name: `Confidentiality - Auto-Label EU Personal Data in Exchange Email`.
5. **Choose a label to auto-apply**: select the existing **Confidential** label. Confirm it is
   *not* shown as a parent label in the picker.
6. **Choose locations**: select **Exchange email** only (leave SharePoint/OneDrive unselected -
   those are covered by the SharePoint/OneDrive EU sibling's own policy). Keep **All** included and
   **None** excluded if the policy must evaluate incoming mail from outside your organization;
   otherwise exclude the nominated legal/eDiscovery mailbox under **Excluded**.
7. **Set up common or advanced rules** → **Common rules** → add condition **Content contains** →
   **Sensitive info types** → add **EU national identification number**, **EU Social Security
   Number (SSN) or Equivalent ID**, and **EU debit card number**, minimum count **1** each,
   combined with **Any of these** (logical OR). To localize to specific member
   states instead of the full EU-wide bundles, search the picker for the individual per-country SIT
   (e.g. "Germany Identity Card Number") and use that in place of the bundle.
8. **Additional label settings**: leave default (don't force-override higher-priority labels).
9. **Decide if you want to test out the policy now or later**: select **Run policy in simulation
   mode**; do **not** enable "turn on automatically after 7 days" - same deliberate-enable standard
   as both sibling scenarios.
10. **Submit** → **Done**.
11. **While simulation is running, send and receive representative test messages.** Exchange
    simulation does not scan existing mailbox content - it only evaluates live traffic during the
    simulation window(the design notes sibling reference). A simulation run with
    no test traffic during the window will show zero matches even for a correctly configured rule.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none. Default SIT set: EU-wide bundles.
./deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' `
    -WhatIf

# 3. Deploy in simulation mode (default) - then send/receive test mail while it runs
./deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com'

# 3b. Or, localized to specific member states instead of the full EU-wide bundle:
./deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -SensitiveInfoTypeName 'Germany Identity Card Number','France Social Security Number','EU debit card number'

# 3c. Or, add the opt-in passport/driver's-license bundle on top of whichever set above is in
# effect - read the U.S./U.K. passport-merge gotcha in the known limitations before enabling for a
# U.K.-only organization:
./deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -IncludeTravelDocumentSits

# 4. After a review window with real test traffic, enforce
./deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedMailboxSmtpAddress 'legalhold@contoso.com' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-EuPersonalDataAutoLabelExchangePolicy.ps1 -LabelName 'Confidential'
```

The deploy script uses Security & Compliance PowerShell (`New-AutoSensitivityLabelPolicy`,
`New-AutoSensitivityLabelRule`, `Get-DlpSensitiveInformationType`) - automation surface 2 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), the same surface both sibling scenarios use.

## Configuration reference

| Setting | Rule: `AutoLabel-EuPersonalData-Exchange` |
|---|---|
| `Workload` | `Exchange` |
| Sensitive info types (default) | EU national identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number - `mincount = 1` each, OR-combined |
| `Policy` | `Confidentiality - Auto-Label EU Personal Data in Exchange Email` |

| Policy-level setting | Value |
|---|---|
| `ApplySensitivityLabel` | `<LabelName>` (default `Confidential`) - must reference an existing, published, non-parent label whose scope includes **Emails** |
| `ExchangeLocation` | `All` |
| `ExchangeSenderException` | `<ExcludedMailboxSmtpAddress>` (optional; one or more SMTP addresses) - excludes that mailbox's **outbound** mail only, not mail sent to it (the design notes, inherited from *Auto-Label Confidential PII in Exchange Email*) |
| `OverwriteLabel` | `$true` - overrides a lower-priority auto-applied/default label only, never a manual one |
| `ExternalMailRightsManagementOwner` | Not set (optional; see the known limitations) |
| `Mode` | `TestWithNotifications` (deploy default) → `Enable` after review |

**Localizing the SIT set (`-SensitiveInfoTypeName`):** identical mechanism to the SharePoint/
OneDrive EU sibling's own the configuration reference - passing a narrower per-country list instead of the default bundle
gives tighter false-positive control and a clearer per-jurisdiction legal-basis mapping:

| Scenario | `-SensitiveInfoTypeName` example |
|---|---|
| Full EU/UK coverage (default) | `'EU national identification number','EU Social Security Number (SSN) or Equivalent ID','EU debit card number'` |
| Germany + France only | `'Germany Identity Card Number','France Social Security Number','EU debit card number'` |
| Add passport numbers too | append `'EU passport number'` (also a real, confirmed EU-wide bundle SIT - the design notes sibling reference) |

**Opt-in travel-document bundle (`-IncludeTravelDocumentSits`):** additive switch - appends `'EU
passport number'` and `"EU driver's license number"` (also real, confirmed EU-wide bundle SITs -
the design notes) to whichever `-SensitiveInfoTypeName` set is already in effect (default or
localized), instead of requiring the full list to be retyped by hand. Ported from the
SharePoint/OneDrive EU sibling's own switch of the same name, for parity across both locations. Use
for an organization whose email traffic is travel-document- or HR-record-heavy. **Before enabling for a
U.K.-only organization:** the "EU passport number" bundle has no standalone U.K. entity - U.K. passport
coverage is merged into a single combined "U.S./U.K. passport number" entity, so this switch also
enables U.S. passport-number detection as an inseparable side effect. The two
opt-in bundles' member-state coverage also isn't identical to each other or to the default
national-ID bundle - see the SharePoint/OneDrive sibling's the design notes for the full per-bundle
membership table (not re-tabled here, per the design notes).

The deploy script resolves every name against `Get-DlpSensitiveInformationType` before creating or
updating the rule, and fails with a list of close matches if a name doesn't resolve exactly - see
the known limitations and the design notes for why this validation exists.

Full cmdlet parameter grounding: `deploy/New-EuPersonalDataAutoLabelExchangePolicy.ps1` inline
comments and its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence**: Off → simulation mode (with test traffic sent/received during the window,
the implementation steps and the validation steps) → review for at least a business cycle (7+ days) → Enable. Same deliberate-enable standard
as both sibling scenarios and this library's standards - do not accept the portal's "auto-turn-on after 7
days" option.

**KPIs to watch (first 30-60 days):**
- **Activity Explorer "Sensitivity label applied" volume for Exchange**, filtered to this label and
  a How-applied value of automatic. Aggregates every auto-labeling policy applying this label, not
  just this one, if more than one exists - same caveat as *Auto-Label Confidential PII in Exchange Email*
  page section 8.
- **Items-to-review match volume during any future re-simulation** (e.g., after a rule change) -
  only reflects traffic sent during that specific window, so a "zero matches" result after a rule
  change needs fresh test traffic before it can be trusted.
- **Per-country match distribution**, inherited from the SharePoint/OneDrive EU sibling's own operations and tuning -
  Activity Explorer's contextual summary can show which specific country's pattern matched a given
  message. A tenant that only ever sees matches from 2-3 countries is a signal to consider
  narrowing to a per-country `-SensitiveInfoTypeName` list rather than running the full
  26-country bundle indefinitely.
- **False-positive rate** - the EU national ID bundle's checksum coverage varies by country: 19 of
  26 members are checksum-validated, 7 are pattern-only (Austria, Croatia, Cyprus, France, Greece,
  Malta, U.K. - full table in the SharePoint/OneDrive sibling's the design notes, cited from this
  scenario's own section 11); watch for user-reported "why was my email suddenly Confidential/encrypted"
  tickets, since there is no per-item failure dashboard for email the way there is for files.

**Alert routing:** no DLP-style incident-report email from auto-labeling itself. For Exchange
specifically, also budget for the **encryption side-effect**: an internal sender whose message
matches this rule will see their message encrypted whether or not the encryption was the intended
outcome - an unexpected support ticket ("why is my recipient unable to forward
this email") is a plausible early signal worth routing to the Information Protection team's queue.

**Review cadence:** monthly for the first quarter alongside both sibling scenarios' own review
cadence (same underlying label, same team, same false-positive tuning conversation), quarterly
thereafter. Re-run `validate/Test-EuPersonalDataAutoLabelExchangePolicy.ps1` each time to catch
configuration drift, **including drift in the configured `-SensitiveInfoTypeName` list itself** if
it was ever narrowed or widened after initial deployment - and, if *Auto-Label EU/UK Personal Data in SharePoint & OneDrive* is also deployed, confirm its own `-SensitiveInfoTypeName` list still matches this
scenario's (the known limitations: nothing ties the two scripts' parameters together automatically).

**Related auto-labeling policies in this tenant (disambiguation for incident response):** if a
tenant has deployed more than one of this library's Information Protection auto-labeling
scenarios, their policy names are similar by design (same naming convention) but target different
locations and/or SIT sets. Confirm the exact policy name before disabling one during an incident:

| Policy name | Location | SIT set |
|---|---|---|
| `Confidentiality - Auto-Label EU Personal Data in Exchange Email` | Exchange | EU/UK (this scenario) |
| `Confidentiality - Auto-Label PII in Exchange Email` | Exchange | U.S. (*Auto-Label Confidential PII in Exchange Email*) |
| `Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive` | SharePoint/OneDrive | EU/UK (*Auto-Label EU/UK Personal Data in SharePoint & OneDrive*) |
| `Confidentiality - Auto-Label PII in SharePoint and OneDrive` | SharePoint/OneDrive | U.S. (*Auto-Label Confidential PII in SharePoint & OneDrive*) |

**Runbook - an email that should be labeled isn't:**
1. Confirm the message wasn't sent/received outside a simulation window if you're still validating
   in simulation - this is expected, not a bug.
2. Confirm the sender isn't the excluded mailbox - outbound mail from that mailbox is
   never evaluated, by design.
3. Confirm at least 60-90 minutes have passed before checking Activity Explorer.
4. If a localized `-SensitiveInfoTypeName` list is in use, confirm the test message's country
   format is actually in the configured list (not the full default bundle) before treating it as a
   policy failure - same EU-specific addition the SharePoint/OneDrive sibling's own runbook makes.
5. Confirm the label's scope still includes **Emails** - an edit to the label (e.g., by someone
   working on either file-scoped sibling scenario's use case) that narrows scope back to "Files &
   other data assets only" would silently stop this policy from having any effect, with no portal
   error surfaced.
6. If none of the above explains it, check for a **rule-load failure** - a malformed rule can
   silently stop matching all Exchange traffic with no item-level failure to review, because the
   rule never loaded in the first place. Re-run the automated config check; if
   it reports the rule missing or malformed, recreate it from this scenario's deploy script.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-EuPersonalDataAutoLabelExchangePolicy.ps1` disables (reversible); add
`-Purge` to permanently delete the policy and its rule.

## References

1. Automatically apply a sensitivity label to Microsoft 365 data - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically>
2. Automatically apply a sensitivity label to Microsoft 365 data - "Auto-labeling for Exchange" behavior (attachment scanning vs. labeling, Message Encryption inheritance, external-sender labeling and encryption defaults) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#compare-auto-labeling-for-office-apps-with-auto-labeling-policies>
3. Automatically apply a sensitivity label to Microsoft 365 data - "How to configure auto-labeling policies for SharePoint, OneDrive, and Exchange" (mass-mailing caution, ExchangeLocation All/None-excluded requirement for external senders) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#how-to-configure-auto-labeling-policies-for-sharepoint,-onedrive,-and-exchange>
4. Data Loss Prevention policy reference - "Content contains" supports multiple sensitive info types combined with "Any of these" (OR) or "All of these" (AND) - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
5. Automatically apply a sensitivity label to Microsoft 365 data - "Will an existing label be overridden?" - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#will-an-existing-label-be-overridden>
6. Automatically apply a sensitivity label to Microsoft 365 data - "Example: Apply a label to Exchange email based on the subject" (live-traffic-only simulation for Exchange, label scope must include Emails) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#example-apply-a-label-to-exchange-email-based-on-the-subject>
7. Use the Insights tab to analyze auto-labeling policies in Microsoft Purview - Exchange email excluded from Labeled items/enforcement metrics; Activity Explorer as the documented alternative, 60-90 minute delay, doesn't identify the specific policy/rule - <https://learn.microsoft.com/purview/auto-label-insights-tab>
8. Use the Insights tab to analyze auto-labeling policies in Microsoft Purview - simulation-mode Insights, Exchange matched-item counts are estimates from sampled data; pre-flight checklist role requirements for turning on a policy (Compliance Administrator / Compliance Data Administrator) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin>
9. New-AutoSensitivityLabelPolicy reference (full parameter syntax - confirms no `-ExchangeLocationException` parameter exists; `-ExchangeSender`/`-ExchangeSenderException`/`-ExchangeSenderMemberOf`/`-ExchangeSenderMemberOfException`/`-ExternalMailRightsManagementOwner`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy>
10. EU national identification number entity definition (member list includes U.K. National Insurance Number) - <https://learn.microsoft.com/purview/sit-defn-eu-national-identification-number>
11. EU Social Security Number (SSN) or Equivalent ID entity definition - <https://learn.microsoft.com/purview/sit-defn-eu-social-security-number-equivalent-identification>
12. EU debit card number entity definition - <https://learn.microsoft.com/purview/sit-defn-eu-debit-card-number>
13. Get-DlpSensitiveInformationType reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpsensitiveinformationtype>
14. New-AutoSensitivityLabelRule reference (`-Workload` accepted values: Exchange, SharePoint, OneDriveForBusiness) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule>
15. Create custom sensitive information types - "These SITs can't be copied" list (names the EU-wide bundle SITs individually, confirming each is a real, selectable SIT object) - <https://learn.microsoft.com/purview/sit-create-a-custom-sensitive-information-type#before-you-begin>
16. Get-Label reference - <https://learn.microsoft.com/powershell/module/exchange/get-label>
17. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
18. Automatically apply a sensitivity label to Microsoft 365 data - "Policy rule fails to load" troubleshooting (rule-load failure has no item-level symptom) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#policy-rule-fails-to-load>

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - auto-labeling behavior for Exchange (simulation semantics, Insights tab detail) and the
> SIT catalog have both changed more than once in this feature's history, same caveat as both
> sibling scenarios.