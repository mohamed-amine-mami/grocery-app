import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/view_models/auth_scope.dart';
import '../../auth/views/profile_photo.dart';
import '../../store/view_models/store_edit_view_model.dart';
import '../view_models/owner_dashboard_view_model.dart';

/// `Accueil` tab — intentionally simple for V1: the store's open/closed
/// state and, until the store is set up, a short checklist.
///
/// Order counters will be added as another section of this list; there is no
/// analytics, revenue or shortcut grid here on purpose.
class OwnerHomeView extends StatelessWidget {
  const OwnerHomeView({
    required this.storeViewModel,
    required this.dashboardViewModel,
    required this.onOpenCatalog,
    required this.onOpenStore,
    super.key,
  });

  final StoreEditViewModel storeViewModel;
  final OwnerDashboardViewModel dashboardViewModel;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    final textTheme = Theme.of(context).textTheme;

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
                onTap: onOpenCatalog,
              ),
              _Step(
                title: 'Ouvrir le magasin',
                hint: 'Vos clients pourront alors commander.',
                isDone: store.isOpen,
                onTap: onOpenStore,
              ),
            ];
            final setupComplete = steps.every((step) => step.isDone);

            return RefreshIndicator(
              onRefresh: dashboard.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const ProfilePhoto(size: 64),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Text(
                          'Bonjour, ${user?.name ?? ''}',
                          style: textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _StoreStatusCard(
                    name: store.name,
                    address: store.address,
                    isOpen: store.isOpen,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (dashboard.status == DashboardStatus.failed)
                    Text(
                      'Impossible de charger la configuration. Tirez vers le bas pour réessayer.',
                      style: textTheme.bodySmall,
                    )
                  else if (dashboard.status == DashboardStatus.ready &&
                      !setupComplete)
                    _SetupChecklist(steps: steps),
                  // Order counters ("À confirmer", "Prêtes à retirer") go here.
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

class _StoreStatusCard extends StatelessWidget {
  const _StoreStatusCard({
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status is carried by icon + text, never by color alone.
            Row(
              children: [
                Icon(
                  isOpen ? Icons.storefront_rounded : Icons.lock_clock_rounded,
                  color: isOpen ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isOpen ? 'Magasin ouvert' : 'Magasin fermé',
                  style: textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isOpen
                  ? 'Les clients peuvent passer commande.'
                  : 'Le magasin n’accepte pas de commandes pour le moment.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Text(name, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(address, style: textTheme.bodySmall),
          ],
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
    final textTheme = Theme.of(context).textTheme;
    final done = steps.where((step) => step.isDone).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Démarrer votre magasin · $done/${steps.length}',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
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
