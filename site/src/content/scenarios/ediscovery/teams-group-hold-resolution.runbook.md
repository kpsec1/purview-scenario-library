---
part: "runbook"
parent: "ediscovery/teams-group-hold-resolution"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Get the group's mailbox and site**: Purview eDiscovery hold-creation flow itself resolves a
   Team/group's mailbox and site automatically when you add it as a data source - no separate
   lookup is needed in the portal (**Create a hold** → **Manage data sources** → search by group
   name). This scenario's script exists for the **automation** path, where a
   Team name arrives from an intake ticket or case-management system and the caller needs the
   underlying mailbox/site values to build a hold-definition file programmatically.
2. **Confirm via Exchange Online PowerShell** (equivalent to what the script does): `Get-UnifiedGroup
   "<Team name>" | FL DisplayName,Alias,PrimarySmtpAddress,SharePointSiteUrl`.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect to Exchange Online (surface 1 -- this scenario's scripts do not connect for you).
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization $TenantDomain

# 2. Resolve every declared group's mailbox/site (read-only; -WhatIf still writes nothing to disk).
./deploy/Resolve-TeamsGroupHoldLocations.ps1 `
    -DefinitionPath ./deploy/config/teams-group-hold-resolution.sample.json -WhatIf

# 3. Resolve for real -- writes deploy/out/teams-group-hold-locations.resolved.json (gitignored).
./deploy/Resolve-TeamsGroupHoldLocations.ps1 `
    -DefinitionPath ./deploy/config/teams-group-hold-resolution.sample.json

# 4a. Merge the resolved fragment into location-scoped-legal-hold's definition file by hand, then
# run that sibling scenario's own deploy script -- OR --
# 4b. Reconcile directly onto an already-existing hold policy:
./deploy/Resolve-TeamsGroupHoldLocations.ps1 `
    -DefinitionPath ./deploy/config/teams-group-hold-resolution.sample.json `
    -AddToHold -CaseId $caseId -HoldId $holdId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf
# then re-run without -WhatIf once the plan looks right.

# 5. Validate.
./validate/Test-TeamsGroupHoldLocations.ps1 `
    -DefinitionPath ./deploy/config/teams-group-hold-resolution.sample.json `
    -CaseId $caseId -HoldId $holdId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

## Configuration reference

| Field (`deploy/config/teams-group-hold-resolution.sample.json`) | Meaning |
|---|---|
| `groups[].identity` | Any value `Get-UnifiedGroup -Identity` accepts - display name, alias, or SMTP address |
| `groups[].resolveMembers` | Optional, default `false`. If `true`, also runs `Get-UnifiedGroupLinks -LinkType Members` and writes a member-roster CSV (informational only - the known limitations) |

| Output object | Written by | Shape |
|---|---|---|
| Resolved hold-location fragment | `Resolve-TeamsGroupHoldLocations.ps1` (always) | `{ "userSources": [{ "email": "..." }], "siteSources": [{ "site": "..." }] }` - the exact `userSources[]`/`siteSources[]` shape *Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)*'s definition file uses |
| Member roster CSV | `Resolve-TeamsGroupHoldLocations.ps1` (only if any group requests `resolveMembers`) | `Group, MemberDisplayName, MemberPrimarySmtpAddress` - one row per current member, per group |

`Get-UnifiedGroup` properties this script reads: `DisplayName`, `Alias`, `PrimarySmtpAddress`,
`SharePointSiteUrl`. Graph endpoints used by `-AddToHold` (identical to the
sibling scenario's - full grounding there): `POST .../legalHolds/{id}/userSources`,
`POST .../legalHolds/{id}/siteSources`.

## Operations and tuning

**KPIs to watch:**
- **A group's `resolved.json` entry going stale** - re-run `Resolve-TeamsGroupHoldLocations.ps1`
  (and, if the group is already on a hold, `-AddToHold` again) whenever a group's mailbox alias or
  SharePoint site URL changes; `validate/Test-TeamsGroupHoldLocations.ps1`'s drift check exists
  specifically to catch this without requiring a human to remember every group's original resolved
  values.
- **A SharePoint-site-provisioning `WARN`** persisting across multiple runs - see this scenario's
  open VERIFY on provisioning timing; treat a `WARN` that doesn't clear within a working day
  as worth investigating directly in the SharePoint admin center rather than continuing to re-run
  this script on a fixed interval.

**Review cadence:** re-run `validate/Test-TeamsGroupHoldLocations.ps1` on the same cadence as the
sibling scenario's own hold-status checks (*Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)* (operations and tuning) - at least
weekly for the life of the matter), since this scenario's output feeds directly into that hold.

**What this scenario deliberately does not monitor:** individual member mailboxes/OneDrive
accounts, and any chat/1:1 content stored outside the group mailbox and site - see the known limitations and
the design notes.

## Rollback and decommission

See the rollback runbook. Quick reference: this scenario's own resolve-only output (the JSON fragment and
CSV roster) are plain files with no tenant-side effect - delete them locally with no further action.
If `-AddToHold` was used, releasing the group's mailbox/site from the hold is the sibling scenario's
own `deploy/Remove-EdiscoveryLocationHold.ps1 -UserSourceEmail`/`-SiteSourceUrl`, not a script this
scenario ships separately - see the rollback runbook for why.

## References

1. Get-UnifiedGroup (Exchange PowerShell reference - `SharePointSiteUrl`, View-Only Recipients role requirement) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-unifiedgroup>
2. Get-UnifiedGroupLinks (Exchange PowerShell reference - `-LinkType`, View-Only Recipients role requirement) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-unifiedgrouplinks>
3. Create holds in eDiscovery - "Create a hold" (group-as-data-source expansion, 100-member cap, point-in-time snapshot) and "Preserve content in Microsoft Teams" / "Microsoft 365 groups" (Get-UnifiedGroup/Get-UnifiedGroupLinks worked example) - <https://learn.microsoft.com/purview/edisc-hold-create>
4. Create userSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-usersources?view=graph-rest-1.0>
5. Create siteSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-sitesources?view=graph-rest-1.0>
6. Manage holds in eDiscovery - "Place a hold on Microsoft Teams and Microsoft 365 groups" - <https://learn.microsoft.com/purview/edisc-hold-manage#place-a-hold-on-microsoft-teams-and-microsoft-365-groups>
7. Groups page in the Microsoft 365 admin center - <https://go.microsoft.com/fwlink/p/?linkid=2052855>
8. Microsoft 365 Group behaviors and provisioning options (`resourceBehaviorOptions.ProvisionSiteOnDemand`) - <https://learn.microsoft.com/graph/group-set-options>
9. *Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)* - the sibling scenario this fragment feeds; see its own page the references for the full `ediscoveryHoldPolicy` v1.0 REST citation set (case/hold/userSource/siteSource create, retry, delete) not repeated here.
10. Manage holds in eDiscovery - "Manage hold status errors" ("Distribution group has too many members," >1,000 addresses; current page, re-fetched 2026-09-04) - <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment -
> Purview's Graph eDiscovery surface has moved namespaces within the product's own history. The
> 100-member vs. >1,000-member group-expansion figures were re-grounded on 2026-09-04 and
> found to be two distinct, current, unreconciled figures - not a stale-vs-current pair - so treat
> the smaller (100-member) figure as the conservative planning threshold until a pilot tenant
> confirms otherwise.