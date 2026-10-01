import 'package:flutter/material.dart';

import '../view_models/auth_scope.dart';
import 'login_view.dart';

/// Ends the session and returns straight to login, not the branded splash —
/// the splash's timed hold is for first launch, not for a repeat visitor
/// logging out.
Future<void> signOut(BuildContext context) async {
  await AuthScope.of(context).logout();
  if (!context.mounted) {
    return;
  }
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginView()),
    (route) => false,
  );
}
