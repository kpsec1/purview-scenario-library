# Rollback — Harassment & Code-of-Conduct Detection

## Recommended sequence

A Communication Compliance policy detects and captures communications for reviewer triage; rolling it
back stops detection but should be staged so you don't lose captured review history or the portal-side
classifier configuration prematurely.

### Stage 1 — Disable the policy (reversible, seconds)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-CodeOfConductPolicy.ps1 -ConfigPath ./deploy/config/code-of-conduct.json
```

Sets the policy `-Enabled $false` (via `Set-SupervisoryReviewPolicyV2`). Detection stops; the policy,
its keyword rule, its reviewers, the portal-configured classifiers, and all captured review history
remain. Reversible — re-run `New-CodeOfConductPolicy.ps1` (or add a user in the portal) to re-enable.
Use this for a change freeze, a tuning pause, or while reworking the lexicon/classifier set.

### Stage 2 — Delete the policy (not reversible)

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./deploy/Remove-CodeOfConductPolicy.ps1 -ConfigPath ./deploy/config/code-of-conduct.json -Delete
```

Removes the policy (`Remove-SupervisoryReviewPolicyV2`), which also removes its rule and the
portal-configured classifier settings attached to it. Re-establishing the control means re-running the
**full two-part deployment** (script the keyword/workflow half, re-add classifiers + locations in the
portal). Only do this when the policy is being permanently retired.

Both stages support `-DryRun` to preview the exact cmdlet without touching the tenant (there is no
working `-WhatIf` in Security & Compliance PowerShell — see `README.md` §11).

## What rollback does **not** undo

- **Captured review items / alerts / cases and their audit history.** Disabling or deleting the policy
  does not purge the communications already captured and surfaced for review, nor the alert/case
  records and their modification history — those follow their own retention and remain for
  investigation/audit. Export the modification history to CSV first if you need a record before a
  delete (`README.md` §8).
- **Reviewer role-group membership.** The Analyst/Investigator/Admin role assignments granted to
  reviewers are not touched — remove them separately in the portal (Settings → Roles and groups) if
  decommissioning the people, not just the policy. Keep ≥1 Communication Compliance / Admins member to
  avoid a zero-administrator lockout.
- **The keyword dictionary / lexicon**, if you attached one as a shared custom keyword dictionary in
  the portal (rather than inline in the rule Condition) — that dictionary object is tenant-level and
  outlives this policy.
- **Global privacy/pseudonymization settings** — those are tenant-wide Communication Compliance
  settings, not part of this policy, and are unaffected.

## Verification after rollback

```powershell
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
./validate/Test-CodeOfConductPolicy.ps1 -ConfigPath ./deploy/config/code-of-conduct.json
```

After **Stage 1**, expect the "Policy is enabled" check to report `[WARN]` (disabled is a valid state,
not a hard failure) while existence/reviewer/rule checks still `[PASS]`. After **Stage 2**, expect the
"Policy exists" check to `[FAIL]` — confirming the policy (and its rule) are gone. Confirm in the
portal that the policy no longer appears under **Communication Compliance → Policies**.
