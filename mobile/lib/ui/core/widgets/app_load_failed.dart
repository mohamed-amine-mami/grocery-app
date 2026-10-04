import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_primary_button.dart';

/// The "could not load" state of a list screen: what failed, a hint, and a
/// retry. Shared so every list says it the same way.
class AppLoadFailed extends StatelessWidget {
  const AppLoadFailed({required this.title, required this.onRetry, super.key});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Vérifiez votre connexion, puis réessayez.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(label: 'Réessayer', onPressed: onRetry),
        ],
      ),
    );
  }
}
