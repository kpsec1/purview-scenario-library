# Four-Lens Review — Scan Credentials: Remaining Kinds

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; every **Fix** was applied to the scenario before this file was finalized (see
"Resolution" under each). One **Fail** was raised and resolved — it required correcting a claim in
a *different* scenario, the same pattern the parent scenario's own review established.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **`AmazonARN`/`ManagedIdentity` credentials have no Key Vault-side detective backstop at all —
   the draft's monitoring section understated this.** The parent scenario's compensating control
   for a silent `PUT`-as-replace re-point is *two* signals: the estate-wide inventory report, and
   Key Vault `AuditEvent` diagnostic logs (which catch a re-point from the vault side even when
   Purview's own audit log stays silent). Three of this fragment's five kinds inherit that second
   signal because they still reference a Key Vault secret. `AmazonARN` and `ManagedIdentity` do
   not — there is no secret, therefore no vault-side signal, ever, for those two kinds specifically.
   The original draft's §8 mentioned this only in passing ("can only be monitored by drift
   detection"), which understates that the estate-wide report isn't merely the *cheaper* signal
   for these two kinds, it is the *only* one.
   - **Resolution:** `README.md` §8 rewritten with a dedicated paragraph stating this plainly and
     recommending a daily (not weekly) inventory-report cadence for any tenant relying on either
     kind, plus a two-row runbook table giving each kind's actual triage path (an AWS-console
     escalation for `AmazonARN`; a UAMI-attachment/grant check for `ManagedIdentity`) since neither
     fits the parent scenario's Key Vault-centric five-step runbook at all.

