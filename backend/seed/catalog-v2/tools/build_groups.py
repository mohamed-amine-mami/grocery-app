"""Stage 2: brand canonicalisation, naming, exact-duplicate merge, identity (existing slugs), slugs, units. No network."""
import json, re, sys, os, collections, hashlib
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
from corrections import correct

S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
st = json.load(open(S + 'out/stage1.json'))
recs, excluded = st['recs'], st['excluded']
existing = json.load(open(S + 'src/existing_db_products.json'))
PRIORITY = {'geant': 0, 'aziza': 1, 'off': 2, 'carrefour': 3, 'mg': 4}

# ------------------------------------------------------------------ brands
def bkey(b):
    return ''.join(toks(b))
BRAND_KEY_ALIAS = {'delicedanone': 'delice', 'landor': 'landor', 'moulindor': 'moulindor', 'kollyoum': 'kollyoum', 'mgjaime': 'mgjaime', 'mgjaimeplus': 'mgjaime'}
BRAND_DISPLAY = {'delice': 'Délice', 'landor': "Land'Or", 'moulindor': "Moulin d'Or", 'cocacola': 'Coca-Cola', 'kollyoum': 'Koll Youm',
                 'mgjaime': "MG J'aime", 'lbm': 'LBM', 'sicam': 'Sicam', 'yab': 'YAB', 'oh': 'OH', 'tej': 'TEJ', 'sbc': 'SBC'}
# --- round 3: brand merges, each backed by pack-photo evidence (see brand-merges.json). Nothing else is merged.
BRAND_MERGES = [  # (source spellings, canonical display, evidence)
 (['Furkitta'], 'Furketta', 'Packs of both records print the same logo "Furketta" (harissa berbère / tradition 190 g appear under both spellings)'),
 (["Jardin d'Emma", "Jardins d'Emma"], "Les Jardins d'Emma", 'Cans of both records print "Les Jardins d\'Emma"'),
 (['Petit Paris'], 'Le Petit Paris', 'Cans and jars of the "Petit Paris" records print "Le Petit Paris"'),
 (['Frideal Olina'], 'Olina', 'Oil bottles of both records print the Olina logo; "Fridéal" is the product line on the label'),
 (['Lovego'], 'Lovege', 'Cartons of both records print "Lovege"'),
 (['Nablia'], 'Neblia', 'Cans of both records print "Neblia" (harissa / hrous)'),
 (['Raoua Chani'], 'Raoua', 'Can of "Raoua Chani" prints the Raoua logo with "Chani" as the flavour; the product name already says "chani"'),
 (['Reflet'], 'Reflets de Tunisie', 'Jars/bags of both records print "Reflets de Tunisie"'),
 (['Royaumes des Abeilles'], 'Royaume des Abeilles', 'Honey jars of both records carry identical label artwork (label text too small to read; spelling follows the majority form)'),
 (['Senietna'], 'Seniatna', 'Boxes of both records print "Seniatna"'),
 (['Tanit'], 'Tanit le Jardin', 'Cans of both records print "Tanit le Jardin"'),
 (['Tifanny', 'Tiffanny'], 'Tiffany', 'Bottles of both spellings print "Tiffany"'),
 (['Tijen Water'], 'Tijen', 'Bottles of both records carry the identical "tijen" label'),
 (['Al Jazia', 'El Jazia'], 'Aljazia', 'Tins of both records print the same "Aljazia" logo'),
 (['National Souani', 'Calife Souani', 'Vieux Calife Souani'], 'Souani', 'Packs print the SOUANI mark with the line name (National / Calife / Vieux Calife); the line is moved into the product name'),
]
SOUANI_LINE = {'nationalsouani': 'National', 'califesouani': 'Calife', 'vieuxcalifesouani': 'Vieux Calife'}
for _spell, _canon, _ev in BRAND_MERGES:
    for _s in _spell:
        BRAND_KEY_ALIAS[bkey(_s)] = bkey(_canon)
    BRAND_DISPLAY[bkey(_canon)] = _canon
