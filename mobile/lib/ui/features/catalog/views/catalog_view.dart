import 'package:flutter/material.dart';

import '../../../../data/models/store_product.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/product_image.dart';
import '../view_models/catalog_view_model.dart';
import 'catalog_picker_view.dart';
import 'store_product_editor_view.dart';

/// `Catalogue` tab — the store's active `StoreProduct`s, grouped by their
/// global category, with the owner's availability switch right in the list.
/// Tapping a row opens the StoreProduct editor; "Ajouter depuis le catalogue"
/// opens the global product picker. Archived products never appear here.
class CatalogView extends StatefulWidget {
  const CatalogView({super.key});

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  CatalogViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    _viewModel ??= CatalogViewModel(
      storeProductsRepository: services.storeProductsRepository,
    )..load();
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the catalog picker, where the owner adds products to the store,
  /// then reloads the list so what was added shows up.
  Future<void> _openPicker() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const CatalogPickerView()));
    if (mounted) {
      await _viewModel!.refresh();
    }
  }

  /// Opens the editor for [product], then reloads the list: whatever was
  /// saved or archived there shows up.
  Future<void> _edit(StoreProduct product) async {
    final message = await openStoreProductEditor(context, product);
    if (!mounted) {
      return;
    }
    await _viewModel!.refresh();
    if (message != null && mounted) {
      _showMessage(message);
    }
  }

  Future<void> _toggle(StoreProduct product) async {
    final error = await _viewModel!.toggleAvailability(product);
    if (error != null && mounted) {
      _showMessage(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        final showList =
            viewModel.status == CatalogStatus.ready &&
            viewModel.products.isNotEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('Catalogue')),
          floatingActionButton: showList
              ? FloatingActionButton.extended(
                  onPressed: _openPicker,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter depuis le catalogue'),
                )
              : null,
          body: SafeArea(
            child: switch (viewModel.status) {
              CatalogStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              CatalogStatus.failed => AppLoadFailed(
                title: 'Impossible de charger le catalogue.',
                onRetry: viewModel.load,
              ),
              CatalogStatus.ready when viewModel.products.isEmpty =>
                _EmptyState(onAdd: _openPicker),
              CatalogStatus.ready => _ProductList(
                viewModel: viewModel,
                onToggle: _toggle,
                onEdit: _edit,
              ),
            },
          ),
        );
      },
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.viewModel,
    required this.onToggle,
    required this.onEdit,
  });

  final CatalogViewModel viewModel;
  final ValueChanged<StoreProduct> onToggle;
  final ValueChanged<StoreProduct> onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final groups = viewModel.groups;
    final showChips = viewModel.categories.isNotEmpty;

    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Extra bottom padding keeps the last row clear of the add button.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.sm,
          AppSpacing.pagePadding,
          96,
        ),
        children: [
          if (showChips) ...[
            _FilterChips(viewModel: viewModel),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Text(
                'Aucun produit dans cette catégorie.',
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '${group.title} · ${group.products.length}',
                style: textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (index, product) in group.products.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    _ProductRow(
                      product: product,
                      isToggling: viewModel.isToggling(product),
                      onToggle: () => onToggle(product),
                      onEdit: () => onEdit(product),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.viewModel});

  final CatalogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final filters = <(String, int?)>[
      ('Tous', null),
      for (final category in viewModel.categories) (category.name, category.id),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, value) in filters) ...[
            ChoiceChip(
              label: Text(label),
              selected: viewModel.filter == value,
              onSelected: (_) => viewModel.selectFilter(value),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.isToggling,
    required this.onToggle,
    required this.onEdit,
  });

  final StoreProduct product;
  final bool isToggling;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // What customers can order — the owner's switch, the catalog and stock
    // combined — not just the switch.
    final available = product.isOrderable;
    final name = product.product.name;
    // The stock count is a fact the backend returns; whether customers can
    // order is still the backend's `isOrderable`, never computed here.
    final tracked = product.trackStock && product.stockQuantity != null;
    final outOfStock = tracked && product.stockQuantity == 0;
    final stock = tracked && !outOfStock
        ? ProductFormat.quantity(product.saleUnit, product.stockQuantity!)
        : null;

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Semantics(
                button: true,
                hint: 'Modifier',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductImage(photo: product.product.photo, size: 56),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: textTheme.bodyMedium?.copyWith(
                              color: available
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            ProductFormat.pricePerUnit(
                              product.saleUnit,
                              product.priceMillimes,
                            ),
                            style: textTheme.labelLarge,
                          ),
                          Text(
                            'Par tranche de ${ProductFormat.quantity(product.saleUnit, product.quantityStep)}',
                            style: textTheme.bodySmall,
                          ),
                          if (stock != null)
                            Text('Stock : $stock', style: textTheme.bodySmall),
                          if (outOfStock)
                            const _StatusLabel(
                              icon: Icons.remove_shopping_cart_outlined,
                              label: 'Rupture de stock',
                            )
                          else if (!available)
                            const _StatusLabel(
                              icon: Icons.block_rounded,
                              label: 'Indisponible',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Disponible : $name',
            child: Switch(
              // The owner's own switch; stock can make a product unorderable
              // while the switch stays on.
              value: product.isAvailable,
              onChanged: isToggling ? null : (_) => onToggle(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text + icon: unavailability never relies on color alone.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Aucun produit',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Choisissez les produits que vous vendez dans le catalogue, puis fixez leur prix.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(
            label: 'Ajouter depuis le catalogue',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
