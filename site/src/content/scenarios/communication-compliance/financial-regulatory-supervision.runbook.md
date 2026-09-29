---
part: "runbook"
parent: "communication-compliance/financial-regulatory-supervision"
---
## Implementation steps

### Portal path - creating the policy (there is no script path for this part; see why this matters/the design notes)

1. Before starting, review `deploy/policy/financial-regulatory-supervision-manifest.json` - the
   recommended policy name, locations, classifiers, and reviewers. **Policy names cannot be changed
   after creation** - confirm before proceeding.
2. Confirm audit logging is on, the registered-representative group/adaptive scope is current,
   and permissions are assigned: at least one person in **Communication Compliance Admins** (or
   **Communication Compliance**) to create the policy, and named, FINRA-registered principals assigned
   to **Communication Compliance Investigators**.
3. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Communication
   Compliance** → **Policies** → **Create policy** → **Custom policy** (not the built-in "Detect
   financial regulatory compliance" template - the design notes explains why this scenario needs the
   custom-policy path to guarantee its exact seven-classifier set).
4. **Name and describe your policy**: `Financial Regulatory Compliance Supervision - Registered
   Representatives` (from the manifest) → **Next**.
5. **Choose users and reviewers**:
   - Users in scope: the firm's registered-representative group/adaptive scope from the manifest's
     `usersInScope` - **not All users**.
   - Reviewers: add the named, FINRA-registered principals from the manifest's
     `reviewers.placeholderMembers` (replaced with real accounts) → **Next**.
6. **Choose locations to detect communications**: select **Exchange** and **Teams** (per the
   manifest's `locations`; add **Viva Engage** only if the firm actually conducts registered-rep
   business communication there) → **Next**.
7. **Choose conditions and review percentage**:
   - Communication direction: **Inbound**, **Outbound**, and **Internal** (desk-to-desk internal chat
     is exactly where collusion/stock-manipulation language is most likely to appear).
   - Conditions: add the **Corporate sabotage**, **Customer complaints**, **Gifts & entertainment**,
     **Money laundering**, **Regulatory collusion**, **Stock manipulation**, and **Unauthorized
     disclosure** trainable classifiers as OR conditions, plus
     **Message/Attachment contains any of these words** using the custom keyword dictionary imported
     from `deploy/policy/finra-supervision-evasion-phrases.txt`.
   - Enable **Use OCR to extract text from images**.
   - Review percentage: **100%** (see section 8 for why this scenario does not treat this the same way the
     harassment sibling treats its own alert-volume lever).
   - Leave **Filter out messages from email blasting services** checked (default) → **Next**.
8. **Review and finish** → **Create policy**. Allow up to ~1 hour for text content and up to 24
   hours for attachments/OCR before the policy begins detecting.
9. **Enable username anonymization.** **Settings** → **Communication Compliance** → **Privacy** tab →
   check **Show anonymized versions of usernames** → **Save** (tenant-wide, not per-policy).
10. **Create a notice template**, if the firm's escalation path uses the **Notify** remediation
    action. **Settings** → **Communication Compliance** → **Notice templates** tab → **Create notice
    template**.
11. **Document the review-percentage and escalation decisions in the firm's WSPs.** Rule 3110(b)(4)
    compliance rests on the firm's own written supervisory procedures matching what this policy
    actually does - a policy configured correctly but undocumented in the WSPs is still an
    examination finding waiting to happen.

### Script path - the audit-trail and evidence-of-review export (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see Automation surface Section 3). The connecting identity
# needs Exchange.ManageAsApp PLUS the View-Only Audit Logs Exchange Online role (RBAC model Section 6).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - queries the last 7 days across all 3 categories, reports what would be merged, writes nothing
./deploy/Export-FinraSupervisionEvidence.ps1 `
    -AuditTrailCsvPath './out/finra-audit-trail.csv' `
    -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv' -WhatIf

# 3. First real run - a one-time backfill covering the full default retention window
./deploy/Export-FinraSupervisionEvidence.ps1 `
    -StartDate (Get-Date).AddDays(-180) -EndDate (Get-Date) `
    -AuditTrailCsvPath './out/finra-audit-trail.csv' `
    -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv'

# 4. Recurring run (schedule daily - overlapping windows are safe, see the design notes Section 8)
./deploy/Export-FinraSupervisionEvidence.ps1 `
    -AuditTrailCsvPath './out/finra-audit-trail.csv' `
    -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv'

# 5. Validate
./validate/Test-FinraSupervisionEvidence.ps1 `
    -AuditTrailCsvPath './out/finra-audit-trail.csv' `
    -EvidenceOfReviewCsvPath './out/finra-evidence-of-review.csv'
```

