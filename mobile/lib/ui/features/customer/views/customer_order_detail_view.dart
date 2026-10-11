import 'package:flutter/material.dart';

import '../../../../data/models/customer_order.dart';
import '../../../../data/models/order.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/polling_guard.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../../orders/order_errors.dart';
import '../../orders/views/order_status_badge.dart';
import '../view_models/customer_order_detail_view_model.dart';
import '../view_models/customer_order_labels.dart';
import '../view_models/customer_scope.dart';

/// One order for its customer: the pickup code, where it stands, what was
/// ordered at which prices, the server's total, and the history. Everything
/// shown is what the backend returned. Polls while the order can still change.
class CustomerOrderDetailView extends StatefulWidget {
  const CustomerOrderDetailView({
    required this.order,
    this.justPlaced = false,
    super.key,
  });

  final CustomerOrder order;

  /// Shown right after the order was sent: a confirmation and the way back.
  final bool justPlaced;

  @override
  State<CustomerOrderDetailView> createState() =>
      _CustomerOrderDetailViewState();
}

class _CustomerOrderDetailViewState extends State<CustomerOrderDetailView> {
  CustomerOrderDetailViewModel? _viewModel;
  PollingGuard? _guard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final viewModel = CustomerOrderDetailViewModel(
        repository: AppServices.of(context).customerOrdersRepository,
        order: widget.order,
      );
      _viewModel = viewModel;
      _guard = PollingGuard(
        onRun: viewModel.startPolling,
        onPause: viewModel.stopPolling,
        onResume: () => _handle(viewModel.refresh()),
      )..attach();
      if (!widget.justPlaced) {
        // The list's copy may be a poll old: show it now, refresh behind it.
        _handle(viewModel.refresh());
      }
    }
  }

  @override
  void dispose() {
    _guard?.dispose();
    _viewModel?.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handle(Future<OrderFailure?> result, {String? success}) async {
    final failure = await result;
    if (!mounted || failure == null) {
      if (mounted && success != null) {
        _show(success);
      }
      return;
    }
    switch (failure.kind) {
      case OrderFailureKind.notFound:
        Navigator.of(context).pop(failure.message);
      case OrderFailureKind.sessionExpired:
        await signOut(context);
      default:
        _show(failure.message);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la commande ?'),
        content: const Text(
          'Votre commande sera annulée. Vous ne pourrez pas la rétablir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler la commande'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _handle(_viewModel!.cancel(), success: 'Commande annulée.');
  }

  void _goTo(CustomerTab tab) {
    CustomerScope.of(context).navigation.select(tab);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        final order = viewModel.order;
        final textTheme = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(title: Text('Commande ${order.code}')),
          bottomNavigationBar: viewModel.canCancel
              ? Material(
                  color: AppColors.surface,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.pagePadding),
                      child: OutlinedButton(
                        onPressed: viewModel.isBusy ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        child: const Text('Annuler la commande'),
                      ),
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _handle(viewModel.refresh()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                children: [
                  // The "just sent" welcome only fits while the store has yet to
                  // answer; once the order moved on (confirmed, ready,
                  // cancelled…) it would say something false.
                  if (widget.justPlaced &&
                      order.status == OrderStatus.pending) ...[
                    _PlacedBanner(
                      onOrders: () => _goTo(CustomerTab.orders),
                      onShop: () => _goTo(CustomerTab.stores),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _StatusCard(order: order),
                  const SizedBox(height: AppSpacing.xxl),
                  _Lines(order: order),
                  const SizedBox(height: AppSpacing.xxl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total',
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                ProductFormat.price(order.totalMillimes),
                                style: textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Paiement',
                                  style: textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                'À la récupération',
                                style: textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _History(order: order),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlacedBanner extends StatelessWidget {
  const _PlacedBanner({required this.onOrders, required this.onShop});

  final VoidCallback onOrders;
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Commande envoyée',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Le magasin va la confirmer. Vous pouvez suivre son état ici.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: 'Voir mes commandes', onPressed: onOrders),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onShop,
              child: const Text('Continuer mes achats'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = CustomerOrderLabels.hint(order.status);
    final reason = order.status == OrderStatus.cancelled
        ? order.events.lastOrNull?.reason
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Code de retrait', style: textTheme.bodySmall),
                      Text(order.code, style: textTheme.headlineSmall),
                    ],
                  ),
                ),
                OrderStatusBadge(
                  status: order.status,
                  label: CustomerOrderLabels.status(order.status),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(hint, style: textTheme.bodySmall),
            ],
            if (reason != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Motif : $reason', style: textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            _StatusTracker(status: order.status),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 24,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Retrait souhaité', style: textTheme.bodySmall),
                      Text(
                        DateFormatFr.pickup(order.requestedPickupAt),
                        style: textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  size: 24,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.storeName, style: textTheme.bodyMedium),
                      Text(order.storeAddress, style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where an order is on its way to being collected: sent → confirmed → ready →
/// collected. A cancelled or uncollected order is not a stage on this road, so
/// it shows nothing here (its status badge says it).
class _StatusTracker extends StatelessWidget {
  const _StatusTracker({required this.status});

  final OrderStatus status;

  /// Above this text scale the step names no longer fit under their icons.
  static const _labelsMaxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final reached = switch (status) {
      OrderStatus.pending => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.readyForPickup => 2,
      OrderStatus.completed => 3,
      OrderStatus.cancelled || OrderStatus.noShow => -1,
    };
    if (reached < 0) {
      return const SizedBox.shrink();
    }
    const labels = ['Envoyée', 'Confirmée', 'Prête', 'Récupérée'];
    // Four narrow columns cannot hold the words at large text sizes without
    // breaking them: keep the icons and name only the current step, whole.
    final compact =
        MediaQuery.textScalerOf(context).scale(16) / 16 > _labelsMaxTextScale;
    final steps = Row(
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: Semantics(
              label: index <= reached
                  ? 'Étape $label : atteinte'
                  : 'Étape $label : à venir',
              excludeSemantics: true,
              child: Column(
                children: [
                  Icon(
                    index <= reached
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: index <= reached
                        ? AppColors.primary
                        : AppColors.disabled,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: index == reached
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: index <= reached
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
    if (!compact) {
      return steps;
    }
    return Column(
      children: [
        steps,
        const SizedBox(height: AppSpacing.sm),
        Text(
          labels[reached],
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final kept = order.activeItems;
    final removed = order.removedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Produits · ${kept.length}', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, item) in kept.indexed) ...[
                if (index > 0) const Divider(height: 1),
                _LineRow(item: item),
              ],
            ],
          ),
        ),
        if (removed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Retirés par le magasin · ${removed.length}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, item) in removed.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _LineRow(item: item, removed: true),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.item, this.removed = false});

  final OrderItem item;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        // The amount sits on the name's first baseline.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: removed
                      ? textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        )
                      : textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${ProductFormat.quantity(item.saleUnit, item.quantity)} · ${ProductFormat.pricePerUnit(item.saleUnit, item.unitPriceMillimes)}',
                  style: textTheme.bodySmall,
                ),
                if (removed) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      SizedBox(width: AppSpacing.xs),
                      Text(
                        'Retiré de la commande',
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
          const SizedBox(width: AppSpacing.md),
          Text(
            ProductFormat.price(item.lineTotalMillimes),
            style: removed
                ? textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  )
                : textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Suivi', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: SizedBox(
            // Full width like the other cards (a card hugs its content).
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, event) in order.events.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.md),
                    Text(
                      CustomerOrderLabels.event(event),
                      style: textTheme.labelLarge,
                    ),
                    Text(
                      DateFormatFr.dateTime(event.createdAt),
                      style: textTheme.bodySmall,
                    ),
                    if (event.reason != null)
                      Text(
                        'Motif : ${event.reason}',
                        style: textTheme.bodySmall,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
