---
title: "Copilot External Email Block"
fullTitle: "DSPM for AI — Copilot External Email Block"
category: "DSPM for AI"
categorySlug: "dspm-for-ai"
slug: "copilot-external-email-block"
repoPath: "scenarios/dspm-for-ai/copilot-external-email-block"
parts: ["design","deploy","validate","rollback"]
related: ["dlp/accepted-domains-hygiene-check","dspm-for-ai/copilot-sensitive-data-exposure","dspm-for-ai/copilot-prompt-full-block"]
deployCount: 2
validateCount: 1
---
## 1. Scenario summary

Adds a fourth rule to the Microsoft 365 Copilot and Copilot Chat DLP policy: when an email a user
received was sent from a sender outside the organization's accepted domains, Copilot excludes that
email from grounding, summarization, and citation entirely. This closes out the fourth and final
documented Copilot-location action Microsoft currently publishes — **"Block external email from
being processed"** — completing the rule set this repo's `dspm-for-ai` scenarios build against the
shared policy first deployed by `copilot-sensitive-data-exposure/` and extended by
`copilot-prompt-full-block/`.

**Who it's for:** an organization already running the parent Copilot DLP policy that wants to reduce
the risk of Copilot reasoning over — and potentially acting on — untrusted instructions embedded in
external email, without giving up Copilot's ability to summarize a user's internal mail and other
permitted Microsoft 365 content.

## 2. Business/regulatory driver

This rule is a **prompt-injection and untrusted-data-influence control**, not a sensitive-data-
leakage control — a materially different driver from this policy's other three rules. Microsoft's
own worked use case for this action:

> *"Contoso wants employees to keep using Microsoft 365 Copilot for productivity, but is concerned
> that external email could carry untrusted instructions or prompt-injection content. They want
> Copilot to ground responses only in trusted internal data."* [[1]](#references)

Regulatory/business drivers this scenario supports:
- **AI-application security hygiene** — as organizations increasingly treat Copilot as an agent that
  can read, summarize, and reason over a user's inbox, an attacker-controlled external email becomes
  a plausible injection vector for steering that reasoning. This control removes external email from
  the trusted-grounding set entirely, closing that vector at the data-source level rather than relying
  on prompt-level defenses.
- **A "trusted sources only" narrative for AI governance reviews** — pairs with this repo's other
  three Copilot-location rules to let a buyer state, with specifics, exactly which categories of
  content Copilot is barred from grounding on (sensitive-labeled content, SIT-laden prompts, and now
  untrusted external email) — see `design.md` §2 for why this driver is framed differently from the
  other three rules.
