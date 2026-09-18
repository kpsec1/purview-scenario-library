---
part: "design"
parent: "ediscovery/search-and-purge-teams-messages"
---
## 1. Problem statement

A Microsoft Teams 1:1 chat, group chat, or channel post contains content that must be removed
immediately, the Teams analog of the mailbox data-spillage case this repo's
`scenarios/ediscovery/search-and-purge-data-spillage/` sibling already automates. That sibling
scenario deliberately scoped Teams content out (`design.md` §8 of that scenario) because Microsoft
Graph's `purgeData` action supports a second `purgeAreas` value, `teamsMessages`, that its own
author flagged as "a materially different, easily-misunderstood guarantee" without building it. This
scenario builds that second half: search for and purge Microsoft Teams chat messages via the same
`ediscoverySearch`/`purgeData` Graph mechanism, with the materially different safety model that
content type actually requires.

## 2. Correcting an assumption carried from the sibling scenario

Re-grounding `purgeAreas: teamsMessages` directly against current Microsoft Learn for this build
surfaced a **factual correction** to the sibling scenario's own docs, not just a new build. The
sibling's `README.md` §6/§11 and `design.md` §7/§8 stated that Teams purge is "compliance-copy-only
deletion, no true hide-from-user equivalent", reasoning that a Teams purge would be *safer*, not
more dangerous, than a mailbox purge. Two current Microsoft Learn pages fetched directly during this
build's grounding pass say the opposite for the mechanism this repo actually scripts:

- The `purgeData` Graph reference itself states: **"When purgeType is set to either `recoverable` or
  `permanentlyDelete` and purgeAreas is set to `teamsMessages`, the Teams messages are permanently
  deleted."** [[1]](#references), both enum values, not just `permanentlyDelete`.
- "Find and delete Microsoft Teams chat messages in eDiscovery" draws the actual distinction: it's
  the **legacy, cmdlet-based** purge path (the old Security & Compliance PowerShell
  `New-ComplianceSearchAction -Purge` mechanism, which this repo's automation-surface guidance
  already avoids for other reasons, §3) that only removes the *compliance* copy, leaving the
  user-visible message untouched, and Microsoft's own guidance says to **avoid** that path for
  Teams for exactly that reason ("the user copy isn't deleted"). The **Graph-based** purge (what
  `Clear-MgSecurityCaseEdiscoveryCaseSearchData` calls) instead "removes the user copy permanently
  and can't be recovered for user use" [[2]](#references).

In other words: the sibling scenario's non-goal note had the risk backwards. Purging Teams messages
via Graph is **not** a softer, compliance-copy-only action, it is an **immediate, unconditional,
irreversible deletion of the user-visible message**, with no `Recoverable`-equivalent mode at all.
This scenario's entire safety design (§5) is built around that corrected understanding, and this
build also corrects the sibling's `README.md`/`design.md` text in place rather than leaving a
materially wrong safety claim standing next to a scenario that contradicts it.

## 3. Design goals

1. **Treat every Teams purge as irreversible for the user copy, regardless of `-PurgeType`.** Unlike
   the mailbox sibling (`Recoverable` safe-by-default, `PermanentlyDelete` gated), there is no
   Teams-side purge that only hides the message from the user. `Invoke-TeamsMessagePurge.ps1`
   therefore requires the same explicit `-ConfirmPermanentDelete` switch for **either** `-PurgeType`
   value, a deliberate, disclosed deviation from the mailbox sibling's pattern (§7).
2. **Script the current, non-retired mechanism**, Microsoft Graph's `ediscoverySearch`/`purgeData`
   (`purgeAreas: teamsMessages`), the same object model and automation-surface rationale as the
   mailbox sibling (`docs/automation-surface.md` §3: app-only auth for eDiscovery Security &
   Compliance PowerShell cmdlets is unsupported). Never build on the cmdlet-based path Microsoft's
   own current guidance tells operators to avoid for Teams specifically (§2).
