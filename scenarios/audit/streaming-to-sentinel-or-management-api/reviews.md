# Four-Lens Review — Continuous Audit Streaming to a SIEM

Reviewed after the initial draft of `README.md`, `design.md`, `deploy/`, and `validate/`. One round
of findings below; all **Fix** items were applied before this file was finalized (see the code diff
each finding cites — `Invoke-ManagementActivityPoll.ps1`'s retry/isolation logic and the `-OutDir`
access-control guidance were added during this review, not before it). No **Fail** items remain.

---

## 🔴 Red Team

**Verdict: Fix (resolved)**

1. **Plaintext DLP content sitting at rest, unrestricted.** `DLP.All` events can carry excerpts of
   matched sensitive content; the original draft only told the operator to secure/dispose of
   `out/*.ndjson` at **decommissioning** (`rollback.md`), saying nothing about access control while
   the pipeline is *live* and the files are actively accumulating.
   - **Resolution:** `README.md` §11 and `rollback.md` §2 now both state explicitly that `-OutDir`
     needs filesystem-level access restriction (ACLs / a private storage container) as an ongoing
     operational control, not only a teardown step.
2. **No throttling-driven retry = a poll that silently degrades under load.** The initial
   `Invoke-ManagementActivityPoll.ps1` draft let any `Invoke-RestMethod`/`Invoke-WebRequest` call
   throw straight out of the script on a 429/`AF429` throttling response (a documented, expected
   condition under sustained polling per Microsoft's own troubleshooting reference) — a scheduled
   job hitting this repeatedly would silently stop making progress on every run rather than backing
   off and recovering.
   - **Resolution:** Added `Invoke-WithRetry` (honors `Retry-After`, exponential backoff otherwise,
     5 attempts) around every content-list and blob-retrieval call — see the script's `.DESCRIPTION`
     and README.md §8/§11.
3. **Credential handling.** The client-secret path marshals a `SecureString` to plaintext in memory
   to build the OAuth2 body (required by this API's documented client-credentials pattern) and never
   writes it to disk/output.
   - **Resolution:** Both scripts null the plaintext variable immediately after use; `.DESCRIPTION`
     and `docs/automation-surface.md` §3 both state certificate-based auth is preferred in
     production — this script accepts a secret because that's the pattern Microsoft's own reference
     documents for this specific API, not because it's the recommended default.
4. **Subscription sprawl / stale grants.** An app registration with `ActivityFeed.Read` (and
   optionally the DLP-events permission) is a standing, broad read grant across tenant activity data.
   - **Resolution:** `rollback.md` §2 explicitly calls out revoking the app registration's Management
     Activity API permissions (or deleting the registration) when the pipeline is decommissioned —
     not just stopping the subscriptions.

No remaining Fix/Fail after resolution.

---

## 🔵 Blue Team

**Verdict: Fix (resolved)**

1. **One content type's failure shouldn't abort the whole scheduled run.** The initial draft ran all
   content types inside a single unguarded loop under `$ErrorActionPreference = 'Stop'` — a
   transient failure on content type 2 of 5 (after Red Team finding 2's retries were exhausted)
   would have aborted types 3–5 entirely for that run, even though nothing about them had failed.
   - **Resolution:** Each content type's list-retrieve-export-checkpoint sequence is now wrapped in
     its own `try`/`catch`; a failure is logged and that type's checkpoint is left unadvanced (so
     it's retried, correctly, on the next scheduled run) while the remaining content types still
     complete.
2. **Readiness before relying on a schedule.** Discovering a missing permission or an unenabled
   subscription only after the first scheduled poll silently produces zero output wastes detection
   time.
   - **Resolution:** `validate/Test-ManagementActivityStreaming.ps1` checks token acquisition,
     per-content-type subscription status, and (once running) checkpoint freshness — so a broken
     pipeline is caught by a scheduled/manual health check, not by noticing a SIEM has gone quiet.
3. **Path A has no equivalent scripted health check.** Sentinel's own data-connector "connected"
   state isn't exposed via a documented REST call this library scripts around.
   - **Disposition: accepted limitation, not fixed.** `README.md` §7 states the Sentinel portal /
     `Get-AzResource` check explicitly as the Path A verification method rather than inventing an
     unconfirmed API-based check — consistent with `AGENTS.md` §4's no-guessing rule.
4. **`Enable-ManagementActivitySubscriptions.ps1`'s `/list` call has no retry wrapper**, unlike the
   poll script.
   - **Disposition: accepted, proportionate.** This script runs rarely (once, or after a config
     change) rather than on a tight schedule, and its `/start` loop already isolates per-content-type
     failures (existing before this review). Adding the same retry machinery for a single
     infrequent call was judged unnecessary duplication rather than a real gap — noted here so the
     asymmetry is a documented decision, not an oversight.

No remaining Fail.

---

## 🎩 CISO

**Verdict: Fix (resolved)**

1. **Which path for which organization, stated plainly.** An organization choosing the wrong path (e.g. deploying
   only the free Sentinel connector, then discovering DLP events never show up) wastes a security
   review cycle discovering the gap themselves.
   - **Resolution:** `design.md` §3's comparison table and `README.md` §11's first bullet state the
     Path A coverage gap (no Entra/DLP) up front, before the deploying organization commits to one path.
2. **Cost is honestly framed, not oversold.** Path A is genuinely free at the ingestion layer
   (§10); Path B has no API cost but isn't "free" once a real SIEM ingestion cost is attached — the
   scenario doesn't claim otherwise.
3. **Compliance narrative.** "Continuous monitoring, not just on-demand investigation" maps cleanly
   to SOC 2 CC7.2 / ISO 27001 A.8.16 / PCI-DSS 10 — concrete, not generic (§2).
4. **Standing risk of a broad read grant** (Red Team finding 4) is priced into the rollback
   discipline rather than left implicit.
5. **Would I fund this?** Yes for an organization already running Sentinel (Path A is free); Path B's
   funding case depends entirely on whether the deploying organization actually needs `DLP.All`/Entra-audit events a
   non-Sentinel SIEM or Path A's gap requires — the scenario is honest that Path B isn't needed by
   everyone, which is itself the right sales conversation to have before building it.

No remaining Fix/Fail after resolution.

---

## 🟦 Microsoft Product Owner

**Verdict: Fix (resolved)**

1. **Correct connector kind and schema.** The Bicep template's `Office365` kind, its three
   `exchange`/`sharePoint`/`teams` data types (and the deliberate absence of an `entra`/`dlp` data
   type on this specific kind), and the `OfficeActivity` destination table are reproduced from the
   `Microsoft.SecurityInsights/dataConnectors` ARM reference and the free-data-sources billing page,
   not paraphrased or guessed.
2. **Correct, distinct API surface for Path B.** The Management Activity API's subscribe (`/start`
   with its 15-minute cooldown), list (`/content`, 24h/7-day limits), `NextPageUri` pagination (named
   correctly as distinct from Graph's `@odata.nextLink`), and `PublisherIdentifier` throttling
   behavior are all sourced from Microsoft's own reference and troubleshooting pages.
3. **Right portal name vs. ARM kind called out.** `README.md` §6 explicitly flags that the portal
   calls this connector "Microsoft 365 (formerly, Office 365)" while the ARM/Bicep `kind` value is
   still literally `Office365` — a detail an under-grounded build would likely get inconsistent.
4. **Not reinventing native capability.** Path A is presented as the default/preferred mechanism
   whenever it's sufficient; Path B is scoped explicitly to the coverage gap (Entra audit, DLP.All)
   and to non-Sentinel SIEMs, not built as a redundant alternative to the native connector.
5. **Honest about two open VERIFYs rather than guessing them:** the Bicep connector resource's exact
   naming contract, and the precise semantics of the `/start` cooldown's 15-minute window — both
   flagged inline (the `.bicep` header and `Enable-ManagementActivitySubscriptions.ps1`'s `.NOTES`)
   rather than asserted.
6. **Forward-looking accuracy.** README §11 notes the Azure-portal-to-Defender-portal Sentinel
   retirement timeline (after March 31, 2027) so organization-facing walkthroughs know to re-check which
   portal a given Sentinel instance actually presents.

No remaining Fail after resolution.

---

## Summary

| Lens | Initial verdict | Findings | Resolution |
|---|---|---|---|
| 🔴 Red Team | Fix | 4 (live-pipeline output access control; missing 429/retry handling; credential handling confirmed sound; subscription-grant revocation on teardown) | Closed |
| 🔵 Blue Team | Fix | 4 (per-content-type failure isolation; readiness/health check; Path A health check gap accepted as a documented limitation; asymmetric retry wrapper accepted as proportionate) | Closed |
| 🎩 CISO | Fix | 1 (path-selection guidance foregrounded); Pass on cost honesty, compliance narrative, funding case | Closed |
| 🟦 Microsoft Product Owner | Fix | 2 VERIFYs recorded (not resolved by guessing); 4 confirmed correct | Closed |

All Fix items are resolved in the current state of `README.md`, `design.md`,
`deploy/office365-connector.bicep`, `deploy/Enable-ManagementActivitySubscriptions.ps1`,
`deploy/Invoke-ManagementActivityPoll.ps1`, `deploy/config/management-activity-streaming.sample.json`,
`validate/Test-ManagementActivityStreaming.ps1`, and `rollback.md`. No Fail items were raised. This
fragment meets the definition of done in `AGENTS.md` §9, with two open VERIFYs recorded rather than
guessed, per `AGENTS.md` §4.
