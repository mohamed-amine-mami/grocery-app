# Catalogue v2 — brand verification

> **Superseded in part by round 3.** Brands were merged where pack photos proved the same brand (15 merges, `brand-merges.json`); the pair classification below is the round-2 view ("none merged" no longer applies). `Tous les jours` is retained provisionally with ownership marked unverified. See `review-round3.md` §2 and §4.


## Decisions applied
- **Carrefour:** 0 products and 0 brands contain "Carrefour" in the file (0 found by name/brand scan). The 2 Carrefour-branded CSV rows (`Café soluble aggloméré`, `Café soluble lyophilisé`, brand `CARREFOUR`) stay excluded. Brands Carrefour merely *sells* are kept (e.g. Délice, Vitalait, Saïda, Sanabel).
- **No brand merges were applied** in this round: nothing below was merged automatically.

## MG J'aime and Koll Youm — kept, evidence
| Brand | Products | Evidence |
|---|---|---|
| `MG J'aime` | 32 | mg.tn (Magasin Général's own site) sells it throughout its food range and publishes press items titled "MG J'aime élue marque de distributeur de l'année 2026 …"; the same fact is reported by African Manager ("MG J'aime élue marque de distributeur de l'année 2026 en Tunisie pour la 3ᵉ fois"). → **verified retailer private label of Magasin Général.** |
| `Koll Youm` | 7 | Sold only on mg.tn, in the same product listings and carousels as `MG J'aime`, with the same "Kollection" textile range. **No page I could reach states ownership explicitly**, and a web search found no third-party mention. → treated as an MG-exclusive label by observation, **not independently verified.** |
Both are genuine brands that exist in the source (not invented); the file carries no ownership field, so no attribution is asserted. The provenance records `privateLabelOf: MG` as an observation only.

## "Tous les jours" — ownership not verifiable
Evidence collected: the brand has 55 products, all from Géant Drive (sources: {'geant': 55}), across {'produits-laitiers': 4, 'epicerie': 37, 'fromages': 3, 'produits-traditionnels': 3, 'petit-dejeuner': 3, 'snacks-aperitif': 5}. It appears on Géant Drive as a brand page (`/tunis-city/brand/2036-tous-les-jours`, listed prominently in the shop header) and **nowhere else** (not in the Carrefour CSV, Aziza's catalogue, MG, or the Open Food Facts records I could read — OFF throttled, so that check is weak). The Géant Drive page has no description. A web search found no source that says it is Géant's own label (or anyone's). A search result mentioned Magasin Général, not Géant, as the Tunisian distributor-brand leader.
- **Conclusion:** it is a real brand string supplied by a retailer, but its owner is **unknown**. Retailer-exclusive + prominent placement makes "house label" *likely* but that is inference.
- **Safest treatment (applied):** keep the brand under the name the source gives, with no ownership claim in the catalog (the provenance does not label it a private label). Alternative if you prefer zero risk: drop the 55 products or set `brandSlug: null` for them — your call.
- Affected: `oeufs-frais-jaune-15-pieces-tous-les-jours`, `oeufs-frais-jaune-30-pieces-tous-les-jours`, `oeufs-frais-jaune-orange-15-pieces-tous-les-jours`, `oeufs-frais-jaune-orange-30-pieces-tous-les-jours`, `basilic-20-g-tous-les-jours`, `boulgour-350-g-tous-les-jours`, `cannelle-30-g-tous-les-jours`, `carvi-moulu-100-g-tous-les-jours` … (55 total, full list: filter `brandSlug == "tous-les-jours"` in `catalog.v2.json`).

## Brand duplicates and spelling variants (rechecked)
70 look-alike pairs (was 90 before the merges and exclusions of this round). Classification, **none merged**:

| Class | Pairs |
|---|---|
| distinct brands with similar names | 19 |
| probable spelling / naming variant of one brand | 6 |
| product-line / sub-brand of the other (source gave it as the brand) | 43 |
| uncertain — not classified | 2 |

### Probable spelling / naming variants (candidates for a merge, awaiting your decision)
| Brand A | Brand B | Class |
|---|---|---|
| Daily | Daily'n | probable spelling / naming variant of one brand |
| Dorra | El Dorra | probable spelling / naming variant of one brand |
| Gazelle | La Gazelle | probable spelling / naming variant of one brand |
| Lebanese Factory | The Lebanese Factory | probable spelling / naming variant of one brand |
| Spiga | Spipa | probable spelling / naming variant of one brand |
| Weepo | Weepop's | probable spelling / naming variant of one brand |

Each pair above is the same *kind* of product from the same retailer with a near-identical name; it remains unproven without the packs. If merged, products with identical name+size under the two spellings would collide on the unique `(name, brand)` index — the planner would flag them.

### Distinct brands with similar names (keep apart)
| Brand A | Brand B | Class |
|---|---|---|
| Biskart | Up Biskart | distinct brands with similar names |
| Carthage | Sanabel Carthage | distinct brands with similar names |
| Crispo | Crispy | distinct brands with similar names |
| Cristal | Cristaline | distinct brands with similar names |
| Darna | Darta | distinct brands with similar names |
| Délice | Delices de la Mer | distinct brands with similar names |
| Dorra | Durra | distinct brands with similar names |
| El Rayen | Rayen | distinct brands with similar names |
| Epices et Saveurs | Saveurs | distinct brands with similar names |
| Grano | Granoro | distinct brands with similar names |
| Ledoux | Leroux | distinct brands with similar names |
| Major | Mayor | distinct brands with similar names |
| Melina | Melita | distinct brands with similar names |
| Milka | Milkana | distinct brands with similar names |
| Olina | Ovolina | distinct brands with similar names |
| Sadia | Safia | distinct brands with similar names |
| Safaa | Safia | distinct brands with similar names |
| Safia | Safir | distinct brands with similar names |
| Vitup | Vitupti | distinct brands with similar names |

### Product lines / sub-brands given as the brand by the source (43 pairs)
Kept as the source states them (e.g. `Dolce Vitalait` vs `Vitalait`, `Milkana Delice` vs `Délice`). The full list with product counts and all raw spellings is in `brands.json`.

### Unclassified (2 pairs)
`Aljazia` / `Al Jazira`, `El Jawhara` / `Jawhara`
