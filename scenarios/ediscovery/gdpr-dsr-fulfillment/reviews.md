# Four-Lens Review — GDPR Data Subject Request (DSR) Fulfillment

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized. No **Fail** items
remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The default (custodian-scoped) search cannot see content *about* the data subject that lives
   in someone else's mailbox.** `dataSourceScopes: allCaseCustodians` only reaches the sources the
   data subject is a custodian of (their own mailbox + site). A colleague's email discussing the
   data subject, with the data subject only cc'd or named in the body, is invisible to this
   scenario's primary search — a genuine Article 15 completeness gap that could let an
   organization under-deliver on an Access request and not even know it.
   - **Resolution:** Added an opt-in `-IncludeParticipantSearch` switch to `New-DsrRequest.ps1`
     that creates a second, tenant-wide `dataSourceScopes: allTenantMailboxes` search with
     `contentQuery: "participants:<email>"`, grounded against Microsoft's documented recipient-
     property KQL expansion. Off by default (same blast-radius tradeoff
     `search-and-purge-data-spillage` already disclosed for its own tenant-wide sweep), and its
     existence and residual SharePoint/OneDrive gap are both stated plainly in `README.md` §11 and
     `design.md` §3 rather than silently left as an unstated limitation.
2. **A populated request-definition file or the ledger, if ever committed to source control,
   permanently exposes a real person's name, email, and DSR history in git history** — worse than a
   single incident's spillage, since the ledger accumulates every request over time.
   - **Resolution:** Added dedicated `.gitignore` patterns (`dsr-ledger.json`,
     `dsr-ledger.*.json`, and every non-`.sample.json` file under this scenario's `deploy/policy/`)
     with a negation rule keeping the illustrative sample tracked. Verified with `git add -n` that
     the sample file is staged and would-be real request files are not. `README.md` §11 calls this
     out explicitly rather than assuming a generic repo-level `.gitignore` would already cover a
     scenario-specific filename.
3. **A fabricated DSR could be used to justify snooping on a colleague's mailbox** (create a case,
   add them as a "data subject" custodian, search their content) by someone with the right role.
   - **Resolution:** Not a gap this scenario's code can close — RBAC already scopes case/custodian
     authoring to the least-privileged eDiscovery Manager/Custodian role combination
     (`docs/rbac-model.md` §4, same as this repo's other eDiscovery scenarios), and `README.md`
     §8/§11 states plainly that identity verification of the requester happens *before* this
     scenario's scripts run, as an organizational prerequisite this scenario's code cannot enforce.
     Confirmed as an accepted, disclosed residual risk rather than left unstated.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`Test-DsrRequest.ps1`'s SLA check is pull-based, not push-based** — nothing pages anyone when
   a request goes Overdue unless someone runs (or schedules) the script.
   - **Resolution:** `README.md` §8 recommends scheduling the script and routing its non-zero exit
     code to the organization's own ticketing/alerting system, the same disclosed pattern this
     repo's `search-and-purge-data-spillage` sibling uses for its own no-native-alerting gap, rather
     than presenting manual, undocumented polling as the only option.
2. **The ledger has no concurrent-write protection** — a classic read-modify-write race if two
   operators (or two scheduled jobs) update it at the same moment, silently losing one write.
   - **Resolution:** Disclosed directly in `README.md` §11 as a known limitation, with explicit
     guidance to serialize execution at low-to-moderate volume and to consider Priva instead of
     scaling this scenario's flat-file ledger further (§10) — not silently presented as
     production-safe at any volume.
3. **The optional participant search's results have no automated cross-check against the primary
   custodian search** — an operator could review only the primary search's estimate and forget the
   participant search exists.
   - **Resolution:** `New-DsrRequest.ps1`'s console output prints a dedicated line naming the
     participant search ID when `-IncludeParticipantSearch` is used, and
     `Test-DsrRequest.ps1` checks for and reports its existence whenever a ledger entry carries a
     `participantSearchId`, so a validation run surfaces it even if the original operator's console
     output is long gone.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Pass**

1. **Would I fund this?** Yes — it closes a gap `gdpr-assessment` already named as a real exposure
   (an Article 12(3) deadline with no tracking mechanism at all), reuses entitlements the
   organization likely already holds for its other eDiscovery scenarios, and the marginal
   engineering cost is small because it composes already-built, already-reviewed scripts rather
   than duplicating them.
2. **Honest about what it isn't**, which is itself a CISO-relevant property: §2's warning banner
   states plainly this is not Priva, and §6/§11 state plainly that half the GDPR DSR activity types
   (Rectification, Restriction, Objection) have zero technical fulfillment here — a vendor tool that
   overclaimed DSR coverage would create false assurance at exactly the moment a regulator asks
   "how do you handle this."
3. **Governance is least-privilege by construction**, not bolted on: no hold is applied (avoiding an
   unnecessary, disproportionate preservation action against the requester's own mailbox), and RBAC
   reuses this repo's already-reviewed eDiscovery role scoping rather than granting anything new.
4. **Scale is honestly bounded.** §10 states this scenario is sized for low-to-moderate DSR volume
   and names the point (a flat-file ledger, no locking) at which Priva becomes the better answer,
   rather than presenting this scenario as infinitely scalable.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with a disclosed grounding-method caveat)**

1. **Correct, current mechanism — two specific traps avoided.** This build's grounding pass
   confirmed the classic "User Data Search" DSR case tool was retired and merged into eDiscovery
   (Standard) on August 30, 2023 (a year *before* the broader classic-eDiscovery retirement this
   repo's other siblings already found) — this scenario is built on the current, non-retired,
   already-merged mechanism, not the old dedicated tool. It also correctly stays off Microsoft
   Priva's Subject Rights Requests surface, which `docs/automation-surface.md` §4 already lists as
   out of scope for this library.
2. **Reuses this repo's own already-grounded cmdlet sequence** (`New-MgSecurityCaseEdiscoveryCase`,
   `*CaseCustodian`, `*CaseCustodianUserSource`, `*CaseSearch`) verbatim from
   `premium-legal-hold-and-export`, rather than re-deriving or guessing a parallel one — the
   `includedSources: 'mailbox, site'` VERIFY that sibling already carries is correctly inherited,
   not silently dropped.
3. **`dataSourceScopes` enum grounded directly**, not assumed: `allCaseCustodians` (primary
   search) and `allTenantMailboxes` (optional participant search) both confirmed against the
   `ediscoverySearch` resource-type reference's documented enum, and `contentQuery`'s optional
   status confirmed against the Create searches reference rather than assumed from the sibling
   scenarios' own (always-populated) usage.
4. **Right feature for the job, complementary rather than duplicative** — composes
   `premium-legal-hold-and-export` (export) and `search-and-purge-data-spillage` (purge) via
   hand-off instead of reimplementing either, exactly the Product Owner concern §5's design
   documents directly.
5. **One disclosed process limitation, not a factual one:** this build's Microsoft Learn MCP tool
   was unavailable in this execution environment, so grounding used web search against
   learn.microsoft.com rather than a direct full-page fetch (README.md §12's closing note). Every
   cmdlet name, enum value, and URL cited was corroborated by at least one direct search-result
   excerpt (in several cases, cross-checked against this repo's own already-fetched sibling-scenario
   grounding for the identical cmdlets), and no cmdlet or blade path was invented — but a
   direct-fetch re-verification pass before a customer-facing deployment is recommended precisely
   because this build could not perform one itself, and is called out as such rather than presented
   as equivalent to a full-page-fetch grounding pass.

No Fix/Fail raised — item 5 is a disclosed process caveat, not a factual finding requiring
correction.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (custodian-scoped search misses participant-only content — fixed with an opt-in second search; uncommitted-PII risk — fixed with `.gitignore` patterns; fabricated-DSR snooping risk — confirmed as a disclosed, RBAC-mitigated residual risk) | Closed |
| 🔵 Blue Team | Fix | 3 (pull-based SLA alerting — disclosed with a scheduling/alerting recommendation; ledger concurrent-write race — disclosed with a volume-bounded scope statement; participant-search visibility — fixed via console output + validate-script cross-check) | Closed |
| 🎩 CISO | Pass | 0 new findings; funding rationale, honest non-Priva/non-full-coverage framing, least-privilege governance, and bounded-scale honesty all confirmed | — |
| 🟦 Microsoft Product Owner | Pass | 0 new findings; correct non-retired/non-Priva mechanism, reused already-grounded cmdlet sequence, directly-confirmed enum values, complementary (not duplicative) design, and one disclosed grounding-method caveat all confirmed | — |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/New-DsrRequest.ps1`, `deploy/policy/dsr-request-definition.sample.json`,
`validate/Test-DsrRequest.ps1`, `rollback.md`, and the repository root `.gitignore`. No Fail items
were raised. This fragment meets the definition of done in `AGENTS.md` §9; product facts are
grounded in Microsoft Learn via web search (Microsoft Learn MCP unavailable in this execution
environment — disclosed above and in `README.md` §12, not silently substituted), no cmdlet or
blade path was invented, and the scenario's honest scope boundary (Access/Portability/Erasure only,
via hand-off to already-reviewed siblings; Rectification/Restriction/Objection tracked but not
fulfilled) is treated as the central design constraint throughout, not smoothed over.
