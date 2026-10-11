import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_info_note.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../order_errors.dart';
import '../order_labels.dart';
import '../view_models/order_detail_view_model.dart';
import 'order_status_badge.dart';

/// One order: who, when, what, the server's total, the history, and the
/// actions the current status offers. Pops with a French message when the
/// order is no longer available to the store.
class OrderDetailView extends StatefulWidget {
  const OrderDetailView({required this.order, super.key});

  final Order order;

  @override
  State<OrderDetailView> createState() => _OrderDetailViewState();
}

class _OrderDetailViewState extends State<OrderDetailView> {
  OrderDetailViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = OrderDetailViewModel(
        ordersRepository: AppServices.of(context).ordersRepository,
        order: widget.order,
      );
      // The list's copy may be a poll old: show it now, refresh behind it.
      _handle(_viewModel!.refresh());
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an action's result: failures are shown in French, the order that is
  /// gone closes the screen, a rejected token signs out.
  Future<void> _handle(Future<OrderFailure?> result, {String? success}) async {
    final failure = await result;
    if (!mounted) {
      return;
    }
    if (failure == null) {
      if (success != null) {
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

  Future<void> _confirm() async {
    final viewModel = _viewModel!;
    final removed = viewModel.stagedItems;
    if (removed.isNotEmpty) {
      final ok = await _confirmDialog(
        context,
        title: 'Retirer ces produits ?',
        body:
            'Ils seront retirés de la commande avant sa confirmation : ${removed.map((i) => i.productName).join(', ')}.',
        action: 'Retirer et confirmer',
      );
      if (ok != true || !mounted) {
        return;
      }
    }
    await _handle(viewModel.confirm(), success: 'Commande confirmée.');
  }

  Future<void> _cancel() async {
    final reason = await _askCancelReason(context);
    if (reason == null || !mounted) {
      return;
    }
    await _handle(_viewModel!.cancel(reason), success: 'Commande annulée.');
  }

  Future<void> _noShow() async {
    final ok = await _confirmDialog(
      context,
      title: 'Marquer comme non récupérée ?',
      body: 'Le client n’est pas venu. Cette action est définitive.',
      action: 'Confirmer',
    );
    if (ok != true || !mounted) {
      return;
    }
    await _handle(
      _viewModel!.markNoShow(),
      success: 'Commande marquée comme non récupérée.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        final order = viewModel.order;
        final actions = viewModel.actions;

        return Scaffold(
          appBar: AppBar(title: Text('Commande ${order.code}')),
          bottomNavigationBar: actions.isEmpty
              ? null
              : _ActionBar(
                  viewModel: viewModel,
                  onConfirm: _confirm,
                  onCancel: _cancel,
                  onReady: () => _handle(
                    viewModel.markReady(),
                    success: 'Commande prête à retirer.',
                  ),
                  onComplete: () => _handle(
                    viewModel.complete(),
                    success: 'Commande récupérée.',
                  ),
                  onNoShow: _noShow,
                ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _handle(viewModel.refresh()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                children: [
                  _Summary(order: order),
                  const SizedBox(height: AppSpacing.xxl),
                  _Lines(viewModel: viewModel),
                  const SizedBox(height: AppSpacing.xxl),
                  _TotalAndPayment(viewModel: viewModel),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(order.code, style: textTheme.titleLarge)),
                OrderStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
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
            const SizedBox(height: AppSpacing.lg),
            _InfoRow(label: 'Client', value: order.customerName),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(label: 'Téléphone', value: order.customerPhone),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(
              label: 'Passée le',
              value: DateFormatFr.dateTime(order.createdAt),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: Text(label, style: textTheme.bodySmall)),
        Expanded(child: Text(value, style: textTheme.labelLarge)),
      ],
    );
  }
}

/// "Lignes conservées" and "Lignes retirées". While the order is pending the
/// owner can stage lines for removal here; nothing is sent until confirming.
class _Lines extends StatelessWidget {
  const _Lines({required this.viewModel});

  final OrderDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final kept = viewModel.keptItems;
    final staged = viewModel.stagedItems;
    final removed = viewModel.order.removedItems;
    final canStage = viewModel.canStageRemovals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lignes conservées · ${kept.length}',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (kept.isEmpty)
          Text('Aucune ligne conservée.', style: textTheme.bodySmall)
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, item) in kept.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _LineRow(
                    item: item,
                    trailing: canStage
                        ? TextButton(
                            onPressed: viewModel.isBusy
                                ? null
                                : () => viewModel.toggleRemoval(item.id),
                            child: const Text('Retirer'),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        if (viewModel.wouldRemoveAll) ...[
          const SizedBox(height: AppSpacing.md),
          const AppInfoNote(
            message: 'Toutes les lignes seraient retirées. Annulez plutôt la commande.',
          ),
        ],
        if (staged.isNotEmpty || removed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Lignes retirées · ${staged.length + removed.length}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, item) in [
                  ...staged,
                  ...removed,
                ].indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _LineRow(
                    item: item,
                    removed: true,
                    trailing: item.isRemoved
                        ? null
                        : TextButton(
                            onPressed: viewModel.isBusy
                                ? null
                                : () => viewModel.toggleRemoval(item.id),
                            child: const Text('Rétablir'),
                          ),
                  ),
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
  const _LineRow({required this.item, this.removed = false, this.trailing});

  final OrderItem item;
  final bool removed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = removed
        ? textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        item.isRemoved ? 'Retirée' : 'Sera retirée',
                        style: const TextStyle(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ProductFormat.price(item.lineTotalMillimes),
                style: muted ?? textTheme.labelLarge,
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalAndPayment extends StatelessWidget {
  const _TotalAndPayment({required this.viewModel});

  final OrderDetailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final order = viewModel.order;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Total', style: textTheme.bodyMedium)),
                Text(
                  ProductFormat.price(order.totalMillimes),
                  style: textTheme.titleLarge,
                ),
              ],
            ),
            if (viewModel.stagedRemovals.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              const AppInfoNote(
                message: 'Le total sera recalculé à la confirmation.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text('Paiement', style: textTheme.bodySmall)),
                Text('À la récupération', style: textTheme.labelLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historique', style: textTheme.titleMedium),
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
                    Text(OrderLabels.event(event), style: textTheme.labelLarge),
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

/// The actions for the current status, pinned at the bottom.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.viewModel,
    required this.onConfirm,
    required this.onCancel,
    required this.onReady,
    required this.onComplete,
    required this.onNoShow,
  });

  final OrderDetailViewModel viewModel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onReady;
  final VoidCallback onComplete;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    final busy = viewModel.isBusy;
    final children = <Widget>[];

    for (final action in viewModel.actions) {
      final (label, callback, primary, destructive) = switch (action) {
        OrderAction.confirm => (
          'Confirmer',
          viewModel.wouldRemoveAll ? null : onConfirm,
          true,
          false,
        ),
        OrderAction.ready => ('Prête', onReady, true, false),
        OrderAction.complete => (
          'Marquer comme récupérée',
          onComplete,
          true,
          false,
        ),
        OrderAction.cancel => ('Annuler', onCancel, false, true),
        OrderAction.noShow => (
          'Marquer comme non récupérée',
          onNoShow,
          false,
          false,
        ),
      };
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(
        primary
            ? AppPrimaryButton(
                label: label,
                onPressed: busy ? null : callback,
                isLoading: busy && callback != null,
              )
            : OutlinedButton(
                onPressed: busy ? null : callback,
                style: destructive
                    ? OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      )
                    : null,
                child: Text(label),
              ),
      );
    }

    return Material(
      color: AppColors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

Future<bool?> _confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Retour'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
}

/// Asks why the order is cancelled; the customer reads the answer. Completes
/// with the trimmed reason, or `null` when the owner backs out.
Future<String?> _askCancelReason(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _CancelReasonDialog(),
  );
}

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Annuler la commande ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Le client verra ce motif.'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motif'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(value.text.trim()),
            child: const Text('Annuler la commande'),
          ),
        ),
      ],
    );
  }
}
