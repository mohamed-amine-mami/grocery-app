import 'package:flutter/material.dart';

import '../../../../data/models/sale_unit.dart';
import '../../../../data/models/store_product.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_info_note.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/product_image.dart';
import '../view_models/store_product_editor_view_model.dart';
import '../view_models/store_product_form_view_model.dart';

/// Opens the editor for [product]. Completes with a French confirmation to
/// show (`Modifications enregistrées.`, `… archivé.`), or `null` when nothing
/// was saved. Whatever the result, the caller should reload what it shows.
Future<String?> openStoreProductEditor(
  BuildContext context,
  StoreProduct product,
) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => StoreProductEditorView(product: product)),
  );
}

/// How the owner's store sells one catalog product. The catalog information
/// on top is read-only; everything under "Votre magasin" is the store's own.
class StoreProductEditorView extends StatefulWidget {
  const StoreProductEditorView({required this.product, super.key});

  final StoreProduct product;

  @override
  State<StoreProductEditorView> createState() => _StoreProductEditorViewState();
}

class _StoreProductEditorViewState extends State<StoreProductEditorView> {
  StoreProductEditorViewModel? _viewModel;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _step = TextEditingController();
  final _max = TextEditingController();
  final _stock = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = StoreProductEditorViewModel(
        storeProductsRepository: AppServices.of(context)
            .storeProductsRepository,
        storeProduct: widget.product,
      );
      _syncFields();
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    for (final controller in [_price, _min, _step, _max, _stock]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Copies the view model's values into the fields (after a unit change, a
  /// reload from the backend, or "use the current stock").
  void _syncFields() {
    final viewModel = _viewModel!;
    _price.text = viewModel.price;
    _min.text = viewModel.min;
    _step.text = viewModel.step;
    _max.text = viewModel.max;
    _stock.text = viewModel.stock;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final viewModel = _viewModel!;
    final saved = await viewModel.save();
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop('Modifications enregistrées.');
    } else {
      // A refused save may have reloaded part of the form from the backend.
      _syncFields();
    }
  }

  Future<void> _archive() async {
    final viewModel = _viewModel!;
    final name = viewModel.product.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archiver ce produit ?'),
        content: Text(
          '« $name » disparaîtra de votre catalogue et ne sera plus visible '
          'par les clients. Vous pourrez le restaurer plus tard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    if (await viewModel.archive() && mounted) {
      Navigator.of(context).pop('$name archivé.');
    }
  }

