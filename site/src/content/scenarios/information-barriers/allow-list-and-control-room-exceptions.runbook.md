---
part: "runbook"
parent: "information-barriers/allow-list-and-control-room-exceptions"
---
## Implementation steps

### PowerShell path

```powershell
# Connect (certificate app-only preferred - Automation surface, section 3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 0. Prerequisite: segregate-trading-and-research must already be deployed (Trading/Research segments exist)

# 1. Dry run - prints the exact New-/Set-OrganizationSegment / New-/Set-InformationBarrierPolicy cmdlets
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json -DryRun

# 2. Create/reconcile segments + allow policies, INACTIVE (no user impact) - review before enforcing
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json

# 3. Validate the staged objects
./validate/Test-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json

# 4. Activate + apply (restricts the exception segments to their allow-lists) - after sign-off
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json -Activate

# 5. Validate enforced state
./validate/Test-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json -RequireActive

# --- Later: add a segment to an existing allow-list (e.g. Legal must now also see Trading) ---
# Edit deploy/config/control-room-allow-exceptions.json: "Legal" -> "allows": ["Research", "Trading"]
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json -DryRun   # see the reconciliation diff
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json           # reconciles, leaves Inactive if it was Active
./deploy/New-ControlRoomAllowException.ps1 -ConfigPath ./deploy/config/control-room-allow-exceptions.json -Activate # reactivate + re-apply
```

### Portal reference

Segments and policies are visible in the [Microsoft Purview portal](https://purview.microsoft.com) →
**Information Barriers** → **Segments** / **Policies** / **Policy application**. `-WhatIf` is non-functional in S&C PowerShell, so the scripts ship a `-DryRun`.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Segment cmdlet | `New-OrganizationSegment -Name -UserGroupFilter` | Same as the base scenario |
| Policy cmdlet (create) | `New-InformationBarrierPolicy -AssignedSegment -SegmentsAllowed -State Inactive` | Comma-separated list; cannot combine with `-SegmentsBlocked` |
| Policy cmdlet (reconcile) | `Set-InformationBarrierPolicy -Identity -SegmentsAllowed` | Set the policy **Inactive first** if it's Active before editing |
| Policy naming | `<assignedSegment>-allow-<allows, joined by '-'>` | e.g. `ComplianceControlRoom-allow-Trading-Research`, `Legal-allow-Research` |
| Allow-list shapes modeled | "Sees both sides" (`ComplianceControlRoom`) and "one-sided" (`Legal`) | Same mechanism, different `allows` list - the pattern generalizes to any number of exception segments |
| Activate | `Set-InformationBarrierPolicy -Identity <GUID> -State Active` | Then apply |
| Apply | `Start-InformationBarrierPoliciesApplication` | Async: ~30 min to start, ~5,000 users/hour; SharePoint up to 24h |
| Status | `Get-InformationBarrierPoliciesApplicationStatus` | Track application progress |
| Policy type immutability | Can't convert Allow<->Block in place | Deactivate + create a new policy of the other type instead |
| One policy per segment | Enforced by design | Never assign 2 policies to the same segment |

Exact cmdlet syntax and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**Signals:** `Get-InformationBarrierPoliciesApplicationStatus` (application completion/errors);
exception-segment membership counts (an exception segment that grows unexpectedly signals scope
creep in "who needs to see across the wall"); the validate script's live-vs-desired `SegmentsAllowed`
diff (a Fail here after a deploy means an edit didn't take, or was applied out of band via the
portal). **Tuning:** review exception-segment membership on the same cadence as the wall itself -
every added member widens who can cross it. Treat a growing `ComplianceControlRoom` as a finding, not
a convenience: exceptions should be as narrow as the supervisory function actually requires (`Legal`'s
one-sided allow-list is the model to prefer over "sees everything" unless the role genuinely needs
both sides).

**Detecting misuse of the exception is out of this scenario's scope** - IB stops *unauthorized*
communication; whether an authorized `ComplianceControlRoom` member is *using* their cross-wall access
appropriately is a DLP/Activity Explorer/insider-risk concern layered on top, not an IB policy setting.

**Change management:** every allow-list edit is a Compliance/Legal-reviewable change (it's a
diffable JSON entry). Keep the config file under version control as the record of who has standing
cross-wall access and why, for audit/exam.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-ControlRoomAllowException.ps1` sets the allow
policies **Inactive**; add `-Apply` to run the application so the exception is actually **revoked**;
add `-Delete` to remove the policies and exception segments. The `Trading`/`Research` wall itself is
never touched by this scenario's rollback.

## References

1. Get started with Information Barriers (Allow/Block policies, one-policy-per-segment, and the compatible-third-segment worked example) - <https://learn.microsoft.com/purview/information-barriers-policies>
2. Use multi-segment support in Information Barriers (IB modes, segment limits, "configuring any Block policy breaks multi-segment"; Legacy mode + Allow policy hides non-IB users/groups from the assigned segment, unlike SingleSegment/MultiSegment) - <https://learn.microsoft.com/purview/information-barriers-multi-segment>
3. New-OrganizationSegment (`-UserGroupFilter`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-organizationsegment>
4. New-InformationBarrierPolicy (`-AssignedSegment`, `-SegmentsAllowed`/`-SegmentsBlocked` - cannot combine, `-State`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/new-informationbarrierpolicy>
5. Start-InformationBarrierPoliciesApplication / Get-InformationBarrierPoliciesApplicationStatus - <https://learn.microsoft.com/powershell/module/exchangepowershell/start-informationbarrierpoliciesapplication>
6. Attributes for information barrier policies - <https://learn.microsoft.com/purview/information-barriers-attributes>
7. Microsoft Purview service description - Information Barriers licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
8. Use Information Barriers with SharePoint (enablement, 24h propagation) - <https://learn.microsoft.com/purview/information-barriers-sharepoint>
9. Information Barriers in Microsoft Teams (block/allow behavior) - <https://learn.microsoft.com/purview/information-barriers-teams>
10. Resolve communication issues in Information Barriers (troubleshooting) - <https://learn.microsoft.com/troubleshoot/microsoft-365/purview/information-barriers/information-barriers-troubleshooting>
11. Manage/edit segments and policies (deactivate-before-edit workflow; can't change policy type in place; Set-InformationBarrierPolicy `-SegmentsAllowed`/`-SegmentsBlocked`) - <https://learn.microsoft.com/purview/information-barriers-edit-segments-policies>
12. Get-PolicyConfig / Set-PolicyConfig (`-InformationBarrierMode`: Legacy/SingleSegment/MultiSegment) - <https://learn.microsoft.com/powershell/module/exchangepowershell/get-policyconfig>

> Re-verify all links, cmdlet parameters, licensing, IB modes, and the replace-vs-merge
> `-SegmentsAllowed` semantics against current Microsoft Learn (and a pilot tenant) before a
> customer-facing deployment. Activation changes live communication for the exception segments -
> stage inactive, review, and get Compliance/Legal sign-off first.