# Handing a Cursor-built project to Claude Code

The prompt below is the one to paste as the first message in a new Claude Code
session on a repo that was built somewhere else and is now being taken
seriously. It is written from what actually happened when this repo made that
move — see [What it caught here](#what-it-caught-here) for the record.

The shape of it: **audit before you add.** A project that was vibe-coded to
working usually has a gap between what it says about itself and what it does.
That gap is invisible from inside the session that wrote it and obvious to
anyone in the field who reads it. Closing it is worth more than the next
feature.

## The prompt

```text
This repo was built in Cursor and I'm handing it to you. Before you add
anything, audit what's here as if you were the engineer whose name goes on it
publicly.

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

6. WRITE THE PR BODY FOR A REVIEWER.
Lead with what was wrong and why it mattered, then what changed. Include a
Verification section listing what you actually checked and how. Include a Not
Done section listing what you couldn't do and why. If the honest answer is
something I don't want to hear, that is the one I most need in there.

Treat distribution as part of the deliverable — README, demo, and launch copy
are load-bearing, not decoration, and the same standard of accuracy applies to
them as to the code.

If the audit turns up more than a handful of things, list them, tell me which
you're taking first, and start. Ask me before any call that changes how the
project is positioned.
```

## Optional add-ons

Append only the ones that apply. Each is a line that changed the outcome here.

| Situation | Line to add |
| --- | --- |
| The repo is about to be posted publicly | `Assume this ships to LinkedIn this week. Anything that would embarrass me in front of someone who does this for a living is a P0.` |
| It has a demo video or screenshots | `Re-derive every demo asset from a script in the repo so it can be regenerated, and check the encoding is actually web-playable, not just present.` |
| It ships to a platform with formatting rules | `Check the copy against how the destination actually renders it, not how Markdown looks in an editor.` |
| The environment can't run the project | `You have no way to run this. Every coverage or performance number is therefore an estimate and must be labelled as one.` |
| It is a library or has no public face | `Skip the framing pass. Spend the time on the API surface: what a caller can misuse, what is undocumented, and what breaks on upgrade.` |
| Someone else keeps working in Cursor | `Leave the repo in a state where the next Cursor session inherits the standard: put the rules in CLAUDE.md rather than only in this PR.` |

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
