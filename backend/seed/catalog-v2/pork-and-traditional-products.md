# Catalogue v2 — pork products, chamia and bsissa

> **Superseded in part by round 3.** The 4 species-unknown pork-family products are now **excluded**; the 9 confirmed are retained. Chamia/bsissa/zrir now live in the dedicated category `produits-traditionnels`, not `petit-dejeuner`. See `review-round3.md` §3 and §6.


## 1. Pork products

Method: every product whose source name/description contains porc, bacon, lardons, chorizo, serrano, jambon (de Paris/cru…), saucisson sec, pepperoni, etc. was pulled with its source evidence.
The catalog has **no schema field for ingredients/diet**, so this is a review list; nothing was removed or flagged in the file.

### Confirmed pork (9) — source says "porc" and/or files it under Géant's *Porc* sub-category
| Slug | Name | Brand | Category | Evidence | First source record |
|---|---|---|---|---|---|
| `bacon-fume-de-porc-100-g-bastides` | Bacon fumé de porc 100 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #25035 “Bacon fumé de porc” (100GR) |
| `chorizo-de-porc-80-g-bastides` | Chorizo de porc 80 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #43087 “Chorizo de porc” (80GR) |
| `jambon-de-paris-180-g-4-tranches-jean-caby` | Jambon de paris 180 g 4 tranches | Jean Caby | charcuterie-traiteur | Géant sub-category "porc" | geant #25031 “Jambon de paris” (180GR-4 Tranches) |
| `jambon-serrano-de-porc-100-g-bastides` | Jambon serrano de porc 100 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #25027 “Jambon serrano de porc” (100GR) |
| `lardons-de-porc-160-g-bastides` | Lardons de porc 160 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #25232 “Lardons de porc” (160GR) |
| `saucisson-sec-de-porc-au-noix-80-g-bastides` | Saucisson sec de porc au noix 80 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #43086 “Saucisson sec de porc” (80GR Au noix) |
| `saucisson-sec-de-porc-au-roquefort-80-g-bastides` | Saucisson sec de porc au roquefort 80 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #43085 “Saucisson sec de porc” (80GR Au roquefort) |
| `saucisson-sec-de-porc-nature-80-g-bastides` | Saucisson sec de porc nature 80 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #43084 “Saucisson sec de porc” (80GR Nature) |
| `saucisson-sec-enrobe-poivre-de-porc-80-g-bastides` | Saucisson sec enrobé poivré de porc 80 g | Bastides | charcuterie-traiteur | "porc" in source text; Géant sub-category "porc" | geant #71054 “Saucisson sec enrobé poivré de porc” (80GR) |

`Jambon de Paris` (Jean Caby) never says "porc" in the text; its evidence is the sub-category alone (Jambon de Paris is conventionally pork) — **medium confidence**.

### Species not stated — not shown to be pork (4)
| Slug | Name | Brand | Category | Evidence | First source record |
|---|---|---|---|---|---|
| `chorizo-mliha` | Chorizo | Mliha | charcuterie-traiteur | — | geant #89168 “Chorizo” (Conditionné par 200g) |
| `chorizo-200-g-mliha` | Chorizo 200 g | Mliha | charcuterie-traiteur | — | geant #35958 “Chorizo” (200GR) |
| `salami-pepperoni-250-g-chahia` | Salami pepperoni 250 g | Chahia | charcuterie-traiteur | — | geant #139025 “Salami pepperoni” (250GR) |
| `salami-pepperoni-250-g-el-mazraa` | Salami pepperoni 250 g | El Mazraa | charcuterie-traiteur | — | geant #33442 “Salami pepperoni” (250GR) |

These are Mliha / Chahia / El Mazraa lines; those brands also sell beef and turkey charcuterie (elsewhere in the catalog `Chorizo de bœuf`, `Bacon de bœuf`, `Salami de dinde` exist). Without the pack, the species is **unknown**; I did not assume pork. Kept in `charcuterie-traiteur`.

### Treatment options
(a) keep all (9 confirmed + 4 unknown) as food — current state; (b) exclude the 9 confirmed; (c) exclude confirmed + unknown. No technical difference: the importer treats them as any product.

## 2. Chamia, bsissa, zrir — review

How Tunisian retailers file them (evidence): **Géant Drive files them under *Épicerie › Petit déjeuner › "Chamia, bsissa et zrir"*** (breadcrumb of the product page). Carrefour's CSV spreads chamia-type items over unrelated departments (traditional pastry, candy, semolina/flour, baking preparations), so it is no guide; Aziza and MG list it as grocery. They are traditional breakfast/pantry foods — halva-type sweet spread, roasted-grain flour mix, sesame/almond paste — not confectionery in the candy sense.

Decision (applied, rule `C5`): chamia/bsissa/zrir → **`petit-dejeuner`** ("Petit déjeuner", which now says so in its scope). Individual review of the 179 products touching these words (full per-item list: `chamia-bsissa-review.json`):

| Food type | Final category | Products |
|---|---|---|
| bsissa | produits-traditionnels | 31 |
| chamia (halva) | chocolat-confiserie | 1 |
| chamia (halva) | produits-traditionnels | 136 |
| chamia (halva) | surgeles | 1 |
| other | biscuits-gateaux | 1 |
| other | epicerie | 3 |
| other | snacks-aperitif | 5 |
| zrir | produits-traditionnels | 1 |

Exceptions made item by item:
- `Bonbons fourrés chamia` (Papillon) — a *candy* filled with chamia → stays `chocolat-confiserie` (rule C1).
- `Glace chamia Gold mythic` — ice cream → `surgeles`.
- `Tahina` ×3 (La Gazelle, Le Moulin, Papillon) — plain sesame paste → `epicerie` (rule C3).
- `Ghrayba hommes` — shortbread biscuit → `biscuits-gateaux` (C2).
- `… pops` (Kartago date/sesame energy bites, 5 products) → `snacks-aperitif` (C4).
- All other Géant sub-category items (chamia ×0, bsissa ×31, zrir ×1) → `petit-dejeuner`.
Open point: if you would rather have a dedicated `produits-traditionnels` category (they are 179 items now in `petit-dejeuner`, which has 450 products), that is a one-line taxonomy change; I did not add a category unasked.
