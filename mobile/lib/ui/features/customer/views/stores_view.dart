import 'package:flutter/material.dart';

import '../../../../data/models/customer_store.dart';
import '../../../core/app_services.dart';
import '../../../core/photo/photo_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../view_models/customer_scope.dart';
import '../view_models/stores_view_model.dart';
import 'store_catalog_view.dart';

/// `Magasins` tab — every store, closed ones included: a closed store can be
/// opened and browsed, it just cannot take an order.
class StoresView extends StatefulWidget {
  const StoresView({super.key});

  @override
  State<StoresView> createState() => _StoresViewState();
}

class _StoresViewState extends State<StoresView> {
  StoresViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= StoresViewModel(
      repository: AppServices.of(context).customerStoresRepository,
    )..load();
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _open(CustomerStore store) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => StoreCatalogView(store: store)),
    );
    if (mounted) {
      // A store may have opened or closed while the customer was inside.
      await _viewModel!.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CustomerScope.of(context).cart;
    return ListenableBuilder(
      listenable: Listenable.merge([_viewModel!, cart]),
      builder: (context, _) {
        final viewModel = _viewModel!;
        return Scaffold(
          appBar: AppBar(title: const Text('Magasins')),
          body: SafeArea(
            child: switch (viewModel.status) {
              StoresStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              StoresStatus.failed => AppLoadFailed(
                title: 'Impossible de charger les magasins.',
                onRetry: viewModel.load,
              ),
              StoresStatus.ready => RefreshIndicator(
                onRefresh: viewModel.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.pagePadding),
                  children: [
                    if (viewModel.refreshFailed) ...[
                      const AppErrorBanner(
                        message: 'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (viewModel.stores.isEmpty)
                      const _Empty()
                    else
                      for (final store in viewModel.orderedStores) ...[
                        _StoreCard(
                          store: store,
                          hasCart: cart.store?.id == store.id,
                          onTap: () => _open(store),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
              ),
            },
          ),
        );
      },
    );
  }
}

/// What a store's address says before its owner has filled it in. It is not
/// an address, so the card does not show it.
const _addressPlaceholder = 'Adresse à renseigner';

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.hasCart,
    required this.onTap,
  });

  final CustomerStore store;
  final bool hasCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final address = store.address.trim();
    final showAddress = address.toLowerCase() != _addressPlaceholder.toLowerCase();
    final description = store.description?.trim() ?? '';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Semantics(
          button: true,
          hint: 'Voir le catalogue',
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No photo: the card is as it always was.
                if (store.photo != null) ...[
                  PhotoImage(shape: PhotoShape.banner, url: store.photo),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(store.name, style: textTheme.titleMedium),
                    ),
                    StoreOpenBadge(isOpen: store.isOpen),
                  ],
                ),
                if (showAddress) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(store.address, style: textTheme.bodySmall),
                      ),
                    ],
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
                if (hasCart) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(
                        Icons.shopping_cart_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Panier en cours',
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Open or closed, as icon + text (never color alone). A closed store is a
/// calm state: it can still be browsed.
class StoreOpenBadge extends StatelessWidget {
  const StoreOpenBadge({required this.isOpen, super.key});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOpen
                ? Icons.check_circle_outline_rounded
                : Icons.lock_clock_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            isOpen ? 'Ouvert' : 'Fermé',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          const Icon(
            Icons.storefront_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Aucun magasin', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Les magasins apparaîtront ici.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
