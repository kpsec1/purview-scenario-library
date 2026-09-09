# Four-Lens Review — Insider Risk Management: Security Policy Violations (base template)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **A newly added member of the source scoping group may be invisible to this control until an
   operator manually re-applies scope — and the original draft's "quarterly review" cadence left
   too wide a window for the specific population this template targets.** Because Microsoft doesn't
   document whether an IRM policy's in-scope population tracks a directly-added group's live
   membership or only its membership at add-time (`README.md` §5 Step 4, §11), the safer assumption
   for a security control is the pessimistic one: a newly hired or newly promoted privileged user
   could go unmonitored for up to a full quarter under the original draft's guidance — exactly
   backwards for a population chosen *because* it's high-risk.
   - **Resolution:** Rewrote `README.md` §8's first bullet to make re-scoping **event-driven** —
     tied to the same process that adds someone to the source privileged group — with the quarterly
     review demoted to a backstop for missed drift, not the primary mechanism. `design.md` §6's new
     table row states the same disclosure explicitly rather than picking one behavior (dynamic vs.
     snapshot) to assume.
2. **This control is completely blind to an offline or physical attack on the endpoint** — the same
   structural EDR-sourced-signal limit already documented for the departing-users sibling.
   - **Not a new finding requiring further action** — the original draft already states this
     plainly in `README.md` §11 as a bullet, not just implicitly through the architecture diagram.
     No change needed.
3. **An attacker aware this template is capped at 1,000 users could, in principle, try to flood the
   template-wide cap with noise (e.g., triggering low-severity alerts across many other in-scope
   users) to degrade detection reliability for an actual target.** A real threat class, but a
   speculative and low-likelihood one given how narrow this scenario's recommended population
   already is (§1: "not a monitor-everyone control") — flooding a deliberately small, curated
   population with enough noise to matter would itself be conspicuous.
   - **Reviewed, no structural change needed:** already implicitly mitigated by this scenario's own
     core design choice (a small, bounded, role-based population rather than a broad one) — adding
     a dedicated countermeasure would be speculative scope creep per `AGENTS.md`'s
     no-unneeded-abstraction guidance. Noted here for the record, not added to `README.md` §11 as a
     numbered gotcha since it's not a gap this scenario's design leaves open by omission.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Same underlying issue as Red Team finding 1, from the detection-operability angle: a
   calendar-only review cadence is a weak control for a population whose entire value proposition
   is "catch tampering by privileged users quickly."** The original draft's guidance would have let
   a real gap sit undetected for up to a quarter with no compensating alert.
   - **Resolution:** Same `README.md` §8 rewrite covers this — tying re-scoping to group-membership
     change events, not just a calendar, is a detection-operability improvement as much as a
     Red Team one already reflected as a Fix above.
2. **The reused export script still can't disambiguate which "Security policy violations…" template
   produced a given alert if this policy and the departing-users sibling both run.** Same disclosed
   gap the sibling scenario already carries.
   - **Reviewed, correctly scoped:** already stated in `README.md` §6 and §11 as an inherited,
     disclosed limitation rather than a gap unique to this build; not re-litigated as a new finding.
     No change needed.
3. **`validate/Test-SecurityPolicyViolationsIrmSetup.ps1` skips its one automated scope check
   entirely if `-GroupId` isn't supplied — does that silently make the script look "all green" when
   nothing was actually verified?**
   - **Reviewed, correctly handled:** the script prints an explicit `[SKIP]` line (not a `[PASS]`)
     when `-GroupId` is omitted, and the final summary line only ever claims automated checks
     "passed," never that every possible check ran — an operator reading the output can't mistake a
     skip for a pass. No change needed.

No remaining Fail. Detection, scoping, and the runbook meet the bar for an operable control.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** proportionate. This scenario adds no new licensing tier beyond what
  a Defender-for-Endpoint-and-IRM tenant already carries — the cost is operational (choosing and
  maintaining a bounded population), not a new spend line. `README.md` §10 states this plainly.
