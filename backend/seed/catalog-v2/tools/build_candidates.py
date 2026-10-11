"""Stage 1: read raw source snapshots, normalise, classify, merge. No network."""
import csv, json, re, sys, os, hashlib, collections
from urllib.parse import quote
sys.path.insert(0, os.path.dirname(__file__))
from textlib import *
from taxonomy import GD_MAP, GD_EXCLUDED_REVIEW

S = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/src/'
REPO = '/Users/medamine/projects/grocery-app/'
OUT = '/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/out/'
os.makedirs(OUT, exist_ok=True)

recs, excluded = [], []   # excluded: dict(src,sid,name,brand,reason)
# --- round 3 inputs (all evidence-based; see round3 report)
VARIANT = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'variant_overrides.json')))
CF_DESC = {}
for _fn in ('cf_pages_desc.txt', 'cf_pages_desc2.txt'):
    for _l in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), _fn), encoding='utf8').read().splitlines():
        if '|' in _l:
            _k, _v = _l.split('|', 1)
            CF_DESC[_k] = _v

def cf_size(desc):
    """Pack size / sale basis from a Carrefour product page's description. -> ('weight', None) | ('size', size_dict) | (None, None)"""
    d = desc or ''
    low = fold(d)
    if re.match(r'^(au poids|au kg|vendue au poids|vendu au poids)', low):
        return 'weight', None
    t = re.sub(r'\s*(?:\+|dont)\s*\d+\s*(?:g|kg|ml|cl|l)\s*gratuit.*$', '', d, flags=re.I)
    t = re.sub(r'\s*-\s*\d+\s*%.*$', '', t)
    m = re.search(r'(\d+)\s+[a-zà-ÿ]+(?:\s+[a-zà-ÿ]+)?\s+de\s+(\d+(?:[.,]\d+)?)\s*(kg|gr|g|ml|cl|l)\b', t, re.I)
    if m:
        u = 'g' if m.group(3).lower() == 'gr' else m.group(3)
        return 'size', parse_size(f"{m.group(1)}x{m.group(2)}{u}")
    m = re.search(r'(?:lot de|les)\s+(\d+)\s+(?:de\s+)?(\d+(?:[.,]\d+)?)\s*(kg|gr|g|ml|cl|l)\b', t, re.I)
    if m:
        u = 'g' if m.group(3).lower() == 'gr' else m.group(3)
        return 'size', parse_size(f"{m.group(1)}x{m.group(2)}{u}")
    m = re.search(r'(\d+)\s*[œo]e?ufs', t, re.I)
    if m:
        return 'size', parse_size(f"{m.group(1)} pièces")
    s = parse_size(t.replace('gr', 'g') if re.search(r'\d\s*gr\b', t, re.I) else t)
    if s:
        return 'size', s
    m = re.search(r'(\d+)\s*(pi[eè]ces|cr[eè]pes|portions|tranches|sachets)', t, re.I)
    if m:
        return 'size', parse_size(f"{m.group(1)} {m.group(2)}")
    return None, None
PORK_UNKNOWN = {'89168': 'Chorizo (Mliha)', '35958': 'Chorizo 200 g (Mliha)', '139025': 'Salami pepperoni 250 g (Chahia)', '33442': 'Salami pepperoni 250 g (El Mazraa)'}
VARIANT_EXCLUDE = {('geant', '72952')}

def exclude(src, sid, name, brand, reason, **kw):
    excluded.append(dict(source=src, sourceId=sid, name=name, brand=brand, reason=reason, **kw))

