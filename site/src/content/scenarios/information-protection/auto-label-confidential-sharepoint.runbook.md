---
part: "runbook"
parent: "information-protection/auto-label-confidential-sharepoint"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the prerequisite banner **Turn on now** has been accepted under **Information
   Protection > Sensitivity labels** (enables sensitivity labels for Office files in SharePoint
   and OneDrive) - or run `Set-SPOTenant -EnableAIPIntegration $true` from SharePoint Online
   Management Shell.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Information Protection** → **Policies** → **Auto-labeling policies** → **+ Create
   auto-labeling policy** → **Automatically apply label only**.
3. Category: **Custom** → **Custom policy** → **Next**.
4. Name: `Confidentiality - Auto-Label PII in SharePoint and OneDrive`.
5. **Choose a label to auto-apply**: select the existing **Confidential** label. Confirm it is
   *not* shown as a parent label in the picker (parent labels are grayed out or, if selected
   anyway, silently label nothing).
6. **Choose locations**: select **SharePoint sites** and **OneDrive accounts**; keep **All**
   included, or exclude the legal-hold/eDiscovery site by URL under **Excluded**.
7. **Set up common or advanced rules** → **Common rules** → add condition **Content contains** →
   **Sensitive info types** → add **U.S. Social Security Number (SSN)** and **Credit Card
   Number**, minimum count **1** each, combined with **Any of these** (logical OR).
