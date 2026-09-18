---
part: "rollback"
parent: "data-quality/rules-and-scorecards"
---
## Recommended sequence

Like the Data Map scan scenario in this repo, Data Quality rules and schedules don't act on live
M365 traffic, removing them stops future scans and scoring, but never touches the source data or
any Microsoft 365 control. Rollback is staged so you can pause scanning without losing the rule
definitions themselves.

### Stage 1, Remove the schedule only (keep the rules)

```powershell
./deploy/Remove-DataQualityRulesAndSchedule.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json'
```

Deletes the `RunOnce` schedule. The rules stay `Active` on the asset, they still contribute to the
asset's score whenever a scan does run (an ad hoc portal "Run quality scan", or a future re-run of
`deploy/New-DataQualityRulesAndSchedule.ps1`), but nothing is scheduled to trigger one automatically.

Use this stage for: pausing automatic scoring (e.g. during a change freeze, or while a rule is under
review) while keeping the rule definitions and prior score history intact.

### Stage 2, Remove the rules too

```powershell
./deploy/Remove-DataQualityRulesAndSchedule.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json' `
    -RemoveRules
```

Deletes both the schedule (Stage 1) and every rule named in the definition file, matched by name via
`Get Rules` and deleted by the ID the API returns, the script never guesses or hard-codes a rule ID.
Any rule in the definition file that's already gone (already deleted, or never successfully created)
is reported and skipped rather than treated as an error, so this is safe to re-run.

## What rollback does **not** undo

- **Score history.** Prior scan runs' scores (up to the last 50 snapshots per Microsoft's documented
 retention) remain visible in the portal even after the rules that produced them are deleted. To
 remove history explicitly, use the portal's **Delete data quality data** action on the asset's
 Data quality overview page (`README.md` reference 8), not scripted here, since it's a destructive,
 rarely needed action this repo's code-standard reserves for explicit, deliberate operator choice
 rather than a default rollback path.
- **The Data Quality data-source connection.** This scenario's deploy script never created it (see
 `README.md` §11), so rollback doesn't touch it either. Remove it separately via the portal
 (**Manage** → **Connections**) if the intent is a full teardown.
- **The governance domain, data product, or data asset.** None of these were created by this
 scenario, see `design.md` §6/§7, so none are removed by rollback.
- **Any score-threshold alerts configured via the portal.** Not scripted by this scenario (see
 `README.md` §11); remove them separately under **Manage** → **Alerts** if desired.

## Verification after rollback

```powershell
# After Stage 1: expect the schedule GET to 404, rules GET to still list all rules.
# After Stage 2: expect both the schedule GET and each named rule's presence in the rules list to be gone.
./validate/Test-DataQualityRulesAndScorecard.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -RulesDefinitionPath './deploy/rules/customer-master-data-quality-rules.json'
```

The validate script's schedule check uses `-Warn` semantics (it will report `[WARN]`, not `[FAIL]`,
once the schedule is gone), after Stage 1 this is expected and not a hard failure. After Stage 2,
the per-rule existence checks will report `[FAIL]` for each removed rule, which is the expected,
correct signal that rollback succeeded, re-run with `-RulesDefinitionPath` pointed at an empty/
trimmed definition file, or simply read the console output, rather than treating a non-zero exit
code as a problem in this specific post-Stage-2 context.
