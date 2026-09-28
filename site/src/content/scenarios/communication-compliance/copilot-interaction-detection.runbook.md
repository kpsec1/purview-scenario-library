---
part: "runbook"
parent: "communication-compliance/copilot-interaction-detection"
---
## Implementation steps

### Portal path - creating the policy (there is no script path for this part; see why this matters/the design notes)

1. Before starting, review `deploy/policy/copilot-interaction-policy-manifest.json` - the
   recommended policy name, scope, and reviewers. **Policy names cannot be changed after creation**
   - confirm before proceeding.
2. Confirm audit logging is on and permissions are assigned: at minimum, one person in
   **Communication Compliance Admins** (or **Communication Compliance**) to create the policy, and
   named Security/Responsible-AI/Legal stakeholders assigned to **Communication Compliance
   Investigators**.
3. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Communication
   Compliance** → **Policies** → **Create policy** → select the **Detect Microsoft 365 Copilot and
   Microsoft 365 Copilot Chat interactions** template.
4. **Name and describe your policy**: `Microsoft 365 Copilot Interaction Detection - All Users`
   (from the manifest) → **Next**.
5. **Choose users and reviewers**:
   - Users in scope: **All users** (this scenario's default - matches this policy template's
     intent of reviewing all Copilot usage; narrow to **Select users** or an **adaptive scope**
     only for a deliberate, documented pilot, same rationale as operations and tuning below).
   - Reviewers: add the named Security/Responsible-AI/Legal stakeholders from the manifest's
     `reviewers.placeholderMembers` (replaced with real accounts). Each reviewer receives an
     automatic email notifying them of the assignment → **Next**.
6. **Review the settings chosen for you by the template**: Location = **Microsoft 365 Copilot and
   Microsoft 365 Copilot Chat**; Direction = Inbound, Outbound, Internal; Review Percentage = 100%;
   Conditions = **Prompt Shields**, **Protected material** classifiers. Do not
   change these unless the tenant has a specific, documented reason - they are exactly this
   scenario's target configuration.
7. Select **Create policy** to accept the template as-is, or **Customize policy** only if a
   documented deviation is needed (e.g. narrowing scope for a pilot, operations and tuning).
8. **Review and finish** → **Create policy**. Allow up to ~1 hour for Copilot prompt/response body
   content before the policy begins detecting.
9. **Enable username anonymization** (if not already on tenant-wide from another Communication
   Compliance policy). **Settings** (top-right) → **Communication Compliance** → **Privacy** tab →
   check **Show anonymized versions of usernames** → **Save**. This is a
   tenant-wide setting, not per-policy - skip if *Workplace Harassment & Code of Conduct* (or any other
   Communication Compliance policy in this tenant) already enabled it.

### Script path - the audit-trail export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3). The connecting identity
#    needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (docs/rbac-model.md §6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - queries the last 7 days across all 3 categories, reports what would be merged, writes nothing
./deploy/Export-CopilotInteractionAuditTrail.ps1 -OutputCsvPath './out/copilot-interaction-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the full default retention window
./deploy/Export-CopilotInteractionAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/copilot-interaction-audit-trail.csv'

# 4. Recurring run (schedule daily or weekly - overlapping windows are safe, see design.md §7)
./deploy/Export-CopilotInteractionAuditTrail.ps1 -OutputCsvPath './out/copilot-interaction-audit-trail.csv'

