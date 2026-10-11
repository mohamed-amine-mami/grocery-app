"""Stage 3b: draw a stratified sample of chosen photos, download them, build numbered contact sheets for visual inspection."""
import json, random, os, sys, re, urllib.request, concurrent.futures as cf, collections
from PIL import Image, ImageDraw, ImageFont
S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
d = json.load(open(S + 'out/stage2.json'))
st = json.load(open(S + 'out/photo_status.json'))
random.seed(20261010)
os.makedirs(S + 'img', exist_ok=True); os.makedirs(S + 'out/sheets', exist_ok=True)

def first_valid(p):
    for m in p['members']:
        u = m.get('image')
        if u and st.get(u, {}).get('ok'):
            return m
    return None

cands = []
for p in d['products']:
    m = first_valid(p)
    if m:
        cands.append((p, m))
by_src = collections.defaultdict(list)
for p, m in cands:
    by_src[m['src']].append((p, m))
sample = []
def take(lst, n):
    return random.sample(lst, min(n, len(lst)))
sample += by_src['mg']                                  # every MG photo (the site is known to have mismatched images)
sample += [(p, m) for p, m in cands if p['existingSlug']]  # every photo that would land on an existing product
# Géant: stratified by category, at least 4 per category, ~110 total
geant = by_src['geant']; cats = collections.defaultdict(list)
for p, m in geant:
    cats[p['category']].append((p, m))
total = len(geant)
for c, lst in cats.items():
    sample += take(lst, max(4, round(110 * len(lst) / total)))
sample += take(by_src['aziza'], 40)
sample += take(by_src['carrefour'], 45)
sample += take(by_src['off'], 20)
seen, uniq = set(), []
for p, m in sample:
    if m['image'] not in seen:
        seen.add(m['image']); uniq.append((p, m))
print('sample size', len(uniq), collections.Counter(m['src'] for p, m in uniq))

def dl(item):
    p, m = item
    fn = S + 'img/' + re.sub(r'[^a-z0-9]+', '_', p['slug'])[:60] + '__' + m['src'] + '.img'
    if not os.path.exists(fn):
        req = urllib.request.Request(m['image'], headers={'User-Agent': 'Mozilla/5.0 (GrocerGo catalog research; visual check)'})
        try:
            open(fn, 'wb').write(urllib.request.urlopen(req, timeout=40).read())
        except Exception as e:
            return None
    return fn
with cf.ThreadPoolExecutor(8) as ex:
    files = list(ex.map(dl, uniq))

CW, CH, COLS, ROWS = 230, 250, 5, 4
try:
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 18)
except Exception:
    font = ImageFont.load_default()
manifest = []
n = 0
sheets = []
for i in range(0, len(uniq), COLS * ROWS):
    batch = list(zip(uniq[i:i + COLS * ROWS], files[i:i + COLS * ROWS]))
    sheet = Image.new('RGB', (COLS * CW, ROWS * CH), 'white')
    dr = ImageDraw.Draw(sheet)
    for k, ((p, m), fn) in enumerate(batch):
        n += 1
        x, y = (k % COLS) * CW, (k // COLS) * CH
        try:
            im = Image.open(fn).convert('RGB')
            im.thumbnail((CW - 10, CH - 40))
            sheet.paste(im, (x + 5 + (CW - 10 - im.width) // 2, y + 30 + (CH - 40 - im.height) // 2))
        except Exception as e:
            dr.text((x + 10, y + 100), 'UNREADABLE', fill='red', font=font)
        dr.rectangle([x, y, x + CW - 1, y + CH - 1], outline='#999')
        dr.text((x + 6, y + 4), f'#{n}', fill='black', font=font)
        manifest.append(dict(n=n, sheet=len(sheets) + 1, slug=p['slug'], name=p['name'], brand=p['brand'], source=m['src'], image=m['image'], file=fn))
    path = S + f'out/sheets/sheet_{len(sheets) + 1:02d}.jpg'
    sheet.save(path, quality=82)
    sheets.append(path)
json.dump(manifest, open(S + 'out/sample_manifest.json', 'w'), ensure_ascii=False, indent=1)
print('sheets', len(sheets))
