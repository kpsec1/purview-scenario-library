# Four-Lens Review — Manage a Data Product in Unified Catalog

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A `-Publish` run could silently ship a data product with no working access-request path.**
   If the REST `Update` operation does not itself enforce the portal's "must configure a data
   access policy before publish" business rule (an open VERIFY — `design.md` §5), this script's
   direct `PUT status: PUBLISHED` call could succeed even though no human has configured **who**
   can request access, what they attest to, or who approves. The result: a data product that
   *looks* live and discoverable in search, but whose "Request access" flow either fails silently
   or grants access with none of the intended approval gating — a worse failure mode than simply
   refusing to publish, because it's not visibly broken.
   - **Resolution:** `Publish-DataProduct` in `deploy/New-DataProduct.ps1` now prints a loud
     `Write-Warning` naming the access-policy prerequisite immediately before every publish
     attempt, not just a passive doc note. `README.md` §3 promotes the access-policy step to a
     **gating prerequisite row**, not a §11 footnote, and §11 records the enforcement question as
     an explicit VERIFY rather than assuming the safer (server-enforced) case. An operator running
     this script unattended still cannot be *stopped* by tooling alone — that's a real residual gap
     — but they can no longer miss the warning.
2. **The `-DeleteDataAssetWrapper` rollback flag has no safety check against orphaning another
   data product.** Because Unified Catalog data assets are shared, reusable wrappers (`design.md`
   §4), a second data product could reference the same wrapper this scenario created — and
   `Remove-DataProduct.ps1` has no reverse lookup ("which data products reference asset X") to
   detect that before deleting it.
   - **Resolution:** Confirmed no REST operation exists to perform that reverse lookup during this
     build's grounding pass — not a code gap this script can close. `-DeleteDataAssetWrapper`
     stays opt-in (never implied by `-Purge` alone), `rollback.md` states the manual-confirmation
     requirement in bold before showing the command, and `Remove-DataProduct.ps1` prints a
     `Write-Warning` at the point of deletion restating the risk. This is the same "state the
     residual risk explicitly rather than fabricate a check that doesn't exist" discipline this
     repo's other scenarios (e.g. `premium-legal-hold-and-export`'s audit-trail gap) already use.
3. **The Data Product Owner role, like Data Steward in `curate-business-glossary`, is
   domain-scoped but not asset-scoped.** A compromised or over-broadly-assigned Data Product Owner
   credential can create, edit, or unpublish *any* data product in its assigned domain(s), not just
   the "Customer Master Data" product this scenario's config targets.
   - **Resolution:** `README.md` §3 cross-references `curate-business-glossary/README.md` §3's
     existing compensating-controls note (scope the role assignment to only the domain(s) this
     automation curates) rather than duplicating the guidance — the mitigation is identical in
     shape to the already-reviewed Data Steward finding, so this scenario inherits it by reference
     instead of re-arguing it.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The validate script's classification report is informational-only, with no threshold or
   alert.** `Test-DataProduct.ps1` prints the underlying asset's classifications (or a warning if
   none are present yet) but never fails the run either way — a data product with an unclassified
   "Customer" table would pass every hard check while quietly missing the SSN/Credit Card Number
   classifications `scan-azure-sql-and-classify` is supposed to have found.
   - **Resolution:** Confirmed intentional, not a gap: classification presence depends on
     `scan-azure-sql-and-classify`'s own scan schedule and is that scenario's operational concern
     to alert on, not this one's (`design.md` §6 non-goals). This scenario's `[INFO]`-level report
     exists so an operator validating the *link* doesn't have to separately query Data Map to
     sanity-check what got linked — it is a convenience cross-check, not a substitute for
     `scan-azure-sql-and-classify`'s own validation. `README.md` §7 (checklist item 1) now states
     this scope boundary explicitly rather than leaving the reader to infer it.
2. **No operational KPI for access-request approval latency or backlog.** `README.md` §8 named the
   "access-request backlog" risk but, as originally drafted, didn't say what a stale-approver-queue
   *looks like* operationally, only that it's a risk.
   - **Resolution:** Confirmed this is portal-only operational data (the `Requests` page under
     Catalog management, per README reference 4) with no REST read surface found during this
     build's grounding pass to script a check against — the same "flag the gap rather than
     fabricate a check" pattern as Red Team finding 2. §8 now states plainly that this is
     portal-only hygiene this scenario's scripts cannot monitor, rather than implying a metric
     exists that the validate script simply doesn't compute yet.

No remaining Fail. Both findings resolved by sharpening scope statements to match what this
scenario's REST surface can actually observe, not by adding unconfirmed code.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

- **Cost visibility:** unlike `curate-business-glossary` (zero PAYG cost by design), this scenario
  **does** activate billing — one governed asset linked, per Microsoft's own documented trigger.
  `README.md` §10 states this difference up front by name rather than assuming a reader has
  memorized the sibling scenario's cost model; a buyer evaluating this scenario in isolation (the
  realistic case — most buyers won't read every prior scenario first) needs that contrast stated
  locally.
  - **Resolution:** §10 rewritten to lead with "unlike `curate-business-glossary`, this scenario
    incurs a PAYG charge" and to clarify the charge is per unique governed asset, deduplicated
    across however many data products/terms/CDEs reference the same underlying asset — so scaling
    up the number of *data products* built on this repeated pattern does not multiply cost
    per-asset.
