---
part: "runbook"
parent: "ediscovery/teams-purge-hold-lifecycle-management"
---
## Implementation steps

### PowerShell path

```powershell
# 1. Connect both surfaces (Automation surface Section 3).
Connect-ExchangeOnline -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'
Connect-IPPSSession -AppId $AppId -Certificate $Cert -Organization 'contoso.onmicrosoft.com'

# 2. Identify -- read-only, safe to run any time.
./deploy/Get-TeamsPurgeMailboxHoldState.ps1 `
    -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json
# (or point -DefinitionPath at the SAME incident config file used with search-and-purge-teams-messages)

# Review BlocksPurge per mailbox. If a mailbox's only blocker is an eDiscovery case hold or legacy
# In-Place Hold, this scenario's Remove script cannot help -- resolve it manually first (this page
# Section 6/the design notes Section 6).

# 3. Remove -- preview first.
./deploy/Remove-TeamsPurgeMailboxHolds.ps1 `
    -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json `
    -StatePath ./hold-removal-state-2026-014.json -WhatIf

./deploy/Remove-TeamsPurgeMailboxHolds.ps1 `
    -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json `
    -StatePath ./hold-removal-state-2026-014.json
# Add -IncludeComplianceTagHold only after reading the design notes Section 5 -- this one clear is IRREVERSIBLE.

# 4. Re-confirm readiness before purging.
./validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1 `
    -DefinitionPath ./deploy/policy/teams-purge-hold-lifecycle-mailboxes.sample.json

# 5. Run the sibling scenario's purge -- NOT part of this scenario.
# ../search-and-purge-teams-messages/deploy/New-TeamsMessagePurgeSearch.ps1 ...
# ../search-and-purge-teams-messages/deploy/Invoke-TeamsMessagePurge.ps1 ...

# 6. Restore -- as soon as the purge is validated. Time-sensitive (this page Section 8).
./deploy/Restore-TeamsPurgeMailboxHolds.ps1 -StatePath ./hold-removal-state-2026-014.json -WhatIf
./deploy/Restore-TeamsPurgeMailboxHolds.ps1 -StatePath ./hold-removal-state-2026-014.json

# 7. Confirm restoration.
./validate/Test-TeamsPurgeMailboxHoldLifecycle.ps1 -StatePath ./hold-removal-state-2026-014.json
```

### Portal reference

