import re, unicodedata

def fold(s):
    s = unicodedata.normalize('NFKD', s or '')
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = s.replace('œ', 'oe').replace('Œ', 'oe').replace('æ', 'ae').replace('’', "'").replace('`', "'")
    return s.lower()

def toks(s):
    return re.findall(r"[a-z0-9]+", fold(s))

def slugify(s):
    return '-'.join(toks(s))

STOP = {'de','du','la','le','les','des','au','aux','a','et','en','d','l','un','une','pour','sans','avec','au','par','the'}

def name_key(s):
    return ' '.join(sorted(set(t for t in toks(s) if t not in STOP)))

SMALL = {'de','du','des','la','le','les','et','au','aux','a','en','pour','sans','avec','sur'}

def sentence_case(s):
    s = re.sub(r'\s+', ' ', s or '').strip()
    if not s:
        return s
    letters = [c for c in s if c.isalpha()]
    if letters and sum(c.isupper() for c in letters) / len(letters) > 0.6:
        s = s.lower()
    return s[0].upper() + s[1:]

def title_brand(s):
    s = re.sub(r'\s+', ' ', s or '').strip()
    out = []
    for i, w in enumerate(s.lower().split(' ')):
        if re.match(r"^[dl]'", w) and len(w) > 2:
            pre, rest = w[:2], w[2:]
            pre = pre.upper() if (i == 0 and pre[0] == 'l') else pre
            out.append(pre + rest[0].upper() + rest[1:])
        elif i > 0 and w in SMALL:
            out.append(w)
        else:
            out.append('-'.join(p[:1].upper() + p[1:] for p in w.split('-')))
    return ' '.join(out)

# ---- sizes ---------------------------------------------------------------
UNITS = {
    'kg': ('kg', 1000, 'g'), 'kilo': ('kg', 1000, 'g'), 'kilos': ('kg', 1000, 'g'),
    'g': ('g', 1, 'g'), 'gr': ('g', 1, 'g'), 'gramme': ('g', 1, 'g'), 'grammes': ('g', 1, 'g'),
    'ml': ('ml', 1, 'ml'), 'cl': ('cl', 10, 'ml'), 'l': ('L', 1000, 'ml'), 'litre': ('L', 1000, 'ml'), 'litres': ('L', 1000, 'ml'),
    'piece': ('pièces', 1, 'pc'), 'pieces': ('pièces', 1, 'pc'), 'pièce': ('pièces', 1, 'pc'), 'pièces': ('pièces', 1, 'pc'),
    'pcs': ('pièces', 1, 'pc'), 'pc': ('pièces', 1, 'pc'),
    'tranche': ('tranches', 1, 'pc'), 'tranches': ('tranches', 1, 'pc'), 'tr': ('tranches', 1, 'pc'),
    'portion': ('portions', 1, 'pc'), 'portions': ('portions', 1, 'pc'),
    'capsule': ('capsules', 1, 'pc'), 'capsules': ('capsules', 1, 'pc'), 'cap': ('capsules', 1, 'pc'), 'caps': ('capsules', 1, 'pc'),
    'sachet': ('sachets', 1, 'pc'), 'sachets': ('sachets', 1, 'pc'),
}
_U = r'(kg|kilos?|g|gr|grammes?|ml|cl|l|litres?|pi[eè]ces?|pcs|pc|tranches?|tr|portions?|capsules?|caps?|sachets?)'
SIZE_RE = re.compile(r'(?<![\w.,/])(?:(\d{1,3})\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*' + _U + r'(?![a-zà-ÿ])(?:\s*[x×]\s*(\d{1,3})(?!\d))?', re.I)

def _num(s):
    return float(s.replace(',', '.'))

def _fmt(n):
    if abs(n - round(n)) < 1e-9:
        return str(int(round(n)))
    return ('%g' % round(n, 3)).replace('.', ',')

def parse_size(text, last=False):
    """-> dict(display, key, span, count) or None. key = (kind, total base units)."""
    ms = list(SIZE_RE.finditer(text or ''))
    if not ms:
        return None
    m = ms[-1] if last else ms[0]
    c1, q, u, c2 = m.group(1), _num(m.group(2)), m.group(3).lower(), m.group(4)
    disp_u, factor, kind = UNITS[u]
    count = int(c1 or c2 or 1)
    # normalise display unit
    unit = disp_u
    if unit == 'g' and q >= 1000 and q % 1000 == 0:
        q, unit = q / 1000, 'kg'
    elif unit == 'ml' and q >= 1000 and q % 1000 == 0:
        q, unit = q / 1000, 'L'
    elif unit == 'cl' and q >= 100 and q % 100 == 0:
        q, unit = q / 100, 'L'
    elif unit == 'cl' and q >= 100:
        q, unit = q / 100, 'L'
    base = _num(m.group(2)) * factor
    if kind == 'pc':
        base = _num(m.group(2))
    total = base * count
    disp = f"{_fmt(q)} {unit}"
    if count > 1:
        disp = f"{count} × {disp}"
    return dict(display=disp, key=(kind, round(total, 3)), span=m.span(), count=count, unit=unit, qty=q, kind=kind)

def strip_span(text, span):
    return (text[:span[0]] + ' ' + text[span[1]:]).strip()

def clean_ws(s):
    return re.sub(r'\s+', ' ', (s or '').replace(' ', ' ')).strip(' -–/,;:.')
