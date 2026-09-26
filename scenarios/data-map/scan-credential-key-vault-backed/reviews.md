# Four-Lens Review - Key Vault-Backed Scan Credential (SQL Auth / Service Principal)

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; every **Fix** was applied to the scenario before this file was finalized (see
"Resolution" under each). One **Fail** was raised and resolved - it required editing two *other*
scenarios, not this one.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Silent credential re-point, with no Purview-side detective control.** `PUT /scan/credentials/{name}`
   is create-or-replace. An operator - or an attacker - holding Data Source Administrator can
   rewrite an existing credential to point at a *different* Key Vault secret, or a different
   service principal, **under the same name**. No new object appears in any inventory, every scan
   referencing it keeps running, and those scans now authenticate as something else entirely.
   Against a data-discovery service with `db_datareader` across an estate, that is a meaningful
   pivot. The original draft's monitoring section only watched for *new* credentials appearing,
   which this attack never triggers.

   The grounding pass on detection was worse than expected and is worth stating precisely:
   Microsoft's enumerated Purview audit-event category table covers Collections, Role assignments,
   Scan rule sets, Classification rules, Scans, and Data sources - **credentials and Key Vault
   connections are absent from it** (`README.md` reference 13). The `Security` diagnostic-log
   category's own documented scope is role assignments and collection create/delete (reference 14).
   So no documented Purview log records this mutation.
   - **Resolution:** three changes. (a) `README.md` §11 gained a dedicated bullet stating the
     attack, the documented absence, and - honestly - the two caveats that keep it from being a
     proven impossibility (the category table is on a classic-portal page, and it says more
     categories will be added), carried as an explicit pilot-tenant VERIFY rather than asserted
     either way. (b) `README.md` §8's monitoring table gained a **credential re-point** row:
     running `validate/` with *all* `-Expected*` parameters supplied from a checked-in parameter
     file turns a re-point into a `[FAIL]`, which is the only compensating detective control
     available today. (c) The same bullet points at Key Vault `AuditEvent` diagnostic logging,
     which does record which identity read which secret, so a re-point at a secret outside the
     expected set is visible from the *vault* side even though it is invisible from the Purview
     side.

2. **The Key Vault grant is vault-wide over secrets, and the draft did not say so.** Neither
   permission model Purview supports can be scoped to individual secrets: an access policy grants
   **Get + List on secrets** across the vault, and **Key Vault Secrets User** is a vault-scoped
   role. Point Purview at a shared application vault and its managed identity can read *every*
   secret in it - database passwords, API keys, signing material - none of which has anything to do
   with scanning. The original draft listed the grant as a neutral prerequisite checkbox.
   - **Resolution:** `README.md` §3's prerequisites table now states the blast radius explicitly
     and recommends a **dedicated scan-credential Key Vault**; §5 step 2 repeats it at the point of
     action, where the operator is actually about to make the grant; §11 carries it as a standing
     limitation. `design.md` §3's trust-boundary table already scoped the Purview managed identity
     to "resolve the secret at scan time," which is now accurate only *because* the dedicated-vault
     recommendation is in place.

3. **Unpinned `secretVersion` hands silent control to whoever can write the vault.** The draft
   framed omitting `-SecretVersion` as a pure convenience ("rotation needs no Purview change"). The
   flip side is that anyone who can add a new version of that secret changes what every referencing
   scan authenticates as, with no Purview change and no Purview record - the same outcome as
   finding 1, reached without touching Purview at all.
   - **Resolution:** `README.md` §8's rotation table gained a **Tradeoff** column making both
     directions explicit, plus a paragraph giving the actual decision rule: omit the version when
     the vault's own access control and audit logging are the intended boundary; **pin it when
     Purview's configuration should be the change-control point** - notably when the vault is
     administered by a different team from the one that owns scanning.

4. **The deploy script cannot leak a scan secret, because it never receives one.** Reviewed and
   confirmed as designed rather than changed: `New-PurviewScanCredential.ps1` takes no plaintext or
   `SecureString` parameter for the target data source, only Key Vault coordinates. This is a
   structural property, not a discipline one, and it is the strongest thing about this fragment.
   - **Resolution:** No change. `design.md` §3 already documents why a "convenient" one-script
     version that also writes the secret and grants vault access was rejected.

5. **Caller client-secret handling** (`-ClientSecret` decrypted in memory to build the OAuth2 token
   body). Identical to every Data Map sibling in this repo.
   - **Resolution:** No change - Microsoft documents no certificate-based alternative for this
     data-plane token endpoint, and the script scopes the plaintext narrowly with
     `finally { $plainSecret = $null }`. Precedent set in
     `scan-azure-sql-and-classify/reviews.md`; not re-litigated here.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **A 404 was being reported as "does not exist" when it may mean "you can't see it."** The
   original draft's deploy-script throw and both validate-script checks said the object "does not
   exist" on any 404. The Scanning API is not documented to distinguish a missing object from one
   the caller lacks the collection role to read - so an operator whose service principal was never
   granted Data Source Administrator would be sent chasing a phantom missing object instead of a
   real RBAC gap. This is the single most likely first-run failure for this scenario, and the
   draft's error message pointed away from the cause.
   - **Resolution:** all three messages rewritten to say "not found (HTTP 404) - absent **OR** not
     visible to this identity" and to name the role to check first. The `Get-PurviewObjectOrNull`
     helper in `validate/` also now rethrows non-404 errors with the failing URI and message
     attached, so an auth/transport failure can never be silently rendered as "absent."

