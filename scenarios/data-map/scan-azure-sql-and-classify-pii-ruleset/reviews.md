# Four-Lens Review - Data Map PII-Only Scan Rule Set for Azure SQL Database

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A `-ScanName`/`-DataSourceName` typo silently reconciles a mismatched scan.** The original
   draft's `deploy/New-PiiOnlyScanRuleset.ps1` fetched whatever scan the two parameters resolved
   to and PUT the new `scanRulesetName` onto it without checking that the scan's own `kind` is
   actually compatible with an `AzureSqlDatabase`-kind ruleset. A parameter typo that happened to
   collide with an unrelated existing scan name would succeed silently at deploy time and only
   surface as a failure the next time that unrelated scan runs - far away, in time and in the
   operator's attention, from the mistake that caused it.
   - **Resolution:** the script now checks `$existingScan.kind` against the two Azure SQL
     Database scan kinds (`AzureSqlDatabaseMsi`/`AzureSqlDatabaseCredential`) before touching
     anything, and throws immediately with a clear message if they don't match. See the script's
     inline comment above the check.
2. **Silent clobber of a shared, account-wide object.** `AzureSqlDatabaseScanRulesetProperties`
   has no `collection` property (design.md §2 goal 3) - a scan rule set is visible and reusable
   account-wide, not scoped to the team or collection that created it. The original draft's
   create-or-replace `PUT` would overwrite a same-named ruleset another team already relies on
   with zero indication anything changed, if both teams left `-ScanRulesetName` at its default.
   - **Resolution:** the script now `GET`s any pre-existing ruleset with the same name before the
     `PUT`, diffs its `excludedSystemClassifications` against the newly computed list, and emits an
     explicit `Write-Warning` naming how many classifications would newly become excluded vs. newly
     become retained whenever the content would actually change (a brand-new ruleset, or a re-run
     with identical content, stays silent - see design.md §2 goal 6).
