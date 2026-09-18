---
title: "Case Escalation to eDiscovery (Premium)"
fullTitle: "Insider Risk Management — Case Escalation to eDiscovery (Premium)"
category: "Insider Risk Management"
categorySlug: "insider-risk"
slug: "irm-case-escalation-to-ediscovery"
repoPath: "scenarios/insider-risk/irm-case-escalation-to-ediscovery"
parts: ["design","deploy","validate","rollback"]
deployCount: 3
validateCount: 1
---
## 1. Scenario summary

Wires Insider Risk Management's manual **"Escalate for investigation"** case action — which opens
a new Microsoft Purview eDiscovery (Premium) case for the flagged user — into this library's
existing eDiscovery (Premium) automation: a documented case-naming convention so the escalated
case is programmatically discoverable, a stamped provenance record linking the eDiscovery case
back to the source IRM case and its alerts (the one thing Microsoft's escalation flow doesn't do
on its own), and a reconciled custodian + mailbox/OneDrive hold for the flagged user.

**Who it's for:** an Insider Risk Management Investigator (or a legal/compliance team acting on
their referral) who has already decided a case needs "extra legal review" and clicked **Escalate
for investigation**, and needs the resulting eDiscovery case reliably provisioned and traceable
back to the alert evidence that justified it — instead of a fresh, disconnected eDiscovery case
that a legal team has to hand-populate and a compliance auditor can't later tie back to the IRM
finding that triggered it.

## 2. Business/regulatory driver

