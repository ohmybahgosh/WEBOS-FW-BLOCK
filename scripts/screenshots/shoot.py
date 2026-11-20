"""Screenshots of the TV app from demo.js, at the TV's 1920x1080.
   python3 scripts/screenshots/shoot.py   (after webos-app/build.sh --no-package)"""
import os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DIST = os.path.join(ROOT, 'webos-app', 'dist')
OUT = os.path.join(ROOT, 'assets', 'screenshots')
DEMO = open(os.path.join(ROOT, 'scripts', 'screenshots', 'demo.js')).read()
os.makedirs(OUT, exist_ok=True)

SHOTS = [
    ('tv-blocked', 'blocked', []),
    ('tv-open', 'open', []),
    ('tv-eth0', 'eth0', []),
    ('tv-eth0-off', 'eth0off', []),
    ('tv-eth0-all', 'eth0all', []),
    ('tv-activity', 'blocked', ['ArrowRight']),
    ('tv-layers', 'eth0', ['ArrowRight', 'ArrowDown', 'ArrowDown', 'Enter']),
    ('tv-caught', 'blocked', ['ArrowRight', 'ArrowDown', 'Enter']),
    ('tv-confirm', 'eth0', ['Enter']),
    ('tv-more', 'blocked', ['ArrowRight', 'ArrowRight']),
    ('tv-backups', 'blocked', ['ArrowRight', 'ArrowRight', 'ArrowDown', 'Enter', 'ArrowDown']),
]
with sync_playwright() as p:
    b = p.chromium.launch()
    errors = []
    for name, tv, keys in SHOTS:
        pg = b.new_page(viewport={'width': 1920, 'height': 1080})
        pg.on('pageerror', lambda e: errors.append(str(e)))
        pg.add_init_script(DEMO)
        pg.goto('file://' + DIST + '/index.html?tv=' + tv)
        pg.wait_for_timeout(400)
        for k in keys:
            pg.keyboard.press(k)
            pg.wait_for_timeout(250)
        pg.screenshot(path=os.path.join(OUT, name + '.png'))
        pg.close()
    b.close()
if errors:
    print('page errors:', errors); sys.exit(1)
print('ok')
