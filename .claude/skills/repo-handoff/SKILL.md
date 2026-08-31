---
name: repo-handoff
description: Audit, harden, and launch a repo that was built somewhere else — Cursor, Lovable, v0, Bolt, ChatGPT, another Claude session, or an old side project being revived. Runs an audit-before-you-add pass that hunts claims the code does not actually back (mockups captioned as production, stock personas in demos, unmeasured coverage reported as fact, README features that do not exist), then produces the launch material: a silent captioned demo video and a plain-text post in Andrew's measured voice. Use this whenever the user hands over a project they built elsewhere, says they are taking a repo seriously or making it public, asks to get something ready to post or share, wants a demo video or launch post for a project, or asks for a repo audit or cleanup before showing it to anyone — even if they never say "handoff" or "audit."
---

# Repo handoff

A project vibe-coded to working almost always has a gap between what it says
about itself and what it does. That gap is invisible from inside the session
that wrote it, and obvious to anyone in the field who reads it. Close that
first, then ship it — a repo nobody sees is the same as a repo that does not
work.

Work the steps in order. Steps 1–5 are the audit, 6–7 produce the launch
material, 8 governs all the copy, 9 is how you report.

Announce what you found before you fix everything. If the audit turns up more
than a handful of things, list them, say which you are taking first, and
start — do not stop for approval on each one. Ask only before a call that
changes how the project is positioned.

## 1. Find the claims that don't hold

Read the whole repo first — code, README, docs, scripts, demo assets, launch
copy, sample data. Then check every place it states or implies something
against what the code actually does: README features, captions on a demo
video, screenshots, metrics, badges, names in a UI, seeded data, draft posts.

Report each gap with the exact file and line and what is actually true.

Weight findings by who reads them. A mockup captioned as production, a stock
persona in a video going out under the user's name, a claimed integration
that is a hardcoded string — these are the ones that cost credibility with an
audience that does this for a living. A typo is not in the same category.

## 2. Fix the framing before the features

Where something is a demo or a reconstruction, label it as one rather than
deleting it. The asset usually still does its job; only the framing was wrong.

Make the disclosure persistent — every frame and every doc that links it, not
one caption and not a footnote. A single honest frame at the start does not
survive being scrubbed past, and frame 0 is usually the thumbnail anyway.

## 3. Verify, don't assert

Anything that goes in a commit message, PR body, or README gets checked first.
Decode the video and read its real duration, resolution, and frame count.
Count the characters against the real limit. Run the tests.

When this environment cannot run something, say so plainly and say what has to
be run to get the real number. Never round an unmeasured thing up into a
claim — "estimated, not measured" is a perfectly good thing to ship, and it is
the sentence that keeps the rest of the report trustworthy.

## 4. Harden what's thin

- Tests that build their own data and do not lean on ambient environment state
- Bulk and failure paths, not just the happy one
- Where the cost of an operation matters, assert on the cost, so a regression
  fails the test rather than surfacing in production
- One command from fresh clone to a working environment
- Any step a script leaves as undocumented manual work becomes part of the
  script

## 5. Don't silently widen scope

Real problems found outside the ask get documented for a decision — in an
architecture doc or the PR body — not fixed in passing. The user decides what
their project becomes.

Where current behavior is questionable but changing it is their call, write a
clearly named characterization test that records what it does today. The suite
stays green while the decision stays open, and nobody has to remember the
issue.

## 6. Build the demo video

60–75 seconds, 1920x1080, silent with captions burned into the frame. Silent
is not a compromise: LinkedIn autoplays muted and most people never turn sound
on, so a video that depends on narration plays as nothing.

Build it as a self-contained HTML page committed to the repo that reconstructs
the real UI with no network calls, drive it with a timed script, and record it
headless. `scripts/record_walkthrough.mjs` in this skill does the recording and
encoding — it is the version that already survived the mistakes below.

Encoding: H.264, CRF 20, yuv420p, 25 fps, `-movflags +faststart`, `-an`.

The rules that matter more than the encoding:

- **One command regenerates it.** No manual conversion step, and honor
  `CHROMIUM_PATH` / `FFMPEG_PATH` so it runs on any machine.
