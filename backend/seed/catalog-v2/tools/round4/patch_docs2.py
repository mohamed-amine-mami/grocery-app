import re
D='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
def patch(fn, reps, regex=False):
    s=open(D+fn).read()
    for a,b in reps:
        n=s.count(a)
        assert n>=1,(fn,a)
        s=s.replace(a,b)
    open(D+fn,'w').write(s)
CAT_OLD={'`produits-laitiers` 351':'`produits-laitiers` 345','`boulangerie` 133':'`boulangerie` 132','`epicerie` 1980':'`epicerie` 1978','`boissons` 630':'`boissons` 628','`fromages` 258':'`fromages` 255','`biscuits-gateaux` 527':'`biscuits-gateaux` 525','`snacks-aperitif` 262':'`snacks-aperitif` 261'}
CATS=list(CAT_OLD.items())
BANNER_R3="> **Superseded in part by Rev 3.1 — see `review-round4.md`.** This file records Rev 3 (5,702 products). Review round 4 merged 17 more confirmed duplicates (5,685 products). The merge breakdown and the removed/added arithmetic below were corrected in round 4; numbers that changed in Rev 3.1 are listed in `changes-since-rev3.json`.\n\n"
# ---------------- validation-report.md
patch('validation-report.md',[('5702 products','5685 products'),('5494 non-null photos','5478 non-null photos'),('| Products | 5660 | 13 | 29 | 0 |','| Products | 5643 | 13 | 29 | 0 |'),
 ('5702 (42 existing + 5660 new)','5685 (42 existing + 5643 new)'),('| KG / PIECE | 344 / 5358 |','| KG / PIECE | 344 / 5341 |'),('5494 / 208','5478 / 207'),
 ('**Uncertain matches (not merged): 159 pairs**','**Uncertain matches (not merged): 143 pairs** (rev 3: 159; 17 merged in round 4, 1 new)')]+[(a.replace('`','`'),b) for a,b in CATS])
# ---------------- photo-validation.md
patch('photo-validation.md',[('| With a photo | 5494 |','| With a photo | 5478 |'),('| – inspected and accepted | 757 |','| – inspected and accepted | 752 |'),('| – URL valid, **not visually inspected** | 4737 |','| – URL valid, **not visually inspected** | 4726 |'),
 ('| `null` photo | 208 |','| `null` photo | 207 |'),('geant 4876, carrefour 406, off 101, aziza 73, mg 38','geant 4868, carrefour 402, off 98, aziza 72, mg 38'),
 ('Why `null` (208): source image URL returns 404 / invalid: 144; existing product with no confident source match (unchanged): 33; image rejected in visual inspection: 31.','Why `null` (207): source image URL returns 404 / invalid: 144; existing product with no confident source match (unchanged): 33; image rejected in visual inspection: 30.'),
 ('(5,494 products with a photo, 208 with `null`)','(5,478 products with a photo, 207 with `null`)'),
 ('| Photos used in the catalogue that were **inspected and accepted** | **757** | |','| Photos used in the catalogue that were **inspected and accepted** | **752** | 5 fewer than Rev 3 only because 17 products were merged; the pack pictures of the 28 round-4 pairs were also looked at side by side (see `review-round4.md`) but are not added to this count |'),
 ('| **4,737** |','| **4,726** |'),
 ('757 photos visually verified, 4,737 not.','752 photos visually verified, 4,726 not.')])
# ---------------- taxonomy-and-rules.md
patch('taxonomy-and-rules.md',[('| 351 |','| 345 |'),('| 133 |','| 132 |'),('| 1980 |','| 1978 |'),('| 630 |','| 628 |'),('| 258 |','| 255 |'),('| 527 |','| 525 |'),('| 262 |','| 261 |'),('344 KG products, 5358 PIECE products.','344 KG products, 5341 PIECE products.')])
# ---------------- impact-existing.md
patch('impact-existing.md',[('**258 cheese products**','**255 cheese products**'),('would hold 609 products','would hold 600 products')])
# ---------------- capacity-assessment.md: measurements stay as measured
s=open(D+'capacity-assessment.md').read()
s=s.replace('Candidate size: **5,702 products** (today\'s dev catalogue: 42).','Candidate size: **5,685 products** in Rev 3.1 (today\'s dev catalogue: 42). The measurements below were taken on the Rev 3 file (5,702 products); the 0.3 % difference changes none of them or of the conclusions.',1)
open(D+'capacity-assessment.md','w').write(s)
print('ok')
