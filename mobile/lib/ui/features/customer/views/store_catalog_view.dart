import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../../data/models/customer_product.dart';
import '../../../../data/models/customer_store.dart';
import '../../../../data/models/sale_unit.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/product_image.dart';
import '../view_models/cart_view_model.dart';
import '../view_models/customer_scope.dart';
import '../view_models/store_catalog_view_model.dart';
import 'quantity_stepper.dart';

/// One store's catalogue ("Liste" direction, `docs/design.md` 5.2): a green
/// store band, search, category tabs, and each category's products as rows on
/// one list surface (thumbnail, name, brand, price column with the add
/// control). A closed store can be browsed but nothing can be added; a product
/// the backend says cannot be ordered shows "Indisponible" and has no add
/// button. Stock is never shown.
class StoreCatalogView extends StatefulWidget {
  const StoreCatalogView({required this.store, super.key});

  final CustomerStore store;

  @override
  State<StoreCatalogView> createState() => _StoreCatalogViewState();
}

class _StoreCatalogViewState extends State<StoreCatalogView> {
  StoreCatalogViewModel? _viewModel;
  final _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final cart = CustomerScope.of(context).cart;
      _viewModel = StoreCatalogViewModel(
        repository: AppServices.of(context).customerStoresRepository,
        storeId: widget.store.id,
        // Freshly loaded prices and availability reach the cart's lines.
        onLoaded: (products) => cart.syncWithCatalog(widget.store.id, products),
      )..load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel?.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add(CustomerProduct product) async {
    final cart = CustomerScope.of(context).cart;
    final result = cart.add(widget.store, product);
    switch (result) {
      case CartAddResult.added:
        break;
      case CartAddResult.unavailable:
        _show('Ce produit n’est pas disponible pour le moment.');
      case CartAddResult.storeClosed:
        _show(
          'Ce magasin est fermé : vous ne pouvez pas commander pour le moment.',
        );
      case CartAddResult.needsStoreSwitch:
        final confirmed = await _confirmSwitch(cart.store!.name);
        if (confirmed == true && mounted) {
          cart
            ..switchStore(widget.store)
            ..add(widget.store, product);
        }
    }
  }

