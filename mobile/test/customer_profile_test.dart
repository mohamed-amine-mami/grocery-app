import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/customer_order.dart';
import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/models/sale_unit.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/core/photo/editable_photo.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/features/customer/view_models/customer_scope.dart';

import 'fakes.dart';

User _customer({
  String name = 'sana ben ali',
  String email = 'sana@example.com',
  String? phone = '+21698765432',
  String? whatsapp,
}) => User(
  id: 2,
  name: name,
  email: email,
  phoneNumber: phone,
  whatsappNumber: whatsapp,
  role: UserRole.client,
);

/// The repository the last [_openProfile] built, to change what it answers.
late FakeCustomerOrdersRepository _orders;

Future<void> _openProfile(
  WidgetTester tester,
  User user, {
  Size size = const Size(402, 874),
  double textScale = 1,
  List<CustomerOrder> orders = const [],
  Object? listError,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpAppSignedInAs(
    tester,
    user,
    storeRepository: FakeStoreRepository.new,
    customerOrdersRepository: (api) {
      _orders = FakeCustomerOrdersRepository(api, orders: orders)
        ..listError = listError;
      return _orders;
    },
  );
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Profil'),
    ),
  );
  await tester.pumpAndSettle();
}

CustomerScope _scope(WidgetTester tester) =>
    CustomerScope.of(tester.element(find.byType(Scaffold).first));

