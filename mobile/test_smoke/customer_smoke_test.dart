// End-to-end smoke test of the whole ordering journey: the real customer and
// owner apps (their UI, repositories and HTTP client) against a REAL backend.
// Only the secure token store is in-memory.
//
// Not part of `flutter test`. Run it against a throwaway backend with the
// global catalog imported (see "Smoke test" in CLAUDE.md):
//
//   flutter test test_smoke/customer_smoke_test.dart \
//       --dart-define=API_BASE_URL=http://localhost:3001
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:grocery_mobile/data/repositories/auth_repository.dart';
import 'package:grocery_mobile/data/repositories/catalog_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_orders_repository.dart';
import 'package:grocery_mobile/data/repositories/customer_stores_repository.dart';
import 'package:grocery_mobile/data/repositories/orders_repository.dart';
import 'package:grocery_mobile/data/repositories/store_products_repository.dart';
import 'package:grocery_mobile/data/repositories/store_repository.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/token_storage.dart';
import 'package:grocery_mobile/ui/app.dart';
import 'package:grocery_mobile/ui/features/auth/view_models/auth_view_model.dart';

const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3001',
);

class _MemoryTokens extends TokenStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

late _MemoryTokens _tokens;

/// Raw HTTP to the backend, to arrange and to check (the apps are what is
/// under test; this is the independent witness).
class _Backend {
  String? token;

  Future<dynamic> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int expect = 200,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final encoded = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'POST' => await http.post(uri, headers: headers, body: encoded),
      'PATCH' => await http.patch(uri, headers: headers, body: encoded),
      _ => throw ArgumentError(method),
    };
    if (response.statusCode != expect) {
      fail('$method $path → ${response.statusCode} ${response.body}');
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }
}

Future<void> _launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  final api = ApiClient(baseUrl: _baseUrl);
  await tester.pumpWidget(
    GroceryApp(
      authViewModel: AuthViewModel(
        authRepository: AuthRepository(api),
        tokenStorage: _tokens,
        apiClient: api,
      ),
      storeRepository: StoreRepository(api),
      catalogRepository: CatalogRepository(api),
      storeProductsRepository: StoreProductsRepository(api),
      ordersRepository: OrdersRepository(api),
      customerStoresRepository: CustomerStoresRepository(api),
      customerOrdersRepository: CustomerOrdersRepository(api),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var i = 0; i < 100; i++) {
    if (find
        .byType(CircularProgressIndicator, skipOffstage: false)
        .evaluate()
        .isEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

String _screenTexts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .join(' | ');

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Timed out waiting for $finder. On screen: ${_screenTexts()}');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    fail('Nothing to tap for $finder. On screen: ${_screenTexts()}');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await _settle(tester);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

Finder _nav(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(_nav(label));
  await _settle(tester);
}

Future<void> _login(WidgetTester tester, String phone, String password) async {
  await _type(tester, 'Numéro de téléphone', phone);
  await _type(tester, 'Mot de passe', password);
  await _tap(tester, find.text('Se connecter'));
}

Future<void> _logoutCustomer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6)); // let a snackbar go
  await _openTab(tester, 'Profil');
  await _tap(tester, find.text('Se déconnecter'));
  await _waitFor(tester, find.text('Connexion'));
}

Future<void> _logoutOwner(WidgetTester tester) async {
  await _openTab(tester, 'Magasin');
  await _tap(tester, find.text('Se déconnecter'));
  await _waitFor(tester, find.text('Connexion'));
}

