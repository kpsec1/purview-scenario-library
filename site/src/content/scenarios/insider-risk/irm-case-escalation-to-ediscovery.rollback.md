---
part: "rollback"
parent: "insider-risk/irm-case-escalation-to-ediscovery"
---
This scenario only adds two things to an already-escalated eDiscovery case: a provenance block in
the case `description`, and (if not already present) a custodian + mailbox/OneDrive hold for the
escalated user. Rollback here is correspondingly narrow — it never closes, reopens, or deletes the
eDiscovery case itself, and never touches the source Insider Risk Management case (design.md §4).
**Releasing a hold this scenario placed for an active investigation prematurely can itself be a
preservation failure — confirm with counsel that the IRM case's preservation duty has actually
lapsed before running Stage 2 below**, the same gate `scenarios/ediscovery/
premium-legal-hold-and-export/rollback.md` uses for its own hold releases.

## Recommended sequence

### Stage 1 — Remove the provenance block only (reversible, no preservation impact)

```powershell
./deploy/Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./deploy/policy/escalation-link-definition.json `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Strips the delimited "IRM ESCALATION PROVENANCE" block from the case description, leaving any
other text (an investigator's own escalation notes) and the custodian/hold untouched. Reversible —
re-run `deploy/Confirm-EdiscoveryEscalationLink.ps1` against the same definition file to re-stamp
it. Use this stage to clean up a mistaken or duplicate stamp (for example, the definition file was
run against the wrong case) without affecting preservation.

### Stage 2 — Also release the custodian's hold (destructive to preservation — counsel gate)

```powershell
./deploy/Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./deploy/policy/escalation-link-definition.json `
    -ReleaseHold -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Additionally calls the custodian `release` action for the user named in the definition file — the
same effect as running `scenarios/ediscovery/premium-legal-hold-and-export/deploy/
Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId -CustodianEmail <user>` directly against this
case. Only run this after the IRM case has resolved (benign or confirmed-violation-but-legal-review-
concluded) in a way that ends the preservation duty for this custodian specifically — not merely
because the escalation "seems done."

### Stage 3 — Case-level rollback (close/delete) — not this scenario's script

Closing or deleting the eDiscovery case itself is out of scope for `Remove-
EdiscoveryEscalationLink.ps1` (design.md §4) — use the sibling scenario's own staged rollback
directly against the case ID:

```powershell
../ediscovery/premium-legal-hold-and-export/deploy/Remove-EdiscoveryPremiumLegalHold.ps1 `
    -CaseId $caseId -CloseCase `  # or -DeleteCase for the permanent stage
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

See that scenario's own `rollback.md` for the full staged Close/Delete procedure and warnings.

## What rollback does **not** undo

- **The source Insider Risk Management case's own status or notes.** This scenario never wrote to
  the IRM case (no API exists to — design.md §4) and has nothing to roll back there. The IRM case's
  own system-generated "A case escalation" note (README.md §8) is permanent regardless of what
  happens on the eDiscovery side.
- **Custodian mailbox/OneDrive content itself**, or **downloaded export packages**, or **review-set
  content** — identical to the sibling scenario's own `rollback.md` "What rollback does not undo"
  section; nothing about this scenario's narrower scope changes those facts once a hold has been
  released or content collected.
- **The historical fact that a provenance block once existed.** Stage 1 removes the block from the
  live description, but the update itself is an audited eDiscovery case-modification event in the
  Microsoft 365 unified audit log (same caveat as the sibling scenario's README.md §8 on the
  custodian-hold-vs-hold-policy audit-operation gap — this scenario's plain `Update-
  MgSecurityCaseEdiscoveryCase` calls are ordinary case-modification audit events, not part of that
  open VERIFY).

## Verification after rollback

Re-run `validate/Test-EdiscoveryEscalationLink.ps1` against the definition file. After Stage 1,
expect the provenance-block check to report `FAIL` ("no provenance block found") — this is the
expected post-rollback state, not a validate-script bug. After Stage 2, additionally expect the
custodian's `HoldStatus` check to report `FAIL` (no longer `success`). After Stage 3
(close/delete), follow the sibling scenario's own `rollback.md` verification steps.
