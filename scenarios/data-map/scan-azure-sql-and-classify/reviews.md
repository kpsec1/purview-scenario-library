# Four-Lens Review — Data Map Scan Azure SQL Database and Classify Sensitive Columns

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Over-broad Azure IAM `Reader` scope.** The original draft told the operator to grant the
   Purview SAMI `Reader` "on the SQL Server/resource group/subscription scope you want the scan
   to reach" without recommending the narrowest of those three. Granting `Reader` at the resource
   group or subscription level gives the Purview account's managed identity read visibility into
   *every other resource* in that scope, not just the targeted SQL server — a lateral
   information-disclosure risk if the Purview account (or an attacker who compromises an identity
   with control over it) is ever misused, and a much larger blast radius than this scenario
   actually needs.
   - **Resolution:** `README.md` §3 and §5 now explicitly recommend scoping `Reader` to **the SQL
     Server resource itself**, with the broader-scope tradeoff called out inline rather than left
     implicit.
2. **The "Allow Azure services and resources to access this server" firewall toggle is a bigger
   opening than its name suggests.** The original draft listed it as a same-weight alternative to
   a managed VNet or self-hosted IR without noting that it accepts connection attempts from *any*
   Azure-hosted resource in *any* tenant, not just this Purview account.
   - **Resolution:** `README.md` §5 step 4 now states the tradeoff explicitly and recommends a
     managed virtual network or self-hosted IR for a production database instead.
