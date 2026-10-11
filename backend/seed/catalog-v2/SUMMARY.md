# Catalogue v2 — summary after review round 4 / Rev 3.1 (nothing imported)

Generated 2026-10-10. **Status: revised candidate (Rev 3.1 = Rev 3 + review round 4), validated, not imported. No backup, no CLI dry-run, no database write, no migration, no application-code change.** Previous revision preserved in `history/rev2/`; exact diff in `changes-since-rev2.json`.

## Start here
| | |
|---|---|
| **`review-round4.md`** | how the 28 likely-duplicate pairs were decided (17 merged, 11 kept), documentation corrections, validation |
| `review-round3.md` | how each of your 7 decisions was applied, with evidence and the exact changes |
| `changes-since-rev3.json`, `duplicate-review-round4.json` | the 17 round-4 merges and the 28 pair decisions with evidence |
| `changes-since-rev2.json` | every addition / removal / merge / rename / category change since rev 2 |
| `brand-merges.json`, `pair-merges.json`, `variant-restores.json`, `carrefour-sizeless-review.md/.json` | audit trails |
| `catalog.v2.json`, `provenance.json` | the candidate and its sidecar (now with `brandOwnership`) |
| `taxonomy-and-rules.md`, `validation-report.md`, `photo-validation.md`, `impact-existing.md`, `capacity-assessment.md` | regenerated for rev 3 |
| `brand-review.md`, `pork-and-traditional-products.md`, `duplicates-and-classification.md` | round-2 analyses, with a "superseded in part" banner |

## Numbers (Rev 3.1)
| | |
|---|---|
| Products | **5,685** = 42 existing + 5,643 new (rev 2: 5,801; rev 3: 5,702) |
| Brands | **654** (rev 2: 671); 349 products brandless |
| Categories | **18** = 7 existing + 11 new (`produits-traditionnels` added); `viandes-poissons` archived |
| KG / PIECE | 344 / 5,341 (no L) |
| Photos | 5,478 URLs, 207 `null`; 752 visually verified, the rest URL-valid only |
| Per category | `fruits` 19, `legumes` 67, `produits-laitiers` 345, `boulangerie` 132, `epicerie` 1978, `boissons` 628, `viandes` 18, `volaille` 50, `poissons-fruits-de-mer` 88, `fromages` 255, `charcuterie-traiteur` 126, `surgeles` 245, `produits-traditionnels` 212, `petit-dejeuner` 450, `biscuits-gateaux` 525, `chocolat-confiserie` 286, `snacks-aperitif` 261 |
| **Importer parser** | **0 errors** |
| **Importer planner** (read-only dev snapshot) | **0 errors**; products created 5,643 / updated 13 / unchanged 29 / archived 0; categories created 11 / unchanged 6 / archived 1; brands created 654; 1 expected warning (the `viandes-poissons` archive) |

## What changed since rev 2 (headline)
- **Products 5,801 → 5,702 (Rev 3) → 5,685 (Rev 3.1).** Rev 3: 113 merge groups (227 Rev 2 products → 113, net −114), 15 removed, 30 added: 5,801 − 114 − 15 + 30 = 5,702. Round 4: 17 pack-photo-confirmed duplicates merged (−17; 130 groups and net −131 since Rev 2): 5,801 − 131 − 15 + 30 = 5,685. Merge causes are given once per group (exclusive partition) in `changes-since-rev2.json` → `reconciliation`; the overlapping per-cause counts are not additive.
- **Brands 671 → 654**: 15 evidence-backed merges (e.g. Furkitta→Furketta, Nablia→Neblia, the Souani camembert lines → Souani with the line in the name).
- **`produits-traditionnels` created** for chamia, bsissa, zrir, droo/sorgho, assida, mesfouf, zgougou and ground grain/pulse pastes (212 products).
- "Au poids" Carrefour items are now loose KG products (KG 344).

## Still open
1. **Scale** — the API and picker pagination are now implemented (`GET /owner/catalog/browse`, lazy paged picker; see `capacity-assessment.md` status note and `docs/owner-domain.md`). Remaining before import: your approval, the database backup and the CLI dry-run. The catalogue is intentionally not trimmed. Known limitations: paging has no snapshot (rows changed mid-walk can be missed or repeated), no response compression, no on-device measurement.
2. **Tous les jours** (55) — kept, ownership unverified.
3. 4 pork-family products excluded pending species evidence.
4. 143 uncertain pairs remain: 11 were reviewed in round 4 and kept separate for stated reasons, 52 have insufficient evidence, 80 carry a different flavour/type in the name; plus 55 excluded look-alikes (all listed, none merged).
5. Photos not visually verified: 4,726.

## Not done (waiting for your approval)
No database dump, no CLI dry-run, no import.
