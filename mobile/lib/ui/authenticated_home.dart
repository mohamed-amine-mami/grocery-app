import 'package:flutter/material.dart';

import '../data/models/user.dart';
import 'features/auth/view_models/auth_scope.dart';
import 'features/customer/views/customer_shell.dart';
import 'features/owner/views/owner_gate.dart';

/// The single post-authentication entry point: every route that ends a
/// login, registration or session restore goes here, so routing by role
/// lives in one place. `OWNER` → [OwnerGate]; `CLIENT` → [CustomerShell].
class AuthenticatedHome extends StatelessWidget {
  const AuthenticatedHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    return user?.role == UserRole.owner
        ? const OwnerGate()
        : const CustomerShell();
  }
}
