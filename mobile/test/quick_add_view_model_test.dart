import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/catalog_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/store_product.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/quick_add_view_model.dart';
import 'package:grocery_mobile/ui/features/catalog/view_models/store_product_form_view_model.dart';

import 'fakes.dart';

/// Tomate: sold by the kilo, 500 g minimum, by 100 g, up to 10 kg.
final _weighed = fakeCatalogProduct();

/// Œufs: counted in pieces only.
final _pieces = fakeCatalogProduct(
  id: 5,
  slug: 'oeufs',
  name: 'Œufs',
  unit: SaleUnit.piece,
  min: 1,
  step: 1,
  max: null,
);

FakeStoreProductsRepository _repository() => FakeStoreProductsRepository(
  ApiClient(),
  catalog: [
    for (final p in [_weighed, _pieces])
      CatalogItem(product: p, inMyStore: false, storeProductArchived: false),
  ],
);

QuickAddViewModel _viewModel(
  CatalogProduct product, [
  FakeStoreProductsRepository? repository,
]) => QuickAddViewModel(
  storeProductsRepository: repository ?? _repository(),
  product: product,
);

/// A form that is valid except for what a test changes.
QuickAddViewModel _filled(
  CatalogProduct product,
  FakeStoreProductsRepository repo,
) => _viewModel(product, repo)..setPrice('1,8');

