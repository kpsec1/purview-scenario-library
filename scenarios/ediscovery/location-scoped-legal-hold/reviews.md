# Four-Lens Review — eDiscovery: Location-Scoped Legal Hold

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Distribution-list expansion is a VERIFY, not a confirmed capability — and if it silently
   doesn't work the way this scenario assumes, the failure mode is "false sense of coverage," not
   an obvious error.** If a tenant's Graph endpoint does *not* expand a distribution list's SMTP
   address into member mailboxes the way the beta custodian-context reference and the "Distribution
   group has too many members" error both imply, the most likely outcome isn't a hard `400` — it's
   a `userSource` that silently holds only the DL's own (largely empty) arbitration mailbox while
   every actual member's mailbox remains completely unheld. A legal team that deployed this
   scenario against a regulatory-sweep DL and later relied on "the hold covers the list" would be
   wrong in exactly the way that matters most for a spoliation claim, with nothing in this
   scenario's own object model flagging the gap (a `userSource` in that state still reports
   `holdStatus: applied` — for the one mailbox it actually is holding).
   - **Resolution:** Sharpened `README.md` §11 and `design.md` §3's VERIFY language from a general
     "confirm before relying on this" note to an explicit instruction: for a distribution list,
     confirm real member-mailbox coverage against a pilot tenant (for example, by independently
     adding one known member's own mailbox as a second, explicit `userSource` and confirming its
     `holdStatus` — the DL-expansion path and the explicit-member path aren't mutually exclusive,
     and a buyer with a size- or compliance-sensitive matter should prefer resolving and listing
     members explicitly over trusting unverified server-side expansion. Not fixed by adding
     unverified membership-resolution code to the deploy script itself, which would just move the
     same unverified assumption one layer deeper — the honest fix here is sharper disclosure and a
     concrete verification step, per `AGENTS.md` §4.
2. **A blank `contentQuery` silently holds everything in every attached location, with no warning
   at deploy time in the original draft.** Unlike the custodian scenario (where `contentQuery`
   lives on the *search*, run explicitly and separately from the hold), this scenario's
   `contentQuery` lives directly on the hold policy itself — an operator who leaves it blank
   thinking it's optional boilerplate (it is optional, syntactically) ends up holding the entire
   contents of a shared mailbox or site indefinitely, with real storage-growth and scope-creep
   consequences neither the original deploy nor validate script surfaced.
   - **Resolution:** Added an explicit `Write-Warning` in
     `deploy/New-EdiscoveryLocationHold.ps1`'s `Get-OrNewHoldPolicy` when `contentQuery` is absent,
     and a matching `WARN` check in `validate/Test-EdiscoveryLocationHold.ps1` so a blank
     `contentQuery` is visible on every subsequent drift check, not just at first deploy.
3. **`siteSource` idempotency matching by parsed URL slug vs. returned title is a real, disclosed
   weak point (`design.md` §6) — could this cause the wrong site to be treated as "already held"?**
   Checked: `Confirm-SiteSource` only compares against sources already present *on this specific
   hold policy* (a small, operator-controlled list), never against a tenant-wide site index — so
   the failure mode is a false-positive/false-negative on this scenario's own idempotency check
   (redundant duplicate add, or an unnecessary re-add attempt), not an accidental hold on an
   unrelated site elsewhere in the tenant. The `Confirm-SiteSource`/`New-...` add call itself always
   uses the real, full `webUrl` from the definition file, never the parsed title — so the *content
   actually held* is always correct regardless of the matching weakness.
   - **Not a new finding requiring a scenario change** — confirmed the existing disclosure
     (`design.md` §6, `README.md` §11) already correctly scopes the risk to idempotency bookkeeping,
     not to holding the wrong content. No fix needed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No poll-and-wait option for newly added sources, unlike the sibling custodian scenario's
   `-WaitForHold`.** The original draft only offered `-Retry` (for sources already in an
   error/partial state) and the separate `validate/` script (run as a distinct step) — an operator
   used to the sibling scenario's pattern would reasonably expect the same "wait and confirm inline"
   option here.
   - **Resolution:** Added `-WaitForApplied` to `deploy/New-EdiscoveryLocationHold.ps1`, polling
     each newly added `userSource`/`siteSource`'s `holdStatus` until it leaves `applying` (bounded
     by `-ApplyPollTimeoutSeconds`), mirroring the sibling scenario's `-WaitForHold` shape.
2. **The blank-`contentQuery` gap (Red Team finding 2, above) is also a Blue Team detectability
   concern** — an unbounded hold with no visible warning in either the deploy log or a later
   validate run is exactly the kind of silent-scope-creep condition an operator running scheduled
   validation should be able to catch without reading the raw API response by hand.
   - **Resolution:** Same fix as Red Team finding 2 — the `WARN`-level check in
     `validate/Test-EdiscoveryLocationHold.ps1` is the detectability half of that fix; not a
     separate change.
3. **`retryPolicy` restamps every source in the policy, not just the failed one** — a large hold
   policy with many locations could see unnecessary churn/throttling risk if `-Retry` were called
   in a tight automated loop rather than as a deliberate, human-triggered step.
   - **Resolution:** Confirmed this is already disclosed correctly — `Invoke-RetryIfNeeded`'s own
     `Write-Warning` text and `README.md` §5 step 4 both frame `-Retry` as a deliberate follow-up
     action, not something wired into a tight polling loop; `-Retry` is off by default and this
     scenario doesn't schedule it automatically anywhere. No code change needed, noted here so the
     reasoning is visible in review.

