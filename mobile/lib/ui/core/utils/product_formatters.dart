import '../../../data/models/sale_unit.dart';

/// French display and input formatting for prices and quantities. Pure
/// functions over the integer model (millimes / base units) — nothing here
/// uses floating point for money.
abstract final class ProductFormat {
  /// `1800` → `1,800 DT` (TND has three decimals).
  static String price(int millimes) => '${_millimesText(millimes)} DT';

  /// `1800`, kg → `1,800 DT / kg`.
  static String pricePerUnit(SaleUnit unit, int millimes) =>
      '${price(millimes)} / ${switch (unit) {
        SaleUnit.piece => 'pièce',
        SaleUnit.kg => 'kg',
        SaleUnit.l => 'L',
      }}';

  /// Label of the price field, adapted to the unit.
  static String priceFieldLabel(SaleUnit unit) => switch (unit) {
    SaleUnit.piece => 'Prix à la pièce (DT)',
    SaleUnit.kg => 'Prix au kilo (DT)',
    SaleUnit.l => 'Prix au litre (DT)',
  };

  /// A quantity in base units, in the most natural unit:
  /// `500` g → `500 g`, `1500` g → `1,5 kg`, `250` mL → `250 mL`, `3` → `3 pièces`.
  static String quantity(SaleUnit unit, int baseQuantity) {
    switch (unit) {
      case SaleUnit.piece:
        return '$baseQuantity ${baseQuantity == 1 ? 'pièce' : 'pièces'}';
      case SaleUnit.kg:
        return baseQuantity < 1000
            ? '$baseQuantity g'
            : '${_thousandths(baseQuantity)} kg';
      case SaleUnit.l:
        return baseQuantity < 1000
            ? '$baseQuantity mL'
            : '${_thousandths(baseQuantity)} L';
    }
  }

  /// What a customer will be able to order, generated from the settings:
  /// `250 g, 500 g, 750 g…`, `1, 2, 3 pièces…`, or the full list when short.
  static String orderablePreview({
    required SaleUnit unit,
    required int min,
    required int step,
    int? max,
    int shown = 3,
  }) {
    if (min <= 0 || step <= 0) {
      return '';
    }
    final total = max == null ? null : (max - min) ~/ step + 1;
    if (total != null && total < 1) {
      return '';
    }
    final count = total == null || total > shown ? shown : total;
    final values = [for (var i = 0; i < count; i++) min + i * step];
    final hasMore = total == null || total > count;

    final list = unit == SaleUnit.piece
        ? '${values.join(', ')} ${values.length == 1 && values.first == 1 ? 'pièce' : 'pièces'}'
        : values.map((v) => quantity(unit, v)).join(', ');
    final upTo = hasMore && max != null
        ? ' jusqu’à ${quantity(unit, max)}'
        : '';
    return '$list${hasMore ? '…' : ''}$upTo';
  }

  /// Parses what an owner types for a price in dinars — `1,8`, `1.800`, `12` —
  /// into millimes without floating point. Returns `null` if it isn't a price
  /// with at most three decimals.
  static int? parseMillimes(String input) {
    final match = RegExp(r'^(\d{1,7})(?:[.,](\d{0,3}))?$')
        .firstMatch(input.trim());
    if (match == null) {
      return null;
    }
    final dinars = int.parse(match.group(1)!);
    final decimals = (match.group(2) ?? '').padRight(3, '0');
    return dinars * 1000 + int.parse(decimals);
  }

  /// `1800` → `1,800`, for pre-filling the price field.
  static String millimesInput(int millimes) => _millimesText(millimes);

  static String _millimesText(int millimes) {
    final dinars = millimes ~/ 1000;
    final rest = (millimes % 1000).toString().padLeft(3, '0');
    return '$dinars,$rest';
  }

  /// `1500` → `1,5`, `1000` → `1`, `1250` → `1,25`.
  static String _thousandths(int value) {
    final whole = value ~/ 1000;
    final fraction = (value % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$whole' : '$whole,$fraction';
  }
}
