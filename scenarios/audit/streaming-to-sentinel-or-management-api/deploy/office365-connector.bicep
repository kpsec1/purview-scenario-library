// office365-connector.bicep
//
// Enables the native Microsoft Sentinel "Microsoft 365 (formerly, Office 365)" data connector
// (ARM/Bicep kind: 'Office365') on an existing Log Analytics workspace with Sentinel already
// onboarded. Streams Exchange/SharePoint/Teams admin+user activity into the OfficeActivity table -
// a free Log Analytics data source (no per-GB ingestion charge). Does NOT cover Entra ID audit
// (Audit.AzureActiveDirectory) or DLP.All - see deploy/Enable-ManagementActivitySubscriptions.ps1
// (Path B) and README.md Section 3 for that coverage gap.
//
// Idempotent: Bicep/ARM deployment is declarative - re-deploying with the same parameters converges
// to the same connector state rather than erroring or duplicating. Preview with native what-if
// before applying (see README.md Section 5):
//   New-AzResourceGroupDeployment -WhatIf -ResourceGroupName <rg> \
//     -TemplateFile ./office365-connector.bicep -workspaceName <name> -tenantId <tenantGuid>
//
// Grounded in Microsoft Learn (verify before production use):
// - Microsoft.SecurityInsights dataConnectors resource format (Office365 kind):
//   https://learn.microsoft.com/azure/templates/microsoft.securityinsights/2024-03-01/dataconnectors
// - Connect Office 365 logs to Microsoft Sentinel (portal path, OfficeActivity table):
//   https://learn.microsoft.com/azure/sentinel/connect-office-365
// - Microsoft Sentinel free data sources (Office 365 Audit Logs are free):
//   https://learn.microsoft.com/azure/sentinel/billing#free-data-sources
// - ARM/Bicep what-if:
//   https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if
//
// VERIFY (pilot tenant): whether the data-connector resource `name` must be a GUID (several
// Microsoft samples for other connector kinds use one) or accepts an arbitrary string for the
// Office365 kind specifically - this template defaults to a deterministic GUID (guid()) so re-runs
// target the same resource, but Microsoft's Office365-kind reference page does not state the name
// constraint explicitly.

@description('Name of the existing Log Analytics workspace that has Microsoft Sentinel enabled.')
param workspaceName string

@description('Microsoft Entra tenant ID whose Office 365 activity this connector streams.')
param tenantId string = tenant().tenantId

@description('Enable the Exchange admin/user activity data type.')
@allowed(['Enabled', 'Disabled'])
param exchangeState string = 'Enabled'

@description('Enable the SharePoint (and OneDrive) activity data type.')
@allowed(['Enabled', 'Disabled'])
param sharePointState string = 'Enabled'

@description('Enable the Microsoft Teams activity data type.')
@allowed(['Enabled', 'Disabled'])
param teamsState string = 'Enabled'

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

// Deterministic name so repeat deployments target the same connector resource instead of
// creating duplicates (see the VERIFY note above re: the exact naming contract for this kind).
var connectorName = guid(workspace.id, 'office365-data-connector')

resource office365Connector 'Microsoft.SecurityInsights/dataConnectors@2024-03-01' = {
  name: connectorName
  scope: workspace
  kind: 'Office365'
  properties: {
    tenantId: tenantId
    dataTypes: {
      exchange: {
        state: exchangeState
      }
      sharePoint: {
        state: sharePointState
      }
      teams: {
        state: teamsState
      }
    }
  }
}

@description('Resource ID of the deployed (or already-existing, if unchanged) Office 365 data connector.')
output connectorId string = office365Connector.id

@description('Resource name of the connector - stable across re-deployments, derived from the workspace ID.')
output connectorName string = connectorName
