# Four-Lens Review - Data Map Scan Azure SQL Managed Instance and Classify Sensitive Columns

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The public endpoint is a bigger opening than the sibling scenario's firewall toggle, and the
   original draft didn't say so as plainly.** Enabling a managed instance's public endpoint puts a
   `<name>.public.<dns-zone>.database.windows.net` name on the public internet - a strictly larger
   network exposure than the sibling scenario's "Allow Azure services and resources to access this
   server" toggle, which at least keeps the connection path inside Azure's own network fabric.
   Authentication (Entra/SQL) is still required either way, but the original draft's §5 step 1
   registered this as a routine registration step rather than a security tradeoff worth calling out.
   - **Resolution:** `README.md` §5 step 1 now states the tradeoff explicitly and recommends a
     private endpoint (with the self-hosted IR + service-principal/SQL-auth fallback this scenario's
     §11 already documents) for a production instance, matching the weight the sibling scenario
     gives its own network-exposure tradeoff.
2. **Directory Readers membership drift has no detection mechanism.** Once granted, nothing in this
   scenario notices if a *different* workload identity is later added to (or removed from) the same
   Directory Readers role - a tenant-wide-flavored grant this scenario's own instance identity now
   shares with whatever else holds it. The original draft flagged the grant's existence but not the
   need to periodically confirm membership hasn't silently changed.
   - **Resolution:** `README.md` §8 "Review cadence" now recommends a periodic
     `Get-MgDirectoryRoleMember` check against the Directory Readers role, not just a network/
     public-endpoint review.
