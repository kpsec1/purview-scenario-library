# Four-Lens Review — eDiscovery: Microsoft Teams / Microsoft 365 Group Hold-Location Resolution

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied to the scenario before this file was finalized
(see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A group with no `SharePointSiteUrl` was silently excluded from the resolved fragment, with
   only a per-group `Write-Warning` an operator could easily miss on a multi-group, non-interactive
   run.** If five groups are declared and one comes back with a blank site (provisioning lag,
   `ProvisionSiteOnDemand`), the original draft buried that fact in a `Write-Warning` mixed in among
   four other groups' normal output — a caller who only checks the script's exit code or greps
   `Write-Host` lines for a final status would come away believing every declared group's site is
   covered when one silently isn't. Exactly the "false sense of coverage" failure mode this
   library's own `location-scoped-legal-hold/reviews.md` Red Team round flagged for a different gap.
   - **Resolution:** Added a rolled-up `Write-Warning` after the resolve loop that names every group
     missing a site in one place (`deploy/Resolve-TeamsGroupHoldLocations.ps1`, after the JSON write)
     — visible on every run regardless of how many groups were declared, not dependent on reading
     interleaved per-group output.
2. **The member-roster CSV and resolved JSON fragment defaulted to writing inside `deploy/config/`
   — a tracked directory — rather than a gitignored output location.** A real run's resolved
   mailbox/site addresses are low-sensitivity, but the member-roster CSV (`-ResolveMembers`) is a
   full display-name/SMTP-address roster of an actual group's membership at matter time — the kind
   of file that should never land in a git history by accident.
   - **Resolution:** Both default to `deploy/out/` now (created on first run if missing), matching
     `.gitignore`'s existing tenant-wide `out/` exclusion and this library's own established
     convention (`premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`'s
     `-OutputCsvPath ./deploy/out/...` examples) — not a new pattern invented for this scenario.
3. **Checked: does `siteSource` title-matching (inherited from the sibling scenario's
   `Confirm-SiteSource`) create a *new* risk here, beyond what `location-scoped-legal-hold/design.md`
   §6 already discloses?** No — this scenario's `Confirm-SiteSourceOnHold` only compares against
   sources already on the *specific hold policy* named by `-CaseId`/`-HoldId`, the same
   bounded-scope reasoning the sibling scenario's own Red Team round already confirmed limits the
   failure mode to idempotency bookkeeping (a redundant add attempt), never to holding the wrong
   site's content — the add call itself always uses the real `SharePointSiteUrl` Graph returned, not
   the parsed title.
   - **Not a new finding requiring a scenario change** — confirmed the inherited design is already
     correctly scoped. No fix needed.
4. **Checked: fail-fast-on-first-bad-group-identity (`$ErrorActionPreference = 'Stop'`, no
   per-group try/catch in the main loop) means one typo in a five-group definition file aborts
   resolution for the other four, not just the bad one.** Confirmed this matches this library's
   established pattern (`location-scoped-legal-hold/deploy/New-EdiscoveryLocationHold.ps1`'s own
   main loop has the same fail-fast shape for a bad `userSource`/`siteSource` add), not a
   scenario-specific regression. A partial-continue-and-report design would be a legitimate
   alternative but would diverge from this repo's existing convention without a scenario-specific
   reason to justify the inconsistency.
   - **Not fixed** — consistent with existing repo convention; noted here so the reasoning is
     visible in review, per the sibling scenario's own precedent for recording "checked, not
     changed" findings.
5. **`Set-StrictMode -Version Latest` plus direct `$groupDef.resolveMembers` property access would
   throw a hard "property cannot be found" error for any group entry that omits the (documented as
   optional, default-`false`) `resolveMembers` key** — not a hypothetical: the scenario's own
   README/`.PARAMETER` text tells a buyer this field is optional, so a config that only sets
   `identity` for groups that don't need member resolution is exactly the expected common case, and
   the original draft would have crashed on it.
   - **Resolution:** Added an explicit property-presence check
     (`$groupDef.PSObject.Properties.Name -contains 'resolveMembers'`) before reading the value,
     in the main resolve loop.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Same finding as Red Team #1 and #2 above, from a detectability angle** — an unbounded "which
   groups actually got a site resolved" gap and a version-control leak risk are both operability
   problems as much as security ones (an operator running this on a schedule needs the summary line
   to actually show up in whatever log captures `Write-Host`/`Write-Warning`, and a roster CSV
   committed by accident is a data-handling incident, not just a security exposure).
   - **Resolution:** Same fixes as Red Team #1/#2 — the rolled-up warning and the `deploy/out/`
     default are the detectability half of both fixes; not separate changes.
2. **`validate/Test-TeamsGroupHoldLocations.ps1`'s hold-reconciliation check requires
   `-CaseId`/`-HoldId` and Graph auth parameters together — what happens if only one pair is
   supplied?** Checked: the script requires `-CaseId`/`-HoldId` together (both empty or both set is
   the only path that reaches the hold-check branch) and separately validates the Graph auth
   parameters are all present before attempting a connection, falling back to a `WARN` (not a hard
   crash) if the auth parameters are incomplete — an operator who forgets `-CertificateThumbprint`
   gets a clear, actionable message rather than an unhandled exception mid-run.
   - **Not a new finding requiring a change** — confirmed the initial draft already handles this
     correctly. No fix needed.
3. **Confirmed this scenario's `-AddToHold` reconciliation prints a per-run summary
   ("Reconciled N group(s) onto hold policy...")**, giving an operator a single line to scan for
   "did this run do what I expected" without reading every per-source `Write-Host` line — consistent
   with this library's existing pattern for multi-item deploy scripts.
   - **Not a new finding** — already present in the initial draft. No fix needed.

No remaining Fail. The scenario is operable and its residual gaps (the 100-vs-1,000-member VERIFY,
the inherited `siteSource` title-matching weak point, the SharePoint-provisioning-timing VERIFY) are
disclosed, not silent.

---

## 🎩 CISO

**Verdict: Pass**

1. **This scenario only ever *adds* preservation scope, never removes it** — `-AddToHold` has no
   equivalent to the sibling scenario's `-DeleteHold`/source-removal paths, and this scenario ships
   no removal script of its own (`rollback.md` explicitly defers to the sibling scenario's
   `Remove-EdiscoveryLocationHold.ps1` for that). The asymmetric risk profile between "over-preserve
   a Team that turns out not to matter" (cost, not spoliation exposure) and "under-preserve, or
   improperly release, a location that does matter" (real legal exposure) means the sibling
   scenario's counsel-confirmation gate belongs on removal, not on this scenario's addition path —
   confirmed this design doesn't need an equivalent gate bolted on here.
2. **Who can actually run `-AddToHold` is already bounded by the same Graph app-only RBAC the
   sibling scenario's §3 establishes** (eDiscovery Manager/Administrator-equivalent permission on
   the automation's service principal) — this scenario introduces no new privilege class or
   standing access; it's the same credential doing a narrower, additive action.
3. **Board-level narrative:** "when a regulatory ask or internal sweep names a Team by name, we
   translate that into the exact technical preservation objects our hold automation needs in one
   auditable script run, instead of a person hand-copying a mailbox address and a SharePoint URL out
   of a PowerShell console into a JSON file." A genuine, if modest, reduction in a specific
   error-prone manual step (a mistyped or stale copy-pasted address), not a new capability with new
   risk surface.
4. **Cost:** zero incremental licensing or billable objects — confirmed accurate in §10, consistent
   with the sibling scenario's own cost profile for hold-location management.
5. **Would I fund this?** Yes, as a small, well-scoped complement to the sibling scenario — the kind
   of "close the last-mile translation gap" fragment that's cheap to build and removes a specific,
   named source of operator error, not a strategic capability decision on its own.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **`Get-UnifiedGroup`'s `SharePointSiteUrl` property and `Get-UnifiedGroupLinks -LinkType Members`
   syntax were confirmed by direct fetch of Microsoft's own "Create holds in eDiscovery" walkthrough
   and the two cmdlets' own Exchange PowerShell reference pages** — the exact worked example
   (`Get-UnifiedGroup "Senior Leadership Team" | FL DisplayName,Alias,PrimarySmtpAddress,
   SharePointSiteUrl`) is quoted, not paraphrased from memory or inferred by cmdlet-naming analogy.
2. **Correctly scopes module dependencies leaner than the sibling scenario's** — this scenario's
   `-AddToHold` path never calls a typed `Microsoft.Graph.Security` cmdlet (it only reconciles
   `userSources`/`siteSources` on an *already-existing* case/hold via raw `Invoke-MgGraphRequest`,
   unlike the sibling scenario's case-creation step, which needs the typed
   `New-/Get-MgSecurityCaseEdiscoveryCase` cmdlets) — so this script's `#Requires` correctly lists
   only `Microsoft.Graph.Authentication`, not `Microsoft.Graph.Security`. A smaller, deliberately
   justified dependency footprint, not an oversight.
3. **The "resolve stage doesn't self-connect to Exchange Online, but the reconcile stage
   self-connects to Graph" split is a real inconsistency on its face — verified it's a deliberate,
   documented choice, not an accident.** `design.md` §1 explains the reasoning (matching this
   library's existing EXO-primary-script precedent,
   `premium-legal-hold-and-export/deploy/Export-EdiscoveryAuditTrail.ps1`, rather than the
   Graph-primary sibling scenario's self-connecting pattern) — confirmed this citation is accurate
   and the reasoning holds up, rather than being an unexplained stylistic drift between this
   scenario's two stages.
4. **The 100-member vs. >1,000-member group-expansion-cap discrepancy (README.md §11) is disclosed
   as an open, unresolved VERIFY rather than silently picking one number** — correctly scoped as not
   blocking for this scenario specifically, since this scenario's own output never performs a
   per-member expansion regardless of which cap is current; correctly flagged as relevant to a
   *future* correction of the sibling scenario's own citation, recorded in `PROGRESS.md` rather than
   fixed here without re-verifying which page is authoritative.
5. **v1.0 vs. beta Graph namespace discipline holds** — every Graph call in `deploy/`/`validate/`
   targets `https://graph.microsoft.com/v1.0`, matching the sibling scenario's own discipline;
   no beta endpoint is called or cited as anything but corroborating evidence.
6. **Correctly reuses, rather than reinvents, the sibling scenario's find-or-create idempotency
   pattern for `-AddToHold`** (duplicated, not a new design) — a buyer running both scenarios against
   the same hold policy gets identical idempotent behavior regardless of which script performed a
   given add.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 5 (3 closed with code changes — missing-site rollup, `deploy/out/` default, `resolveMembers` StrictMode fix — 2 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed — same code changes as Red Team #1/#2 — 2 confirmed already correct) | Closed |
| 🎩 CISO | Pass | 5 (asymmetric-risk reasoning, RBAC inheritance, cost, narrative all confirmed sound) | — |
| 🟦 Microsoft Product Owner | Pass | 6 (grounding, dependency scoping, design-split rationale, namespace discipline all confirmed correct) | — |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`,
`README.md`, and `design.md`. No Fail items were raised. This fragment meets the definition of done
in `AGENTS.md` §9.
