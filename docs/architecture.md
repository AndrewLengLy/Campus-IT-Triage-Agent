# Architecture

The Campus IT Triage Agent is a Service Cloud backend for Agentforce. Conversation handling stays in Agent Builder. This project owns the actions, routing rules, known-issue catalog, SLA targets, and the append-only audit trail.

## Request path

```
Student request
    → Find Campus IT Self-Service Guide
        → walk through Resolution Steps
        → if they fail or Requires Escalation = true
    → Escalate Campus IT Ticket
        → reuse an open Case in the same category, or insert a new Case
        → stamp Agent Sourced, first-response due, and optional self-service context
        → publish a Case Comment
    → Add Campus IT Ticket Update     (more detail on an open ticket)
    → Check Campus IT Ticket Status
    → Get Campus IT Operations Snapshot   (desk load and today's deflection)
    → every action writes Campus_IT_Interaction__c
```

## Why the work is split this way

| Concern | Where it lives | Why |
| --- | --- | --- |
| What the agent says | Agent Builder topic | Product copy changes without a deploy. |
| What the agent is allowed to do | Five `@InvocableMethod` classes | One action, one job, bulk-safe lists. |
| Where a ticket goes | `IT_Category_Queue_Map__mdt` + `ITDeskRoutingService` | Admins change queues without Apex. |
| Which issues stay in chat | `IT_Known_Issue__mdt` | Service desk owns the catalog. |
| How fast a human should answer | `IT_SLA_Rule__mdt` | First-response hours by priority. |
| Whether the desk is working | `Campus_IT_Interaction__c` + operations snapshot | Deflection and load are measured, not guessed. |

Shared helpers stay out of Agent Builder:

- `ITDeskRoutingService` — priority, category, queue, Contact, Case reuse, published comments
- `ITDeskAuditService` — interaction rows and first-response due dates. Writes never throw into the student path.

## Data the agent leaves behind

**Case** (technician work)

- `Student_ID__c`, `IT_Category__c`
- `Agent_Sourced__c`, `Reused_Existing_Ticket__c`
- `Self_Service_Attempted__c`, `Self_Service_Article__c`
- `First_Response_Due__c` from the SLA rule for that priority

**Campus IT Interaction** (operations / risk)

- Action type, outcome, success flag
- Student ID, Case lookup, Case Number, category, article title, summary
- Autonumber `INT-00000`
- Before-update and before-delete trigger blocks edits so the trail stays append-only

## Action contracts

Each class takes `List<Request>` and returns `List<Result>` in the same order. Atlas binds slots from the `@InvocableVariable` labels.

| Action | Class | Writes |
| --- | --- | --- |
| Find Campus IT Self-Service Guide | `ITDeskSelfService` | Interaction only |
| Escalate Campus IT Ticket | `ITDeskTicketEscalation` | Case, Case Comment, Interaction |
| Add Campus IT Ticket Update | `ITDeskTicketUpdate` | Case Comment, Interaction |
| Check Campus IT Ticket Status | `ITDeskTicketStatus` | Interaction |
| Get Campus IT Operations Snapshot | `ITDeskOperationsSnapshot` | Interaction (snapshot) |

## Operating queries the snapshot uses

Open load: open Cases where `Agent_Sourced__c = true`, optionally filtered by queue name.

Today's deflection:

```
self-service matches today
÷ (self-service matches today + new escalations today)
```

Reused tickets do not count as new escalations. A high deflection rate means the catalog absorbed volume. A low rate with a long oldest wait means the desk needs people, not another chatbot prompt.