# --------------------------------------------------------------- category guess by keywords
RULES = [
 ('produits-traditionnels', r'^(?:chamia|helva|halwa|bsissa|zrir|assida|mesfouf)\b'),
 ('charcuterie-traiteur', r'\b(salami|jambon|saucisson|saucisses?|mortadelle|regaline|pastrami|bacon|lardons?|chorizo|terrine|foie gras|rillettes?|charcuterie|kebab|chawarma|chakchouka|mechouia|tastira|sandwich|pizza (?:fraiche|pret)|plat cuisine|brik|salade (?:tunisienne|cesar))\b'),
 ('surgeles', r'(surgel|congel|\bpane(?:e|s|es)?\b|nuggets|\bglace\b|\bglaces\b|cornet|sorbet|esquimau|\bbuche glacee)'),
 ('poissons-fruits-de-mer', r'\b(poissons?|saumon|thon frais|sardines? fraiche|maquereau|merlan|mulet|daurade|dorade|loup|crevettes?|chevrettes?|calamars?|seiches?|moules?|poulpe|crabe|langoustes?|merou|rouget|sole|crustaces?|coquillages?|fruits de mer|boutargue|gambas|saurel|thonine|anchois frais|pageot|denti|bar\b|espadon|requin|sepia)'),
 ('volaille', r'\b(poulet|poulets|dinde|dindonneau|volaille|chicken|pilons?|ailes? de|cuisses?|blanc de|escalopes? de (?:poulet|dinde)|canard|lapin|pintade|coq|poule|haut de cuisse|habra)\b'),
 ('viandes', r'\b(boeuf|veau|agneau|mouton|merguez|viande|hachee?|steaks?|cotelettes?|jarrets?|kefta|brochettes?|gigot|entrecote|bavette|rosbif|osso|tete d\'agneau|foie|cervelle|escalope de veau|cote)\b'),
 ('fromages', r'\b(fromages?|mozzarella|mascarpone|ricotta|gouda|edam|emmental|cheddar|camembert|brie|feta|parmesan|gruyere|roquefort|chevre|boursin|kiri|vache qui rit|cream cheese|triangle|portions|slice)\b'),
 ('produits-laitiers', r'\b(lait|laits|yaourts?|yogourts?|yoghourt|leben|raieb|kefir|beurre|creme fraiche|creme dessert|cremes? dessert|flan|dessert lacte|liegeois|oeufs?|oeuf|margarine|matiere grasse|fromage blanc|petit suisse|activia|danette|boisson lactee|specialite laitiere|creme liquide|creme de cuisson|creme sucree|creme fouettee)\b'),
 ('boulangerie', r'\b(pain|pains|baguette|croissant|viennoiserie|brioche|pain de mie|tabouna|tabouna|pain burger|pains? (?:complet|aux|au)|chausson|mini pain|tortilla|pita|pain grille|pizza)\b'),
 ('boissons', r'\b(boisson|boissons|jus|nectar|eau|eaux|soda|cola|limonade|citronnade|sirop|ice tea|\bthe\b(?! box)|infusion|tisane|cafe|chicoree|energisant|energetique|biere sans alcool|malt|sparkling|punch|orangina|fanta|sprite|schweppes|pepsi|coca|boga|celtia sans)\b'),
 ('biscuits-gateaux', r'\b(biscuits?|gaufrettes?|cookies?|cakes?|madeleines?|muffins?|brownies?|donuts?|tartelettes?|croustina|gateau|gateaux|sables?|boudoir|cigare|langue de chat|barre|barres|petit beurre|crostatini|blondiz|wafer|biscotti|bachkoutou|makroud|baklawa|patisserie)\b'),
 ('chocolat-confiserie', r'\b(chocolat|chocolats|bonbons?|chewing|bubble|sucettes?|dragees?|caramels?|nougat|loukoum|halva|halwa|chamia|bsissa|zrir|confiserie|praline|guimauve|tablette|pate d\'amande|cacahuetes? enrobee)\b'),
 ('snacks-aperitif', r'\b(chips|pop corn|popcorn|snack|snacks|takis|cacahuetes?|crackers?|aperitif|mais souffle|pretzel|biscuits? sales?)\b'),
 ('petit-dejeuner', r'\b(cereales?|corn flakes|muesli|granola|confitures?|miel|pate a tartiner|creme a tartiner|biscottes?|nutella|chocolat instantane|chocolat en poudre|cacao en poudre|poudre instantanee|tartiner|compote)\b'),
 ('legumes', r'\b(legumes?|salade|laitue|persil|menthe|coriandre|tomates?|oignons?|carottes?|courgettes?|poivrons?|concombres?|pommes? de terre|aubergines?|piments?|ail|champignons? frais|haricots verts frais|choux?|navet|radis|betterave|epinards?|celeri|blette|fenouil|artichaut|petits? pois frais)\b'),
 ('fruits', r'\b(fruits?|pommes?|bananes?|oranges?|citrons?|fraises?|raisins?|poires?|peches?|abricots?|melons?|pasteque|kiwi|ananas|mangues?|avocats?|clementines?|mandarines?|grenades?|figues?|cerises?|prunes?|nectarines?)\b'),
 ('epicerie', r'.'),
]
_P = {c: pat for c, pat in RULES if c in ('charcuterie-traiteur','poissons-fruits-de-mer','volaille','viandes')}
def guess_category(text):
    t = fold(text)
    for cat, pat in RULES:
        if re.search(pat, t):
            return cat
    return 'epicerie'