3. **Model Teams data sources explicitly, not as a tenant-wide sweep.** Unlike the mailbox sibling's
   `allTenantMailboxes` scope, a Teams-focused search targets a small, specific set of mailboxes
   (chat participants, a parent team's mailbox, or a private-channel mailbox), see §4. This
   scenario's search definition takes an explicit target-mailbox list rather than a blanket scope,
   both because that is what Microsoft's own workflow documents (identify the right mailboxes first)
   and because it keeps blast radius bounded for a content type this scenario cannot make
   reversible.
4. **Reuse, don't reimplement, this repo's existing Teams/group mailbox resolution.** For standard
   and shared channels, the target mailbox is the parent team's own group mailbox, the same
   `PrimarySmtpAddress` value `scenarios/ediscovery/teams-group-hold-resolution/` already resolves
   via `Get-UnifiedGroup`. This scenario's definition file accepts that value directly rather than
   re-deriving it, and its README points operators at that sibling for the resolution step.
5. **Disclose the hold-removal requirement as a real operational step, not a silent skip.** Unlike
   mailbox purge (a held mailbox just gets its item hidden from view, not removed, the mailbox
   sibling's own documented gap), Microsoft states plainly that an active hold or retention policy on
   a target mailbox **blocks** a Teams purge from removing anything at all: "If you don't remove
   these holds, the chat messages you're trying to delete are retained" [[2]](#references). This
   scenario documents the required remove-hold → purge → verify → reapply-hold sequence in the
   README rather than silently assuming holds don't apply, and does not attempt to automate hold
   removal/reapplication itself, that is other scenarios' own scoped responsibility in this repo
   (for example `priority-cleanup-exchange-data-spillage`'s hold-aware design), not duplicated here.
6. **Split discovery from destruction into two scripts**, matching the mailbox sibling's pattern, 
   `New-TeamsMessagePurgeSearch.ps1` (find/create case+search, bind target mailboxes, estimate) is
   separate from `Invoke-TeamsMessagePurge.ps1` (the single irreversible action).

## 4. Where Teams content actually lives (and what to search)

Microsoft's own data-source table for this exact workflow [[2]](#references):

| Teams content type | Search this mailbox |
|---|---|
| 1:1 chat | The mailbox of **each** chat participant |
| Group chat (1:N) | The mailbox of **each** chat participant |
| Standard or shared channel post | The mailbox associated with the **parent team** |
| Private channel post | A **dedicated mailbox** for that private channel |

A separate, deeper Microsoft Learn page on Teams content storage describes private-channel storage
differently, "messages sent in a private channel are stored in the Exchange Online mailboxes of
**all members** of the private channel" [[3]](#references), which does not obviously match "a
dedicated mailbox for each private channel" from the purge-workflow page. Both pages are current
(non-retired); this build did not find a third source reconciling them. **VERIFY (pilot tenant or a
future Microsoft Learn pass):** whether a private channel's compliance copies live in one dedicated
mailbox, in every member's own mailbox, or both, flagged inline in `README.md` §11 rather than
guessed. Until resolved, treat a private-channel target as needing per-member verification via the
`Get-TeamChannelUser` membership-lookup procedure Microsoft documents for the equivalent
private-channel-search workflow [[3]](#references), not just the "dedicated mailbox" claim alone.

This scenario's search-definition file takes each target mailbox as an explicit, pre-resolved SMTP
address tagged with its `sourceType` (`OneToOneChat` / `GroupChat` / `StandardOrSharedChannel` /
`PrivateChannel`) for audit-trail clarity, resolution of *which* mailboxes those are is either
already known (chat participants) or delegated to `teams-group-hold-resolution` (parent-team
mailbox) or the manual private-channel membership lookup above; re-deriving that resolution logic
here would duplicate scope this repo already covers elsewhere.

## 5. Query construction

Microsoft's own tip for this workflow: "use the **Type** condition and select the **Instant
messages** option" in the portal's condition builder for the most comprehensive match across 1:1,
group, and channel chats [[2]](#references). The condition-builder reference's **Message kind**
condition documents the equivalent KQL-level value as `microsoftteams`
[[4]](#references)[[5]](#references), this scenario's sample `contentQuery` therefore leads with
`kind:microsoftteams`, not the Skype-for-Business-oriented `kind:im` (which requires an explicit
`AND subject:conversation` exclusion to avoid also matching Teams content, the opposite problem
[[5]](#references)). Narrow further with a date range or distinctive keyword, the same tuning
guidance as the mailbox sibling.

## 6. Data-source binding mechanics

The mailbox sibling's `dataSourceScopes: allTenantMailboxes` has no Teams-appropriate equivalent, 
this scenario instead binds an explicit mailbox list as **non-custodial data sources** on the search,
the pattern Microsoft's own `Create searches` reference worked example demonstrates
(`noncustodialSources@odata.bind`) [[6]](#references):

1. For each target mailbox, find-or-create a case-level `ediscoveryNoncustodialDataSource`, 
   `dataSource: { "@odata.type": "microsoft.graph.security.userSource", "email": "<SMTP>" }`
   [[7]](#references), via `New-MgSecurityCaseEdiscoveryCaseNoncustodialDataSource`.
2. Bind those sources onto the search at creation time via the `noncustodialSources@odata.bind`
   request-body property [[6]](#references), or after creation via
   `POST .../searches/{id}/noncustodialSources/$ref` [[8]](#references) for a mailbox added on a
   later run.
3. `dataSourceScopes` is left `none` on the search object, the documented value Microsoft's own
   example response shows when a search's sources are supplied explicitly rather than via a blanket
   scope [[6]](#references).

**VERIFY (pilot tenant or a future Microsoft Learn/SDK pass):** the exact typed PowerShell cmdlet
name for step 2's `$ref`-bind action (the Graph SDK's usual convention would produce something like
`New-MgSecurityCaseEdiscoveryCaseSearchNoncustodialSourceByRef`, but this build found no page
directly confirming that name for the v1.0 `Microsoft.Graph.Security` module). `deploy/
New-TeamsMessagePurgeSearch.ps1` therefore calls the confirmed raw HTTP shape via
`Invoke-MgGraphRequest` for that one step rather than guessing an unconfirmed cmdlet name, per
`AGENTS.md` §4, flagged in that script's own `.NOTES`.

**VERIFY (pilot tenant):** how a case-level `ediscoveryNoncustodialDataSource` object's `DisplayName`
is populated for a `userSource` (a mailbox), Microsoft's own worked example shows a `siteSource`'s
`DisplayName` as the SharePoint site's title, but no example shows the equivalent for a mailbox
`userSource`. `New-TeamsMessagePurgeSearch.ps1`'s find-or-create idempotency check for this object
therefore matches on `DisplayName` as a best-effort heuristic and is flagged as `[WARN]`, not
`[PASS]`, by the validation script until confirmed.

## 7. The always-double-confirmed purge

The mailbox sibling requires `-ConfirmPermanentDelete` only when `-PurgeType PermanentlyDelete` is
selected, because `-PurgeType Recoverable` is genuinely reversible there (Outlook's Recover Deleted
Items). For Teams, §2/§3 established that **no** `-PurgeType` value is reversible for the
user-visible message. `Invoke-TeamsMessagePurge.ps1` therefore requires `-ConfirmPermanentDelete`
unconditionally, for both `-PurgeType Recoverable` and `-PurgeType PermanentlyDelete`, the switch
still exists (it's a required Graph request property, and it plausibly still affects the compliance
copy's own retention/hold-interaction timeline, which this build found no page confirming either
way, a second, narrower VERIFY carried into `README.md` §11), but it is no longer, by itself, a
safety gate the way it is for the mailbox sibling.

## 8. Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| API surface | Microsoft Graph `purgeData` with `purgeAreas: teamsMessages`, not the legacy cmdlet path | Microsoft's own current guidance says to avoid the cmdlet path for Teams (compliance-copy-only, user copy remains), §2 |
| Confirmation gate | `-ConfirmPermanentDelete` required for **both** `-PurgeType` values | No Teams purge is reversible for the user-visible message regardless of `purgeType`, §7 |
| Data sources | Explicit per-mailbox `noncustodialDataSource` list, not `allTenantMailboxes` | No Teams-appropriate tenant-wide scope exists; bounded blast radius for an irreversible action, §3 goal 3, §6 |
| Query | `kind:microsoftteams`-led KQL | Matches Microsoft's own condition-builder guidance for Teams content; avoids the Skype-for-Business-oriented `kind:im` ambiguity, §5 |
| Hold handling | Documented manual remove/reapply sequence, not automated | A Teams purge is fully blocked (not just hidden) by an active hold, a materially different, heavier operational step than the mailbox sibling's "skip and hide" behavior; automating hold lifecycle is other scenarios' scope, §3 goal 5 |
| Private-channel mailbox resolution | Documented as an open VERIFY, not asserted | Two current Microsoft Learn pages describe private-channel compliance storage differently, §4 |
| Correction to sibling scenario | `search-and-purge-data-spillage`'s README/design updated in place | That scenario's non-goal text asserted the opposite (safer, not more dangerous) of what current Microsoft Learn documents for the mechanism it named, §2 |

## 9. Non-goals

- **Exchange mailbox purge** (`purgeAreas: mailboxes`), the mailbox sibling's own scope; this
  scenario is Teams-only.
- **Automating hold/retention-policy removal and reapplication**, documented as a required manual
  sequence (§3 goal 5); a future cross-cutting follow-up could script it, but that is a distinct,
  separately-scoped fragment.
- **Teams Connect Chat (external access/federation) conversations**, Microsoft states search and
  purge isn't supported for these [[2]](#references); not scriptable, not attempted.
- **Chats with yourself**, explicitly unsupported for search and delete [[2]](#references).
- **The newer Data Security Investigations purge-queue workflow** Microsoft references as an
  alternative entry point [[2]](#references), a different product surface this build didn't ground;
  a candidate future fragment, not folded in here.

## References

See `README.md` §12 for the full, numbered source list shared with this file.
