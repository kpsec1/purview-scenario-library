# Four-Lens Review — Data Map PII-Only Scan Rule Set for Azure SQL Managed Instance

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The independently-confirmed name-equals-kind relationship for THIS source type is easy to
   over-generalize into "every Data Map PII-ruleset scenario in this repo either always matches or
   always differs" — neither is true, and the next builder to extend this pattern to the
   still-unbuilt on-premises SQL Server sibling (`kind: SqlServerDatabase`) could mechanically copy
   whichever of this scenario's or the Synapse sibling's `-RevertToRulesetName` pattern they saw
   most recently, without re-verifying.** This build itself avoided that trap — it independently
   direct-fetched `New-AzPurviewAzureSqlDatabaseManagedInstanceScanRulesetObject.md` rather than
   assuming Managed Instance would follow either prior sibling's pattern — but the original draft's
   `design.md` did not yet say so explicitly enough to stop a future, less careful build from
   skipping that step.
   - **Resolution:** `design.md` §2 goal 6 and `README.md` §11 both state plainly that this
     scenario's name-equals-kind finding was independently confirmed for Managed Instance
     specifically, contrast it against both prior siblings (one matches, one doesn't), and
     explicitly warn that the still-unbuilt `SqlServerDatabase` sibling must not inherit either
     conclusion without its own direct-fetch confirmation. `rollback.md` repeats the warning at the
     exact point (`-RevertToRulesetName`) where a copy-paste mistake would land.
2. **A `-ScanName`/`-DataSourceName` typo silently reconciles a mismatched scan.** Same class of
   finding as both sibling scenarios: the original draft did not check the existing scan's `kind`
   before reconciling it onto an `AzureSqlDatabaseManagedInstance`-kind ruleset.
   - **Resolution:** the script checks `$existingScan.kind` against both confirmed Managed Instance
     scan kinds (`AzureSqlDatabaseManagedInstanceMsi`/`AzureSqlDatabaseManagedInstanceCredential`)
     before touching anything, and throws immediately with a clear message if they don't match.
3. **Silent clobber of a shared, account-wide object.** Same finding and same resolution as both
   siblings: the deploy script `GET`s any pre-existing ruleset with the same name before the `PUT`,
   diffs its `excludedSystemClassifications` against the newly computed list, and emits an explicit
   `Write-Warning` whenever the content would actually change.
4. **The scenario's entire purpose is a monitoring-coverage reduction — and Managed Instance is
   disproportionately likely to hold the messiest, highest-risk data in the estate.** Managed
   Instance is commonly a lift-and-shift landing zone for on-premises SQL Server (design.md §1,
   README.md §2) — exactly the kind of long-lived, schema-drifted database most likely to contain
   an undocumented sensitive column the System default's ~200-classification sweep would have
   caught and this scenario's narrower ruleset will not.
   - **Resolution:** `README.md` §2 states the lift-and-shift context explicitly; §11 states the
     coverage-reduction tradeoff plainly, matching both siblings' disclosure but naming the
     elevated stakes for this specific source type rather than reusing generic wording.
5. **`GET`-then-`PUT` on the scan has no concurrency guard (TOCTOU).** Same limitation the base
   `scan-azure-sql-managed-instance-and-classify` scenario and both sibling PII-ruleset scenarios
   already carry — Microsoft's Scans REST reference documents no concurrency-token mechanism.
   - **Resolution:** Not changed — a pre-existing, repo-wide limitation, not one this scenario
     introduces. Noted here for visibility rather than re-litigated per scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Narrowing classification scope on a lift-and-shift instance is a security-relevant change
   with no operational guidance on how to detect it after the fact.** Same finding as both
   siblings.
   - **Resolution:** `README.md` §8/§11 instruct pulling **Scan rule set: Create/Update/Delete**
     Management-category audit events (via the `PurviewDataMapOperation` Microsoft Graph security
     audit log record type) into the same SIEM/Sentinel pipeline used for this repo's other Purview
     audit activity, matching both siblings' resolution.
2. **A reader could assume this scenario also grants or verifies the base scenario's own unusually
   long prerequisite list** (public endpoint, Microsoft Entra admin, Directory Readers role, NSG
   rule, `db_datareader` grant) **since both concern the same scan object.** The original draft's
   Prerequisites table did not explicitly disclaim this.
   - **Resolution:** `README.md` §3's first row explicitly states this scenario assumes the base
     scenario's own scan already runs successfully, and `design.md` §5 lists exactly which of the
     base scenario's prerequisites this scenario does not grant or verify.
3. **No structured/machine-readable deploy summary.** Same non-fix as both siblings — colored
   `Write-Host` text matches every other scenario's script style in this repo; introducing
   structured output here alone would be an inconsistent, scenario-local deviation.
   - **Resolution:** Not changed — same repo-wide-follow-up framing as both siblings' own reviews.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

1. **Residual risk is real, now explicit, and correctly scoped to this source type's actual
   profile.** `README.md` §2/§11 state plainly that the ~198 excluded classifications are genuinely
   un-monitored once this scenario is applied, and specifically name the elevated stakes of doing
   so on a lift-and-shift instance rather than reusing generic wording from either sibling.
2. **No new licensing spend.** Confirmed — this scenario reuses the base scenario's PAYG Data Map
   billing with no new consumption meter (`README.md` §10).
3. **Compliance narrative is directly demonstrable**, and speaks to a scenario a buyer's auditor is
   likely to ask about directly: "the lift-and-shift instance that used to be on-premises SQL
   Server — how do you know what's in it now?" A scoped `excludedSystemClassifications` array on
   that instance's own scan is legible evidence the discovery scope was deliberately narrowed to
   match a named compliance driver, not left at whatever the migration happened to carry over.
4. **Change-management dependency is named, not glossed over.** Same as both siblings — a changing
   regulatory driver requires a manual re-run with an updated `-RetainedSystemClassifications`
   list.
5. **The independent-verification discipline (Red Team finding 1) is itself a fundable, not just
   technical, point.** Three sibling scenarios in, this repo could have started pattern-matching
   source types against each other to save grounding effort. This build instead re-verified the
   name-vs-kind relationship from scratch for Managed Instance and found it happened to match one
   sibling and not the other — the kind of engineering diligence a CISO evaluating this repo as a
   vendor deliverable should expect to see repeated for the remaining sibling, not assumed away for
   speed.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, independently-confirmed API surface for this specific source type.** The Custom
   `AzureSqlDatabaseManagedInstanceScanRuleset` shape and its `Kind:
   "AzureSqlDatabaseManagedInstance"` value were confirmed via direct fetch of the Az.Purview
   PowerShell module's own GitHub source — a real Microsoft-maintained reference, not a guess by
   analogy from either sibling. The `learn.microsoft.com` REST reference page itself could not be
   independently direct-fetched in this build environment (`EGRESS_BLOCKED`, the same restriction
   the Synapse sibling's own build hit and worked around the same way); this is disclosed as an
   open VERIFY in `README.md` §11 rather than silently treated as equivalent-strength evidence to a
   direct REST-reference fetch.
2. **Not reinventing a native capability.** Same as both siblings — this scenario configures
   Purview's own native custom scan rule set feature exactly as Microsoft's own guidance describes
   the use case, applied to Azure SQL Managed Instance instead of Azure SQL Database or Azure
   Synapse Analytics.
3. **Correctly treats each source type as its own grounding question rather than a template
   substitution.** Confirming (rather than assuming) that Managed Instance's name-vs-kind
   relationship happens to match the Azure SQL Database sibling — and explicitly is not assumed to
   also hold for the still-unbuilt on-premises SQL Server sibling — is exactly the discipline a
   reviewer familiar with the real, source-type-fragmented Data Map API surface would expect.
4. **Design choice (live Types API query vs. a hard-coded snapshot) inherited correctly.** The
   Types API is tenant-wide and source-type-agnostic, so reusing both siblings' confirmed call
   shape unchanged here — rather than re-deriving it from scratch — is the right amount of new
   grounding work for what is genuinely a shared surface, not a missed verification step.
5. **Compatible scan kinds correctly sourced from the base scenario's own already-grounded
   README, not re-derived speculatively.** `AzureSqlDatabaseManagedInstanceMsi`/
   `AzureSqlDatabaseManagedInstanceCredential` were both already confirmed when the base scenario
   was built; reusing that citation here (rather than re-fetching the same fact) is the correct
   amount of redundant grounding for an already-established fact.

No Fix/Fail raised.

---

## Summary

Two lenses (Red Team, Blue Team) raised Fix items; all are resolved in `design.md`, `README.md`,
and `rollback.md` as described above — no code changes were needed since the deploy and validate
scripts were drafted with both sibling scenarios' already-reviewed guards (scan-kind compatibility
check, shared-object clobber warning) built in from the start rather than added after the fact. The
highest-value finding (Red Team #1) is forward-looking: it does not describe a defect in this
scenario itself, but a documentation gap that could have let a future build of the remaining
on-premises SQL Server sibling skip independent verification of its own name-vs-kind relationship.
CISO and Microsoft Product Owner passed without required changes. No Fail verdicts. Fragment meets
`AGENTS.md` §9's definition of done.
