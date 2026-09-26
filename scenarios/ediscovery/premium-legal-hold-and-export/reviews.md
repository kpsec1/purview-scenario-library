# Four-Lens Review — eDiscovery (Premium): Legal Hold, Collection, Review, and Export

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **No independent audit trail for who released a hold or closed/deleted a case.** The draft's
   objects (case, custodian) only expose a single `lastModifiedBy`/`closedBy` snapshot property —
   an eDiscovery Administrator with legitimate portal/Graph access could release a custodian's
   hold, let deletion-eligible content age out under whatever retention policy otherwise applies,
   and re-apply the hold later, leaving nothing in this scenario's own object model to flag the
   gap. Given §2's spoliation-sanction stakes, an insider (or a compromised eDiscovery
   Administrator account) with this capability and no independent monitoring is a real, not
   theoretical, exposure.
   - **Resolution:** Added an explicit "Audit visibility" subsection to `README.md` §8 naming the
     gap directly, pointing at `Search-UnifiedAuditLog` (automation surface 1) as the correct
     independent channel, and being honest that the exact `RecordType`/`Operations` values for
     eDiscovery hold/case-lifecycle events weren't grounded in this build rather than guessed by
     analogy to a different module's audit schema — tracked as a scoped follow-up in
     `PROGRESS.md` rather than fabricated here.
2. **Custodian hold coverage silently excludes Teams channel messages.** The original draft's
   `userSource` (mailbox + OneDrive) description implied "the custodian's data" without
   qualification; Teams *channel* messages are stored in the team's own mailbox/site, not the
   individual custodian's, so a custodian on hold in this scenario's default configuration has no
   preservation over channel conversations they participated in — a red-teamer (or, more
   realistically, a custodian's own imprecise mental model of "I'm on hold, so I'm covered")
   could treat channel content as unprotected when the matter's scope actually includes it.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming the gap and the specific
     remediation (`New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource` against the relevant
     team, added alongside — not instead of — the custodian holds this scenario places).
3. **`ediscoveryHoldPolicy` vs. custodian `applyHold` naming collision** — both are called "legal
   hold" in Microsoft's own docs; a reader who assumes this scenario's custodian-scoped hold is
   *the* legal hold mechanism could miss that a location-scoped hold (a shared departmental
   mailbox, a distribution-list sweep with no single custodian owner) needs the other object
   entirely, and wrongly conclude "custodian" coverage is complete for a matter that also needs
   location-scoped preservation.
   - **Not a new finding requiring a scenario change** — already correctly disclosed as a
     dedicated Known Limitations bullet (`README.md` §11) and explained in full in `design.md`
     §3, including why this scenario picked the custodian path and what the alternative covers.
     Confirmed the existing text already resolves this rather than assuming a gap.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No scheduled-monitoring guidance for `HoldStatus` regression.** The original draft's KPI
   list named `HoldStatus` regression as something to "track" without saying how, unlike this
   library's other scenarios that explicitly wire their validate script into a recurring check.
   - **Resolution:** `README.md` §8's Review cadence already specified a weekly
     `validate/Test-EdiscoveryPremiumCaseSetup.ps1` run for every case with an active hold before
     this review round — confirmed the existing text already covers the "how," not just the
     "what," so no further change needed here; the audit-trail fix above (Red Team finding 1)
     adds the complementary piece (who), which was the real gap.
2. **The validate script's export-age check (`ExportOperationId` parameter) is opt-in and easy to
   forget to pass on a scheduled run**, silently skipping the one check most likely to catch a
   soon-to-expire, not-yet-downloaded export before the 30-day window closes.
   - **Resolution:** Confirmed this is a deliberate, disclosed design choice, not an oversight —
     `Test-EdiscoveryPremiumCaseSetup.ps1`'s own doc comment states the export check is optional
     because an export is "a point-in-time production, not an always-present piece of ongoing
     case state." Added no code change; instead this finding is recorded here as an explicit
     operational reminder: a scheduled validation job should pass every open export operation ID
     it's tracking, not just the case ID, to get this check's benefit. Not silently assumed
     covered.
3. **`Wait-CaseOperation`'s timeout produces a `Write-Warning`, not a script failure, for a
   long-running `addToReviewSet`/export** — a CI-style pipeline treating any warning as
   non-blocking could report "success" for a collection that's actually still running, and move
   on to a download step that finds nothing ready yet.
   - **Resolution:** Confirmed as correct, disclosed behavior, not a defect — `design.md` §5
     explains why a timeout is deliberately not an error (a large custodian population can
     legitimately outlast a reasonable script timeout). `Get-EdiscoveryExportPackage.ps1`
     independently checks the operation's `status` before downloading and warns (rather than
     silently downloading a partial/absent file list) if it isn't `succeeded` — so the pipeline
     risk is already mitigated at the point that matters (the download step), not just narrated.
     No change made; noted here so the reasoning is visible in review rather than assumed.

