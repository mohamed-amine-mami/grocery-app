import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/views/sign_out.dart';
import '../view_models/cart_view_model.dart';
import '../view_models/checkout_failure.dart';
import '../view_models/checkout_view_model.dart';
import '../view_models/customer_scope.dart';
import 'cart_view.dart' show EstimatedTotal, LineDivider, LineThumbnail;
import 'customer_order_detail_view.dart';

/// The last step before an order is sent: what is ordered, when it will be
/// picked up, and that payment is at the store. The total here is an estimate;
/// the backend confirms the real one when the order is sent, and the order
/// shown afterwards is the backend's answer.
class CheckoutView extends StatefulWidget {
  const CheckoutView({super.key});

  @override
  State<CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends State<CheckoutView> {
  CheckoutViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final services = AppServices.of(context);
      _viewModel = CheckoutViewModel(
        ordersRepository: services.customerOrdersRepository,
        storesRepository: services.customerStoresRepository,
        cart: CustomerScope.of(context).cart,
      )..refreshStoreState();
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final viewModel = _viewModel!;
    final order = await viewModel.submit();
    if (!mounted) {
      return;
    }
    if (order != null) {
      // The server's order is what is shown; the cart is already cleared.
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) =>
              CustomerOrderDetailView(order: order, justPlaced: true),
        ),
      );
      return;
    }
    if (viewModel.failure?.kind == CheckoutFailureKind.sessionExpired) {
      await signOut(context);
    }
  }

  Future<void> _pickSlot() async {
    final viewModel = _viewModel!;
    viewModel.refreshSlots(); // never offer a time that has gone stale
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (context) =>
          _SlotSheet(slots: viewModel.slots, selected: viewModel.selectedSlot),
    );
    if (chosen != null) {
      viewModel.selectSlot(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CustomerScope.of(context).cart;
    return ListenableBuilder(
      listenable: Listenable.merge([_viewModel!, cart]),
      builder: (context, _) {
        final viewModel = _viewModel!;
        final store = cart.store;
        final textTheme = Theme.of(context).textTheme;
        final retrying = viewModel.pendingKey != null;

        return Scaffold(
          appBar: AppBar(title: const Text('Valider la commande')),
          bottomNavigationBar: Material(
            color: AppColors.surface,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: AppPrimaryButton(
                  label: retrying
                      ? 'Réessayer l’envoi'
                      : 'Confirmer la commande',
                  isLoading: viewModel.isSubmitting,
                  trailing: ProductFormat.price(cart.estimatedTotalMillimes),
                  onPressed: viewModel.canSubmit ? _submit : null,
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: store == null
                ? Center(
                    child: Text(
                      'Votre panier est vide.',
                      style: textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.pagePadding),
                    children: [
                      if (viewModel.failure != null) ...[
                        AppErrorBanner(message: viewModel.failure!.message),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (viewModel.storeClosed &&
                          viewModel.failure == null) ...[
                        AppErrorBanner(
                          message: CheckoutFailure.storeClosed.message,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      // Where: the store, as a heading (no card).
                      Text(store.name, style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(store.address, style: textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.xxl),
                      // When and how: one list surface of two rows.
                      Text('Retrait', style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            InkWell(
                              key: const Key('pickup-field'),
                              onTap: viewModel.isSubmitting ? null : _pickSlot,
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Heure de retrait souhaitée',
                                            style: textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            viewModel.selectedSlot == null
                                                ? 'Aucun horaire disponible'
                                                : DateFormatFr.pickup(
                                                    viewModel.selectedSlot!,
                                                  ),
                                            style: textTheme.titleMedium,
                                          ),
                                        ],
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
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              // Label and value side by side; at large
                              // text the value goes under its label whole,
                              // never broken inside a word.
                              child: SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.md,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    Text(
                                      'Paiement',
                                      style: textTheme.bodySmall,
                                    ),
                                    Text(
                                      'À la récupération',
                                      style: textTheme.labelLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'C’est une heure souhaitée, pas un créneau réservé.',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // What: the lines, on one list surface like the cart's.
                      Text('Votre commande', style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final (index, line) in cart.lines.indexed) ...[
                              if (index > 0) const LineDivider(),
                              _SummaryLine(line: line),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      EstimatedTotal(
                        totalMillimes: cart.estimatedTotalMillimes,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = line.product;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineThumbnail(photo: product.photo, quietWithoutPhoto: true),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The name has the whole width of the text column.
                Text(
                  product.name,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Quantity and unit price, then the line's amount — the same
                // anatomy as a cart line, in every row. The meta breaks
                // between its two pieces, never inside "2,000 DT / pièce".
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      '${ProductFormat.quantity(product.saleUnit, line.quantity)} ·',
                      style: textTheme.bodySmall,
                    ),
                    Text(
                      ProductFormat.pricePerUnit(
                        product.saleUnit,
                        product.priceMillimes,
                      ),
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  ProductFormat.price(line.subtotalMillimes),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// The pickup times, every 30 minutes, under their day.
class _SlotSheet extends StatelessWidget {
  const _SlotSheet({required this.slots, required this.selected});

  final List<DateTime> slots;
  final DateTime? selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final entries = <Widget>[];
    String? currentDay;
    for (final slot in slots) {
      final day = DateFormatFr.day(slot, now: now);
      final key = '${slot.year}-${slot.month}-${slot.day}';
      if (key != currentDay) {
        currentDay = key;
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.lg,
              AppSpacing.pagePadding,
              AppSpacing.xs,
            ),
            child: Text(day, style: textTheme.titleMedium),
          ),
        );
      }
      entries.add(
        ListTile(
          key: Key('slot-${slot.millisecondsSinceEpoch}'),
          title: Text(DateFormatFr.time(slot)),
          trailing: slot == selected
              ? const Icon(Icons.check_rounded, color: AppColors.primary)
              : null,
          onTap: () => Navigator.of(context).pop(slot),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: slots.isEmpty
          ? const Center(child: Text('Aucun horaire disponible.'))
          : ListView(children: entries),
    );
  }
}
