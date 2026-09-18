---
part: "deploy"
parent: "insider-risk/irm-case-escalation-to-ediscovery"
---
The scripts and configuration below deploy this scenario. Review them, then run in order — each is designed to be idempotent and has a matching rollback.


#### `Confirm-EdiscoveryEscalationLink.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Finishes wiring an Insider Risk Management case's "Escalate for investigation" action to a
    fully provisioned eDiscovery (Premium) hold, and stamps a traceable provenance record onto
    the eDiscovery case linking it back to the source IRM case and alerts.

.DESCRIPTION
    Insider Risk Management's "Escalate for investigation" case action (portal-only -- see
    README.md section 5) opens a brand-new Microsoft Purview eDiscovery (Premium) case. Microsoft
    documents that this integration exists, but:
      1. There is no Microsoft Graph or PowerShell API to trigger the escalation itself -- it is a
         portal-only action (README.md section 3/11, design.md section 1).
      2. The resulting eDiscoveryCase object carries no property that names the source IRM case or
         its alerts -- microsoft.graph.security.ediscoveryCase's only free-text field is
         'description' (design.md section 2).
      3. Microsoft's own documentation for the escalation flow does not state that the flagged
         user is automatically added as a custodian with a hold applied -- it only confirms the
         case itself is created (design.md section 3).

    This script closes those last two gaps for a case an operator has ALREADY escalated from the
    portal (it never creates the eDiscoveryCase -- see the naming-convention prerequisite in
    README.md section 5 and design.md section 1):
      1. Find the escalated eDiscoveryCase by DisplayName (must already exist -- throws a clear,
         actionable error naming the missing portal step if it does not).
      2. Best-effort resolve each declared IRM alert ID via Get-MgSecurityAlertV2 -AlertId (Title/
         Severity only, for a human-readable provenance record -- a lookup failure is a Write-
         Warning, not a fatal error, since an alert can be merged into an incident or aged out
         after the case was escalated).
      3. Stamp (or, on re-run, confirm) a delimited "IRM ESCALATION PROVENANCE" block onto the
         case's description via Update-MgSecurityCaseEdiscoveryCase, preserving whatever text was
         already there (an investigator's own escalation notes) rather than overwriting it.
      4. Reconcile the flagged user as a custodian with a mailbox+OneDrive userSource and an
         applied hold, using the exact same find-or-create/applyHold pattern as
         scenarios/ediscovery/premium-legal-hold-and-export/deploy/New-EdiscoveryPremiumLegalHold.ps1
         (duplicated here, not dot-sourced across scenario directories, per this repo's
         one-scenario-one-self-contained-deploy-tree convention).

    Uses Microsoft Graph (automation surface 3 per docs/automation-surface.md), the only supported
    app-only path for eDiscovery (Premium) authoring -- see
    scenarios/ediscovery/premium-legal-hold-and-export/design.md section 1. Every mutating Graph
    cmdlet used here natively implements ShouldProcess, so -WhatIf on this script fans out to a
    true dry run -- no writes occur.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/escalation-link-definition.json's shape (irmCase:
    caseId, userPrincipalName, alertIds[]; ediscoveryCase: displayName).

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth. Must hold
    eDiscovery.ReadWrite.All (case description update, custodian, hold) and, only if -alertIds is
    non-empty, SecurityAlert.Read.All (alert lookup) -- see README.md section 3.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store, used
    for certificate-based app-only authentication. Mutually exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object (for example, resolved from Key Vault at run time) to use
    instead of -CertificateThumbprint. Mutually exclusive with -CertificateThumbprint.

.PARAMETER WaitForHold
    Poll HoldStatus after applying hold until it leaves 'notStarted'/'running', instead of
    firing-and-forgetting the applyHold call. Off by default, matching
    New-EdiscoveryPremiumLegalHold.ps1's own default.

.PARAMETER Force
    Required to proceed when the case already carries a provenance block for a DIFFERENT IRM case
    ID / user than this run's definition file -- normally a sign the case-naming convention
    (README.md section 5 step 2) was accidentally reused across two separate escalations. Without
    -Force the script throws rather than risk misattributing provenance; with -Force it appends an
    additional block rather than overwriting the existing one, so no prior provenance record is
    ever lost.

.EXAMPLE
    ./Confirm-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every description/custodian/userSource/hold action this run would take, without
    calling any mutating Graph endpoint. Still performs the case lookup and (if alertIds are
    declared) the read-only alert lookups, since neither mutates state.