def meat_family_fix(cat, text):
    """Géant/Carrefour put charcuterie, frozen and mixed items under meat sub-categories; split by the product name."""
    if cat not in ('viandes', 'volaille', 'poissons-fruits-de-mer', 'charcuterie-traiteur', 'surgeles'):
        return cat
    t = fold(text)
    if re.search(_P['charcuterie-traiteur'], t):
        return 'charcuterie-traiteur'
    if re.search(r'surgel|congel|\bpane(?:e|s|es)?\b|nuggets|cordon bleu|\bsur\.\.\.|\bsurg', t):
        return 'surgeles'
    if re.search(_P['poissons-fruits-de-mer'], t):
        return 'poissons-fruits-de-mer'
    if re.search(_P['volaille'], t):
        return 'volaille'
    if re.search(_P['viandes'], t):
        return 'viandes'
    return cat

def is_alcohol(text):
    return bool(re.search(r'\b(vin|vins|biere|bieres|whisky|vodka|rhum|gin|champagne|cidre alcool|liqueur|boukha|alcool|spiritueux|apero|pastis|cognac|legmi|rose|rouge|blanc de blancs)\b', fold(text))) and not re.search(r'sans alcool|0\s?%', fold(text))

NONFOOD = r'\b(shampooing|savon|dentifrice|deodorant|lessive|javel|detergent|vaisselle|couche|serviettes? hygien|lingettes?|mascara|parfum|eau de toilette|eau de cologne|rasoir|brosse|papier|aluminium|plastique|poele|casserole|cartouche|pile|cable|smartphone|ordinateur|gel douche|creme (?:de jour|de nuit|solaire|anti)|maquillage|vernis|coton|insecticide|desodorisant|filtre|ustensile)\b'

# --------------------------------------------------------------- GÉANT DRIVE
gd_full = json.load(open(S + 'gd_full.json')) if os.path.exists(S + 'gd_full.json') else {}
COND = re.compile(r'condition+n?[ée]*\s*par\s*(\d+(?:[.,]\d+)?)\s*(kg|g|gr)\b', re.I)
LEKG = re.compile(r'(?<![a-z])(?:le|au|/)\s*kg\b|\bprix au kilo|\bvendu au kg', re.I)
LEPIECE = re.compile(r"\b(?:la pi[eè]ce|l'unit[eé]|la botte|le sachet|la barquette|la bo[iî]te|le bouquet|le pot)\b", re.I)

def gd_unit(desc, cat):
    """-> ('kg', min_g) | ('piece', None) | (None, None)"""
    m = COND.search(desc)
    if m:
        n = _num(m.group(1)) * (1000 if m.group(2).lower() == 'kg' else 1)
        return 'kg', int(n)
    if LEKG.search(desc):
        return 'kg', None
    if LEPIECE.search(desc):
        return 'piece', None
    return None, None

def _num(s):
    return float(s.replace(',', '.'))