- **Wait on a completion flag the page sets**, not a fixed timeout. A timeout
  ships a video that cuts off mid-scene on a slower machine.
- **`+faststart` matters.** Without it the `moov` atom lands after `mdat` and
  the file downloads in full before rendering a frame.
- **Route every caption through one function.** Then a disclosure tag appended
  there holds for the entire runtime instead of one frame.
- **Frame 0 is the thumbnail.** It carries the project name and the claim.
- **If it is a reconstruction, say so on screen for the full duration.**
- **The logged-in user in any UI is the author**, never a stock persona. A
  stranger's name in the corner invites exactly the question the disclosure
  was there to answer.
- **Show the behavior that is hard, not the happy path.** What the system
  refuses to do is usually the most convincing beat — the duplicate it does
  not open, the update it rejects.
- Caption copy follows step 8. Same register as the post, so the two read as
  one piece.

## 7. Write the launch post

Plain text. LinkedIn renders Markdown literally, so bold markers and backticks
ship as visible punctuation. Under 3000 characters.

- **First line at most 140 characters.** That is the mobile "see more" cut. A
  longer first line truncates mid-sentence, usually on the best word in it.
- **Open on a concrete specific from the domain** that proves the author has
  actually done this work — a detail only someone who has would reach for,
  not a claim of experience.
- **Repo link goes in a first comment, not the body.** A bare external link in
  the body suppresses reach.
- **Upload the video natively.** Never link out to YouTube or Vimeo.
- **Carry the same disclosure the video carries.** The people reading those
  hashtags will recognize a reconstruction, and being corrected in the
  comments costs far more than the qualifier.
- **Ship three registers on one opener**: blunt as primary, conversational,
  technical. Report the character count and first-line length for each.
- If the hook is seasonal or otherwise expires, say so in the posting notes.
- Include posting mechanics and video specs so the user can post without
  asking anything.

## 8. Write it in Andrew's voice

Governs the video captions, the post, and any copy written for him.

- One idea per paragraph. Most paragraphs are one sentence. Use the white space.
- Short declaratives, hard stops. Median sentence around 25–30 characters.
- Fragments are fine when they land. Noun phrases as sentences.
- Concrete specifics instead of adjectives — real identifiers, real numbers,
  real names for things. Never "seamless," "powerful," "robust."
- Contrast pairs do the arguing: "in Setup, not in code." "It reuses 00001024.
  It does not open 00001025."
- State the turn flatly. "So I built one that doesn't." No build-up.
- Lead with what it refuses to do. The negative space is the product.
- No emoji. No exclamation marks. No "excited to share." No rhetorical
  questions to open.
- Admit limits in the same flat register as the claims — neither softened nor
  dramatized.
- End plainly. "Repo in the comments."

**This spec is measured, not impressionistic.** It comes from the post Andrew
chose as primary over a conversational and a technical alternate: 1237
characters, 14 paragraphs, 6 of 14 a single sentence, median sentence 26
characters, first line exactly 140. Its shortest sentences are the
load-bearing ones — *They guess. No secrets. Hardware queue. Four-hour clock.*

Check drafts rather than eyeballing them:

```bash
python3 scripts/voice_check.py draft.txt
```

It reports the same metrics and flags Markdown artifacts, emoji, exclamation
marks, an over-length first line, and median drift. Treat a failing check as a
signal to cut, not as a reason to argue with the number — but the numbers are
targets, not a rubric to satisfy mechanically. Copy that hits every metric and
says nothing is still bad copy.

If working on behalf of someone else, re-derive the spec from their own
writing with the same script instead of applying Andrew's.

## 9. Write the PR body for a reviewer

Lead with what was wrong and why it mattered, then what changed. Then:

- **Verification** — what you actually checked and how
- **Not done** — what you could not do and why

If the honest answer is something the user does not want to hear, that is the
one they most need in there. The value of the report is that it can be
trusted; a Not Done section is what buys that.

## Bundled scripts

| Script | Use |
| --- | --- |
| `scripts/voice_check.py` | Measure any draft against the voice spec in step 8 |
| `scripts/record_walkthrough.mjs` | Record and encode the step 6 walkthrough video |
