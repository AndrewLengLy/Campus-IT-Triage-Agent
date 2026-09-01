# Handing a Cursor-built project to Claude Code

This is packaged as a skill: [`.claude/skills/repo-handoff/`](../.claude/skills/repo-handoff/SKILL.md).
It triggers on its own when a repo built elsewhere gets handed over, so there
is nothing to paste. This page is the provenance — where the steps came from
and what they caught — plus how to install the skill globally.

**The skill's [`SKILL.md`](../.claude/skills/repo-handoff/SKILL.md) is the
source of truth for the steps.** They are not duplicated here, so the two
cannot drift.

## Install it for every project

The skill lives in this repo, which makes it active here. To have it fire on
any repo:

```bash
cp -r .claude/skills/repo-handoff ~/.claude/skills/
```

Nothing else to configure. It triggers on phrasings like "I built this in
Cursor, take it over," "get this ready to post," "make a demo video for this,"
or "audit this before I show anyone."

## What it does

Nine steps in three groups.

**1–5, the audit.** Find claims the code does not back, fix framing before
features, verify rather than assert, harden bulk and failure paths, and
document out-of-scope findings for a decision instead of fixing them in
passing.

**6–7, the launch material.** A 60–75s silent captioned walkthrough video, and
a plain-text post with the first line inside the mobile truncation cut, the
link in a first comment, and three registers on one opener.

**8, the voice spec**, which governs both the captions and the post — see
below.

**9, the PR body**, with Verification and Not Done sections.

Two bundled scripts do the parts worth automating:

| Script | What it does |
| --- | --- |
| `scripts/voice_check.py` | Measures a draft against the voice spec and flags Markdown artifacts, emoji, an over-length first line, and median drift |
| `scripts/record_walkthrough.mjs` | Serves a walkthrough page, records it headless, encodes web-ready H.264 |

The shape of all of it: **audit before you add, then ship it.** A project
vibe-coded to working usually has a gap between what it says about itself and
what it does. That gap is invisible from inside the session that wrote it and
obvious to anyone in the field who reads it. Close that first. Then produce
the launch material, because a repo nobody sees is the same as a repo that
does not work.

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

Re-run the measurement on any draft before shipping it — that is what
`scripts/voice_check.py` in the skill is for. If the median sentence drifts
past 40 characters, it has stopped sounding like him.

The numbers are targets, not a rubric. Copy that hits every metric and says
nothing is still bad copy.

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
