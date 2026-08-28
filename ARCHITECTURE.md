# Architecture

Campus IT Triage is a native Service Cloud backend. It takes a described problem, tries to
resolve it from a known-issue catalog, and if a human is needed opens exactly one Case on the
right queue with a first-response clock running, then writes an append-only audit row so the
desk can prove what happened.

Everything in this repo is Salesforce metadata: Apex, Custom Metadata Types, queues, a custom
object, a trigger, a permission set, and a Lightning app. There is no external service, no
Connected App, no named credential, and no runtime secret. The technician workspace is standard
Service Cloud.

This document is about the decisions, not the syntax. Where a decision has a cost, the cost is
named.

---

## The shape of the system

```
caller (Flow, REST, anonymous Apex, or a chat layer)
   │
   ├─ Find Campus IT Self-Service Guide ──── IT_Known_Issue__mdt
   ├─ Escalate Campus IT Ticket ──────────── IT_Category_Queue_Map__mdt → Campus_IT_* queue
   │                                          IT_SLA_Rule__mdt → Case.First_Response_Due__c
   ├─ Add Campus IT Ticket Update ────────── CaseComment
   ├─ Check Campus IT Ticket Status ──────── Case
   └─ Get Campus IT Operations Snapshot ──── open load + today's deflection
                    │
                    └─ every call ──────────► Campus_IT_Interaction__c (append-only)
```

Five Apex classes, one `@InvocableMethod` each. Two shared services underneath:

| Class | Owns |
| --- | --- |
| `ITDeskRoutingService` | priority mapping, category → queue, Contact and Case lookups, Case reuse selection, published comments |
| `ITDeskAuditService` | interaction rows and first-response due dates |

---

## Decisions

### Routing rules live in Custom Metadata, not in Apex and not in a Flow

`IT_Category_Queue_Map__mdt` holds one row per queue: a keyword, a comma-separated alias list,
the target queue's `DeveloperName`, and a default flag.

The alternatives and why they lost:

**Hardcoded in Apex.** A service desk lead who wants "eduroam" to route like "wifi" should not
need a developer, a sandbox, a code review, and a deployment window. Routing vocabulary changes
weekly at a campus desk; Apex changes should not.

**A Flow with decision elements.** Flow can do this, and for a single-branch decision it would
be reasonable. It loses on three counts here. Flow decision elements are edited one branch at a
time in a canvas, so a twenty-alias vocabulary becomes an unreadable diagram. Flow versions are
not diffable in source control in any useful way, so "who changed routing and when" stops being
answerable from git. And the routing decision is needed inside a bulk Apex loop, where calling
out to a Flow per record is the wrong shape entirely.

**A custom object.** Custom Metadata deploys with the code, so a scratch org comes up with
routing already configured and the tests can assert against the shipped configuration. Rows in a
custom object are data: they do not deploy, they need a seeding step, and a fresh org routes
everything to the default queue until someone remembers to load them. Custom Metadata is also
free to read — `getAll()` costs no SOQL — which matters inside a 200-record transaction.

**The cost.** Custom Metadata has no ordering. `getAll()` returns rows in no defined order and
the code walks a `Map` whose key iteration order Apex does not define. So when a category matches
two rules, which queue wins is unspecified. See **Known issues**, item A. This is the price of
the design as built, and it is fixable with one more column rather than a different design.

Queues are referenced by `DeveloperName`, never by Id. Record Ids differ in every org; a
hardcoded Id is the single most common reason a Salesforce demo does not survive being deployed
somewhere else.

### The audit trail is its own append-only object

`Campus_IT_Interaction__c` gets one row per action call: action type, outcome, success flag,
student ID, Case lookup, Case Number as text, category, article title, and a summary.

**Why not Field History Tracking.** It records field-level before and after values on records
that exist. It cannot record the thing this desk most needs to count: the lookups that
successfully avoided creating a record at all. Deflection is measured in events that produced no
Case, and field history has nothing to attach to.

