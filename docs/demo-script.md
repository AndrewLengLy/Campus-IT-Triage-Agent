# Demo script

About eight minutes. Use an org seeded by `./scripts/setup-scratch-org.sh`, or by a deploy plus `scripts/apex/seedSampleData.apex`.

Demo students:

| Student ID | Name | Use for |
| --- | --- | --- |
| S10000001 | Alex Rivera | Self-service success (WiFi) |
| S10000002 | Jordan Chen | Escalation after first aid (laptop) |
| S10000003 | Sam Patel | Status miss, then a new ticket if you want a third Case |

## 1. Technician workspace (45 seconds)

App Launcher → **Campus IT**. Show **Campus IT Agent Cases** and **Campus IT Interactions Today**.

Say: this is not a chatbot bolted onto email. It writes Cases technicians already know how to work, and an audit row for every action, so the desk can measure deflection.

## 2. Self-service first (90 seconds)

In the agent preview, as Alex:

> Campus WiFi keeps dropping in my residence hall. My student ID is S10000001.

The agent should call **Find Campus IT Self-Service Guide** and walk the reconnect steps. Do not escalate if the steps are enough.

Then open **Campus IT Interactions Today**. A Self Service / Matched row should be there.

## 3. Escalate only when a human is required (2 minutes)

As Jordan:

> My laptop will not power on and I have an exam. Student ID S10000002. I already tried a different charger.

The agent should still call the guide (laptop is first aid, then escalate), then **Escalate Campus IT Ticket** with Self Service Attempted = true.

Read back the Case Number. Open the Case:

- Owner is the Hardware queue
- Priority is High
- **Agent Sourced** is checked
- **First Response Due** is about four hours out
- **Self Service Article** is filled in
- A published Case Comment is on the record
- Related **Campus IT Interactions** show the escalate row

## 4. Reuse beats duplicate tickets (60 seconds)

As Jordan again:

> It is the same laptop. Still dead. The power light never comes on.

The agent should reuse the open Hardware ticket and add a comment, not open a second Case. Show `isExistingTicket` behavior as a second comment on the same Case Number.

## 5. Status and a closed-ticket rule (60 seconds)

As Jordan: “What is going on with my ticket?”

**Check Campus IT Ticket Status** should return the number, High, Hardware, and the queue name.

If you close the Case in the UI and ask to add “I tried one more charger,” **Add Campus IT Ticket Update** should refuse and tell the agent to open a new ticket.

## 6. Operations snapshot (90 seconds)

In preview, as a supervisor or as a student asking whether the desk is backed up:

> How busy is the Campus IT desk right now?

**Get Campus IT Operations Snapshot** should speak open agent-sourced count, high-priority count, oldest wait, and today's deflection rate.

Point at the formula: matches ÷ (matches + new tickets). Reused tickets do not count as new volume.

## 7. What you would change next week (30 seconds)

Setup → Custom Metadata Types:

- Add a known-issue article if the same question repeats
- Change SLA hours without a code deploy
- Retarget a category alias to another `Campus_IT_*` queue

No hardcoded Salesforce Ids. Tests run without `SeeAllData`.
