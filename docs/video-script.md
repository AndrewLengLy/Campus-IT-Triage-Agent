# 60-second video demo script

Record in 16:9. Speak to camera or voice-over. LinkedIn autoplay is muted, so keep on-screen text in the first two seconds and burn captions if you can.

Total talk time: ~58 seconds. Cut anything that does not earn the next second.

| Time | On screen | Voice |
| --- | --- | --- |
| 0:00–0:07 **Hook** | Tight on you, then cut to App Launcher → **Campus IT**. Super: “Triage the repeats. Escalate the real work.” | Campus IT desks do not have a ticket problem. They have a repeatability problem. |
| 0:07–0:16 **Problem** | Four words on screen: WiFi. Password. MFA. “Where is my ticket?” Then a Case list that looks busy. | The same five requests hit the queue every morning. Hardware waits behind work a script could finish. Chatbots guess, open duplicates, and cannot prove deflection. |
| 0:16–0:28 **Technical solution** | Cut between: (1) Apex class list `ITDesk*`, (2) Custom Metadata `IT_Known_Issue` / `IT_SLA_Rule`, (3) a Case with First Response Due and Agent Sourced checked. | I built this as native Salesforce. Five Apex invocable actions. Routing and SLA hours live in Custom Metadata, with no hardcoded IDs. Every call writes an append-only audit row. |
| 0:28–0:50 **Live demo** | **Campus IT Agent Cases**: seven seeded tickets across five queues. Open Jordan Chen’s Hardware Case: Case Number, queue, High priority, First Response Due, Self Service Article, published comment. Open Wei Zhang’s printing Case to show two comments on one ticket. Flip to **Campus IT Interactions Today**. | Watch the path. A WiFi question matched a guide and never became a ticket. The dead laptop became one Case on Hardware, High priority, SLA clock running. The same student reporting the same problem again lands on that ticket as a comment, not a duplicate. Every one of those is a row in the audit object, which is how the desk measures deflection. |
| 0:50–0:58 **CTA** | Full-screen URL. Super: github.com/AndrewLengLy/Campus-IT-Triage-Agent | Code, deploy steps, and the operating model are on GitHub. Clone it, deploy to a Developer org, assign the permset. |

## Before you record

Seed the org so every shot has real data in it:

```bash
./scripts/setup-scratch-org.sh
```

Record the seeded records, not a mock. Do not fake a Case Number.

## Shot list (prep before you hit record)

1. App Launcher → Campus IT → Campus IT Agent Cases, sorted by First Response Due
2. Jordan Chen’s Case: queue, priority, First Response Due, Self Service Article, published comment
3. Wei Zhang’s printing Case: two published comments on one ticket
4. Campus IT Interactions Today: a mix of Matched, Created, Updated, and Not Found
5. Setup → Custom Metadata Types → IT Category Queue Map, showing the alias list an admin edits
6. GitHub repo in a clean browser tab