**Why not Case Comments.** Comments are the student-visible conversation and they die with the
Case. An operations trail needs to outlive the record it describes, which is why `Case_Number__c`
is stored as text next to the `Case__c` lookup.

**Why not a Big Object.** Big Objects are the right answer at genuine scale and the wrong answer
here. They cannot be queried with normal SOQL, they cannot back a standard list view or report,
and they cannot be shown in the Lightning app a technician already uses. At demo scale a custom
object is queryable, reportable, and visible. See **At real campus scale** for when that flips.

**Why append-only.** The trail exists to answer "did the desk actually deflect anything, and
what did it do on this student's behalf?" A trail that can be edited answers neither question,
because the answer is only as good as the assumption that nobody edited it.

### Invocable actions are the interface

Each action takes `List<Request>` and returns `List<Result>` in the same order, with every input
and output declared as an `@InvocableVariable` carrying a label and a description.

That signature is callable from Flow, from Process Builder, from the REST actions endpoint, from
anonymous Apex, and from any orchestration layer bolted on later, without a wrapper for each. The
labels and descriptions are what make it usable from a point-and-click tool: an admin building a
Flow sees "Student ID — Campus student identifier (for example S12345678)", not a parameter named
`p1`.

The list-in/list-out shape is not decoration. Salesforce hands invocable methods a batch, and a
method that assumes one record and queries inside a loop dies at scale. Everything here queries
once, builds in memory, and does DML once. `ITDeskBulkTest` asserts that: it pushes 200 records
through every action and fails if the SOQL or DML count moves with the batch size.

**Never throw.** An action returns a failure result with a student-safe message and a next step,
rather than raising an exception. A caller mid-conversation with a student can read out "I need
your student ID before I can open a ticket". It cannot do anything sensible with a stack trace.
Partial failure is per-record: one bad request in a batch of 200 fails that request and no other,
and the result stays in its original position so the caller can match results to requests.

### The SLA clock is data, not code

`IT_SLA_Rule__mdt` maps priority to first-response hours (High 4, Medium 16, Low 40) and stamps
`Case.First_Response_Due__c` at creation. Same reasoning as routing: a service desk lead
renegotiating a first-response target should edit a row, not open a pull request.

It is a plain hour offset, not business hours. A Low priority ticket opened on Friday afternoon
is due Sunday morning. That is wrong for a real desk and right for a demo that has to deploy into
any org without a configured Business Hours record. See **At real campus scale**.

### Duplicate suppression reuses an open ticket

Before creating a Case, the escalation action looks for an open Case for the same student that is
either already sitting on the target queue, or still carries the same `IT_Category__c`. If it
finds one it appends a comment instead of opening a second ticket, stamps
`Reused_Existing_Ticket__c`, and returns the original Case Number.

Duplicate tickets are the failure mode that makes service desks distrust automation. A student
who reports the same broken laptop three times should end up with one ticket and three comments,
not three tickets and a technician deciding which to close.

The escape hatch is the `Force New Ticket` input, set only when the student confirms this is a
genuinely different problem. The heuristic is deliberately conservative in that direction:
over-merging is annoying, and under-merging is the thing that erodes trust.

### Audit writes run in system mode and never throw

`ITDeskAuditService` inserts through a `without sharing` inner class and wraps the write in a
try/catch that swallows.

The reasoning: a student must never lose their ticket because a field-level permission was
misconfigured on the audit object. The Case is the thing that matters to the person on the other
end of the conversation.

The cost is real and worth stating plainly: an audit trail that can silently drop rows is
weaker than one that cannot. See **Known issues**, item H, for the proposed middle ground.

---

## Append-only: what is and is not guaranteed

Enforced in code, at two layers:

