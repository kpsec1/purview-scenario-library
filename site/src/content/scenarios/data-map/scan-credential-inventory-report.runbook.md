---
part: "runbook"
parent: "data-map/scan-credential-inventory-report"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. In the [Microsoft Purview portal](https://purview.microsoft.com) → **Data Map** → **Source
   management** → **Credentials**, review the current credential list - name, authentication
   method, and Key Vault connection per row.
2. There is no native export or historical trend for this list - this is exactly the gap this
   scenario's script closes.
3. Assign the automation identity's service principal the **Data Reader** role on the collection(s)
   in scope: **Data Map** → **Collections** → select the collection → **Role assignments** → add
   under **Data readers**.
4. Copy `deploy/policy/expected-credential-inventory.json`, rename it, and fill in the credentials
   you expect to exist - kind, and the fingerprint fields from the configuration reference's table for that kind.

### Script path (idempotent by RunId, parameterized, dry-run capable)

```powershell
# 1. Dry run - lists every credential, computes fingerprints, prints a summary, writes nothing to disk
./deploy/Export-CredentialInventoryReport.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ExpectedStatePath './deploy/policy/expected-credential-inventory.json' `
    -TrendLogPath './deploy/out/credential-inventory-trend.csv' `
    -DriftReportDirectory './deploy/out/drift-reports' -WhatIf

# 2. Run for real - writes/replaces today's trend-log row(s) and this run's drift-report JSON
./deploy/Export-CredentialInventoryReport.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -ExpectedStatePath './deploy/policy/expected-credential-inventory.json' `
    -TrendLogPath './deploy/out/credential-inventory-trend.csv' `
    -DriftReportDirectory './deploy/out/drift-reports'

# 3. Validate - file-integrity checks, the drift gate, and an optional live reconciliation
./validate/Test-CredentialInventoryReport.ps1 `
    -TrendLogPath './deploy/out/credential-inventory-trend.csv' `
    -DriftReportDirectory './deploy/out/drift-reports' -FailOnDrift `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret
```

Both scripts use the **Microsoft Purview Scanning data-plane REST API** - automation surface 4 per
[Automation surface, section 1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first) - the same surface *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)*'s own scripts
use. Token acquisition follows the identical client-credentials pattern.

**Scheduling:** this scenario ships no scheduler-specific code - wire
`deploy/Export-CredentialInventoryReport.ps1` into whatever recurring-execution mechanism the deploying organization
already runs other PowerShell automation on, then gate on `validate/
Test-CredentialInventoryReport.ps1 -FailOnDrift`'s exit code. A daily run is the right default
cadence for a control this library positions as a change-management/audit-evidence mechanism; a tenant
with frequent, legitimate credential churn (many onboarding pipelines) may prefer a lower-frequency
review cadence instead to reduce `NotTracked` noise - see operations and tuning.

## Configuration reference

### Fingerprint fields extracted per `kind`

| `kind` | Fields (all are identity properties or Key Vault secret **references** - never secret values) |
|---|---|
| `SqlAuth`, `BasicAuth` | `User`, `Password.SecretName`, `Password.KeyVaultConnectionName`, `Password.SecretVersion` |
| `ServicePrincipal` | `ServicePrincipalId`, `Tenant`, `ServicePrincipalKey.SecretName`, `ServicePrincipalKey.KeyVaultConnectionName`, `ServicePrincipalKey.SecretVersion` |
| `AccountKey` | `AccountKey.SecretName`, `AccountKey.KeyVaultConnectionName`, `AccountKey.SecretVersion` |
| `AmazonARN` | `RoleARN` (plain string - this kind has no Key Vault reference at all) |
| `ConsumerKeyAuth` | `User`, `ConsumerKey`, `ConsumerSecret.SecretName`/`.KeyVaultConnectionName`/`.SecretVersion`, `Password.SecretName`/`.KeyVaultConnectionName`/`.SecretVersion` (two independent secret references) |
| `DelegatedAuth` | `ClientId`, `User`, `Password.SecretName`/`.KeyVaultConnectionName`/`.SecretVersion` |
| `ManagedIdentity` | `PrincipalId`, `ResourceId`, `TenantId` (no Key Vault reference at all) |

Full per-kind grounding and the REST shapes behind this table: the design notes, and
`deploy/Export-CredentialInventoryReport.ps1`'s `Get-CredentialFingerprint` function.

### Report status values

| `Status` | Meaning |
|---|---|
| `Match` | The credential exists live, is named in the expected-state file, and every expected field matches |
| `Drift` | The credential exists live, is named in the expected-state file, but one or more fields (or its `kind`) no longer match |
| `Missing` | The credential is named in the expected-state file but does **not** exist live - deleted, or never deployed |
| `NotTracked` | The credential exists live but has no matching entry in the expected-state file (or no `-ExpectedStatePath` was supplied at all) |

### Deploy script parameters (selected)

| Parameter | Default | Notes |
|---|---|---|
| `-ExpectedStatePath` | *(none)* | Optional - omit for an inventory-only report (every credential reported as `NotTracked`) |
| `-RunId` | Current UTC date (`yyyy-MM-dd`) | Re-running for the same RunId replaces that RunId's rows rather than duplicating |
| `-ApiVersion` | `2023-09-01` | Same version *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* was grounded against |

### Validate script parameters (selected)

| Parameter | Default | Notes |
|---|---|---|
| `-FailOnDrift` | Off | When set, any `Drift`/`Missing` credential in the most recent run is a hard `[FAIL]` rather than an informational `[WARN]` - the parameter a CI/scheduled-pipeline gate should pass |
| `-FailOnUntracked` | Off | When set, **also** fails on any `NotTracked` credential - a wholly new, never-approved credential (not a re-point of a tracked one) otherwise only ever shows as `NotTracked` and `-FailOnDrift` alone will not catch it. See the known limitations's Red Team finding. Recommended in any tenant where new-credential creation is rare/tightly controlled; leave off where legitimate onboarding regularly adds credentials faster than the expected-state file is updated |
| `-DriftReportDirectory` | *(none)* | Required for the drift gate and to inspect the most recent run's full per-field mismatch detail |

## Operations and tuning

**KPIs / what to watch**

| Signal | Where | Healthy | Act when |
|---|---|---|---|
| `Drift` or `Missing` status count, per run | Trend-log CSV, or `validate/ -FailOnDrift` exit code | Zero | Any non-zero count - investigate immediately, not on the next scheduled review (the known limitations's runbook) |
| `NotTracked` count trend | Trend-log CSV | Roughly stable, or trending toward zero as the expected-state file is kept current | A sustained rise means the expected-state file has fallen behind real onboarding - add the new credentials to it deliberately, don't just ignore the noise |
| Live-reconciliation `[WARN]` frequency | `validate/` console output | Clears on the next scheduled run | Persists across two or more runs - investigate as a possible stale report or a scope mismatch |

**Alert routing:** same posture as *Exportable, Historical Classification Coverage Report* (operations and tuning) - this scenario
produces flat files and a non-zero exit code, not a native Purview alert. Route
`validate/Test-CredentialInventoryReport.ps1 -FailOnDrift`'s exit code into whatever CI/ops alerting
the deploying organization already uses for scheduled scripts.

**Runbook - a `Drift` or `Missing` status appears**

1. **Do not assume malice first, but do not assume benign either - the runbook is what tells them
   apart, not a guess.** Pull the mismatch detail from the drift-report JSON (`validate/` prints it,
   or open `<RunId>-credential-inventory-drift.json` directly).
2. **Cross-check with change records.** Was there a legitimate, recent deploy of `scan-credential-key-vault-backed/deploy/New-PurviewScanCredential.ps1` against this credential name - a planned
   secret rotation with a new `-SecretVersion`, or an intentional re-point? If yes and it matches
   what was approved, update the expected-state file to reflect the new values (a deliberate,
   reviewed commit - not a silent edit) and re-run.
3. **If no legitimate change explains it** - treat this as the Red Team finding
   *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* (the known limitations) describes made concrete: escalate as a possible
   unauthorized credential modification. Check who currently holds Data Source Administrator on the
   affected collection, check Key Vault `AuditEvent` diagnostic logs for reads against the *new*
   secret reference the drift report shows (a re-point at a secret outside the expected set is
   visible from the vault side even though Purview's own audit trail is silent - the same
   compensating control named in that section), and treat this the same as any other
   privileged-configuration-tampering incident until proven otherwise.
4. **`Missing` status specifically** - confirm whether the credential was deliberately decommissioned
   (via `scan-credential-key-vault-backed/deploy/Remove-PurviewScanCredential.ps1`, per its own rollback runbook) before assuming this is a problem. If it was, remove that entry from the
   expected-state file in the same commit that records the decommission.

**Review cadence:** daily is the default `-RunId` grain; review the trend log itself (not just react
to `[FAIL]`s) at least monthly to catch a `NotTracked` count that's quietly grown because the
expected-state file wasn't kept current.

## Rollback and decommission

See the rollback runbook. Summary: this scenario creates **no Purview object** - there is nothing in the
Purview account itself to roll back. Decommissioning means stopping the scheduled execution,
removing the reporting service principal's Data Reader role assignment, and deciding what to do with
the already-produced trend-log/drift-report files and the checked-in expected-state file.

## References

1. [Credential - List (Purview Scanning data plane, 2023-09-01)](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/list) - `GET /scan/credentials`, `{ count, nextLink, value[] }` envelope, worked 2-credential example, all eight kind-specific `properties`/`typeProperties` definitions used to build the configuration reference's fingerprint table.
2. [Credential - Create Or Replace](https://learn.microsoft.com/rest/api/purview/scanningdataplane/credential/create-or-replace) - the same eight kind definitions from the write side, cross-checked for consistency with reference 1.
3. [Tutorial: Use REST APIs to authenticate for Microsoft Purview data-plane APIs](https://learn.microsoft.com/purview/data-gov-api-rest-data-plane) - token acquisition and data-plane role assignment.
4. [Manage domains and collections in Microsoft Purview Data Map](https://learn.microsoft.com/purview/data-map-domains-collections-manage) - Data Reader role definition (credentials not named specifically - see the VERIFY in the prerequisites and the known limitations).
5. [Audit logs, diagnostics, and activity history](https://learn.microsoft.com/purview/data-gov-classic-audit-logs-diagnostics) - the enumerated Management audit-event categories that do **not** include credentials or Key Vault connections, the documented absence this scenario's drift detection compensates for.

Related scenarios in this library:
- *Key Vault-Backed Scan Credential (SQL Auth / Service Principal)* - creates the credentials this scenario
  reports on; its the known limitations names the silent-re-point gap this scenario closes.
- *Scan Credentials: Remaining Kinds (Account Key, Role ARN, Consumer Key, Delegated Auth, User-Assigned Managed Identity)* - creates the other five credential kinds
  (`AccountKey`, `AmazonARN`, `ConsumerKeyAuth`, `DelegatedAuth`, `ManagedIdentity`) this scenario's
  fingerprint table already covers; no change was needed here to support them.
- *Exportable, Historical Classification Coverage Report* - the sibling reporting scenario
  this fragment's trend-log/replace-by-RunId idempotency pattern is reused from verbatim.
- [RBAC model, section 5](/docs/rbac-model/#5-data-governance-roles-data-map--unified-catalog---a-separate-model) - Data Map collection roles.
- [Automation surface](/docs/automation-surface/) - surface 4 (Purview data-plane REST).

> Re-verify all links against current Microsoft Learn before a customer-facing deployment - this
> repo's Data Map REST surface is explicitly called out elsewhere
> (*Scan Azure SQL Database and Classify Sensitive Columns* (the known limitations)) as evolving.