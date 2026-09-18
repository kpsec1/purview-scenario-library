---
part: "rollback"
parent: "ediscovery/gdpr-dsr-fulfillment"
---
This scenario creates three kinds of state: Graph objects (case/custodian/userSource/search), the
ledger file, and, only if a hand-off script ran, whatever that sibling scenario's own rollback
covers (a review set/export, or a purge). Each is staged separately below.

## Recommended sequence

### Stage 1, Fulfillment rollback (if a hand-off script already ran)

- **Access/Portability** (review set/export): follow
 `premium-legal-hold-and-export/rollback.md` unchanged, the review set and export package are its
 objects, created under this scenario's case/search but governed by that scenario's own rollback
 guidance.
- **Erasure** (purge): follow `search-and-purge-data-spillage/rollback.md` unchanged. **A
 `PermanentlyDelete` purge cannot be undone**, see that document's own warning; this applies
 identically to a DSR erasure request.
- **Rectification/Restriction/Objection**: no Purview-side rollback exists, since no Purview-side
 fulfillment action was taken (`design.md` §6). Any correction was made directly in the system of
 record and is that system's own rollback concern.

### Stage 2, Remove the custodian userSource / custodian (rarely needed)

```powershell
# Only if the custodian was added in error (e.g., wrong data subject identified at intake).
Remove-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $caseId -EdiscoveryCustodianId $custodianId
```

Since this scenario never applies a hold, there is no release-hold step to run first, unlike
`premium-legal-hold-and-export`'s rollback, which must release the hold before the custodian can be
removed. Removing the custodian also removes its userSource.

### Stage 3, Close or delete the case

```powershell
# Close: case record remains, reopenable later via the Purview portal case Actions menu.
Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId -BodyParameter @{ status = 'closed' }

# Delete: permanently removes the case and its custodian/search/operation history. No "undo."
Remove-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $caseId
```

**Close, don't delete, once a request is fulfilled.** The case is part of the organization's
Article 5(2) accountability record for how it responded to the request, closing preserves that
evidence (what was searched, exported, or purged, and when) the same way
`search-and-purge-data-spillage/rollback.md` recommends for its own incident cases. Delete only once
your organization's own DSR-record retention period for this request has been satisfied.

### Stage 4, The ledger entry

Do **not** delete a ledger entry when a case is closed or deleted. Update its `status` to `Closed`
instead:

```powershell
./deploy/New-DsrRequest.ps1 -DefinitionPath <the original definition file> `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -Status Closed
```

The ledger entry, request received date, due date, extension history, status, is itself part of
the accountability record; removing it destroys the evidence that the request was tracked and
answered on time. If a ledger entry was created in genuine error (for example, a duplicate
`requestId` from a re-submitted intake form), edit `dsr-ledger.json` directly rather than through
the script, and note the correction in your own change log, this scenario's script has no
`-RemoveEntry` switch, deliberately, since removing SLA-tracking history is not a routine operation.

## What this rollback cannot do

- **Reverse a completed Erasure (purge).** See `search-and-purge-data-spillage/rollback.md`.
- **Undo a correction made outside Purview** for a Rectification request, that's the system of
 record's own history/versioning, not this scenario's.
- **Retract an export package already delivered to the data subject** for an Access/Portability
 request, once delivered, it's out of this scenario's (and Microsoft's) control.
- **Tell you whether closing or deleting a given case is the right call.** That's a records-
 retention/accountability decision for the organization, informed by §9 of `README.md` and Stage 3
 above, not something this scenario's scripts can decide for you.
