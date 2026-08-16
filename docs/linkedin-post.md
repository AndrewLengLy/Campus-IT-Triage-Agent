Campus IT desks do not have a ticket problem. They have a repeatability problem.

The same WiFi, password, MFA, and “what’s going on with my ticket?” requests hit the queue every morning. Hardware that actually needs a technician waits behind work a script could finish. Most chatbots make that worse: they guess, they open duplicates, and nobody can prove whether they deflected anything.

I built a Salesforce Agentforce agent that sits in Service Cloud and behaves like a triage desk.

It tries a known-issue guide first. If the student still needs a human, it opens one Case on the right queue, stamps a first-response SLA, and reuses the open ticket instead of creating a second one. Every action writes an append-only audit row. Supervisors can ask how backed up the desk is and get open load, oldest wait, and today’s deflection rate.

How it works:

1. Find a self-service guide — WiFi, password, VPN, Outlook, MFA, or laptop first aid
2. Escalate only when a technician is required — queue routing, SLA clock, published Case comment
3. Update or check status on the existing Case — closed tickets are rejected
4. Snapshot desk load from the audit trail — deflection is matches ÷ (matches + new tickets)

Routing, known-issue articles, and SLA hours live in Custom Metadata. No hardcoded Salesforce IDs. Tests run without SeeAllData.

Repo, docs, and the 80-second walkthrough:

https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

#Salesforce #Agentforce #ServiceCloud #Apex #HigherEd #ITSM
