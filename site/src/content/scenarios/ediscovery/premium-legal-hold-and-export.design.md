---
part: "design"
parent: "ediscovery/premium-legal-hold-and-export"
---
## 1. Why Microsoft Graph, not Security & Compliance PowerShell

Every other Purview policy-authoring scenario in this library that has a scriptable surface uses
Security & Compliance PowerShell (`Connect-IPPSSession`, automation surface 2). eDiscovery
(Premium) is the deliberate exception: Microsoft's own permissions documentation states plainly
that **app-only authentication for eDiscovery cmdlets in Security & Compliance PowerShell is
unsupported**, and its remediation guidance is to "transition automations to Microsoft Graph APIs
where available". This isn't a stylistic preference, S&C PowerShell
does still expose legacy eDiscovery cmdlets (`New-ComplianceCase`, `New-CaseHoldPolicy`, etc.),
and an *interactive, delegated* session can use them, but no unattended pipeline can, since
app-only auth against that specific connection is unsupported for this module family. Every
mutating call in this scenario's `deploy/` therefore goes through the `Microsoft.Graph.Security`
module (`microsoft.graph.security` namespace, v1.0, not `microsoft.graph.ediscovery`, which
Microsoft's own reference marks deprecated in favor of the `security` subnamespace
), matching [Automation surface §1](/docs/automation-surface/#1-five-automation-surfaces-not-one-read-this-first)'s routing rule for
"case-based work with review sets/analytics."

## 2. Two-API design: authoring vs. package download

The scenario's third deploy script (`Get-EdiscoveryExportPackage.ps1`) authenticates against a
*second*, non-Graph API, the "Microsoft Purview eDiscovery API", with its own token, scoped to
a separate first-party resource (`00001111-aaaa-2222-bbbb-3333cccc4444`) via `MSAL.PS`, and its
own `eDiscovery.Download.Read` application permission granted against a distinct service
principal (`MicrosoftPurviewEDiscovery`) that must be registered in the tenant before first use
. This isn't a design choice this scenario made, it's how Microsoft
built the download path, and getting it wrong (assuming the Graph token from the first two scripts
also authorizes the download) is the single most common failure mode a first-time implementer of
this pattern hits. The design keeps this as two clearly separated scripts (`New-Ediscovery*.ps1`
vs. `Get-EdiscoveryExportPackage.ps1`) rather than one, specifically so the two credentials/tokens
are never silently conflated in one function's scope.

## 3. Custodian-scoped hold vs. `ediscoveryHoldPolicy`, which one, and why

The v1.0 Graph API exposes two distinct hold mechanisms under an eDiscovery case:

1. **`ediscoveryCustodian.applyHold`**, the mechanism this scenario uses. A custodian is a named
 person; adding their `userSource`(s) and calling `applyHold` places a hold on that person's
 mailbox/OneDrive.
2. **`ediscoveryHoldPolicy`** (`POST.../legalHolds`), a separate object with its own
 `siteSources`/`userSources` relationships and an optional `contentQuery`, not necessarily tied
 to a named custodian at all.

Both are legitimately called "legal hold" in Microsoft's documentation, and a reader coming from
the S&C PowerShell world (where `New-CaseHoldPolicy` is the *only* hold object) can reasonably
expect one unified concept. This scenario deliberately picked the custodian-centric path because
it matches the overwhelmingly common real-world shape of a litigation hold, "preserve these
named individuals' data", and because custodian objects carry richer case-management semantics
(hold status, release, re-activate) that a bare `ediscoveryHoldPolicy` doesn't. The
`ediscoveryHoldPolicy` path is the better fit for a hold organized around a *location* rather than
a *person* (for example, a shared departmental mailbox with no single owner, or a regulatory sweep
across a distribution list), explicitly out of scope here and tracked as a follow-up in
`PROGRESS.md` rather than conflated into this fragment.

## 4. Idempotency design

Every object this scenario creates is found-or-created by exact-match lookup on a stable key,
mirroring the pattern this library already established for other name-less-unique Purview REST
surfaces (`scenarios/unified-catalog/curate-business-glossary/design.md` §2,
`scenarios/data-quality/rules-and-scorecards/`):

| Object | Lookup key | Why this key |
|---|---|---|
| Case | `displayName` (exact match, client-side) | No documented case-name-uniqueness filter API; client-side match mirrors the portal's own "case name must be unique" UX rule |
| Custodian | `email` | The one identifying property Microsoft's own `Create custodians` example uses |
| Custodian userSource | `email` within the custodian's userSource collection | userSources have no separate display name |
| Search | `displayName` | Same rationale as case |
| Review set | `displayName` | Same rationale as case; review set names are documented as unique with a 64-character limit |
| Custodian hold | `HoldStatus == 'success'` | Re-invoking `applyHold` on an already-held custodian is itself idempotent per Microsoft's async-operation design (a repeat `applyHold` simply re-asserts the hold), but this scenario still skips the call once `success` is observed, to avoid generating a redundant `ediscoveryHoldOperation` on every re-run |
| `addToReviewSet` / export | operation type + (best-effort) `outputName`/"any succeeded op" | **Weakest link in this design**, see §7 non-goal below and README.md §11's explicit VERIFY; no documented "does an equivalent operation already exist" filter exists for these two operation types |

## 5. Async operation handling

`addToReviewSet` and `export` both return `202 Accepted` with a `Location` header pointing at a
`caseOperation` resource, not the finished object, the API is explicitly asynchronous
. `New-EdiscoverySearchReviewSetExport.ps1` captures the operation ID
from the response headers (`-ResponseHeadersVariable`) and polls
`Get-MgSecurityCaseEdiscoveryCaseOperation` until the status leaves the in-flight set
(`notStarted`/`running`) or the caller-configurable timeout elapses, rather than either blocking
forever or assuming the call is synchronous. A timeout is treated as "still running, check back
later" (a `Write-Warning`, not a thrown error), a long collection genuinely can outlast a
reasonable script timeout for a large custodian population, and that's an operational fact, not a
failure this script should misreport.

## 6. Component summary

| Component | Purpose | Idempotency mechanism |
|---|---|---|
| `deploy/New-EdiscoveryPremiumLegalHold.ps1` | Case + custodian + userSource + hold | Find-or-create by key (§4); native `SupportsShouldProcess` on every Graph SDK cmdlet |
| `deploy/New-EdiscoverySearchReviewSetExport.ps1` | Search + review set + commit + export | Find-or-create by key (§4); async poll (§5) |
| `deploy/Get-EdiscoveryExportPackage.ps1` | Download the export package via the separate Purview eDiscovery API | Skips files already present locally with a matching byte size |
| `deploy/Remove-EdiscoveryPremiumLegalHold.ps1` | Staged rollback: release hold → close case → delete case | Each stage gated by an explicit switch; `-DeleteCase` implies `-CloseCase` |
| `deploy/policy/ediscovery-case-definition.json` | Declarative case/custodian/search/reviewSet/export definition | Single source of truth all four scripts read, so a re-run against the same file is a true no-op once the target state is reached |
| `validate/Test-EdiscoveryPremiumCaseSetup.ps1` | Read-only proof the case/custodians/hold/search/review-set/export state matches the definition file | `eDiscovery.Read.All` only; never calls a mutating endpoint |
| `deploy/Export-EdiscoveryAuditTrail.ps1` | Independent case-lifecycle/hold-policy-lifecycle audit trail via `Search-UnifiedAuditLog` (automation surface 1, not Graph), closes the Red Team finding in `reviews.md` that this scenario's own Graph objects carry no actor/history trail | Rolling CSV merge, de-duplicated by a composite key hashing `AuditData`, identical mechanism to `scenarios/compliance-manager/assess-against-iso27001/`'s and `scenarios/communication-compliance/harassment-and-code-of-conduct/`'s own audit-trail scripts |
| `validate/Test-EdiscoveryAuditTrail.ps1` | Read-only CSV schema/de-duplication/operation-value/sort-order checks for the audit trail file | Needs no tenant connection; never calls a mutating endpoint |

## 7. Non-goals (explicitly out of scope for this fragment)

- **`ediscoveryHoldPolicy`-based (location-scoped, non-custodian) holds**, see §3. A
 location-scoped hold scenario (regulatory sweep, departmental shared mailbox) is a natural,
 separately scoped follow-up, not a variant of this fragment.
- **Legal hold notifications** (the Premium custodian-communication workflow, initial notice,
 reminders, escalations, acknowledgment tracking), a follow-up fragment was tracked in
 `PROGRESS.md` to build this as a companion scenario, on the assumption (common to several other
 no-write-API Purview surfaces this library documents) that the gap was "portal-driven, no Graph
 write API." Re-grounding for that follow-up found something different and more final: Microsoft's
 current "Manage hold notifications" page states outright that legal hold custodian communications
 were **permanently retired on August 31, 2025** and aren't available in the new eDiscovery
 experience, not merely unautomatable, but gone. No companion scenario was built as a result; see
 README.md §11 for what that means for a preservation narrative and `PROGRESS.md` for the closed
 follow-up record.
- **Review-set analytics** (near-duplicate detection, themes, email threading, predictive coding,
 attorney-client privilege detection, redaction/PDF conversion), this scenario stops at
 "collect, commit, export," which is the right depth for a template scenario; a large,
 contested-privilege review would layer these on top of (not instead of) this fragment's
 foundation.
- **Export to a customer-owned Azure Storage account** (`azureBlobContainer`/`azureBlobToken`), 
 documented only for the deprecated beta `ediscovery` subnamespace's `reviewSet: export` action,
 not the current v1.0 `security.ediscoveryReviewSet: export` this scenario calls, which returns
 Microsoft-managed storage + a download URL only. A buyer who specifically needs bring-your-own-
 storage export should be told this path is not currently available on the supported v1.0
 surface, not have it silently attempted.
- **Insider Risk Management case escalation**, eDiscovery (Premium) supports being the
 *destination* of an escalated IRM case; wiring that integration is a
 natural follow-up once `scenarios/insider-risk/` has a scenario that produces an escalatable
 case, not something this fragment builds standalone. **Built** as
 `scenarios/insider-risk/irm-case-escalation-to-ediscovery/`, which reuses this scenario's
 custodian/hold pattern unmodified and picks up exactly where the manual "Escalate for
 investigation" portal click leaves off.

## 8. Audit trail script, grounding and the custodian-vs-hold-policy caveat

`deploy/Export-EdiscoveryAuditTrail.ps1` (added as a follow-up fragment; see `PROGRESS.md`) queries
`Search-UnifiedAuditLog -RecordType Discovery` for two categories confirmed verbatim against
Microsoft's "Audit log activities" eDiscovery reference: case lifecycle
(`CaseAdded`/`CaseUpdated`/`CaseClosed`/`CaseReopened`/`CaseRemoved`) and hold-**policy** lifecycle
(`HoldCreated`/`HoldUpdated`/`HoldRemoved`/`HoldRetryDistributionSync`). The reference page itself
carries no legacy-experience caution banner and is the same page this repo's
`scenarios/ediscovery/location-scoped-legal-hold/` scenario's design already cites for its own
`ediscoveryHoldPolicy` object, so the hold-policy category is confidently grounded for *that*
object model.

What it does **not** resolve: whether those same four hold-policy `Operation` values also fire for
*this* scenario's own `ediscoveryCustodian: applyHold`/`release` calls (§3's custodian-scoped hold
mechanism, a different object from `ediscoveryHoldPolicy`). One Microsoft Learn page states that a
custodian hold is "automatically added to a custodian hold policy" internally
, which would suggest yes, but that page, and the only page describing
a dedicated per-custodian audit search UI, both carry Microsoft's
caution banner limiting them to organizations hosted by 21Vianet (China) after the classic
eDiscovery experience's retirement everywhere else on August 31, 2025. Neither is confirmed to
describe the current, non-legacy experience this scenario's own deploy scripts target. Rather than
assume either direction, this was recorded as an explicit VERIFY (pilot tenant) in `PROGRESS.md`
and in the script's own `.NOTES`, per `AGENTS.md` §4, the script still queries the hold-policy
category (the best-documented signal available; a zero-row result for a tenant that has only ever
used custodian holds is itself informative), it just doesn't claim more than it's confirmed.

