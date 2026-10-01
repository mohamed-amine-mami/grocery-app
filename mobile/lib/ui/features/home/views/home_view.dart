import 'package:flutter/material.dart';

import '../../../../data/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/view_models/auth_scope.dart';
import '../../auth/views/sign_out.dart';

/// The landing screen once authenticated. Deliberately minimal — products,
/// cart, and orders are out of scope for this flow.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    final roleLabel = user?.role == UserRole.owner ? 'propriétaire' : 'client';

    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxxl),
              Text(
                'Bonjour, ${user?.name ?? ''}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vous êtes connecté en tant que $roleLabel.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => signOut(context),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
