import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../auth/view_models/auth_scope.dart';
import '../../auth/views/profile_photo.dart';
import '../../orders/order_labels.dart';
import '../../orders/views/order_detail_view.dart';
import '../../orders/views/order_status_badge.dart';
import '../../store/view_models/store_edit_view_model.dart';
import '../view_models/owner_dashboard_view_model.dart';

/// Above this text size a pickup's time goes on its own line over its details
/// instead of sitting in a rail beside them, and an action row drops its icon
/// so the label and its supporting line keep the width.
const _maxTilesTextScale = 1.3;

bool _tilesAcross(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 <= _maxTilesTextScale;

/// `Accueil` tab — the store's day at a glance, most urgent first:
///
/// 1. who and where: the greeting and the store, open or closed;
/// 2. the setup checklist, until the store is ready to take orders;
/// 3. **À traiter** — how many orders wait for the store at each step, each a
///    way into the order list filtered on that step;
/// 4. **Prochains retraits** — the next pickups, soonest first;
/// 5. **Stock** — products customers cannot order because of their stock.
///
/// Every number is the backend's own; there is no analytics, revenue or chart
/// here on purpose. While this tab is the visible one (and the app is in the
/// foreground, and no order page covers it) it refreshes every 30 seconds.
class OwnerHomeView extends StatefulWidget {
  const OwnerHomeView({
    required this.storeViewModel,
    required this.dashboardViewModel,
    required this.onOpenCatalog,
    required this.onOpenStore,
    required this.onOpenOrders,
    this.isActive = true,
    super.key,
  });

  final StoreEditViewModel storeViewModel;
  final OwnerDashboardViewModel dashboardViewModel;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenStore;

  /// Opens the Commandes tab with this status as its filter.
  final ValueChanged<OrderStatus> onOpenOrders;

  /// Whether this tab is the visible one. Polling only runs while it is.
  final bool isActive;

  @override
  State<OwnerHomeView> createState() => _OwnerHomeViewState();
}

class _OwnerHomeViewState extends State<OwnerHomeView>
    with WidgetsBindingObserver {
  bool _inForeground = true;
  bool _detailOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPolling();
  }

  @override
  void didUpdateWidget(OwnerHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dashboardViewModel != oldWidget.dashboardViewModel) {
      oldWidget.dashboardViewModel.stopPolling();
    }
    if (widget.isActive != oldWidget.isActive ||
        widget.dashboardViewModel != oldWidget.dashboardViewModel) {
      _syncPolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _inForeground) {
      return;
    }
    _inForeground = foreground;
    if (foreground && widget.isActive && !_detailOpen) {
      widget.dashboardViewModel.refresh();
    }
    _syncPolling();
  }

  /// Polling runs only while the tab is visible, the app is in the foreground
  /// and no order page covers the home.
  void _syncPolling() {
    final dashboard = widget.dashboardViewModel;
    if (widget.isActive && _inForeground && !_detailOpen) {
      dashboard.startPolling();
    } else {
      dashboard.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dashboardViewModel.stopPolling();
    super.dispose();
  }

  Future<void> _openOrder(Order order) async {
    setState(() => _detailOpen = true);
    _syncPolling();
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => OrderDetailView(order: order)),
    );
    if (!mounted) {
      return;
    }
    setState(() => _detailOpen = false);
    _syncPolling();
    // Whatever happened there, the numbers are behind.
    widget.dashboardViewModel.refresh();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    final textTheme = Theme.of(context).textTheme;
    final storeViewModel = widget.storeViewModel;
    final dashboardViewModel = widget.dashboardViewModel;

    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([storeViewModel, dashboardViewModel]),
          builder: (context, _) {
            final store = storeViewModel.store;
            final dashboard = dashboardViewModel;
            final steps = [
              _Step(
                title: 'Ajouter des produits',
                hint: 'Prix, unité de vente et quantités.',
                // Done as soon as one product can be ordered: no minimum.
                isDone: dashboard.hasOrderable,
                status: dashboard.hasOrderable ? null : 'À compléter',
                detail: dashboard.hasProduct
                    ? _inventory(
                        dashboard.productCount,
                        dashboard.orderableCount,
                      )
                    : null,
                onTap: widget.onOpenCatalog,
              ),
              _Step(
                title: 'Ouvrir le magasin',
                hint: 'Vos clients pourront alors commander.',
                isDone: store.isOpen,
                onTap: widget.onOpenStore,
              ),
            ];
            final setupComplete = steps.every((step) => step.isDone);
            final productsReady = dashboard.status == DashboardStatus.ready;
            final ordersFailed =
                dashboard.ordersStatus == DashboardStatus.failed;
            // A store still being set up, with nothing under way, has nothing
            // to show but its checklist.
            final showOperations =
                setupComplete ||
                dashboard.ordersStatus != DashboardStatus.ready ||
                dashboard.hasActivity;

            return RefreshIndicator(
              onRefresh: dashboard.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.xxxl,
                ),
                children: [
                  Row(
                    children: [
                      const ProfilePhoto(size: 48),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Bonjour, ${user?.name ?? ''}',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _StoreStrip(
                    name: store.name,
                    address: store.address,
                    isOpen: store.isOpen,
                  ),
                  if (dashboard.status == DashboardStatus.failed) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Impossible de charger la configuration. Tirez vers le bas pour réessayer.',
                      style: textTheme.bodySmall,
                    ),
                  ] else if (productsReady && !setupComplete) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _SetupChecklist(steps: steps),
                  ],
                  if (showOperations) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _WorkloadHeading(dashboard: dashboard),
                    _Workload(
                      dashboard: dashboard,
                      onOpen: widget.onOpenOrders,
                      onRetry: dashboard.refresh,
                    ),
                    if (!ordersFailed) ...[
                      const SizedBox(height: AppSpacing.xl),
                      const _SectionHeading('Prochains retraits'),
                      _Pickups(dashboard: dashboard, onOpen: _openOrder),
                    ],
                  ],
                  if (productsReady && dashboard.hasProduct) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionHeading('Stock'),
                    _StockAlerts(
                      outOfStock: dashboard.outOfStockCount,
                      belowMinimum: dashboard.belowMinimumCount,
                      onOpenCatalog: widget.onOpenCatalog,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "3 produits · 2 disponibles à la commande" — facts, not a target.
String _inventory(int total, int orderable) {
  final products = '$total produit${total > 1 ? 's' : ''}';
  final available = orderable == 0
      ? 'aucun disponible à la commande'
      : '$orderable disponible${orderable > 1 ? 's' : ''} à la commande';
  return '$products · $available';
}

/// A section's name — the same 16/700 heading as the customer catalogue's.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The store: its name and address, and whether customers can order. Flat —
/// a quiet tint, no border — so the workload below is the only framed block
/// at the top. Open or closed is icon + text, never colour alone.
class _StoreStrip extends StatelessWidget {
  const _StoreStrip({
    required this.name,
    required this.address,
    required this.isOpen,
  });

  final String name;
  final String address;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = isOpen ? AppColors.success : AppColors.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isOpen ? AppColors.primary.withValues(alpha: 0.08) : null,
        border: isOpen ? null : Border.all(color: const Color(0x1A18221C)),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(name, style: textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOpen
                          ? Icons.storefront_rounded
                          : Icons.lock_clock_rounded,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        isOpen ? 'Magasin ouvert' : 'Magasin fermé',
                        style: textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(address, style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isOpen
                  ? 'Les clients peuvent passer commande.'
                  : 'Le magasin n’accepte pas de commandes pour le moment.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// How many orders wait for the store at each step: three action rows on one
/// subtly framed surface, each a way into the order list on that step. The
/// counts are the dashboard's own (the backend's totals); the header's total
/// is their sum and nothing else. The one row that asks for action now —
/// orders to confirm, when there are some — wears the Citrus accent.
class _Workload extends StatelessWidget {
  const _Workload({
    required this.dashboard,
    required this.onOpen,
    required this.onRetry,
  });

  final OwnerDashboardViewModel dashboard;
  final ValueChanged<OrderStatus> onOpen;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (dashboard.ordersStatus == DashboardStatus.failed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Impossible de charger les commandes.',
                  style: textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    final known = dashboard.ordersStatus == DashboardStatus.ready;
    final rows = [
      _ActionRow(
        label: 'À confirmer',
        supporting: 'Nouvelles commandes',
        icon: Icons.inbox_rounded,
        iconColor: AppColors.warning,
        iconBackground: AppColors.accent.withValues(alpha: 0.22),
        count: known ? dashboard.pendingCount : null,
        urgent: true,
        spoken: 'en attente de confirmation',
        onTap: () => onOpen(OrderStatus.pending),
      ),
      _ActionRow(
        label: 'À préparer',
        supporting: 'Commandes confirmées',
        icon: Icons.shopping_basket_rounded,
        iconColor: AppColors.primary,
        iconBackground: AppColors.primary.withValues(alpha: 0.10),
        count: known ? dashboard.confirmedCount : null,
        spoken: 'à préparer',
        onTap: () => onOpen(OrderStatus.confirmed),
      ),
      _ActionRow(
        label: 'Prêtes à retirer',
        supporting: 'En attente du client',
        icon: Icons.shopping_bag_rounded,
        iconColor: AppColors.success,
        iconBackground: AppColors.textSecondary.withValues(alpha: 0.10),
        count: known ? dashboard.readyCount : null,
        spoken: 'prêtes à retirer',
        onTap: () => onOpen(OrderStatus.readyForPickup),
      ),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              const Padding(
                // Inset to the text, past the icon.
                padding: EdgeInsets.only(
                  left: AppSpacing.lg + 44 + AppSpacing.md,
                ),
                child: Divider(height: 1),
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// The section's title and, once the counts are known, how many orders they
/// add up to ("7 commandes").
class _WorkloadHeading extends StatelessWidget {
  const _WorkloadHeading({required this.dashboard});

  final OwnerDashboardViewModel dashboard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = dashboard.ordersStatus == DashboardStatus.ready
        ? dashboard.pendingCount +
              dashboard.confirmedCount +
              dashboard.readyCount
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      // Side by side; the total drops under the title when they do not fit.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            Semantics(
              header: true,
              child: Text(
                'À traiter',
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (total != null)
              Text(
                '$total commande${total > 1 ? 's' : ''}',
                style: textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.supporting,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.count,
    required this.spoken,
    required this.onTap,
    this.urgent = false,
  });

  final String label;
  final String supporting;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  /// `null` while the numbers are not known yet.
  final int? count;
  final String spoken;
  final VoidCallback onTap;

  /// Whether a non-zero count asks for action now (the Citrus accent).
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = count;
    final highlight = urgent && (value ?? 0) > 0;
    final number = Text(
      value == null ? '–' : '$value',
      style: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: (value == null || value == 0) && !highlight
            ? AppColors.textSecondary
            : AppColors.textPrimary,
      ),
    );
    final iconBox = DecoratedBox(
      decoration: BoxDecoration(
        color: iconBackground,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, size: 22, color: iconColor),
      ),
    );
    final labelText = Text(
      label,
      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final supportingText = Text(supporting, style: textTheme.bodySmall);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [labelText, supportingText],
    );
    final counter = highlight
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadii.badge),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              child: number,
            ),
          )
        : number;
    const chevron = Icon(
      Icons.chevron_right_rounded,
      color: AppColors.textSecondary,
    );
    return Semantics(
      button: true,
      enabled: value != null,
      label: value == null
          ? label
          : '$value ${value == 1 ? 'commande' : 'commandes'} $spoken',
      hint: 'Ouvrir la liste',
      excludeSemantics: true,
      child: InkWell(
        onTap: value == null ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: _tilesAcross(context)
                ? Row(
                    children: [
                      iconBox,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: texts),
                      const SizedBox(width: AppSpacing.md),
                      counter,
                      const SizedBox(width: AppSpacing.xs),
                      chevron,
                    ],
                  )
                // Large text: the icon steps aside and the supporting line
                // gets the whole width under the label and the count.
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: labelText),
                          const SizedBox(width: AppSpacing.md),
                          counter,
                          const SizedBox(width: AppSpacing.xs),
                          chevron,
                        ],
                      ),
                      supportingText,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The next pickups, soonest requested time first, on one surface. The time
/// leads each row (it is what the owner plans around), then who and which
/// order. A time that has passed is said in words — it is the customer's
/// desired time, not a reservation, so it is a note and not an alarm.
class _Pickups extends StatelessWidget {
  const _Pickups({required this.dashboard, required this.onOpen});

  final OwnerDashboardViewModel dashboard;
  final ValueChanged<Order> onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (dashboard.ordersStatus == DashboardStatus.loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text('Chargement des retraits…', style: textTheme.bodySmall),
        ),
      );
    }
    final pickups = dashboard.upcomingPickups;
    if (pickups.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aucun retrait prévu', style: textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Les commandes confirmées apparaissent ici, avec leur heure de retrait souhaitée.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final now = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, order) in pickups.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _PickupRow(
              order: order,
              past: OwnerDashboardViewModel.isRequestedTimePast(order, now),
              onTap: () => onOpen(order),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickupRow extends StatelessWidget {
  const _PickupRow({
    required this.order,
    required this.past,
    required this.onTap,
  });

  final Order order;
  final bool past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Time rail at the left at normal text; above 1.3× the time and day go
    // on a line of their own over the details, which keep the whole width.
    final rail = _tilesAcross(context);
    final timeText = Text(
      DateFormatFr.time(order.requestedPickupAt),
      style: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final dayText = Text(
      DateFormatFr.day(order.requestedPickupAt),
      style: textTheme.labelSmall,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          order.customerName,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              order.code,
              style: textTheme.labelSmall?.copyWith(
                letterSpacing: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            OrderStatusBadge(
              status: order.status,
              label: OrderLabels.status(order.status),
            ),
          ],
        ),
        if (past) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Heure souhaitée passée',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    return Semantics(
      button: true,
      hint: 'Ouvrir la commande',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: rail
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 64),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [timeText, dayText],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: details),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.end,
                              children: [timeText, dayText],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            details,
                          ],
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Products customers cannot order because of their stock — the backend's
/// verdict, not a threshold of ours — each row a way into the catalogue. With
/// none, one quiet line says so.
class _StockAlerts extends StatelessWidget {
  const _StockAlerts({
    required this.outOfStock,
    required this.belowMinimum,
    required this.onOpenCatalog,
  });

  final int outOfStock;
  final int belowMinimum;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (outOfStock == 0 && belowMinimum == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Icon(Icons.task_alt_rounded, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Aucune alerte de stock',
                  style: textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      );
    }
    String products(int count) => '$count produit${count > 1 ? 's' : ''}';
    final rows = [
      if (outOfStock > 0)
        _AlertRow(
          icon: Icons.remove_shopping_cart_rounded,
          count: products(outOfStock),
          label: 'en rupture de stock',
          onTap: onOpenCatalog,
        ),
      if (belowMinimum > 0)
        _AlertRow(
          icon: Icons.inventory_2_rounded,
          count: products(belowMinimum),
          label: 'sous le minimum de commande',
          onTap: onOpenCatalog,
        ),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const Divider(height: 1),
            row,
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon,
    required this.count,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$count $label',
      hint: 'Ouvrir le catalogue',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.warning),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: count,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: ' $label', style: textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.title,
    required this.hint,
    required this.isDone,
    required this.onTap,
    this.status,
    this.detail,
  });

  final String title;
  final String hint;
  final bool isDone;

  /// A short state word for a step that is not done (text, not just colour).
  final String? status;

  /// Facts about the step, shown whether or not it is done.
  final String? detail;
  final VoidCallback onTap;
}

class _SetupChecklist extends StatelessWidget {
  const _SetupChecklist({required this.steps});

  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((step) => step.isDone).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('Démarrer votre magasin · $done/${steps.length}'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, step) in steps.indexed) ...[
                if (index > 0) const Divider(height: 1),
                _StepRow(step: step),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label:
          '${step.title}, ${step.isDone ? 'terminé' : (step.status ?? 'à faire')}'
          '${step.detail == null ? '' : ', ${step.detail}'}',
      button: !step.isDone,
      excludeSemantics: true,
      child: InkWell(
        // A finished step is informational; only open ones are actionable.
        onTap: step.isDone ? null : step.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                step.isDone
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: step.isDone
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: textTheme.bodyMedium?.copyWith(
                        color: step.isDone
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (step.detail != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(step.detail!, style: textTheme.bodySmall),
                    ],
                    if (!step.isDone && step.detail == null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(step.hint, style: textTheme.bodySmall),
                    ],
                    if (!step.isDone && step.status != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        step.status!,
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!step.isDone)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
