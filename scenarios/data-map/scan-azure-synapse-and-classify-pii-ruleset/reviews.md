# Four-Lens Review — Data Map PII-Only Scan Rule Set for Azure Synapse Analytics

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The system-name-vs-kind naming trap is the single highest-value bypass to a lazy copy-paste
   from the sibling scenario, and it fails in the worst possible direction.** If
   `deploy/Remove-PiiOnlyScanRuleset.ps1`'s `-RevertToRulesetName` default had been mechanically
   copied from the Azure SQL Database sibling's pattern (`kind` string == system ruleset name) it
   would default to `'AzureSynapseWorkspace'` — which is not a System ruleset name at all, it's the
   *custom* ruleset's `kind`. A rollback run with that wrong default would PUT the scan with
   `scanRulesetName: 'AzureSynapseWorkspace'`/`scanRulesetType: 'System'`, referencing a System
   ruleset that does not exist under that name. Depending on how the Scanning service validates an
   unrecognized System ruleset name on PUT, this either fails loudly (best case) or silently leaves
   the scan in a broken or ambiguous state at its *next run* — far from the moment of the mistake,
   the same delayed-failure shape the sibling's own Red Team review flagged for a different bug.
   - **Resolution:** `-RevertToRulesetName` is hard-coded to the independently-confirmed correct
     string `'AzureSynapseSQL'` (design.md §2 goal 6), with the script's own `.PARAMETER` help and
     inline comment explicitly calling out why it is not derived from the ruleset `kind` constant
     used elsewhere in the same file. `README.md` §11 and `rollback.md` both carry the same callout
     so a reader skimming either file catches it before running the wrong default in production.
2. **A `-ScanName`/`-DataSourceName` typo silently reconciles a mismatched scan.** Same class of
   finding as the Azure SQL Database sibling: the original draft did not check the existing scan's
   `kind` before reconciling it onto an `AzureSynapseWorkspace`-kind ruleset.
   - **Resolution:** the script checks `$existingScan.kind` against both confirmed Synapse scan
     kinds (`AzureSynapseWorkspaceMsi`/`AzureSynapseWorkspaceCredential`) before touching anything,
     and throws immediately with a clear message if they don't match.
3. **Silent clobber of a shared, account-wide object.** Same finding and same resolution as the
   sibling: the deploy script `GET`s any pre-existing ruleset with the same name before the `PUT`,
   diffs its `excludedSystemClassifications` against the newly computed list, and emits an explicit
   `Write-Warning` whenever the content would actually change.
4. **The scenario's entire purpose is a monitoring-coverage reduction across a workspace's SQL
   pools — that needs to be said plainly.** Same finding as the sibling, restated for Synapse's
   dual-pool surface (both dedicated and serverless pools lose visibility into the excluded
   classifications, not just one).
   - **Resolution:** `README.md` §2 and §11 state the coverage-reduction tradeoff explicitly.
5. **`GET`-then-`PUT` on the scan has no concurrency guard (TOCTOU).** Same limitation the base
   `scan-azure-synapse-and-classify` scenario and the Azure SQL Database sibling both already
   carry — Microsoft's Scans REST reference documents no concurrency-token mechanism.
   - **Resolution:** Not changed — a pre-existing, repo-wide limitation, not one this scenario
     introduces. Noted here for visibility rather than re-litigated per scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Narrowing classification scope across a Synapse workspace is a security-relevant change with
   no operational guidance on how to detect it after the fact.** Same finding as the sibling.
   - **Resolution:** `README.md` §8/§11 instruct pulling **Scan rule set: Create/Update/Delete**
     Management-category audit events (via the `PurviewDataMapOperation` Microsoft Graph security
     audit log record type) into the same SIEM/Sentinel pipeline used for this repo's other Purview
     audit activity, matching the sibling's own resolution.
2. **A reader could assume this scenario also resolves the base scenario's still-open
   `resourceTypes` VERIFY, since both concern the same scan object.** The original draft's
   design.md did not explicitly say this scenario is neutral on that point.
   - **Resolution:** `design.md` §2 goal 2 and §5 explicitly state the reconcile step preserves
     whatever `resourceTypes` state already exists without deciding it one way or the other, and
     `README.md` §11 carries the same disclosure forward so it isn't mistaken for a new finding.
