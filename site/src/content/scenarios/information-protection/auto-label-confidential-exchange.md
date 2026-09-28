---
title: "Auto-Label Confidential PII in Exchange Email"
category: "Information Protection"
categorySlug: "information-protection"
theme: "stop-the-leak"
slug: "auto-label-confidential-exchange"
teaser: "Automatically applies an existing \"Confidential\" sensitivity label to Exchange Online email (subject, body, and Office/PDF attachments) that contains personal data (U.S. Social Security Numbers and credit card…"
readingMinutes: 11
whoFor: "The exact organization of *Auto-Label Confidential PII in SharePoint & OneDrive* - any enterprise that needs systematic, evidenced classification coverage for regulated personal data - extended to close the email channel that scenario explicitly leaves open. Deploy this **alongside**, not instead of, the SharePoint/OneDrive scenario; they share a label and a design philosophy but are otherwise independent policies with materially different evaluation models."
frameworks: ["GDPR","ISO 27001","CCPA"]
licensing: ["Microsoft 365 E5"]
deployCount: 2
validateCount: 1
hasDesign: true
hasRollback: true
hasRunbook: true
toc: [{"id":"the-short-version","text":"The short version"},{"id":"why-this-matters","text":"Why this matters"},{"id":"how-the-control-works","text":"How the control works"},{"id":"what-it-takes","text":"What it takes"},{"id":"proof-it-works","text":"Proof it works"},{"id":"where-it-stops","text":"Where it stops"}]
---
## The short version

Automatically applies an existing **"Confidential"** sensitivity label to Exchange Online email
(subject, body, and Office/PDF attachments) that contains personal data (U.S. Social Security
Numbers and credit card numbers, the same representative PII/financial sensitive information
types as the sibling scenario) as messages are sent and received - without waiting on end users to
label anything themselves. Deployed as a single Microsoft Purview auto-labeling policy with one
rule, staged simulation-first, with an optional sender-based exclusion for a nominated
legal/eDiscovery mailbox.

## Why this matters

Same drivers as the sibling scenario - **GDPR Article 32**, **CCPA/CPRA**, and **ISO/IEC
27001:2022 Annex A.5.12/A.8.2** - applied to a different, high-volume channel for the same
regulated data. Email is a common, often overlooked exfiltration and mishandling path for SSNs and
card numbers: a well-meaning employee forwarding an unredacted spreadsheet, a customer service
reply that pastes a card number back to a customer, or a departing employee mailing records to a
personal account are all covered by this scenario's classification pass even before any
DLP-style blocking control exists on the same content.

**Scope note:** the same U.S.-centric starter-set caveat from the sibling scenario applies
here - SSN and Credit Card Number are a representative starter set, not jurisdiction-complete
personal-data coverage. See that scenario's why this matters for the full discussion; it isn't
repeated here to avoid drift between two copies of the same caveat.

## How the control works

```mermaid
flowchart TD
    A[Email sent or received<br/>via Exchange Online] --> B{Sender on the<br/>exclusion list?}
    B -- Yes --> Z[Not evaluated by this policy]
    B -- No --> C{"Subject, body, or Office/PDF<br/>attachment contains SSN or<br/>Credit Card Number, count >= 1?"}
    C -- No --> Y[No action]
    C -- Yes --> D{Existing label state?}
    D -- Unlabeled --> E["Apply Confidential label<br/>to the EMAIL, not the attachment"]
    D -- Auto-applied, lower priority --> E
    D -- Manual, any priority --> F[Not overridden - left as-is]
    D -- Auto-applied or manual,<br/>higher priority --> F
    E --> G[Activity Explorer:<br/>Sensitivity label applied<br/>- 60-90 min delay]

    subgraph Rollout["Staged rollout (this scenario's default path)"]
        direction LR
        S1[Off] --> S2[Simulation mode -<br/>live traffic only] --> S3["Review Items to review<br/>7+ days, with test<br/>traffic during the window"] --> S4[Enable]
    end
```