.EXAMPLE
    ./Confirm-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Stamps the provenance block (if not already present) and reconciles the custodian/userSource/
    hold for the escalated case named in the definition file.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12 for the full citation list. Cmdlet/endpoint shapes used:
      - Get-MgSecurityCaseEdiscoveryCase (GET /security/cases/ediscoveryCases, filtered client-side
        on DisplayName -- no documented case-name filter API, same pattern as the sibling scenario)
      - Update-MgSecurityCaseEdiscoveryCase (PATCH .../ediscoveryCases/{id} -- description field)
      - Get-MgSecurityAlertV2 -AlertId (GET /security/alerts_v2/{id})
      - New-MgSecurityCaseEdiscoveryCaseCustodian, New-MgSecurityCaseEdiscoveryCaseCustodianUserSource,
        Add-MgSecurityCaseEdiscoveryCaseCustodianHold (identical to the sibling scenario)

    VERIFY before relying on this in production (see PROGRESS.md and README.md section 11):
      - The exact format of the "Case ID" the Insider Risk Management Cases dashboard displays is
        not confirmed against a pilot tenant (numeric, GUID, or another scheme) -- this script and
        the naming convention it depends on treat irmCase.caseId as an opaque display string only,
        never parsed or validated against a specific format.
      - Whether the portal's "Escalate for investigation" flow automatically adds the flagged user
        as a custodian with a hold applied is not documented either way by Microsoft. This script
        does not assume it did -- it unconditionally reconciles the custodian/userSource/hold to
        the declared target state, which is a safe no-op if the portal already did this work
        (find-or-create logic, identical to the sibling scenario) and a real fix if it did not.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [Parameter(Mandatory)]
    [string]$AppId,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Thumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'CertObject')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [switch]$WaitForHold,
    [int]$HoldPollTimeoutSeconds = 300,
    [int]$HoldPollIntervalSeconds = 15,

    # Confirm that a second, genuinely distinct IRM escalation is intentionally sharing an
    # eDiscovery case whose description already carries a provenance block for a different IRM
    # case/user -- see Confirm-ProvenanceBlock. Without -Force, a mismatch throws rather than
    # silently misattributing provenance.
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Delimits the block this script owns inside the case description, so a re-run can detect it
# (idempotent -- no duplicate block on a second run) without disturbing any text an investigator
# typed into the "Escalate for investigation" dialog's own notes field.
$ProvenanceMarkerStart = '--- IRM ESCALATION PROVENANCE (managed by irm-case-escalation-to-ediscovery; do not hand-edit between the markers) ---'
$ProvenanceMarkerEnd = '--- END IRM ESCALATION PROVENANCE ---'

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

function Get-EscalatedEdiscoveryCase {
    param([string]$DisplayName)

    $existing = Get-MgSecurityCaseEdiscoveryCase -All |
        Where-Object { $_.DisplayName -eq $DisplayName } |
        Select-Object -First 1
    if (-not $existing) {
        throw "No eDiscovery (Premium) case named '$DisplayName' was found. This script never " +
            "creates the case -- there is no Graph/PowerShell API for Insider Risk Management's " +
            "'Escalate for investigation' action (README.md section 3). Complete that portal step " +
            "first (README.md section 5), typing this exact name into the escalation dialog, then " +
            're-run this script.'
    }
    Write-Verbose "Found escalated case '$($existing.DisplayName)' (id=$($existing.Id))."
    return $existing
}

function Resolve-IrmAlertSummary {
    param([string[]]$AlertIds)

    $summaries = @()
    foreach ($alertId in $AlertIds) {
        try {
            $alert = Get-MgSecurityAlertV2 -AlertId $alertId
            $summaries += "  - $($alert.Id): [$($alert.Severity)] $($alert.Title)"
        } catch {
            Write-Warning "Could not resolve IRM alert '$alertId' via Get-MgSecurityAlertV2 (it may have been merged into an incident, or the automation identity lacks SecurityAlert.Read.All) -- recording the bare ID in the provenance block instead. Error: $($_.Exception.Message)"
            $summaries += "  - $alertId (title/severity unresolved at stamp time)"
        }
    }
    return $summaries
}

