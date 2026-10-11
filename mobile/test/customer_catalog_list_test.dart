import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/brand.dart';
import 'package:grocery_mobile/data/models/catalog_category.dart';
import 'package:grocery_mobile/data/models/customer_product.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/widgets/product_image.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';

import 'fakes.dart';

const _heinz = Brand(id: 1, slug: 'heinz', name: 'Heinz');
const _amora = Brand(id: 2, slug: 'amora', name: 'Amora');
const _sauces = CategoryRef(id: 7, slug: '', name: 'Sauces');
const _spices = CategoryRef(id: 8, slug: '', name: 'Épices');
const _photo = 'https://res.example/f_auto,q_auto/v1/heinz.jpg';

CustomerProduct _ketchup({
  required int id,
  Brand? brand,
  String? photo,
  bool isOrderable = true,
  String name = 'Ketchup',
  int minQuantity = 1,
  int step = 1,
  SaleUnit unit = SaleUnit.piece,
  int? max = 12,
  CategoryRef category = _sauces,
}) => fakeCustomerProduct(
  id: id,
  name: name,
  brand: brand,
  photo: photo,
  category: category,
  unit: unit,
  priceMillimes: 2500,
  minQuantity: minQuantity,
  quantityStep: step,
  maxQuantity: max,
  isOrderable: isOrderable,
);

/// A signed-in customer inside the Menzah Market catalogue, on a phone-sized
/// screen (400 × 3000 logical pixels, so the whole list is in view).
Future<FakeCustomerStoresRepository> _open(
  WidgetTester tester,
  List<CustomerProduct> products, {
  Size size = const Size(400, 3000),
  bool isOpen = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repository = FakeCustomerStoresRepository(
    ApiClient(),
    stores: [fakeCustomerStore(id: 10, name: 'Menzah Market', isOpen: isOpen)],
    products: {10: products},
  );
  await pumpAppSignedInAs(
    tester,
    testClient,
    storeRepository: FakeStoreRepository.new,
    customerStoresRepository: (_) => repository,
  );
  await tester.tap(find.text('Menzah Market'));
  await tester.pumpAndSettle();
  return repository;
}

/// The row of product [id] (every row carries its product's key).
Finder _row(int id) => find.byKey(ValueKey(id));

Finder _in(int id, Finder matching) =>
    find.descendant(of: _row(id), matching: matching);

/// [text] shown in a product row (not, say, typed in the search field).
Finder _inList(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w.key is ValueKey<int>),
  matching: find.text(text),
);

Finder _tab(String label) => find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.text(label),
);

