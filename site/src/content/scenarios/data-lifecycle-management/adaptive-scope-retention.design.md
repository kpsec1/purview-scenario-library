---
part: "design"
parent: "data-lifecycle-management/adaptive-scope-retention"
---
## 1. Problem statement

A static-scope retention policy names its targets explicitly (a SharePoint site URL, a list of
mailboxes, a distribution group). For a population that changes constantly, executives who are
promoted, hired, or leave; users whose country or department changes, a static scope goes stale:
someone has to notice the org-chart change and edit the policy. Microsoft's own worked example is
exactly this case: "Emails and OneDrive documents for executives require a longer retention period
than standard users... For new executives, there's no need to reconfigure the retention policy
because these new users with their corresponding values... are automatically picked up"
. This scenario builds that pattern as code: a query-driven **adaptive scope**
plus a retention policy/rule that targets it, instead of a location list that needs maintenance.

## 2. Design goals

1. **Membership by attribute, not by list.** Target executives via the Entra `Title` attribute
 (an adaptive scope), not a static distribution group someone has to keep current.
2. **Reproducible as code.** One config → scope + policy + rule; re-running is safe and reports
 rather than silently mutates existing objects.
3. **Honest about the object model's actual parameter surface.** The `AdaptiveScopeLocation`
 parameter set of `New-RetentionCompliancePolicy` is genuinely thinner than the static
 (`Default`) parameter set, no separate location toggles, and this design says so rather than
 inventing a narrower scope than what's documented (§4).
4. **Lower-irreversibility default.** Uses a **Keep-only** action, not a record or regulatory
 record label, this scenario is about *who* gets targeted (adaptively), not about
 immutability, which the sibling `retention-labels-financial-records` scenario already covers.
5. **Companion to the static-scope sibling, not a replacement.** `retention-labels-financial-
 records/README.md` Section 11 flags adaptive scopes as an explicit follow-up for large/dynamic
 estates; this scenario is that follow-up, generalized as its own reusable pattern (an
 auto-apply retention **label** policy can use the identical `-AdaptiveScopeLocation` parameter
 set with `New-RetentionComplianceRule -ApplyComplianceTag` instead of
 `-RetentionComplianceAction`, see §7).

## 3. Why an adaptive scope, and why `Title` as the attribute

Purview offers two ways to scope a policy for retention: **static** (explicit locations/lists) and
**adaptive** (a daily-refreshed query against Entra attributes or SharePoint site properties)
. Adaptive scopes exist specifically to remove the maintenance burden static
scopes carry for populations that change, the documented advantages include no per-policy item
limits, resilience to org changes that don't get reflected in group membership, and support for
Entra administrative units. `Title` (Job title) is a documented **Users**-type
adaptive scope attribute, and it's the exact attribute Microsoft's own
"executives" example uses, this scenario reuses that grounded example rather
than inventing a new one.

## 4. Object model, and the genuine parameter-surface gap

```mermaid
sequenceDiagram
    participant Script as New-AdaptiveScopeRetention.ps1
    participant SCC as Security & Compliance PowerShell

    Script->>SCC: Get-AdaptiveScope (scope exists?)
    alt not found
        Script->>SCC: New-AdaptiveScope -Name -LocationType User -FilterConditions {Title in [...]}
        Note over SCC: Query re-evaluated daily; up to 5 days to fully populate
    end
    Script->>SCC: Get-RetentionCompliancePolicy (policy exists?)
    alt not found
        Script->>SCC: New-RetentionCompliancePolicy -Name -AdaptiveScopeLocation <scope name>
    end
    Script->>SCC: Get-RetentionComplianceRule -Policy (rule exists?)
    alt not found
        Script->>SCC: New-RetentionComplianceRule -Policy -RetentionDuration -RetentionComplianceAction Keep -ExpirationDateOption
    end
    Note over SCC: Policy applies to whichever locations the adaptive scope's LocationType covers
```

**The gap, disclosed rather than guessed:** `New-RetentionCompliancePolicy`'s `AdaptiveScopeLocation`
parameter set syntax is:

```
New-RetentionCompliancePolicy [-Name] <String> -AdaptiveScopeLocation <MultiValuedProperty>
    [-Applications <MultiValuedProperty>] [-Comment <String>] [-Enabled <Boolean>] ...
```

