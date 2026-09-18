---
title: "Copilot Prompt Full-Response Block"
category: "DSPM for AI"
categorySlug: "dspm-for-ai"
slug: "copilot-prompt-full-block"
whoFor: "an organization that already deployed `copilot-sensitive-data-exposure` and has"
frameworks: []
licensing: []
deployCount: 2
validateCount: 1
hasDesign: true
hasRollback: true
toc: [{"id":"1-scenario-summary","text":"1. Scenario summary"},{"id":"2-businessregulatory-driver","text":"2. Business/regulatory driver"},{"id":"3-prerequisites","text":"3. Prerequisites"},{"id":"4-architecture","text":"4. Architecture"},{"id":"5-step-by-step-implementation","text":"5. Step-by-step implementation"},{"id":"6-configuration-reference","text":"6. Configuration reference"},{"id":"7-validation--how-to-prove-it-works","text":"7. Validation / how to prove it works"},{"id":"8-operations--tuning","text":"8. Operations & tuning"},{"id":"9-rollback--decommission","text":"9. Rollback / decommission"},{"id":"10-cost--licensing-notes","text":"10. Cost & licensing notes"},{"id":"11-known-limitations--gotchas","text":"11. Known limitations & gotchas"},{"id":"12-references","text":"12. References"}]
---
## 1. Scenario summary

Adds a third, stronger DLP rule to the Microsoft 365 Copilot and Copilot Chat DLP policy: when a
user's prompt itself contains a configured sensitive information type (SIT), Copilot **refuses to
respond at all**, not just to web-grounded searches, but to internal Microsoft 365 grounding too.
This extends `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/`, which already deploys a
policy with a label-exclusion rule and a web-grounding-restriction rule; this scenario adds the
missing third documented Copilot-location action, **"Prevent Copilot from processing content >
Processing prompts"**, which Microsoft's own use-case guidance frames as the control for the
highest-severity SIT categories an organization wants users simply unable to submit to Copilot at
all (not just prevented from triggering an external web search).

**Who it's for:** an organization that already deployed `copilot-sensitive-data-exposure` and has
determined, through its own risk assessment, that a specific set of SIT categories (e.g. national
ID numbers, bank account numbers, a jurisdiction-specific regulated identifier) are severe enough
that no Copilot response should be generated at all when a prompt contains them, not even one
grounded purely in internal, already-accessible Microsoft 365 content.

## 2. Business/regulatory driver

Microsoft's own worked example for this action targets exactly this kind of policy choice: *"Contoso
encourages their employees to use Microsoft 365 Copilot to enhance productivity, but they don't want
their users placing Canada physical addresses or EU debit card numbers into prompts."* The action is
explicit that this is a stronger control than restricting web search alone: **"Copilot doesn't
respond to the prompt. Prompt isn't used for internal or web searches"**, a full stop, not a
narrower web-grounding restriction.

Regulatory/business drivers this scenario supports:
- **A stronger technical backstop for a narrow, high-severity SIT set**, where
 `copilot-sensitive-data-exposure`'s Rule 1 (`RestrictWebGrounding`) is deliberately a light-touch
 control (block external web search only, let Copilot still answer from internal sources), this
 scenario is the deliberately blunt instrument for SIT categories a buyer has decided should never
 reach Copilot at all, regardless of grounding source.
- **Payment-card/regulated-identifier hygiene**, Microsoft's own example uses **EU debit card
 numbers**; a PCI-scoped or EU-regulated tenant can use this rule for card or national-identifier
 SITs it does not want summarized, referenced, or reasoned over by Copilot under any circumstance.
- **User-facing deterrence, not just detection**, unlike Rule 1 (silent web-grounding restriction,
 the user isn't necessarily told), this action returns a message to the user explaining the request
 was blocked by an organizational policy, which can support a "the control is
 visibly enforced" narrative for an audit or a regulator, at the cost of user friction (see §11,
 `reviews.md` Blue Team/CISO).

**Scope note carried from the parent scenario:** this rule protects **prompt text** only. It does
not replace `copilot-sensitive-data-exposure`'s Rule 0 (labeled file/email exclusion) and has no
bearing on the unlabeled-oversharing problem that only the DSPM for AI data risk assessment finds, 
see that scenario's `README.md` §2 and §11 for the full scope discussion, which applies unchanged
here.

## 3. Prerequisites

Full licensing detail and citations: [Licensing matrix](/docs/licensing-matrix/). This scenario adds to, and assumes,
`copilot-sensitive-data-exposure`'s prerequisites (§3 of that scenario's `README.md`). Delta for this
scenario specifically:

