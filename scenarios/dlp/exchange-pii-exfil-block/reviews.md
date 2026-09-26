# Four-Lens Review - Exchange PII Exfiltration Block

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Encrypt-mode exception group is a silent bypass, not a logged override.** In Block mode, the
   nominated exception group gets a block-with-justification override - every use is logged. In
   Encrypt mode, the same group is simply excluded from the encrypt rule
   (`ExceptIfFromMemberOf`), because `EncryptRMSTemplate` is non-halting and has no override
   concept to log against. A compromised or repurposed member of that group in a tenant running
   `-Action Encrypt` can send SSNs/card numbers externally in **cleartext**, with zero alert,
   incident report, or override record - a materially worse position than Block mode's own
   exception path, and the original draft didn't call out the asymmetry.
   - **Resolution:** Documented explicitly in `README.md` §11 and `design.md` §6 as an unmitigated
     residual risk for that specific combination, with a concrete mitigation suggestion (a
     separate low-severity audit rule scoped to the same group) for an organization that needs both
     Encrypt mode and a logged exception path. Not silently fixed by inventing an unconfirmed
     "override with justification for a non-halting action" mechanism Microsoft doesn't document.
2. **Encrypt-Only doesn't restrict what the recipient does after decrypting.** The default RMS
   template protects the message in transit and at rest, but a legitimate external recipient can
   decrypt and then forward the plaintext content with no further control - a red-teamer's
   obvious next move once they have a valid decrypt (e.g., a coerced or phished external partner
   contact). The original draft picked Encrypt-Only for a good reason (no unwanted forward/print
   restriction on legitimate use) but didn't flag the security trade-off that reasoning implies.
   - **Resolution:** Added to `design.md` §6 and `README.md` §11 as an explicit trade-off, with
     `-EncryptTemplateName 'Do Not Forward'` named as the alternative for an organization whose threat
     model treats the recipient as the risk, not just the transport path.
3. **Single-message evaluation boundary - no cross-message correlation.** Same class of gap as
   `pci-teams-exfil-block` (split PAN/SSN across two messages defeats every rule here too).
   - **Resolution:** Already carried forward into `README.md` §11 as an explicit, unmitigated
     residual risk with a pointer to `pci-teams-exfil-block-part2-obfuscation-mitigation`'s
     Adaptive Protection / IRM pattern as the only capability this library has that addresses it
     - correctly not claimed as covered here.
4. **`AccessScope: NotInOrganization` trusts the recipient's domain, not their identity.** A
   lookalike-domain phishing account or a compromised partner mailbox that happens to be in an
   allowed/guest tenant relationship isn't distinguished from a legitimate external recipient by
   this condition alone.
   - **Resolution:** Out of scope by design - domain-spoofing and partner-tenant trust are
     Exchange anti-phishing / cross-tenant-access-settings concerns, not a DLP gap this scenario's
     content-based rule can or should attempt to close. No change made; noted here for visibility
     rather than left silently unconsidered.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **An alert alone doesn't reveal which action mode (Block vs. Encrypt) was active at match
   time.** If a tenant switches `-Action` over time (§6 of `README.md`, "Switching -Action"), an
   analyst reviewing a `PII-Exchange-Protect-External` incident report months later has no
   built-in way to tell from the alert whether the match was blocked or encrypted without
   separately checking the rule's current configuration - and the *current* configuration might
   not even match what was active when the historical alert fired.
   - **Resolution:** Added as runbook step context in `README.md` §8 (analysts should check
     current policy config alongside historical alerts, not assume they match) - this is a
     genuine, disclosed observability gap in the native Purview surface, not something this
     scenario's own tooling can retroactively fix. No fabricated per-alert action-mode field was
     added.
2. **Bifurcation makes "one incident" ambiguous without training.** An analyst unfamiliar with
   Exchange bifurcation could misread a blocked-external-fork alert as meaning the whole message
   (including any internal recipients) was stopped, when in fact internal recipients received
   their copy normally.
   - **Resolution:** Added an explicit bifurcation functional test (§7, step 6) and a runbook step
     (§8, step 4) directing analysts to identify which fork an alert/incident report refers to
     before drawing conclusions.
3. **Signal-to-noise on the internal-audit rule.** Same accepted, documented trade-off already
   established for `pci-teams-exfil-block`'s own internal-audit rule (help-desk staff quoting
   partial numbers, etc.).
   - **Resolution:** Not changed - `README.md` §8's KPI section already directs tuning from
     observed volume rather than a fixed threshold, consistent with the sibling scenario's
     precedent. Flagged here for visibility, not as an unresolved Fix.

No remaining Fail. Detection, logging, and the runbook (with the two additions above) meet the bar
for an operable control.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** strong and, unlike most scenarios in this library, cheaper - base
  DLP for Exchange is E3, not E5, because this scenario deliberately avoids advanced
  classification/Teams conditions. `README.md` §10 makes this explicit rather than burying it.
