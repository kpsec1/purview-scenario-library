---
part: "deploy"
parent: "ediscovery/location-scoped-legal-hold"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `New-EdiscoveryLocationHold.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or reconciles) a Microsoft Purview eDiscovery (Premium) case and a location-scoped
    legal hold policy (an ediscoveryHoldPolicy) covering one or more mailboxes/distribution lists
    (userSources) and SharePoint sites (siteSources), with an optional KQL contentQuery -- the
    hold mechanism that isn't organized around a named custodian.

.DESCRIPTION
    Idempotent, parameterized deploy script for the eDiscovery location-scoped-legal-hold
    scenario, the sibling of scenarios/ediscovery/premium-legal-hold-and-export/ that covers the
    *other* v1.0 Graph hold object: microsoft.graph.security.ediscoveryHoldPolicy
    (POST .../legalHolds), not ediscoveryCustodian.applyHold. See design.md section 1 for why the
    two are genuinely different object models, not two ways to do the same thing.

    Uses Microsoft Graph (automation surface 3 per docs/automation-surface.md) for the same
    reason the sibling scenario does -- app-only auth for eDiscovery cmdlets in Security &
    Compliance PowerShell is explicitly unsupported by Microsoft (docs/automation-surface.md
    section 3, README.md section 5).

    No v1.0 typed PowerShell cmdlet exists for ediscoveryHoldPolicy or its siteSources/userSources
    collections -- only the Microsoft.Graph.Beta.Security module has one
    (New-MgBetaSecurityCaseEdiscoveryCaseLegalHold), and docs/automation-surface.md section 2
    directs shipped automation to pin to v1.0 and avoid Microsoft.Graph.Beta.* modules. This
    script therefore calls the v1.0 REST endpoints directly via Invoke-MgGraphRequest, the same
    pattern Remove-EdiscoveryPremiumLegalHold.ps1 already uses for the (also typed-cmdlet-less)
    custodian release action.

    Stages, each individually idempotent (re-running this script after a partial failure is
    safe):
      1. Find-or-create the eDiscoveryCase by DisplayName (same pattern as the sibling scenario).
      2. Find-or-create the ediscoveryHoldPolicy by DisplayName within that case.
      3. Find-or-create each declared userSource (mailbox or distribution-list email) on the hold.
      4. Find-or-create each declared siteSource (SharePoint site URL) on the hold.
      5. With -Retry, call retryPolicy for any source currently in an error/partial state.

    This script uses a hand-rolled $PSCmdlet.ShouldProcess() gate around every
    Invoke-MgGraphRequest write (Invoke-MgGraphRequest has no native ShouldProcess support), the
    same approach scenarios/data-map/scan-azure-sql-and-classify/ and
    scenarios/data-lineage/end-to-end-lineage-validation/ already use for raw-REST Purview calls
    -- so -WhatIf still produces a true dry run even without a typed SDK cmdlet.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/location-hold-definition.json's shape (case, hold,
    userSources[], siteSources[]).

.PARAMETER Retry
    After reconciling sources, call POST .../legalHolds/{id}/retryPolicy if the policy's own
    `errors` collection is non-empty, or if any source's holdStatus is not in
    ('applied','applying'). Off by default -- most first-run failures need the underlying cause
    fixed (invalid email, inaccessible site) before a retry helps; see README.md section 8.

.PARAMETER WaitForApplied
    Poll each newly added userSource/siteSource's holdStatus until it leaves 'applying', instead
    of firing-and-forgetting the add. Off by default -- mirrors the sibling custodian scenario's
    -WaitForHold switch (premium-legal-hold-and-export/deploy/New-EdiscoveryPremiumLegalHold.ps1),
    added during this scenario's Blue Team review round so an operator has the same "wait and
    confirm" option there instead of only the validate script's later, separate check.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as
    scenarios/ediscovery/premium-legal-hold-and-export/deploy/*.ps1.

.EXAMPLE
    ./New-EdiscoveryLocationHold.ps1 -DefinitionPath ./policy/location-hold-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/hold/source action this run would take, without calling any mutating
    Graph endpoint.

.EXAMPLE
    ./New-EdiscoveryLocationHold.ps1 -DefinitionPath ./policy/location-hold-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case and hold policy (if they don't already exist) and adds any missing
    userSources/siteSources.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12 for the full citation list. Endpoints used here:
      - POST   /security/cases/ediscoveryCases                                  (case, typed cmdlet reused)
      - POST   /security/cases/ediscoveryCases/{id}/legalHolds                  (create hold policy)
      - GET    /security/cases/ediscoveryCases/{id}/legalHolds                  (list, for find-or-create)
      - POST   .../legalHolds/{id}/userSources                                  (email + includedSources=mailbox)
      - POST   .../legalHolds/{id}/siteSources                                  (site.webUrl)
      - POST   .../legalHolds/{id}/retryPolicy                                  (no body)

    VERIFY before relying on this in production: the v1.0 "Create userSource" reference for this
    specific endpoint documents the email property only as "SMTP address of the user," unlike the
    sibling (beta, custodian-context) legalHold userSource reference, which explicitly documents
    "or the SMTP address of the group mailbox." Microsoft's own "Manage hold status errors"
    reference does separately document a "Distribution group has too many members" error for a
    group above 1,000 addresses, which only makes sense if a distribution list's own SMTP address
    is an accepted -- and server-side expanded -- userSource.email value; this script accepts a
    DL email in userSources[] on that basis, but confirm the expansion behavior against a pilot
    tenant before pointing this at a distribution list you haven't already tested, per README.md
    section 11. Note two DIFFERENT current Microsoft Learn pages document two different
    group-expansion member caps -- 100 members (portal data-source picker, "Create holds in
    eDiscovery") vs. >1,000 addresses (hold-application error, "Manage holds in eDiscovery") --
    and neither is confirmed to be the limit this REST-driven userSources path actually hits;
    treat 100 as the conservative planning threshold and confirm both against a pilot tenant.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [switch]$Retry,

    [switch]$WaitForApplied,
    [int]$ApplyPollTimeoutSeconds = 180,
    [int]$ApplyPollIntervalSeconds = 10,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphBase = 'https://graph.microsoft.com/v1.0'

function Connect-EdiscoveryGraph {
    param($AppId, $TenantId, $CertificateThumbprint, $Certificate)

    if (Get-MgContext) {
        Write-Verbose 'Reusing existing Microsoft Graph connection.'
        return
    }
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) {
        $connectParams['Certificate'] = $Certificate
    } else {
        $connectParams['CertificateThumbprint'] = $CertificateThumbprint
    }
    Connect-MgGraph @connectParams
}

function Get-OrNewEdiscoveryCase {
    param($Definition)

    # Same find-or-create-by-DisplayName pattern as
    # scenarios/ediscovery/premium-legal-hold-and-export/deploy/New-EdiscoveryPremiumLegalHold.ps1
    # -- no documented case-name-uniqueness filter API, so this matches client-side, mirroring
    # the portal's own "case name must be unique" UX rule.
    $existing = Get-MgSecurityCaseEdiscoveryCase -All |
        Where-Object { $_.DisplayName -eq $Definition.displayName } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Case '$($Definition.displayName)' already exists (id=$($existing.Id))."
        return $existing
    }

    $body = @{
        displayName = $Definition.displayName
        description = $Definition.description
        externalId  = $Definition.externalId
    }
    if ($PSCmdlet.ShouldProcess($Definition.displayName, 'Create eDiscovery (Premium) case')) {
        $created = New-MgSecurityCaseEdiscoveryCase -BodyParameter $body
        Write-Host "Created case '$($created.DisplayName)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<case-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OrNewHoldPolicy {
    param($CaseId, $HoldDef)

    $listUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds"
    $existing = $null
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $listUri
        $existing = $response.value | Where-Object { $_.displayName -eq $HoldDef.displayName } | Select-Object -First 1
    } catch {
        Write-Verbose "Could not list existing hold policies for case $CaseId (expected under -WhatIf on a not-yet-created case)."
    }
    if ($existing) {
        Write-Verbose "Hold policy '$($HoldDef.displayName)' already exists (id=$($existing.id))."
        return $existing
    }

    $body = @{
        displayName = $HoldDef.displayName
        description = $HoldDef.description
    }
    if ($HoldDef.contentQuery) {
        $body['contentQuery'] = $HoldDef.contentQuery
    } else {
        Write-Warning "Hold '$($HoldDef.displayName)' has no contentQuery -- this holds ALL content in every location added to it, not a filtered subset. Confirm this is intentional (README.md section 6) before continuing."
    }
    if ($PSCmdlet.ShouldProcess($HoldDef.displayName, "Create location-scoped hold policy in case $CaseId")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json)
        Write-Host "Created hold policy '$($created.displayName)' (id=$($created.id))."
        return $created
    }
    return [pscustomobject]@{ id = '<hold-id-pending>'; displayName = $HoldDef.displayName }
}

function Wait-SourceApplied {
    param([string]$GetUri, [string]$Label)

    if (-not $WaitForApplied) { return }

    $elapsed = 0
    do {
        Start-Sleep -Seconds $ApplyPollIntervalSeconds
        $elapsed += $ApplyPollIntervalSeconds
        $refreshed = Invoke-MgGraphRequest -Method GET -Uri $GetUri
        Write-Verbose "  holdStatus for ${Label}: $($refreshed.holdStatus) (elapsed ${elapsed}s)"
    } while ($refreshed.holdStatus -eq 'applying' -and $elapsed -lt $ApplyPollTimeoutSeconds)

    if ($refreshed.holdStatus -ne 'applied') {
        Write-Warning "${Label} holdStatus is '$($refreshed.holdStatus)' after ${elapsed}s -- this does not necessarily indicate failure (Microsoft doesn't publish an exact propagation SLA for this object, README.md section 7); re-check via validate/Test-EdiscoveryLocationHold.ps1 later, or pass -Retry, rather than treating this alone as an error."
    }
}

function Confirm-UserSource {
    param($CaseId, $HoldId, $UserSourceDef)

    $listUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId/userSources"
    $existingSources = @()
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $listUri
        $existingSources = @($response.value)
    } catch {
        Write-Verbose "Could not list existing userSources for hold $HoldId (expected under -WhatIf on a not-yet-created hold)."
    }
    if ($existingSources | Where-Object { $_.email -eq $UserSourceDef.email }) {
        Write-Verbose "userSource for '$($UserSourceDef.email)' already exists on hold $HoldId."
        return
    }

    # Only 'mailbox' is a valid includedSources value for a legalHold userSource -- unlike the
    # custodian userSource shape, siteSources are a separate collection here (design.md section
    # 2), not a combined 'mailbox, site' string.
    $body = @{ email = $UserSourceDef.email; includedSources = 'mailbox' }
    if ($PSCmdlet.ShouldProcess($UserSourceDef.email, "Add userSource to hold policy $HoldId")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json)
        Write-Host "Added userSource '$($UserSourceDef.email)' to hold policy $HoldId."
        Wait-SourceApplied -GetUri "$listUri/$($created.id)" -Label "userSource '$($UserSourceDef.email)'"
    }
}

function Confirm-SiteSource {
    param($CaseId, $HoldId, $SiteSourceDef)

    $listUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId/siteSources"
    $existingSources = @()
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $listUri
        $existingSources = @($response.value)
    } catch {
        Write-Verbose "Could not list existing siteSources for hold $HoldId (expected under -WhatIf on a not-yet-created hold)."
    }
    # siteSource list responses key off the SharePoint site's own id/displayName, not the URL --
    # match on displayName (the site's title) as the closest available client-side key. Sites
    # without a title cannot be held at all (README.md section 11), so this is not a new gap.
    $siteTitle = ($SiteSourceDef.site -split '/')[-1]
    if ($existingSources | Where-Object { $_.displayName -eq $siteTitle }) {
        Write-Verbose "siteSource for '$($SiteSourceDef.site)' already appears present on hold $HoldId (matched by title '$siteTitle')."
        return
    }

    $body = @{ site = @{ webUrl = $SiteSourceDef.site } }
    if ($PSCmdlet.ShouldProcess($SiteSourceDef.site, "Add siteSource to hold policy $HoldId")) {
        $created = Invoke-MgGraphRequest -Method POST -Uri $listUri -Body ($body | ConvertTo-Json -Depth 5)
        Write-Host "Added siteSource '$($SiteSourceDef.site)' to hold policy $HoldId."
        Wait-SourceApplied -GetUri "$listUri/$($created.id)" -Label "siteSource '$($SiteSourceDef.site)'"
    }
}

function Invoke-RetryIfNeeded {
    param($CaseId, $HoldId)

    $getUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId"
    $policy = Invoke-MgGraphRequest -Method GET -Uri $getUri
    $hasErrors = $policy.errors -and @($policy.errors).Count -gt 0

    $userSources = @((Invoke-MgGraphRequest -Method GET -Uri "$getUri/userSources").value)
    $siteSources = @((Invoke-MgGraphRequest -Method GET -Uri "$getUri/siteSources").value)
    $unhealthy = ($userSources + $siteSources) | Where-Object { $_.holdStatus -notin @('applied', 'applying') }

    if (-not $hasErrors -and -not $unhealthy) {
        Write-Verbose "Hold policy $HoldId reports no errors and every source is applied/applying -- nothing to retry."
        return
    }

    Write-Warning "Hold policy $HoldId has $(@($policy.errors).Count) reported error(s) and $($unhealthy.Count) source(s) not in an applied/applying state. See 'Manage hold status errors' (README.md section 12) for per-error remediation before retrying if this repeats."
    if ($PSCmdlet.ShouldProcess($HoldId, 'Retry hold policy application')) {
        Invoke-MgGraphRequest -Method POST -Uri "$getUri/retryPolicy" | Out-Null
        Write-Host "Requested retryPolicy for hold $HoldId. This restamps every source in the policy -- re-check status after a few minutes."
    }
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-OrNewEdiscoveryCase -Definition $definition.case
$hold = Get-OrNewHoldPolicy -CaseId $case.Id -HoldDef $definition.hold

foreach ($userSourceDef in $definition.userSources) {
    Confirm-UserSource -CaseId $case.Id -HoldId $hold.id -UserSourceDef $userSourceDef
}
foreach ($siteSourceDef in $definition.siteSources) {
    Confirm-SiteSource -CaseId $case.Id -HoldId $hold.id -SiteSourceDef $siteSourceDef
}

if ($Retry -and $hold.id -ne '<hold-id-pending>') {
    Invoke-RetryIfNeeded -CaseId $case.Id -HoldId $hold.id
}

Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)), hold policy '$($hold.displayName)' (id=$($hold.id)): $($definition.userSources.Count) userSource(s), $($definition.siteSources.Count) siteSource(s) reconciled."
Write-Host 'Next: ./validate/Test-EdiscoveryLocationHold.ps1 to confirm hold status.'
```

