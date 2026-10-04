/**
 * How a product is sold — the catalog product's default, and the unit a store
 * actually sells it in. Quantities are integers in the unit's *base*:
 * PIECE → pieces, KG → grams, L → millilitres. Packaging words (bottle, pack,
 * box, dozen) are deliberately not units — they belong in the product name.
 */
export enum SaleUnit {
  PIECE = 'PIECE',
  KG = 'KG',
  L = 'L',
}
