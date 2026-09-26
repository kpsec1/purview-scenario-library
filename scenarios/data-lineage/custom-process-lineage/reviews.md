# Four-Lens Review - DataSet -> Process -> DataSet Custom Lineage

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Custom-type creation may be an account-wide privilege, not a collection-scoped one - and the
   original draft under-stated the blast radius even while flagging it as a VERIFY.** Apache Atlas
   type definitions are shared, tenant-wide objects (unlike entities, which live inside a
   collection). This scenario's grounding pass confirmed collection-level Data Curator is
   sufficient for the closely related "create a custom classification" action, but found no
   equally explicit statement for creating a custom **entity type definition** specifically. The
   original draft correctly flagged this as unconfirmed, but didn't spell out the consequence if
   it resolves the "worse" way: a compromised or careless automation identity holding only
   collection-scoped Data Curator could still create or pollute type definitions visible across the
   **entire tenant**, not just inside its own collection - a materially larger blast radius than
   the collection-wide entity/relationship risk the sibling scenario already documents.
   - **Resolution:** `README.md` §3's prerequisites table now states this residual risk explicitly,
     regardless of how the underlying VERIFY resolves - "treat the deploy credential's blast radius
     as tenant-wide for this specific action."
2. **Custom lineage - including the Process node's attributes - is asserted, not verified**, same
   integrity posture as the sibling scenario. Correctly scoped as a known, disclosed limitation
   already (`README.md` §11), not a gap this scenario claims to close - confirmed adequate on
   review, no change needed.
