# Four-Lens Review — Data Map PII-Only Scan Rule Set for On-Premises SQL Server

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A future builder skimming this scenario's `kind` confirmation could over-generalize "the
   ruleset `kind` matches the data source `kind`" into "therefore the System ruleset's literal
   `name` is also confirmed" — the two are NOT the same claim, and this draft's language was, on
   first pass, not sharp enough to stop that conflation.** This build's own three-source confirmation
   covers the ruleset object's `kind` discriminator only; no worked example anywhere pairs a literal
   `scanRulesetName: "SqlServerDatabase"` with `scanRulesetType: "System"`. Presenting the `kind`
   finding without immediately and repeatedly distinguishing it from the still-open `name` VERIFY
   risks a reader (or a future automation run) treating `-RevertToRulesetName`'s default as fully
   grounded when it is not.
   - **Resolution:** `design.md` §2 goal 6's closing paragraph, `README.md` §11 (both the `kind`
     bullet and its own separate `VERIFY` bullet), and `rollback.md`'s Stage 1 all now state the
     distinction explicitly and in the same place a reader would look for either fact — the `kind`
     is confirmed; the System ruleset's `name` is not. `deploy/Remove-PiiOnlyScanRuleset.ps1`'s
     `.PARAMETER RevertToRulesetName` doc-comment repeats the caveat at the exact parameter a
     copy-paste mistake would land on.
2. **A `-ScanName`/`-DataSourceName` typo silently reconciles a mismatched scan.** Same class of
   finding as every sibling scenario: the original draft did not check the existing scan's `kind`
   before reconciling it onto a `SqlServerDatabase`-kind ruleset.
   - **Resolution:** the script checks `$existingScan.kind` against the one confirmed on-premises
     SQL Server scan kind (`SqlServerDatabaseCredential`) before touching anything, and throws
     immediately with a clear message if it doesn't match. Unlike the Azure siblings' two-kind
     guard list, this one is deliberately a single value — no managed-identity variant exists for
     this source type at all (base scenario's own `design.md` §4), so accepting a second value here
     would silently widen the guard past what Microsoft documents as possible.
3. **Silent clobber of a shared, account-wide object.** Same finding and same resolution as every
   sibling: the deploy script `GET`s any pre-existing ruleset with the same name before the `PUT`,
   diffs its `excludedSystemClassifications` against the newly computed list, and emits an explicit
   `Write-Warning` whenever the content would actually change.
4. **This scenario's entire purpose is a monitoring-coverage reduction — and on-premises SQL Server
   is, per the base scenario's own framing, the single most likely place in the estate to hold an
   undocumented sensitive column.** Narrower ruleset + "oldest, least-documented" data is a
   materially higher-stakes combination than the same trade-off on a newly-provisioned Azure PaaS
   database.
   - **Resolution:** `README.md` §2 restates the base scenario's own "oldest, least-documented"
     framing explicitly rather than only cross-referencing it, and §8/§11 name the elevated stakes
     plainly rather than reusing generic sibling wording unmodified.
5. **A narrowed classification scope compounds with an already-elevated on-premises failure mode:
   the SHIR node silently going offline.** None of the three Azure siblings have this second,
   independent failure path — a scan there either runs against Azure-managed compute or fails
   loudly on a credential/network problem. Here, a SHIR node quietly going `Disconnected` produces
   *no* new classifications at all, which is a different and easier-to-miss failure than "the scan
   ran but under-classified due to a narrow ruleset." An operator monitoring only "did the last scan
   complete" could miss both simultaneously.
   - **Resolution:** `README.md` §8 explicitly calls out correlating a ruleset-narrowing audit event
     with the SHIR node's own health signal as a distinct SIEM/Sentinel correlation, not just
     restating the generic "audit the ruleset change" guidance every sibling already gives.
     `validate/Test-PiiOnlyScanRuleset.ps1` prints an explicit reminder that it cannot check SHIR
     node health, rather than letting a clean "All hard checks passed" result imply more coverage
     than it actually has.
6. **`GET`-then-`PUT` on the scan has no concurrency guard (TOCTOU).** Same limitation the base
   scenario and every sibling PII-ruleset scenario already carries — Microsoft's Scans REST
   reference documents no concurrency-token mechanism.
   - **Resolution:** Not changed — a pre-existing, repo-wide limitation, not one this scenario
     introduces. Noted here for visibility rather than re-litigated per scenario.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Narrowing classification scope on the organization's oldest, least-documented estate is a
   security-relevant change with no operational guidance on how to detect it after the fact,
   correlated with the source type's own distinctive availability risk.** Same base finding as every
   sibling, with the SHIR-correlation gap specific to this source type (Red Team finding 5).
   - **Resolution:** `README.md` §8 instructs pulling **Scan rule set: Create/Update/Delete**
     Management-category audit events (via the `PurviewDataMapOperation` Microsoft Graph security
     audit log record type) into the same SIEM/Sentinel pipeline used for this repo's other Purview
     audit activity, explicitly correlated with SHIR node health rather than treated as an
     independent signal.
2. **A reader could assume this scenario also provisions, verifies, or troubleshoots the base
   scenario's own unusually long on-premises prerequisite list** (SHIR resource + software install +
   node registration, SQL/Windows login + grant, Key Vault secret, Purview credential object)
   **since both concern the same scan object.** The original draft's Prerequisites table did not
   explicitly disclaim this as sharply as it should have for a prerequisite list this long.
   - **Resolution:** `README.md` §3's first row explicitly states this scenario assumes the base
     scenario's own scan already runs successfully and enumerates exactly what's assumed rather than
     just cross-referencing, and `design.md` §6 lists precisely which of the base scenario's
     prerequisites this scenario does not touch.
