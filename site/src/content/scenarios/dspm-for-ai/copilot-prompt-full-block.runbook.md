---
part: "runbook"
parent: "dspm-for-ai/copilot-prompt-full-block"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the "Block sensitive information types in prompts" feature has rolled out to your tenant
   (Microsoft's own guidance: "check whether rollout has reached your tenant" - no fixed portal flag
   is documented for this; if the third action below isn't selectable, it hasn't arrived yet).
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
   prevention** → **Policies** → open **Copilot DLP - Sensitive Data Exposure Protection** (the
   parent scenario's policy) → **Edit rules** → **Create rule**.
3. Name: `Copilot-Block-SensitivePrompts-FullResponse`. Priority: after the existing two rules
   (portal typically appends new rules last; confirm and reorder if needed so Rule 0/Rule 1 still
   evaluate first).
4. Condition: **Content contains** → **Sensitive information types** → select your highest-severity
   SIT set (defaults to **Canada physical addresses**, **EU debit card numbers** in this scenario's
   script - Microsoft's own worked example pair; replace with your own).
5. Action: **Restrict Copilot from processing content** → **Processing prompts**.
   (Microsoft's own documentation uses both "Restrict Copilot from processing content" in its
   use-case narrative and "Prevent Copilot from processing content" in its supported-actions table
   for this same action - an inconsistency in Microsoft's own wording, not a typo
   in this scenario; both refer to the identical "Processing prompts" sub-action.)
6. Leave the policy's overall **Mode** as-is (this scenario does not change the parent policy's
   mode) - a new rule added to a policy already in `Enable` mode enforces immediately once portal/
   PowerShell sync completes (up to 4 hours); add the rule while the **parent policy** is still in
   `TestWithNotifications` if you want to observe this new rule's own match volume in simulation
   first.
7. **Save**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports the change, makes none
./deploy/Add-CopilotPromptFullBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Add the rule (parent policy's own Mode governs enforcement - see §8)
./deploy/Add-CopilotPromptFullBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. Validate
./validate/Test-CopilotPromptFullBlockRule.ps1
```

The deploy script uses `New-DlpComplianceRule` with a standard `-ContentContainsSensitiveInformation`
condition (the same, confirmed parameter the parent scenario's Rule 1 uses) and
`-RestrictAccess @(@{setting='ExcludeContentProcessing'; value='Block'})` as the action.

**VERIFY - read before relying on this script in production.** Microsoft's own `New-DlpComplianceRule`
/ `New-DlpCompliancePolicy` reference publishes a worked example combining the `ExcludeContentProcessing`/
`Block` `-RestrictAccess` pair with a sensitivity-**label** condition (`-AdvancedRule`, the parent
scenario's Rule 0) and a separate worked example combining a **CCSI** condition with
`-RestrictWebGrounding $true` (the parent scenario's Rule 1). As of this build, Microsoft has **not**
published a worked example combining a CCSI condition with the `-RestrictAccess`
`ExcludeContentProcessing`/`Block` pair specifically for the "Processing prompts" full-block action -
the exact literal `setting` value for this third action is not independently confirmed. This script's
choice is a documented, reasoned inference, not a fabricated parameter - the
`-RestrictAccess` parameter itself, its hashtable shape, and the `ExcludeContentProcessing`/`Block`
value pair are all individually confirmed in Microsoft's reference; what's unconfirmed is that the
same value pair is what the portal emits when this specific condition/action combination is chosen.
**Before enforcing in production:** create the rule once through the portal (step 5 above), then run
`Get-DlpComplianceRule -Identity 'Copilot-Block-SensitivePrompts-FullResponse' | Format-List RestrictAccess`
and compare against this script's output - `validate/Test-CopilotPromptFullBlockRule.ps1` automates
this comparison as a `[WARN]`-level (not `[FAIL]`-level) check for exactly this reason.

## Configuration reference

| Setting | Rule 2: `Copilot-Block-SensitivePrompts-FullResponse` |
|---|---|
| Priority | 2 (evaluated after the parent scenario's Rule 0 = 0, Rule 1 = 1) |
| Policy | `Copilot DLP - Sensitive Data Exposure Protection` (parent scenario's policy - parameterizable via `-PolicyName`) |
| Condition | `ContentContainsSensitiveInformation` = configurable SIT list, default **Canada physical addresses**, **EU debit card numbers** (Microsoft's own worked-example pair) |
| Action | `RestrictAccess` = `@{setting='ExcludeContentProcessing'; value='Block'}` - **VERIFY**, see section 5 |
| What it stops | Copilot from responding to the prompt at all - not used for internal or web grounding |
| What it does **not** stop | A user rephrasing the sensitive data so it no longer matches the configured SIT pattern; a user uploading the data as a file attachment instead of typing it (DLP does not scan uploaded file content - same documented limitation as the parent scenario's Rule 1, *Copilot Sensitive Data Exposure Protection* (the known limitations)) |
| `GenerateAlert` / `GenerateIncidentReport` | Admin/SOC mailbox |
| `ReportSeverityLevel` | High (a full-response block is the most severe of the three rules) |
| `Disabled` | `$false` by default; the rollback script sets this to `$true` for a reversible pause |

Full cmdlet parameter grounding: `deploy/Add-CopilotPromptFullBlockRule.ps1` inline comments and its
`.NOTES` block.

## Operations and tuning

**Deployment sequence:** this rule inherits the parent **policy's** `Mode` - it has no independent
mode of its own. If the parent policy is already in `Enable` (full enforcement) when this rule is
added, the new rule enforces as soon as it propagates (up to 4 hours) - there is no simulation-only
window for just this one rule. **Recommendation:** add this rule while the parent policy is still in
`TestWithNotifications`, observe its match volume for a tuning window, and only then move the whole
policy to `Enable` - or accept that adding this rule to an already-`Enable` policy means it starts
blocking without its own simulation period. Document which path was taken in the change record.

**KPIs to watch (first 30 days):**
- **Rule 2 match count and false-positive rate.** This is the most user-visible of the three rules in
  this policy (the user is told their request was blocked) - a high false-positive rate translates
  directly into help-desk tickets and productivity complaints, not just a silent DLP log entry. Watch
  this more closely than the parent scenario's Rule 1.
- **Rule 2 vs. Rule 1 overlap.** If a prompt matches both rules' SIT sets, Rule 2's full block makes
  Rule 1's web-grounding restriction moot for that prompt - not a conflict, but confirm your SIT
  taxonomy is deliberate rather than accidentally duplicated across rules.
- **Help-desk ticket volume citing "Copilot won't respond."** A leading indicator that either the SIT
  set is too broad (over-blocking legitimate prompts, e.g. an address format that also matches
  ordinary business correspondence) or that user education about the new control hasn't kept pace
  with deployment.

**Review cadence:** monthly during the first quarter after deployment (given the preview status and
higher user-visible friction than the parent scenario's other two rules), dropping to quarterly once
the false-positive rate stabilizes and the feature reaches GA.

**Incident-response runbook (Rule 2 alert):**
1. **Triage** - open the alert; confirm which SIT matched and the submitting user.
2. **Classify** - a single match from a user who has not triggered this rule before is very likely
   legitimate (probing the boundary, or a one-off need to discuss the flagged data type) rather than
   malicious; a pattern of repeated matches from the same user, especially rephrased attempts shortly
   after a block, is a stronger signal warranting Insider Risk Management
   or manager involvement.
3. **Document** - retain alert records as evidence of an actively enforced, user-facing control.
4. **Do not tune by widening exceptions without review** - because this rule fully blocks a response
   (not just a web search), an ad hoc exception added under user pressure has a materially larger
   blast radius than loosening the parent scenario's Rule 1. Route exception requests through the
   same change-control process used for the parent policy, not a one-off rule edit.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-CopilotPromptFullBlockRule.ps1` disables just this rule (`Set-DlpComplianceRule
-Disabled $true`, reversible, leaves Rule 0/Rule 1 and the parent policy untouched); add `-Purge` to
permanently delete this rule only (`Remove-DlpComplianceRule`), also leaving the rest of the parent
policy intact.

## References

1. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
   365 Copilot and Copilot Chat - "Block sensitive information types in prompts" section (preview
   status, rollout note, use-case example, supported conditions/actions table, files-uploaded-in-prompts limitation) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-sensitive-information-types-in-prompts>
2. Same page - Supported conditions and actions table (three distinct Copilot-location actions:
   label exclusion, prompt full-block, web-grounding restriction) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#supported-conditions-and-actions>
3. New-DlpComplianceRule reference - `-RestrictAccess`, `-ContentContainsSensitiveInformation`
   parameters and syntax (confirms parameter existence and shape; does not publish a worked example
   for this specific condition/action combination - see the implementation steps VERIFY) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
4. New-DlpCompliancePolicy reference - Example 4 (the `ExcludeContentProcessing`/`Block`
   `-RestrictAccess` pair, worked for a label condition, reused by the parent scenario's Rule 0) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
5. Set-DlpComplianceRule reference (`-Disabled` parameter, used by this scenario's rollback path) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
6. Remove-DlpComplianceRule reference (rule-level deletion, used by this scenario's `-Purge` path) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
7. *Copilot Sensitive Data Exposure Protection* - the parent scenario this fragment
   extends; shared prerequisites, architecture, and policy object.

> Re-verify the preview/GA status of this specific action and the `-RestrictAccess` setting-value
> VERIFY in the implementation steps against current Microsoft Learn before a customer-facing deployment - this is the
> newest and least-mature of the three Copilot-location DLP actions this library documents.