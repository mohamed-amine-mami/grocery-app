# Catalogue v2 — taxonomy and rules

Generated 2026-10-10. Nothing here has been imported. Every rule below is enforced by the importer contract
(`backend/src/catalog/catalog-file.ts`, `catalog-plan.ts`, `products/product-rules.ts`) or is a convention this
phase applied and documented.

## 1. Categories

| Slug | Display name | Status | Scope | Products |
|---|---|---|---|---|
| `fruits` | Fruits | existing, kept | Fresh fruit (loose by weight or by piece), prepared fresh fruit | 19 |
| `legumes` | Légumes | existing, kept | Fresh vegetables, herbs, salads (loose or packed) | 67 |
| `produits-laitiers` | Produits laitiers | existing, kept | Milk, yoghurt, leben/raieb, cream, butter, margarine, eggs, chilled dairy desserts | 345 |
| `boulangerie` | Boulangerie | existing, kept | Bread, viennoiserie, pastries from the bakery counter | 132 |
| `viandes-poissons` | Viandes et poissons | existing, **archived** (needs your approval) | Previous combined category — now empty and archived (see impact report) | 0 |
| `epicerie` | Épicerie | existing, kept | Pantry: pasta, rice, couscous, flour, sugar, oil, vinegar, canned goods, sauces, spices, pulses, dates, dried fruit, baking aids | 1978 |
| `boissons` | Boissons | existing, kept | Water, soft drinks, juices, nectars, syrups, coffee, tea, infusions, chicory, energy drinks, non-alcoholic beer | 628 |
| `viandes` | Viandes | new | Beef, veal, lamb, minced meat, merguez, other fresh meat (pork cuts if any) | 18 |
| `volaille` | Volaille | new | Chicken, turkey, other poultry and rabbit (fresh cuts and whole birds) | 50 |
| `poissons-fruits-de-mer` | Poissons et fruits de mer | new | Fish and seafood (fresh, packed, smoked; not canned tuna/sardines) | 88 |
| `fromages` | Fromages | new | All cheeses (portions, slices, spreads, grated, cooking cheeses) | 255 |
| `charcuterie-traiteur` | Charcuterie et traiteur | new | Cold cuts, salami, ham, prepared dishes, ready meals, sandwiches | 126 |
| `surgeles` | Surgelés | new | Frozen foods, ice cream, ice cubes | 245 |
| `produits-traditionnels` | Produits traditionnels | new | Traditional Tunisian specialties that are a food type of their own: chamia (halva), bsissa, zrir, assida/mesfouf/droo (sorghum) and zgougou preparations, ground pulse/grain/nut pastes (as Géant groups them: "Chamia, bsissa et zrir" and "Préparations traditionnelles") | 212 |
| `petit-dejeuner` | Petit déjeuner | new | Cereals, jams, honey, spreads, rusks, instant chocolate drinks, and the traditional breakfast items chamia (halva), bsissa and zrir (as Géant files them: Épicerie > Petit déjeuner) | 450 |
| `biscuits-gateaux` | Biscuits et gâteaux | new | Biscuits, wafers, cakes, madeleines, muffins, packaged pastries | 525 |
| `chocolat-confiserie` | Chocolat et confiserie | new | Chocolate, sweets, chewing gum (candies merely filled with chamia stay here) | 286 |
| `snacks-aperitif` | Snacks et apéritif | new | Crisps, puffs, crackers and savoury snacks | 261 |

Decisions applied: `epicerie` kept; `viandes`, `volaille`, `poissons-fruits-de-mer` are separate global categories;
cheese is split out of `produits-laitiers` (one existing product, `fromage-emmental`, moves — listed in the impact report).
Category slugs are permanent identities; names can change later without a new row. Categories carry no description or photo.

## 2. Product identity and slugs

- A product's identity is its **slug**; the importer matches on nothing else. Renames keep the slug.
- The 42 existing slugs are restated unchanged and never reused. A new product whose generated slug would collide gets `-2`, `-3` in deterministic order.
- New slug = `slugify(display name + brand)`; the brand is not repeated when the name already contains it. Max 100 characters.
- **Same product** (merged) = same brand + same normalised wording + same size, across sources. Different flavour, size,
  count or brand = different product. Wording-only look-alikes are listed in `uncertain-matches.json`, never merged.
- Existing product ↔ source record matching is deliberately narrow: brandless **and** the same normalised name. 9 of 42 matched.

## 3. Display names (French)

