---
title: "Location-Scoped Legal Hold (Regulatory Sweep / Shared Mailbox)"
category: "eDiscovery"
categorySlug: "ediscovery"
slug: "location-scoped-legal-hold"
whoFor: "a legal/compliance team (or an MSSP acting on their behalf) responding to a"
frameworks: []
licensing: []
deployCount: 3
validateCount: 1
hasDesign: true
hasRollback: true
toc: [{"id":"1-scenario-summary","text":"1. Scenario summary"},{"id":"2-businessregulatory-driver","text":"2. Business/regulatory driver"},{"id":"3-prerequisites","text":"3. Prerequisites"},{"id":"4-architecture","text":"4. Architecture"},{"id":"5-step-by-step-implementation","text":"5. Step-by-step implementation"},{"id":"6-configuration-reference","text":"6. Configuration reference"},{"id":"7-validation--how-to-prove-it-works","text":"7. Validation / how to prove it works"},{"id":"8-operations--tuning","text":"8. Operations & tuning"},{"id":"9-rollback--decommission","text":"9. Rollback / decommission"},{"id":"10-cost--licensing-notes","text":"10. Cost & licensing notes"},{"id":"11-known-limitations--gotchas","text":"11. Known limitations & gotchas"},{"id":"12-references","text":"12. References"}]
---
## 1. Scenario summary

Builds a Microsoft Purview eDiscovery (Premium) location-scoped legal hold, a
`microsoft.graph.security.ediscoveryHoldPolicy` covering one or more mailboxes, distribution
lists, and SharePoint sites, via app-only Microsoft Graph automation, for matters where the
preservation obligation attaches to a **location**, not a **named custodian**.

**Who it's for:** a legal/compliance team (or an MSSP acting on their behalf) responding to a
regulatory inquiry or internal sweep that names a shared departmental mailbox, a compliance
distribution list, or a team site rather than a specific individual, the companion scenario to
`scenarios/ediscovery/premium-legal-hold-and-export/`, which covers the named-custodian path.
Run both against the same case when a matter needs both kinds of preservation.

## 2. Business/regulatory driver

