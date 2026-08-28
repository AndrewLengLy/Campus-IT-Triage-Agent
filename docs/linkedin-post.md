# LinkedIn post draft

---

Campus IT service desks do not have a ticket problem. They have a repeatability problem.

The same requests arrive every shift. WiFi, password resets, MFA, VPN, a course missing from the
LMS, a print job that will not release. Work a documented procedure could finish sits in the same
queue as work that genuinely needs a technician, so the cracked laptop before an exam waits behind
twenty password resets. And when someone asks how much the desk actually deflected, nobody can
answer, because nothing recorded the conversations that ended without a ticket.

I built a Service Cloud backend for that. It is a demo and a portfolio piece, not something
running at a university, and I would rather say that up front than imply otherwise.

What it does: checks a known-issue catalog first, opens one Case on the right queue when a person
is needed, reuses the open ticket instead of creating a duplicate, starts a first response clock,
and writes an append only audit row for every action so deflection is a number you can query
rather than a claim.

The decision worth explaining is where the routing rules live. They are in Custom Metadata, not in
Apex. A service desk lead who wants "eduroam" routed like "wifi" edits a row in Setup. No code
review, no deployment window. That is the point of Custom Metadata: it deploys with the code, so a
fresh org comes up already configured and the tests can assert against the shipped rules.

It has a cost I did not paper over. Custom Metadata has no ordering, so when a category matches
two rules, which queue wins is undefined. That is written up in the repo as a known issue with the
fix I would make, which is a priority column.

Stack: Apex invocable actions on API 64.0, Custom Metadata for routing and SLA targets, five
queues, an append only audit object with a trigger that blocks edits and deletes, and a Lightning
app. One script takes a fresh clone to a working scratch org with sample data.

The tests are the part I would want a reviewer to read. Salesforce hands invocable methods a batch
of records, so there is a test that pushes 200 records through every action in one transaction and
fails if the SOQL or DML count moves with the batch size. That is the difference between code that
passes a single record test and code that survives production.

Code, architecture notes, and the known issues list:
https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

#Salesforce #ServiceCloud #Apex #SalesforceDeveloper #ITSM #HigherEd