function Confirm-ProvenanceBlock {
    param($Case, $IrmCaseId, $UserPrincipalName, [string[]]$AlertSummaryLines, [switch]$Force)

    $existingDescription = if ($Case.Description) { $Case.Description } else { '' }
    if ($existingDescription -like "*$ProvenanceMarkerStart*") {
        $matchesThisDefinition = $existingDescription -like "*Source Insider Risk Management case: $IrmCaseId*" -and
            $existingDescription -like "*Escalated for user: $UserPrincipalName*"
        if ($matchesThisDefinition) {
            Write-Verbose "Provenance block already present on case '$($Case.DisplayName)' and matches this definition file -- leaving description unchanged."
            return
        }
        # A block exists but names a DIFFERENT IRM case/user than this run's definition file --
        # most likely the eDiscoveryCase displayName naming convention (README.md section 5 step
        # 2) was reused across two different escalations. Silently appending a second, conflicting
        # provenance record would misattribute this case's preservation justification -- fail
        # closed unless the operator explicitly confirms with -Force that a second, genuinely
        # distinct escalation legitimately landed on the same case name.
        if (-not $Force) {
            throw "Case '$($Case.DisplayName)' already carries a provenance block for a DIFFERENT " +
                "IRM case/user than this definition file declares (IrmCaseId='$IrmCaseId', " +
                "User='$UserPrincipalName'). This usually means the case-naming convention " +
                "(README.md section 5 step 2) was reused across two separate escalations -- " +
                'verify which escalation this case actually belongs to before proceeding. Re-run ' +
                'with -Force only if a second, genuinely distinct escalation is intentionally ' +
                'sharing this case, to append (never overwrite) an additional provenance block.'
        }
        Write-Warning "Appending an additional provenance block to case '$($Case.DisplayName)' under -Force -- the existing block is preserved, not replaced, so the case's provenance history stays intact."
    }

    $stampedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $blockLines = @(
        $ProvenanceMarkerStart
        "Source Insider Risk Management case: $IrmCaseId"
        "Escalated for user: $UserPrincipalName"
        "Linked via: manual portal 'Escalate for investigation' action, naming-convention match (design.md section 1)"
        'Insider Risk Management alerts at stamp time:'
    ) + @($AlertSummaryLines) + @(
        "Provenance stamped: $stampedUtc"
        $ProvenanceMarkerEnd
    )
    $block = $blockLines -join "`n"

    $newDescription = if ($existingDescription.Trim()) { "$existingDescription`n`n$block" } else { $block }

    if ($PSCmdlet.ShouldProcess($Case.DisplayName, 'Stamp IRM escalation provenance block onto case description')) {
        Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $Case.Id -BodyParameter @{ description = $newDescription } | Out-Null
        Write-Host "Stamped provenance block onto case '$($Case.DisplayName)'."
    }
}

function Get-OrNewCustodian {
    param($CaseId, [string]$Email)

    $existing = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.Email -eq $Email } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Custodian '$Email' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add custodian to case $CaseId")) {
        $created = New-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -Email $Email
        Write-Host "Added custodian '$($created.Email)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<custodian-id-pending>'; Email = $Email; HoldStatus = $null }
}

function Confirm-CustodianUserSource {
    param($CaseId, $CustodianId, [string]$Email)

    $existingSources = @()
    try {
        $existingSources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource `
            -EdiscoveryCaseId $CaseId -EdiscoveryCustodianId $CustodianId -All
    } catch {
        Write-Verbose "Could not list existing userSources for custodian $CustodianId (expected under -WhatIf on a not-yet-created custodian)."
    }
    if ($existingSources | Where-Object { $_.Email -eq $Email }) {
        Write-Verbose "userSource for '$Email' already exists on custodian $CustodianId."
        return
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add mailbox + OneDrive userSource to custodian $CustodianId")) {
        New-MgSecurityCaseEdiscoveryCaseCustodianUserSource -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $CustodianId -Email $Email -IncludedSources 'mailbox, site' | Out-Null
        Write-Host "Added userSource (mailbox, site) for '$Email'."
    }
}

function Confirm-CustodianHold {
    param($CaseId, $Custodian)

    if ($Custodian.HoldStatus -eq 'success') {
        Write-Verbose "Custodian $($Custodian.Email) is already on hold (HoldStatus=success)."
        return
    }

    if ($PSCmdlet.ShouldProcess($Custodian.Email, "Apply eDiscovery hold (case $CaseId)")) {
        Add-MgSecurityCaseEdiscoveryCaseCustodianHold -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $Custodian.Id | Out-Null
        Write-Host "Requested hold for custodian '$($Custodian.Email)'. Microsoft documents up to a 24-hour propagation window before the hold is fully in effect."

        if ($WaitForHold) {
            $elapsed = 0
            do {
                Start-Sleep -Seconds $HoldPollIntervalSeconds
                $elapsed += $HoldPollIntervalSeconds
                $refreshed = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId `
                    -EdiscoveryCustodianId $Custodian.Id
                Write-Verbose "  HoldStatus for $($Custodian.Email): $($refreshed.HoldStatus) (elapsed ${elapsed}s)"
            } while ($refreshed.HoldStatus -in @('notStarted', 'running', $null) -and $elapsed -lt $HoldPollTimeoutSeconds)

            if ($refreshed.HoldStatus -ne 'success') {
                Write-Warning "Custodian $($Custodian.Email) HoldStatus is '$($refreshed.HoldStatus)' after ${elapsed}s -- this does not necessarily indicate failure; re-check via validate/Test-EdiscoveryEscalationLink.ps1 later."
            }
        }
    }
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-EscalatedEdiscoveryCase -DisplayName $definition.ediscoveryCase.displayName

