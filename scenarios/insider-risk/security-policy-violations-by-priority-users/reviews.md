# Four-Lens Review — Insider Risk Management: Security Policy Violations by Priority Users

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A guest account or a service/non-interactive account with no populated Microsoft Graph `mail`
   attribute could be silently excluded from the priority population, exactly the kind of identity
   this template exists to watch more closely.** `Get-PriorityUserGroupScopeCandidates.ps1` flags
   such candidates with a `[WARN]`, but the original draft didn't state what an operator should do
   about that warning beyond "confirm in the portal" — leaving open the risk that a `[WARN]` gets
   treated as noise and the flagged users get quietly dropped from the CSV before upload, with
   nobody recording that a privileged service account or B2B guest with elevated access ended up
   outside the higher-scrutiny population entirely.
   - **Resolution:** Added an explicit bullet to `README.md` §11 naming this as a disclosed
     coverage gap when mail-enablement genuinely can't be satisfied, and pointing to the base
     template scenario (which has no mail-enablement constraint) as the compensating control for
     that specific population, rather than letting the gap pass silently.
2. **This control is completely blind to an offline or physical attack on the endpoint** — the same
   structural EDR-sourced-signal limit already documented for every sibling in this family.
   - **Not a new finding requiring further action** — the draft already states this plainly in
     `README.md` §11 as its own bullet. No change needed.
3. **A red-teamer aware of the undocumented dual-cap interaction (§3) could deliberately grow a
   priority user group past the 1,000-actively-scored template cap to push a specific target user
   out of active scoring, if Microsoft's actual (unconfirmed) behavior is "first N added win" or
   similar.** A real theoretical vector, but this scenario already treats the interaction as
   explicitly unverified rather than asserting a specific (and therefore game-able) selection
   rule, and recommends confirming live behavior in a pilot tenant precisely because an unconfirmed
   mechanism shouldn't be relied on for coverage guarantees either way.
   - **Reviewed, no structural change needed:** the honest "we don't know, verify before relying on
     full coverage" framing already in `README.md` §6/§11 and `design.md` §3 is the correct
     response to an unconfirmed mechanism — asserting a specific selection rule to "close" this
     finding would mean guessing at Microsoft's internal behavior, which this library's grounding
     standard (`AGENTS.md` §4) explicitly rules out. No change made.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass (with one Fix)**

1. **The "Users and groups" step's exact acceptance rule (priority group only, vs. priority group
   plus additional scope) affects whether an operator could accidentally believe a broader
   population is covered than actually is.** The original draft's README §5 Step 5 asserted, without
   a confirmed source, that this template "does not accept a plain Entra group or individual users
   the way the base template does" — an operability-relevant claim (it shapes how an operator plans
   scope) stated more confidently than this build's grounding actually supports.
   - **Resolution:** Softened `README.md` §5 Step 5 and the §6 configuration-reference table to
     state this as an open **VERIFY** rather than an asserted exclusivity rule — this build found
     Microsoft's own statement that a priority user group *must* be assigned to this template, but
     no worked example confirming whether that assignment is exclusive or additive.
2. **Reviewer-permission scoping is documented as a feature, but is there any way to confirm it's
   actually in effect (a detective control), versus just trusting it was configured correctly at
   setup time?** No Graph/PowerShell read API exists for priority user group configuration
   (`design.md` §2 goal 6) — the same disclosed gap this whole scenario already carries for every
   other portal-only setting.
   - **Reviewed, correctly scoped:** already captured in `validate/
     Test-PriorityUserGroupIrmSetup.ps1`'s manual checklist as an explicit item to confirm reviewer
     permissions are "deliberately scoped (not left at a broader default)" — the honest answer here
     is "no automated detective control exists," stated plainly rather than fabricated. No change
     needed.