void main() {
  group('prefill from the catalog', () {
    test('a weighed product starts in its default unit with its rules', () {
      final vm = _viewModel(_weighed);

      expect(vm.saleUnit, SaleUnit.kg);
      expect(vm.min, '500');
      expect(vm.step, '100');
      expect(vm.max, '10000');
      expect(vm.price, isEmpty); // the one thing the owner types
      expect(vm.trackStock, isFalse);
      expect(vm.isAvailable, isTrue);
      expect(vm.stock, isEmpty);
      expect(vm.hasErrors, isTrue); // only because the price is missing
      expect(vm.errorFor(StoreProductField.price), isNull); // …not shown yet
    });

    test(
      'a piece-counted product starts with piece defaults and no maximum',
      () {
        final vm = _viewModel(_pieces);

        expect(vm.saleUnit, SaleUnit.piece);
        expect(vm.allowedUnits, [SaleUnit.piece]);
        expect(vm.min, '1');
        expect(vm.step, '1');
        expect(vm.max, isEmpty);
      },
    );

    test('shows what the catalog suggests, read-only', () {
      expect(
        _viewModel(_weighed).catalogRulesPreview,
        '500 g, 600 g, 700 g… jusqu’à 10 kg',
      );
      expect(_viewModel(_pieces).catalogRulesPreview, '1, 2, 3 pièces…');
    });

    test('names the base unit quantities are typed in', () {
      expect(_viewModel(_weighed).baseUnitName, 'g');
      expect(_viewModel(_pieces).baseUnitName, 'pièces');
    });
  });

  group('unit', () {
    test('a weighed product may be sold by the kilo or by the piece', () {
      expect(_viewModel(_weighed).allowedUnits, [SaleUnit.kg, SaleUnit.piece]);
    });

    test(
      'switching to pieces uses the piece defaults, not the gram numbers',
      () {
        final vm = _viewModel(_weighed)..selectUnit(SaleUnit.piece);

        expect(vm.saleUnit, SaleUnit.piece);
        expect(vm.min, '1');
        expect(vm.step, '1');
        expect(vm.max, isEmpty);
        expect(vm.baseUnitName, 'pièces');
        expect(vm.hasErrors, isTrue); // price still missing
        vm.setPrice('0,5');
        expect(vm.hasErrors, isFalse);
      },
    );

    test('switching back restores the catalog defaults', () {
      final vm = _viewModel(_weighed)
        ..selectUnit(SaleUnit.piece)
        ..selectUnit(SaleUnit.kg);

      expect(vm.min, '500');
      expect(vm.step, '100');
      expect(vm.max, '10000');
    });

    test('an unrelated unit is refused', () {
      final vm = _viewModel(_weighed)..selectUnit(SaleUnit.l);

      expect(vm.saleUnit, SaleUnit.kg);
      expect(vm.min, '500');
    });

    test('a piece-only product cannot be sold by weight', () {
      final vm = _viewModel(_pieces)
        ..selectUnit(SaleUnit.kg)
        ..selectUnit(SaleUnit.l);

      expect(vm.saleUnit, SaleUnit.piece);
    });

    test('changing the unit makes the owner type the stock again', () {
      final vm = _viewModel(_weighed)
        ..setTrackStock(true)
        ..setStock('20000')
        ..selectUnit(SaleUnit.piece);

      expect(vm.stock, isEmpty);
      expect(vm.trackStock, isTrue);
      expect(vm.stockError, 'Indiquez le stock actuel (0 si épuisé).');
    });

    test('rules are checked in the unit that is selected', () {
      final vm = _viewModel(_weighed)..setPrice('1');
      vm.setStep('5'); // fine for pieces, not for grams
      expect(vm.stepError, 'Utilisez un multiple de 10 g.');

      vm.selectUnit(SaleUnit.piece);
      vm.setStep('5');
      vm.setMin('5');
      expect(vm.stepError, isNull);
    });
  });

  group('price validation', () {
    String? errorFor(String text) =>
        (_viewModel(_weighed)..setPrice(text)).priceError;

    test('is required', () {
      expect(errorFor(''), 'Le prix est requis.');
      expect(errorFor('   '), 'Le prix est requis.');
    });

    test('rejects what is not a price', () {
      expect(errorFor('abc'), 'Prix invalide (ex. 1,800).');
      expect(errorFor('1,2345'), 'Prix invalide (ex. 1,800).'); // 4 decimals
      expect(errorFor('-3'), 'Prix invalide (ex. 1,800).');
      expect(errorFor('1,8,2'), 'Prix invalide (ex. 1,800).');
    });

    test('must be above zero', () {
      expect(errorFor('0'), 'Le prix doit être supérieur à 0.');
      expect(errorFor('0,000'), 'Le prix doit être supérieur à 0.');
    });

    test('has a sanity ceiling', () {
      expect(errorFor('10000,001'), 'Prix trop élevé (maximum 10 000 DT).');
      expect(errorFor('10000'), isNull);
    });

    test('accepts the ways owners write a price', () {
      for (final text in ['1,8', '1.800', '12', '0,350', ' 4,5 ']) {
        expect(errorFor(text), isNull, reason: text);
      }
    });

    test('parses to exact millimes — no floating point', () {
      final repo = _repository();
      final vm = _viewModel(_weighed, repo)..setPrice('1,8');

      vm.submit();

      expect(repo.lastCreate!.priceMillimes, 1800);
    });

    test('an untouched form shows no errors until the owner interacts', () {
      final vm = _viewModel(_weighed);
      expect(vm.errorFor(StoreProductField.price), isNull);

      vm.setPrice('');
      expect(vm.errorFor(StoreProductField.price), 'Le prix est requis.');
    });
  });

  group('quantity rule validation', () {
    QuickAddViewModel vm() => _viewModel(_weighed)..setPrice('1');

    test('the catalog defaults are valid', () {
      expect(vm().hasErrors, isFalse);
    });

    test('step and minimum are required', () {
      expect((vm()..setStep('')).stepError, 'La tranche est requise.');
      expect((vm()..setMin('')).minError, 'Le minimum est requis.');
    });

    test('quantities are whole numbers above zero', () {
      for (final text in ['0', '-100', '1.5', 'abc']) {
        expect(
          (vm()..setStep(text)).stepError,
          'Entrez un nombre entier supérieur à 0.',
          reason: text,
        );
      }
    });

    test('weights must be multiples of 10 g — the 1-vs-1000 mix-up guard', () {
      expect((vm()..setStep('15')).stepError, 'Utilisez un multiple de 10 g.');
      expect((vm()..setMin('505')).minError, 'Utilisez un multiple de 10 g.');
    });

    test('quantities have a ceiling per unit', () {
      expect((vm()..setStep('100010')).stepError, 'Maximum 100 kg.');
      final pieces = _viewModel(_pieces)..setMax('1001');
      expect(pieces.maxError, 'Maximum 1000 pièces.');
    });

    test('the minimum must be a multiple of the step', () {
      final v = vm()
        ..setStep('250')
        ..setMin('600');
      expect(v.minError, 'Doit être un multiple de la tranche (250 g).');
    });

    test('the maximum is optional; blank means no maximum', () {
      expect((vm()..setMax('')).maxError, isNull);
      expect((vm()..setMax('   ')).maxError, isNull);
    });

    test('the maximum must reach the minimum and sit on the step', () {
      expect(
        (vm()..setMax('400')).maxError,
        'Doit être au moins égal au minimum.',
      );
      expect(
        (vm()..setMax('10050')).maxError,
        'Doit être un multiple de la tranche (100 g).',
      );
      expect((vm()..setMax('500')).maxError, isNull);
    });

    test('piece quantities accept single pieces', () {
      final v = _viewModel(_pieces)
        ..setPrice('0,35')
        ..setMax('12');
      expect(v.hasErrors, isFalse);
    });

    test('tells the sheet when an error is inside the collapsed section', () {
      expect(vm().advancedHasError, isFalse);
      expect((vm()..setStep('15')).advancedHasError, isTrue);
      // A price error is not "advanced".
      expect(_viewModel(_weighed).advancedHasError, isFalse);
    });
  });

  group('stock validation', () {
    QuickAddViewModel vm() => _viewModel(_weighed)
      ..setPrice('1')
      ..setTrackStock(true);

    test('is ignored while stock is not tracked', () {
      final v = _viewModel(_weighed)
        ..setPrice('1')
        ..setStock('garbage');
      expect(v.stockError, isNull);
      expect(v.hasErrors, isFalse);
    });

    test('is required once tracking is on — zero is a valid answer', () {
      expect(vm().stockError, 'Indiquez le stock actuel (0 si épuisé).');
      expect((vm()..setStock('0')).stockError, isNull);
    });

    test('is a whole number, zero or more', () {
      for (final text in ['-1', '1.5', 'abc']) {
        expect(
          (vm()..setStock(text)).stockError,
          'Entrez un nombre entier (0 ou plus).',
          reason: text,
        );
      }
    });

    test('follows the unit: weights in multiples of 10 g, pieces singly', () {
      expect(
        (vm()..setStock('15')).stockError,
        'Utilisez un multiple de 10 g.',
      );
      expect((vm()..setStock('20000')).stockError, isNull);

      final pieces = _viewModel(_pieces)
        ..setPrice('1')
        ..setTrackStock(true)
        ..setStock('12');
      expect(pieces.stockError, isNull);
    });

    test('has a ceiling per unit', () {
      expect((vm()..setStock('10000010')).stockError, startsWith('Maximum'));
      final pieces = _viewModel(_pieces)
        ..setTrackStock(true)
        ..setStock('100001');
      expect(pieces.stockError, startsWith('Maximum'));
    });

    test('turning tracking off removes the requirement', () {
      final v = vm();
      expect(v.hasErrors, isTrue);

      v.setTrackStock(false);

      expect(v.hasErrors, isFalse);
    });
  });

  group('zero stock', () {
    QuickAddViewModel vm({String stock = '0'}) => _viewModel(_weighed)
      ..setPrice('1')
      ..setTrackStock(true)
      ..setStock(stock);

    test('explains that customers will not be able to order it', () {
      expect(
        vm().stockNote,
        'Stock à 0 : le produit sera indisponible pour les clients tant que '
        'vous n’aurez pas ajouté de stock.',
      );
    });

    test('also explains stock below the minimum order', () {
      expect(
        vm(stock: '50').stockNote,
        'Stock inférieur à la quantité minimale : le produit restera '
        'indisponible pour les clients.',
      );
    });

    test('has no note when there is enough stock, or none is tracked', () {
      expect(vm(stock: '5000').stockNote, isNull);
      expect(
        (_viewModel(_weighed)..setStock('0')).stockNote,
        isNull,
      ); // not tracking
    });

    test(
      'the app never flips availability itself — the backend derives it',
      () {
        final v = vm();

        expect(v.isAvailable, isTrue);
        v.setTrackStock(true);
        expect(v.isAvailable, isTrue);
      },
    );

    test(
      'creating with zero stock comes back unorderable, switch still on',
      () async {
        final repo = _repository();
        final v = _viewModel(_weighed, repo)
          ..setPrice('1,8')
          ..setTrackStock(true)
          ..setStock('0');

        final outcome = await v.submit();

        expect(repo.lastCreate!.trackStock, isTrue);
        expect(repo.lastCreate!.stockQuantity, 0);
        expect(repo.lastCreate!.isAvailable, isTrue);
        final created = outcome!.created!;
        expect(created.isAvailable, isTrue);
        expect(created.isOrderable, isFalse);
        expect(created.unavailabilityReason, UnavailabilityReason.outOfStock);
      },
    );
  });

  group('submitting', () {
    test(
      'an invalid form never reaches the backend, and shows its errors',
      () async {
        final repo = _repository();
        final vm = _viewModel(_weighed, repo)..setStep('15');

        final outcome = await vm.submit();

        expect(outcome, isNull);
        expect(repo.createCalls, 0);
        expect(vm.errorFor(StoreProductField.price), 'Le prix est requis.');
        expect(
          vm.errorFor(StoreProductField.step),
          'Utilisez un multiple de 10 g.',
        );
        expect(vm.errorMessage, isNull);
        expect(vm.isBusy, isFalse);
      },
    );

    test(
      'adds the product with the catalog defaults and the typed price',
      () async {
        final repo = _repository();
        final vm = _filled(_weighed, repo);

        final outcome = await vm.submit();

        final sent = repo.lastCreate!;
        expect(sent.productId, _weighed.id);
        expect(sent.priceMillimes, 1800);
        expect(sent.saleUnit, SaleUnit.kg);
        expect(sent.minQuantity, 500);
        expect(sent.quantityStep, 100);
        expect(sent.maxQuantity, 10000);
        expect(sent.noMaximum, isFalse);
        expect(sent.trackStock, isFalse);
        expect(sent.stockQuantity, isNull);
        expect(sent.isAvailable, isTrue);
        expect(outcome!.created!.product.slug, 'tomate');
        expect(outcome.conflict, isFalse);
        expect(vm.isBusy, isFalse);
        expect(vm.errorMessage, isNull);
      },
    );

    test('sends exactly what the owner configured', () async {
      final repo = _repository();
      final vm = _viewModel(_weighed, repo)
        ..setPrice('0,5')
        ..selectUnit(SaleUnit.piece)
        ..setMin('2')
        ..setStep('2')
        ..setMax('')
        ..setTrackStock(true)
        ..setStock('30')
        ..setAvailable(false);

      await vm.submit();

      final sent = repo.lastCreate!;
      expect(sent.saleUnit, SaleUnit.piece);
      expect(sent.priceMillimes, 500);
      expect(sent.minQuantity, 2);
      expect(sent.quantityStep, 2);
      expect(sent.maxQuantity, isNull);
      expect(
        sent.noMaximum,
        isTrue,
      ); // cleared on purpose, not "use the default"
      expect(sent.trackStock, isTrue);
      expect(sent.stockQuantity, 30);
      expect(sent.isAvailable, isFalse);
    });

    test(
      'sends no stock when stock is not tracked, even if one was typed',
      () async {
        final repo = _repository();
        final vm = _filled(_weighed, repo)
          ..setStock('5000')
          ..setTrackStock(false);

        await vm.submit();

        expect(repo.lastCreate!.trackStock, isFalse);
        expect(repo.lastCreate!.stockQuantity, isNull);
      },
    );

    test('a double tap adds the product once', () async {
      final repo = _repository();
      final vm = _filled(_weighed, repo);

      final first = vm.submit();
      final second = await vm.submit();
      await first;

      expect(second, isNull);
      expect(repo.createCalls, 1);
    });

    test('is busy while the request runs', () async {
      final vm = _filled(_weighed, _repository());
      final states = <bool>[];
      vm.addListener(() => states.add(vm.isBusy));

      await vm.submit();

      expect(states.first, isTrue);
      expect(states.last, isFalse);
    });
  });

  group('duplicate product', () {
    test(
      'a product the store already sells is a conflict, not an error',
      () async {
        final repo = FakeStoreProductsRepository(
          ApiClient(),
          products: [fakeStoreProduct(id: 40, product: _weighed)],
          catalog: [fakeCatalogItem(id: 1, name: 'Tomate')],
        );
        final vm = _filled(_weighed, repo);

        final outcome = await vm.submit();

        expect(outcome!.conflict, isTrue);
        expect(outcome.created, isNull);
        expect(vm.errorMessage, isNull);
        expect(vm.isBusy, isFalse);
      },
    );

    test('a product the catalog removed is also a conflict (404)', () async {
      final repo = _repository()
        ..createError = const ApiException(statusCode: 404);
      final vm = _filled(_weighed, repo);

      expect((await vm.submit())!.conflict, isTrue);
    });
  });

  group('API errors', () {
    Future<QuickAddViewModel> failedWith(Object error) async {
      final repo = _repository()..createError = error;
      final vm = _filled(_weighed, repo);
      expect(await vm.submit(), isNull);
      return vm;
    }

    test(
      'the server refusing the values is explained, and the form stays',
      () async {
        final vm = await failedWith(const ApiException(statusCode: 400));

        expect(
          vm.errorMessage,
          'Le serveur a refusé ces valeurs. Vérifiez le prix, les quantités et '
          'le stock.',
        );
        expect(vm.isBusy, isFalse);
        expect(vm.price, '1,8'); // nothing the owner typed is lost
      },
    );

    test('a server failure is retryable', () async {
      final vm = await failedWith(const ApiException(statusCode: 500));

      expect(
        vm.errorMessage,
        'Impossible d’ajouter le produit. Veuillez réessayer.',
      );
    });

    test('being offline is its own message', () async {
      final vm = await failedWith(const NetworkException('offline'));

      expect(
        vm.errorMessage,
        'Impossible de contacter le serveur. Vérifiez votre connexion.',
      );
    });

    test('an expired session is a generic failure, not a crash', () async {
      final vm = await failedWith(const ApiException(statusCode: 401));

      expect(vm.errorMessage, startsWith('Impossible d’ajouter'));
    });

    test('retrying after an error works, and clears the message', () async {
      final repo = _repository()
        ..createError = const NetworkException('offline');
      final vm = _filled(_weighed, repo);
      await vm.submit();
      expect(vm.errorMessage, isNotNull);

      repo.createError = null;
      final outcome = await vm.submit();

      expect(outcome!.created, isNotNull);
      expect(vm.errorMessage, isNull);
    });

    test('editing a field clears the error', () async {
      final vm = await failedWith(const NetworkException('offline'));

      vm.setPrice('2');

      expect(vm.errorMessage, isNull);
    });
  });
}