| Requirement | Minimum | Notes |
|---|---|---|
| **`copilot-sensitive-data-exposure` already deployed** | The named policy from that scenario must already exist | This scenario adds a rule to that policy by name (default `Copilot DLP - Sensitive Data Exposure Protection`); it does not create a new policy. Run that scenario's `deploy/New-CopilotSensitiveDataProtectionPolicy.ps1` first. |
| "Block sensitive information types in prompts" feature rollout | **Preview**, rolling out to all tenants with Microsoft 365 Copilot/Copilot Chat access as of this writing | Confirm the feature has reached your tenant before relying on this scenario, Microsoft's own guidance says to check rollout status, it is not universally available on a fixed date. Available in Microsoft 365 Copilot, Copilot Chat, and Copilot in Word/Excel/PowerPoint; during preview, the in-app messaging in Word/Excel/PowerPoint may not clearly say the block is policy-driven. |
| DLP to author the Copilot-location policy | Same Copilot-location-specific role list as the parent scenario (Purview Data Security AI Admin(s), Compliance Administrator, etc.) | See parent scenario's `README.md` §3 and [RBAC model §3](/docs/rbac-model/#3-microsoft-entra-roles-that-map-into-purview), unchanged by this addition. |
| Sensitive information types for this rule | At least one built-in or custom SIT, distinct from the parent scenario's Rule 1 SITs if you want the two rules' severity levels to stay meaningfully different (see `design.md` §4) | Defaults to Microsoft's own worked-example pair, **Canada physical addresses** and **EU debit card numbers**, parameterize to your own highest-severity SIT set before production use. |

> Verify current entitlement names and the preview/GA status of this specific action against
> [Licensing matrix](/docs/licensing-matrix/) and current Microsoft Learn before a sales commitment, this is a
> newer, faster-moving Copilot-related capability than the parent scenario's other two rules.

## 4. Architecture

```mermaid
flowchart TD
    U[User prompt to Copilot / Copilot Chat] --> F{Prompt text contains a<br/>configured high-severity SIT?<br/>e.g. Canada physical address,<br/>EU debit card number}
    F -- Yes --> B["Rule 2: Copilot-Block-SensitivePrompts-FullResponse<br/>Prevent Copilot from processing content &gt; Processing prompts<br/>Copilot does not respond at all &mdash; not used for internal OR web grounding"]
    F -- No --> W{Prompt text contains a Rule 1 SIT?<br/>e.g. SSN, credit card number<br/>(parent scenario)}
    W -- Yes --> G["Rule 1: Copilot-Restrict-WebGrounding-SensitivePrompts (parent scenario)<br/>Blocks external web search only<br/>Copilot may still answer from internal M365 sources"]
    W -- No --> N[Normal response,<br/>grounded in whatever the user already has access to]
    B -.alert.-> A[DLP Alerts dashboard /<br/>Microsoft Defender portal]
    G -.alert.-> A
    B -.user-facing message.-> U2[User sees: request blocked by organizational policy]
```

This scenario adds **one rule** (`Copilot-Block-SensitivePrompts-FullResponse`, priority 2) to the
**same** DLP policy the parent scenario deploys (`Copilot DLP - Sensitive Data Exposure Protection`,
scoped to the Microsoft 365 Copilot Applications location, `EnforcementPlanes = CopilotExperiences`).
It does not create a new policy or duplicate the parent's Rule 0/Rule 1, see `design.md` §3 for why
a shared policy (not a second policy) is the correct model. Same up-to-four-hour propagation window
as the parent scenario applies.

## 5. Step-by-step implementation

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the "Block sensitive information types in prompts" feature has rolled out to your tenant
 (Microsoft's own guidance: "check whether rollout has reached your tenant", no fixed portal flag
 is documented for this; if the third action below isn't selectable, it hasn't arrived yet)
