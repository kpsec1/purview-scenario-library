---
part: "validate"
parent: "insider-risk/irm-case-escalation-to-ediscovery"
---
Run these checks after deployment to confirm the control is working as designed.


#### `Test-EdiscoveryEscalationLink.ps1`

```powershell
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Security'; ModuleVersion = '2.25.0' }
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.25.0' }

<#
.SYNOPSIS
    Read-only validation that an escalated eDiscovery (Premium) case carries the IRM provenance
    block, and has a reconciled custodian/userSource/hold for the escalated user.

.DESCRIPTION
    Never calls a mutating Graph endpoint -- eDiscovery.Read.All and (only if the definition
    file's alertIds are non-empty) SecurityAlert.Read.All are sufficient. Checks, each reported
    PASS/WARN/FAIL:
      1. The eDiscoveryCase named in the definition file exists.
      2. Its description contains the delimited provenance block, and the block's IRM case ID and
         user match the definition file (catches a stale/hand-edited description).
      3. A custodian matching irmCase.userPrincipalName exists on the case.
      4. That custodian has a userSource covering 'mailbox, site'.
      5. That custodian's HoldStatus is 'success' (WARN, not FAIL, if it's still propagating --
         mirrors the sibling scenario's Test-EdiscoveryPremiumCaseSetup.ps1 24-hour-window logic).
      6. Best-effort: each declared alertId still resolves via Get-MgSecurityAlertV2 (WARN, not
         FAIL, on a lookup miss -- an alert can be legitimately merged into an incident after
         escalation; this is informational, not a correctness signal for the escalation link
         itself).

    Exits non-zero if any hard FAIL is found (safe for a CI-style pre-flight or a scheduled drift
    check), matching this repo's established validate/ exit-code convention.

.PARAMETER DefinitionPath
    Path to the same JSON file passed to the deploy scripts.

.PARAMETER AppId
.PARAMETER TenantId
.PARAMETER CertificateThumbprint
.PARAMETER Certificate
    Same Graph app-only authentication parameters as the deploy scripts. eDiscovery.Read.All is
    sufficient unless alertIds are declared, in which case SecurityAlert.Read.All is also needed.

.EXAMPLE
    ./Test-EdiscoveryEscalationLink.ps1 -DefinitionPath ./deploy/policy/escalation-link-definition.json `
        -AppId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint

.NOTES
    Grounded in Microsoft Learn -- same citation set as the deploy scripts (README.md section 12).
#>
[CmdletBinding()]
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
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProvenanceMarkerStart = '--- IRM ESCALATION PROVENANCE (managed by irm-case-escalation-to-ediscovery; do not hand-edit between the markers) ---'

$script:HardFailures = 0

function Write-CheckResult {
    param([ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status, [string]$Message)
    switch ($Status) {
        'PASS' { Write-Host "[$Status] $Message" -ForegroundColor Green }
        'WARN' { Write-Host "[$Status] $Message" -ForegroundColor Yellow }
        'FAIL' { Write-Host "[$Status] $Message" -ForegroundColor Red; $script:HardFailures++ }
    }
}

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
    Write-CheckResult FAIL "eDiscovery case '$($definition.ediscoveryCase.displayName)' not found -- the portal 'Escalate for investigation' step (README.md section 5) has not been completed, or the definition file's displayName doesn't match what was typed into the dialog."
    exit 1
}
Write-CheckResult PASS "eDiscovery case '$($case.DisplayName)' (id=$($case.Id)) exists."

$description = if ($case.Description) { $case.Description } else { '' }
if ($description -notlike "*$ProvenanceMarkerStart*") {
    Write-CheckResult FAIL "Case description has no IRM escalation provenance block -- run deploy/Confirm-EdiscoveryEscalationLink.ps1."
} else {
    $caseIdOk = $description -like "*Source Insider Risk Management case: $($definition.irmCase.caseId)*"
    $userOk = $description -like "*Escalated for user: $($definition.irmCase.userPrincipalName)*"
    if ($caseIdOk -and $userOk) {
        Write-CheckResult PASS 'Provenance block present and matches the definition file (IRM case ID + escalated user).'
    } else {
        Write-CheckResult FAIL 'Provenance block present but does NOT match the definition file (stale stamp from a prior run with different values, or a hand-edit) -- re-run Confirm-EdiscoveryEscalationLink.ps1 after reconciling the definition file with the actual case.'
    }
}

$custodian = Get-MgSecurityCaseEdiscoveryCaseCustodian -EdiscoveryCaseId $case.Id -All |
    Where-Object { $_.Email -eq $definition.irmCase.userPrincipalName } |
    Select-Object -First 1

if (-not $custodian) {
    Write-CheckResult FAIL "No custodian '$($definition.irmCase.userPrincipalName)' found on case '$($case.DisplayName)' -- run deploy/Confirm-EdiscoveryEscalationLink.ps1."
} else {
    Write-CheckResult PASS "Custodian '$($custodian.Email)' (id=$($custodian.Id)) exists on the case."

    $userSources = Get-MgSecurityCaseEdiscoveryCaseCustodianUserSource `
        -EdiscoveryCaseId $case.Id -EdiscoveryCustodianId $custodian.Id -All
    $matchingSource = $userSources | Where-Object { $_.Email -eq $custodian.Email }
    if ($matchingSource) {
        Write-CheckResult PASS "Custodian has a userSource for '$($custodian.Email)'."
    } else {
        Write-CheckResult FAIL "Custodian has no userSource for '$($custodian.Email)' -- mailbox/OneDrive are not covered by any hold."
    }

    if ($custodian.HoldStatus -eq 'success') {
        Write-CheckResult PASS "Custodian HoldStatus is 'success'."
    } elseif ($custodian.HoldStatus -in @('notStarted', 'running', $null)) {
        Write-CheckResult WARN "Custodian HoldStatus is '$($custodian.HoldStatus)' -- Microsoft documents up to a 24-hour propagation window; re-run this check later before treating this as a failure."
    } else {
        Write-CheckResult FAIL "Custodian HoldStatus is '$($custodian.HoldStatus)' -- not on hold."
    }
}

if ($definition.irmCase.alertIds -and $definition.irmCase.alertIds.Count -gt 0) {
    foreach ($alertId in $definition.irmCase.alertIds) {
        try {
            $alert = Get-MgSecurityAlertV2 -AlertId $alertId
            Write-CheckResult PASS "IRM alert '$alertId' resolves (title: '$($alert.Title)')."
        } catch {
            Write-CheckResult WARN "IRM alert '$alertId' does not resolve via Get-MgSecurityAlertV2 (merged into an incident, aged out, or a permission gap) -- informational only, does not affect the escalation link's own validity."
        }
    }
}

Write-Host ''
if ($script:HardFailures -gt 0) {
    Write-Host "$script:HardFailures hard failure(s) found." -ForegroundColor Red
    exit 1
}
Write-Host 'All hard checks passed (WARNs, if any, are informational).' -ForegroundColor Green
exit 0
```