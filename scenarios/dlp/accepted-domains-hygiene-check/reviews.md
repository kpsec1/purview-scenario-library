# Four-Lens Review - DLP Accepted-Domains Hygiene Check

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The baseline diff didn't check `MatchSubDomains` drift at all - the single biggest gap in the
   first draft.** A domain already present in the known-domains config, with an unchanged
   `DomainType`, that has its `MatchSubDomains` flag flipped to `$true` silently extends
   in-organization trust to *every subdomain* of that domain for every `FromScope`-consuming rule in
   the tenant. The first draft's `DomainTypeChangedSincePreviousRun`/`DefaultChangedSincePreviousRun`
   checks would not have caught this - an attacker (or an unreviewed misconfiguration) who flips this
   one flag on an already-trusted domain would produce zero findings from the original design.
   - **Resolution:** Added an independent `MatchSubDomainsChangedSincePreviousRun` finding
     (`FAIL` if flipped to `$true` on an in-organization domain, else `WARN`) to
     `deploy/Export-AcceptedDomainsHygieneReport.ps1`'s baseline-diff logic. While fixing this, also
     found and fixed a second, related bug: the original diff used an `elseif` chain, so a domain
     that changed **both** `DomainType` and `Default` (or now, `MatchSubDomains`) in the same run
     would only report the first match, silently dropping the others. Changed to independent `if`
     checks so multiple simultaneous changes on the same domain are each reported. Covered by a new
     functional test in `README.md` §7 step 5.
2. **The known-domains config and baseline files are trusted inputs this scenario does not itself
   protect.** Write access to `KnownDomains.json` lets an actor make a malicious domain pass review by
   simply adding it to the allowlist; write access to the baseline file lets an actor pre-seed a
   domain into the "already known" state, suppressing the `DomainAddedSincePreviousRun` finding that
   would otherwise catch it. Neither risk was disclosed in the first draft.
   - **Resolution:** Added an explicit `README.md` §11 limitation naming both risks and recommending
     source-controlled/pull-request-reviewed change discipline for `KnownDomains.json` and
     restricted, automation-identity-only write access for the baseline file - the same class of
     operational prerequisite disclosure this repo already uses for `copilot-external-email-block`'s
     accepted-domains dependency.
3. **This is a detective control with a real, undisclosed detection-latency window.** The first draft
   recommended a daily cadence without stating the practical consequence: a domain added minutes
   after a scheduled run holds unreviewed in-organization trust for up to a full day before this
   scenario's next run surfaces it. Not a flaw in the design (a real-time push-based alternative isn't
   available - Microsoft publishes no event-driven trigger for accepted-domains changes, `design.md`
   §5), but stating the honest latency window matters for an organization deciding whether daily is
   sufficient for their risk tolerance.
   - **Resolution:** `README.md` §8 now states the detection-latency trade-off explicitly and
     documents how to run this scenario on a sub-daily cadence (an explicit, more granular `-RunId`)
     for a higher-assurance environment, rather than presenting daily as the only option.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **`validate/Test-AcceptedDomainsHygieneReport.ps1`'s live-reconciliation check only covered the
   silent-bypass direction, not the false-positive-exclusion direction.** The first draft's
   `-CheckLive` reconciliation confirmed every unreviewed live trusted domain is reflected as an
   `UnexpectedTrustedDomain` finding, but had no equivalent check confirming a *missing* required
   domain is reflected as a `MissingExpectedDomain` finding - an asymmetric validation that would have
   let a regression in the deploy script's first check (§3, `design.md`) go undetected by this
   scenario's own test suite while the second check's regression would not.
   - **Resolution:** Added the symmetric check to `validate/Test-AcceptedDomainsHygieneReport.ps1` -
     every `required: true` known domain absent from live `Get-AcceptedDomain` is now confirmed
     reflected as a `MissingExpectedDomain` finding in the most recent drift-log run, matching the
     existing `UnexpectedTrustedDomain` check's structure.
