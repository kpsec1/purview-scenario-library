---
part: "rollback"
parent: "information-barriers/sharepoint-onedrive-enablement-and-site-association"
---
## ⚠️ Read first: prefer narrowing over suspending

This scenario has two independent things to roll back, at very different blast radii:

- **Site associations** (this scenario's own additions), narrow, reversible, no impact beyond
 the specific sites you configured.
- **Tenant-wide enablement**, broad: suspending it drops IB enforcement for **every** SharePoint
 site and **every** OneDrive account tenant-wide, including the Teams-connected (Implicit mode)
 sites that `../segregate-trading-and-research/`'s wall already protects automatically.

**Default to removing only this scenario's site associations.** Only suspend the tenant-wide
switch if you are decommissioning SharePoint/OneDrive IB coverage entirely, e.g. the whole
ethical wall (Teams included) is being retired, and confirm that decision with Compliance/Legal
first, the same way you would before lifting `segregate-trading-and-research` itself.

## Recommended sequence

### Stage 1, Remove this scenario's site associations

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
Connect-SPOService -Url https://contoso-admin.sharepoint.com -ClientId $AppId -Certificate $Cert

./deploy/Set-SiteInformationSegments.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json -RemoveConfigured -DryRun
./deploy/Set-SiteInformationSegments.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json -RemoveConfigured
```

Removes exactly the segments this config associated. A site reverts to **Open** mode if that was
its last remaining segment; a site with other segments this config didn't add keeps them. Teams-
connected sites and OneDrive are untouched (they were never managed by this scenario's site-segment
script in the first place).

This is the right stopping point if you're only decommissioning this scenario's specific site
coverage while keeping the tenant-wide switch and the parent Teams wall intact.

### Stage 2, Suspend tenant-wide enablement (full decommission only)

```powershell
./deploy/Set-SharePointOneDriveIBEnablement.ps1 -DryRun -Suspend
./deploy/Set-SharePointOneDriveIBEnablement.ps1 -Suspend
```

Sets `InformationBarriersSuspension = $true` tenant-wide. This **also lifts IB enforcement on
Teams-connected sites and all OneDrive accounts**, not just what Stage 1 touched. Use this only
when SharePoint/OneDrive IB coverage is being retired entirely, with the same Compliance/Legal
confirmation `segregate-trading-and-research/rollback.md` requires before lifting the underlying
wall.

Re-enabling later (`./deploy/Set-SharePointOneDriveIBEnablement.ps1`, no `-Suspend`) restores
enforcement from the still-existing segments/policies, this scenario's site associations survive
a suspend (they're read from live `Get-SPOSite` state, not deleted), so an accidental Stage 2 can
be undone by simply re-enabling rather than re-running Stage 1's site associations.

## What rollback does **not** undo

- **The underlying IB segments and block policies**, those belong to
 `../segregate-trading-and-research/`; roll that scenario back separately if the whole wall is
 being retired.
- **Anything that happened while a site was Explicit-mode.** Sharing/access that was blocked stays
 blocked in the past; rollback restores future access, it doesn't retroactively recreate declined
 shares.
- **Audit records** of the enablement, association, and removal actions, retained per their own
 policy; see `README.md` §8.

## Verification after rollback

```powershell
./validate/Test-SharePointOneDriveInformationBarrierSetup.ps1 -ConfigPath ./deploy/config/sharepoint-site-segments.json -AllowSuspended
```

After **Stage 1**, expect the per-site segment-association checks to `[FAIL]` (confirming removal)
while tenant enablement still `[PASS]`es. After **Stage 2**, pass `-AllowSuspended` so the tenant
check `[WARN]`s instead of hard-failing, and confirm in the portal that a Trading and a Research
user can now access each other's SharePoint/OneDrive content again (allow up to the same
propagation windows as enablement).
