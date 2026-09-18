---
part: "design"
parent: "data-lifecycle-management/adaptive-scope-auto-apply-label"
---
## 1. Problem statement

Two patterns already exist separately in this repo: an **adaptive scope** targets a population that
changes over time by querying an Entra attribute instead of maintaining a static list
(`scenarios/data-lifecycle-management/adaptive-scope-retention/`), and an **auto-apply retention
label** locks matching content as a formal **record** instead of merely retaining it
(`scenarios/data-lifecycle-management/retention-labels-financial-records/`, which explicitly flags
adaptive scopes as an out-of-scope follow-up for large/dynamic estates in its own README §11). This
scenario is the documented combination of the two: a query-driven population gets a **record** label
auto-applied to its content, not a Keep-only retention action. `PROGRESS.md` records this as the
`adaptive-scope-retention` sibling's own flagged non-goal (design.md §7 there): "the identical
`-AdaptiveScopeLocation` parameter set on `New-RetentionCompliancePolicy` supports it directly."

## 2. Design goals

1. **Reuse, don't reinvent, both existing object models.** Adaptive scope creation mirrors
   `adaptive-scope-retention/deploy/New-AdaptiveScopeRetention.ps1` exactly (same cmdlet, same
   config shape); label + auto-apply mirrors `retention-labels-financial-records/deploy/
   New-FinancialRecordsRetention.ps1` (same cmdlets, same regulatory-record guard) — minus one
   corrected defect (§3).
2. **Share the adaptive scope object, don't duplicate it.** Adaptive scopes are documented as shared,
   reusable objects across retention policies (and Insider Risk Management, Communication
   Compliance). This scenario's config defaults to the *same scope name* as the `adaptive-scope-
   retention` sibling so a tenant that deploys both scenarios ends up with one scope, two policies —
   not two competing scopes with drifting queries. The deploy script detects and reuses an existing
   scope by name (`Get-AdaptiveScope`) rather than creating a duplicate.
3. **Be honest that this raises the consequence of scope error, not just its shape.** The Keep-only
   sibling releases retention cleanly on rollback (`Remove-RetentionComplianceRule` "causes the
   release of... retentions"). A record label does not release the same way — only a records manager
   can unlock/remove it, and rollback here explicitly does not attempt to. `README.md` §2/§11 and
   `rollback.md` state this plainly rather than reusing the Keep-only sibling's lower-irreversibility
   framing where it no longer applies.
4. **Correct a real defect found while grounding this fragment, rather than propagate it.** See §3.
5. **Same regulatory-record guard as the static-scope sibling.** Auto-apply does not support
   regulatory records regardless of whether the scope is static or adaptive — this is a property of
   auto-apply itself, not of adaptive scopes, so the guard carries over unchanged.

## 3. Grounding correction: `-Name` and `-ApplyComplianceTag` are mutually exclusive

While grounding this fragment against `New-RetentionComplianceRule`'s current Microsoft Learn
reference, its documented `-Name` parameter description states: **"You can't use this parameter with
the `ApplyComplianceTag` or `PublishComplianceTag` parameters."** The `ComplianceTag` parameter set
(the one `-ApplyComplianceTag` belongs to) does not list `-Name` at all — only `-Policy`,
`-ApplyComplianceTag`, and the optional `-ContentMatchQuery`/`-ContentContainsSensitiveInformation`/
`-ExpirationDateOption`/`-RetentionComplianceAction`/`-IRMRiskyUserProfiles`/
`-MachineLearningModelIDs`/`-PriorityCleanup` [[1]](#references).

`scenarios/data-lifecycle-management/retention-labels-financial-records/deploy/
New-FinancialRecordsRetention.ps1` passes **both** `-Name` and `-ApplyComplianceTag` in the same
`New-RetentionComplianceRule` call — a parameter combination that does not match any documented
parameter set and would not resolve at runtime. This build does not repeat that combination: the
rule created here omits `-Name` entirely when calling `-ApplyComplianceTag`, matching the
`ComplianceTag` parameter set as documented. The existing idempotency check
(`Get-RetentionComplianceRule -Policy <policy>`) already locates the rule by its policy, never by
name, so nothing else in this scenario (or, if corrected, the sibling) depends on the rule having an
explicit name. This defect against the sibling script is recorded as a follow-up in `PROGRESS.md`
rather than silently fixed here — fixing it is a change to a different, already-`DONE` fragment, out
of scope for this one (`AGENTS.md` §6).

## 4. Object model

```mermaid
sequenceDiagram
    participant Script as New-AdaptiveScopeAutoApplyLabel.ps1
    participant SCC as Security & Compliance PowerShell

    Script->>SCC: Get-AdaptiveScope (scope exists? - possibly already created by the Keep-only sibling)
    alt not found
        Script->>SCC: New-AdaptiveScope -Name -LocationType User -FilterConditions {Title in [...]}
        Note over SCC: Query re-evaluated daily; up to 5 days to fully populate
    end
    Script->>SCC: Get-ComplianceTag (label exists?)
    alt not found
        Script->>SCC: New-ComplianceTag -Name -RetentionAction Keep -RetentionDuration -IsRecordLabel $true
    end
    alt label.regulatory = true
        Note over Script: STOP - auto-apply not supported for regulatory records
    else label.regulatory = false
        Script->>SCC: Get-RetentionCompliancePolicy (policy exists?)
        alt not found
            Script->>SCC: New-RetentionCompliancePolicy -Name -AdaptiveScopeLocation <scope name>
        end
        Script->>SCC: Get-RetentionComplianceRule -Policy (rule exists?)
        alt not found
            Script->>SCC: New-RetentionComplianceRule -Policy -ApplyComplianceTag <label> [-ContentMatchQuery]
            Note over SCC: NOT -Name - documented mutually exclusive with -ApplyComplianceTag (§3)
        end
    end
    Note over SCC: Two independent delays stack: scope population (5 days) + auto-apply distribution (7 days)
