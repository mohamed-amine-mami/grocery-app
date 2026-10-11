import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/view_models/auth_scope.dart';
import '../../auth/views/profile_photo.dart';
import '../../auth/views/sign_out.dart';

/// `Profil` tab — who is signed in, and sign out.
class CustomerProfileView extends StatelessWidget {
  const CustomerProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: ProfilePhoto(size: 112)),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Bonjour, ${user?.name ?? ''}',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vous êtes connecté en tant que client.',
                style: textTheme.bodySmall,
              ),
              if (user?.phoneNumber != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(user!.phoneNumber!, style: textTheme.labelLarge),
              ],
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
