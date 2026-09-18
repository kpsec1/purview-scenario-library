---
part: "design"
parent: "dspm-for-ai/copilot-external-email-block"
---
## 1. Problem statement

`scenarios/dspm-for-ai/copilot-sensitive-data-exposure/design.md` and
`scenarios/dspm-for-ai/copilot-prompt-full-block/design.md` §7 both explicitly deferred the
fourth documented Microsoft 365 Copilot and Copilot Chat DLP-location action, **"Block external
email from being processed"**, as out of scope, tracking it as a follow-up in `PROGRESS.md`. This
scenario is that follow-up: it adds a fourth rule to the same shared policy, closing out the full
set of documented Copilot-location conditions/actions this repo tracks.

## 2. What this control actually does (and why it's a different class of problem)

Every other rule in this policy family (Rule 0 label exclusion, Rule 1 web-grounding restriction,
Rule 2 prompt full-block) reacts to **content the user is actively submitting or that Copilot would
surface**, a prompt, a labeled file, a labeled email. This rule reacts to **where an email came
from**, not what it says. Per Microsoft's own documentation (fetched directly this build,
2026-09-10):

> "The policy evaluates email metadata only - specifically, the sender domain compared against your
> tenant's accepted domains. The body of the email isn't inspected." [[1]](#references)

The business problem this addresses is also different in kind from the other three rules:
**prompt-injection and untrusted-data-influence risk**, not sensitive-data leakage. Microsoft's own
worked use case for this action is explicit that the concern is an external email carrying
"untrusted instructions or prompt-injection content" that Copilot might reason over as if it were
trusted internal context [[1]](#references), a control against Copilot being manipulated by
attacker-controlled grounding data, not a control against Copilot leaking the organization's own
sensitive data outward. This scenario's README frames the driver accordingly (§2), distinct from the
SIT/label-driven framing of its three siblings.

## 3. Why a new rule on the existing policy, not a new policy

Same reasoning as `copilot-prompt-full-block/design.md` §3, which this scenario inherits unchanged:
the Microsoft 365 Copilot and Copilot Chat location is a single policy-location unit, and Microsoft's
own guidance describes only the "cannot combine content-contains-SIT and content-contains-label in
the same rule, but can in the same policy" restriction, which doesn't even apply here, since this
rule's condition (**Email is received from > External users**) is neither a CCSI nor an
AdvancedRule/label condition. There is no documented restriction against adding this fourth,
structurally distinct condition type as a fourth rule in the same policy, and doing so keeps this
repo's `Get-DlpCompliancePolicy`/`Get-DlpComplianceRule` inventory model consistent (one policy per
location, per `copilot-prompt-full-block/design.md` §3).

## 4. Grounding the condition: `-FromScope NotInOrganization`

Microsoft's dedicated Copilot-location page names the condition only at the portal level ("Email is
received from > External users") and does not publish a PowerShell parameter for it directly. This
scenario's grounding pass found no worked example combining any specific parameter with the
Microsoft 365 Copilot location for this condition. The evidence assembled instead, independently
confirmed this build via three separate Microsoft Learn sources:

| Source | What it confirms |
|---|---|
| `New-DlpComplianceRule` full parameter syntax (fetched directly) | `-FromScope <Microsoft.Office.CompliancePolicy.PolicyEvaluation.FromScope>` exists as a real, current parameter of the same cmdlet this repo already uses for every other rule in this policy (`-RestrictAccess`, `-RestrictWebGrounding`, `-ContentContainsSensitiveInformation`, `-AdvancedRule`), not a fabricated name. |
| "Data loss prevention Exchange conditions and actions reference" (fetched directly) | Portal condition **"Sender scope"** maps to PowerShell condition `FromScope` (exception `ExceptIfFromScope`), property type `UserScopeFrom`, described as "Messages sent by either internal or external senders." |
| "Supported Microsoft Exchange resources for Tenant Configuration Management" (Graph UTCM reference, fetched via search) | States the `FromScope` parameter's allowed values explicitly: **`InOrganization`, `NotInOrganization`**, resolving the exact literal string this scenario's script must pass. |

