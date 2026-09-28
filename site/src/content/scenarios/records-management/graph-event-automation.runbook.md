---
part: "runbook"
parent: "records-management/graph-event-automation"
---
## Implementation steps

```powershell
# Connect (app-only certificate preferred for a service integration - docs/automation-surface.md §3)
Connect-MgGraph -Scopes 'RecordsManagement.ReadWrite.All'

# 1. Dry run (real -WhatIf via the SDK) - shows the event type (and event, with -FireEvent) it would create
./deploy/New-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json -WhatIf

# 2. Ensure the event type exists (idempotent; starts NO clock)
./deploy/New-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json

# 3. Validate
./validate/Test-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json

# 4. LATER, from your business system, for a real dated event (irreversible; requires event.fire=true):
./deploy/New-GraphRetentionEvent.ps1 -ConfigPath ./deploy/config/graph-event-automation.json -FireEvent
```

### REST / raw HTTP (surface 3)

```http
POST https://graph.microsoft.com/v1.0/security/triggerTypes/retentionEventTypes
{ "@odata.type": "#microsoft.graph.security.retentionEventType", "displayName": "Contract Expiration" }

POST https://graph.microsoft.com/v1.0/security/triggers/retentionEvents
{
  "@odata.type": "#microsoft.graph.security.retentionEvent",
  "displayName": "Contract 4815 expired",
  "eventQuery": [ { "queryType": "files", "query": "ComplianceAssetID:4815" } ],
  "eventTriggerDateTime": "2026-09-04T00:00:00Z",
  "retentionEventType@odata.bind": "https://graph.microsoft.com/v1.0/security/triggerTypes/retentionEventTypes/{id}"
}
```

The scripts use `Invoke-MgGraphRequest` (works with both delegated and app-only tokens). The typed
`Microsoft.Graph.Security` cmdlets (`New-MgSecurityTriggerTypeRetentionEventType`,
`New-MgSecurityTriggerRetentionEvent`) are the equivalent path - see the configuration reference.

## Configuration reference

| Setting | Value this scenario uses | Notes |
|---|---|---|
| Event-type endpoint | `POST /security/triggerTypes/retentionEventTypes` | `displayName`, `description` |
| Event endpoint | `POST /security/triggers/retentionEvents` | Fires the event |
| `retentionEventType@odata.bind` | `.../triggerTypes/retentionEventTypes/{id}` | Binds the event to its type |
| `eventQuery[].queryType` | `files` (SPO/ODB) or `messages` (EXO) | Workload of the query |
| `eventQuery[].query` | `ComplianceAssetID:<id>` (files) / keywords (messages) | Scopes the event to specific content |
| `eventTriggerDateTime` | ISO 8601 timestamp | The date retention starts counting from |
| Typed cmdlets | `New-MgSecurityTriggerTypeRetentionEventType` / `New-MgSecurityTriggerRetentionEvent` | Microsoft.Graph.Security equivalents |
| Permission | `RecordsManagement.ReadWrite.All` | Read-only validate: `RecordsManagement.Read.All` |

Exact request bodies and Learn sources are cited in each script's `.NOTES`.

## Operations and tuning

**KPIs / signals:** **eventPropagationResults** status per workload (the Graph-native signal that a
fired event reached SharePoint/Exchange - this scenario's key advantage over the PowerShell path); count
of events fired vs. business events recorded (a gap means the integration is dropping triggers);
disposition backlog downstream. **Tuning:** always set a precise `eventQuery` (Asset ID / keywords) -
an event with no query starts retention for **all** content carrying that event-type label. For a high-volume integration, fire one event per business entity (per contract, per
employee) with its own Asset ID, rather than broad events.

**Change management:** treat the app registration and its `RecordsManagement.ReadWrite.All` grant as a
high-privilege records identity - an app that can fire retention events can start irreversible retention.
Scope it to app-only with a certificate, monitor its activity, and keep the config under version
control.

## Rollback and decommission

See the rollback runbook. Quick reference: `./deploy/Remove-GraphRetentionEvent.ps1` deletes retention **event
records** matching the config's `event.displayName`; `-DeleteEventType` also removes the event type (if
unreferenced). **Deleting an event does not stop retention it already started** - that's bookkeeping
only, by the platform's design. There is no supported "un-fire".

## References

1. Start retention when an event occurs (event-based retention; can't-cancel; ≤7-day sync; asset-ID scoping) - <https://learn.microsoft.com/purview/event-driven-retention>
2. Automate events by using Graph API (REST event API deprecated → use Microsoft Graph) - <https://learn.microsoft.com/purview/event-driven-retention#automate-events-by-using-powershell>
3. Use the Microsoft Graph records management APIs (overview; trigger events for an existing label) - <https://learn.microsoft.com/graph/api/resources/security-recordsmanagement-overview>
4. Microsoft Graph permissions reference (RecordsManagement.ReadWrite.All / .Read.All) - <https://learn.microsoft.com/graph/permissions-reference>
5. retentionEvent resource type (methods: list/create/get/delete) - <https://learn.microsoft.com/graph/api/resources/security-retentionevent>
6. Microsoft Purview service description - Records Management licensing - <https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description>
7. Create retentionEventType (POST /security/triggerTypes/retentionEventTypes) - <https://learn.microsoft.com/graph/api/security-retentioneventtype-post>
8. Create retentionEvent (POST /security/triggers/retentionEvents; eventQuery, eventTriggerDateTime, retentionEventType@odata.bind; RecordsManagement.ReadWrite.All) - <https://learn.microsoft.com/graph/api/security-retentionevent-post>
9. eventQuery resource type (queryType files|messages; query = Asset ID / keywords) - <https://learn.microsoft.com/graph/api/resources/security-eventquery>
10. New-MgSecurityTriggerRetentionEvent / New-MgSecurityTriggerTypeRetentionEventType (Microsoft.Graph.Security) - <https://learn.microsoft.com/powershell/module/microsoft.graph.security/new-mgsecuritytriggerretentionevent>

> Re-verify all links, endpoints, permission names, and the irreversibility behaviors against current
> Microsoft Learn before a customer-facing deployment. Firing an event is irreversible - the scenario is
> deliberately conservative (real `-WhatIf`, double-gated event, create-or-report event type).