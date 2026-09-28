---
part: "design"
parent: "communication-compliance/teams-viva-engage-content-safety"
---
## 1. Problem statement

*Workplace Harassment & Code of Conduct* already covers Threat, Discrimination, Harassment, and Profanity
across Exchange/Teams/Viva Engage using Microsoft's pattern-based trainable classifiers. It does not
- and structurally cannot, given the trainable-classifier catalog's fixed set - detect **sexual
content** in workplace messages, or **employee self-harm risk signals**, and it carries no
severity-ranked triage mechanism for any of its matches. Microsoft's **Detect inappropriate content**
template, built on a distinct detection technology (Azure AI Content Safety large-language-model
classifiers, preview) fills exactly that gap for two Microsoft 365 workloads (Teams, Viva Engage) via
four classifiers: Hate, Sexual, Violence, Self-harm. This scenario stands that template up correctly,
with a deliberate operational emphasis on the one classifier - Self-harm - that carries a
fundamentally different response obligation than a standard conduct-policy match.

## 2. Why this is a template deployment, not a custom policy

Same reasoning *Microsoft 365 Copilot Interaction Detection* (why this matters) already established for its own
template: the **Detect inappropriate content** template's fixed configuration -

> Location: Microsoft Teams, Viva Engage · Direction: Inbound, Outbound, Internal ·
> Review Percentage: 100% · Conditions: Hate, Violence, Sexual, Self-harm classifiers
>

- is already exactly this scenario's target. Using the template directly means Microsoft owns
keeping the classifier pairing current; a hand-built custom-policy equivalent would silently drift
from any future template update. operations and tuning documents the two supported deviations an organization may
legitimately want (adding Copilot as a location; applying the optional
`deploy/policy/short-form-crisis-threat-phrases.txt` custom keyword dictionary via **Customize
policy** for a confirmed short-message risk profile - see the configuration reference and operations and tuning) - both opt-in,
tenant-decided
extensions layered on top of the template, not a reason to abandon the template as this scenario's
deployment method.

## 3. The no-write-API constraint still applies

Identical grounding to both sibling scenarios: Communication Compliance has no documented
PowerShell, Graph, or REST write API for policy creation or management, template-based or custom. This scenario ships the same two-part
solution shape: a precise portal runbook plus one genuinely scriptable piece of
automation - an audit-trail export reusing the identical, already-grounded `Search-UnifiedAuditLog`
surface (the validation steps below).

## 4. Relationship to *Workplace Harassment & Code of Conduct*: complementary, not duplicate or competing

This is the first scenario in this library where two Communication Compliance policies would plausibly
run side by side against overlapping risk categories, so the overlap needs an explicit design
answer, not a silent one:

| Risk category | *Workplace Harassment & Code of Conduct* | This scenario | Relationship |
|---|---|---|---|
| Threats of violence | **Threat** trainable classifier (pattern/ML-based, multi-language, has a feedback loop, Exchange+Teams+Viva Engage) | **Violence** LLM classifier (preview, severity-ranked, Teams+Viva Engage only, no feedback loop yet) | Two independently-built detection mechanisms for an overlapping risk - a message matching both is expected, not a bug. Treated as **complementary defense in depth**, not redundant: the LLM classifier's severity ranking and different detection approach can catch what the pattern-based one misses, and vice versa. |
| Discriminatory/hateful language | **Discrimination**, **Harassment** trainable classifiers | **Hate** LLM classifier | Same complementary relationship - different technology, overlapping target, same reasoning as above. |
| Sexual content in text | Not covered (the trainable-classifier catalog has no general "sexual content in text" classifier - **Adult/Racy images** classifiers cover images only) | **Sexual** LLM classifier | **New coverage**, not an overlap. |
| Employee self-harm risk | Not covered - no trainable classifier addresses this at all | **Self-harm** LLM classifier | **New coverage** - the primary reason this scenario exists. |

