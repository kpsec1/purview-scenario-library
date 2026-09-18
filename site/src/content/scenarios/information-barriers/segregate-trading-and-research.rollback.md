---
part: "rollback"
parent: "information-barriers/segregate-trading-and-research"
---
## ⚠️ Read first: lifting an ethical wall is a compliance decision

The wall exists to satisfy a conflict-of-interest obligation (FINRA 2241, SEC Reg AC, MiFID II).
**Removing it re-enables communication that may be regulated.** Do not run any stage of this rollback
until **Compliance/Legal confirm** the wall is no longer required. When in doubt, keep the wall.

## Recommended sequence

Deactivation only takes effect for users after a policy-**application** run — so lifting the wall is a
two-part act: set the policies inactive, then apply.

### Stage 1 — Deactivate and lift the wall

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -DryRun
./deploy/Remove-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -Apply
```

Sets both block policies `Inactive` and runs `Start-InformationBarrierPoliciesApplication`, so the
block is actually lifted tenant-wide (asynchronous; SharePoint/OneDrive up to 24h). The segments and
the (now inactive) policy objects remain, so the wall can be re-enforced quickly by re-running the
deploy with `-Activate`. Use this to pause the wall (e.g. a reorganization) without discarding the
definition.

Without `-Apply`, the policies are marked inactive but **users are still blocked** until an application
run occurs — the script warns about this. Always `-Apply` when you actually intend to lift the wall.

### Stage 2 — Delete the policies and segments

```powershell
./deploy/Remove-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json -Apply -Delete
```

Lifts the wall (Stage 1) and then deletes the block policies (`Remove-InformationBarrierPolicy`) and
the segments (`Remove-OrganizationSegment`). Re-establishing the wall then means re-running the full
deploy. Use this only when the wall is being permanently retired.

## What rollback does **not** undo

- **Anything that happened while the wall was up.** Removed chat memberships, blocked access — lifting
  the wall restores future communication, it doesn't retroactively recreate conversations that were
  disabled.
- **SharePoint/OneDrive IB enablement** (if you enabled it separately) — disable that via its own
  configuration if fully decommissioning.
- **The source directory attribute** used for segmentation — untouched; the wall's segmentation logic
  lives in that attribute, which you manage independently.
- **Audit records** of the IB configuration and application runs — retained per their own policy.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-TradingResearchBarrier.ps1 -ConfigPath ./deploy/config/trading-research-barrier.json
```

After **Stage 1**, expect the policies to exist but be `Inactive` (the "state is Active" check `[WARN]`s
without `-RequireActive`), and a fresh application run to be reported. After **Stage 2**, expect the
segment and policy existence checks to `[FAIL]` — confirming removal. Then confirm in Teams that a
Trading and a Research user can communicate again (allow up to 24h for SharePoint).