The equivalent manual actions are documented directly by Microsoft under **Step 3/Step 4/Step 7** of
"Find and delete Microsoft Teams chat messages in eDiscovery", which itself points
to **eDiscovery → Cases → [case] → Hold policies** for eDiscovery case holds
specifically (the one hold type this scenario's scripts never touch - the configuration reference), and **Data lifecycle
management → Retention policies** in the Microsoft Purview portal for editing a retention policy's
location list directly.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Identify cmdlets | `Get-Mailbox` (`LitigationHoldEnabled`, `InPlaceHolds`, `ComplianceTagHoldApplied`, `DelayHoldApplied`, `DelayReleaseHoldApplied`), `Get-OrganizationConfig` (`InPlaceHolds`) | Exchange Online PowerShell |
| `InPlaceHolds` prefix parsing | `UniH` = eDiscovery hold; `mbx`/`skp` = mailbox-scoped (specific-location, regular mailbox) or org-wide retention policy (cross-checked); `grp` = org-wide Group policy when GUID matches `Get-OrganizationConfig`, otherwise a mailbox-scoped Group-location policy (group/team mailbox only) or, on a non-group mailbox, an unrecognized anomaly; `-mbx` = org-wide exclusion; no prefix = legacy In-Place Hold | the design notes.1, grounded against Microsoft's own prefix table |
| Resolve policy name | `Get-RetentionCompliancePolicy <guid> -DistributionDetail` | Security & Compliance PowerShell |
| Remove - Litigation Hold | `Set-Mailbox -LitigationHoldEnabled $false` | |
| Remove - mailbox-scoped policy (regular mailbox) | `Set-RetentionCompliancePolicy -RemoveExchangeLocation <mailbox>` |; never used against a group/team mailbox - |
| Remove - mailbox-scoped Group-location policy | `Set-RetentionCompliancePolicy -RemoveModernGroupLocation <mailbox>` | **Only** when the target is a group/team mailbox (`RecipientTypeDetails -eq 'GroupMailbox'`) -; resulting `InPlaceHolds` notation is an open VERIFY, the design notes.1 |
| Remove - org-wide Exchange policy | `Set-RetentionCompliancePolicy -AddExchangeLocationException <mailbox>` (excludes the mailbox; does not edit the policy itself) | **Only** for a non-group mailbox - |
| Remove - org-wide Group policy | `Set-RetentionCompliancePolicy -AddModernGroupLocationException <mailbox>` | **Only** when the target is a group/team mailbox (`RecipientTypeDetails -eq 'GroupMailbox'`, e.g. a standard/shared channel's parent team) - never conflate with the Exchange-location parameter above. the design notes |
| Remove - retention-label hold (opt-in) | `Set-Mailbox -RemoveComplianceTagHoldApplied -ProvideConsent` | `-IncludeComplianceTagHold` switch; **irreversible**, no restore cmdlet exists |
| Remove - delay hold (pre-existing only) | `Set-Mailbox -RemoveDelayHoldApplied` / `-RemoveDelayReleaseHoldApplied` | Requires the **Legal Hold** role |
| Restore - Litigation Hold | `Set-Mailbox -LitigationHoldEnabled $true` | |
| Restore - mailbox-scoped policy (regular mailbox) | `Set-RetentionCompliancePolicy -AddExchangeLocation <mailbox>` | |
| Restore - mailbox-scoped Group-location policy | `Set-RetentionCompliancePolicy -AddModernGroupLocation <mailbox>` |; the design notes.1 |
| Restore - org-wide exception | `Set-RetentionCompliancePolicy -RemoveExchangeLocationException <mailbox>` | |
| Never touched | eDiscovery case holds (`UniH`), legacy In-Place Holds, `*-AppRetentionCompliancePolicy`-governed newer-location policies, an unrecognized `grp`-prefixed entry on a non-group mailbox | the design notes.1 |
| Informational listing | `Get-AppRetentionCompliancePolicy` | Tenant-wide, never matched to a specific mailbox |
| State file | `-StatePath` JSON (`Remove-TeamsPurgeMailboxHolds.ps1` writes it; `Restore-`/`Test-` scripts read it) | Records only what was actually changed - the design notes goal 3 |

## Operations and tuning

**KPIs / signals:** count of mailboxes with `BlocksPurge=true` before remediation vs. after Remove
runs; count of mailboxes whose only remaining blocker is a non-scriptable hold type (eDiscovery case
hold or legacy In-Place Hold) - these need manual resolution before the purge can succeed at all;
whether `-IncludeComplianceTagHold` was ever used (track separately - it's a one-way action with no
scripted undo). **The single biggest operational-timing risk in this scenario is the 30-day delay
hold**: removing a hold doesn't take effect at Managed Folder Assistant speed, and this
scenario cannot force that assistant to run immediately - if a purge attempt still fails after Remove
reports success, a just-triggered delay hold on the *next* Managed Folder Assistant pass is a plausible
cause, not necessarily a script defect. **Restore promptly**: Microsoft notes that reapplying a hold
within 24 hours of a Teams purge can still preserve the mailbox's compliance copy from background
deletion (*Search-and-Purge for Microsoft Teams Messages* (the configuration reference)) - treat Stage 6 (Restore) as time-sensitive,
not a background chore. **SIEM integration:** forward the underlying `Set-Mailbox`/
`Set-RetentionCompliancePolicy` audit events to Sentinel/SIEM alongside the sibling scenario's own
`ediscoveryCase` operation-completion events, so a hold-removal/reapplication gap is visible
independent of the purge's own success/failure.

## Rollback and decommission

See the rollback runbook. Quick reference: this scenario's own "rollback" **is** its Restore stage - there is
no separate decommission step beyond deleting the `-StatePath` state files once an incident record no
longer needs them (they may contain mailbox addresses and policy names, treat as sensitive for the
life of the incident, matching the sibling scenario's own guidance for its search definition).

## References

1. Find and delete Microsoft Teams chat messages in eDiscovery (Step 3/4/7 hold-removal/reapplication
   sequence, Top Locations statistics) - <https://learn.microsoft.com/purview/edisc-search-teams-data>
2. Feature permissions in Exchange Online (In-Place Hold / Legal Hold role table) - <https://learn.microsoft.com/exchange/permissions-exo/feature-permissions>
3. Records Management role group (Retention Management role) - see [RBAC model, section 4](/docs/rbac-model/#4-purview-role-groups-by-module-representative-not-exhaustive); Microsoft
   Purview compliance portal permissions - <https://learn.microsoft.com/purview/microsoft-365-compliance-center-permissions>
4. Manage holds in eDiscovery (Turn on/off/retry a hold policy - the portal-only action for the
   eDiscovery-case-hold gap this scenario discloses) - <https://learn.microsoft.com/purview/edisc-hold-manage>
5. Identify Exchange mailbox hold types in eDiscovery (InPlaceHolds prefix table, delay holds,
   ComplianceTagHoldApplied, `Get-AppRetentionCompliancePolicy`/newer-locations reference) - <https://learn.microsoft.com/purview/edisc-hold-types-mailboxes>
6. Delete items in the Recoverable Items folder for mailboxes on hold in eDiscovery (Litigation Hold
   removal, org-wide-policy exclusion mechanism, 24-hour sync note, delay-hold removal) - <https://learn.microsoft.com/purview/edisc-hold-delete-recoverable-items>
7. Set-RetentionCompliancePolicy reference (`-RemoveExchangeLocation`/`-AddExchangeLocation`,
   `-AddExchangeLocationException`/`-RemoveExchangeLocationException`) - <https://learn.microsoft.com/powershell/module/exchangepowershell/set-retentioncompliancepolicy>
8. PowerShell cmdlets for retention policies and retention labels (`*-AppRetentionCompliancePolicy`
   newer-locations table) - <https://learn.microsoft.com/purview/retention-cmdlets>
9. *Search-and-Purge for Microsoft Teams Messages* - the parent scenario this companion
   removes/restores holds for; shares its `-DefinitionPath` JSON schema.
10. Common settings for retention policies and retention label policies (confirms the Exchange-mailboxes
    location - org-wide or specific-location - never covers a Microsoft 365 Group mailbox, including
    the exact "RemoteGroupMailbox isn't a valid selection" save-time error) - <https://learn.microsoft.com/purview/retention-settings>

> Re-verify all links and cmdlet parameter names against current Microsoft Learn before a
> customer-facing deployment. This scenario treats a `-IncludeComplianceTagHold` clear as an
> irreversible action requiring deliberate opt-in, and treats eDiscovery case holds/legacy In-Place
> Holds/newer-location policies as disclosed gaps rather than solved problems - see the known limitations.