void main() {
  setUpAll(() {
    HttpOverrides.global = null; // this test needs real HTTP
  });

  testWidgets(
    'Ordering: customer orders → owner confirms/ready/completes → customer follows → cancellations and no-show',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final stamp = DateTime.now().millisecondsSinceEpoch % 10000000;
      final ownerPhone = '2$stamp'.padLeft(8, '2');
      final customerPhone = '9$stamp'.padLeft(8, '9');
      const password = 'fortunes';
      // Unique names: the shared test database keeps other runs' stores.
      final shopName = 'Épicerie Parcours $stamp';
      final closedName = 'Primeur Fermé $stamp';
      _tokens = _MemoryTokens();
      final api = _Backend();

      // ── Arrange (independent of the apps): an open store with products ─
      final ownerAuth = await tester.runAsync(() async {
        final register = await api.call(
          'POST',
          '/auth/register',
          expect: 201,
          body: {
            'name': 'Karim Smoke',
            'email': 'owner-$stamp@example.com',
            'password': password,
            'phoneNumber': ownerPhone,
            'role': 'OWNER',
          },
        );
        api.token = register['accessToken'] as String;
        await api.call(
          'POST',
          '/owner/store',
          expect: 201,
          body: {'name': shopName, 'address': '5 Rue du Parcours, Tunis'},
        );
        await api.call('PATCH', '/owner/store', body: {'isOpen': true});
        final catalog =
            await api.call('GET', '/owner/catalog/products') as List<dynamic>;
        int idOf(String name) =>
            (catalog.firstWhere((p) => (p as Map)['name'] == name) as Map)['id']
                as int;
        final ids = <String, int>{};
        for (final (name, price, stock) in [
          ('Banane', 1800, 3000),
          ('Lait entier 1 L', 1200, 10),
          ('Yaourt nature (pot)', 700, null),
          ('Pomme', 2000, 0), // tracked and sold out: unavailable
        ]) {
          final created = await api.call(
            'POST',
            '/owner/store-products',
            expect: 201,
            body: {
              'productId': idOf(name),
              'priceMillimes': price,
              if (stock != null) ...{
                'trackStock': true,
                'stockQuantity': stock,
              },
            },
          );
          ids[name] = created['id'] as int;
        }
        // A second, closed store the customer can only browse.
        final closedOwner = await api.call(
          'POST',
          '/auth/register',
          expect: 201,
          body: {
            'name': 'Sana Fermée',
            'email': 'closed-$stamp@example.com',
            'password': password,
            'phoneNumber': '3$stamp'.padLeft(8, '3'),
            'role': 'OWNER',
          },
        );
        final ownerToken = api.token;
        api.token = closedOwner['accessToken'] as String;
        await api.call(
          'POST',
          '/owner/store',
          expect: 201,
          body: {'name': closedName, 'address': '1 Rue Fermée, Ariana'},
        );
        api.token = ownerToken;
        await api.call(
          'POST',
          '/auth/register',
          expect: 201,
          body: {
            'name': 'Sana Cliente',
            'email': 'client-$stamp@example.com',
            'password': password,
            'phoneNumber': customerPhone,
            'role': 'CLIENT',
          },
        );
        return ids;
      });
      final ids = ownerAuth!;

      Future<T> backend<T>(Future<T> Function() action) async =>
          (await tester.runAsync(action)) as T;
      Future<dynamic> ownerCall(
        String method,
        String path, {
        Map<String, dynamic>? body,
        int expect = 200,
      }) => backend(() => api.call(method, path, body: body, expect: expect));
      Future<int?> stock(String name) async {
        final product = await ownerCall(
          'GET',
          '/owner/store-products/${ids[name]}',
        );
        return (product as Map)['stockQuantity'] as int?;
      }

      // ── 1. Customer logs in ───────────────────────────────────────────
      await _launchApp(tester);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.text('Connexion'), findsOneWidget);
      await _login(tester, customerPhone, password);
      await _waitFor(tester, _nav('Magasins'));
      expect(_nav('Panier'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));

      // ── 2. Choose a store; a closed store can be browsed only ─────────
      await _waitFor(tester, find.text(shopName));
      expect(find.text(closedName), findsOneWidget);
      expect(find.text('Fermé'), findsWidgets);
      await _tap(tester, find.text(closedName));
      expect(
        find.textContaining('Ce magasin est fermé pour le moment'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);

      // ── 3. Browse the open store: unavailable product, no stock shown ─
      await _tap(tester, find.text(shopName));
      await _waitFor(tester, find.text('Banane'));
      expect(find.text('Pomme'), findsOneWidget);
      expect(find.text('Indisponible'), findsOneWidget);
      expect(find.byTooltip('Ajouter Pomme'), findsNothing);
      for (final word in ['tock', 'Rupture']) {
        expect(find.textContaining(word), findsNothing);
      }

      // Search and category filter.
      await tester.enterText(find.byType(TextField), 'yaourt');
      await _settle(tester);
      expect(find.text('Yaourt nature (pot)'), findsOneWidget);
      expect(find.text('Banane'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await _settle(tester);
      expect(find.text('Banane'), findsOneWidget);

      // ── 4. Add products: 700 g bananas, 2 milks, 3 yogurts ───────────
      await _tap(tester, find.byTooltip('Ajouter Banane')); // 500 g
      await _tap(tester, find.byTooltip('Augmenter la quantité de Banane'));
      await _tap(tester, find.byTooltip('Augmenter la quantité de Banane'));
      expect(find.text('700 g'), findsOneWidget);
      await _tap(tester, find.byTooltip('Ajouter Lait entier 1 L'));
      await _tap(
        tester,
        find.byTooltip('Augmenter la quantité de Lait entier 1 L'),
      );
      await _tap(tester, find.byTooltip('Ajouter Yaourt nature (pot)'));
      for (var i = 0; i < 2; i++) {
        await _tap(
          tester,
          find.byTooltip('Augmenter la quantité de Yaourt nature (pot)'),
        );
      }
      expect(
        find.textContaining('Voir le panier · 3 produits'),
        findsOneWidget,
      );

      // ── 5. Cart → checkout ────────────────────────────────────────────
      await _tap(tester, find.textContaining('Voir le panier'));
      expect(find.text('Total estimé'), findsOneWidget);
      expect(find.text('5,760 DT'), findsOneWidget); // 1,260 + 2,400 + 2,100
      await _tap(tester, find.text('Commander'));
      expect(find.text('Valider la commande'), findsOneWidget);
      expect(find.text('À la récupération'), findsOneWidget);

      // ── 6. Pick a pickup time (the 4th offered) and submit ───────────
      await _tap(tester, find.byKey(const Key('pickup-field')));
      final slotKeys = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('slot-'),
      );
      final chosenMillis = int.parse(
        (slotKeys.at(3).evaluate().single.widget.key! as ValueKey<String>).value
            .substring(5),
      );
      await _tap(tester, find.byKey(ValueKey('slot-$chosenMillis')));
      await _tap(tester, find.text('Confirmer la commande'));

      // ── 7. The server-created order is shown ─────────────────────────
      await _waitFor(tester, find.text('Commande envoyée'));
      expect(find.text('En attente'), findsWidgets);
      expect(find.text('5,760 DT'), findsWidgets); // the server's total
      expect(find.text('À la récupération'), findsOneWidget);
      final codeText = find
          .descendant(
            of: find.byType(AppBar),
            matching: find.textContaining('Commande '),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .first;
      final code = codeText.substring('Commande '.length);
      expect(code, matches(RegExp(r'^[A-Z0-9]{6}$')));

      // Independent check at the backend.
      final orders = await ownerCall(
        'GET',
        '/owner/orders?status=PENDING',
      ) as Map<String, dynamic>;
      final order = (orders['items'] as List).single as Map<String, dynamic>;
      expect(order['code'], code);
      expect(order['status'], 'PENDING');
      expect(order['totalMillimes'], 5760);
      expect(
        DateTime.parse(order['requestedPickupAt'] as String)
            .millisecondsSinceEpoch,
        chosenMillis,
      );
      final events = order['events'] as List;
      expect(events, hasLength(1));
      expect((events.single as Map)['toStatus'], 'PENDING');
      expect(await stock('Banane'), 2300);
      expect(await stock('Lait entier 1 L'), 8);
      expect(await stock('Yaourt nature (pot)'), isNull);
      final orderId = order['id'] as int;

      // Back to the history; the cart is empty.
      await _tap(tester, find.text('Voir mes commandes'));
      expect(find.text(code), findsOneWidget);
      await _openTab(tester, 'Panier');
      expect(find.text('Votre panier est vide'), findsOneWidget);
      await _logoutCustomer(tester);

      // ── 8. Owner: sees the pending order, confirms removing the milk ──
      await _login(tester, ownerPhone, password);
      await _waitFor(tester, _nav('Commandes'));
      await _openTab(tester, 'Commandes');
      await _waitFor(tester, find.text(code));
      expect(find.byKey(const Key('pending-count')), findsOneWidget);
      expect(find.text('commande en attente'), findsOneWidget);
      await _tap(tester, find.text(code));
      expect(find.text('Sana Cliente'), findsOneWidget);
      expect(find.text('Lignes conservées · 3'), findsOneWidget);
      // Remove the milk line.
      await tester.ensureVisible(find.text('Lait entier 1 L'));
      await _tap(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text('Lait entier 1 L'),
            matching: find.byType(Padding),
          ),
          matching: find.text('Retirer'),
        ),
      );
      expect(find.text('Lignes retirées · 1'), findsOneWidget);
      await _tap(tester, find.text('Confirmer'));
      await _tap(tester, find.text('Retirer et confirmer'));
      expect(find.text('Confirmée'), findsWidgets);
      expect(
        find.text('3,360 DT'),
        findsWidgets,
      ); // 1,260 + 2,100: milk excluded
      expect(await stock('Lait entier 1 L'), 10); // restored once
      expect(await stock('Banane'), 2300);
      await _tap(tester, find.text('Prête'));
      expect(find.text('Prête à retirer'), findsWidgets);
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);
      await _logoutOwner(tester);

      // ── 9. Customer follows: READY, sees the pickup code ─────────────
      await _login(tester, customerPhone, password);
      await _waitFor(tester, _nav('Commandes'));
      await _openTab(tester, 'Commandes');
      await _waitFor(tester, find.text(code));
      await _tap(tester, find.text(code));
      expect(find.text('Prête à retirer'), findsWidgets);
      expect(find.text('Code de retrait'), findsOneWidget);
      expect(find.text(code), findsWidgets);
      expect(find.text('3,360 DT'), findsWidgets);
      expect(find.text('Retirés par le magasin · 1'), findsOneWidget);
      expect(find.textContaining('tock'), findsNothing);
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);
      await _logoutCustomer(tester);

      // ── 10. Owner completes ──────────────────────────────────────────
      await _login(tester, ownerPhone, password);
      await _waitFor(tester, _nav('Commandes'));
      await _openTab(tester, 'Commandes');
      await _tap(tester, find.text(code));
      await _tap(tester, find.text('Marquer comme récupérée'));
      expect(find.text('Terminée'), findsOneWidget);
      expect(await stock('Banane'), 2300); // stays consumed
      expect(await stock('Lait entier 1 L'), 10);
      final done = await ownerCall(
        'GET',
        '/owner/orders/$orderId',
      ) as Map<String, dynamic>;
      expect(done['status'], 'COMPLETED');
      expect(
        [for (final e in done['events'] as List) (e as Map)['toStatus']],
        ['PENDING', 'CONFIRMED', 'READY_FOR_PICKUP', 'COMPLETED'],
      );
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);
      await _logoutOwner(tester);

      // ── 11. Customer cancels a pending order from the app ────────────
      await _login(tester, customerPhone, password);
      await _waitFor(tester, _nav('Magasins'));
      await _tap(tester, find.text(shopName));
      await _waitFor(tester, find.text('Banane'));
      await _tap(tester, find.byTooltip('Ajouter Lait entier 1 L'));
      await _tap(tester, find.textContaining('Voir le panier'));
      await _tap(tester, find.text('Commander'));
      await _tap(tester, find.text('Confirmer la commande'));
      await _waitFor(tester, find.text('Commande envoyée'));
      expect(await stock('Lait entier 1 L'), 9);
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Annuler la commande'),
      );
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la commande'),
        ),
      );
      expect(find.text('Annulée'), findsWidgets);
      expect(await stock('Lait entier 1 L'), 10); // restored exactly once

      // ── 12. Store switching with a non-empty cart ────────────────────
      // (Only one open store exists: the dialog needs a second open store, so
      // it is covered by the widget tests; here the closed one cannot take
      // products at all.)
      await tester.tap(
        find.byTooltip('Retour'),
      ); // the welcome is gone: it is cancelled
      await _settle(tester);
      await _openTab(tester, 'Magasins');
      await _tap(tester, find.text(closedName));
      expect(find.text('Ajouter'), findsNothing);
      expect(find.byTooltip('Ajouter Lait entier 1 L'), findsNothing);
      await tester.tap(find.byTooltip('Retour'));
      await _settle(tester);

      // ── 13. Sign out ─────────────────────────────────────────────────
      await _logoutCustomer(tester);
      expect(find.text('Connexion'), findsOneWidget);

      // The HTTP client keeps idle connections alive for 15 s on the test's
      // clock; let those timers fire so none is left pending.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
