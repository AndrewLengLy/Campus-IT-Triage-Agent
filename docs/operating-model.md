# Operating model

This is how a campus service desk should run the agent after deploy. Change metadata before you change Apex.

## Who owns what

| Role | Owns | Does not change |
| --- | --- | --- |
| Service desk lead | Known-issue articles, category-to-queue map, SLA hours | Apex, permission set |
| Technician | Cases on the Campus IT app, queue membership | Interaction rows |
| Agentforce admin | Topic instructions, action assignment, running user | Case field definitions |
| Platform owner | Deploy, tests, permission set assignment | Day-to-day ticket text |

## Rules that stay in Custom Metadata

**IT Known Issue** — title, keywords, resolution steps, category, requires escalation, active flag.

Add an article when the same question hits the desk twice in a week. Set **Requires Escalation** when first aid is useful but a technician still has to finish (hardware is the shipped example).

**IT Category Queue Map** — keyword, aliases, queue DeveloperName, default flag.

Point aliases at an existing `Campus_IT_*` queue. Do not put Salesforce record Ids in metadata.

**IT SLA Rule** — priority and first-response hours.

Shipped defaults:

| Priority | First response |
| --- | --- |
| High | 4 hours |
| Medium | 16 hours |
| Low | 40 hours |

The escalate action stamps `First_Response_Due__c` when the Case is created. Changing a rule does not rewrite open tickets.

## What “good” looks like

Read these from **Get Campus IT Operations Snapshot** or the Campus IT app, not from chat anecdotes.

| Signal | Healthy | Investigate |
| --- | --- | --- |
| Self-service deflection today | Catalog is matching common issues | Near 0% with high chat volume: keywords are wrong or the agent is skipping the guide action |
| New escalations today | Tickets that need a human | Spike in one category: add or tighten a known-issue article |
| Oldest wait hours | Inside the SLA for that priority | Oldest High ticket past 4 hours: queue staffing, not the agent |
| Reused vs created | Follow-ups land on the open Case | Many duplicates in one category: reuse matching or Force New Ticket usage |

Deflection is:

`matched guides today ÷ (matched guides today + newly created tickets today)`

A reused ticket is a follow-up, not a failed deflection.

## Audit trail

Every agent action inserts a `Campus_IT_Interaction__c` row. The running user can create and read rows. Updates and deletes are blocked in a trigger so operations numbers cannot be edited after the fact.

Use the **Campus IT Interactions Today** list view for a shift review. Open a Case to see the related interaction list: guide match, escalate, status check, comments.

## Technician workspace

App Launcher → **Campus IT**

- **Campus IT Open Cases** — all open tickets, including first-response due
- **Campus IT Agent Cases** — open tickets the agent created
- **Campus IT Interactions Today** — what the agent did on this shift

Assign the **Campus IT Case** page layout and compact layout on Case if Student ID, category, and first-response due should show in highlights.

## When to escalate in chat vs open a ticket

The topic instructions already say this. The operating rule is the same:

1. Look up an existing ticket if the student has a number or Student ID.
2. Try a known-issue guide.
3. Open a ticket only when the guide is missing, marked for escalation, already tried, or the student asks for a person.
4. Never invent a Case Number.
5. Never add a comment to a closed ticket; open a new one.

## Permission set

Assign **Campus IT Triage Agent** to the Agentforce running user after every deploy. It covers the five Apex actions, Case create/edit, Contact read, and Interaction create/read.