n_trunc_unresolved = 0
for r in json.load(open(S + 'gd_raw.json')):
    mm = re.search(r'/tunis-city/([^/]+)/', r['url'] or '')
    sub = mm.group(1) if mm else '?'
    if sub not in GD_MAP:
        continue   # non-food / out of scope sub-category: not individually listed (counted in the report)
    sid = r['sourceId']
    full = gd_full.get(sid, {})
    name = (full.get('name') or r['name'] or '').strip()
    desc = (full.get('desc') if full.get('desc') is not None else r['desc'] or '').strip()
    if name.endswith('...') or name.endswith('…'):
        exclude('geant', sid, r['name'], r['brand'], 'name truncated in listing and product page could not be read', url=r['url']); continue
    brand = r['brand'].strip()
    if sid in PORK_UNKNOWN:
        exclude('geant', sid, name, brand, 'pork-family charcuterie whose species (pork vs beef/turkey) cannot be established from the source', url=r['url']); continue
    cat = meat_family_fix(GD_MAP[sub], name + ' ' + (mm.group(0) if mm else '') + ' ' + (r['url'] or ''))
    if re.search(NONFOOD, fold(name)) and not re.search(r'\b(cafe|the)\b', fold(name)):
        exclude('geant', sid, name, brand, 'non-food item inside a food sub-category'); continue
    if is_alcohol(name + ' ' + desc) and cat == 'boissons':
        exclude('geant', sid, name, brand, 'alcoholic beverage (out of scope)'); continue
    if re.search(r'\b(lot de|sur 2[eè]me|gratuit|gratuits|offre|promo)\b', fold(name + ' ' + desc)) or re.match(r'^\s*lot\b', fold(name)):
        exclude('geant', sid, name, brand, 'promotional bundle or offer text in the product record', desc=desc); continue
    kind, minq = gd_unit(desc, cat)
    d2 = COND.sub(' ', desc); d2 = LEKG.sub(' ', d2); d2 = LEPIECE.sub(' ', d2)
    size = None if kind else parse_size(d2)
    if size:
        d2 = strip_span(d2, size['span'])
    d2 = re.sub(r'\.{2,}|…', '', d2)
    d2 = re.sub(r'^\s*(?:de|-)\s*', '', d2)
    qual = clean_ws(d2)
    ov = VARIANT.get('geant:' + sid)
    if ov:
        qual = ov['qual']
        if ov.get('core'):
            name = ov['core']
    if ('geant', sid) in VARIANT_EXCLUDE:
        continue
    # 'Moyen modèle' etc. kept as qualifier; trailing pack info like '- 4 Tranches' already parsed.
    recs.append(dict(src='geant', sid=sid, srcName=r['name'], srcFullName=name, srcBrand=brand, srcDesc=desc,
                     srcCat=sub, catGuess=cat, url=r['url'], image=r['image'], price=r['price'],
                     core=name, qual=qual, size=size, loose=kind, looseMin=minq))

# --------------------------------------------------------------- AZIZA
AZ_CAT_FIX = {}
for i, line in enumerate(open(S + 'aziza_raw_food.tsv', encoding='utf8').read().splitlines()[1:]):
    title, brand, qty, imgid, price = (line.split('\t') + [''] * 5)[:5]
    sid = imgid
    t = title
    mult = None
    mg = re.match(r'^(?:Lot|Groupage) de (\d+)\s+(.*)$', t)
    if mg:
        mult, t = int(mg.group(1)), mg.group(2)
    elif re.match(r'^Groupage\s+(.*)$', t):
        t = re.match(r'^Groupage\s+(.*)$', t).group(1)
    q = qty.replace('GRT', '').replace('+ 30 G', '').strip()
    size = parse_size(q)
    qual_extra = ''
    if size is None and q:
        qual_extra = q.lower()
    if size and mult and size['count'] == 1 and mg:
        pass
    if mult and size and size['count'] == 1 and size['kind'] in ('g', 'ml') and re.match(r'^Groupage', title):
        # 'Groupage de 4 brownies | 200 G' = a pack of 4 weighing 200 g in total
        t = f"{t} (×{mult})"
    if re.search(r'(?:drôo|ptichat|hrouss)', fold(title)) or re.search(r'drôo|ptichat|hrouss', title.lower()):
        exclude('aziza', sid, title, brand, 'name cannot be verified or classified from the source alone'); continue
    cat = guess_category(t)
    cat = meat_family_fix(cat, t)
    recs.append(dict(src='aziza', sid=sid, srcName=title, srcFullName=title, srcBrand=brand, srcDesc=qty, srcCat='weekly-promo',
                     catGuess=cat, url='https://www.aziza.tn/', image=f'https://btoc.azizacdn.com/images/{imgid}.jpg', price=price,
                     core=t, qual=qual_extra, size=size, loose=None, looseMin=None))

# mixed assortments and non-food rows deliberately left out of the TSV (documented):
for title, brand, why in [
    ('Lot de 3 double concentré de tomate + harissa', 'ZINA', 'promotional bundle of different products'),
    ('Lot de 2 barquettes de glace aux différents parfums', 'ESKIMO', 'promotional bundle of assorted flavours'),
]:
    exclude('aziza', '', title, brand, why)

