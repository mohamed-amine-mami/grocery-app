import 'package:flutter/widgets.dart';

import 'cart_view_model.dart';

/// The customer areas of the shell.
enum CustomerTab { stores, cart, orders, profile }

/// Which customer tab is showing. Lives beside the cart so a screen pushed on
/// top of the shell (a placed order) can send the customer back to a tab.
class CustomerNavigation extends ChangeNotifier {
  CustomerTab _tab = CustomerTab.stores;
  CustomerTab get tab => _tab;

  void select(CustomerTab tab) {
    if (tab != _tab) {
      _tab = tab;
      notifyListeners();
    }
  }
}

/// Exposes the customer's cart and tab selection to the whole app, above the
/// navigator, so screens pushed over the shell (catalogue, checkout, order)
/// share them.
class CustomerScope extends InheritedWidget {
  const CustomerScope({
    required this.cart,
    required this.navigation,
    required super.child,
    super.key,
  });

  final CartViewModel cart;
  final CustomerNavigation navigation;

  static CustomerScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CustomerScope>();
    assert(scope != null, 'No CustomerScope found in context');
    return scope!;
  }

  static CustomerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomerScope>();

  @override
  bool updateShouldNotify(CustomerScope oldWidget) => false;
}
