---
part: "rollback"
parent: "ediscovery/location-scoped-legal-hold"
---
This hold mechanism has **no reversible "pause" on v1.0** (`design.md` §4) — `enablePolicy`/
`disablePolicy` exist only in the beta Graph namespace, which this library's automation does not
call (`docs/automation-surface.md` §2). Every stage below is either narrowly scoped (release one
location) or fully destructive (delete the whole policy); there is no "turn it off, turn it back
on next week" middle ground the way there is for a custodian's hold release/re-apply cycle in the
sibling scenario. **Confirm with counsel that the preservation duty for the affected location(s)
has actually lapsed before running any stage below on a matter that involved actual litigation or
a regulatory inquiry** — this is a legal determination, not one this scenario's scripts can make
for you.

Both removal paths carry Microsoft's own documented warning, quoted directly:

> "Turning off a hold policy might result in the permanent deletion of any content currently
> being preserved." — and, for delete: "When you delete a hold policy, you remove all associated
> holds and release all sites and mailboxes. This action might result in permanent deletion of
> any content currently being preserved."
> [[reference below]]

There is no v1.0 "turn off" action distinct from delete/remove (`design.md` §4) — the stages below
are the only two supported release mechanisms.

## Recommended sequence

### Stage 1 — Release specific locations (targeted, not reversible for that location)

```powershell
./deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
    -UserSourceEmail 'payments-compliance-dl@contoso.com' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

or, for a site:

```powershell
./deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
    -SiteSourceUrl 'https://contoso.sharepoint.com/sites/PaymentsTeam' `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Removes the hold on the named location(s) only — the policy, its other locations, and the case
are untouched. **Not the same as the custodian scenario's `release` action**: there is no
equivalent "re-apply" call for a single location short of re-running
`deploy/New-EdiscoveryLocationHold.ps1`, which re-adds the source as a brand-new `userSource`/
`siteSource` object (a new `id`, holding content again from that point forward — it does not
retroactively re-cover the gap while the location was unheld). Use this stage when one location's
preservation obligation has definitively ended (the distribution list was disbanded, the shared
mailbox was decommissioned) but the matter itself is still active.

### Stage 2 — Delete the entire hold policy (all locations, not reversible)

```powershell
./deploy/Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId -DeleteHold `
    -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

Releases **every** location in the policy at once and removes the policy object itself. The
script emits an explicit warning (quoting Microsoft's own documentation, above) before this runs.
There is no "undo" — re-establishing the hold means re-running
`deploy/New-EdiscoveryLocationHold.ps1` against a new hold policy, referencing
`deploy/policy/location-hold-definition.json` again as the configuration source of truth. This
does not close or delete the case itself — see the sibling scenario's own
`deploy/Remove-EdiscoveryPremiumLegalHold.ps1`/`rollback.md` for case-level close/delete stages,
which apply identically to a case holding this scenario's location-scoped hold.

## What rollback does **not** undo

- **Mailbox/site content itself.** Removing a source or deleting the policy removes *eDiscovery's*
  preservation of that location — it does not delete anything, and it does not restore anything.
  Whatever normal retention/deletion policy would otherwise apply to that mailbox or site (if any)
  resumes governing it once the hold is gone. Per Microsoft's own warning above, if nothing else
  was independently preserving that content, it can become **immediately eligible for permanent
  deletion** the moment the hold is removed — this is the sharpest practical difference from the
  custodian scenario's `release`, which does not carry the same explicit permanent-deletion
  warning in Microsoft's documentation.
- **Distribution-list membership changes that occurred while the hold was active.** If a
  distribution-list `userSource` was relying on server-side expansion (§11's VERIFY), anyone who
  left the list before the hold was removed was preserved only for their time as a member — this
  scenario's automation has no visibility into list-membership history to reconstruct who was
  covered when.
- **Audit log entries.** Every source-removal and policy-delete action is itself an audited event
  in the Microsoft 365 unified audit log, independent of the hold's own lifecycle — rollback of
  the *control* does not roll back the *record that it existed*.

## Verification after rollback

Re-run `validate/Test-EdiscoveryLocationHold.ps1` against the case/hold (Stage 1) and confirm the
expected location(s) are no longer found among the hold's `userSources`/`siteSources` — the
validate script will report `FAIL` for a location still expected to be present, or simply won't
find the hold policy at all after Stage 2 (both are expected states post-rollback, not
validate-script bugs). For Stage 2, also confirm in the Purview portal's **Hold policies** tab
that the policy no longer appears.

Reference: Manage holds in eDiscovery (Turn off / Delete a hold policy, permanent-deletion
warnings verbatim) — <https://learn.microsoft.com/purview/edisc-hold-manage#turn-off-a-hold-policy>