- Source wording is kept (sentence case, whitespace collapsed, truncation markers removed after reading the full product page).
- Packaged products carry their package size at the end (`Yaourt aromatisé fraise 100 g`, `Eau minérale 1,5 L`) because the
  database requires unique names per brand and sizes are the only honest discriminator. Flavour/variant text from the source is
  kept before the size. Multi-packs are written `3 × 25 g`.
- Nothing is translated or invented. Loose produce keeps its plain name (`Courgette`).
- Original source names, ids and URLs live only in `provenance.json`.

## 4. Brands

- Brand = the manufacturer/brand string of the source, folded by case, accents, apostrophes and spacing
  (`MOULIN D'OR` = `MOULIN DOR` = `MOULIN D OR` → `Moulin d'Or`). Explicit alias: `DELICE` = `DÉLICE DANONE` → `Délice`.
- Display spelling: the most common mixed-case source spelling, else title case with elision rules (`d'`, `l'`).
- Slug = slugify(display name). Brandless (`brandSlug: null`) is valid: loose produce, bakery counter, butcher, fishmonger.
- **Excluded:** any brand or product name containing "Carrefour" (2 Carrefour records dropped). Other brands sold at Carrefour are kept.
- Retailer own-brands are *not* excluded (only Carrefour was): MG own labels `MG J'aime` and `Koll Youm` (39 products, flagged `privateLabelOf: MG` in the provenance). `Tous les jours` (55 products) appears as a featured house brand on Géant Drive; **unverified** whether it is Géant's own label.
- Brands are never archived or deleted by the importer; a wrong brand can only be renamed or re-pointed. Look-alike brands that were **not** merged are in `brands.json`.

## 5. Units and quantity rules (explicit in the file — nothing left to importer defaults)

Importer constraints: unit ∈ PIECE/KG/L; quantities are integers in pieces / **grams** / mL; KG and L values must be multiples of 10;
caps 1,000 pieces / 100,000 g; `min` and `max` multiples of `step`; `max ≥ min`.
A PIECE product can only ever be sold in PIECE; a KG product can be sold in KG or PIECE.

| Case | Unit | min / step / max | Basis |
|---|---|---|---|
| Packaged product (anything with a stated pack size, bottle, can, box) | PIECE | 1 / 1 / 24 | house default; matches existing packaged products (existing ones keep their own 12–120 maxima) |
| Loose fruit & vegetables | KG | 500 / 100 / 10000 | same as the existing produce products |
| Loose meat, poultry, fish | KG | 500 / 100 / 5000 | same family as existing `daurade`, `poulet-entier` |
| Loose cheese / deli cut | KG | 100 / 50 / 2000 | same as existing `fromage-emmental` |
| Loose pantry (spices, nuts, dried fruit, dates) | KG | 250 / 50 / 5000 (or the source's "Conditionné par N g" as min) | same as existing `dattes`, `olives-vertes` |
| Sold per piece/bunch ("La pièce", "La botte", "Le sachet") | PIECE | 1 / 1 / 24 | source states it is sold by the piece |

344 KG products, 5341 PIECE products. **No product uses L**: bottles are PIECE, as the existing catalog does.
`L` is only for loose liquids, and none was found.
These are catalog **defaults**. A store's price, unit, quantity rules, stock and availability are untouched and set per StoreProduct.

Evidence for KG: Géant's own wording (`Le KG`, `Conditionné par 500 g/100 g`, loose market items), Carrefour's loose-counter flag
carried over from the earlier conversion, or the Carrefour product page saying "Au poids" / "Au Kg". Where the source gives no sale basis the product is PIECE.

## 6. Categories assignment

Géant Drive sub-category → category map (`tools/taxonomy.py`), then name-based overrides for the meat/poultry/fish/charcuterie/frozen
family (Géant files sausages under "bœuf", frozen escalopes under "hachées"). Carrefour products reuse the earlier conversion's
category, re-split by name. Aziza/MG/OFF products are classified by keyword (`tools/build_candidates.py`, `guess_category`).
Classification is rule-based with an explicit correction layer (`classification-corrections.json`, rules C1–C5, M1–M12); it is **not manually reviewed per product**.

## 7. Out of scope

Non-food (hygiene, cosmetics, cleaning, electronics, kitchenware, baby care, pet food), alcoholic beverages, dietary supplements,
promotional bundles / mixed lots / "gratuit" offers, anything where the name could not be read or classified from the source.
Counts: see `exclusions.json`.
