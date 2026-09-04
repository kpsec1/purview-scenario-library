# Four-Lens Review — Data Map Scan Azure Synapse Analytics Workspace and Classify Sensitive Columns

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Storage Blob Data Reader, as Microsoft's own documented steps describe granting it, is broader
   than this scenario needs.** The grant is scoped to the **resource group or subscription** holding
   the storage account, not the storage account resource itself — meaning the Purview MSI ends up with
   blob-read access to every other storage account in that resource group/subscription, not just the
   one backing the Synapse workspace's serverless pool. The original draft's §3 table stated the
   requirement without flagging this as an over-broad-by-default grant worth narrowing.
   - **Resolution:** `README.md` §3's Storage Blob Data Reader row now explicitly recommends scoping
     the assignment to the storage account resource itself where the tenant's Azure RBAC delegation
     model allows it, while still documenting Microsoft's own resource-group/subscription-level
     example.
2. **The external-table scoped-credential grant is a silent coverage gap, not a loud failure, if
   skipped.** A workspace with external tables backed by a scoped credential this grant wasn't applied
   to still produces a scan that reports "Succeeded" — it just silently doesn't classify those tables'
   columns. The original draft's §5 step 4 listed the T-SQL statement as a conditional step without
   warning that skipping it fails quietly rather than loudly, which is exactly the kind of gap a
   compliance team relying on "the scan succeeded" as proof of coverage would miss.
   - **Resolution:** `README.md` §5 step 4 now states this explicitly and points to a query
     (`sys.database_scoped_credentials`) an operator can run to confirm which databases actually need
     the grant before treating a clean scan run as complete coverage.
