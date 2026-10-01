import 'package:flutter/material.dart';

import 'authenticated_home.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_primary_button.dart';
import 'core/widgets/brand_mark.dart';
import 'features/auth/view_models/auth_scope.dart';
import 'features/auth/view_models/auth_view_model.dart';
import 'features/auth/views/splash_view.dart';

/// Decides, once at startup, whether a stored session can be restored.
/// Shows [AuthenticatedHome] directly when it can, otherwise the [SplashView] flow.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _bootstrapStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bootstrapStarted) {
      _bootstrapStarted = true;
      AuthScope.of(context).bootstrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return switch (auth.status) {
      AuthStatus.unknown => const _BootstrapLoading(),
      AuthStatus.authenticated => const AuthenticatedHome(),
      AuthStatus.unauthenticated => const SplashView(),
      AuthStatus.unreachable => _SessionCheckFailed(onRetry: auth.bootstrap),
    };
  }
}

/// Shown only while the stored session is being validated — brief, and only
/// for a returning user (checking a token against `GET /auth/me`). Carries
/// the same brand mark as [SplashView] so there's no visual flash between
/// the two, plus a small progress indicator since real work is in flight.
class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(),
            const SizedBox(height: AppSpacing.xxl),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stored session couldn't be checked because the backend is unreachable.
/// The session is kept; the owner can retry or sign out.
class _SessionCheckFailed extends StatelessWidget {
  const _SessionCheckFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandMark(iconSize: 96, spacing: AppSpacing.sm),
              const SizedBox(height: AppSpacing.xxxl),
              Text(
                'Impossible de joindre le serveur.',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vérifiez votre connexion, puis réessayez. Vous restez connecté.',
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppPrimaryButton(label: 'Réessayer', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
