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
# ---------------- review-round3.md: keep as the Rev 3 record, fix its internal inconsistencies
s=open(D+'review-round3.md').read()
s=s.replace('# Catalogue v2 — review round 3 (decisions applied)\n\n','# Catalogue v2 — review round 3 (decisions applied)\n\n'+BANNER_R3,1)
# header misalignment (rows have 6 cells: Slug | Name | Old | New | Offerings | Unit)
s=s.replace('| Slug | Old category | New category | Offerings | Unit & quantities |\n|---|---|---|---|---|','| Slug | Name | Old category | New category | Offerings | Unit & quantities |\n|---|---|---|---|---|---|',1)
old9=s[s.index('## 9. Exact changes since rev 2'):s.index('## 10. Unresolved')]
new9='''## 9. Exact changes since rev 2 (`changes-since-rev2.json`) — corrected in round 4
Rev 2 had 5,801 products; Rev 3 has 5,702. The categories below are **not** additive with each other — they are listed with the arithmetic that closes the count.

| Change | Count | Notes |
|---|---|---|
| Unchanged (same slug, name, category) | 5,135 | |
| Renamed / re-slugged | 310 | size from the Carrefour page, brand merge, variant name, Souani line |
| Category only | 205 | almost all → `produits-traditionnels` |
| **Merge groups** | **113** | absorb **136** Rev 2 products; 22 of the groups carry a new slug, so the net reduction is **114** |
| Removed | 15 listed / **14 net** | 4 pork species unknown, 4 Carrefour indistinguishable, 6 look-alikes, 1 jam with illegible flavour. One slug (`tortillas-de-farine-complete-360-g-deli-sun`) is also in "added": the look-alike was removed and then restored under a variant name |
| Added | 30 listed / **29 net** | variants restored from look-alikes |

**Closing arithmetic:** 5,801 − 114 (merges, net) − 14 (removed, net) + 29 (added, net) = **5,702**.

**Why the merge causes are not additive.** The earlier text read "96 Carrefour + 29 descriptor + 56 pack-photo", which sums to 181 and cannot be compared with 113 groups: the 29 descriptor merges were already applied in Rev 2, and a group can have several causes. Each of the 113 groups assigned to exactly one primary cause: **95** Carrefour pack size read from the product page (96 Carrefour records fall in these groups), **17** pack-photo pair merges (56 pairs in total, 55 of which fall in groups that also have a Carrefour record), **1** descriptor-only. Overlapping counts per cause: Carrefour 95, pack-photo pair 55, brand merge 4, descriptor 1.

'''
s=s.replace(old9,new9,1)
s=s.replace('| Photos (URL) / `null` | 5,591 / 210 | 5,494 / 208 |','| Photos (URL) / `null` | 5,591 / 210 | 5,494 / 208 |\n| KG / PIECE | 324 / 5,477 | **344 / 5,358** |',1)
open(D+'review-round3.md','w').write(s)
# ---------------- SUMMARY.md (rewrite the data-dependent lines for Rev 3.1)
s=open(D+'SUMMARY.md').read()
s=s.replace('# Catalogue v2 — summary after review round 3 (nothing imported)','# Catalogue v2 — summary after review round 4 / Rev 3.1 (nothing imported)',1)
s=s.replace('Generated 2026-10-10. **Status: revised candidate (rev 3), validated, not imported.','Generated 2026-10-10. **Status: revised candidate (Rev 3.1 = Rev 3 + review round 4), validated, not imported.',1)
s=s.replace('| **`review-round3.md`** |','| **`review-round4.md`** | how the 28 likely-duplicate pairs were decided (17 merged, 11 kept), documentation corrections, validation |\n| `review-round3.md` |',1)
s=s.replace('| `changes-since-rev2.json` |','| `changes-since-rev3.json`, `duplicate-review-round4.json` | the 17 round-4 merges and the 28 pair decisions with evidence |\n| `changes-since-rev2.json` |',1)
s=s.replace('## Numbers (rev 3)','## Numbers (Rev 3.1)',1)
for a,b in [('**5,702** = 42 existing + 5,660 new (rev 2: 5,801)','**5,685** = 42 existing + 5,643 new (rev 2: 5,801; rev 3: 5,702)'),
            ('344 / 5,358 (no L)','344 / 5,341 (no L)'),
            ('5,494 URLs, 208 `null`; 757 visually verified','5,478 URLs, 207 `null`; 752 visually verified'),
            ('products created 5,660 / updated 13','products created 5,643 / updated 13')]+CATS:
    assert a in s,a; s=s.replace(a,b)
i=s.index('- **Products 5,801 → 5,702**'); j=s.index('\n',i)
s=s[:i]+"- **Products 5,801 → 5,702 (Rev 3) → 5,685 (Rev 3.1).** Rev 3: 113 merge groups absorbing 136 products (net −114, because 22 groups carry a new slug), 14 removed net, 29 added net: 5,801 − 114 − 14 + 29 = 5,702. Round 4: 17 pack-photo-confirmed duplicates merged (−17). Causes are listed once each in `changes-since-rev2.json` → `reconciliation`; they are not additive across overlapping categories."+s[j:]
s=s.replace('4. 159 low-similarity uncertain pairs and 55 excluded look-alikes are listed, not resolved.','4. 143 uncertain pairs remain: 11 were reviewed in round 4 and kept separate for stated reasons, 52 have insufficient evidence, 80 carry a different flavour/type in the name; plus 55 excluded look-alikes (all listed, none merged).',1)
s=s.replace('5. Photos not visually verified: 4,737.','5. Photos not visually verified: 4,726.',1)
open(D+'SUMMARY.md','w').write(s)
# ---------------- validation-report.md
patch('validation-report.md',[('5702 products','5685 products'),('5494 non-null photos','5478 non-null photos'),('| Products | 5660 | 13 | 29 | 0 |','| Products | 5643 | 13 | 29 | 0 |'),
 ('5702 (42 existing + 5660 new)','5685 (42 existing + 5643 new)'),('| KG / PIECE | 344 / 5358 |','| KG / PIECE | 344 / 5341 |'),('5494 / 208','5478 / 207'),
 ('**Uncertain matches (not merged): 159 pairs**','**Uncertain matches (not merged): 143 pairs** (rev 3: 159; 17 merged in round 4, 1 new)'),
 ('**Size of the catalogue**: 5702 products','**Size of the catalogue**: 5685 products')]+[(a.replace('`','`'),b) for a,b in CATS])
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
