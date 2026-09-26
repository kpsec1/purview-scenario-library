# Four-Lens Review - Data Map Scan On-Premises SQL Server and Classify Sensitive Columns

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round of
findings below; all **Fix** items were applied to the scenario before this file was finalized (see
"Resolution" under each). No **Fail** items were raised.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **The provisioning script prints a live registration secret to the console, and the original draft
   didn't warn about where that output can end up.** `New-OnPremisesSqlServerDataMapScan.ps1` retrieves
   and prints the integration runtime's auth key so an operator can paste it into the SHIR installer -
   but a key printed via `Write-Host` lands in whatever captures that stream, including a CI/CD job's
   persisted log, a chat-ops integration that echoes command output, or a transcript file. Anyone who
   later reads a leaked copy can register a rogue SHIR node that receives real scan jobs dispatched to
   this Purview account and sees the results this scenario classifies - a direct path to data
   exfiltration or to poisoning classification results, not a theoretical risk. The original draft
   noted the key is "shown once" but didn't say anything about where console output travels once it
   leaves the terminal.
   - **Resolution:** the script's own printed output now states this risk explicitly before showing the
     key (`deploy/New-OnPremisesSqlServerDataMapScan.ps1`), and `README.md` §11 adds a dedicated bullet
     instructing operators to run the initial provisioning call interactively, never inside a pipeline
     step that persists stdout, and to pass `-SkipIntegrationRuntimeAuthKey` on every subsequent
     reconciliation run so the key is never re-printed or rotated unnecessarily.
2. **A compromised SHIR host has a blast radius the original draft didn't size.** Every data source
   whose scan names the same integration runtime is only as trustworthy as that one host - compromise
   it, and an attacker can see or interfere with every scan job Purview dispatches through it, not just
   this scenario's. The original draft treated the SHIR purely as a connectivity mechanism without
   calling out this shared-chokepoint risk.
   - **Resolution:** `README.md` §8 now adds a "Blast-radius note" recommending dedicated SHIR hosts per
     sensitivity tier for tenants running multiple on-premises sources, rather than one shared runtime
     for everything.
3. **`db_datareader` plus `master`-database access remains a broad read grant relative to "classify a
   few columns."** Same inherent tension as every Data Map sibling scenario's own Red Team finding - not
   a bug in this script, and not changed here for the same reason: the mitigation is process (who
   approves the login/grant), not a scripting change. Carried forward from
   `scan-azure-sql-and-classify/reviews.md` by reference rather than re-litigated.
   - **Resolution:** Not changed - noted here for visibility, consistent with every sibling scenario's
     own disposition of the same finding.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **The automated validate script cannot check SHIR node health, and the original draft didn't explain
   the mechanism gap clearly enough.** `Test-OnPremisesSqlServerDataMapScan.ps1` confirms the
   integration runtime *resource* exists via the Data Map REST API, but that API's Get operation returns
   the resource definition, not live node connectivity/health - a scan can pass every automated check in
   this repo and still fail at run time because no SHIR node has actually registered and connected yet.
   The original draft mentioned this only in the script's own doc comment, not prominently enough in the
   README an organization actually reads first.
   - **Resolution:** `README.md` §7 now states this explicitly as check 2 (not buried in a script
     comment), naming the exact portal path to confirm node health manually, and the validate script's
     own Check 1 output prints the same caveat inline at run time so it's visible in every invocation,
     not just on first read.
2. **Incident-response runbook needed an on-premises-specific branch, not just a pointer to the Azure
   siblings' four causes.** The original draft's §8 pointed at the sibling scenarios' runbook without
   naming the failure causes unique to this data source (SHIR node down, credential password rotated
   out of sync, network path blocked in either direction, SHIR software expired).
   - **Resolution:** `README.md` §8 now leads with an on-premises-specific incident-response list ahead
     of any cause shared with the Azure siblings, since (a) SHIR-node-down is empirically the single
     most common failure mode for this source type and deserves to be checked first, not fourth.
3. **No SIEM/Sentinel integration mentioned.** Same as every sibling scenario - correctly out of scope
   for a single-scenario fragment, and Data Map has no alert stream to route regardless of source type
   or network location.
   - **Resolution:** No change needed - confirmed not a gap.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Cross-team coordination cost wasn't priced into the adoption narrative.** The SHIR host is
   overwhelmingly likely to be owned and patched by an infrastructure/on-premises-operations team, not
   whoever is standing up Purview Data Map - the same category of gap `scan-azure-sql-managed-instance-
   and-classify`'s own CISO review caught for its Directory Readers grant (a different team, a different
   approver). The original draft's §3 listed the SHIR as a technical prerequisite without calling out
   that it's also an ownership/coordination dependency that can silently rot (a host repurposed or
   decommissioned by a team that doesn't know Purview depends on it).
   - **Resolution:** `README.md` §3's SHIR row now states the ownership gap explicitly, and §8's review
     cadence adds a periodic check that the owning team still has this dependency on their own
     patching/decommissioning checklist.
2. **Risk reduction vs. cost:** proportionate, and arguably higher-value than any of the three Azure
   siblings alone. On-premises SQL Server is disproportionately likely to hold an organization's oldest,
   least-documented regulated data - exactly the "we thought we migrated everything" blind spot a
   cloud-only Data Map deployment leaves open.