Deliberately **not merged into one policy**: the two use different underlying detection
technologies with different maturity/feedback-loop/language-support/workload-coverage profiles, and Microsoft ships them as genuinely separate template families rather than one
combined condition set. Running them as two policies with a **shared reviewer pool** (section 5 below) gets
the coverage benefit without the maintenance cost of trying to hand-build a merged custom policy
that would need to track two independently-evolving classifier families.

## 5. Reviewer pool: deliberately the same HR/Legal team as *Workplace Harassment & Code of Conduct*

Unlike *Microsoft 365 Copilot Interaction Detection* (which chose a different reviewer pool - Security/
Responsible-AI/Legal - because its risk categories, jailbreak/IP exposure, are a different natural
fit), this scenario's four risk categories (workplace hate speech, sexual content, threats,
self-harm) are the same natural fit as *Workplace Harassment & Code of Conduct*'s HR/Legal pool. Reusing the
same reviewer team, rather than standing up a second one, means one trained group handles both
policies' overlapping risk surface coherently, and only one team needs the duty-of-care runbook
training rather than duplicating that training across two separate pools. Reviewers are assigned
to **Communication Compliance Investigators** (full content access), for the same reason
*Workplace Harassment & Code of Conduct* (the implementation steps) already establishes: a credible assessment of whether a
flagged message is a genuine risk needs the actual text, not just metadata.

## 6. The Self-harm duty-of-care runbook: a process control, not a product feature

This is this scenario's central design decision, and the reason it isn't simply "the harassment
scenario, but with different classifiers." Communication Compliance has **no documented capability
to route a Self-harm-classifier match to a different reviewer, on a different SLA, or through a
different workflow than a Hate/Sexual/Violence match** - every alert this policy generates lands in
the same Investigator queue, differentiated only by the shared Severity column. Two design choices follow from that gap:

1. **The escalation split is documented entirely as a runbook**, not built as a
   technical control, because no technical control for it exists. This is stated plainly rather than
   implied - a reviewer team that hasn't internalized the runbook will not be technically prevented
   from mishandling a Self-harm alert (the known limitations, the Red Team review finding).
2. **Staffing the escalation path is a go-live gate, not a post-launch tuning item.** the implementation steps
   step 10 and operations and tuning both frame this as a precondition, mirroring the same "deployed-but-unmonitored
   control is worse than no control" reasoning *Microsoft 365 Copilot Interaction Detection* (via its
   CISO-lens finding) already established for its own triage-SLA requirement - except here the
   consequence of getting it wrong is a missed welfare-risk signal, not a missed security event.

## 7. The audit-trail script: same surface, two new derived columns

`Export-ContentSafetyAuditTrail.ps1` queries the identical three `Search-UnifiedAuditLog` categories
both sibling scripts already grounded (`SupervisionRuleMatch`; `RecordType Discovery` +
`SupervisionPolicyCreated`/`Updated`/`Deleted`; `RecordType AeD` + `SupervisoryReviewTag`) - reusing
the confirmed shape rather than inventing a new one, for the same reason
*Microsoft 365 Copilot Interaction Detection* (the validation steps) gives. What's new in this script:

- **`-PolicyNameFilter`**, defaulted to this scenario's own policy name - identical mechanism and
  rationale to *Microsoft 365 Copilot Interaction Detection*'s own parameter, so a tenant running this scenario
  alongside either sibling gets correctly-attributed, separate rolling CSVs.
- **`ContentSafetyContext`**, a best-effort derived column distinguishing which of the four
  classifiers (Hate / Sexual / Violence / Self-harm) a `PolicyMatch` row corresponds to, parsed the
  same never-blocking way *Microsoft 365 Copilot Interaction Detection*'s `CopilotContext` column is (the known limitations VERIFY - the exact `AuditData` shape for this classifier pairing is not independently
  confirmed).
- **`SeverityHint`**, a best-effort derived column carrying the raw severity value if present in the
  parsed `AuditData`, never blocking and never assumed present - genuinely new relative to both
  sibling scripts, because this is the first Communication Compliance scenario in this library whose
  classifier family populates a Severity column at all.
