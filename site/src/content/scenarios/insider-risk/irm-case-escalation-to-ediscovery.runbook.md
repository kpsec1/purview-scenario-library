---
part: "runbook"
parent: "insider-risk/irm-case-escalation-to-ediscovery"
---
## Implementation steps

### Portal path (the one manual step this scenario cannot script)

1. In the Microsoft Purview portal, go to **Insider Risk Management** → **Cases**, select the case
   to escalate, and select **Escalate for investigation** on the case action toolbar.
2. In the **Escalate for investigation** dialog, name the new case using this scenario's
   convention: **`IRM-<IRM Case ID>-<UPN local part>`** - for example, `IRM-2026-0143-jordan.reyes`
   for IRM case `2026-0143` escalating `jordan.reyes@contoso.com`. This name is *this library's own
   convention*, not a Microsoft-documented one - the case name is the only key
   `Confirm-EdiscoveryEscalationLink.ps1` can use to find the case later, so consistency matters
   more than the exact format.
3. Add any investigator notes and select **Escalate**, review the notice fields, then **Confirm**
   to create the case. Note the IRM case's own **Case ID** (shown in the Cases
   dashboard) and, from the case's **Alerts** tab, the **Alert ID**(s) that justified the
   escalation - both go into the definition file below.
4. The new case appears under **eDiscovery** → **Advanced** in the Purview portal.

### Script path (idempotent, parameterized, dry-run capable) - after step 3 above

```powershell
# 1. Fill in deploy/policy/escalation-link-definition.json with the IRM case ID, the escalated
#    user's UPN, any alert IDs from the IRM case's Alerts tab, and the exact case name typed in
#    portal step 2.

# 2. Connect (app-only, certificate -- see docs/automation-surface.md §3).

# 3. Dry run -- confirms the case is findable and reports every provenance/custodian/hold action
#    this run would take, without calling any mutating Graph endpoint.
./deploy/Confirm-EdiscoveryEscalationLink.ps1 `
    -DefinitionPath ./deploy/policy/escalation-link-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

# 4. Stamp the provenance block and reconcile the custodian/userSource/hold.
./deploy/Confirm-EdiscoveryEscalationLink.ps1 `
    -DefinitionPath ./deploy/policy/escalation-link-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 5. Validate.
./validate/Test-EdiscoveryEscalationLink.ps1 `
    -DefinitionPath ./deploy/policy/escalation-link-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# 6. From here, the case is a normal eDiscovery (Premium) case -- proceed with the sibling
#    scenario's search/review-set/export scripts, unmodified:
../ediscovery/premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1 `
    -DefinitionPath ../ediscovery/premium-legal-hold-and-export/deploy/policy/ediscovery-case-definition.json `
    -CaseId $caseId -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

## Configuration reference

| Object / field | Cmdlet or field name | Key values (from `deploy/policy/escalation-link-definition.json`) |
|---|---|---|
| IRM case reference | `irmCase.caseId` | Free-text; the Case ID shown on the IRM Cases dashboard (exact format not format-validated by this script - the known limitations) |
| Escalated user | `irmCase.userPrincipalName` | Used as both the alert-lookup context and the custodian `email` |
| IRM alerts (optional) | `irmCase.alertIds[]` | Resolved via `Get-MgSecurityAlertV2 -AlertId` for the provenance block; safe to leave empty |
| Escalated case lookup key | `ediscoveryCase.displayName` | Must exactly match the name typed into the portal's "Escalate for investigation" dialog |
| Case lookup | `Get-MgSecurityCaseEdiscoveryCase -All \| Where-Object DisplayName -eq ...` | Client-side exact match - same pattern as the sibling scenario (no documented case-name filter API) |
| Provenance stamp | `Update-MgSecurityCaseEdiscoveryCase -BodyParameter @{ description = ... }` | Delimited block; idempotent - skipped if already present |
| Custodian | `New-MgSecurityCaseEdiscoveryCaseCustodian` | `email` = `irmCase.userPrincipalName` |
| Custodian userSource | `New-MgSecurityCaseEdiscoveryCaseCustodianUserSource` | `email`, `includedSources = 'mailbox, site'` |
| Hold | `Add-MgSecurityCaseEdiscoveryCaseCustodianHold` | (no body - targets one custodian per call) |
| Release hold (rollback, opt-in) | `Invoke-MgGraphRequest POST .../custodians/{id}/release` | Identical to the sibling scenario's rollback action |

## Operations and tuning

