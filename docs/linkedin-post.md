# LinkedIn launch post

LinkedIn does not render Markdown. Everything inside the fenced blocks is plain
text on purpose — copy it exactly. Asterisks, backticks, and `[text](url)` links
show up as literal characters in the feed.

Three variants below in different voices. Pick one, or tell me which parts of
which to splice. They all say the same true things about the app; only the voice
changes.

---

## Variant A — blunt and short

Short lines, hard stops, no throat-clearing. Reads confident. Best if you want
the post to feel like a senior engineer stating facts. Risk: can read cold, and
it claims some authority.

```text
Campus IT desks don't have a ticket problem. They have a repeatability problem.

Same five requests every morning. WiFi. Passwords. MFA. VPN. "Where's my ticket?"

Meanwhile the dead laptop that needs an actual technician sits behind all of it.

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

#Salesforce #Agentforce #ServiceCloud #Apex #ITSM
```

---

## Variant B — conversational, building in public (recommended)

First person, admits what's still being learned, ends on a real question. Best
fit for someone early in their career shipping something ambitious: it invites
replies instead of daring people to poke holes, and the closing line converts
"who is this guy" into a conversation. Also the easiest to defend in comments.

```text
I kept hearing the same thing about campus IT: it isn't that there are too many tickets, it's that they're the same tickets.

WiFi. Password resets. MFA loops. "Where's my ticket?" Every single morning.

And the student whose laptop actually died before an exam? They wait behind all of it.

I wanted to see if I could fix the ordering problem, so I built a triage agent on Salesforce. Here's 65 seconds of it — no sound, captions are on screen.

The part I care about most is what it doesn't do.

A student reports dropping WiFi. It hands back a guide and opens nothing. No ticket. That's a deflection, and it gets counted rather than guessed at.

Another student's laptop won't turn on before an exam. It tries first aid, then opens exactly one Case on the Hardware queue, High priority, four-hour response clock, contact linked.

Then that same student messages again about that same laptop. It reuses the ticket instead of opening a second one. That one behaviour is most of what makes support bots infuriating.

Under the hood: five Apex actions Agentforce can call, with routing rules and SLA hours in Custom Metadata so a service desk lead retunes them in Setup without touching code. Every action writes an audit row that can't be edited or deleted, so the deflection number can't quietly drift.

Being upfront: the video is a walkthrough of the interface, labelled as such, not a recording of a live org. The Apex, metadata, and permission set are real and deploy with the Salesforce CLI.

Still learning this stack. If you've worked a service desk and I've got the model wrong somewhere, I'd genuinely like to hear it.

Repo in the comments.

#Salesforce #Agentforce #ServiceCloud #BuildInPublic
```

---

## Variant C — technical and detailed

Names the metadata types and the actual invariants. Best if the audience you
want is Salesforce developers and architects rather than a general feed. Denser,
will lose non-technical readers, but the people it's for will trust it more.

```text
I built a Service Cloud triage agent that treats deflection as a measured number instead of a marketing claim.

The problem with most service desk bots isn't the conversation. It's that nothing downstream is auditable. They guess a category, open a duplicate, and leave you no way to prove what was actually deflected.

Architecture:

Five Apex invocable actions exposed to Agentforce — self-service lookup, escalation, ticket update, status check, operations snapshot. One @InvocableMethod each, List in, List out.

Routing lives in IT_Category_Queue_Map__mdt, known issues in IT_Known_Issue__mdt, SLA hours in IT_SLA_Rule__mdt. A service desk lead retunes queues, articles, or response targets in Setup with no deploy. No Salesforce record IDs are hardcoded anywhere.

Every action inserts a Campus_IT_Interaction__c row, and a before-update/before-delete trigger blocks tampering. Deflection is computed off that trail — matches divided by matches plus new Cases — so the number can't be rewritten after the fact.

Escalation is idempotent per student and category: an open Case is reused and commented on rather than duplicated, unless a force-new flag is set. Updates against closed Cases are rejected outright.

Apex tests run without SeeAllData, with test queues namespaced so they never collide with the packaged ones.

The 65-second walkthrough is attached, silent with captions. It shows the interface and is labelled on screen as a walkthrough, not a live org capture — the Apex, custom metadata, queues, and permission set are real and deploy with sf project deploy start.

Repo and architecture notes in the comments.

#Salesforce #Agentforce #ServiceCloud #Apex #ITSM
```

---

## First comment (post this immediately after, whichever variant you use)

```text
Code, architecture notes, and deploy steps:
https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

Developer Edition or a Trailhead Playground, Salesforce CLI, one deploy, one permission set. Agentforce is only needed for the conversational half — the technician app works without it.
```

## How to post it

1. Upload `docs/demo/campus-it-app-recording.mp4` as a **native video**. Do not
   link out to YouTube or Vimeo — LinkedIn only autoplays video it hosts, and
   link posts get less reach.
2. Keep the GitHub URL out of the post body. Put it in the first comment
   (above). A bare external link in the body suppresses distribution.
3. The first two lines are all that shows before "…see more" on mobile, so the
   hook has to survive alone. All three variants front-load it.
4. The video is silent with burned-in captions, which is what you want: LinkedIn
   autoplays muted, and most people never turn sound on.

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

Every variant above keeps that disclosure. Keep it. The audience for these
hashtags is people who work in Salesforce every day and will recognise a
reconstruction. Being straight about it costs nothing and is much cheaper than
being corrected in the comments.

**Want footage of the real thing?** Deploy to a Developer org (README, steps 1–5),
then screen-record the shot list in [`video-script.md`](video-script.md). That
gives you a genuine capture you can post without the qualifier — drop the
disclosure sentence from whichever variant you picked.

## Regenerating the walkthrough

```bash
cd scripts/demo-video
npm install
node record.mjs     # writes docs/demo/campus-it-app-recording.mp4
```

Needs `ffmpeg` on PATH. Set `CHROMIUM_PATH` to reuse a preinstalled browser and
`FFMPEG_PATH` if ffmpeg lives somewhere unusual.