$alertSummaryLines = @('  (no alert IDs declared in the definition file)')
if ($definition.irmCase.alertIds -and $definition.irmCase.alertIds.Count -gt 0) {
    $alertSummaryLines = Resolve-IrmAlertSummary -AlertIds $definition.irmCase.alertIds
}

Confirm-ProvenanceBlock -Case $case -IrmCaseId $definition.irmCase.caseId `
    -UserPrincipalName $definition.irmCase.userPrincipalName -AlertSummaryLines $alertSummaryLines -Force:$Force

$custodian = Get-OrNewCustodian -CaseId $case.Id -Email $definition.irmCase.userPrincipalName
Confirm-CustodianUserSource -CaseId $case.Id -CustodianId $custodian.Id -Email $definition.irmCase.userPrincipalName
Confirm-CustodianHold -CaseId $case.Id -Custodian $custodian

Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)) is linked to IRM case '$($definition.irmCase.caseId)' and has a custodian hold reconciled for '$($definition.irmCase.userPrincipalName)'."
Write-Host 'Next: scenarios/ediscovery/premium-legal-hold-and-export/deploy/New-EdiscoverySearchReviewSetExport.ps1 to search, collect, and export -- this scenario does not duplicate that step.'
```

#### `policy/escalation-link-definition.json`

```json
{
  "irmCase": {
    "caseId": "IRM-2026-0143",
    "userPrincipalName": "jordan.reyes@contoso.com",
    "alertIds": [
      "00000000-0000-0000-0000-000000000001",
      "00000000-0000-0000-0000-000000000002"
    ]
  },
  "ediscoveryCase": {
    "displayName": "IRM-2026-0143-jordan.reyes"
  }
}
```

#### `Remove-EdiscoveryEscalationLink.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Undoes what Confirm-EdiscoveryEscalationLink.ps1 added: the provenance block it stamped onto
    the eDiscovery case description, and (opt-in) the custodian hold it applied.

.DESCRIPTION
    Deliberately narrow, staged rollback -- see rollback.md for the full procedure and why each
    stage is separately gated:
      1. Default (no switches): removes only the delimited "IRM ESCALATION PROVENANCE" block from
         the case description, leaving any other description text an investigator wrote untouched.
         Safe, reversible (re-run Confirm-EdiscoveryEscalationLink.ps1 to re-stamp it), and never
         touches the custodian/hold or the case itself.
      2. -ReleaseHold: additionally calls the custodian 'release' action (the same
         Invoke-MgGraphRequest POST .../custodians/{id}/release pattern as the sibling scenario's
         own Remove-EdiscoveryPremiumLegalHold.ps1) for the custodian named in the definition file.
         Releasing a hold this scenario placed for an active IRM investigation can itself be a
         preservation failure -- this switch exists for the case actually resolves as benign, not
         as a routine cleanup step. See rollback.md's counsel-confirmation gate.

    This script never closes or deletes the eDiscoveryCase itself, and never touches the source
    Insider Risk Management case (no Graph/PowerShell write API exists for either IRM case
    resolution or, per design.md section 1, the escalation relationship). Closing/deleting the
    case is scenarios/ediscovery/premium-legal-hold-and-export/deploy/Remove-EdiscoveryPremiumLegalHold.ps1's
    job -- deliberately not duplicated here, since it operates on the same case object this
    scenario only adds a custodian/provenance block to.

