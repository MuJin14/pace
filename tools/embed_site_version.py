"""Embed version data into index.html at deploy time.

Why: the page's version badge and APK size need real values, but the obvious
approaches both fail through Cloudflare on the site domain:
  * fetch('/api/v1/app/version') -> 404 (the Origin Rule that rewrites the
    origin port to 8443 does not cover /api)
  * fetch('version.json')        -> 404 (same story; the origin serves it, the
    edge does not)
Verified pattern: every path that requires an origin fetch 404s at the edge,
while already-cached static files (html/css/webp) serve fine.

So: no request at all. This rewrites the placeholder values in the HTML with
real numbers before upload. The page then renders correct data even offline.
"""
import io
import json
import os
import re
import sys

SITE = r'C:\Users\沐瑾\Desktop\project\campus-run-backend\site'
HTML = os.path.join(SITE, 'index.html')
VER = os.path.join(SITE, 'version.json')

if not os.path.exists(VER):
    print('no version.json - nothing to embed')
    sys.exit(0)

data = json.load(io.open(VER, encoding='utf-8'))
latest = data.get('latest') or ''
size_bytes = data.get('apkSizeBytes') or 0
size_mb = ('%.1f MB' % (size_bytes / 1048576)) if size_bytes else ''

if not latest:
    print('version.json has no latest - nothing to embed')
    sys.exit(0)

html = io.open(HTML, encoding='utf-8').read()
orig = html

# 1) version badges
html = re.sub(r'(<span id="ver">)[^<]*(</span>)', r'\g<1>' + latest + r'\g<2>', html)
html = re.sub(r'(<span id="ver2">)[^<]*(</span>)', r'\g<1>' + latest + r'\g<2>', html)

# 2) size labels
if size_mb:
    html = re.sub(r'(<span id="size">)[^<]*(</span>)', r'\g<1>' + size_mb + r'\g<2>', html)
    html = re.sub(r'(<span id="size2">)[^<]*(</span>)', r'\g<1>' + size_mb + r'\g<2>', html)

# 3) Runtime refresh of the version badge, pointed at the DOWNLOAD host.
#
# Why not rely on the baked-in value alone: it goes stale the moment a new APK
# is published, and the site is a Workers upload nobody wants to redo on every
# release. (Exactly what happened: the badge sat at 1.3.0 through the 1.4.1
# release.)
#
# Why fetch from dl.hibiscus.wiki instead of this host's /version.json: the page
# is served by Cloudflare Workers, which only has the uploaded files, and the
# site domain cannot reach the origin (its Origin Rule does not cover arbitrary
# paths). dl.hibiscus.wiki is the very host the download button already uses,
# and it is verified working.
#
# The baked-in values remain as the fallback, so the badge is never empty even
# if the fetch fails.
# The badge block carries an explicit id so it can be replaced precisely.
#
# ⚠️ This used to be `re.sub(r"<script>\n// 版本[^\x00]*?</script>", '', html)` --
# a regex that starts at a bare `<script>` and ends at the next `</script>`.
# It worked only while the badge script was the ONLY script in the page. The
# moment the page gained other plain `<script>` blocks (the hero track
# animation, the changelog fade-in), this pattern swallowed whichever one
# followed the `// 版本` marker -- silently deleting real page code on every
# deploy. Match on the id, never on surrounding markup.
BADGE_OPEN = '<script id="ver-badge">'
BADGE_BLOCK = re.compile(
    r'<script id="ver-badge">.*?</script>|<script>\s*// 版本[^\x00]*?</script>',
    re.S)
html = BADGE_BLOCK.sub('', html)
html = re.sub(
    r"fetch\('version\.json'\)",
    "fetch('https://dl.hibiscus.wiki:8443/version.json')",
    html)