1. **`CampusITInteractionGuard`** rejects every `before update` and `before delete` with an
   explanatory error. Triggers run for Apex, Flow, the Lightning UI, Data Loader, and the SOAP
   and REST APIs alike, so there is no ordinary path around it. `CampusITInteractionGuardTest`
   asserts this for single records and for a 200-row batch, including
   `Database.update(rows, false)`, where partial success must not let any individual row through.
2. **The `Campus_IT_Triage_Agent` permission set** grants Create and Read on the object and
   withholds Edit and Delete, so the running user cannot reach the trigger in the first place.

Two holes remain. Both are named here rather than quietly left for a reviewer to find:

- **`Case__c` uses the `SetNull` delete constraint.** Deleting the parent Case clears the lookup
  on the audit row through a platform cascade rather than a normal update. `Case_Number__c` is
  stored as text specifically so the trail survives this, but the lookup change itself is not
  covered by the guard. Proposal: change the constraint to `Restrict`, which makes the
  relationship explicit and forces a deliberate decision when someone tries to delete a Case that
  has audit history.
- **A user with Author Apex can deactivate the trigger**, and Modify All Data plus a metadata
  deployment can remove it. This is true of every trigger-based control on the platform. If the
  requirement is tamper-evidence against a privileged insider rather than against ordinary use,
  the answer is Shield Field Audit Trail or an off-platform write-once store, not a trigger.

---

## Known issues

Found while writing the tests. Nothing here has been changed in the behaviour of the shipped
code; each is a decision to make, and several are one-line fixes deliberately left alone.