# --------------------------------------------------------------- MG
MG = {  # sourceId -> (name, size text or None, category, brand)   hand-normalised from the 57 crawled rows; every food row listed
 '271': ('Ail en poudre', '70 g', 'epicerie', "MG J'aime"), '273': ('Romarin en sachet', '20 g', 'epicerie', 'Koll Youm'),
 '280': ("Thon entier à l'huile d'olive", '700 g', 'epicerie', "MG J'aime"), '284': ('Chamia aux amandes', '350 g', 'produits-traditionnels', 'Koll Youm'),
 '285': ('Pâte à tartiner aux noisettes', '1 kg', 'produits-traditionnels', 'Koll Youm'), '282': ('Chips', '65 g', 'snacks-aperitif', "MG J'aime"),
 '302': ('Miel', '250 g', 'petit-dejeuner', "MG J'aime"), '303': ("Confiture de coing et d'abricot", None, 'petit-dejeuner', "MG J'aime"),
 '304': ('Biscotte nature', '280 g', 'petit-dejeuner', "MG J'aime"), '311': ('Fromage fondu', '24 portions', 'fromages', "MG J'aime"),
 '312': ('Chicorée café soluble', '50 g', 'boissons', "MG J'aime"), '313': ('Beurre de cacahuètes au miel', '190 g', 'petit-dejeuner', "MG J'aime"),
 '314': ('Granola en pot', '180 g', 'petit-dejeuner', "MG J'aime"), '316': ("Thon entier à l'huile végétale", '160 g', 'epicerie', "MG J'aime"),
 '329': ('Chamia aux fruits secs', '350 g', 'produits-traditionnels', 'Koll Youm'), '330': ('Chicorée café soluble', '200 g', 'boissons', "MG J'aime"),
 '331': ('Pâte à tartiner aux noisettes et au cacao', '350 g', 'petit-dejeuner', "MG J'aime"), '336': ('Compote de pomme', '125 g', 'petit-dejeuner', "MG J'aime"),
 '337': ('Purée de 4 légumes jardinière', '125 g', 'epicerie', "MG J'aime"), '340': ('Confiture de fraise', '340 g', 'petit-dejeuner', "MG J'aime"),
 '341': ('Café soluble', '190 g', 'boissons', "MG J'aime"), '346': ('Café intense en capsules', '10 capsules', 'boissons', "MG J'aime"),
 '347': ("Thon entier à l'huile d'olive", '400 g', 'epicerie', "MG J'aime"), '348': ('Huile de friture', '3,8 L', 'epicerie', 'Koll Youm'),
 '349': ('Harissa', '380 g', 'epicerie', "MG J'aime"), '350': ('Petits pois 1/2', None, 'epicerie', "MG J'aime"),
 '363': ('Pâte feuilletée', '450 g', 'epicerie', "MG J'aime"), '371': ('Café chicorée soluble', '200 g', 'boissons', "MG J'aime"),
 '372': ('Pâte à tartiner aux noisettes', '500 g', 'produits-traditionnels', 'Koll Youm'), '390': ('Maïs doux naturel 1/2', None, 'epicerie', "MG J'aime"),
 '394': ('Miel au thym', '250 g', 'petit-dejeuner', "MG J'aime"), '416': ('Pâte brisée', '450 g', 'epicerie', "MG J'aime"),
 '421': ('Confiture allégée', None, 'petit-dejeuner', "MG J'aime"), '422': ('Chicorée café soluble', '50 g', 'boissons', "MG J'aime"),
 '423': ('Chamia aux amandes', '350 g', 'produits-traditionnels', 'Koll Youm'), '426': ('Biscotte au son', '280 g', 'petit-dejeuner', "MG J'aime"),
 '432': ('Granola en pot', '350 g', 'petit-dejeuner', "MG J'aime"), '433': ("Thon en morceaux à l'huile végétale", '1,7 kg', 'epicerie', 'Koll Youm'),
 '434': ('Champignons de Paris 1/2', None, 'epicerie', "MG J'aime"), '436': ('Sauce pizza', '400 g', 'epicerie', "MG J'aime"),
 '486': ('Céréales', '220 g', 'petit-dejeuner', "MG J'aime"), '485': ('Double concentré de tomates', '800 g', 'epicerie', "MG J'aime"),
}
mg_raw = {r['sourceId']: r for r in json.load(open(S + 'mg_raw.json'))}
for sid, r in mg_raw.items():
    if sid not in MG:
        exclude('mg', sid, r['name'], '', 'non-food merchandise (kitchenware, cleaning, hygiene, appliances)', url=r['url'])
        continue
    name, sz, cat, brand = MG[sid]
    recs.append(dict(src='mg', sid=sid, srcName=r['name'], srcFullName=r['name'], srcBrand=brand, srcDesc='', srcCat=r['sourceCategory'],
                     catGuess=cat, url=r['url'], image=quote(r['image'], safe=':/%'), price=r['price'], core=name, qual='',
                     size=parse_size(sz) if sz else None, loose=None, looseMin=None, privateLabel='MG'))

