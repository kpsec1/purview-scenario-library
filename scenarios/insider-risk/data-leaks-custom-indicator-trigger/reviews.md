# Four-Lens Review — Insider Risk Management: Data Leaks (custom-indicator / third-party-connector trigger)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **This scenario introduces a new trust boundary neither sibling Data-leaks-template scenario has:
   an externally-produced CSV file whose provenance is never verified, only its shape.**
   `deploy/Send-InsiderRiskIndicatorRecord.ps1`'s validation (schema, ISO 8601, numeric threshold,
   source-value match, duplicate detection) confirms a record is well-formed — it has no way to confirm
   a record genuinely came from the claimed third-party tool, wasn't tampered with in transit to the
   script's host, or wasn't selectively omitted before the script ever read the file. Anyone with write
   access to the export path or the scheduled-task host could inject a fabricated detection (implicating
   an innocent user, or generating alert-fatigue noise) or suppress their own genuine detection entirely
   — a materially different attack surface from either sibling scenario, both of which only ingest
   signals Microsoft's own services generate and control end to end.
   - **Resolution:** Added a `README.md` §11 bullet naming this trust boundary and its consequence
     explicitly (not just a neutral description of what the script validates), plus a cross-referencing
     `README.md` §8 operational bullet recommending the export path and scheduled-task host be treated
     as a security-control input, not merely an operational detail. No code control can close this gap —
     schema validation cannot confirm provenance — so disclosure is the correct and complete resolution,
     consistent with how this library treats other undetectable-by-design gaps (e.g. the WPD-spoofing
     and friendly-name-spoofing findings already disclosed elsewhere in this repo).
2. **A disciplined insider aware of a specific custom indicator's threshold can pace activity to stay
   under it, the same class of finding already disclosed for both sibling scenarios' fixed thresholds.**
   - **Reviewed, already correctly disclosed:** `README.md` §11's threshold-fallback bullet and §8's
     tuning guidance already frame the threshold as a first-class, deliberately-chosen lever with no
     default to hide behind; the general pacing-evasion property is the same structural limitation this
     library's other fixed-threshold Insider Risk Management scenarios already carry
     (`data-leaks-by-risky-users/README.md` §11), and doesn't need restating as a new finding specific to
     this scenario.
3. **The documented silent-drop-on-duplicate and hard-fail-on-source-mismatch behaviors are real,
   exploitable-by-carelessness data-loss modes if left unmitigated — correctly treated as security-
   relevant, not merely a data-quality nicety.** The original draft already built client-side detection
   for both.
   - **Reviewed, already correctly mitigated:** `deploy/Send-InsiderRiskIndicatorRecord.ps1` fails
     closed on both by default (§6, `design.md` §2 goal 3/§6) rather than warning and proceeding. No
     additional change needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A failed scheduled upload produces no native Microsoft alert — a real detection gap for the
   pipeline's own health, not just its data.** Unlike a Microsoft-native connector whose health status
   Microsoft itself can surface, this pipeline's only failure signals are the connector's own manually-
   pulled Download log or whatever the operator's task scheduler happens to capture.
   - **Reviewed, already correctly disclosed:** the original draft's §8 and §11 both already name this
     gap and recommend wiring the scheduled task's exit code into existing infrastructure monitoring. No
     additional change needed.
2. **A multi-chunk upload has no all-or-nothing transaction semantics and no automatic resume-from-
   failure — a partial network failure leaves a partially-ingested run with no built-in recovery
   story**, and the original draft didn't disclose the practical consequence of re-running the script
   afterward (whether it double-counts or safely skips the already-ingested chunks).
   - **Resolution:** Added a `README.md` §11 bullet explaining the partial-failure behavior explicitly,
     including the reasoning for why a full re-run is expected to be safe (the same duplicate-detection
     rule treats already-ingested rows as duplicates on re-upload) while flagging that this interaction
     isn't a Microsoft-documented supported scenario and should be confirmed for the operator's own data
     before being relied on.
3. **Analysts triaging a custom-indicator-driven alert need the underlying third-party tool's own alert
   semantics (what "Salesforce - Sensitive report downloaded and emailed externally" actually means
   operationally) to investigate effectively — a cross-tool runbook dependency this scenario can name but
   not build.**
   - **Reviewed, already correctly disclosed:** the original draft's §8 already states this scenario
     "inherits whatever gaps and false-positive/negative rates the upstream... aggregation already has"
     and that Insider Risk Management "cannot compensate for a third-party tool that under- or
     over-detects" — the runbook-dependency consequence is the same underlying point, already framed
     correctly as an inherited limitation rather than a fixable gap. No additional change needed.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once the Fix
items above are applied.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** favorable and genuinely incremental — this is the only trigger mechanism
  in this library's Data-leaks family that extends coverage to a SaaS app or detection source Microsoft
  doesn't natively see, and it costs no additional Microsoft license if the tenant already has the base
  Insider Risk Management entitlement.