8. **Additional label settings**: leave default (don't force-override higher-priority labels).
9. **Decide if you want to test out the policy now or later**: select **Run policy in simulation
   mode**; do **not** enable "turn on automatically after 7 days" - this scenario's staged
   rollout enables deliberately, not on a timer.
10. **Submit** → **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none
./deploy/New-ConfidentialAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real content first
./deploy/New-ConfidentialAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold'

# 4. After a review window, enforce
./deploy/New-ConfidentialAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-ConfidentialAutoLabelPolicy.ps1 -LabelName 'Confidential'
```

The deploy script uses Security & Compliance PowerShell (`New-AutoSensitivityLabelPolicy`,
`New-AutoSensitivityLabelRule`) - automation surface 2 per [Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first).

## Configuration reference

| Setting | Rule: `AutoLabel-Confidential-PII-SharePoint` | Rule: `AutoLabel-Confidential-PII-OneDrive` |
|---|---|---|
| `Workload` | `SharePoint` | `OneDriveForBusiness` |
| Sensitive info types | U.S. Social Security Number (SSN), Credit Card Number - `mincount = 1` each, OR-combined | Same |
| `Policy` | `Confidentiality - Auto-Label PII in SharePoint and OneDrive` (shared) | Same |

| Policy-level setting | Value |
|---|---|
| `ApplySensitivityLabel` | `<LabelName>` (default `Confidential`) - must reference an existing, published, non-parent label |
| `SharePointLocation` / `OneDriveLocation` | `All` |
| `SharePointLocationException` | `<ExcludedSharePointSiteUrl>` (optional; legal-hold/eDiscovery site) |
| `OverwriteLabel` | `$true` - allows overriding a **lower-priority auto-applied** label only; manual labels and higher-priority labels are never overridden regardless of this setting |
| `Mode` | `TestWithNotifications` (deploy default) → `Enable` after review |

Full cmdlet parameter grounding: `deploy/New-ConfidentialAutoLabelPolicy.ps1` inline comments and
its `.NOTES` block cite the exact Microsoft Learn PowerShell reference pages.

## Operations and tuning

**Deployment sequence**: Off → simulation mode → simulation mode reviewed for at least a business
cycle (7+ days) → Enable. The deploy script's default `-Mode TestWithNotifications` corresponds to
simulation; pass `-Mode Enable` deliberately once the Labeled items / failures review looks right.
Do not accept the portal wizard's "automatically turn on after 7 days if not edited" option - a
deliberate, reviewed enable is the standard this library holds all controls to.

**KPIs to watch (first 30-60 days):**
- **Labeled file volume vs. failure count**, from the policy's Overview page - a rising failure
  count with a flat labeled count usually means files are checked out, in a check-out-required
  library, or open elsewhere at scan time; investigate the failure-reason
  breakdown before assuming a policy misconfiguration.
- **Backlog coverage** - auto-labeling policies evaluate content going forward from activation and
  on an ongoing scan cadence; a tenant with years of existing SharePoint/OneDrive content should
  pair this rollout with an **on-demand classification** run to extend coverage to files that
  haven't been modified recently rather than waiting for the standard pass to
  reach them.
- **False-positive rate on the SSN SIT** - nine-digit numbers that aren't SSNs (order numbers,
  some internal IDs) are the most common false-positive source for this SIT; track override/manual
  relabel activity in Activity Explorer to catch a pattern worth tuning (e.g., raising the SIT's
  confidence requirement) rather than reacting to a single report.

**Alert routing:** auto-labeling doesn't generate DLP-style incident-report emails; its
observability surface is the policy's **Overview / Labeled items / Labeling failures** dashboard
in the Purview portal, and **Activity Explorer** for ongoing labeling activity across the tenant.
For SIEM integration, pull labeling events via the Audit Search / Graph pattern in
[Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) rather than expecting a native alert feed.

**Review cadence:** monthly for the first quarter (labeling failure trend, backlog coverage),
quarterly thereafter alongside the tenant's broader Information Protection posture review;
re-run `validate/Test-ConfidentialAutoLabelPolicy.ps1` each time to catch configuration drift.

**Runbook - a file that should be labeled isn't:**
1. Confirm the file wasn't updated after the last simulation/evaluation pass -
   re-run simulation or wait for the next production pass.
2. Check the **Labeled items → Failed** view for a specific failure reason (checked out, password
   protected, unsupported format, existing higher-priority label).
3. If the failure reason is "existing label, not overridden" and that's unexpected, confirm
   whether the existing label was applied manually (never overridden by design) versus by another,
   higher-priority auto-labeling or default-label policy (also never overridden) - this is
   expected behavior per the configuration reference, not a bug.
4. If no failure reason is surfaced and the file still isn't labeled after a full pass cycle,
   confirm `EnableAIPIntegration` is still `$true` on the tenant (`(Get-SPOTenant).EnableAIPIntegration`)
   - this can be reset by unrelated SharePoint tenant administration and silently stops all
   labeling with no portal error.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-ConfidentialAutoLabelPolicy.ps1` disables (reversible); add `-Purge`
to permanently delete the policy and its rules.

## References

1. Automatically apply a sensitivity label to Microsoft 365 data - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically>
2. Automatically apply a sensitivity label to Microsoft 365 data - pre-flight checklist, prerequisites, PDF 100,000-files/day limit, SIT going-forward-only behavior - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#how-to-configure-auto-labeling-policies-for-sharepoint,-onedrive,-and-exchange>
3. New-AutoSensitivityLabelRule reference (`-Workload` accepted values: Exchange, SharePoint, OneDriveForBusiness) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule>
4. Data Loss Prevention policy reference - "Content contains" supports multiple sensitive info types combined with "Any of these" (OR) or "All of these" (AND); same condition-group model underlies auto-labeling rules - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
5. Automatically apply a sensitivity label to Microsoft 365 data - "Will an existing label be overridden?" (manual labels never overridden; lower-priority auto-applied/default labels overridden only with the override setting enabled) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#will-an-existing-label-be-overridden>
6. Automatically apply a sensitivity label to Microsoft 365 data - policy Overview / Labeled items / Labeling failures review pages - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#how-to-configure-auto-labeling-policies-for-sharepoint,-onedrive,-and-exchange>
7. Configure SharePoint with a sensitivity label to extend permissions to downloaded documents - label requirements including "Assign permissions now" vs. user-defined permissions for encryption - <https://learn.microsoft.com/purview/sensitivity-labels-sharepoint-extend-permissions#requirements>
8. Enable sensitivity labels for files in SharePoint and OneDrive (`Set-SPOTenant -EnableAIPIntegration`, replication timing, PDF/video support toggles) - <https://learn.microsoft.com/purview/sensitivity-labels-sharepoint-onedrive-files>
9. New-AutoSensitivityLabelPolicy reference (`-Mode`, `-SharePointLocation`, `-OneDriveLocation`, `-SharePointLocationException`, `-OverwriteLabel`, `-ApplySensitivityLabel`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy>
10. Set-AutoSensitivityLabelPolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-autosensitivitylabelpolicy>
11. Remove-AutoSensitivityLabelPolicy reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-autosensitivitylabelpolicy>
12. Get-Label reference (retrieving label GUID/name for search and validation) - <https://learn.microsoft.com/powershell/module/exchange/get-label>
13. Learn about sensitive information types - confidence levels, SSN/Credit Card Number built-in SITs - <https://learn.microsoft.com/purview/sit-sensitive-information-type-learn-about>
14. Connect-IPPSSession reference (app-only certificate auth) - <https://learn.microsoft.com/powershell/module/exchangepowershell/connect-ippssession>
15. Automatically apply a sensitivity label to Microsoft 365 data - pre-flight checklist role requirements for turning on a policy (Compliance Administrator / Compliance Data Administrator) - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin>

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - auto-labeling behavior (limits, region availability, prerequisite toggles) has changed
> more than once in this feature's history.