# Catalogue v2 — photo URL validation report

Generated 2026-10-10. Photos are direct third-party URLs stored as plain strings; nothing was downloaded into the project.

## 1. Basic validity — **every** candidate URL

All 5831 distinct candidate URLs (every photo of every source record, not only the chosen one) were requested
(HEAD, falling back to a ranged GET). A URL is "valid" only if the answer is HTTP 200/206, `Content-Type: image/*`, and the size is ≥ 1.5 KB.

| Host | Result | URLs |
|---|---|---|
| back.carrefour.tn | valid | 493 |
| btoc.azizacdn.com | valid | 124 |
| cdn.geantdrive.tn | INVALID | 147 |
| cdn.geantdrive.tn | valid | 4901 |
| images.openfoodfacts.org | valid | 127 |
| mg.tn | valid | 39 |

- Valid: **5684**, invalid: **147** (all Géant `cdn.geantdrive.tn` HTTP 404: the product page references an image that no longer exists).
- Invalid URLs are never used; the product falls back to another source's valid photo, or to `null`.
- No placeholder/"no image" clusters were found (the largest identical-size cluster was 3 files, all different products' real photos).
- mg.tn file names are not reliable as a relevance signal: several URLs carry another product's slug but show the right product (and vice-versa could occur). Only visual inspection was used for MG.

## 2. Visual inspection — exactly what was and was not inspected

**846 distinct images were looked at** (contact sheets of 20, numbered, compared with the product name and brand).
What was verified for each: the picture shows the product named (right type; right flavour/variant when the name states one; brand when legible),
is a product photo (not a label scan, back of pack, nutrition table or screenshot), and carries no other shop's watermark.
What was **not** verified: net weight/size printed on the pack, colour accuracy, current packaging design, image resolution beyond "readable".

| Source | Photos in the catalogue's candidate set | Inspected | Accepted | Rejected: wrong | Rejected: approximate |
|---|---|---|---|---|---|
| geant | 5048 | 394 | 390 | 4 | 0 |
| aziza | 124 | 124 | 99 | 5 | 20 |
| carrefour | 493 | 162 | 160 | 2 | 0 |
| mg | 39 | 39 | 38 | 0 | 1 |
| off | 127 | 127 | 117 | 10 | 0 |

- **Fully inspected populations:** every Aziza photo, every MG photo, every Open Food Facts photo, and every photo placed on one of the 42 existing products.
- **Sampled only:** Géant Drive — 394 of 4901 valid URLs (stratified by category, ≥ 4 per category); Carrefour — 162 of 493 valid URLs (random).
  Géant sample: 4 wrong variant in 394. Carrefour: 2 of 162. These rates are an estimate for the un-inspected remainder, **not** a verification: 4488 Géant and 249 Carrefour photos used in the catalogue were checked for URL validity only.
- Aziza photos are weakest: 25 of 124 (20 %) were rejected, mostly one shared multi-flavour assortment image reused for several flavours. OFF: 10 of 127 rejected (label scans, back of pack, blur, shop watermark, brand mismatch) and the accepted ones are crowd-sourced phone photos of uneven quality.
- MG product photos are correct but small (product occupies a fraction of a 1100×1422 canvas); low visual quality, not a correctness issue.

### Rejected after inspection (replaced by another source's photo or `null`)

| Item | Source | Product | Verdict | Reason |
|---|---|---|---|---|
| #97 | geant | Moutarde A l'ancienne 200 ml | wrong | wrong variant (Dijon mustard shown for "à l'ancienne") |
| #166 | aziza | Boisson gazeuse canette cidre 24 cl | wrong | wrong flavour (cola can shown for cidre) |
| #173 | aziza | Yaourt aromatisé aux fruits des bois 100 g | wrong | wrong flavour (fraise shown for fruits des bois) |
| #174 | aziza | Boisson gazeuse canette pomme 24 cl | approximate | shared assortment image (several flavours), variant not identifiable |
| #175 | aziza | Biscuit petit matin aux céréales et pépites de cho | approximate | shared assortment image |
| #178 | aziza | Mon dessert dessert noisette 100 g | approximate | shared assortment image |
| #186 | aziza | Chips the box hot et spicy 125 g | approximate | shared assortment image |
| #191 | aziza | Yaourt aromatisé à la fraise 100 g | approximate | shared assortment image |
| #193 | aziza | Mon dessert vanille 100 g | approximate | shared assortment image |
| #194 | aziza | Boisson gazeuse canette citron 24 cl | approximate | shared assortment image |
| #260 | off | Major ( chocolat ) 180 g | wrong | third-party shop watermark |
| #276 | aziza | Cake nature vanille 700 g | wrong | image shows a different named product (Barre d'or) — identity not confirmable |
| #284 | aziza | Donuts fourré à la crème saveur vanille 50 g | approximate | shared assortment image |
| #286 | aziza | Gaufrette croustina chocolat 100 g | approximate | shared assortment image |
| #307 | aziza | Boisson gazeuse canette pêche 24 cl | approximate | shared assortment image |
| #309 | aziza | Boisson gazeuse cidre punch 1,5 L | wrong | image appears to show a different flavour (dark cola-like drink for cidre) |
| #316 | aziza | Boisson pêche abricot 200 ml | approximate | shared assortment image |
| #318 | off | Chicorée Café Brava 300 g | wrong | cropped label close-up, not the product |
| #319 | aziza | Chips the box barbacue 42 g | approximate | shared assortment image |
| #322 | aziza | Chips the box hot spicy 42 g | approximate | shared assortment image |
| #328 | off | Déli'o menthe 25 cl | wrong | label scan, not a product photo |
| #331 | off | Eau de source naturelle 1,5 L | wrong | label scan, not a product photo |
| #336 | off | Eau minérale naturelle 0,4 L | wrong | bottle unreadable (no visible brand/label) |
| #348 | off | Eau minérale naturelle 1,5 L | wrong | blurry, unrecognisable |
| #354 | aziza | Jus multivitaminé 20 cl | approximate | shared assortment image |
| #364 | off | Yopro fraise framboise 300 g | wrong | back of pack (nutrition table), not the product front |
| #372 | off | Mille Recettes - Chocolat noir 100 g | wrong | third-party shop watermark |
| #385 | off | Double concentré de tomates 800 g | wrong | brand mismatch (Le Petit Paris can shown for Comocap) |
| #444 | aziza | Lait aromatisé banane 20 cl | approximate | shared assortment image |
| #446 | aziza | Lait aromatisé fraise 20 cl | approximate | shared assortment image |
| #447 | aziza | Lait aromatisé vanille 20 cl | approximate | shared assortment image |
| #459 | off | Raib 420 g | wrong | back panel of the carton, not the product front |
| #473 | aziza | Yaourt brassé fraise 100 g | approximate | shared assortment image |
| #486 | aziza | Chips paprika The box 125 g | approximate | shared assortment image |
| #487 | aziza | Chips paprika The box 42 g | approximate | shared assortment image |
| #488 | aziza | Chips potato cheese 65 g | wrong | flavour mismatch (classic-taste bag shown for cheese) |
| #503 | mg | Miel 250 g | approximate | shared assortment image |
| #515 | geant | Ail rouge en fillet | wrong | garlic in net: shown item looks like onions/shallots, identity not confirmable |
| #608 | geant | Glace fraise-Cheesecake 900 ml | wrong | brand mismatch (Eskimo tub shown for Exquise) |
| #644 | carrefour | Gâteaux au café | wrong | shows another retailer's brand/logo (Carrefour bakery) |
| #645 | carrefour | Tarte amandine | wrong | shows another retailer's brand/logo (Carrefour bakery) |
| #705 | geant | Miel tout fleur 250 g | wrong | pack not identifiable as the named brand (sibling product shows a different jar) |

## 3. Photos actually used

| | Products |
|---|---|
| With a photo | 5478 |
| – inspected and accepted | 752 |
| – URL valid, **not visually inspected** | 4726 |
| `null` photo | 207 |

By source of the photo used: geant 4868, carrefour 402, off 98, aziza 72, mg 38.

Why `null` (207): source image URL returns 404 / invalid: 144; existing product with no confident source match (unchanged): 33; image rejected in visual inspection: 30.

Existing products that gain a photo: 9 (all visually inspected and accepted; listed in `impact-existing.md`). The other 33 stay `null`.

## 4. Caveats for using these URLs

- Hot-linked images from `cdn.geantdrive.tn`, `back.carrefour.tn`, `btoc.azizacdn.com`, `mg.tn`, `images.openfoodfacts.org` can change or disappear; the product is then shown without image (the apps already have a placeholder).
- Open Food Facts images are licensed CC BY-SA (attribution to Open Food Facts contributors); Carrefour/Géant/Aziza/MG images belong to the retailers/brands. Accepted for this portfolio project per your decision.
- Per-URL results, HTTP status, content type, size and the visual verdict are in `photo-validation.json`.


<!-- round2 -->
## 5. Review round 2 — definitions, coverage and the targeted sample

Counts are over the **current** candidate (5,478 products with a photo, 207 with `null`). Five different things are counted separately:

| Measure | Count | What it means |
|---|---|---|
| URLs **checked for HTTP/accessibility and image content type** | **5,831** | every candidate URL of every source record (HEAD, ranged-GET fallback; 200/206 + `image/*` + ≥ 1.5 KB) |
| – passed | 5,684 | |
| – **failed / removed** | **147** | 147 HTTP 404, 0 other; never used |
| Images **visually inspected** | **846** distinct | round 1: 469; round 2 (targeted): 325 |
| – inspected and **rejected** (not used → fallback source or `null`) | **42** | {'aziza:approximate': 20, 'aziza:wrong': 5, 'carrefour:wrong': 2, 'geant:wrong': 4, 'mg:approximate': 1, 'off:wrong': 10} |
| Photos used in the catalogue that were **inspected and accepted** | **752** | 5 fewer than Rev 3 only because 17 products were merged; the pack pictures of the 28 round-4 pairs were also looked at side by side (see `review-round4.md`) but are not added to this count |
| Photos used that are URL-valid but **not visually verified** | **4,726** | relevance to the product is **unverified**; not claimed as correct |

### Did the first sample cover the sources and categories? — no, so a targeted round was added
Round 1 covered every source but was thin in fresh produce (34 of 235 inspected), meat/poultry/fish, frozen, charcuterie, snacks and confectionery, and had no check for variant families, package sizes or identical files. Round 2 inspected **325 more images** aimed at those gaps:

| Target | Images | Result |
|---|---|---|
| Fresh produce — every remaining photo in `fruits` and `legumes` | 63 | 1 rejected (garlic/onion confusion); 1 misfiled product found (citron under légumes → fixed) |
| Fresh meat / poultry / fish sample | 32 | 0 rejected; 1 misfiled (sardine under viandes → fixed), 1 soup under volaille (fixed) |
| Low-coverage categories (surgelés, charcuterie, snacks, confiserie, boulangerie, fromages) | 60 | 1 rejected (Exquise tub showed Eskimo), 2 rejected (bakery photos carry Carrefour's logo) |
| Variant families (same brand + line, ≥ 4 distinct photos; 3 sampled each) | 36 | 0 wrong flavour found in 12 families |
| Package-size families (same brand/line, 2 sizes) | 28 | 1 rejected (honey box ≠ sibling jar); others fine |
| Byte-identical image files shared by different products (all 14 groups) | 28 | 0 rejected (size variants and generic stock photos) |
| Other-retailer logo / branding check on **every** brandless Carrefour counter item not yet seen | 79 | 0 more with logos |

### Coverage by category — photos used / inspected and accepted
| Category | Photos used | Inspected & accepted | Share |
|---|---|---|---|
| epicerie | 1915 | 149 | 7 % |
| boissons | 600 | 88 | 14 % |
| biscuits-gateaux | 503 | 67 | 13 % |
| petit-dejeuner | 435 | 48 | 11 % |
| produits-laitiers | 335 | 62 | 18 % |
| chocolat-confiserie | 278 | 24 | 8 % |
| snacks-aperitif | 254 | 31 | 12 % |
| fromages | 252 | 40 | 15 % |
| surgeles | 239 | 34 | 14 % |
| produits-traditionnels | 204 | 17 | 8 % |
| boulangerie | 127 | 34 | 26 % |
| charcuterie-traiteur | 125 | 25 | 20 % |
| poissons-fruits-de-mer | 86 | 28 | 32 % |
| legumes | 62 | 62 | 100 % |
| volaille | 48 | 22 | 45 % |
| viandes | 17 | 12 | 70 % |
| fruits | 14 | 14 | 100 % |

### Coverage by source of the photo used
| Source | Photos used | Inspected & accepted | Share |
|---|---|---|---|
| geant | 4876 | 388 | 7 % |
| carrefour | 406 | 157 | 38 % |
| off | 101 | 101 | 100 % |
| aziza | 73 | 73 | 100 % |
| mg | 38 | 38 | 100 % |

Weak area that remains: `epicerie` (the largest category, mostly Géant packs). Its inspected share is the lowest of the big categories; the Géant sample error rate overall is 4 rejects in 394 Géant images inspected, which is an estimate, not a verification of the other ~4,488 Géant photos.

### Known wrong or unreliable matches → `null` (or fallback to a verified photo)
All 42 rejected images are listed with reasons in section 2 of this report (round 1) and below (round 2):

| Item | Source | Product | Reason |
|---|---|---|---|
| 515 | geant | Ail rouge en fillet | garlic in net: shown item looks like onions/shallots, identity not confirmable |
| 608 | geant | Glace fraise-Cheesecake 900 ml | brand mismatch (Eskimo tub shown for Exquise) |
| 644 | carrefour | Gâteaux au café | shows another retailer's brand/logo (Carrefour bakery) |
| 645 | carrefour | Tarte amandine | shows another retailer's brand/logo (Carrefour bakery) |
| 705 | geant | Miel tout fleur 250 g | pack not identifiable as the named brand (sibling product shows a different jar) |

Rule applied for the **un-inspected** population: a photo is used only if its URL passed the accessibility check; that is *not* evidence the picture is right. The honest statement for the catalogue is: 752 photos visually verified, 4,726 not.