if 'dl.hibiscus.wiki:8443/version.json' not in html:
    snippet = (
        '\n' + BADGE_OPEN + '\n'
        '// 版本徽章：静态值由部署时烘焙（兜底），再尝试从下载域拉最新值。\n'
        '// 拉取失败不影响页面 —— 静态值已经是正确的。\n'
        'fetch("https://dl.hibiscus.wiki:8443/version.json")\n'
        '  .then(function (r) { return r.json(); })\n'
        '  .then(function (d) {\n'
        '    if (!d || !d.latest) return;\n'
        '    ["ver", "ver2"].forEach(function (id) {\n'
        '      var el = document.getElementById(id);\n'
        '      if (el) el.textContent = d.latest;\n'
        '    });\n'
        '    if (d.apkSizeBytes) {\n'
        '      var mb = (d.apkSizeBytes / 1048576).toFixed(1) + " MB";\n'
        '      ["size", "size2"].forEach(function (id) {\n'
        '        var el = document.getElementById(id);\n'
        '        if (el) el.textContent = mb;\n'
        '      });\n'
        '    }\n'
        '  })\n'
        '  .catch(function () { /* keep the static value */ });\n'
        '</script>\n'
    )
    html = html.replace('</body>', snippet + '</body>', 1)

# 4) Cache-bust the assets.
#
# Cloudflare caches this HTML and the css/webp aggressively, and there is no
# API token to purge with. Giving every release distinct asset URLs means the
# edge fetches the new files on its own.
#
# Only versioned when the asset is NOT already versioned, so repeated runs do
# not stack `?v=1.3.0?v=1.3.0`.
def _bust(m):
    url = m.group(2)
    if '?v=' in url:
        url = url.split('?v=')[0]
    return '%s%s?v=%s%s' % (m.group(1), url, latest, m.group(3))

html = re.sub(r'(src=")((?:shots/|style\.)[^"]*)(")', _bust, html)
html = re.sub(r'(href=")(style\.css[^"]*)(")', _bust, html)

# 5) Guard: refuse to write a page that lost content.
#
# ⚠️ This is the lesson from a real incident. A previous version of this script
# replaced the badge block with the regex `<script>\n// 版本[^\x00]*?</script>`,
# which anchors on bare markup instead of an id. As soon as the page gained
# other plain `<script>` blocks (the hero track animation, the changelog
# fade-in), the pattern deleted one of THEM -- every deploy silently stripped
# real page code, and nothing anywhere reported a problem.
#
# So: assert the page still contains everything it must, and abort loudly if
# not. A deploy that refuses to run is infinitely better than one that quietly
# ships a broken page.
REQUIRED = [
    ('classList.add("js")', 'JS-available marker (progressive enhancement)'),
    ('track-dot', 'hero track decoration'),
    ('IntersectionObserver', 'changelog fade-in'),
    ('dl.hibiscus.wiki:8443/version.json', 'version badge fetch'),
]
missing = [(needle, why) for needle, why in REQUIRED if needle not in html]
if missing:
    raise SystemExit(
        '\nREFUSING TO WRITE: the page lost required content.\n' +
        ''.join('  missing %-38s (%s)\n' % (n, w) for n, w in missing) +
        'Fix the transform above; do not ship a page with missing scripts.'
    )

script_open = len(re.findall(r'<script[^>]*>', html))
script_close = len(re.findall(r'</script>', html))
if script_open != script_close:
    raise SystemExit(
        '\nREFUSING TO WRITE: <script> tags are unbalanced (%d open, %d close).'
        % (script_open, script_close)
    )

io.open(HTML, 'w', encoding='utf-8', newline='\n').write(html)

print('embedded v%s  %s' % (latest, size_mb))
print('  index.html: %d -> %d bytes' % (len(orig.encode('utf-8')), len(html.encode('utf-8'))))
for probe in [('ver">%s<' % latest), ('size">%s<' % size_mb if size_mb else '')]:
    if probe:
        print('  %-28s %s' % (probe, 'OK' if probe in html else 'MISSING'))
print('  runtime fetch removed:', 'fetch(' not in html)
print('  cache-busted assets :', html.count('?v=' + latest))
print('  content guard       : OK (%d scripts paired)' % script_close)
