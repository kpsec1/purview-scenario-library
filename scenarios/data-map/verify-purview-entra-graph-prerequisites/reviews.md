# Four-Lens Review — Verify Purview / Azure SQL Managed Instance Microsoft Entra Prerequisites

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The JSON report is itself a privileged-role reconnaissance target.** Every report lists the
   *current full membership* of a tenant-wide, security-sensitive Entra role (object IDs, and
   best-effort display names) — exactly the intelligence an attacker attempting lateral movement or
   privilege escalation would want to collect, and this scenario manufactures it on a schedule. The
   original draft treated `-ReportPath` as a generic output path with no callout that its contents
   need the same handling discipline as the role membership it describes.
   - **Resolution:** `README.md` §11 now states this explicitly and points at the same access-
     restriction discipline `entra-privileged-role-monitoring`'s own audit trail already requires;
     `rollback.md`'s retention guidance was strengthened to match; `design.md` §9 records the
     reasoning (inherent to the report's purpose, not fixable in code — the mitigation is access
     control on the caller's filesystem, which this script cannot enforce on its own).
2. **The inventory CSV is an unguarded trust boundary for the drift check.** Drift is computed as
   "current Directory Readers members minus inventory rows" — so anyone who can edit
   `-ManagedInstanceInventoryPath` before a run can add their own (or a compromised) principal's
   object ID to it, and that principal's Directory Readers membership stops being reported as drift
   entirely. The original draft never named the inventory file as something requiring integrity
   protection, reading like an oversight rather than a disclosed boundary.
   - **Resolution:** `README.md` §11 now flags this explicitly with a concrete mitigation (treat the
     CSV as a change-controlled, reviewed artifact — the same discipline this repo's DLP scenarios
     already apply to their own device/user allowlists); `design.md` §9 records why this script
     cannot verify the file's provenance itself (no signing/attestation mechanism in scope).
3. **A FAIL result alone does not prove an attacker revoked the grant maliciously** — an
   administrative change during a legitimate identity security review is a far more likely cause
   than an attack. Considered as a possible finding, but not a gap: `README.md` §8's incident-
   response runbook already treats every FAIL as "confirm via the portal, then escalate," which does
   not assume malice and correctly leaves attribution to the human investigating.
   - **Resolution:** Not changed — confirmed already correctly scoped.

No remaining Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Exit code alone under-reports drift.** The script's exit code is non-zero only for a `FAIL`
   (a missing expected member); a new `WARN` — someone else being added to a shared, security-
   sensitive role — does not flip it, by design (drift is informational, not fatal). The original
   draft's Operations & tuning section listed drift review as a KPI but never warned that a pipeline
   gating only on exit code would silently miss it.
   - **Resolution:** `README.md` §8 now has an explicit "Alerting note" instructing the caller to
     also inspect `DriftMemberCount`/`DriftMembers` from the JSON report, not rely on exit code
     alone.
2. **No report history — the "FAIL count trend" KPI the original draft named has nothing to trend
   against.** Unlike this repo's rolling audit-trail export scripts (which merge and de-duplicate
   into one accumulating CSV), this script's `-ReportPath` is a point-in-time snapshot that gets
   overwritten on every run. The original draft named trending as a KPI without acknowledging the
   report format doesn't support it out of the box.
   - **Resolution:** `README.md` §8 now explicitly documents the gap and the operational fix
     (date-stamp `-ReportPath` per scheduled run and retain the series); `design.md` §7's "Report
     format" decision row cross-references it.
3. **No SIEM/Sentinel integration or self-scheduling.** Same as every other Data Map/Graph checker
   scenario in this repo — correctly out of scope for a single-scenario fragment (`design.md` §10
   Non-goals already states this); confirmed not a gap unique to this scenario.
   - **Resolution:** No change needed — confirmed correctly scoped.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **`RoleManagement.Read.Directory` will read as high-privilege to a security reviewer skimming
   permission names, slowing the approval this scenario needs to ever run.** It is in fact the
   least-privileged, read-only option of four alternatives Microsoft documents for the exact two
   cmdlets this script calls — but the original draft's prerequisites table stated the requirement
   without pre-empting that objection, risking a slower approval cycle than the actual risk
   warrants.
   - **Resolution:** `README.md` §3 now has an explicit "For the approval conversation" callout
     naming the three broader alternatives and stating plainly that this permission cannot assign,
     remove, or modify any role membership.
