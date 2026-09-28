---
part: "runbook"
parent: "communication-compliance/teams-viva-engage-content-safety"
---
## Implementation steps

### Portal path - creating the policy (there is no script path for this part; see why this matters/the design notes)

1. Before starting, review `deploy/policy/content-safety-policy-manifest.json` - the recommended
   policy name, scope, and reviewers. **Policy names cannot be changed after creation**
   - confirm before proceeding.
2. Confirm audit logging is on and permissions are assigned: at minimum, one person in
   **Communication Compliance Admins** to create the policy, named HR/Legal stakeholders assigned to
   **Communication Compliance Investigators**, and - the prerequisite specific to this scenario - a
   confirmed, reachable EAP/HR duty-of-care escalation contact.
3. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Communication
   Compliance** → **Policies** → **Create policy** → select the **Detect inappropriate content**
   template.
4. **Name and describe your policy**: `Teams and Viva Engage Content Safety Detection - All Users`
   (from the manifest) → **Next**.
5. **Choose users and reviewers**:
   - Users in scope: **All users** (this scenario's default, matching *Workplace Harassment & Code of Conduct*'s
     own all-users scoping rationale - a self-harm or violence risk signal is not one to leave a
     coverage gap in for any subset of the workforce).
   - Reviewers: add the named HR/Legal stakeholders from the manifest's `reviewers.placeholderMembers`
     (replaced with real accounts) - this scenario's default reviewer pool is the **same** HR/Legal
     function *Workplace Harassment & Code of Conduct* uses, deliberately, so a single trained reviewer team
     handles both policies' overlapping risk categories. Each reviewer receives an
     automatic email notifying them of the assignment → **Next**.
6. **Review the settings chosen for you by the template**: Location = **Microsoft Teams, Viva
   Engage**; Direction = Inbound, Outbound, Internal; Review Percentage = 100%; Conditions = **Hate**,
   **Violence**, **Sexual**, **Self-harm** classifiers. Do not change these unless
   the tenant has a specific, documented reason - they are exactly this scenario's target
   configuration.
7. Select **Create policy** to accept the template as-is, or **Customize policy** only if a
   documented deviation is needed - e.g. adding the optional compensating custom
   keyword dictionary, `deploy/policy/short-form-crisis-threat-phrases.txt`, described in operations and tuning.
8. **Review and finish** → **Create policy**. Allow up to ~1 hour for Teams/Viva Engage body content
   before the policy begins detecting.
9. **Enable username anonymization** (if not already on tenant-wide from another Communication
   Compliance policy). **Settings** → **Communication Compliance** → **Privacy** tab → check
   **Show anonymized versions of usernames** → **Save**. Tenant-wide, not
   per-policy - skip if *Workplace Harassment & Code of Conduct* or *Microsoft 365 Copilot Interaction Detection* already
   enabled it.
10. **Confirm the duty-of-care escalation runbook is staffed and acknowledged by the reviewer
    team before this policy goes active** - this is a go-live precondition for this scenario, not an
    operational nicety.

### Script path - the audit-trail export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3). The connecting identity
#    needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (docs/rbac-model.md §6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - queries the last 7 days across all 3 categories, reports what would be merged, writes nothing
./deploy/Export-ContentSafetyAuditTrail.ps1 -OutputCsvPath './out/content-safety-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the full default retention window
./deploy/Export-ContentSafetyAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/content-safety-audit-trail.csv'

# 4. Recurring run (schedule daily or weekly - overlapping windows are safe, see design.md §7)
./deploy/Export-ContentSafetyAuditTrail.ps1 -OutputCsvPath './out/content-safety-audit-trail.csv'

