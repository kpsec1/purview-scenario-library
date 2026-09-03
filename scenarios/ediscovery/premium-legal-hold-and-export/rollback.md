# Rollback — eDiscovery (Premium) Legal Hold, Collection & Export

## ⚠️ Read first: releasing a legal hold is a legal act

A legal hold preserves evidence for litigation or investigation. **Releasing it prematurely can be
spoliation**, with real sanctions. Do not run any stage of this rollback until **Legal confirms** the
preservation obligation for this matter is over. When in doubt, keep the hold.

## Recommended sequence

### Stage 1 — Release the legal hold (reversible in effect: re-deploy re-enables)

```powershell
Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
./deploy/Remove-EdiscoveryHoldAndCollect.ps1 -ConfigPath ./deploy/config/legal-hold-case.json -WhatIf
./deploy/Remove-EdiscoveryHoldAndCollect.ps1 -ConfigPath ./deploy/config/legal-hold-case.json
```

Sets the legal hold `isEnabled = false` (PATCH) — preservation-in-place ends, but the hold object,
the case, custodians, the collection search, and any collected/exported content all remain. Re-enable
by re-running `New-EdiscoveryHoldAndCollect.ps1` (which recreates/enables the hold). Use `-WhatIf`
first — this is the one rollback you most want to preview.

### Stage 2 — Delete the hold and collection search

```powershell
Connect-MgGraph -Scopes 'eDiscovery.ReadWrite.All'
./deploy/Remove-EdiscoveryHoldAndCollect.ps1 -ConfigPath ./deploy/config/legal-hold-case.json -Delete
```

Releases the hold (Stage 1) and then **deletes** the legal hold and the collection search objects.
Collected content, review sets, and exports are **not** deleted.

### Stage 3 — Release custodians and close the case (portal, governed)

This scenario deliberately does **not** script releasing custodians or closing/deleting the case —
those actions end a legal matter and should be performed deliberately, with Legal's confirmation, in
the [Microsoft Purview portal](https://purview.microsoft.com):
- **Release custodians** (removes their case-level hold) on the case's **Data sources / Custodians**
  tab.
- **Close** (and later delete, if retention policy allows) the case from the case settings.

## What rollback does **not** undo

- **Collected content, review sets, and exports.** Anything already collected into a review set or
  exported is preserved — rollback never deletes evidence or work product. Manage exported packages
  (which may contain PII/privileged material) under your matter's data-handling rules.
- **The case, custodians, and custodian source associations.** Left intact by the scripted stages;
  handled in Stage 3 in the portal.
- **Audit trail.** eDiscovery activity in the Microsoft Purview audit log is retained per its own
  policy and is not affected.
- **The definition file.** Keep it in version control as the record of how this matter was scoped,
  even after the case is closed.

## Verification after rollback

```powershell
Connect-MgGraph -Scopes 'eDiscovery.Read.All'
./validate/Test-EdiscoveryHoldAndCollect.ps1 -ConfigPath ./deploy/config/legal-hold-case.json
```

After **Stage 1**, expect the "Legal hold is enabled" check to `[FAIL]` (hold released) while the
case/custodian/search existence checks still `[PASS]`. After **Stage 2**, expect the hold and search
existence checks to `[FAIL]`. Confirm custodian hold status and case state in the portal after Stage 3.
