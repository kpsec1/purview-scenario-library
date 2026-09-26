# Four-Lens Review — Adaptive Protection: Devices Endpoint DLP Enforcement

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One
round of findings below; all **Fix** items were applied to the scenario before this file was
finalized (see "Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Two of Microsoft's six documented Quick Setup Devices actions are not scripted at all**
   ("Access by restricted apps," cloud/browser upload restriction) — a red-teamer who correctly
   infers they've been rate-limited on clipboard/USB/network-share/print would immediately pivot
   to an unmanaged app or a personal cloud-storage upload, both completely uninspected by this
   policy. The original draft's `.NOTES` explained *why* these two are missing (undocumented
   parameter shape) but didn't foreground it as an active bypass path a red-teamer would find in
   minutes.
   - **Resolution:** `README.md` §5 Step 6 and §11 rewritten to name this as a live bypass path,
     not a documentation footnote, with an explicit manual-portal completion step for an organization that
     wants parity with Quick Setup's full six-action rule.
2. **This scenario's rule has no file-type restriction, unlike Microsoft's own Quick Setup rule**
   — a byproduct of choosing the Advanced-classification-scanning prerequisite path over a File
   Type condition (`design.md` §6). This was initially treated as a pure content-scope decision
   in the draft; a Red Team read flags the flip side: **broader** file-type coverage is a
   *strength*, not a weakness, from a bypass-resistance standpoint (Quick Setup's own rule would
   let an Elevated user freely copy a `.txt` or `.log` file to USB, since it isn't one of the five
   listed types) — but this needed to be stated as a deliberate, understood tradeoff, not
   discovered by a customer reading the fine print later.
   - **Resolution:** Added an explicit row to `README.md` §6 and a `design.md` §6 decision row
     documenting the broader-file-type/narrower-activity tradeoff plainly, framed correctly (as a
     net security improvement in this dimension, at the cost of Quick Setup parity) rather than
     an unexplained divergence.
3. **A patient attacker could exploit the disclosed `NotifyUser`/Quick-Setup tension** (§11) to
   infer whether they're being silently monitored (audit) vs actively blocked, if the resulting
   toast behavior differs unexpectedly from Quick Setup's documented "Off" posture.
   - **Not a new finding requiring a code change** — this is exactly why the tension is flagged as
     a pilot-tenant VERIFY rather than assumed either way (`README.md` §11); no fabricated
     resolution would remove the underlying uncertainty, so disclosure is the correct mitigation
     here, consistent with `AGENTS.md` §4. No change beyond what already exists.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass (one clarification)**

1. **Alert volume from two independent policies (this scenario + the Exchange/Teams sibling)
   could double-count or confuse triage if not correlated.** The original draft's Operations
   section didn't explicitly tell an analyst to review both policies together.
   - **Resolution:** `README.md` §8 updated with an explicit instruction to track the split
     between the two policies together, framing a user blocked on one channel and active on the
     other as expected, working-as-intended behavior rather than a gap.
2. **The "most restrictive policy wins" interaction with `scenarios/dlp/endpoint-dlp-usb-block`
   is documented but not independently testable from this repo alone.** Confirmed as a correctly
   disclosed VERIFY (§11) rather than an omission — consistent with this library's standard for
   claims that require a pilot tenant to confirm. No change needed beyond what's already there.
3. **The validate script's manual checklist is long (9 items) relative to its automated checks
   (13 automated PASS/FAIL/WARN lines).** Checked against the Exchange/Teams sibling's own
   validate script (5 manual items) — the longer list here is proportionate, not bloat: this
   scenario genuinely has more portal-only and undocumented-shape prerequisites than its sibling
   (device onboarding and Advanced classification scanning are Devices-specific; the two
   unscripted Quick Setup actions have no Exchange/Teams equivalent). No change needed.

No Fail items. Detection, alerting, and the runbook meet the bar for an operable control, with the
one Operations-section clarification applied.

---

## 🎩 CISO

**Verdict: Pass (one Fix)**

1. **An organization evaluating this scenario against Microsoft's own marketing/documentation for
   "Adaptive Protection on Devices" could reasonably expect full Quick Setup parity** and be
   surprised, post-purchase, to learn two of six actions are missing. The original draft disclosed
   this accurately in `README.md` §11 but the framing ("VERIFY" language, deep in a limitations
   section) undersold how material the gap is for a security narrative built on "we replicate
   Microsoft's own reference architecture."
   - **Resolution:** `README.md` §1 (Scenario summary) and §5 Step 6 now state the 4-of-6-action
     scope plainly near the top of the document, not only in §11, so an organization's expectations are
     set correctly before they reach the fine print.
