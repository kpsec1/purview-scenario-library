# Four-Lens Review — Exchange PII Exfiltration Block: Encrypt-Mode Audit Companion

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; the single **Fix** item was applied to the scenario before this file was
finalized (see "Resolution"). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Pass**

1. **This is detection, not prevention — by design, not by oversight.** A compromised or
   repurposed member of the exception group can still send matching PII externally in cleartext;
   this companion does not stop that. A red-teamer inside the exception group gains nothing new to
   defend against and loses nothing new to exploit — the traffic was always going to be delivered
   in Encrypt mode's exception path.
   - **Assessment:** Not a gap in this fragment specifically — it is the explicitly stated scope
     (`README.md` §1, §11; `design.md` §1, §5). The actual residual risk (cleartext delivery to
     that population) belongs to the parent scenario and is already documented there. Flagging here
     for completeness, not as a Fix: a reviewer reading only this fragment's docs should not come
     away thinking it closes the underlying exposure.
2. **No new bypass surface introduced.** The rule's conditions (`FromMemberOf`, `AccessScope
   NotInOrganization`, same SITs) are a strict subset of conditions already present on the parent's
   own rules — this fragment doesn't introduce a new exception, override, or exclusion an attacker
   could target. Confirmed by the Non-member control test (`README.md` §7 step 4): the rule cannot
   fire for anyone outside the nominated exception group.
3. **Membership timing (TOCTOU) is not this fragment's concern.** Whether Exchange evaluates
   `FromMemberOf` against live group membership at message-send time versus a cached snapshot is a
   platform behavior shared with every other `FromMemberOf` condition in this library's DLP
   scenarios (including the parent's own override rule) — not a new question this companion raises.
   No independent finding recorded here to avoid duplicating a residual question that belongs, if
   anywhere, to the parent scenario's own review.

No Fix/Fail from this lens. This fragment does exactly what it claims — makes an existing gap
visible — and claims nothing more.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Hardcoded `Low` severity risks under-triage for a high-risk population.** The initial draft
   hardcoded `ReportSeverityLevel = 'Low'` to match the internal-audit rule's convention. But the
   scenario this rule exists to cover is specifically "a member of a trusted exception group sends
   matching PII externally" — if that population ever includes privileged, high-risk, or frequently
   targeted mailboxes (e.g., an executive-assistant group with broad external correspondence), a
   compromised account in that group generates only a `Low`-severity alert, which is exactly the
   priority tier most likely to be batched, deprioritized, or missed in SOC triage. The original
   draft gave the operator no way to change this without hand-editing the script.
   - **Resolution:** Added a `-ReportSeverityLevel` parameter (`ValidateSet('Low','Medium','High')`,
     default `Low`) to `deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1`, threaded through to
     the rule's actual `ReportSeverityLevel` property, with a matching parameter on
     `validate/Test-ExchangePiiEncryptModeAuditCompanion.ps1` so validation checks the severity that
     was actually configured rather than assuming `Low`. Documented in `design.md` §4 and
     `README.md` §8/§11 as an explicit governance decision left to the operator, not defaulted away.
2. **Alert-name recognizability.** An analyst scanning the DLP Alerts dashboard needs to recognize
   `PII-Exchange-Audit-Encrypt-Exception` as "expected exception traffic, now visible" rather than
   a new incident class.
   - **Assessment:** Addressed by naming alone (distinct from every other rule name in the policy)
     plus the explicit runbook note in `README.md` §8. No further tooling change needed — this
     library does not build a custom SIEM/alert-triage layer (`docs/automation-surface.md` §4
     scopes that out for every scenario, not just this one).
3. **No policy tip / sender-facing notification.** Confirmed as a deliberate, not overlooked,
   choice — consistent with the parent's own `PII-Exchange-Audit-Internal` rule, which also omits
   `NotifyUser`. Notifying the sender of a match that changes nothing about their mail's delivery
   would be a confusing signal, not a useful one.
   - **Assessment:** No change — correct as designed (`design.md` §4).

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** this is the cheapest fragment in this library's DLP module — one
  additional rule on an already-licensed, already-deployed policy, no new tier, no new
  infrastructure. It closes a documented audit-trail gap, not a data-protection gap; the value is
  evidentiary and operational (SOC visibility, incident-response starting point), not preventive.
  `README.md` §1 and §11 state this distinction plainly rather than overselling it as a fix for the
  underlying exposure.
- **Board-level narrative:** "we already knew this specific population's Encrypt-mode traffic
  wasn't logged; now it is" is a clean, honest, low-cost remediation story for an audit finding —
  exactly the kind of finding-to-fix narrative a compliance program needs to show it closes gaps it
  discovers in its own controls, including gaps in its own DLP program.
- **Compliance mapping:** same GDPR/CCPA/ISO 27001:2022 scope as the parent scenario, correctly
  narrowed in `README.md` §2 to the specific audit-trail-completeness angle rather than restated
  wholesale.
- **Change-management impact:** minimal — this is a single non-blocking rule addition; it changes
  no user-facing behavior (mail delivery is identical before and after), so it carries none of the
  business-disruption risk a new blocking or encrypting rule would.
- **Governance decision surfaced, not defaulted:** the now-parameterized `-ReportSeverityLevel`
  (Blue Team finding, resolved above) is exactly the kind of business-risk-tolerance call a
  technical scenario should expose as a choice rather than make silently — consistent with this
  library's established pattern (e.g., the parent scenario's own Block-vs-Encrypt `-Action` choice).
- **Would I fund this?** Yes — near-zero cost, closes a self-identified gap, no operational
  disruption.

No Fix/Fail from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass**

1. **Correct, current cmdlets and parameters throughout** — `New-/Get-/Set-/Remove-
   DlpComplianceRule`, `FromMemberOf`, `AccessScope`, `BlockAccess`, `GenerateAlert`,
   `GenerateIncidentReport`, `ReportSeverityLevel`, `Priority` — every one already confirmed against
   the official `New-DlpComplianceRule` reference during the parent scenario's own build, and this
   fragment introduces no new parameter or cmdlet that wasn't already grounded there. No deprecated
   surface used.
2. **Rule-priority handling is grounded, not assumed.** This build independently fetched and cited
   Microsoft's own statement that Exchange-hosted-location rules are assigned priority by creation
   order by default, and that when a message matches multiple rules only the most restrictive is
   enforced while every match is still logged (`design.md` §4, References #1). The deploy script's
   explicit-priority-computation approach is a reasonable, disclosed design choice given that
   grounding — not a workaround for an unconfirmed behavior.
3. **Correctly declines to invent an Encrypt-mode override mechanism.** The original backlog item
   could have been read as "give Encrypt mode an override, like Block mode has" — this build
   correctly recognized (via the parent scenario's own `design.md` §6, and confirmed here against
   the `NotifyAllowOverride` reference, which is documented only in the context of a
   blocking/restricting action) that no such mechanism exists for a non-halting action, and did not
   fabricate one. `design.md` §5 states this as an explicit non-goal rather than silently omitting
   it.
4. **No reinvented native capability.** This is exactly the shape Microsoft's own DLP rule model
   supports for "log this population's activity without acting on it" — a rule with `BlockAccess
   $false` and alerting actions is a first-class, documented pattern, not a workaround.

No Fix/Fail from this lens.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Pass | 3 (all confirmed correctly scoped / not new gaps) | — |
| 🔵 Blue Team | Fix | 3 (1 closed by parameterizing severity, 2 confirmed already correctly designed) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Pass | 0 (4 confirmations) | — |

The one Fix item from this round (Blue Team finding 1 — hardcoded `Low` severity) is resolved in
the current state of `deploy/New-ExchangePiiEncryptModeAuditCompanion.ps1`,
`validate/Test-ExchangePiiEncryptModeAuditCompanion.ps1`, `README.md`, and `design.md`. No Fail
items were raised. This fragment meets the definition of done in `AGENTS.md` §9.
