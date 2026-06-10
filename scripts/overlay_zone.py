#!/usr/bin/env python3
"""
Draw the current driveway zone (from garage-vision/workflow.json) onto an image,
scaled to that image's size exactly like the Scale_Zone block does at runtime.
Use it to check whether the zone lines up with the driveway on a real frame.

    python3 scripts/overlay_zone.py <frame.jpg> [out.png]
"""
import ast
import json
import re
import sys
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
WF = ROOT / "garage-vision" / "workflow.json"

if len(sys.argv) < 2:
    sys.exit("usage: overlay_zone.py <frame.jpg> [out.png]")
src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path("/tmp/zone_overlay.png")

code = next(b["code"]["run_function_code"]
            for b in json.loads(WF.read_text())["dynamic_blocks_definitions"]
            if b["manifest"]["block_type"] == "Scale_Zone")
ref_w = float(re.search(r"ref_w\s*,\s*ref_h\s*=\s*([\d.]+)", code).group(1))
ref_h = float(re.search(r"ref_w\s*,\s*ref_h\s*=\s*[\d.]+\s*,\s*([\d.]+)", code).group(1))
drawn = ast.literal_eval(re.search(r"drawn\s*=\s*(\[\[.*?\]\])", code).group(1))

img = Image.open(src).convert("RGBA")
w, h = img.size
poly = [(round(max(0.0, min(1.0, x / ref_w)) * (w - 1)),
         round(max(0.0, min(1.0, y / ref_h)) * (h - 1))) for x, y in drawn]

overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
d = ImageDraw.Draw(overlay)
d.polygon(poly, fill=(255, 40, 40, 90), outline=(255, 40, 40, 255), width=max(3, w // 250))
for px, py in poly:
    r = max(4, w // 180)
    d.ellipse([px - r, py - r, px + r, py + r], fill=(255, 220, 0, 255))

Image.alpha_composite(img, overlay).convert("RGB").save(out)
print(f"frame {w}x{h} (aspect {w/h:.3f})")
print(f"zone points: {poly}")
print(f"wrote {out}")