| # | Issue | Where | Impact | Proposal |
| --- | --- | --- | --- | --- |
| A | **Routing precedence is undefined when two rules match.** `resolveQueueDeveloperName` iterates `Map.keySet()`, and Apex defines no iteration order for `Map`. A category like "email account recovery" matches both the software and identity rules; which one wins is not specified and can change between runs. | `ITDeskRoutingService.resolveQueueDeveloperName` | A ticket lands on an arbitrary one of two plausible queues. Low blast radius today because most categories match one rule, but it is unpredictable by construction. | Add a `Priority__c` number column to `IT_Category_Queue_Map__mdt`, sort rules by it, first match wins. Makes precedence visible to the admin who owns the rules. |
| B | **Multiple default rules give an undefined fallback.** `activeDefaultQueueDeveloperName` returns the first row with `Is_Default__c` set, in `getAll()` order. | `ITDeskRoutingService.activeDefaultQueueDeveloperName` | Two default rows means the fallback queue is arbitrary. `ITDeskQueueRoutingTest` now fails the build if more than one ships, but nothing stops an admin adding one in production. | Same priority column, or a validation rule on the Custom Metadata Type. |
| C | **Keyword matching is substring, not word boundary.** `normalized.contains(keyword)`. | `ITDeskRoutingService.resolveQueueDeveloperName` | "Accountancy software licence" matches `account` and can route to identity rather than software. | Match on tokenized whole words first, fall back to substring only if nothing matches. |
| D | **The Case-reuse subject fallback is too loose.** After the queue and category checks, reuse falls back to `ticket.Subject.contains(category)`. Every triage-created subject begins `Campus IT: `, so a category of "IT" or "Campus" merges the new report into any open ticket the student has. | `ITDeskRoutingService.findReusableOpenCase` | A student's unrelated problem gets appended to the wrong ticket. | The fallback existed for Cases created before `IT_Category__c` was stamped. Now that every triage-created Case carries it, either drop the fallback or restrict it to the canonical label rather than the raw caller input. |
| E | **A punctuation-only student ID is accepted and then normalizes away.** `isValid` checks `String.isNotBlank`, but `normalizeStudentId('---')` returns null. | `ITDeskTicketEscalation.isValid` | The Case is created with no Student ID and can never be found by a student-ID lookup, and the audit row cannot be attributed. Covered by a characterisation test in `ITDeskNegativePathTest`. | Validate the normalized value, not the raw string. |
| F | **A malformed email silently kills the whole ticket.** `studentEmail` is copied to `Case.SuppliedEmail` unvalidated; the platform rejects the insert and the caller gets the generic "I wasn't able to create a ticket just now." | `ITDeskTicketEscalation.buildCase` | A student who mistypes their email loses the ticket and is told nothing useful. | Validate the address; if it is malformed, drop it, create the ticket, and record the supplied text in the Description. The email is a convenience, not a reason to fail. |
| G | **Duplicate suppression does not apply within a single batch.** Open Cases are queried once before the inserts, so two requests for the same student and category in one call both create Cases. | `ITDeskTicketEscalation.escalate` | Correct for one-at-a-time callers, wrong for a Flow loop or a bulk API caller. | Track `(student, queue)` pairs claimed earlier in the same loop and reuse within the batch. |
| H | **Audit write failures are invisible.** `log` catches and discards every exception, and inserts with `allOrNone = false`. | `ITDeskAuditService.log` | Rows can be dropped with no signal, which weakens the deflection metric the object exists to support. | Keep the swallow, since a student must not lose a ticket to a logging failure, but publish a Platform Event or increment a counter on failure so it can be alerted on. |
| I | **`Case__c` uses `SetNull`.** Covered above under append-only. | `Campus_IT_Interaction__c.Case__c` | Deleting a Case mutates audit rows outside the guard. | Change to `Restrict`. |
| J | **The routing keyword map is rebuilt on every call.** `activeKeywordMap()` re-reads the rules and re-splits every alias string each time; escalation calls it three times per record. | `ITDeskRoutingService.activeKeywordMap` | Roughly 600 rebuilds for a 200-record batch. Wasted CPU, not a correctness problem. | Memoize per transaction in a static. |
| K | **Two queries have no bound.** The operations snapshot selects every open triage-sourced Case, and `queryOpenCasesByStudentId` has no `LIMIT`. | `ITDeskOperationsSnapshot`, `ITDeskRoutingService` | Fine at demo scale. At campus scale it is a `QueryException` at 50,001 rows. | Use aggregate queries for the counts and a `LIMIT 1` ordered query for the oldest ticket. |
| L | **The snapshot's queue filter is a substring match on the queue label**, so a filter of "Campus IT" matches every queue, and any Case owned outside a `Campus_IT_*` queue is bucketed as "Unassigned / other". | `ITDeskOperationsSnapshot.buildSnapshot` | Surprising rather than wrong. Documented here and asserted in `ITDeskOperationsSnapshotTest`. | Filter on `DeveloperName` and take the label from the queue record. |
| M | **The snapshot is O(requests × open tickets).** Each request re-walks the full open-ticket list. | `ITDeskOperationsSnapshot.buildSnapshot` | 200 requests over 200 tickets is 40,000 iterations, which is fine. 200 requests over 5,000 tickets is not. | Compute the breakdown once and filter the aggregate per request. |

---

## Extension points

Everything below can be changed by an admin in Setup, with no deployment:

| Change | Where |
| --- | --- |
| Route a new vocabulary word to an existing queue | `IT_Category_Queue_Map` → the queue's row → Aliases |
| Add or retire a self-service article | `IT_Known_Issue` → Title, Keywords, Resolution Steps, Requires Escalation, Is Active |
| Change a first-response target | `IT_SLA_Rule` → First Response Hours |
| Change who works a queue | Setup → Queues → queue members |

Changes that need Apex:

| Change | Why |
| --- | --- |
| A new queue | The queue itself is metadata, but `labelForQueueDeveloperName` maps queue names to the five `Case.IT_Category__c` picklist values, so a sixth queue needs a picklist value and a mapping. Worth moving onto the Custom Metadata row as a `Case_Category_Label__c` column. |
| A new action | A new class with one `@InvocableMethod`, following the same list-in/list-out and never-throw contract |
| A different matching algorithm | `ITDeskSelfService.matchIssue` scores keyword hits and adds two for a category match. Swapping in Einstein Search or a vector match is a change to that one method |

