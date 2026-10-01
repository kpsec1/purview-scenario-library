#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Creates (or reconciles) a Microsoft Purview eDiscovery (Premium) case, adds one or more
    custodians, and places a legal hold on each custodian's Exchange mailbox and OneDrive site.

.DESCRIPTION
    Idempotent, parameterized deploy script for the first stage of the eDiscovery (Premium)
    legal-hold-and-export scenario. Uses Microsoft Graph (automation surface 3 per
    docs/automation-surface.md) because app-only authentication for eDiscovery cmdlets in
    Security & Compliance PowerShell is explicitly unsupported by Microsoft -- see
    docs/automation-surface.md section 3 and README.md section 5.

    Stages, each individually idempotent (re-running this script after a partial failure is safe):
      1. Find-or-create the eDiscoveryCase by DisplayName.
      2. Find-or-create each custodian by email.
      3. Find-or-create each custodian's userSource (mailbox + OneDrive site).
      4. Apply hold to every custodian whose HoldStatus isn't already 'success'.

    Every mutating Graph cmdlet used here (New-MgSecurityCaseEdiscoveryCase,
    New-MgSecurityCaseEdiscoveryCaseCustodian, New-MgSecurityCaseEdiscoveryCaseCustodianUserSource,
    Add-MgSecurityCaseEdiscoveryCaseCustodianHold) natively implements ShouldProcess, so -WhatIf
    on this script fans out to a true dry run on every Graph call -- no writes occur.

.PARAMETER DefinitionPath
    Path to a JSON file matching deploy/policy/ediscovery-case-definition.json's shape (case,
    custodians[]). Keeps the case/custodian list out of the script body.

.PARAMETER AppId
    Application (client) ID of the Entra app registration used for Graph app-only auth.

.PARAMETER TenantId
    Directory (tenant) ID.

.PARAMETER CertificateThumbprint
    Thumbprint of the client certificate installed in the current user's certificate store,
    used for certificate-based app-only authentication (docs/automation-surface.md section 3).
    Mutually exclusive with -Certificate.

.PARAMETER Certificate
    An in-memory X509Certificate2 object (for example, resolved from Key Vault at run time) to
    use instead of -CertificateThumbprint. Prefer this in a CI/CD pipeline so the private key is
    never written to disk. Mutually exclusive with -CertificateThumbprint.

.EXAMPLE
    ./New-EdiscoveryPremiumLegalHold.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -WhatIf

    Reports every case/custodian/userSource/hold action this run would take, without calling any
    mutating Graph endpoint.

.EXAMPLE
    ./New-EdiscoveryPremiumLegalHold.ps1 -DefinitionPath ./policy/ediscovery-case-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

    Creates the case (if it doesn't already exist), adds any missing custodians and userSources,
    and applies hold to every custodian not already on hold.

.NOTES
    Grounded in Microsoft Learn (Microsoft Graph API reference, v1.0, microsoft.graph.security
    namespace) -- see README.md section 12 for the full citation list. Cmdlet names and request
    shapes used here:
      - New-MgSecurityCaseEdiscoveryCase                    (POST /security/cases/ediscoveryCases)
      - New-MgSecurityCaseEdiscoveryCaseCustodian            (POST .../custodians)
      - New-MgSecurityCaseEdiscoveryCaseCustodianUserSource  (POST .../custodians/{id}/userSources)
      - Add-MgSecurityCaseEdiscoveryCaseCustodianHold        (POST .../custodians/{id}/applyHold)

    VERIFY before relying on this in production: Microsoft's own hold-creation guidance states a
    newly applied eDiscovery hold can take up to 24 hours to take effect (README.md section 11,
    reference 8) -- this script's -WaitForHold switch polls HoldStatus but does not itself wait
    out that propagation window; a 'success' HoldStatus reflects Graph's own state, not confirmed
    end-to-end preservation, which Microsoft does not expose an API to confirm directly.
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

    # Poll HoldStatus after applying hold until it leaves 'notStarted'/'running', instead of
    # firing-and-forgetting the applyHold call. Off by default -- hold application is
    # asynchronous and this script is meant to be safe to re-run rather than to block.
    [switch]$WaitForHold,

    [int]$HoldPollTimeoutSeconds = 300,
    [int]$HoldPollIntervalSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    param($Definition, [switch]$WhatIfPreference)

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
    # -WhatIf path: nothing was created, return a placeholder so downstream -WhatIf reporting
    # can still describe what it *would* do against this case.
    return [pscustomobject]@{ Id = '<case-id-pending>'; DisplayName = $Definition.displayName }
}