# 5. Validate
./validate/Test-CopilotInteractionAuditTrail.ps1 -AuditTrailCsvPath './out/copilot-interaction-audit-trail.csv'
```

The audit-trail script uses Exchange Online PowerShell's `Search-UnifiedAuditLog` - automation
surface 1 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), because Communication Compliance has no surface of
its own for anything, including its own audit footprint.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy type | Template (**Detect Microsoft 365 Copilot and Microsoft 365 Copilot Chat interactions**), unmodified | The template's fixed defaults already match this scenario's target - the design notes |
| Locations | Microsoft 365 Copilot and Microsoft 365 Copilot Chat only | No PAYG requirement, unlike Enterprise/Other AI apps locations - the prerequisites and operations and tuning |
| Direction | Inbound, Outbound, Internal | Full coverage - template default |
| Users in scope | All users (this scenario's default) | Narrow only for a documented pilot - operations and tuning |
| Conditions | Prompt Shields (prompts only), Protected material (responses only) | the design notes for exactly what each does and does not cover |
| Review percentage | 100% | Template default; a documented, revisitable lever if alert volume becomes unmanageable - operations and tuning |
| Reviewer role | Communication Compliance Investigators | Full content access - the design notes |
| Reviewer pool (this scenario's default) | Security / Responsible-AI / Legal stakeholders | Different natural pool than *Workplace Harassment & Code of Conduct*'s HR/Legal - the design notes |
| Username anonymization | On (tenant-wide setting) | Settings > Communication Compliance > Privacy - shared with any other Communication Compliance policy in the tenant |
| Audit-trail script query categories | `PolicyMatch` (`SupervisionRuleMatch`), `PolicyUpdate` (`RecordType Discovery` + 3 operations), `ReviewTag` (`RecordType AeD` + `SupervisoryReviewTag`) | Identical grounded shape to *Workplace Harassment & Code of Conduct* - the design notes |
| Audit-trail script policy-name filter | `-PolicyNameFilter 'Microsoft 365 Copilot Interaction Detection - All Users'` (default) | Client-side filter on the parsed `AuditData` JSON so this scenario's CSV doesn't merge in unrelated policies' events if both scenarios are deployed in the same tenant - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Same rolling-history pattern as *Workplace Harassment & Code of Conduct*'s and *Assess Against ISO/IEC 27001:2022*'s audit-trail scripts |

Full cmdlet parameter grounding: `deploy/Export-CopilotInteractionAuditTrail.ps1`'s inline comments
and its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Prompt Shields match volume** - an unexpectedly high volume in a specific team or business unit
  is worth investigating: it may indicate deliberate jailbreak experimentation, a compromised
  account, or (benignly) a security-research/red-team activity that should be documented as an
  authorized exception rather than repeatedly triaged as a fresh incident.
- **Protected material match volume** - recurring matches from the same user(s) may indicate a
  workflow that habitually asks Copilot to reproduce third-party content (e.g. drafting marketing
  copy from song lyrics) that needs a non-technical process fix, not just repeated alert dismissal.
- **Review-tag volume and reviewer turnaround time** (`ReviewTag` category in the audit-trail CSV)
  - a growing backlog undermines the "active oversight" narrative this control exists to support
 as much as not detecting the interaction at all.
- **`PolicyUpdate` event volume/content** - the audit-trail script's inline `Write-Warning` fires on
  every detected policy change; review each against what was actually intended.
- **Storage-limit indicator** - each policy has a hard **100 GB or 1,000,000-message** limit;
  reaching it **auto-deactivates the policy with no in-band alert to anyone outside the
  Communication Compliance/Communication Compliance Admins role groups**. Same
  documented silent-failure mode *Workplace Harassment & Code of Conduct* (operations and tuning) already flags -
  monitor actively.

**No built-in severity ranking for these two classifiers.** Unlike the LLM-based content-safety
classifiers (Hate/Sexual/Violence/Self-harm), which populate a **Severity** column on the Alerts
dashboard for triage prioritization, Prompt Shields and Protected material matches carry no
documented severity score - every alert this policy generates needs to be triaged
on its own merits; there is no "review the high-severity ones first" shortcut available here.

**Lower the default alert-aggregation threshold for this policy.** Communication Compliance's
system-generated alert policy defaults to a **4-activity threshold within a 60-minute window**
before an alert fires (minimum configurable value: 3; a single email notification then covers every
match in that window). That default is tuned for a general content-monitoring
policy, not for a security-sensitive Prompt Shields match - waiting for a fourth jailbreak attempt
in an hour before the first alert fires is the wrong trade-off here. On the **Alert policies** page
in Microsoft Purview, lower this policy's alert-policy threshold to its documented **minimum of 3**
activities (3 is the floor; a true single-event alert is not configurable) so a jailbreak attempt is
surfaced as close to real time as this policy's ~1 hour detection latency allows, rather than
silently accumulating toward the default threshold.

**Establish a defined response SLA before go-live - a documented-but-ignored alert is worse than no
alert.** Once this policy is active, every Prompt Shields/Protected material match becomes a
timestamped, discoverable record that the organization was aware of a specific risky interaction.
An organization that deploys this control but has no committed process for actually triaging those
alerts creates a "known but not acted on" record that is a worse position, from a legal-discovery
and audit-committee perspective, than not having deployed the detection at all. Confirm the
Security/Responsible-AI/Legal reviewer pool has a committed triage SLA (e.g., same-business-day
review of Prompt Shields matches) before enabling this policy tenant-wide, not after the first
alert arrives.

**Consider a phased pilot before "All users."** As with *Workplace Harassment & Code of Conduct* (operations and tuning)'s identical recommendation, a tenant deploying this for the first time with no existing baseline
for Prompt Shields/Protected material match volume should weigh a 2-4 week pilot scoped to
**Select users** (the earliest Copilot pilot cohort, which for most tenants already exists as a
distinct group) before expanding to **All users**. Record this as a deliberate, time-boxed exception
in `deploy/policy/copilot-interaction-policy-manifest.json` if taken.

**Alternative/complementary path: add Copilot as a location to an existing policy instead.** If the
tenant already runs *Workplace Harassment & Code of Conduct* (or any other Communication Compliance policy)
and wants that policy's own classifiers (Threat/Harassment/Discrimination/Profanity) to also apply
to Copilot prompts/responses, Microsoft documents this as a supported edit: open the existing
policy → **Edit** → **Choose locations to detect communications** → enable **Microsoft Copilot
experiences**. This scenario deliberately keeps its own policy separate rather
than only relying on that path, because Prompt Shields/Protected material are only available via
this dedicated template/condition set - see the design notes for why the two policies are not merged.

**Review cadence:** daily triage of new alerts (jailbreak attempts are time-sensitive from a
security-response perspective); weekly review of the **Reports** page trends; monthly review of
match-volume baselines; immediately upon any audit-trail `PolicyUpdate` or storage-limit-approaching
warning.

**Incident-response runbook (alert triage):**
1. **Triage by classifier.** A **Prompt Shields** match is a security-relevant event (potential
   jailbreak/compromise) that should route to the Security function first; a **Protected material**
   match is primarily a Legal/IP-risk event. Both land in the same Investigator queue by default -
   the reviewer pool's internal triage process (not Communication Compliance itself) should route
   accordingly.
2. **Examine the prompt/response details** - sender, direction, and the full flagged text - before
   deciding a remediation action.
3. **Remediate**: **Resolve** (including "misclassified" if the match was a false positive -
   improves future classifier accuracy), **Tag as** Compliant/Noncompliant/Questionable, **Notify**,
   or **Escalate**/**Escalate for investigation**, per Microsoft's documented remediation-action set. Note that **Remove message** (available for Teams chat remediation in
   *Workplace Harassment & Code of Conduct*) has no equivalent for a Copilot interaction - a Copilot response
   already delivered to the user cannot be retracted through this workflow.
4. **For a confirmed jailbreak attempt**, treat it as a security incident per the organization's
   existing incident-response process, not solely a Communication Compliance remediation action -
   consider whether the same user/account shows other risk signals (cross-reference
   *Insider Risk Management* if deployed).
5. **Document** - every remediation action is captured in the unified audit log as a
   `SupervisoryReviewTag` event and merged into this scenario's audit-trail CSV; do not delete rows
   from it.

## Rollback and decommission

See the rollback runbook for the full staged procedure (pause → revoke access → delete, handled
independently from the audit-trail script's own rollback). Quick reference: use **Pause policy** in
the portal for a reversible stop; **Delete** only when permanently retiring the control - Delete
**permanently removes all captured prompts, responses, and alerts**.

## References

1. Configure a Communication Compliance policy to detect generative AI interactions - Responsible AI
   commitment statement, prerequisites, how policy matches appear - <https://learn.microsoft.com/purview/communication-compliance-copilot>
2. Configure a Communication Compliance policy to detect generative AI interactions - PAYG
   requirement scoped to non-Microsoft-365 AI data only - <https://learn.microsoft.com/purview/communication-compliance-copilot#microsoft-copilot-experience>
3. Create and manage Communication Compliance policies - policy template table (Copilot
   interactions row: location, direction, review percentage, conditions) - <https://learn.microsoft.com/purview/communication-compliance-policies#choose-a-policy-template>
4. Trainable classifiers definitions - Prompt Shields and Protected material classifier
   definitions, scope (prompts-only / responses-only), and supported language - <https://learn.microsoft.com/purview/trainable-classifiers-definitions#prompt-shields>
5. Microsoft Copilot prompt defense in depth - Copilot's own built-in runtime protections (block
   list, Responsible AI classifier filtering, protected-materials detection, DLP for prompts,
   hidden-Unicode-instruction blocking) - <https://learn.microsoft.com/microsoft-365/copilot/copilot-prompt-defense-in-depth>
6. Azure AI Content Safety - Prompt Shields concept (jailbreak/prompt-injection attack types,
   subtypes, language/region limitations) - <https://learn.microsoft.com/azure/ai-services/content-safety/concepts/jailbreak-detection>
7. Create and manage Communication Compliance policies - content safety classifiers based on large
   language models (Severity column scoped to Hate/Sexual/Violence/Self-harm only, not Prompt
   Shields/Protected material) - <https://learn.microsoft.com/purview/communication-compliance-policies#content-safety-classifiers-based-on-large-language-models>
8. Create and manage Communication Compliance policies - Integrate with Insider Risk Management,
   generative AI policy indicators (Prompt Shields, Protected material detection feeding IRM risk
   templates) - <https://learn.microsoft.com/purview/communication-compliance-policies#select-generative-ai-policy-indicators-for-policy-templates>
9. Microsoft Purview service description - Communications Compliance (licensing table, PAYG scope
   for non-M365 AI data) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-communications-compliance>
10. Create and manage Communication Compliance policies (policy templates, PowerShell-not-supported
    statement, storage limits, pause/copy, reviewer roles) - <https://learn.microsoft.com/purview/communication-compliance-policies>
11. Create and manage Communication Compliance policies - policy activity detection / time-to-detection
    table (Microsoft 365 Copilot and Microsoft 365 Copilot Chat body content: 1 hour) - <https://learn.microsoft.com/purview/communication-compliance-policies#policy-activity-detection>
12. Use Communication Compliance reports and audits - Sensitive information type per location report,
    including the Microsoft 365 Copilot and Microsoft 365 Copilot Chat column - <https://learn.microsoft.com/purview/communication-compliance-reports-audits>
13. Configure a Communication Compliance policy to detect generative AI interactions - Add a
    generative AI app as a location for an existing policy - <https://learn.microsoft.com/purview/communication-compliance-copilot#add-a-generative-ai-app-as-a-location-for-an-existing-policy>
14. Investigate and remediate Communication Compliance alerts (Analysts vs. Investigators
    permissions, remediation actions) - <https://learn.microsoft.com/purview/communication-compliance-investigate-remediate>
15. Create and manage Communication Compliance policies - explicit "PowerShell isn't supported"
    statement - <https://learn.microsoft.com/purview/communication-compliance-policies#create-and-manage-policies>
16. Get started with Communication Compliance - explicit "PowerShell isn't supported" restatement,
    generative AI channel selection (Microsoft Copilot experiences, Enterprise AI apps, Other AI
    apps) - <https://learn.microsoft.com/purview/communication-compliance-configure#notes-and-tips-on-creating-communication-compliance-policies>
17. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
18. Audit log activities - Communication compliance activities table - <https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities>
19. Use Communication Compliance with SIEM solutions (SupervisionRuleMatch worked example) - <https://learn.microsoft.com/purview/communication-compliance-siem>
20. Azure AI Content Safety - Protected material detection concept (text/code scope, examples) - <https://learn.microsoft.com/azure/ai-services/content-safety/concepts/protected-material>
21. Manage audit log retention policies (180-day Standard default, 1-year E5 default) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
22. Detect channel signals with Communication Compliance - Generative AI section ("Microsoft
    Copilot experiences" location description, including Copilot Studio-built Copilots) - <https://learn.microsoft.com/purview/communication-compliance-channels#generative-ai>
23. Learn about Insider Risk Management policy templates - Risky Agents template (Copilot Studio/
    Microsoft Foundry agent risk detection) - <https://learn.microsoft.com/purview/insider-risk-management-policy-templates#policy-templates>
24. Microsoft Purview data security and compliance protections for generative AI apps - AI-apps
    coverage table grouping Microsoft Copilot Studio under "Copilot experiences and agents" (with
    Microsoft 365 Copilot & Microsoft 365 Copilot Chat) and Microsoft Foundry under the separate
    "Enterprise AI apps" category - <https://learn.microsoft.com/purview/ai-microsoft-purview>
25. Privacy and protections (Microsoft Copilot) - explicit rename note: "Microsoft 365 Copilot is
    now named Microsoft Copilot, and Microsoft 365 Copilot Chat is now named Microsoft Copilot
    Chat... There are no changes to security, compliance, and privacy for organizations." -
    <https://learn.microsoft.com/copilot/privacy-and-protections>

> Re-verify all links, the licensing model, and the applicable regulatory-driver framing
> against current Microsoft Learn guidance before a customer-facing assessment or sale - both
> product behavior and AI-governance regulatory frameworks are moving targets.