One auto-labeling policy (`Confidentiality - Auto-Label PII in Exchange Email`) with one rule
(`-Workload Exchange` is single-valued and this scenario targets exactly one workload - no
multi-rule split needed, unlike the sibling scenario's SharePoint/OneDrive pair). Full rationale:
the design notes.

## What it takes

### Prerequisites

Full licensing detail and citations: [Licensing matrix](/docs/licensing-matrix/). Summary for this scenario
(deltas from the sibling scenario called out explicitly):

| Requirement | Minimum | Notes |
|---|---|---|
| Automatic / policy-based labeling | **Microsoft 365 E5 / A5 / G5**, **Microsoft Purview Suite** (ex-E5 Compliance), or the **Information Protection & Governance (IP&G)** add-on | Same tier as the sibling scenario - [Licensing matrix, section 2](/docs/licensing-matrix/#2-master-capability--license-matrix), Information Protection row |
| Role to author/edit the policy | **Information Protection Admin** role group | [RBAC model, section 3](/docs/rbac-model/#3-microsoft-entra-roles-that-map-into-purview). This role can create the policy and run it in simulation. |
| Role to turn the policy on after simulation | **Compliance Administrator** or **Compliance Data Administrator** | Distinct from the authoring role above - without one of these, the **Turn on policy** action is greyed out in the portal even after a successful simulation. Not previously called out in the sibling scenario's prerequisites; applies there too. |
| Automation identity | App registration with **Exchange.ManageAsApp**, granted the Information Protection Admin role group (plus Compliance Administrator/Compliance Data Administrator if the same identity also enforces) | Certificate-based app-only auth - [Automation surface, section 3](/docs/automation-surface/#3-authentication-patterns---interactive-vs-unattended) |
| Dependency (not deployed by this scenario) | A published sensitivity label named **Confidential** (parameterizable), with label scope including **Emails**, and **not** a parent label | **Different scope requirement than the sibling scenario**, which needs "Files & other data assets." If the label was published only for that scenario, confirm (or extend) its scope to include Emails before deploying this one - see the design notes |
| Tenant configuration: unified audit logging on | Audit log search enabled | Required for simulation results and for **Activity Explorer**, this scenario's primary validation surface |
| Tenant configuration: sensitivity labels enabled for SharePoint/OneDrive (`EnableAIPIntegration`) | **Not required for this scenario** | Genuine simplification versus the sibling scenario - that toggle is SharePoint/OneDrive-specific and has no Exchange equivalent |
| Region availability | Auto-labeling available in tenant's region | Same regional-availability caveat as the sibling scenario |
| Scoping nuance | At least one **non-EDM** sensitive information type per rule | Same rule as the sibling scenario |

> Verify current entitlement names against [Licensing matrix](/docs/licensing-matrix/) (dated 2026-09-02) and the
> Product Terms before a sales commitment - SKU names change.

### Cost and licensing

- **No PAYG component for M365 mail.** Exchange auto-labeling is covered by the same per-user
  E5-tier/IP&G entitlement as the sibling scenario - see [Licensing matrix, sections 1 and 2](/docs/licensing-matrix/#1-the-two-billing-models-read-this-first). No
  separate licensing line for this scenario if the sibling scenario is already deployed; both draw
  from the same entitlement.
- **No additional Azure subscription required.**
- **Sizing note:** unlike the sibling scenario's "All" SharePoint/OneDrive location scope, this
  policy's default `ExchangeLocation = All` similarly means every licensed mailbox is effectively
  in scope - no incremental licensing decision beyond what the sibling scenario already requires
  for the same user population.

## Proof it works

**Read this section before assuming a passing check proves the control works - Exchange's
observability surface is genuinely different from the sibling scenario's, not just smaller.**

1. **Automated config check** - `./validate/Test-ConfidentialAutoLabelExchangePolicy.ps1
   -LabelName 'Confidential'` confirms the policy and rule exist with the expected location, SIT
   conditions, and target label; exits non-zero on any hard failure. Like the sibling scenario,
   this proves the policy is *shaped* correctly, not that it is *labeling anything*.
2. **Simulation results** - Purview portal → Information Protection → Auto-labeling policies →
   select the policy → **Items to review** tab. Unlike the sibling scenario's "Labeled items" tab,
   this only shows messages sent/received **while the simulation was actively running**
   - re-running simulation with no test traffic shows nothing, which is expected
   behavior, not a failure.
3. **Functional test** - send a test email containing a documented test SSN or card-brand test
   number (never real PII) from an in-scope mailbox to another in-scope mailbox, while the policy is
   in simulation or enabled. Confirm the match appears on **Items to review** (simulation) or, once
   enforced, in **Activity Explorer** (step 4).
4. **Post-enforcement confirmation - Activity Explorer, not Labeled items.** After moving to
   `-Mode Enable`, Purview portal → **Data classification** → **Activity Explorer** → filter
   **Activity type = Sensitivity label applied**, narrow by label/date/location. Allow **60-90
   minutes** for the activity to appear. Activity Explorer confirms the
   resulting label and **How applied** (automatic vs. manual), but does **not** identify which
   specific auto-labeling policy or rule applied it - if more than one auto-labeling policy targets
   Exchange in the tenant, corroborate with the single-policy **Items to review** history instead of
   assuming Activity Explorer disambiguates for you.
5. **Exclusion test** - send a test message *from* the excluded mailbox. Confirm it is **not**
   labeled. Then send a test message *to* the excluded mailbox from an unrelated in-scope sender.
   Confirm it **is** labeled - the exclusion is sender-scoped, not mailbox-scoped, and this
   asymmetry is exactly what this test is meant to catch.
6. **Override-safety test** - same pattern as the sibling scenario: manually apply a different
   label to a test message before sending, then confirm the policy does not replace it.
7. **Enforcement confirmation** - after moving to `-Mode Enable`, re-run the automated config check
   and confirm it reports `Mode: Enable` rather than a `Test*` value.

## Where it stops

- **In-transit only - no backlog coverage.** This is the load-bearing limitation of the whole
  scenario. Mail delivered before this policy existed, or before it was turned
  on, is never retroactively labeled. There is no on-demand-classification equivalent for Exchange.
  If an organization needs historical-mail classification, that is a separate eDiscovery/Content
  Search-based project, not an extension of this scenario.
- **No "Labeled items" dashboard or policy-level Insights enforcement metrics for Exchange** - both
  report only SharePoint/OneDrive files. Use Activity Explorer instead,
  and budget for its 60-90 minute delay and its inability to name which specific policy/rule
  applied a given label.
- **Exchange match counts shown during simulation Insights are estimates from sampled data, not
  exact counts** - do not report a simulation match count to a compliance
  stakeholder as an exact figure.
- **Simulation only sees live traffic during the run window.** A common false alarm: re-running
  simulation after a rule edit and seeing zero matches, when the real cause is that no test traffic
  was sent during the window - see the runbook in operations and tuning.
- **The exclusion mechanism is sender-scoped, not mailbox-scoped, and asymmetric - and that
  asymmetry is also a standing exfiltration path, not just an under-protection gap.**
  `-ExchangeSenderException` protects a nominated mailbox's outbound mail only; mail *sent to* that
  mailbox by anyone else is still evaluated and can still be labeled/encrypted. Read the other
  direction (a Red Team finding from this scenario's four-lens review, the review notes): **any mail
  this excluded mailbox sends - including sensitive content - leaves completely unlabeled and
  unencrypted by this control, by design.** If the excluded mailbox is ever compromised, shared
  more broadly than intended, or simply used for something other than its original legal-hold
  purpose, it is a standing, control-free channel for the exact data this scenario exists to
  protect. Treat the exclusion list the same way the sibling scenario treats its excluded
  SharePoint site (the known limitations there): a monitored asset, reviewed periodically, not a "set once and
  forget" configuration value. A legal-hold custodian's *inbound* Confidential-labeled mail is
  separately not exempted by this configuration either - if that is also required, it needs its
  own explicit design decision (e.g., excluding the sender who routinely emails that custodian,
  which doesn't generalize) rather than being assumed covered by this parameter.
- **Encryption side effects are workload-specific and easy to under-scope - and the default is
  weaker for the more dangerous direction of travel.** If `Confidential` applies encryption:
  internal senders are always encrypted once labeled; external senders are **not** encrypted by
  default unless `-ExternalMailRightsManagementOwner` is configured. Read
  plainly: **out of the box, a message containing an SSN or card number sent to an external
  recipient is labeled Confidential but leaves the tenant in cleartext** - the exact direction of
  travel (data leaving the org) that matters most for breach-notification exposure under the
  GDPR/CCPA drivers in why this matters. This is a genuine Red Team/CISO finding from this scenario's four-lens
  review, not a minor configuration nuance: an organization whose primary concern is
  external data loss (not just internal classification hygiene) should configure
  `-ExternalMailRightsManagementOwner` deliberately, or pair this scenario with
  *Exchange PII Exfiltration Block (Block or Encrypt)* - a content-based Exchange DLP policy, built
  specifically to close this gap, that blocks or forces encryption on outbound SSN/Credit-Card-
  Number mail to external recipients regardless of whether this auto-labeling policy has run -
  the same "don't rely on the label alone for real-time protection" pattern already established for
  the sibling scenario (the known limitations there) and for *PCI Teams Card-Data Exfiltration Block*. Unencrypted
  Office (Word/PowerPoint/Excel) attachments on a matching, encryption-applying message are
  documented to be separately encrypted to match the email; whether a PDF attachment on the same
  message ends up protected as part of the overall encrypted message envelope, or left effectively
  in the clear alongside a protected email body, is not stated explicitly by Microsoft's
  documentation for this specific case - **VERIFY** (pilot tenant) before relying on this control
  for PDF-carried sensitive content specifically; treat PDF as unconfirmed rather than protected in
  the interim.
- **Label scope requirement differs from the sibling scenario.** This scenario needs the
  `Confidential` label's scope to include **Emails**; the sibling scenario needs "Files & other
  data assets." If both scenarios are deployed against the same label (the intended pattern), the
  label's scope must include both - confirm this explicitly rather than assuming one scenario's
  prerequisite check covers the other.
- **A rule-load failure has no item-level symptom.** Unlike a SharePoint/OneDrive labeling failure
  (which shows up per-file with a reason), a malformed Exchange auto-labeling rule can silently stop
  matching **all** Exchange traffic tenant-wide with nothing to review, because the rule never
  compiled in the first place - see the runbook in operations and tuning, step 5.
- **Config validation is not match validation** - same caveat as the sibling scenario.
  `validate/Test-ConfidentialAutoLabelExchangePolicy.ps1` confirms the policy and rule are shaped
  correctly; it cannot confirm any email has actually been labeled. Always cross-check Activity
  Explorer before treating a green validation run as end-to-end proof.
- **A manually applied label permanently defeats this control**, same bypass class already
  documented for the sibling scenario: a message pre-labeled by a human keeps that label
  indefinitely, regardless of content added afterward (impossible to edit content after send in
  practice, but a draft saved with a manual label and later completed with sensitive content is the
  realistic version of this gap for email). No auto-labeling-side mitigation exists; pair with a
  content-based Exchange DLP condition for movement-blocking use cases that must not depend on the
  label being correct.
- **Don't repurpose this policy for mass encrypted mailings.** Microsoft explicitly documents that
  auto-labeling policies aren't designed for bulk encrypted-distribution mailing and can cause
  delivery failures if used that way; Message Encryption's own "automatically
  send emails" label setting is the correct mechanism for that use case, not this scenario.