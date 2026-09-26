# Four-Lens Review - On-Premises Accepted-Domains Hygiene Check (Hybrid Companion)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The first draft's session check only confirmed `Get-AcceptedDomain` existed somewhere in the
   process - not that it resolved to the on-premises session.** `design.md` §3 already disclosed the
   Import-PSSession/Connect-ExchangeOnline name-collision risk as a documented operational hazard, but
   the deploy and validate scripts' own `Assert`-style checks only called
   `Get-Command Get-AcceptedDomain -ErrorAction SilentlyContinue` - true whether the resolved command
   came from the on-premises session or a co-loaded Exchange Online session. An organization that (against the
   documented guidance) ran both sessions in one process would get a **clean-looking report with zero
   indication anything was wrong** - a silent false negative on the exact control this scenario exists
   to provide, and a worse failure mode than an outright error would have been.
   - **Resolution:** Both `deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1`'s
     `Assert-OnPremisesExchangeSession` and `validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`'s
     live-reconciliation entry point now call `Get-Command Get-AcceptedDomain -All`, which surfaces
     every loaded command with that name across every module/session-state - not just the one an
     unqualified call would resolve to. A count greater than 1 now emits a loud, specific
     `Write-Warning` naming the collision and the exact remediation (`-Prefix`), rather than proceeding
     silently. Deliberately a warning, not a hard failure - the collision alone doesn't prove which
     environment actually got queried on a given run, and a hard failure would block a legitimate
     single-session run for a false-positive reason if only one module happened to shadow-register a
     stub. `README.md` §11 documents this as an automatic check now, not just a manual caution.
2. **The shared `KnownDomains.json` file is a higher-value target than it was for the parent scenario
   alone.** The parent's own Red Team review (its `reviews.md`, finding 2) already disclosed that
   write access to that file lets an actor suppress a finding by adding a malicious domain to the
   allowlist. Because this companion scenario reuses the **same** file (`design.md` §7), compromising
   it now suppresses findings in **both** environments simultaneously with one write, not just one -
   a real escalation in blast radius this build's grounding pass surfaced, not previously stated
   anywhere in this repo.
   - **Resolution:** `README.md` §11 states this explicitly as a companion-specific escalation of the
     parent's already-disclosed risk, reinforcing (not duplicating) the parent's own recommended
     source-controlled/pull-request-reviewed change discipline for that file.