raw_spell = collections.defaultdict(collections.Counter)
for r in recs:
    b = (r['srcBrand'] or '').strip()
    if b:
        k = BRAND_KEY_ALIAS.get(bkey(b), bkey(b))
        raw_spell[k][b] += 1
def display_for(k):
    if k in BRAND_DISPLAY:
        return BRAND_DISPLAY[k]
    spells = raw_spell[k]
    mixed = [s for s in spells if s != s.upper() and s != s.lower()]
    if mixed:
        return max(mixed, key=lambda s: spells[s])
    return title_brand(max(spells, key=lambda s: spells[s]))
BRANDS = {k: display_for(k) for k in raw_spell}
for r in recs:
    b = (r['srcBrand'] or '').strip()
    r['brandKey'] = BRAND_KEY_ALIAS.get(bkey(b), bkey(b)) if b else ''
    r['brand'] = BRANDS.get(r['brandKey']) if r['brandKey'] else None

# ------------------------------------------------------------------ names
def lower_first(q):
    return q if (len(q) > 1 and q[:2].isupper()) else (q[:1].lower() + q[1:] if q else q)

def make_name(r):
    core = sentence_case(clean_ws(re.sub(r'\.{2,}|…', '', r['core'])))
    # remove an appended brand (MG sources append it to the title)
    qual = clean_ws(r['qual'] or '')
    size2 = None
    if qual:
        s2 = parse_size(qual)
        if s2:
            size2 = s2
            qual = clean_ws(strip_span(qual, s2['span']))
    qual = lower_first(clean_ws(qual))
    parts = [core]
    if qual and (set(toks(qual)) - set(toks(core))):
        parts.append(qual)
    if r['size']:
        parts.append(r['size']['display'])
    if size2 and not (r['size'] and r['size']['key'] == size2['key']):
        parts.append(size2['display'])
    name = clean_ws(' '.join(parts))
    r['size2'] = size2
    return name

for r in recs:
    _raw = bkey((r['srcBrand'] or '').strip()) if (r['srcBrand'] or '').strip() else ''
    if _raw in SOUANI_LINE:
        r['core'] = r['core'] + ' ' + SOUANI_LINE[_raw]
    r['name'] = make_name(r)
    keys = [r['size']['key']] if r['size'] else []
    if r.get('size2'):
        keys.append(r['size2']['key'])
    r['sizeKey'] = json.dumps(keys)
    r['nameKey'] = name_key(re.sub(r'\b\d+(?:[.,]\d+)?\s*(?:kg|g|gr|ml|cl|l|pi[eè]ces?|tranches?|portions?|capsules?)\b', ' ', r['core'] + ' ' + (r['qual'] or ''), flags=re.I))
    r['groupKey'] = '|'.join([r['brandKey'], r['sizeKey'], r['nameKey'], 'kg' if r.get('loose') == 'kg' else ''])

# ------------------------------------------------------------------ groups (exact duplicates only)
groups = collections.OrderedDict()
same_source_collisions = []
for r in sorted(recs, key=lambda r: (PRIORITY[r['src']], r['sid'])):
    g = groups.get(r['groupKey'])
    if g is None:
        groups[r['groupKey']] = dict(key=r['groupKey'], members=[r])
        continue
    if any(m['src'] == r['src'] for m in g['members']):
        # same source, same brand+size+name, different record id -> not provably the same product: first kept, others listed
        same_source_collisions.append(r)
        continue
    g['members'].append(r)

