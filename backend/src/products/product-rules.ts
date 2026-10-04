import { SaleUnit } from './sale-unit.enum.js';

/**
 * Pure domain rules for catalog products and store products — no framework,
 * no database — so the same logic backs the catalog, the store's offerings and,
 * later, order items.
 *
 * Model: `priceMillimes` is the price of **one sale unit** (1 piece / 1 kg /
 * 1 L). A quantity is an integer in the unit's base (pieces / grams / mL).
 * The orderable quantities are `minQuantity`, `minQuantity + quantityStep`, …
 * up to `maxQuantity`; `min` and `max` are multiples of `quantityStep`.
 *
 * The same rules apply at two levels: a global catalog product carries default
 * rules, and a store's offering of it (its "store product") carries the rules
 * the store actually sells with. Stock belongs to the store product only.
 */

interface UnitRules {
  /** Base units per sale unit: 1 kg = 1000 g, 1 L = 1000 mL. */
  baseFactor: number;
  /** Quantities must be multiples of this, which stops unit mix-ups (1 "g" typed for 1 kg). */
  granularity: number;
  /** Largest value accepted for min, step or max — a sanity ceiling. */
  cap: number;
  /** Largest stock a store can declare, in base units — a sanity ceiling. */
  stockCap: number;
  defaultStep: number;
}

export const UNIT_RULES: Record<SaleUnit, UnitRules> = {
  [SaleUnit.PIECE]: {
    baseFactor: 1,
    granularity: 1,
    cap: 1_000,
    stockCap: 100_000,
    defaultStep: 1,
  },
  [SaleUnit.KG]: {
    baseFactor: 1000,
    granularity: 10,
    cap: 100_000,
    stockCap: 10_000_000,
    defaultStep: 100,
  },
  [SaleUnit.L]: {
    baseFactor: 1000,
    granularity: 10,
    cap: 100_000,
    stockCap: 10_000_000,
    defaultStep: 100,
  },
};

export interface QuantityRules {
  saleUnit: SaleUnit;
  minQuantity: number;
  quantityStep: number;
  maxQuantity: number | null;
}

/** Fills the optional inputs: the step defaults per unit, the minimum to one step. */
export function withQuantityDefaults(input: {
  saleUnit: SaleUnit;
  minQuantity?: number | null;
  quantityStep?: number | null;
  maxQuantity?: number | null;
}): QuantityRules {
  const quantityStep =
    input.quantityStep ?? UNIT_RULES[input.saleUnit].defaultStep;
  return {
    saleUnit: input.saleUnit,
    quantityStep,
    minQuantity: input.minQuantity ?? quantityStep,
    maxQuantity: input.maxQuantity ?? null,
  };
}

/** Returns every violated rule as a human-readable message; empty means valid. */
export function quantityRuleErrors(rules: QuantityRules): string[] {
  const { saleUnit, minQuantity, quantityStep, maxQuantity } = rules;
  const { granularity, cap } = UNIT_RULES[saleUnit];
  const baseName = { PIECE: 'pieces', KG: 'grams', L: 'millilitres' }[saleUnit];
  const errors: string[] = [];

  const checkBasics = (label: string, value: number) => {
    if (!Number.isInteger(value) || value <= 0) {
      errors.push(`${label} must be a positive integer (in ${baseName})`);
      return false;
    }
    if (value > cap) {
      errors.push(`${label} must be at most ${cap} ${baseName}`);
      return false;
    }
    if (value % granularity !== 0) {
      errors.push(`${label} must be a multiple of ${granularity} ${baseName}`);
      return false;
    }
    return true;
  };

  const minOk = checkBasics('minQuantity', minQuantity);
  const stepOk = checkBasics('quantityStep', quantityStep);
  const maxOk =
    maxQuantity === null ? true : checkBasics('maxQuantity', maxQuantity);

  if (minOk && stepOk && minQuantity % quantityStep !== 0) {
    errors.push('minQuantity must be a multiple of quantityStep');
  }
  if (maxQuantity !== null && minOk && maxOk && maxQuantity < minQuantity) {
    errors.push('maxQuantity must be greater than or equal to minQuantity');
  }
  if (
    maxQuantity !== null &&
    maxOk &&
    stepOk &&
    maxQuantity % quantityStep !== 0
  ) {
    errors.push('maxQuantity must be a multiple of quantityStep');
  }
  return errors;
}

/**
 * Whether a *requested* quantity (base units) can be ordered under a store
 * product's rules: at least the minimum, at most the maximum (if any), and a
 * multiple of the step — the orderable quantities are `min`, `min + step`, ….
 * The rules themselves are assumed valid (see `quantityRuleErrors`). Returns
 * every violated rule; empty means orderable.
 */
export function requestedQuantityErrors(
  quantity: number,
  rules: QuantityRules,
): string[] {
  const { saleUnit, minQuantity, quantityStep, maxQuantity } = rules;
  const baseName = { PIECE: 'pieces', KG: 'grams', L: 'millilitres' }[saleUnit];
  if (!Number.isInteger(quantity) || quantity <= 0) {
    return [`quantity must be a positive integer (in ${baseName})`];
  }
  const errors: string[] = [];
  if (quantity < minQuantity) {
    errors.push(`quantity must be at least ${minQuantity} ${baseName}`);
  }
  if (maxQuantity !== null && quantity > maxQuantity) {
    errors.push(`quantity must be at most ${maxQuantity} ${baseName}`);
  }
  if (quantity % quantityStep !== 0) {
    errors.push(`quantity must be a multiple of ${quantityStep} ${baseName}`);
  }
  return errors;
}

