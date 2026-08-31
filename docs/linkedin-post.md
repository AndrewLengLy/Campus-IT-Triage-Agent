# LinkedIn launch post

LinkedIn does not render Markdown. Everything inside the fenced blocks is plain
text on purpose — copy it exactly. Asterisks, backticks, and `[text](url)` links
show up as literal characters in the feed.

## Post

Opens on the start of term and names `eduroam` — the specific that signals
you've actually worked a campus desk rather than read about one. Loose and
spoken from there: contractions, questions, an aside. Says the same true things
as the tighter versions below without sounding like a spec sheet.

The first line is 121 characters, which keeps it inside LinkedIn's mobile
"…see more" cut (~140) so it reads whole before anyone expands the post. If you
edit that line, keep it under that.

**The opener has a shelf life.** It reads as current for the first couple of
weeks of the semester and stale after. Post it while term is starting, or swap
the first line.

```text
The semester's starting back up, so the tech support queue is about to be mostly eduroam, password resets, and MFA loops.

None of it's hard. There's just a lot of it.

And the laptop that actually died the night before an exam? It's stuck in line behind all of that.

Most support bots don't help here. They guess, they open a second ticket for a problem that already has one, and nobody can tell you what actually got deflected.

So I built one that doesn't do that.

Here's 65 seconds of it — no sound, captions are on screen.

Someone's WiFi keeps dropping. It hands back the fix and doesn't open a ticket at all. That's a deflection you can actually count.

Someone's laptop won't turn on before an exam. First aid, then one ticket on the Hardware queue, high priority, four-hour clock.

Same person messages again about the same laptop. It reuses ticket 00001024 instead of opening 00001025. That one's my favourite.

Someone asks how backed up the desk is. Open tickets, longest wait, deflection rate — pulled from an audit trail nobody can edit.

It's five Apex actions underneath. Routing rules and SLA hours live in Custom Metadata, so whoever runs the desk can change them in Setup without touching any code.

One note: the video walks through the interface, not a live org, and it says so on screen. The code is real though — clone it and deploy it.

Repo's in the comments.

#Salesforce #Agentforce #ServiceCloud #HigherEd #ITSM
```

### First comment (post this immediately after)

```text
Code, architecture notes, and deploy steps:
https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

Developer Edition or a Trailhead Playground, Salesforce CLI, one deploy, one permission set. Agentforce is only needed for the conversational half — the technician app works without it.
```

---

## Alternates

Same opener, tighter registers. All keep the walkthrough disclosure.

<details>
<summary><b>Blunt</b> — short lines, hard stops, no hedging. Reads confident, can read cold.</summary>

```text
The regular semester is starting up and the highest volume of tech support problems are things like eduroam, password resets, and MFA loops.

None of it is hard. It's just constant.

Meanwhile the laptop that actually died before an exam sits behind all of it.

Most chatbots make this worse. They guess. They open duplicates. They can't prove they deflected anything.

So I built one that doesn't.

65 seconds, no sound, captions on screen:

A WiFi complaint comes in. It matches a guide. No ticket opened. That's a deflection you can count.

A laptop won't power on before an exam. First aid first, then one Case. Hardware queue. High priority. Four-hour clock.

Same student messages again. It reuses ticket 00001024. It does not open 00001025.

A supervisor asks how backed up the desk is. Open load, oldest wait, deflection rate. Straight from an audit trail nobody can edit.

Five Apex actions. Routing and SLA hours in Custom Metadata, so a desk lead changes them in Setup, not in code. No hardcoded IDs. No secrets.

The video is a walkthrough of the interface, labelled on screen, not a live org. The code is real and deploys with the Salesforce CLI.

Repo in the comments.

#Salesforce #Agentforce #ServiceCloud #HigherEd #ITSM
```

</details>

<details>
<summary><b>Conversational</b> — first person, ends on a question to service-desk people. Invites replies rather than daring people to poke holes.</summary>

```text
The regular semester is starting up and the highest volume of tech support problems are things like eduroam, password resets, and MFA loops.

None of it is hard. It's just constant. And the student whose laptop actually died the night before an exam is sitting in that same queue, behind all of it.

That ordering problem is the part I wanted to work on, so I built a triage agent on Salesforce. Here's 65 seconds of it — no sound, captions are on screen.

The part I care about most is what it doesn't do.

A student reports WiFi dropping in their residence hall. It hands back the reconnect steps and opens nothing. No ticket. That's a deflection, and it gets counted rather than guessed at.

Another student's laptop won't power on before an exam. It walks through first aid, then opens exactly one Case on the Hardware queue — High priority, four-hour response clock, contact linked.

Then that same student messages again about that same laptop. It reuses the existing ticket instead of opening a second one. That single behaviour is most of what makes support bots infuriating.

Under the hood: five Apex actions Agentforce can call, with routing rules and SLA hours in Custom Metadata, so a service desk lead retunes them in Setup without touching code. Every action writes an audit row that can't be edited or deleted, so the deflection number can't quietly drift.

Being upfront: the video is a walkthrough of the interface, labelled as such, not a recording of a live org. The Apex, metadata, and permission set are real and deploy with the Salesforce CLI.

Still learning this stack. If you've worked a campus service desk and I've got the model wrong somewhere, I'd genuinely like to hear it.

Repo in the comments.

#Salesforce #Agentforce #ServiceCloud #HigherEd #BuildInPublic
```

