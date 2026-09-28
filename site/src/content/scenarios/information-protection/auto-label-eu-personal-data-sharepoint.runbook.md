---
part: "runbook"
parent: "information-protection/auto-label-eu-personal-data-sharepoint"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the prerequisite banner **Turn on now** has been accepted under **Information
   Protection > Sensitivity labels** (or run `Set-SPOTenant -EnableAIPIntegration $true`) - same
   one-time tenant step as the sibling scenario.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** →
   **Information Protection** → **Policies** → **Auto-labeling policies** → **+ Create
   auto-labeling policy** → **Automatically apply label only**.
3. Category: **Custom** → **Custom policy** → **Next**.
4. Name: `Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive`.
5. **Choose a label to auto-apply**: select the existing **Confidential** label. Confirm it is
   *not* shown as a parent label in the picker.
6. **Choose locations**: select **SharePoint sites** and **OneDrive accounts**; keep **All**
   included, or exclude the legal-hold/eDiscovery site by URL under **Excluded**.
7. **Set up common or advanced rules** → **Common rules** → add condition **Content contains** →
   **Sensitive info types** → add **EU national identification number**, **EU Social Security
   Number (SSN) or Equivalent ID**, and **EU debit card number**, minimum count **1** each,
   combined with **Any of these** (logical OR). To localize to specific member
   states instead of the full EU-wide bundles, search the picker for the individual per-country
   SIT (e.g. "Germany Identity Card Number") and use that in place of the bundle - see the configuration reference.
8. **Additional label settings**: leave default (don't force-override higher-priority labels).
9. **Decide if you want to test out the policy now or later**: select **Run policy in simulation
   mode**; do **not** enable "turn on automatically after 7 days."
10. **Submit** → **Done**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only - see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run - reports every change, makes none. Default SIT set: EU-wide bundles (§6).
./deploy/New-EuPersonalDataAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' `
    -WhatIf

# 3. Deploy in simulation mode (default) to observe real content first
./deploy/New-EuPersonalDataAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold'

# 3b. Or, localized to specific member states instead of the full EU-wide bundle (§6):
./deploy/New-EuPersonalDataAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -SensitiveInfoTypeName 'Germany Identity Card Number','France Social Security Number','EU debit card number'

# 3c. Or, add the opt-in passport/driver's-license bundle on top of whichever set above is in
#     effect (§6) - read the U.S./U.K. passport-merge gotcha in §11 before enabling for a
#     U.K.-only organization:
./deploy/New-EuPersonalDataAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -IncludeTravelDocumentSits

# 4. After a review window, enforce
./deploy/New-EuPersonalDataAutoLabelPolicy.ps1 `
    -LabelName 'Confidential' `
    -ExcludedSharePointSiteUrl 'https://contoso.sharepoint.com/sites/LegalHold' `
    -Mode Enable -Force

# 5. Validate
./validate/Test-EuPersonalDataAutoLabelPolicy.ps1 -LabelName 'Confidential'
```

The deploy script uses Security & Compliance PowerShell (`New-AutoSensitivityLabelPolicy`,
`New-AutoSensitivityLabelRule`, `Get-DlpSensitiveInformationType`) - automation surface 2 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first).

## Configuration reference

| Setting | Rule: `AutoLabel-EuPersonalData-SharePoint` | Rule: `AutoLabel-EuPersonalData-OneDrive` |
|---|---|---|
| `Workload` | `SharePoint` | `OneDriveForBusiness` |
| Sensitive info types (default) | EU national identification number, EU Social Security Number (SSN) or Equivalent ID, EU debit card number - `mincount = 1` each, OR-combined | Same |
| `Policy` | `Confidentiality - Auto-Label EU Personal Data in SharePoint and OneDrive` (shared) | Same |

