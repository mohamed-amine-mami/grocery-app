import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../../auth/views/sign_out.dart';
import '../order_errors.dart';
import '../order_labels.dart';
import '../view_models/owner_orders_view_model.dart';
import 'order_detail_view.dart';
import 'order_status_badge.dart';

/// `Commandes` tab — the store's orders, newest first, with the pending count
/// up top, a status filter, pull-to-refresh and polling while the tab is the
/// one being looked at ([isActive]) and the app is in the foreground.
class OwnerOrdersView extends StatefulWidget {
  const OwnerOrdersView({this.isActive = true, this.filterRequest, super.key});

  /// Whether this tab is the visible one. Polling only runs while it is.
  final bool isActive;

  /// Another part of the app (the home's workload) asking for a status filter.
  /// A new request, even for the same status, applies the filter again.
  final OrdersFilterRequest? filterRequest;

  @override
  State<OwnerOrdersView> createState() => _OwnerOrdersViewState();
}

/// A request to show the order list on one status. Compared by identity: each
/// tap makes a new one.
class OrdersFilterRequest {
  const OrdersFilterRequest(this.status);

  final OrderStatus status;
}

class _OwnerOrdersViewState extends State<OwnerOrdersView>
    with WidgetsBindingObserver {
  OwnerOrdersViewModel? _viewModel;
  bool _inForeground = true;
  bool _detailOpen = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = OwnerOrdersViewModel(
        ordersRepository: AppServices.of(context).ordersRepository,
      )..addListener(_onChange);
      _viewModel!.load();
      _syncPolling();
    }
  }

  @override
  void didUpdateWidget(OwnerOrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final request = widget.filterRequest;
    if (request != null && !identical(request, oldWidget.filterRequest)) {
      _viewModel?.selectFilter(request.status);
    }
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        // Back on the tab: what it shows may be stale.
        _viewModel?.refresh();
      }
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
      _viewModel?.refresh();
    }
    _syncPolling();
  }

  /// Polling runs only while the tab is visible, the app is in the foreground
  /// and no detail screen covers the list.
  void _syncPolling() {
    final viewModel = _viewModel;
    if (viewModel == null) {
      return;
    }
    if (widget.isActive && _inForeground && !_detailOpen) {
      viewModel.startPolling();
    } else {
      viewModel.stopPolling();
    }
  }

  /// A rejected token ends the session, through the app's existing sign-out.
  void _onChange() {
    if (_viewModel?.failure?.kind == OrderFailureKind.sessionExpired &&
        !_signingOut &&
        mounted) {
      _signingOut = true;
      signOut(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel?.removeListener(_onChange);
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _open(Order order) async {
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
    // Whatever happened there, the list is behind.
    await _viewModel!.refresh();
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        return Scaffold(
          appBar: AppBar(title: const Text('Commandes')),
          body: SafeArea(
            child: switch (viewModel.status) {
              OrdersStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              OrdersStatus.failed => AppLoadFailed(
                title: 'Impossible de charger les commandes.',
                onRetry: viewModel.load,
              ),
              OrdersStatus.ready => _OrderList(
                viewModel: viewModel,
                onOpen: _open,
              ),
            },
          ),
        );
      },
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.viewModel, required this.onOpen});

  final OwnerOrdersViewModel viewModel;
  final ValueChanged<Order> onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final orders = viewModel.orders;

    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          _PendingCount(viewModel: viewModel),
          const SizedBox(height: AppSpacing.lg),
          _FilterChips(viewModel: viewModel),
          const SizedBox(height: AppSpacing.lg),
          if (viewModel.refreshFailed && viewModel.failure != null) ...[
            AppErrorBanner(message: viewModel.failure!.message),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    viewModel.filter == null
                        ? 'Aucune commande'
                        : 'Aucune commande · ${OrderLabels.filter(viewModel.filter)}',
                    style: textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Les nouvelles commandes apparaîtront ici.',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final order in orders) ...[
            _OrderCard(order: order, onTap: () => onOpen(order)),
            const SizedBox(height: AppSpacing.md),
          ],
          if (viewModel.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: viewModel.isLoadingMore
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : OutlinedButton(
                      onPressed: viewModel.loadMore,
                      child: const Text('Voir plus de commandes'),
                    ),
            ),
        ],
      ),
    );
  }
}

/// The backend's count of orders waiting for the owner, front and centre.
class _PendingCount extends StatelessWidget {
  const _PendingCount({required this.viewModel});

  final OwnerOrdersViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = viewModel.pendingCount ?? 0;
    final label = switch (count) {
      0 => 'Aucune commande en attente',
      1 => 'commande en attente',
      _ => 'commandes en attente',
    };
    final highlighted = count > 0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => viewModel.selectFilter(OrderStatus.pending),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                highlighted
                    ? Icons.notifications_active_rounded
                    : Icons.check_circle_outline_rounded,
                color: highlighted ? AppColors.warning : AppColors.success,
              ),
              const SizedBox(width: AppSpacing.md),
              if (highlighted) ...[
                Text(
                  '$count',
                  key: const Key('pending-count'),
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: Text(label, style: textTheme.bodyMedium)),
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

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.viewModel});

  final OwnerOrdersViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final filters = <OrderStatus?>[null, ...OrderStatus.values];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            ChoiceChip(
              label: Text(OrderLabels.filter(filter)),
              selected: viewModel.filter == filter,
              onSelected: (_) => viewModel.selectFilter(filter),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Semantics(
          button: true,
          hint: 'Ouvrir la commande',
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(order.code, style: textTheme.titleMedium),
                    ),
                    OrderStatusBadge(status: order.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(order.customerName, style: textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        DateFormatFr.pickup(order.requestedPickupAt),
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      ProductFormat.price(order.totalMillimes),
                      style: textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
