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
                  // The server's total, apart from the line amounts above
                  // it (20/700, no card), and how it will be paid.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text('Total', style: textTheme.bodyLarge),
                      ),
                      Text(
                        ProductFormat.price(order.totalMillimes),
                        style: textTheme.titleLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: AppSpacing.md,
                      children: [
                        Text('Paiement', style: textTheme.bodySmall),
                        Text('À la récupération', style: textTheme.labelLarge),
                      ],
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

/// The pickup ticket: the code, where the order stands and what it means,
/// the way it is going (tracker), then when and where to collect it.
///
/// The code is the big thing while the order can still be collected (pending,
/// confirmed, ready). Once it is over (collected, cancelled, not collected) it
/// stays readable but quiet: nothing says it can be presented.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final CustomerOrder order;

  static bool _open(OrderStatus status) =>
      status == OrderStatus.pending ||
      status == OrderStatus.confirmed ||
      status == OrderStatus.readyForPickup;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = CustomerOrderLabels.hint(order.status);
    final reason = order.status == OrderStatus.cancelled
        ? order.events.lastOrNull?.reason
        : null;
    final open = _open(order.status);
    const tabular = [FontFeature.tabularFigures()];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text('Code de retrait', style: textTheme.bodySmall),
                    OrderStatusBadge(
                      status: order.status,
                      label: CustomerOrderLabels.status(order.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: 'Code de retrait ${order.code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      order.code,
                      maxLines: 1,
                      style: open
                          ? textTheme.displaySmall?.copyWith(
                              letterSpacing: 1.5,
                              fontFeatures: tabular,
                            )
                          : textTheme.titleLarge?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              fontFeatures: tabular,
                            ),
                    ),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    hint,
                    style: open ? textTheme.bodyLarge : textTheme.bodySmall,
                  ),
                ],
                if (reason != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Motif : $reason', style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TicketFact(
                  icon: Icons.schedule_rounded,
                  label: 'Retrait souhaité',
                  value: DateFormatFr.pickup(order.requestedPickupAt),
                  strong: true,
                ),
                const SizedBox(height: AppSpacing.md),
                _TicketFact(
                  icon: Icons.storefront_rounded,
                  label: order.storeName,
                  value: order.storeAddress,
                ),
              ],
            ),
          ),
          if (order.status != OrderStatus.cancelled &&
              order.status != OrderStatus.noShow) ...[
            // The ticket's perforation, then the way it is going: the time
            // and the place come first, so they are on screen with the code.
            const _Perforation(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _StatusTracker(status: order.status),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dashed line across the ticket, between its code and its tracker.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dash = 6.0;
          const gap = 5.0;
          final count = (constraints.maxWidth / (dash + gap)).floor();
          return ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < count; i++)
                  const SizedBox(
                    width: dash,
                    height: 1,
                    child: ColoredBox(color: Color(0x3318221C)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// An icon and two lines: a small label over its value (or a name over its
/// address). The icon is a quiet Secondary Text one, not brand green.
class _TicketFact extends StatelessWidget {
  const _TicketFact({
    required this.icon,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: strong ? textTheme.bodySmall : textTheme.bodyLarge,
              ),
              Text(
                value,
                style: strong ? textTheme.titleMedium : textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
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

    Widget surface(List<OrderItem> items, {bool removed = false}) => Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Divider(height: 1),
              ),
            _LineRow(item: item, removed: removed),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Produits · ${kept.length}', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        surface(kept),
        if (removed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Retirés par le magasin · ${removed.length}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          surface(removed, removed: true),
        ],
      ],
    );
  }
}

/// One line of the order, the cart's anatomy without a control: name on the
/// whole width, `quantité · prix unitaire / unité`, then the line amount.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.item, this.removed = false});

  final OrderItem item;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.productName,
            style: removed
                ? nameStyle?.copyWith(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  )
                : nameStyle,
          ),
          const SizedBox(height: AppSpacing.xs),
          // Breaks between its two pieces, never inside "2,000 DT / pièce".
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              Text(
                '${ProductFormat.quantity(item.saleUnit, item.quantity)} ·',
                style: textTheme.bodySmall,
              ),
              Text(
                ProductFormat.pricePerUnit(
                  item.saleUnit,
                  item.unitPriceMillimes,
                ),
                style: textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ProductFormat.price(item.lineTotalMillimes),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: removed ? AppColors.textSecondary : null,
              decoration: removed ? TextDecoration.lineThrough : null,
            ),
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
                Flexible(
                  child: Text(
                    'Retiré de la commande',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