2. **No alerting exists; this is inherently a pull-based control.** Purview raises no alert when a
   credential breaks - the failure surfaces as a scan run failure, potentially days later, on the
   next schedule.
   - **Resolution:** `README.md` §8 now recommends running `validate/` **on a schedule** (weekly,
     or in the pipeline that deploys scans) rather than only at deploy time, and states the
     reasoning: it is the cheapest way to catch a secret that was deleted, disabled, or allowed to
     expire *before* a scan fails on it. `validate/` gained the 30-day secret-expiry warning
     specifically to make that scheduled run predictive rather than merely reactive.

3. **The triage path for "authentication failure" spans three systems.** An operator seeing a
   failed scan has to reason about the credential object, Key Vault, and the data source, and the
   draft gave no ordering.
   - **Resolution:** `README.md` §8 gained a five-step runbook that starts with the one command
     that discriminates the four common causes (`validate/ ... -CheckKeyVaultSecret`), then splits
     the residual case into the two legs this scenario cannot inspect (Purview→Key Vault,
     credential→data source) with the specific thing to check on each, and names the escalation
     trigger.

4. **`validate/`'s exit code inverts after a deliberate rollback.** Post-rollback, "credential
   absent" is the desired state but produces `[FAIL]` and exit 1.
   - **Resolution:** Called out in `rollback.md`'s verification section - the non-zero exit *is*
     the pass condition there - with an explicit warning not to wire that invocation into a
     pipeline gate without inverting the expectation. Also surfaced in the check's own message
     text so the operator sees it in context.

5. **`Remove-PurviewScanCredential.ps1` cannot see scan-object consumers.** The API documents no
   reverse lookup from credential to scans, so the script's safety check covers only other
   *credentials* sharing the Key Vault connection.
   - **Resolution:** Not fixable in code - disclosed instead, in the script's `.NOTES`,
     `README.md` §11, and `design.md` §7. More usefully, `rollback.md` gained a **Stage 0** that
     enumerates data sources and their scans and prints every consumer, explicitly marked "do not
     skip," so the gap is closed by procedure even though it cannot be closed by the script.

No remaining Fix/Fail after resolution.

---

## 🎩 CISO

**Verdict: Pass (with one Fix applied)**

1. **Would I fund this? Yes - it is cheap and it removes a manual step from an audited control.**
   No new licensing, no new metered consumption (§10), and the work is bounded. The real return is
   that Data Map onboarding becomes fully reproducible: a rebuilt Purview account or a newly
   onboarded collection no longer depends on someone remembering which portal blade they clicked.
   For an auditor asking "how is scan authentication configured," a scripted, diffable artifact is
   a materially better answer than a screenshot.

2. **The separation of duties is the headline, and it is real rather than aspirational.** Because a
   credential object holds only a reference, the deploy automation provably cannot read or set a
   secret value - it is not trusted with one. Three parties (Purview Data Source Administrator, Key
   Vault Secrets Officer, Purview managed identity) each hold one capability and none holds two.
   That maps cleanly onto SOC 2 CC6.1/CC6.3 and ISO 27001 A.5.15/A.8.2.

3. **Fix - the org-change cost was unstated.** The draft sold the separation of duties without
   noting that it *is* a coordination burden: onboarding a source and rotating a credential now
   require two teams. A CISO reading only the upside would be surprised by the first rotation
   ticket that stalls waiting on a vault owner.
   - **Resolution:** `README.md` §10 gained a "hidden cost worth naming in a business case" bullet
     stating it plainly - the control working as intended, but a process change, not a free one.
     `design.md` §3 closes on the same point.