# --------------------------------------------------------------- CARREFOUR (CSV is the source; the earlier conversion only supplies sku->category)
old = json.load(open(REPO + 'backend/seed/carrefour/carrefour_grocergo_catalog.json'))
oldrep = json.load(open(REPO + 'backend/seed/carrefour/carrefour_grocergo_conversion_report.json'))
old_by_slug = {p['slug']: (c['slug'], p) for c in old['categories'] for p in c['products']}
OLDCAT = {'fruits': 'fruits', 'legumes': 'legumes', 'viandes-poissons': 'viandes', 'produits-laitiers': 'produits-laitiers',
          'boulangerie': 'boulangerie', 'boissons': 'boissons', 'fromages': 'fromages', 'charcuterie-traiteur': 'charcuterie-traiteur',
          'surgeles': 'surgeles', 'pates-riz-legumes-secs': 'epicerie', 'conserves': 'epicerie', 'thon-sardines': 'epicerie',
          'huiles': 'epicerie', 'sauces-condiments': 'epicerie', 'epices-olives': 'epicerie', 'fruits-secs': 'epicerie',
          'snacks-aperitif': 'snacks-aperitif', 'biscuits-gateaux': 'biscuits-gateaux', 'chocolat-confiserie': 'chocolat-confiserie',
          'petit-dejeuner': 'petit-dejeuner', 'cafe-the': 'boissons', 'sucre-farine': 'epicerie', 'epicerie': 'epicerie'}
for row in csv.DictReader(open(REPO + 'carrefour_food_500.csv', encoding='utf8')):
    sku = row['sku']
    slug = oldrep['skuToSlug'].get(sku)
    oc, op = old_by_slug.get(slug, (None, None))
    if re.search(r'carrefour', fold(row['brand'] + ' ' + row['name'])):
        exclude('carrefour', sku, row['name'], row['brand'], 'Carrefour-branded product (excluded by decision)', url=row['product_url']); continue
    cat = OLDCAT.get(oc, 'epicerie')
    cat = meat_family_fix(cat, row['name'])
    if cat == 'epicerie' and oc is None:
        cat = guess_category(row['name'])
    unit_kg = bool(op and op['defaultSaleUnit'] == 'KG')
    nm = row['name'].strip()
    size = parse_size(nm, last=True)
    cfd = CF_DESC.get(sku)
    cf_note = None
    if cfd is not None:
        cf_note = cfd
        kind_, s_ = cf_size(cfd)
        if kind_ == 'weight':
            unit_kg = True
            size = None
        elif kind_ == 'size':
            size = s_
    core = nm
    name_size = parse_size(nm, last=True)
    if name_size:
        core = clean_ws(strip_span(nm, name_size['span']))
    recs.append(dict(src='carrefour', sid=sku, srcName=row['name'], srcFullName=row['name'], srcBrand=row['brand'].strip(), srcDesc='',
                     srcCat=row['category'], catGuess=cat, url=row['product_url'], image=row['image_url'], price=None,
                     core=core, qual='', size=size, loose='kg' if (unit_kg and not size) else None, looseMin=None, oldSlug=slug, cfPageDesc=cf_note))

