---
part: "design"
parent: "insider-risk/irm-case-escalation-to-ediscovery"
---
## 1. Why this is a thin integration layer, not a re-implementation

Microsoft's own documentation confirms the integration exists and names the mechanism: Insider
Risk Management's **"Escalate for investigation"** case action opens a new eDiscovery (Premium)
case, and the resulting case appears under **eDiscovery → Advanced** in the Microsoft Purview
portal. But the escalation action itself has
**no Graph or PowerShell API**, it is reachable only through the case action toolbar in the
Insider Risk Management **Cases** dashboard. This matches a pattern this library has already
documented for several other Purview surfaces (Compliance Manager assessment creation,
Communication Compliance policy authoring, Insider Risk Management policy authoring itself), 
Microsoft ships the capability in the portal well ahead of (or instead of) an automatable API for
it. This scenario does not fight that boundary: it names it plainly (§1 here, README.md §3/§11)
and automates everything *downstream* of the one manual click, using APIs this library has
already grounded and used elsewhere:

- **Custodian + hold provisioning**, the identical `applyHold` pattern from
 `scenarios/ediscovery/premium-legal-hold-and-export/deploy/New-EdiscoveryPremiumLegalHold.ps1`,
 duplicated (not dot-sourced) into this scenario's own `deploy/` tree per this repo's
 one-scenario-one-self-contained-deploy-tree convention (every other scenario in this library
 follows the same rule, see, for example, how `scenarios/unified-catalog/manage-data-products/`
 re-implements rather than imports `curate-business-glossary`'s owner-resolution pattern).
- **IRM alert lookup**, `Get-MgSecurityAlertV2 -AlertId`, the get-by-ID parameter set of the same
 cmdlet `scenarios/insider-risk/departing-employee-data-theft/deploy/Export-InsiderRiskAlerts.ps1`
 already uses for bulk alert export.

## 2. The provenance-linking problem, and why the case `description` field is the answer

The `microsoft.graph.security.ediscoveryCase` resource has exactly eight writable/settable
properties, and none of them identifies where the case came from: no `source`, `origin`,
`caseType`, or foreign-key-shaped field of any kind exists on the resource
. Once an investigator clicks "Escalate for investigation," the only
programmatic trace connecting the new eDiscovery case back to the Insider Risk Management case
and its alerts is whatever the investigator typed into the escalation dialog's own name/notes
fields, and Microsoft's documentation doesn't specify a naming convention, so two different
investigators could name the same kind of escalation two different ways, making the case
undiscoverable by anything other than a human reading through the eDiscovery case list.

This scenario closes that gap with two deliberately low-tech mechanisms, chosen because they use
only fields the v1.0 API actually exposes rather than inventing a linkage Microsoft doesn't
support:

1. **A documented naming convention** (`IRM-<IRM Case ID>-<UPN local part>`, README.md §5) for the
 case name typed into the escalation dialog, this is *this repo's own convention*, not a
 Microsoft one, and is the only way `deploy/Confirm-EdiscoveryEscalationLink.ps1` can find the
 escalated case by `displayName` (the same client-side exact-match lookup pattern the sibling
 scenario's `design.md` §4 already establishes for the "no documented case-name uniqueness
 filter API" gap).
2. **A delimited provenance block stamped into the case `description` field**, the one free-text
 property `Update-MgSecurityCaseEdiscoveryCase` can write, recording
 the source IRM case ID, the escalated user, and a best-effort resolved list of the IRM alerts
 that led to the escalation. The block is delimited by fixed marker strings so a re-run can
 detect it (idempotent, no duplicate stamp) without disturbing whatever notes an investigator
 already typed into the description themselves.

Both mechanisms are disclosed as *this scenario's* design choice, not a Microsoft-native linkage, 
see README.md §11 and the Product Owner review round in `reviews.md`.

Because the naming convention is the *only* lookup key, a reused case name across two genuinely
different escalations is a real (if narrow) failure mode: without a guard, a second run would
silently stamp the wrong IRM case ID/user onto a case that already carries a correct provenance
record for someone else's investigation. `Confirm-ProvenanceBlock` (in
`deploy/Confirm-EdiscoveryEscalationLink.ps1`) checks whether an existing block's IRM case ID and
user match the current run's definition file before treating "a block exists" as "done", a
mismatch throws unless the caller passes `-Force`, and even then the script appends a second block
rather than overwriting the first, so provenance history is never destroyed by a re-run (a Blue
Team finding from this scenario's own review round, `reviews.md`).

## 3. Why this script unconditionally reconciles the custodian, rather than only checking

Microsoft's documentation for "Escalate for investigation" describes the dialog (name, notes,
notice-template fields) and confirms the new case is created, but does not state whether the
flagged user is automatically added as a custodian with a hold applied, or whether the new case
starts empty and the legal team is expected to add custodians themselves (the same way they would
for any newly created eDiscovery case). Rather than guess either
answer, `Confirm-EdiscoveryEscalationLink.ps1` treats custodian/userSource/hold provisioning as an
idempotent target-state reconciliation, identical in mechanism to
`New-EdiscoveryPremiumLegalHold.ps1`'s own find-or-create logic:

- If the portal already added the user as a custodian with a hold, every step in this script is a
 no-op (find-or-create finds; `HoldStatus == 'success'` skips the `applyHold` call), safe.
- If it didn't, this script does the work that would otherwise require someone to remember to do
 it manually after every escalation, the actual value this scenario adds beyond documentation.

This is the same "unconditionally reconcile to a declared target state, and let idempotency do the
safety work" philosophy this library uses throughout (see, for example,
`scenarios/records-management/regulatory-records-disposition/design.md`'s create-or-report
pattern), applied here to resolve a genuine unknown rather than a confirmed fact.

