import json
PV={p['slug']:p for p in json.load(open('/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/history/rev3/provenance.rev3.json'))['products']}
P=json.load(open('/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/history/rev3/uncertain-matches.rev3.json'))['pairs']
EV={
2:"Both packs are the Mama Mia 'Pain de mie Nature' bag, same 14-slice format.",
9:"Both are the Daily'n marbled loaf cake in the same wrapper (chocolate/vanilla marbling, Daily'n band), 700 g; Carrefour calls it 'Grand Mère', Géant 'Cake'.",
10:"Both packs read 'Slice – Recette Grand-Mère – chocolat vanille' (Daily'n 40 g); only the wrapper print generation differs.",
26:"Carrefour/OFF pack reads 'Demi-écrémé' (Délice UHT 1 L); the Géant record names it '1/2 écrémé' 1 L. The Géant carton art does not show the variant, so the variant rests on the two source names.",
41:"Both cartons read 'Tropico – cocktail de fruits – multivitamine', 1 L.",
44:"Both are the standard Red Bull 25 cl can.",
73:"Both packs are the Natilait 'mon Dessert' chocolate cup (Géant cup reads 'Dessert Chocolat'), 100 g; Aziza's picture is the same cup in a set.",
75:"Géant cup reads 'mon Dessert Vanille' (Natilait, 100 g); Aziza names it 'Mon dessert vanille'.",
84:"Both packs are the L'Epi d'Or 'Farine pâtissière' 1 kg bag.",
86:"Both cans read 'SICAM – Harissa du Cap Bon – 135 g'.",
108:"Both are the Souani 'Tomme de Tebourba' round (red label, 280 g); 'camembert' in the Carrefour name is not on the pack.",
112:"Both packs are the Majesté 'Fromage Mozzarella' 250 g block.",
117:"Both bags read 'Majesté – Rap'cheez – 4 fromages', 500 g.",
121:"Géant pack, enlarged, reads 'Vitalait – Beurre extra fin – 200 g'; the OFF pack reads 'Vitalait – Beurre extra fin'.",
142:"Both cups read 'YAB – Plaisir Liégeois – goût chocolat', 12 cl (older vs current print).",
150:"Both tubs read 'Goldina – Tartine & Cuisson – riche en vitamines A et E', 100 g.",
158:"Both bags read 'Céréalis – Sweet Popcorn', 75 g."}
pm=json.load(open('/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/work/pair_merges.rev3.json'))
n=max((x['pair'] for x in pm if isinstance(x.get('pair'),int)),default=0)
print('rev3 entries',len(pm),'max pair',n)
for i,ev in EV.items():
    p=P[i]; a=PV[p['aSlug']]['sources'][0]; b=PV[p['bSlug']]['sources'][0]
    n+=1
    pm.append(dict(pair=n,a=[f"{a['source']}:{a['sourceId']}"],b=[f"{b['source']}:{b['sourceId']}"],aName=p['a'],bName=p['b'],brand=p['brand'],evidence=ev,round=4,uncertainIndex=i))
json.dump(pm,open('/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/work/pair_merges.json','w'),ensure_ascii=False,indent=1)
print(len(pm))
