# tools/ — snapshots of the scripts that produced catalog.v2.json

These are **provenance snapshots**, not part of the application build or `npm run` scripts. Paths inside them point at the scratch
workspace used on 2026-10-10 (raw crawls were not kept in the repo; `sources/` holds the small ones). Order they ran in:

1. `crawl_gd.py`, `crawl_gd2.py` (Géant Drive category pages, 0.8 s between requests), `fetch_trunc.py` (full names/descriptions of truncated listings),
   `crawl_mg.py` (mg.tn), `crawl_off.py` (Open Food Facts API; throttled), Aziza rows were read from the rendered page and saved as `sources/aziza_raw_food.tsv`.
2. `build_candidates.py` → `build_groups.py` (normalise, classify, merge exact duplicates, existing-slug identity, slugs, units).
3. `photos_check.py` (URL validity of every candidate), `photos_sample.py` (contact sheets for visual review — verdicts were recorded by hand).
4. `finalize.py` (assemble catalog + provenance + photo data), `validate.mjs` (real importer `parseCatalog`/`planCatalog`, no database), `write_reports.py`.

`taxonomy.py` is the category map and category list; `textlib.py` holds size parsing and text normalisation.
