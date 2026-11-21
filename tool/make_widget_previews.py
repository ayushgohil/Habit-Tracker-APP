"""Draws the previews shown in Android's widget picker.

Run from the repo root: python3 tool/make_widget_previews.py
Writes android_overlay/res/drawable-nodpi/ember_preview_*.png and the
per-widget provider files in android_overlay/res/xml.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

S = 4  # draw at 4x and shrink for smooth edges
W = 320
BG = (33, 27, 24, 255)
INK = (255, 107, 44, 255)
FAINT = (255, 107, 44, 70)
OUT = Path("android_overlay/res/drawable-nodpi")
XML = Path("android_overlay/res/xml")
OUT.mkdir(parents=True, exist_ok=True)


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size * S)
        except OSError:
            continue
    return ImageFont.load_default()


def canvas():
    img = Image.new("RGBA", (W * S, W * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((0, 0, W * S - 1, W * S - 1), radius=28 * S, fill=BG)
    return img, d


def px(v):
    return int(v * S)


def ring(d, cx, cy, r, width, share):
    box = (px(cx - r), px(cy - r), px(cx + r), px(cy + r))
    d.ellipse(box, outline=FAINT, width=px(width))
    d.arc(box, -90, -90 + 360 * share, fill=INK, width=px(width))


def centered(d, text, cx, cy, size, fill=INK):
    f = font(size)
    box = d.textbbox((0, 0), text, font=f)
    d.text((px(cx) - (box[2] - box[0]) / 2 - box[0], px(cy) - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill=fill)


def save(img, name):
    img.resize((W, W), Image.LANCZOS).save(OUT / f"ember_preview_{name}.png")


# streak
img, d = canvas()
centered(d, "12", 160, 140, 120)
centered(d, "DAYS STREAK", 160, 245, 22, (255, 107, 44, 190))
save(img, "streak")

# ring
img, d = canvas()
ring(d, 160, 140, 88, 20, 0.7)
d.ellipse((px(140), px(108), px(180), px(148)), fill=INK)
d.rectangle((px(148), px(144), px(172), px(176)), fill=INK)
centered(d, "7/10", 160, 270, 28, (255, 107, 44, 220))
save(img, "ring")

# week
img, d = canvas()
for i, h in enumerate([0.5, 0.8, 0.3, 1.0, 0.65, 0.9, 0.2]):
    x = 38 + i * 40
    top = 235 - 170 * h
    d.rounded_rectangle((px(x), px(top), px(x + 22), px(235)), radius=px(11), fill=INK)
    centered(d, "MTWTFSS"[i], x + 11, 270, 20, (255, 107, 44, 190))
save(img, "week")

# trend
img, d = canvas()
pts = [0.1, 0.1, 0.2, 0.15, 0.4, 0.35, 0.6, 0.5, 0.7, 0.55, 0.85, 0.8, 0.95]
xy = [(px(36 + i * (248 / (len(pts) - 1))), px(240 - 150 * v)) for i, v in enumerate(pts)]
d.line(xy, fill=INK, width=px(7), joint="curve")
d.ellipse((xy[-1][0] - px(10), xy[-1][1] - px(10), xy[-1][0] + px(10), xy[-1][1] + px(10)), fill=INK)
d.line((px(36), px(262), px(284), px(262)), fill=FAINT, width=px(2))
save(img, "trend")

# month
img, d = canvas()
for r in range(5):
    for c in range(7):
        x, y = 40 + c * 36, 66 + r * 40
        n = r * 7 + c
        if n < 17 and n % 5 != 3:
            d.ellipse((px(x - 11), px(y - 11), px(x + 11), px(y + 11)), fill=INK)
        elif n < 17:
            d.line((px(x - 7), px(y - 7), px(x + 7), px(y + 7)), fill=(255, 107, 44, 170), width=px(3))
            d.line((px(x + 7), px(y - 7), px(x - 7), px(y + 7)), fill=(255, 107, 44, 170), width=px(3))
        elif n == 17:
            d.ellipse((px(x - 10), px(y - 10), px(x + 10), px(y + 10)), outline=INK, width=px(3))
        else:
            d.ellipse((px(x - 11), px(y - 11), px(x + 11), px(y + 11)), fill=FAINT)
save(img, "month")

# grid
img, d = canvas()
for i, share in enumerate([1.0, 0.6, 0.3, 0.8, 0.0, 0.5]):
    cx, cy = 100 + (i % 2) * 120, 70 + (i // 2) * 88
    ring(d, cx, cy, 30, 8, share)
    d.ellipse((px(cx - 9), px(cy - 9), px(cx + 9), px(cy + 9)), fill=INK)
save(img, "grid")

# today's list (the older widget, wider)
img = Image.new("RGBA", (W * S, int(W * 0.6) * S), (0, 0, 0, 0))
d = ImageDraw.Draw(img, "RGBA")
d.rounded_rectangle((0, 0, W * S - 1, int(W * 0.6) * S - 1), radius=28 * S, fill=BG)
f = font(18)
d.text((px(22), px(16)), "EMBER", font=f, fill=INK)
d.text((px(22), px(40)), "2 of 4 done", font=font(26), fill=(246, 239, 234, 255))
for i, line in enumerate(["Read", "Workout  29/45 min", "Water  1500/2000"]):
    d.text((px(22), px(86 + i * 30)), "o  " + line, font=font(20), fill=(246, 239, 234, 255))
img.resize((W, int(W * 0.6)), Image.LANCZOS).save(OUT / "ember_preview_list.png")

# one provider file per widget so each gets its own preview
TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="110dp"
    android:minHeight="110dp"
    android:minResizeWidth="70dp"
    android:minResizeHeight="70dp"
    android:targetCellWidth="2"
    android:targetCellHeight="2"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/ember_card"
    android:previewImage="@drawable/ember_preview_{kind}"
    android:description="@string/ember_widget_{kind}"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:configure="__PACKAGE__.EmberWidgetConfigActivity"
    android:widgetFeatures="reconfigurable" />
"""
for kind in ("streak", "ring", "week", "trend", "month", "grid"):
    (XML / f"ember_{kind}_info.xml").write_text(TEMPLATE.format(kind=kind))
print("previews written")