3. **`db_datareader` remains a broad read grant relative to "classify a few columns."** Same
   inherent tension as the sibling scenario's own Red Team finding - not a bug in this script, and
   not changed here for the same reason: the mitigation is process (who can assign the SAMI's
   IAM/SQL/Entra grants), not a scripting change. Carried forward from `scan-azure-sql-and-classify/
   reviews.md` by reference rather than re-litigated.
   - **Resolution:** Not changed - noted here for visibility, consistent with the sibling scenario's
     own disposition of the same finding.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The automated validate script can't check the Directory Readers grant, and the original draft
   didn't explain why.** `Test-AzureSqlManagedInstanceDataMapScan.ps1` authenticates against the
   Purview Data Map data-plane resource (`https://purview.azure.net`) with a Data Reader-scoped
   Purview role; confirming Directory Readers membership requires a *separate* Microsoft Graph token
   and a directory-read permission this scenario's automation identity has no reason to hold. The
   original draft left this as a manual portal/PowerShell step in §7 without saying why it wasn't
   automated, reading like an oversight rather than a deliberate scope boundary.
   - **Resolution:** `README.md` §7 check 4 now states the reason (a different auth surface/
     permission set than the rest of this script's checks) explicitly. This gap is now closed by
     the dedicated companion scenario `scenarios/data-map/verify-purview-entra-graph-prerequisites/`,
     which checks Directory Readers membership (and drift) across every Managed-Instance-backed
     Purview source, not just this one - built as a separate fragment per `AGENTS.md` §6.
2. **Incident-response runbook needed a Managed-Instance-specific branch, not just the sibling
   scenario's four causes.** The original draft's §8 pointed at the sibling scenario's runbook
   without naming the two failure causes unique to this data source (Directory Readers revoked;
   public endpoint disabled).
   - **Resolution:** `README.md` §8 now adds causes (e) and (f) as an explicit "Managed
     Instance-specific" addition to the sibling scenario's runbook.
3. **No SIEM/Sentinel integration mentioned.** Same as the sibling scenario - correctly out of scope
   for a single-scenario fragment, and Data Map has no alert stream to route regardless of source
   type.
   - **Resolution:** No change needed; confirmed not a gap.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Cross-team coordination cost wasn't priced into the adoption narrative.** Unlike the sibling
   scenario (whose prerequisites all sit within the data/security team's own Purview and Azure IAM
   role scope), this scenario's Directory Readers grant requires a **Privileged Role Administrator**
   - almost always a different team (identity/IAM) than whoever is standing up Data Map scanning.
   The original draft priced this as "one more prerequisite row" without calling out that it's a
   different *approver*, not just a different permission.
   - **Resolution:** `README.md` §3's Directory Readers row now states this explicitly ("Granted by
     a Privileged Role Administrator") and §8's review-cadence addition makes clear this is a
     standing coordination point, not a one-time checkbox.
2. **Risk reduction vs. cost:** proportionate. This scenario closes the same classification-coverage
   gap the sibling scenario closes, for a data source (lift-and-shift Managed Instance) that
   specifically tends to carry migrated, schema-drifted legacy data - arguably a *higher*-value
   target for automated discovery than a greenfield Azure SQL Database.
3. **Board-level narrative:** "our automated data-discovery coverage extends to our lift-and-shift
   SQL estate, not just greenfield Azure SQL," is a stronger, more complete claim than the sibling
   scenario alone supports - a genuine incremental value-add, not a duplicate.
4. **Change-management impact:** higher than the sibling scenario (five out-of-band prerequisites
   instead of three, one requiring a different approver), but still bounded and one-time per
   instance - the staged rollback in `rollback.md` gives the same proportionate off-ramp.
5. **Would I fund this?** Yes - the incremental cost is entirely coordination/process (getting IAM
   sign-off once), not licensing, and it closes a real, commonly-missed discovery gap for exactly the
   kind of legacy-migrated database most likely to still hold undiscovered sensitive data.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Redirect-vs-Proxy connection-policy default changed in October 2025 - the original draft's
   default `-Port 3342` needed a currency check, not a silent carry-forward.** Microsoft's own
   documentation confirms Redirect became the default connection type for connections originating
   inside Azure starting October 2025 (Proxy remains default for connections originating outside
   Azure); this affects which *NSG ports* the network path needs (§3/§6), not the registration port
   itself, but the original draft's default `-Port 3342` (Microsoft's own worked *registration*
   example) could be read as implying Proxy is still the universal default.
   - **Resolution:** `README.md` §6 and §11 now separate the two concerns explicitly - the
     registration `-Port` parameter (confirm against the instance's actual public-endpoint
     configuration, flagged as an explicit VERIFY) versus the NSG/network-path port requirement
     (which does depend on Redirect-vs-Proxy, already correctly split out in §3's table).
2. **SAMI as the default authentication method is correct, current best practice for this source
   type too** - confirmed against the same "System or user assigned managed identity" section of
   Microsoft's Managed Instance-specific documentation, not just carried over by assumption from the
   sibling scenario.
3. **No deprecated cmdlets/endpoints used.** All four REST operations' API version (`2023-09-01`)
   were independently confirmed current via direct fetch of each operation's own canonical Microsoft
   Learn REST reference page - closing three VERIFY items the sibling scenario left open, and
   catching two real shape corrections (Run Scan's action-style POST; List Scan History's nested
   asset-count fields) documented in `design.md` §5 and carried into this scenario's scripts.
4. **Licensing citation accuracy** - confirmed identical to the sibling scenario: PAYG/Azure-
   consumption billed, no per-user M365 entitlement, no source-type-specific billing delta.
5. **Reinventing-a-native-capability check:** this scenario is a direct, idiomatic use of the same
   Data Map REST surface the sibling scenario uses, adapted only where Microsoft's own documentation
   says the two data source `kind`s genuinely differ (`design.md` §4) - not a parallel mechanism.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via explicit tradeoff/monitoring documentation, 1 confirmed as an inherent trust-model note carried from the sibling scenario) | Closed |
| 🔵 Blue Team | Fix | 3 (1 scope-boundary clarification + follow-up recorded, 1 runbook addition, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (cross-team coordination cost made explicit); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (registration-port vs. network-path-port distinction sharpened); 4 confirmed correct, including two real REST-shape corrections over the sibling scenario | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AzureSqlManagedInstanceDataMapScan.ps1`, and
`validate/Test-AzureSqlManagedInstanceDataMapScan.ps1`. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.