3. **The dual-cap check in both the deploy script and the validate script uses `-Warn` (never
   contributes to a hard failure/non-zero exit) even for exceeding the 10,000-member group cap,
   which is plausibly a hard, portal-enforced limit rather than an advisory one like the
   1,000-actively-scored template cap.**
   - **Reviewed, no structural change needed:** consistent with the base template scenario's own
     precedent (`security-policy-violations/design.md` §6: "a hard block would imply a certainty
     this script doesn't have"), this scenario's scripts report and warn rather than assert a hard
     failure for a limit whose enforcement mechanism (client-side portal validation vs. silent
     truncation vs. something else) isn't independently confirmed either. Treating it as a hard
     `[FAIL]`-with-nonzero-exit would imply more certainty about Microsoft's actual enforcement
     behavior than this build has grounds for. No change made.

No remaining Fail. Detection, sizing, and the runbook meet the bar for an operable control once
the Fix above is applied.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate and clearly incremental over the base template — no
  new licensing tier, the added cost is the operational discipline of maintaining a priority user
  group and its reviewer-permission scoping. `README.md` §10 states this plainly.
- **Board-level narrative:** "we apply heightened scrutiny, and restrict who can see the results, for
  our most sensitive population" is a clear, differentiated narrative from both the base template
  ("bounded role-based coverage") and the departing-users template ("offboarding integrity") —
  `README.md` §1/§2 make the distinction explicit rather than presenting this as a redundant fourth
  copy of the same control.
- **Compliance mapping:** correctly scoped as endpoint-integrity monitoring evidence for a formally
  designated population, not tied to a named regulatory requirement — same honest framing precedent
  as every other Insider Risk Management scenario in this library.
- **Governance tradeoff, stated rather than hidden:** `README.md` §8's reviewer-permission-scoping
  guidance is explicit that the least-privilege benefit only materializes if an operator actually
  uses it — a CISO evaluating this template over the base one needs to know that benefit isn't
  automatic, which the current draft states directly rather than implying it by default.
- **Open questions are surfaced as open, not resolved by optimistic assumption** — the dual-cap
  interaction (§3/§6/§11) is exactly the kind of unresolved technical detail a CISO would want
  flagged before committing a genuinely sensitive population (e.g., the full executive team) to a
  template whose behavior at that population's likely size isn't confirmed.
- **Would I fund this?** Yes, for a tenant that already runs the base or departing-users sibling and
  has a genuinely higher-risk population (executives, privileged admins, investigation subjects)
  that warrants both stronger scoring and restricted reviewer access — with the explicit caveat
  that a population approaching 1,000 members should have the dual-cap interaction confirmed in a
  pilot before being treated as a production commitment.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (with one Fix)**

1. **The README §5 Step 5 exclusivity claim (flagged independently by Blue Team above) is a
   Product-Owner-relevant correctness issue in its own right** — stating a template's scope-input
   acceptance rule more confidently than Microsoft Learn actually confirms is exactly the class of
   error this lens exists to catch, regardless of which lens raises it first.
   - **Resolution:** Same fix as Blue Team finding 1 — resolved in `README.md` §5/§6 by both
     lenses' review passes converging on the identical change.
2. **Template name, prerequisite requirement (priority user group), and preview status are
   consistent with this build's grounding, though obtained via web search of the official Microsoft
   Learn URLs rather than a direct page fetch** (this environment's network access to
   learn.microsoft.com is proxy-blocked — disclosed in `README.md`'s closing note, not hidden). The
   10,000-member cap and the `user principal name` CSV column requirement are each corroborated by
   more than one independent description of the same Microsoft documentation, not a single
   unverified source.
3. **The 1,000-actively-scored cap and its cumulative sharing with the base template is reused from
   the base template scenario's own, separately-grounded citation** (`security-policy-violations/
   README.md` §12 reference 6, itself fetched during that scenario's build) rather than re-derived
   from a weaker secondary source — the strongest-available grounding path for a fact this
   scenario's core design decision (`design.md` §3) rests on.
4. **No fabricated priority-user-group authoring or CSV-upload API.** This build searched
   specifically for a documented Graph/PowerShell write surface for priority user groups and found
   none — `deploy/Get-PriorityUserGroupScopeCandidates.ps1` is explicit in its own `.DESCRIPTION`
   and `.NOTES` that it prepares input for a manual portal workflow, not that it performs that
   workflow, consistent with `docs/automation-surface.md` §6.
5. **`Get-MgGroupTransitiveMemberAsUser`'s cmdlet syntax, required `ConsistencyLevel: eventual`
   header, and permission set are reused unmodified from the base template scenario's own,
   independently-grounded usage** — not re-derived by potentially-drifting analogy, but the exact
   same confirmed pattern applied to a new context (candidate-list-for-CSV rather than
   candidate-list-for-direct-policy-scope).
6. **The scenario correctly distinguishes this template's priority-user-group population mechanism
   from the base template's plain-group mechanism throughout**, including the scoring-boost and
   reviewer-permission-scoping differentiators that are unique to the priority-group object — both
   `README.md` §1/§2/§6 and `design.md` §1/§2/§5 name these distinctions explicitly rather than
   treating this scenario as a smaller copy of the base template with a different template name.

No remaining Fix/Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a README §11 addition, 2 confirmed already correctly scoped/handled) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed with a README §5/§6 correction, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | — | — |
| 🟦 Microsoft Product Owner | Fix | 6 (1 closed — same underlying issue Blue Team raised independently — 5 confirmed correct/well-grounded) | Closed |

Two lenses (Blue Team and Microsoft Product Owner) independently converged on the same finding —
the README's overconfident claim about this template's exact scope-input acceptance rule — and it
was resolved with a single coherent change rather than two competing patches. The one genuinely new
Red Team finding (silent exclusion of no-`mail` candidates) was resolved with a disclosure, not a
fabricated workaround. No Fail items were raised. This fragment meets the definition of done in
`AGENTS.md` §9.