3. **`db_datareader` is a broad read grant relative to "classify a few columns."** The SAMI can
   read every row of every table it's granted access to, not just the columns that end up
   classified as sensitive — an inherent tension in any content-sampling classification design,
   not a bug in this specific script.
   - **Resolution:** Not changed — flagged here for visibility rather than as a fixable gap. This
     is the same trust model Microsoft's own SAMI-based scanning requires by design; the
     mitigation is process (who can assign the SAMI's IAM/SQL grants — already covered by
     `docs/rbac-model.md`'s Collection Admin gatekeeping), not a scripting change. Noted in
     `design.md` §4's table as an explicit part of the trust boundary rather than glossed over.
4. **Client secret handling.** `-ClientSecret` is a `SecureString` parameter, matching this
   repo's minimum bar, but the deploy/validate scripts decrypt it to a plaintext string in memory
   to build the OAuth2 token request body (the Data Map token endpoint requires a plaintext
   `client_secret` form field — there is no certificate-based alternative documented for this
   specific data-plane token flow, unlike surfaces 1–3 in `docs/automation-surface.md`).
   - **Resolution:** Not changed — this is the standard, Microsoft-documented pattern for this
     one data-plane token endpoint (`README.md` reference 3), and the scripts scope the plaintext
     variable narrowly (`finally { $plainSecret = $null }`) rather than leaving it live longer
     than necessary. Flagged in `design.md` as a known deviation from this repo's usual
     certificate-preferred pattern, not silently normalized.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No incident-response runbook for scan failures.** The original draft correctly noted that
   Data Map scans don't generate alerts the way DLP rules do, and pointed at polling
   `validate/Test-AzureSqlDataMapScan.ps1`, but stopped short of saying what an operator should
   actually *do* when a poll turns up a non-`Succeeded` status.
   - **Resolution:** Added a four-step runbook to `README.md` §8 covering triage, the four most
     likely failure causes ranked by likelihood (firewall/network, SAMI database-grant loss,
     ARM-path break from a resource move, transient failure), remediation, and an escalation
     trigger.
2. **Validate script's scan-history check has a silent failure mode.** The scan-run-history REST
   call is one of this scenario's VERIFY-tagged endpoints (unconfirmed exact shape); if the call
   fails for a reason unrelated to "no run has happened yet," the original draft's catch block
   would have looked identical to the "not yet run" case.
   - **Resolution:** `validate/Test-AzureSqlDataMapScan.ps1`'s catch block explicitly names the
     VERIFY status and tells the operator to check the portal directly, rather than presenting an
     ambiguous warning that could be mistaken for "everything's fine, just hasn't run yet."
3. **No SIEM/Sentinel integration mentioned.** Correctly out of scope for a single-scenario
   fragment (per this repo's established pattern in `scenarios/dlp/pci-teams-exfil-block/`), and
   Data Map doesn't have an alert stream to route in the first place — confirmed not a gap, just a
   different operational model from the DLP scenarios' alert-based one.
   - **Resolution:** No change needed; `README.md` §8 already scopes detection to polling rather
     than overclaiming an alert integration that doesn't exist for this object type.

No remaining Fail. The runbook addition brings this to the same operability bar as the DLP
template scenario, adapted to Data Map's poll-based (not alert-based) failure model.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Uncapped PAYG cost growth.** The original draft correctly identified PAYG billing and gave a
   sizing note (frequency/source-count drives cost), but didn't translate that into a concrete
   governance action — a real risk for a foundational, "we'll scan everything eventually" scenario
   that a team could scale up without budget visibility.
   - **Resolution:** Added an explicit Azure Cost Management budget/alert recommendation to
     `README.md` §10, scoped to before rollout past "a handful of databases."
2. **Risk reduction vs. cost:** clear and proportionate once the cost-governance gap above is
   closed. This scenario is the evidentiary foundation ("we scanned, we found N classified
   columns, here's when") for every downstream Data Security control's compliance narrative — a
   comparatively low, metered cost for a capability every other scenario in this repo assumes
   already ran.
3. **Board-level narrative:** "we automatically and continuously discover where regulated data
   lives in our Azure SQL estate, instead of relying on a stale manual inventory" is defensible
   and specific, and the Red Team's residual-risk findings (broad `Reader`/`db_datareader` grants
   as an inherent trust boundary, not a fixable bug) are now documented rather than silently
   assumed away.
4. **Change-management impact:** low — registering a source and scanning it doesn't touch live
   M365 controls or user-facing behavior, unlike the DLP/labeling scenarios this repo has already
   shipped. The staged rollback in `rollback.md` (trigger-only → scan → full removal) gives a
   proportionate off-ramp at each level of commitment.
5. **Would I fund this?** Yes, with the budget alert now in place as a condition — bounded,
   metered cost, clear compliance-evidence payoff, and it's a prerequisite this repo's other
   funded controls (DLP, auto-labeling) already implicitly depend on.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Custom, PII-only scan rule set was originally presented as this scenario's default without a
   confirmed REST body.** The first draft's config table and design rationale described a "custom
   rule set scoped to SSN + Credit Card Number" as the shipped default, but this build's grounding
   pass never independently confirmed the exact REST JSON shape for the "Scan Rulesets - Create Or
   Update" operation — only that the product supports an exclusion-based custom rule set model (via
   the `Az.Purview` module's `New-AzPurviewAzureSqlDatabaseScanRulesetObject
   -ExcludedSystemClassification` parameter). Shipping a fabricated body for the scenario's default
   path would have violated `AGENTS.md` §4's no-invented-endpoints rule.
   - **Resolution:** Reworked `README.md` §1/§6/§11, `design.md` §2/§6/§7, and the deploy script's
     default `-ScanRulesetType 'System'` to ship Microsoft's **system default** scan rule set
     instead — which already includes the SSN/Credit Card Number pair this repo standardizes on,
     alongside ~200 other built-in SITs — and documented the custom-rule-set REST gap as an
     explicit VERIFY/follow-up rather than asserting an unverified shape.
2. **SAMI as the default authentication method is correct, current best practice.** Confirmed
   against Microsoft's own documentation, which labels system-assigned managed identity
   "(recommended)" among the four supported authentication options for this exact source type —
   this scenario's design choice aligns with product direction, not a workaround.
3. **No deprecated cmdlets/endpoints used.** The Scans object's API version (`2023-09-01`) was
   independently confirmed current via a direct fetch of Microsoft's own REST reference at build
   time; no `2021-*-preview` or other stale version is referenced as the primary path.
4. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`: Data Map scanning
   is correctly described as PAYG/Azure-consumption billed, not a per-user M365 entitlement,
   matching the cross-cutting matrix's existing "Data Map" row. No conflation with the separate
   Unified Catalog PAYG meter.
5. **Reinventing-a-native-capability check:** this scenario doesn't build a parallel discovery
   mechanism — it's a direct, idiomatic use of the Data Map REST surface Microsoft ships
   specifically for this purpose, following the same create-or-replace idempotency contract the
   API itself documents rather than layering extra state-tracking logic on top.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 closed via scope/tradeoff documentation, 2 confirmed as inherent trust-model notes rather than fixable gaps) | Closed |
| 🔵 Blue Team | Fix | 3 (1 missing runbook, closed; 1 ambiguous-failure-mode fix applied to the validate script; 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (cost-governance recommendation added); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (dropped an unverified custom-rule-set default in favor of the confirmed system default, with the gap tracked as a follow-up); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-AzureSqlDataMapScan.ps1`, and `validate/Test-AzureSqlDataMapScan.ps1`. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.

---

## Follow-up review — Run Scan / List Scan History REST shape correction (2026-09-04)

A targeted four-lens pass on the backported correction (not a full re-review of the scenario):
the sibling `scan-azure-sql-managed-instance-and-classify` build independently direct-fetched the
canonical **Scan Result - Run Scan** and **Scan Result - List Scan History** REST reference pages
this scenario's own build could not reach, and found both of this scenario's reconstructed shapes
were wrong (§11 VERIFY previously covered this — see `README.md` for the corrected text).

- **🔴 Red Team — Pass.** No new attack surface: the corrected call still authenticates with the
  same bearer token and least-privilege role as every other call in this script; a wrong endpoint
  shape was a reliability defect, not an exploitable one. Confirms the fix doesn't silently swallow
  a scan-run failure any differently than before.
- **🔵 Blue Team — Pass (closes a prior finding for real).** The original review's Blue Team fix
  (validate script's catch block naming the "VERIFY status" on scan-history failure, item 2 above)
  was a mitigation for an *unconfirmed* shape. With the shape now confirmed and corrected, the
  script's primary path reads the real nested fields directly — the catch-block fallback becomes a
  true "transient/permission error" handler rather than a mask for a shape guess. Text describing it
  updated in `validate/Test-AzureSqlDataMapScan.ps1`'s catch message accordingly.
- **🎩 CISO — Pass.** No cost or licensing impact. Slightly higher confidence in the classification
  coverage evidence this scenario produces for every downstream Data Security control, since
  `-RunNow`'s scan-trigger call and the validate script's asset counts it reports on are now
  grounded rather than best-effort.
- **🟦 Microsoft Product Owner — Pass.** `AGENTS.md` §4 says ground every product fact; this
  correction is exactly that discipline applied retroactively once better grounding became
  available elsewhere in the repo, rather than leaving a known-wrong shape shipped indefinitely.
  Two narrower VERIFY items remain open (Data Sources/Triggers body shapes for the `AzureSqlDatabase`
  kind specifically, and the two unrelated custom-rule-set/credential-object gaps) — not resolved by
  this pass, and not claimed to be.

No Fix/Fail from this follow-up pass.