- **Board-level narrative:** correctly scoped as a narrower, complementary control — "we watch our
  highest-access users for security tampering even outside a departure event" — not oversold as
  broad tenant-wide coverage. `README.md` §1's opening callout ("this is not a monitor-everyone
  control") and §11's correction of the originating backlog item's framing both work directly
  against overselling this to a buyer, which is exactly what a CISO reading this for a funding
  decision needs to see stated up front, not discovered later.
- **Compliance mapping:** correctly scoped as endpoint-integrity monitoring evidence for a defined
  population, not tied to a named regulatory requirement — same honest framing precedent as every
  other Insider Risk Management scenario in this library (`README.md` §2).
- **Governance/accountability tradeoff, stated rather than hidden:** `README.md` §8's
  "Population-selection accountability" bullet names directly that this template lacks the
  priority-users sibling's formal, auditable priority-user-group object — a real governance
  weakness a CISO should know about before choosing this template over that one, not something this
  scenario's marketing-adjacent framing would benefit from omitting.
- **Would I fund this?** Yes, for a tenant that already runs Defender for Endpoint and wants
  continuous coverage of a specific, bounded privileged population that doesn't fit the
  departing-users or priority-users templates' own gating mechanisms — the incremental cost is
  operational discipline, not new spend, and the risk it closes (security-control tampering by an
  already-elevated-access user, outside any departure event) is real and complementary to, not
  redundant with, the sibling scenarios already in this library.

No Fix/Fail items from this lens — the one cadence issue that would have affected this lens's
recommendation was already caught and resolved under Red Team/Blue Team above.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Template name, prerequisite/triggering-event table, and preview status are all verified
   against current Microsoft Learn, not assumed or carried forward from the sibling scenario.** The
   policy-templates prerequisites table was fetched directly during this build and confirms the
   base template's triggering event *is* the Defender for Endpoint alert itself, with no HR
   connector or priority-user-group prerequisite — the exact basis for this scenario's core design
   decision (§2 goal 1).
2. **The 1,000-user limit — and its equality with the priority-users sibling's own cap despite
   requiring no priority-group object — is grounded directly against Microsoft's limits reference,
   not inferred.** This is the single most consequential fact this scenario's design rests on
   (`design.md` §3), and it was checked rather than assumed to differ proportionally from the
   sibling caps.
3. **No fabricated policy-authoring, group-scope-sync, or template-usage-count API.** This build
   searched for a documented way to (a) author IRM policy scope programmatically, (b) confirm
   whether policy scope tracks live group membership, and (c) query cumulative template-wide usage
   across policies, and found none for any of the three — all three are stated as portal-only or
   disclosed-unknown in `README.md` and `design.md` rather than guessed at, consistent with
   `docs/automation-surface.md` §6 and this library's grounding standard.
4. **`Get-MgGroupTransitiveMemberAsUser`'s cmdlet syntax, required `ConsistencyLevel: eventual`
   header, output type, and permission set were fetched directly from both the PowerShell cmdlet
   reference and the underlying Graph REST reference**, not assumed by analogy with the
   non-cast `Get-MgGroupTransitiveMember` cmdlet — confirming the OData-cast-specific consistency
   header requirement in particular, which is easy to miss by analogy alone.
5. **The scenario correctly avoids conflating this template's plain-group scoping with the
   priority-users sibling's formal "priority user group" object** — both `README.md` §2 and §8 name
   the distinction explicitly rather than blurring the two population mechanisms together.

No Fix/Fail items from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a README + design.md change, 2 confirmed already correctly scoped) | Closed |
| 🔵 Blue Team | Fix | 3 (1 closed by the same README change as the Red Team finding, 2 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | — (benefited from the Red/Blue Team fix; no separate finding of its own) | — |
| 🟦 Microsoft Product Owner | Pass | 5 (all confirmed correct/well-grounded, no changes required) | — |

The one substantive finding this round (the group-membership-change re-scoping gap) surfaced
independently from both the Red Team and Blue Team lenses and was resolved with a single coherent
change to `README.md` §8 and `design.md` §6, rather than two competing patches. No Fail items were
raised. This fragment meets the definition of done in `AGENTS.md` §9.
