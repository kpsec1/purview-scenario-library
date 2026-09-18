---
part: "rollback"
parent: "data-lifecycle-management/publish-labels-for-manual-application"
---
## Read first: this only controls whether the label is offered — never the label itself

This scenario's scripts never create, edit, or delete a retention label. Rollback here can only
stop the label from being **offered** for *new* manual applications — it can never recall a label a
user already applied, and it has no code path capable of touching the label object at all (contrast
the auto-apply sibling's `-TryRemoveLabel` option, which this scenario deliberately does not have).

## Recommended sequence

### Stage 1 — Disable the publish policy (stops offering the label to new selections)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json -DryRun
./deploy/Remove-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json
```

Sets the policy `-Enabled $false`. Users in the scoped locations stop seeing the label as an option
in Outlook/SharePoint/OneDrive/Teams going forward. Items already labeled keep their label and
retention. Reversible: re-run the deploy to re-enable.

### Stage 2 — Delete the publish policy and rule

```powershell
./deploy/Remove-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json -Delete
```

Removes the policy (and its rule). Still does **not** un-label any content. Use when this
distribution mechanism is being retired for this label/location set — e.g. because a different
publish policy now covers the same label, or the label is being retired.

## What rollback does **not** undo

- **Any content a user already labeled.** The label and its retention settings stay exactly as they
  were before this rollback — publishing/unpublishing never touches applied labels.
- **The label object itself** — this scenario has no mechanism to create, edit, or delete it in the
  first place. See the sibling `retention-labels-financial-records/rollback.md` for that lifecycle.
- **Regulatory record restrictions.** If the published label is a regulatory record and a user
  applied it, that content is immutable regardless of what happens to this policy — unpublishing
  removes the *future* ability to apply it, not the *past* application.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-PublishRetentionLabelPolicy.ps1 -ConfigPath ./deploy/config/publish-financial-records-label.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]` while the label and rule still
exist. After **Stage 2**, expect the policy/rule existence checks to `[FAIL]`. The label existence
check `[PASS]`es throughout — this scenario never affects it.
