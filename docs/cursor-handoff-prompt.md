# Handing a Cursor-built project to Claude Code

The prompt below is the one to paste as the first message in a new Claude Code
session on a repo that was built somewhere else and is now being taken
seriously. It is written from what actually happened when this repo made that
move — see [What it caught here](#what-it-caught-here) for the record.

The shape of it: **audit before you add, then ship it.** A project that was
vibe-coded to working usually has a gap between what it says about itself and
what it does. That gap is invisible from inside the session that wrote it and
obvious to anyone in the field who reads it. Close that first. Then produce
the launch material — the demo video and the post — because a repo nobody sees
is the same as a repo that doesn't work.

Steps 6 and 7 produce that material, and they are governed by the voice spec
in step 8, which is [derived from measurements](#the-voice-spec) of the post
Andrew chose as primary here, not from a general idea of good writing.

## The prompt

```text
This repo was built in Cursor and I'm handing it to you. Before you add
anything, audit what's here as if you were the engineer whose name goes on it
publicly. Then get it ready to post.

Read the whole thing first — code, README, docs, scripts, demo assets, launch
copy, sample data. Then work in this order.

1. FIND THE CLAIMS THAT DON'T HOLD.
Everywhere the repo states or implies something — a README feature, a caption
on a demo video, a screenshot, a metric, a badge, a name in a UI, seeded data,
a draft post — check it against what the code actually does. Report each gap
with the exact file and line and what is actually true. Weight it by who reads
it: a mockup captioned as production, a stock persona in a video going out
under my name, a claimed integration that is a hardcoded string. Assume the
audience does this for a living and will notice.

2. FIX THE FRAMING BEFORE THE FEATURES.
Where something is a demo or a reconstruction, label it as one instead of
deleting it. Keep the asset, make it accurate, and make the disclosure
persistent — every frame and every doc that links it, not one caption and not
a footnote.

3. VERIFY, DON'T ASSERT.
Anything you put in a commit message, PR body, or README, you check first.
Decode the video and read its real duration, resolution, and frame count.
Count the characters against the real limit. Run the tests. If this
environment cannot run something, say so plainly, say what has to be run to
get the real number, and never round an unmeasured thing up into a claim.

4. HARDEN WHAT'S THIN.
Tests that build their own data and don't lean on ambient environment state.
Bulk and failure paths, not just the happy one — and where the cost of an
operation matters, assert on the cost so a regression fails the test rather
than showing up in production. One command from fresh clone to a working
environment. Any step a script leaves as undocumented manual work becomes part
of the script.

5. DON'T SILENTLY WIDEN SCOPE.
Real problems you find outside what I asked for get documented for a decision
— in an architecture doc or the PR body — not fixed in passing. Where current
behavior is questionable but changing it is my call, write a clearly named
characterization test that records what it does today, so the suite stays
green while the decision is open.

6. BUILD THE DEMO VIDEO.
60 to 75 seconds, 1920x1080, silent with captions burned into the frame —
LinkedIn autoplays muted and most people never turn sound on. Build it as a
self-contained HTML page committed to the repo that reconstructs the real UI
with no network calls, drive it with a timed script, and record it headless
with Playwright. Encode H.264 at CRF 20, yuv420p, 25 fps, with -movflags
+faststart so it streams instead of downloading in full before the first
frame, and -an since there is no audio.

Rules that matter more than the encoding:
- One command regenerates it from the repo. No manual conversion step, and
  honor CHROMIUM_PATH / FFMPEG_PATH so it runs anywhere.
- Wait on a completion flag the page sets, not a fixed timeout, or you will
  ship a video that cuts off mid-scene on a slow machine.
- Route every caption through one function, so an honesty tag appended there
  holds for the whole runtime instead of one frame.
- Frame 0 is the thumbnail. It carries the project name and the claim.
- If it is a reconstruction, say so on screen for the full duration.
- The logged-in user in any UI is me, not a stock persona.
- Show the behavior that is hard, not the happy path: the thing it refuses to
  do is usually the most convincing beat.
- Caption copy follows the voice spec in step 8. Same register as the post.

7. WRITE THE LAUNCH POST.
Plain text — LinkedIn renders Markdown literally, so bold markers and
backticks ship as punctuation. Under 3000 characters.

- First line at most 140 characters. That is the mobile "see more" cut, and a
  first line past it truncates mid-sentence, usually on the best word in it.
- Open on a concrete specific from the domain that proves I have actually done
  this work. Not a claim of experience — a detail only someone who has would
  reach for.
- Repo link goes in a first comment, not the body. A bare external link in the
  body suppresses reach.
- Upload the video natively. Never link out to YouTube or Vimeo.
- Carry the same disclosure the video carries. The people in those hashtags
  will recognize a reconstruction, and being corrected in the comments costs
  far more than the qualifier.
- Ship three registers on the same opener: blunt as primary, conversational,
  technical. Give me the character count and first-line length for each.
- If the hook is seasonal or otherwise expires, say so in the posting notes.
- Include posting mechanics and video specs so I can post it without asking
  you anything.

8. WRITE IT IN MY VOICE.
Governs step 6, step 7, and any copy you write for me.

- One idea per paragraph. Most paragraphs are one sentence. Use the white
  space.
- Short declaratives, hard stops. Median sentence around 25-30 characters.
  "They guess." "No secrets." "Four-hour clock."
- Fragments are fine when they land. Noun phrases as sentences.
- Concrete specifics instead of adjectives. Real identifiers, real numbers,
  real names for things. Never "seamless," "powerful," "robust."
- Contrast pairs do the arguing: "in Setup, not in code." "It reuses 00001024.
  It does not open 00001025."
- State the turn flatly. "So I built one that doesn't." No build-up.
- Lead with what it refuses to do. The negative space is the product.
- No emoji. No exclamation marks. No "excited to share." No rhetorical
  questions to open.
- Admit the limits in the same flat register as the claims. Do not soften
  them and do not dramatize them.
- End plainly. "Repo in the comments."

9. WRITE THE PR BODY FOR A REVIEWER.
Lead with what was wrong and why it mattered, then what changed. Include a
Verification section listing what you actually checked and how. Include a Not
Done section listing what you couldn't do and why. If the honest answer is
something I don't want to hear, that is the one I most need in there.

If the audit turns up more than a handful of things, list them, tell me which
you're taking first, and start. Ask me before any call that changes how the
project is positioned. Don't ask me to approve copy before writing it — write
it, then I'll edit.
```

## Optional add-ons

Append only the ones that apply. Each is a line that changed the outcome here.

| Situation | Line to add |
| --- | --- |
| The repo is about to be posted publicly | `Assume this ships to LinkedIn this week. Anything that would embarrass me in front of someone who does this for a living is a P0.` |
| The project can't be screen-recorded live | `I have no deployed environment to capture. Build the walkthrough as a reconstruction and label it as one — do not fake a live capture.` |
| It already has demo assets | `Re-derive every demo asset from a script in the repo so it can be regenerated, and check the encoding is actually web-playable, not just present.` |
| Posting somewhere other than LinkedIn | `Check the copy against how the destination actually renders it and what it does to reach, not how Markdown looks in an editor.` |
| The environment can't run the project | `You have no way to run this. Every coverage or performance number is therefore an estimate and must be labelled as one.` |
| It is a library or has no public face | `Skip the framing pass and the video. Spend the time on the API surface: what a caller can misuse, what is undocumented, and what breaks on upgrade.` |
| Someone else keeps working in Cursor | `Leave the repo in a state where the next Cursor session inherits the standard: put the rules in CLAUDE.md rather than only in this PR.` |

## The voice spec

Step 8 is measured, not guessed. The numbers come from the primary post in
`docs/linkedin-post.md` — the register chosen as primary over the
conversational and technical alternates:

| | |
| --- | --- |
| Length | 1237 characters |
| Paragraphs | 14 |
| Single-sentence paragraphs | 6 of 14 |
| Median sentence | 26 characters |
| First line | 140 characters, exactly at the mobile cut |

The shortest sentences in it are the load-bearing ones: *They guess. No
secrets. High priority. Hardware queue. Four-hour clock. No ticket opened. No
hardcoded IDs. Five Apex actions.*

The video captions are written in the same register, which is why the two read
as one piece: *"Self-service match. The Case list does not grow. Deflection
stays measurable."* · *"Same student, same laptop. Reuse 00001024. Do not open
00001025."*

Re-run the measurement on any post before shipping it. If the median sentence
is drifting past 40 characters, it has stopped sounding like him.

## What it caught here

Four Cursor commits built a working Salesforce triage agent and its launch
material. The handoff produced three PRs, none of them feature work.
[#2](https://github.com/AndrewLengLy/Campus-IT-Triage-Agent/pull/2) is merged;
[#1](https://github.com/AndrewLengLy/Campus-IT-Triage-Agent/pull/1) and
[#3](https://github.com/AndrewLengLy/Campus-IT-Triage-Agent/pull/3) are still
open, so each finding below says where it stands.

**Positioning was wrong.** *(#1, open)* The repo sold itself as an Agentforce
agent when what it is is a native Service Cloud backend that an org with
Agentforce enabled can expose. Corrected across the Apex headers, the
invocable-variable copy, the `Source:` line written into every Case
description, the Custom Metadata descriptions, the permission set, the README,
and five docs.

**The demo video claimed to be a live org.** *(#2, merged)* The walkthrough
page is a self-contained reconstruction — zero network calls, every reply a
hardcoded string — and it opened on the caption *"A live Campus IT desk in
Lightning Experience."* Frame 0 is also the LinkedIn thumbnail, so that claim
would have led the post in front of an audience that works in Salesforce
daily. The video was kept and relabelled, with a persistent `UI walkthrough ·
not a live org capture` tag appended by `setCaption()` to every caption for
all 65 seconds, rather than one honest frame.

**The demo workspace was logged in as a stranger.** *(#3, open — still on
`main`)* The Lightning header showed a placeholder service desk lead, "Maya
Ortiz," in a video going out under Andrew's own name.

**The post was written in Markdown.** *(#2, merged)* LinkedIn renders it
literally, so every `**bold**` and backtick would have shipped as punctuation.
Rewritten as plain text, with the repo link moved into a first comment so the
body carries no reach-demoting external link.

**The first line ran 207 characters.** *(#2, merged)* Well past LinkedIn's
~140-character mobile "see more" cut, so it would have truncated mid-sentence
directly on `eduroam` — the one word in it that signals having actually worked
a campus desk. All three variants were resized to 140.

**The recording script wasn't reproducible.** *(#2, merged)* `record.mjs`
stopped at Playwright's WebM and left MP4 conversion as an undocumented manual
step, and the committed MP4 had its `moov` atom after `mdat`, so it downloaded
in full before rendering a frame. It now encodes H.264 with `+faststart` and
honors `CHROMIUM_PATH` / `FFMPEG_PATH`.

**Tests didn't cover the paths that break.** *(#1, open)* Six new classes: a
shared factory with isolated `CIT_Test_*` queues, end-to-end proof that the
shipped Custom Metadata routes onto all five real queues, 200 records through
every action in one transaction asserting on `Limits.getQueries()` so a
regression fails the test rather than the org, negative paths for deleted
queues and partial saves, and append-only enforcement under
`allOrNone = false`.

And the two things it refused to overstate: coverage was reported as
**estimated, not measured**, because that environment had no Salesforce CLI
and no org to run against; and thirteen issues found while writing those tests
were written up for a decision rather than fixed in passing, with
characterization tests holding current behavior green while the decision stays
open.

Every claim above was checked before it was written — full-file decode passes,
frame counts, `moov` position, sampled frames, character counts.
