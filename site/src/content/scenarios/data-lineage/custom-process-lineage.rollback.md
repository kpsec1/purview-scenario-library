---
part: "rollback"
parent: "data-lineage/custom-process-lineage"
---
## Recommended sequence

Like the sibling *Close Gaps and Validate End-to-End Customer Data Lineage* scenario, none of this scenario's objects touch
live M365 traffic or the underlying source data. Removing them stops the Process node and its two
relationships from appearing in the lineage graph, but never touches either DataSet asset's actual
data or the nightly job that moves it.

### Remove the relationships and the Process entity

```powershell
./deploy/Remove-CustomProcessLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-process-lineage.json'
```

Deletes, in order: the `dataset_process_inputs` relationship, the `process_dataset_outputs`
relationship (both via `Relationship - Delete`, looked up by GUID through the same depth-2
`Lineage - Get By Unique Attribute` call the deploy script uses for its own existence check), then
the Process entity itself (via `Entity - Delete By Unique Attribute`). Anything already gone
(already deleted, or never successfully created) is reported and skipped rather than treated as an
error, so this script is safe to re-run.

Add `-WhatIf` first to see what would be deleted without deleting it.

## What rollback does **not** undo

- **The upstream or downstream DataSet assets themselves.** Neither was created by this scenario, so rollback doesn't touch either one.
- **The nightly transform job.** Not created, deployed, or managed by this scenario.
- **The custom Process type definition (`PurviewScenarioLibraryEtlProcess`) itself.** Deliberately
  left in place by `Remove-CustomProcessLineage.ps1`, for three reasons:
  1. **Type definitions are account-level objects, not scoped to this scenario's two assets.** If a
     organization models more than one custom job using the same type (a realistic next step this
     scenario's own design notes anticipates), deleting the type on every single-job rollback
     would break every other entity of that type.
  2. **Microsoft's own reference for `Type - Delete` does not document its behavior when the type
     has - or ever had - entity instances.** The exact REST path is now confirmed (2026-09-28
     maintenance pass, direct Microsoft Learn fetch - this page reference 18):
     `DELETE {endpoint}/datamap/api/atlas/v2/types/typedef/name/{name}`, returning `204 No Content`
     on success. But the reference page's only documented failure shape is a generic
     `AtlasErrorResponse` ("an unexpected error response") - it still does not say whether the call
     succeeds, no-ops, or errors against a type with existing (or previously-deleted-but-once-existing)
     instances. Scripting a delete-type action on that unconfirmed behavior risks either a confusing
     failure or, worse, silently succeeding in a way that surprises an organization that still has
     other entities of that type.
  3. **This mirrors the sibling scenario's own "never touch what you didn't create for this one
     purpose" discipline** - just applied to a type definition, a shared account-level object,
     rather than an asset.

  If an organization genuinely wants the type definition gone (e.g. decommissioning this scenario
  entirely, with no other entities of this type anywhere in the tenant), that's a manual,
  reviewed action: confirm zero remaining entities of the type first (there's no confirmed
  "count entities by type" REST call in this library's grounding - the safest manual check is
  Data Map's own search/browse UI filtered by type), then call
  `DELETE {endpoint}/datamap/api/atlas/v2/types/typedef/name/PurviewScenarioLibraryEtlProcess`
  directly (this page reference 18), verifying against a pilot tenant first that the call
  behaves as expected when zero entities of the type remain - its in-use behavior is still
  unconfirmed either way (see above).

## Manual portal alternative

If the automation identity's credential is unavailable, the Process entity and its relationships
can be reviewed (though not necessarily deleted end-to-end - Microsoft's portal delete-lineage-entry action is documented for relationships, per the sibling scenario's reference 6, but this
build did not independently confirm a portal action for deleting a custom *entity*) via the
upstream asset's **Lineage** tab. Prefer the script for a complete, auditable removal.

## Verification after rollback

```powershell
# Expect [FAIL] for the Process entity's presence, and consequently both hop checks - this is the
# correct, expected signal that rollback succeeded, not a problem to investigate.
./validate/Test-ProcessLineage.ps1 `
    -PurviewAccountEndpoint 'https://api.purview-service.microsoft.com' `
    -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -LineageDefinitionPath './deploy/lineage/customer-risk-summary-process-lineage.json'
```

The **type-exists** check will still report `[PASS]` after rollback - the type definition is left
in place, by design (see above). This is expected, not a rollback failure.

Re-run `deploy/New-CustomProcessLineage.ps1` at any time afterward to restore the full chain - it
will correctly detect the type as already present, upsert the Process entity, and re-create both
relationships.