# ------------------------------------------------------------------ units / quantity rules
KG_DEFAULT = {  # (min, step, max) in grams, restated explicitly for every KG product
 'fruits': (500, 100, 10000), 'legumes': (500, 100, 10000),
 'viandes': (500, 100, 5000), 'volaille': (500, 100, 5000), 'poissons-fruits-de-mer': (500, 100, 5000),
 'fromages': (100, 50, 2000), 'charcuterie-traiteur': (100, 50, 2000), 'epicerie': (250, 50, 5000),
}
KG_FALLBACK = (500, 100, 5000)
def kg_rule(cat, minq):
    mn, st_, mx = KG_DEFAULT.get(cat, KG_FALLBACK)
    if minq:
        mn = minq
        st_ = 100 if (minq >= 500 and minq % 100 == 0) else 50 if minq % 50 == 0 else 10
        if mx < mn:
            mx = max(mn * 10, mn)
        mx = mx - (mx % st_)
    return mn, st_, mx

def best(g, field):
    for m in g['members']:
        if m.get(field):
            return m[field]
    return None

ex_by_key = {}
for e in existing:
    k = name_key(re.sub(r'\([^)]*\)', ' ', e['name']))
    ex_by_key.setdefault(k, e)
EX_SLUGS = {e['slug'] for e in existing}

products, id_matches = [], []
for g in groups.values():
    ms = g['members']
    top = ms[0]
    cat = top['catGuess']
    for m in ms:   # prefer the supermarket's own category over keyword guesses
        if m['src'] in ('geant', 'aziza', 'mg'):
            cat = m['catGuess']; break
    kg_loose = any(m.get('loose') == 'kg' for m in ms) and not top['size']
    piece_loose = any(m.get('loose') == 'piece' for m in ms)
    minq = next((m['looseMin'] for m in ms if m.get('looseMin')), None)
    fixed = None
    if not (not top['brandKey'] and ex_by_key.get(top['nameKey'])):
        fixed = correct(top['name'], cat)
        if fixed:
            cat = fixed[0]
    p = dict(name=top['name'], correction=(fixed[1] if fixed else None), brand=top['brand'], brandKey=top['brandKey'], category=cat, members=ms,
             unit='KG' if kg_loose else 'PIECE', privateLabel=next((m['privateLabel'] for m in ms if m.get('privateLabel')), None),
             existingSlug=None)
    if kg_loose:
        p['min'], p['step'], p['max'] = kg_rule(cat, minq)
    else:
        p['min'], p['step'], p['max'] = 1, 1, 24
    # identity: brandless + same normalised name as one of the 42 existing products
    if not top['brandKey']:
        e = ex_by_key.get(top['nameKey'])
        if e and e['slug'] not in {x['existingSlug'] for x in products if x['existingSlug']}:
            p['existingSlug'] = e['slug']
            id_matches.append((e['slug'], top['name'], [m['src'] for m in ms],
                               'unit differs (existing kept): source says %s' % p['unit'] if e['defaultSaleUnit'] != p['unit'] else ''))
    products.append(p)

# ------------------------------------------------------------------ cross-source merge of descriptor-only differences
NEUTRAL = {'canette', 'naturelle', 'naturel', 'boisson', 'gazeuse', 'jus', 'gout', 'saveur', 'and', 'box', 'the', 'aromatise', 'aromatisee'}
def _sing(t):
    return t[:-1] if len(t) > 3 and t.endswith('s') and not t.endswith('ss') else t
def _lev1(a, b):
    if a == b: return True
    if len(a) < 4 or abs(len(a) - len(b)) > 1: return False
    i = 0
    while i < min(len(a), len(b)) and a[i] == b[i]: i += 1
    return a[i+1:] == b[i+1:] or a[i:] == b[i+1:] or a[i+1:] == b[i:]
def _core_tokens(name):
    stripped = re.sub(r'\b\d+(?:[.,]\d+)?\s*(?:kg|g|gr|ml|cl|l|pi[eè]ces?|tranches?|portions?|capsules?)\b|\d+\s*×', ' ', name, flags=re.I)
    return [_sing(t) for t in toks(stripped) if t not in STOP and t not in NEUTRAL]
