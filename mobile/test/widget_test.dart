import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Avoids the real `flutter_secure_storage` platform channel in widget
/// tests — there's no stored session, so bootstrap should land on the splash.
class _NoTokenStorage extends TokenStorage {
  @override
  Future<String?> readToken() async => null;
}

AuthViewModel _buildAuthViewModel(ApiClient apiClient) {
  return AuthViewModel(
    authRepository: AuthRepository(apiClient),
    tokenStorage: _NoTokenStorage(),
    apiClient: apiClient,
  );
}

/// Lets the auth bootstrap check (an async gap) resolve and the splash's
/// entrance fade finish, without yet firing its auto-advance timer.
Future<void> _pumpToSplash(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// The splash auto-advances after a fixed hold + fade. Widget tests run on a
/// fake clock, so real time never passes — pump past both explicitly to
/// reach the login screen deterministically.
Future<void> _pumpPastSplash(WidgetTester tester) async {
  await _pumpToSplash(tester);
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('splash shows only the brand, then advances to login', (
    tester,
  ) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      GroceryApp(
        authViewModel: _buildAuthViewModel(apiClient),
        storeRepository: StoreRepository(apiClient),
        catalogRepository: CatalogRepository(apiClient),
        storeProductsRepository: StoreProductsRepository(apiClient),
        ordersRepository: OrdersRepository(apiClient),
        customerStoresRepository: CustomerStoresRepository(apiClient),
        customerOrdersRepository: CustomerOrdersRepository(apiClient),
      ),
    );
    await _pumpToSplash(tester);

    // Splash: brand only, no buttons or other controls.
    expect(find.text('GrocerGo'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    await _pumpPastSplash(tester);

    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('GrocerGo'), findsOneWidget);
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Nouveau ici ? Créer un compte'), findsOneWidget);
  });

  testWidgets('login shows a French error for empty fields', (tester) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      GroceryApp(
        authViewModel: _buildAuthViewModel(apiClient),
        storeRepository: StoreRepository(apiClient),
        catalogRepository: CatalogRepository(apiClient),
        storeProductsRepository: StoreProductsRepository(apiClient),
        ordersRepository: OrdersRepository(apiClient),
        customerStoresRepository: CustomerStoresRepository(apiClient),
        customerOrdersRepository: CustomerOrdersRepository(apiClient),
      ),
    );
    await _pumpPastSplash(tester);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Le numéro de téléphone est requis.'), findsOneWidget);
    expect(find.text('Le mot de passe est requis.'), findsOneWidget);
  });

  testWidgets('account type selection shows both account types', (
    tester,
  ) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      GroceryApp(
        authViewModel: _buildAuthViewModel(apiClient),
        storeRepository: StoreRepository(apiClient),
        catalogRepository: CatalogRepository(apiClient),
        storeProductsRepository: StoreProductsRepository(apiClient),
        ordersRepository: OrdersRepository(apiClient),
        customerStoresRepository: CustomerStoresRepository(apiClient),
        customerOrdersRepository: CustomerOrdersRepository(apiClient),
      ),
    );
    await _pumpPastSplash(tester);

    await tester.tap(find.text('Nouveau ici ? Créer un compte'));
    await tester.pumpAndSettle();

    expect(find.text('Vous êtes...'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
  });

  testWidgets('client account type opens the client registration form', (
    tester,
  ) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      GroceryApp(
        authViewModel: _buildAuthViewModel(apiClient),
        storeRepository: StoreRepository(apiClient),
        catalogRepository: CatalogRepository(apiClient),
        storeProductsRepository: StoreProductsRepository(apiClient),
        ordersRepository: OrdersRepository(apiClient),
        customerStoresRepository: CustomerStoresRepository(apiClient),
        customerOrdersRepository: CustomerOrdersRepository(apiClient),
      ),
    );
    await _pumpPastSplash(tester);

    await tester.tap(find.text('Nouveau ici ? Créer un compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client'));
    await tester.pumpAndSettle();

    expect(find.text('Créer un compte client'), findsOneWidget);
    expect(find.text('Nom'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(find.text('Numéro WhatsApp'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    // The photo is added after sign-up, from the profile: no link field here.
    expect(find.text('Photo de profil'), findsNothing);
    expect(find.textContaining('Lien de la photo'), findsNothing);
    expect(find.text('Créer mon compte'), findsOneWidget);
  });

  testWidgets('owner account type opens the owner registration form', (
    tester,
  ) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      GroceryApp(
        authViewModel: _buildAuthViewModel(apiClient),
        storeRepository: StoreRepository(apiClient),
        catalogRepository: CatalogRepository(apiClient),
        storeProductsRepository: StoreProductsRepository(apiClient),
        ordersRepository: OrdersRepository(apiClient),
        customerStoresRepository: CustomerStoresRepository(apiClient),
        customerOrdersRepository: CustomerOrdersRepository(apiClient),
      ),
    );
    await _pumpPastSplash(tester);

    await tester.tap(find.text('Nouveau ici ? Créer un compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Propriétaire'));
    await tester.pumpAndSettle();

    expect(find.text('Créer un compte propriétaire'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });
}