  /// Changing store empties the cart: only after an explicit yes.
  Future<bool?> _confirmSwitch(String currentStoreName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer de magasin ?'),
        content: Text(
          'Votre panier contient des produits de $currentStoreName. Changer de magasin videra votre panier.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Garder mon panier'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vider et changer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = CustomerScope.of(context);
    final cart = scope.cart;
    return ListenableBuilder(
      listenable: Listenable.merge([_viewModel!, cart]),
      builder: (context, _) {
        final viewModel = _viewModel!;
        final inCart = cart.store?.id == widget.store.id && !cart.isEmpty;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Light status-bar content over the green band.
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            bottomNavigationBar: inCart
                ? _CartBar(
                    cart: cart,
                    onOpen: () {
                      scope.navigation.select(CustomerTab.cart);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  )
                : null,
            body: Column(
              children: [
                _StoreBand(store: widget.store),
                Expanded(
                  child: switch (viewModel.status) {
                    StoreCatalogStatus.loading => const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                    StoreCatalogStatus.failed => AppLoadFailed(
                      title: 'Impossible de charger le catalogue.',
                      onRetry: viewModel.load,
                    ),
                    StoreCatalogStatus.ready => _Catalog(
                      store: widget.store,
                      viewModel: viewModel,
                      cart: cart,
                      searchController: _searchController,
                      onAdd: _add,
                    ),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The store's identity and state: a Primary band with white text. It is the
/// one large green surface of the screen.
class _StoreBand extends StatelessWidget {
  const _StoreBand({required this.store});

  final CustomerStore store;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final address = store.address.trim();
    // What an address says before its owner has filled it in is not one.
    final showAddress =
        address.isNotEmpty && address.toLowerCase() != 'adresse à renseigner';
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BackButton(color: Colors.white),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: AppSpacing.pagePadding,
                      ),
                      child: Text(
                        store.name,
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePadding,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _BandOpenState(isOpen: store.isOpen),
                    if (showAddress)
                      Text(
                        address,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open or closed on the band: icon + text, white on a white 16% fill.
class _BandOpenState extends StatelessWidget {
  const _BandOpenState({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
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
            color: Colors.white,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            isOpen ? 'Ouvert' : 'Fermé',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.store,
    required this.viewModel,
    required this.cart,
    required this.searchController,
    required this.onAdd,
  });

  final CustomerStore store;
  final StoreCatalogViewModel viewModel;
  final CartViewModel cart;
  final TextEditingController searchController;
  final ValueChanged<CustomerProduct> onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The store itself has nothing to offer right now: no products at all, or
    // some that none of which can be ordered. That is not a search with no
    // match, and filters mean nothing there.
    final products = viewModel.products;
    final storeEmpty = products.isEmpty;
    final storeUnavailable =
        !storeEmpty && products.every((product) => !product.isOrderable);
    final storeLevel = storeEmpty || storeUnavailable;
    final groups = storeLevel
        ? const <CustomerProductGroup>[]
        : viewModel.groups;
    const sidePadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.pagePadding,
    );
    // With one category selected, its tab already says which it is: the
    // heading is only for "Tous".
    final showHeadings = viewModel.categoryFilter == null;

    // Slivers, not a ListView of Columns: each category's rows are a lazy
    // list, so only the rows near the screen are built (a store can hold
    // hundreds of products).
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              store: store,
              viewModel: viewModel,
              searchController: searchController,
              showFilters: !storeLevel,
            ),
          ),
          if (storeLevel)
            SliverPadding(
              padding: sidePadding,
              sliver: SliverToBoxAdapter(
                child: _StoreNothingToOrder(
                  noProducts: storeEmpty,
                  onBrowseStores: () {
                    CustomerScope.of(context).navigation
                        .select(CustomerTab.stores);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ),
            )
          else if (groups.isEmpty)
            SliverPadding(
              padding: sidePadding,
              sliver: SliverToBoxAdapter(
                child: _NothingFound(
                  filtered: viewModel.hasActiveFilters,
                  onClear: () {
                    searchController.clear();
                    viewModel.clearFilters();
                  },
                ),
              ),
            ),
          for (final group in groups) ...[
            if (showHeadings)
              SliverPadding(
                padding: sidePadding,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: group.category.name,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: ' · ${group.products.length}',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: sidePadding,
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final product = group.products[index];
                  return _ProductRow(
                    key: ValueKey(product.id),
                    product: product,
                    storeOpen: store.isOpen,
                    quantity: cart.quantityOf(product.id),
                    cart: cart,
                    isFirst: index == 0,
                    isLast: index == group.products.length - 1,
                    onAdd: () => onAdd(product),
                  );
                }, childCount: group.products.length),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ],
      ),
    );
  }
}

/// What sits under the band: closed note, search and category tabs.
class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.viewModel,
    required this.searchController,
    this.showFilters = true,
  });

  final CustomerStore store;
  final StoreCatalogViewModel viewModel;
  final TextEditingController searchController;

  /// Search and category tabs: hidden when the store has nothing to filter.
  final bool showFilters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!store.isOpen)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.lg,
              AppSpacing.pagePadding,
              0,
            ),
            child: _ClosedNote(),
          ),
        if (showFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.lg,
              AppSpacing.pagePadding,
              0,
            ),
            child: TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              // Product names are not prose: the keyboard must not "correct" a
              // search (it turned "lait" into a name on iOS).
              autocorrect: false,
              enableSuggestions: false,
              onChanged: viewModel.search,
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
                          viewModel.search('');
                        },
                      ),
              ),
            ),
          ),
        if (showFilters && viewModel.categories.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding - AppSpacing.md,
              ),
              child: Row(
                children: [
                  for (final (label, id) in <(String, int?)>[
                    ('Tous', null),
                    for (final c in viewModel.categories) (c.name, c.id),
                  ])
                    _CategoryTab(
                      label: label,
                      selected: viewModel.categoryFilter == id,
                      onTap: () => viewModel.selectCategory(id),
                    ),
                ],
              ),
            ),
          ),
        if (viewModel.refreshFailed)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.lg,
              AppSpacing.pagePadding,
              0,
            ),
            child: AppErrorBanner(
              message: 'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
            ),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// One category in the strip: text with an underline when selected (not a
