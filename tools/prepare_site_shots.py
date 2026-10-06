"""Prepare website screenshots into campus-run-backend/site/shots/.

Sources (in priority order for each slot):
  1. a real device screenshot dropped into campus-run-backend/site/raw/
     (e.g. 首页.png — if present it wins, because real beats mockup)
  2. the design assets in campus-run-app/design/

Design assets are RGBA PNGs from a design tool; re-encoding them as RGB PNG
without the alpha channel cuts ~40% of the bytes for identical pixels.
The site is served over a phone connection, so that matters.
"""
import io
import os
import shutil

from PIL import Image

ROOT = r'C:\Users\沐瑾\Desktop\project'
BK = os.path.join(ROOT, 'campus-run-backend')
DESIGN = os.path.join(ROOT, 'campus-run-app', 'design')
OUT = os.path.join(BK, 'site', 'shots')
RAW = os.path.join(BK, 'site', 'raw')

os.makedirs(OUT, exist_ok=True)

# slot name -> (design asset, list of acceptable names in raw/)
SLOTS = {
    'home.png': ('home_loaded.png', ['首页.png', 'home.png', '首页.jpg']),
    'home-empty.png': ('home_empty.png', ['空态.png', 'home-empty.png']),
    'spec.png': ('home_spec.png', ['规格.png', 'spec.png']),
}


def pick(raw_names):
    """Prefer a real device screenshot if the user dropped one in raw/."""
    if not os.path.isdir(RAW):
        return None
    for n in raw_names:
        p = os.path.join(RAW, n)
        if os.path.isfile(p):
            return p
        # also match case-insensitively / with any extension
        stem = os.path.splitext(n)[0].lower()
        for f in os.listdir(RAW):
            if os.path.splitext(f)[0].lower() == stem:
                return os.path.join(RAW, f)
    return None


def optimize(src, dst, max_width=None):
    im = Image.open(src)
    if max_width and im.width > max_width:
        ratio = max_width / im.width
        im = im.resize((max_width, round(im.height * ratio)), Image.LANCZOS)
    # flatten alpha onto white: the site background is near-white, and
    # dropping the alpha channel saves a third of the file size
    if im.mode in ('RGBA', 'LA', 'P'):
        im = im.convert('RGBA')
        bg = Image.new('RGB', im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    elif im.mode != 'RGB':
        im = im.convert('RGB')
    im.save(dst, 'PNG', optimize=True)
    return im.size


print('screenshots ->', OUT)
print()
total = 0
for out_name, (design_name, raw_names) in SLOTS.items():
    src = pick(raw_names)
    origin = 'raw/ (真实截图)'
    if not src:
        src = os.path.join(DESIGN, design_name)
        origin = 'design/'
    if not os.path.isfile(src):
        print('  SKIP %-16s (not found: %s)' % (out_name, src))
        continue
    before = os.path.getsize(src)
    # the spec board is wide; cap it so the page stays light on mobile
    cap = 1000 if out_name == 'spec.png' else None
    size = optimize(src, os.path.join(OUT, out_name), max_width=cap)
    after = os.path.getsize(os.path.join(OUT, out_name))
    total += after
    print('  %-16s <- %-18s %sx%s  %dKB -> %dKB  (-%d%%)'
          % (out_name, origin, size[0], size[1],
             before // 1024, after // 1024,
             round(100 - after * 100 / before)))

print()
print('total shots size: %d KB' % (total // 1024))
for f in sorted(os.listdir(OUT)):
    print('   ', f)