2. **`ConsumerKeyAuth`'s plain-text `consumerKey` could leak into a `-WhatIf -Verbose` transcript.**
   The deploy script's `Invoke-PurviewPut` helper — copied structurally from the parent scenario's
   identical function — logs the full request body under `-WhatIf -Verbose` for operator visibility.
   For the parent scenario this is always safe: every field in its three kinds' bodies is either a
   name/reference or a `KeyVaultSecret` pointer, never a value worth protecting. This fragment
   breaks that invariant: `ConsumerKeyAuth`'s `consumerKey` is a genuine credential-adjacent value
   (a Salesforce Connected App's Consumer Key) written directly into the body as a plain string.
   The original draft reused the parent's logging code unchanged, meaning a dry run — explicitly
   framed everywhere else in this repo as the safe, side-effect-free way to preview a change — could
   print that value to a console or, worse, a CI pipeline's captured log.
   - **Resolution:** `Invoke-PurviewPut` gained an optional `-LogBody` parameter used only for the
     `-WhatIf` verbose preview; the credential-PUT call site now builds a redacted copy (consumerKey
     replaced with a placeholder string) for `ConsumerKeyAuth` specifically and passes it as
     `-LogBody`, leaving every other kind's logging behavior byte-for-byte unchanged. The real
     (non-`-WhatIf`) `PUT` never logs the body at all, for any kind, matching the parent scenario.

3. **The credential re-point risk, the vault-wide Key Vault grant blast radius, and the unpinned-
   `secretVersion` tradeoff are all inherited from the parent scenario, unchanged, for the three
   secret-bearing kinds here.** Reviewed and confirmed as correctly disclosed by reference rather
   than needing to be independently re-derived — `README.md` §11 points at the parent's §11 for the
   full text rather than duplicating it.
   - **Resolution:** No change needed.

4. **The deploy script cannot leak a secret value for the three secret-bearing kinds, structurally,
   same as the parent scenario.** Confirmed: no plaintext or `SecureString` parameter for any of
   `-SecretName`'s underlying value, `-ConsumerSecretName`'s underlying value, exists anywhere in
   this script — only Key Vault coordinates.
   - **Resolution:** No change.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **No runbook existed for the two kinds whose failure modes don't touch a Key Vault at all.** The
   parent scenario's five-step runbook assumes every failure eventually traces to "credential
   object, Key Vault, or data source." `AmazonARN` and `ManagedIdentity` failures never touch a Key
   Vault, so an operator following that runbook verbatim would waste a step. The original draft's
   §8 kind-specific table named *what* differs operationally but gave no ordered triage path.
   - **Resolution:** `README.md` §8 gained the two-row runbook table described in Red Team finding
     1's resolution — first check, then where to escalate, for each of the two kinds specifically.

2. **`validate/`'s `-CheckKeyVaultSecret` derived the Azure Key Vault name from
   `store.referenceName` (the Purview *connection* name), which is not guaranteed to equal the
   Azure vault's actual name.** The parent scenario's equivalent check derives the vault name from
   the Key Vault connection object's own `baseUrl` (a `GET` it already issued for check 1), which is
   authoritative. This fragment's `Test-KeyVaultSecretReference` helper originally took a narrower
   path — it didn't re-fetch the connection object, so it fell back to assuming the connection name
   and the vault name match, which is the common case but not a documented guarantee.
   - **Resolution (code fix, applied in a follow-up pass):** `Test-KeyVaultSecretReference` now
     takes `-Endpoint`/`-Token`/`-ApiVersion` and calls a new `Get-KeyVaultNameForConnection` helper
     that duplicates the parent script's own check-1 `GET .../scan/azureKeyVaults/{connectionName}`
     → derive-from-`baseUrl` sequence exactly, cached per connection name (`$script:
     KeyVaultConnectionCache`) so `ConsumerKeyAuth`'s two secret references — which commonly, but not
     necessarily, share a connection — only trigger one GET each. If the connection can't be found or
     carries no `baseUrl`, the check is skipped with an explicit `[WARN]` naming the connection,
     instead of guessing. Only the three secret-bearing kinds (`AccountKey`, `ConsumerKeyAuth`,
     `DelegatedAuth`) call this path; `AmazonARN`/`ManagedIdentity` never reference a Key Vault
     secret at all (Red Team finding 1), so there is nothing to derive for them.

3. **The two discriminator-literal `[WARN]`-not-`[FAIL]` severity, and the "structural verification
   only, the real proof is a scan run" closing disclaimer, are both inherited unchanged from the
   parent scenario.** Confirmed present and consistent.
   - **Resolution:** No change.

4. **`Remove-PurviewScanCredential.ps1`'s reused reference check correctly produces "not
   referenced" for `AmazonARN`/`ManagedIdentity` credentials — verified, not assumed.** Traced the
   parent script's `foreach ($prop in $tp.PSObject.Properties)` loop against `AmazonARN`'s `{
   roleARN: <string> }` and `ManagedIdentity`'s `{ principalId, resourceId, tenantId }` shapes: none
   of those properties' values carry a `.store.referenceName`, so the loop correctly finds no match
   and neither credential is ever reported as blocking a Key Vault connection deletion. This is the
   *correct* answer (they never reference one), not a false negative.
   - **Resolution:** No change — `rollback.md` states this explicitly so a reader doesn't need to
     trace the code themselves to trust it.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass (with one Fix applied)**

1. **Would I fund this? Yes.** It closes a named gap at low cost and, for two of the five kinds
   (`AmazonARN`, `ConsumerKeyAuth`), removes the *only* portal-only step blocking full automation
   for an entire source category — there was never a managed-identity alternative to route around
   for Amazon S3 or Salesforce. For `ManagedIdentity`, it scripts Microsoft's actual second-choice
   authentication method, which the parent scenario's own three kinds all rank below.

2. **Fix — the cross-team, and in one case cross-cloud, coordination cost was unstated.** The
   original draft named the Key Vault Secrets Officer coordination cost (inherited from the parent
   scenario) but didn't call out that `AmazonARN` and `ManagedIdentity` each introduce a *new*
   coordination dependency the parent scenario never had: an AWS IAM role (commonly owned by a cloud
   infrastructure team, not the Purview governance team) and an Azure user-assigned managed identity
   (an Azure identity-administration action). A CISO reading only the parent scenario's cost model
   would underestimate this fragment's rollout timeline.
   - **Resolution:** `README.md` §10 gained an explicit bullet naming both dependencies and why
     each sits outside the Purview governance team's normal scope.

3. **Residual risk, accepted and bounded: `ManagedIdentity`'s Preview status.** A production
   rollout built on a preview capability could be disrupted by a behavior change with no
   corresponding documentation update.
   - **Resolution:** Already disclosed at draft time in §3/§10/§11 and in the deploy script's own
     runtime `Write-Warning`, not just in a document a buyer might not open — reviewed and confirmed
     sufficient without further change.

4. **Governance point: this fragment doesn't create new incentive to move off managed identity —
   if anything, the opposite.** Unlike the parent scenario (which serves tiers 3–4 of Microsoft's
   credential priority order and had to explicitly guard against nudging customers away from SAMI),
   this fragment's `ManagedIdentity` kind *is* tier 2 — using it where SAMI is unavailable is
   already the recommended path, not a compromise.
   - **Resolution:** No change needed; `README.md` §2 already frames this correctly.

---

## 🟦 Microsoft Product Owner

**Verdict: Fail (resolved)**

1. **FAIL — the parent scenario's own README asserted a boundary this fragment now closes, and
   left it unresolved.** `scan-credential-key-vault-backed/README.md` §11 stated "Five credential
   kinds are out of scope" and left `ManagedIdentity` as an open "reasonable future fragment"
   suggestion. Shipping this fragment without updating that bullet would repeat exactly the
   consistency failure the parent scenario's *own* review round flagged as a Fail against two of
   *its* siblings ("a new folder does not retract an old assertion").
   - **Resolution:** `scan-credential-key-vault-backed/README.md` §11's bullet rewritten in place as
     a RESOLVED entry pointing at this scenario, and both scenarios' "Related scenarios" sections
     cross-link each other. `scan-credential-inventory-report/README.md`'s "Related scenarios"
     section also updated to note it required no changes to already support these five kinds.

2. **Correct feature for the job, and grounded per-kind against real source-type documentation, not
   just the generic REST reference.** Every one of the five kinds' "who actually uses this" claims
   in §2/§6 is cited against a specific Microsoft Learn source-connector page (Amazon S3, Salesforce
   via the credentials overview page, Microsoft Fabric, Power BI) rather than inferred from the REST
   schema alone — matching or exceeding the grounding depth of the parent scenario's own three kinds.

3. **Licensing is accurate** — no new metered Purview consumption; the `ManagedIdentity` preview
   caveat is stated as a licensing-adjacent risk (no SLA) rather than omitted.

4. **No deprecated paths.** Portal terminology matches the current Microsoft Purview portal
   (**Data Map → Source management → Credentials**), consistent with the parent scenario.

5. **Not reinventing a native capability**, and — notably — this fragment **declines** to reinvent
   one where it would have been tempting: it does not attempt to derive or generate the `AmazonARN`
   kind's Microsoft account ID / external ID values despite the operational convenience that would
   offer, because no documented source for deriving them was found (§4, `README.md` §11). Inventing
   a derivation would have violated `AGENTS.md` §4 exactly the way the parent scenario's own
   discriminator-literal VERIFY was kept as an open parameter rather than silently hard-coded.

6. **Scope discipline is correct and, if anything, more conservative than it needed to be** — no
   consuming scan scenario is built for any of these five kinds, each documented as an explicit,
   named non-goal (`design.md` §7) rather than left implicit.

No remaining Fix/Fail after resolution.

---

## Round summary

| Lens | Verdict | Fix/Fail items | Status |
|---|---|---|---|
| 🔴 Red Team | Fix | 2 (Key Vault-side detection gap for two kinds, plaintext-consumerKey WhatIf-verbose leak) | Both resolved |
| 🔵 Blue Team | Fix | 2 (missing runbook for two kinds, vault-name-derivation assumption in `-CheckKeyVaultSecret`) | Both resolved (vault-name derivation code-fixed in a follow-up pass — see finding 2's Resolution) |
| 🎩 CISO | Pass | 1 (cross-team/cross-cloud coordination cost unstated) | Resolved |
| 🟦 Microsoft Product Owner | **Fail** | 1 (parent scenario's stale "out of scope" claim left uncorrected) | Resolved — corrected in place, cross-linked both directions |

Carried forward as `PROGRESS.md` follow-ups (not resolvable without a pilot tenant, or out of this
fragment's scope): whether the `AmazonARN` Microsoft account ID/external ID pair has any REST
source; `ManagedIdentity`'s current GA/preview status, to be periodically re-checked; and every
VERIFY the parent scenario already carries for the three secret-bearing kinds here (the two
`KeyVaultSecret` discriminator literals; omitted-`secretVersion` semantics).

**Update:** `-CheckKeyVaultSecret`'s vault-name derivation (Blue Team finding 2) has since been
code-fixed — see the Resolution under that finding above and `PROGRESS.md`'s DONE entry for this
follow-up. It no longer appears in the carried-forward list.
