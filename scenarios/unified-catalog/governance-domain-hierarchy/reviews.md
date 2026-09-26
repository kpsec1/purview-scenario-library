# Four-Lens Review — Governance Domain Hierarchy in Unified Catalog

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`isRestricted` was a silent full-replace-PUT data-loss bug, not just a documented risk.**
   The initial draft of `New-DomainRequestBody` only set `body.isRestricted` when the definition
   file's node explicitly declared it — every other field this run doesn't touch (`managedAttributes`,
   `domains`) was already correctly seeded from the live `Enumerate` snapshot per `design.md`
   Section 4's own stated discipline, but `isRestricted` was not. A domain restricted via the
   portal (this scenario's own worked example marks `Sales - EMEA` `isRestricted: true` for a GDPR
   review) would have had that restriction **silently cleared** on any future re-run whose
   definition file omitted the flag — exactly the kind of full-replace-PUT clobbering
   `curate-business-glossary/README.md` Section 11 already warned about in the abstract, but
   concretely present in this scenario's first draft.
   - **Resolution:** `deploy/New-GovernanceDomainHierarchy.ps1`'s `New-DomainRequestBody` now falls
     back to `$Existing.isRestricted` when the node doesn't declare the field, matching the
     treatment already given to `managedAttributes` and `domains`. Verified by re-reading the
     updated function: a node that never mentions `isRestricted` now preserves whatever the live
     domain already has, rather than defaulting the field out of the request body entirely.
2. **Data estate mapping could be mistaken for an access-control boundary.** The initial draft
   documented the mapping's mechanics (`design.md` Section 5) but never stated the one fact that
   matters most to a security reviewer: Microsoft documents this mapping as "recommended guidance,"
   not enforcement — a Data Steward on a mapped domain is not thereby restricted from any other,
   unmapped Data Map collection. Presenting this to an organization without that caveat risks it being
   sold or configured as a segregation control it does not provide.
   - **Resolution:** `README.md` Section 11 now states this explicitly, with the direct Microsoft
     Learn quote, and instructs that the real access boundary (if one is needed) is the separate
     Data Map collection-role assignment model in `docs/rbac-model.md` Section 5.