2. **Coordination cost is proportionate and one-time.** Unlike the sibling scenario's own Directory
   Readers *grant* (a standing Privileged Role Administrator relationship), this scenario's own
   permission (`RoleManagement.Read.Directory`) is requested once, by whoever stands up the checker's
   app registration — it does not create an ongoing per-instance approval burden the way the
   sibling's grant does.
3. **Risk reduction vs. cost: proportionate.** The cost is one script plus one narrow, read-only
   Graph permission; the risk closed is a *silent, tenant-wide* authentication failure for every
   Managed-Instance-backed Purview source, discovered today only by noticing stale scan results.
   Direct, measurable improvement over "no signal at all."
4. **Board-level narrative:** "we detect the loss of a scan-critical Entra prerequisite before it
   causes an unnoticed classification-coverage regression, not after" is a defensible, specific
   claim — not marketing filler.
5. **Would I fund this?** Yes — low, one-time cost; the alternative (finding out from a failed
   audit or a stale-data incident) is materially worse.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Reinventing-a-native-capability check found a real overlap risk, now resolved by explicit
   differentiation, not by assumption.** Microsoft publishes its own broader Purview data-source
   readiness checklist (`data-map-data-sources-check-azure-readiness`) that also validates
   Entra-authentication-adjacent prerequisites for a Managed Instance data source. The original
   draft was written without checking whether that native tool already covers this scenario's exact
   check, which could have made this entire fragment redundant.
   - **Resolution:** This build's grounding pass confirmed Microsoft's script validates the
     **Purview account's own managed identity** (Reader/`db_datareader`/network/firewall/Entra-
     authentication-enabled), not Directory Readers membership for the **managed instance's own**
     identity — a different identity, checked for a different purpose, at a different cadence
     (one-time readiness vs. this scenario's ongoing monitoring). `design.md` §8 records the
     comparison; `README.md` §3 and §12 cross-reference Microsoft's script explicitly so an organization
     runs both rather than assuming either alone is sufficient.
2. **`RoleManagement.Read.Directory` confirmed as the least-privileged, current, non-deprecated
   option** for both `Get-MgDirectoryRole` and `Get-MgDirectoryRoleMember`, corroborated across
   independent search results for each cmdlet plus the equivalent REST reference pages (List
   directoryRoles / List members of a directory role) — not asserted from a single source.
3. **No deprecated cmdlets used.** `Get-MgDirectoryRole`/`Get-MgDirectoryRoleMember` are current
   Microsoft.Graph.Identity.DirectoryManagement (v1.0-surfaced) cmdlets, not the retired AzureAD/
   MSOnline module family this repo's other scenarios have already flagged as deprecated elsewhere.
4. **Grounding-strength disclosure is accurate and necessary, not a Fail.** This build's environment
   blocked direct `learn.microsoft.com` fetches (egress policy — see `PROGRESS.md` "Blocked / needs
   user"), so every citation rests on Microsoft Learn-hosted WebSearch results, corroborated across
   at least two independent queries per fact, rather than a verbatim page fetch. `README.md` §12
   discloses this plainly rather than presenting WebSearch-derived facts as fetch-confirmed —
   consistent with this repo's established practice for the same environment constraint in prior
   fragments.
5. **Licensing citation accuracy** — confirmed no licensing delta: reading a built-in Entra ID
   directory role's membership is available on every Entra ID tier including Free, correctly
   distinguished from the *paid* Entra P1/P2 add-ons `docs/licensing-matrix.md` §8–9 document for
   other scenarios in this repo.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via explicit sensitivity/integrity documentation, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed via alerting/report-history guidance, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (approval-conversation framing added); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (native-capability overlap checked and explicitly differentiated, not assumed); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Confirm-DirectoryReadersMembership.ps1`, and
`validate/Test-DirectoryReadersMembershipInputs.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.