3. **A malicious or careless caller could set `runbookUrl` to an attacker-controlled or misleading
   external link**, since this scenario doesn't validate the URL's content or target. Low severity
   (Data Curator is already a trusted, elevated role, and this is metadata rather than an
   executable action - clicking a bad link is a phishing-adjacent risk, not a data-exfiltration
   one), and no different in kind from any other free-text attribute this repo's other scenarios
   already accept (e.g. `Export-ComplianceManagerAuditTrail.ps1`'s own free-text fields). Correctly
   left unvalidated - confirmed adequate on review, no change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The deploy script's type-existence check is existence-only, not a schema check - and nothing
   in the original draft would ever notice or report drift.** `Test-ProcessTypeExists` (deploy
   script) only asks "does a type with this name exist" before skipping `Type - Bulk Create`
   entirely - correct behavior (that operation's own reference page warns against recreating
   existing types, and no confirmed "update an existing type" body exists to reconcile against).
   But the original draft's `validate/Test-ProcessLineage.ps1` had exactly the same existence-only
   check, meaning a type edited out-of-band (an attribute silently renamed or removed, whether by a
   different script, a portal action, or a second, slightly different deployment of this same
   scenario against the same tenant) would produce **zero signal** anywhere in this scenario - not
   a `[FAIL]`, not a `[WARN]`, nothing. An operator debugging a subsequent Entity - Bulk Create Or
   Update failure (caused by the drifted schema) would have no path back to "the type definition
   itself changed" as a hypothesis.
   - **Resolution:** `validate/Test-ProcessLineage.ps1` now fetches the live type definition's full
     body (not just a boolean existence check) and compares its attribute names against this
     scenario's definition file, reporting a dedicated `[FAIL]`/`[PASS]` with both attribute lists
     printed on mismatch. Deliberately detection-only, not auto-remediating - matching the same
     "don't guess at an unconfirmed update body" discipline this repo already applies elsewhere.
     `deploy/New-CustomProcessLineage.ps1`'s existence-check function now also cross-references the
     validate script in its own inline comment, so a reader of either script finds the other half
     of the story.
2. **No native alert for a stale `runbookUrl` or a broken lineage relationship** - same situation as
   the sibling scenario, correctly documented rather than silently omitted (`README.md` §8). No
   change needed.
3. **The incident-response runbook correctly distinguishes a Process-entity-only failure (lower
   severity - the data-flow claim itself may still hold via a direct edge, only the job's context
   is missing) from a full connectivity gap** - a genuine, useful triage distinction the sibling
   scenario's runbook doesn't need (it has no Process node to lose independently). Confirmed
   present and correctly reasoned on review - no change needed.

No remaining Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

1. **Risk-reduction narrative is specific and defensible**: "the transform job itself is now a
   searchable, attributed node in the same graph the rest of our governance program already relies
   on" is a concrete, demonstrable improvement over an unattributed edge, and the scenario is
   honest about what it doesn't prove (Red Team finding 2 above).
2. **Cost is negligible** - a thin REST layer over already-governed assets, no new PAYG meter, no
   M365 license implication. Consistent with the sibling scenario's cost framing.
3. **Change-management impact: minimal**, same as the sibling scenario - no user-facing control, no
   DLP policy, purely metadata. The one operational cost worth budgeting (keeping `runbookUrl`/
   `scheduleExpression` current as ownership changes) is explicitly called out in §10, not buried.
4. **The Red Team blast-radius finding is the one thing that needed to be explicit before signing
   off**, and it now is - a risk committee reviewing this scenario's credential grant should see the
   tenant-wide type-namespace exposure stated plainly, not discoverable only by reading the deploy
   script's REST calls. With that stated, the funding decision is straightforward: this is a small,
   reversible, well-scoped addition to an already-approved capability (the sibling scenario).
5. **Would I fund this?** Yes, without further conditions beyond what's now documented.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Every REST operation this scenario depends on is directly confirmed against its own canonical
   reference page or a literal Microsoft worked example - matching the sibling scenario's strong
   grounding bar, and closing a follow-up that scenario's own design.md explicitly deferred rather
   than guessed at.** `Type - Bulk Create`, `Type - Get Entity Def By Name`, `Entity - Bulk Create
   Or Update`, `Relationship - Create` (x2 relationship types), and `Lineage - Get By Unique
   Attribute` were each fetched directly during this build at a consistent API version
   (`2023-09-01`). The two operations used only in the rollback path (`Relationship - Delete`,
   `Entity - Delete By Unique Attribute`) are corroborated via SDK method signatures rather than a
   fetched canonical REST-reference page for the latter specifically - correctly flagged as a
   narrower-than-usual citation in `README.md` reference 17 rather than presented with equal
   confidence to the deploy-path operations.
2. **Correct, minimal relationship-type selection.** `dataset_process_inputs` +
   `process_dataset_outputs` is the documented, literal shape for exactly this "model the transform
   as its own node" case - not a heavier or lighter mechanism than what Microsoft's own tutorial
   demonstrates for the identical scenario shape.
3. **Custom type vs. reusing a built-in subtype: correctly reasoned, not a reinvention.** Choosing a
   custom `PurviewScenarioLibraryEtlProcess` type over reusing an unrelated built-in subtype (e.g.
   `hive_view_query`, which would misdescribe a non-Hive job) or instantiating the abstract `Process`
   base type directly (unconfirmed by any worked example) is the right call, and `design.md` §3
   explains why plainly rather than asserting it.
4. **No deprecated cmdlets/endpoints.** Same dual-endpoint parameterization and API-version pinning
   discipline as the sibling scenario.
5. **Composability with the sibling scenario was worth stating explicitly, and the original draft
   did so correctly** (`design.md` §6) - this scenario doesn't silently assume it's the only lineage
   mechanism in play, and correctly anticipates a reader seeing both a direct edge and a
   Process-mediated path in the same graph without treating that as a bug.

No remaining Fail after resolution (the one Fix below is shared with the Blue Team finding above,
listed here because it's also a product-correctness issue, not only an operability one).

6. **The original draft's type-existence check, reused verbatim in both deploy and validate,
   under-delivers on what "validate" should mean for a shared, mutable, account-wide object type** -
   same finding as Blue Team item 1, resolved the same way (validate script now checks schema, not
   just existence).

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed via README §3 addition, 2 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed via a new validate-script schema-drift check + deploy-script cross-reference comment, 2 confirmed already adequate) | Closed |
| 🎩 CISO | Pass | - | - |
| 🟦 Microsoft Product Owner | Fix | 1 closed (shared with Blue Team finding 1); 5 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`,
`deploy/New-CustomProcessLineage.ps1`, and `validate/Test-ProcessLineage.ps1`. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9.