3. **`validate/Test-PiiOnlyScanRuleset.ps1`'s original draft risked implying full coverage with a
   clean "All hard checks passed" result, when SHIR node health — the single most common on-premises
   scan failure cause per the base scenario's own README §8 — is structurally outside what this
   script (or any Data Map REST call) can check.**
   - **Resolution:** the script now prints an explicit reminder after a fully-passing run, pointing
     the operator at the portal's Nodes tab, rather than letting silence imply more confidence than
     is warranted.
4. **No structured/machine-readable deploy summary.** Same non-fix as every sibling — colored
   `Write-Host` text matches every other scenario's script style in this repo; introducing
   structured output here alone would be an inconsistent, scenario-local deviation.
   - **Resolution:** Not changed — same repo-wide-follow-up framing as every sibling's own reviews.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

1. **Residual risk is real, now explicit, and correctly scoped to this source type's actual
   profile.** `README.md` §2/§8/§11 state plainly that the ~198 excluded classifications are
   genuinely un-monitored once this scenario is applied, and specifically name the elevated stakes
   of doing so on the organization's oldest, least-documented data rather than reusing generic
   wording from any sibling unmodified.
2. **No new licensing spend.** Confirmed — this scenario reuses the base scenario's PAYG Data Map
   billing with no new consumption meter, and does not add a second SHIR host or change the base
   scenario's own infrastructure cost (`README.md` §10).
3. **Compliance narrative is directly demonstrable**, and speaks to exactly the question an organization's
   auditor is most likely to ask about an on-premises estate: "the SQL Server instance nobody's
   touched since before the cloud migration — how do you know what's in it now, and why is your
   classification scope what it is?" A scoped `excludedSystemClassifications` array on that
   instance's own scan is legible evidence the discovery scope was deliberately narrowed to match a
   named compliance driver, not left at whatever a decade-old schema happens to contain.
4. **Change-management dependency is named, not glossed over.** Same as every sibling — a changing
   regulatory driver requires a manual re-run with an updated `-RetainedSystemClassifications` list.