- **A loud, distinct `Write-Warning` specifically for any newly-merged row where `ContentSafetyContext`
  resolves to `SelfHarm`** - deliberately more prominent in the script's console output than the
  generic `PolicyUpdate` warning both sibling scripts already emit, because a Self-harm match is the
  one outcome this scenario's entire operational design is built around not missing. This is a
  secondary, delayed-by-schedule safety net (the script runs on whatever cadence it's scheduled at,
  not in real time) - it does not replace the immediate, in-portal duty-of-care escalation the configuration reference
  requires; it exists so a scheduled audit-trail run also surfaces the event for anyone reviewing its
  output after the fact.

Idempotency model: identical rolling-history pattern to both sibling scripts - merge and
de-duplicate by `(CreationDate, Operations, UserIds, hash(AuditData))`.

## 8. Non-goals

- **Adding this policy's classifiers to Exchange or Copilot as locations.** Exchange is not a
  supported location for this classifier family at all; Copilot is
  supported by the classifiers in general but not by this specific template's fixed location list
  - operations and tuning documents the supported edit for an organization that wants
  Copilot coverage as a forward reference, not deployed by this scenario's default.
- **Building a technical (in-product) routing mechanism for Self-harm matches.** No such capability
  exists to build against - this scenario's contribution is the documented runbook, not a
  fabricated API-driven routing feature.
- **Reproducing or replacing the organization's existing crisis hotline/EAP promotion program.**
  This scenario is a detection-and-escalation aid layered on top of whatever crisis-support
  infrastructure the organization already runs - not a substitute for it.
- **The Insider Risk Management generative-AI or Communication-Compliance-signal integrations.**
  Same documented-but-not-configured treatment both sibling scenarios already apply - tracked as a
  standalone follow-up in the project backlog, not part of this fragment.
- **SIEM/Sentinel wiring** - same native `OfficeActivity`/Sentinel path both siblings already
  document; this scenario's CSV is SIEM-ingestible by the same mechanism, not rebuilt here.
- **Merging this policy with *Workplace Harassment & Code of Conduct* into one custom policy.** See section 4 - a
  deliberate, reasoned choice to keep them separate.

## 9. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Policy creation method | Portal wizard, from the built-in **Detect inappropriate content** template | Template's fixed configuration already matches this scenario's target - why this matters. No write API exists either way - the prerequisites. |
| Classifiers | Hate, Violence, Sexual, Self-harm (the template's fixed set, unmodified) | Azure AI Content Safety LLM classifiers - the only Communication Compliance condition family with sexual-content-in-text and self-harm detection, and the only one with severity ranking - the short version. |
| Relationship to *Workplace Harassment & Code of Conduct* | Separate, complementary policy, deliberately not merged | Different, overlapping-but-not-identical detection technology and risk coverage - the architecture. |
| Reviewer pool | Same HR/Legal team as *Workplace Harassment & Code of Conduct* | One trained team, one duty-of-care runbook to maintain, rather than a duplicated pool - the implementation steps. |
| Self-harm handling | Documented runbook (immediate parallel escalation to a named EAP/HR contact), not a technical control | No product capability to route by classifier exists - the configuration reference. |
| Scriptable deliverable | Audit-trail export, same 3-query shape as both siblings, plus `ContentSafetyContext`/`SeverityHint` derived columns and a distinct Self-harm warning | Reused grounded surface; genuinely new columns for this classifier family's new signal (severity) - the validation steps. |
| Locations | Teams, Viva Engage only (template default) | No PAYG requirement found for this scope; Exchange unsupported by this classifier family; Copilot available only via a documented edit, not the template default - operations and tuning. |

## 10. Data flow / where each piece runs

See the architecture for the full Mermaid diagram (identical structure to both sibling scenarios,
with the added Self-harm-escalation branch this scenario's design centers on).

## References

See the references for the full, numbered source list this design references by bracketed number.
