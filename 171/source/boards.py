"""Before/after boards for #171: today's render beside the HTML mockup, all at 2x points.
Each board is rows of (label, image, scale to 2x); images in a row sit side by side, top-aligned."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FONTS, BEFORE, AFTER, OUT = (Path(p) for p in sys.argv[1:5])
GROUND, INK, MUTED, RULE = (0x17, 0x17, 0x17), (0xED, 0xED, 0xEA), (0xA8, 0xA8, 0xA5), (0x2E, 0x2E, 0x2E)
PAD, GAP, HEAD, CAP = 64, 48, 120, 56
B, A = BEFORE, AFTER

BOARDS = [
    ("1-panel", "Menu-bar panel", [
        [("Today: following layers", B / "panel-layers.png", .5), ("Proposed, dark (with Tempo master)", A / "panel-after.png", 1),
         ("Proposed, light", A / "panel-light-after.png", 1)],
        [("Today: bridge stopped, with help", B / "panel-many-lights.png", .5), ("Proposed", A / "panel-stopped-after.png", 1)],
    ]),
    ("2-settings", "Settings", [
        [("Today: one form, 874 pt tall", B / "settings.png", 1), ("Proposed: Controller", A / "settings-controller-after.png", 1),
         ("Proposed: Decks", A / "settings-decks-after.png", 1)],
        [("Proposed: Syndicate", A / "settings-syndicate-after.png", 1), ("Proposed: General", A / "settings-general-after.png", 1),
         ("Proposed: Decks, light", A / "settings-decks-light-after.png", 1)],
    ]),
    ("3-diagnostics", "Diagnostics", [
        [("Today", B / "diagnostics-midi-monitor.png", .5)],
        [("Proposed", A / "diagnostics-after.png", 1)],
    ]),
    ("4-setup", "Setup guide", [
        [("Today", B / "setup-guide-connected.png", .5), ("Proposed", A / "setup-after.png", 1)],
    ]),
]


def load(path, scale):
    im = Image.open(path).convert("RGB")
    return im if scale == 1 else im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)


bold = ImageFont.truetype(str(FONTS / "Inter-Bold.ttf"), 44)
label = ImageFont.truetype(str(FONTS / "Inter-SemiBold.ttf"), 24)
OUT.mkdir(parents=True, exist_ok=True)
for name, title, rows in BOARDS:
    rows = [[(t, load(p, s)) for t, p, s in row] for row in rows]
    widths = [sum(i.width for _, i in r) + GAP * (len(r) - 1) for r in rows]
    heights = [max(i.height for _, i in r) + CAP for r in rows]
    W, H = PAD * 2 + max(widths), HEAD + sum(heights) + GAP * (len(rows) - 1) + PAD
    board = Image.new("RGB", (W, H), GROUND)
    d = ImageDraw.Draw(board)
    d.text((PAD, 56), f"#171 · {title}", font=bold, fill=INK, anchor="lm")
    y = HEAD
    for row, h in zip(rows, heights):
        x = PAD
        for text, im in row:
            d.text((x, y + 16), text, font=label, fill=MUTED, anchor="lm")
            d.rectangle((x - 1, y + CAP - 1, x + im.width, y + CAP + im.height), outline=RULE)
            board.paste(im, (x, y + CAP))
            x += im.width + GAP
        y += h + GAP
    board.save(OUT / f"{name}.png", optimize=True)
    print(name, board.size)