function Get-OrNewCustodian {
    param($CaseId, $CustodianDef)

    $existing = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId -All |
        Where-Object { $_.Email -eq $CustodianDef.email } |
        Select-Object -First 1
    if ($existing) {
        Write-Verbose "Custodian '$($CustodianDef.email)' already exists (id=$($existing.Id))."
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($CustodianDef.email, "Add custodian to case $CaseId")) {
        $created = New-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $CaseId `
            -Email $CustodianDef.email
        Write-Host "Added custodian '$($created.Email)' (id=$($created.Id))."
        return $created
    }
    return [pscustomobject]@{ Id = '<custodian-id-pending>'; Email = $CustodianDef.email; HoldStatus = $null }
}

function Confirm-CustodianUserSource {
    param($CaseId, $CustodianId, $Email)

    $existingSources = @()
    try {
        $existingSources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource `
            -EdiscoveryCaseId $CaseId -EdiscoveryCustodianId $CustodianId -All
    } catch {
        # A pending (-WhatIf) custodian has no real ID to query against yet -- treat as empty.
        Write-Verbose "Could not list existing userSources for custodian $CustodianId (expected under -WhatIf on a not-yet-created custodian)."
    }
    if ($existingSources | Where-Object { $_.Email -eq $Email }) {
        Write-Verbose "userSource for '$Email' already exists on custodian $CustodianId."
        return
    }

    if ($PSCmdlet.ShouldProcess($Email, "Add mailbox + OneDrive userSource to custodian $CustodianId")) {
        # Microsoft's v1.0 "Create custodian userSource" reference worked example POSTs
        # includedSources = 'mailbox' alone and its own response shows the resulting userSource
        # with includedSources = 'mailbox,site' -- confirming the API includes the custodian's
        # OneDrive/SharePoint site automatically and that 'mailbox' is the documented, confirmed
        # v1.0 request value. See README.md section 12 reference 23 (Create custodian userSource).
        New-MgSecurityCaseEdiscoveryCaseCustodianUserSource -EdiscoveryCaseId $CaseId `
            -EdiscoveryCustodianId $CustodianId -Email $Email -IncludedSources 'mailbox' | Out-Null
        Write-Host "Added userSource (mailbox + site) for '$Email'."
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
        Write-Host "Requested hold for custodian '$($Custodian.Email)'. This is asynchronous -- Microsoft documents up to a 24-hour propagation window before the hold is fully in effect (README.md section 11)."

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
                Write-Warning "Custodian $($Custodian.Email) HoldStatus is '$($refreshed.HoldStatus)' after ${elapsed}s -- this does not necessarily indicate failure (hold application can legitimately take longer than this poll window); re-check via validate/Test-EdiscoveryPremiumCaseSetup.ps1 later rather than treating this as an error."
            }
        }
    }
}

# --- main ---

$definition = Get-Content -Path $DefinitionPath -Raw | ConvertFrom-Json

Connect-EdiscoveryGraph -AppId $AppId -TenantId $TenantId `
    -CertificateThumbprint $CertificateThumbprint -Certificate $Certificate

$case = Get-OrNewEdiscoveryCase -Definition $definition.case

foreach ($custodianDef in $definition.custodians) {
    $custodian = Get-OrNewCustodian -CaseId $case.Id -CustodianDef $custodianDef
    Confirm-CustodianUserSource -CaseId $case.Id -CustodianId $custodian.Id -Email $custodianDef.email
    Confirm-CustodianHold -CaseId $case.Id -Custodian $custodian
}

Write-Host "Done. Case '$($case.DisplayName)' (id=$($case.Id)) has $($definition.custodians.Count) custodian(s) reconciled."
Write-Host 'Next: ./New-EdiscoverySearchReviewSetExport.ps1 to search, collect into a review set, and export.'