#### `policy/location-hold-definition.json`

```json
{
  "_comment": "Reference definition for the eDiscovery location-scoped legal hold scenario. Consumed by New-EdiscoveryLocationHold.ps1 and Remove-EdiscoveryLocationHold.ps1 via -DefinitionPath. Author-only reference for the buyer's own tenant -- replace every value below before use. No secrets belong in this file.",
  "case": {
    "displayName": "CONTOSO-REG-2026-009",
    "description": "Regulatory sweep -- FTC civil investigative demand covering the Payments team's shared inbox and site, plus a compliance distribution list. Outside counsel: Example & Example LLP.",
    "externalId": "2026-009"
  },
  "hold": {
    "displayName": "CONTOSO-REG-2026-009 - Payments team location hold",
    "description": "Location-scoped hold covering the shared Payments mailbox/site and the payments-compliance-dl distribution list, per the CID date range. Not tied to a named custodian -- see design.md section 3.",
    "contentQuery": "(chargeback OR refund OR \"card present\" OR interchange) AND date>=2025-06-01"
  },
  "userSources": [
    { "email": "payments-team@contoso.com", "note": "Shared departmental mailbox -- no single owning custodian." },
    { "email": "payments-compliance-dl@contoso.com", "note": "Mail-enabled distribution list. Microsoft's own hold-error reference documents a 'Distribution group has too many members' condition above 1,000 addresses, implying the service expands a DL's own SMTP address into its member mailboxes -- but a separate current page caps the portal's own group-expansion picker at 100 members for any supported group type, and neither figure is confirmed to be the limit this REST-driven path hits -- VERIFY per README.md section 11 before relying on this for a DL near either size; for a DL you already know is large, resolve and list individual member emails here instead." }
  ],
  "siteSources": [
    { "site": "https://contoso.sharepoint.com/sites/PaymentsTeam" }
  ]
}
```