3. **`db_datareader` remains a broad read grant relative to "classify a few columns."** Same inherent
   tension both sibling scenarios' own Red Team findings already raised — not a bug in this script, and
   not changed here for the same reason: the mitigation is process (who can assign the SAMI's IAM/SQL
   grants), not a scripting change. Carried forward by reference rather than re-litigated.
   - **Resolution:** Not changed — noted here for visibility, consistent with both sibling scenarios'
     own disposition of the same finding.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The automated validate script can't check the serverless enumeration login, and the original
   draft didn't explain why.** `Test-AzureSynapseDataMapScan.ps1` authenticates against the Purview
   Data Map data-plane resource (`https://purview.azure.net`) with a Data Reader-scoped Purview role;
   confirming the serverless `CREATE LOGIN` grant exists requires a *separate* SQL connection to the
   serverless endpoint itself — an auth surface this scenario's automation identity has no other reason
   to hold. The original draft left this as a manual step in §7 check 4 without saying why it wasn't
   automated, reading like an oversight rather than a deliberate scope boundary (the same pattern the
   Managed Instance sibling scenario's own Blue Team review already caught once, for its Directory
   Readers check).
   - **Resolution:** `README.md` §7 check 4 now states the reason (a different auth surface than the
     rest of this script's checks) explicitly, and a dedicated SQL-permissioned checker script covering
     both the enumeration login and the `db_datareader` grant is recorded as a follow-up in
     `PROGRESS.md` rather than silently left unautomated.
2. **Incident-response runbook correctly anticipates the two Synapse-specific failure causes.** The
   original draft's §8 already added causes (e) (serverless enumeration login dropped/never created)
   and (f) (Storage Blob Data Reader revoked) as an explicit Synapse-specific addition to both sibling
   scenarios' shared runbook — confirmed adequate on review, no gap found.
   - **Resolution:** No change needed; confirmed not a gap.
3. **No SIEM/Sentinel integration mentioned.** Same as both sibling scenarios — correctly out of scope
   for a single-scenario fragment, and Data Map has no alert stream to route regardless of source type.
   - **Resolution:** No change needed; confirmed not a gap.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Prerequisite effort scales with database count, unlike either sibling scenario's fixed one-time
   cost.** Both sibling scenarios' out-of-band prerequisites are a fixed, one-time set of grants per
   *database* (i.e., per scenario deployment). This scenario's per-database enumeration login
   (serverless) and `db_datareader` grants multiply by however many databases the target workspace
   actually has — a workspace with dozens of serverless databases means dozens of manual T-SQL
   operations before this scenario's scan can classify any of them. The original draft's §3/§5 listed
   the grants as prerequisite steps without pricing in that this cost is variable, not fixed, which
   understates the real rollout effort for a large workspace.
   - **Resolution:** `README.md` §3 now carries an explicit cost/effort note stating this scaling
     behavior, and a bulk-grant helper script is recorded as a follow-up in `PROGRESS.md` rather than
     built speculatively into this fragment (which targets a single representative workspace, same
     framing both sibling scenarios use for a single representative database).
2. **Risk reduction vs. cost:** proportionate, and arguably higher-value than either sibling scenario
   alone. A Synapse workspace is disproportionately likely to be an aggregation point for sensitive
   data copied in from many upstream systems (README.md §2) — closing its classification-coverage gap
   protects a wider blast radius than a single source database.
3. **Board-level narrative:** "our automated data-discovery coverage now extends across our Azure SQL
   family — logical databases, migrated legacy SQL Server instances, and our enterprise analytics
   warehouse" is a materially more complete claim with this third scenario than either sibling alone
   supports.
4. **Change-management impact:** proportionate to the workspace's database count (point 1 above), but
   still bounded, one-time per database, and the staged rollback in `rollback.md` gives the same
   proportionate off-ramp both sibling scenarios provide.
5. **Would I fund this?** Yes — the incremental cost is grant/coordination effort that scales with a
   metric (database count) the buyer already knows and controls, not licensing, and it closes real
   coverage gaps (the aggregation-point risk in point 2, and the silent external-table gap the Red Team
   lens raised) a buyer running Synapse alongside either sibling scenario would otherwise carry
   unknowingly.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The original draft didn't distinguish this scenario's data source from Microsoft's separate,
   older "dedicated SQL pool (formerly SQL DW)" standalone source.** Microsoft Purview documents *two*
   distinct data sources for dedicated SQL pools: a standalone one (registered independently of any
   workspace, for a dedicated pool that hasn't enabled Azure Synapse workspace features) and the
   `AzureSynapseWorkspace` workspace-based source this scenario uses. The original draft correctly used
   the workspace-based `kind` throughout but never explicitly told a reader that a *different* Purview
   data source with a similar name exists and isn't what this scenario automates — a real risk for a
   buyer who already has the legacy source registered and might assume this scenario is a drop-in
   replacement or duplicate registration for the same pool.
   - **Resolution:** `README.md` §1 now opens with an explicit callout distinguishing the two sources
     and stating which one this scenario targets and why (current documented path; the only one of the
     two that also covers serverless). `design.md` §8 records the standalone source as an explicit
     non-goal with the same reasoning, and `README.md` §12 adds a reference citation.
2. **`AzureSynapseWorkspace`/`AzureSynapseWorkspaceMsi` as the current, correct `kind` pair for the
   workspace-based path** — confirmed via the Az.Purview PowerShell module's own worked examples
   (`New-AzPurviewAzureSynapseWorkspaceDataSourceObject` / `-MsiScanObject`), not just carried over by
   assumption from either sibling scenario.
3. **SAMI as the default authentication method is correct, current best practice for this source type
   too** — confirmed as the first-listed, recommended option in Microsoft's own three-way authentication
   comparison (managed identity, service principal, SQL authentication) for this source type.
4. **No deprecated cmdlets/endpoints used.** The generic Data Sources/Scans/Triggers/Scan Result call
   shapes are reused unchanged from the Managed Instance sibling scenario's own direct-fetch
   confirmation (API version `2023-09-01`); the Synapse-specific `kind`/property names are independently
   confirmed per point 2. The one property this build could not confirm to an exact shape
   (`resourceTypes`) is correctly omitted rather than guessed, and flagged as an explicit VERIFY —
   consistent with `AGENTS.md` §4's no-invented-parameters rule.
5. **Licensing citation accuracy** — confirmed identical to both sibling scenarios: PAYG/Azure-
   consumption billed, no per-user M365 entitlement, no source-type-specific billing delta from
   Purview's side.
6. **Reinventing-a-native-capability check:** this scenario is a direct, idiomatic use of the same Data
   Map REST surface both sibling scenarios use, adapted only where Microsoft's own documentation says
   Synapse genuinely differs (`design.md` §4) — not a parallel mechanism.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via scoping/coverage-gap documentation, 1 confirmed as an inherent trust-model note carried from both sibling scenarios) | Closed |
| 🔵 Blue Team | Fix | 3 (1 scope-boundary clarification + follow-up recorded, 2 confirmed correctly scoped/adequate) | Closed |
| 🎩 CISO | Fix | 1 closed (per-database cost-scaling made explicit + follow-up recorded); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (legacy-vs-workspace data source distinction made explicit); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AzureSynapseDataMapScan.ps1`, and `validate/Test-AzureSynapseDataMapScan.ps1`. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
