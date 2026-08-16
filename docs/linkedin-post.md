Campus IT desks do not have a ticket problem. They have a repeatability problem.

The same WiFi, password, MFA, and “what’s going on with my ticket?” requests hit the queue every morning. Hardware that needs a technician waits behind work a script could finish. Most chatbots make that worse: they guess, they open duplicates, and nobody can prove deflection.

I built a native Salesforce Agentforce agent that sits in Service Cloud and behaves like a triage desk — not a FAQ widget.

Stack: Apex invocables (API 64.0), Service Cloud Cases, Custom Metadata for routing / known issues / SLA, five Campus IT queues, an append-only `Campus_IT_Interaction__c` object, and a Lightning app technicians already know how to use. No hardcoded record IDs. No Connected Apps. No secrets. Tests run without SeeAllData.

What it does:

- Tries a known-issue guide before anyone opens a Case
- Escalates once, on the right queue, with a first-response clock
- Reuses the open ticket instead of creating a duplicate
- Rejects updates on closed Cases
- Reports open load, oldest wait, and today’s deflection rate from the audit trail

Try it: Developer Edition or Trailhead Playground, Salesforce CLI, `sf project deploy start`, assign **Campus IT Triage Agent**, run the demo data script. Agentforce is optional for the technician app and required for the conversational demo.

Code, architecture, unmanaged-package steps, and the 60-second script:

https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

#Salesforce #Agentforce #ServiceCloud #Apex #SalesforceDeveloper #ITSM #HigherEd #BuildInPublic