2. **Exit-code-based alerting only works if the scheduler actually surfaces it.** The deploy script's
   non-zero exit on any `FAIL`-severity finding (README.md §6) is only useful if whatever runs it on a
   schedule (Azure Automation, a cron job, a scheduled task) is itself configured to alert on a
   non-zero exit - an easy step to skip silently, leaving the control technically running but
   practically unmonitored.
   - **Resolution:** `README.md` §8's incident-response runbook already assumed alerting was wired
     up; added no further change here since this is inherently a platform-configuration step outside
     this scenario's own code (the same boundary `classification-coverage-report/rollback.md` draws
     for its own scheduling mechanism) - confirmed this is disclosed, not silently assumed, via the
     existing §5 step 6 instruction to wire the deploy script into the deploying organization's own scheduler.
3. **Severity model for `DomainTypeMismatch`/`MatchSubDomainsChanged` correctly distinguishes a
   trust-boundary change from cosmetic drift, not a blanket severity.** Checked against the risk of a
   SOC team either over-alarming on every `DomainTypeMismatch` (most of which don't change the trust
   boundary - `Authoritative`↔`InternalRelay`) or under-reacting to the ones that do
   (`ExternalRelay` involvement, or a `MatchSubDomains` flip). Confirmed both the original draft and
   the finding-1 fix compute severity based on whether the in-organization boundary actually moves,
   not just whether a value changed - correct by inspection, no fix needed.

No remaining Fail. Detection, logging (findings JSON + drift-log CSV, both suitable for SIEM/ticketing
ingestion, README.md §7), and the incident-response runbook (§8) meet the bar for an operable control,
with the explicit caveat that domain-addition/removal attribution to a specific admin action is not
achievable from this script alone (design.md §5) - a genuine tooling gap, not a Blue Team process gap.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **The "no incremental licensing" framing needed a direct comparison, not just a citation.** The
   first draft's §10 stated no incremental Purview/Copilot licensing is required but didn't foreground
   how that compares to the cost of the control this scenario protects - an organization evaluating whether to
   fund this alongside `copilot-external-email-block`'s E5-class requirement benefits from seeing the
   asymmetry stated plainly.
   - **Resolution:** `README.md` §10 already drew this comparison in the first draft ("meaningfully
     cheaper to run than the FromScope-consuming scenarios it protects") - reviewed and confirmed
     sufficient; no further change needed.
- **Risk reduction vs. cost:** high - this is a low-cost (no incremental licensing, one cmdlet call
  per scheduled run), high-leverage control: it protects the correctness of every `FromScope`-based
  DLP rule the deploying organization has deployed or will deploy in this repo, not just one scenario. The
  cost-to-protection ratio is unusually favorable compared to most scenarios in this repo.
- **Board-level narrative:** "We continuously verify that the accepted-domains configuration our DLP
  controls depend on hasn't silently drifted, and we can show same-day detection of any unreviewed
  change" is a concrete, auditable claim - not a vague "we have monitoring" gesture.
- **Compliance mapping:** correctly scoped as a compensating/detective control for an underlying
  dependency, not framed as a new preventive capability it isn't - §2's driver framing avoids
  overclaiming real-time or preventive protection (Red Team finding 3's latency disclosure
  reinforces this honesty).
- **Would I fund this?** Yes, unconditionally - it requires no new licensing tier, meaningfully
  reduces a real and previously-undisclosed blind spot across this repo's entire `FromScope`-based
  DLP portfolio (not just one scenario), and the engineering cost is low. This is one of the
  higher risk-reduction-per-dollar scenarios in this repo specifically because it has no licensing
  gate.

No remaining Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **The `ExternalRelay`-is-on-premises-only finding needed to be flagged for backport, not left
   inconsistent with the originating scenario.** This build's grounding pass (design.md §2) found that
   `copilot-external-email-block/design.md` §4 states the general `UserScopeFrom`/accepted-domains
   mechanism without noting that `ExternalRelay` - the specific `DomainType` that mechanism's own
   cited definition of "external" depends on - is unreachable on the pure-cloud tenant that scenario
   targets. Left uncorrected, a reader could reasonably conclude from that scenario alone that
   `ExternalRelay` is a live concern for a standard Exchange Online deployment.
   - **Resolution:** `README.md` §11 states the finding and its practical implication for a
     cloud-only tenant; a `PROGRESS.md` follow-up tracks the actual backport into
     `copilot-external-email-block/design.md` §4 itself, rather than editing that scenario's files
     directly from this fragment, per `AGENTS.md` §6's one-fragment-per-turn discipline.
2. **Correctly scoped to a genuinely new, standalone control rather than duplicating or
   re-implementing part of `copilot-external-email-block`.** This scenario reads the same
   `Get-AcceptedDomain` surface that scenario's `FromScope` condition depends on, but creates no DLP
   object, doesn't touch that scenario's policy, and is independently useful to any `FromScope`-based
   rule in the tenant, not just Copilot's. Correct "protects a shared dependency" pattern, not a
   redundant fork.
3. **`Get-AcceptedDomain`/`Set-AcceptedDomain`/`New-AcceptedDomain`/`Remove-AcceptedDomain` cmdlet
   names, parameters, and on-premises-vs-cloud applicability statements are all independently
   confirmed by direct fetches of Microsoft's own reference pages this build, not inferred or
   carried over from another scenario** - the `ExternalRelay`-on-premises-only and
   `New-`/`Remove-AcceptedDomain`-on-premises-only findings in particular are new grounding this
   fragment contributes to the repo, not restated from an existing source.
4. **`Search-UnifiedAuditLog`/Entra directory-audit attribution is correctly disclosed as unconfirmed
   rather than asserted.** The `-IncludeAuditAttribution` switch and its `.NOTES`/`README.md` §11
   VERIFY correctly distinguish "the general default logging behavior for Exchange admin cmdlets" (a
   documented pattern this repo has already established elsewhere) from "confirmed specifically for
   `Set-AcceptedDomain`" (not independently confirmed) - matches this repo's evidentiary standard, no
   overclaim found.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 missing detection logic closed + a related elseif bug fixed, 1 config/baseline integrity risk disclosed, 1 detection-latency trade-off disclosed with a mitigation) | Closed |
