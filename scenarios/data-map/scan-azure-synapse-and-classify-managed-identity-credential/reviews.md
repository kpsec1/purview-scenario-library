# Four-Lens Review — UAMI Credential for the Azure Synapse Workspace Scan

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. This is
the third and last of three sibling scenarios; this round focuses on what's genuinely different or
newly discovered about the Synapse port, building on the pattern (and fixes) both predecessors
already established.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The three-part serverless grant model (workspace Reader + Storage Blob Data Reader + per-
   database enumeration login) means a partial grant against the UAMI can leave serverless scanning
   silently broken while dedicated scanning succeeds, with no way to tell from this scenario's own
   checks alone.** The original draft's §11 mentioned the three-part model inherited from the base
   scenario but didn't call out that *this scenario specifically* — by moving from a SAMI that may
   already have held all three grants to a UAMI starting from zero — is exactly the moment this
   partial-grant failure mode becomes most likely to actually occur (an operator granting the
   simpler Reader role and forgetting the two serverless-specific ones).
   - **Resolution:** `README.md` §11 gained an explicit bullet stating this plainly, and naming the
     only available detection method (inspecting a scan run's own error detail in the portal, since
     no Purview API exposes Azure IAM/SQL grant state).

2. **Verified the credential-kind-mismatch hard-stop (both siblings' own Red Team fix) was ported
   into this scenario's first draft.** Confirmed by direct code read:
   `deploy/New-AzureSynapseManagedIdentityCredentialScan.ps1`'s precheck throws on a confirmed kind
   mismatch (unless `-Force`) and only warns on the ambiguous 404 case.
   - **Resolution:** No change needed — confirmed correct from the first draft.

3. **Checked whether the workspace firewall requirement introduces a bypass path specific to the
   credential change.** Traced the base scenario's own design: the firewall setting gates network
   reachability, not authentication — unaffected by which identity (SAMI/UAMI) is used. No new
   bypass surface.
   - **Resolution:** No change — confirmed, not assumed.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Pass**

1. **The scan-to-credential-reference drift gap (no detective control beyond a scheduled
   `validate/` run) is identical to both siblings' own Blue Team finding.** Ported directly into
   `README.md` §8 from the first draft.
   - **Resolution:** No change needed.

2. **Verified the validate script's run-history check uses the confirmed nested
   `discoveryExecutionDetails.statistics.assets` shape**, matching both siblings (traced against the
   base Synapse scenario's own already-corrected validate script, not assumed).
   - **Resolution:** No change — confirmed correct.

3. **A single scan object covers both dedicated and serverless pools together (inherited from the
   base scenario's own one-scan-per-workspace model) — confirmed this scenario's validate script
   correctly reports one aggregate run status, not a false impression of per-pool-type granularity
   it cannot actually provide.** Traced: `validate/Test-AzureSynapseManagedIdentityCredentialScan.ps1`
   reports the scan's single most-recent run without claiming per-pool-type breakdown anywhere.
   - **Resolution:** No change — confirmed accurate, not overclaimed.

No Fix/Fail.

---

## 🎩 CISO

**Verdict: Pass**

1. **Would I fund this? Yes — arguably the strongest candidate of the three siblings for early
   adoption.** `scan-azure-synapse-and-classify/README.md` §2 already frames Synapse as a common
   aggregation point for sensitive data copied in from many upstream systems; narrowing the scanning
   identity's blast radius has proportionally higher value here than for a single Azure SQL
   Database.
   - **Resolution:** `README.md` §8 states this explicitly rather than repeating the sibling
     scenarios' generic "adopt selectively" language unchanged.

2. **Coordination cost is unchanged from both siblings** — one more UAMI to provision, grant
   (now across three grant types instead of one or two), and monitor.
   - **Resolution:** No change.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Fix — the base scenario's own grant-assignment steps were cited as equally UAMI-confirmed as
   the core REST claim, when only the REST claim is directly page-confirmed.** This fragment's core
   grounding is genuinely stronger than either sibling's: a worked JSON example on the base
   scenario's own canonical page explicitly shows `ManagedIdentity` as a valid `credentialType` for
   this exact scan `kind` (§1, `design.md` §1) — not inferred from a separate generic list, unlike
   both siblings. But the same page's IAM role-assignment and T-SQL grant *steps* use generic
   "Microsoft Purview account MSI" wording throughout, never explicitly naming UAMI as an alternative
   selectable principal the way the Database sibling's own page does. Drafting §3/§5 as if this
   distinction between "REST-level claim: directly confirmed" and "portal/T-SQL step wording: UAMI
   applicability inferred, not verbatim" didn't matter would have slightly overstated this
   fragment's grounding — the same category of finding the Managed Instance sibling's own review
   caught, applied here with more precision since this fragment's core claim needed no such caveat.
   - **Resolution:** `README.md` §3's Reader/Storage Blob Data Reader table rows and §11 both
     rewritten to state plainly which claim is which: the `credentialType` value is directly
     page-confirmed; the grant-assignment steps' UAMI applicability is mechanism-inferred (same
     generic Azure RBAC/SQL external-provider-user mechanism), flagged as an explicit VERIFY rather
     than presented as equally confirmed.

2. **Correct feature for the job, and the distinct scan `kind`/properties object were independently
   confirmed, not assumed identical to either sibling by naming convention.** Direct fetch of
   `AzureSynapseWorkspaceCredentialScanProperties` confirmed it carries **no**
   `databaseName`/`serverEndpoint` fields at all — a genuine structural difference from both
   siblings, correctly reflected in the deploy script (no such properties to preserve) rather than
   copy-pasted from either sibling's reconciliation body.

3. **The `resourceTypes` worked example this build incidentally discovered was correctly kept out of
   this fragment's scope** rather than opportunistically adopted mid-fragment — `design.md` §2 goal
   2 explains the reasoning (a scan-scoping behavior change is independent of an authentication-only
   fragment), and the discovery was still recorded as a `PROGRESS.md`/base-scenario-README follow-up
   rather than silently dropped.

4. **Licensing accurate; no deprecated paths; correctly scoped.**

No remaining Fix/Fail after resolution.

---

## Round summary

| Lens | Verdict | Fix/Fail items | Status |
|---|---|---|---|
| 🔴 Red Team | Fix | 1 (partial-grant failure mode understated for this specific transition) | Resolved — disclosed explicitly |
| 🔵 Blue Team | Pass | 0 | — |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 1 (grant-assignment step grounding conflated with the stronger core REST claim) | Resolved — distinguished explicitly, new VERIFY added |

Carried forward as `PROGRESS.md` follow-ups (out of this fragment's scope): the VERIFY raised above
(Synapse workspace grant-assignment steps' UAMI wording, pilot tenant or future Microsoft Learn
pass); the base scenario's own newly-updated `resourceTypes` follow-up (an explicit `-ResourceNames`
scoping parameter, `scan-azure-synapse-and-classify/README.md` §11); every VERIFY already carried by
`scan-azure-synapse-and-classify` itself (unchanged by this fragment); and
`scan-credential-remaining-kinds`'s own carried-forward `ManagedIdentity` GA/preview-status recheck.
With this fragment, all three siblings `scan-credential-remaining-kinds/README.md` §6 named as
directly wireable are now built.