## 4. Non-goals (explicitly out of scope for this fragment)

- **Triggering the escalation itself.** No Graph/PowerShell write API exists for it, see §1. A
 human with Insider Risk Management Investigator/Analyst access must complete the portal step
 first; this scenario begins after that click.
- **A genuinely automatic, event-driven trigger for `Confirm-EdiscoveryEscalationLink.ps1` upon
 escalation.** See §5, neither Power Automate's IRM triggers nor the IRM audit log offer one as
 currently documented; a scheduled poll (README.md §8) is the only unattended option today.
- **Resolving, assigning, or otherwise acting on the source Insider Risk Management case.** IRM
 case management (as opposed to read-only alert export) has no documented Graph/PowerShell write
 API, the same finding `scenarios/insider-risk/departing-employee-data-theft/design.md` §6
 already recorded and left as a non-goal for that scenario. This scenario adds nothing new on
 that front; it only reads alert metadata for the provenance block.
- **Search, review set, and export.** Once this scenario's custodian/hold is in place, the case is
 functionally identical to one built entirely by
 `scenarios/ediscovery/premium-legal-hold-and-export/`, and that scenario's own
 `New-EdiscoverySearchReviewSetExport.ps1` / `Get-EdiscoveryExportPackage.ps1` /
 `Export-EdiscoveryAuditTrail.ps1` scripts apply unmodified from that point forward, deliberately
 not duplicated here.
- **Closing, reopening, or deleting the eDiscovery case.** Same reasoning, this scenario only adds
 a custodian/description to an existing case; the sibling scenario's
 `Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId... -CloseCase/-DeleteCase` already owns that
 lifecycle for any case built with this library's tooling, escalated or not.
- **Auto-discovering escalated cases without the naming convention.** Given §2's finding (no
 `source`/`origin` field on `ediscoveryCase`), there is no way to enumerate "all eDiscovery cases
 that originated from an IRM escalation" without either the naming convention this scenario
 establishes or a human manually cross-referencing case-creation timestamps against IRM case
 escalation notes, a follow-up worth tracking only if Microsoft ships a linking field.