Finder get _signOut => find.widgetWithText(OutlinedButton, 'Se déconnecter');

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  group('header', () {
    testWidgets('shows the stored name exactly, with no greeting or role '
        'sentence', (tester) async {
      await _openProfile(tester, _customer(name: 'sana ben ali'));
      expect(find.text('sana ben ali'), findsOneWidget);
      expect(find.textContaining('Bonjour'), findsNothing);
      expect(find.textContaining('connecté en tant que'), findsNothing);
      expect(find.text('Votre compte GrocerGo'), findsOneWidget);
      final name = tester.widget<Text>(find.text('sana ben ali'));
      expect(name.style?.fontSize, 20);
      expect(name.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('keeps the editable photo, small, beside the name', (
      tester,
    ) async {
      await _openProfile(tester, _customer());
      final photo = find.byType(EditablePhoto);
      expect(photo, findsOneWidget);
      expect(tester.widget<EditablePhoto>(photo).size, 72);
      expect(tester.widget<EditablePhoto>(photo).title, 'Photo de profil');
      // Beside the name, on its left, at the page's left edge.
      final photoRect = tester.getRect(photo);
      final name = tester.getRect(find.text('sana ben ali'));
      expect(photoRect.left, 16);
      expect(photoRect.right, lessThan(name.left));
      expect(photoRect.center.dy, closeTo(name.center.dy, 40));
    });
  });

  group('information', () {
    testWidgets('lists the phone and the e-mail, labelled, with their real '
        'values', (tester) async {
      await _openProfile(tester, _customer());
      expect(find.text('Mes informations'), findsOneWidget);
      expect(find.text('Téléphone'), findsOneWidget);
      expect(find.text('+21698765432'), findsOneWidget);
      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('sana@example.com'), findsOneWidget);
      // Inline at normal text: the label, then its value to the right.
      final label = tester.getRect(find.text('Téléphone'));
      final value = tester.getRect(find.text('+21698765432'));
      expect(label.right, lessThan(value.left));
      expect((label.center.dy - value.center.dy).abs(), lessThan(12));
      expect(value.right, lessThanOrEqualTo(402 - 16));
    });

    testWidgets('shows WhatsApp only when there is a number', (tester) async {
      await _openProfile(tester, _customer(whatsapp: '+21655443322'));
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('+21655443322'), findsOneWidget);
    });

    testWidgets('omits WhatsApp when it is missing or blank', (tester) async {
      await _openProfile(tester, _customer());
      expect(find.text('WhatsApp'), findsNothing);
    });

    testWidgets('a blank WhatsApp is not a row', (tester) async {
      await _openProfile(tester, _customer(whatsapp: '   '));
      expect(find.text('WhatsApp'), findsNothing);
    });

    testWidgets('a missing phone leaves no empty row', (tester) async {
      await _openProfile(tester, _customer(phone: null));
      expect(find.text('Téléphone'), findsNothing);
      expect(find.text('E-mail'), findsOneWidget);
      // Only the e-mail row: no divider, no blank label.
      expect(
        find.descendant(of: find.byType(Card), matching: find.byType(Divider)),
        findsNothing,
      );
    });

    testWidgets('does not suggest the details can be edited', (tester) async {
      await _openProfile(tester, _customer(whatsapp: '+21655443322'));
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.textContaining('Modifier'), findsNothing);
    });
  });

  group('large text', () {
    testWidgets('the rows stack, label over value, without icons', (
      tester,
    ) async {
      await _openProfile(tester, _customer(), textScale: 1.65);
      final label = tester.getRect(find.text('Téléphone'));
      final value = tester.getRect(find.text('+21698765432'));
      expect(label.bottom, lessThanOrEqualTo(value.top));
      expect(find.byIcon(Icons.phone_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('sign out', () {
    final yaourt = fakeCustomerProduct(
      id: 1,
      name: 'Yaourt',
      unit: SaleUnit.piece,
      priceMillimes: 1000,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 12,
    );
    final store = fakeCustomerStore(id: 10, name: 'Menzah Market');
    final dialog = find.byType(AlertDialog);
    final confirm = find.descendant(
      of: dialog,
      matching: find.text('Se déconnecter'),
    );

    testWidgets('is a neutral secondary button, 48 px or more', (tester) async {
      await _openProfile(tester, _customer());
      expect(_signOut, findsOneWidget);
      expect(tester.getSize(_signOut).height, greaterThanOrEqualTo(48));
      final style = tester.widget<OutlinedButton>(_signOut).style!;
      expect(style.side!.resolve({})!.color, AppColors.textSecondary);
      expect(style.foregroundColor!.resolve({}), AppColors.textPrimary);
    });

    testWidgets('asks first, and says nothing about a cart when there is '
        'none', (tester) async {
      await _openProfile(tester, _customer());
      await tester.ensureVisible(_signOut);
      await tester.tap(_signOut);
      await tester.pumpAndSettle();
      expect(find.text('Se déconnecter ?'), findsOneWidget);
      expect(
        find.text('Vous devrez vous reconnecter pour commander.'),
        findsOneWidget,
      );
      expect(find.textContaining('panier'), findsNothing);
    });

    testWidgets('warns that a cart in progress will be cleared', (
      tester,
    ) async {
      await _openProfile(tester, _customer());
      _scope(tester).cart.add(store, yaourt);
      await tester.pump();
      await tester.ensureVisible(_signOut);
      await tester.tap(_signOut);
      await tester.pumpAndSettle();
      expect(
        find.text('Votre panier en cours (1 produit) sera vidé.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling keeps the session and the cart', (tester) async {
      await _openProfile(tester, _customer());
      final cart = _scope(tester).cart..add(store, yaourt);
      await tester.pump();
      await tester.ensureVisible(_signOut);
      await tester.tap(_signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.text('Mes informations'), findsOneWidget);
      expect(find.text('Se connecter'), findsNothing);
      expect(cart.isEmpty, isFalse);
      expect(cart.lineCount, 1);
    });

    testWidgets('confirming signs out as before: back to the login, cart '
        'cleared, stores tab selected', (tester) async {
      await _openProfile(tester, _customer());
      final scope = _scope(tester);
      scope.cart.add(store, yaourt);
      await tester.pump();
      await tester.ensureVisible(_signOut);
      await tester.tap(_signOut);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Se connecter'), findsWidgets);
      expect(find.text('Mes informations'), findsNothing);
      expect(scope.cart.isEmpty, isTrue);
      expect(scope.navigation.tab, CustomerTab.stores);
    });
  });

  group('orders', () {
    final live = fakeCustomerOrder(
      id: 5,
      code: 'K7M2QX',
      storeName: 'Menzah Market',
    );

    testWidgets('shows the live order: store, status, pickup, code, '
        'total', (tester) async {
      await _openProfile(tester, _customer(), orders: [live]);
      expect(find.text('Commande en cours'), findsOneWidget);
      expect(find.text('Menzah Market'), findsOneWidget);
      expect(find.text('En attente'), findsOneWidget);
      expect(find.textContaining('Retrait ·'), findsOneWidget);
      expect(find.text('K7M2QX'), findsOneWidget);
      expect(find.text('3,300 DT'), findsOneWidget);
      // The existing status sentence, not a new one.
      expect(
        find.text('Le magasin va confirmer votre commande.'),
        findsOneWidget,
      );
    });

    testWidgets('opens the existing order page', (tester) async {
      await _openProfile(tester, _customer(), orders: [live]);
      await tester.tap(find.text('Menzah Market'));
      await tester.pumpAndSettle();
      expect(find.text('Commande K7M2QX'), findsOneWidget);
      expect(find.text('Code de retrait'), findsOneWidget);
    });

    testWidgets('prefers a live order over a newer finished one', (
      tester,
    ) async {
      await _openProfile(
        tester,
        _customer(),
        orders: [
          fakeCustomerOrder(id: 1, code: 'LIVE01'),
          fakeCustomerOrder(
            id: 2,
            code: 'DONE02',
            status: OrderStatus.completed,
          ),
        ],
      );
      expect(find.text('Commande en cours'), findsOneWidget);
      expect(find.text('LIVE01'), findsOneWidget);
      expect(find.text('DONE02'), findsNothing);
    });

    testWidgets('with only finished orders: the latest, calm, no next-step '
        'sentence', (tester) async {
      await _openProfile(
        tester,
        _customer(),
        orders: [
          fakeCustomerOrder(
            id: 1,
            code: 'OLD001',
            status: OrderStatus.cancelled,
          ),
          fakeCustomerOrder(
            id: 2,
            code: 'NEW002',
            status: OrderStatus.completed,
            items: const [],
          ),
        ],
      );
      expect(find.text('Dernière commande'), findsOneWidget);
      expect(find.text('Commande en cours'), findsNothing);
      expect(find.text('NEW002'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('several live orders: one card and a way to all of them', (
      tester,
    ) async {
      await _openProfile(
        tester,
        _customer(),
        orders: [
          fakeCustomerOrder(id: 1, code: 'AAA111'),
          fakeCustomerOrder(id: 2, code: 'BBB222'),
        ],
      );
      expect(find.text('BBB222'), findsOneWidget);
      expect(find.text('AAA111'), findsNothing);
      await tester.tap(find.text('Voir les 2 commandes en cours'));
      await tester.pumpAndSettle();
      expect(_scope(tester).navigation.tab, CustomerTab.orders);
    });

    testWidgets('no orders: an empty state that leads to the stores', (
      tester,
    ) async {
      await _openProfile(tester, _customer());
      expect(find.text('Aucune commande pour le moment'), findsOneWidget);
      expect(find.text('Commande en cours'), findsNothing);
      await tester.ensureVisible(find.text('Voir les magasins'));
      await tester.tap(find.text('Voir les magasins'));
      await tester.pumpAndSettle();
      expect(_scope(tester).navigation.tab, CustomerTab.stores);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      await _openProfile(
        tester,
        _customer(),
        listError: const ApiException(statusCode: 500),
      );
      expect(find.text('Impossible de charger vos commandes.'), findsOneWidget);
      _orders.listError = null;
      _orders.add(live);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Commande en cours'), findsOneWidget);
    });

    testWidgets('asks for a small window and reloads when the tab is '
        'opened again', (tester) async {
      await _openProfile(tester, _customer(), orders: [live]);
      int profileCalls() =>
          _orders.listCalls.where((c) => c.limit == 10).length;
      expect(profileCalls(), greaterThanOrEqualTo(1));
      final before = profileCalls();
      for (final tab in ['Magasins', 'Profil']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(profileCalls(), before + 1);
    });
  });

  group('responsive', () {
    final long = _customer(
      name: 'Mohamed Amine Ben Abdelkader El Mekki Ouled Hadj',
      email: 'mohamed.amine.ben.abdelkader.el.mekki@exemple-tres-long.com.tn',
      phone: '+21698765432',
      whatsapp: '+21655443322',
    );

    for (final (width, height, scale) in [
      (320.0, 568.0, 2.0),
      (360.0, 640.0, 1.65),
      (402.0, 874.0, 1.0),
    ]) {
      testWidgets('long values do not overflow at $width px, $scale×', (
        tester,
      ) async {
        await _openProfile(
          tester,
          long,
          size: Size(width, height),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(long.name), findsOneWidget);
        // Everything stays inside the screen's width.
        for (final text in [long.name, long.email]) {
          expect(
            tester.getRect(find.text(text)).right,
            lessThanOrEqualTo(width),
          );
        }
      });

      testWidgets('the page scrolls to sign out at $width px, $scale×', (
        tester,
      ) async {
        await _openProfile(
          tester,
          long,
          size: Size(width, height),
          textScale: scale,
        );
        await tester.scrollUntilVisible(
          _signOut,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(_signOut);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('the sign-out button follows the content, not the bottom of '
        'the screen', (tester) async {
      await _openProfile(tester, _customer());
      final rect = tester.getRect(_signOut);
      final info = tester.getRect(
        find.ancestor(of: find.text('E-mail'), matching: find.byType(Card)),
      );
      // Right under the last section, not pinned to the bottom.
      expect(rect.top - info.bottom, lessThan(40));
    });
  });
}
