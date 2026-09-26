# Four-Lens Review — Data Quality Connection and Scorecard Alerts

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Alert-receiver redirection is a stealthier bypass than deleting the alert.** Because
   **Data Quality Steward** is governance-domain-wide (same blast radius the sibling
   `rules-and-scorecards` review already flagged for that role), anyone holding it can call
   `Update Alert` directly and repoint `receivers` to an unmonitored mailbox — or drop the real
   distribution list entirely — without touching `status`, `condition`, or the alert's existence.
   The original draft's validation only proved the alert *exists* with the *expected* body at
   deploy time; it said nothing about catching a later, out-of-band edit.
   - **Resolution:** `README.md` §3's Data Quality Steward row now states this blast radius
     concretely for connections/alerts (not just a pointer to the sibling scenario), and §8 now
     explicitly instructs wiring `validate/Test-DataQualityConnectionAndAlerts.ps1` — which already
     diffs `receivers` against the source-controlled definition file — into a **recurring**
     pipeline rather than treating a one-time post-deploy run as sufficient, with the definition
     file itself subject to the same PR-review discipline as this repo's DLP/label policies.
2. **Rollback Stage 2 (remove connection) can silently start failing the sibling scenario's
   schedule.** If an operator removes the connection without first pausing or repointing
   `rules-and-scorecards`' schedule, the next scheduled scan fails outright.
   - **Resolution:** Already correctly flagged in `rollback.md` Stage 2 ("Any scan scheduled by
     `rules-and-scorecards` against this connection will start failing...") — confirmed adequate
     on review, no change needed. Additionally cross-referenced from `README.md` §8's runbook as
     classification cause (d), so an operator diagnosing a connection-failure alert also considers
     "did someone just run this scenario's own rollback" before assuming a source-side fault.
3. **Managed-VNet region deletion cascades beyond this scenario's own connection.** Deleting a
   provisioned region under Settings > Unified Catalog > Virtual network removes *every* connection
   linked to it tenant-wide, not just this scenario's — a shared blast radius the original draft
   mentioned only in a reference footnote.
   - **Resolution:** `rollback.md`'s "What rollback does not undo" section already calls this out
     explicitly with the specific caution to confirm no other connection depends on the region
     first — confirmed adequate on review, no change needed.
4. **The example alerts' thresholds (95% / 10-point regression) are illustrative, not
   validated against real data.** Same class of finding as the sibling scenario's weak example
   regex — an unrealistic threshold could either never fire (false confidence) or fire constantly
   (alert fatigue, training operators to ignore it).
   - **Resolution:** Not a documentation gap to fix — `README.md` §8's review-cadence guidance
     already tells operators to revisit thresholds quarterly rather than treating the shipped
     example values as production-ready; confirmed this is the same "starter, not
     compliance-grade, content" framing the sibling scenario's own Red Team review established for
     its example rule, applied consistently here.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No audit trail to programmatically confirm *who* changed a connection or alert.** The original
   draft's incident-response runbook could tell an operator *that* a connection was misbehaving but
   had no way to query *whether a recent change* (this scenario's own rollback, or an out-of-band
   `Update Alert`/`Update Data Source` call) was the cause, short of asking around.
   - **Resolution (updated by a later grounding pass, tracked in `PROGRESS.md`):** the original
     round flagged this as an open VERIFY — not yet grounded. A dedicated follow-up pass has since
     grounded it and found the gap is real, not just unresearched: no `Search-UnifiedAuditLog`
     `RecordType`/`Operations` pair, and no other documented audit mechanism, covers Unified
     Catalog Data Quality connection/alert lifecycle events today (three independent corroborating
     findings — `README.md` §11, `design.md`'s Non-goals). `README.md` §11 no longer carries this
     as an open VERIFY; it's a confirmed, cited finding. The runbook's item (d) stays phrased as
     "ask whether a teardown happened" because that finding is what makes it stay a human question
     rather than a query — not because the check was left ungrounded.
2. **Validate script's error handling was checked for the same ambiguous-failure-mode class the
   sibling scenario's review found** (a wrong/stale ID looking identical to "doesn't exist yet").
   - **Resolution:** Confirmed **not present** here — both the connection and alert existence
     checks in `validate/Test-DataQualityConnectionAndAlerts.ps1` explicitly re-throw any non-404
     error rather than swallowing it into a generic warning, so a malformed `businessDomainId` or
     an auth failure surfaces as an exception distinct from a clean "not found." No change needed;
     this is a stricter pattern than the sibling script's asset-score check and should be the
     template for any future validate script in this repo, not just this one.
3. **No SIEM/Sentinel integration mentioned.** Correctly out of scope, consistent with this repo's
   established precedent (`rules-and-scorecards/reviews.md` Blue Team finding 3) of not overclaiming
   an alert-stream integration Data Quality doesn't natively provide.
   - **Resolution:** No change needed; confirmed correctly scoped, matching finding 1's honesty
     about the same underlying gap (no confirmed audit/event surface) rather than restating it as a
     separate issue.

No remaining Fail. The Fix item brings this scenario's operability guidance to the same bar the
sibling scenario's review established, extended to this scenario's own specific failure mode
(a silent, in-place alert redirection rather than an outright scan failure).

---

## 🎩 CISO

**Verdict: Pass**

1. **This scenario is the sibling's stated go-live gate, made concrete, not a separate ask.**
   `rules-and-scorecards/README.md` §8 already states that scenario "should not be considered
   monitored" until an alert exists — this scenario is exactly and only that missing piece. An organization
   funding `rules-and-scorecards` is, in practice, already committed to funding this scenario too;
   the original draft's §1 scenario summary states this relationship directly rather than
   presenting two independent asks.
2. **Risk-reduction narrative:** the same BCBS 239/GDPR/SOX narrative as the sibling scenario, now
   with the concrete addition an auditor is most likely to test directly — "show me the alert that
   fired the last time this dropped below threshold" (§2). Auditable, specific, not aspirational.
3. **Cost narrative is honest about a second cost dimension.** §10 correctly separates Data
   Quality's DGPU metering from the managed-VNet path's own Azure networking cost (compute location,
   private endpoints) — an organization evaluating the VNet option isn't surprised by a cost outside the
   DGPU line item they budgeted for.
4. **Change-management impact:** low — same assessment as the sibling scenario; deploying a
   connection and alerts doesn't touch live M365 controls or user-facing behavior. The staged
   rollback (alerts-only → alerts + connection, with a non-destructive pause option in between)
   gives a proportionate off-ramp.
5. **Would I fund this?** Yes, without conditions beyond what `rules-and-scorecards` already
   carries — this scenario removes rather than adds a funding gate, by closing the one that
   scenario's own review already identified.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **`computeId` was re-investigated rather than re-stated as still-blocked, and the finding holds
   up.** Independently re-fetched Create/Get/Update Data Source and the full REST operation-group
   index; confirmed `computeId` appears only in the managed-VNet worked example and is absent from
   the non-VNet Get/Update examples, and confirmed no Get/List Compute operation exists anywhere in
   the current operation-group index. This narrows (not eliminates) the sibling scenario's disclosed
   gap correctly — verified against the primary source rather than assumed from the prior build's
   summary.
   - No resolution needed — this is the finding, not a defect.
2. **`condition` function set matches Microsoft's own worked examples exactly** —
   `score_threshold(GLOBAL_SCORE)` and `score_variance(GLOBAL_SCORE)` are the only two functions
   present in Get Alert/Get Alerts/Update Alert's REST examples; no third function name was
   invented for the example definition file.
3. **Public Preview status is prominent from the first section**, applying the same fix the sibling
   scenario's own Product Owner review round required after the fact — this scenario's `README.md`
   §1 opens with the callout rather than burying it, learned from that precedent rather than
   repeating the gap.
4. **Alert-scope flexibility was under-documented in the original draft.** The confirmed
   `AlertScope` schema supports a data-product-wide scope (omit `dataAsset`), which the original
   draft's example and prose didn't mention — a reader could reasonably assume one-alert-per-asset
   is the only supported pattern.
   - **Resolution:** `README.md` §11 now documents the product-level scoping option explicitly,
     including that `New-DataQualityAlert.ps1` already supports it today (no code change needed —
     `dataAssetId` was already optional in the script's scope-construction logic).
5. **Reinventing-a-native-capability check:** this scenario is a direct REST wrapper around
   Create/Get/Update/Delete Data Source and Update/Get/Delete Alert — no parallel connection-
   management or alerting system is built, and no fabricated provisioning endpoint was invented for
   the one genuinely-portal-only piece (`computeId`/managed-VNet provisioning).
6. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md`: PAYG/DGPU framing
   matches the sibling scenario and the cross-cutting matrix exactly; no conflation with per-user or
   governed-assets/day meters.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 closed via README/rollback guidance additions, 2 confirmed already adequately documented) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed via a new README §11 VERIFY + runbook cross-reference, 2 confirmed correct/adequately scoped) | Closed |
| 🎩 CISO | Pass | 5 confirmed correct; no Fix/Fail | Closed |
| 🟦 Microsoft Product Owner | Fix | 6 (1 closed via a new README §11 documentation addition, 5 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DataQualityConnection.ps1`, `deploy/New-DataQualityAlert.ps1`,
`deploy/Remove-DataQualityConnectionAndAlerts.ps1`, `rollback.md`, and
`validate/Test-DataQualityConnectionAndAlerts.ps1`. No Fail items were raised. This fragment meets
the definition of done in `AGENTS.md` §9.

---

## Round 2 — companion product-level alert example (`PROGRESS.md` follow-up)

Round 1's Microsoft Product Owner finding 4 noted the product-level `AlertScope` shape was
*documented* as supported but not *shipped* as a worked example. This round adds
`deploy/alerts/customer-360-product-score-alert.json` (one alert, `dataProductId` only) and updates
`README.md`/`design.md`/`rollback.md`/both scripts' `.EXAMPLE` blocks accordingly — no change to
either script's logic, since `New-DataQualityAlert.ps1` already built this shape whenever
`dataAssetId` was absent.

### 🔴 Red Team — Verdict: Pass

A product-level alert widens what one `receivers` list gets notified about (every asset in the
product, not one), but does not widen who can *cause* a notification or *read* one — same
**Data Quality Steward**/**Data Quality Reader** blast radius already documented in §3 and Round 1
finding 1. No new bypass surface: an attacker who already holds Data Quality Steward could already
repoint or delete an asset-level alert exactly as easily. No Fix/Fail.

### 🔵 Blue Team — Verdict: Fix (resolved)

1. **A product-level alert's notification doesn't say which asset regressed**, unlike an
   asset-level one — an operator triaging the email has to go check the product's per-asset scores
   in the portal before they know where to look, a slower first-triage step than the asset-level
   alert provides today.
   - **Resolution:** `README.md` §8 now states this trade-off directly ("Choosing asset-level vs.
     product-level alert scope") and §11's rewritten scope-granularity bullet cross-references it,
     rather than presenting the product-level file as a strictly better option.
2. **Confirmed the new example doesn't weaken the recurring-validation guidance from Round 1
   finding 1** (receivers-redirection detection) — `validate/Test-DataQualityConnectionAndAlerts.ps1`
   needed no code change to check the new file, since its alert checks are already generic over
   scope shape. No Fix needed.

### 🎩 CISO — Verdict: Pass

Zero net-new licensing or cost dimension — same PAYG/DGPU framing as Round 1 finding 3; a
product-level alert is not separately metered any more than an asset-level one is (§10 unchanged).
Gives an organization with a multi-asset data product a lower-alert-count option than "one alert per asset,"
which is itself a minor operational-cost (alert-fatigue) reduction the CISO lens welcomes, with the
Blue Team's triage-speed trade-off disclosed rather than oversold. Would fund this addition; it's
in scope of what was already funded for the parent scenario.

### 🟦 Microsoft Product Owner — Verdict: Pass (Round 1 finding 4 now fully closed)

The shape shipped matches what Round 1 already inferred from the `AlertScope` schema reference: no
new field, no invented parameter. A direct re-fetch of the `Update Alert` REST reference this round
confirmed the worked example still only shows the asset-level (`dataProduct` + `dataAsset` together)
shape — no Microsoft worked example independently confirms `dataAsset` can be omitted — so the new
file's own header comment and `README.md` §11 state this as inferred-from-schema-and-corroborated,
not pilot-tenant-confirmed, consistent with this repo's grounding standard (`AGENTS.md` §4) rather
than silently upgrading the claim now that a file ships. Re-open if a pilot-tenant run or a future
Microsoft worked example either confirms or rejects the shape.

### Round 2 summary

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Pass | 0 | — |
| 🔵 Blue Team | Fix | 2 (1 closed via README §8/§11 trade-off note, 1 confirmed no change needed) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Pass | 0 (grounding re-confirmed, framing unchanged) | — |

No remaining Fix/Fail. This addition meets the definition of done in `AGENTS.md` §9.
