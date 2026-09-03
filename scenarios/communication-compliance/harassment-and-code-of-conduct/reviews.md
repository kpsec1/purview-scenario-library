# Four-Lens Review — Harassment & Code-of-Conduct Detection

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied before this file was finalized (see "Resolution" under
each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Keyword-only detection is trivially evaded.** A code-of-conduct control that relied on a static
   lexicon alone is defeated by spelling variants, spacing, emoji, or paraphrase — and worse, it
   creates false assurance ("we have a harassment policy") while missing most real harassment, which
   is contextual.
   - **Resolution:** The scenario is explicitly a **two-part** control — the trainable classifiers
     (Targeted harassment/Threat/Discrimination) carry contextual detection and the keyword rule only
     *complements* them. `README.md` §1/§11 and `design.md` §3 state plainly that the script alone is
     not the full control and that classifiers are mandatory (portal-configured). The sample lexicon
     is labeled illustrative and the deploy script refuses to run with placeholder-only terms.
2. **Over-broad reviewer access / privacy abuse.** An investigator with content access across all
   staff is itself a risk (snooping, retaliation), and disabling pseudonymization would turn a conduct
   control into surveillance.
   - **Resolution:** The script only *assigns* reviewers who already hold the Analyst/Investigator
     role (it never elevates), never disables pseudonymization, and never grants content access;
     `design.md` §6 documents the Analyst-vs-Investigator content boundary and admin-unit scoping, and
     `README.md`/manifest keep pseudonymization on by default with disabling flagged as an explicit
     HR/Legal decision.
3. **Supervising unlicensed users is a silent gap.** If scoped users lack the required license, they
   simply aren't covered — a false sense of coverage.
   - **Resolution:** `README.md` §3/§11 state the per-scoped-user licensing requirement explicitly and
     tell the operator to confirm seat coverage for the whole reviewee group, not just admins.
4. **Fabricated automation risk.** The temptation to script the classifiers via the undocumented
   `-AdvancedRule` parameter would have shipped a guessed, likely-wrong payload.
   - **Resolution:** Not done — classifiers are left portal-only with an explicit VERIFY, honoring
     `AGENTS.md` §4. Flagged as the key design decision rather than papered over.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No working dry-run.** The obvious `-WhatIf` doesn't work in Security & Compliance PowerShell, so a
   naive script would offer a dry-run that silently does nothing useful (or worse, executes).
   - **Resolution:** The deploy/remove scripts implement a custom **`-DryRun`** that prints every
     mutating cmdlet and invokes none, with the `-WhatIf` limitation documented inline and in
     `README.md` §5/§11.
2. **False-positive flood from classifiers.** Harassment/threat classifiers over-detect bulk/newsletter
   mail, which can bury real alerts and burn out reviewers.
   - **Resolution:** `README.md` §8 makes **Filter email blasts** the first tuning lever, tracks
     false-positive rate and the *Report as Misclassified* feedback loop as KPIs, and calls out
     reviewer-time as the real operating cost so scope/sampling are tuned deliberately.
3. **Validation can't see the classifier half.** A validate script that only checked the cmdlet-visible
   objects could report "all good" while the classifiers were never added in the portal.
   - **Resolution:** `validate/Test-CodeOfConductPolicy.ps1` hard-checks the scriptable half **and**
     prints an explicit manual checklist for the portal-only items (classifiers, locations, filter,
     reviewer role membership, pseudonymization), so "green" never implies the classifier half is done.

No remaining Fail. Operability includes a native reviewer/case workflow plus a scriptable gate for the
keyword/workflow half.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Surveillance / works-council risk.** A communication-monitoring control that isn't visibly
   privacy-preserving is a legal and cultural liability (especially under EU works-council regimes).
   - **Resolution:** `README.md` §2/§7/§11 and `design.md` §6 foreground privacy-by-design
     (pseudonymization default, role separation, admin-unit scoping) as the controls that make the
     program defensible; disabling pseudonymization is framed as an explicit, documented HR/Legal
     decision.
2. **Risk reduction vs. cost:** proportionate. The licensing is per-scoped-user and the dominant
   operating cost is reviewer time; both are called out with tuning guidance so the program is
   sustainable rather than a queue nobody works.
3. **Board narrative:** defensible and specific — "we detect harassment and conduct violations across
   Teams/Exchange/Viva Engage with ML classifiers plus our own lexicon, route matches to trained
   reviewers under role-based access with pseudonymized identities, and keep an auditable
   investigation trail." Supports anti-harassment obligations and regulated-industry supervision.
4. **Change-management impact:** meaningful (this monitors employee communications) — mitigated by
   staged rollout, draft/tuning via `-DryRun`, reviewer training, and a clean disable/delete off-ramp
   in `rollback.md`.
5. **Would I fund this?** Yes — clear obligation coverage, privacy controls that keep it defensible,
   bounded cost, and honest scoping of what's automated vs. portal-managed.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Respecting the PowerShell support boundary.** Microsoft states PowerShell isn't supported for CC
   policy management; presenting a script as the primary/complete method would contradict product
   guidance.
   - **Resolution:** The **portal is documented as the primary, supported surface** for the classifier
     half; the `SupervisoryReview` cmdlets (real, documented, and the engine underneath CC) are used
     only for the keyword/workflow subset, with an explicit VERIFY on portal-vs-PowerShell equivalence
     (`README.md` §11, `design.md` §3/§4).
2. **Correct, current cmdlets and template.** All six cmdlets used
   (`New-/Set-/Get-/Remove-SupervisoryReviewPolicyV2`, `New-/Set-/Get-SupervisoryReviewRule`) and the
   `-Condition` grammar are reproduced from their own reference pages; the "Detect inappropriate text"
   template and its Targeted harassment/Threat/Discrimination classifiers match the current policy
   templates table.
3. **No deprecated path.** Uses the V2 supervisory-review cmdlets (not the retired V1 supervision
   surface) and the current Communication Compliance solution, not legacy Supervision.
4. **Accurate licensing and roles.** Purview Suite / O365 E5 / E3+Advanced Compliance for scoped
   users, and the six role groups with the Analyst-vs-Investigator content boundary, are stated per
   the plan/permissions docs.
5. **Not reinventing a native capability.** The scenario uses the native engine and the native portal;
   it adds value only where the product leaves a gap (as-code keyword/workflow deployment + a diffable
   record of the portal config), and points at native alerts/remediation rather than rebuilding them.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (keyword-only evasion → two-part control + no-placeholder guard; reviewer/privacy scope; unlicensed-user gap; no fabricated classifier params) | Closed |
| 🔵 Blue Team | Fix | 3 (custom `-DryRun` for the non-functional `-WhatIf`; false-positive tuning + KPIs; validate covers portal half via checklist) | Closed |
| 🎩 CISO | Fix | 1 closed (privacy-by-design foregrounded); Pass on cost/narrative/change-mgmt | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (portal as primary supported surface; scripted subset scoped honestly); 4 confirmed correct | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-CodeOfConductPolicy.ps1`, `deploy/Remove-CodeOfConductPolicy.ps1`,
`deploy/config/code-of-conduct.sample.json`, `deploy/policy/inappropriate-text-portal-reference.json`,
and `validate/Test-CodeOfConductPolicy.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9, with the portal-managed classifier half and preview-adjacent
parameter behavior recorded as explicit VERIFYs (not fabricated) per `AGENTS.md` §4.
