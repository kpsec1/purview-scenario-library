---
part: "design"
parent: "data-lifecycle-management/event-based-retention-and-disposition"
---
## 1. Problem statement

Employee-record retention obligations are usually anchored to **separation date**, not document
creation date, "keep for N years after the employee leaves." Purview's creation/modification-age
retention types can't express that; only **event-based retention** can, because the clock starts
when an admin/integration tells Purview a specific event happened for specific content, on a date
that can be past, present, or future. The second half of the problem is that
permanently deleting a departed employee's records shouldn't be a silent, unattended action, 
records governance and (in many organizations) legal defensibility expect a **human chain of
review** before disposal. This scenario builds the whole chain as code: the event type, the label,
the publish mechanism, and the per-employee event trigger, with a deliberately staged, two-reviewer
disposition review before anything is deleted.

## 2. Design goals

1. **Model the real trigger, not a proxy.** Use `-EventType`/`RetentionType EventAgeInDays` so the
 retention clock genuinely starts from the departure date, not from a workaround like a long
 creation-age duration that hopes to outlast tenure.
2. **Defensible disposition, not silent deletion.** `KeepAndDelete` + a **two-stage**
 `MultiStageReviewProperty` (HR Records, then Legal) so no single reviewer can unilaterally
 dispose of employee records, modeling a realistic sign-off chain, not this module's simpler
 single-`ReviewerEmail` sibling.
3. **Separate the one-time policy from the recurring operational action.** Deploying the event
 type/label/policy is a one-time (or rare) change; firing an event is something that happens
 *every time an employee leaves*. Two scripts, two different safety postures.
4. **Guard the dangerous default.** An event fired with no Asset ID scope retains **everything**
 under that event type, tenant-wide, the trigger script refuses this unless
 the caller explicitly opts in with `-Force`.
5. **Honest about undocumented edges.** `-AutoApprovalPeriod`, the `MultiStageReviewProperty`
 read-back shape, and whether `-ReviewerEmail`/`-MultiStageReviewProperty` can coexist are all
 genuinely undocumented on Microsoft's own reference pages (stub descriptions), flagged inline
 rather than guessed, per `AGENTS.md` §4.

## 3. Object model

```mermaid
sequenceDiagram
    participant Deploy as New-EventBasedRetentionAndDisposition.ps1
    participant SCC as Security & Compliance PowerShell
    participant HR as HR / Records manager (portal)
    participant Trigger as New-RetentionTriggerEvent.ps1

    Deploy->>SCC: Get-ComplianceRetentionEventType (exists?)
    alt not found
        Deploy->>SCC: New-ComplianceRetentionEventType -Name "Employee Departure"
    end
    Deploy->>SCC: Get-ComplianceTag (label exists?)
    alt not found
        Deploy->>SCC: New-ComplianceTag -EventType "Employee Departure" -RetentionAction KeepAndDelete -RetentionType EventAgeInDays -RetentionDuration 3650 -MultiStageReviewProperty <2-stage JSON>
    end
    Deploy->>SCC: Get-RetentionCompliancePolicy / Get-RetentionComplianceRule (exist?)
    alt not found
        Deploy->>SCC: New-RetentionCompliancePolicy -SharePointLocation <HR site>
        Deploy->>SCC: New-RetentionComplianceRule -PublishComplianceTag <label>
    end
    Note over HR: (up to 7d later) HR applies the published label + ComplianceAssetID to a departed employee's records
    Trigger->>SCC: Get-ComplianceRetentionEvent -Identity <EventName> (already fired?)
    alt not found
        Trigger->>SCC: New-ComplianceRetentionEvent -EventType "Employee Departure" -SharePointAssetIdQuery "ComplianceAssetID:<id>" -EventDateTime <date>
    end
    Note over SCC: retention clock starts (up to 7d sync); at end of duration, Stage 1 (HR) then Stage 2 (Legal) disposition review runs; final approval -> permanent deletion within 15 days
```

Four durable objects (event type, label, policy, rule) created once by the deploy script, plus one
recurring, append-only object (the event) created per employee by the trigger script. Labeling
individual content and setting its Asset ID is a manual, human step in between, deliberately not
scripted (see §7).

## 4. Why publish, not auto-apply

