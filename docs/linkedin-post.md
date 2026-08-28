# LinkedIn launch post

LinkedIn does not render Markdown. The block below is plain text on purpose —
copy it exactly as it is. Asterisks, backticks, and `[text](url)` links show up
as literal characters in the feed.

## Post (copy from here)

```text
Campus IT desks don't have a ticket problem. They have a repeatability problem.

The same requests hit the queue every morning: WiFi, password resets, MFA loops, VPN, "where's my ticket?" Meanwhile the dead laptop that actually needs a technician waits behind all of it.

Most chatbots make that worse. They guess, they open duplicate tickets, and nobody can prove they deflected anything.

So I built a triage agent on Salesforce that behaves like a service desk instead of a FAQ widget.

What's in the video (65 seconds, no audio, captions on screen):

1. A student reports dropping WiFi. The agent matches a known-issue guide and opens no ticket. A measured deflection, not a guess.

2. Another student's laptop won't power on before an exam. First aid first, then one Case on the Hardware queue at High priority, contact linked, with a four-hour first-response clock.

3. Same student, same laptop, second message. It reuses ticket 00001024 instead of opening 00001025.

4. A supervisor asks how backed up the desk is. Open load, oldest wait, and today's deflection rate, read from an append-only audit object.

How it's built:

- Five Apex invocable actions, called from Agentforce
- Routing rules, known-issue articles, and SLA hours live in Custom Metadata, so a desk lead changes them in Setup with no deploy
- Every action writes an append-only interaction row, and a trigger blocks edits and deletes, so the deflection number can't be quietly rewritten
- No hardcoded record IDs, no Connected Apps, no secrets
- Apex tests run without SeeAllData

About the video: it's a walkthrough of the interface, labelled on screen, not a capture of a live org. The Apex, custom metadata, queues, and permission set are real and deploy to a Developer org with the Salesforce CLI.

Repo and deploy steps in the comments.

#Salesforce #Agentforce #ServiceCloud #Apex #ITSM
```

## First comment (post this immediately after)

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
   hook has to survive alone. It does.
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

Keep that label. The audience for these hashtags is people who work in
Salesforce every day and will recognise a reconstruction. Being straight about
it costs nothing and is much cheaper than being corrected in the comments.

**Want footage of the real thing?** Deploy to a Developer org (README, steps 1–5),
then screen-record the shot list in [`video-script.md`](video-script.md). That
gives you a genuine capture you can post without the qualifier — and you can
reuse this same post text, minus the "About the video" paragraph.

## Regenerating the walkthrough

```bash
cd scripts/demo-video
npm install
node record.mjs     # writes docs/demo/campus-it-app-recording.mp4
```

Needs `ffmpeg` on PATH. Set `CHROMIUM_PATH` to reuse a preinstalled browser and
`FFMPEG_PATH` if ffmpeg lives somewhere unusual.
