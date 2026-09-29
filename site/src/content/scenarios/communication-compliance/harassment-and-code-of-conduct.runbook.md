---
part: "runbook"
parent: "communication-compliance/harassment-and-code-of-conduct"
---
## Implementation steps

### Portal path - creating the policy (there is no script path for this part; see why this matters/the design notes)

0. **(Optional, one-time, tenant-wide)** If the tenant has [eDiscovery compliance
   boundaries](https://learn.microsoft.com/purview/ediscovery-set-up-compliance-boundaries)
   configured, run this once (Security & Compliance PowerShell) so Investigators/Admins can access
   the policy's scoped review mailbox - skip if the tenant has no compliance boundaries:
   ```powershell
   Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain
   New-ComplianceSecurityFilter -FilterName "CC_mailbox" `
       -Users <HR/Legal reviewer + admin aliases> `
       -Filters "Mailbox_Name -like 'SupervisoryReview{*}'" -Action All
   ```
  
1. Before starting, review `deploy/policy/communication-compliance-policy-manifest.json` - the
   recommended policy name, locations, classifiers, and reviewers. **Policy names cannot be changed
   after creation** - confirm before proceeding.
2. Confirm audit logging is on and permissions are assigned: at minimum, one person in
   **Communication Compliance Admins** (or **Communication Compliance**) to create the policy, and
   named HR/Legal stakeholders assigned to **Communication Compliance Investigators**.
3. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Communication
   Compliance** → **Policies** → **Create policy** → **Custom policy** (not a template - this
   scenario's classifier + custom-dictionary combination needs the custom-policy path).
4. **Name and describe your policy**: `Workplace Harassment and Code of Conduct - All Users`
   (from the manifest) → **Next**.
5. **Choose users and reviewers**:
   - Users in scope: **All users** (Microsoft's own planning guidance: "most organizations should
     include all users in Communication Compliance policies optimized for harassment or
     discrimination detection").
   - Reviewers: add the named HR/Legal stakeholders from the manifest's
     `reviewers.placeholderMembers` (replaced with real accounts). Each reviewer receives an
     automatic email notifying them of the assignment → **Next**.
6. **Choose locations to detect communications**: select **Exchange**, **Teams**, and **Viva
   Engage** (per the manifest's `locations`) → **Next**.
7. **Choose conditions and review percentage**:
   - Communication direction: **Inbound**, **Outbound**, and **Internal** (all three).
   - Conditions: add the **Discrimination**, **Harassment** (may display as "Targeted harassment" -
     section 11), **Profanity**, and **Threat** trainable classifiers as OR conditions, plus **Message/
     Attachment contains any of these words** using a custom keyword dictionary imported from
     `deploy/policy/code-of-conduct-evasion-phrases.txt`.
   - Enable **Use OCR to extract text from images** (catches screenshotted harassing content).
   - Review percentage: **100%**.
   - Leave **Filter out messages from email blasting services** checked (default)
     → **Next**.
8. **Review and finish** → **Create policy**. Allow up to ~1 hour for text content and up to 24
   hours for attachments/OCR before the policy begins detecting.
9. **Reassign the User-reported messages policy's reviewers.** This system policy is auto-created
   by the tenant's Communication Compliance license (up to 30 days after purchase) and its default
   reviewers/creator fall back to the **Communication Compliance Admins** role group or, if empty,
   a **randomly selected Global Administrator**. Go to **Communication
   Compliance** → **Policies** → **User-reported messages** → **Edit**, and assign the same
   HR/Legal reviewers as step 5. This lets employees self-report inappropriate Teams/Viva Engage
   messages directly - Microsoft's own guidance: "Admins should immediately assign custom
   reviewers to this policy".
10. **Enable username anonymization.** **Settings** (top-right) → **Communication Compliance** →
    **Privacy** tab → check **Show anonymized versions of usernames** → **Save**. This is a tenant-wide setting, not per-policy.
11. **Create a notice template.** **Settings** → **Communication Compliance** → **Notice
    templates** tab → **Create notice template** - used by reviewers when the **Notify**
    remediation action is the appropriate response to a lower-severity match.

### Script path - the audit-trail export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface, section 3). The connecting identity
# needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (RBAC model, section 6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - queries the last 7 days across all 3 categories, reports what would be merged, writes nothing
./deploy/Export-CommunicationComplianceAuditTrail.ps1 -OutputCsvPath './out/cc-audit-trail.csv' -WhatIf

# 3. First real run - a one-time backfill covering the full default retention window
./deploy/Export-CommunicationComplianceAuditTrail.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -OutputCsvPath './out/cc-audit-trail.csv'

# 4. Recurring run (schedule daily or weekly - overlapping windows are safe, see the design notes)
./deploy/Export-CommunicationComplianceAuditTrail.ps1 -OutputCsvPath './out/cc-audit-trail.csv'

# 5. Validate
./validate/Test-CommunicationComplianceAuditTrail.ps1 -AuditTrailCsvPath './out/cc-audit-trail.csv'
```

The audit-trail script uses Exchange Online PowerShell's `Search-UnifiedAuditLog` - automation
surface 1 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first), because Communication Compliance has no surface of
its own for anything, including its own audit footprint.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy type | Custom policy (not a template) | Needed to combine classifiers with a custom keyword dictionary in one policy - the design notes |
| Locations | Exchange Online, Microsoft Teams, Viva Engage | Matches the built-in "Detect inappropriate text" template's location set |
| Direction | Inbound, Outbound, Internal | Full coverage |
| Users in scope | All users | Microsoft's own planning guidance for harassment/discrimination policies |
| Trainable classifiers | Discrimination, Harassment ("Targeted harassment"), Profanity, Threat | the design notes for selection rationale |
| Custom keyword dictionary | `deploy/policy/code-of-conduct-evasion-phrases.txt` | Evasion/concealment phrases only - not a slur/profanity duplicate list, the design notes |
| OCR | Enabled | Screenshotted harassing content |
| Review percentage | 100% | A documented, revisitable alert-volume lever - operations and tuning |
| Filter email blasts | On (default) | Reduces newsletter/spam false positives |
| Reviewer role | Communication Compliance Investigators | Full content access - the design notes |
| Username anonymization | On (tenant-wide setting) | Settings > Communication Compliance > Privacy |
| User-reported messages reviewers | Reassigned to the same HR/Legal reviewers | Default falls back to Communication Compliance Admins/Global Admin - step 9 |
| Audit-trail script query categories | `PolicyMatch` (`SupervisionRuleMatch`), `PolicyUpdate` (`RecordType Discovery` + 3 operations), `ReviewTag` (`RecordType AeD` + `SupervisoryReviewTag`) | the design notes separate calls, matching Microsoft's own worked examples |
| Audit-trail script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` | Rolling-history pattern, same as *Assess Against ISO/IEC 27001:2022*'s audit-trail script |

Full cmdlet parameter grounding: `deploy/Export-CommunicationComplianceAuditTrail.ps1`'s inline
comments and its `.NOTES` block cite the exact Microsoft Learn reference pages.

## Operations and tuning

**KPIs to watch (first 30 days):**
- **Classifier match volume, per classifier.** Microsoft's own documented expected-volume table
 sets a rough baseline: Discrimination/Harassment/Threat are documented as
  typically **Low** volume; Profanity as **Medium**. A Profanity volume far above that baseline in
  a specific team or channel is worth investigating for a culture issue, not just tuning out as
  noise.
- **Review-tag volume and reviewer turnaround time** (`ReviewTag` category in the audit-trail CSV)
  - a growing backlog of unaddressed alerts undermines the "promptly correct" element of the
  *Faragher*/*Ellerth* affirmative defense as much as not detecting the harassment at all.
- **`PolicyUpdate` event volume/content** - the audit-trail script's inline `Write-Warning` fires
  on every detected policy change; review each against what was actually intended.
- **Storage-limit indicator** - each policy has a hard **100 GB or 1,000,000-message** limit;
  reaching it **auto-deactivates the policy with no in-band alert to anyone outside the
  Communication Compliance/Communication Compliance Admins role groups**. A
  policy that silently stops protecting because nobody was watching the 80/90/95% notification
  emails is a real, documented failure mode - see the known limitations and the Red Team finding in the review notes.

**Alert-volume tuning (if 100% review percentage proves unsustainable):** Microsoft's own
best-practices guidance recommends, in order: use **sentiment evaluation** to triage
negative-sentiment messages first; **report false positives as misclassified** to improve future
accuracy; **combine classifiers** (e.g. Threat + Profanity, or Harassment + Profanity) to raise the
match threshold; and only then consider **lowering the review percentage** below 100%. Lowering review percentage is the last lever, not the first, for a
harassment-focused policy - a sampled 10% review means 90% of genuine matches go unreviewed.

**Consider a phased pilot before "All users."** Microsoft's own planning guidance recommends
scoping harassment/discrimination policies to all users, and this scenario follows that
recommendation as its target end state - but a tenant deploying this for the first time, with no
existing baseline for its own Profanity-classifier volume, should weigh a 2-4 week pilot scoped to
**Select users** (one business unit) before expanding to **All users**, so HR/Legal can validate
signal-to-noise and staff the review workload realistically before it's tenant-wide. Record this as
a deliberate, time-boxed exception in `deploy/policy/communication-compliance-policy-manifest.json`
if taken - don't let a "temporary" pilot scope quietly become the permanent one.

**Cross-policy resolution (preview):** on by default - resolving a match in this policy
auto-resolves the same underlying message match in any other policy where it was also detected.
Understand this setting before assuming every "Resolved" count in a report represents an
independently reviewed decision.

**Review cadence:** daily triage of new alerts is the practical minimum for a harassment-focused
policy given the "promptly correct" legal standard; weekly review of the **Reports** page
trends; monthly review of classifier-volume baselines against Microsoft's documented expectations;
immediately upon any audit-trail `PolicyUpdate` or storage-limit-approaching warning.

**Incident-response runbook (alert triage):**
1. **Triage by classifier and sentiment.** A **Threat** classifier match is a different urgency
   tier than a **Profanity** match - treat a Threat match as a potential physical-safety concern
   requiring immediate escalation to Security/Legal (and, per the organization's own policy,
   potentially law enforcement), not a routine HR queue item.
2. **Examine message details** - sender, recipient, sentiment evaluation, and (if OCR-matched) the
   extracted image text - before deciding a remediation action.
3. **Remediate**: **Resolve** (including "misclassified" if the match was a false positive -
   improves future classifier accuracy), **Tag as** Compliant/Noncompliant/Questionable, **Notify**
   (using the notice template from section 5 step 11), or **Escalate**/**Escalate for investigation** for
   HR/Legal case management, per Microsoft's documented remediation-action set.
4. **For a Teams message requiring removal**, use the **Remove message** remediation action
   (Investigators only) - note the documented limitation that a message sent
   *before* the reporting user joined the chat cannot be removed via Teams message remediation.
5. **Document** - every remediation action is captured in the unified audit log as a
   `SupervisoryReviewTag` event and merged into this scenario's audit-trail CSV; do not delete rows
   from it.

## Rollback and decommission

See the rollback runbook for the full staged procedure (pause → revoke access → delete, handled
independently from the audit-trail script's own rollback). Quick reference: use **Pause policy**
in the portal for a reversible stop; **Delete** only when permanently retiring the control - Delete
**permanently removes all captured messages, attachments, and alerts**.

## References

1. Learn about Communication Compliance (limitations table - evasive typing, 12 languages, feedback
   loop) - <https://learn.microsoft.com/purview/communication-compliance-solution-overview>
2. Plan for Communication Compliance (all-users recommendation for harassment/discrimination
   policies, adaptive scopes, licensing note) - <https://learn.microsoft.com/purview/communication-compliance-plan>
3. Create and manage Communication Compliance policies (policy templates, PowerShell-not-supported
   statement, User-reported messages policy defaults, OCR, storage limits, pause/copy, condition
   builder, alert policy defaults) - <https://learn.microsoft.com/purview/communication-compliance-policies>
4. Get started with Communication Compliance (step-by-step policy workflow, Viva Engage Native Mode
   requirement, compliance boundaries, notice templates/anonymization, test policy) - <https://learn.microsoft.com/purview/communication-compliance-configure>
5. (see reference 4) Step 6 - Update compliance boundaries for Communication Compliance policies
   (`New-ComplianceSecurityFilter`)
6. Investigate and remediate Communication Compliance alerts (Analysts vs. Investigators
   permissions, remediation actions, sentiment evaluation, cross-policy resolution, Power Automate) - <https://learn.microsoft.com/purview/communication-compliance-investigate-remediate>
7. Microsoft Purview service description - Communications Compliance (licensing table, PAYG scope
   for non-M365 AI data) - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-communications-compliance>
8. Create and manage Communication Compliance policies - trainable classifier table and volume
   guidance (Discrimination/Harassment/Profanity/Threat descriptions, custom classifiers not
   supported, word-count requirement) - <https://learn.microsoft.com/purview/communication-compliance-policies#use-microsoft-provided-trainable-classifiers> and <https://learn.microsoft.com/purview/communication-compliance-alerts-best-practices>
9. Best practices for managing the volume of alerts in Communication Compliance (sentiment
   evaluation, combine classifiers, review percentage, content-safety classifiers Teams/Viva
   Engage/Copilot-only scope) - <https://learn.microsoft.com/purview/communication-compliance-alerts-best-practices>
10. Create and manage Communication Compliance policies - Integrate with Insider Risk Management
    (Insider risk trigger policy, Threat/Harassment/Discrimination classifiers) - <https://learn.microsoft.com/purview/communication-compliance-policies#integrate-communication-compliance-with-microsoft-purview-insider-risk-management>
11. Use Communication Compliance with SIEM solutions (SupervisionRuleMatch, ComplianceSupervisionExchange, Sentinel/OfficeActivity integration) - <https://learn.microsoft.com/purview/communication-compliance-siem>
12. Create and manage Communication Compliance policies - explicit "PowerShell isn't supported"
    statement - <https://learn.microsoft.com/purview/communication-compliance-policies#create-and-manage-policies>
13. Get started with Communication Compliance - explicit "PowerShell isn't supported" restatement - <https://learn.microsoft.com/purview/communication-compliance-configure#notes-and-tips-on-creating-communication-compliance-policies>
14. New-SupervisoryReviewPolicyV2 reference (legacy cmdlet name, not the current supported policy-authoring path - see the design notes) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-supervisoryreviewpolicyv2>
15. U.S. EEOC - EEOC Commission Votes to Rescind 2024 Harassment Guidance (January 23, 2026) - <https://www.eeoc.gov/newsroom/eeoc-commission-votes-rescind-2024-harassment-guidance>
16. Search-UnifiedAuditLog reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
17. Manage audit log retention policies (180-day Standard default, 1-year E5 default for Entra/
    Exchange/OneDrive/SharePoint, up to 10 years with Audit Premium retention policies) - <https://learn.microsoft.com/purview/audit-log-retention-policies>
18. Audit log activities - Communication compliance activities table - <https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities>
19. Use Communication Compliance reports and audits (Export policy updates/review activities,
    Discovery/AeD RecordType worked examples, `Get-SupervisoryReviewPolicyV2` mailbox-size check) - <https://learn.microsoft.com/purview/communication-compliance-reports-audits>

> Re-verify all links, the licensing model, and the regulatory-driver currency note
> against current Microsoft Learn and EEOC guidance before a customer-facing assessment or sale -
> both product behavior and the applicable regulatory guidance landscape change over time, and this
> build already caught one material change (the January 2026 EEOC guidance rescission) mid-research.