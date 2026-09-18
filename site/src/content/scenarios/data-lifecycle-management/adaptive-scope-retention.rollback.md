---
part: "rollback"
parent: "data-lifecycle-management/adaptive-scope-retention"
---
## Lower irreversibility than a record label, read first

This scenario deploys a **Keep-only** retention policy (`RetentionComplianceAction: Keep`), not a
record or regulatory record label. Per Microsoft's own documented behavior for
`Remove-RetentionComplianceRule`: removing the rule "causes the release of all Exchange mailbox and
SharePoint site retentions that are associated with the rule", i.e. there is
**no permanently locked content to force-release** the way there is for
`scenarios/data-lifecycle-management/retention-labels-financial-records/`. Rollback here is
materially lower-risk. The residual risk is different: an **over-broad adaptive scope query**
retains (or under a mis-scoped rollback, stops retaining) more or fewer mailboxes than intended, 
see `reviews.md` Red Team finding 1.

## Recommended sequence

### Stage 1, Disable the policy (default; stops new/changed content from being retained)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json -DryRun
./deploy/Remove-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json
```

Sets the policy `-Enabled $false`. The scope, the policy, and the rule all still exist, this only
pauses enforcement. Fully reversible: re-run the deploy script to re-enable. Use this to pause a
mis-scoped rollout while you fix the adaptive scope's query.

### Stage 2, Delete the policy and rule

```powershell
./deploy/Remove-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json -Delete
```

`Remove-RetentionCompliancePolicy` removes the policy **and its rule together** (Microsoft's own
documented behavior) and, per the citation above, releases the retention that
was in force. This is a clean rollback: nothing is left locked.

### Stage 3, Also remove the adaptive scope (optional)

```powershell
./deploy/Remove-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json -Delete -TryRemoveScope
```

Attempts `Remove-AdaptiveScope`. Adaptive scopes are reusable across retention policies, Insider
Risk Management policies, and Communication Compliance policies, **only remove
the scope if you're certain nothing else references it.** The script reports a failure rather than
forcing it; pass `-ForceScopeDeletion` (→ `Remove-AdaptiveScope -ForceDeletion`) only after
confirming that in the portal (**Settings** > **Roles and scopes** > **Adaptive scopes**).

## What rollback does **not** undo

- **Content that was deleted under a `KeepAndDelete`/`Delete` variant of this policy** (this
 scenario's sample config is `Keep`-only, but the same object model supports the stronger
 actions), deletion, once it happens, is not reversible by this or any rollback.
- **The distribution/population delay on the way back in.** Re-enabling the policy or re-creating
 the scope restarts the same up-to-5-day (scope) / multi-day (policy distribution) delays
 documented in `README.md` Section 7/8, rollback is not instant to reverse either.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-AdaptiveScopeRetention.ps1 -ConfigPath ./deploy/config/adaptive-scope-retention.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]` while the scope, policy, and
rule all still `[PASS]` as existing. After **Stage 2**, expect the policy/rule existence checks to
`[FAIL]` while the scope check still `[PASS]`es. After **Stage 3**, the scope check `[FAIL]`s too, 
confirming full teardown.

## References

1. Remove-RetentionComplianceRule ("causes the release of all Exchange mailbox and SharePoint site retentions that are associated with the rule"), <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancerule>
2. Remove-RetentionCompliancePolicy ("This cmdlet also removes the corresponding retention rule"), <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-retentioncompliancepolicy>
3. Adaptive scopes (reusable across retention, communication compliance, and, per Get-AdaptiveScopeMembers' own description, Insider Risk Management policies), <https://learn.microsoft.com/purview/purview-adaptive-scopes>
