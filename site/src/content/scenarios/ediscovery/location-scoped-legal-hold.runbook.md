---
part: "runbook"
parent: "ediscovery/location-scoped-legal-hold"
---
## Implementation steps

### Portal path (for a first manual walkthrough / to validate intent before scripting)

1. **Open (or create) the case**: Purview portal → **eDiscovery** → **Cases** → select the case
   (or **Create case** if this is a standalone matter).
2. **Create the hold policy**: in the case, **Hold policies** tab → **Create hold policy** → name
   and description → add data sources: enter the shared mailbox and/or distribution-list email
   under **Users**, and the SharePoint site URL under **Sites** → optionally add a KQL content
   query to scope what's held → **Apply hold**.
3. **Confirm status**: on the **Hold policy** page, confirm the policy shows **On** and each
   location's status shows no errors; if any location shows an error, use **Policy actions** →
   **Retry policy** after fixing the underlying cause (invalid address, inaccessible site).

### Script path (idempotent, parameterized, dry-run capable)

```powershell
# 1. Connect (app-only, certificate -- see Automation surface section 3).

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
no typed v1.0 cmdlet exists for those - the design notes).

## Configuration reference

| Object | Call | Key fields (from `deploy/policy/location-hold-definition.json`) |
|---|---|---|
| Case | `New-MgSecurityCaseEdiscoveryCase` (typed cmdlet, reused from the sibling scenario) | `displayName`, `description`, `externalId` |
| Hold policy | `POST .../legalHolds` | `displayName`, `description`, `contentQuery` (optional - blank holds all content in the specified locations) |
| userSource | `POST .../legalHolds/{id}/userSources` | `email`, `includedSources = 'mailbox'` (the only valid value in this context - the design notes) |
| siteSource | `POST .../legalHolds/{id}/siteSources` | `site.webUrl` |
| Retry a failed/partial source | `POST .../legalHolds/{id}/retryPolicy` | no body |
| Release one location | `DELETE .../userSources/{id}` or `.../siteSources/{id}` | - |
| Delete the entire hold policy | `DELETE .../legalHolds/{id}` | - |

`dataSourceHoldStatus` values used by the checks in `validate/Test-EdiscoveryLocationHold.ps1`:
`notApplied`, `applied`, `applying`, `removing`, `partial`. Policy-level
`policyStatus` values: `Pending`, `Error`, `Success`.

Full parameter grounding: each script's `.NOTES` block cites the exact Microsoft Learn REST
reference page for every endpoint it calls.

## Operations and tuning

**KPIs to watch:**
- **Per-source `holdStatus` regression** - a location that was `applied` and later shows
  `partial` or an error (without anyone running `Remove-EdiscoveryLocationHold.ps1`) signals an
  identity change (mailbox renamed, site URL changed) or an external hold action - see
  Microsoft's "Hold changed outside eDiscovery" error entry. Treat this the
  same way the sibling scenario treats a `HoldStatus` regression: an incident, not routine drift,
  given the spoliation exposure in why this matters.
- **The hold policy's `errors` collection** - should be empty in steady state; any non-empty
  value is a `FAIL` in `validate/Test-EdiscoveryLocationHold.ps1` and maps to a documented,
  actionable cause.
- **Distribution-list size drift toward the group-expansion cap(s)** - if this scenario's
  `userSources[]` includes a distribution list rather than individually resolved mailboxes,
  list growth over time is a real risk to watch, not a one-time concern at deploy. Treat **100
  members** (the more conservative, "every supported group type" figure Microsoft documents for
  the portal's own expansion picker) as the review trigger, not the larger >1,000-address figure
  documented for the hold-application error - see the known limitations for why the two aren't confirmed to be the
  same limit.

**Review cadence:** re-run `validate/Test-EdiscoveryLocationHold.ps1` on every active
location-scoped hold at least weekly for the life of the matter, mirroring the sibling scenario's
own cadence recommendation (*Legal Hold, Collection, Review, and Export* (operations and tuning)).

**Audit visibility:** the same gap the sibling scenario documents applies here - none of this
scenario's own Graph objects retain a full actor/history trail for who removed a source or deleted
the policy, beyond the object's own `lastModifiedBy` snapshot. Route hold-policy admin actions
through the Microsoft 365 unified audit log (`Search-UnifiedAuditLog`, automation surface 1) for
independent visibility; the exact `RecordType`/`Operations` values for these events are the same
open item tracked in the project backlog against the sibling scenario, not re-investigated separately
here.

## Rollback and decommission

See the rollback runbook for the full staged procedure. Quick reference:
`./deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId -UserSourceEmail
'<email>'` releases one named location; `-SiteSourceUrl '<url>'` releases one site; `-DeleteHold`
permanently deletes the entire policy. **Unlike the sibling custodian scenario's `release` action,
there is no reversible "pause" here on v1.0** - both removal paths carry Microsoft's own
documented warning that they might permanently delete content currently being preserved.

## References

1. Create and manage cases in eDiscovery - <https://learn.microsoft.com/purview/edisc-cases-manage>
2. Create holds in eDiscovery (portal hold-policy creation, data source types) - <https://learn.microsoft.com/purview/edisc-hold-create>
3. Manage holds in eDiscovery (hold policy states: Draft/On/In progress/Off/Pending deletion) - <https://learn.microsoft.com/purview/edisc-hold-manage#hold-policy-states>
4. userSource resource type (v1.0 `dataSourceHoldStatus` enum: notApplied/applied/applying/removing/partial) - <https://learn.microsoft.com/graph/api/resources/security-usersource?view=graph-rest-1.0>
5. ediscoveryHoldPolicy resource type (v1.0 `policyStatus` enum: Pending/Error/Success) - <https://learn.microsoft.com/graph/api/resources/security-ediscoveryholdpolicy?view=graph-rest-1.0>
6. Manage holds in eDiscovery - "Manage hold status errors" (full error table, incl. "Hold changed outside eDiscovery") - <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>
7. Manage holds in eDiscovery - SharePoint site must have a title to be placed on hold - <https://learn.microsoft.com/purview/edisc-hold-manage#manage-hold-status-errors>
8. Create ediscoveryHoldPolicy (v1.0 REST reference, request/response shape) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-post-legalholds?view=graph-rest-1.0>
9. Update ediscoveryHoldPolicy (v1.0 - only `contentQuery`/`description` are updatable) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-update?view=graph-rest-1.0>
10. Delete ediscoveryHoldPolicy (v1.0) - <https://learn.microsoft.com/graph/api/security-ediscoverycase-delete-legalholds?view=graph-rest-1.0>
11. Create userSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-usersources?view=graph-rest-1.0>
12. Create siteSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-post-sitesources?view=graph-rest-1.0>
13. Delete userSource / Delete siteSource (v1.0, `ediscoveryHoldPolicy` context) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-delete-usersources?view=graph-rest-1.0>, <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-delete-sitesources?view=graph-rest-1.0>
14. ediscoveryHoldPolicy: retryPolicy (v1.0) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-retrypolicy?view=graph-rest-1.0>
15. ediscoveryHoldPolicy: enablePolicy / disablePolicy (beta only; re-verified still beta-only 2026-09-04) - <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-enablepolicy?view=graph-rest-beta>, <https://learn.microsoft.com/graph/api/security-ediscoveryholdpolicy-disablepolicy?view=graph-rest-beta>
16. Create legalHold userSource (beta, custodian/legalHold context - group-mailbox email support) - <https://learn.microsoft.com/graph/api/ediscovery-legalhold-post-usersources?view=graph-rest-beta>

> Re-verify all links against current Microsoft Learn before a customer-facing deployment -
> Purview's Graph eDiscovery surface has moved namespaces within the product's own history, and
> beta-to-v1.0 promotions (including, possibly, `enablePolicy`/`disablePolicy` themselves) can
> change without notice.