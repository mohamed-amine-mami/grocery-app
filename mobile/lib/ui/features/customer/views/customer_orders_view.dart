import 'package:flutter/material.dart';

import '../../../../data/models/customer_order.dart';
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final CustomerOrder order;
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
                    OrderStatusBadge(
                      status: order.status,
                      label: CustomerOrderLabels.status(order.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(order.storeName, style: textTheme.bodySmall),
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