def _same_tokens(a, b):
    if not a or not b or len(a) != len(b): return False
    return all(any(_lev1(x, y) for y in b) for x in a) and all(any(_lev1(y, x) for x in a) for y in b)
merged_pairs = []
buckets = collections.defaultdict(list)
for p_ in products:
    if p_['brandKey'] and p_['members'][0]['sizeKey'] != '[]' and not p_['existingSlug']:
        buckets[(p_['brandKey'], p_['members'][0]['sizeKey'])].append(p_)
drop = set()
for key_, ps_ in buckets.items():
    ps_.sort(key=lambda q: min(PRIORITY[m['src']] for m in q['members']))
    for i in range(len(ps_)):
        a = ps_[i]
        if id(a) in drop: continue
        for j in range(i + 1, len(ps_)):
            b = ps_[j]
            if id(b) in drop: continue
            if {m['src'] for m in a['members']} & {m['src'] for m in b['members']}: continue
            if a['category'] != b['category'] and not {a['category'], b['category']} <= {'boissons', 'produits-laitiers'}:
                continue
            if _same_tokens(_core_tokens(a['name']), _core_tokens(b['name'])):
                a['members'] += b['members']
                merged_pairs.append((a['name'], b['name'], a['brand'], [m['src'] for m in a['members']]))
                drop.add(id(b))
products = [q for q in products if id(q) not in drop]

# ------------------------------------------------------------------ pack-photo-verified merges (reviewed pair by pair, see pair-merges.json)
PAIR_MERGES = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pair_merges.json')))
_by_member = {}
for p_ in products:
    for m_ in p_['members']:
        _by_member[f"{m_['src']}:{m_['sid']}"] = p_
pair_applied = []
_dropped = set()
for pm in PAIR_MERGES:
    a = _by_member.get(pm['a'][0]); b = _by_member.get(pm['b'][0])
    if a is None or b is None or a is b or id(a) in _dropped or id(b) in _dropped:
        continue
    a['members'] += b['members']
    if pm.get('keepName'):
        a['name'] = pm['keepName']
    for m_ in b['members']:
        _by_member[f"{m_['src']}:{m_['sid']}"] = a
    _dropped.add(id(b))
    pair_applied.append(dict(kept=a['name'], mergedAway=pm['bName'], brand=pm['brand'], evidence=pm['evidence'], sources=sorted({m['src'] for m in a['members']})))
products = [q for q in products if id(q) not in _dropped]