3. **The scenario's entire purpose is a monitoring-coverage reduction - that needs to be said
   plainly, not just implied.** A PII-only ruleset is, by construction, blind to every
   classification it excludes: a credential, key, or out-of-program data category that would have
   triggered a System-default classification will simply never be flagged once this scenario is
   applied. This is not a bug to fix (it is the scenario's stated purpose - README.md §1-2), but
   the original draft's `README.md` §11 did not say so explicitly enough for a reviewer skimming
   limitations to catch it.
   - **Resolution:** `README.md` §11 now states the coverage-reduction tradeoff explicitly and
     cross-references the CISO lens's residual-risk framing below, rather than leaving a reader to
     infer "excludes 198 classifications" implies "loses visibility into 198 classifications."
4. **`GET`-then-`PUT` on the scan has no concurrency guard (TOCTOU).** Between this script's
   `GET` of the existing scan and its `PUT` of the reconciled body, another admin's concurrent
   change to the same scan (e.g. switching its authentication kind) would be silently overwritten.
   - **Resolution:** Not changed - this is the same limitation the base `scan-azure-sql-and-classify`
     scenario already carries (its `deploy/New-AzureSqlDataMapScan.ps1` has no ETag/If-Match
     support either, and Microsoft's Scans REST reference documents no concurrency-token
     mechanism). Not a gap this scenario introduces; noted here for visibility rather than
     re-litigated per scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Narrowing classification scope is a security-relevant change with no operational guidance on
   how to detect it after the fact.** The original draft validated the ruleset's *content* but
   said nothing about how a security team would notice, after deployment, that someone had
   narrowed (or widened) a production scan's classification coverage outside of this script.
   - **Resolution:** grounded during this review - Microsoft's own audit event catalog lists
     **Scan rule set: Create / Update / Delete** as an audited Management-category event
     (`README.md` reference 12), consumable via the `PurviewDataMapOperation` Microsoft Graph
     security audit log record type (reference 13). `README.md` §8 and §11 now instruct pulling
     these events into the same SIEM/Sentinel pipeline used for this repo's other Purview audit
     activity, so a ruleset narrowing gets the same review rigor as a DLP policy exception.
2. **No structured/machine-readable deploy summary.** The deploy and validate scripts emit
   colored `Write-Host` text, fine for an interactive run but not directly consumable by an
   automation pipeline that wants to log "ruleset X now retains Y, excludes Z" as structured data.
   - **Resolution:** Not changed - this matches every other scenario's script style in this repo
     (base `scan-azure-sql-and-classify` included); introducing structured output here alone would
     be an inconsistent, scenario-local deviation rather than a repo-wide pattern. Noted as a
     candidate repo-wide follow-up (a shared output-formatting convention), not a fix scoped to
     this one fragment.
3. **Scan run duration as a "did it work" signal is soft.** `README.md` §8's suggestion to compare
   scan duration before/after as a sanity check is directionally useful but not a hard pass/fail
   signal - a database schema change between runs could confound the comparison just as easily as
   the ruleset change.
   - **Resolution:** Not changed as a hard check - `validate/Test-PiiOnlyScanRuleset.ps1` already
     provides the actual hard verification (ruleset content, scan's ruleset reference); §8's
     duration note is explicitly framed as "a rough sanity check," not a validation gate, so no
     false confidence is implied.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

1. **Residual risk is real and now explicit, not hidden.** Once this scenario is applied, the
   ~198 excluded classifications are genuinely un-monitored by this scan - that is a deliberate,
   named tradeoff (faster scans, a catalog matched to a specific compliance driver) with a real
   cost (reduced blast-radius awareness for data categories outside that driver). `README.md` §2
   and §11 now state this plainly enough to put in front of a board: "this control narrows
   monitoring scope to a named list; anything outside that list is not this scan's job." That is
   fundable *because* it is honestly scoped, not despite it - a security program that tries to
   monitor everything everywhere often ends up meaningfully monitoring nothing well.
2. **No new licensing spend.** Confirmed - this scenario reuses the base scenario's PAYG Data Map
   billing with no new consumption meter (`README.md` §10). A CISO evaluating this as an add-on to
   an already-funded Data Map program sees a process improvement, not a new procurement.
3. **Compliance narrative is directly demonstrable.** A PCI DSS assessor asking "show me your
   cardholder-data discovery scope" gets a ruleset whose `excludedSystemClassifications` array
   *is* the evidence that scope was deliberately and narrowly configured - more legible than
   pointing at a System-default scan and explaining which of ~200 matched classifications are
   actually in scope for the audit.
4. **Change-management dependency is named, not glossed over.** §8 correctly states that a
   changing regulatory driver requires a manual re-run with an updated
   `-RetainedSystemClassifications` list - this is a process control (who reviews the retained
   list, how often), not a scripting gap, and the CISO lens agrees that is the right place to draw
   the line for this fragment.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct API surface, current API version.** `scan/scanrulesets/{name}` (Create Or Replace /
   Get / Delete) is the confirmed, current (`2023-09-01`) REST surface for this exact operation -
   direct-fetched in full during this build, not reconstructed from adjacent evidence (the gap the
   base scenario's `README.md` §11 explicitly carried forward). This closes that VERIFY rather
   than leaving it open a second time.
2. **Not reinventing a native capability.** This scenario does not build a custom
   classification-filtering layer on top of Purview's output; it configures the product's own
   native custom scan rule set feature exactly as Microsoft's "Create a scan rule set in Data Map"
   guidance describes the use case ("if your data is limited to specific kinds of information...
   create a custom scan rule set that excludes identification for other regions" - the same
   pattern, applied to a PII/PCI program instead of a region).
3. **Correctly identifies and respects an unscriptable adjacent feature.** Custom classification
   *rule* authoring (as opposed to referencing one by name) is correctly left out of scope with a
   grounded citation (no documented REST endpoint; Microsoft's own community guidance states
   portal-only) rather than guessed at - consistent with how the base scenario handled the
   credential-object creation gap.
4. **Design choice (live Types API query vs. a hard-coded snapshot) is the more product-aligned
   pattern, not just the safer one.** Querying the tenant's own current type definitions instead
   of shipping a point-in-time list means this scenario stays correct as Microsoft's own
   classification catalog evolves, without requiring a repo update - the kind of design a product
   team would recognize as "using the platform as intended" rather than working around it.

No Fix/Fail raised.

---

## Summary

Two lenses (Red Team, Blue Team) raised Fix items; both are resolved in `deploy/New-PiiOnlyScanRuleset.ps1`
and `README.md`/`design.md` as described above. CISO and Microsoft Product Owner passed without
required changes. No Fail verdicts. Fragment meets `AGENTS.md` §9's definition of done.