- **Board-level narrative:** "our existing CASB/DLP/SIEM investment now feeds the same investigation
  workflow as our Microsoft-native insider-risk signals, instead of sitting in a second, disconnected
  alert queue" is a clear, differentiated value statement from either sibling scenario.
- **Cost transparency:** §10 correctly refuses to present this as license-neutral — the third-party
  tool supplying the source data is explicitly called out as the deploying organization's own separate cost and
  prerequisite, not something this scenario provisions or discounts.
- **New operational surface, honestly scoped:** an Entra app registration, a scheduled script, and a new
  trust boundary (Red Team finding 1) are real, if modest, additions to what an organization has to operate and
  govern versus either sibling scenario — §8's operational guidance and §11's disclosures present this
  plainly rather than understating it.
- **Preview-status risk correctly flagged**: `README.md` §3's caveat to re-check preview/GA status
  against the live portal before a customer-facing commitment is present, consistent with how this
  library treats every preview-labeled capability it documents.
- **Would I fund this?** Yes, specifically for an organization that already operates the upstream third-party
  tooling this scenario assumes — it would not be worth recommending to an organization starting from zero, and
  the scenario correctly frames itself that way (§1 "who it's for").

No Fix/Fail raised from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **This build's citations were grounded via a direct Microsoft Learn MCP fetch across all four
   primary source pages, plus an independent direct GitHub fetch of the actual ingestion sample script
   — a stronger grounding posture than most scenarios in this library, which typically rely on
   documentation prose alone for script-level implementation details.** The confirmed-identical (token
   endpoint, resource ID, webhook URL) versus confirmed-different (chunk-size default) findings in
   `design.md` §2 goal 5 are a genuine, source-verified contribution, not an assumption carried over from
   the HR-connector sibling.
2. **The flexible, non-fixed CSV column-name handling is correctly identified as a real difference from
   the HR-connector sibling's own fixed schema, and the script is designed accordingly** (parameterized
   column names rather than a hard-coded three-column check) — this is the right level of genericity for
   what Microsoft's own documentation actually describes, not over-engineered beyond what's grounded.
3. **The two documented failure modes (silent duplicate-drop, hard source-mismatch failure) are
   correctly sourced to specific quoted sentences in Microsoft's own documentation, not inferred or
   assumed** — both are reproduced verbatim in `deploy/Send-InsiderRiskIndicatorRecord.ps1`'s own
   `.DESCRIPTION` and this scenario's docs, with the client-side checks built to match exactly what
   Microsoft says will happen, not a stricter or looser interpretation.
4. **The template-scope ambiguity (§2 goal 7) is handled with the correct level of caution** — rather
   than assuming "Data theft and Data leaks policies" extends to every named Data-leaks-family template,
   this fragment scopes itself to exactly the template `PROGRESS.md`'s own follow-up item named and
   flags the broader question as unresolved, consistent with `AGENTS.md` §4's grounding standard.
5. **No fabricated connector-configuration read API, custom-indicator read API, or threshold-
   recommendation mechanism for custom indicators.** Consistent with every other scenario in this
   library, and specifically consistent with Microsoft's own explicit statement that no recommended
   threshold exists for custom indicators — this build did not invent one.
6. **Script reuse is correctly justified and the app-registration reuse is a genuine, verified
   simplification, not an assumption of convenience.** Reusing `Register-HrConnectorApp.ps1`/
   `Test-HrConnectorAppRegistration.ps1` unmodified is grounded in Microsoft's own Step 1 for this
   connector describing the identical generic requirement (app ID, secret, tenant ID, no permissions) as
   the HR connector's own Step 2 — not merely convenient reuse, but confirmed applicable.

No Fix/Fail from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with new README §8/§11 disclosure, 2 confirmed already correctly disclosed/mitigated) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with new README §11 disclosure, 2 confirmed already correctly disclosed) | Closed |
| 🎩 CISO | Pass | — | — |
| 🟦 Microsoft Product Owner | Pass | — | — |

The Red Team's data-provenance finding was this round's most operationally significant: unlike every
other trigger mechanism this library has built for the Data-leaks template family, this one ingests
data from outside Microsoft's own control boundary, and no schema-level validation can confirm that
data's authenticity — only access-control discipline on the export path and script host can. That
consequence is now stated plainly (not just the mechanical description of what the script checks) in
`README.md` §8 and §11. The Blue Team's partial-chunk-upload finding closes a real gap in the operator's
understanding of failure-recovery behavior, resolved the same way — disclosure of the actual behavior
and its reasoning, since the underlying duplicate-detection rule already makes a full re-run safe by
construction, not by a new code capability. Both fixes were applied as doc changes; this scenario's one
new script, `deploy/Send-InsiderRiskIndicatorRecord.ps1`, needed no code change as a result of this
review (its fail-closed validation behavior was already correct at the point of review). No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9.
