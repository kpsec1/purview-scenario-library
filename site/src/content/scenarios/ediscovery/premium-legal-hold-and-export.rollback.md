---
part: "rollback"
parent: "ediscovery/premium-legal-hold-and-export"
---
Releasing a hold or closing/deleting a case has real preservation consequences (§2 of README.md)
, this document is staged, least-disruptive first, the same way this library's other rollback
docs are, but the stakes here are higher than most: releasing a hold too early can itself be a
spoliation event if the preservation duty hasn't actually lapsed. **Confirm with counsel that the
duty to preserve has ended before running any stage below on a matter that involved actual
litigation or a regulatory inquiry**, this is a legal determination, not one this scenario's
scripts can make for you.

## Recommended sequence

### Stage 1, Release specific custodians' holds (targeted, reversible)

```powershell
./deploy/Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId `
    -CustodianEmail 'dana.chen@contoso.com' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Releases the hold on the named custodian(s) only, the case, its other custodians, review set,
and exports are untouched. Reversible: re-run `deploy/New-EdiscoveryPremiumLegalHold.ps1` against
the same definition file (or a definition file naming just that custodian) to re-apply the hold.
Use this stage when one custodian's preservation obligation has ended (for example, they were
dismissed from the matter) but the case itself is still active.

### Stage 2, Release every held custodian, keep the case (partial rollback)

```powershell
./deploy/Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Omitting `-CustodianEmail` releases every custodian currently on hold. The case, its search(es),
review set(s), and any completed exports remain, this is the right stage when the matter has
settled or concluded but the case record (searches run, review-set tagging decisions, export
history) still has documented retention value for the org's own records.

### Stage 3, Close the case (all holds off, case record preserved)

```powershell
./deploy/Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId -CloseCase `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Closing turns off **every** hold in the case in one operation, including any custodian not passed
via `-CustodianEmail` in an earlier Stage 1 run, the script emits an explicit warning before this
runs. The case itself, its members, searches, review sets, and export history remain visible and
can be reopened later (Purview portal → case **Actions** → **Reopen case**)
[[reopen reference below]].

### Stage 4, Delete the case (not reversible)

```powershell
./deploy/Remove-EdiscoveryPremiumLegalHold.ps1 -CaseId $caseId -DeleteCase `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

`-DeleteCase` implies `-CloseCase`. Permanently removes the case and its holds/searches/review
sets. There is no "undo", re-establishing the matter means re-running
`deploy/New-EdiscoveryPremiumLegalHold.ps1` / `deploy/New-EdiscoverySearchReviewSetExport.ps1`
from scratch against a new case, referencing `deploy/policy/ediscovery-case-definition.json`
again as the configuration source of truth. Confirm the org's records-retention policy for closed
legal matters doesn't require keeping the case record (not just released holds) before choosing
this stage over Stage 3.

## What rollback does **not** undo

- **Custodian mailbox/OneDrive content itself.** Releasing a hold removes *eDiscovery's*
 preservation of that content, it does not delete anything, and it does not restore anything.
 Whatever normal retention/deletion policy would otherwise apply to that mailbox or site (if
 any) resumes governing it once the hold is gone.
- **Downloaded export packages.** Files already downloaded via
 `deploy/Get-EdiscoveryExportPackage.ps1` to local/pipeline storage are not touched by any stage
 above, they are outside eDiscovery's control the moment they're downloaded, and their
 retention/disposition (privileged production material, likely subject to its own legal-hold or
 confidentiality obligations toward outside counsel) is the operator's responsibility, not this
 scenario's.
- **Review-set content in Microsoft-managed Azure Storage**, once a review set exists, is not
 automatically deleted by releasing a custodian's hold or even closing the case, only by
 explicitly deleting the review set (portal) or the case itself (Stage 4).
- **Audit log entries.** Every case-close and case-delete action, and every hold-**policy**
 create/update/remove/retry action, is itself an audited event in the Microsoft 365 unified audit
 log, independent of the case's own lifecycle, rollback of the *control* does not roll back the
 *record that it existed*. Run `deploy/Export-EdiscoveryAuditTrail.ps1` before and after each
 rollback stage to capture the actor/timestamp for the record (README.md §8 has the open caveat on
 whether this scenario's own custodian-scoped release calls specifically are covered).

## Verification after rollback

Re-run `validate/Test-EdiscoveryPremiumCaseSetup.ps1` against the case (Stages 1-3) and confirm
the expected custodians now show a `HoldStatus` other than `success` (the validate script's
custodian check will report `FAIL` for a custodian still expected to be on hold, or simply won't
find the case at all after Stage 4, both are expected states post-rollback, not validate-script
bugs). For Stage 3/4, also confirm in the Purview portal that the case's **Status** shows
**Closed** (Stage 3) or that the case no longer appears in the **Cases** dashboard (Stage 4).

Reference: Create and manage cases in eDiscovery (Reopen/Delete case, status transitions), 
<https://learn.microsoft.com/purview/edisc-cases-manage>
