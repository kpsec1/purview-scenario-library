---
part: "rollback"
parent: "dlp/accepted-domains-hygiene-check-on-premises"
---
## What there is to roll back

Same archetype as the parent `scenarios/dlp/accepted-domains-hygiene-check`: this scenario creates
**no object inside the on-premises Exchange organization, Exchange Online, or Microsoft Purview at
all**, no accepted domain, no DLP policy, no rule. Every call
`deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1` and
`validate/Test-OnPremisesAcceptedDomainsHygieneReport.ps1` make is read-only (`Get-AcceptedDomain`,
optionally `Search-AdminAuditLog`); `-CloudBaselinePath` is a plain file read, never a write.
"Rollback" here means four things, none of which touch on-premises Exchange, Exchange Online, or
Purview configuration:

1. Stop the scheduled execution of `deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1`.
2. Close/remove the on-premises remote PowerShell session and the automation identity's on-premises
   Exchange role assignment.
3. Decide what to do with the already-produced on-premises baseline, drift-log, and findings files.
4. Decide whether the parent cloud scenario should keep running on its own, it does not depend on
   this companion (`design.md` §6).

## 1. Stop the schedule

This scenario ships no scheduler-specific code (`README.md` §5), remove or disable whatever
recurring-execution mechanism was wired up (a Windows Task Scheduler task, an Azure Automation hybrid
runbook worker job, or equivalent) using that platform's own removal procedure. There is nothing
Exchange- or Purview-side to undo as part of this step.

## 2. Close the remote session and remove the role assignment

- Close any lingering on-premises Exchange remote PowerShell session
  (`Remove-PSSession $OnPremSession`, or let it time out) on whatever machine was running this
  scenario's scripts.
- Remove whatever on-premises Exchange role/role group (`README.md` §3, Organization Management or a
  narrower custom role group) was assigned to the account or service principal running this
  scenario's scripts. Standard on-premises Exchange role-group membership removal
  (`Remove-RoleGroupMember`, or the Exchange admin center equivalent), no scenario-specific step.
  This is a **separate** role-assignment system from the parent scenario's Exchange Online role
  removal (`README.md` §3, §11), removing one does not affect the other.
- If `-IncludeAuditAttribution` was used, confirm the identity has no residual on-premises
  audit-log-search role it doesn't need elsewhere.

## 3. Decide the fate of already-produced report files

- **On-premises baseline JSON, drift-log CSV, and per-run findings JSON files** are ordinary files
  this scenario wrote outside of Exchange/Purview, delete them, archive them, or leave them in place
  per the buyer's own data-retention policy, same guidance as the parent scenario's own
  `rollback.md` §3.
- These files are entirely separate from the parent scenario's own baseline/drift-log files
  (`design.md` §6), removing this scenario's files has **zero effect** on the parent's own state, and
  vice versa.
- The shared `KnownDomains.json` config is **not** owned by this scenario, it belongs to the parent
  scenario and should be kept regardless of whether this on-premises companion is decommissioned; see
  the parent's own `rollback.md` §3 for that file's disposition.

## 4. Decide whether the parent cloud scenario continues

Decommissioning this on-premises companion does **not** require decommissioning the parent
`accepted-domains-hygiene-check` scenario, the two run independently (`design.md` §3/§6) and neither
depends on the other's continued operation. A buyer who decommissions only this companion returns to
the parent scenario's own pre-existing limitation: the on-premises side of a hybrid tenant becomes
invisible again (`README.md` §2), the same gap this scenario was built to close. State that trade-off
explicitly if this companion is being removed while the hybrid deployment itself remains in place.

## What rollback does **not** undo

- **Any on-premises Exchange, Exchange Online, or Purview object.** There isn't one, see "What there
  is to roll back," above. Removing this scenario's automation has zero effect on the on-premises
  organization's actual accepted-domains configuration.
- **Findings already surfaced.** If a prior run reported an `UnexpectedTrustedDomain` or
  `CrossEnvironmentMismatch` finding, that underlying condition is unaffected by removing this
  scenario's monitoring. Confirm any open finding has been addressed (or consciously accepted) before
  decommissioning the check that surfaces it, same discipline as the parent scenario's `rollback.md`.

## Re-enabling later

Re-running `deploy/Export-OnPremisesAcceptedDomainsHygieneReport.ps1` after a rollback is safe at any
time: re-establish the on-premises remote PowerShell session (§2, reversed), re-assign the
on-premises Exchange role, point `-BaselinePath`/`-DriftLogPath` at either fresh files or the
previously-archived ones, and resume scheduling. If the on-premises baseline file was kept, the next
run resumes normal Added/Removed/Changed drift detection immediately; if it was deleted, the next run
is treated as a first run (`design.md` §6), a re-enablement after a long gap should be followed by a
second run soon after to re-establish real drift detection, same guidance as the parent scenario.