# 5. Validate
./validate/Test-ContentSafetyAuditTrail.ps1 -AuditTrailCsvPath './out/content-safety-audit-trail.csv'
```

The audit-trail script uses Exchange Online PowerShell's `Search-UnifiedAuditLog` - automation
surface 1 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), because Communication Compliance has no surface of
its own for anything, including its own audit footprint.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy type | Template (**Detect inappropriate content**), unmodified | The template's fixed defaults already match this scenario's target - the design notes |
| Locations | Microsoft Teams, Viva Engage only | **Not** Exchange (unsupported for this classifier family - section 11) and **not** the Copilot generative-AI locations by template default (section 11 documents the optional edit to add one) |
| Direction | Inbound, Outbound, Internal | Full coverage - template default |
| Users in scope | All users | See the implementation steps - a self-harm/violence risk control is not one to leave scoped out for any subset of the workforce |
| Conditions | Hate, Violence, Sexual, Self-harm (Azure AI Content Safety LLM classifiers, preview) | the design notes for exactly what each does and does not cover |
| Custom keyword dictionary (**optional, not applied by default**) | `deploy/policy/short-form-crisis-threat-phrases.txt` | Compensating control for the word-count gap below - see operations and tuning. Applied only via **Customize policy**, only after HR/Legal reviewer review - `deploy/policy/content-safety-policy-manifest.json`'s `customKeywordDictionaryOption` |
| Minimum message length to evaluate | **Documented inconsistently by Microsoft: "three or more words" in one section of the same source page, "five or more words" in another** | See the known limitations - a genuine, disclosed source inconsistency, not resolved by guessing which figure is current |
| Message length ceiling | Up to 10,000 characters per message | |
| Severity threshold for alert + Severity column | 4 or higher (on Azure AI Content Safety's 0-7, trimmed-to-0/2/4/6 scale) | - a materially different triage mechanism from *Workplace Harassment & Code of Conduct*'s trainable classifiers, which carry no severity score at all |
| Review percentage | 100% | Template default; a documented, revisitable lever if alert volume becomes unmanageable - operations and tuning |
| Reviewer role | Communication Compliance Investigators | Full content access - the design notes |
| Reviewer pool (this scenario's default) | Same HR/Legal pool as *Workplace Harassment & Code of Conduct* | Deliberate reuse, not a new pool - the design notes |
| Duty-of-care escalation path (Self-harm matches) | Process control layered on top of the standard workflow - operations and tuning | Not a Communication Compliance product feature; this scenario's own runbook |
| Username anonymization | On (tenant-wide setting) | Settings > Communication Compliance > Privacy - shared with any other Communication Compliance policy in the tenant |
| OCR / attachments / meeting transcripts | Not evaluated by this classifier family | - a materially narrower content surface than the trainable-classifier family, which does support OCR |
| Feedback loop (misclassification reporting to Microsoft) | **Not yet supported** for this classifier family | - unlike the trainable classifiers, which do support it (*Workplace Harassment & Code of Conduct*'s classifier table) |
| Audit-trail script query categories | `PolicyMatch` (`SupervisionRuleMatch`), `PolicyUpdate` (`RecordType Discovery` + 3 operations), `ReviewTag` (`RecordType AeD` + `SupervisoryReviewTag`) | Identical grounded shape to both sibling scenarios - the design notes |
| Audit-trail script policy-name filter | `-PolicyNameFilter 'Teams and Viva Engage Content Safety Detection - All Users'` (default) | Client-side filter, same pattern as *Microsoft 365 Copilot Interaction Detection* - the design notes |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Same rolling-history pattern as both sibling scenarios' audit-trail scripts |

Full cmdlet parameter grounding: `deploy/Export-ContentSafetyAuditTrail.ps1`'s inline comments and
its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**Establish and staff the Self-harm duty-of-care escalation path BEFORE this policy goes
active - this is this scenario's single gating operational requirement, not a tunable KPI.**
Communication Compliance has no classifier-specific auto-routing capability: a Self-harm match
lands in the same Investigator alert queue as a Hate, Sexual, or Violence match, with no
product-level urgency differentiation beyond the shared Severity column. This
scenario's runbook therefore requires the reviewer team to:

1. **Triage every new alert by classifier first, severity second.** A **Self-harm** classifier match
   - at any severity level Communication Compliance surfaces as an alert - is treated as
   **time-critical** and routed immediately to the named EAP/HR duty-of-care contact, in
   parallel with (not instead of) standard Investigator review. Do not wait for a scheduled daily
   triage cycle for a Self-harm match.

   **This requires the duty-of-care escalation contact to be reachable outside standard
   business hours, not just during them.** Detection latency for Teams/Viva Engage body content is
   already up to ~1 hour; if the escalation contact is only monitored 9-to-5 on weekdays, a
   message sent Friday evening could go unaddressed until Monday - a gap of days, not hours, for
   exactly the signal this scenario exists to catch quickly. Before go-live, confirm with the named
   contact (or the organization's crisis-response/EAP function generally) whether after-hours and
   weekend coverage exists; if it does not, document that gap explicitly as a known, accepted
   residual risk rather than letting the runbook silently imply 24/7 coverage it doesn't have
   (the Red Team review finding).
2. **Do not treat a Self-harm match as a conduct violation.** The standard remediation vocabulary -
   Resolve, Tag as Noncompliant, Notify, Escalate - is built for policy-violation triage, not a
   welfare check. A Self-harm-classifier alert's outcome should be a human welfare response
   coordinated with HR/EAP, documented separately from (though still tagged/resolved within,
   for audit-trail completeness) the standard Communication Compliance workflow.
3. **Hate, Sexual, and Violence classifier matches** follow the same remediation workflow this
   repo's other Communication Compliance scenarios already document: Resolve, Tag as
   Compliant/Noncompliant/Questionable, Notify, Escalate, or (Teams only) Remove message.
4. **Document the escalation, even when it turns out to be a false positive or a non-crisis
   context** (e.g., a message discussing self-harm in a clinical/educational/support-group context
   the classifier flagged without intent present) - a documented "reviewed, no welfare concern
   found" outcome is the defensible record; silence on a flagged self-harm signal is not.

**KPIs to watch (first 30 days):**
- **Self-harm match volume and time-to-first-human-contact** - the single most important metric this
  scenario produces. Track from alert-generation timestamp to the duty-of-care contact's first
  documented action, not just to Investigator triage.
- **Hate/Violence match volume by team or business unit** - an unexpectedly concentrated pattern is
  worth investigating as a workplace-culture signal, not just a series of individually-triaged
  alerts (same framing *Workplace Harassment & Code of Conduct* (operations and tuning) already establishes for its own
  overlapping Threat/Discrimination classifiers).
- **Sexual-classifier match volume** - the one classifier in this policy with no direct counterpart
  in *Workplace Harassment & Code of Conduct*'s trainable-classifier set; establish a baseline over the first
  30 days rather than assuming any particular volume is normal.
- **Overlap rate with *Workplace Harassment & Code of Conduct* alerts** (if that scenario is also deployed) -
  a message matching both policies (e.g., a threatening message catching both the Threat trainable
  classifier and this policy's Violence LLM classifier) is expected and not a bug;
  track it to confirm the two policies are behaving as complementary, not redundant, layers.
- **Storage-limit indicator** - the same hard **100 GB or 1,000,000-message** per-policy limit as
  every other Communication Compliance policy in this library; reaching it **auto-deactivates the
  policy with no in-band alert to anyone outside the Communication Compliance/Communication
  Compliance Admins role groups**. Monitor actively - the consequence of a
  silently-deactivated Self-harm detection control is materially worse than for a general
  conduct-monitoring policy.

**Short messages bypass this classifier family entirely - an OPTIONAL compensating custom keyword
dictionary now ships for tenants where that risk is material.** Whether the true minimum is three or
five words (the known limitations's disclosed source inconsistency), a short, unambiguous message - "going to hurt
him", "want to end it" - can fall under either threshold and never reach the classifier at all. This
is a genuine, exploitable detection gap, not just a documentation nit: an evasive or simply terse
sender is not detected by word-count alone. `harassment-and-code-of-conduct/deploy/policy/
code-of-conduct-evasion-phrases.txt` already established the pattern for this library - a custom
keyword dictionary targeting known short-form crisis/threat phrasing - as a compensating control
layered onto a classifier-only policy; `deploy/policy/short-form-crisis-threat-phrases.txt` is that
same pattern applied here, illustrative rather than exhaustive (self-harm-ideation and terse-threat
phrasing, not a slur/profanity duplicate - the classifiers already cover that ground). This
scenario's **default** deployment still does not apply it (the template's fixed classifier set is
used unmodified out of the box, the design notes) - a tenant with a confirmed short-message risk
profile applies it explicitly via **Customize policy** (section 5, step 7;
`deploy/policy/content-safety-policy-manifest.json`'s `customKeywordDictionaryOption` block), after
the dutyOfCareEscalationContact and HR/Legal reviewer pool have reviewed and extended the phrase list
for this tenant's own case patterns - never applied as a static, unreviewed file.

**No feedback loop to Microsoft for misclassified items (yet).** Unlike the trainable classifiers
(*Workplace Harassment & Code of Conduct*'s **Report as Misclassified** action improves future accuracy),
this preview classifier family does not yet support submitting corrections back to Microsoft
 - a documented false positive today does not improve the model tomorrow; plan
reviewer workload accordingly rather than expecting the false-positive rate to self-improve over
time the way it might for the trainable-classifier scenario.

**Lower the default alert-aggregation threshold, same reasoning as *Microsoft 365 Copilot Interaction Detection*
applied to its own security-sensitive matches.** Communication Compliance's system-generated alert
policy defaults to a **4-activity threshold within a 60-minute window** - for a
policy whose most important signal (Self-harm) should ideally not wait for a fourth matching
activity in an hour before the first alert fires, lower this policy's alert-policy threshold to
Microsoft's documented **minimum of 3** activities on the **Alert policies** page. A true
single-event alert is not configurable (3 is the floor), but 3 is materially better than the
default 4 for this scenario's risk profile.

**Consider a phased pilot before "All users" only if the Self-harm duty-of-care runbook is not yet
staffed** - otherwise, deploy to All users from day one; unlike *Workplace Harassment & Code of Conduct*'s
and `copilot-interaction-detection's` optional pilot recommendation, narrowing this scenario's scope
means narrowing self-harm-risk coverage, which is a materially different trade-off than narrowing a
general conduct-monitoring policy's blast radius. Do not default to a pilot here without a specific
reason.