void main() {
  // Phone-width layouts depend on real glyph widths (the test font would make
  // every letter a full em wide).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  group('the store band', () {
    testWidgets('names the store, says open and gives the address', (
      tester,
    ) async {
      await _open(tester, [_ketchup(id: 1)]);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('Ouvert'), findsOneWidget);
      expect(find.text('12 Rue de la Liberté, Tunis'), findsOneWidget);
      // White on the brand colour, the screen's one large green surface.
      final band = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Menzah Market'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(band.color, AppColors.primary);
      expect(
        tester.widget<Text>(find.text('Menzah Market')).style?.color,
        Colors.white,
      );
    });

    testWidgets('the placeholder address is not shown', (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeCustomerStoresRepository(
        ApiClient(),
        stores: [
          fakeCustomerStore(
            id: 10,
            name: 'Menzah Market',
            address: 'Adresse à renseigner',
          ),
        ],
        products: {
          10: [_ketchup(id: 1)],
        },
      );
      await pumpAppSignedInAs(
        tester,
        testClient,
        storeRepository: FakeStoreRepository.new,
        customerStoresRepository: (_) => repository,
      );
      await tester.tap(find.text('Menzah Market'));
      await tester.pumpAndSettle();
      expect(find.text('Adresse à renseigner'), findsNothing);
      expect(find.text('Ouvert'), findsOneWidget);
    });

    testWidgets('a closed store says Fermé, explains, and has no controls', (
      tester,
    ) async {
      await _open(tester, [_ketchup(id: 1, brand: _heinz)], isOpen: false);
      expect(find.text('Fermé'), findsOneWidget);
      expect(find.textContaining('mais pas commander'), findsOneWidget);
      expect(find.text('Heinz'), findsOneWidget);
      expect(find.text('Ketchup'), findsOneWidget);
      expect(find.byTooltip('Ajouter Ketchup'), findsNothing);
      // The price stays.
      expect(find.text('2,500 DT'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('is one column of rows on one list surface', (tester) async {
      await _open(tester, [
        for (var i = 1; i <= 4; i++) _ketchup(id: i, name: 'Sauce $i'),
      ]);

      final lefts = {
        for (var i = 1; i <= 4; i++)
          tester.getTopLeft(_in(i, find.text('Sauce $i'))).dx,
      };
      expect(lefts, hasLength(1), reason: 'one column');
      final tops = [for (var i = 1; i <= 4; i++) tester.getTopLeft(_row(i)).dy];
      expect(tops, [...tops]..sort());
      // No bordered card per product.
      expect(
        find.descendant(of: _row(1), matching: find.byType(Card)),
        findsNothing,
      );
      // Hairlines between rows of one list, none above the first.
      expect(find.byType(Divider), findsNWidgets(3));
    });

    testWidgets('a photographed product has a 56 px tile, a photo-less one a '
        'quiet 48 px tile, and their text lines up', (tester) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Avec photo', photo: _photo),
        _ketchup(id: 2, name: 'Sans photo'),
      ]);

      final withPhoto = tester.widget<ProductImage>(
        _in(1, find.byType(ProductImage)),
      );
      expect(withPhoto.size, 56);
      expect(withPhoto.tile, isTrue);
      expect(withPhoto.fit, BoxFit.contain);
      expect(withPhoto.quiet, isFalse);

      final without = tester.widget<ProductImage>(
        _in(2, find.byType(ProductImage)),
      );
      expect(without.size, 48);
      expect(without.quiet, isTrue);

      // Same slot: the names start at the same x.
      expect(
        tester.getTopLeft(_in(1, find.text('Avec photo'))).dx,
        tester.getTopLeft(_in(2, find.text('Sans photo'))).dx,
      );
    });

    testWidgets('the add control is a filled 44 px circle with a white plus', (
      tester,
    ) async {
      await _open(tester, [_ketchup(id: 1, brand: _heinz)]);

      final add = find.descendant(
        of: _row(1),
        matching: find.byType(IconButton),
      );
      expect(add, findsOneWidget);
      expect(tester.getSize(add), const Size(44, 44));
      expect(find.byType(OutlinedButton), findsNothing);
      final button = tester.widget<IconButton>(add);
      expect(button.style?.backgroundColor?.resolve({}), AppColors.primary);
      expect(button.style?.foregroundColor?.resolve({}), Colors.white);
      expect(button.icon, isA<Icon>());
      expect((button.icon as Icon).icon, Icons.add_rounded);
      // At the row's right edge, the price at the text's left edge.
      expect(
        tester.getRect(add).right,
        closeTo(400 - 2 * AppSpacing.pagePadding, 1),
      );
      expect(
        tester.getTopLeft(_in(1, find.text('2,500 DT'))).dx,
        tester.getTopLeft(_in(1, find.text('Ketchup'))).dx,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no brand, no minimum: the price sits right under the name', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Sel'),
        _ketchup(id: 2, name: 'Mayo', brand: _heinz, minQuantity: 3),
      ]);
      final plain =
          tester.getTopLeft(_in(1, find.text('2,500 DT'))).dy -
          tester.getBottomLeft(_in(1, find.text('Sel'))).dy;
      expect(plain, lessThan(16), reason: 'no empty metadata slot');
      // Compact: an ordinary row is well under 100 px high.
      expect(tester.getSize(_row(1)).height, lessThan(100));
      // A row with metadata keeps it, then the price.
      final meta = tester.getBottomLeft(_in(2, find.text('Min. 3 pièces'))).dy;
      expect(
        tester.getTopLeft(_in(2, find.text('2,500 DT'))).dy,
        greaterThan(meta),
      );
    });

    for (final size in [const Size(400, 3000), const Size(320, 3000)]) {
      testWidgets('adding a product does not change the row height ($size)', (
        tester,
      ) async {
        await _open(tester, [
          _ketchup(
            id: 1,
            name: 'Poivre',
            unit: SaleUnit.kg,
            minQuantity: 500,
            step: 250,
            max: 5000,
          ),
        ], size: size);
        final before = tester.getSize(_row(1)).height;
        await tester.tap(find.byTooltip('Ajouter Poivre'));
        await tester.pumpAndSettle();
        expect(tester.getSize(_row(1)).height, before);
        expect(find.text('500 g'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('on a narrow screen the control goes under the price, for '
        'every state of the row', (tester) async {
      await _open(tester, [
        _ketchup(
          id: 1,
          name: 'Poivre',
          unit: SaleUnit.kg,
          minQuantity: 500,
          step: 250,
          max: 5000,
        ),
      ], size: const Size(320, 3000));
      final price = tester.getRect(_in(1, find.text('2,500 DT')));
      final add = tester.getRect(find.byTooltip('Ajouter Poivre'));
      expect(add.top, greaterThanOrEqualTo(price.bottom));
      await tester.tap(find.byTooltip('Ajouter Poivre'));
      await tester.pumpAndSettle();
      // The same arrangement with the stepper: price above, control below.
      final stepper = tester.getRect(
        find.byTooltip('Retirer Poivre du panier'),
      );
      expect(stepper.top, greaterThanOrEqualTo(price.bottom));
      // The unit stays under its amount, never split off.
      final unit = tester.getRect(_in(1, find.text('/ kg')));
      expect(unit.left, price.left);
      expect(tester.takeException(), isNull);
    });

    testWidgets('controls line up down the list, short name or long', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Sel'),
        _ketchup(id: 2, name: 'Boisson au jus ananas 20 cl', brand: _heinz),
        _ketchup(id: 3, name: 'Mayo', minQuantity: 3, max: 12),
      ]);
      final rights = {
        for (final name in ['Sel', 'Boisson au jus ananas 20 cl', 'Mayo'])
          tester.getRect(find.byTooltip('Ajouter $name')).right,
      };
      expect(rights, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('hierarchy: name 500, price 700, unit and brand small', (
      tester,
    ) async {
      await _open(tester, [_ketchup(id: 1, brand: _heinz, minQuantity: 2)]);

      final name = tester.widget<Text>(_in(1, find.text('Ketchup')));
      expect(name.style?.fontSize, 16);
      expect(name.style?.fontWeight, FontWeight.w500);
      final price = tester.widget<Text>(_in(1, find.text('2,500 DT')));
      expect(price.style?.fontSize, 18);
      expect(price.style?.fontWeight, FontWeight.w700);
      final unit = tester.widget<Text>(_in(1, find.text('/ pièce')));
      expect(unit.style?.fontSize, 12);
      expect(unit.style?.fontWeight, FontWeight.w400);
      expect(unit.style?.color, AppColors.textSecondary);
      final brand = tester.widget<Text>(_in(1, find.text('Heinz')));
      expect(brand.style?.fontSize, 12);
      // The minimum is said before adding, in the same quiet style.
      expect(_in(1, find.text('Min. 2 pièces')), findsOneWidget);
    });

    testWidgets('a long name wraps to at most three lines, nothing overflows', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(
          id: 1,
          name:
              'Huile d’olive extra vierge pressée à froid bouteille en verre '
              'de un litre et demi pour la cuisine et les salades',
          brand: _heinz,
        ),
      ]);
      expect(tester.takeException(), isNull);
      final name = find.textContaining('Huile d’olive');
      expect(name, findsOneWidget);
      expect(tester.widget<Text>(name).maxLines, 3);
      // Price and control are still there.
      expect(
        find.byTooltip('Ajouter ${tester.widget<Text>(name).data}'),
        findsOneWidget,
      );
    });

    testWidgets('weighed and measured units say their unit', (tester) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Poulet', unit: SaleUnit.kg, minQuantity: 500),
        _ketchup(id: 2, name: 'Lait', unit: SaleUnit.l, minQuantity: 500),
      ]);
      expect(_in(1, find.text('/ kg')), findsOneWidget);
      expect(_in(2, find.text('/ L')), findsOneWidget);
      expect(_in(1, find.text('Min. 500 g')), findsOneWidget);
    });

    testWidgets('the rows are built lazily', (tester) async {
      await _open(tester, [
        for (var i = 1; i <= 120; i++) _ketchup(id: i, name: 'Sauce $i'),
      ], size: const Size(400, 800));
      final built = tester.widgetList(find.byType(ProductImage)).length;
      expect(built, lessThan(30));
      expect(built, greaterThan(3));
    });

    testWidgets('a category heading above each list, with its count', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1),
        _ketchup(id: 2, name: 'Cumin', category: _spices),
        _ketchup(id: 3, name: 'Poivre', category: _spices),
      ]);
      expect(find.text('Sauces · 1'), findsOneWidget);
      expect(find.text('Épices · 2'), findsOneWidget);
    });

    testWidgets('a selected category is not repeated as a heading', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1),
        _ketchup(id: 2, name: 'Cumin', category: _spices),
      ]);
      await tester.tap(_tab('Épices'));
      await tester.pumpAndSettle();

      expect(find.text('Cumin'), findsOneWidget);
      expect(find.text('Ketchup'), findsNothing);
      expect(find.textContaining('Épices ·'), findsNothing);
      // The tab says which category it is.
      expect(_tab('Épices'), findsOneWidget);
    });
  });

  group('category tabs', () {
    testWidgets('are text with an underline for the selected one', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1),
        _ketchup(id: 2, name: 'Cumin', category: _spices),
      ]);
      expect(find.byType(ChoiceChip), findsNothing);
      for (final label in ['Tous', 'Sauces', 'Épices']) {
        expect(_tab(label), findsOneWidget);
      }
      final tous = tester.widget<Text>(_tab('Tous'));
      final sauces = tester.widget<Text>(_tab('Sauces'));
      expect(tous.style?.fontWeight, FontWeight.w600);
      expect(sauces.style?.fontWeight, FontWeight.w500);
      expect(sauces.style?.color, AppColors.textSecondary);
      // 48 px to touch.
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: _tab('Sauces'), matching: find.byType(InkWell))
                  .first,
            )
            .height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('when the store has nothing to order', () {
    testWidgets('no products at all: says the store has not added any, and '
        'offers the way back', (tester) async {
      await _open(tester, const []);

      expect(
        find.text('Ce magasin n’a pas encore ajouté de produits'),
        findsOneWidget,
      );
      expect(
        find.text('Aucun produit disponible pour le moment'),
        findsNothing,
      );
      expect(find.text('Aucun produit trouvé'), findsNothing);
      expect(find.text('Voir les autres magasins'), findsOneWidget);
      // Nothing to search or filter.
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('products that none can be ordered: a different message, '
        'the same way back', (tester) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Ketchup', isOrderable: false),
        _ketchup(id: 2, name: 'Mayo', isOrderable: false),
      ]);

      expect(
        find.text('Aucun produit disponible pour le moment'),
        findsOneWidget,
      );
      expect(find.text('Voir les autres magasins'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Ajouter Ketchup'), findsNothing);
    });

    testWidgets('one orderable product is enough for the normal catalogue', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Ketchup', isOrderable: false),
        _ketchup(id: 2, name: 'Mayo'),
      ]);
      expect(find.text('Voir les autres magasins'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Ajouter Mayo'), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);
    });

    testWidgets('"Voir les autres magasins" goes back to the store list', (
      tester,
    ) async {
      await _open(tester, const []);
      await tester.tap(find.text('Voir les autres magasins'));
      await tester.pumpAndSettle();

      expect(find.text('Voir les autres magasins'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('Magasins'), findsWidgets);
    });

    testWidgets('a search with no match is "Aucun produit trouvé", and '
        'clearing it restores the catalogue', (tester) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Ketchup'),
        _ketchup(id: 2, name: 'Mayo'),
      ]);
      await tester.enterText(find.byType(TextField), 'inexistant');
      await tester.pumpAndSettle();

      expect(find.text('Aucun produit trouvé'), findsOneWidget);
      expect(find.text('Effacer les filtres'), findsOneWidget);
      expect(find.text('Voir les autres magasins'), findsNothing);

      await tester.tap(find.text('Effacer les filtres'));
      await tester.pumpAndSettle();
      expect(find.text('Ketchup'), findsOneWidget);
      expect(find.text('Mayo'), findsOneWidget);
    });

    testWidgets('a category with no match behaves the same way', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, name: 'Ketchup'),
        fakeCustomerProduct(id: 2, name: 'Banane'),
      ]);
      await tester.tap(_tab('Sauces'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'banane');
      await tester.pumpAndSettle();

      expect(find.text('Aucun produit trouvé'), findsOneWidget);
      await tester.tap(find.text('Effacer les filtres'));
      await tester.pumpAndSettle();
      expect(find.text('Ketchup'), findsOneWidget);
      expect(find.text('Banane'), findsOneWidget);
    });
  });

  group('availability', () {
    testWidgets('an unavailable product stays visible and cannot be added', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, brand: _heinz),
        _ketchup(id: 2, name: 'Mayo', brand: _amora, isOrderable: false),
      ]);

      expect(find.text('Mayo'), findsOneWidget);
      expect(find.text('Amora'), findsOneWidget);
      expect(find.text('2,500 DT'), findsNWidgets(2));
      // Icon + text, in the row; no control.
      expect(_in(2, find.text('Indisponible')), findsOneWidget);
      expect(find.byTooltip('Ajouter Mayo'), findsNothing);
      expect(find.byTooltip('Ajouter Ketchup'), findsOneWidget);
      // Dimmed picture, secondary-colour name.
      final opacity = tester.widget<Opacity>(
        find.descendant(of: _row(2), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 0.45);
      expect(
        tester.widget<Text>(_in(2, find.text('Mayo'))).style?.color,
        AppColors.textSecondary,
      );
      for (final word in ['tock', 'Rupture', 'restant']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  group('search', () {
    final products = [
      _ketchup(id: 1, brand: _heinz),
      _ketchup(id: 2, brand: _amora),
      _ketchup(id: 3, name: 'Mayonnaise', brand: null),
      fakeCustomerProduct(id: 4, name: 'Banane'),
    ];

    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    testWidgets('finds a product by its brand', (tester) async {
      await _open(tester, products);
      await search(tester, 'Heinz');
      expect(_inList('Heinz'), findsOneWidget);
      expect(_inList('Amora'), findsNothing);
      expect(_inList('Mayonnaise'), findsNothing);
      expect(find.byTooltip('Ajouter Ketchup'), findsOneWidget);
    });

    testWidgets('ignores case and accents in the brand too', (tester) async {
      await _open(tester, [
        _ketchup(
          id: 1,
          brand: const Brand(id: 9, slug: 'delice', name: 'Délice'),
        ),
        fakeCustomerProduct(id: 2, name: 'Banane'),
      ]);
      await search(tester, 'DELICE');
      expect(_inList('Délice'), findsOneWidget);
      expect(_inList('Banane'), findsNothing);
    });

    testWidgets('still finds a product by its name', (tester) async {
      await _open(tester, products);
      await search(tester, 'ketchup');
      expect(_inList('Heinz'), findsOneWidget);
      expect(_inList('Amora'), findsOneWidget);
      expect(_inList('Mayonnaise'), findsNothing);
      expect(find.byTooltip('Ajouter Ketchup'), findsNWidgets(2));
    });

    testWidgets('a brand and a name together narrow it down', (tester) async {
      await _open(tester, products);
      await search(tester, 'amora ketchup');
      expect(_inList('Amora'), findsOneWidget);
      expect(_inList('Heinz'), findsNothing);
    });
  });

  group('the cart stays the one source of truth', () {
    testWidgets('Ajouter puts the minimum in the cart; the row follows it', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(id: 1, brand: _heinz, photo: _photo),
        _ketchup(id: 2, name: 'Mayo'),
      ]);
      final cart = CustomerScope.of(tester.element(find.byType(Scaffold).first))
          .cart;

      await tester.tap(find.byTooltip('Ajouter Ketchup'));
      await tester.pumpAndSettle();

      expect(cart.quantityOf(1), 1); // the product's own minimum
      expect(cart.quantityOf(2), 0);
      expect(find.byTooltip('Ajouter Ketchup'), findsNothing);
      expect(find.text('1 pièce'), findsOneWidget);
      // The bar: the count and the total beside the action.
      expect(find.text('Voir le panier'), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
      expect(find.text('2,500 DT'), findsNWidgets(3)); // two rows + the bar
      expect(find.byTooltip('Ajouter Mayo'), findsOneWidget);
    });

    testWidgets('the bar opens the cart', (tester) async {
      await _open(tester, [_ketchup(id: 1)]);
      await tester.tap(find.byTooltip('Ajouter Ketchup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir le panier'));
      await tester.pumpAndSettle();

      expect(find.text('Total estimé'), findsWidgets);
      expect(find.text('Commander'), findsWidgets);
    });

    testWidgets('the stepper uses the cart’s own step and maximum', (
      tester,
    ) async {
      await _open(tester, [
        _ketchup(
          id: 1,
          name: 'Poivre',
          unit: SaleUnit.kg,
          minQuantity: 500,
          step: 250,
          max: 1000,
        ),
      ]);
      final cart = CustomerScope.of(tester.element(find.byType(Scaffold).first))
          .cart;

      await tester.tap(find.byTooltip('Ajouter Poivre'));
      await tester.pumpAndSettle();
      expect(find.text('500 g'), findsOneWidget);
      expect(find.byTooltip('Retirer Poivre du panier'), findsOneWidget);

      await tester.tap(find.byTooltip('Augmenter la quantité de Poivre'));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(1), 750);
      expect(find.text('750 g'), findsOneWidget);

      await tester.tap(find.byTooltip('Augmenter la quantité de Poivre'));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(1), 1000);
      // At the maximum the plus is disabled.
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.add_rounded),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      // Down to the minimum, then the trash removes the line.
      await tester.tap(find.byTooltip('Diminuer la quantité de Poivre'));
      await tester.tap(find.byTooltip('Diminuer la quantité de Poivre'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retirer Poivre du panier'));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(1), 0);
      expect(find.byTooltip('Ajouter Poivre'), findsOneWidget);
    });

    testWidgets('the stepper fits on a small phone', (tester) async {
      await _open(tester, [
        _ketchup(
          id: 1,
          name: 'Poivre',
          brand: _heinz,
          unit: SaleUnit.kg,
          minQuantity: 1000,
          step: 500,
          max: 10000,
        ),
        _ketchup(id: 2, name: 'Mayo'),
      ], size: const Size(320, 3000));
      await tester.tap(find.byTooltip('Ajouter Poivre'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byTooltip('Augmenter la quantité de Poivre'));
        await tester.pumpAndSettle();
      }
      expect(find.text('5 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('the price is read with its unit, the add control by name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, [_ketchup(id: 1, brand: _heinz)]);

      expect(find.bySemanticsLabel(RegExp('2,500 DT par pièce')), findsWidgets);
      expect(find.byTooltip('Ajouter Ketchup'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Image du produit')), findsWidgets);
      semantics.dispose();
    });
  });

  group('large text', () {
    const example = 'Boisson au jus ananas 20 cl';

    List<CustomerProduct> products() => [
      _ketchup(id: 1, name: example, brand: _heinz, photo: _photo),
      _ketchup(id: 2, name: 'Sel', minQuantity: 6, max: 24),
      _ketchup(id: 3, name: 'Poulet', unit: SaleUnit.kg, minQuantity: 500),
      _ketchup(id: 4, name: 'Mayo', isOrderable: false),
    ];

    for (final (label, size, scale) in [
      ('1.3× on a 360 px phone', const Size(360, 3000), 1.3),
      ('1.65× on a 400 px phone', const Size(400, 3000), 1.65),
      ('2× on a 320 px phone', const Size(320, 4000), 2.0),
    ]) {
      testWidgets('$label: nothing overflows, price and control are there', (
        tester,
      ) async {
        await _open(tester, products(), size: size, textScale: scale);
        expect(tester.takeException(), isNull);

        // The whole name, however many lines it takes.
        expect(find.text(example), findsOneWidget);
        expect(
          tester.getRect(find.text(example)).right,
          lessThanOrEqualTo(size.width),
        );
        // Essential information is never dropped.
        expect(find.text('2,500 DT'), findsNWidgets(4));
        expect(find.text('Min. 6 pièces'), findsOneWidget);
        expect(find.text('Indisponible'), findsOneWidget);
        for (final name in [example, 'Sel', 'Poulet']) {
          final add = find.byTooltip('Ajouter $name');
          expect(add, findsOneWidget);
          expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
          expect(tester.getSize(add).width, greaterThanOrEqualTo(44));
          expect(tester.getRect(add).right, lessThanOrEqualTo(size.width));
        }
      });
    }

    testWidgets('a long name is shown whole at large text, on several lines', (
      tester,
    ) async {
      const name = 'Bachkoutou sésame 1 kg avec du miel et des amandes';
      await _open(
        tester,
        [_ketchup(id: 1, name: name, brand: _heinz)],
        size: const Size(402, 3000),
        textScale: 2.3,
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse);
      // Taller than one line of 16 × 1.25 × 2.3.
      expect(tester.getSize(find.text(name)).height, greaterThan(46 * 1.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('2×: the thumbnail steps aside, the text keeps its width', (
      tester,
    ) async {
      await _open(
        tester,
        products(),
        size: const Size(320, 4000),
        textScale: 2,
      );
      expect(find.byType(ProductImage), findsNothing);
    });

    testWidgets('at the default size the thumbnail is there', (tester) async {
      await _open(tester, products(), size: const Size(320, 3000));
      expect(find.byType(ProductImage), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the action bar stacks the total above the button', (
      tester,
    ) async {
      await _open(
        tester,
        products(),
        size: const Size(320, 4000),
        textScale: 2,
      );
      await tester.tap(find.byTooltip('Ajouter Sel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final button = tester.getRect(find.text('Voir le panier'));
      final count = tester.getRect(find.text('1 produit'));
      expect(count.bottom, lessThan(button.top));
      expect(button.right, lessThanOrEqualTo(320));
    });

    testWidgets('search and category tabs work the same', (tester) async {
      await _open(
        tester,
        [
          _ketchup(id: 1, name: example),
          _ketchup(id: 2, name: 'Cumin', category: _spices),
        ],
        size: const Size(320, 4000),
        textScale: 2,
      );
      await tester.tap(_tab('Épices'));
      await tester.pumpAndSettle();
      expect(find.text('Cumin'), findsOneWidget);
      expect(find.text(example), findsNothing);

      await tester.tap(_tab('Tous'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ananas');
      await tester.pumpAndSettle();
      expect(find.text(example), findsOneWidget);
      expect(find.text('Cumin'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