4. **Residual risk, accepted and bounded: the two unconfirmed field literals.** A production-first
   deployment could fail on a field shape no Microsoft source pins (§11). This is the one place
   this fragment could waste an organization's time.
   - **Resolution:** mitigated rather than hidden. The two values are parameters with researched
     defaults, `validate/` prints the observed values and treats a mismatch as `[WARN]` (not
     `[FAIL]`, so operators don't learn to ignore the one check that can close the question), and
     `README.md` §5 now opens the script path with an explicit **pilot-first** callout describing
     the single portal-create-then-`GET` that converts the unknown into a known value. Residual
     risk after that: one pilot iteration, not a production outage.

5. **Governance point worth stating: this scenario makes it easier to move *off* managed identity.**
   A library that ships slick automation for credential-based scanning could nudge a team toward
   stored credentials where a managed identity would have worked - a net security regression.
   - **Resolution:** `README.md` §11 closes with an explicit "prefer managed identity when you can"
     bullet citing Microsoft's own "whenever possible" guidance, and states that this scenario
     exists for the cases where SAMI is genuinely unavailable - it is not a recommendation to
     migrate. `design.md` §7 lists "replacing managed identity where it works" as a non-goal. The
     summary in §1 frames the audience as specifically those who *cannot* use SAMI.

---

## 🟦 Microsoft Product Owner

**Verdict: Fail (resolved)**

1. **FAIL - this library now contradicts itself, and the old claim is the wrong one.** Two shipped
   scenarios state, in their READMEs, design docs, and script help, that **no documented REST
   endpoint exists for Purview credential creation** and that the portal is the only path:
   `scan-azure-sql-and-classify` (§11 VERIFY, §6 table, `design.md` §7) and
   `scan-on-premises-sql-server-and-classify` (§11, §3 prerequisites table, deploy script
   `.NOTES` and `.PARAMETER`). This scenario demonstrates the opposite. Shipping it without
   correcting them would leave a paying reader with two documents making incompatible claims about
   the same API - exactly the credibility failure `AGENTS.md` §4 exists to prevent. A new folder
   does not retract an old assertion.
   - **Resolution:** both scenarios corrected **in place**, marked with the correction date rather
     than quietly rewritten, so a returning reader can see what changed:
     - `scan-azure-sql-and-classify/README.md` §11 - the VERIFY struck through and replaced with a
       RESOLVED entry naming both endpoints and pointing at this scenario; §6's scan-`kind` table
       row rewritten to drop "via the Purview portal."
     - `scan-azure-sql-and-classify/design.md` §7 - non-goal rewritten to keep credential creation
       out of scope *there* (it is a shared, reusable object, not a per-scan concern) while stating
       plainly that it is no longer a manual step anywhere in this repo.
     - `scan-on-premises-sql-server-and-classify/README.md` §11 and §3 - corrected, including the
       specific misreading that produced the original error: Microsoft's disaster-recovery
       statement that "there's no API to extract credentials" is about **exporting existing secret
       material** (true, and by design), not about **creating the object**. That distinction is
       what the earlier build got wrong, and naming it is more useful than just flipping the claim.
     - `scan-on-premises-sql-server-and-classify/deploy/New-OnPremisesSqlServerDataMapScan.ps1` -
       `.NOTES` corrected and `.PARAMETER CredentialReferenceName` now points at this scenario's
       deploy script as the way to produce the value it requires.

2. **Correct feature for the job, and the right default.** Using the Scanning data plane's own
   Credential/Key Vault Connections operation groups is the native path; there is no PowerShell or
   Graph alternative (`Az.Purview` ships scan-object cmdlets only, which this build confirmed
   while searching for a credential cmdlet). Defaulting `-CredentialType` to `SqlAuth` matches the
   credential type Microsoft's own worked example for the consuming scan kind uses.

3. **Licensing is accurate.** Data Map is PAYG Azure consumption, not a per-user M365 entitlement,
   and this scenario correctly claims it adds none: configuration objects are not metered. The Key
   Vault per-transaction secret-operation cost is named rather than rounded to zero (§10).

4. **No deprecated paths.** Portal steps use the current Microsoft Purview portal navigation
   (**Data Map → Source management → Credentials**), not the classic governance portal's Management
   Center. API version `2023-09-01` is the version Microsoft's reference serves for these operation
   groups.
   - **One caveat surfaced and handled:** the audit-event category table cited for the Red Team
     finding above *is* on a classic-portal page (`data-gov-classic-audit-logs-diagnostics`).
     `README.md` §11 states that caveat explicitly rather than presenting a classic-portal
     enumeration as authoritative for the current experience.

5. **Not reinventing a native capability.** Purview offers no bulk credential import, no ARM/Bicep
   resource for credential objects, and no "test credential" API. This scenario wraps the
   documented endpoints and - importantly - does **not** invent a connection test to fill that gap;
   §7 states plainly that the only end-to-end proof is a scan run reaching `Succeeded`.

6. **Scope discipline is correct.** Three of eight credential kinds are scripted, and §11 explains
   the choice rather than implying the other five are unsupported - including the substantive
   observation that `ManagedIdentity` (user-assigned) has no Key Vault reference in its
   `typeProperties` at all, making it a structurally different build rather than a parameter tweak.

No remaining Fix/Fail after resolution.

---

## Round summary

| Lens | Verdict | Fix/Fail items | Status |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (re-point detection, vault-wide grant scope, unpinned-version tradeoff) | All resolved |
| 🔵 Blue Team | Fix | 3 (404-vs-403 messaging, scheduled validation + runbook, rollback consumer inventory) | All resolved |
| 🎩 CISO | Pass | 1 (org-change cost unstated) | Resolved |
| 🟦 Microsoft Product Owner | **Fail** | 1 (two sibling scenarios assert the opposite) | Resolved - both corrected in place |

Carried forward as open VERIFY items (recorded in `PROGRESS.md`, not resolvable without a tenant):
the two `KeyVaultSecret` discriminator literals; omitted-`secretVersion` semantics; whether
`PurviewSecurityLogs` emits undocumented credential-mutation events; and the pre-existing
`BasicAuth` ↔ Windows Authentication mapping inherited from the on-premises sibling.
