# Rollback — Regulatory Retention Labels for Financial Records

## ⚠️ Read first: regulatory records cannot be released

A **regulatory record** label, once applied to content, is **irreversible**: the label can't be
removed, relabeled, or unlocked, its retention can't be shortened, and the content can't be edited or
deleted — by anyone — until the retention period expires. That is the whole point of the control
(SEC 17a-4 WORM immutability). **Rollback here can only stop FUTURE auto-labeling; it cannot release
content already made a record.** If you deployed to the wrong scope, the labeled content stays
immutable for its full term — which is exactly why the deploy is guarded (lab test, `-DryRun`,
Records/Legal sign-off).

## Recommended sequence

### Stage 1 — Disable the auto-apply policy (stops labeling new content)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -DryRun
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json
```

Sets the policy `-Enabled $false` — no *new* content is auto-labeled. The label, the rule, and all
already-labeled records are untouched. Reversible: re-run the deploy to re-enable. Use this to pause a
mis-scoped rollout **before** more content is labeled.

### Stage 2 — Delete the auto-apply policy and rule

```powershell
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -Delete
```

Removes the policy (and its rule). Still does **not** release any labeled content. Use when the
auto-apply mechanism is being retired but the label must remain for existing records.

### Stage 3 — Remove the label (only if it was never applied)

```powershell
./deploy/Remove-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json -Delete -TryRemoveLabel
```

Attempts `Remove-ComplianceTag`. This **succeeds only if the label was never applied** (and isn't a
published/regulatory record in use). For a regulatory record label with records in existence, the
service **refuses** the delete — the script reports that refusal rather than forcing it. This is
correct and expected: you cannot delete a label that immutable records depend on.

## What rollback does **not** undo

- **Any content already labeled as a regulatory record** — immutable for its full retention term.
  There is no admin override, by design.
- **Retention already in force** — a regulatory record's retention can't be shortened.
- **The label object**, once records exist under it — it can't be deleted.
- **Storage consumed** by retained content — it can't be deleted early.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-FinancialRecordsRetention.ps1 -ConfigPath ./deploy/config/financial-records-retention.json
```

After **Stage 1**, expect the "Policy is enabled" check to `[WARN]`/`[FAIL]` while the label and rule
still exist. After **Stage 2**, expect the policy/rule existence checks to `[FAIL]`. After **Stage 3**,
the label check `[FAIL]`s only if the label was actually removable; otherwise it still `[PASS]`es —
confirming the regulatory record label (correctly) could not be deleted.
