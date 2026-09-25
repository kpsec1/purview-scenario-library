# Four-Lens Review — UAMI Credential for the Azure SQL Database Scan

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; every **Fix** was applied to the scenario before this file was finalized (see
"Resolution" under each).

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A confirmed kind mismatch on the referenced credential was only a `[WARN]`, the same severity
   as an ambiguous 404.** The original draft's precheck treated "credential not found" (which could
   mean absent, OR simply not visible to this identity — genuinely ambiguous) and "credential found
   but is the wrong kind" (unambiguous — Purview's `CredentialType` enum is closed and this **will**
   fail at run time) identically, as a non-fatal warning an operator could scroll past. That let a
   `-CredentialReferenceName` pointed at, say, a `ServicePrincipal` credential reconcile the scan
   silently, deferring the failure to the next scheduled scan run instead of surfacing it at deploy
   time when it's cheapest to fix.
   - **Resolution:** the deploy script now hard-stops (`throw`) on a confirmed kind mismatch, distinct
     from the 404 case, which still only warns (genuinely ambiguous — could be a permissions gap, not
     a missing object). A new `-Force` switch exists for the rare case of an intentional test. See
     `deploy/New-AzureSqlManagedIdentityCredentialScan.ps1`'s precheck block and `README.md` §6.

2. **Reconciling onto a `ManagedIdentity` credential removes the only Key Vault-side detective
   control the base scenario's alternative auth paths (SQL auth, service principal) would have
   had.** Inherited directly from `scan-credential-remaining-kinds` (its own Red Team finding 1): a
   `ManagedIdentity` credential carries no secret, so there is nothing for a Key Vault `AuditEvent`
   diagnostic log to catch if the credential is silently re-pointed. Reviewed and confirmed correctly
   disclosed by reference rather than needing independent re-derivation.
   - **Resolution:** No change needed — `README.md` §8 already states this and points at the
     estate-wide inventory report as the only available detective control, matching the parent
     scenario's own disclosure pattern.

