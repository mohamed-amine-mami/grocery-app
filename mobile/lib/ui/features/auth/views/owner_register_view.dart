import 'package:flutter/material.dart';

import '../../../../data/models/user.dart';
import '../../../authenticated_home.dart';
import 'register_form.dart';

/// `Création du compte` for an `OWNER`. A new owner has no store yet, so the
/// post-auth entry point routes them to store creation.
class OwnerRegisterView extends StatelessWidget {
  const OwnerRegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte propriétaire')),
      body: SafeArea(
        child: RegisterForm(
          role: UserRole.owner,
          submitLabel: 'Continuer',
          onSuccess: (context) {
            // Drop the whole auth stack: going "back" from here would land on
            // the account-type screen while already signed in.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthenticatedHome()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }
}
