import 'package:flutter/widgets.dart';

import 'auth_view_model.dart';

/// Exposes the app-wide [AuthViewModel] to the widget tree and rebuilds
/// dependents whenever it calls `notifyListeners()`.
class AuthScope extends InheritedNotifier<AuthViewModel> {
  const AuthScope({
    required AuthViewModel authViewModel,
    required super.child,
    super.key,
  }) : super(notifier: authViewModel);

  static AuthViewModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in context');
    return scope!.notifier!;
  }
}