- **Change-management impact:** the audit-first internal rule, staged simulation rollout, and
  logged override path (Block mode) all follow this library's established pattern for avoiding a
  DLP program getting cancelled by business pushback in month one.
- **Board-level narrative:** "we stop SSNs and card numbers leaving the company by email to
  outsiders - either by blocking the send or by encrypting it, our choice - and every documented
  exception is logged" is a clean, defensible narrative. The two Red Team residual risks (Encrypt-
  mode's silent group exception, Encrypt-Only's post-decrypt limitation) are now documented,
  named trade-offs rather than silent gaps, which is exactly what a board/audit committee needs.
- **Compliance mapping:** correctly scoped to GDPR Art. 32 / CCPA-CPRA / ISO 27001:2022 Annex
  A.5.12/A.8.2, consistent with every sibling scenario; doesn't overclaim coverage this control
  doesn't provide (no cross-message detection, no anti-phishing/domain-trust control - both
  explicitly out of scope per `design.md` §7 and the Red Team findings above).
- **Governance observation (not a Fix):** a policy offering two operating modes (Block/Encrypt)
  needs a single documented organizational decision about which mode is the approved default for
  which data class - this scenario supports either but doesn't make that decision for the deploying organization,
  correctly, since it's a business-risk-tolerance call outside a technical scenario's scope. Worth
  a one-line note in an organization's own security policy, not something this repo should default.
- **Would I fund this?** Yes - genuinely lower licensing cost than most of this library's DLP
  scenarios, clear regulatory hook, and an honest residual-risk section.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Why a custom policy instead of the built-in "U.S. Patriot Act" template**, which already
   combines Credit Card Number + SSN conditions, an external-recipient scope, and a
   block-with-override action - structurally very close to this scenario's own shape? The
   original draft built a parallel policy without addressing the overlap, which on first read
   looks like it might be reinventing a native starting point.
   - **Resolution:** Added `design.md` §3a, grounded directly against Microsoft's own "What the
     DLP policy templates include" reference, explaining the template's volume-banded (1-9/10-500)
     tuning philosophy doesn't match this library's `mincount = 1` standard, its lack of an
     Encrypt-mode action, its non-group-scoped generic override, and the regulatory-narrative risk
     of naming a GDPR/CCPA-driven control after the Patriot Act - the same class of justification
     `pci-teams-exfil-block/design.md` §3a already gives for not editing the tenant's default
     Teams policy. Also confirms the standalone "U.S. PII Data" template doesn't even cover Credit
     Card Number, so it alone wouldn't meet this scenario's stated goal regardless.
2. **`AccessScope` applicability to Exchange rules directly** - confirmed, not assumed: the
   official `New-DlpComplianceRule` parameter reference documents `AccessScope`/
   `ExceptIfAccessScope` as generic parameters (not workload-restricted), and the dedicated
   "Data loss prevention Exchange conditions and actions reference" page independently lists
   "Recipient scope/Content is shared with" → `AccessScope` as a supported Exchange **recipient**
   condition. No deprecated cmdlets used (`New-/Set-/Remove-DlpCompliancePolicy`/
   `DlpComplianceRule` are the current family, matching every DLP scenario in this library).
3. **`EncryptRMSTemplate` and `Get-RMSTemplate` are real, current parameters/cmdlets** - confirmed
   against their official reference pages - but neither publishes a canonical template-name string
   guaranteed identical across tenants for the auto-created Encrypt-Only template.
   - **Resolution:** Not treated as confirmed. The deploy script performs a runtime pre-flight
     check (`Get-RMSTemplate -ResultSize Unlimited`) rather than trusting the default name
     blindly, and `README.md` §11 carries an explicit VERIFY. Matches `AGENTS.md` §4's grounding
     standard - tag and defensively check, don't fabricate or silently assume.
4. **Sensitive info type choice** - reusing the same built-in SSN + Credit Card Number pair as
   every Exchange/SharePoint/OneDrive scenario in this library is the right call for consistency;
   both are Microsoft-maintained, checksum/pattern-validated SITs already appearing in this
   tenant's other Purview surfaces, so this scenario's alerts won't surprise an admin comparing
   against ones they already see.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (2 new gaps documented as residual risk, 1 already-known gap carried forward, 1 confirmed correctly out of scope) | Closed |
| 🔵 Blue Team | Fix | 3 (2 runbook/test gaps closed, 1 confirmed already correctly scoped) | Closed |
| 🎩 CISO | Pass | 0 (1 governance observation, not a Fix) | - |
| 🟦 Microsoft Product Owner | Fix | 4 (1 closed with a new design.md section, 1 closed with a defensive runtime check + VERIFY, 2 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-ExchangePiiDlpPolicy.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.
