import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/store_product_editor_view_model.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/store_product_form_view_model.dart';

import 'fakes.dart';

/// Tomate sold by the kilo at 1,800 DT, by 500 g up to 10 kg (the fixture's
/// default is 500 g min / 500 g step).
StoreProduct _tomatoes({
  bool trackStock = false,
  int? stockQuantity,
  bool isAvailable = true,
  bool isArchived = false,
  int? maxQuantity = 10000,
}) => fakeStoreProduct(
  id: 7,
  trackStock: trackStock,
  stockQuantity: stockQuantity,
  isAvailable: isAvailable,
  isArchived: isArchived,
  maxQuantity: maxQuantity,
);

({StoreProductEditorViewModel vm, FakeStoreProductsRepository repo}) _editor(
  StoreProduct product,
) {
  final repo = FakeStoreProductsRepository(ApiClient(), products: [product]);
  return (
    vm: StoreProductEditorViewModel(
      storeProductsRepository: repo,
      storeProduct: product,
    ),
    repo: repo,
  );
}

void main() {
  group('loading the store product into the form', () {
    test('shows the store configuration, prefilled', () {
      final (:vm, repo: _) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      expect(vm.saleUnit, SaleUnit.kg);
      expect(vm.price, '1,800');
      expect(vm.min, '500');
      expect(vm.step, '500');
      expect(vm.max, '10000');
      expect(vm.trackStock, isTrue);
      expect(vm.stock, '20000');
      expect(vm.isAvailable, isTrue);
      expect(vm.hasErrors, isFalse);
      expect(vm.currentStockText, '20 kg');
    });

    test('no maximum and untracked stock load as blank', () {
      final (:vm, repo: _) = _editor(_tomatoes(maxQuantity: null));

      expect(vm.max, isEmpty);
      expect(vm.trackStock, isFalse);
      expect(vm.stock, isEmpty);
      expect(vm.currentStockText, isNull);
    });

    test('an untouched form has nothing to save and sends nothing', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      expect(vm.hasChanges, isFalse);
      // Even forced, an unchanged form produces no update request.
      expect(await vm.save(), isTrue);
      expect(repo.updateCalls, 0);
      expect(repo.availabilityCalls, 0);
    });
  });

  group('the global product is never part of an update', () {
    test('an update carries only store fields', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      vm
        ..setPrice('2')
        ..setStep('100')
        ..setStock('15000');
      await vm.save();

      final json = repo.lastUpdate!.toJson();
      expect(
        json.keys,
        isNot(
          anyOf(
            contains('name'),
            contains('slug'),
            contains('description'),
            contains('photo'),
            contains('category'),
            contains('categoryId'),
            contains('productId'),
          ),
        ),
      );
      expect(
        json.keys.toSet().difference({
          'priceMillimes',
          'saleUnit',
          'minQuantity',
          'quantityStep',
          'maxQuantity',
          'trackStock',
          'stockQuantity',
          'expectedStockQuantity',
        }),
        isEmpty,
      );
    });

    test('the global product is exposed, unchanged, for display only', () {
      final stored = _tomatoes();
      final (:vm, :repo) = _editor(stored);

      expect(vm.product, same(stored.product));
      expect(repo.updateCalls, 0);
    });
  });

  group('price', () {
    test('editing the price sends only the price', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setPrice('2,5');
      expect(vm.hasChanges, isTrue);
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.toJson(), {'priceMillimes': 2500});
      expect(vm.current.priceMillimes, 2500);
      expect(vm.price, '2,500'); // shown as the backend holds it
    });

    test('a blank, malformed, zero or huge price is refused locally', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      for (final (text, message) in [
        ('', 'Le prix est requis.'),
        ('abc', 'Prix invalide (ex. 1,800).'),
        ('0', 'Le prix doit être supérieur à 0.'),
        ('10000,001', 'Prix trop élevé (maximum 10 000 DT).'),
      ]) {
        vm.setPrice(text);
        expect(await vm.save(), isFalse, reason: text);
        expect(vm.errorFor(StoreProductField.price), message);
      }
      expect(repo.updateCalls, 0);
    });
  });

  group('sale unit', () {
    test('a weighed product may be sold by weight or by the piece', () {
      final (:vm, repo: _) = _editor(_tomatoes());

      expect(vm.allowedUnits, [SaleUnit.kg, SaleUnit.piece]);
    });

    test('a piece product has no other unit to choose', () {
      final (:vm, repo: _) = _editor(fakeEggs());

      expect(vm.allowedUnits, [SaleUnit.piece]);
      vm.selectUnit(SaleUnit.kg); // not allowed: ignored
      expect(vm.saleUnit, SaleUnit.piece);
      expect(vm.hasChanges, isFalse);
    });

    test('switching unit resets the rules, empties price and stock', () {
      final (:vm, repo: _) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      vm.selectUnit(SaleUnit.piece);

      expect(vm.saleUnit, SaleUnit.piece);
      expect(vm.price, isEmpty); // a price per kilo is not a price per piece
      expect(vm.min, '${SaleUnit.piece.defaultStep}');
      expect(vm.step, '${SaleUnit.piece.defaultStep}');
      expect(vm.max, isEmpty);
      expect(vm.stock, isEmpty); // grams are not pieces
      expect(vm.errorFor(StoreProductField.price), isNull); // not shown yet
    });

    test(
      'the new unit is only saved with its price, rules and stock',
      () async {
        final (:vm, :repo) = _editor(
          _tomatoes(trackStock: true, stockQuantity: 20000),
        );

        vm.selectUnit(SaleUnit.piece);
        expect(await vm.save(), isFalse); // price and stock still missing
        expect(repo.updateCalls, 0);

        vm
          ..setPrice('0,4')
          ..setStock('30');
        expect(await vm.save(), isTrue);

        expect(repo.lastUpdate!.toJson(), {
          'priceMillimes': 400,
          'saleUnit': 'PIECE',
          'minQuantity': 1,
          'quantityStep': 1,
          'maxQuantity': null,
          'stockQuantity': 30,
          'expectedStockQuantity': 20000,
        });
        expect(vm.current.saleUnit, SaleUnit.piece);
        expect(vm.current.stockQuantity, 30);
      },
    );

    test('an untracked product changes unit without any stock', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm
        ..selectUnit(SaleUnit.piece)
        ..setPrice('0,4');
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.stock, isNull);
      expect(repo.lastUpdate!.saleUnit, SaleUnit.piece);
    });
  });

  group('quantity rules', () {
    test('changing the step sends the whole rule set', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm
        ..setMin('100')
        ..setStep('100');
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.toJson(), {
        'minQuantity': 100,
        'quantityStep': 100,
        'maxQuantity': 10000,
      });
      expect(vm.current.quantityStep, 100);
    });

    test('a blank maximum is sent as an explicit null', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setMax('');
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.toJson()['maxQuantity'], isNull);
      expect(repo.lastUpdate!.toJson().containsKey('maxQuantity'), isTrue);
      expect(vm.current.maxQuantity, isNull);
    });

    test('a maximum can be added to a product that had none', () async {
      final (:vm, :repo) = _editor(_tomatoes(maxQuantity: null));

      vm.setMax('5000');
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.maxQuantity, 5000);
      expect(vm.current.maxQuantity, 5000);
    });

    test('uses the same validation as quick-add', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setStep('155'); // not a multiple of 10 g
      expect(await vm.save(), isFalse);
      expect(
        vm.errorFor(StoreProductField.step),
        'Utilisez un multiple de 10 g.',
      );

      vm
        ..setStep('300')
        ..setMin('500'); // 500 is not a multiple of 300
      expect(await vm.save(), isFalse);
      expect(
        vm.errorFor(StoreProductField.min),
        'Doit être un multiple de la tranche (300 g).',
      );

      vm
        ..setMin('600')
        ..setMax('300'); // below the minimum
      expect(await vm.save(), isFalse);
      expect(
        vm.errorFor(StoreProductField.max),
        'Doit être au moins égal au minimum.',
      );
      expect(repo.updateCalls, 0);
    });
  });

  group('stock tracking', () {
    test(
      'turning it on sends the stock, checked against "untracked"',
      () async {
        final (:vm, :repo) = _editor(_tomatoes());

        vm
          ..setTrackStock(true)
          ..setStock('8000');
        expect(await vm.save(), isTrue);

        expect(repo.lastUpdate!.toJson(), {
          'trackStock': true,
          'stockQuantity': 8000,
          'expectedStockQuantity': null,
        });
        expect(vm.current.trackStock, isTrue);
        expect(vm.currentStockText, '8 kg');
      },
    );

    test('turning it on requires a stock (0 is allowed)', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setTrackStock(true);
      expect(await vm.save(), isFalse);
      expect(
        vm.errorFor(StoreProductField.stock),
        'Indiquez le stock actuel (0 si épuisé).',
      );
      expect(repo.updateCalls, 0);

      vm.setStock('0');
      expect(await vm.save(), isTrue);
    });

    test(
      'turning it off sends no quantity, checked against the stock',
      () async {
        final (:vm, :repo) = _editor(
          _tomatoes(trackStock: true, stockQuantity: 20000),
        );

        vm.setTrackStock(false);
        expect(await vm.save(), isTrue);

        expect(repo.lastUpdate!.toJson(), {
          'trackStock': false,
          'expectedStockQuantity': 20000,
        });
        expect(vm.current.trackStock, isFalse);
        expect(vm.current.stockQuantity, isNull);
        expect(vm.currentStockText, isNull);
      },
    );

    test('changing the stock sends the new count and the loaded one', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      vm.setStock('12000');
      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.toJson(), {
        'stockQuantity': 12000,
        'expectedStockQuantity': 20000,
      });
      expect(vm.currentStockText, '12 kg');
      expect(vm.knownStock, 12000);
    });

    test('stock is validated for the unit', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      for (final (text, message) in [
        ('', 'Indiquez le stock actuel (0 si épuisé).'),
        ('-5', 'Entrez un nombre entier (0 ou plus).'),
        ('1,5', 'Entrez un nombre entier (0 ou plus).'),
        ('125', 'Utilisez un multiple de 10 g.'),
        ('99999999', 'Maximum 10000 kg.'),
      ]) {
        vm.setStock(text);
        expect(await vm.save(), isFalse, reason: text);
        expect(vm.errorFor(StoreProductField.stock), message, reason: text);
      }
      expect(repo.updateCalls, 0);
    });

    test('with tracking off, stock is ignored and not validated', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setStock('not a number'); // hidden field: must not block or be sent
      vm.setPrice('2');
      expect(vm.stockError, isNull);
      expect(await vm.save(), isTrue);
      expect(repo.lastUpdate!.toJson(), {'priceMillimes': 2000});
    });
  });

  group('zero stock is derived by the backend', () {
    test('stock 0 → "Rupture de stock", the owner switch untouched', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      vm.setStock('0');
      expect(vm.stockNote, contains('indisponible pour les clients'));
      expect(await vm.save(), isTrue);

      expect(vm.current.isOrderable, isFalse);
      expect(vm.current.unavailabilityReason, UnavailabilityReason.outOfStock);
      expect(vm.statusTitle, 'Rupture de stock');
      expect(vm.statusDetail, contains('le stock est à 0'));
      // The owner's own setting is intact — the app never flips it.
      expect(vm.isAvailable, isTrue);
      expect(vm.current.isAvailable, isTrue);
      expect(repo.availabilityCalls, 0);
      expect(repo.lastUpdate!.toJson().containsKey('isAvailable'), isFalse);
    });

    test(
      'adding stock again makes it orderable, as the backend says',
      () async {
        final (:vm, repo: _) = _editor(
          _tomatoes(trackStock: true, stockQuantity: 0),
        );
        expect(vm.statusTitle, 'Rupture de stock');

        vm.setStock('5000');
        await vm.save();

        expect(vm.current.isOrderable, isTrue);
        expect(vm.statusTitle, 'Disponible pour les clients');
        expect(vm.statusDetail, isNull);
      },
    );

    test('untracked stock never makes a product unorderable', () async {
      final (:vm, repo: _) = _editor(_tomatoes());

      vm.setStock('0');
      vm.setPrice('2');
      await vm.save();

      expect(vm.current.isOrderable, isTrue);
    });

    test('stock below the minimum order is explained, not decided here', () {
      final (:vm, repo: _) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );

      vm.setStock('300'); // less than the 500 g minimum
      expect(vm.stockNote, contains('inférieur à la quantité minimale'));
      expect(vm.isAvailable, isTrue);
    });
  });

  group('availability and status', () {
    test('the owner switch is saved through its own endpoint', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm.setAvailable(false);
      expect(vm.hasChanges, isTrue);
      expect(await vm.save(), isTrue);

      expect(repo.availabilityCalls, 1);
      expect(repo.updateCalls, 0);
      expect(vm.current.isAvailable, isFalse);
      expect(vm.statusTitle, 'Désactivé par vous');
      expect(vm.statusDetail, contains('Disponible à la vente'));
    });

    test('price and switch are both saved in one go', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      vm
        ..setPrice('2')
        ..setAvailable(false);
      expect(await vm.save(), isTrue);

      expect(repo.updateCalls, 1);
      expect(repo.availabilityCalls, 1);
      expect(vm.current.priceMillimes, 2000);
      expect(vm.current.isAvailable, isFalse);
    });

    test(
      'if the switch fails after the rest was saved, only it is retried',
      () async {
        final (:vm, :repo) = _editor(_tomatoes());
        repo.availabilityError = const NetworkException('offline');

        vm
          ..setPrice('2')
          ..setAvailable(false);
        expect(await vm.save(), isFalse);

        // The price went through and is now the baseline; the switch is still
        // what the owner chose, waiting to be saved.
        expect(vm.current.priceMillimes, 2000);
        expect(vm.isAvailable, isFalse);
        expect(vm.hasChanges, isTrue);
        expect(vm.errorMessage, contains('Impossible de contacter le serveur'));

        repo.availabilityError = null;
        expect(await vm.save(), isTrue);
        expect(repo.updateCalls, 1); // the price was not sent twice
        expect(repo.availabilityCalls, 2);
        expect(vm.current.isAvailable, isFalse);
      },
    );

    test('every backend reason is told apart in words', () {
      String title(StoreProduct p) => _editor(p).vm.statusTitle;

      expect(title(_tomatoes()), 'Disponible pour les clients');
      expect(title(_tomatoes(isAvailable: false)), 'Désactivé par vous');
      expect(
        title(_tomatoes(trackStock: true, stockQuantity: 0)),
        'Rupture de stock',
      );
      expect(
        title(_tomatoes(trackStock: true, stockQuantity: 100)),
        'Stock insuffisant',
      );
      expect(title(_tomatoes(isArchived: true)), 'Produit archivé');
      expect(
        title(_tomatoes().copyWithReason(UnavailabilityReason.catalogArchived)),
        'Retiré du catalogue',
      );
    });

    test('the owner switch outranks stock in the backend reason', () {
      final (:vm, repo: _) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 0, isAvailable: false),
      );

      expect(vm.statusTitle, 'Désactivé par vous');
      expect(vm.isAvailable, isFalse);
    });
  });

  group('archive and restore', () {
    test('archiving calls the archive endpoint', () async {
      final (:vm, :repo) = _editor(_tomatoes());

      expect(await vm.archive(), isTrue);

      expect(repo.archiveCalls, 1);
      expect(repo.byName('Tomate').isArchived, isTrue);
      expect(vm.didChange, isTrue);
    });

    test('an archived product shows as archived and cannot be saved', () async {
      final (:vm, :repo) = _editor(_tomatoes(isArchived: true));

      expect(vm.isArchived, isTrue);
      expect(vm.statusTitle, 'Produit archivé');
      expect(vm.hasChanges, isFalse);
      vm.setPrice('9');
      expect(vm.hasChanges, isFalse);
      expect(await vm.save(), isFalse);
      expect(await vm.archive(), isFalse);
      expect(repo.updateCalls, 0);
      expect(repo.archiveCalls, 0);
    });

    test('restoring brings back the same store product, no new one', () async {
      final (:vm, :repo) = _editor(_tomatoes(isArchived: true));

      expect(await vm.restore(), isTrue);

      expect(repo.restoreCalls, 1);
      expect(repo.createCalls, 0);
      expect(vm.isArchived, isFalse);
      expect(vm.current.id, 7);
      expect((await repo.list(status: StoreProductStatus.all)).length, 1);
      expect(vm.statusTitle, 'Disponible pour les clients');
      expect(vm.didChange, isTrue);
      // And it is editable again.
      vm.setPrice('3');
      expect(await vm.save(), isTrue);
    });

    test('restoring keeps the configuration it had', () async {
      final (:vm, repo: _) = _editor(
        _tomatoes(isArchived: true, trackStock: true, stockQuantity: 4000),
      );

      await vm.restore();

      expect(vm.price, '1,800');
      expect(vm.stock, '4000');
      expect(vm.trackStock, isTrue);
    });

    test('archive and restore failures are explained and retryable', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      repo.archiveError = const NetworkException('offline');

      expect(await vm.archive(), isFalse);
      expect(vm.errorMessage, contains('Impossible de contacter le serveur'));
      expect(vm.didChange, isFalse);

      repo.archiveError = const ApiException(statusCode: 500, message: 'x');
      expect(await vm.archive(), isFalse);
      expect(
        vm.errorMessage,
        'Impossible d’archiver ce produit. Veuillez réessayer.',
      );

      repo.archiveError = null;
      expect(await vm.archive(), isTrue);
    });

    test('a failed restore leaves it archived', () async {
      final (:vm, :repo) = _editor(_tomatoes(isArchived: true));
      repo.restoreError = const ApiException(statusCode: 500, message: 'x');

      expect(await vm.restore(), isFalse);

      expect(vm.isArchived, isTrue);
      expect(vm.errorMessage, contains('restaurer'));
    });
  });

  group('API errors keep the owner\'s form', () {
    test('a server refusal (400) is explained and nothing is lost', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      repo.updateError = const ApiException(statusCode: 400, message: 'bad');

      vm
        ..setPrice('2')
        ..setStep('100');
      expect(await vm.save(), isFalse);

      expect(vm.errorMessage, contains('Le serveur a refusé ces valeurs'));
      expect(vm.price, '2');
      expect(vm.step, '100');
      expect(vm.hasChanges, isTrue);
      expect(vm.current.priceMillimes, 1800); // nothing applied
    });

    test('a server error and being offline are told apart', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      vm.setPrice('2');

      repo.updateError = const ApiException(statusCode: 500, message: 'x');
      await vm.save();
      expect(vm.errorMessage, contains('Impossible d’enregistrer'));

      repo.updateError = const NetworkException('offline');
      await vm.save();
      expect(vm.errorMessage, contains('Impossible de contacter le serveur'));
      expect(vm.price, '2');
    });

    test('a product archived elsewhere (409) says so', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      repo.updateError = const ApiException(statusCode: 409, message: 'x');

      vm.setPrice('2');
      await vm.save();

      expect(vm.errorMessage, contains('depuis un autre appareil'));
      expect(vm.price, '2');
    });

    test('retrying after an error succeeds and clears it', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      repo.updateError = const NetworkException('offline');
      vm.setPrice('2');
      await vm.save();
      expect(vm.errorMessage, isNotNull);

      repo.updateError = null;
      expect(await vm.save(), isTrue);

      expect(vm.errorMessage, isNull);
      expect(vm.current.priceMillimes, 2000);
    });

    test('editing after an error clears the message', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      repo.updateError = const NetworkException('offline');
      vm.setPrice('2');
      await vm.save();

      vm.setPrice('2,2');

      expect(vm.errorMessage, isNull);
    });

    test('a double tap saves once', () async {
      final (:vm, :repo) = _editor(_tomatoes());
      vm.setPrice('2');

      final results = await Future.wait([vm.save(), vm.save()]);

      expect(results, [true, false]);
      expect(repo.updateCalls, 1);
    });
  });

  group('the stock changed while editing', () {
    test(
      'nothing is applied, the form is kept, the new stock is known',
      () async {
        final (:vm, :repo) = _editor(
          _tomatoes(trackStock: true, stockQuantity: 20000),
        );
        vm
          ..setPrice('2')
          ..setStock('15000');
        repo.changeStockExternally(7, 17000); // an order, meanwhile

        expect(await vm.save(), isFalse);

        expect(vm.hasStockConflict, isTrue);
        expect(vm.knownStock, 17000);
        expect(vm.errorMessage, isNull);
        // What the owner typed is still there, and nothing was applied.
        expect(vm.price, '2');
        expect(vm.stock, '15000');
        expect(vm.current.priceMillimes, 1800);
        expect(vm.current.stockQuantity, 20000);
        expect(vm.hasChanges, isTrue);
        expect(vm.didChange, isFalse);
      },
    );

    test('the owner can adopt the stock the backend holds now', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      vm.setStock('15000');
      repo.changeStockExternally(7, 17000);
      await vm.save();

      vm.useServerStock();

      expect(vm.stock, '17000');
    });

    test('saving again afterwards is checked against the new stock', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      vm.setStock('15000');
      repo.changeStockExternally(7, 17000);
      await vm.save();

      expect(await vm.save(), isTrue);

      expect(repo.lastUpdate!.stock!.expectedStockQuantity, 17000);
      expect(vm.hasStockConflict, isFalse);
      expect(vm.current.stockQuantity, 15000);
    });

    test('a conflict does not repeat once the stock is the same', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      vm.setStock('15000');
      repo.changeStockExternally(7, 15000);

      // The backend refuses (stale expectation); the stock it holds equals
      // what the owner typed, so there is nothing left to change.
      expect(await vm.save(), isFalse);
      expect(vm.hasStockConflict, isTrue);
      expect(await vm.save(), isTrue);
      expect(repo.updateCalls, 1); // refused once; nothing left to send
    });

    test('a refused stock edit does not leave a half-applied price', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      vm
        ..setPrice('9')
        ..setStock('1000');
      repo.changeStockExternally(7, 1);

      await vm.save();

      expect((await repo.get(7)).priceMillimes, 1800);
    });

    test(
      'tracking switched off elsewhere is reported without a quantity',
      () async {
        final (:vm, :repo) = _editor(
          _tomatoes(trackStock: true, stockQuantity: 20000),
        );
        vm.setStock('15000');
        repo.updateError = const StockChangedException();

        await vm.save();

        expect(vm.hasStockConflict, isTrue);
        expect(vm.knownStock, isNull);
        vm.useServerStock(); // nothing to adopt: must not crash or blank it
        expect(vm.stock, '15000');
      },
    );

    test('the conflict flag clears on the next attempt', () async {
      final (:vm, :repo) = _editor(
        _tomatoes(trackStock: true, stockQuantity: 20000),
      );
      vm.setStock('15000');
      repo.updateError = const StockChangedException(currentStockQuantity: 100);
      await vm.save();
      expect(vm.hasStockConflict, isTrue);

      repo.updateError = const NetworkException('offline');
      await vm.save();

      expect(vm.hasStockConflict, isFalse);
      expect(vm.errorMessage, isNotNull);
    });
  });
}

extension on StoreProduct {
  /// The same offering as the backend would describe it when the catalog
  /// archived the product.
  StoreProduct copyWithReason(UnavailabilityReason reason) => StoreProduct(
    id: id,
    product: product,
    saleUnit: saleUnit,
    priceMillimes: priceMillimes,
    minQuantity: minQuantity,
    quantityStep: quantityStep,
    maxQuantity: maxQuantity,
    trackStock: trackStock,
    stockQuantity: stockQuantity,
    isAvailable: isAvailable,
    isOrderable: false,
    unavailabilityReason: reason,
  );
}