**Why `NotInOrganization` is the right value, not a guess:** the Exchange 2013 mail-flow-rule
predicate reference (a still-current description of the underlying `UserScopeFrom` property model,
independently cross-checked this build) defines "outside the organization" as: *"The sender's email
address isn't in an accepted domain, OR the sender's email address is in an accepted domain
configured as an external relay domain."* This is the **same accepted-domains mechanism** the
Copilot-location page itself describes ("the sender domain compared against your tenant's accepted
domains") [[1]](#references), the two independently-sourced descriptions of "external" converge on
the same underlying comparison, which is meaningfully stronger corroboration than this repo's typical
single-source VERIFY.

**Correction (backported from `scenarios/dlp/accepted-domains-hygiene-check/design.md` §2, built in a
later fragment):** the "configured as an external relay domain" clause above is **on-premises Exchange
only.** Microsoft's `Set-AcceptedDomain` reference states this explicitly, `ExternalRelay` is *"a type
of non-authoritative domain that's available only in on-premises Exchange organizations,"* and
`New-`/`Remove-AcceptedDomain` are both on-premises-Exchange-only cmdlets with no Exchange Online
equivalent. For the pure Exchange Online tenant this scenario targets (`docs/automation-surface.md`
§1), only the `Authoritative` and `InternalRelay` accepted-domain types are reachable, both of which
count as in-organization, so in practice this tenant class's `NotInOrganization` match is driven by
the "isn't in an accepted domain" clause alone; the external-relay clause is a real mechanism in
Exchange generally, but not one a pure-cloud buyer's accepted-domains list can actually exercise. A
hybrid Exchange Online/on-premises tenant is the one case where an on-premises-configured
`ExternalRelay` domain is real, but it is a separate on-premises Active Directory object this
scenario's Exchange-Online-only tooling cannot see. See
`scenarios/dlp/accepted-domains-hygiene-check/design.md` §2 for the full grounding and its
`ExternalRelayObserved` finding, which flags exactly this rare case as `[INFO]` if it's ever observed
against a cloud tenant.

**What remains genuinely unconfirmed, and is carried forward as an explicit VERIFY** (not resolved by
this reasoning): whether the **Microsoft 365 Copilot and Copilot Chat policy location specifically**
accepts `-FromScope` as a condition at all. `-FromScope` is confirmed to exist in the cmdlet's shared
parameter set (used across every DLP location), and its semantics independently match the Copilot
page's own prose description of the condition, but no Microsoft-published example, for any location,
combines `-FromScope` with the `CopilotExperiences` enforcement plane the way Example 4 combines
`-AdvancedRule`/`-RestrictAccess` for the label-condition rule this repo already ships. This is the
same class of gap as `copilot-prompt-full-block/design.md` §5's `-RestrictAccess` VERIFY, a
parameter/value pair independently confirmed to exist and be semantically apt, not independently
confirmed for this exact location.

## 5. Grounding the action: `-RestrictAccess ExcludeContentProcessing/Block`

Unlike `copilot-prompt-full-block` (which needed a *sub-action*-specific inference, because its
condition/action pairing is documented as **"Prevent Copilot from processing content > Processing
prompts"**, a parent action with a named sub-action), this scenario's action is documented with no
sub-action at all: the Copilot-location page's own supported-conditions-and-actions table lists the
action for this condition simply as **"Prevent Copilot from processing content"**
[[2]](#references), the exact same top-level action text, verbatim, as **Rule 0's** label-exclusion
action, which is the one combination Microsoft's `New-DlpCompliancePolicy` reference publishes a full
worked example for (`-RestrictAccess @(@{setting='ExcludeContentProcessing';value='Block'})` paired
with `-AdvancedRule`, a label condition) [[3]](#references). This scenario's inference therefore
rests on a narrower gap than `copilot-prompt-full-block`'s own already-accepted inference: the
*action* side of this rule is the one Microsoft has fully worked an example for; only the *condition*
side (`-FromScope` in place of `-AdvancedRule`) is unconfirmed for this specific rule shape. Still
flagged as an explicit `VERIFY` everywhere it matters (`README.md` §5/§11, the deploy script's
`.NOTES`, `validate/Test-CopilotExternalEmailBlockRule.ps1`'s `[WARN]`-level check), consistent with
`AGENTS.md` §4, reasoned inference, not fabrication, and not silently presented as certain.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| New scenario vs. extending a sibling in place | New, separate scenario folder that adds a fourth rule to the shared parent policy | Matches the established "extends" pattern from `copilot-prompt-full-block`, keeps this fragment's own `reviews.md` scoped to what it actually changed. |
| Deploy mechanism | `New-DlpComplianceRule -FromScope NotInOrganization -RestrictAccess @(@{setting='ExcludeContentProcessing';value='Block'})` added to the existing policy by name | Best-grounded available mechanism per §4/§5; explicitly flagged as unconfirmed for this exact location rather than presented as certain. |
| Priority | 3 (after Rule 0 = 0, Rule 1 = 1, Rule 2 = 2 from the two existing siblings) | Keeps evaluation order stable and documented; does not reorder or renumber any existing rule. |
| Default `ReportSeverityLevel` | `Low` (configurable via `-ReportSeverityLevel`) | Unlike the SIT/label-based rules, a match here is an expected, routine consequence of receiving any external email that Copilot is later asked to summarize or reason over, not, by itself, an anomalous or high-risk event. A high default severity would flood the alerts queue with expected-behavior noise (see `README.md` §8). Operators in a high-assurance environment (see §2's prompt-injection framing) can raise it. |
| Rollback granularity | Disable/remove **this rule only**, never touching the parent policy or its other three rules | Same non-negotiable boundary as `copilot-prompt-full-block/design.md` §6, this scenario is additive to a policy it doesn't own outright. |
| Policy `Mode` | Not managed by this scenario | Same reasoning as `copilot-prompt-full-block/design.md` §6, avoids two scenarios both claiming ownership of the same policy-level setting. |

## 7. Non-goals

- This scenario does not create the parent policy. If the named policy doesn't already exist, the
  deploy script fails fast rather than silently creating one (same guard as `copilot-prompt-full-block`).
- This scenario does not resolve the open `-FromScope`-on-Copilot-location VERIFY definitively, 
  that requires either a pilot tenant (permanently out of reach for this repo's build process) or a
  future Microsoft-published worked example combining the two. It closes the "should we build this at
  all" question with a stronger-than-usual evidentiary basis (§4/§5), not the underlying grounding gap
  itself.
- This scenario does not attempt to inspect email **body** content for prompt-injection payloads, 
  Microsoft's own documentation is explicit that this control is metadata-only (sender-domain
  comparison), and this scenario does not claim otherwise anywhere in its docs or scripts.
- This scenario does not address prompt-injection risk from **other** external content Copilot can
  ground on (e.g., an external SharePoint guest share, a web search result before Rule 1 applies), 
  it closes exactly the one documented gap Microsoft names for external **email**, nothing broader.

## 8. References

Full citation list with URLs: `README.md` §12.
