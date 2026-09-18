---
part: "rollback"
parent: "data-lifecycle-management/retention-labels-financial-records"
---
## ⚠️ Read first: a locked record (or regulatory record) cannot be casually released

By default this scenario auto-applies a plain **record** label: once applied, content is locked (can't
be edited/deleted) but a **records manager** can still unlock or remove the label. If you instead
configured a **regulatory record** (`regulatory: true`, which this scenario's deploy script only ever
*creates*, never auto-applies; see `README.md` §2), that label is **irreversible**: it can't be
removed, relabeled, or unlocked, its retention can't be shortened, and the content can't be edited or
deleted, by anyone, until the retention period expires. **Rollback here can only stop FUTURE
auto-labeling (record label only); it cannot release content already labeled, and it cannot touch a
regulatory record at all.** If you deployed to the wrong scope, the labeled content stays locked (or,
for a regulatory record, immutable) for its full term, which is exactly why the deploy is guarded
(lab test, `-DryRun`, Records/Legal sign-off).

## Recommended sequence

### Stage 1, Disable the auto-apply policy (stops labeling new content)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -DryRun
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json
```

Sets the policy `-Enabled $false`, no *new* content is auto-labeled. The label, the rule, and all
already-labeled records are untouched. Reversible: re-run the deploy to re-enable. Use this to pause a
mis-scoped rollout **before** more content is labeled.

### Stage 2, Delete the auto-apply policy and rule

```powershell
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -Delete
```

Removes the policy (and its rule). Still does **not** release any labeled content. Use when the
auto-apply mechanism is being retired but the label must remain for existing records.

### Stage 3, Remove the label (only if it was never applied)

```powershell
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. This **succeeds only if the label was never applied** (and isn't
configured for event-based retention). For a record label with records in existence, or any
regulatory record label at all, the service **refuses** the delete, the script reports that refusal
rather than forcing it. This is correct and expected: you cannot delete a label that locked or
immutable records depend on.

## What rollback does **not** undo

- **Any content already labeled as a record**, locked for its full retention term; only a records
 manager can unlock/remove the label early. **As a regulatory record**, no one can, ever.
- **Retention already in force**, a regulatory record's retention can't be shortened; a record
 label's can only be changed by a records manager, deliberately.
- **The label object**, once records exist under it, it can't be deleted (regulatory: never
 deletable once applied, regardless).
- **Storage consumed** by retained content, it can't be deleted early.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]`/`[FAIL]` while the label and rule
still exist. After **Stage 2**, expect the policy/rule existence checks to `[FAIL]`. After **Stage 3**,
the label check `[FAIL]`s only if the label was actually removable; otherwise it still `[PASS]`es, 
confirming the record (or regulatory record) label correctly could not be deleted.

If the deployed label is a **regulatory record**, `validate/Test-FinancialRecordsRetention.ps1` skips
the policy/rule checks entirely (they were never created, see `README.md` §2/§11) and only the label
existence check is meaningful; roll back its distribution instead via the sibling
`scenarios/data-lifecycle-management/publish-labels-for-manual-application/rollback.md`.