.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
 prevention** → **Policies** → open **Copilot DLP - Sensitive Data Exposure Protection** (the
 parent scenario's policy) → **Edit rules** → **Create rule**.
3. Name: `Copilot-Block-SensitivePrompts-FullResponse`. Priority: after the existing two rules
 (portal typically appends new rules last; confirm and reorder if needed so Rule 0/Rule 1 still
 evaluate first).
4. Condition: **Content contains** → **Sensitive information types** → select your highest-severity
 SIT set (defaults to **Canada physical addresses**, **EU debit card numbers** in this scenario's
 script, Microsoft's own worked example pair; replace with your own).
5. Action: **Restrict Copilot from processing content** → **Processing prompts**.
 (Microsoft's own documentation uses both "Restrict Copilot from processing content" in its
 use-case narrative and "Prevent Copilot from processing content" in its supported-actions table
 for this same action, an inconsistency in Microsoft's own wording, not a typo
 in this scenario; both refer to the identical "Processing prompts" sub-action.)
6. Leave the policy's overall **Mode** as-is (this scenario does not change the parent policy's
 mode), a new rule added to a policy already in `Enable` mode enforces immediately once portal/
 PowerShell sync completes (up to 4 hours); add the rule while the **parent policy** is still in
 `TestWithNotifications` if you want to observe this new rule's own match volume in simulation
 first (see §8).
7. **Save**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only, see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run, reports the change, makes none
./deploy/Add-CopilotPromptFullBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Add the rule (parent policy's own Mode governs enforcement, see §8)
./deploy/Add-CopilotPromptFullBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. Validate
./validate/Test-CopilotPromptFullBlockRule.ps1
```

The deploy script uses `New-DlpComplianceRule` with a standard `-ContentContainsSensitiveInformation`
condition (the same, confirmed parameter the parent scenario's Rule 1 uses) and
`-RestrictAccess @(@{setting='ExcludeContentProcessing'; value='Block'})` as the action.

**VERIFY, read before relying on this script in production.** Microsoft's own `New-DlpComplianceRule`
/ `New-DlpCompliancePolicy` reference publishes a worked example combining the `ExcludeContentProcessing`/
`Block` `-RestrictAccess` pair with a sensitivity-**label** condition (`-AdvancedRule`, the parent
scenario's Rule 0) and a separate worked example combining a **CCSI** condition with
`-RestrictWebGrounding $true` (the parent scenario's Rule 1). As of this build, Microsoft has **not**
published a worked example combining a CCSI condition with the `-RestrictAccess`
`ExcludeContentProcessing`/`Block` pair specifically for the "Processing prompts" full-block action, 
the exact literal `setting` value for this third action is not independently confirmed. This script's
choice is a documented, reasoned inference (see `design.md` §5), not a fabricated parameter, the
`-RestrictAccess` parameter itself, its hashtable shape, and the `ExcludeContentProcessing`/`Block`
value pair are all individually confirmed in Microsoft's reference; what's unconfirmed is that the
same value pair is what the portal emits when this specific condition/action combination is chosen.
**Before enforcing in production:** create the rule once through the portal (step 5 above), then run
`Get-DlpComplianceRule -Identity 'Copilot-Block-SensitivePrompts-FullResponse' | Format-List RestrictAccess`
and compare against this script's output, `validate/Test-CopilotPromptFullBlockRule.ps1` automates
this comparison as a `[WARN]`-level (not `[FAIL]`-level) check for exactly this reason.

## 6. Configuration reference

| Setting | Rule 2: `Copilot-Block-SensitivePrompts-FullResponse` |
|---|---|
| Priority | 2 (evaluated after the parent scenario's Rule 0 = 0, Rule 1 = 1) |
| Policy | `Copilot DLP - Sensitive Data Exposure Protection` (parent scenario's policy, parameterizable via `-PolicyName`) |
| Condition | `ContentContainsSensitiveInformation` = configurable SIT list, default **Canada physical addresses**, **EU debit card numbers** (Microsoft's own worked-example pair) |
| Action | `RestrictAccess` = `@{setting='ExcludeContentProcessing'; value='Block'}`, **VERIFY**, see §5 |
| What it stops | Copilot from responding to the prompt at all, not used for internal or web grounding |
| What it does **not** stop | A user rephrasing the sensitive data so it no longer matches the configured SIT pattern (see `reviews.md` Red Team); a user uploading the data as a file attachment instead of typing it (DLP does not scan uploaded file content, same documented limitation as the parent scenario's Rule 1, `copilot-sensitive-data-exposure/README.md` §11) |
| `GenerateAlert` / `GenerateIncidentReport` | Admin/SOC mailbox |
| `ReportSeverityLevel` | High (a full-response block is the most severe of the three rules) |
| `Disabled` | `$false` by default; the rollback script sets this to `$true` for a reversible pause (see `rollback.md`) |

Full cmdlet parameter grounding: `deploy/Add-CopilotPromptFullBlockRule.ps1` inline comments and its
`.NOTES` block.

## 7. Validation / how to prove it works

1. **Automated config check**, `./validate/Test-CopilotPromptFullBlockRule.ps1` confirms the rule
 exists with the expected priority, SIT condition, and `RestrictAccess` setting; exits non-zero on
 any hard failure. The `RestrictAccess` setting/value check is `[WARN]`, not `[FAIL]`, per the §5
 VERIFY note, re-run it after creating the rule once through the portal to confirm the two match.
2. **Functional test**, from a test account, submit a Copilot prompt containing a documented test
 value for one of the configured SITs (e.g. a placeholder Canada physical address), phrased as a
 normal request (never a real person's data). Expect: Copilot does not respond, and the user sees a
 message indicating the request can't be completed because it contains information the organization
 has blocked Copilot from using, contrast with the parent scenario's Rule 1
 functional test, where the user still gets an answer (just not web-grounded).
3. **Negative test**, submit an equivalent prompt using a Rule 1 SIT (e.g. a test SSN) that is **not**
 in this rule's SIT list. Expect: Copilot still responds (using internal grounding only, per the
 parent scenario's Rule 1), confirming this rule's stronger action is scoped only to its own SIT set
 and hasn't inadvertently widened to cover Rule 1's SITs too.
4. **Evidence**, DLP Alerts dashboard or Microsoft Defender portal incidents queue, confirm the test
 event appears under rule name `Copilot-Block-SensitivePrompts-FullResponse`, distinguishable from
 Rule 1's alerts by name and by the higher `ReportSeverityLevel`.
5. **DSPM for AI Activity explorer**, Purview portal → DSPM for AI (classic) → Activity explorer →
 filter by **DLP rule match** to confirm ongoing match volume once live.

## 8. Operations & tuning

**Deployment sequence:** this rule inherits the parent **policy's** `Mode`, it has no independent
mode of its own. If the parent policy is already in `Enable` (full enforcement) when this rule is
added, the new rule enforces as soon as it propagates (up to 4 hours), there is no simulation-only
window for just this one rule. **Recommendation:** add this rule while the parent policy is still in
`TestWithNotifications`, observe its match volume for a tuning window, and only then move the whole
policy to `Enable`, or accept that adding this rule to an already-`Enable` policy means it starts
blocking without its own simulation period. Document which path was taken in the change record.

**KPIs to watch (first 30 days):**
- **Rule 2 match count and false-positive rate.** This is the most user-visible of the three rules in
 this policy (the user is told their request was blocked), a high false-positive rate translates
 directly into help-desk tickets and productivity complaints, not just a silent DLP log entry. Watch
 this more closely than the parent scenario's Rule 1.
- **Rule 2 vs. Rule 1 overlap.** If a prompt matches both rules' SIT sets, Rule 2's full block makes
 Rule 1's web-grounding restriction moot for that prompt, not a conflict, but confirm your SIT
 taxonomy is deliberate (see `design.md` §4) rather than accidentally duplicated across rules.
- **Help-desk ticket volume citing "Copilot won't respond."** A leading indicator that either the SIT
 set is too broad (over-blocking legitimate prompts, e.g. an address format that also matches
 ordinary business correspondence) or that user education about the new control hasn't kept pace
 with deployment.

**Review cadence:** monthly during the first quarter after deployment (given the preview status and
higher user-visible friction than the parent scenario's other two rules), dropping to quarterly once
the false-positive rate stabilizes and the feature reaches GA.

**Incident-response runbook (Rule 2 alert):**
1. **Triage**, open the alert; confirm which SIT matched and the submitting user.
2. **Classify**, a single match from a user who has not triggered this rule before is very likely
 legitimate (probing the boundary, or a one-off need to discuss the flagged data type) rather than
 malicious; a pattern of repeated matches from the same user, especially rephrased attempts shortly
 after a block (see `reviews.md` Red Team), is a stronger signal warranting Insider Risk Management
 or manager involvement.
3. **Document**, retain alert records as evidence of an actively enforced, user-facing control.
4. **Do not tune by widening exceptions without review**, because this rule fully blocks a response
 (not just a web search), an ad hoc exception added under user pressure has a materially larger
 blast radius than loosening the parent scenario's Rule 1. Route exception requests through the
 same change-control process used for the parent policy, not a one-off rule edit.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure. Quick reference:
`./deploy/Remove-CopilotPromptFullBlockRule.ps1` disables just this rule (`Set-DlpComplianceRule
-Disabled $true`, reversible, leaves Rule 0/Rule 1 and the parent policy untouched); add `-Purge` to
permanently delete this rule only (`Remove-DlpComplianceRule`), also leaving the rest of the parent
policy intact.

## 10. Cost & licensing notes

- **No incremental licensing cost beyond the parent scenario.** This rule is a third rule inside the
 same DLP policy and location the parent scenario already licenses for, see that scenario's
 `README.md` §10.
- **Confirm preview-to-GA licensing has not changed** before quoting, Microsoft's licensing
 reference for DLP-for-Copilot (parent scenario `README.md` §3, ref 4) does not yet break out this
 specific action separately from the other two; re-verify against [Licensing matrix](/docs/licensing-matrix/) before
 a sales commitment, since preview features occasionally ship with different entitlement rules than
 their GA successor.

## 11. Known limitations & gotchas

- **The exact `-RestrictAccess` setting/value pair for this action is not independently confirmed**
 by a Microsoft-published worked example, see the detailed VERIFY in §5. This is the single most
 important caveat in this scenario; confirm via `Get-DlpComplianceRule` against a portal-created
 rule before production reliance.
- **Preview feature, tenant rollout not guaranteed on any fixed date.** Confirm the action is
 selectable in the portal for your tenant before assuming the script will succeed, if the feature
 hasn't rolled out yet, the underlying service will likely reject the `ExcludeContentProcessing`
 setting for a CCSI-conditioned rule (or silently no-op it) rather than the script failing loudly;
 always run the portal check in §5 step 1 first.
- **Same SIT-evasion residual risk as every SIT-based DLP rule in this repo.** A user who paraphrases,
 splits across multiple turns, or uses non-standard formatting for the sensitive data can defeat
 pattern-based detection, see `reviews.md` Red Team and the parent scenario's equivalent, already-
 documented limitation.
- **Files uploaded directly into a prompt are not scanned.** Same Microsoft-documented limitation as
 the parent scenario's Rule 1, DLP inspects only the typed prompt text, not uploaded file content
.
- **No independent simulation mode for this one rule**, see §8. Adding it to an already-enforcing
 policy means it enforces on first propagation, with no per-rule staging option Microsoft documents.
- **User-facing friction is real and higher than the parent scenario's other two rules.** Because the
 user is told their request was blocked (rather than the block being silent, as Rule 1's web-grounding
 restriction can appear), poor SIT tuning here produces visible help-desk load, budget for a tuning
 window before wide rollout.
- **During preview, Word/Excel/PowerPoint messaging may not clearly attribute the block to policy**
, set user expectations accordingly if this rule is deployed before the feature
 reaches GA.
- **The user-visible block message is a probing oracle.** Unlike Rule 1 (a silent web-grounding
 restriction the user may not notice), this rule tells the user their request was blocked by an
 organizational policy. A user (or an insider deliberately testing boundaries) can use repeated,
 varied prompts against this visible signal to map out which specific SIT patterns and formats
 trigger a block, then craft a near-miss variant designed to evade detection, a faster feedback
 loop for evasion than the parent scenario's silent rules provide. There is no Microsoft-documented
 mitigation for this within the DLP-for-Copilot feature itself; treat repeated near-miss attempts
 from the same user as an Insider Risk Management signal (§8 runbook), not just a tuning input.
- **Over-blocking risks pushing users to ungoverned tools.** Because this rule fully refuses a
 response (rather than degrading gracefully like Rule 1), a poorly tuned SIT set that blocks
 legitimate everyday requests can push frustrated users toward unmanaged, personal generative-AI
 tools outside this organization's Purview/DLP visibility entirely, the opposite of this
 scenario's intent. Pair deployment with user communications explaining why the control exists and
 a clear internal exception-request path (§8), not just the technical rollout.

## 12. References

1. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
 365 Copilot and Copilot Chat, "Block sensitive information types in prompts" section (preview
 status, rollout note, use-case example, supported conditions/actions table, files-uploaded-in-
 prompts limitation), <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-sensitive-information-types-in-prompts>
2. Same page, Supported conditions and actions table (three distinct Copilot-location actions:
 label exclusion, prompt full-block, web-grounding restriction), <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#supported-conditions-and-actions>
3. New-DlpComplianceRule reference, `-RestrictAccess`, `-ContentContainsSensitiveInformation`
 parameters and syntax (confirms parameter existence and shape; does not publish a worked example
 for this specific condition/action combination, see §5 VERIFY), <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
4. New-DlpCompliancePolicy reference, Example 4 (the `ExcludeContentProcessing`/`Block`
 `-RestrictAccess` pair, worked for a label condition, reused by the parent scenario's Rule 0), <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
5. Set-DlpComplianceRule reference (`-Disabled` parameter, used by this scenario's rollback path), <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
6. Remove-DlpComplianceRule reference (rule-level deletion, used by this scenario's `-Purge` path), <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
7. `scenarios/dspm-for-ai/copilot-sensitive-data-exposure/`, the parent scenario this fragment
 extends; shared prerequisites, architecture, and policy object.

> Re-verify the preview/GA status of this specific action and the `-RestrictAccess` setting-value
> VERIFY in §5 against current Microsoft Learn before a customer-facing deployment, this is the
> newest and least-mature of the three Copilot-location DLP actions this repo documents.
