import 'package:flutter/material.dart';

import '../../../../data/models/user.dart';
import '../../../authenticated_home.dart';
import 'register_form.dart';

/// `Création du compte` for a `CLIENT`.
class ClientRegisterView extends StatelessWidget {
  const ClientRegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte client')),
      body: SafeArea(
        child: RegisterForm(
          role: UserRole.client,
          submitLabel: 'Créer mon compte',
          onSuccess: (context) {
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