| Policy-level setting | Value |
|---|---|
| `ApplySensitivityLabel` | `<LabelName>` (default `Confidential`) - must reference an existing, published, non-parent label |
| `SharePointLocation` / `OneDriveLocation` | `All` |
| `SharePointLocationException` | `<ExcludedSharePointSiteUrl>` (optional; legal-hold/eDiscovery site) |
| `OverwriteLabel` | `$true` - overrides a lower-priority **auto-applied** label only; manual and higher-priority labels are never overridden |
| `Mode` | `TestWithNotifications` (deploy default) → `Enable` after review |

**Localizing the SIT set (`-SensitiveInfoTypeName`):** the default three-SIT set
matches every EU member state's own identifier format via Microsoft's built-in EU-wide bundle
SITs. An organization whose regulated population is limited to specific member states gets tighter
false-positive control, and a clearer per-jurisdiction legal-basis mapping, by passing only those
countries' own per-country SITs instead - e.g.:

| Scenario | `-SensitiveInfoTypeName` example |
|---|---|
| Full EU/UK coverage (default) | `'EU national identification number','EU Social Security Number (SSN) or Equivalent ID','EU debit card number'` |
| Germany + France only | `'Germany Identity Card Number','France Social Security Number','EU debit card number'` |

**Opt-in travel-document bundle (`-IncludeTravelDocumentSits`):** additive switch - appends `'EU
passport number'` and `"EU driver's license number"` (also real, confirmed EU-wide bundle SITs -
the design notes) to whichever `-SensitiveInfoTypeName` set is already in effect (default or
localized), instead of requiring the full list to be retyped by hand. Use for an organization whose
SharePoint/OneDrive estate is travel-document- or HR-record-heavy. **Before enabling for a U.K.-only
organization:** the "EU passport number" bundle has no standalone U.K. entity - U.K. passport coverage is
merged into a single combined "U.S./U.K. passport number" entity, so this switch also enables U.S.
passport-number detection as an inseparable side effect. The two opt-in bundles'
member-state coverage also isn't identical to each other or to the default national-ID bundle - see
the design notes for the full per-bundle membership table.

The deploy script resolves every name against `Get-DlpSensitiveInformationType` before creating or
updating any rule, and fails with a list of close matches if a name doesn't resolve exactly - see
the known limitations and the design notes for why this validation exists.

Full cmdlet parameter grounding: `deploy/New-EuPersonalDataAutoLabelPolicy.ps1` inline comments and
its `.NOTES` block.

## Operations and tuning

**Deployment sequence**: identical staged model to the sibling scenario - Off → simulation mode →
simulation mode reviewed for at least a business cycle (7+ days) → Enable.

**KPIs to watch (first 30-60 days):**
- **Labeled file volume vs. failure count**, from the policy's Overview page - same triage
  approach as the sibling scenario (checked-out files, unsupported formats, etc.).
- **Per-country match distribution** - if using the default EU-wide bundle, Activity Explorer's
  contextual summary can show which specific country's pattern matched a given file
  (keyword-highlighting is supported on these SITs, per each entity definition page). A tenant
  that only ever sees matches from 2-3 countries is a strong signal to consider narrowing to a
  per-country `-SensitiveInfoTypeName` list for tighter false-positive control, rather than
  running the full 26-country bundle indefinitely.
- **False-positive rate** - national ID formats with weak or no checksum validation carry a
  materially higher false-positive risk than checksum-validated formats like EU debit card number.
  the design notes now tables all 26 EU national ID bundle members: 19 are checksum-validated, 7 are
  pattern-only (Austria, Croatia, Cyprus, France, Greece, Malta, U.K.) - if a tenant's regulated
  population includes one of those 7, expect a higher false-positive rate from that country's
  matches specifically; track override/manual relabel activity in Activity Explorer.
- **Backlog coverage** - same on-demand classification recommendation as the sibling scenario for
  a tenant with years of existing content.