3. **Board-level narrative:** "our automated data-discovery coverage now extends past the cloud estate
   to on-premises SQL Server, closing the most common blind spot in a partial cloud migration" is a
   materially stronger and more complete claim than any Azure-only sibling scenario supports alone.
4. **Change-management impact:** higher than any single Azure sibling (a physical host to provision,
   install software on, and maintain, on top of the Purview-side objects), but bounded and mostly
   one-time per SHIR (which can then serve multiple sources) - the staged rollback in `rollback.md`
   gives a proportionate off-ramp, including the option to leave the SHIR running for other sources
   while removing just this scenario's data source and scan.
5. **Would I fund this?** Yes - for any organization with a partial cloud migration, this closes a real,
   commonly-overlooked discovery gap, and the incremental engineering cost here is genuinely lower than
   the Azure siblings expected: this build scripted the SHIR resource + auth key via REST, something
   none of the three Azure siblings managed to automate for their own portal-only steps.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Two unconfirmed defaults needed to be flagged as VERIFY, not shipped as if confirmed.** This
   build's grounding pass could not find a worked example pairing `scanRulesetName: "SqlServerDatabase"`
   with `scanRulesetType: "System"` (unlike every Azure sibling, each of which confirmed its own system
   ruleset name via a worked example), and could not find a `CredentialType` enum value confirmed to
   represent "Windows Authentication" in the portal despite Microsoft documenting it as a supported
   authentication method for this source type.
   - **Resolution:** Both are stated as explicit VERIFY items in `README.md` §11 and the deploy script's
     `.PARAMETER`/`.NOTES` blocks, with the exact reasoning for the best-effort default chosen in each
     case (pattern-matching the sibling scenarios' confirmed naming convention; matching Microsoft's own
     worked PowerShell example's `CredentialType 'SqlAuth'` value) - not silently guessed, per `AGENTS.md`
     §4.
2. **No managed-identity authentication path is correctly identified as a genuine source-type
   difference, not an oversight.** Confirmed directly: Microsoft's REST/SDK definitions expose only a
   `SqlServerDatabaseCredential` scan kind for this source type, with no `...Msi` counterpart, matching
   the conceptual documentation's statement that on-premises sources are credential-only.
3. **The Kubernetes-based self-hosted data integration runtime is correctly scoped out, not conflated
   with the classic SHIR this scenario uses.** Confirmed as a separate, more recent Microsoft capability
   (container-based, SQL Server and Oracle only, SQL-authentication-only) rather than an alternative
   deployment mode of the same object this scenario provisions.
4. **No deprecated cmdlets/endpoints used.** All REST operations' API version (`2023-09-01`) were
   independently confirmed current via direct fetch of each operation's own canonical Microsoft Learn
   REST reference page, including the two Integration Runtimes operations - a capability this repo's
   Data Map scenarios hadn't scripted before this build.
5. **Reinventing-a-native-capability check:** this scenario is a direct, idiomatic use of the same Data
   Map REST surface the three Azure sibling scenarios use, extended only where Microsoft's own
   documentation says on-premises SQL Server genuinely differs (`design.md` §4) - not a parallel
   mechanism, and not an attempt to script around the SHIR software installation Microsoft itself treats
   as a manual host-level step.
6. **Licensing citation accuracy** - confirmed consistent with the three Azure siblings: PAYG/Azure-
   consumption billed for the Data Map scanning meter itself, with the SHIR host's own infrastructure
   cost correctly called out as a separate, scenario-specific line item in `README.md` §10 that the
   Azure siblings don't carry.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 3 (2 closed via explicit warnings/documentation, 1 confirmed as an inherent trust-model note carried from the sibling scenarios) | Closed |
| 🔵 Blue Team | Fix | 3 (2 closed via README/script visibility fixes, 1 confirmed correctly scoped) | Closed |
| 🎩 CISO | Fix | 1 closed (cross-team coordination cost made explicit); Pass on all other dimensions | Closed |
| 🟦 Microsoft Product Owner | Fix | 1 closed (two defaults flagged as explicit VERIFY rather than shipped as confirmed); 5 confirmed correct, including a first-in-this-repo automation of the integration-runtime layer itself | Closed |

All Fix items from this round are resolved in the current state of `README.md`, `design.md`,
`deploy/New-OnPremisesSqlServerDataMapScan.ps1`, `deploy/Remove-OnPremisesSqlServerDataMapScan.ps1`, and
`validate/Test-OnPremisesSqlServerDataMapScan.ps1`. No Fail items were raised. This fragment meets the
definition of done in `AGENTS.md` §9.

**Maintenance addendum (2026-09-26):** of the Microsoft Product Owner finding's two flagged VERIFY
items, the system scan rule set name (`scanRulesetName: "SqlServerDatabase"`, `scanRulesetType:
"System"`) is now confirmed via the System Scan Rulesets - Get REST reference's own worked example
(`README.md` §11, `#14` reference). The Windows Authentication `CredentialType` mapping remains an
open VERIFY, unaffected by this pass.