/**
 * The units a store may sell a catalog product in: the product's own default
 * unit, or `PIECE`. A product is never sold in an unrelated unit (bananas are
 * not sold by the litre), and a product that is already counted in pieces
 * (a 1 L bottle of milk) can only be sold in pieces.
 */
export function allowedSaleUnits(defaultSaleUnit: SaleUnit): SaleUnit[] {
  return defaultSaleUnit === SaleUnit.PIECE
    ? [SaleUnit.PIECE]
    : [defaultSaleUnit, SaleUnit.PIECE];
}

export function saleUnitErrors(
  defaultSaleUnit: SaleUnit,
  saleUnit: SaleUnit,
): string[] {
  const allowed = allowedSaleUnits(defaultSaleUnit);
  return allowed.includes(saleUnit)
    ? []
    : [`saleUnit must be one of ${allowed.join(', ')} for this product`];
}

export interface CatalogDefaults {
  defaultSaleUnit: SaleUnit;
  defaultMinQuantity: number;
  defaultQuantityStep: number;
  defaultMaxQuantity: number | null;
}

/**
 * The rules a store product starts with. In the product's default unit they
 * are the catalog defaults; in another unit (bananas by the piece) the catalog
 * numbers are meaningless — 100 would be pieces, not grams — so that unit's own
 * defaults apply instead.
 */
export function storeProductDefaults(
  product: CatalogDefaults,
  saleUnit: SaleUnit = product.defaultSaleUnit,
): QuantityRules {
  if (saleUnit === product.defaultSaleUnit) {
    return {
      saleUnit,
      minQuantity: product.defaultMinQuantity,
      quantityStep: product.defaultQuantityStep,
      maxQuantity: product.defaultMaxQuantity,
    };
  }
  return withQuantityDefaults({ saleUnit });
}

/**
 * Stock is only declared while it is tracked: `trackStock` and `stockQuantity`
 * go together (the database enforces the same pairing). The quantity is in the
 * sale unit's base — pieces / grams / mL — with the same granularity as orders.
 */
export function stockErrors(input: {
  saleUnit: SaleUnit;
  trackStock: boolean;
  stockQuantity: number | null;
}): string[] {
  const { saleUnit, trackStock, stockQuantity } = input;
  if (!trackStock) {
    return stockQuantity === null
      ? []
      : ['stockQuantity must be empty when stock is not tracked'];
  }
  if (stockQuantity === null) {
    return ['stockQuantity is required when stock is tracked'];
  }
  const { granularity, stockCap } = UNIT_RULES[saleUnit];
  const baseName = { PIECE: 'pieces', KG: 'grams', L: 'millilitres' }[saleUnit];
  if (!Number.isInteger(stockQuantity) || stockQuantity < 0) {
    return [`stockQuantity must be a non-negative integer (in ${baseName})`];
  }
  if (stockQuantity > stockCap) {
    return [`stockQuantity must be at most ${stockCap} ${baseName}`];
  }
  if (stockQuantity % granularity !== 0) {
    return [`stockQuantity must be a multiple of ${granularity} ${baseName}`];
  }
  return [];
}

export type UnavailabilityReason =
  /** The store archived this offering. */
  | 'ARCHIVED'
  /** The owner switched it off (`isAvailable = false`). */
  | 'OWNER_DISABLED'
  /** The global product or its category was archived in the catalog. */
  | 'CATALOG_ARCHIVED'
  /** Tracked stock is zero. */
  | 'OUT_OF_STOCK'
  /** Tracked stock is positive but below the minimum order. */
  | 'STOCK_BELOW_MINIMUM';

export interface OrderabilityInput {
  /** The offering itself is not archived. */
  offeringIsActive: boolean;
  isAvailable: boolean;
  productIsActive: boolean;
  categoryIsActive: boolean;
  trackStock: boolean;
  stockQuantity: number | null;
  minQuantity: number;
}

/**
 * Why customers cannot order a store product right now, or `null` when they
 * can. Derived on every read — never stored — so it cannot drift from its
 * inputs. Having stock is not enough: stock below the minimum order cannot
 * satisfy any valid quantity.
 */
export function unavailabilityReason(
  input: OrderabilityInput,
): UnavailabilityReason | null {
  if (!input.offeringIsActive) return 'ARCHIVED';
  if (!input.isAvailable) return 'OWNER_DISABLED';
  if (!input.productIsActive || !input.categoryIsActive) {
    return 'CATALOG_ARCHIVED';
  }
  if (input.trackStock) {
    const stock = input.stockQuantity ?? 0;
    if (stock <= 0) return 'OUT_OF_STOCK';
    if (stock < input.minQuantity) return 'STOCK_BELOW_MINIMUM';
  }
  return null;
}

export function isOrderable(input: OrderabilityInput): boolean {
  return unavailabilityReason(input) === null;
}

/**
 * Price of `quantity` (base units) at `priceMillimes` per sale unit, in whole
 * millimes. Exact integer arithmetic (BigInt, no floats); a fractional
 * millime rounds half up. Example: 1800 millimes/kg × 500 g = 900.
 */
export function lineTotalMillimes(
  saleUnit: SaleUnit,
  priceMillimes: number,
  quantity: number,
): number {
  if (!Number.isInteger(priceMillimes) || priceMillimes < 0) {
    throw new RangeError('priceMillimes must be a non-negative integer');
  }
  if (!Number.isInteger(quantity) || quantity < 0) {
    throw new RangeError('quantity must be a non-negative integer');
  }
  const factor = BigInt(UNIT_RULES[saleUnit].baseFactor);
  const exactTimesFactor = BigInt(priceMillimes) * BigInt(quantity);
  return Number((2n * exactTimesFactor + factor) / (2n * factor));
}