```

Same genuine location-scope gap as the `adaptive-scope-retention` sibling: `New-
RetentionCompliancePolicy`'s `AdaptiveScopeLocation` parameter set has no `-ExchangeLocation`/
`-OneDriveLocation` equivalent, so which of the scope's `User`-type locations the policy actually
covers is not exposed as a documented parameter here either — carried forward as the same disclosed
`VERIFY (pilot tenant)`, not re-litigated or guessed differently for the label variant.

## 5. Idempotency and safety posture

Create-or-report for all four objects (scope, label, policy, rule) — consistent with both parent
patterns. Because a record label is higher-consequence than a Keep-only action, this scenario keeps
the financial-records sibling's stronger safety language (lab-tenant test, `-DryRun`, Records/Legal
sign-off) rather than the Keep-only sibling's lighter framing — and adds one new consequence unique
to the *adaptive* combination: an over-broad or stale `Title` query now locks the wrong population's
content as records, not just retains it. `rollback.md` states plainly that policy/rule rollback never
unlocks or removes an already-applied record label — that action requires a records manager and is
out of scope for this or any automated rollback here.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope reuse | Default to the same scope name as `adaptive-scope-retention` | Adaptive scopes are documented shared objects; avoids two scopes with drifting queries targeting the same intended population |
| Label strength | Record (`IsRecordLabel: true`), not regulatory, by default | Auto-apply does not support regulatory records (Microsoft, corroborated in the financial-records sibling); regulatory stays a create-only, publish-distributed path |
| Rule parameters | `-Policy -ApplyComplianceTag [-ContentMatchQuery]`, no `-Name` | Matches the documented `ComplianceTag` parameter set exactly; corrects the sibling script's defect (§3) rather than repeating it |
| Content targeting | No default `-ContentMatchQuery` | Unlike the financial-records sibling (content-signal matching within a broad static site), this scenario's targeting is entirely population-based (the adaptive scope) — matching the Keep-only sibling's own no-query design |
| Idempotency | Create-or-report for all four objects | Consistent with this repo's established retention-object convention |
| Rollback | Disable → delete policy+rule (stops future auto-apply only) → optionally remove the scope only if unreferenced. Label and labeled content are never touched. | A record label's irreversibility is a different, stronger failure mode than the Keep-only sibling's — rollback must not imply it undoes labeling that already happened |

## 7. Non-goals

- **Regulatory records via this scenario's own policy/rule** — not supported by auto-apply at all;
  use `scenarios/data-lifecycle-management/publish-labels-for-manual-application/` for that
  distribution path, same as the financial-records sibling.
- **Fixing the `-Name`/`-ApplyComplianceTag` defect in the financial-records sibling's own script** —
  recorded as a follow-up in `PROGRESS.md`, not fixed here (a different, already-`DONE` fragment).
- **`-LocationType Site` / `Group` adaptive scopes, or non-`Title` attributes** — same non-goal as the
  Keep-only sibling; this scenario reuses that sibling's exact scope shape by design (§2).
- **Content-condition auto-apply (trainable classifiers, sensitive-information-type matching)** — the
  financial-records sibling already demonstrates `-ContentMatchQuery`; this scenario's config exposes
  the same field but defaults it empty, since the point being demonstrated here is population-based
  (adaptive-scope) targeting, not content-signal targeting.
- **Unlocking or removing an already-applied record label** — a records-manager action, out of scope
  for this scenario's automation (`rollback.md`).

## References

1. New-RetentionComplianceRule — `-Name` parameter description ("You can't use this parameter with the ApplyComplianceTag or PublishComplianceTag parameters") and the `ComplianceTag` parameter set — <https://learn.microsoft.com/powershell/module/exchangepowershell/new-retentioncompliancerule>