#### `Remove-EdiscoveryLocationHold.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Staged rollback for the eDiscovery location-scoped-legal-hold scenario: remove one or more
    named locations (userSources/siteSources) from a hold policy, or delete the entire hold
    policy outright.

.DESCRIPTION
    Mirrors the staged approach in rollback.md. Unlike the sibling
    premium-legal-hold-and-export scenario's custodian release (a reversible "release, re-apply
    later" action with its own release endpoint), the v1.0 Graph API exposes no "turn off and
    keep for later" action for an ediscoveryHoldPolicy -- enablePolicy/disablePolicy exist only
    in the beta namespace (design.md section 4). On v1.0 there are exactly two ways to stop a
    location-scoped hold from preserving content:
      1. Delete one userSource or siteSource (releases that single location; the policy and its
         other locations are untouched).
      2. Delete the entire ediscoveryHoldPolicy (-DeleteHold) -- releases every location in it at
         once. There is no partial, reversible "pause" in between on v1.0.

    Both actions carry the same Microsoft-documented warning, quoted directly rather than
    softened: "Turning off a hold policy might result in the permanent deletion of any content
    currently being preserved" / "When you delete a hold policy ... This action might result in
    permanent deletion of any content currently being preserved" (README.md section 12). This
    script never deletes mailbox/SharePoint content itself -- it only removes the eDiscovery
    hold that was preserving it; whatever normal retention/deletion processing already applies
    (or doesn't) to that location resumes once the hold is gone, per rollback.md "What rollback
    does not undo."

.PARAMETER CaseId
    The eDiscoveryCase id to act on.

.PARAMETER HoldId
    The ediscoveryHoldPolicy id to act on.

.PARAMETER UserSourceEmail
    One or more userSource email addresses to remove from the hold. If omitted (and
    -SiteSourceUrl is also omitted), every userSource and siteSource currently on the hold is
    removed -- functionally equivalent to (but not the same API call as) deleting the policy;
    prefer -DeleteHold for that case, since it also clears the policy object itself.

.PARAMETER SiteSourceUrl
    One or more SharePoint site URLs to remove from the hold.

.PARAMETER DeleteHold
    Permanently delete the entire hold policy object (all its sources with it) rather than
    removing sources individually. Not reversible -- re-establishing the hold means re-running
    deploy/New-EdiscoveryLocationHold.ps1 against a new hold policy.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy script.

.EXAMPLE
    ./Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId `
        -UserSourceEmail 'payments-compliance-dl@contoso.com' `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports that this run would remove one named location, without removing anything.

.EXAMPLE
    ./Remove-EdiscoveryLocationHold.ps1 -CaseId $caseId -HoldId $holdId -DeleteHold `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Permanently deletes the entire hold policy after the loud confirmation prompt (or
    unattended, if -Confirm:$false is also supplied by the caller).

.NOTES
    Grounded in Microsoft Learn: Delete userSource / Delete siteSource
    (DELETE .../legalHolds/{id}/userSources/{id} and .../siteSources/{id}) and Delete
    ediscoveryHoldPolicy (DELETE .../legalHolds/{id}), all v1.0. No typed cmdlet exists for any
    of these three operations (design.md section 4) -- Invoke-MgGraphRequest is used throughout,
    matching New-EdiscoveryLocationHold.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$CaseId,

    [Parameter(Mandatory)]
    [string]$HoldId,

    [string[]]$UserSourceEmail,
    [string[]]$SiteSourceUrl,

    [switch]$DeleteHold,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphBase = 'https://graph.microsoft.com/v1.0'
$holdBaseUri = "$script:GraphBase/security/cases/ediscoveryCases/$CaseId/legalHolds/$HoldId"

if (Get-MgContext) {
    Write-Verbose 'Reusing existing Microsoft Graph connection.'
} else {
    $connectParams = @{ ClientId = $AppId; TenantId = $TenantId; NoWelcome = $true }
    if ($Certificate) { $connectParams['Certificate'] = $Certificate }
    else { $connectParams['CertificateThumbprint'] = $CertificateThumbprint }
    Connect-MgGraph @connectParams
}

if ($DeleteHold) {
    Write-Warning "Deleting hold policy $HoldId releases every location in it at once. Microsoft's own documentation: 'When you delete a hold policy, you remove all associated holds and release all sites and mailboxes. This action might result in permanent deletion of any content currently being preserved.' Confirm the preservation duty for every location in this policy has actually lapsed before continuing (rollback.md)."
    if ($PSCmdlet.ShouldProcess($HoldId, 'PERMANENTLY DELETE eDiscovery location-scoped hold policy')) {
        Invoke-MgGraphRequest -Method DELETE -Uri $holdBaseUri | Out-Null
        Write-Host "Deleted hold policy $HoldId. This cannot be undone -- see rollback.md."
    }
    Write-Host 'Done.'
    return
}

$userSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdBaseUri/userSources").value)
$siteSources = @((Invoke-MgGraphRequest -Method GET -Uri "$holdBaseUri/siteSources").value)

$userTargets = if ($UserSourceEmail) {
    $userSources | Where-Object { $_.email -in $UserSourceEmail }
} elseif (-not $SiteSourceUrl) {
    $userSources
} else {
    @()
}

$siteTargets = if ($SiteSourceUrl) {
    $siteTitles = $SiteSourceUrl | ForEach-Object { ($_ -split '/')[-1] }
    $siteSources | Where-Object { $_.displayName -in $siteTitles }
} elseif (-not $UserSourceEmail) {
    $siteSources
} else {
    @()
}

if (-not $userTargets -and -not $siteTargets) {
    Write-Host 'No matching userSources/siteSources found -- nothing to release.'
} else {
    foreach ($source in $userTargets) {
        if ($PSCmdlet.ShouldProcess($source.email, "Remove userSource from hold policy $HoldId")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$holdBaseUri/userSources/$($source.id)" | Out-Null
            Write-Host "Removed userSource '$($source.email)' from hold policy $HoldId."
        }
    }
    foreach ($source in $siteTargets) {
        if ($PSCmdlet.ShouldProcess($source.displayName, "Remove siteSource from hold policy $HoldId")) {
            Invoke-MgGraphRequest -Method DELETE -Uri "$holdBaseUri/siteSources/$($source.id)" | Out-Null
            Write-Host "Removed siteSource '$($source.displayName)' from hold policy $HoldId."
        }
    }
}

Write-Host 'Done. The hold policy object itself still exists -- pass -DeleteHold to remove it entirely, or re-run deploy/New-EdiscoveryLocationHold.ps1 to add locations back.'
```