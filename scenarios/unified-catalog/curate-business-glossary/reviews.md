# Four-Lens Review - Curate a Business Glossary in Unified Catalog

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`User.Read.All` is a tenant-wide read-any-user grant for a scenario that only needs to
   resolve a handful of named owners.** Microsoft Graph publishes no application permission
   scoped narrower than "read every user in the directory" for resolving a UPN to an object ID.
   A compromised client secret for this automation's app registration therefore exposes basic
   profile data (name, job title, mail, manager, group membership context) for the entire
   directory, not just the glossary's owner/expert list - a blast radius well beyond what the
   scenario's actual task requires.
   - **Resolution:** `README.md` §3 now states this explicitly as a **compensating-controls**
     note rather than leaving it implicit: short secret expiry + vault-based rotation, and -
     since the Graph side genuinely cannot be narrowed further - scoping the Purview-side
     **Data Steward**/**Governance Domain Creator** role assignment to only the specific
     governance domain(s) this automation curates, not tenant-wide, so a leaked credential's
     *Purview*-side blast radius stays bounded even though its *Graph*-side exposure cannot be.
2. **Stale owner resolution.** `Resolve-ContactId` only confirms a UPN resolves to *an* Entra
   account - a departed employee's disabled-but-not-deleted account resolves successfully and is
   silently assigned as term owner indefinitely, with no signal to the operator that the "owner"
   no longer has any real accountability for the term.
   - **Resolution:** `README.md` §8 ("Ownership hygiene") now names this gap explicitly and
     directs it into the same offboarding/access-review process the RBAC model already
     recommends for other Purview role assignments, rather than treating resolved owners as
     self-maintaining.
3. **No content validation on the definition file itself.** The script trusts the JSON file's
   description/resource-link content completely - a merged PR with a misleading term definition
   (e.g. mischaracterizing a field's sensitivity, or a resource link to an attacker-controlled
   domain) would deploy exactly as written. This is not fixable in the tooling: the definition
   file **is** meant to be human-authored content, and the correct control is the same one this
   scenario's whole design argues for - pull-request review before merge/deploy (`design.md` §1).
   - **Resolution:** no code change; confirmed `README.md`'s framing throughout (§1, "reviewed
     the same way the rest of their infrastructure is - via a pull request") already states this
     as the intended control rather than implying the script itself validates content quality.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No documented answer to "who changed this term, and when" or "how would we detect drift."**
   The original draft shipped strong idempotent create/update/publish logic but no operational
   story for attribution or for catching a portal-made edit that silently gets overwritten by the
   next scripted deploy (§8 already warned that create/update reconciles to the file's content,
   but didn't say how an operator would *notice* the conflict before it happened).
   - **Resolution:** `README.md` §8 now documents the API's built-in `systemData.createdBy/At` /
     `lastModifiedBy/At` fields as the point-in-time attribution mechanism (with the honest caveat
     that there's no full change-history API beyond that single snapshot), and recommends running
     `validate/Test-BusinessGlossary.ps1` on a schedule - not just post-deploy - so a
     content-mismatch `[FAIL]` surfaces drift before the next deploy run silently clobbers it.
2. **Validation script's relationship check depends on both terms already existing in
   `$termsByName`.** If a related term failed its own existence check earlier in the same
   validation run, the relationship check for it is silently skipped (`if (-not
   $termsByName.ContainsKey($relatedName)) { continue }` - no explicit `[FAIL]`) rather than
   reported as a hard failure.
   - **Resolution:** Confirmed intentional, not a gap: the *term's own* existence check already
     reports `[FAIL]` earlier in the same run (the term-existence loop), so the relationship
     section skipping a term that's already failed doesn't hide any signal - it avoids a
     redundant second failure for the same underlying problem. No change needed.

No remaining Fail. Attribution and drift-detection guidance now meet the bar for an operable,
git-reviewed glossary process.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** this is a foundational enablement investment, not a risk-reduction
  control in the way the DLP/IRM scenarios are - its value is downstream (every later governance
  domain, data product, and access-policy scenario in this library depends on a curated glossary
  existing first). At **zero incremental PAYG cost** (§10 - the governed-assets meter doesn't
  start until an asset is actually attached), this is close to a free foundational step, which
  makes the funding decision easy.
- **Change-management impact:** the git-PR-review model (§1, §8) is the right fit for this
  library's target organization (a team already running infrastructure-as-code discipline elsewhere) and
  avoids the "who edited this term and why" ambiguity that pure portal-driven curation invites at
  scale. The DRAFT-by-default / explicit `-Publish` pattern gives a deliberate review gate that
  matches this repo's established "off by default" code standard.
- **Residual risk after the Red Team round:** the `User.Read.All` compensating-controls note
  (Red Team finding 1, above) is exactly the kind of finding a CISO needs surfaced, not buried -
  it's now explicit in Prerequisites rather than an implicit assumption a security review would
  have had to dig for. Accepting the residual Graph-side exposure (with the stated mitigations) is
  a reasonable and clearly-documented tradeoff, not a silent gap.
- **Would I fund this?** Yes - low cost, foundational for everything else in the Data Governance
  half of this library, and the residual risks are named rather than hidden.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Building production-recommended automation against a Public Preview API surface** deserves
   sharper visibility than a single closing-paragraph disclaimer. The Unified Catalog REST API is
   explicitly scoped by Microsoft to "only cover Unified Catalog features that are available in
   General Availability (GA)" even while the API itself is Public Preview - an important but easy
   to miss distinction (the *features* are GA; the *API surface* accessing them is not).
   - **Resolution:** Confirmed `README.md` already states this distinction accurately in its
     closing disclaimer (§12) and cites the operation-groups overview page directly; no content
     was inaccurate, but reviewed for prominence - the §11 Known Limitations section separately
     calls out the two concrete preview-surface risks (`nameKeyword` semantics, Business Domain
     "required" field discrepancy) rather than leaving the preview caveat as one generic footnote,
     which is the right level of specificity for a vendor-sellable deliverable.
2. **Why not just use the portal's CSV bulk-import instead of custom REST code?** An organization
   evaluating this scenario will reasonably ask why it doesn't reuse Microsoft's own native bulk
   path.
   - **Resolution:** `design.md` §3 already answers this with the single fact that settles it:
     bulk import "can't be used to edit or update glossary terms," quoted directly from Microsoft's
     own documentation - making this scenario's REST-based upsert a genuine capability gap-fill,
     not a reinvention of an existing feature. No further change needed.
3. **RBAC correctness** - checked against `docs/rbac-model.md` §5: **Data Steward** for term
   authoring and **Governance Domain Creator** for domain creation are both correctly cited as the
   *governance-domain-level* and *catalog-level* roles respectively, correctly distinguished from
   the separate Data Map collection-role model. No deprecated cmdlets or endpoints used - this
   scenario correctly avoids the classic (pre-Unified-Catalog) Atlas-API glossary endpoints in
   favor of the current Unified Catalog Terms/Business Domain operation groups.
4. **Sensible term set** - the four-term "Customer / Customer ID / Customer Lifetime Value / Net
   Promoter Score" example directly mirrors the term set Microsoft's own Cloud Adoption Framework
   guidance names as the canonical harmonization example (`README.md` reference 2), which is the
   right choice for a reference implementation an organization will recognize as idiomatic rather than
   contrived.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (Graph blast-radius compensating controls added; stale-owner review guidance added; content-validation gap confirmed as an intentional PR-review control, not a tooling gap) | Closed |
| 🔵 Blue Team | Fix | 2 (attribution/drift-detection guidance added; relationship-check skip behavior confirmed correct, not a gap) | Closed |
| 🎩 CISO | Pass | 0 | - |
| 🟦 Microsoft Product Owner | Fix | 4 (2 confirmed already correctly scoped/prominent, 2 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-BusinessGlossary.ps1`, and `deploy/Remove-BusinessGlossary.ps1`. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9.

## Maintenance addendum - 2026-09-27

Closed the open `README.md` §11 VERIFY on the Business Domain Create/Update "required" fields
(`systemData`/`thumbnail`/`domains`/`managedAttributes`, plus `id`/`parentId`) via a Microsoft
Learn MCP re-grounding pass: the REST reference's Request Body table is confirmed to reuse the
response `Domain` schema, so it over-marks response-only, server-computed fields as request-
required - a documentation-generation artifact, not a real API constraint. Microsoft's own
Disaster recovery for Unified Catalog article independently corroborates the minimal body this
scenario already sends. No code or behavior change; `README.md` §11/§12 and the deploy script's
`.NOTES` updated to record the closure and cite the exact evidence.

## Maintenance addendum - 2026-09-29

Fixed a citation-numbering error in `README.md` §12: references 16 and 17 (Business Domain -
Create, and the Business Domain operation group) were both printed as "16.", which silently
shifted every reference after them out of step with its own list position (though the two inline
citations that used printed numbers `[16]`/`[17]` still happened to resolve to their intended
entries). Renumbered references 17-21 sequentially and updated the one inline citation
(`README.md` §12's closing note) that pointed at the now-renumbered entry, from `[17]` to `[18]`.
No content, fact, or URL changed - numbering only. While re-verifying, also re-fetched the
`Terms - Query` REST reference (`Terms - Count`'s description and request/response shapes too)
directly via the Microsoft Learn MCP tool: both still expose `nameKeyword` only as an untyped-
semantics `string` filter ("Filter by name keyword" / "The keyword to search for duplicate
elements by name"), with no substring/prefix/tokenized statement - the open `nameKeyword` match-
semantics VERIFY (`README.md` §11, `design.md` §4) remains genuinely undocumented as of this
re-check, not narrowed further.