/// pill). At least 48 px tall.
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The minimum order, when it is worth saying before adding: one piece is the
/// obvious default, anything else (500 g, 6 pieces…) is not.
String? _minimumHint(CustomerProduct product) {
  final unit = product.saleUnit;
  if (unit == SaleUnit.piece && product.minQuantity == 1) {
    return null;
  }
  return 'Min. ${ProductFormat.quantity(unit, product.minQuantity)}';
}

class _ClosedNote extends StatelessWidget {
  const _ClosedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_rounded, size: 20, color: AppColors.warning),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Ce magasin est fermé pour le moment. Vous pouvez parcourir son catalogue, mais pas commander.',
              style: TextStyle(fontSize: 14, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// The white list surface, one slice per row: its fill and hairline outline,
/// rounded at the top of the first row and the bottom of the last. Painted per
/// row so that a long category stays a lazy list.
class _RowSurfacePainter extends CustomPainter {
  const _RowSurfacePainter({required this.isFirst, required this.isLast});

  final bool isFirst;
  final bool isLast;

  static const _line = Color(0x1A18221C);

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(AppRadii.card);
    const r = AppRadii.card;
    final fill = RRect.fromLTRBAndCorners(
      0,
      0,
      size.width,
      size.height,
      topLeft: isFirst ? radius : Radius.zero,
      topRight: isFirst ? radius : Radius.zero,
      bottomLeft: isLast ? radius : Radius.zero,
      bottomRight: isLast ? radius : Radius.zero,
    );
    canvas.drawRRect(fill, Paint()..color = AppColors.surface);

    // The outline is inset by half its width so that it is not clipped.
    final w = size.width - 0.5;
    final h = size.height - 0.5;
    const o = 0.5;
    final path = Path();
    if (isFirst) {
      path
        ..moveTo(o, isLast ? h - r : h)
        ..lineTo(o, r + o)
        ..arcToPoint(const Offset(r + o, o), radius: radius)
        ..lineTo(w - r, o)
        ..arcToPoint(Offset(w, r + o), radius: radius)
        ..lineTo(w, isLast ? h - r : h);
    } else {
      path
        ..moveTo(o, 0)
        ..lineTo(o, isLast ? h - r : h)
        ..moveTo(w, 0)
        ..lineTo(w, isLast ? h - r : h);
    }
    if (isLast) {
      if (isFirst) {
        path
          ..moveTo(w, h - r)
          ..arcToPoint(Offset(w - r, h), radius: radius)
          ..lineTo(r + o, h)
          ..arcToPoint(Offset(o, h - r), radius: radius);
      } else {
        path
          ..moveTo(o, h - r)
          ..arcToPoint(Offset(r + o, h), radius: radius, clockwise: false)
          ..lineTo(w - r, h)
          ..arcToPoint(Offset(w, h - r), radius: radius, clockwise: false);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RowSurfacePainter oldDelegate) =>
      oldDelegate.isFirst != isFirst || oldDelegate.isLast != isLast;
}

/// One product of the list (`docs/design.md` 4.1): thumbnail tile on the left;
/// on the right the name (brand, minimum) and, directly beneath, one line with
/// the price at the left and the control at the right edge. The cart is the
/// source of truth — the row only shows the [quantity] it is given and calls
/// the cart's own methods.
///
/// The price is always two short lines (amount, then unit) as tall as the
/// 44 px control, so adding a product never changes the row's height, and the
/// unit never wraps by accident. When the text column cannot hold the price
/// and the widest control side by side, the control goes under the price
/// instead — decided from measured widths, the same for every state of a row.
/// A row has no fixed height: it grows with the name, and nothing is dropped.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.storeOpen,
    required this.quantity,
    required this.cart,
    required this.isFirst,
    required this.isLast,
    required this.onAdd,
    super.key,
  });

  final CustomerProduct product;
  final bool storeOpen;
  final int quantity;
  final CartViewModel cart;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onAdd;

  /// A picture's tile; a product without one gets the smaller quiet tile, in
  /// the same slot, so the text of every row starts at the same place.
  static const _photoTile = 56.0;
  static const _quietTile = 48.0;
  static const _control = 44.0;

  /// Above this text size the thumbnail steps aside (its width goes to the
  /// text).
  static const _maxThumbnailTextScale = 1.6;

  static double _width(String text, TextStyle? style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final textScale = scaler.scale(16) / 16;
    final orderable = product.isOrderable;
    final brand = product.brand;
    final hint = _minimumHint(product);
    final hasPhoto = product.photo != null;
    final showThumbnail = textScale <= _maxThumbnailTextScale;
    const tabular = [FontFeature.tabularFigures()];

    final amountStyle = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: tabular,
      height: 1.2,
      color: orderable ? AppColors.textPrimary : AppColors.textSecondary,
    );
    final unitText = '/ ${ProductFormat.perUnit(product.saleUnit)}';
    final unitStyle = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    final priceText = ProductFormat.price(product.priceMillimes);
    final spoken = '$priceText par ${ProductFormat.perUnit(product.saleUnit)}';

    // The stepper's width follows its quantity text; the decision between
    // "side by side" and "stacked" uses the widest it can be (the minimum, the
    // current quantity, the maximum) so that it never flips while adding.
    double stepperFor(int q) =>
        2 * _control +
        _width(
          ProductFormat.quantity(product.saleUnit, q),
          textTheme.bodyMedium,
          scaler,
        ).ceilToDouble() +
        AppSpacing.sm;
    final stepperWidth = stepperFor(
      quantity == 0 ? product.minQuantity : quantity,
    );
    final widestStepper = [
      stepperFor(product.minQuantity),
      stepperFor(quantity == 0 ? product.minQuantity : quantity),
      if (product.maxQuantity != null) stepperFor(product.maxQuantity!),
    ].reduce((a, b) => a > b ? a : b);

    final thumbnail = SizedBox(
      width: _photoTile,
      child: Align(
        alignment: Alignment.topCenter,
        child: Opacity(
          opacity: orderable ? 1 : 0.45,
          child: ProductImage(
            photo: product.photo,
            size: hasPhoto ? _photoTile : _quietTile,
            fit: BoxFit.contain,
            tile: true,
            quiet: !hasPhoto,
          ),
        ),
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          // Rows grow with the text: no line limit once it is large.
          maxLines: textScale > 1.3 ? null : 3,
          // An ellipsis with no line limit would cut the name to one line.
          overflow: textScale > 1.3 ? TextOverflow.clip : TextOverflow.ellipsis,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: orderable ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        if (brand != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            brand.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall,
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(hint, style: textTheme.labelSmall),
        ],
      ],
    );

    Widget? control() {
      if (!orderable) {
        return const _UnavailableLabel();
      }
      if (!storeOpen) {
        return null;
      }
      if (quantity == 0) {
        return Tooltip(
          message: 'Ajouter ${product.name}',
          child: IconButton.filled(
            onPressed: onAdd,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              fixedSize: const Size.square(_control),
              minimumSize: const Size.square(_control),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        );
      }
      return SizedBox(
        width: stepperWidth,
        height: _control,
        child: QuantityStepper(
          compact: true,
          productName: product.name,
          unit: product.saleUnit,
          quantity: quantity,
          atMinimum: quantity - product.quantityStep < product.minQuantity,
          canIncrement:
              product.maxQuantity == null ||
              quantity + product.quantityStep <= product.maxQuantity!,
          onIncrement: () => cart.increment(product.id),
          onDecrement: () => cart.decrement(product.id),
        ),
      );
    }

    final price = _Price(
      price: priceText,
      unit: unitText,
      amountStyle: amountStyle,
      unitStyle: unitStyle,
      spoken: spoken,
    );
    final priceWidth = [
      _width(priceText, amountStyle, scaler),
      _width(unitText, unitStyle, scaler),
    ].reduce((a, b) => a > b ? a : b).ceilToDouble();
    final controlWidth = !orderable
        ? 124.0 * textScale
        : (storeOpen ? widestStepper : 0.0);

    final lead = showThumbnail ? _photoTile + AppSpacing.md : 0.0;

    return CustomPaint(
      painter: _RowSurfacePainter(isFirst: isFirst, isLast: isLast),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isFirst)
            Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.pagePadding + lead,
                right: AppSpacing.pagePadding,
              ),
              child: const Divider(height: 1),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePadding,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showThumbnail) ...[
                  thumbnail,
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBySide =
                          priceWidth + AppSpacing.md + controlWidth <=
                          constraints.maxWidth;
                      final c = control();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          text,
                          const SizedBox(height: AppSpacing.sm),
                          if (c == null)
                            Align(alignment: Alignment.centerLeft, child: price)
                          else if (sideBySide)
                            // As tall as the control, taller with large text.
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: _control,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: price,
                                    ),
                                  ),
                                  c,
                                ],
                              ),
                            )
                          else ...[
                            price,
                            const SizedBox(height: AppSpacing.sm),
                            Align(alignment: Alignment.centerRight, child: c),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The amount over its unit, left-aligned: two short lines, read as
/// "2,000 DT par pièce".
class _Price extends StatelessWidget {
  const _Price({
    required this.price,
    required this.unit,
    required this.amountStyle,
    required this.unitStyle,
    required this.spoken,
  });

  final String price;
  final String unit;
  final TextStyle? amountStyle;
  final TextStyle? unitStyle;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(price, style: amountStyle, maxLines: 1),
          Text(unit, style: unitStyle, maxLines: 1),
        ],
      ),
    );
  }
}

/// Text + icon: unavailability never relies on color alone. It says nothing
/// about why, and in particular nothing about stock.
class _UnavailableLabel extends StatelessWidget {
  const _UnavailableLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block_rounded, size: 16, color: AppColors.warning),
        SizedBox(width: AppSpacing.xs),
        Text(
          'Indisponible',
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }
}

/// The whole store has nothing to order: it has listed no products, or all of
/// its products are unavailable right now. Two different sentences, one way
/// out: back to the stores.
class _StoreNothingToOrder extends StatelessWidget {
  const _StoreNothingToOrder({
    required this.noProducts,
    required this.onBrowseStores,
  });

  final bool noProducts;
  final VoidCallback onBrowseStores;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            noProducts
                ? 'Ce magasin n’a pas encore ajouté de produits'
                : 'Aucun produit disponible pour le moment',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            noProducts
                ? 'Revenez plus tard, ou découvrez un autre magasin.'
                : 'Les produits de ce magasin ne peuvent pas être commandés '
                      'actuellement. Réessayez plus tard ou choisissez un '
                      'autre magasin.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(
            label: 'Voir les autres magasins',
            onPressed: onBrowseStores,
          ),
        ],
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.filtered, required this.onClear});

  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          Icon(
            filtered ? Icons.search_off_rounded : Icons.inventory_2_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            filtered ? 'Aucun produit trouvé' : 'Aucun produit pour le moment',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (filtered) ...[
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: onClear,
              child: const Text('Effacer les filtres'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The cart, one tap away from the catalogue: the count and the total beside
/// the action, on a white bar with a hairline top divider. Large text or a
/// narrow screen: the summary sits above a full-width button.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.onOpen});

  final CartViewModel cart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = cart.lineCount;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final stacked = scale > 1.3 || MediaQuery.sizeOf(context).width < 360;
    final label = Text(
      '$count ${count == 1 ? 'produit' : 'produits'}',
      style: textTheme.labelSmall,
    );
    final total = Text(
      ProductFormat.price(cart.estimatedTotalMillimes),
      style: textTheme.titleLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final button = ElevatedButton(
      onPressed: onOpen,
      child: const Text('Voir le panier'),
    );
    return Material(
      color: AppColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x1A18221C))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: stacked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: AppSpacing.md,
                        children: [label, total],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      button,
                    ],
                  )
                : Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [label, total],
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: button),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