The preservation duty described in `scenarios/ediscovery/premium-legal-hold-and-export/README.md`
§2 (FRCP Rule 37(e), common-law preservation duty, regulatory civil investigative demands) applies
identically here, what differs is the *shape* of what needs preserving. A regulator's CID or an
internal investigation frequently names a function, a distribution list, or a shared resource
("preserve the Payments team's shared inbox and site, and everyone on the
`payments-compliance-dl` list") rather than a roster of named individuals. Forcing that into the
custodian model means either resolving list membership into named custodians one by one, losing
the "membership changes, the hold should track it" property a location-scoped hold naturally has
, or leaving the shared/functional mailbox uncovered because it has no single owning person to
name as a custodian. This scenario is the technical control for that second, genuinely common
shape of preservation obligation.

## 3. Prerequisites

Full licensing and role detail: [Licensing matrix](/docs/licensing-matrix/) and [RBAC model](/docs/rbac-model/). This
scenario's requirements are identical to the sibling custodian scenario's, see
`scenarios/ediscovery/premium-legal-hold-and-export/README.md` §3 for the full table (eDiscovery
Premium licensing on every held mailbox, tenant/case Premium toggles, eDiscovery Manager/
Administrator RBAC, and the Graph app-only auth requirement). Two differences specific to this
scenario:

| Requirement | Minimum | Notes |
|---|---|---|
| Licensing on a **shared/functional mailbox** | The mailbox itself needs eDiscovery Premium-tier licensing/entitlement the same as a person's mailbox would, a shared mailbox has no independent license by default in many tenants | Confirm the shared mailbox has the Exchange Online Plan 2 (or Plan 1 + Archiving add-on) entitlement this scenario's parent doc already requires for shared-mailbox custodians, before adding it as a userSource |
| **Gating prerequisite for `-DeleteHold` or removing a userSource/siteSource (`Remove-EdiscoveryLocationHold.ps1`)** | Written confirmation from counsel that the preservation duty for the affected location(s) has actually lapsed | Both removal paths on this object carry Microsoft's own documented risk of **permanent deletion of content currently being preserved** (§9, `rollback.md`), a materially higher-stakes rollback than the custodian scenario's reversible release |

> Verify current entitlement names against [Licensing matrix](/docs/licensing-matrix/) and the Product Terms
> before a sales commitment, SKU names change.

## 4. Architecture

```mermaid
flowchart TD
    A[New-EdiscoveryLocationHold.ps1] -->|find-or-create| B[eDiscoveryCase]
    A -->|find-or-create| C[ediscoveryHoldPolicy<br/>displayName, contentQuery]
    C -->|find-or-create| D[userSource<br/>payments-team@contoso.com]
    C -->|find-or-create| E[userSource<br/>payments-compliance-dl@contoso.com<br/>distribution list]
    C -->|find-or-create| F[siteSource<br/>PaymentsTeam SharePoint site]

    D -.holdStatus.-> H{{Hold policy status /<br/>portal Hold policies tab}}
    E -.holdStatus.-> H
    F -.holdStatus.-> H
    C -.policy status + errors.-> H

    A -.-Retry, on error/partial.-> G[retryPolicy]
    G -.restamps.-> D
    G -.restamps.-> E
    G -.restamps.-> F

    subgraph Removal["Remove-EdiscoveryLocationHold.ps1 -- no v1.0 'pause', only delete"]
        direction LR
        I["Delete one userSource/siteSource<br/>(that location only)"]
        J["-DeleteHold<br/>(entire policy, all locations)"]
    end
```

All authoring goes through Microsoft Graph, `microsoft.graph.security` namespace, v1.0, the same
supported app-only path the sibling custodian scenario uses, for the same reason
([Automation surface §3](/docs/automation-surface/#3-authentication-patterns-interactive-vs-unattended)). Unlike the custodian scenario, **no v1.0 typed PowerShell
cmdlet exists** for `ediscoveryHoldPolicy` or its `siteSources`/`userSources` collections (only
the Beta SDK module has one), this scenario's scripts call the v1.0 REST endpoints directly via
`Invoke-MgGraphRequest`, per `design.md` §4.

## 5. Step-by-step implementation

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Open (or create) the case**: Purview portal → **eDiscovery** → **Cases** → select the case
 (or **Create case** if this is a standalone matter).
2. **Create the hold policy**: in the case, **Hold policies** tab → **Create hold policy** → name
 and description → add data sources: enter the shared mailbox and/or distribution-list email
 under **Users**, and the SharePoint site URL under **Sites** → optionally add a KQL content
 query to scope what's held → **Apply hold**.
3. **Confirm status**: on the **Hold policy** page, confirm the policy shows **On** and each
 location's status shows no errors; if any location shows an error, use **Policy actions** →
 **Retry policy** after fixing the underlying cause (invalid address, inaccessible site)
.

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (app-only, certificate -- see docs/automation-surface.md section 3).

# 2. Dry run -- reports every case/hold/source action this run would take, makes none.
./deploy/New-EdiscoveryLocationHold.ps1 `
    -DefinitionPath ./deploy/policy/location-hold-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

# 3. Create the case (if needed), the hold policy, and every declared userSource/siteSource.
./deploy/New-EdiscoveryLocationHold.ps1 `
    -DefinitionPath ./deploy/policy/location-hold-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
# Note the case id and hold policy id printed at the end.

# 4. If any source reports an error or a non-applied/applying status, retry.
./deploy/New-EdiscoveryLocationHold.ps1 `
    -DefinitionPath ./deploy/policy/location-hold-definition.json -Retry `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

# Optional: -WaitForApplied polls each newly added source until it leaves 'applying', instead of
# firing-and-forgetting the add (mirrors the sibling scenario's -WaitForHold).

# 5. Validate.
./validate/Test-EdiscoveryLocationHold.ps1 `
    -DefinitionPath ./deploy/policy/location-hold-definition.json `
    -CaseId $caseId -HoldId $holdId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Both deploy/validate scripts use Microsoft Graph (`Microsoft.Graph.Security` module for the case,
`Invoke-MgGraphRequest` against the v1.0 REST endpoints for the hold policy and its sources, since
no typed v1.0 cmdlet exists for those, `design.md` §4/§7).

## 6. Configuration reference

| Object | Call | Key fields (from `deploy/policy/location-hold-definition.json`) |
|---|---|---|
| Case | `New-MgSecurityCaseEdiscoveryCase` (typed cmdlet, reused from the sibling scenario) | `displayName`, `description`, `externalId` |
| Hold policy | `POST.../legalHolds` | `displayName`, `description`, `contentQuery` (optional, blank holds all content in the specified locations) |
| userSource | `POST.../legalHolds/{id}/userSources` | `email`, `includedSources = 'mailbox'` (the only valid value in this context, `design.md` §2) |
| siteSource | `POST.../legalHolds/{id}/siteSources` | `site.webUrl` |
| Retry a failed/partial source | `POST.../legalHolds/{id}/retryPolicy` | no body |
| Release one location | `DELETE.../userSources/{id}` or `.../siteSources/{id}` |, |
| Delete the entire hold policy | `DELETE.../legalHolds/{id}` |, |

`dataSourceHoldStatus` values used by the checks in `validate/Test-EdiscoveryLocationHold.ps1`:
`notApplied`, `applied`, `applying`, `removing`, `partial`. Policy-level
`policyStatus` values: `Pending`, `Error`, `Success`.

Full parameter grounding: each script's `.NOTES` block cites the exact Microsoft Learn REST
reference page for every endpoint it calls.

## 7. Validation / how to prove it works

1. **Automated check**, `./validate/Test-EdiscoveryLocationHold.ps1 -DefinitionPath...
 -CaseId $caseId -HoldId $holdId...` confirms the case, hold policy, every declared
 userSource/siteSource, and the policy's own error collection; exits non-zero on any hard
 failure (safe for a CI-style pre-flight or a scheduled drift check).
2. **Propagation timing**, a freshly added source can show `applying` before settling to
 `applied`; the validate script reports `applying` as `WARN`, not `FAIL`. Microsoft doesn't
 publish an exact propagation SLA for this object the way it does for custodian holds (up to 24
 hours), treat a source still `applying` after a comparable window as worth investigating with
 **Retry policy**, not immediately re-run as a fresh add.
3. **Functional proof (portal)**, open the case's **Hold policies** tab and confirm the policy
 shows **On** with every location's status green/no errors.
4. **Error-driven proof**, Microsoft's own hold-error reference (§12) maps each error string to a
 specific, actionable cause (invalid email/URL, inaccessible site, distribution-group size cap,
 identity change since the hold was applied). Treat any non-empty `errors` collection the
 validate script reports as a specific remediation task, not generic "flakiness."

## 8. Operations & tuning

**KPIs to watch:**
- **Per-source `holdStatus` regression**, a location that was `applied` and later shows
 `partial` or an error (without anyone running `Remove-EdiscoveryLocationHold.ps1`) signals an
 identity change (mailbox renamed, site URL changed) or an external hold action, see
 Microsoft's "Hold changed outside eDiscovery" error entry. Treat this the
 same way the sibling scenario treats a `HoldStatus` regression: an incident, not routine drift,
 given the spoliation exposure in §2.
- **The hold policy's `errors` collection**, should be empty in steady state; any non-empty
 value is a `FAIL` in `validate/Test-EdiscoveryLocationHold.ps1` and maps to a documented,
 actionable cause (§12).
- **Distribution-list size drift toward the group-expansion cap(s)**, if this scenario's
 `userSources[]` includes a distribution list rather than individually resolved mailboxes (§11),
 list growth over time is a real risk to watch, not a one-time concern at deploy. Treat **100
 members** (the more conservative, "every supported group type" figure Microsoft documents for
 the portal's own expansion picker) as the review trigger, not the larger >1,000-address figure
 documented for the hold-application error, see §11 for why the two aren't confirmed to be the
 same limit.

**Review cadence:** re-run `validate/Test-EdiscoveryLocationHold.ps1` on every active
location-scoped hold at least weekly for the life of the matter, mirroring the sibling scenario's
own cadence recommendation (`premium-legal-hold-and-export/README.md` §8).

**Audit visibility:** the same gap the sibling scenario documents applies here, none of this
scenario's own Graph objects retain a full actor/history trail for who removed a source or deleted
the policy, beyond the object's own `lastModifiedBy` snapshot. Route hold-policy admin actions
through the Microsoft 365 unified audit log (`Search-UnifiedAuditLog`, automation surface 1) for
independent visibility; the exact `RecordType`/`Operations` values for these events are the same
open item tracked in `PROGRESS.md` against the sibling scenario, not re-investigated separately
here.

## 9. Rollback / decommission

See `rollback.md` for the full staged procedure. Quick reference:
`./deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId -UserSourceEmail
'<email>'` releases one named location; `-SiteSourceUrl '<url>'` releases one site; `-DeleteHold`
permanently deletes the entire policy. **Unlike the sibling custodian scenario's `release` action,
there is no reversible "pause" here on v1.0**, both removal paths carry Microsoft's own
documented warning that they might permanently delete content currently being preserved
(`design.md` §4, `rollback.md`).

## 10. Cost & licensing notes

Identical to `scenarios/ediscovery/premium-legal-hold-and-export/README.md` §10, no PAYG
component for hold creation/management; licensing is per-mailbox, not per-case, and (per §3
above) a shared/functional mailbox included in this hold needs the same Exchange Online
entitlement a person's mailbox would. A distribution list itself has no license requirement, but
every mailbox it expands to at hold time needs the qualifying entitlement.

## 11. Known limitations & gotchas

- **No v1.0 "turn off and keep for later."** `enablePolicy`/`disablePolicy` exist only in the
 beta Graph namespace (`design.md` §4), **re-verified 2026-09-04, still beta-only**; no
 promotion has occurred, and the v1.0 Update operation still exposes only `contentQuery`/
 `description` (`isEnabled` is not PATCH-settable either). This scenario's
 `Remove-EdiscoveryLocationHold.ps1` can only release individual locations or delete the whole
 policy, both are Microsoft-documented as potentially causing **permanent deletion of content
 currently being preserved**, not a reversible pause.
- **VERIFY (pilot tenant, before pointing this at a distribution list you haven't already
 tested):** whether a distribution list's own SMTP address is accepted as a `userSource.email`
 value on the v1.0 `ediscoveryHoldPolicy` endpoint and expanded server-side to member mailboxes.
 Corroborated by Microsoft's beta custodian-context userSource reference ("or the SMTP address
 of the group mailbox") and by the "Distribution group has too many members" (>1,000) error
 reference, but the v1.0, non-beta endpoint this scenario actually calls does not itself
 document group-mailbox support (`design.md` §3). If unconfirmed for your tenant, resolve and
 list individual member mailboxes instead.
- **Two different, current Microsoft Learn pages document two different group-expansion member
 caps, and neither is confirmed to govern this scenario's own REST-API code path (`design.md`
 §3, re-grounded 2026-09-04):** "Create holds in eDiscovery" documents the **portal's own
 interactive data-source picker** as limited to **100 members**, for "every supported group
 type" (distribution list, mail-enabled security group, Microsoft 365 group, Microsoft Teams
 group, Viva Engage group); "Manage holds in eDiscovery" documents a
 **"Distribution group has too many members" hold-application error** at **more than 1,000
 email addresses**, specific to distribution groups. Both pages are current
 (not legacy/superseded, re-fetched directly, not stale). Microsoft does not state whether
 these describe the same limit surfaced at two different moments (portal member-picker vs.
 post-apply error) or two genuinely independent limits on two different code paths, and this
 scenario's script uses neither the portal picker nor is confirmed to hit the same expansion
 logic the >1,000 error describes, it calls the `ediscoveryHoldPolicy` REST `userSources`
 endpoint directly. Treat **100 members** as the conservative planning threshold (§8); watch for
 the **"Distribution group has too many members"** string specifically in the policy's `errors`
 collection as the one hard failure mode Microsoft documents by name. VERIFY against a pilot
 tenant, at both thresholds, which (if either) applies to this REST-driven path before relying
 on server-side DL expansion for a list near either size.
- **`siteSource` find-or-create/validate matching is by parsed URL slug vs. returned site title,
 not a direct URL comparison**, neither the `List siteSources` nor `Create siteSource` v1.0
 reference exposes the source's `webUrl` on the response object. This is a real, disclosed weak
 point (`design.md` §6), not a robust match; a site whose title diverges from its URL slug can
 produce a false "not found."
- **A SharePoint site without a title cannot be placed on hold at all**, Microsoft's own guidance
 states this as a hard requirement.
- **This scenario does not resolve Teams/Microsoft 365 Group membership into a hold.** Holding a
 Team or group means adding its own mailbox and SharePoint site (resolved via
 `Get-UnifiedGroup`/`Get-UnifiedGroupLinks` in Exchange Online PowerShell) as a userSource/
 siteSource pair, mechanically supported by this scenario's scripts, but the lookup itself is
 out of scope here (`design.md` §8).
- **Deleting the case turns off every hold in it, including this location-scoped one**, the same
 fact the sibling scenario documents for custodian holds applies identically here; the two hold
 types share the same case lifecycle.
- **Condition filters and KeyQL filters beyond `contentQuery`** are a richer portal capability
 this scenario's single-`contentQuery` model doesn't cover (`design.md` §8), a portal edit that
 adds those filters directly won't be reflected in, or reconciled by, this scenario's definition
 file.

## 12. References

1. Create and manage cases in eDiscovery, <https://learn.microsoft.com/purview/edisc-cases-manage>
2. Create holds in eDiscovery (portal hold-policy creation, data source types), <https://learn.microsoft.com/purview/edisc-hold-create>
3. Manage holds in eDiscovery (hold policy states: Draft/On/In progress/Off/Pending deletion), <https://learn.microsoft.com/purview/edisc-hold-manage#hold-policy-states>
4. userSource resource type (v1.0 `dataSourceHoldStatus` enum: notApplied/applied/applying/removing/partial), <https://learn.microsoft.com/graph/api/resources/security-usersource?view=graph-rest-1.0>
5. ediscoveryHoldPolicy resource type (v1.0 `policyStatus` enum: Pending/Error/Success), <https://learn.microsoft.com/graph/api/resources/security-ediscoveryholdpolicy?view=graph-rest-1.0>
6. Manage holds in eDiscovery, "Manage hold status errors" (full error table, incl. "Hold changed outside eDiscovery"), <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>
7. Manage holds in eDiscovery, SharePoint site must have a title to be placed on hold, <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>
8. Create ediscoveryHoldPolicy (v1.0 REST reference, request/response shape), <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-legalholds?view=graph-rest-1.0>
9. Update ediscoveryHoldPolicy (v1.0, only `contentQuery`/`description` are updatable), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-update?view=graph-rest-1.0>
10. Delete ediscoveryHoldPolicy (v1.0), <https://learn.microsoft.com/graph/api/security-ediscoverycase-delete-legalholds?view=graph-rest-1.0>
11. Create userSource (v1.0, `ediscoveryHoldPolicy` context), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-usersources?view=graph-rest-1.0>
12. Create siteSource (v1.0, `ediscoveryHoldPolicy` context), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-sitesources?view=graph-rest-1.0>
13. Delete userSource / Delete siteSource (v1.0, `ediscoveryHoldPolicy` context), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-delete-usersources?view=graph-rest-1.0>, <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-delete-sitesources?view=graph-rest-1.0>
14. ediscoveryHoldPolicy: retryPolicy (v1.0), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-retrypolicy?view=graph-rest-1.0>
15. ediscoveryHoldPolicy: enablePolicy / disablePolicy (beta only; re-verified still beta-only 2026-09-04), <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-enablepolicy?view=graph-rest-beta>, <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-disablepolicy?view=graph-rest-beta>
16. Create legalHold userSource (beta, custodian/legalHold context, group-mailbox email support), <https://learn.microsoft.com/graph/api/ediscovery-legalhold-post-usersources?view=graph-rest-beta>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment, 
> Purview's Graph eDiscovery surface has moved namespaces within the product's own history, and
> beta-to-v1.0 promotions (including, possibly, `enablePolicy`/`disablePolicy` themselves) can
> change without notice.
