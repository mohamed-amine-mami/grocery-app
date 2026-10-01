import { SaleUnit } from './sale-unit.enum.js';

/**
 * Pure product domain rules — no framework, no database — so the same logic
 * can back the catalog now and order items later.
 *
 * Model: `priceMillimes` is the price of **one sale unit** (1 piece / 1 kg /
 * 1 L). A quantity is an integer in the unit's base (pieces / grams / mL).
 * The orderable quantities are `minQuantity`, `minQuantity + quantityStep`, …
 * up to `maxQuantity`; `min` and `max` are multiples of `quantityStep`.
 */

interface UnitRules {
  /** Base units per sale unit: 1 kg = 1000 g, 1 L = 1000 mL. */
  baseFactor: number;
  /** Quantities must be multiples of this, which stops unit mix-ups (1 "g" typed for 1 kg). */
  granularity: number;
  /** Largest value accepted for min, step or max — a sanity ceiling. */
  cap: number;
  defaultStep: number;
}

export const UNIT_RULES: Record<SaleUnit, UnitRules> = {
  [SaleUnit.PIECE]: {
    baseFactor: 1,
    granularity: 1,
    cap: 1_000,
    defaultStep: 1,
  },
  [SaleUnit.KG]: {
    baseFactor: 1000,
    granularity: 10,
    cap: 100_000,
    defaultStep: 100,
  },
  [SaleUnit.L]: {
    baseFactor: 1000,
    granularity: 10,
    cap: 100_000,
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