**Alternative/complementary path: add Copilot as a location.** Microsoft documents that Azure AI
classifiers for this family also apply to Microsoft 365 Copilot, even though the
**Detect inappropriate content** template's own fixed location list is Teams/Viva Engage only
 - adding **Microsoft Copilot experiences** as a location to this policy (or a new
one) via **Edit** → **Choose locations to detect communications** is a documented, supported edit, matching the same "add a location to an existing policy" pattern
*Microsoft 365 Copilot Interaction Detection* (operations and tuning) documents in reverse. Not deployed by this scenario's
default configuration - see the design notes.

**Review cadence:** Self-harm matches - immediate, always (section 8 item 1). Daily triage of all other new
alerts. Weekly review of the Reports page trends. Monthly review of match-volume baselines and the
Self-harm-runbook drill cadence (recommend quarterly tabletop exercises, not just a one-time go-live
drill). Immediately upon any audit-trail `PolicyUpdate` or storage-limit-approaching warning.

**Incident-response runbook (alert triage):**
1. **Triage by classifier first** (section 8 above) - Self-harm routes to the duty-of-care path in
   parallel with standard review; Hate/Sexual/Violence follow the standard workflow.
2. **Examine the message details** - sender, direction, severity, and the full flagged text -
   before deciding a remediation action.