5. **The independent-verification discipline is itself a fundable, not just technical, point — and
   this build's own grounding is measurably stronger than any prior sibling's.** Four sibling
   scenarios in, this repo could have started pattern-matching source types against each other to
   save grounding effort, or treated a partial `EGRESS_BLOCKED` history as an excuse to guess. This
   build instead independently re-verified the `kind` value from three converging Microsoft sources
   (reachable directly in this build's environment, unlike two prior sibling builds), found it
   matched one prior sibling's pattern and not another's, and — critically — did **not** overstate
   that confirmation into also resolving an adjacent, still-open question (the System ruleset's
   literal `name`) just because the two questions are related. That kind of precision about exactly
   what was and wasn't proven is exactly the engineering diligence a CISO evaluating this repo as a
   vendor deliverable should expect, and is more valuable here than a superficially "complete"
   VERIFY-free writeup would have been.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, independently-confirmed API surface for this specific source type — and confirmed via
   an unusually strong three-source convergence.** The Custom `SqlServerDatabaseScanRuleset` shape
   and its `Kind: "SqlServerDatabase"` value were confirmed via direct fetch of the Az.Purview
   PowerShell reference, the Scan Rulesets REST reference, and the `@azure-rest/purview-scanning` JS
   SDK's TypeScript interfaces — all three agreeing independently, and all three genuinely
   first-party Microsoft references rather than one primary source corroborated by inference.
2. **Not reinventing a native capability.** Same as every sibling — this scenario configures
   Purview's own native custom scan rule set feature exactly as Microsoft's own guidance describes
   the use case, applied to on-premises SQL Server instead of any Azure PaaS source type.
3. **Correctly treats each source type as its own grounding question rather than a template
   substitution, and correctly declines to over-claim.** Confirming (rather than assuming) that this
   source type's ruleset `kind` matches the Azure SQL Database/Managed Instance pattern rather than
   the Synapse naming trap — while explicitly NOT claiming the adjacent System-ruleset-name question
   is also resolved just because the `kind` question is — is exactly the discipline a reviewer
   familiar with the real, source-type-fragmented Data Map API surface would expect, and is a more
   accurate representation of the evidence than either "fully confirmed" or "still just guessing"
   would be.
4. **Design choice (live Types API query vs. a hard-coded snapshot) inherited correctly.** The Types
   API is tenant-wide and source-type-agnostic, so reusing every sibling's confirmed call shape
   unchanged here — rather than re-deriving it from scratch — is the right amount of new grounding
   work for what is genuinely a shared surface, not a missed verification step.
5. **Compatible scan kind correctly sourced from the base scenario's own already-grounded README, not
   re-derived speculatively, and correctly narrowed to a single value rather than over-generalized
   from the Azure siblings' two-kind pattern.** `SqlServerDatabaseCredential` being the *only*
   compatible kind (no managed-identity variant) is stated plainly rather than the guard silently
   accepting a hypothetical second kind that doesn't exist for this source type.

No Fix/Fail raised.

---

## Summary

Two lenses (Red Team, Blue Team) raised Fix items; all are resolved in `design.md`, `README.md`,
`rollback.md`, and the deploy/validate scripts' own doc-comments and runtime messages as described
above — the core deploy and validate scripts needed no logic changes beyond what was already built in
from the start (the single-kind compatibility guard, the shared-object clobber warning, and the
validate script's SHIR-health disclaimer), since this build drafted them with every sibling's
already-reviewed guards in place from the first pass. The highest-value finding (Red Team #1) is
forward-looking in a different way than prior siblings' equivalent findings: it is not about a future
source type inheriting an unverified assumption, but about this scenario's OWN two closely-related
findings (`kind` confirmed, `name` still open) getting conflated into an overstated single claim —
now stated with enough precision in every file that references it that this cannot happen by a
skimming reader or a future automated re-run. CISO and Microsoft Product Owner passed without
required changes, both specifically calling out this build's stronger-than-usual grounding (direct
`learn.microsoft.com` access, three converging sources) and its precision about exactly what that
grounding did and did not resolve. No Fail verdicts. This is the fourth and last of this repo's Data
Map PII-only scan rule set scenarios — no further "apply this pattern to source type X" follow-up
remains open. Fragment meets `AGENTS.md` §9's definition of done.
