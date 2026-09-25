# Four-Lens Review — UAMI Credential for the Azure SQL Managed Instance Scan

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. This
scenario ports several fixes and patterns already established by its Database sibling
(`scan-azure-sql-and-classify-managed-identity-credential`) from the start, so this round focuses on
what's genuinely different about the Managed Instance port, not re-litigating settled findings.

---

## 🔴 Red Team

**Verdict: Pass**

1. **The credential-kind-mismatch hard-stop (the Database sibling's own Red Team fix) was ported
   into this scenario's first draft, not bolted on after a repeat finding.** Verified by direct code
   read: `deploy/New-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1`'s precheck throws on a
   confirmed kind mismatch (unless `-Force`) and only warns on the genuinely ambiguous 404 case —
   identical logic to the fixed version of the sibling script, not the pre-fix version.
   - **Resolution:** No change needed — confirmed correct from the first draft.

2. **Checked whether Managed Instance's own network model (public endpoint vs. private, self-hosted
   IR) introduces a bypass path the Database sibling doesn't have.** Traced the base scenario's own
   `design.md`/`README.md`: this scenario (like the base scenario) only ever targets the public
   endpoint; self-hosted IR is out of scope for both SAMI and UAMI on this source type (confirmed via
   direct Microsoft Learn fetch during this build: "If you're using Private Endpoints to connect to
   Microsoft Purview, managed identity isn't supported"). No new bypass surface introduced by adding
   the UAMI credential path specifically.
   - **Resolution:** No change — confirmed, not assumed.

3. **The Key Vault-side detection gap for `ManagedIdentity` credentials (inherited from
   `scan-credential-remaining-kinds`) applies identically here.** Same finding as the Database
   sibling's Red Team finding 2 — reviewed and confirmed correctly disclosed by reference.
   - **Resolution:** No change needed.

No Fix/Fail — this round confirmed the sibling's fixes were ported correctly rather than finding new
issues.

---

## 🔵 Blue Team

**Verdict: Pass**

1. **The scan-to-credential-reference drift gap (no detective control beyond a scheduled
   `validate/` run) is identical to the Database sibling's own Blue Team finding 1.** Ported directly
   into `README.md` §8 rather than omitted and re-discovered later.
   - **Resolution:** No change needed — confirmed present in the first draft.

2. **Verified the validate script's Check 5 (scan run history) uses the same confirmed
   `discoveryExecutionDetails.statistics.assets` nested shape the base Managed Instance scenario's
   own build corrected (2026-09-04) after finding the sibling's original flat-property assumption was
   wrong.** This fragment's `validate/Test-AzureSqlManagedInstanceManagedIdentityCredentialScan.ps1`
   was written against the already-corrected shape from the start — traced against the base
   scenario's own `validate/Test-AzureSqlManagedInstanceDataMapScan.ps1` to confirm, not assumed by
   copying the Database sibling's (also-since-corrected) validate script.
   - **Resolution:** No change — confirmed correct.

No Fix/Fail.

---

## 🎩 CISO

**Verdict: Pass**

1. **Would I fund this? Yes, on the same selective-adoption basis as the Database sibling.**
   Managed Instance is frequently the landing zone for a *larger*, more consequential lift-and-shift
   migration than a single Azure SQL Database — arguably a stronger candidate for identity separation
   than the Database sibling, not a weaker one, given the typical blast radius of a compromised
   Managed Instance scanning identity.
   - **Resolution:** `README.md` §8 carries the same phased-adoption guidance as the Database
     sibling; no additional change needed.

2. **Coordination cost is unchanged from the Database sibling** — one more UAMI to provision, grant,
   and monitor. No new cost driver specific to Managed Instance.
   - **Resolution:** No change.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Fix — the Azure IAM Reader role-assignment portal walkthrough was cited as equally well-grounded
   for Managed Instance as for the Database sibling, when it is not.** The Database sibling's
   citation for "the Select box accepts your Microsoft Purview account name or UAMI" comes from a
   verbatim quote on the **Azure SQL Database** page's "Configure portal authentication" section.
   During this build's own grounding pass, a targeted search confirmed Managed Instance is listed
   among Microsoft's "Supported data sources for UAMI" and that its own registration page states
   "either managed identity will need permission to get metadata for the database, schemas and
   tables" — but no equivalent verbatim IAM-role-assignment walkthrough was found on the
   Managed-Instance-specific page. Drafting §5 step 3 and the prerequisites table as if this were
   independently page-confirmed (rather than mechanism-inferred from the same generic Azure RBAC
   role-assignment flow) would have overstated this fragment's grounding relative to its own
   `AGENTS.md` §4 standard.
   - **Resolution:** `README.md` §3 (prerequisites table), §5 step 3, and §11 all rewritten to state
     plainly what is directly confirmed (UAMI is a supported identity for this source; the same
     permission requirement applies to "either managed identity") versus what is inferred from the
     same underlying Azure RBAC mechanism rather than independently page-confirmed (the exact IAM
     role-assignment click-path). Flagged as a VERIFY in §11, not silently presented as equally
     grounded.

2. **Correct feature for the job, and the distinct scan `kind`/properties object were independently
   confirmed, not assumed identical to the Database sibling by naming convention.** Direct fetch of
   `AzureSqlDatabaseManagedInstanceCredentialScanProperties` during this build confirmed the same
   field names (`databaseName`, `serverEndpoint`, `collection`, `scanRulesetName`, `scanRulesetType`,
   `credential`) as the Database sibling's properties object, but as its own distinct schema, not
   inherited or shared — the base scenario's own `design.md` §4 had already established this same
   "genuinely different `kind`" discipline for the non-credential path, and this fragment holds the
   same bar for the credential path.

3. **Licensing accurate; no deprecated paths; correctly scoped** — same confirmations as the Database
   sibling, re-verified independently for this source type rather than assumed to carry over
   automatically.

No remaining Fix/Fail after resolution.

---

## Round summary

| Lens | Verdict | Fix/Fail items | Status |
|---|---|---|---|
| 🔴 Red Team | Pass | 0 (confirmed sibling's fixes ported correctly) | — |
| 🔵 Blue Team | Pass | 0 (confirmed sibling's disclosures and corrected REST shape both ported correctly) | — |
| 🎩 CISO | Pass | 0 | — |
| 🟦 Microsoft Product Owner | Fix | 1 (overstated grounding for the IAM role-assignment portal walkthrough on this specific source page) | Resolved — corrected in place with an explicit VERIFY |

Carried forward as `PROGRESS.md` follow-ups (out of this fragment's scope): the same UAMI wiring for
the third and last sibling, Azure Synapse dedicated SQL pools (`scan-credential-remaining-kinds/
README.md` §6); the VERIFY raised above (Azure IAM Reader role-assignment walkthrough for Managed
Instance UAMI, pilot-tenant or future Microsoft Learn pass); every VERIFY already carried by
`scan-azure-sql-managed-instance-and-classify` itself (unchanged by this fragment); and
`scan-credential-remaining-kinds`'s own carried-forward `ManagedIdentity` GA/preview-status recheck.