## 5. Why "wire this to run automatically on escalation" stays unresolved, not guessed

README.md §8 originally described this scenario's "next step" as a scheduled poll *or* "a Power
Automate flow triggered on escalation", implying the two were equally automatic. A follow-up
grounding pass on this fragment found that characterization wrong and corrected it:

- Microsoft's own custom-flow documentation for Insider Risk Management states its case-scoped
 trigger is something "you can select … from the Insider Risk Management Cases dashboard"
 and that running it is a three-step manual action, "Select **Automate**
 on the case action toolbar," "Choose the Power Automate flow to run," "select **Run flow**"
, not a subscription that fires when a case is escalated. Of the five
 documented Purview-connector actions available to a custom IRM flow (Get alert/case/user/
 alerts-for-case, Add case note), none is a trigger *or* action tied to
 escalation specifically, and none can invoke an external script, a custom flow would need a
 generic, non-Purview action (HTTP/webhook, Azure Automation, Functions) added on top, which is
 ordinary Power Automate capability but is flagged in Microsoft's own licensing note as potentially
 requiring **more Power Automate licenses** than the recommended templates need
.
- The **Insider Risk Management audit log**, a plausible alternative "poll for the escalation event
 instead of polling the case itself" mechanism, is explicitly documented as "independent" of the
 Microsoft 365 unified audit log this library's other audit-trail scripts query via
 `Search-UnifiedAuditLog`, and is viewable/exportable only through the Purview portal, with no
 Graph/REST endpoint of its own found during this pass.

Neither path is a Microsoft-documented, automatable, event-driven trigger. Rather than build a
custom Power Automate flow whose value (skipping a tool-switch, not skipping a manual click) doesn't
match the "no human has to remember anything" bar this scenario's own KPI (README.md §8) sets, or
guess at an undocumented IRM-audit-log API, this fragment corrects the record (README.md §8/§11,
this section) and leaves genuine event-driven automation as an explicit non-goal (§4) pending either
a documented IRM-audit-log query API or a true escalation-triggered Power Automate trigger from
Microsoft, tracked in `PROGRESS.md` as a re-check item rather than resolved by guessing, per
`AGENTS.md` §4.

## References {#references-design}

- R1. Microsoft Purview eDiscovery legacy solutions, "Integration with Insider Risk Management" (escalation opens a new eDiscovery (Premium) case), <https://learn.microsoft.com/purview/ediscovery#comparison-of-key-capabilities>
- R2. Take action on Insider Risk Management cases, "Escalate for investigation" / "Escalate a case to a user investigation" full portal walkthrough, <https://learn.microsoft.com/purview/insider-risk-management-cases#case-actions>
- R3. Get-MgSecurityAlertV2 (PowerShell reference, `-AlertId` "Get" parameter set), <https://learn.microsoft.com/powershell/module/microsoft.graph.security/get-mgsecurityalertv2?view=graph-powershell-1.0>
- R4. ediscoveryCase resource type (full property/relationship list, no source/origin field), <https://learn.microsoft.com/graph/api/resources/security-ediscoverycase?view=graph-rest-1.0>
- R5. Update ediscoveryCase (PATCH `.../ediscoveryCases/{id}`, `description`/`displayName`/`externalId` are the only writable fields), <https://learn.microsoft.com/graph/api/security-ediscoverycase-update?view=graph-rest-1.0>
- R6. Automate Insider Risk Management actions with Microsoft Power Automate flows, custom-flow triggers/actions, manual "Run flow" invocation, and the premium-connector licensing caveat, <https://learn.microsoft.com/purview/insider-risk-management-settings-power-automate>
- R7. Review activities with the Insider Risk Management audit log, "isn't associated with the Microsoft 365 audit log," portal view/CSV export only, <https://learn.microsoft.com/purview/insider-risk-management-audit-log>
