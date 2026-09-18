---
part: "design"
parent: "dspm-for-ai/copilot-prompt-full-block"
---
## 1. Problem statement

[`dspm-for-ai/copilot-sensitive-data-exposure`](/scenarios/dspm-for-ai/copilot-sensitive-data-exposure/) deploys two of the three documented
Copilot-location DLP actions (label-based content exclusion, SIT-based web-grounding restriction).
Its own `design.md` §6 recorded the third — full prompt-response blocking on a SIT match — as
explicitly out of scope, because at that build time it was a preview feature with no published
Microsoft PowerShell worked example. `PROGRESS.md` carried this forward as a follow-up: "needs a
fresh grounding pass once Microsoft publishes an example or the feature reaches GA." This scenario
is that fresh grounding pass.

## 2. What changed since the original build

A dedicated Microsoft Learn re-check (this build) found:
- The "Block sensitive information types in prompts" section of the DLP-for-Copilot Learn page now
  documents this action with a full worked business use case (Contoso / Canada physical addresses /
  EU debit card numbers) and an explicit supported-conditions-and-actions table row, distinguishing
  it clearly from the web-grounding-restriction action for the first time in this repo's grounding
  history.
- The feature is still explicitly labeled **preview**, "rolling out to all tenants" — not GA, and not
  guaranteed present in every tenant on a fixed date.
- Microsoft's `New-DlpComplianceRule`/`New-DlpCompliancePolicy` reference still does **not** publish
  a worked PowerShell example combining a `ContentContainsSensitiveInformation` (CCSI) condition with
  the `RestrictAccess` action specifically for this behavior. Two adjacent, individually-confirmed
  data points exist instead (§5 below).

**Conclusion:** enough changed to justify building this as its own scenario (extending the parent
rather than leaving it as a portal-only callout), but not enough to fully close the original
PowerShell-grounding gap. This scenario is deliberately explicit about which half closed and which
half remains open — see §5 and `README.md` §5/§11.

## 3. Why a new rule on the existing policy, not a new policy

Microsoft's own DLP-for-Copilot documentation is explicit that **you cannot combine a sensitivity-
labels condition and a sensitive-information-types condition in the same rule, but you can create a
rule for each condition in the same policy** — this is exactly the model the parent scenario already
uses (Rule 0 = label condition, Rule 1 = CCSI condition, same policy). This scenario's new rule is a
second CCSI-conditioned rule in that same policy, distinguished from Rule 1 by its action
(`RestrictAccess` full block vs. `RestrictWebGrounding` partial restriction) and, by default, its SIT
set. A second policy would mean a second `-Locations`/`-EnforcementPlanes` object targeting the same
location, which Microsoft's own availability note discourages implicitly (a policy per location is
the natural unit) and which would complicate `Get-DlpCompliancePolicy` inventory/audit for no benefit.

## 4. SIT taxonomy: why this rule's default SITs differ from the parent scenario's Rule 1

