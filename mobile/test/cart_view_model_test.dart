import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/cart_view_model.dart';

import 'fakes.dart';

final _store = fakeCustomerStore(id: 10, name: 'Menzah Market');
final _other = fakeCustomerStore(id: 20, name: 'Lac Épicerie');

void main() {
  group('adding', () {
    test(
      'a product enters the cart at its minimum quantity, for its store',
      () {
        final cart = CartViewModel();
        expect(cart.isEmpty, isTrue);
        expect(cart.store, isNull);

        final result = cart.add(_store, fakeCustomerProduct(id: 1));

        expect(result, CartAddResult.added);
        expect(cart.store?.id, 10);
        expect(cart.lines.single.quantity, 500); // the product's minimum
        expect(cart.quantityOf(1), 500);
        expect(cart.isEmpty, isFalse);
      },
    );

    test('adding a product again does not add a second line or change it', () {
      final cart = CartViewModel()
        ..add(_store, fakeCustomerProduct(id: 1))
        ..increment(1);
      cart.add(_store, fakeCustomerProduct(id: 1));
      expect(cart.lineCount, 1);
      expect(cart.quantityOf(1), 600);
    });

    test('an unavailable product cannot be added', () {
      final cart = CartViewModel();
      final result = cart.add(
        _store,
        fakeCustomerProduct(id: 1, isOrderable: false),
      );
      expect(result, CartAddResult.unavailable);
      expect(cart.isEmpty, isTrue);
      expect(cart.store, isNull);
    });

    test('nothing can be added at a closed store', () {
      final cart = CartViewModel();
      final result = cart.add(
        fakeCustomerStore(isOpen: false),
        fakeCustomerProduct(),
      );
      expect(result, CartAddResult.storeClosed);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('quantity', () {
    test('increments by the product’s step', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.increment(1);
      expect(cart.quantityOf(1), 600);
      cart.increment(1);
      expect(cart.quantityOf(1), 700);
    });

    test('pieces move one at a time', () {
      final cart = CartViewModel()..add(_store, fakeMilk(id: 2));
      expect(cart.quantityOf(2), 1);
      cart.increment(2);
      expect(cart.quantityOf(2), 2);
    });

    test('never goes above the maximum', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      for (var i = 0; i < 100; i++) {
        cart.increment(1);
      }
      expect(cart.quantityOf(1), 5000);
      expect(cart.lines.single.canIncrement, isFalse);
    });

    test('a product with no maximum keeps going', () {
      final cart = CartViewModel()
        ..add(_store, fakeCustomerProduct(id: 1, maxQuantity: null));
      for (var i = 0; i < 100; i++) {
        cart.increment(1);
      }
      expect(cart.quantityOf(1), 500 + 100 * 100);
      expect(cart.lines.single.canIncrement, isTrue);
    });

    test('decrements by one step', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart
        ..increment(1)
        ..increment(1)
        ..decrement(1);
      expect(cart.quantityOf(1), 600);
    });

    test('at the minimum, decrementing removes the line (never below it)', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.decrement(1);
      expect(cart.quantityOf(1), 0);
      expect(cart.isEmpty, isTrue);
    });

    test(
      'quantities are always the minimum plus whole steps within the maximum',
      () {
        final product = fakeCustomerProduct(
          id: 1,
          minQuantity: 250,
          quantityStep: 250,
          maxQuantity: 2000,
        );
        final cart = CartViewModel()..add(_store, product);
        final seen = <int>{cart.quantityOf(1)};
        for (var i = 0; i < 20; i++) {
          cart.increment(1);
          seen.add(cart.quantityOf(1));
        }
        for (var i = 0; i < 20; i++) {
          cart.decrement(1);
          if (cart.quantityOf(1) > 0) {
            seen.add(cart.quantityOf(1));
          }
        }
        expect(seen.toList()..sort(), [
          250,
          500,
          750,
          1000,
          1250,
          1500,
          1750,
          2000,
        ]);
      },
    );

    test('an unknown product is ignored', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart
        ..increment(99)
        ..decrement(99)
        ..remove(99);
      expect(cart.lineCount, 1);
    });
  });

  group('removing and emptying', () {
    test('removing a line keeps the others', () {
      final cart = CartViewModel()
        ..add(_store, fakeCustomerProduct(id: 1))
        ..add(_store, fakeMilk(id: 2));
      cart.remove(1);
      expect(cart.lines.map((l) => l.product.id), [2]);
      expect(cart.store?.id, 10);
    });

    test('removing the last line releases the store', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.remove(1);
      expect(cart.isEmpty, isTrue);
      expect(cart.store, isNull);
    });

    test('clear empties the cart', () {
      final cart = CartViewModel()
        ..add(_store, fakeCustomerProduct(id: 1))
        ..add(_store, fakeMilk(id: 2));
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.store, isNull);
    });
  });

  group('estimated total', () {
    test('is the sum of the line subtotals from the prices loaded', () {
      final cart = CartViewModel()
        ..add(_store, fakeCustomerProduct(id: 1)) // 500 g × 1,800 DT/kg
        ..add(_store, fakeMilk(id: 2)); // 1 × 1,200
      expect(cart.lines[0].subtotalMillimes, 900);
      expect(cart.lines[1].subtotalMillimes, 1200);
      expect(cart.estimatedTotalMillimes, 2100);

      cart.increment(2);
      expect(cart.estimatedTotalMillimes, 3300);
    });

    test('is zero for an empty cart', () {
      expect(CartViewModel().estimatedTotalMillimes, 0);
    });
  });

  group('switching store', () {
    test('an empty cart takes any store without asking', () {
      final cart = CartViewModel();
      expect(cart.add(_store, fakeCustomerProduct(id: 1)), CartAddResult.added);
      cart.clear();
      expect(cart.add(_other, fakeMilk(id: 5)), CartAddResult.added);
      expect(cart.store?.id, 20);
    });

    test('a cart with products asks first and changes nothing', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      final result = cart.add(_other, fakeMilk(id: 5));

      expect(result, CartAddResult.needsStoreSwitch);
      expect(cart.store?.id, 10); // still the current store
      expect(cart.lines.map((l) => l.product.id), [
        1,
      ]); // nothing lost, nothing added
    });

    test('the new store becomes active only after the switch is accepted', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.add(_other, fakeMilk(id: 5));
      expect(cart.store?.id, 10);

      cart.switchStore(_other);

      expect(cart.store?.id, 20);
      expect(cart.isEmpty, isTrue); // the old cart is gone
      expect(cart.add(_other, fakeMilk(id: 5)), CartAddResult.added);
      expect(cart.lines.single.product.id, 5);
    });

    test('adding at the cart’s own store never asks', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      expect(cart.add(_store, fakeMilk(id: 2)), CartAddResult.added);
      expect(cart.lineCount, 2);
    });
  });

  group('keeping up with the catalogue', () {
    test('new prices and rules replace the old ones', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.syncWithCatalog(10, [
        fakeCustomerProduct(id: 1, priceMillimes: 2000),
      ]);
      expect(cart.lines.single.product.priceMillimes, 2000);
      expect(cart.lines.single.subtotalMillimes, 1000);
      expect(cart.hasProblems, isFalse);
    });

    test(
      'a product that became unavailable or vanished is flagged, not dropped',
      () {
        final cart = CartViewModel()
          ..add(_store, fakeCustomerProduct(id: 1))
          ..add(_store, fakeMilk(id: 2));
        cart.syncWithCatalog(10, [
          fakeCustomerProduct(id: 1, isOrderable: false),
        ]);

        expect(cart.lineCount, 2);
        expect(cart.lines[0].problem, CartProblem.unavailable);
        expect(
          cart.lines[1].problem,
          CartProblem.unavailable,
        ); // gone from the store
        expect(cart.hasProblems, isTrue);
      },
    );

    test(
      'a quantity that no longer fits the rules is flagged, then fixable',
      () {
        final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
        cart.syncWithCatalog(10, [
          fakeCustomerProduct(id: 1, minQuantity: 1000, quantityStep: 500),
        ]);
        expect(cart.lines.single.problem, CartProblem.invalidQuantity);

        cart.fixQuantity(1);
        expect(cart.quantityOf(1), 1000);
        expect(cart.hasProblems, isFalse);
      },
    );

    test('another store’s catalogue never touches this cart', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.syncWithCatalog(20, [fakeCustomerProduct(id: 1, priceMillimes: 1)]);
      expect(cart.lines.single.product.priceMillimes, 1800);
    });

    test('the store’s open state can be updated', () {
      final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
      cart.updateStore(_store.copyWith(isOpen: false));
      expect(cart.store?.isOpen, isFalse);
    });
  });

  test('lines know their unit', () {
    final cart = CartViewModel()..add(_store, fakeCustomerProduct(id: 1));
    expect(cart.lines.single.product.saleUnit, SaleUnit.kg);
  });
}