- **Access-governance narrative for the board:** the data-product model's core pitch — one access
  request instead of fifteen, one policy surface instead of fifteen — is a genuine risk-reduction
  story (fewer stale, individually-granted table permissions to audit) that a CISO can put in front
  of a board more easily than "we scanned a table and gave it a glossary term." §2 now leads with
  that operational failure mode by name (the "15 similarly-named tables" example) rather than
  starting from an abstract governance-maturity framing the way `curate-business-glossary`'s driver
  section does — appropriately, since this scenario's value proposition is concrete in a way the
  glossary-alone scenario's is not.
- **Residual risk after the Red Team round:** the open VERIFY on server-side access-policy
  enforcement (Red Team finding 1) is exactly the kind of "we don't yet know if the safety net is
  real" finding that belongs in front of a CISO before this scenario is presented as
  production-ready, not discovered after a customer's first unattended `-Publish` run.
  - **Resolution:** promoted from an inline code comment to a named `README.md` §11 VERIFY with an
    explicit pointer to the operational mitigation already in place (the pre-publish warning) — a
    CISO reading this scenario now sees both the gap and the interim compensating control in the
    same place.

No remaining Fail. Funding recommendation: **yes**, with the stated VERIFY tracked as a follow-up
to close via a pilot-tenant test before this scenario is presented as fully hardened.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Conflating the two "Policies" concepts would have been a real, embarrassing error.** The REST
   API's `Policies` operation group and the portal's "data product access policy" feature share a
   name but are architecturally unrelated — the former is the RBAC authorization-policy engine
   (the same mechanism underlying every Purview role assignment), the latter is the
   consumer-facing access-request workflow. An earlier draft of `design.md` risked implying the
   `Policies` REST group could be used to script data product access policies, which would have
   been fabricated and wrong.
   - **Resolution:** `design.md` §5 now states the distinction explicitly, grounded in a direct
     inspection of the `Policies - List` operation's worked example (its response is attribute/
     decision-rule JSON keyed by domain/entity GUIDs — visibly not an access-request configuration
     object). `README.md` §11 repeats the warning as a named gotcha so a reader skimming only the
     README, not `design.md`, still catches it.
2. **`type` enum values need a portal-vs-REST mapping caveat, not silent substitution.** The
   REST `CatalogModelDataProductTypeEnum` has 14 values; the portal's own "Data product types"
   documentation describes 11 differently-worded options. An earlier draft picked `Master` without
   flagging that this doesn't cleanly correspond to the portal's "Master and reference data" label
   (which maps more naturally to the REST enum's separate `MasterDataAndReferenceData` value).
   - **Resolution:** `README.md` §6's configuration-reference table now lists the full 14-value
     REST enum, names the mismatch with the portal's 11 labels explicitly, and states this
     scenario's specific choice (`Master`) as a judgment call rather than an authoritative mapping
     — with a VERIFY in §11 pointing back to it.
3. **Correct choice to build on the newer Data Assets operation group rather than reusing the
   Data Map/Atlas entity API directly for linking.** Confirmed the 2026-03-20-preview `Data Assets`
   group is the current, intended mechanism for representing a Data Map asset inside Unified
   Catalog (per the API's own release notes, README reference 15) — this scenario is not
   reinventing a capability Microsoft already ships elsewhere, nor using a deprecated path.
4. **Correctly avoided the CSV bulk-import (preview) path for data products**, for the identical,
   well-grounded reason `curate-business-glossary/design.md` §3 gives for glossary terms (bulk
   import cannot edit existing records) — consistent reasoning applied to a sibling feature with
   the same limitation, not a copy-pasted justification that doesn't actually hold for this object
   type. Independently confirmed against the data-products-create-manage article's own bulk-import
   section before accepting the analogy.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (publish-gate bypass risk elevated to a loud warning + gating prerequisite; orphan-wrapper deletion risk confirmed unfixable in tooling, documented instead; domain-scoped-role risk inherited by reference from `curate-business-glossary`) | Closed |
| 🔵 Blue Team | Fix | 2 (classification-report scope boundary clarified; access-request-backlog KPI confirmed portal-only, not a scripting gap) | Closed |
| 🎩 CISO | Fix | 3 (cost-contrast stated locally in §10; access-governance narrative sharpened in §2; publish-gate VERIFY promoted to a named, tracked finding) | Closed |
| 🟦 Microsoft Product Owner | Fix | 4 (two-"Policies"-concepts conflation risk closed before it shipped; type-enum mismatch documented; REST-surface-choice and bulk-import-avoidance both independently confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DataProduct.ps1`, and `deploy/Remove-DataProduct.ps1`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9.
