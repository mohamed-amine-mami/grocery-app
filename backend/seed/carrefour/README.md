# Carrefour catalog (converted, not imported)

`carrefour_grocergo_catalog.json` is the Carrefour CSV (`carrefour_food_500.csv`, repo root) converted to the
catalog format the existing importer reads. **Nothing here has been imported.** It is separate from
`seed/catalog.json`, which it never replaces.

```bash
npm run catalog:convert-carrefour        # CSV → the three files below (deterministic; no database, no downloads)
npm run catalog:import -- --dry-run --file seed/carrefour/carrefour_grocergo_catalog.json   # what the importer would do
```

| File | What it is |
|---|---|
| `carrefour_grocergo_catalog.json` | `brands`, then `categories[].products[]`, as `parseCatalog` expects |
| `carrefour_grocergo_conversion_report.json` | everything counted, mapped, excluded or flagged; also `skuToSlug` for tracing a product back to Carrefour |
| `carrefour_grocergo_conversion_summary.md` | the short human-readable version |

How a row becomes a product (the code is `scripts/carrefour/lib.ts`, with its tests in `lib.spec.ts`):

- **Name**: trimmed and whitespace-collapsed; an all-capitals name gets normal capitals. Nothing is reworded.
- **Brand**: a blank brand is a brandless product. Spellings that slugify identically share one brand; look-alikes
  (`AL JAZIA` / `AL JAZIRA`) are reported, not merged. The Carrefour spelling is kept as the brand name.
- **Slug**: `slugify(name)` + `-` + `slugify(brand)` (the brand is not repeated when the name already ends with it).
  Accents are removed, `œ`→`oe`, apostrophes dropped. A slug taken twice gets `-2`, `-3`… in SKU order.
- **Category**: Carrefour's breadcrumb → one of 22 flat categories by the rules in `PATH_RULES` (most specific
  wins); a few products are placed by name where the CSV files them wrongly or under a bare root (`NAME_RULES`).
  Six categories keep the slug and name of the development catalog's, so the importer sees them as unchanged.
- **Sale unit**: `UNIT_RULES`, first match wins. `KG` where weight is plausible (a `KG` product can still be sold
  by the piece; a `PIECE` product can never be weighed), `PIECE` for packaged goods, bakery and prepared dishes.
  `L` only for a loose liquid named as such (none in this CSV). Doubtful ones stay in the catalog and are listed
  under `unitClassification.needsReview`.
- **Quantities, price, stock, availability**: not in the file. Minimum, step and maximum are left to the importer's
  per-unit defaults; the rest is the owner's, on the store product.
- **Photo**: the Carrefour `image_url`, unchanged, if it passes the importer's rule. Not downloaded.
- **Not kept**: `sku`, `product_url`, `source` (only in the report).