No remaining Fail. The scenario is operable and its residual gaps are disclosed, not silent.

---

## 🎩 CISO

**Verdict: Pass (with one Fix)**

1. **Releasing a hold is a legal, not technical, decision, and the original draft only surfaced
   that in `rollback.md`, not as a gating prerequisite up front.** A team that reads only
   `README.md` before running `Remove-EdiscoveryPremiumLegalHold.ps1` for the first time could
   miss the spoliation-risk framing entirely if it's buried in a rollback doc they don't read
   until they're already mid-rollback.
   - **Resolution:** Added an explicit row to `README.md` §3's prerequisites table — "written
     confirmation from counsel that the preservation duty has lapsed" — as a gating prerequisite
     for any hold release, cross-referencing `rollback.md`, mirroring this library's established
     precedent (`scenarios/communication-compliance/harassment-and-code-of-conduct/` promoting its
     own legal-counsel gating item the same way).
- **Risk reduction vs. cost:** proportionate and, unusually for this library, the cost driver
  (E5/eDiscovery & Audit add-on licensing per custodian, scoped to litigation-exposed population
  per §10) is more legally *mandatory* than most controls here — the alternative to this control
  isn't "less protection," it's "manual, error-prone hold management with a much higher spoliation
  risk," which is a materially different risk profile than most DLP/labeling scenarios in this
  repo where the alternative is merely a less-automated version of the same control.
- **Board-level narrative:** "we have a repeatable, auditable process for preserving and producing
  data the moment a legal or regulatory matter opens, instead of ad hoc portal clicks with no
  standard record" — clear, and honest about its boundaries (§11's limitations list, especially
  the notification-workflow gap) rather than overclaiming full legal-hold-lifecycle coverage.
- **Compliance mapping:** correctly scoped to FRCP Rule 37(e) / common-law preservation duty and
  regulatory-investigation preservation obligations (§2) — does not overclaim a specific named
  regulation the way a PCI/HIPAA-scoped control correctly can, because litigation-hold obligations
  are cross-cutting rather than tied to one regulatory framework.
- **Would I fund this?** Yes — for any org with recurring litigation/investigation exposure
  (which is most enterprises above a certain size), the alternative is manual portal work per
  matter with no consistency guarantee across legal-ops staff, and the downside of getting this
  wrong (sanctions, adverse inference) is severe enough that the automation's cost is easily
  justified.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **The Graph-only, no-S&C-PowerShell design is correct and independently re-confirmed, not
   assumed from `docs/automation-surface.md` alone.** This build directly fetched "Assign
   permissions in eDiscovery"'s app-only-authentication section and confirmed the "unsupported"
   status and Microsoft's own remediation guidance (migrate to Graph) verbatim, rather than
   trusting the cross-cutting doc's prior summary as sufficient grounding for a whole scenario.
2. **Cmdlet names are verified per-cmdlet against their own Microsoft Learn reference pages, not
   inferred by naming-pattern analogy in every case** — the one place this build *did* rely on
   pattern analogy (`New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource`, README.md §11) was
   independently confirmed to exist via a targeted search before being cited, rather than left as
   an assumed-correct guess.
3. **The two-API (Graph + separate Purview eDiscovery download API) design is correctly
   represented as Microsoft's own architecture, not a workaround this scenario invented** —
   `design.md` §2 and the architecture diagram (`README.md` §4) both make the split explicit, and
   `deploy/Get-EdiscoveryExportPackage.ps1` is a parameterized, idempotent adaptation of
   Microsoft's own published reference script rather than an independently reverse-engineered
   flow, with the adaptation's changes disclosed in the script's own `.NOTES`.
4. **v1.0 vs. beta namespace discipline is correct throughout.** Every cmdlet/REST reference cited
   uses the `microsoft.graph.security` (v1.0) namespace, not `microsoft.graph.ediscovery` (beta,
   explicitly marked deprecated by Microsoft in favor of `security`) or `Microsoft.Graph.Beta.*`
   cmdlets — consistent with `docs/automation-surface.md` §2's guidance to pin to v1.0 in shipped
   automation. The one deliberate exception (citing the beta `userSource` worked example for the
   `includedSources` combined-string form, README.md §11) is explicitly flagged as a VERIFY rather
   than silently presented as v1.0-confirmed.
5. **Licensing citations match `docs/licensing-matrix.md`'s existing eDiscovery rows** (Standard =
   E3, Premium = E5/Suite/add-on) with no new, uncross-checked claims introduced in this
   scenario's own prerequisites table.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with README/design additions, 1 confirmed already correctly disclosed) | Closed |
| 🔵 Blue Team | Fix | 3 (1 confirmed already covered, 1 recorded as an operational reminder with no code change needed, 1 confirmed already mitigated at the right point) | Closed |
| 🎩 CISO | Pass (1 Fix) | 1 closed with a README §3 prerequisites addition; overall verdict Pass | Closed |
| 🟦 Microsoft Product Owner | Pass | 5 (all confirmed correct/well-grounded, no changes required) | — |

