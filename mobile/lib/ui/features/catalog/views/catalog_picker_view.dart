import 'package:flutter/material.dart';

import '../../../../data/models/catalog_product.dart';
import '../../../../data/models/store_product.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../../../core/widgets/product_image.dart';
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
    // Restoring (or anything else) there changes this row: bring it up to date
    // without reloading the pages the owner has scrolled through.
    await viewModel.syncItem(item.product.id);
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
    // The store or the catalog changed under the owner: look at this product
    // again, then say which.
    final current = await viewModel.syncItem(item.product.id);
    if (!mounted) {
      return;
    }
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
            if (!viewModel.hasLoadedOnce) {
              // Nothing loaded yet: the whole screen is the spinner or the
              // retry. Afterwards the search stays and the list reloads.
              return switch (viewModel.status) {
                CatalogPickerStatus.failed => AppLoadFailed(
                  title: 'Impossible de charger le catalogue.',
                  onRetry: viewModel.load,
                ),
                _ => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              };
            }
            if (viewModel.status == CatalogPickerStatus.ready &&
                viewModel.total == 0 &&
                !viewModel.hasActiveFilters) {
              return const _EmptyCatalog();
            }
            return _Browser(
              viewModel: viewModel,
              searchController: _searchController,
              onClearFilters: _clearFilters,
              onSelect: _select,
            );
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
    final ready = viewModel.status == CatalogPickerStatus.ready;
    final total = viewModel.total;

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
                        viewModel.clearSearch();
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
              ready ? '$total produit${total > 1 ? 's' : ''}' : ' ',
              style: textTheme.labelSmall,
            ),
          ),
        ),
        Expanded(
          child: switch (viewModel.status) {
            CatalogPickerStatus.loading => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            CatalogPickerStatus.failed => AppLoadFailed(
              title: 'Impossible de charger les produits.',
              onRetry: viewModel.load,
            ),
            CatalogPickerStatus.ready when viewModel.items.isEmpty =>
              _NoResults(onClear: onClearFilters),
            CatalogPickerStatus.ready => _ProductList(
              viewModel: viewModel,
              onSelect: onSelect,
            ),
          },
        ),
      ],
    );
  }
}

/// The loaded products, built lazily as they scroll into view; the next page
/// is requested when the end of the loaded rows comes near.
class _ProductList extends StatelessWidget {
  const _ProductList({required this.viewModel, required this.onSelect});

  /// How many rows before the end the next page is requested.
  static const _prefetchDistance = 8;

  final CatalogPickerViewModel viewModel;
  final ValueChanged<CatalogItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = viewModel.items;
    final hasFooter =
        viewModel.isLoadingMore ||
        viewModel.loadMoreFailed ||
        viewModel.hasMore;

    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.xs,
          AppSpacing.pagePadding,
          AppSpacing.xxl,
        ),
        itemCount: items.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return _ListFooter(viewModel: viewModel);
          }
          if (index >= items.length - _prefetchDistance &&
              viewModel.hasMore &&
              !viewModel.isLoadingMore &&
              !viewModel.loadMoreFailed) {
            // Not during the build: the view model notifies.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => viewModel.loadMore(),
            );
          }
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: _ProductRow(item: item, onSelect: () => onSelect(item)),
            ),
          );
        },
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.viewModel});

  final CatalogPickerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Text(
              'Impossible de charger la suite.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: viewModel.loadMore,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
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
///
/// A small picture leads the row: in a catalog of thousands, near-identical
/// pack names are told apart by sight. It is the same [ProductImage] as
/// everywhere (neutral placeholder without a photo, while loading, or on
/// error), decoded at its own size, and only for the rows that are built.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.item, required this.onSelect});

  final CatalogItem item;
  final VoidCallback onSelect;

  /// Smaller than the store catalogue's 56: these rows have fewer lines.
  static const _thumbnailSize = 48.0;

  /// Above this text scale the row keeps its width for the name.
  static const _thumbnailMaxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = item.product;
    final added = item.inMyStore;
    final archived = item.storeProductArchived;
    final blocked = added;
    final title = product.brand == null
        ? product.name
        : '${product.name}, ${product.brand!.name}';
    final showThumbnail =
        MediaQuery.textScalerOf(context).scale(16) / 16 <=
        _thumbnailMaxTextScale;

    return Semantics(
      button: !blocked,
      enabled: !blocked,
      label: added
          ? '$title, déjà ajouté'
          : archived
          ? '$title, archivé dans votre magasin, ouvrir pour restaurer'
          : 'Ajouter $title',
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
                // Inside the row's own semantics (which hide their children):
                // the row is announced by name, not as "an image".
                if (showThumbnail) ...[
                  ProductImage(photo: product.photo, size: _thumbnailSize),
                  const SizedBox(width: AppSpacing.md),
                ],
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
                      if (product.brand != null)
                        Text(product.brand!.name, style: textTheme.labelSmall),
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