3. **A domain deliberately kept `Authoritative` on-premises but flipped to `ExternalRelay` in a
   future (currently-impossible-per-definition, but not schema-enforced) cloud entry would be silently
   excluded from `CrossEnvironmentMismatch` by the `ExternalRelay`-exclusion rule.** Checked whether
   this is an exploitable gap: since `ExternalRelay` is confirmed on-premises-Exchange-only by
   Microsoft's own applicability statement (`design.md` §2), a cloud-baseline entry legitimately
   showing `ExternalRelay` should never happen in practice - but this script does not itself validate
   that the cloud baseline file it reads is well-formed input, and a corrupted or hand-edited cloud
   baseline claiming `ExternalRelay` would be silently exempted from cross-environment comparison by
   design, on both directions of a potential mismatch.
   - **Resolution:** Not fixed with new validation logic - assessed as out of proportion to the
     threat model (the cloud baseline file is the parent scenario's own trusted output, not
     attacker-reachable input any more than `KnownDomains.json` already is, and is covered by the same
     write-access-discipline recommendation as finding 2). Instead, `README.md` §11's `-CloudBaselinePath`
     documentation is explicit that this is a plain, unauthenticated file read with no schema
     validation, so the same access-control discipline applies to it as to the known-domains config -
     disclosed, not silently assumed safe.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`'s live-reconciliation check had no way
   to verify `CrossEnvironmentMismatch` findings - the one finding category unique to this scenario.**
   The first draft's `-CheckLive` reconciliation mirrored the parent's own two checks
   (`UnexpectedTrustedDomain`/`MissingExpectedDomain`) but had no equivalent for the cross-environment
   direction, meaning a regression in the deploy script's `CrossEnvironmentMismatch` logic - this
   scenario's actual headline capability (`README.md` §8) - could silently go undetected by this
   scenario's own test suite, the exact asymmetry the parent's own Blue Team review (finding 1) caught
   and fixed for its two checks.
   - **Resolution:** Added an optional `-CloudBaselinePath` parameter to the validate script. When
     supplied (alongside `-CheckLive`), it independently recomputes which live on-premises domains
     disagree with the cloud baseline's recorded `DomainType` (excluding `ExternalRelay` pairs, same
     rule as the deploy script) and confirms each one is reflected as a `CrossEnvironmentMismatch`
     finding in the most recent drift-log run - the symmetric check the other two directions already
     had. `README.md` §5/§7 updated to show this parameter in the recommended validation command.
2. **Exit-code alerting correctly covers the new finding category without a separate switch.** Checked
   that `CrossEnvironmentMismatch`'s `FAIL`-severity path (trust-boundary disagreement between
   environments) flows into the same `$failCount`/exit-1 logic as every other category - confirmed by
   inspection, no fix needed. A scheduler already alerting on the deploy script's non-zero exit code
   (parent `README.md` §8's own disclosed dependency, which applies identically here) needs no
   additional wiring for this new category.
3. **Two independent schedules writing to two independent file sets removes a contention risk the
   parent scenario didn't have to solve, but introduces a staleness risk instead.** If the on-premises
   and cloud schedules run at different times (or different cadences), `-CloudBaselinePath` may reflect
   the cloud side's state from up to one full cloud-schedule interval before the on-premises run that
   reads it - a `CrossEnvironmentMismatch` finding could reflect a disagreement that's already been
   corrected on the cloud side, or miss one that hasn't been recorded there yet.
   - **Resolution:** `README.md` §8 states this staleness window explicitly and recommends the deploying organization
     document which scheduling convention they use (on-premises-then-cloud, or accept a one-cycle lag)
     rather than presenting the cross-environment check as reflecting real-time state - matches the
     parent scenario's own honesty precedent for its daily-cadence detection-latency disclosure
     (parent `reviews.md`, Red Team finding 3).

No remaining Fail. Detection, logging (on-premises findings JSON + drift-log CSV, same
SIEM/ticketing-ingestible shape as the parent), and the incident-response runbook (`README.md` §8) meet
the bar for an operable control. The on-premises `-IncludeAuditAttribution` switch is a genuine
operability improvement over the parent's own equivalent (it can attribute Add/Remove, not just
Set-type changes - `design.md` §5), with the `-AdminAuditLogCmdlets`-default VERIFY (§11) as the one
disclosed, unresolved gap in that capability.

---

## 🎩 CISO

**Verdict: Pass**

- **Applicability is narrow and correctly scoped, not oversold.** `README.md` §1 states plainly this
  scenario is only relevant to a hybrid Exchange deployment - a pure-cloud organization should run the parent
  alone. No attempt to inflate this into a general-purpose control every organization needs; a CISO evaluating
  it can immediately tell whether it applies to their environment.
- **Risk reduction vs. cost:** proportionate. No incremental licensing (§10) - the only cost is
  wiring a scheduled job with network reachability to an on-premises server the deploying organization already
  operates, and the engineering/operational overhead of running a second, independent scheduled check.
  For a hybrid organization specifically, this closes a real, previously-undisclosed blind spot (the parent's
  own `design.md` §7 non-goal) at a cost well below the parent scenario's own already-favorable
  cost-to-protection ratio.
- **Board-level narrative:** "We monitor accepted-domains hygiene across both halves of our hybrid
  Exchange deployment, and we can show when the two sides disagree" extends the parent's own concrete,
  auditable claim to the deploying organization's actual full estate rather than leaving a silent gap an auditor could
  reasonably ask about.
- **Compliance mapping:** correctly framed as a compensating/detective control, same class as the
  parent - no overclaiming of real-time or preventive protection. The `CrossEnvironmentMismatch`
  severity model's deliberate refusal to treat every disagreement as `FAIL` (`design.md` §4) is the
  right call for a board narrative too: a control that cried wolf on every legitimate hybrid-migration
  domain would erode trust in its own alerts faster than it built risk reduction.
- **Would I fund this?** Yes, conditionally on the deploying organization actually being hybrid - this is not a
  blanket recommendation for every organization of the parent scenario, and the documentation makes that
  distinction clearly enough that a CISO evaluating the two scenarios together won't over-purchase
  scope they don't need.

No Fix/Fail raised.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Checked whether Microsoft already ships a native hybrid domain-consistency check this scenario
   would be reinventing** (e.g. as part of Hybrid Configuration Wizard health checks or hybrid agent
   diagnostics). This build's grounding pass found no Microsoft-documented capability that validates
   `DomainType` consistency for a given accepted domain **across** the on-premises and Exchange Online
   sides of a hybrid deployment specifically - HCW's own health/diagnostic tooling is documented as
   covering mail-flow connector configuration, not this kind of admin-level policy-consistency check.
   No reinvention found; this fills a genuine, undocumented gap rather than duplicating a native
   capability.
   - **Resolution:** No change needed - `design.md` §1/§4 already frames this as filling a disclosed
     gap, not introducing a new capability class; confirmed accurate on review.
2. **All four newly-cited cmdlets/features (`New-AcceptedDomain`, `Remove-AcceptedDomain`,
   `Search-AdminAuditLog`, `Set-AdminAuditLogConfig`) and the remote-PowerShell connection pattern were
   independently re-verified this build via the canonical `MicrosoftDocs` GitHub source repositories
   Microsoft Learn itself renders from - not carried over from the parent scenario's own citations
   (which only needed `Get-AcceptedDomain`/`Set-AcceptedDomain`) or asserted from training knowledge.**
   `learn.microsoft.com` itself was unreachable from this build's network egress policy (`README.md`
   §12) - flagged explicitly rather than silently substituting an unverified secondary source for a
   primary one.
   - **Resolution:** No change needed - confirmed as the correct grounding discipline on review; the
     one exception (the hybrid `Authoritative`-vs-`InternalRelay` guidance, sourced from secondary
     community content because the primary conceptual page was unreachable) is itself flagged
     inline (`README.md` §11, `design.md` §4) rather than presented with the same confidence as the
     primary-sourced facts.
3. **The `-AdminAuditLogCmdlets` default-value gap needed to be stated as a genuine unknown, not
   filled in with the commonly-assumed `*` default from general Exchange administrator knowledge.**
   This build's own fetch of `Set-AdminAuditLogConfig`'s reference content did not return an explicit
   stated default for that parameter, even though `*`-audits-everything is a widely-repeated
   community assumption. Checked whether to state it as fact anyway (it is very likely correct) -
   decided against, per `AGENTS.md` §4's grounding discipline: only what was actually confirmed by
   this build's own fetch is stated as fact.
   - **Resolution:** No change needed - `design.md` §2, `README.md` §11, and the deploy script's
     `.NOTES` all already carry this as an explicit VERIFY rather than an assumed default; confirmed
     this is the correct level of caution on review, not excessive hedging (the practical
     consequence - an organization should check their own `Get-AdminAuditLogConfig` output before trusting
     `-IncludeAuditAttribution` for an investigation - is concrete and actionable, not vague).
4. **Correctly scoped as a companion, not a fork or a duplicate implementation.** Reuses the parent's
   `KnownDomains.json` schema verbatim, reuses its baseline/drift-log/idempotency shape, and creates no
   Exchange or Purview object of its own - same "protects a shared dependency, doesn't reinvent it"
   pattern the parent scenario's own Product Owner review (finding 2 there) established as correct.

No remaining Fail after resolution. Item 1 in this list surfaced no fix (confirmed no reinvention);
items 2-4 confirmed correct grounding/scoping discipline on inspection rather than finding new defects
- recorded as Fix-then-resolved per this repo's review-format convention rather than folded into a
silent Pass, since each involved an active verification step during this review, not just a read-through.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 false-negative session-collision gap closed with a real code fix, 1 shared-file blast-radius escalation disclosed, 1 corrupted-input edge case assessed and consciously not over-engineered) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script coverage gap for the scenario's own headline finding closed with a real code fix, 1 confirmed correct by inspection, 1 staleness window disclosed) | Closed |
| 🎩 CISO | Pass | 0 | N/A |
| 🟦 Microsoft Product Owner | Fix | 4 (1 confirmed no native-capability reinvention, 1 confirmed independent grounding discipline, 1 confirmed correct VERIFY-not-assumed-default discipline, 1 confirmed correct companion scoping) | Closed |

Both genuine code-level fixes from this round (the `Get-Command -All` session-collision detection in
`deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1` and
`validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`, and the `-CloudBaselinePath` addition to
the validate script for symmetric `CrossEnvironmentMismatch` verification) are present in the current
state of those files. This fragment meets the definition of done in `AGENTS.md` §9. Two open items are
carried forward honestly rather than resolved by guessing, both already disclosed in `README.md` §11
and `design.md` §2/§4: the default value of `-AdminAuditLogCmdlets` is not independently confirmed, and
which `DomainType` is "correct" for a shared-namespace hybrid domain is not resolved to a single rule.
A `PROGRESS.md` follow-up tracks re-verifying the parent scenario's `KnownDomains.sample.json`
`hybrid.contoso.com` entry against a primary Microsoft Learn source once reachable.

---

## Correction addendum - on-premises RBAC cross-reference closed (later build)

**Scope:** doc-only follow-up, not a new four-lens round (no code changed). Closes the
`PROGRESS.md` item this file's own Summary flagged as open: `docs/rbac-model.md` did not yet
document on-premises Exchange RBAC as its own system. A later build added `docs/rbac-model.md`
§13 (on-premises Exchange RBAC - a ninth system), grounded via `WebSearch` result summaries citing
Microsoft Learn URLs (direct `WebFetch` to `learn.microsoft.com` was blocked again in that build's
environment, the same recurring blocker this scenario's own `design.md` §2/§12 already disclosed).

- **Confirms, does not weaken, this review's Red Team/Blue Team/Product Owner findings above.**
  §13 documents **Organization Management** as the confirmed-sufficient role group (matching
  `README.md` §3/§11 unchanged) and records three narrower candidates (**Compliance Management**,
  **View-Only Organization Management**, **Recipient Management**) as explicit, source-cited
  **VERIFY** leads rather than asserting any of them as a confirmed least-privilege alternative -
  the same "state the genuine unknown, don't fill it in from common assumption" discipline
  Product Owner finding 3 above required for `-AdminAuditLogCmdlets`'s default value.
- **`README.md` §3/§11 updated in place** to point at `docs/rbac-model.md` §13 instead of stating
  the gap as still open.
- No new Fix/Fail: this closes a documentation cross-reference gap, not a defect in this
  scenario's own docs/code.

## Correction addendum - shared-namespace `InternalRelay`-vs-`Authoritative` question closed (later build)

**Scope:** doc-only follow-up, not a new four-lens round (no code changed). Closes the
`PROGRESS.md` item this file's own Summary flagged as open: which `DomainType` is "correct" for a
shared-namespace hybrid domain, and whether the parent scenario's `KnownDomains.sample.json`
`hybrid.contoso.com` (`InternalRelay`) entry needed correcting. A later build's `WebSearch` pass
(direct `WebFetch` to `learn.microsoft.com` was blocked again, the same recurring restriction
already disclosed in `README.md` §12) found three authoritative Microsoft Learn conceptual pages -
not secondary community/Q&A content this time - that resolve the question: `InternalRelay` is the
documented shared-namespace case, and `Authoritative`+Directory-Based-Edge-Blocking is a domain's
*later* state, reached only once all recipients are migrated to Exchange Online, not a contradiction
of the sample's own "coexistence domain" label.

- **Confirms, does not weaken, this review's findings above.** No sample or code correction was
  needed - the ambiguity was in `design.md` §4's framing of the open question, not in the sample
  itself, matching this repo's discipline of stating a genuine unknown rather than guessing (Product
  Owner finding 3 above) but now updating that record once the unknown is actually resolved with a
  primary source, rather than leaving it open indefinitely.
- **`design.md` §4 and `README.md` §11/§12 updated in place** with the citation trail; the
  `CrossEnvironmentMismatch` check's `WARN`-not-`FAIL` severity is unchanged (still correct - a live
  tenant can legitimately be mid-migration on one side and not the other).
- No new Fix/Fail: this closes a disclosed grounding gap with a primary source, not a defect in this
  scenario's own docs/code.

---

## Follow-up four-lens review - `MatchSubDomains`/`Default` cross-environment reconciliation (later build)

**Scope:** a real code change, not a doc-only correction addendum. Closes the `design.md` §9 non-goal
("Does not attempt to reconcile `MatchSubDomains`/`Default` flags across environments... once a concrete
organization need surfaces one") once that follow-up was picked up from `PROGRESS.md`. Adds two new finding
categories to `deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1`'s cross-environment check
(§4): `CrossEnvironmentMatchSubDomainsMismatch` and `CrossEnvironmentDefaultMismatch`, alongside the
existing `CrossEnvironmentMismatch` (`DomainType`). A full four-lens round, not a correction addendum,
because this is new detection logic shipping, not a documentation fix.

### 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The first draft folded all three fields into the single existing `CrossEnvironmentMismatch`
   category.** For a domain diverging on both `MatchSubDomains` and `Default` in the same run, this
   produces two rows sharing the same `(RunId, Category, DomainName)` key - the drift-log CSV's
   documented uniqueness invariant (§6, matching the parent scenario's own model). This isn't a
   cosmetic issue: `validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1`'s existing duplicate-row
   check exists specifically to catch replace-by-`RunId` idempotency regressions, and a genuine,
   intentional two-finding case would trip it as a false `[FAIL]`, training an operator to distrust or
   ignore that check - the same "erodes trust in its own alerts" failure mode the CISO lens already
   flagged for over-alerting in the original round.
   - **Verified directly, not just reasoned about:** a mocked-`Get-AcceptedDomain` PowerShell 7.4.6 run
     (two domains, one diverging on `MatchSubDomains`+`Default` simultaneously) reproduced the
     collision exactly as predicted - `validate/...ps1` reported `[FAIL] No duplicate (RunId, Category,
     DomainName) rows in the drift log` against the single-category draft.
   - **Resolution:** Split into three separate categories (`CrossEnvironmentMismatch`/
     `CrossEnvironmentMatchSubDomainsMismatch`/`CrossEnvironmentDefaultMismatch`), mirroring this
     scenario's own baseline-diff block's existing per-field-category convention (§6). Re-ran the same
     mocked scenario after the fix: 4 distinct findings, 5 total drift-log rows (including the
     unrelated `UnexpectedTrustedDomain`), zero duplicate-key failures, confirmed by both the deploy
     script's own summary and the validate script's symmetric reconciliation. Re-ran a second time with
     an unchanged `-RunId` to confirm replace-by-`RunId` idempotency held (5 rows before, 5 after, no
     duplication) - the exact regression class this finding was about.
2. **`MatchSubDomains` severity: does the FAIL threshold actually catch the risk it claims to?** The
   rule is FAIL if *either* side has `MatchSubDomains=$true`. Considered whether a narrower rule (FAIL
   only if the *more permissive* side is the one a DLP `FromScope` condition doesn't see) would be more
   precise. Rejected: which side a given DLP/mail-flow rule actually evaluates depends on where the
   message currently routes, which this script cannot determine from two baseline snapshots alone -
   the broader "either side" rule is the safe default, and the finding `Detail` text already tells the
   operator to check which side is the more restrictive one before triaging (matches this scenario's
   established pattern of disclosing interpretation limits rather than asserting more certainty than
   the read-only data supports).

No remaining Fix/Fail after resolution.

### 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The validate script's original single-category symmetric check couldn't detect under-reporting on
   the two new categories.** Before this round, `-CheckLive -CloudBaselinePath` only reconciled
   `DomainType` disagreements - the exact "new finding category ships with no way to prove it isn't
   silently under-reporting" gap the original round's own Blue Team finding 1 already fixed once for
   `CrossEnvironmentMismatch`, now recurring for its two new siblings.
   - **Resolution:** Extended the same reconciliation block to independently recompute
     `MatchSubDomains`/`Default` disagreements and confirm each is reflected under its own category
     name in the most recent drift-log run - verified live: the mocked functional test above exercised
     `-CheckLive -CloudBaselinePath` end to end and every expected finding reconciled as `[PASS]`.
2. **Exit-code alerting correctly covers both new categories without a separate switch.** Confirmed by
   inspection: `Add-Finding` still routes every category through the same `$findings` list and
   `$failCount`/exit-1 logic regardless of category name - no fix needed, and the mocked test's exit
   code (1, driven by the `MatchSubDomains` `FAIL` rows) confirms it live, not just by reading the code.
3. **`CrossEnvironmentDefaultMismatch` is always `WARN`, never `FAIL` - confirm this doesn't create a
   silent blind spot.** Considered whether an attacker who could flip a domain's `Default` flag could
   use it for anything actionable enough to warrant `FAIL`. `Default` governs new-recipient primary
   SMTP address generation (§4), not mail acceptance or trust boundary - changing it doesn't grant an
   attacker mail delivery for a domain they don't already control acceptance for. `WARN` is
   proportionate to the actual risk, not a coverage gap.

No remaining Fail. The new categories inherit the same drift-log CSV / findings-JSON evidentiary shape
and the same scheduler exit-code contract as every other category in this scenario - no new alerting
plumbing required at the deploying organization's SIEM/ticketing layer.

### 🎩 CISO

**Verdict: Pass**

- **Incremental, not scope-creeping.** This closes a non-goal `design.md` §9 explicitly deferred
  "pending a concrete organization need" - the discipline that non-goal called for was followed: it stayed
  deferred until picked up as a scoped `PROGRESS.md` follow-up, not built speculatively ahead of need.
- **Cost:** zero incremental licensing or infrastructure - same deploy/validate scripts, same schedule,
  same output files, three more field comparisons per already-read domain object. No new decision for
  a CISO to fund separately; it rides the existing scenario's already-approved cost basis.
- **Narrows a real, previously-silent gap without overclaiming.** Before this round, a hybrid organization
  could have `DomainType` parity across environments while silently diverging on subdomain-mail
  acceptance - a gap the original scenario's own `README.md` never claimed to cover. The board
  narrative ("we monitor accepted-domains configuration for drift across our hybrid estate") is now
  actually true of all three fields Exchange exposes per domain, not just one.
- **`CrossEnvironmentDefaultMismatch`'s permanent `WARN` severity is the right compliance posture** -
  it avoids manufacturing false urgency around an operational-hygiene signal that isn't a trust-boundary
  control, preserving the credibility of the `FAIL` signals that are.

No Fix/Fail raised.

### 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Are `MatchSubDomains` and `Default` grounded against a primary Microsoft source, not assumed from
   naming convention?** `learn.microsoft.com` was blocked again in this build's network egress (the
   same recurring restriction `README.md` §12 already discloses); fetched `Set-AcceptedDomain.md`
   directly from the canonical `MicrosoftDocs/office-docs-powershell` GitHub source instead (the same
   grounding method this scenario's original build used for its five core citations). Confirmed
   verbatim: `-MatchSubDomains` "enables mail to be sent by and received from users on any subdomain of
   this accepted domain," default `$false`; `-MakeDefault` "specifies whether the accepted domain is
   the default domain."
   - **Resolution:** No fabrication - both properties were already used, unexamined, by the *parent*
     scenario's own baseline JSON shape and this scenario's baseline-diff block before this round; this
     round is the first to cite their actual Microsoft-documented semantics directly (`README.md` §12
     reference 4, updated).
2. **Does `-MakeDefault $true` on one domain provably clear `Default` from whichever domain held it
   previously?** Microsoft's own reference states what the parameter does but not this side effect.
   Asserting a single-default invariant as fact would violate this repo's `AGENTS.md` §4 grounding
   standard.
   - **Resolution:** Not asserted as fact. `README.md` §8's remediation step and §11's limitations both
     state this as an explicit VERIFY (pilot tenant) rather than an assumed behavior - the finding's own
     severity (`WARN`, never `FAIL`) doesn't depend on the answer either way, so this doesn't block
     shipping the check, only the specific one-step-fix remediation claim.
3. **Is a three-category design the right shape, or should this have been a single category with a
   `Field` column added to the CSV schema instead?** Considered both. A schema change (`Field` column)
   would also fix the uniqueness-key collision, but would diverge the drift-log CSV shape from the
   parent scenario's own (§6's stated "same shape" contract) and from this scenario's own baseline-diff
   block, which already solves the identical structural problem with per-field categories, not an extra
   column. Three categories is the smaller, more consistent change.
   - **Resolution:** No change - three-category design confirmed as the better fit for this repo's
     existing conventions on review, not just the first idea that worked.

No remaining Fail.

### Summary - follow-up round

| Lens | Verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (1 real drift-log row-collision bug found via direct functional testing and fixed with a three-category redesign, 1 severity-threshold choice reviewed and confirmed correct) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script coverage gap for both new categories closed with a real code fix, 1 confirmed correct by inspection and live test, 1 severity-proportionality check confirmed no blind spot) | Closed |
| 🎩 CISO | Pass | 0 | N/A |
| 🟦 Microsoft Product Owner | Fix | 3 (1 confirmed primary-source grounding not naming-convention guessing, 1 confirmed a genuine unknown stayed disclosed as VERIFY rather than asserted, 1 confirmed the three-category design over a schema-change alternative) | Closed |

The row-collision bug this round found and fixed was caught by actually running the modified scripts
against a mocked on-premises session (PowerShell 7.4.6) with a domain deliberately diverging on
multiple fields at once - not by static review alone - matching this repo's stated verification bar.
Both the deploy and validate script changes were re-tested after the fix, including a same-`RunId`
re-run to confirm replace-by-`RunId` idempotency held. One VERIFY carried forward rather than resolved
by guessing: whether `-MakeDefault $true` clears the flag from the domain that previously held it
(`README.md` §8/§11/§12). This follow-up meets the definition of done in `AGENTS.md` §9.