  Future<void> _restore() async {
    final viewModel = _viewModel!;
    if (await viewModel.restore() && mounted) {
      _syncFields();
      _showMessage('${viewModel.product.name} restauré.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        final textTheme = Theme.of(context).textTheme;
        final editable = !viewModel.isArchived;
        final unit = viewModel.saleUnit;
        final base = viewModel.baseUnitName;
        final stockText = viewModel.currentStockText;
        final note = viewModel.stockNote;

        return Scaffold(
          appBar: AppBar(title: const Text('Produit')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              children: [
                // ── Global catalog information: read-only ─────────────────
                _CatalogCard(viewModel: viewModel),
                const SizedBox(height: AppSpacing.lg),
                _StatusBanner(viewModel: viewModel),
                const SizedBox(height: AppSpacing.xxl),

                // ── The store's own configuration: editable ───────────────
                Text('Votre magasin', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  editable
                      ? 'Réglages propres à votre magasin. Le produit du '
                            'catalogue, lui, ne change pas.'
                      : 'Ces réglages sont conservés. Restaurez le produit '
                            'pour les modifier.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _price,
                  enabled: editable,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: viewModel.setPrice,
                  decoration: InputDecoration(
                    labelText: ProductFormat.priceFieldLabel(unit),
                    errorText: viewModel.errorFor(StoreProductField.price),
                  ),
                ),
                if (viewModel.allowedUnits.length > 1) ...[
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<SaleUnit>(
                    segments: [
                      for (final option in viewModel.allowedUnits)
                        ButtonSegment(
                          value: option,
                          label: Text(ProductFormat.unitLabel(option)),
                        ),
                    ],
                    selected: {unit},
                    showSelectedIcon: false,
                    onSelectionChanged: editable
                        ? (selection) {
                            viewModel.selectUnit(selection.first);
                            _syncFields();
                          }
                        : null,
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Vendu ${ProductFormat.unitLabel(unit).toLowerCase()}',
                    style: textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _min,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  onChanged: viewModel.setMin,
                  decoration: InputDecoration(
                    labelText: 'Quantité minimale ($base)',
                    errorText: viewModel.errorFor(StoreProductField.min),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _step,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  onChanged: viewModel.setStep,
                  decoration: InputDecoration(
                    labelText: 'Par tranche de ($base)',
                    errorText: viewModel.errorFor(StoreProductField.step),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _max,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  onChanged: viewModel.setMax,
                  decoration: InputDecoration(
                    labelText: 'Quantité maximale ($base) — facultatif',
                    errorText: viewModel.errorFor(StoreProductField.max),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Suivre le stock'),
                  subtitle: Text(
                    viewModel.trackStock
                        ? 'Activé'
                        : 'Désactivé : le stock ne décide pas de la '
                              'disponibilité.',
                    style: textTheme.bodySmall,
                  ),
                  value: viewModel.trackStock,
                  onChanged: editable ? viewModel.setTrackStock : null,
                ),
                if (viewModel.trackStock) ...[
                  if (stockText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Stock actuel : $stockText',
                        style: textTheme.titleSmall,
                      ),
                    ),
                  TextField(
                    controller: _stock,
                    enabled: editable,
                    keyboardType: TextInputType.number,
                    onChanged: viewModel.setStock,
                    decoration: InputDecoration(
                      labelText: stockText == null
                          ? 'Stock actuel ($base)'
                          : 'Modifier le stock ($base)',
                      errorText: viewModel.errorFor(StoreProductField.stock),
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppInfoNote(message: note),
                  ],
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponible à la vente'),
                  subtitle: Text(
                    'Votre interrupteur, indépendant du stock.',
                    style: textTheme.bodySmall,
                  ),
                  value: viewModel.isAvailable,
                  onChanged: editable ? viewModel.setAvailable : null,
                ),

                // ── Outcome of the last attempt ───────────────────────────
                if (viewModel.hasStockConflict) ...[
                  const SizedBox(height: AppSpacing.md),
                  _StockConflictBanner(
                    viewModel: viewModel,
                    onUseServerStock: () {
                      viewModel.useServerStock();
                      _syncFields();
                    },
                  ),
                ],
                if (viewModel.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppErrorBanner(message: viewModel.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (editable) ...[
                  AppPrimaryButton(
                    label: 'Enregistrer',
                    isLoading: viewModel.isBusy,
                    onPressed: viewModel.hasChanges ? _save : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: viewModel.isBusy ? null : _archive,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archiver ce produit'),
                  ),
                ] else
                  AppPrimaryButton(
                    label: 'Restaurer ce produit',
                    isLoading: viewModel.isBusy,
                    onPressed: _restore,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The global product: image, name, category, description. Visibly read-only,
/// with nothing to tap or type into.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.viewModel});

  final StoreProductEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = viewModel.product;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Catalogue — lecture seule',
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImage(photo: product.photo),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name, style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(product.category.name, style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (product.description != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(product.description!, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// What customers can do with this product right now, as the backend derives
/// it. Icon, title and explanation — never color alone.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.viewModel});

  final StoreProductEditorViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reason = viewModel.current.unavailabilityReason;
    final orderable = reason == null;
    final color = orderable ? AppColors.success : AppColors.warning;
    final icon = switch (reason) {
      null => Icons.check_circle_outline_rounded,
      UnavailabilityReason.archived => Icons.archive_outlined,
      UnavailabilityReason.ownerDisabled => Icons.toggle_off_outlined,
      UnavailabilityReason.outOfStock => Icons.remove_shopping_cart_outlined,
      UnavailabilityReason.stockBelowMinimum => Icons.warning_amber_rounded,
      UnavailabilityReason.catalogArchived => Icons.block_rounded,
    };
    final detail = viewModel.statusDetail;

    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewModel.statusTitle,
                    style: textTheme.labelLarge?.copyWith(color: color),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(detail, style: textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stock changed (an order, another device) while the owner was editing.
/// Nothing was applied; what they typed is still in the field.
class _StockConflictBanner extends StatelessWidget {
  const _StockConflictBanner({
    required this.viewModel,
    required this.onUseServerStock,
  });

  final StoreProductEditorViewModel viewModel;
  final VoidCallback onUseServerStock;

  @override
  Widget build(BuildContext context) {
    final known = viewModel.knownStock;
    final now = known == null
        ? null
        : ProductFormat.quantity(viewModel.current.saleUnit, known);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppErrorBanner(
          message: now == null
              ? 'Le suivi du stock a changé entre-temps. Vos modifications '
                    'n’ont pas été enregistrées.'
              : 'Le stock a changé entre-temps : il est maintenant de $now. '
                    'Vos modifications n’ont pas été enregistrées. Vérifiez '
                    'votre saisie, puis enregistrez à nouveau.',
        ),
        if (now != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onUseServerStock,
              child: Text('Utiliser le stock actuel ($now)'),
            ),
          ),
      ],
    );
  }
}
