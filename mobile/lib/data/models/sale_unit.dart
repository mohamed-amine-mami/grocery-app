/// Mirrors the backend's `SaleUnit` (`backend/src/products/sale-unit.enum.ts`).
///
/// The price is for ONE sale unit (1 piece / 1 kg / 1 L). Quantities are
/// integers in the unit's *base*: pieces, grams, millilitres.
enum SaleUnit {
  piece(baseFactor: 1, granularity: 1, cap: 1000, defaultStep: 1),
  kg(baseFactor: 1000, granularity: 10, cap: 100000, defaultStep: 100),
  l(baseFactor: 1000, granularity: 10, cap: 100000, defaultStep: 100);

  const SaleUnit({
    required this.baseFactor,
    required this.granularity,
    required this.cap,
    required this.defaultStep,
  });

  /// Base units per sale unit: 1 kg = 1000 g, 1 L = 1000 mL.
  final int baseFactor;

  /// Quantities must be multiples of this (same rule as the backend).
  final int granularity;

  /// Largest accepted min / step / max, in base units.
  final int cap;
  final int defaultStep;

  static SaleUnit fromJson(String value) => switch (value) {
    'PIECE' => SaleUnit.piece,
    'KG' => SaleUnit.kg,
    'L' => SaleUnit.l,
    _ => throw FormatException('Unknown sale unit: $value'),
  };

  String toJson() => switch (this) {
    SaleUnit.piece => 'PIECE',
    SaleUnit.kg => 'KG',
    SaleUnit.l => 'L',
  };

  /// Price of [quantity] base units, in whole millimes. Exact integer
  /// arithmetic — no floating point; a fractional millime rounds half up.
  /// Identical to the backend's `lineTotalMillimes`, so what the owner previews
  /// is what an order will later charge. 1800 millimes/kg × 500 g = 900.
  int lineTotalMillimes({required int priceMillimes, required int quantity}) {
    if (priceMillimes < 0 || quantity < 0) {
      throw RangeError('priceMillimes and quantity must not be negative');
    }
    return (2 * priceMillimes * quantity + baseFactor) ~/ (2 * baseFactor);
  }
}