Rule 1 (parent scenario) uses **U.S. Social Security Number (SSN)** and **Credit Card Number** —
this repo's established default sensitive-data taxonomy, reused across `auto-label-confidential-
sharepoint` and `endpoint-dlp-usb-block`. This scenario's Rule 2 defaults instead to Microsoft's own
worked-example pair, **Canada physical addresses** and **EU debit card numbers**, for two reasons:

1. **Grounding fidelity.** Using the exact SITs from Microsoft's own use-case example keeps this
   scenario's default configuration citable against a real Microsoft-published scenario, not an
   invented pairing.
2. **Avoiding an accidental severity inversion.** If Rule 2 (full block) and Rule 1 (web-grounding
   restriction only) shared the same SIT set, a buyer might reasonably ask "why does this prompt
   sometimes get fully blocked and sometimes just lose web grounding?" — the honest answer would be
   "it depends on which rule's `Priority` and internal evaluation order wins," which is a confusing
   operational story. Keeping the two rules' SIT sets distinct by default (documented, not enforced
   by the script) makes each rule's severity level unambiguous. A buyer who deliberately wants the
   same SIT to be fully blocked (superseding Rule 1) can pass the same SIT name to both rules'
   `-SensitiveInformationTypeName` parameters — DLP rules are independently evaluated and there is no
   documented conflict in doing so, since a full block simply makes a web-grounding restriction moot
   for that specific prompt — but this is a deliberate buyer choice, not this script's default.

## 5. The central open question: does `ExcludeContentProcessing`/`Block` apply to a CCSI-conditioned rule?

Two individually-confirmed data points, neither of which is the exact combination this scenario
needs:

| Confirmed example | Condition | Action |
|---|---|---|
| `New-DlpCompliancePolicy` reference, Example 4 | `AdvancedRule` (sensitivity label) | `RestrictAccess = @{setting='ExcludeContentProcessing'; value='Block'}` |
| Parent scenario's own grounding (Rule 1) | `ContentContainsSensitiveInformation` (CCSI) | `RestrictWebGrounding = $true` (a distinct, separately-named parameter) |

The action this scenario needs is a *third* combination Microsoft has not published a worked example
for: CCSI condition + `RestrictAccess`. The reasoning for still scripting it (rather than declining,
as the parent scenario did for this exact action) is:

1. **The portal's own supported-actions table lists "Processing prompts" and "Performing Web
   Searches" as two sibling sub-actions of the same parent action family
   ("Prevent Copilot from processing content" / "Restrict Copilot from processing content"), both
   triggered by the same CCSI condition type.** Since "Performing Web Searches" is confirmed to map
   to `-RestrictWebGrounding` (a dedicated boolean, not part of `-RestrictAccess`), the remaining
   sibling action is the more natural candidate for the `-RestrictAccess` mechanism — the same
   mechanism used for the *other* full-block action (label exclusion) in this same location.
2. **`-RestrictAccess`'s documented purpose across every Purview DLP location it appears in is "block
   access to the matched content."** A full prompt-response block is conceptually the same class of
   action as a full content-exclusion block; reusing the same setting/value pair for both is a
   parsimonious, plausible design on Microsoft's part, not an arbitrary guess.
3. **This is materially different from fabricating a cmdlet or parameter name.** The parameter
   (`-RestrictAccess`), its type (`Hashtable[]`), and the specific `setting`/`value` string pair
   (`ExcludeContentProcessing`/`Block`) are all independently confirmed to exist and to be valid for
   this exact DLP location. What's unconfirmed is only whether the *same* value pair is what the
   portal emits for a *different* condition-and-sub-action combination within that same location —
   a narrower, more defensible gap than an invented parameter would be.

This is still flagged as an explicit `VERIFY` everywhere it matters (`README.md` §5/§11, the deploy
script's `.NOTES`, and `validate/Test-CopilotPromptFullBlockRule.ps1`'s `[WARN]`-level check) rather
than presented as confirmed — per `AGENTS.md` §4, the responsible middle ground between fabricating
an unconfirmed detail outright and declining to build anything at all when partial, reasoned grounding
exists.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| New scenario vs. extending `copilot-sensitive-data-exposure` in place | New, separate scenario folder that adds a rule to the parent's existing policy | Keeps each scenario's own `reviews.md`/four-lens history scoped to what it actually changed; matches this repo's established "extends" pattern (e.g. `sensitivity-label-coverage-report` extending `classification-coverage-report`) rather than re-opening and re-reviewing the parent scenario's own files. |
| Deploy mechanism | `New-DlpComplianceRule -ContentContainsSensitiveInformation ... -RestrictAccess @(@{setting='ExcludeContentProcessing';value='Block'})` added to the existing policy by name | Best-grounded available mechanism per §5; explicitly flagged as unconfirmed rather than silently presented as certain. |
| Default SITs | Canada physical addresses, EU debit card numbers (Microsoft's own worked example) | See §4 — grounding fidelity and avoiding a severity-taxonomy collision with the parent scenario's Rule 1. |
| Priority | 2 (after the parent's Rule 0 = 0, Rule 1 = 1) | Keeps evaluation order stable and documented; does not reorder or renumber the parent's existing rules. |
| Rollback granularity | Disable/remove **this rule only** (`Set-DlpComplianceRule -Disabled`/`Remove-DlpComplianceRule`), never touching the parent policy or its other two rules | This scenario is additive to a policy it does not own outright; rollback must not have blast radius into Rule 0/Rule 1, which may be independently tuned by then. |
| Policy `Mode` | Not managed by this scenario at all | The parent policy's `Mode` already governs enforcement for all its rules; this scenario deliberately has no `-Mode` parameter, to avoid two scenarios both claiming ownership of the same policy-level setting — see `README.md` §8 for the operational implication (no independent simulation window for just this rule). |

## 7. Non-goals

- This scenario does not create the parent policy. If `Copilot DLP - Sensitive Data Exposure
  Protection` (or a custom `-PolicyName`) does not already exist, the deploy script fails fast with
  a message pointing at `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/deploy/New-
  CopilotSensitiveDataProtectionPolicy.ps1` rather than silently creating one.
- This scenario does not attempt the "Block external email from being processed" preview action
  (a fourth, distinct Copilot-location action with its own condition type, `Email is received from
  > External users`) — out of scope for this fragment. **Built** as
  [`dspm-for-ai/copilot-external-email-block`](/scenarios/dspm-for-ai/copilot-external-email-block/), which adds it as Rule 3 on this same shared
  policy.
- This scenario does not resolve the open `-RestrictAccess` VERIFY definitively — that requires
  either a pilot tenant (permanently out of reach for this repo's build process) or a future
  Microsoft-published worked example. It closes the "should we build this at all" question (yes, with
  the caveat clearly carried forward) but not the underlying grounding gap itself.