3. **Remediate**: **Resolve** (including "misclassified" if a false positive), **Tag as**
   Compliant/Noncompliant/Questionable, **Notify**, **Escalate**/**Escalate for investigation**, or
   (Teams only) **Remove message**. A Self-harm match's remediation tag should
   reflect the welfare-check outcome (operations and tuning item 2), not just a conduct-violation disposition.
4. **For a Violence-classifier match indicating a credible threat**, treat it as a security incident
   per the organization's existing threat-management process, in addition to Communication
   Compliance remediation - cross-reference *Insider Risk Management* if deployed.
5. **Document** - every remediation action is captured in the unified audit log as a
   `SupervisoryReviewTag` event and merged into this scenario's audit-trail CSV; do not delete rows
   from it. For a Self-harm escalation specifically, also document the duty-of-care contact's
   response per the org's own HR/EAP record-keeping process (outside Communication Compliance).

## Rollback and decommission

See the rollback runbook for the full staged procedure (pause → revoke access → delete, handled
independently from the audit-trail script's own rollback). Quick reference: use **Pause policy** in
the portal for a reversible stop; **Delete** only when permanently retiring the control - Delete
**permanently removes all captured messages and alerts**. **Do not pause or
delete this policy without a documented decision that accounts for the loss of self-harm-risk
detection coverage** - see the rollback runbook for why this scenario's rollback carries a materially
different risk calculus than a general conduct-monitoring policy's.

## References

1. Communication Compliance solution overview - <https://learn.microsoft.com/purview/communication-compliance-solution-overview>
2. Create and manage Communication Compliance policies - "PowerShell isn't supported..." statement - <https://learn.microsoft.com/purview/communication-compliance-policies#create-and-manage-policies>
3. Create and manage Communication Compliance policies - policy template table (Inappropriate content row: location, direction, review percentage, conditions) - <https://learn.microsoft.com/purview/communication-compliance-policies#choose-a-policy-template>
4. Create and manage Communication Compliance policies - Content safety classifiers based on large language models, and Considerations when using classifiers (workload scope, word-count figures, OCR/attachment/transcript exclusions, character limit, no feedback loop) - <https://learn.microsoft.com/purview/communication-compliance-policies#content-safety-classifiers-based-on-large-language-models>, <https://learn.microsoft.com/purview/communication-compliance-policies#policy-settings>
5. Language support for Azure AI Content Safety (eight specially-trained languages; broader but lower-quality support elsewhere) - <https://learn.microsoft.com/azure/ai-services/content-safety/language-support>
6. Communication Compliance - Limitations of Communication Compliance (evasive-typing coverage, "12 languages supported today" general product claim) - <https://learn.microsoft.com/purview/communication-compliance-solution-overview#limitations-of-communication-compliance>
7. Get started with Communication Compliance - Choose locations to detect communications (generative AI channel options, including Microsoft Copilot experiences) - <https://learn.microsoft.com/purview/communication-compliance-configure#step-5-required-create-a-communication-compliance-policy>
8. Create and manage Communication Compliance policies - Integrate Communication Compliance with Microsoft Purview Insider Risk Management (documented but not configured by this scenario) - <https://learn.microsoft.com/purview/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
9. Microsoft Purview service description - Communications Compliance (licensing table) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-communications-compliance>
10. Create and manage Communication Compliance policies (policy templates, storage limits, pause/copy, alert policy default threshold/window/minimum) - <https://learn.microsoft.com/purview/communication-compliance-policies>
11. Create and manage Communication Compliance policies - Policy activity detection / time-to-detection table (Teams body content, Viva Engage body content: 1 hour) - <https://learn.microsoft.com/purview/communication-compliance-policies#policy-activity-detection>
12. Harm categories in Azure AI Content Safety - severity levels (full 0-7 scale, trimmed to 0/2/4/6) - <https://learn.microsoft.com/azure/ai-services/content-safety/concepts/harm-categories#severity-levels>
13. Investigate and remediate Communication Compliance alerts (Analysts vs. Investigators permissions, remediation actions) - <https://learn.microsoft.com/purview/communication-compliance-investigate-remediate>
14. Assign permissions in Communication Compliance (role-group action matrix) - <https://learn.microsoft.com/purview/communication-compliance-permissions>
15. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
16. Audit log activities - Communication compliance activities table - <https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities>
17. Use Communication Compliance with SIEM solutions (SupervisionRuleMatch worked example) - <https://learn.microsoft.com/purview/communication-compliance-siem>
18. Use Communication Compliance reports and audits (Discovery/AeD RecordType + Operations worked examples) - <https://learn.microsoft.com/purview/communication-compliance-reports-audits>
19. Manage audit log retention policies (180-day Standard default, 1-year E5 default) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
20. Detect channel signals with Communication Compliance - Viva Engage detection latency, Native Mode requirement - <https://learn.microsoft.com/purview/communication-compliance-channels#viva-engage>

> Re-verify all links, cmdlet/API behavior, and licensing terms against current Microsoft Learn
> before a customer-facing assessment or sale - this module changes faster than most in the
> Purview portfolio, and this scenario's classifier family is explicitly preview.