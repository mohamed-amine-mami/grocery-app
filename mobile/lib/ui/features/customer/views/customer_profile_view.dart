import 'package:flutter/material.dart';

import '../../../../data/models/customer_order.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../auth/view_models/auth_scope.dart';
import '../../auth/views/profile_photo.dart';
import '../../auth/views/sign_out.dart';
import '../../orders/views/order_status_badge.dart';
import '../view_models/customer_order_labels.dart';
import '../view_models/customer_orders_view_model.dart';
import '../view_models/customer_scope.dart';
import 'customer_order_detail_view.dart';

/// Above this text size the account rows stack their label over their value
/// and the small icons step aside, so a long value keeps the width.
const _maxInlineTextScale = 1.3;

bool _isInline(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 <= _maxInlineTextScale;

/// How many of the newest orders the profile looks at to find the live one.
const _ordersWindow = 10;

/// `Profil` tab — who is signed in, the order that is under way (or the
/// latest one), the account details the app holds, and sign out. The details
/// are read-only: the backend has no endpoint to change them.
class CustomerProfileView extends StatefulWidget {
  const CustomerProfileView({this.isActive = true, super.key});

  /// Whether this tab is the visible one: the orders are reloaded when it
  /// becomes so.
  final bool isActive;

  @override
  State<CustomerProfileView> createState() => _CustomerProfileViewState();
}

class _CustomerProfileViewState extends State<CustomerProfileView> {
  CustomerOrdersViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The profile's own, small view of the same orders the Commandes tab
    // shows: no polling, reloaded when the tab is opened.
    _viewModel ??= CustomerOrdersViewModel(
      repository: AppServices.of(context).customerOrdersRepository,
      pageSize: _ordersWindow,
    )..load();
  }

  @override
  void didUpdateWidget(CustomerProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _viewModel?.refresh();
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _open(CustomerOrder order) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CustomerOrderDetailView(order: order)),
    );
    if (!mounted) {
      return;
    }
    // The order may have been cancelled from its page.
    _viewModel?.refresh();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmSignOut() async {
    final products = CustomerScope.maybeOf(context)?.cart.lineCount ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: Text(
          products > 0
              ? 'Votre panier en cours (${_products(products)}) sera vidé.'
              : 'Vous devrez vous reconnecter pour commander.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await signOut(context);
    }
  }

  static String _products(int count) => '$count produit${count > 1 ? 's' : ''}';

  /// An optional value that is actually there: not null, not blank.
  static String? _present(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    final textTheme = Theme.of(context).textTheme;
    final phone = _present(user?.phoneNumber);
    final whatsapp = _present(user?.whatsappNumber);
    final email = _present(user?.email);
    final rows = <_InfoRow>[
      if (phone != null)
        _InfoRow(icon: Icons.phone_rounded, label: 'Téléphone', value: phone),
      if (email != null)
        _InfoRow(icon: Icons.mail_rounded, label: 'E-mail', value: email),
      if (whatsapp != null)
        _InfoRow(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'WhatsApp',
          value: whatsapp,
        ),
    ];
    final navigation = CustomerScope.maybeOf(context)?.navigation;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        // Scrolls: at large text or on a short phone the page grows instead
        // of clipping, and the sign-out button follows the content.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Who: the photo (editable) beside the stored name, as it is.
              Row(
                children: [
                  const ProfilePhoto(size: 72),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Votre compte GrocerGo',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              // What is under way: the live order, or the latest one.
              ListenableBuilder(
                listenable: _viewModel!,
                builder: (context, _) => _OrderSection(
                  viewModel: _viewModel!,
                  onOpen: _open,
                  onBrowse: () => navigation?.select(CustomerTab.stores),
                  onShowAll: () => navigation?.select(CustomerTab.orders),
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                const _SectionHeading('Mes informations'),
                // One list surface, hairlines between the rows.
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (index, row) in rows.indexed) ...[
                        if (index > 0)
                          Padding(
                            padding: EdgeInsets.only(
                              left:
                                  AppSpacing.pagePadding +
                                  (_isInline(context) ? 20 + AppSpacing.md : 0),
                              right: AppSpacing.pagePadding,
                            ),
                            child: const Divider(height: 1),
                          ),
                        row,
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              // Secondary: a neutral outline (docs/design.md §4.5), not the
              // green of a primary action.
              OutlinedButton(
                onPressed: _confirmSignOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textSecondary),
                  // Room for the label to grow with the text size.
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's name — the same 16/700 heading as the catalogue's.
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

/// The profile's order block, from the orders the customer already has: the
/// order that is under way (with a way to open it), else the latest one, else
/// an invitation to shop. Nothing here is computed beyond picking among them.
class _OrderSection extends StatelessWidget {
  const _OrderSection({
    required this.viewModel,
    required this.onOpen,
    required this.onBrowse,
    required this.onShowAll,
  });

  final CustomerOrdersViewModel viewModel;
  final ValueChanged<CustomerOrder> onOpen;
  final VoidCallback onBrowse;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    switch (viewModel.status) {
      case CustomerOrdersStatus.loading:
        return Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Chargement de vos commandes…',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        );
      case CustomerOrdersStatus.failed:
        return Row(
          children: [
            Expanded(
              child: Text(
                'Impossible de charger vos commandes.',
                style: textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: viewModel.load,
              child: const Text('Réessayer'),
            ),
          ],
        );
      case CustomerOrdersStatus.ready:
        break;
    }

    final orders = viewModel.orders;
    if (orders.isEmpty) {
      return _NoOrders(onBrowse: onBrowse);
    }
    final live = [
      for (final order in orders)
        if (!order.isFinished) order,
    ];
    final isLive = live.isNotEmpty;
    final featured = isLive ? live.first : orders.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(isLive ? 'Commande en cours' : 'Dernière commande'),
        _OrderCard(
          order: featured,
          isLive: isLive,
          onTap: () => onOpen(featured),
        ),
        if (live.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onShowAll,
              child: Text('Voir les ${live.length} commandes en cours'),
            ),
          ),
      ],
    );
  }
}

/// One order: the store and its status, when it is to be picked up, what
/// happens next (the existing status sentence), then the code and the total.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isLive,
    required this.onTap,
  });

  final CustomerOrder order;
  final bool isLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hint = isLive ? CustomerOrderLabels.hint(order.status) : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(
          // A live order gets a Primary outline; a finished one stays calm.
          color: isLive
              ? AppColors.primary.withValues(alpha: 0.5)
              : const Color(0x1A18221C),
        ),
      ),
      child: InkWell(
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Retrait · ${DateFormatFr.pickup(order.requestedPickupAt)}',
                    style: textTheme.bodySmall,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(hint, style: textTheme.labelLarge),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: AppSpacing.md,
                          children: [
                            Text(
                              order.code,
                              style: textTheme.labelSmall?.copyWith(
                                letterSpacing: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              ProductFormat.price(order.totalMillimes),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
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

/// A customer with no order yet: one sentence and the way to the stores.
class _NoOrders extends StatelessWidget {
  const _NoOrders({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Aucune commande pour le moment',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choisissez un magasin pour passer votre première commande.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: 'Voir les magasins', onPressed: onBrowse),
          ],
        ),
      ),
    );
  }
}

/// One labelled account detail. Inline (label left, value right) at normal
/// text; stacked, without its icon, when the text is large — so a long e-mail
/// wraps in the whole width instead of a squeezed column.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final inline = _isInline(context);
    final labelText = Text(
      label,
      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
    );
    final valueText = Text(
      value,
      textAlign: inline ? TextAlign.end : TextAlign.start,
      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pagePadding,
          vertical: AppSpacing.md,
        ),
        child: inline
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.md),
                  labelText,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: valueText),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelText,
                  const SizedBox(height: AppSpacing.xs),
                  valueText,
                ],
              ),
      ),
    );
  }
}
