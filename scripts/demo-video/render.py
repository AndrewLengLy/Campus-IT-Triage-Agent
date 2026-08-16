#!/usr/bin/env python3
"""Render captioned 16:9 slides for the Campus IT Triage Agent demo video."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1920
HEIGHT = 1080
NAVY = (8, 18, 36)
NAVY_CARD = (16, 32, 56)
NAVY_LINE = (32, 56, 88)
WHITE = (244, 247, 251)
MUTED = (154, 170, 192)
BLUE = (61, 139, 255)
BLUE_DIM = (28, 74, 140)
GREEN = (61, 196, 140)
AMBER = (245, 165, 36)
RED = (232, 93, 93)

FONT_HEAD = Path("/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf")
FONT_BODY = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
FONT_BOLD = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")

OUT_DIR = Path(__file__).resolve().parents[2] / "docs" / "demo" / "frames"


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def new_slide() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (WIDTH, HEIGHT), NAVY)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 12, HEIGHT), fill=BLUE)
    draw.text((64, 48), "CAMPUS IT  ·  SERVICE DESK TRIAGE AGENT", font=font(FONT_BOLD, 22), fill=BLUE)
    draw.text((64, 1012), "Agentforce  ·  Service Cloud  ·  Salesforce DX", font=font(FONT_BODY, 22), fill=MUTED)
    return image, draw


def wrap(draw: ImageDraw.ImageDraw, text: str, typeface: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        trial = word if not current else f"{current} {word}"
        if draw.textlength(trial, font=typeface) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def heading(draw: ImageDraw.ImageDraw, eyebrow: str, title: str, y: int = 120) -> int:
    draw.text((64, y), eyebrow.upper(), font=font(FONT_BOLD, 24), fill=BLUE)
    title_font = font(FONT_HEAD, 64)
    lines = wrap(draw, title, title_font, 1760)
    cursor = y + 46
    for line in lines:
        draw.text((64, cursor), line, font=title_font, fill=WHITE)
        cursor += 74
    return cursor + 12


def card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int] = NAVY_CARD) -> None:
    draw.rounded_rectangle(box, radius=18, fill=fill, outline=NAVY_LINE, width=2)


def save(image: Image.Image, name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    image.save(path, "PNG")
    print(path)


def slide_title() -> None:
    image, draw = new_slide()
    draw.text((64, 280), "CAMPUS IT", font=font(FONT_HEAD, 42), fill=BLUE)
    draw.text((64, 340), "Triage the repeats.", font=font(FONT_HEAD, 92), fill=WHITE)
    draw.text((64, 450), "Escalate the real work.", font=font(FONT_HEAD, 92), fill=WHITE)
    draw.text(
        (64, 600),
        "An Agentforce agent for Service Cloud. Known-issue guides first,\n"
        "one Case on the right queue, an SLA clock, and an audit trail\n"
        "that can prove deflection.",
        font=font(FONT_BODY, 34),
        fill=MUTED,
        spacing=10,
    )
    save(image, "01-title.png")


def slide_problem() -> None:
    image, draw = new_slide()
    y = heading(draw, "The problem", "Campus desks drown in the same tickets every shift")
    items = [
        ("WiFi / VPN", "Residence-hall drops and off-campus VPN fill the queue every morning."),
        ("Password / MFA", "Identity lockouts are scripted work sitting in front of a technician."),
        ("“Where is my ticket?”", "Status questions create more tickets instead of answers."),
        ("Hardware waits", "Laptops that will not power on sit behind issues a guide could close."),
    ]
    top = y + 20
    for index, (title, body) in enumerate(items):
        col = index % 2
        row = index // 2
        x = 64 + col * 900
        box_y = top + row * 230
        card(draw, (x, box_y, x + 860, box_y + 200))
        draw.text((x + 36, box_y + 36), title, font=font(FONT_BOLD, 32), fill=WHITE)
        for i, line in enumerate(wrap(draw, body, font(FONT_BODY, 26), 780)):
            draw.text((x + 36, box_y + 90 + i * 36), line, font=font(FONT_BODY, 26), fill=MUTED)
    save(image, "02-problem.png")


def slide_solves() -> None:
    image, draw = new_slide()
    y = heading(draw, "What it solves", "A triage desk, not another FAQ chatbot")
    outcomes = [
        ("01", "Deflect", "Walk the student through a known-issue guide before anyone opens a Case."),
        ("02", "Escalate once", "If a human is required, create one ticket on the right queue with a first-response due time."),
        ("03", "Measure", "Every action writes an append-only row so the desk can see deflection and oldest wait."),
    ]
    top = y + 30
    for index, (num, title, body) in enumerate(outcomes):
        x = 64 + index * 600
        card(draw, (x, top, x + 572, top + 420))
        draw.text((x + 36, top + 36), num, font=font(FONT_HEAD, 40), fill=BLUE)
        draw.text((x + 36, top + 110), title, font=font(FONT_HEAD, 44), fill=WHITE)
        cursor = top + 190
        for line in wrap(draw, body, font(FONT_BODY, 28), 500):
            draw.text((x + 36, cursor), line, font=font(FONT_BODY, 28), fill=MUTED)
            cursor += 40
    save(image, "03-solves.png")


def slide_flow() -> None:
    image, draw = new_slide()
    heading(draw, "How it works", "Self-service first. A human only when needed.")
    steps = [
        ("1", "Guide", "Match WiFi, password,\nVPN, Outlook, MFA,\nor laptop first aid."),
        ("2", "Escalate", "Open or reuse a Case.\nRoute by category.\nStamp the SLA."),
        ("3", "Follow up", "Add a comment or\nread back status.\nRefuse closed tickets."),
        ("4", "Snapshot", "Open load, oldest wait,\nhigh-priority count,\ntoday’s deflection."),
    ]
    y = 360
    for index, (num, title, body) in enumerate(steps):
        x = 64 + index * 460
        card(draw, (x, y, x + 420, y + 430))
        draw.ellipse((x + 28, y + 28, x + 88, y + 88), fill=BLUE)
        draw.text((x + 48, y + 38), num, font=font(FONT_BOLD, 32), fill=WHITE)
        draw.text((x + 28, y + 120), title, font=font(FONT_HEAD, 40), fill=WHITE)
        draw.multiline_text((x + 28, y + 190), body, font=font(FONT_BODY, 26), fill=MUTED, spacing=8)
        if index < 3:
            draw.polygon(
                [(x + 428, y + 210), (x + 452, y + 222), (x + 428, y + 234)],
                fill=BLUE,
            )
    save(image, "04-flow.png")


def slide_actions() -> None:
    image, draw = new_slide()
    heading(draw, "The five actions", "Each one is invocable Apex the agent can call")
    rows = [
        ("Find Campus IT Self-Service Guide", "Try this first. Returns steps or says escalate."),
        ("Escalate Campus IT Ticket", "Create or reuse a Case. Queue + SLA + comment."),
        ("Add Campus IT Ticket Update", "Published Case Comment. Closed tickets are rejected."),
        ("Check Campus IT Ticket Status", "By Case Number or Student ID, including short numbers."),
        ("Get Campus IT Operations Snapshot", "Desk load and today’s deflection from the audit trail."),
    ]
    top = 340
    for index, (title, body) in enumerate(rows):
        y = top + index * 120
        card(draw, (64, y, 1856, y + 104))
        draw.rectangle((64, y, 76, y + 104), fill=BLUE)
        draw.text((108, y + 18), title, font=font(FONT_BOLD, 30), fill=WHITE)
        draw.text((108, y + 58), body, font=font(FONT_BODY, 24), fill=MUTED)
    save(image, "05-actions.png")


def slide_artifacts() -> None:
    image, draw = new_slide()
    heading(draw, "What it leaves behind", "Technicians keep Cases. Operations keep the trail.")
    card(draw, (64, 360, 930, 940))
    draw.text((104, 396), "Case", font=font(FONT_HEAD, 40), fill=WHITE)
    case_lines = [
        "Student ID and IT category",
        "Agent sourced, reused-ticket flag",
        "Self-service attempted + article",
        "First response due from SLA rules",
        "Published Case Comment",
        "Routed to Campus_IT_* queues",
    ]
    for i, line in enumerate(case_lines):
        draw.ellipse((104, 478 + i * 64, 120, 494 + i * 64), fill=GREEN)
        draw.text((144, 464 + i * 64), line, font=font(FONT_BODY, 28), fill=MUTED)

    card(draw, (990, 360, 1856, 940))
    draw.text((1030, 396), "Campus IT Interaction", font=font(FONT_HEAD, 40), fill=WHITE)
    audit_lines = [
        "INT-00000 autonumber",
        "Action, outcome, success",
        "Student, Case, category, article",
        "Written on every agent call",
        "Updates and deletes blocked",
        "Source for deflection math",
    ]
    for i, line in enumerate(audit_lines):
        draw.ellipse((1030, 478 + i * 64, 1046, 494 + i * 64), fill=AMBER)
        draw.text((1070, 464 + i * 64), line, font=font(FONT_BODY, 28), fill=MUTED)
    save(image, "06-artifacts.png")


def slide_ops() -> None:
    image, draw = new_slide()
    heading(draw, "Operations snapshot", "A number for load. A number for deflection.")
    metrics = [
        ("Open tickets", "12", "Agent-sourced, still open"),
        ("High priority", "3", "Waiting on a technician"),
        ("Oldest wait", "5h", "Inside a 4–40h SLA window"),
        ("Deflection", "67%", "Matches ÷ (matches + new Cases)"),
    ]
    top = 380
    for index, (label, value, note) in enumerate(metrics):
        x = 64 + index * 460
        card(draw, (x, top, x + 432, top + 360))
        draw.text((x + 32, top + 36), label.upper(), font=font(FONT_BOLD, 22), fill=BLUE)
        draw.text((x + 32, top + 100), value, font=font(FONT_HEAD, 84), fill=WHITE)
        for i, line in enumerate(wrap(draw, note, font(FONT_BODY, 26), 360)):
            draw.text((x + 32, top + 230 + i * 36), line, font=font(FONT_BODY, 26), fill=MUTED)
    draw.text(
        (64, 780),
        "Illustrative desk-load figures. Live values come from Cases and today’s audit rows.",
        font=font(FONT_BODY, 22),
        fill=MUTED,
    )
    save(image, "07-ops.png")


def slide_find() -> None:
    image, draw = new_slide()
    heading(draw, "Where to find it", "Open source. Deploy with Salesforce CLI.")
    card(draw, (64, 380, 1856, 720))
    draw.text((104, 430), "github.com/AndrewLengLy/Campus-IT-Triage-Agent", font=font(FONT_HEAD, 48), fill=WHITE)
    draw.text(
        (104, 520),
        "Apex actions, Custom Metadata, queues, permission set, demo data,\n"
        "architecture notes, operating model, and an eight-minute live-org script.",
        font=font(FONT_BODY, 30),
        fill=MUTED,
        spacing=10,
    )
    draw.text((104, 640), "sf project deploy start  ·  no hardcoded record IDs  ·  tests without SeeAllData", font=font(FONT_BOLD, 24), fill=BLUE)
    draw.text((64, 780), "Watch muted. Every slide is captioned.", font=font(FONT_BODY, 26), fill=MUTED)
    save(image, "08-find.png")


def main() -> None:
    slide_title()
    slide_problem()
    slide_solves()
    slide_flow()
    slide_actions()
    slide_artifacts()
    slide_ops()
    slide_find()


if __name__ == "__main__":
    main()