---

## At real campus scale

What is right for a portfolio demo and wrong for thirty thousand students:

**The SLA clock ignores business hours.** A Low priority ticket opened Friday at 4pm is due
Sunday at 8am, and nobody is there. A real deployment computes `First_Response_Due__c` from a
Business Hours record via `BusinessHours.add()`, with a separate calendar for term time,
vacation, and the first two weeks of semester when the desk is underwater.

**Keyword matching will not hold.** A hand-maintained alias list is honest and inspectable at
twenty rows. At two hundred it becomes a second job, and it fails on the phrasings nobody
predicted. The path is to keep this as the deterministic floor and layer a classifier above it,
because the failure mode of a classifier with no floor is a confidently wrong queue and no way to
explain it to the technician who received the ticket.

**The audit object becomes a data volume problem.** One row per action across a busy desk is
millions of rows a year on an object that also has to stay reportable. The migration is a Big
Object for the raw trail plus a rollup object holding daily aggregates by queue and outcome, with
the operations snapshot reading the rollup rather than counting live rows. That also fixes issue
K, since the snapshot stops scanning open Cases entirely.

**The snapshot should not be computed on demand.** Counting open Cases per request is fine for a
supervisor asking once an hour and wasteful for a dashboard refreshing every thirty seconds. A
scheduled job writing a snapshot record every five minutes serves both, costs a fixed amount, and
gives the desk a trend line instead of a single number.

**Reuse should look at more than category.** The current heuristic is student plus queue or
category. It cannot tell "my laptop will not charge" from "my laptop screen is cracked", and both
are Hardware. A real implementation matches on the substance of the problem, and gets the escape
hatch wrong less often.

**Sharing needs a real decision.** Every class is `with sharing`, and the audit object is
Public Read/Write with the permission set withholding Edit and Delete. At campus scale, whether a
technician in one faculty can read another faculty's tickets is a policy question that has to be
answered before it is implemented, and the answer is usually a sharing model plus queue
membership, not a permission set.

**Errors need somewhere to go.** Never-throw is right at the action boundary and insufficient on
its own. A real deployment pairs it with an error log the platform team can alert on, so a
routing rule pointing at a deleted queue surfaces in an alert rather than in a student's
confusion three weeks later.

---

## Test strategy

| Class | Covers |
| --- | --- |
| `ITDeskTestFactory` | Shared builders. Every test creates its own data; nothing reads org records |
| `ITDeskRoutingServiceTest` | Rule matching, aliases, the default-rule fallback, normalization helpers, Case reuse selection, query helpers |
| `ITDeskQueueRoutingTest` | The routing configuration this repo actually ships, end to end onto all five `Campus_IT_*` queues |
| `ITDeskTicketEscalationTest` | What lands on the Case, priority mapping, reuse and Force New Ticket |
| `ITDeskTicketStatusTest`, `ITDeskTicketUpdateTest`, `ITDeskSelfServiceTest`, `ITDeskOperationsSnapshotTest` | Per-action behaviour |
| `ITDeskNegativePathTest` | Missing input, missing queues, a queue that cannot own a Case, save failures partway through a batch |
| `ITDeskBulkTest` | 200 records through every action, asserting SOQL and DML stay flat |
| `CampusITInteractionGuardTest` | The append-only guarantee, single and bulk |
| `ITDeskDemoDataTest` | The org a reviewer gets from the setup script |

Two tests are deliberately written as characterisations of current behaviour rather than
specifications, and say so in their names and comments:
`resolveQueue_multipleMatchingRulesHaveUnspecifiedPrecedence` (issue A) and
`escalate_studentIdWithNoAlphanumericsProducesAnUnfindableTicket` (issue E). They document what
the code does today so the suite stays green while the decision is open.

No test uses `SeeAllData`. Test queues use `CIT_Test_*` DeveloperNames so they cannot collide
with the packaged `Campus_IT_*` queues.