2. **Risk reduction vs. cost:** proportionate — for a tenant already running the Exchange/Teams
   sibling scenario, the incremental cost of this scenario is device-onboarding effort (already
   required for `endpoint-dlp-usb-block`, if also deployed, or a first-time cost otherwise) plus
   the operational discipline in §8, not new licensing (§10).
3. **Board-level narrative:** "we automatically tighten the same risk-based control across both
   the network and device exfiltration channels for the exact users our insider risk program has
   flagged" is a stronger, more complete narrative than the Exchange/Teams sibling alone — and,
   post-fix, one that's honestly scoped about the two actions it doesn't yet cover.
4. **Employment-relations/optics risk** — identical to the Exchange/Teams sibling scenario (an
   automated action driven by an ML risk score, not a human decision). No new consideration beyond
   what that scenario's `reviews.md` CISO lens already covers; cross-referenced in `README.md` §8
   rather than re-litigated here.
- **Would I fund this?** Yes, as a direct, low-incremental-cost follow-on for any organization that has
  already funded (or is funding via this library) the Exchange/Teams sibling scenario — not as a
  standalone first Purview investment.

---

## 🟦 Microsoft Product Owner

**Verdict: Pass (two Fix)**

1. **The four scripted `-EndpointDlpRestrictions` Setting names are independently confirmed
   current and correct** — checked against both `New-DlpComplianceRule` and
   `Set-DlpComplianceRule`'s Microsoft Learn parameter references, which list identical Setting
   names (`Print`, `CopyPaste`, `ScreenCapture`, `RemovableMedia`, `NetworkShare`,
   `UnallowedApps`) and an identical Value enum (`Audit`/`Block`/`Ignore`/`Warn`) on both pages.
2. **The claim that `UnallowedApps` and the cloud/browser restriction have no documented
   rule-level action shape is independently verified, not assumed.** Both official cmdlet
   reference pages were fetched and searched directly during this build; the only documented
   `UnallowedApps` example declares an app, not an action, and no alternate Setting name for the
   cloud/browser restriction appears in either page's examples or in `Set-PolicyConfig`'s
   `-EndpointDlpGlobalSettings` examples (a different, tenant-wide-list parameter, correctly
   distinguished in `design.md` §7 rather than conflated with the per-rule action gap).
3. **An earlier draft omitted the file-type-scope divergence from Quick Setup's own reference
   rule entirely** — the draft's config table stated the four scripted settings without noting
   that Quick Setup's version of this same rule additionally scopes to five specific file types
   via a File Type condition this scenario's rule doesn't carry.
   - **Resolution:** Added the file-type-scope row to `README.md` §6 and the corresponding
     `design.md` §6 decision row (§2 above, Red Team finding, applies here too — one shared fix
     satisfies both lenses' concerns).
4. **The Advanced-classification-vs-File-Type prerequisite choice is correctly grounded, not
   arbitrary.** Verified against `dlp-adaptive-protection-learn`'s own "Important" callout
   (verbatim: "you must either enable Advanced classification scanning and protection or ... select
   the File Type is condition") and against `-ContentFileTypeMatches`'s placeholder-text
   description on both cmdlet references — the scenario's choice of the Advanced-classification
   path is the only one of the two options with a documented PowerShell/portal path forward
   (portal toggle vs. an undocumented condition value).
   - **Resolution:** Added the Advanced-classification file-size/type-limit disclosure (64 MB
     text, 50 MB OCR images, Office/PDF-only full support) to `README.md` §11, so this grounded
     but non-obvious side effect of the chosen prerequisite path is visible to an evaluator, not
     just the prerequisite choice itself.
5. **Licensing citation accuracy** — checked against `docs/licensing-matrix.md` §2: the Adaptive
   Protection and Endpoint DLP rows match this scenario's §3/§10 claims exactly, with no new
   licensing claim introduced here that isn't already grounded there.
6. **The two-separate-policies design (this scenario + the sibling) matches Microsoft's own
   documented Quick Setup output exactly** (two distinct auto-created policies, not one combined
   policy) — confirmed directly against `dlp-adaptive-protection-learn`'s own policy-name table.

No remaining Fix/Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed with doc changes making disclosed gaps prominent rather than buried, 1 confirmed already correctly handled by disclosure) | Closed |
| 🔵 Blue Team | Pass (1 clarification) | 3 (1 closed with an Operations-section addition, 2 confirmed correct/proportionate) | Closed |
| 🎩 CISO | Pass (1 Fix) | 4 (1 closed by moving scope disclosure earlier in the document, 3 confirmed correct) | Closed |
| 🟦 Microsoft Product Owner | Pass (2 Fix) | 6 (2 closed with new disclosure rows, 4 confirmed correct/well-grounded) | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`, and
`deploy/New-AdaptiveProtectionDevicesDlpPolicy.ps1`. No Fail items were raised. This fragment
meets the definition of done in `AGENTS.md` §9.