</details>

<details>
<summary><b>Technical</b> — names the metadata types and invariants. For a developer audience; loses general readers.</summary>

```text
The regular semester is starting up and the highest volume of tech support problems are things like eduroam, password resets, and MFA loops.

The problem with pointing a bot at that isn't the conversation. It's that nothing downstream is auditable. Most of them guess a category, open a duplicate, and leave you no way to prove what was actually deflected.

So I built the triage agent as Service Cloud metadata rather than a chat layer.

Five Apex invocable actions exposed to Agentforce — self-service lookup, escalation, ticket update, status check, operations snapshot. One @InvocableMethod each, List in, List out.

Routing lives in IT_Category_Queue_Map__mdt, known issues in IT_Known_Issue__mdt, SLA hours in IT_SLA_Rule__mdt. A service desk lead retunes queues, articles, or response targets in Setup with no deploy. No Salesforce record IDs are hardcoded anywhere.

Every action inserts a Campus_IT_Interaction__c row, and a before-update/before-delete trigger blocks tampering. Deflection is computed off that trail — matches divided by matches plus new Cases — so the number can't be rewritten after the fact.

Escalation is idempotent per student and category: an open Case is reused and commented on rather than duplicated, unless a force-new flag is set. Updates against closed Cases are rejected outright.

Apex tests run without SeeAllData, with test queues namespaced so they never collide with the packaged ones.

The 65-second walkthrough is attached, silent with captions. It shows the interface and is labelled on screen as a walkthrough, not a live org capture — the Apex, custom metadata, queues, and permission set are real and deploy with sf project deploy start.

Repo and architecture notes in the comments.

#Salesforce #Agentforce #ServiceCloud #Apex #HigherEd
```

</details>

---

## How to post it

1. Upload `docs/demo/campus-it-app-recording.mp4` as a **native video**. Do not
   link out to YouTube or Vimeo — LinkedIn only autoplays video it hosts, and
   link posts get less reach.
2. Keep the GitHub URL out of the post body. Put it in the first comment
   (above). A bare external link in the body suppresses distribution.
3. Only the first line or two show before "…see more" on mobile. Every opener
   here is sized to survive that cut intact.
4. The video is silent with burned-in captions, which is what you want: LinkedIn
   autoplays muted, and most people never turn sound on.
5. Timing: post while term is actually starting. The hook is doing real work and
   it expires.

### Video specs

| | |
| --- | --- |
| File | `docs/demo/campus-it-app-recording.mp4` |
| Length | 65 seconds |
| Resolution | 1920 x 1080 (16:9) |
| Size | ~6 MB |
| Audio | None — captions are burned in |

LinkedIn accepts 3 seconds to 10 minutes and up to 5 GB, so this clears every
limit with room to spare.

## What the video is, and is not

The recording is a scripted walkthrough of the Campus IT workspace interface. It
is not screen capture from a live Salesforce org, and it says so on screen for
its full length ("UI walkthrough · not a live org capture"). The behaviour it
shows — self-service match, single escalation, ticket reuse, the operations
snapshot — mirrors what the Apex in this repo actually does, but the frames are
rendered from `docs/demo/app-walkthrough.html`, not from Salesforce.

Every version above keeps that disclosure. Keep it. The audience for these
hashtags is people who work in Salesforce every day and will recognise a
reconstruction. Being straight about it costs nothing and is much cheaper than
being corrected in the comments.

**Want footage of the real thing?** Deploy to a Developer org (README, steps 1–5),
then screen-record the shot list in [`video-script.md`](video-script.md). That
gives you a genuine capture you can post without the qualifier — drop the
disclosure sentence from whichever version you picked.

## Regenerating the walkthrough

```bash
cd scripts/demo-video
npm install
node record.mjs     # writes docs/demo/campus-it-app-recording.mp4
```

Needs `ffmpeg` on PATH. Set `CHROMIUM_PATH` to reuse a preinstalled browser and
`FFMPEG_PATH` if ffmpeg lives somewhere unusual.