Insider risk cases that escalate to legal review are, by definition, the highest-stakes subset of
an Insider Risk Management program — Microsoft's own guidance frames escalation as the step for
when "you need extra legal review for the user's risk activity" [[1]](#references). Two gaps
specifically matter for a defensible investigation and, later, litigation posture:

- **Preservation must actually happen, promptly, every time.** An escalation that creates an empty
  eDiscovery case — with no custodian added and no hold applied because a human forgot the manual
  follow-up step — creates exactly the kind of preservation gap `scenarios/ediscovery/
  premium-legal-hold-and-export/README.md` §2 already frames as spoliation exposure under FRCP
  Rule 37(e) and the common-law duty to preserve. This scenario removes the "did someone remember
  to finish provisioning the case" dependency on a busy investigator's memory.
- **The evidentiary chain from alert → case → legal hold must be reconstructible later.** An
  auditor, opposing counsel, or a later reviewer asking "why was this eDiscovery case opened, and
  what evidence justified it" should not have to rely on an investigator's memory or a
  Teams/email thread outside Purview — the provenance block this scenario stamps (§8) is a durable,
  in-product answer to that question, sourced from fields the v1.0 Graph API actually exposes
  (design.md §2), not a fabricated linkage.

## 3. Prerequisites

Full licensing and role detail: `docs/licensing-matrix.md` and `docs/rbac-model.md`. This scenario
is additive on top of two scenarios this library already covers in full —
`scenarios/insider-risk/departing-employee-data-theft/` (or any other IRM policy producing cases)
and `scenarios/ediscovery/premium-legal-hold-and-export/` — so its own incremental requirements
are narrow:

| Requirement | Minimum | Notes |
|---|---|---|
| Insider Risk Management, with at least one policy producing cases | See `scenarios/insider-risk/departing-employee-data-theft/README.md` §3 | This scenario assumes a case already exists and has been escalated — it does not create IRM policies or cases |
| Role to escalate an IRM case | **Insider Risk Management** or **Insider Risk Management Investigators** role group | The manual portal step this scenario starts after (§5); see `docs/rbac-model.md` §4 |
| eDiscovery (Premium) features + role/licensing for custodian/hold automation | Identical to `scenarios/ediscovery/premium-legal-hold-and-export/README.md` §3 | Same **eDiscovery Manager**/**Administrator** role, same per-custodian E5/add-on licensing requirement |
| Automation identity (case description update, custodian, userSource, hold) | Entra app registration, certificate-based app-only auth, **`eDiscovery.ReadWrite.All`** application permission, registered as an eDiscovery Manager/Administrator service principal | Identical requirement to the sibling scenario — see that scenario's README.md §3 and `docs/automation-surface.md` §3 for why Graph, not S&C PowerShell, is the only supported app-only path |
| Automation identity (optional alert-title lookup for the provenance block) | The same or a separate app registration, granted **`SecurityAlert.Read.All`** application permission | Only needed if the definition file's `alertIds` array is non-empty; the scenario still functions without it (README.md §11) |
| **Gating prerequisite for `-ReleaseHold` in `Remove-EdiscoveryEscalationLink.ps1`** | Written confirmation from counsel that the IRM case's preservation duty has actually lapsed | Identical gate to the sibling scenario's `rollback.md`; releasing a hold placed for an active investigation prematurely can itself be a preservation failure |

## 4. Architecture

```mermaid
flowchart TD
    A[Insider Risk Management case] -->|manual portal click:<br/>Escalate for investigation<br/>NO API - README §3/§11| B[New eDiscovery (Premium) case<br/>named per this scenario's<br/>IRM-&lt;CaseID&gt;-&lt;UPN&gt; convention]

    B --> C[Confirm-EdiscoveryEscalationLink.ps1]
    C -->|find by displayName<br/>throws if not found| B
    C -->|GET, best-effort| D[(IRM alerts<br/>Get-MgSecurityAlertV2 -AlertId)]
    C -->|PATCH description<br/>idempotent, marker-delimited| B
    C -->|find-or-create + applyHold,<br/>same pattern as the sibling scenario| E[Custodian: flagged user<br/>mailbox + OneDrive userSource]

    B --> F[scenarios/ediscovery/premium-legal-hold-and-export/<br/>New-EdiscoverySearchReviewSetExport.ps1<br/>-- unmodified, reused as-is]

    subgraph ThisScenario["This scenario's scope"]
        C
        E
    end
    subgraph SiblingScenario["scenarios/ediscovery/premium-legal-hold-and-export (reused, not duplicated)"]
        F
    end
```

The escalation click (portal-only, no API — design.md §1) is the one step this scenario cannot
automate. Everything after it — provenance linkage and custodian/hold reconciliation — runs
through Microsoft Graph (`microsoft.graph.security` namespace, automation surface 3), the same
surface and auth pattern as `scenarios/ediscovery/premium-legal-hold-and-export/`.

## 5. Step-by-step implementation

### Portal path (the one manual step this scenario cannot script)

1. In the Microsoft Purview portal, go to **Insider Risk Management** → **Cases**, select the case
   to escalate, and select **Escalate for investigation** on the case action toolbar
   [[2]](#references).
2. In the **Escalate for investigation** dialog, name the new case using this scenario's
   convention: **`IRM-<IRM Case ID>-<UPN local part>`** — for example, `IRM-2026-0143-jordan.reyes`
   for IRM case `2026-0143` escalating `jordan.reyes@contoso.com`. This name is *this repo's own
   convention*, not a Microsoft-documented one (design.md §2) — the case name is the only key
   `Confirm-EdiscoveryEscalationLink.ps1` can use to find the case later, so consistency matters
   more than the exact format.
3. Add any investigator notes and select **Escalate**, review the notice fields, then **Confirm**
   to create the case [[2]](#references). Note the IRM case's own **Case ID** (shown in the Cases
   dashboard) and, from the case's **Alerts** tab, the **Alert ID**(s) that justified the
   escalation — both go into the definition file below.
4. The new case appears under **eDiscovery** → **Advanced** in the Purview portal [[1]](#references).

### Script path (idempotent, parameterized, dry-run capable) — after step 3 above

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

## 6. Configuration reference

| Object / field | Cmdlet or field name | Key values (from `deploy/policy/escalation-link-definition.json`) |
|---|---|---|
| IRM case reference | `irmCase.caseId` | Free-text; the Case ID shown on the IRM Cases dashboard (exact format not format-validated by this script — README.md §11) |
| Escalated user | `irmCase.userPrincipalName` | Used as both the alert-lookup context and the custodian `email` |
| IRM alerts (optional) | `irmCase.alertIds[]` | Resolved via `Get-MgSecurityAlertV2 -AlertId` for the provenance block; safe to leave empty |
| Escalated case lookup key | `ediscoveryCase.displayName` | Must exactly match the name typed into the portal's "Escalate for investigation" dialog (§5 step 2) |
| Case lookup | `Get-MgSecurityCaseEdiscoveryCase -All \| Where-Object DisplayName -eq ...` | Client-side exact match — same pattern as the sibling scenario (no documented case-name filter API) |
| Provenance stamp | `Update-MgSecurityCaseEdiscoveryCase -BodyParameter @{ description = ... }` | Delimited block; idempotent — skipped if already present |
| Custodian | `New-MgSecurityCaseEdiscoveryCaseCustodian` | `email` = `irmCase.userPrincipalName` |
| Custodian userSource | `New-MgSecurityCaseEdiscoveryCaseCustodianUserSource` | `email`, `includedSources = 'mailbox, site'` |
| Hold | `Add-MgSecurityCaseEdiscoveryCaseCustodianHold` | (no body — targets one custodian per call) |
| Release hold (rollback, opt-in) | `Invoke-MgGraphRequest POST .../custodians/{id}/release` | Identical to the sibling scenario's rollback action |

## 7. Validation / how to prove it works

1. **Automated check** — `./validate/Test-EdiscoveryEscalationLink.ps1 -DefinitionPath ... ...`
   confirms the case exists, the provenance block is present and matches the definition file, the
   custodian and userSource exist, and the hold status; exits non-zero on any hard failure.
2. **Hold propagation** — same 24-hour caveat as the sibling scenario: a non-`success` `HoldStatus`
   immediately after this script runs is reported `WARN`, not `FAIL`; re-run later.
3. **Functional proof (portal)** — open the escalated case in **eDiscovery → Advanced**, confirm
   the **Description** field shows the provenance block, and confirm the custodian's **Hold
   policies** show mailbox + OneDrive as **On**.
4. **Traceability proof** — from the description's `Source Insider Risk Management case: ...`
   line, confirm a reviewer with IRM access can independently locate the originating case by its
   Case ID and cross-check the listed alert IDs against that case's **Alerts** tab.

## 8. Operations & tuning

**KPIs to watch:**
- **Time from escalation to a reconciled hold.** The whole value of this scenario is closing the
  window between "investigator clicks Escalate" and "custodian is actually on hold." Two mitigations
  are available today, **neither of which is a true automatic trigger** — grounded and corrected in
  this build after an earlier draft of this section implied otherwise:
  1. **A scheduled poll** — run `Confirm-EdiscoveryEscalationLink.ps1` on a recurring schedule (e.g.
     hourly) against every definition file for cases the team expects to be escalated soon. This is
     the only option that needs no human to remember anything after the portal click, at the cost of
     up-to-one-interval latency.
  2. **A manually-run Power Automate flow, invoked from the same toolbar the investigator just used
     to escalate** — the case action toolbar's **Automate** control [[3]](#references) supports a
     *custom* flow using the "For a selected Insider Risk Management case" trigger
     [[10]](#references); an investigator who has just escalated can select **Automate** → the flow
     → **Run flow** [[10]](#references) as their very next click, one tool-switch cheaper than
     opening a PowerShell session. **This is still a manually-invoked action, not an event-driven
     one** — Microsoft's own custom-flow documentation describes the trigger as something "you can
     select … from the Insider Risk Management Cases dashboard" [[10]](#references), not something
     that fires automatically when a case is escalated. None of the five documented Microsoft
     Purview-connector actions available to a custom flow (Get IRM alert/case/user/alerts-for-case,
     Add IRM case note [[10]](#references)) can call this scenario's script directly either — doing
     so requires adding a generic, non-Purview action (an HTTP request to a webhook, or an Azure
     Automation/Functions connector) to the custom flow, which is ordinary Power Automate capability
     but may require a **premium connector license** beyond what the recommended IRM templates need
     [[10]](#references) — VERIFY (pilot tenant) before assuming zero incremental Power Automate
     cost for this specific integration.
  A genuinely automatic trigger would need either an event-driven Power Automate trigger for
  escalation (not documented as of this build) or a queryable API for case-escalation activity. The
  dedicated **Insider Risk Management audit log** does record case actions, but Microsoft states it
  "isn't associated with the Microsoft 365 audit log" — it's "independent," viewable and
  CSV-exportable only from the Purview portal, with no documented Graph/REST endpoint of its own
  [[11]](#references); `Search-UnifiedAuditLog` (the mechanism this library's other audit-trail
  scripts, e.g. `scenarios/ediscovery/premium-legal-hold-and-export/deploy/
  Export-EdiscoveryAuditTrail.ps1`, already use) does not cover this workload. Until one of those two
  gaps closes, option 1 (scheduled poll) is the only way to guarantee this scenario always runs
  without depending on a human's memory.
- **Provenance-block mismatch rate** — `validate/Test-EdiscoveryEscalationLink.ps1`'s FAIL for "block
  present but doesn't match the definition file" signals either a re-used case name across two
  different escalations (a naming-convention violation, §5 step 2) or a stale definition file —
  both worth tracking, since either erodes the traceability this scenario exists to provide.
- **Custodian `HoldStatus` regression** — identical KPI to the sibling scenario's README.md §8;
  applies equally to a custodian this scenario added.

**Review cadence:** re-run `validate/Test-EdiscoveryEscalationLink.ps1` on the same cadence as the
sibling scenario's own weekly hold-health check, for the life of the matter.

**Provenance is one-directional.** This scenario stamps the eDiscovery case with a pointer back to
the IRM case; it does not (and cannot — design.md §4) write anything back onto the IRM case itself
recording that it was escalated and to where. An investigator relying on the IRM case alone, without
also checking eDiscovery → Advanced, will not see this scenario's work reflected there — Microsoft's
own system-generated case note ("A case escalation" — see the sibling `insider-risk-management-cases`
reference [[3]](#references)) is the only trace left on the IRM side, and it doesn't name the
resulting eDiscovery case.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure. Quick reference:
`./deploy/Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ...` strips the provenance block only
(reversible — re-run `Confirm-EdiscoveryEscalationLink.ps1` to re-stamp it); add `-ReleaseHold` for
the destructive stage, gated the same way as the sibling scenario. Closing or deleting the
eDiscovery case itself is the sibling scenario's `Remove-EdiscoveryPremiumLegalHold.ps1`'s job, not
duplicated here (design.md §4).

## 10. Cost & licensing notes

No incremental licensing beyond what `scenarios/insider-risk/departing-employee-data-theft/` and
`scenarios/ediscovery/premium-legal-hold-and-export/` already require — this scenario adds no new
Purview feature, only automation gluing two already-licensed capabilities together. See those two
scenarios' README.md §10 for the underlying licensing/PAYG notes (IRM's cloud/GenAI PAYG
processing units; eDiscovery Export API's PAYG metering).

## 11. Known limitations & gotchas

- **This scenario cannot trigger the escalation itself, and cannot create the eDiscovery case.**
  There is no Graph/PowerShell API for Insider Risk Management's "Escalate for investigation"
  action — confirmed by its absence from every Graph security API surface this library has
  grounded (design.md §1). `Confirm-EdiscoveryEscalationLink.ps1` throws a clear, actionable error
  naming the missing portal step if the case isn't found, rather than silently doing nothing.
- **The naming convention (`IRM-<Case ID>-<UPN local part>`) is this repo's own invention, not a
  Microsoft one.** Nothing in the product enforces it, and a typo or a different investigator's
  different naming habit breaks the lookup silently (the script reports "case not found," which
  could equally mean "not yet escalated" or "escalated under a different name") — this is the
  single biggest operational risk in this scenario and is called out again in `reviews.md` (Red
  Team). A **different**, sharper failure mode — the same case name accidentally reused across two
  *separate* escalations — is guarded against directly: `Confirm-EdiscoveryEscalationLink.ps1`
  throws rather than silently stamping mismatched provenance if the case already carries a block
  for a different IRM case/user, and requires an explicit `-Force` to proceed (which appends,
  never overwrites, so no prior provenance record is lost).
- **VERIFY (pilot tenant):** the exact format of the "Case ID" shown on the Insider Risk
  Management Cases dashboard (numeric, GUID, or another scheme) is not confirmed by Microsoft's
  documentation, which only describes it as "The ID of the case." This scenario treats it as an
  opaque string throughout and never parses or format-validates it.
- **VERIFY (pilot tenant):** whether the portal's "Escalate for investigation" flow automatically
  adds the flagged user as a custodian with a hold applied is not documented either way by
  Microsoft. `Confirm-EdiscoveryEscalationLink.ps1` does not assume an answer — see design.md §3
  for why unconditional reconciliation is safe regardless of which way this turns out.
- **The provenance block records alert *titles/severities* at stamp time, not a live link.** If an
  alert is later re-triaged, merged into an incident, or its severity changes, the provenance block
  is not automatically refreshed — re-run `Confirm-EdiscoveryEscalationLink.ps1` (it detects the
  existing block and currently skips re-stamping; see the script's `.NOTES` for the exact
  behavior) or treat the block as a point-in-time record, which is what a defensible provenance
  record should be regardless.
- **This scenario does not resolve, close, or otherwise act on the source Insider Risk Management
  case.** IRM case management has no documented Graph/PowerShell write API — same finding
  `scenarios/insider-risk/departing-employee-data-theft/design.md` §6 already recorded.
- **There is no automatic, event-driven way to fire `Confirm-EdiscoveryEscalationLink.ps1` the
  instant a case is escalated.** Grounded in this build (§8): the Power Automate "For a selected
  Insider Risk Management case" trigger is manually selected by a human from the Cases dashboard,
  not fired by the escalation event itself [[10]](#references); the separate Insider Risk
  Management audit log that does record case actions has no documented Graph/REST query endpoint of
  its own and isn't covered by `Search-UnifiedAuditLog` [[11]](#references). A scheduled poll of
  this script (§8) is therefore the only way to guarantee it always runs unattended.

## 12. References

1. Microsoft Purview eDiscovery legacy solutions — "Integration with Insider Risk Management" — <https://learn.microsoft.com/purview/ediscovery#comparison-of-key-capabilities>
2. Take action on Insider Risk Management cases — "Escalate for investigation" full portal walkthrough — <https://learn.microsoft.com/purview/insider-risk-management-cases#case-actions>
3. Take action on Insider Risk Management cases — system-generated case notes ("A case escalation") and the case action toolbar's Automate/Power Automate option — <https://learn.microsoft.com/purview/insider-risk-management-cases#investigate-a-case>
4. ediscoveryCase resource type (property/relationship reference — no source/origin field) — <https://learn.microsoft.com/graph/api/resources/security-ediscoverycase?view=graph-rest-1.0>
5. Update ediscoveryCase (PATCH `.../ediscoveryCases/{id}` — `description` field) — <https://learn.microsoft.com/graph/api/security-ediscoverycase-update?view=graph-rest-1.0>
6. Get-MgSecurityAlertV2 (PowerShell reference — `-AlertId` "Get" parameter set) — <https://learn.microsoft.com/powershell/module/microsoft.graph.security/get-mgsecurityalertv2?view=graph-powershell-1.0>
7. Learn about Insider Risk Management — workflow overview, eDiscovery (Premium) escalation step — <https://learn.microsoft.com/purview/insider-risk-management#workflow>
8. scenarios/ediscovery/premium-legal-hold-and-export/README.md — the sibling scenario this one is additive on top of (custodian/hold pattern, licensing, search/review-set/export continuation) — `scenarios/ediscovery/premium-legal-hold-and-export/README.md`
9. scenarios/insider-risk/departing-employee-data-theft/README.md — an example IRM policy producing escalatable cases, and its own Graph alert-export pattern reused here — `scenarios/insider-risk/departing-employee-data-theft/README.md`
10. Automate Insider Risk Management actions with Microsoft Power Automate flows — confirms the "For a selected Insider Risk Management case" custom-flow trigger is manually selected from the Cases dashboard (not event-driven), the five Purview-connector actions available to a custom flow, and the premium-connector licensing caveat for custom flows beyond the recommended templates — <https://learn.microsoft.com/purview/insider-risk-management-settings-power-automate>
11. Review activities with the Insider Risk Management audit log — confirms the IRM audit log is independent of the Microsoft 365 unified audit log, with no documented Graph/REST query endpoint (portal view + CSV export only) — <https://learn.microsoft.com/purview/insider-risk-management-audit-log>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment.