Uses `Search-UnifiedAuditLog` - automation surface 1 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - because
Communication Compliance has no surface of its own for anything, including its own audit footprint.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Policy type | Custom policy (not a template) | Guarantees the exact 7-classifier set - the design notes |
| Locations | Exchange Online, Microsoft Teams (Viva Engage optional) | the design notes |
| Direction | Inbound, Outbound, Internal | Internal desk-to-desk chat is a primary collusion/stock-manipulation surface |
| Users in scope | The firm's registered-representative group/adaptive scope, **not All users** | the design notes |
| Trainable classifiers | Corporate sabotage, Customer complaints, Gifts & entertainment, Money laundering, Regulatory collusion, Stock manipulation, Unauthorized disclosure | the design notes |
| Custom keyword dictionary | `deploy/policy/finra-supervision-evasion-phrases.txt` | Evasion/concealment phrases only - never restricted-list tickers/company names - the design notes |
| OCR | Enabled | |
| Review percentage | 100% | Rule 3110(b)(4)'s evidence-of-review requirement, not just an alert-volume preference - the design notes below |
| Filter email blasts | On (default) | |
| Reviewer role | Communication Compliance Investigators, each separately FINRA-registered | the design notes |
| Username anonymization | On (tenant-wide setting) | |
| Audit-trail script query categories | `PolicyMatch` (`SupervisionRuleMatch`), `PolicyUpdate` (`RecordType Discovery` + 3 operations), `ReviewTag` (`RecordType AeD` + `SupervisoryReviewTag`) | Identical to the harassment sibling's script - Communication-Compliance-wide, not policy-specific - the design notes |
| Evidence-of-review derivation | From `ReviewTag` rows: Reviewer, review Date, a best-available content reference, and the raw `AuditData` action-taken field | See the known limitations for the one unconfirmed field this derivation flags rather than guesses |
| Script idempotency | Merge + de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))` for both output files | Same rolling-history pattern as the harassment sibling's script |

## Operations and tuning

**Why review percentage is treated differently here than in the harassment sibling.** The harassment
scenario frames its own 100% review percentage as a documented, revisitable alert-volume lever - the
cost of lowering it is more unreviewed harassment, a serious but operational risk. Here, an unreviewed
match under a FINRA-registered-person population is a **documented supervisory-review gap under Rule
3110(b)(4) itself** - regulators do not mandate a specific fixed sampling rate (this build's WebSearch
grounding: enforcement focuses on outcomes and a reasonably designed system, not a tick-box
percentage), but whatever percentage the firm's own WSPs commit to must actually be implemented and
evidenced. This scenario ships **100%** as its default because it is the simplest position to defend
to an examiner; lowering it is a firm's own WSP decision requiring Compliance/Legal sign-off, not a
default this scenario recommends.

**KPIs to watch (first 30 days):**
- **Classifier match volume, per classifier** - establish a baseline; a sudden spike in Stock
  manipulation or Money laundering matches from a specific desk warrants immediate escalation, not
  routine triage.
- **Evidence-of-review completeness** - every `SupervisionRuleMatch` should eventually produce a
  corresponding `SupervisoryReviewTag` event; a growing gap between matches and reviews is a Rule
  3110(b)(4) exposure, not just an operational backlog.
- **Storage-limit indicator** - same 100 GB / 1,000,000-message per-policy limit as every
  Communication Compliance policy; reaching it auto-deactivates the policy with no in-band alert
  outside the Communication Compliance/Communication Compliance Admins role groups.

**Alert-volume tuning, if 100% proves operationally unsustainable at trading-floor volume:** the same
levers Microsoft documents for the harassment sibling apply technically (sentiment triage, combining
classifiers, OCR scope) - but any reduction below 100% here must be a **documented WSP decision with
Compliance/Legal sign-off**, not a unilateral engineering tuning choice, given the regulatory stakes.

**Review cadence:** daily triage is the practical minimum given Rule 3110(b)(4)'s expectation of
timely review; monthly reconciliation of the evidence-of-review CSV against the firm's WSP-committed
review percentage; **quarterly reconciliation of Communication Compliance Investigators role-group
membership against the firm's current FINRA registration roster** - a reviewer who held a valid
registration when first assigned can later leave the firm, transfer to a non-supervisory role, or have
their registration suspended, and nothing in Purview's own RBAC model will flag that drift. Treat this reconciliation as an operational control, not a one-time onboarding check; immediately
upon any storage-limit-approaching warning.

**Cross-link - retention is a separate control.** This scenario's evidence-of-review export proves
*who reviewed what, when*; it is not the system of record for SEC 17a-4/FINRA 4511's multi-year
immutable retention of the underlying communications. Deploy
*Retention Labels for Financial Records* alongside this scenario for
that separate, equally mandatory obligation - see the design notes.

**Incident-response runbook (alert triage):**
1. **Triage by classifier.** A Stock manipulation or Money laundering match is a different urgency
   tier from a Gifts & entertainment match - escalate the former to Legal/senior Compliance
   immediately, not into a routine queue.
2. **Examine message details** - sender, recipient, sentiment evaluation, OCR-matched image text -
   before deciding a remediation action.
3. **Remediate and document**: Resolve, Tag as, Notify (using the notice template from the implementation steps), or
   Escalate, per Microsoft's documented remediation-action set. Every action must be capturable in the
   evidence-of-review CSV's action-taken field (the known limitations - one unconfirmed `AuditData` field flagged there).
4. **For a Teams message requiring removal**, use the **Remove message** remediation action
   (Investigators only).

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference: use **Pause policy** in the portal
for a reversible stop; **Delete** only when permanently retiring the control - Delete **permanently
removes all captured messages, attachments, and alerts**.

## References

1. Communication Compliance - regulatory compliance classifier family (Corporate sabotage, Customer
   complaints, Gifts & entertainment, Money laundering, Regulatory collusion, Stock manipulation,
   Unauthorized disclosure) - confirmed directly via
   <https://learn.microsoft.com/purview/communication-compliance-policies#policy-settings> and
   <https://learn.microsoft.com/purview/trainable-classifiers-definitions#regulatory-collusion>.
2. "Detect financial regulatory compliance" and "Detect conflict of interest" built-in policy
   templates, including each template's exact classifier bundling, location, direction, and review
   percentage - confirmed directly via
   <https://learn.microsoft.com/purview/communication-compliance-policies#choose-a-policy-template>.
3. Create and manage Communication Compliance policies (policy templates, PowerShell-not-supported
   statement, storage limits, pause/copy) - <https://learn.microsoft.com/purview/communication-compliance-policies>
4. Get started with Communication Compliance (step-by-step policy workflow, notice templates/
   anonymization, test policy) - <https://learn.microsoft.com/purview/communication-compliance-configure>
5. Investigate and remediate Communication Compliance alerts (Analysts vs. Investigators permissions,
   remediation actions) - <https://learn.microsoft.com/purview/communication-compliance-investigate-remediate>
6. Use Communication Compliance reports and audits (Discovery/AeD RecordType worked examples for
   `SupervisionPolicy*`/`SupervisoryReviewTag`) - <https://learn.microsoft.com/purview/communication-compliance-reports-audits>
7. Use Communication Compliance with SIEM solutions (`SupervisionRuleMatch` worked example) -
   <https://learn.microsoft.com/purview/communication-compliance-siem>
8. Audit log activities - Communication compliance activities table -
   <https://learn.microsoft.com/purview/audit-log-activities#communication-compliance-activities>
9. FINRA Rule 3110 (Supervision), specifically 3110(b)(4) (review of correspondence/internal
   communications - registered-principal review, four required evidence-of-review elements) -
   corroborated via WebSearch across multiple independent secondary sources summarizing
   <https://www.finra.org/rules-guidance/rulebooks/finra-rules/3110> (not directly fetchable from this
   build's network - the design notes). Re-verify the rule's current text directly before a
   customer-facing compliance assessment.
10. SEC Rule 17a-4 electronic recordkeeping requirements for broker-dealers (3-year retention, 2-year
    easily-accessible requirement, WORM/audit-trail-alternative storage) - corroborated via WebSearch
    summarizing <https://www.sec.gov/investment/amendments-electronic-recordkeeping-requirements-broker-dealers>
    (not directly fetchable from this build's network - the design notes).
11. SEC/CFTC "off-channel communications" enforcement sweep, December 2021 - August 2024 (JPMorgan
    $125M; 16-firm $1.1B settlement; 13-firm $549M SEC/CFTC settlement; further 2024 rounds; >$3
    billion combined penalties across 100+ firms) - corroborated via WebSearch across multiple
    independent law-firm and industry secondary sources reporting on the same SEC/CFTC enforcement
    actions.
12. Create and manage Communication Compliance policies / Get started with Communication Compliance -
    explicit "PowerShell isn't supported" statements - <https://learn.microsoft.com/purview/communication-compliance-policies#create-and-manage-policies>,
    <https://learn.microsoft.com/purview/communication-compliance-configure#notes-and-tips-on-creating-communication-compliance-policies>
13. FINRA Rule 3220 (Influencing or Rewarding Employees of Others) and Rule 4530 (customer complaint
    reporting) - cited for the Gifts & entertainment and Customer complaints classifiers' regulatory
    mapping; re-verify current rule text before a customer-facing citation.

> This scenario's regulatory-driver research relied on WebSearch corroboration rather than a direct
> Microsoft Learn/SEC/FINRA fetch - see the design notes for the environment limitation and what that
> means for re-verification before a customer-facing sale.