# Four-Lens Review — Auto-Label Confidential PII in Exchange Email

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized (see "Resolution"
under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Scoping-off-`All` silently exempts inbound external mail.** An operator narrowing the policy to
   a pilot sender group (a natural instinct) would, per Microsoft's documented behavior, exempt all
   email from *outside* the org — precisely the highest-risk inbound direction — with no error.
   - **Resolution:** Kept `exchangeLocation = All` as the default with a `Write-Warning` in the
     deploy script when it isn't `All`, and documented the exact behavior in `README.md` §8/§11 and
     `design.md` §6. Narrowing is steered to rule conditions, not sender scoping.
2. **Manual / higher-priority label defeats the control.** Same class of bypass as the sibling: a
   message pre-labeled with something innocuous is never relabeled (absent the email-only override).
   - **Resolution:** Documented in `README.md` §11 as an unmitigated residual risk with the pointer
     to pairing content-based DLP (keyed off the SIT, not the label), matching
     `scenarios/dlp/pci-teams-exfil-block/`.
3. **Simulation blind spot mistaken for coverage.** Because Exchange simulation only sees mail that
   flows during the run, a reviewer could conclude "nothing matched, we're clean" when in fact no
   representative mail was sent.
   - **Resolution:** Called out explicitly in `README.md` §7/§11 and `design.md` §5 — send
     representative test mail during the simulation window; empty Items-to-review is usually "no mail
     flowed," not "no risk."

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **Config validation reads as match validation.** A green validation run proves shape, not that
   any mail is being labeled — especially acute for email, where a correct policy labels nothing
   until matching mail flows.
   - **Resolution:** Added the explicit caveat to the validate script `.DESCRIPTION` and to
     `README.md` §11, directing operators to the Items to review tab for real volume.
2. **Simulation fires activity alerts.** An operator wiring alerts off auto-labeling/SIT activity
   would get a mass-alert wave the moment simulation matches real mail.
   - **Resolution:** Documented in `README.md` §8 (scope or pause the alert policy during the
     simulation window) — grounded in Microsoft's simulation-behavior guidance.
3. **Encryption blast radius on inbound external mail.** If the label encrypts and external-mail
   encryption is enabled, inbound external mail can be encrypted to the tenant; without a Rights
   Management owner it can't be managed later.
   - **Resolution:** `externalMailRightsManagementOwner` is optional/off by default, the deploy
     script warns when it's set, and `README.md` §8/§11 explain the single-user RM-owner requirement.

No remaining Fail. Native observability (Items to review + Activity Explorer) is thinner than a DLP
policy's, which is stated honestly rather than hidden.

---

## 🎩 CISO

**Verdict: Pass**

- **Risk reduction vs. cost:** email is the dominant regulated-data egress path; labeling it in
  transit is high-value, low-incremental-cost infrastructure (no PAYG per §10) that email-encryption
  and DLP controls key off. Correctly scoped once the U.S.-centric SIT caveat is explicit.
- **Change-management impact:** "never override a manual label by default" preserves user trust in
  the labeling program, and simulation-first avoids surprising users with sudden mail encryption.
- **Board narrative:** "we systematically classify regulated data in email as it moves, so
  encryption and DLP have a reliable signal, and we extend the SIT set to our jurisdictions over
  time" is honest and defensible.
- **Compliance mapping:** ISO 27001 Annex A.5.12/A.8.2 as the primary satisfied driver as shipped,
  GDPR/CCPA as the reason the capability matters once extended — consistent with the sibling.
- **Would I fund this?** Yes — it and the SharePoint sibling together give end-to-end classification
  coverage across at-rest and in-transit data.

No Fix/Fail items from this lens.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **`-ExchangeLocation` vs. the sibling's location-exception model.** The draft initially reused the
   sibling's mental model of a location-URL exclusion. Verified against the
   `New-AutoSensitivityLabelPolicy` reference: there is **no** `-ExchangeLocationException` — Exchange
   scoping/exclusion is via `-ExchangeSenderMemberOf(Exception)` and rule conditions.
   - **Resolution:** Corrected the exclusion model throughout (`design.md` §6, `README.md` §11,
     config `_policyNote`); the deploy script exposes sender exceptions and
     `-ExceptIfRecipientDomainIs`, not a location exception.
2. **`-Workload` single-valued, Exchange is one workload.** Verified `Accepted values: Exchange,
   SharePoint, OneDriveForBusiness`, mandatory, one per rule — so the one-rule design is correct, not
   an oversight, and distinct from the sibling's two-rule split.
   - **Resolution:** Design and docs state one rule / one workload explicitly.
3. **Email-only override parameter not fully documented.** The wizard's "Emails only" override maps
   to `-ApplySensitivityLabelOverwriteWorkloads <Workload>`, but the reference does not enumerate its
   values or its interaction with the boolean `-OverwriteLabel`.
   - **Resolution:** Left as an explicit **VERIFY** in the script `.NOTES`, `README.md` §11, and the
     config note; the script sets `-OverwriteLabel` (confirmed) and passes the override switch only
     when explicitly provided, unmodified — no fabricated value, per `AGENTS.md` §4.
4. **In-transit vs. at-rest correctness.** Confirmed against the concept doc that Exchange
   auto-labeling evaluates mail sent/received (not stored mailbox items), is service-side (no app
   dependency), starts simulation immediately, and that no mail flow rule or DLP policy is required.
   - **Resolution:** Reflected accurately in `design.md` §5 and `README.md` §4/§11.
5. **Licensing** — checked against `docs/licensing-matrix.md`: E5-tier or the IP&G add-on, same row
   as the sibling. No deprecated cmdlets used (the `*-AutoSensitivityLabel*` family is current).

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (1 closed with a warning + docs, 2 documented as residual risk) | Closed |
| 🔵 Blue Team | Fix | 3 (1 caveat + doc edit, 2 documented operational guidance) | Closed |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 5 (2 corrected models, 1 VERIFY-flagged, 2 confirmed correct) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, the
deploy/validate scripts, and the config. No Fail items were raised. One genuine **VERIFY**
(email-only override parameter semantics) is carried forward — flagged inline rather than guessed,
per `AGENTS.md` §4. This fragment meets the definition of done in `AGENTS.md` §9.
