import {
  lineTotalMillimes,
  quantityRuleErrors,
  withQuantityDefaults,
  type QuantityRules,
} from './product-rules.js';
import { SaleUnit } from './sale-unit.enum.js';

const rules = (overrides: Partial<QuantityRules>): QuantityRules => ({
  saleUnit: SaleUnit.KG,
  minQuantity: 500,
  quantityStep: 500,
  maxQuantity: null,
  ...overrides,
});

describe('quantityRuleErrors', () => {
  it.each([
    ['tomatoes by the kg', rules({ maxQuantity: 10_000 })],
    ['cheese by the kg', rules({ minQuantity: 100, quantityStep: 100 })],
    [
      'eggs by the piece',
      rules({ saleUnit: SaleUnit.PIECE, minQuantity: 1, quantityStep: 1 }),
    ],
    [
      'milk by the litre',
      rules({ saleUnit: SaleUnit.L, minQuantity: 250, quantityStep: 250 }),
    ],
    [
      'a minimum of several steps',
      rules({ minQuantity: 1000, quantityStep: 500 }),
    ],
  ])('accepts %s', (_label, input) => {
    expect(quantityRuleErrors(input)).toEqual([]);
  });

  it('rejects non-positive and non-integer values', () => {
    expect(quantityRuleErrors(rules({ minQuantity: 0 }))).toContainEqual(
      expect.stringContaining('minQuantity must be a positive integer'),
    );
    expect(quantityRuleErrors(rules({ quantityStep: -100 }))).toContainEqual(
      expect.stringContaining('quantityStep must be a positive integer'),
    );
    expect(quantityRuleErrors(rules({ minQuantity: 1.5 }))).toContainEqual(
      expect.stringContaining('minQuantity must be a positive integer'),
    );
  });

  it('rejects a minimum that is not a multiple of the step', () => {
    expect(
      quantityRuleErrors(rules({ minQuantity: 600, quantityStep: 500 })),
    ).toEqual(['minQuantity must be a multiple of quantityStep']);
  });

  it('rejects a max below the min or off the step', () => {
    expect(
      quantityRuleErrors(
        rules({ minQuantity: 1000, quantityStep: 500, maxQuantity: 500 }),
      ),
    ).toEqual(['maxQuantity must be greater than or equal to minQuantity']);
    expect(quantityRuleErrors(rules({ maxQuantity: 1250 }))).toContainEqual(
      expect.stringContaining('maxQuantity must be a multiple of'),
    );
  });

  it('accepts a max equal to the min', () => {
    expect(quantityRuleErrors(rules({ maxQuantity: 500 }))).toEqual([]);
  });

  describe('unit-dependent rules', () => {
    it('catches the classic mix-up of typing 1 for one kilo (= 1 gram)', () => {
      const errors = quantityRuleErrors(
        rules({ minQuantity: 1, quantityStep: 1 }),
      );
      expect(errors).toContainEqual(
        expect.stringContaining('multiple of 10 grams'),
      );
    });

    it('applies the same granularity to litres', () => {
      expect(
        quantityRuleErrors(
          rules({ saleUnit: SaleUnit.L, minQuantity: 5, quantityStep: 5 }),
        ),
      ).toContainEqual(expect.stringContaining('multiple of 10 millilitres'));
    });

    it('allows single pieces but not more than the piece ceiling', () => {
      expect(
        quantityRuleErrors(
          rules({ saleUnit: SaleUnit.PIECE, minQuantity: 1, quantityStep: 1 }),
        ),
      ).toEqual([]);
      expect(
        quantityRuleErrors(
          rules({
            saleUnit: SaleUnit.PIECE,
            minQuantity: 1,
            quantityStep: 1,
            maxQuantity: 1001,
          }),
        ),
      ).toContainEqual(expect.stringContaining('at most 1000 pieces'));
    });

    it('caps kilos and litres at 100 000 base units', () => {
      expect(
        quantityRuleErrors(rules({ maxQuantity: 100_500, quantityStep: 500 })),
      ).toContainEqual(expect.stringContaining('at most 100000 grams'));
    });
  });
});

