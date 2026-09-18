---
part: "rollback"
parent: "data-map/scan-credential-remaining-kinds"
---
## This scenario reuses the parent scenario's delete script, unmodified

`scenarios/data-map/scan-credential-key-vault-backed/deploy/Remove-PurviewScanCredential.ps1` issues
a plain `DELETE {endpoint}/scan/credentials/{credentialName}`, it never inspects `typeProperties`,
so it deletes a credential created by this scenario exactly the way it deletes the parent's own
three kinds. No second delete script exists in this folder; write one would duplicate working code
for no functional gain (`design.md` §6).

```powershell
../scan-credential-key-vault-backed/deploy/Remove-PurviewScanCredential.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 's3-role-arn' -WhatIf
# then re-run without -WhatIf
```

## Before you start, the same consumer-inventory caveat as the parent scenario

No scenario in this library currently scans Amazon S3, Salesforce, Microsoft Fabric, or Power BI
(`README.md` §11), so for `AmazonARN`/`ConsumerKeyAuth`/`DelegatedAuth` credentials built from this
scenario alone, **Stage 0 in the parent scenario's `rollback.md` will most likely find zero
consumers**, there is nothing in this repo pointing at them yet. That changes the moment you wire
one into a scan built outside this library (or a future fragment here, `design.md` §7): run that
same Stage 0 inventory query before deleting a credential once any scan references it by name.

`ManagedIdentity` credentials are the one kind here that **does** overlap this repo's existing scan
scenarios in principle (`scan-azure-sql-and-classify` and siblings support UAMI authentication per
`README.md` §6), if you wire one in, treat it as a real consumer for Stage 0 purposes even though
that wiring isn't built by any fragment in this repo today.

## Removing the Key Vault connection (AccountKey / ConsumerKeyAuth / DelegatedAuth only)

If the Key Vault connection this scenario's `AccountKey`/`ConsumerKeyAuth`/`DelegatedAuth`
credentials reference is the **same shared connection** the parent scenario's `SqlAuth`/`BasicAuth`/
`ServicePrincipal` credentials use (the common case, one Key Vault connection, many credentials),
removing it is entirely the parent scenario's Stage 2 procedure: use
`Remove-PurviewScanCredential.ps1 -RemoveKeyVaultConnection`, which lists **every** remaining
credential referencing the connection (regardless of which scenario created it) before allowing the
delete, and refuses if any are found (override with `-Force` only when they're also being retired).

That reference check walks any `KeyVaultSecret`-shaped child of `properties.typeProperties`, 
it correctly finds `ConsumerKeyAuth`'s **two** references (`consumerSecret` and `password`) as two
separate hits against the same connection, and correctly finds nothing for `AmazonARN`/
`ManagedIdentity` credentials, which is the accurate answer for those two kinds (§ below).

## `AmazonARN` and `ManagedIdentity`: nothing to check against a Key Vault connection

Because these two kinds carry no `KeyVaultSecret` reference at all, deleting a Key Vault connection
never needs to consider them, and the parent script's reference check never will. Their rollback is
simply: delete the credential object (above). There is no Stage-2-equivalent step for these two
kinds.

## What rollback does **not** undo

Identical to the parent scenario's `rollback.md`, plus two kind-specific notes:

- **`AmazonARN`:** deleting the Purview credential does **not** delete or modify the AWS IAM role,
  or its trust policy naming Microsoft's account ID and external ID. That is AWS-side state, entirely
  outside this scenario and the Purview API. Remove it in the AWS console if this is a full teardown.
- **`ManagedIdentity`:** deleting the Purview credential does **not** delete the user-assigned managed
  identity, or remove whatever access grant it holds at the target source. Both are Azure-side
  resources this scenario never created, remove them separately (the Purview account's **Managed
  identities** blade, and the source's own IAM/RBAC surface) if this is a full teardown.
- Everything else, catalog assets, scan run history, the Key Vault secret's value (for the three
  secret-bearing kinds here), and any scan object referencing the credential, behaves exactly as
  documented in the parent scenario's `rollback.md`.

## Verification after rollback

```powershell
# Expect [FAIL] "Credential ... not found", which is the intended post-rollback result.
./validate/Test-PurviewScanCredentialExtended.ps1 `
    -PurviewAccountName 'contoso-purview' -TenantId $TenantId -AppId $AppId -ClientSecret $ClientSecret `
    -CredentialName 's3-role-arn'
```

Same inverted-exit-code caveat as the parent scenario: after a deliberate rollback, the non-zero
exit **is** the pass condition, don't wire this invocation into a pipeline gate without inverting
the expectation.
