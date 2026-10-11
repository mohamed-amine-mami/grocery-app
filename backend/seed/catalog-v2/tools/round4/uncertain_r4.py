import json,collections
D='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'; W='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
st2=json.load(open(W+'out/stage2.json'))
old=json.load(open(D+'history/rev3/uncertain-matches.rev3.json'))['pairs']
cur={p['slug'] for k in json.load(open(D+'catalog.v2.json'))['categories'] for p in k['products']}
LD={2,9,10,26,41,44,45,46,49,50,73,74,75,84,86,89,108,109,112,114,115,117,121,132,134,142,150,158}
INS={5,6,7,8,14,16,17,18,25,28,29,30,31,32,33,34,35,42,43,51,52,54,55,56,57,58,59,60,67,68,76,77,78,79,85,87,88,92,96,110,111,116,118,119,120,123,126,127,129,130,131,141}
MERGE={2,9,10,26,41,44,73,75,84,86,108,112,117,121,142,150,158}
KEEP={
45:"Power Horse: the Carrefour can is the Manchester City 'official partner' edition; the Géant can is the standard design. Same drink, different packaging edition, so kept as two products.",
46:"Coca-Cola: the Carrefour picture is a promotional 'goût original – +25 cl gratuit' bottle; the Géant/OFF bottle is the standard 1.5 L. The promotion changes the pack content, so kept separate.",
49:"Brava chicorée 200 g: the Carrefour/Géant record shows a glass jar, the other Géant record shows a soft pouch. Different packaging, kept separate.",
50:"Brava chicorée 100 g: the Géant picture is a pouch, the OFF picture a glass jar. Different packaging, kept separate.",
74:"Natilait noisette: the Géant picture is the 'Montagne de Goût' layered dessert (another line), while Aziza's is a multi-flavour 'mon Dessert' assortment that does not show noisette. The two cannot be shown to be the same product.",
89:"Kartago sesame pops: the Carrefour pack is a 50 g sachet, the Géant one a 250 g tub. Different size and packaging.",
109:"Président 8 portions: the Carrefour record is the rectangular 'Carré – frais & délicieux' block, the Géant record the round 'fromage fondu pour tartine' box. Different products.",
114:"Majesté edam: the Carrefour record is sold by weight (page says 'Au poids', KG), the Géant record is a packed 80 g wedge (PIECE). Different sale format.",
115:"Majesté gruyère râpé: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 100 g bag (PIECE).",
132:"Mont Regal râpé emmental: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 450 g bag (PIECE).",
134:"Mont Regal râpé mozzarella: Carrefour is sold by weight ('Au poids', KG); Géant is a packed 1 kg bag (PIECE)."}
by_slugs={(p['aSlug'],p['bSlug']):i for i,p in enumerate(old)}
new=[]; counts=collections.Counter()
renamed={}  # old slug -> new slug via changes-since-rev3
ch3=json.load(open(D+'changes-since-rev3.json'))
for m in ch3['merged']:
    for x in m['mergedFrom']: renamed[x['slug']]=m['slug']
for p in st2['uncertain']:
    q=dict(p)
    idx=by_slugs.get((p['aSlug'],p['bSlug']))
    if idx is None:
        # same pair as in rev3 but with a merged-product slug
        for (a,b),i in by_slugs.items():
            if renamed.get(a,a)==p['aSlug'] and renamed.get(b,b)==p['bSlug']: idx=i; break
    if idx in KEEP:
        q['risk']='reviewed-kept-separate'; q['round4']=dict(decision='keep both',evidence=KEEP[idx])
    elif idx is None:
        q['risk']='potentially-distinct'; q['note']='new pair created by round-4 naming: vanilla slice vs marbled slice (different flavour on the pack)'
    elif idx in INS:
        q['risk']='insufficient-evidence'
    else:
        q['risk']='potentially-distinct'
    counts[q['risk']]+=1
    new.append(q)
print(len(new),dict(counts))
json.dump(dict(note='Rev 3.1. Pairs that look alike but are NOT merged. risk = reviewed-kept-separate (pack photos / sale format checked in round 4), insufficient-evidence (cannot be decided from the data held), potentially-distinct (names carry a different flavour, type or variant). 17 likely duplicates of rev 3 were merged in round 4 (see pair-merges.json) and no longer appear here.',pairs=new),open(D+'uncertain-matches.json','w'),ensure_ascii=False,indent=1)
pm=json.load(open(W+'work/pair_merges.json'))
json.dump(dict(note='Same-product merges verified pair by pair on the pack photos (rounds 3 and 4). a/b are source-record ids (source:id). Round-4 entries carry round=4 and the evidence read from the packs; keepName is the kept product name where the kept record had a less precise one.',applied=st2['packPhotoMerges'],candidates=pm),open(D+'pair-merges.json','w'),ensure_ascii=False,indent=1)
print(len(st2['packPhotoMerges']),len(pm))
# duplicate-review.json: refresh the two uncertain lists, keep the rest
dr=json.load(open(D+'duplicate-review.json'))
dr['sameBrandSameSizeSimilarWording']=[q for q in new if q['reason'].startswith('same brand; same size')]
dr['sameWordingSizeUnknown']=[q for q in new if q['reason'].startswith('same brand; size unknown')]
json.dump(dr,open(D+'duplicate-review.json','w'),ensure_ascii=False,indent=1)
print({k:len(v) for k,v in dr.items()})
# round-4 decisions file
dec=[]
P=json.load(open(D+'history/rev3/uncertain-matches.rev3.json'))['pairs']
EV={x['uncertainIndex']:x for x in pm if x.get('uncertainIndex') is not None}
for i in sorted(LD):
    p=P[i]
    if i in MERGE:
        x=EV[i]; dec.append(dict(index=i,brand=p['brand'],a=p['a'],aSlug=p['aSlug'],b=p['b'],bSlug=p['bSlug'],decision='merged',evidence=x['evidence'],keptName=x.get('keepName') or p['a'],pairId=x['pair']))
    else:
        dec.append(dict(index=i,brand=p['brand'],a=p['a'],aSlug=p['aSlug'],b=p['b'],bSlug=p['bSlug'],decision='kept separate',evidence=KEEP[i]))
json.dump(dict(note='Review round 4: the 28 likely-duplicate pairs of rev 3, each decided on the pack photos (both retailers\' pictures viewed side by side, one enlarged) and on the sale format. 17 merged, 11 kept separate.',summary=dict(merged=len(MERGE),keptSeparate=len(KEEP),total=len(LD)),decisions=dec),open(D+'duplicate-review-round4.json','w'),ensure_ascii=False,indent=1)