All Fix items from this round are resolved in the current state of `README.md` and `design.md`.
No Fail items were raised. This fragment meets the definition of done in `AGENTS.md` §9.

---

## Follow-up round — `deploy/Export-EdiscoveryAuditTrail.ps1` added

Added to close Red Team finding 1, above ("no independent audit trail for who released a hold or
closed/deleted a case"), per the follow-up tracked in `PROGRESS.md`. A short four-lens pass on the
addition itself, not a full re-review of the whole scenario:

- **🔴 Red Team — Pass.** The finding is genuinely narrowed: case-lifecycle events
  (create/update/close/reopen/delete) are now independently, tamper-evidently visible via
  `Search-UnifiedAuditLog`, confirmed against Microsoft's own eDiscovery audit reference. Residual
  gap, disclosed rather than silently assumed closed: whether the hold-policy `Operation` values
  also capture this scenario's own custodian-scoped `applyHold`/`release` calls is unconfirmed for
  the current experience (design.md §8) — the script's `.NOTES` and README.md §8 both say so
  explicitly, and `PROGRESS.md` carries a pilot-tenant VERIFY rather than a fabricated "yes."
- **🔵 Blue Team — Pass.** Same rolling-CSV, composite-key de-duplication mechanism this repo's two
  other no-independent-audit-trail scenarios already use; `-CaseName` lets an operator scope the
  tenant-wide trail to one matter, which those two sibling scripts don't need (they have no
  multi-case concept). `Write-Warning` on `CaseRemoved`/`HoldRemoved` rows gives an operator a
  same-run signal rather than requiring them to grep the CSV by hand.
- **🎩 CISO — Pass.** Directly answers the spoliation-defensibility gap §2/§8 already frame as the
  scenario's highest-stakes risk, without overclaiming coverage the grounding doesn't support — the
  custodian-vs-hold-policy caveat is surfaced up front (README.md §8), not buried in a footnote.
- **🟦 Microsoft Product Owner — Pass.** `RecordType Discovery` and all nine `Operation` values are
  quoted directly from Microsoft's own "Audit log activities" reference page, not inferred by
  analogy; the classic-experience/21Vianet-China-only caution banners on the two corroborating
  pages (`ediscovery-managing-holds`, `ediscovery-view-custodian-activity`) are surfaced rather than
  silently treated as applicable to the modern experience this scenario automates.

No Fix/Fail from this round. `PROGRESS.md` carries the one open pilot-tenant VERIFY forward.

---

## Follow-up round — legal-hold-notifications finding corrected (no companion scenario built)

`PROGRESS.md` tracked a follow-up to build `scenarios/ediscovery/legal-hold-notifications/` as a
companion scenario for the Premium custodian-communication workflow this scenario's own README.md
§11 flagged as a real gap. Re-grounding that follow-up found the workflow was **permanently
retired by Microsoft on August 31, 2025** and isn't available in the current eDiscovery experience
— not merely unautomatable. No companion scenario was built; instead README.md §11 and design.md
§7 were corrected in place. A short four-lens pass on the correction itself, not a full re-review:

- **🔴 Red Team — Pass.** The correction closes a worse risk than the one it replaces: a companion
  scenario built on the original assumption would have walked an organization through Microsoft Learn pages
  for a feature that no longer exists in their tenant, or shipped a script polling
  `acknowledgedDateTime` as if it were a live signal when nothing in the current experience can set
  it. Both would have been confidently wrong rather than honestly incomplete. The corrected text
  instead tells the operator the acknowledgment field is expected to stay null and points them at an
  external process.
- **🔵 Blue Team — Pass.** `validate/Test-EdiscoveryPremiumCaseSetup.ps1` already doesn't check
  `acknowledgedDateTime` — confirmed as the right call now, not a coincidence, and the updated
  README.md §11 explains why rather than leaving the omission unexplained.
- **🎩 CISO — Pass.** The corrected text is more useful to an organization than the original follow-up
  would have produced: instead of a scenario documenting a dead portal feature, they get a direct
  instruction to treat notice-and-acknowledgment as an external process today, which is the
  actionable fact a legal/compliance stakeholder needs for their preservation narrative.
- **🟦 Microsoft Product Owner — Pass.** The retirement is grounded against Microsoft's own current
  (non-legacy-banner) "Manage hold notifications" page, which states it in an `Important` callout —
  a more direct and current source than the classic-experience caution banner this build initially
  expected to rely on. The stale "Communication" RBAC role still listed on the current, non-banner
  "Assign permissions in eDiscovery" page was noticed but correctly not treated as evidence the
  feature is still live — the retirement page is the more specific and more recent source.

No Fix/Fail from this round. `PROGRESS.md`'s legal-hold-notifications follow-up is closed as
"investigated, not built" rather than carried forward or silently dropped.