## References {#references-design}

- R1. Assign permissions in eDiscovery, app-only auth unsupported statement and remediation guidance, <https://learn.microsoft.com/purview/edisc-permissions#configure-app-only-authentication-for-ediscovery-powershell>
- R2. Create legalHold (beta, deprecated `microsoft.graph.ediscovery` subnamespace notice pointing to `microsoft.graph.security`), <https://learn.microsoft.com/graph/api/ediscovery-case-post-legalholds?view=graph-rest-beta>
- R3. Use Microsoft Purview APIs for eDiscovery, two-API design, `MicrosoftPurviewEDiscovery` app registration, `eDiscovery.Download.Read`, <https://learn.microsoft.com/purview/edisc-ref-api-guide>
- R4. ediscoveryHoldPolicy resource type (siteSources/userSources relationships, contentQuery), <https://learn.microsoft.com/graph/api/resources/security-ediscoveryholdpolicy?view=graph-rest-1.0>
- R5. Create and manage cases in eDiscovery ("The case name must be unique in your organization"), <https://learn.microsoft.com/purview/edisc-cases-manage>
- R6. New-MgSecurityCaseEdiscoveryCaseReviewSet reference (`displayName` unique, 64-character limit), <https://learn.microsoft.com/powershell/module/microsoft.graph.security/new-mgsecuritycaseediscoverycasereviewset?view=graph-powershell-1.0>
- R7. ediscoveryReviewSet: addToReviewSet / export actions (202 Accepted + Location header), <https://learn.microsoft.com/graph/api/security-ediscoveryreviewset-addtoreviewset?view=graph-rest-1.0>, <https://learn.microsoft.com/graph/api/security-ediscoveryreviewset-export?view=graph-rest-1.0>
- R8. Microsoft Purview eDiscovery legacy solutions, Insider Risk Management case escalation to eDiscovery (Premium), <https://learn.microsoft.com/purview/ediscovery#comparison-of-key-capabilities>
- R9. Audit log activities, eDiscovery activity reference (`Operation` names/descriptions for case and hold-policy lifecycle events, no legacy-experience caution banner), <https://learn.microsoft.com/purview/audit-log-activities#ediscovery-activities>
- R10. Manage holds in eDiscovery (Premium), "custodian hold policy" claim; classic-experience/21Vianet-China-only caution banner, <https://learn.microsoft.com/purview/ediscovery-managing-holds>
- R11. View custodian audit activity, per-custodian audit search UI; classic-experience/21Vianet-China-only caution banner, <https://learn.microsoft.com/purview/ediscovery-view-custodian-activity>
- R12. Manage hold notifications (current, non-legacy page, the permanent-retirement `Important` callout that closed the legal-hold-notifications follow-up in §7 above), <https://learn.microsoft.com/purview/ediscovery-manage-hold-notifications>