# ------------------------------------------------------------------ Carrefour size-less records: individual decisions
CF_IDS = set(json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cf_sel.json'))))
def _jac(a, b):
    a, b = set(a), set(b)
    return len(a & b) / len(a | b) if a | b else 0
sized_by_brand = collections.defaultdict(list)
for p_ in products:
    if p_['brandKey'] and p_['members'][0]['sizeKey'] != '[]':
        sized_by_brand[p_['brandKey']].append(p_)
cf_decisions = []
ambiguous_drop = set()
for p_ in products:
    only_cf = all(m['src'] == 'carrefour' for m in p_['members'])
    unsized = p_['members'][0]['sizeKey'] == '[]' and not any(m.get('loose') == 'kg' for m in p_['members'])
    if only_cf and unsized and p_['brandKey'] and not p_['existingSlug']:
        ct = _core_tokens(p_['name'])
        best = max(((_jac(ct, _core_tokens(q['name'])), q) for q in sized_by_brand.get(p_['brandKey'], [])), key=lambda t: t[0], default=(0, None))
        if best[1] is not None and best[0] >= 0.999:
            ambiguous_drop.add(id(p_))
            p_['cfDecision'] = ('excluded', f"no pack size on the product page and too similar ({best[0]:.2f}) to the sized product \"{best[1]['name']}\" [{'+'.join(sorted({m['src'] for m in best[1]['members']}))}] to be told apart")
for p_ in products:
    for m_ in p_['members']:
        if m_['src'] == 'carrefour' and m_['sid'] in CF_IDS:
            if id(p_) in ambiguous_drop:
                dec = p_['cfDecision']
            elif len({x['src'] for x in p_['members']}) > 1:
                others = [x for x in p_['members'] if x['src'] != 'carrefour']
                dec = ('merged', f"pack size from the product page ({m_.get('cfPageDesc')!r}) makes it an exact duplicate of {others[0]['src']} record \"{others[0]['srcFullName']}\"")
            elif any(x.get('loose') == 'kg' for x in p_['members']):
                dec = ('retained', f"page says {m_.get('cfPageDesc')!r}: sold by weight, a distinct loose product")
            elif m_['sizeKey'] != '[]':
                dec = ('retained', f"pack size from the product page ({m_.get('cfPageDesc')!r}); no sized sibling with identical wording")
            else:
                dec = ('retained', f"page gives no pack size ({m_.get('cfPageDesc')!r}) but no sized sibling is close enough to be a duplicate")
            cf_decisions.append(dict(sid=m_['sid'], name=m_['srcFullName'], brand=p_['brand'], pageDescription=m_.get('cfPageDesc'), decision=dec[0], reason=dec[1], url=m_['url']))
products = [q for q in products if id(q) not in ambiguous_drop]

# ------------------------------------------------------------------ final names, slugs
used_slugs = set(EX_SLUGS)
used_names = set()
def uniq(slug_base, ident):
    s = slug_base[:100].strip('-')
    if s not in used_slugs:
        return s
    n = 2
    while True:
        suffix = f'-{n}'
        c = (slug_base[:100 - len(suffix)].strip('-')) + suffix
        if c not in used_slugs:
            return c
        n += 1

name_collisions = []
final = []
for p in sorted(products, key=lambda p: (p['category'], fold(p['name']), p['members'][0]['sid'])):
    if p['existingSlug']:
        e = next(x for x in existing if x['slug'] == p['existingSlug'])
        p['slug'] = e['slug']
        used_names.add((fold(e['name']), None))
        final.append(p); continue
    nk = (fold(p['name']), p['brandKey'] or None)
    if nk in used_names or (nk[0], None) in {(fold(e['name']), None) for e in existing} and not p['brandKey']:
        name_collisions.append(p); continue
    used_names.add(nk)
    base = slugify(p['name'] + ('' if (p['brand'] and slugify(p['brand']) in slugify(p['name'])) or not p['brand'] else ' ' + p['brand']))
    if not base:
        name_collisions.append(p); continue
    p['slug'] = uniq(base, p['members'][0]['sid'])
    used_slugs.add(p['slug'])
    final.append(p)

# brand registry (only brands actually used)
used_brand_keys = sorted({p['brandKey'] for p in final if p['brandKey']})
brand_slugs = {}
for k in used_brand_keys:
    s = slugify(BRANDS[k]) or k
    base, n = s, 2
    while s in brand_slugs.values():
        s = f'{base}-{n}'; n += 1
    brand_slugs[k] = s

# ------------------------------------------------------------------ uncertain matches (not merged)
by_brand = collections.defaultdict(list)
for p in final:
    by_brand[p['brandKey']].append(p)
uncertain = []
for bk, ps in by_brand.items():
    if not bk:
        continue
    for i in range(len(ps)):
        a = ps[i]; ta = set(toks(a['name'])) - STOP
        for j in range(i + 1, len(ps)):
            b = ps[j]
            if a['members'][0]['src'] == b['members'][0]['src'] and not (
                    a['members'][0]['src'] == 'carrefour'):
                continue
            tb = set(toks(b['name'])) - STOP
            ska, skb = a['members'][0]['sizeKey'], b['members'][0]['sizeKey']
            if ska != '[]' and skb != '[]' and ska != skb:
                continue
            if not ta or not tb:
                continue
            jac = len(ta & tb) / len(ta | tb)
            sub = ta <= tb or tb <= ta
            if jac >= 0.6 or (sub and min(len(ta), len(tb)) >= 2):
                srcs = {m['src'] for m in a['members']} | {m['src'] for m in b['members']}
                if len(srcs) > 1 or ska == '[]' or skb == '[]':
                    uncertain.append(dict(brand=a['brand'], a=a['name'], aSlug=a['slug'], aSources=[m['src'] for m in a['members']],
                                          b=b['name'], bSlug=b['slug'], bSources=[m['src'] for m in b['members']],
                                          similarity=round(jac, 2), reason='same brand; ' + ('size unknown on one side' if ska == '[]' or skb == '[]' else 'same size, similar wording')))

# near-duplicate brand names
bk = list(used_brand_keys)
def lev(a, b):
    if abs(len(a) - len(b)) > 2: return 9
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]
brand_variants = []
for i in range(len(bk)):
    for j in range(i + 1, len(bk)):
        a, b = bk[i], bk[j]
        if (len(a) >= 5 and len(b) >= 5 and lev(a, b) <= 1) or (len(a) >= 5 and len(b) >= 5 and (a in b or b in a)):
            brand_variants.append((BRANDS[a], BRANDS[b]))