, no `-ExchangeLocation`/`-OneDriveLocation`/`-SharePointLocation`/`-TeamsChatLocation` parameters
appear in this parameter set the way they do in the `Default` (static) parameter set
. The portal's own documented flow implies granular control ("select one or more
locations. The locations that you can select depend on the scope types added")
, but no corresponding PowerShell parameter for restricting *which* of the
scope's covered locations (for a `User`-type scope: Exchange mailboxes, OneDrive accounts, Teams
chats/private-channel messages, Viva Engage user messages, Teams call logs, Copilot experiences,
Enterprise/Other AI apps) a given policy actually applies to was found in this
cmdlet's reference. **This build does not guess an answer.** `README.md` Section 11 and the deploy
script's `.NOTES` carry the same disclosure, tagged `VERIFY (pilot tenant)`: confirm in a lab
tenant whether an adaptive-scope policy created via PowerShell applies to all `User`-type locations
by default, or whether the portal's per-policy location selection is enforced some other way (e.g.
a property settable only via `Set-RetentionCompliancePolicy` after creation, not found either), 
before assuming "Exchange + OneDrive only" in a customer deployment.

## 5. Idempotency and safety posture

Create-or-report, matching this repo's established retention-object convention: the deploy script
locates the scope, policy, and rule by name and, if present, reports and moves on rather than
silently mutating them (a query or retention-duration change is a deliberate, reviewed action, not
an automatic reconciliation). `-DryRun` substitutes for the non-functional S&C `-WhatIf`. Because
this scenario uses a `Keep`-only action rather than a record label, the safety posture is
proportionally lighter than the sibling scenario's (no irreversibility warnings, no "test in a lab
tenant before deploying a WORM control"), but the deploy/validate output still calls out the two
genuine sources of delay (adaptive scope population, up to 5 days; policy distribution) so an
operator doesn't mistake "just deployed" for "already enforced."

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope type | `User` (`-LocationType User`), attribute `Title` | Matches Microsoft's own documented "executives" example directly (§3) |
| Query shape | Simple `-FilterConditions` hashtable (`Conditions`/`Conjunction`) | Matches the one fully-worked example in Microsoft's own `New-AdaptiveScope` reference; `-RawQuery` (OPATH) is the advanced-query alternative, noted but not used by default |
| Retention action | `Keep` (not a record/regulatory record label) | This scenario's contribution is *adaptive targeting*, not immutability, record-strength retention is the sibling scenario's job |
| Location-scope granularity | Not restricted beyond the adaptive scope's own `LocationType` | No documented parameter for narrower control was found, disclosed as a genuine gap (§4) rather than a fabricated parameter |
| Idempotency | Create-or-report (no silent update) | Consistent with this repo's established retention-object convention |
| Rollback | Disable → delete policy+rule (releases retention, not a record) → optionally remove the scope only if unreferenced | Lower-irreversibility control; still respects that adaptive scopes are shared, reusable objects (`rollback.md`) |

## 7. Non-goals

- **An adaptive-scope *auto-apply retention label* policy** (`New-RetentionComplianceRule
 -ApplyComplianceTag` instead of `-RetentionComplianceAction`), the identical
 `-AdaptiveScopeLocation` parameter set on `New-RetentionCompliancePolicy` supports it directly;
 this scenario builds the plain retention-policy variant as the clearer worked example and leaves
 the label variant as a companion follow-up (`PROGRESS.md`).
- **SharePoint-site or Microsoft 365 Group adaptive scopes** (`-LocationType Site` / `Group`), the
 `User`-type scope is the one Microsoft's own worked example uses; the other two scope types
 follow the same object model with different attributes (§3) and are a natural extension, not
 built here.
- **Administrative-unit-restricted scopes** (`-AdministrativeUnit`), supported by the config
 schema (left blank by default) but not exercised in the sample; relevant for MSSP/delegated-admin
 deployments.
- **Advanced query builder (`-RawQuery`, OPATH/KeyQL)**, noted as the alternative to the simple
 `-FilterConditions` builder for queries the simple builder can't express; not used by default.
- **Editing an existing scope's query or an existing policy's retention settings**, the deploy
 script reports and does not mutate; changes are a deliberate, reviewed action (`Set-AdaptiveScope`
 / `Set-RetentionCompliancePolicy`, out of scope here).

## References

1. Learn about retention policies and retention labels, "executives" adaptive-scope worked example, <https://learn.microsoft.com/purview/retention#adaptive-or-static-policy-scopes-for-retention>
2. Adaptive or static policy scopes for retention (overview), <https://learn.microsoft.com/purview/retention#adaptive-or-static-policy-scopes-for-retention>
3. Adaptive scopes, advantages, <https://learn.microsoft.com/purview/purview-adaptive-scopes#advantages-of-using-adaptive-scopes>
4. Adaptive scopes, scope types and supported attributes/properties table, <https://learn.microsoft.com/purview/purview-adaptive-scopes#configure-adaptive-scopes>
5. New-RetentionCompliancePolicy, AdaptiveScopeLocation parameter set syntax, <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancepolicy>
6. Create and configure retention policies, portal's adaptive-scope location-selection step, <https://learn.microsoft.com/purview/create-retention-policies#create-and-configure-a-retention-policy>