The sibling `retention-labels-financial-records` scenario **auto-applies** its label from a content
signal (a KQL match) because the label there targets an entire content *category* (financial
records) that a query can reliably identify. This scenario's label targets **one specific
employee's** records at a time, there's no reliable content signal that says "this document belongs
to employee 123456" other than a human records manager deciding it does and setting the Asset ID
accordingly. A **publish** policy (`-PublishComplianceTag`) is therefore the correct mechanism: it
makes the label available for records managers to apply, rather than trying to auto-match on content
that has no query-able "which employee" signal. This is consistent with Microsoft's own worked
event-based examples, which all describe records managers manually applying the label and entering
an Asset ID.

Publish-then-manually-apply has a consequence worth naming: content isn't a locked record until
someone actually applies the label. The recommended operating model (README §5) is to apply the
label during onboarding, so the only action required at departure is firing the event, otherwise
the window between "employee leaves" and "someone gets around to labeling their folder" is a window
where those records are as editable/deletable as anything else. This is a real, disclosed limitation
of a publish-based design, not a defect (`reviews.md` Red Team).

## 5. Two scripts, two safety postures

| | `New-EventBasedRetentionAndDisposition.ps1` | `New-RetentionTriggerEvent.ps1` |
|---|---|---|
| Cadence | Once (or rarely, for policy changes) | Every employee departure |
| Idempotency model | Create-or-report by name (standard for this repo's retention objects) | Create-or-report by event `-Name`, but **cannot** detect a differently-named duplicate for the same employee (no documented query-by-Asset-ID cmdlet) |
| Dominant risk | Over-scoping the publish policy's locations | Firing an unscoped event (retains **everything** of that event type) |
| Guardrail | `-DryRun`; create-or-report | `-DryRun`; **requires** `-EmployeeId` unless `-Force`; refuses to re-fire an identically-named event |

Splitting these into two scripts (rather than one script with a mode flag) keeps the recurring,
per-employee operational action small, auditable by its own `-EventName`, and safe to hand to an HR
integration without also granting it the ability to redefine the retention policy itself.

## 6. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Retention type | `EventAgeInDays` bound to a custom event type | The only mechanism that starts a clock from separation date, not content age |
| Retention action | `KeepAndDelete` | Required (with `Delete`) to use disposition review; `Keep`-only can't dispose |
| Disposition review | Two-stage `MultiStageReviewProperty` (HR, then Legal) | Realistic sign-off chain for a sensitive, irreversible disposal decision |
| Record flag | `IsRecordLabel = $true`, not `Regulatory` | Locks content until disposed, matching Microsoft's own worked example, without the sibling scenario's stronger, admin-proof regulatory-record commitment |
| Label mechanism | Publish (`-PublishComplianceTag`), not auto-apply | No reliable per-employee content signal; matches Microsoft's own worked event-based examples |
| Event scoping | `-SharePointAssetIdQuery "ComplianceAssetID:<id>"`, required unless `-Force` | Prevents the single most dangerous failure mode: an unscoped event retaining all content of that type |
| Auto-approval | Disabled (`null`) by default | `-AutoApprovalPeriod`'s cmdlet-level documentation is an unfilled stub; conservative default until confirmed |
| Rollback | Disable/delete policy; never force-remove the label, event type, or fired events | Fired events can't be canceled; record-labeled content stays locked regardless of policy state |

## 7. Non-goals

- **Auto-apply for this label.** See §4, no reliable per-employee content signal exists; publish is
 the correct mechanism here, not a limitation to fix later.
- **An HR-system connector or "missing events" reconciliation report.** `New-RetentionTriggerEvent.ps1`
 is the integration point an HR system (or a scheduled script reading an HR export) would call, 
 building that connector, and a report of departed employees with no matching fired event, is a
 distinct, documented follow-up (`PROGRESS.md`).
- **Publishing this repo's *financial-records* label for manual application.** A tracked, separate
 follow-up (`publish-labels-for-manual-application`), different label, different scenario.
- **File plan descriptors, adaptive scopes, and bulk multi-class file plans.** Same non-goals as the
 sibling starter; candidate follow-ups shared across the module.
- **Editing an existing label/policy/rule.** The deploy reports and does not mutate; changes are a
 deliberate, reviewed action given the event type's permanent binding (§6, README §8).

## 8. References

Same source set as `README.md` §12; not duplicated here.
