# Campus IT Service Desk Triage Agent

Salesforce DX backend for an Agentforce agent that sits in Service Cloud. The agent tries a known-issue guide first, escalates what it cannot fix, reuses an open ticket when the problem is the same, takes follow-up comments, reports status, and publishes an operations snapshot. Every action writes an append-only audit row.

**80-second walkthrough (captioned, watch muted):** [docs/demo/campus-it-triage-agent-demo.mp4](docs/demo/campus-it-triage-agent-demo.mp4)

Configure the agent persona, topics, and (optional) Knowledge articles in Agent Builder. This repo is the invocable Apex and supporting metadata.

## How the pieces connect

```
Student request
    → Find Campus IT Self-Service Guide   (try this first)
        → walk through Resolution Steps
        → if they fail or Requires Escalation = true
    → Escalate Campus IT Ticket
        → reuse open Case in the same category, or insert a new Case
        → stamp SLA first-response due, agent-sourced, optional self-service context
        → publish a Case Comment; set ContactId and SuppliedEmail when known
    → Add Campus IT Ticket Update         (more detail on an existing ticket)
    → Check Campus IT Ticket Status
    → Get Campus IT Operations Snapshot   (open load, oldest wait, today's deflection)
    → Agent speaks the Case Number / next steps
    → Campus_IT_Interaction__c records the action
```

| Action in Agent Builder | Apex class | When to call |
| --- | --- | --- |
| Find Campus IT Self-Service Guide | `ITDeskSelfService` | First. WiFi, password, VPN, Outlook, MFA, laptop power, and similar. |
| Escalate Campus IT Ticket | `ITDeskTicketEscalation` | No guide, steps already failed, or the student asks for a human. |
| Add Campus IT Ticket Update | `ITDeskTicketUpdate` | Student has more detail for an existing ticket. |
| Check Campus IT Ticket Status | `ITDeskTicketStatus` | "What's going on with my ticket?" |
| Get Campus IT Operations Snapshot | `ITDeskOperationsSnapshot` | Supervisor load question, or "how backed up is the desk?" |

Supporting metadata: `ITDeskRoutingService`, `ITDeskAuditService`, `IT_Category_Queue_Map__mdt`, `IT_Known_Issue__mdt`, `IT_SLA_Rule__mdt`, `Campus_IT_*` queues, Case operational fields, `Campus_IT_Interaction__c`, `Campus_IT` Lightning app, `Campus_IT_Triage_Agent` permission set.

| Doc | What it is for |
| --- | --- |
| [`docs/agent-builder-topic.md`](docs/agent-builder-topic.md) | Paste-ready topic instructions |
| [`docs/architecture.md`](docs/architecture.md) | Action contracts and data the agent writes |
| [`docs/operating-model.md`](docs/operating-model.md) | Who edits metadata, SLA, deflection |
| [`docs/demo-script.md`](docs/demo-script.md) | Eight-minute walkthrough with demo Student IDs |

Keep Agent Builder instruction text in sync with the Apex `label` / `description` values if you edit either side.

Lookups tolerate messy speech: Student ID `s 1000-0001` stores as `S10000001`, and Case Number `1234` matches `00001234`. Status falls back to Student ID when the Case Number is wrong. Updates on closed tickets are rejected. Interaction rows cannot be edited or deleted.

## Authorize and deploy (Developer org)

```bash
sf version
sf org login web --alias campus-it-dev --set-default --instance-url https://login.salesforce.com

sf project deploy start --source-dir force-app --target-org campus-it-dev --wait 10

sf apex run test --tests ITDeskTicketEscalationTest --tests ITDeskTicketStatusTest --tests ITDeskSelfServiceTest --tests ITDeskTicketUpdateTest --tests ITDeskDemoDataTest --tests ITDeskAuditServiceTest --tests ITDeskOperationsSnapshotTest --target-org campus-it-dev --code-coverage --result-format human --wait 10

sf org assign permset --name Campus_IT_Triage_Agent --target-org campus-it-dev

sf apex run --file scripts/apex/createDemoData.apex --target-org campus-it-dev
```

Sandbox login uses `--instance-url https://test.salesforce.com`. Developer orgs need `sf project deploy start`, not `sf project push`.

Demo Contacts after the script: **S10000001** Alex Rivera, **S10000002** Jordan Chen, **S10000003** Sam Patel. The first run also seeds a self-service match, a High hardware ticket, and status lookups so the app and snapshot are not empty.

## Agent Builder setup (you still do this in the UI)

1. Create the Campus IT Service Desk agent and persona.
2. Add a topic such as "Student IT triage".
3. Add the five Apex actions above to that topic.
4. Paste the topic instructions from [`docs/agent-builder-topic.md`](docs/agent-builder-topic.md).
5. App Launcher → **Campus IT** for Cases, Contacts, and Interactions. Assign the **Campus IT Case** page layout and compact layout on Case if you want Student ID and first-response due in highlights.

## Routing, known issues, and SLA (no hardcoded IDs)

Edit in **Setup → Custom Metadata Types**:

- `IT_Category_Queue_Map` — keyword / aliases → queue DeveloperName
- `IT_Known_Issue` — self-service articles (title, keywords, steps, requires escalation)
- `IT_SLA_Rule` — first-response hours by Case Priority (High 4, Medium 16, Low 40)

| Keyword | Aliases | Queue |
| --- | --- | --- |
| network | wifi, vpn | `Campus_IT_Network` |
| hardware | laptop, printer | `Campus_IT_Hardware` |
| software | application, license, email, outlook | `Campus_IT_Software` |
| account | password, login, identity, mfa | `Campus_IT_Identity` |
| (default) | | `Campus_IT_General` |

Shipped guides: campus WiFi, password reset, VPN, Outlook offline, MFA, laptop no power (that last one still escalates after first aid).

Today's deflection rate from the snapshot is self-service matches divided by matches plus newly created tickets. Reused tickets do not count as new escalations.

## Still UI-only (not in this repo)

These are product/org steps, not more Apex:

- Agent persona, topics, and utterance tests in Agent Builder
- Optional Salesforce Knowledge articles if your org has Knowledge
- Assign the permission set to the Agentforce running user
- Assign the Campus IT Case layout if you want the technician page out of the box
- AgentExchange listing, screenshots, and a recorded demo
- Managed package / `global` visibility if you later package the actions
