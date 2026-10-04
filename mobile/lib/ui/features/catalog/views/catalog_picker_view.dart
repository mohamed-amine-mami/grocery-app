import 'package:flutter/material.dart';

import '../../../../data/models/catalog_product.dart';
import '../../../../data/models/store_product.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../view_models/catalog_picker_view_model.dart';
import 'quick_add_sheet.dart';
import 'store_product_editor_view.dart';

/// "Ajouter depuis le catalogue" — the owner browses the global catalog and
/// adds products to the store. Everything shown is read-only catalog data: the
/// screen can neither create nor edit a product. Choosing a product opens the
/// quick-add sheet; once added, the row reads "Ajouté" and the owner can carry
/// on with the next one.
class CatalogPickerView extends StatefulWidget {
  const CatalogPickerView({super.key});

  @override
  State<CatalogPickerView> createState() => _CatalogPickerViewState();
}

class _CatalogPickerViewState extends State<CatalogPickerView> {
  CatalogPickerViewModel? _viewModel;
  final _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= CatalogPickerViewModel(
      catalogRepository: AppServices.of(context).catalogRepository,
    )..load();
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _searchController.clear();
    _viewModel!.clearFilters();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// A product to add opens quick-add; one the store archived opens its
  /// editor, where it can be restored (never added a second time).
  Future<void> _select(CatalogItem item) =>
      item.storeProductArchived ? _openArchived(item) : _add(item);

  Future<void> _openArchived(CatalogItem item) async {
    final viewModel = _viewModel!;
    final StoreProduct stored;
    try {
      stored = await AppServices.of(context).storeProductsRepository
          .get(item.storeProductId!);
    } catch (_) {
      if (mounted) {
        _say('Impossible d’ouvrir ce produit. Veuillez réessayer.');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final message = await openStoreProductEditor(context, stored);
    if (!mounted) {
      return;
    }
    // Restoring (or anything else) there changes this row: reload it.
    await viewModel.refresh();
    if (message != null && mounted) {
      _say(message);
    }
  }

  /// Opens the quick-add sheet for [item] and reflects what happened.
  Future<void> _add(CatalogItem item) async {
    final viewModel = _viewModel!;
    final outcome = await showQuickAddSheet(context, item);
    if (!mounted || outcome == null) {
      return;
    }
    final created = outcome.created;
    if (created != null) {
      viewModel.markAdded(item.product.id, created.id);
      _say('${item.product.name} ajouté à votre magasin.');
      return;
    }
    // The store or the catalog changed under the owner: reload, then say which.
    await viewModel.refresh();
    if (!mounted) {
      return;
    }
    final current = viewModel.itemFor(item.product.id);
    _say(
      current == null
          ? 'Ce produit n’est plus disponible dans le catalogue.'
          : current.inMyStore
          ? 'Ce produit est déjà dans votre magasin.'
          : current.storeProductArchived
          ? 'Ce produit est archivé dans votre magasin.'
          : 'Ce produit n’a pas pu être ajouté. Veuillez réessayer.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter depuis le catalogue')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel!,
          builder: (context, _) {
            final viewModel = _viewModel!;
            return switch (viewModel.status) {
              CatalogPickerStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              CatalogPickerStatus.failed => AppLoadFailed(
                title: 'Impossible de charger le catalogue.',
                onRetry: viewModel.load,
              ),
              CatalogPickerStatus.ready when viewModel.items.isEmpty =>
                const _EmptyCatalog(),
              CatalogPickerStatus.ready => _Browser(
                viewModel: viewModel,
                searchController: _searchController,
                onClearFilters: _clearFilters,
                onSelect: _select,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _Browser extends StatelessWidget {
  const _Browser({
    required this.viewModel,
    required this.searchController,
    required this.onClearFilters,
    required this.onSelect,
  });

  final CatalogPickerViewModel viewModel;
  final TextEditingController searchController;
  final VoidCallback onClearFilters;
  final ValueChanged<CatalogItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visible = viewModel.visibleItems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.sm,
            AppSpacing.pagePadding,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: searchController,
            onChanged: viewModel.setQuery,
            textInputAction: TextInputAction.search,
            // Product names are French proper nouns: no autocorrection (iOS
            // turned "tomate" into "tomato").
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Rechercher un produit',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: viewModel.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        searchController.clear();
                        viewModel.setQuery('');
                      },
                    ),
            ),
          ),
        ),
        _CategoryChips(viewModel: viewModel),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.sm,
            AppSpacing.pagePadding,
            AppSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visible.length} produit${visible.length > 1 ? 's' : ''}',
              style: textTheme.labelSmall,
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _NoResults(onClear: onClearFilters)
              : RefreshIndicator(
                  onRefresh: viewModel.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.xs,
                      AppSpacing.pagePadding,
                      AppSpacing.xxl,
                    ),
                    children: [
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final (index, item) in visible.indexed) ...[
                              if (index > 0) const Divider(height: 1),
                              _ProductRow(
                                item: item,
                                onSelect: () => onSelect(item),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.viewModel});

  final CatalogPickerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final filters = <(String, int?)>[
      ('Tous', null),
      for (final category in viewModel.categories) (category.name, category.id),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: Row(
        children: [
          for (final (label, value) in filters) ...[
            ChoiceChip(
              label: Text(label),
              selected: viewModel.categoryFilter == value,
              onSelected: (_) => viewModel.selectCategory(value),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// One catalog product. A product the store already sells is shown as
/// "Ajouté" (icon + text, never color alone) and cannot be added again; one the
/// store archived says "Archivé" and opens its editor to restore it — it is
/// never added a second time.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.item, required this.onSelect});

  final CatalogItem item;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = item.product;
    final added = item.inMyStore;
    final archived = item.storeProductArchived;
    final blocked = added;

    return Semantics(
      button: !blocked,
      enabled: !blocked,
      label: added
          ? '${product.name}, déjà ajouté'
          : archived
          ? '${product.name}, archivé dans votre magasin, ouvrir pour restaurer'
          : 'Ajouter ${product.name}',
      excludeSemantics: true,
      child: InkWell(
        onTap: blocked ? null : onSelect,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.ctaMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
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
                          color: blocked
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${product.category.name} · ${ProductFormat.unitLabel(product.defaultSaleUnit)}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (added)
                  const _StatusLabel(
                    icon: Icons.check_circle_rounded,
                    label: 'Ajouté',
                    color: AppColors.success,
                  )
                else if (archived)
                  const _StatusLabel(
                    icon: Icons.inventory_2_rounded,
                    label: 'Archivé',
                    color: AppColors.textSecondary,
                  )
                else
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Aucun produit trouvé',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Essayez un autre mot ou une autre catégorie.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: onClear,
            child: const Text('Effacer les filtres'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

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
            'Le catalogue est vide',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Aucun produit n’est disponible pour le moment.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