- **Graceful degradation, not user-facing friction** — unlike Rule 2 (`copilot-prompt-full-block`),
  which fully refuses a response, this rule only removes external email from the grounding set;
  Copilot still answers using internal email and other permitted sources, and the user's own access
  to the excluded email is unaffected [[1]](#references). This is the lightest-touch rule in the
  policy from a user-experience standpoint.

**Scope note carried from the parent scenario:** this rule protects Copilot's **grounding inputs**
only. It has no bearing on the unlabeled-oversharing problem that only the DSPM for AI data risk
assessment finds, and no bearing on sensitive data the user themselves types into a prompt (Rule 1/
Rule 2's problem) — see `copilot-sensitive-data-exposure/README.md` §2 and §11 for the full scope
discussion, which applies unchanged here.

## 3. Prerequisites

Full licensing detail and citations: `docs/licensing-matrix.md`. This scenario adds to, and assumes,
`copilot-sensitive-data-exposure`'s prerequisites (§3 of that scenario's `README.md`). Delta for this
scenario specifically:

| Requirement | Minimum | Notes |
|---|---|---|
| **`copilot-sensitive-data-exposure` already deployed** | The named policy from that scenario must already exist | This scenario adds a fourth rule to that policy by name (default `Copilot DLP - Sensitive Data Exposure Protection`); it does not create a new policy. |
| "Block external email from being processed" feature | **Preview** as of this writing | No fixed tenant-rollout date documented by Microsoft for this specific action — confirm it's selectable in the portal before relying on the script (see §5 step 1). |
| DLP to author the Copilot-location policy | Same Copilot-location-specific role list as the parent scenario (Purview Data Security AI Admin(s), Compliance Administrator, Microsoft Entra AI Admin, etc.) | See parent scenario's `README.md` §3 and `docs/rbac-model.md` §3 — unchanged by this addition. |
| Tenant accepted domains configured correctly | Every legitimate internal/partner sending domain must already be a correctly-configured accepted domain in Exchange Online | This rule's "external" determination is driven entirely by the tenant's Exchange accepted-domains list (`design.md` §4) — a misconfigured accepted domain (e.g. a legitimate subsidiary domain not yet added) would cause this rule to over-exclude that subsidiary's mail from Copilot grounding. Not a new prerequisite this scenario introduces, but one this scenario's correctness now directly depends on. Ongoing monitoring for this dependency: [`dlp/accepted-domains-hygiene-check`](/scenarios/dlp/accepted-domains-hygiene-check/). |

**Licensing note specific to this action.** Microsoft's Purview service description draws a tier
split between the two file/email-facing Copilot DLP capabilities and the prompt-facing one:
"Purview DLP to restrict Copilot from processing **files and emails**" is listed **No** for
Microsoft 365 Business Basic/Standard/Premium and the E3/A3/A1/G3/F3/F1 tiers, **Yes** only for
E5/A5-class tiers (Microsoft Purview Suite/EDU/FLW, Microsoft 365 E5/A5 Information Protection and
Governance) and Office 365 E5/A5; "Purview DLP to safeguard **prompts**" is listed **Yes*** for every
tier with Copilot access [[6]](#references). This rule's condition ("Email is received from") is a
files-and-emails-category capability by Microsoft's own grouping, not a prompt-safeguarding one — so,
unlike Rule 1/Rule 2's broader Copilot-DLP-for-prompts entitlement, this rule specifically requires
the higher E5-class tier the "files and emails" row names. This split is now also reflected in
`docs/licensing-matrix.md` §2 (DSPM for AI rows) — re-verify both against current Microsoft Learn
before a sales commitment.

> Verify current entitlement names and the preview/GA status of this specific action against
> `docs/licensing-matrix.md` and current Microsoft Learn before a sales commitment — this is the
> newest of the four Copilot-location DLP actions this repo documents.

## 4. Architecture

```mermaid
flowchart TD
    E[Email received by a user] --> S{Sender domain in tenant's<br/>Exchange accepted domains?<br/>&#40;FromScope&#41;}
    S -- "No — external" --> B["Rule 3: Copilot-Exclude-ExternalEmail-Processing<br/>Prevent Copilot from processing content<br/>Email excluded from grounding, summarization, citation"]
    S -- "Yes — internal" --> N[Email remains eligible for<br/>Copilot grounding, subject to Rule 0&ndash;2]
    U[User asks Copilot to summarize inbox<br/>or reason over recent email] --> Q{Does the referenced<br/>email pass Rule 3?}
    Q -- Excluded --> R1[Copilot responds using internal<br/>email + other permitted sources only.<br/>User sees: some content excluded<br/>by organizational policy]
    Q -- Not excluded --> R2[Email eligible as grounding input,<br/>subject to Rule 0&ndash;2's own checks]
    B -.alert.-> A[DLP Alerts dashboard /<br/>Microsoft Defender portal]
    B -.-.-> U2[User's own access to the<br/>excluded email is unaffected]
```

This scenario adds **one rule** (`Copilot-Exclude-ExternalEmail-Processing`, priority 3) to the
**same** DLP policy the parent scenario deploys and `copilot-prompt-full-block` already extended
(`Copilot DLP - Sensitive Data Exposure Protection`, scoped to the Microsoft 365 Copilot Applications
location, `EnforcementPlanes = CopilotExperiences`). It does not create a new policy or duplicate any
existing rule — see `design.md` §3 for why a shared policy remains the correct model even for a
structurally different condition type. Same up-to-four-hour propagation window as every rule in this
policy family [[1]](#references).

## 5. Step-by-step implementation

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. Confirm the "Block external email from being processed" action is selectable in your tenant's
   Purview portal — Microsoft documents no fixed rollout date for this preview feature; if the
   condition below isn't available, it hasn't arrived yet.
2. Sign in to the [Microsoft Purview portal](https://purview.microsoft.com) → **Data loss
   prevention** → **Policies** → open **Copilot DLP - Sensitive Data Exposure Protection** (the
   parent scenario's policy) → **Edit rules** → **Create rule**.
3. Name: `Copilot-Exclude-ExternalEmail-Processing`. Priority: after the existing three rules
   (portal typically appends new rules last; confirm and reorder if needed so Rules 0–2 still
   evaluate first).
4. Condition: **Email is received from** → **External users** [[1]](#references).
5. Action: **Prevent Copilot from processing content** [[1]](#references)[[2]](#references) — this
   action has no further sub-action to select, unlike Rule 1/Rule 2's SIT-conditioned rules.
6. Leave the policy's overall **Mode** as-is (this scenario does not change the parent policy's
   mode) — see §8 for the operational implication of adding a rule to an already-`Enable` policy.
7. **Save**.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (certificate app-only — see docs/automation-surface.md §3)
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization $TenantDomain

# 2. Dry run — reports the change, makes none
./deploy/Add-CopilotExternalEmailBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com' `
    -WhatIf

# 3. Add the rule (parent policy's own Mode governs enforcement — see §8)
./deploy/Add-CopilotExternalEmailBlockRule.ps1 `
    -AdminNotificationEmail 'soc@contoso.com'

# 4. Validate
./validate/Test-CopilotExternalEmailBlockRule.ps1
```

The deploy script uses `New-DlpComplianceRule` with `-FromScope NotInOrganization` as the condition
and `-RestrictAccess @(@{setting='ExcludeContentProcessing'; value='Block'})` as the action.

**VERIFY — read before relying on this script in production.** Microsoft's `New-DlpComplianceRule`
reference confirms `-FromScope` exists as a parameter (type
`Microsoft.Office.CompliancePolicy.PolicyEvaluation.FromScope`) and confirms its two allowed values
(`InOrganization`, `NotInOrganization`) via a separate reference page — but no Microsoft-published
worked example combines `-FromScope` with the Microsoft 365 Copilot and Copilot Chat location
(`CopilotExperiences` enforcement plane) specifically. This scenario's choice is a documented,
reasoned inference from independently-converging sources (see `design.md` §4), not a fabricated
parameter — the parameter itself, its type, and its two allowed literal values are all individually
confirmed to exist; what's unconfirmed is that this specific location honors it as a condition.
`-RestrictAccess`'s `ExcludeContentProcessing`/`Block` pair is, by contrast, the **one** combination
Microsoft's own `New-DlpCompliancePolicy` reference publishes a full worked example for on this
location (paired there with a label condition, `design.md` §5) — the strongest-grounded action this
repo has used for any Copilot-location rule. **Before enforcing in production:** create the rule once
through the portal (step 5 above), then run
`Get-DlpComplianceRule -Identity 'Copilot-Exclude-ExternalEmail-Processing' | Format-List FromScope, RestrictAccess`
and compare against this script's output — `validate/Test-CopilotExternalEmailBlockRule.ps1`
automates this comparison as a `[WARN]`-level (not `[FAIL]`-level) check for exactly this reason.

## 6. Configuration reference

| Setting | Rule 3: `Copilot-Exclude-ExternalEmail-Processing` |
|---|---|
| Priority | 3 (evaluated after Rules 0–2 from the parent and `copilot-prompt-full-block` scenarios) |
| Policy | `Copilot DLP - Sensitive Data Exposure Protection` (parent scenario's policy — parameterizable via `-PolicyName`) |
| Condition | `FromScope = NotInOrganization` — **VERIFY**, see §5 |
| Action | `RestrictAccess = @{setting='ExcludeContentProcessing'; value='Block'}` — same confirmed pair as Rule 0, see `design.md` §5 |
| What it stops | An externally-sent email from being used by Copilot for grounding, summarization, or citation — sender-domain metadata only, the email body is never inspected [[1]](#references) |
| What it does **not** stop | Sensitive content *within* an internal email (Rules 0–2's job, not this rule's); a prompt-injection payload delivered through an internal-domain account that has been compromised (this rule only evaluates sender domain, not sender trustworthiness within the domain); external content reaching Copilot through a channel other than email (e.g. an external SharePoint guest share, or a Rule-1-uncovered web search) — see `design.md` §7 |
| `GenerateAlert` / `GenerateIncidentReport` | Admin/SOC mailbox |
| `ReportSeverityLevel` | `Low` by default (configurable via `-ReportSeverityLevel`) — see `design.md` §6 for why this rule's default severity is deliberately lower than its three siblings |
| `Disabled` | `$false` by default; the rollback script sets this to `$true` for a reversible pause (see `rollback.md`) |

Full cmdlet parameter grounding: `deploy/Add-CopilotExternalEmailBlockRule.ps1` inline comments and
its `.NOTES` block.

## 7. Validation / how to prove it works

1. **Automated config check** — `./validate/Test-CopilotExternalEmailBlockRule.ps1` confirms the rule
   exists with the expected priority, `FromScope` condition, and `RestrictAccess` setting; exits
   non-zero on any hard failure. The `FromScope` condition check is `[WARN]`, not `[FAIL]`, per the
   §5 VERIFY note — re-run it after creating the rule once through the portal to confirm the two
   match.
2. **Functional test** — from a test mailbox, send a test email from a genuinely external domain
   (e.g. a personal/test account you control, never a real third party's address) to a test user's
   internal mailbox. Ask Copilot to summarize that user's inbox or reason over the received message.
   Expect: the external email is excluded from the response, and the user sees a message indicating
   some content was excluded by an organizational policy [[1]](#references).
3. **Negative test** — send an equivalent test email from an internal-domain account. Expect: Copilot
   includes it normally when summarizing/reasoning over the inbox, confirming this rule hasn't
   inadvertently widened to exclude internal mail too.
4. **Evidence** — DLP Alerts dashboard or Microsoft Defender portal incidents queue, confirm the test
   event appears under rule name `Copilot-Exclude-ExternalEmail-Processing`.
5. **DSPM for AI Activity explorer** — Purview portal → DSPM for AI (classic) → Activity explorer →
   filter by **DLP rule match** to confirm ongoing match volume once live.

## 8. Operations & tuning

**Deployment sequence:** this rule inherits the parent **policy's** `Mode`, same as every rule in
this family — no independent simulation window of its own. If the parent policy is already in
`Enable` mode when this rule is added, it enforces as soon as it propagates (up to 4 hours).

**KPIs to watch (first 30 days):**
- **Rule 3 match volume, as a baseline, not an incident feed.** Because every external email a user
  receives is a potential match candidate, expect materially higher match volume than Rules 0–2 —
  this is expected behavior, not a sign of tuning trouble. Watch the *trend*, not the raw count.
- **Accepted-domains hygiene.** A legitimate partner or subsidiary domain missing from the tenant's
  Exchange accepted-domains list will show up here as unexpected external-email exclusions —
  cross-check any user complaint that "Copilot won't summarize an email from [legitimate partner]"
  against the accepted-domains list before assuming this rule is misbehaving.
- **Correlation with Rule 1/Rule 2 matches.** A pattern of prompts triggering Rule 1/Rule 2 shortly
  after a Rule 3 exclusion event on the same user's mailbox may indicate a user attempting to work
  around the external-email exclusion by re-typing or re-pasting the excluded content directly into a
  prompt — treat as a tuning signal, not automatically as malicious (most such attempts are
  legitimate users trying to get their work done, not evasion).

**Review cadence:** monthly during the first quarter after deployment (given the preview status and
the FromScope-on-Copilot-location VERIFY carried in §5), dropping to quarterly once the feature
reaches GA and the VERIFY is closed.

**Incident-response runbook (Rule 3 alert):**
1. **Triage** — this is, by design, a lower-severity signal than Rules 0–2 (see `design.md` §6).
   Most alerts require no action; use the alert primarily to confirm the control is active and
   matching, not as a per-event investigation queue.
2. **Escalate only on a pattern** — a specific external domain generating a sustained, unusual volume
   of matches against a specific user or small group of users may warrant a closer look (e.g., a
   phishing campaign using a spoofed-looking external domain attempting to reach users' inboxes with
   content crafted to look like legitimate business correspondence) — route to the mail-flow/anti-phish
   team, not this scenario's own operators, since this rule has no visibility into email content.
3. **Document** — retain alert records to support the "Copilot only grounds on trusted internal data"
   narrative for an AI-governance review.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure. Quick reference:
`./deploy/Remove-CopilotExternalEmailBlockRule.ps1` disables just this rule (`Set-DlpComplianceRule
-Disabled $true`, reversible, leaves Rules 0–2 and the parent policy untouched); add `-Purge` to
permanently delete this rule only (`Remove-DlpComplianceRule`), also leaving the rest of the parent
policy intact.

## 10. Cost & licensing notes

- **This rule sits in Microsoft's "files and emails" Copilot-DLP licensing tier, not the broader
  "prompts" tier** — see §3's licensing note. Unlike Rule 1/Rule 2 (available to any tenant with
  Copilot access, per Microsoft's own `*` footnote), this rule specifically requires an E5-class
  entitlement (or the standalone Microsoft Purview Suite equivalent) [[6]](#references). Confirm this
  before assuming this rule is a "free" addition once the parent policy already exists.
- **Confirm preview-to-GA licensing has not changed** before quoting — this is a newer, faster-moving
  capability than even `copilot-prompt-full-block`'s own action; re-verify against
  `docs/licensing-matrix.md` and current Microsoft Learn before a sales commitment.

## 11. Known limitations & gotchas

- **The `-FromScope` condition is not independently confirmed for the Microsoft 365 Copilot
  location** — see the detailed VERIFY in §5. This is the single most important caveat in this
  scenario; confirm via `Get-DlpComplianceRule` against a portal-created rule before production
  reliance.
- **Preview feature, tenant rollout not guaranteed on any fixed date.** Confirm the condition is
  selectable in the portal for your tenant before assuming the script will succeed.
- **Metadata-only: this rule never inspects email body content.** A prompt-injection payload
  delivered from a domain that happens to be on the tenant's accepted-domains list (e.g. a
  compromised partner-organization mailbox, or an internal account) is not covered — this rule's
  entire detection surface is sender-domain comparison, nothing more [[1]](#references).
- **Accepted-domains misconfiguration is a real, silent failure mode.** See §3 and §8 — a legitimate
  sending domain not yet added to (or wrongly removed from) the tenant's Exchange accepted-domains
  list will be treated as external by this rule, with no error or warning surfaced anywhere in this
  scenario's own scripts (they don't independently re-derive or check the accepted-domains list). For
  ongoing, automated monitoring of exactly this dependency (in both directions — a domain silently
  excluded from trust, and a domain silently granted it), see `scenarios/dlp/
  accepted-domains-hygiene-check/`, built as this finding's compensating control.
- **No independent simulation mode for this one rule** — see §8. Adding it to an already-enforcing
  policy means it enforces on first propagation, with no per-rule staging option Microsoft documents.
- **Higher licensing tier than its Rule 1/Rule 2 siblings.** See §3/§10 — do not assume this rule is
  licensing-neutral just because the parent policy and its other rules already exist in the tenant.
- **Expected high match volume is not itself a signal of malicious activity or misconfiguration** —
  see §8's KPI guidance; a naive "alert count went up" read of this rule's dashboard will
  systematically over-alarm relative to its three siblings.
- **Does not, by itself, defend against prompt injection delivered through any channel other than
  email** — see `design.md` §7's explicit non-goal. A buyer asking "are we now protected from
  prompt injection in Copilot" should be told this closes exactly one documented vector, not the
  general problem.

## 12. References

1. Learn about using Microsoft Purview Data Loss Prevention to protect interactions with Microsoft
   365 Copilot and Copilot Chat — "Block external email from being processed (preview)" section
   (preview status, use-case example, metadata-only behavior, user-facing message) — <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#block-external-email-from-being-processed-preview>
2. Same page — Supported conditions and actions table (fourth Copilot-location row: **Email is
   received from > External users** condition, **Prevent Copilot from processing content** action,
   no sub-action) — <https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about#supported-conditions-and-actions>
3. New-DlpComplianceRule reference — full parameter syntax confirming `-FromScope` (type
   `Microsoft.Office.CompliancePolicy.PolicyEvaluation.FromScope`) and `-RestrictAccess` both exist
   as parameters of this cmdlet (does not publish a worked example for this specific
   condition/action/location combination — see `design.md` §4/§5 VERIFY) — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancerule>
4. Data loss prevention Exchange conditions and actions reference — confirms the portal condition
   "Sender scope" maps to the PowerShell condition `FromScope`/`ExceptIfFromScope`, property type
   `UserScopeFrom` — <https://learn.microsoft.com/purview/dlp-exchange-conditions-and-actions>
5. New-DlpCompliancePolicy reference, Example 4 (the `ExcludeContentProcessing`/`Block`
   `-RestrictAccess` pair, worked for a label condition on the Microsoft 365 Copilot location, reused
   by the parent scenario's Rule 0 and by this rule's action) — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-dlpcompliancepolicy>
6. Microsoft Purview service description — Data Loss Prevention (DLP) for Microsoft Copilot licensing
   table (the "files and emails" vs. "prompts" tier split referenced in §3/§10) — <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description#microsoft-purview-data-loss-prevention-dlp-for-microsoft-copilot>
7. Set-DlpComplianceRule reference (`-Disabled` parameter, used by this scenario's rollback path) — <https://learn.microsoft.com/powershell/module/exchangepowershell/set-dlpcompliancerule>
8. Remove-DlpComplianceRule reference (rule-level deletion, used by this scenario's `-Purge` path) — <https://learn.microsoft.com/powershell/module/exchangepowershell/remove-dlpcompliancerule>
9. [`dspm-for-ai/copilot-sensitive-data-exposure`](/scenarios/dspm-for-ai/copilot-sensitive-data-exposure/) — the parent scenario this fragment
   extends; shared prerequisites, architecture, and policy object.
10. [`dspm-for-ai/copilot-prompt-full-block`](/scenarios/dspm-for-ai/copilot-prompt-full-block/) — the sibling scenario establishing the
    "extends the shared policy" pattern this fragment follows.

> Re-verify the preview/GA status of this specific action and the `-FromScope`-on-Copilot-location
> VERIFY in §5 against current Microsoft Learn before a customer-facing deployment — this is the
> newest and least-mature of the four Copilot-location DLP actions this repo documents, and the only
> one whose condition type has no Microsoft-published worked example on this location at all.
