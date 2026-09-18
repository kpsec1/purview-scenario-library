---
part: "design"
parent: "ediscovery/teams-purge-hold-lifecycle-management"
---
## 1. Problem statement

`scenarios/ediscovery/search-and-purge-teams-messages/` deliberately left the hold-removal and
reapplication sequence manual: "identify and remove any hold or retention policy on every target
mailbox... reapply every hold/retention policy removed" (that scenario's `README.md` §5 steps 3/6,
`design.md` §3 goal 5). Microsoft's own guidance for that workflow states plainly why this step
cannot be skipped: **"If you don't remove these holds, the chat messages you're trying to delete are
retained"**, a held mailbox doesn't just hide the item from Teams users the way a
held mailbox does for the sibling's Exchange counterpart (`search-and-purge-data-spillage`); it
silently blocks the purge from removing anything at all.

This companion scenario scripts the genuinely scriptable subset of that sequence: **identify** every
hold type documented against a target mailbox, **remove** the ones that have a documented, app-only-
compatible PowerShell mechanism, and **restore** them afterward from a recorded state file, while
being explicit, not silent, about the hold types this scenario cannot safely or completely automate.

## 2. Scope boundary: which hold types this scenario actually handles

Microsoft's own reference architecture for identifying and removing Exchange mailbox holds
 distinguishes several hold types. This
scenario's `deploy/` scripts handle each differently, by design:

| Hold type | Identify | Remove | Reapply | Why |
|---|---|---|---|---|
| **Litigation Hold** | Yes (`LitigationHoldEnabled`) | Yes (`Set-Mailbox -LitigationHoldEnabled $false`) | Yes (`$true`) | Fully documented, Exchange Online PowerShell (app-only supported) |
| **Mailbox-scoped Microsoft Purview retention policy** (`InPlaceHolds` `mbx`/`skp` prefix, a regular mailbox only) | Yes (GUID resolved via `Get-RetentionCompliancePolicy`) | Yes (`Set-RetentionCompliancePolicy -RemoveExchangeLocation`) | Yes (`-AddExchangeLocation`) | Documented Security & Compliance PowerShell cmdlet, non-eDiscovery (app-only supported, §3) |
| **Mailbox-scoped Group-location retention policy** (`InPlaceHolds` `grp` prefix, not org-wide, a group/team mailbox only) | Yes (GUID resolved via `Get-RetentionCompliancePolicy`) | Yes (`Set-RetentionCompliancePolicy -RemoveModernGroupLocation`) | Yes (`-AddModernGroupLocation`) | `-AddModernGroupLocation`/`-RemoveModernGroupLocation` are confirmed real `Set-RetentionCompliancePolicy` parameters, but the resulting `InPlaceHolds` notation for this specific, non-org-wide case is **not** explicitly confirmed by Microsoft's own identify-hold-types reference (§8), flagged as a VERIFY, not guessed |
| **Organization-wide Microsoft Purview retention policy** (`Get-OrganizationConfig` `InPlaceHolds` `mbx`/`grp` prefix) | Yes | Yes, via **exception**, not removal (`-AddExchangeLocationException`) | Yes (`-RemoveExchangeLocationException`) | Microsoft's own documented mechanism excludes the one mailbox rather than editing the org-wide policy itself |
| **Unrecognized `grp`-prefixed entry on a non-group mailbox** | Yes (GUID only) | **No**, identify-only | N/A | No Microsoft Learn citation this scenario carries explains a `grp`-prefixed stamp on a mailbox that isn't a group/team mailbox (§8), disclosed as an anomaly, never guessed at |
| **Retention label hold** (`ComplianceTagHoldApplied`) | Yes | **Opt-in only**, `-IncludeComplianceTagHold` (`Set-Mailbox -RemoveComplianceTagHoldApplied -ProvideConsent`) | **No**, no documented "set back to true" cmdlet exists | One-way flag; clearing it doesn't remove the underlying item-level labels, and Microsoft's own docs describe no reverse cmdlet, §5 |
| **Delay hold** (`DelayHoldApplied`/`DelayReleaseHoldApplied`) | Yes | Yes, if already present from a prior removal cycle (`-RemoveDelayHoldApplied`/`-RemoveDelayReleaseHoldApplied`) | **N/A**, system-managed, re-applied automatically by the Managed Folder Assistant | Not a hold this scenario itself creates; only relevant if a previous, unrelated hold-removal already triggered one, §5 |
| **eDiscovery case hold** (`InPlaceHolds` `UniH` prefix) | Yes (GUID only) | **No**, identify-only, manual/portal action required | N/A | Resolving/removing it needs `Get-CaseHoldPolicy`/`Get-ComplianceCase`, both eDiscovery cmdlets in Security & Compliance PowerShell, the one documented **app-only-unsupported** exception this repo's [Automation surface §3](/docs/automation-surface/#3-authentication-patterns-interactive-vs-unattended) already carries, §6 |
| **Legacy In-Place Hold** (`InPlaceHolds` entry with **no** recognized prefix) | Yes (GUID only) | **No** | N/A | Microsoft's own retirement guidance: "the hold duration of in-place holds can no longer be changed. You can only remove an In-Place Hold that results in the deletion of the inactive mailbox", not a scriptable removal path for an active mailbox |
| **Newer-location retention policy** (Teams chats/private-channel messages via `*-AppRetentionCompliancePolicy`) | **Informational only**, tenant-wide list, not matched to a mailbox | No | No | Microsoft's own docs state these policies "don't stamp directly on organization configuration or Exchange Online objects", no documented per-mailbox applicability check exists, §7 |