json.dump(dict(
    products=[dict(slug=p['slug'], name=p['name'], brand=p['brand'], brandKey=p['brandKey'], brandSlug=brand_slugs.get(p['brandKey']),
                   category=p['category'], unit=p['unit'], min=p['min'], step=p['step'], max=p['max'], existingSlug=p['existingSlug'],
                   privateLabel=p['privateLabel'],
                   correction=p.get('correction'), members=[{k: m.get(k) for k in ('src', 'sid', 'srcName', 'srcFullName', 'srcBrand', 'srcDesc', 'srcCat', 'url', 'image', 'price', 'catGuess', 'loose', 'looseMin', 'sizeKey', 'oldSlug')} for m in p['members']])
              for p in final],
    brands=[dict(key=k, name=BRANDS[k], slug=brand_slugs[k], spellings=dict(raw_spell[k])) for k in used_brand_keys],
    sameSourceCollisions=[{k: r.get(k) for k in ('src', 'sid', 'srcName', 'name', 'brand', 'srcDesc')} for r in same_source_collisions],
    nameCollisions=[dict(name=p['name'], brand=p['brand'], sources=[(m['src'], m['sid']) for m in p['members']]) for p in name_collisions],
    uncertain=uncertain, brandVariants=brand_variants, identityMatches=id_matches, descriptorMerges=merged_pairs, packPhotoMerges=pair_applied, cfDecisions=cf_decisions,
    brandMergeAudit=[dict(source=r['src'], sid=r['sid'], rawBrand=r['srcBrand'], canonical=r['brand'], line=SOUANI_LINE.get(bkey((r['srcBrand'] or '').strip()))) for r in recs if r['srcBrand'] and r['brandKey'] in {bkey(c) for _s, c, _e in BRAND_MERGES} and bkey(r['srcBrand'].strip()) != r['brandKey']],
    brandMerges=[dict(spellings=s, canonical=c, evidence=e) for s, c, e in BRAND_MERGES],
    excludedPre=excluded, dupGroupsMerged=sum(1 for g in groups.values() if len(g['members']) > 1),
), open(S + 'out/stage2.json', 'w'), ensure_ascii=False)
print('groups', len(groups), 'products', len(final), 'sameSourceCollisions', len(same_source_collisions), 'nameCollisions', len(name_collisions))
print('merged groups (multi-source)', sum(1 for g in groups.values() if len(g['members']) > 1), 'brands', len(used_brand_keys))
print('identity matches', len(id_matches)); [print('  ', m) for m in id_matches]
print('uncertain', len(uncertain), 'brandVariants', len(brand_variants))
print(collections.Counter(p['category'] for p in final))
print(collections.Counter(p['unit'] for p in final))
