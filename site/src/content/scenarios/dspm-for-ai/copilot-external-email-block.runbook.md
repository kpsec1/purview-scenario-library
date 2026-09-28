---
part: "runbook"
parent: "dspm-for-ai/copilot-external-email-block"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the "Block external email from being processed" action is selectable in your tenant's
   Purview portal - Microsoft documents no fixed rollout date for this preview feature; if the
   condition below isn't available, it hasn't arrived yet.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
   prevention** → **Policies** → open **Copilot DLP - Sensitive Data Exposure Protection** (the
   parent scenario's policy) → **Edit rules** → **Create rule**.
3. Name: `Copilot-Exclude-ExternalEmail-Processing`. Priority: after the existing three rules
   (portal typically appends new rules last; confirm and reorder if needed so Rules 0-2 still
   evaluate first).
4. Condition: **Email is received from** → **External users**.
5. Action: **Prevent Copilot from processing content** - this
   action has no further sub-action to select, unlike Rule 1/Rule 2's SIT-conditioned rules.
6. Leave the policy's overall **Mode** as-is (this scenario does not change the parent policy's
   mode) - see operations and tuning for the operational implication of adding a rule to an already-`Enable` policy.
7. **Save**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports the change, makes none
./deploy/Add-CopilotExternalEmailBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Add the rule (parent policy's own Mode governs enforcement - see §8)
./deploy/Add-CopilotExternalEmailBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. Validate
./validate/Test-CopilotExternalEmailBlockRule.ps1
```

The deploy script uses `New-DlpComplianceRule` with `-FromScope NotInOrganization` as the condition
and `-RestrictAccess @(@{setting='ExcludeContentProcessing'; value='Block'})` as the action.

**VERIFY - read before relying on this script in production.** Microsoft's `New-DlpComplianceRule`
reference confirms `-FromScope` exists as a parameter (type
`Microsoft.Office.CompliancePolicy.PolicyEvaluation.FromScope`) and confirms its two allowed values
(`InOrganization`, `NotInOrganization`) via a separate reference page - but no Microsoft-published
worked example combines `-FromScope` with the Microsoft 365 Copilot and Copilot Chat location
(`CopilotExperiences` enforcement plane) specifically. This scenario's choice is a documented,
reasoned inference from independently-converging sources, not a fabricated
parameter - the parameter itself, its type, and its two allowed literal values are all individually
confirmed to exist; what's unconfirmed is that this specific location honors it as a condition.
`-RestrictAccess`'s `ExcludeContentProcessing`/`Block` pair is, by contrast, the **one** combination
Microsoft's own `New-DlpCompliancePolicy` reference publishes a full worked example for on this
location (paired there with a label condition, the design notes) - the strongest-grounded action this
repo has used for any Copilot-location rule. **Before enforcing in production:** create the rule once
through the portal (step 5 above), then run
`Get-DlpComplianceRule -Identity 'Copilot-Exclude-ExternalEmail-Processing' | Format-List FromScope, RestrictAccess`
and compare against this script's output - `validate/Test-CopilotExternalEmailBlockRule.ps1`
automates this comparison as a `[WARN]`-level (not `[FAIL]`-level) check for exactly this reason.

## Configuration reference

| Setting | Rule 3: `Copilot-Exclude-ExternalEmail-Processing` |
|---|---|
| Priority | 3 (evaluated after Rules 0-2 from the parent and *Copilot Prompt Full-Response Block* scenarios) |
| Policy | `Copilot DLP - Sensitive Data Exposure Protection` (parent scenario's policy - parameterizable via `-PolicyName`) |
| Condition | `FromScope = NotInOrganization` - **VERIFY**, see section 5 |
| Action | `RestrictAccess = @{setting='ExcludeContentProcessing'; value='Block'}` - same confirmed pair as Rule 0, see the design notes |
| What it stops | An externally-sent email from being used by Copilot for grounding, summarization, or citation - sender-domain metadata only, the email body is never inspected |
| What it does **not** stop | Sensitive content *within* an internal email (Rules 0-2's job, not this rule's); a prompt-injection payload delivered through an internal-domain account that has been compromised (this rule only evaluates sender domain, not sender trustworthiness within the domain); external content reaching Copilot through a channel other than email (e.g. an external SharePoint guest share, or a Rule-1-uncovered web search) - see the design notes |
| `GenerateAlert` / `GenerateIncidentReport` | Admin/SOC mailbox |
| `ReportSeverityLevel` | `Low` by default (configurable via `-ReportSeverityLevel`) - see the design notes for why this rule's default severity is deliberately lower than its three siblings |
| `Disabled` | `$false` by default; the rollback script sets this to `$true` for a reversible pause |

Full cmdlet parameter grounding: `deploy/Add-CopilotExternalEmailBlockRule.ps1` inline comments and
its `.NOTES` block.

## Operations and tuning

**Deployment sequence:** this rule inherits the parent **policy's** `Mode`, same as every rule in
this family - no independent simulation window of its own. If the parent policy is already in
`Enable` mode when this rule is added, it enforces as soon as it propagates (up to 4 hours).

**KPIs to watch (first 30 days):**
- **Rule 3 match volume, as a baseline, not an incident feed.** Because every external email a user
  receives is a potential match candidate, expect materially higher match volume than Rules 0-2 -
  this is expected behavior, not a sign of tuning trouble. Watch the *trend*, not the raw count.
- **Accepted-domains hygiene.** A legitimate partner or subsidiary domain missing from the tenant's
  Exchange accepted-domains list will show up here as unexpected external-email exclusions -
  cross-check any user complaint that "Copilot won't summarize an email from [legitimate partner]"
  against the accepted-domains list before assuming this rule is misbehaving.
- **Correlation with Rule 1/Rule 2 matches.** A pattern of prompts triggering Rule 1/Rule 2 shortly
  after a Rule 3 exclusion event on the same user's mailbox may indicate a user attempting to work
  around the external-email exclusion by re-typing or re-pasting the excluded content directly into a
  prompt - treat as a tuning signal, not automatically as malicious (most such attempts are
  legitimate users trying to get their work done, not evasion).

**Review cadence:** monthly during the first quarter after deployment (given the preview status and
the FromScope-on-Copilot-location VERIFY carried in the implementation steps), dropping to quarterly once the feature
reaches GA and the VERIFY is closed.

**Incident-response runbook (Rule 3 alert):**
1. **Triage** - this is, by design, a lower-severity signal than Rules 0-2.
   Most alerts require no action; use the alert primarily to confirm the control is active and
   matching, not as a per-event investigation queue.
2. **Escalate only on a pattern** - a specific external domain generating a sustained, unusual volume
   of matches against a specific user or small group of users may warrant a closer look (e.g., a
   phishing campaign using a spoofed-looking external domain attempting to reach users' inboxes with
   content crafted to look like legitimate business correspondence) - route to the mail-flow/anti-phish
   team, not this scenario's own operators, since this rule has no visibility into email content.
3. **Document** - retain alert records to support the "Copilot only grounds on trusted internal data"
   narrative for an AI-governance review.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-CopilotExternalEmailBlockRule.ps1` disables just this rule (`Set-DlpComplianceRule
-Disabled $true`, reversible, leaves Rules 0-2 and the parent policy untouched); add `-Purge` to
permanently delete this rule only (`Remove-DlpComplianceRule`), also leaving the rest of the parent
policy intact.

## References

1. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
   365 Copilot and Copilot Chat - "Block external email from being processed (preview)" section
   (preview status, use-case example, metadata-only behavior, user-facing message) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-external-email-from-being-processed-preview>
2. Same page - Supported conditions and actions table (fourth Copilot-location row: **Email is
   received from > External users** condition, **Prevent Copilot from processing content** action,
   no sub-action) - <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#supported-conditions-and-actions>
3. New-DlpComplianceRule reference - full parameter syntax confirming `-FromScope` (type
   `Microsoft.Office.CompliancePolicy.PolicyEvaluation.FromScope`) and `-RestrictAccess` both exist
   as parameters of this cmdlet (does not publish a worked example for this specific
   condition/action/location combination - see the design notes VERIFY) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
4. Data loss prevention Exchange conditions and actions reference - confirms the portal condition
   "Sender scope" maps to the PowerShell condition `FromScope`/`ExceptIfFromScope`, property type
   `UserScopeFrom` - <https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions>
5. New-DlpCompliancePolicy reference, Example 4 (the `ExcludeContentProcessing`/`Block`
   `-RestrictAccess` pair, worked for a label condition on the Microsoft 365 Copilot location, reused
   by the parent scenario's Rule 0 and by this rule's action) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
6. Microsoft Purview service description - Data Loss Prevention (DLP) for Microsoft Copilot licensing
   table (the "files and emails" vs. "prompts" tier split referenced in the prerequisites and the cost and licensing notes) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-dlp-for-microsoft-copilot>
7. Set-DlpComplianceRule reference (`-Disabled` parameter, used by this scenario's rollback path) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
8. Remove-DlpComplianceRule reference (rule-level deletion, used by this scenario's `-Purge` path) - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
9. *Copilot Sensitive Data Exposure Protection* - the parent scenario this fragment
   extends; shared prerequisites, architecture, and policy object.
10. *Copilot Prompt Full-Response Block* - the sibling scenario establishing the
    "extends the shared policy" pattern this fragment follows.

> Re-verify the preview/GA status of this specific action and the `-FromScope`-on-Copilot-location
> VERIFY in the implementation steps against current Microsoft Learn before a customer-facing deployment - this is the
> newest and least-mature of the four Copilot-location DLP actions this library documents, and the only
> one whose condition type has no Microsoft-published worked example on this location at all.