| 🔵 Blue Team | Fix | 3 (1 validate-script asymmetry closed, 1 confirmed already correctly disclosed, 1 confirmed correct by inspection) | Closed |
| 🎩 CISO | Fix | 1 (confirmed already sufficient on review), remainder Pass | Closed |
| 🟦 Microsoft Product Owner | Fix | 4 (1 cross-scenario correction flagged for backport via PROGRESS.md, 1 confirmed-correct scoping, 1 confirmed new grounding contribution, 1 confirmed-correct evidentiary honesty) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/Export-AcceptedDomainsHygieneReport.ps1`, and
`validate/Test-AcceptedDomainsHygieneReport.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9. Two open items were originally carried forward honestly rather
than resolved by guessing, both disclosed in `README.md` §11 and `design.md` §5: `Set-AcceptedDomain`'s
exact audit-log `RecordType`/`Operations` shape was not independently confirmed by a Microsoft-published
worked example, and this scenario cannot attribute a domain-addition or -removal event to a specific
admin action (Exchange Online has no cmdlet for that action to audit in the first place). A
`PROGRESS.md` follow-up tracks backporting the `ExternalRelay`-on-premises-only correction into
`copilot-external-email-block/design.md` §4.

**Correction addendum - VERIFY closed 2026-09-28 (maintenance pass, Microsoft Learn MCP):** the first
of those two open items is now resolved. Finding 4 above (no overclaim found) still holds - re-checked
before closing, not merely carried forward. Microsoft's "Audit log activities" reference's "Exchange
admin activities" section states the default rule directly: every Exchange Online PowerShell change is
logged under `RecordType ExchangeAdmin` except cmdlets beginning with `Get-`/`Search-`/`Test-`, plus a
narrower, separately-named exception for internal Microsoft-datacenter/service-account maintenance
cmdlets. `Set-AcceptedDomain` is a customer-facing `Set-` cmdlet and falls under neither exception, so
it is covered by the default rule. This is the strongest evidence obtainable short of a pilot-tenant
test or a worked example naming this exact cmdlet, and is treated as sufficient to close the VERIFY.
`README.md` §11/§12 (new reference 6a) and `design.md` §5 updated from VERIFY to confirmed; the
`.NOTES`/inline `Write-Warning` in `deploy/Export-AcceptedDomainsHygieneReport.ps1` updated to match.
The second open item (domain add/remove attribution) is untouched by this pass and remains open. No new
four-lens review round required - doc-and-script correction only, no design surface or behavior change.
