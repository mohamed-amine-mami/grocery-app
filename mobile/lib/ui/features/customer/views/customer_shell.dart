import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../view_models/customer_scope.dart';
import 'cart_view.dart';
import 'customer_orders_view.dart';
import 'customer_profile_view.dart';
import 'stores_view.dart';

/// The customer's main navigation: **Magasins · Panier · Commandes · Profil**.
/// The cart is always one tap away and its badge counts the products in it.
/// There is no owner navigation here.
class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key});

  static (String, IconData) _destination(CustomerTab tab) => switch (tab) {
    CustomerTab.stores => ('Magasins', Icons.storefront_rounded),
    CustomerTab.cart => ('Panier', Icons.shopping_cart_rounded),
    CustomerTab.orders => ('Commandes', Icons.receipt_long_rounded),
    CustomerTab.profile => ('Profil', Icons.person_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final scope = CustomerScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.navigation, scope.cart]),
      builder: (context, _) {
        final tab = scope.navigation.tab;
        return Scaffold(
          // Each tab keeps its state (loaded lists, search text) when
          // switching between them.
          body: IndexedStack(
            index: tab.index,
            children: [
              // Each tab gets its own messenger so its snackbars sit above its
              // own content.
              ScaffoldMessenger(child: const StoresView()),
              ScaffoldMessenger(child: const CartView()),
              ScaffoldMessenger(
                child: CustomerOrdersView(isActive: tab == CustomerTab.orders),
              ),
              ScaffoldMessenger(child: const CustomerProfileView()),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (index) =>
                scope.navigation.select(CustomerTab.values[index]),
            destinations: [
              for (final destination in CustomerTab.values)
                NavigationDestination(
                  icon: destination == CustomerTab.cart && !scope.cart.isEmpty
                      ? Badge(
                          // A count, not an alarm: Citrus fill, Primary Text
                          // (see docs/design.md, Accent).
                          backgroundColor: AppColors.accent,
                          textColor: AppColors.textPrimary,
                          label: Text('${scope.cart.lineCount}'),
                          child: Icon(_destination(destination).$2),
                        )
                      : Icon(_destination(destination).$2),
                  label: _destination(destination).$1,
                ),
            ],
          ),
        );
      },
    );
  }
}