This table is the scenario's actual definition of done: six hold types are fully identify+remove+
restore automated (the Group-location row carries a disclosed notation VERIFY, not a removal-mechanism
guess, §8), one is identify+remove(opt-in)+no-restore (disclosed asymmetry), and three are
identify-only by design (disclosed gaps, not silently ignored).

## 3. Design goals

1. **Reuse the parent scenario's target-mailbox list, don't re-derive it.** `-DefinitionPath` accepts
 the exact same JSON schema `search-and-purge-teams-messages/deploy/New-TeamsMessagePurgeSearch.ps1`
 consumes (`.search.targetMailboxes[].email`), in practice, the same incident config file drives
 both scenarios. `-Mailbox <string[]>` is available as a direct alternative for operators not using
 that file.
2. **Never guess which mechanism removes a hold.** Every `Set-Mailbox`/`Set-RetentionCompliancePolicy`
 parameter this scenario calls is grounded against a Microsoft Learn reference documenting that exact
 parameter for that exact purpose (§2's citations), no parameter name is inferred by analogy.
3. **Record exactly what was changed, not what was intended.** `Remove-TeamsPurgeMailboxHolds.ps1`
 writes a state file (`-StatePath`) capturing only the holds it actually removed, per mailbox, not
 a copy of the identify report. `Restore-TeamsPurgeMailboxHolds.ps1` reads only that file, so a
 partial removal (one mailbox's Litigation Hold call failed, another succeeded) restores exactly
 what succeeded, not a stale wishlist.
4. **Never touch a hold type this scenario cannot safely reverse, without an explicit opt-in.** The
 retention-label hold (`ComplianceTagHoldApplied`) is real and does block a purge, but clearing it is
 one-way, §2, §5. Default behavior skips it; `-IncludeComplianceTagHold` requires the operator to
 read the warning and choose it deliberately, the same opt-in-for-irreversible-action pattern this
 repo already uses elsewhere (e.g. `priority-cleanup-exchange-data-spillage`'s `-Enabled` switch).
5. **Disclose, don't paper over, the eDiscovery-hold and newer-location-policy gaps.** Both are
 real limitations grounded in current Microsoft Learn guidance (app-only auth unsupported for
 eDiscovery S&C PowerShell cmdlets; no documented per-mailbox applicability check for
 `*-AppRetentionCompliancePolicy`-based Teams-chat policies), not implementation shortcuts, §6, §7.
6. **Split identify / remove / restore into three scripts**, matching this repo's established
 discover-then-act pattern (e.g. the parent scenario's own search/purge split). A fourth,
 `validate/`, re-checks state against the recorded file rather than trusting the removal script's
 own exit code.

## 4. Identifying holds: the `InPlaceHolds` prefix table

`Get-Mailbox <mailbox> | FL LitigationHoldEnabled,InPlaceHolds` and
`Get-OrganizationConfig | FL InPlaceHolds` are the two documented entry points
. Every `deploy/`/`validate/` script in this
scenario parses `InPlaceHolds` values using the same, Microsoft-documented prefix table:

| Prefix | Meaning | Source cmdlet |
|---|---|---|
| *(not an `InPlaceHolds` value, a separate `True`/`False` property)* | Litigation Hold, via the `LitigationHoldEnabled` mailbox property, not `InPlaceHolds` itself | `Get-Mailbox` |
| `UniH` | eDiscovery case hold (Unified Hold) | `Get-Mailbox` |
| *(an `InPlaceHolds` entry with none of the prefixes below)* | Legacy **In-Place Hold**, deprecated, not removable for an active mailbox (§2) | `Get-Mailbox` |
| `mbx<guid>:<suffix>` / `skp<guid>:<suffix>` | Retention policy applied to this **specific-location** (mailbox-scoped) target, **or** an organization-wide policy (distinguish by cross-checking the same GUID against `Get-OrganizationConfig`'s own `InPlaceHolds` list). Microsoft's own "Identify Exchange mailbox hold types" reference documents `mbx`/`skp` as the **only** two prefixes for a `Get-Mailbox`-visible specific-location stamp, never `grp` (§8) | `Get-Mailbox` / `Get-OrganizationConfig` |
| `grp<guid>:<suffix>` | Organization-wide retention policy applied to Microsoft 365 Groups / Teams channel messages, when the GUID matches `Get-OrganizationConfig`'s own `InPlaceHolds` list. A `grp`-prefixed entry that does **not** match an org-wide GUID is a distinct, undocumented case (§8), never merged into the `mbx`/`skp` bucket above | `Get-OrganizationConfig` (org-wide); undocumented for any other case |
| `-mbx<guid>` (leading `-`) | This mailbox is **excluded** from an organization-wide policy | `Get-Mailbox` |
| *(no `InPlaceHolds` entry for a mailbox already in an org-wide policy)* | Org-wide policies don't always stamp `InPlaceHolds` on the mailbox at all, cross-check `Get-OrganizationConfig` unconditionally, never infer "no `InPlaceHolds` entries" as "no applicable policy" | `Get-OrganizationConfig` |

A GUID's `:<suffix>` (`:1`/`:2`/`:3`) identifies the retention action (delete / hold / hold-then-
delete), this scenario's scripts don't act on the suffix, only the prefix, since
every documented retention action still blocks a Teams purge per §2's citation.

## 5. The delay-hold and retention-label edge cases

Two findings from this build's grounding pass materially changed this scenario's design from a naive
"identify → remove → purge → reapply" loop:

- **Removing any hold triggers a 30-day delay hold** (`DelayHoldApplied`/`DelayReleaseHoldApplied`),
 applied by the Managed Folder Assistant the *next time it processes the mailbox after detecting a
 hold was removed*, not instantly. A delay hold "means the mailbox is still
 considered to be on hold for an unlimited hold duration, as if the mailbox was on Litigation Hold."
 Because the Managed Folder Assistant runs on its own schedule (not scriptable to trigger on demand),
 `Remove-TeamsPurgeMailboxHolds.ps1` cannot guarantee a hold it just removed won't reappear as a delay
 hold before the purge runs, it identifies and clears any **pre-existing** delay hold from an earlier
 cycle, and `README.md` §8/§11 name this as an operational timing risk to watch, not something this
 scenario can eliminate. Removing a delay hold itself requires the **Legal Hold** Exchange Online RBAC
 role, `README.md` §3.
- **`ComplianceTagHoldApplied` has a documented one-way clear, no documented reverse.** Microsoft
 publishes `Set-Mailbox -RemoveComplianceTagHoldApplied -ProvideConsent`
 but no equivalent to set the property back to `True`, its own docs note the flag
 "doesn't automatically change back to `False`" even after labeled items are gone, and only changes
 again when a *new* labeled item triggers it. Reapplying "the same hold" for this type has no scripted
 meaning, §2's table marks Reapply "No" for exactly this reason, not an oversight.

## 6. Why eDiscovery case holds are identify-only

[Automation surface §3](/docs/automation-surface/#3-authentication-patterns-interactive-vs-unattended) already establishes, for this entire repo, that **app-only
authentication for eDiscovery cmdlets in Security & Compliance PowerShell is unsupported**, 
Microsoft's own guidance is to use Graph instead, which is exactly why every eDiscovery `deploy/`
script in this repo (including this scenario's own parent) targets
`Microsoft.Graph.Security` rather than `Connect-IPPSSession`. Resolving a `UniH`-prefixed hold's name
and case, though, requires `Get-CaseHoldPolicy`/`Get-ComplianceCase`
, both eDiscovery cmdlets, both unsupported app-only. This scenario's scripts
therefore report the raw `UniH<guid>` value and stop: the operator either resolves and turns the hold
off in the Microsoft Purview portal (**eDiscovery → Cases → [case] → Hold policies → Policy actions →
Turn off**), or, if the hold was created by this repo's own
`premium-legal-hold-and-export`/`location-scoped-legal-hold` scenarios, uses those scenarios' own
Graph-based `Remove-EdiscoveryPremiumLegalHold.ps1`-style tooling instead. Building a workaround that
calls the unsupported cmdlet path anyway (even read-only) would contradict this repo's own established
automation-surface guidance for no operational benefit, the identify step already surfaces the GUID
for the operator to act on manually.

## 7. Why newer-location (`*-AppRetentionCompliancePolicy`) policies are informational-only

Microsoft's retention-cmdlets reference draws a hard line: policies covering **Teams chats**,
**Teams private channel messages**, **Microsoft Copilot experiences**, and several other newer
locations use a **separate** cmdlet family (`Get-/New-/Set-/Remove-AppRetentionCompliancePolicy`) and
explicitly **"don't stamp directly on organization configuration or Exchange Online objects"**
, meaning this scenario's entire `InPlaceHolds`/`Get-OrganizationConfig` detection
mechanism (§4) cannot see them at all. Microsoft's own recommended way to check whether one of these
newer-style policies applies to a specific mailbox is **Policy Lookup**, a Microsoft Purview portal
feature, not a documented PowerShell/Graph query. `Get-AppRetentionCompliancePolicy` itself only lists
policies and their configured application scope; it does not expose a "does this apply to mailbox X"
query. This scenario's `Get-TeamsPurgeMailboxHoldState.ps1` lists every tenant-wide
`*-AppRetentionCompliancePolicy` as **informational context only**, explicitly labeled unmatched to any
specific mailbox, rather than fabricating a matching heuristic. A tenant with a Teams-chat retention
policy created via the *older* `Set-RetentionCompliancePolicy -Applications
"User:TeamsChatUserInteractions"` path **is** covered by this scenario's
`InPlaceHolds`-based detection (that path still stamps `InPlaceHolds`); only the newer cmdlet family's
policies are the disclosed gap.

## 8. Exchange-location vs. Group-location policies, org-wide AND mailbox-scoped

An org-wide `InPlaceHolds` GUID's prefix (§4) is not just cosmetic, Microsoft's own reference draws a
hard functional line between the two org-wide prefixes that matters directly for which removal
mechanism is correct:

- `mbx<guid>:n` (from `Get-OrganizationConfig`), an org-wide policy applied to **Exchange mailboxes,
 Exchange public folders, and 1xN Teams chats**. This applies to every ordinary
 mailbox, including every 1:1/group-chat participant this scenario's scripts ever target. Excepting
 one mailbox uses `Set-RetentionCompliancePolicy -AddExchangeLocationException`.
- `grp<guid>:n` (from `Get-OrganizationConfig`), an org-wide policy applied to **Microsoft 365 Groups
 and Teams channel messages**, i.e. the **group mailbox** associated with a Team, 
 the target this scenario's scripts see for a standard/shared-channel `sourceType`. This does **not**
 apply to a regular user mailbox, and excepting one requires the different
 `-AddModernGroupLocationException` parameter.

Every script in this scenario checks `Get-Mailbox`'s own `RecipientTypeDetails` property
(`'GroupMailbox'` vs. a regular mailbox type) before treating a `grp`-prefixed org-wide policy as
applicable, a `grp`-prefixed policy is never applied as an exception against a 1:1/group-chat
participant's own mailbox, and a `mbx`-prefixed policy's exception is never mistakenly routed through
the Group-location parameter. This distinction was caught during this build's own four-lens review
pass (`reviews.md`, Red Team finding 1) rather than in the initial draft, an earlier version of
these scripts conflated the two prefixes into
a single "org-wide" bucket and always used `-AddExchangeLocationException`, which would have silently
failed (or worse, targeted the wrong location parameter) for any standard/shared-channel target
mailbox under a Group-scoped org-wide policy.

One asymmetry is disclosed, not solved: no confirmed `InPlaceHolds` notation for a **Group-location
exclusion** (the `grp`-prefixed equivalent of `-mbx<guid>` for Exchange-location exclusions) was found
during this build's grounding pass. `Restore-TeamsPurgeMailboxHolds.ps1` therefore always issues the
`-RemoveModernGroupLocationException` call for a recorded Group-kind exception rather than pre-checking
current state first (the way it does for the confirmed Exchange-location exclusion notation), and
`validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1` reports a Group-kind exception as `[WARN]`
("cannot verify"), never `[PASS]`/`[FAIL]`, README.md §11.

### 8.1 The same distinction, re-grounded for the mailbox-scoped (specific-location) case

A follow-up grounding pass (this build) found that the Exchange-vs-Group split above is **not** unique
to org-wide policies, it applies just as hard to a mailbox-scoped (specific-location) policy, and the
initial draft's `mailboxScoped` handling had not carried the distinction across:

- **Microsoft's retention-settings reference states plainly that the "Exchange mailboxes" location, 
 org-wide or specific-location, it doesn't distinguish, never covers a Microsoft 365 Group mailbox.**
 "Email contacts and Microsoft 365 group mailboxes aren't supported for Exchange email." For a
 specific-location (static-scope) policy specifically: "Although the Exchange location initially
 allows a group mailbox to be selected for a static scope, when you try to save the retention policy,
 you receive an error that 'RemoteGroupMailbox' isn't a valid selection for this location."
 
- **Microsoft's own "Identify Exchange mailbox hold types in eDiscovery" reference documents the
 `Get-Mailbox`-visible specific-location prefix table as `mbx`/`skp` only**, the `grp` prefix appears
 exclusively under the separate `Get-OrganizationConfig` (org-wide) table. No
 specific-location Group-mailbox `InPlaceHolds` notation is documented anywhere in this reference.

Combining these: a Group/team mailbox can **never** carry an `mbx`/`skp`-prefixed specific-location
stamp (the Exchange-mailboxes location rejects it outright), and the `grp` prefix Microsoft documents is
scoped to the org-wide table only. The initial draft's `ConvertTo-ParsedInPlaceHolds` function, however,
classified **any** unmatched `mbx`/`skp`/`grp`-prefixed entry as generically "mailbox-scoped" and routed
all three through `-RemoveExchangeLocation`/`-AddExchangeLocation`, a call that, per the citation above,
can never have targeted a group/team mailbox in the first place, and would misfire if it ever tried.
The same conflation also left `applicableOrgWideExchange`'s gating asymmetric with its Group
counterpart: only the Group side was gated on `RecipientTypeDetails -eq 'GroupMailbox'`, when the
Exchange side needed the identical, inverse gate.

**Fix applied across all four scripts** (`Get-/Remove-/Restore-TeamsPurgeMailboxHolds.ps1`,
`validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1`):

1. `ConvertTo-ParsedInPlaceHolds` now parses `grp` separately from `mbx`/`skp`. A `grp`-prefixed entry
 matching an org-wide GUID is (as before) org-wide; one that doesn't is put in a new
 `MailboxScopedGroupPolicyNames` bucket, never merged into `MailboxScopedPolicyNames`.
2. A mailbox is classified as the recipient of a Group-location policy (`MailboxScopedGroupPolicyNames`
 → act on it) only when `Get-Mailbox`'s own `RecipientTypeDetails -eq 'GroupMailbox'`, the only
 mechanism (`-AddModernGroupLocation`) that could plausibly have produced the entry. On any other
 mailbox, the same bucket is renamed `UnrecognizedPolicyGuids`/`unrecognizedPolicyGuidsNotRemoved`:
 identify-only, reported loudly, **never** acted on, no citation explains that case, so this scenario
 doesn't guess at one (`AGENTS.md` §4).
3. `Remove-/Restore-TeamsPurgeMailboxHolds.ps1` route the recognized Group-location bucket through
 `-RemoveModernGroupLocation`/`-AddModernGroupLocation`, confirmed real `Set-RetentionCompliancePolicy`
 parameters, instead of the Exchange-location pair. The `InPlaceHolds` notation
 this produces on the mailbox is disclosed as an open VERIFY (README.md §11), not asserted with the
 same confidence as the `mbx`/`skp` case, because Microsoft's reference doesn't explicitly cover it.
4. `applicableOrgWideExchange` is now gated on `-not $isGroupMailbox`, mirroring the pre-existing
 `applicableOrgWideGroup` gate on `$isGroupMailbox`, closing the asymmetry described above.

This mirrors the exact class of bug `reviews.md`'s Round 1 Red Team finding 1 already caught for the
org-wide case (§8 above), the same conflation risk simply hadn't been re-checked for the mailbox-scoped
path until this pass. See `reviews.md`'s new round for the four-lens review of this specific fix.

## 9. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Companion to `search-and-purge-teams-messages`, reusing its definition-file schema | Design goal 1; avoids re-deriving target-mailbox resolution this repo already covers |
| Org-wide policy removal mechanism | Per-mailbox exception, not editing the policy's own location list | Matches Microsoft's own documented remediation for this exact case |
| Org-wide Exchange vs. Group policies | Tracked and remediated separately (`-AddExchangeLocationException` vs. `-AddModernGroupLocationException`), gated on `Get-Mailbox`'s `RecipientTypeDetails` | Conflating the two would silently misfire against a group/team mailbox, §8 |
| Mailbox-scoped Exchange vs. Group-location policies | Tracked and remediated separately (`-RemoveExchangeLocation`/`-AddExchangeLocation` vs. `-RemoveModernGroupLocation`/`-AddModernGroupLocation`), gated on `Get-Mailbox`'s `RecipientTypeDetails`; a `grp`-prefixed entry on a non-group mailbox is reported as `UnrecognizedPolicyGuids` and never acted on | Same conflation risk as the org-wide row, re-grounded for the mailbox-scoped case, §8.1 |
| Retention-label hold | Opt-in only (`-IncludeComplianceTagHold`), never restored | One-way, disclosed clearly rather than silently defaulted on, §5 |
| eDiscovery case hold | Identify-only, never removed by this scenario | App-only auth unsupported for the resolving cmdlets, §6 |
| Newer-location policies | Informational listing only, never mailbox-matched | No documented per-mailbox applicability check exists, §7 |
| State tracking | A dedicated `-StatePath` JSON written by Remove, consumed by Restore and Validate | Restores exactly what was actually changed, not what was merely identified, design goal 3 |
| Auth surfaces | Exchange Online PowerShell (`Connect-ExchangeOnline`, `Get-/Set-Mailbox`, `Get-OrganizationConfig`) + Security & Compliance PowerShell (`Connect-IPPSSession`, `Get-/Set-RetentionCompliancePolicy`, `Get-AppRetentionCompliancePolicy`) | Both support certificate-based app-only auth per [Automation surface §3](/docs/automation-surface/#3-authentication-patterns-interactive-vs-unattended); neither is the eDiscovery-cmdlet exception |

## 10. Non-goals

- **Removing or resolving eDiscovery case holds** (§6), a disclosed, deliberate gap, not deferred
 guesswork.
- **Matching newer-location (`*-AppRetentionCompliancePolicy`) policies to a specific mailbox** (§7), 
 no documented mechanism exists.
- **Triggering the Managed Folder Assistant on demand**, no documented cmdlet exists to force an
 immediate mailbox processing pass; the timing risk in §5 is disclosed, not engineered around.
- **Re-implementing the Teams search or purge itself**, this scenario is purely the hold lifecycle
 companion; `search-and-purge-teams-messages` remains the search/purge scenario.
- **A general-purpose "remove every hold on this mailbox" tool** for non-Teams-purge use cases (e.g.
 the Recoverable-Items-folder-deletion workflow Microsoft documents separately
), this scenario's scope, naming, and warnings are specifically about clearing
 the path for a Teams-message purge, not a general hold-management utility.

## References

See `README.md` §12 for the full, numbered source list shared with this file.