**KPIs to watch:**
- **Time from escalation to a reconciled hold.** The whole value of this scenario is closing the
  window between "investigator clicks Escalate" and "custodian is actually on hold." Two mitigations
  are available today, **neither of which is a true automatic trigger** - grounded and corrected in
  this build after an earlier draft of this section implied otherwise:
  1. **A scheduled poll** - run `Confirm-EdiscoveryEscalationLink.ps1` on a recurring schedule (e.g.
     hourly) against every definition file for cases the team expects to be escalated soon. This is
     the only option that needs no human to remember anything after the portal click, at the cost of
     up-to-one-interval latency.
  2. **A manually-run Power Automate flow, invoked from the same toolbar the investigator just used
     to escalate** - the case action toolbar's **Automate** control supports a
     *custom* flow using the "For a selected Insider Risk Management case" trigger; an investigator who has just escalated can select **Automate** → the flow
     → **Run flow** as their very next click, one tool-switch cheaper than
     opening a PowerShell session. **This is still a manually-invoked action, not an event-driven
     one** - Microsoft's own custom-flow documentation describes the trigger as something "you can
     select … from the Insider Risk Management Cases dashboard", not something
     that fires automatically when a case is escalated. None of the five documented Microsoft
     Purview-connector actions available to a custom flow (Get IRM alert/case/user/alerts-for-case,
     Add IRM case note) can call this scenario's script directly either - doing
     so requires adding a generic, non-Purview action (an HTTP request to a webhook, or an Azure
     Automation/Functions connector) to the custom flow, which is ordinary Power Automate capability
     but may require a **premium connector license** beyond what the recommended IRM templates need
     - VERIFY (pilot tenant) before assuming zero incremental Power Automate
     cost for this specific integration.
  A genuinely automatic trigger would need either an event-driven Power Automate trigger for
  escalation (not documented as of this build) or a queryable API for case-escalation activity. The
  dedicated **Insider Risk Management audit log** does record case actions, but Microsoft states it
  "isn't associated with the Microsoft 365 audit log" - it's "independent," viewable and
  CSV-exportable only from the Purview portal, with no documented Graph/REST endpoint of its own; `Search-UnifiedAuditLog` (the mechanism this library's other audit-trail
  scripts, e.g. *Legal Hold, Collection, Review, and Export*
  Export-EdiscoveryAuditTrail.ps1`, already use) does not cover this workload. Until one of those two
  gaps closes, option 1 (scheduled poll) is the only way to guarantee this scenario always runs
  without depending on a human's memory.
- **Provenance-block mismatch rate** - `validate/Test-EdiscoveryEscalationLink.ps1`'s FAIL for "block
  present but doesn't match the definition file" signals either a re-used case name across two
  different escalations (a naming-convention violation, the implementation steps step 2) or a stale definition file -
  both worth tracking, since either erodes the traceability this scenario exists to provide.
- **Custodian `HoldStatus` regression** - identical KPI to the sibling scenario's operations and tuning;
  applies equally to a custodian this scenario added.

**Review cadence:** re-run `validate/Test-EdiscoveryEscalationLink.ps1` on the same cadence as the
sibling scenario's own weekly hold-health check, for the life of the matter.

**Provenance is one-directional.** This scenario stamps the eDiscovery case with a pointer back to
the IRM case; it does not (and cannot - the design notes) write anything back onto the IRM case itself
recording that it was escalated and to where. An investigator relying on the IRM case alone, without
also checking eDiscovery → Advanced, will not see this scenario's work reflected there - Microsoft's
own system-generated case note ("A case escalation" - see the sibling `insider-risk-management-cases`
reference) is the only trace left on the IRM side, and it doesn't name the
resulting eDiscovery case.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ...` strips the provenance block only
(reversible - re-run `Confirm-EdiscoveryEscalationLink.ps1` to re-stamp it); add `-ReleaseHold` for
the destructive stage, gated the same way as the sibling scenario. Closing or deleting the
eDiscovery case itself is the sibling scenario's `Remove-EdiscoveryPremiumLegalHold.ps1`'s job, not
duplicated here.

## References

1. Microsoft Purview eDiscovery legacy solutions - "Integration with Insider Risk Management" - <https://learn.microsoft.com/purview/ediscovery#comparison-of-key-capabilities>
2. Take action on Insider Risk Management cases - "Escalate for investigation" full portal walkthrough - <https://learn.microsoft.com/purview/insider-risk-management-cases#case-actions>
3. Take action on Insider Risk Management cases - system-generated case notes ("A case escalation") and the case action toolbar's Automate/Power Automate option - <https://learn.microsoft.com/purview/insider-risk-management-cases#investigate-a-case>
4. ediscoveryCase resource type (property/relationship reference - no source/origin field) - <https://learn.microsoft.com/graph/api/resources/security-ediscoverycase?view=graph-rest-1.0>
5. Update ediscoveryCase (PATCH `.../ediscoveryCases/{id}` - `description` field) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-update?view=graph-rest-1.0>
6. Get-MgSecurityAlertV2 (PowerShell reference - `-AlertId` "Get" parameter set) - <https://learn.microsoft.com/powershell/module/microsoft.graph.security/get-mgsecurityalertv2?view=graph-powershell-1.0>
7. Learn about Insider Risk Management - workflow overview, eDiscovery (Premium) escalation step - <https://learn.microsoft.com/purview/insider-risk-management#workflow>
8. *Legal Hold, Collection, Review, and Export* - the sibling scenario this one is additive on top of (custodian/hold pattern, licensing, search/review-set/export continuation) - *Legal Hold, Collection, Review, and Export*
9. *Departing Employee Data Theft* - an example IRM policy producing escalatable cases, and its own Graph alert-export pattern reused here - *Departing Employee Data Theft*
10. Automate Insider Risk Management actions with Microsoft Power Automate flows - confirms the "For a selected Insider Risk Management case" custom-flow trigger is manually selected from the Cases dashboard (not event-driven), the five Purview-connector actions available to a custom flow, and the premium-connector licensing caveat for custom flows beyond the recommended templates - <https://learn.microsoft.com/purview/insider-risk-management-settings-power-automate>
11. Review activities with the Insider Risk Management audit log - confirms the IRM audit log is independent of the Microsoft 365 unified audit log, with no documented Graph/REST query endpoint (portal view + CSV export only) - <https://learn.microsoft.com/purview/insider-risk-management-audit-log>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment.