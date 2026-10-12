import 'package:flutter/material.dart';

import '../../../../data/models/customer_store.dart';
import '../../../core/app_services.dart';
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
  final _searchController = TextEditingController();

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
    _searchController.dispose();
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

  void _clearSearch() {
    _searchController.clear();
    _viewModel!.search('');
  }

  /// The stores in their existing order, split in two by whether they are open
  /// (open first, as the view model already orders them), each under its
  /// heading with its count. A group with no store has no heading.
  List<Widget> _sections(List<CustomerStore> ordered, int? cartStoreId) {
    final groups = [
      (
        'Ouverts maintenant',
        [
          for (final s in ordered)
            if (s.isOpen) s,
        ],
      ),
      (
        'Fermés',
        [
          for (final s in ordered)
            if (!s.isOpen) s,
        ],
      ),
    ];
    final children = <Widget>[];
    for (final (title, stores) in groups) {
      if (stores.isEmpty) {
        continue;
      }
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.xxl));
      }
      children.add(_SectionHeading(title: title, count: stores.length));
      for (final (index, store) in stores.indexed) {
        if (index > 0) {
          children.add(const SizedBox(height: AppSpacing.md));
        }
        children.add(
          _StoreCard(
            store: store,
            hasCart: cartStoreId == store.id,
            onTap: () => _open(store),
          ),
        );
      }
    }
    return children;
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
                // A wide window gets a readable column, not stretched photos.
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxListWidth),
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        AppSpacing.pagePadding,
                        AppSpacing.pagePadding,
                        AppSpacing.xxxl,
                      ),
                      children: [
                        if (viewModel.refreshFailed) ...[
                          const AppErrorBanner(
                            message: 'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (viewModel.stores.isEmpty)
                          const _Empty()
                        else ...[
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            // Store names are not prose: no "correction".
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: viewModel.search,
                            decoration: InputDecoration(
                              hintText: 'Rechercher un magasin ou une ville',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: viewModel.query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Effacer la recherche',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: _clearSearch,
                                    ),
                            ),
                          ),
                          if (!cart.isEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            _CartShortcut(
                              storeName: cart.store?.name,
                              lineCount: cart.lineCount,
                              onTap: () =>
                                  CustomerScope.of(context).navigation
                                      .select(CustomerTab.cart),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          if (viewModel.visibleStores.isEmpty)
                            _NoResults(onClear: _clearSearch)
                          else
                            ..._sections(
                              viewModel.visibleStores,
                              cart.store?.id,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            },
          ),
        );
      },
    );
  }
}

/// The widest the list gets: on a wide window the cards stay a column.
const _maxListWidth = 560.0;

/// The store's photo is landscape, always at this ratio (2:1).
const _coverAspectRatio = 2 / 1;

/// A 16 px icon and the gap after it: where a line's text starts.
const _iconIndent = 16.0 + AppSpacing.xs;

/// A group's name and how many stores it holds — the catalogue's section
/// heading (`Boissons · 4`): the name 16/700, the count 14/400 Secondary.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: title,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: ' · $count', style: textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// One store, on its own card: its photo (only if it has one), its name with
/// the chevron, whether it is open, its address and description. The whole
/// card is the target; a closed store opens too.
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
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final address = store.address.trim();
    final showAddress =
        address.isNotEmpty &&
        address.toLowerCase() != storeAddressPlaceholder.toLowerCase();
    final description = store.description?.trim() ?? '';
    final photo = store.photo;
    final radius = BorderRadius.circular(AppRadii.card);
    // One card: the photo is its first child, clipped to the card's corners,
    // and the hairline is drawn over everything so the photo is outlined
    // like the rest of the card.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: Theme.of(context).dividerTheme.color ?? AppColors.disabled,
        ),
      ),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            hint: 'Voir le catalogue',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StoreCover(url: photo),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The name and the chevron share a line; the chevron
                        // stays at the first line of a name that wraps.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                store.name,
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _OpenState(isOpen: store.isOpen),
                        if (showAddress) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _IconLine(
                            icon: Icons.place_outlined,
                            child: Text(
                              address,
                              maxLines: scale > 1.3 ? null : 1,
                              overflow: scale > 1.3
                                  ? TextOverflow.clip
                                  : TextOverflow.ellipsis,
                              style: textTheme.bodySmall,
                            ),
                          ),
                        ],
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          // Under the address, aligned with its text, not
                          // with its pin.
                          Padding(
                            padding: EdgeInsets.only(
                              left: showAddress ? _iconIndent : 0,
                            ),
                            child: Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall,
                            ),
                          ),
                        ],
                        if (hasCart) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _IconLine(
                            icon: Icons.shopping_cart_rounded,
                            child: Text(
                              'Panier en cours',
                              style: textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 16 px Secondary icon and a text that wraps beside it.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: child),
      ],
    );
  }
}

/// Open or closed, in words with a mark: a green dot for open, a neutral
/// clock for closed. The word says it; the colour only helps.
class _OpenState extends StatelessWidget {
  const _OpenState({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.success : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 8),
            ),
          )
        else
          Icon(Icons.schedule_rounded, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            isOpen ? 'Ouvert' : 'Fermé',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// The top of every card: the store's photo, landscape (2:1), cropped to fit.
/// The space is always there, so nothing moves when a photo arrives or fails.
/// Beneath the photo sits the fallback — the warm cream with a quiet
/// storefront — which is all there is for a store with no photo, an unusable
/// address, or a photo that cannot be loaded. It also holds the space while a
/// photo loads; the photo fades in over it once it has.
class _StoreCover extends StatelessWidget {
  const _StoreCover({required this.url});

  final String? url;

  static bool _usable(String? url) {
    final uri = Uri.tryParse(url?.trim() ?? '');
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: _coverAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.background,
              child: Center(
                child: Icon(
                  Icons.storefront_rounded,
                  size: 40,
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
            ),
            if (_usable(url))
              LayoutBuilder(
                builder: (context, constraints) => Image.network(
                  url!.trim(),
                  fit: BoxFit.cover,
                  // Decoded at the size it is shown, not at its own.
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                  frameBuilder: (_, child, frame, synchronous) => synchronous
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: child,
                        ),
                  // A photo that cannot load leaves the fallback showing.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
          ],
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

/// The way back to a cart in progress: shown only while the cart has
/// products, it names the cart's store and says how many products it holds,
/// and opens the Panier tab. The cart itself stays the single source.
class _CartShortcut extends StatelessWidget {
  const _CartShortcut({
    required this.storeName,
    required this.lineCount,
    required this.onTap,
  });

  final String? storeName;
  final int lineCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = '$lineCount produit${lineCount > 1 ? 's' : ''}';
    final name = storeName?.trim() ?? '';
    final detail = name.isEmpty ? count : '$name · $count';
    return Semantics(
      button: true,
      label: 'Reprendre mon panier, $detail',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reprendre mon panier',
                          style: textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(detail, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A search that matched no store.
class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Aucun magasin trouvé',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Essayez un autre nom ou une autre ville.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: onClear,
            child: const Text('Effacer la recherche'),
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
