import 'package:flutter/material.dart';

import '../../../../data/models/customer_order.dart';
import '../../../../data/models/order.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/polling_guard.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_load_failed.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../../orders/order_errors.dart';
import '../../orders/views/order_status_badge.dart';
import '../view_models/customer_order_labels.dart';
import '../view_models/customer_orders_view_model.dart';
import '../view_models/customer_scope.dart';
import 'customer_order_detail_view.dart';

/// `Commandes` tab — the customer's orders, newest first, kept fresh by
/// pull-to-refresh and by polling while the tab is the one being looked at.
class CustomerOrdersView extends StatefulWidget {
  const CustomerOrdersView({this.isActive = true, super.key});

  /// Whether this tab is the visible one. Polling only runs while it is.
  final bool isActive;

  @override
  State<CustomerOrdersView> createState() => _CustomerOrdersViewState();
}

class _CustomerOrdersViewState extends State<CustomerOrdersView> {
  CustomerOrdersViewModel? _viewModel;
  PollingGuard? _guard;
  bool _signingOut = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final viewModel = CustomerOrdersViewModel(
        repository: AppServices.of(context).customerOrdersRepository,
      )..addListener(_onChange);
      _viewModel = viewModel;
      viewModel.load();
      _guard = PollingGuard(
        visible: widget.isActive,
        onRun: viewModel.startPolling,
        onPause: viewModel.stopPolling,
        onResume: viewModel.refresh,
      )..attach();
    }
  }

  @override
  void didUpdateWidget(CustomerOrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _guard?.visible = widget.isActive;
  }

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
    _guard?.dispose();
    _viewModel?.removeListener(_onChange);
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _open(CustomerOrder order) async {
    _guard?.covered = true;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CustomerOrderDetailView(order: order)),
    );
    if (!mounted) {
      return;
    }
    _guard?.covered = false; // refreshes and resumes polling
    if (message != null) {
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
              CustomerOrdersStatus.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              CustomerOrdersStatus.failed => AppLoadFailed(
                title: 'Impossible de charger vos commandes.',
                onRetry: viewModel.load,
              ),
              CustomerOrdersStatus.ready => _OrderList(
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

  final CustomerOrdersViewModel viewModel;
  final ValueChanged<CustomerOrder> onOpen;

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
                  Text('Aucune commande', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Vos commandes apparaîtront ici.',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AppPrimaryButton(
                    label: 'Voir les magasins',
                    onPressed: () =>
                        CustomerScope.of(context).navigation
                            .select(CustomerTab.stores),
                  ),
                ],
              ),
            ),
          if (orders.isNotEmpty)
            // One list surface, hairlines between the orders.
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (index, order) in orders.indexed) ...[
                    if (index > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.pagePadding,
                        ),
                        child: Divider(height: 1),
                      ),
                    _OrderRow(order: order, onTap: () => onOpen(order)),
                  ],
                ],
              ),
            ),
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

/// One order of the list: the store and its status, when it is to be picked
/// up, then the code and the total. Same order of information on every row;
/// no colour per status (the badge says it, with an icon and a word).
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onTap});

  final CustomerOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ready = order.status == OrderStatus.readyForPickup;
    return InkWell(
      onTap: onTap,
      child: Semantics(
        button: true,
        hint: 'Ouvrir la commande',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(order.storeName, style: textTheme.titleMedium),
                    OrderStatusBadge(
                      status: order.status,
                      label: CustomerOrderLabels.status(order.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  DateFormatFr.pickup(order.requestedPickupAt),
                  style: textTheme.bodySmall,
                ),
                if (ready) ...[
                  // What to do next, in words, for the one order that waits.
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Présentez votre code au magasin.',
                    style: textTheme.labelLarge,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpacing.md,
                  children: [
                    Text(
                      order.code,
                      style: textTheme.labelSmall?.copyWith(
                        letterSpacing: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ProductFormat.price(order.totalMillimes),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