# --------------------------------------------------------------- OPEN FOOD FACTS (crowdsourced; only if it was reachable)
OFFMAP = [
 ('en:beverages', 'boissons'), ('en:waters', 'boissons'), ('en:dairies', 'produits-laitiers'), ('en:cheeses', 'fromages'),
 ('en:biscuits', 'biscuits-gateaux'), ('en:cakes', 'biscuits-gateaux'), ('en:chocolates', 'chocolat-confiserie'), ('en:confectioneries', 'chocolat-confiserie'),
 ('en:snacks', 'snacks-aperitif'), ('en:breakfasts', 'petit-dejeuner'), ('en:spreads', 'petit-dejeuner'), ('en:jams', 'petit-dejeuner'),
 ('en:honeys', 'petit-dejeuner'), ('en:frozen-foods', 'surgeles'), ('en:meats', 'viandes'), ('en:fishes', 'poissons-fruits-de-mer'),
 ('en:breads', 'boulangerie'), ('en:canned-foods', 'epicerie'), ('en:pastas', 'epicerie'), ('en:groceries', 'epicerie'), ('en:sauces', 'epicerie'),
 ('en:oils', 'epicerie'), ('en:cereals-and-potatoes', 'epicerie'), ('en:condiments', 'epicerie'), ('en:plant-based-foods', 'epicerie'),
]
OFF_FILES = [f for f in ('off_raw2.json', 'off_raw.json') if os.path.exists(S + f)]
off_rows = {}
for f in OFF_FILES:
    for p in json.load(open(S + f)):
        off_rows.setdefault(p.get('code'), p)
for code, p in off_rows.items():
    nm = (p.get('product_name_fr') or p.get('product_name') or '').strip()
    br = (p.get('brands') or '').split(',')[0].strip()
    q = (p.get('quantity') or '').strip()
    tags = p.get('categories_tags') or []
    if not nm or not br or not q or not p.get('image_front_url'):
        exclude('off', code, nm, br, 'Open Food Facts record incomplete (needs name, brand, quantity and a front photo)'); continue
    if p.get('lang') and p.get('lang') not in ('fr',) and not p.get('product_name_fr'):
        exclude('off', code, nm, br, 'no French product name', lang=p.get('lang')); continue
    if re.search(r'carrefour', fold(br + nm)):
        exclude('off', code, nm, br, 'Carrefour-branded product (excluded by decision)'); continue
    GENERIC_OK = {'raieb', 'raib', 'lben', 'leben', "l'ben", 'lait', 'beurre', 'ricotta', 'margarine', 'harissa', 'mayonnaise', 'croissant'}
    ntok = [t for t in toks(nm) if t not in STOP and not t.isdigit()]
    btok = set(toks(br))
    if (not ntok or set(ntok) <= btok or (len(ntok) < 2 and fold(nm) not in GENERIC_OK) or sum(c.isalpha() for c in nm) < 4):
        exclude('off', code, nm, br, 'product name not descriptive (brand or product-line name only)'); continue
    cat = next((c for tag, c in OFFMAP if tag in tags), None)
    size = parse_size(q) or parse_size(re.sub(r'^(\d+(?:[.,]\d+)?)$', r'\1 l', q) if re.match(r'^\d+([.,]\d+)?$', q) else '')
    if not size:
        exclude('off', code, nm, br, 'quantity not parseable', quantity=q); continue
    if cat is None:
        cat = guess_category(nm)
    cat = meat_family_fix(cat, nm)
    if is_alcohol(nm) and cat == 'boissons':
        exclude('off', code, nm, br, 'alcoholic beverage (out of scope)'); continue
    if re.search(NONFOOD, fold(nm)):
        exclude('off', code, nm, br, 'non-food'); continue
    if size['kind'] == 'ml' and cat in ('boulangerie', 'biscuits-gateaux', 'chocolat-confiserie', 'snacks-aperitif', 'fruits', 'legumes', 'viandes', 'volaille', 'fromages', 'charcuterie-traiteur'):
        exclude('off', code, nm, br, 'quantity unit inconsistent with the product type (data error)', quantity=q); continue
    recs.append(dict(src='off', sid=code, srcName=nm, srcFullName=nm, srcBrand=br, srcDesc=q, srcCat=','.join(tags[:3]), catGuess=cat,
                     url=f'https://world.openfoodfacts.org/product/{code}', image=p['image_front_url'], price=None,
                     core=nm, qual='', size=size, loose=None, looseMin=None))

json.dump(dict(recs=recs, excluded=excluded), open(OUT + 'stage1.json', 'w'), ensure_ascii=False)
print('records', len(recs), collections.Counter(r['src'] for r in recs))
print('excluded', len(excluded), collections.Counter((e['source'], e['reason'][:50]) for e in excluded).most_common(12))
