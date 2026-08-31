# LinkedIn launch post

LinkedIn does not render Markdown. Everything inside the fenced blocks is plain
text on purpose — copy it exactly. Asterisks, backticks, and `[text](url)` links
show up as literal characters in the feed.

## Post

Andrew's own draft, edited rather than replaced. His sentences and rhythm are
kept — "Oftentimes", "The idea is to improve ticket resolution times", the
"While the video… However the code is real" construction, the short enthusiastic
sign-off. Three things were added because the draft was missing them:

1. **The repo is public, so the post should send people there.** The draft ended
   on "Repo will come out soon!", which spends the post's attention and asks for
   it back later. Attention on a feed does not come back.
2. **Duplicate suppression.** Reusing the open ticket instead of opening a
   second one is the behaviour that separates this from a FAQ bot, and it was
   in the video but not the post.
3. **The audit trail.** Without it the post describes something any chatbot
   claims. "A log that can't be edited afterwards" is the sentence that makes
   the deflection number believable.

The first line is 132 characters, inside LinkedIn's mobile "…see more" cut
(~140). The draft's opener ran 203 and would have been chopped mid-clause, so
"around this time" was dropped — "starting up again" already carries the timing.

**Two claims to be comfortable with.** The four hour deadline is this repo's own
SLA rule for high-priority tickets, not an industry standard. And the hashtags
are an addition — the draft had none; they help discovery but drop them if they
feel off.

**The opener has a shelf life.** It reads as current for the first couple of
weeks of term and stale after.

```text
The regular semester is starting up again, and the IT issues I remember having to go through were eduroam, password resets, and MFA.

Oftentimes a high volume of people running into the same problems leads to a backlog that could be solved with the same solution.

So I built a Salesforce app that sorts problems by how fast they can potentially be solved. It is Apex actions that Agentforce can call, creating real Cases on real support queues. Where a wifi problem is handed a known solution and can get sorted out in a minute, a broken laptop is marked high priority, routed to the hardware queue, and given a four hour first response deadline.

It also handles the things that make backlogs worse. If the same student writes in again about the same laptop issues, it adds to the request they already have instead of opening another ticket, so they can keep their position in queue. Updates on a closed ticket get turned away rather than quietly lost.

The idea is to improve ticket resolution times. Routine problems are given known solutions before queuing for support and the person who needs specialized solutions can get recognized faster.

The routing rules, the known solutions, and the response deadlines all live in Salesforce settings instead of the code, so whoever runs the desk can retune them without a developer.

The part I found most interesting to build was the record keeping. Every action is written to a log that can't be edited or deleted afterwards, and that is enforced in the code rather than by policy, so the desk can show how much really got resolved without support instead of estimating it.

Important to note that while the video walks through the interface, it isn't recorded from a live org. However the code is real, it deploys with the Salesforce CLI, and the Apex is tested.

Link to the repo is in the comments! :)
```

### First comment (post this immediately after)

```text
Code, architecture notes, and deploy steps:
https://github.com/AndrewLengLy/Campus-IT-Triage-Agent

Developer Edition or a Trailhead Playground, Salesforce CLI, one deploy, one permission set. Agentforce is only needed for the conversational half — the technician app works without it.
```

---

## Alternates

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