3. **`-Purge` on a domain with concepts this scenario didn't create.** Same class of finding
   `curate-business-glossary/rollback.md` already discloses for its own domain — a domain in this
   tree that has glossary terms/data products/OKRs/critical data elements added by other scenarios
   or portal users may reject the `Delete` call server-side until those are removed first.
   - **Resolution:** confirmed already disclosed in `rollback.md` ("Prerequisite the script does
     not check for you"); no further change needed beyond naming `Corporate`/`Sales` specifically
     as the domains most likely to have such dependents, since this scenario's own README positions
     them as a base other scenarios build on.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No explicit recommendation to re-run validation on a schedule for drift detection**, unlike
   `curate-business-glossary/README.md` Section 8's equivalent guidance. Given this scenario's own
   Section 8 already documents an "Attribute-definition drift" scenario (an admin renaming/expiring
   an attribute after deployment), the operational answer ("how would an operator notice before the
   next deploy run either errors or silently misbehaves") was implied but not stated.
   - **Resolution:** `README.md` Section 8's "Attribute-definition drift" paragraph now explicitly
     directs re-running `validate/Test-GovernanceDomainHierarchy.ps1` after any attribute-definition
     change, matching the glossary scenario's own drift-detection guidance pattern.
2. **The validate script's data estate mapping check is a `WARN`, not a `FAIL`, even when the
   block is completely absent.** This is a deliberate design choice (Section 5's disclosed
   ambiguity means a `FAIL` here could be wrong in either direction), but a `WARN` sitting next to
   other `PASS`/`FAIL` output could be scanned past in a CI log at scale.
   - **Resolution:** confirmed intentional and already labeled distinctly in the check's own
     description string ("VERIFY - undocumented semantics, README.md Section 11"), which surfaces
     the caveat inline in the same log line rather than requiring a reader to already know to
     discount it. No further change needed — a hard `FAIL` here would be worse (asserting confident
     ground truth about a field this build cannot actually confirm), and the message is
     self-explanatory without cross-referencing another document first.

No remaining Fail. Drift-detection guidance now matches this repo's established operational bar.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The "Governance Domain Owner" role was cited in this scenario's own Prerequisites table but
   was missing from `docs/rbac-model.md` itself** — a cross-cutting reference gap a CISO reviewing
   role assignments tenant-wide would hit immediately (the role exists and is required per
   Microsoft Learn, but this repo's own RBAC reference didn't list it as its own row, only implying
   it via "becomes domain owner by default" under Governance Domain Creator).
   - **Resolution:** `docs/rbac-model.md` Section 5 now has an explicit **Governance Domain Owner**
     row, grounded directly in Microsoft's own "governance domain owner role" edit requirement, and
     this scenario's `README.md` Section 3 cites it directly instead of describing it as "not
     currently broken out."
- **Risk reduction vs. cost:** same foundational-enablement category as `curate-business-glossary`
  — zero incremental PAYG cost (Section 10), high downstream leverage (every domain this scenario
  creates is a prerequisite location for later data products/terms/critical data elements in this
  library). Easy funding decision.
- **Change-management impact:** the git-PR-review model plus DRAFT-by-default publish gating scales
  the same governance discipline `curate-business-glossary` established from one domain to an
  entire federated tree — directly relevant to an organization past the single-domain pilot stage, which is
  this scenario's stated audience.
- **Residual risk after this round:** the data estate mapping ambiguity (Red Team finding 2) and
  the depth/count-ceiling enforcement uncertainty (README Section 11) are both named, not hidden,
  with a concrete recommended default (`-SkipDataEstateMapping` on first use) rather than left as
  an implicit risk a security review would have to surface unassisted.
- **Would I fund this?** Yes — same low-cost, foundational-value profile as its single-domain
  predecessor, with this round's fixes closing the one real security-relevant gap (the
  `isRestricted` clobber risk) before shipping.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **`docs/rbac-model.md` gap** — same finding as the CISO lens, from the product-correctness
   angle: a scenario citing a real, documented Microsoft role that the repo's own cross-cutting
   reference doesn't list is an internal-consistency defect, not just an operational one.
   - **Resolution:** same fix as above — `docs/rbac-model.md` Section 5 now lists **Governance
     Domain Owner** as its own row, cited directly from Microsoft's governance-domain management
     documentation.
2. **Correct positioning against the portal's native domain-creation wizard.** Checked: the portal
   has no bulk/file-driven way to author a domain tree (each domain is one wizard flow), so this
   scenario is a genuine capability gap-fill, not a reinvention of an existing bulk-import feature
   — unlike the glossary scenario, which had to explicitly rule out the CSV bulk-import path
   (`curate-business-glossary/design.md` Section 3), there is no comparable native alternative here
   to rule out.
3. **RBAC and API-surface correctness** — checked against `docs/rbac-model.md` Section 5 and the
   Business Domain operation group reference directly: **Governance Domain Creator** for new
   domains and **Governance Domain Owner** for edits are both correctly distinguished catalog-level
   vs. governance-domain-level roles; no deprecated (classic Atlas-API) domain endpoints used; the
   `2026-03-20-preview` API version matches this repo's other Unified Catalog scenarios exactly.
4. **Worked example fidelity** — the `Corporate → Sales (→ Sales - EMEA) / Marketing` shape
   directly mirrors Microsoft's own "Sample setup for data governance" walkthrough's
   `Corporate → Sales` federation example (README.md reference 8), which is the right choice for a
   reference implementation an organization will recognize as idiomatic.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (`isRestricted` clobber bug fixed in code; data estate mapping guidance-not-enforcement caveat added; `-Purge` dependent-concepts risk confirmed already disclosed) | Closed |
| 🔵 Blue Team | Fix | 2 (drift-detection re-run guidance added; WARN-vs-FAIL choice for the mapping check confirmed correct) | Closed |
| 🎩 CISO | Fix | 1 (Governance Domain Owner role added to `docs/rbac-model.md`) | Closed |
| 🟦 Microsoft Product Owner | Fix | 4 (same rbac-model.md gap fixed; 3 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`docs/rbac-model.md`, `deploy/New-GovernanceDomainHierarchy.ps1`, and
`deploy/Remove-GovernanceDomainHierarchy.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
