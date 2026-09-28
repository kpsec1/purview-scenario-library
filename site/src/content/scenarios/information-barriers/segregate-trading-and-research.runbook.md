---
part: "runbook"
parent: "information-barriers/segregate-trading-and-research"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 1. Dry run - prints the exact New-OrganizationSegment / New-InformationBarrierPolicy cmdlets
./deploy/New-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -DryRun

# 2. Create segments + block policies, INACTIVE (no user impact) - review before enforcing
./deploy/New-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json

# 3. Validate the staged objects
./validate/Test-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json

# 4. Activate + apply (BLOCKS live communication) - after Compliance/Legal sign-off
./deploy/New-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -Activate

# 5. Validate enforced state
./validate/Test-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -RequireActive
```

### Portal reference

Segments and policies are visible in the [Microsoft Purview portal](https://purview.microsoft.com) →
**Information Barriers** → **Segments** / **Policies** / **Policy application**.
`-WhatIf` is non-functional in S&C PowerShell, so the scripts ship a `-DryRun`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Segment cmdlet | `New-OrganizationSegment -Name -UserGroupFilter` | Attribute filter, e.g. `"Department -eq 'Trading'"` |
| Policy cmdlet | `New-InformationBarrierPolicy -AssignedSegment -SegmentsBlocked -State Inactive` | One-way block; `-SegmentsAllowed` for allow-lists |
| Policy naming | `<assigned>-block-<blocks>` | e.g. `Trading-block-Research` |
| Directions | Two policies (Trading→Research, Research→Trading) | A full wall needs both |
| Activate | `Set-InformationBarrierPolicy -Identity <GUID> -State Active` | Then apply |
| Apply | `Start-InformationBarrierPoliciesApplication` | Async: ~30 min to start, ~5,000 users/hour; SharePoint up to 24h |
| Status | `Get-InformationBarrierPoliciesApplicationStatus` | Track application progress |
| One policy per segment | Enforced by design | Never assign 2 policies to the same segment |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**Signals:** `Get-InformationBarrierPoliciesApplicationStatus` (application completion/errors);
segment membership counts (a segment that suddenly covers too many/too few users signals an attribute
data problem); IB troubleshooting cmdlets for "communication allowed when it should be blocked". **Tuning:** keep segments **mutually exclusive** - a user who ends up in both
Trading and Research breaks the wall; audit the source attribute regularly. New joiners/movers get
walled automatically as their attribute changes and the next application runs, so keep the attribute
authoritative and re-apply on cadence.

**Change management:** activation is a controlled, Compliance/Legal-approved change (it removes people
from conversations). Communicate before enforcing. Keep the config file under version control as the
record of the wall's definition for audit/exam.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-TradingResearchBarrier.ps1` sets the policies
**Inactive**; add `-Apply` to run the application so the wall is actually **lifted**; add `-Delete` to
remove the policies and segments. Lifting an ethical wall re-enables communication that may carry
regulatory obligations - do it only with Compliance/Legal confirmation.

## References

1. Get started with Information Barriers (segments, block/allow policies, apply, one-policy-per-segment) - <https://learn.microsoft.com/purview/information-barriers-policies>
2. Use multi-segment support in Information Barriers (IB modes, segment limits) - <https://learn.microsoft.com/purview/information-barriers-multi-segment>
3. New-OrganizationSegment (`-UserGroupFilter`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-organizationsegment>
4. New-InformationBarrierPolicy (`-AssignedSegment`, `-SegmentsBlocked`/`-SegmentsAllowed`, `-State`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-informationbarrierpolicy>
5. Start-InformationBarrierPoliciesApplication / Get-InformationBarrierPoliciesApplicationStatus - <https://learn.microsoft.com/powershell/module/exchangepowershell/start-informationbarrierpoliciesapplication>
6. Attributes for information barrier policies - <https://learn.microsoft.com/purview/information-barriers-attributes>
7. Microsoft Purview service description - Information Barriers licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. Use Information Barriers with SharePoint (enablement, 24h propagation, app-only bypass) - <https://learn.microsoft.com/purview/information-barriers-sharepoint>
9. Information Barriers in Microsoft Teams (block behavior) - <https://learn.microsoft.com/purview/information-barriers-teams>
10. Resolve communication issues in Information Barriers (troubleshooting) - <https://learn.microsoft.com/troubleshoot/microsoft-365/purview/information-barriers/information-barriers-troubleshooting>
11. Manage / edit segments and policies (deactivate, remove) - <https://learn.microsoft.com/purview/information-barriers-edit-segments-policies>

> Re-verify all links, cmdlet parameters, licensing, IB modes, and the propagation timings against
> current Microsoft Learn before a customer-facing deployment. Activation changes live communication -
> stage inactive, review, and get Compliance/Legal sign-off first.