3. **The rollback path (`Remove-...ps1`) reverts the scan's `kind`/`credential` but never verifies
   the SAMI's own grants are still intact before doing so.** Confirmed as an inherited, disclosed
   limitation rather than a new gap: no Purview API exists to check an Azure IAM role assignment or
   a SQL external-provider user from the Scanning data-plane, the same boundary every other
   credential-consuming script in this repo respects (`scan-credential-key-vault-backed/README.md`
   §7). `rollback.md` states the precondition explicitly rather than silently assuming it.
   - **Resolution:** No code change — already disclosed; confirmed consistent with repo-wide scope.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No detective control exists for the *scan's own* credential reference drifting, as distinct
   from the *credential object's* content drifting.** `scan-credential-inventory-report` fingerprints
   and diffs credential objects (their `principalId`/`resourceId`/`tenantId`), but has no concept of
   which scans reference which credential — it would never catch this specific scan being
   re-pointed at a different, still-perfectly-valid `ManagedIdentity` credential object. The original
   draft didn't call this distinction out, potentially leaving a reader to assume the inventory
   report's existing coverage was sufficient here too.
   - **Resolution:** `README.md` §8 gained an explicit paragraph naming the gap and the only
     available mitigation (a scheduled `validate/...  -ExpectedCredentialReferenceName` run) — no
     code fix is possible, since no Purview audit event or scan-to-credential-reference API exists to
     build one against (consistent with `AGENTS.md` §4: disclose, don't invent an endpoint).

2. **Signal-to-noise and on-call burden are otherwise unchanged from the base scenario** — this
   fragment changes authentication only, not scan scheduling, failure classification, or run-history
   retention. Confirmed no new alert type, KPI, or runbook step is needed beyond what's added above.
   - **Resolution:** No change.

3. **`validate/`'s `-CheckCredentialObject` check correctly distinguishes "scan misconfigured" from
   "credential object itself is gone/wrong-kind."** Traced both code paths: Check 2/3 fail on the
   scan's own properties; Check 4 (separate, opt-in) fails on the referenced object's state — an
   operator running both can tell which side broke without manually cross-referencing two GET calls.
   - **Resolution:** No change needed — confirmed by design, not asserted.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass (with one Fix applied)**

1. **Would I fund this? Yes, selectively.** For an MSSP or an enterprise with a genuine
   segregation-of-duties requirement across sources, this closes a real blast-radius gap at low
   incremental cost (no new licensing surface — §10). It is not, however, a blanket improvement over
   SAMI for every source; the original draft didn't say so clearly enough.
   - **Resolution:** `README.md` §8 gained an explicit "adopt selectively" paragraph recommending
     phased rollout starting with the highest-sensitivity sources, naming the per-UAMI coordination
     cost as the reason not to blanket-apply this to every scan.

2. **Compliance mapping is concrete, not generic.** SOC 2 CC6.1 and ISO 27001 A.8.2 are both cited
   with the specific control this scenario maps to (per-source identity scoping / blast-radius
   reduction), not a vague "improves security" claim.
   - **Resolution:** No change — confirmed specific in `README.md` §2.

3. **Residual risk, accepted and bounded: the `ManagedIdentity` kind's Preview status**, inherited
   from `scan-credential-remaining-kinds`. A production rollout built on a preview capability could
   be disrupted by an undocumented behavior change.
   - **Resolution:** Already disclosed at draft time (§10, §11, and the parent scenario's own
     runtime warning) — reviewed and confirmed sufficient without further change.

---

## 🟦 Microsoft Product Owner

**Verdict: Fail (resolved)**

1. **FAIL — two sibling scenarios' own READMEs asserted this exact wiring was "not built here" and
   were left uncorrected in the original draft.** `scan-credential-remaining-kinds/README.md` §6
   stated wiring a UAMI credential into `scan-azure-sql-and-classify` was "the most immediately
   actionable follow-up... not built here," and `scan-azure-sql-and-classify/README.md` §6 still
   described `AzureSqlDatabaseCredential` only in terms of SQL auth/service principal. Shipping this
   fragment without correcting both would repeat the exact consistency failure `scan-credential-
   remaining-kinds`'s own review round flagged against *its* parent scenario ("a new folder does not
   retract an old assertion") — and this time the fragment being reviewed would be the one leaving a
   stale claim behind, not just inheriting one.
   - **Resolution:** `scan-credential-remaining-kinds/README.md` §6's bullet rewritten in place as a
     RESOLVED entry pointing at this scenario (Azure SQL Managed Instance/Synapse left explicitly
     open), its "Related scenarios" section updated to link here, and
     `scan-azure-sql-and-classify/README.md` §6's alternative-kind row updated to name this
     scenario instead of only SQL auth/service principal.

2. **Correct feature for the job, grounded against the primary REST reference, not inferred.** The
   `AzureSqlDatabaseCredentialScanProperties`/`CredentialReference`/`CredentialType` shapes — and
   specifically that `CredentialType`'s enum includes `ManagedIdentity` as a sibling of `SqlAuth`/
   `ServicePrincipal` — were confirmed via a direct fetch of the Scans - Create Or Replace REST
   reference during this build, not assumed from the credential object's own kind name.

3. **Licensing is accurate** — no new metered surface introduced; the `ManagedIdentity` Preview
   caveat is carried forward, not omitted.

4. **No deprecated paths.** The T-SQL grant syntax and Azure IAM role-assignment steps in §5 were
   confirmed against the same current, non-legacy "Configure authentication for a scan" page the
   base scenario already cites — not a cached or superseded version.

5. **Not reinventing a native capability, and correctly scoped.** This scenario deliberately does
   not attempt to create the UAMI, attach it to the Purview account, or create the credential object
   — all three already have a documented, scripted home in `scan-credential-remaining-kinds`. Scope
   discipline matches that scenario's own conservative boundary (`design.md` §7 of both).

No remaining Fix/Fail after resolution.

---

## Round summary

| Lens | Verdict | Fix/Fail items | Status |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (WARN-only kind mismatch, inherited Key Vault-detection gap confirmed not new) | Kind-mismatch fixed in code; detection gap confirmed correctly disclosed, not new |
| 🔵 Blue Team | Fix | 1 (no detective control for scan-to-credential-reference drift) | Disclosed in docs (no code fix possible — no API exists) |
| 🎩 CISO | Pass | 1 (blanket-adoption framing) | Resolved — phased-adoption guidance added |
| 🟦 Microsoft Product Owner | **Fail** | 1 (two sibling scenarios' stale "not built here" claims left uncorrected) | Resolved — corrected in place, cross-linked both directions |

Carried forward as `PROGRESS.md` follow-ups (out of this fragment's scope, not blocked on a VERIFY):
the same wiring for the Azure SQL Managed Instance and Azure Synapse dedicated-pool sibling
scenarios (`scan-credential-remaining-kinds/README.md` §6 names both as still open); every VERIFY
already carried by `scan-azure-sql-and-classify` for the underlying Data Sources/Triggers REST body
shapes (unchanged by this fragment, which only ever calls the already-confirmed Scans endpoint); and
`scan-credential-remaining-kinds`'s own carried-forward `ManagedIdentity` GA/preview-status recheck,
which this scenario inherits unchanged.
