import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../auth/views/sign_out.dart';
import '../../store/views/store_create_view.dart';
import '../view_models/owner_store_view_model.dart';
import 'owner_shell.dart';

/// Where an authenticated `OWNER` lands. Asks the backend for their store:
/// with one → [OwnerShell]; without → [StoreCreateView]. An owner without a
/// store never sees the normal owner screens.
class OwnerGate extends StatefulWidget {
  const OwnerGate({super.key});

  @override
  State<OwnerGate> createState() => _OwnerGateState();
}

class _OwnerGateState extends State<OwnerGate> {
  OwnerStoreViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??=
        OwnerStoreViewModel(
            storeRepository: AppServices.of(context).storeRepository,
          )
          ..addListener(_onViewModelChanged)
          ..load();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel!;
    return switch (viewModel.status) {
      OwnerStoreStatus.loading => const _StoreLoading(),
      OwnerStoreStatus.noStore => const StoreCreateView(),
      OwnerStoreStatus.ready => OwnerShell(store: viewModel.store!),
      OwnerStoreStatus.failed => _StoreLoadFailed(onRetry: viewModel.load),
    };
  }
}

/// Same brand mark as the splash, so resolving the store right after the
/// session check doesn't flash a different screen.
class _StoreLoading extends StatelessWidget {
  const _StoreLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(),
            SizedBox(height: AppSpacing.xxl),
            SizedBox(
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

class _StoreLoadFailed extends StatelessWidget {
  const _StoreLoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Impossible de charger votre magasin.',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vérifiez votre connexion, puis réessayez.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppPrimaryButton(label: 'Réessayer', onPressed: onRetry),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
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