No remaining Fail. The scenario is operable and its residual gaps (VERIFY items, the disclosed
`siteSource` matching weak point) are disclosed, not silent.

---

## 🎩 CISO

**Verdict: Pass**

1. **The counsel-confirmation gating prerequisite was already promoted to `README.md` §3 up front
   in the initial draft** (not left buried in `rollback.md` alone), applying the precedent this
   library's `premium-legal-hold-and-export` and `harassment-and-code-of-conduct` scenarios each
   established after their own CISO review rounds found the same gap. Confirmed this scenario
   didn't need a Fix here because that lesson was already applied proactively during drafting.
2. **Risk profile is, if anything, higher-stakes than the sibling custodian scenario's, and the
   draft is honest about that rather than presenting this as a drop-in equivalent** — the "no
   reversible pause on v1.0" finding (`design.md` §4) means every rollback path here risks
   permanent content loss in a way the custodian scenario's `release`/`re-apply` cycle doesn't.
   `rollback.md` quotes Microsoft's own warning verbatim rather than paraphrasing it into something
   softer.
3. **Board-level narrative:** "we can preserve content tied to a function, list, or shared resource
   — not just a named individual — the moment a regulatory inquiry or internal sweep names one,
   with the same repeatable, auditable process as our named-custodian holds." Clear, and explicit
   about where this control's guarantees stop (the DL-expansion VERIFY, the `siteSource` matching
   weak point) rather than overclaiming coverage.
4. **Cost:** no new licensing category beyond what §10 (and the sibling scenario's §10) already
   establishes — the one incremental cost-relevant fact (a shared/functional mailbox needs the same
   entitlement a person's mailbox would) is called out explicitly in §3, not left implicit.
5. **Would I fund this?** Yes, as a direct complement to the custodian scenario for the same
   reasons that scenario's own CISO review already established — and specifically *because* the
   "distribution list / shared resource" preservation shape is common enough in real regulatory
   sweeps that not having an automated path for it would force legal ops back to ad hoc portal
   work for a meaningful fraction of matters.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **The "no v1.0 typed cmdlet, `enablePolicy`/`disablePolicy` are beta-only" finding is
   independently re-confirmed, not assumed from the sibling scenario's own beta-vs-v1.0 discipline
   alone** — this build directly fetched the v1.0 `ediscoveryHoldPolicy` resource's own method list
   (no enable/disable action listed), the v1.0 Update reference (only `contentQuery`/`description`
   are updatable — `isEnabled` is not), and both beta `enablePolicy`/`disablePolicy` action pages
   independently, rather than inferring the gap from the resource page's prose alone.
2. **The `userSource.includedSources = 'mailbox'`-only design decision is a strength worth calling
   out, not just a resolved ambiguity** — this endpoint's own v1.0 reference states the constraint
   in plain English ("Only mailbox is applicable for user sources"), which is a *more* directly
   confirmed data point than the sibling custodian scenario's own still-open `'mailbox, site'`
   VERIFY. The scenario correctly doesn't import the sibling's uncertainty into a context where
   Microsoft's own docs are actually unambiguous.
3. **Cmdlet/endpoint names are verified per-call against their own canonical reference pages** — no
   name was inferred by pattern analogy in this build; the one place this scenario *does* rely on
   analogy (the DL-expansion behavior, §3) is explicitly disclosed as analogy-based rather than
   confirmed, consistent with `AGENTS.md` §4.
4. **v1.0 vs. beta namespace discipline is correct throughout** — every REST call in `deploy/`/
   `validate/` targets `https://graph.microsoft.com/v1.0`; the one beta reference cited
   (`edisc-legalhold-post-usersources`, beta) is cited only as corroborating evidence for the §3
   VERIFY, never as a basis for a script to call the beta endpoint itself.
5. **Correctly reuses, rather than re-implements, the sibling scenario's case find-or-create
   pattern** (`New-MgSecurityCaseEdiscoveryCase`, typed v1.0 cmdlet) instead of introducing a second,
   inconsistent way to create a case — the two scenarios can safely target the same case.
6. **Licensing citations are consistent with `docs/licensing-matrix.md` and the sibling scenario's
   own §3/§10** — the one new claim (shared/functional mailbox entitlement) is a direct, correctly
   scoped extension of an already-grounded rule, not a new uncross-checked claim.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with disclosure/code changes, 1 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed with code changes — `-WaitForApplied`, blank-`contentQuery` `WARN` — 1 confirmed already correctly disclosed) | Closed |
| 🎩 CISO | Pass | 5 (gating prerequisite already applied proactively; overall verdict Pass) | — |
| 🟦 Microsoft Product Owner | Pass | 6 (all confirmed correct/well-grounded, no changes required) | — |

All Fix items from this round are resolved in the current state of `deploy/`, `validate/`,
`README.md`, and `design.md`. No Fail items were raised. This fragment meets the definition of
done in `AGENTS.md` §9.
