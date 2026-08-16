# 60-second video demo script

Record in 16:9. Speak to camera or voice-over. LinkedIn autoplay is muted, so keep on-screen text in the first two seconds and burn captions if you can.

Total talk time: ~58 seconds. Cut anything that does not earn the next second.

| Time | On screen | Voice |
| --- | --- | --- |
| 0:00–0:07 **Hook** | Tight on you, then cut to App Launcher → **Campus IT**. Super: “Triage the repeats. Escalate the real work.” | Campus IT desks do not have a ticket problem. They have a repeatability problem. |
| 0:07–0:16 **Problem** | Four words on screen: WiFi. Password. MFA. “Where is my ticket?” Then a Case list that looks busy. | The same five requests hit the queue every morning. Hardware waits behind work a script could finish. Chatbots guess, open duplicates, and cannot prove deflection. |
| 0:16–0:28 **Technical solution** | Cut between: (1) Apex class list `ITDesk*`, (2) Custom Metadata `IT_Known_Issue` / `IT_SLA_Rule`, (3) a Case with First Response Due and Agent Sourced checked. | I built this as native Salesforce. Five Agentforce-callable Apex actions. Routing and SLA hours live in Custom Metadata — no hardcoded IDs. Every call writes an append-only audit row. |
| 0:28–0:50 **Live demo** | Agent preview. Type: “Campus WiFi keeps dropping. Student ID S10000001.” Show the guide. Then Jordan: “Laptop will not power on, S10000002.” Show Case Number, Hardware queue, High, first-response due. Flip to **Campus IT Interactions Today**. | Watch the path. WiFi gets a guide, not a ticket. The dead laptop becomes one Case on Hardware, High priority, SLA stamped. Same student, same category reuses that ticket. The interaction object is how the desk measures deflection. |
| 0:50–0:58 **CTA** | Full-screen URL. Super: github.com/AndrewLengLy/Campus-IT-Triage-Agent | Code, deploy steps, and the operating model are on GitHub. Clone it, deploy to a Developer org, assign the permset. |

## Utterances to type on camera

```
Campus WiFi keeps dropping in my residence hall. My student ID is S10000001.
```

```
My laptop will not power on and I have an exam. Student ID S10000002. I already tried a different charger.
```

If Agentforce is not enabled in the recording org, skip the preview and run the same path from **Developer Console → Debug → Open Execute Anonymous Window** is weaker on camera. Prefer: show the **Campus IT** app, open the seeded Jordan Case, then the Interactions list, and say the agent actions are in the repo. Do not fake a Case Number.

## Shot list (prep before you hit record)

1. App Launcher → Campus IT → Campus IT Agent Cases
2. Jordan’s Case: queue, priority, First Response Due, Self Service Article
3. Campus IT Interactions Today
4. Agent Builder preview logged in (optional)
5. GitHub repo in a clean browser tab
