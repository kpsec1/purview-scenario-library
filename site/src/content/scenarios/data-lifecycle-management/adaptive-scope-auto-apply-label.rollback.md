---
part: "rollback"
parent: "data-lifecycle-management/adaptive-scope-auto-apply-label"
---
## Higher irreversibility than the Keep-only sibling — read first

This scenario deploys a **record** retention label (`IsRecordLabel: true`), not a Keep-only
retention action. Per Microsoft's own documented behavior, an applied record label can only be
unlocked or removed by a user with **records-manager** privilege [[1]](#references) — unlike the
`adaptive-scope-retention` sibling, where removing the rule "causes the release of all Exchange
mailbox and SharePoint site retentions that are associated with the rule." **Rolling back this
scenario's policy/rule does not unlock or remove any record label already applied to content** — it
only stops **future** auto-apply. Plan for records-manager involvement if content was ever
mis-labeled; this rollback script cannot substitute for that.

## Recommended sequence

### Stage 1 — Disable the policy (default; stops new content from being auto-labeled)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json -DryRun
./deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json
```

Sets the policy `-Enabled $false`. The scope, label, policy, and rule all still exist — this only
pauses **future** auto-apply. Content already labeled is unaffected either way. Fully reversible:
re-run the deploy script to re-enable. Use this to pause a mis-scoped rollout while you fix the
adaptive scope's query — before more content gets locked, not to undo content already locked.

### Stage 2 — Delete the policy and rule

```powershell
./deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json -Delete
```

`Remove-RetentionCompliancePolicy` removes the policy **and its rule together** [[2]](#references).
This stops future auto-apply entirely. **It does not touch the label definition or any content
already labeled** — those require separate, deliberate action (see below).

### Stage 3 — Also remove the adaptive scope (optional)

```powershell
./deploy/Remove-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json -Delete -TryRemoveScope
```

Attempts `Remove-AdaptiveScope`. **Check first whether the `adaptive-scope-retention` sibling (or
any other policy) still references the same scope name** — this scenario's config defaults to
sharing that scope by design (`design.md` §2). Removing it here would also break the Keep-only
sibling's coverage if both are deployed. The script reports a failure rather than forcing it; pass
`-ForceScopeDeletion` only after confirming in the portal (**Settings** > **Roles and scopes** >
**Adaptive scopes**) that nothing else needs it.

## Unlocking or removing an already-applied record label (not automated here)

This is deliberately **not** scripted in this scenario — it is a higher-consequence, records-manager
action, distinct from policy/rule rollback:

1. Confirm the specific items that were mis-labeled (content search scoped to the label, or the
   portal's Records Management reporting).
2. A user with the **Records Management** role group (or **RecordManagement** sub-role) can remove
   the record label from specific content, or (with the appropriate file-plan permission) change the
   label's own definition [[3]](#references).
3. **This is not possible at all if the label was ever created with `Regulatory: true`** — a
   regulatory record cannot be removed by anyone, including a Global Administrator, once applied
   [[1]](#references). This scenario's default config uses a plain (non-regulatory) record precisely
   so this recovery path stays available — do not change `label.regulatory` to `true` without
   understanding this is a one-way door.

## What rollback does **not** undo

- **Any record already applied to content.** Policy/rule rollback stops future labeling only — see
  above for the separate, manual, records-manager-gated recovery path.
- **A regulatory record, ever, by anyone** — not applicable to this scenario's default config, but
  relevant if you changed `label.regulatory` to `true` and then used the publish sibling to
  distribute it.
- **The distribution/population delay on the way back in.** Re-enabling the policy or re-creating the
  scope restarts the same up-to-5-day (scope) and up-to-7-day (auto-apply distribution) delays
  documented in `README.md` §6/§7 — rollback is not instant to reverse either.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-AdaptiveScopeAutoApplyLabel.ps1 -ConfigPath ./deploy/config/adaptive-scope-auto-apply-label.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]` while the scope, label, policy,
and rule all still `[PASS]` as existing. After **Stage 2**, expect the policy/rule existence checks to
`[FAIL]` while the scope and label checks still `[PASS]`. After **Stage 3**, the scope check `[FAIL]`s
too. None of these stages will ever show whether content already carries the label — check that
separately via content search or the portal.

## References

1. Declare records by using retention labels (record removal requires records-manager privilege; regulatory record cannot be removed by anyone) — <https://learn.microsoft.com/purview/declare-records>
2. Remove-RetentionCompliancePolicy ("This cmdlet also removes the corresponding retention rule") — <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancepolicy>
3. Records management for documents and emails in Microsoft 365 (Records Management role group; file-plan permissions) — <https://learn.microsoft.com/purview/records-management>