describe('withQuantityDefaults', () => {
  it.each([
    [SaleUnit.PIECE, 1],
    [SaleUnit.KG, 100],
    [SaleUnit.L, 100],
  ])(
    '%s defaults to a step of %i and a minimum of one step',
    (saleUnit, step) => {
      expect(withQuantityDefaults({ saleUnit })).toEqual({
        saleUnit,
        quantityStep: step,
        minQuantity: step,
        maxQuantity: null,
      });
    },
  );

  it('keeps explicit values and defaults the minimum to the given step', () => {
    expect(
      withQuantityDefaults({
        saleUnit: SaleUnit.KG,
        quantityStep: 250,
        maxQuantity: 5000,
      }),
    ).toEqual({
      saleUnit: SaleUnit.KG,
      quantityStep: 250,
      minQuantity: 250,
      maxQuantity: 5000,
    });
  });

  it('every defaulted rule set is itself valid', () => {
    for (const saleUnit of Object.values(SaleUnit)) {
      expect(quantityRuleErrors(withQuantityDefaults({ saleUnit }))).toEqual(
        [],
      );
    }
  });
});

describe('lineTotalMillimes', () => {
  it('prices weighed items from grams: 1.800 DT/kg', () => {
    expect(lineTotalMillimes(SaleUnit.KG, 1800, 500)).toBe(900);
    expect(lineTotalMillimes(SaleUnit.KG, 1800, 1000)).toBe(1800);
    expect(lineTotalMillimes(SaleUnit.KG, 1800, 1500)).toBe(2700);
  });

  it('prices cheese by 100 g steps: 28.000 DT/kg', () => {
    expect(lineTotalMillimes(SaleUnit.KG, 28000, 100)).toBe(2800);
    expect(lineTotalMillimes(SaleUnit.KG, 28000, 300)).toBe(8400);
  });

  it('prices liquids from millilitres', () => {
    expect(lineTotalMillimes(SaleUnit.L, 2400, 250)).toBe(600);
  });

  it('prices pieces directly', () => {
    expect(lineTotalMillimes(SaleUnit.PIECE, 350, 12)).toBe(4200);
    expect(lineTotalMillimes(SaleUnit.PIECE, 1350, 1)).toBe(1350);
  });

  it('rounds a fractional millime half up, deterministically', () => {
    // 1 g at 1500/kg = 1.5 millimes → 2 ; 1 g at 1499/kg = 1.499 → 1
    expect(lineTotalMillimes(SaleUnit.KG, 1500, 1)).toBe(2);
    expect(lineTotalMillimes(SaleUnit.KG, 1499, 1)).toBe(1);
    // 10 g at 1234/kg = 12.34 → 12 ; 10 g at 1250/kg = 12.5 → 13
    expect(lineTotalMillimes(SaleUnit.KG, 1234, 10)).toBe(12);
    expect(lineTotalMillimes(SaleUnit.KG, 1250, 10)).toBe(13);
  });

  it('stays exact where floating point would drift', () => {
    // 0.1 + 0.2 style trouble cannot occur: everything is integer.
    expect(lineTotalMillimes(SaleUnit.KG, 10_000_000, 100_000)).toBe(
      1_000_000_000,
    );
    expect(lineTotalMillimes(SaleUnit.KG, 2_147_483_647, 99_990)).toBe(
      214_726_889_864,
    );
  });

  it('is zero for a zero quantity', () => {
    expect(lineTotalMillimes(SaleUnit.KG, 1800, 0)).toBe(0);
  });

  it('refuses non-integers and negatives', () => {
    expect(() => lineTotalMillimes(SaleUnit.KG, 1.5, 100)).toThrow(RangeError);
    expect(() => lineTotalMillimes(SaleUnit.KG, 1800, 0.5)).toThrow(RangeError);
    expect(() => lineTotalMillimes(SaleUnit.KG, -1, 100)).toThrow(RangeError);
  });
});
