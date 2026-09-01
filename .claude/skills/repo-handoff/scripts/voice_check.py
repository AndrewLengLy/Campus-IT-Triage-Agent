#!/usr/bin/env python3
"""Measure a draft against the voice spec in SKILL.md step 8.

Usage:
    python3 voice_check.py draft.txt
    python3 voice_check.py post.md --block 1   # nth ```text fenced block
    cat draft.txt | python3 voice_check.py

The targets come from the post Andrew chose as primary over two alternates:
1237 chars, 14 paragraphs, 6 of 14 single-sentence, median sentence 26 chars,
first line exactly 140. They are targets, not a rubric — copy that passes every
check and says nothing is still bad copy. Exits 1 if any hard limit is broken
so it can gate a commit.
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys

MEDIAN_MAX = 40        # drift past this and it stops sounding like him
FIRST_LINE_MAX = 140   # LinkedIn mobile "see more" cut
TOTAL_MAX = 3000       # LinkedIn post limit

MARKDOWN = [
    (r"\*\*[^*\n]+\*\*", "bold markers (**) — LinkedIn prints these literally"),
    (r"(?<!`)`[^`\n]+`(?!`)", "backticks — printed literally"),
    (r"^\s{0,3}#{1,6}\s", "heading syntax — printed literally"),
    (r"\[[^\]\n]+\]\([^)\n]+\)", "markdown links — printed literally"),
    (r"^\s{0,3}[-*+]\s", "markdown bullets — use plain lines or real characters"),
]
EMOJI = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF←-⇿⬀-⯿]"
)


def extract(text: str, block: int | None) -> str:
    """Pull the nth fenced block if asked, else use the text as-is."""
    if block is None:
        return text.strip()
    blocks = re.findall(r"```(?:text|txt)?\n(.*?)```", text, re.S)
    if not blocks:
        sys.exit("no fenced blocks found; drop --block to measure the whole file")
    if block < 1 or block > len(blocks):
        sys.exit(f"--block {block} out of range; file has {len(blocks)}")
    return blocks[block - 1].strip()


def sentences(text: str) -> list[str]:
    return [s.strip() for s in re.findall(r"[^.!?\n]+[.!?]", text) if s.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description="Check a draft against the voice spec.")
    ap.add_argument("path", nargs="?", help="file to check; omit to read stdin")
    ap.add_argument("--block", type=int, help="measure the nth ```text fenced block")
    args = ap.parse_args()

    raw = open(args.path, encoding="utf-8").read() if args.path else sys.stdin.read()
    text = extract(raw, args.block)
    if not text:
        sys.exit("nothing to measure")

    lines = text.split("\n")
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    sents = sentences(text)
    if not sents:
        sys.exit("no sentences found — check the input is prose, not a fragment")

    lengths = sorted(len(s) for s in sents)
    median = int(statistics.median(lengths))
    single = sum(1 for p in paras if len(re.findall(r"[.!?]", p)) <= 1)
    first = len(lines[0])

    print(f"  characters       {len(text)}")
    print(f"  paragraphs       {len(paras)}")
    print(f"  single-sentence  {single} of {len(paras)}")
    print(f"  sentences        {len(sents)}")
    print(f"  median sentence  {median} chars")
    print(f"  first line       {first} chars")
    print("\n  shortest:", " / ".join(sorted(sents, key=len)[:4]))

    hard, soft = [], []

    if first > FIRST_LINE_MAX:
        hard.append(
            f"first line is {first} chars, past the {FIRST_LINE_MAX} mobile cut — "
            f"it will truncate on '{lines[0][:FIRST_LINE_MAX].split()[-1]}'"
        )
    if len(text) > TOTAL_MAX:
        hard.append(f"{len(text)} chars, over the {TOTAL_MAX} limit")

    for pattern, why in MARKDOWN:
        found = re.findall(pattern, text, re.M)
        if found:
            hard.append(f"{why} — {len(found)} found, e.g. {found[0].strip()!r}")

    if EMOJI.search(text):
        hard.append(f"emoji present: {''.join(dict.fromkeys(EMOJI.findall(text)))}")
    if "!" in text:
        hard.append(f"{text.count('!')} exclamation mark(s)")

    if median > MEDIAN_MAX:
        soft.append(f"median sentence {median} chars, past {MEDIAN_MAX} — cut and split")
    if paras and single / len(paras) < 0.3:
        soft.append(
            f"only {single} of {len(paras)} paragraphs are a single sentence — "
            "break up the dense ones"
        )
    for phrase in ("excited to share", "thrilled", "delighted", "game-chang",
                   "seamless", "powerful", "robust", "leverage", "cutting-edge"):
        if phrase in text.lower():
            soft.append(f"{phrase!r} — swap for a concrete specific")

    for label, items in (("FAIL", hard), ("SOFT", soft)):
        for item in items:
            print(f"\n  {label}  {item}")
    if not hard and not soft:
        print("\n  clean — reads in register")

    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