3. **No structured/machine-readable deploy summary.** Same non-fix as the sibling — colored
   `Write-Host` text matches every other scenario's script style in this repo; introducing
   structured output here alone would be an inconsistent, scenario-local deviation.
   - **Resolution:** Not changed — same repo-wide-follow-up framing as the sibling's own review.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

1. **Residual risk is real and now explicit, not hidden.** Same framing as the sibling, restated
   for a workspace's full SQL-pool surface: `README.md` §2/§11 state plainly that the ~198 excluded
   classifications are genuinely un-monitored across both dedicated and serverless pools once this
   scenario is applied.
2. **No new licensing spend.** Confirmed — this scenario reuses the base scenario's PAYG Data Map
   billing with no new consumption meter (`README.md` §10).
3. **Compliance narrative is directly demonstrable**, and arguably more valuable here than on the
   Azure SQL Database sibling: a Synapse workspace often aggregates data from many upstream sources
   into one analytics surface, so a scoped `excludedSystemClassifications` array on the workspace's
   own scan is legible evidence that the analytics layer's discovery scope was deliberately
   narrowed to match the compliance driver, not left at whatever the platform happened to ship.
4. **Change-management dependency is named, not glossed over.** Same as the sibling — a changing
   regulatory driver requires a manual re-run with an updated `-RetainedSystemClassifications` list.
5. **The naming-trap fix (Red Team finding 1) is itself a fundable, not just technical, point.** A
   rollback that silently mis-targets a nonexistent System ruleset name is exactly the kind of
   avoidable incident that erodes trust in an automation program; catching and hard-coding the
   correct value during the build, rather than after a customer hits it, is the kind of engineering
   diligence a CISO evaluating this repo as a vendor deliverable should expect to see repeated
   across every sibling scenario as the pattern is reused for more source types.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, independently-confirmed API surface for this specific source type.** The Custom
   `AzureSynapseWorkspaceScanRuleset` shape and its `kind: AzureSynapseWorkspace` value were
   confirmed via direct fetch of the Az.Purview PowerShell module's own GitHub source — a real
   Microsoft-maintained reference, not a guess by analogy from the Azure SQL Database sibling. The
   `learn.microsoft.com` REST reference page itself could not be independently direct-fetched in
   this build environment (`EGRESS_BLOCKED`, the same restriction the base Synapse scenario's own
   build hit and worked around the same way); this is disclosed as an open VERIFY in `README.md`
   §11 rather than silently treated as equivalent-strength evidence to a direct REST-reference
   fetch.
2. **Not reinventing a native capability.** Same as the sibling — this scenario configures
   Purview's own native custom scan rule set feature exactly as Microsoft's own guidance describes
   the use case, applied to Azure Synapse Analytics instead of Azure SQL Database.
3. **Correctly distinguishes a genuine source-type difference from a copy-paste shortcut.** The
   system-name-vs-kind naming trap (design.md §2 goal 6) is exactly the kind of product-specific
   nuance a reviewer familiar with the real API surface would catch — treating Azure Synapse
   Analytics as "the same pattern as Azure SQL Database with different strings substituted" would
   have shipped a rollback script that targets a nonexistent ruleset name.
4. **Design choice (live Types API query vs. a hard-coded snapshot) inherited correctly.** The
   Types API is tenant-wide and source-type-agnostic, so reusing the sibling's own confirmed call
   shape unchanged here — rather than re-deriving it from scratch — is the right amount of new
   grounding work for what is genuinely a shared surface, not a missed verification step.

No Fix/Fail raised.

---

## Summary

Two lenses (Red Team, Blue Team) raised Fix items; all are resolved in
`deploy/New-PiiOnlyScanRuleset.ps1`, `deploy/Remove-PiiOnlyScanRuleset.ps1`, `design.md`, and
`README.md` as described above. The highest-value finding (Red Team #1) was a naming trap specific
to this source type that a naive port of the Azure SQL Database sibling's pattern would have
shipped as a working-looking but incorrect default. CISO and Microsoft Product Owner passed without
required changes. No Fail verdicts. Fragment meets `AGENTS.md` §9's definition of done.