.PARAMETER DefinitionPath
    Path to the same JSON file passed to Confirm-EdiscoveryEscalationLink.ps1.

.PARAMETER ReleaseHold
    Also release the eDiscovery hold on the custodian named in the definition file. Requires
    written confirmation that the IRM case resolved in a way that ends the preservation duty --
    see rollback.md and the counsel-confirmation gate this scenario inherits from the sibling
    eDiscovery scenario.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as Confirm-EdiscoveryEscalationLink.ps1.

.EXAMPLE
    ./Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports what would be removed, makes no change.

.EXAMPLE
    ./Remove-EdiscoveryEscalationLink.ps1 -DefinitionPath ./policy/escalation-link-definition.json `
        -ReleaseHold -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Strips the provenance block AND releases the custodian's hold. Only run this after counsel
    has confirmed the preservation duty for this matter has lapsed (rollback.md).

.NOTES
    Grounded in Microsoft Learn -- same citation set as Confirm-EdiscoveryEscalationLink.ps1 and
    scenarios/ediscovery/premium-legal-hold-and-export/deploy/Remove-EdiscoveryPremiumLegalHold.ps1
    (README.md section 12). The custodian 'release' action has no typed Graph SDK cmdlet as of this
    build (same finding the sibling scenario already recorded) -- both scripts call it via
    Invoke-MgGraphRequest against the documented v1.0 REST action instead of a fabricated cmdlet
    name.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DefinitionPath,

    [switch]$ReleaseHold,

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

$ProvenanceMarkerStart = '--- IRM ESCALATION PROVENANCE (managed by irm-case-escalation-to-ediscovery; do not hand-edit between the markers) ---'
$ProvenanceMarkerEnd = '--- END IRM ESCALATION PROVENANCE ---'

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

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-MgSecurityCaseEdiscoveryCase -All |
    Where-Object { $_.DisplayName -eq $definition.ediscoveryCase.displayName } |
    Select-Object -First 1

if (-not $case) {
    Write-Warning "No eDiscovery case named '$($definition.ediscoveryCase.displayName)' was found -- nothing to roll back."
} else {
    $description = if ($case.Description) { $case.Description } else { '' }
    if ($description -like "*$ProvenanceMarkerStart*") {
        $pattern = [regex]::Escape($ProvenanceMarkerStart) + '.*?' + [regex]::Escape($ProvenanceMarkerEnd)
        $stripped = [regex]::Replace($description, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline).Trim()

        if ($PSCmdlet.ShouldProcess($case.DisplayName, 'Remove IRM escalation provenance block from case description')) {
            Update-MgSecurityCaseEdiscoveryCase -EdiscoveryCaseId $case.Id -BodyParameter @{ description = $stripped } | Out-Null
            Write-Host "Removed provenance block from case '$($case.DisplayName)'."
        }
    } else {
        Write-Verbose "No provenance block found on case '$($case.DisplayName)' -- description left untouched."
    }

    if ($ReleaseHold) {
        $custodian = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $case.Id -All |
            Where-Object { $_.Email -eq $definition.irmCase.userPrincipalName } |
            Select-Object -First 1

        if (-not $custodian) {
            Write-Warning "No custodian '$($definition.irmCase.userPrincipalName)' found on case '$($case.DisplayName)' -- nothing to release."
        } elseif ($custodian.HoldStatus -ne 'success') {
            Write-Verbose "Custodian '$($custodian.Email)' HoldStatus is '$($custodian.HoldStatus)', not 'success' -- skipping release."
        } elseif ($PSCmdlet.ShouldProcess($custodian.Email, "RELEASE eDiscovery hold (case $($case.Id)) -- confirm the preservation duty has lapsed; see rollback.md")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "/v1.0/security/cases/ediscoveryCases/$($case.Id)/custodians/$($custodian.Id)/release" | Out-Null
            Write-Host "Released hold for custodian '$($custodian.Email)'."
        }
    }
}

Write-Host 'Done. This script never closes/deletes the eDiscovery case or touches the source Insider Risk Management case -- see rollback.md for those separate, more destructive stages.'
```