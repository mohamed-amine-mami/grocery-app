import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/ui/core/utils/product_formatters.dart';

void main() {
  group('SaleUnit.lineTotalMillimes (same cases as the backend)', () {
    int total(SaleUnit unit, int price, int quantity) =>
        unit.lineTotalMillimes(priceMillimes: price, quantity: quantity);

    test('weighed items are priced from grams', () {
      expect(total(SaleUnit.kg, 1800, 500), 900);
      expect(total(SaleUnit.kg, 1800, 1000), 1800);
      expect(total(SaleUnit.kg, 1800, 1500), 2700);
      expect(total(SaleUnit.kg, 28000, 100), 2800);
      expect(total(SaleUnit.kg, 28000, 300), 8400);
    });

    test('liquids are priced from millilitres, pieces directly', () {
      expect(total(SaleUnit.l, 2400, 250), 600);
      expect(total(SaleUnit.piece, 350, 12), 4200);
      expect(total(SaleUnit.piece, 1350, 1), 1350);
    });

    test('a fractional millime rounds half up', () {
      expect(total(SaleUnit.kg, 1500, 1), 2);
      expect(total(SaleUnit.kg, 1499, 1), 1);
      expect(total(SaleUnit.kg, 1234, 10), 12);
      expect(total(SaleUnit.kg, 1250, 10), 13);
    });

    test('large values stay exact', () {
      expect(total(SaleUnit.kg, 10000000, 100000), 1000000000);
      expect(total(SaleUnit.kg, 2147483647, 99990), 214726889864);
    });

    test('zero quantity is zero, negatives are refused', () {
      expect(total(SaleUnit.kg, 1800, 0), 0);
      expect(() => total(SaleUnit.kg, -1, 100), throwsRangeError);
    });
  });

  group('SaleUnit JSON', () {
    test('round-trips the backend values', () {
      for (final unit in SaleUnit.values) {
        expect(SaleUnit.fromJson(unit.toJson()), unit);
      }
      expect(SaleUnit.fromJson('PIECE'), SaleUnit.piece);
      expect(() => SaleUnit.fromJson('G'), throwsFormatException);
    });
  });

  group('price formatting', () {
    test('uses three decimals and a comma', () {
      expect(ProductFormat.price(1800), '1,800 DT');
      expect(ProductFormat.price(350), '0,350 DT');
      expect(ProductFormat.price(1), '0,001 DT');
      expect(ProductFormat.price(12000), '12,000 DT');
    });

    test('adds the unit', () {
      expect(ProductFormat.pricePerUnit(SaleUnit.kg, 1800), '1,800 DT / kg');
      expect(
        ProductFormat.pricePerUnit(SaleUnit.piece, 350),
        '0,350 DT / pièce',
      );
      expect(ProductFormat.pricePerUnit(SaleUnit.l, 2400), '2,400 DT / L');
    });

    test('the price label adapts to the unit', () {
      expect(ProductFormat.priceFieldLabel(SaleUnit.kg), 'Prix au kilo (DT)');
      expect(ProductFormat.priceFieldLabel(SaleUnit.l), 'Prix au litre (DT)');
      expect(
        ProductFormat.priceFieldLabel(SaleUnit.piece),
        'Prix à la pièce (DT)',
      );
    });
  });

  group('parseMillimes', () {
    test('parses dinars with a comma or a dot', () {
      expect(ProductFormat.parseMillimes('1,8'), 1800);
      expect(ProductFormat.parseMillimes('1.800'), 1800);
      expect(ProductFormat.parseMillimes('12'), 12000);
      expect(ProductFormat.parseMillimes('0,350'), 350);
      expect(ProductFormat.parseMillimes('0,05'), 50);
      expect(ProductFormat.parseMillimes(' 28 '), 28000);
      expect(ProductFormat.parseMillimes('3,'), 3000);
    });

    test('rejects anything that is not a price', () {
      for (final bad in ['', 'abc', '1,2345', '-1', '1,2,3', '1 800', ',5']) {
        expect(ProductFormat.parseMillimes(bad), isNull, reason: bad);
      }
    });

    test('round-trips through the input format', () {
      for (final millimes in [1, 350, 1800, 28000, 9999999]) {
        expect(
          ProductFormat.parseMillimes(ProductFormat.millimesInput(millimes)),
          millimes,
        );
      }
    });
  });

  group('quantity formatting', () {
    test('picks g / kg', () {
      expect(ProductFormat.quantity(SaleUnit.kg, 250), '250 g');
      expect(ProductFormat.quantity(SaleUnit.kg, 500), '500 g');
      expect(ProductFormat.quantity(SaleUnit.kg, 1000), '1 kg');
      expect(ProductFormat.quantity(SaleUnit.kg, 1500), '1,5 kg');
      expect(ProductFormat.quantity(SaleUnit.kg, 1250), '1,25 kg');
      expect(ProductFormat.quantity(SaleUnit.kg, 10000), '10 kg');
    });

    test('picks mL / L', () {
      expect(ProductFormat.quantity(SaleUnit.l, 250), '250 mL');
      expect(ProductFormat.quantity(SaleUnit.l, 1000), '1 L');
      expect(ProductFormat.quantity(SaleUnit.l, 1500), '1,5 L');
    });

    test('pluralizes pieces', () {
      expect(ProductFormat.quantity(SaleUnit.piece, 1), '1 pièce');
      expect(ProductFormat.quantity(SaleUnit.piece, 6), '6 pièces');
    });
  });

  group('orderable quantities preview', () {
    String preview(SaleUnit unit, int min, int step, [int? max]) =>
        ProductFormat.orderablePreview(
          unit: unit,
          min: min,
          step: step,
          max: max,
        );

    test('is generated from the settings, not hard-coded', () {
      expect(preview(SaleUnit.kg, 250, 250), '250 g, 500 g, 750 g…');
      expect(preview(SaleUnit.kg, 500, 500), '500 g, 1 kg, 1,5 kg…');
      expect(preview(SaleUnit.kg, 100, 100), '100 g, 200 g, 300 g…');
      expect(preview(SaleUnit.kg, 1000, 500), '1 kg, 1,5 kg, 2 kg…');
      expect(preview(SaleUnit.l, 250, 250), '250 mL, 500 mL, 750 mL…');
      expect(preview(SaleUnit.piece, 1, 1), '1, 2, 3 pièces…');
      expect(preview(SaleUnit.piece, 6, 6), '6, 12, 18 pièces…');
    });

    test('shows the full list, without an ellipsis, when it is short', () {
      expect(preview(SaleUnit.kg, 500, 500, 1000), '500 g, 1 kg');
      expect(preview(SaleUnit.piece, 1, 1, 2), '1, 2 pièces');
      expect(preview(SaleUnit.piece, 1, 1, 1), '1 pièce');
      expect(preview(SaleUnit.kg, 500, 500, 500), '500 g');
      expect(preview(SaleUnit.kg, 500, 500, 1500), '500 g, 1 kg, 1,5 kg');
    });

    test('names the maximum when the list is longer than what is shown', () {
      expect(
        preview(SaleUnit.kg, 500, 500, 10000),
        '500 g, 1 kg, 1,5 kg… jusqu’à 10 kg',
      );
      expect(
        preview(SaleUnit.piece, 1, 1, 30),
        '1, 2, 3 pièces… jusqu’à 30 pièces',
      );
    });

    test('is empty for unusable settings', () {
      expect(preview(SaleUnit.kg, 0, 500), '');
      expect(preview(SaleUnit.kg, 500, 0), '');
      expect(preview(SaleUnit.kg, 1000, 500, 500), '');
    });
  });
}