- **If `-IncludeTravelDocumentSits` is enabled**, watch its false-positive rate separately from the
  default condition set - the design notes tables both opt-in bundles and finds only 8% (passport)
  and 11% (driver's license) of their per-country entities are checksum-validated, versus 73% for
  the default national-ID bundle. Expect proportionally more manual overrides/relabels from these
  two SITs and narrow to specific countries via the configuration reference if the volume is high.

**Alert routing:** same as the sibling scenario - no DLP-style incident-report email; use the
policy's Overview/Labeled items/Labeling failures dashboard and Activity Explorer, or pull labeling
events via the Audit Search/Graph pattern in [Automation surface, section 4](/docs/automation-surface/#4-routing-table---which-surface-for-which-purview-task) for SIEM integration.

**Review cadence:** monthly for the first quarter, quarterly thereafter; re-run
`validate/Test-EuPersonalDataAutoLabelPolicy.ps1` each time to catch configuration drift,
**including drift in the configured `-SensitiveInfoTypeName` list itself** if it was ever narrowed
or widened after initial deployment (the validation script checks the exact set passed to it, not
just "some SIT is configured").

**Runbook - a file that should be labeled isn't:** identical triage sequence to the sibling
scenario (*Auto-Label Confidential PII in SharePoint & OneDrive* (operations and tuning)) - confirm evaluation-pass timing,
check the Labeled items → Failed view, distinguish "existing label, not overridden" from a real
failure, and confirm `EnableAIPIntegration` is still `$true` on the tenant. One EU-specific
addition: if a file that should match a **localized, narrowed** `-SensitiveInfoTypeName` list
isn't labeled, first confirm the file's country format is actually in the configured list (not the
full default bundle) before treating it as a policy failure.

## Rollback and decommission

See the rollback runbook for the full staged procedure (disable → simulation → permanent purge). Quick
reference: `./deploy/Remove-EuPersonalDataAutoLabelPolicy.ps1` disables (reversible); add `-Purge`
to permanently delete the policy and its rules.

## References

1. Automatically apply a sensitivity label to Microsoft 365 data - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically>
2. New-AutoSensitivityLabelRule reference (`-Workload` accepted values: Exchange, SharePoint, OneDriveForBusiness) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelrule>
3. Data Loss Prevention policy reference - "Content contains" supports multiple sensitive info types combined with "Any of these" (OR) or "All of these" (AND) - <https://learn.microsoft.com/purview/dlp-policy-reference#rules>
4. Automatically apply a sensitivity label to Microsoft 365 data - "Will an existing label be overridden?" - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#will-an-existing-label-be-overridden>
5. Automatically apply a sensitivity label to Microsoft 365 data - policy Overview / Labeled items / Labeling failures review pages - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#how-to-configure-auto-labeling-policies-for-sharepoint,-onedrive,-and-exchange>
6. Create custom sensitive information types - "These SITs can't be copied" list (names the EU-wide bundle SITs individually) - <https://learn.microsoft.com/purview/sit-create-a-custom-sensitive-information-type#before-you-begin>
7. EU national identification number entity definition (member list includes U.K. National Insurance Number) - <https://learn.microsoft.com/purview/sit-defn-eu-national-identification-number>
8. Automatically apply a sensitivity label to Microsoft 365 data - pre-flight checklist role requirements for turning on a policy - <https://learn.microsoft.com/purview/apply-sensitivity-label-automatically#before-you-begin>
9. Get-DlpSensitiveInformationType reference - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpsensitiveinformationtype>
10. EU Social Security Number (SSN) or Equivalent ID entity definition - <https://learn.microsoft.com/purview/sit-defn-eu-social-security-number-equivalent-identification>
11. EU debit card number entity definition - <https://learn.microsoft.com/purview/sit-defn-eu-debit-card-number>
12. New-AutoSensitivityLabelPolicy reference (`-Mode`, `-SharePointLocation`, `-OneDriveLocation`, `-SharePointLocationException`, `-OverwriteLabel`, `-ApplySensitivityLabel`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-autosensitivitylabelpolicy>

> Re-verify all links against current Microsoft Learn before a customer-facing assessment or
> sale - auto-labeling behavior and the SIT catalog have both changed more than once in this
> feature's history.