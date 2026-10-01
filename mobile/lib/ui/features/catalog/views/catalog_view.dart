import 'package:flutter/material.dart';

import '../../../../data/models/product.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../view_models/catalog_view_model.dart';
import 'categories_view.dart';
import 'product_editor_view.dart';

/// `Catalogue` tab — the active products, organized by category, with the
/// availability switch right in the list. Categories are managed from the
/// app bar; archived products never appear here.
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
      productRepository: services.productRepository,
      categoryRepository: services.categoryRepository,
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

  Future<void> _openEditor([Product? product]) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ProductEditorView(product: product)),
    );
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message);
    await _viewModel!.load();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const CategoriesView()));
    if (mounted) {
      await _viewModel!.load();
    }
  }

  Future<void> _toggle(Product product) async {
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
          appBar: AppBar(
            title: const Text('Catalogue'),
            actions: [
              IconButton(
                tooltip: 'Gérer les catégories',
                icon: const Icon(Icons.category_rounded),
                onPressed: _openCategories,
              ),
            ],
          ),
          floatingActionButton: showList
              ? FloatingActionButton.extended(
                  onPressed: _openEditor,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter un produit'),
                )
              : null,
          body: SafeArea(
            child: switch (viewModel.status) {
              CatalogStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              CatalogStatus.failed => _LoadFailed(onRetry: viewModel.load),
              CatalogStatus.ready when viewModel.products.isEmpty =>
                _EmptyState(onAdd: _openEditor),
              CatalogStatus.ready => _ProductList(
                viewModel: viewModel,
                onOpen: _openEditor,
                onToggle: _toggle,
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
    required this.onOpen,
    required this.onToggle,
  });

  final CatalogViewModel viewModel;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onToggle;

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
                      onTap: () => onOpen(product),
                      onToggle: () => onToggle(product),
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
      if (viewModel.hasUncategorized)
        ('Sans catégorie', CatalogViewModel.uncategorizedFilter),
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
    required this.onTap,
    required this.onToggle,
  });

  final Product product;
  final bool isToggling;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final available = product.isAvailable;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
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
                  if (!available) ...[
                    const SizedBox(height: AppSpacing.xs),
                    // Text + icon: unavailability never relies on color alone.
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: AppColors.warning,
                        ),
                        SizedBox(width: AppSpacing.xs),
                        Text(
                          'Indisponible',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Semantics(
              label: 'Disponible : ${product.name}',
              child: Switch(
                value: available,
                onChanged: isToggling ? null : (_) => onToggle(),
              ),
            ),
          ],
        ),
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
            'Ajoutez vos premiers produits : prix, unité de vente et quantités commandables.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(label: 'Ajouter un produit', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

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
            'Impossible de charger le catalogue.',
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
