---
part: "runbook"
parent: "information-barriers/sharepoint-onedrive-enablement-and-site-association"
---
## Implementation steps

### PowerShell path

```powershell
# Connect both surfaces (certificate app-only preferred - Automation surface Section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientId $AppId -Certificate $Cert

# 0. Confirm the parent scenario's policies are Active and applied (24h propagated)
../segregate-trading-and-research/validate/Test-TradingResearchBarrier.ps1 -RequireActive

# 1. Dry run - tenant enablement
./deploy/Set-SharePointOneDriveIBEnablement.ps1 -DryRun

# 2. Enable SharePoint/OneDrive IB tenant-wide (~1 hour to take effect)
./deploy/Set-SharePointOneDriveIBEnablement.ps1

# 3. Dry run - site segment association
./deploy/Set-SiteInformationSegments.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json -DryRun

# 4. Associate segments with the configured standalone sites
./deploy/Set-SiteInformationSegments.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json

# 5. Validate
./validate/Test-SharePointOneDriveInformationBarrierSetup.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json
```

### Portal reference

Segments-per-site are visible in the [SharePoint admin center](https://admin.microsoft.com) →
**Active sites** → select a site → **Settings** tab; the tenant-wide switch has no portal toggle -
it's SharePoint Online Management Shell only. `-WhatIf` is non-functional in
this module, so both scripts ship a `-DryRun`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Tenant enablement | `Set-SPOTenant -InformationBarriersSuspension $false` | Enables SharePoint **and** OneDrive IB together - cannot be enabled separately |
| Tenant suspend (rollback) | `Set-SPOTenant -InformationBarriersSuspension $true` | Tenant-wide; drops enforcement on Teams-Implicit sites too - the rollback plan and the known limitations |
| Segment lookup | `Get-OrganizationSegment \| ft Name, EXOSegmentID` | Security & Compliance PowerShell (surface 2); this scenario's scripts also fall back to `.Guid` - the known limitations |
| Add segment to site | `Set-SPOSite -Identity <url> -AddInformationSegment <GUID>` | Sets the site's mode to Explicit; up to 100 compatible segments per site |
| Remove segment from site | `Set-SPOSite -Identity <url> -RemoveInformationSegment <GUID>` | Reverts to Open if it was the site's last segment |
| Read site segments | `Get-SPOSite -Identity <url> \| Select InformationSegment` | Returns associated segment GUIDs |
| Read site IB mode | `Get-SPOSite -Identity <url> \| Select InformationBarriersMode` | `Open` / `Owner Moderated` / `Implicit` / `Explicit` |
| App-only bypass (not enabled by default) | `Set-SPOTenant -AppBypassInformationBarriers $true` | Opt-in; widens the wall's exceptions - the known limitations |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**Signals:** the seven audit activities Microsoft documents for SharePoint IB - enabling/disabling
tenant-wide, and applying/changing/removing a segment or IB mode on a site - are logged and visible
via the Microsoft Purview portal audit log; the exact `Search-UnifiedAuditLog`
`RecordType`/`Operations` values for scripted export aren't confirmed in this build (the known limitations, a
follow-up shared with the parent scenario's own open audit-trail item). **Tuning:** re-run
`Set-SiteInformationSegments.ps1` whenever a new standalone site is provisioned for either side -
this scenario does not auto-discover new sites; use the Information Barriers
policy compliance report to catch sites that fall out of compliance after a segment/policy change.

**Change management:** treat both the tenant-enablement step and each site association with the
same Compliance/Legal sign-off used for the parent scenario's `-Activate` - associating a segment
with a live, in-use site immediately narrows who can access it.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Set-SiteInformationSegments.ps1 -RemoveConfigured`
removes this scenario's own site associations (sites revert to Open if that was their last
segment); `./deploy/Set-SharePointOneDriveIBEnablement.ps1 -Suspend` suspends the tenant-wide
switch - **only for a full decommission**, since it also drops enforcement on the Teams-Implicit
sites the parent scenario protects.

## References

1. Use Information Barriers with SharePoint (enablement, site/segment association, modes, audit activities, suspend) - <https://learn.microsoft.com/purview/information-barriers-sharepoint>
2. Get started with Information Barriers - Step 5 (SharePoint/OneDrive configuration overview) - <https://learn.microsoft.com/purview/information-barriers-policies#step-5-configure-information-barriers-on-sharepoint-and-onedrive>
3. Set-SPOTenant (`-InformationBarriersSuspension`, `-IBImplicitGroupBased`, `-AppBypassInformationBarriers`, `-DefaultOneDriveInformationBarrierMode`) - <https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/set-spotenant>
4. Set-SPOSite (`-InformationBarriersMode`) - <https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/set-sposite>
5. Get-SPOTenant reference (no documented parameters; output properties not exhaustively listed) - <https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/get-spotenant>
6. `../segregate-trading-and-research/` - the parent scenario this one extends (segments, block policies, activation).
7. Microsoft Purview service description - Information Barriers licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. Use Information Barriers with SharePoint - Explicit mode access/sharing behavior - <https://learn.microsoft.com/purview/information-barriers-sharepoint#explicit-mode>
9. Use Information Barriers with OneDrive (modes, automatic Explicit-mode protection within 24h) - <https://learn.microsoft.com/purview/information-barriers-onedrive>
10. Use Information Barriers with SharePoint - Auditing (the seven logged activities) - <https://learn.microsoft.com/purview/information-barriers-sharepoint#auditing>
11. Learn how to create an Information Barriers policy compliance report in PowerShell - <https://learn.microsoft.com/purview/information-barriers-sharepoint-report>

> Re-verify all links, cmdlet parameters, property names (the known limitations VERIFY items), and propagation
> timings against current Microsoft Learn before a customer-facing deployment. Both enabling the
> tenant switch and associating a segment with a live site change real access/sharing behavior -
> stage with `-DryRun`, review, and get Compliance/Legal sign-off first.