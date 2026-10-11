import 'package:flutter/material.dart';

import '../../../../data/models/catalog_product.dart';
import '../../../../data/models/sale_unit.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_info_note.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/product_image.dart';
import '../view_models/quick_add_view_model.dart';
import '../view_models/store_product_form_view_model.dart';

/// Opens the quick-add sheet for [item]. Completes with what happened, or
/// `null` if the owner dismissed it.
Future<QuickAddOutcome?> showQuickAddSheet(
  BuildContext context,
  CatalogItem item,
) {
  return showModalBottomSheet<QuickAddOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
    ),
    builder: (_) => QuickAddSheet(product: item.product),
  );
}

/// Adds one catalog product to the store: the product is shown read-only, and
/// the owner types a price — everything else is prefilled from the catalog and
/// tucked under one section, so adding stays fast.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({required this.product, super.key});

  final CatalogProduct product;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  QuickAddViewModel? _viewModel;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _step = TextEditingController();
  final _max = TextEditingController();
  final _stock = TextEditingController();
  final _rules = ExpansibleController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = QuickAddViewModel(
        storeProductsRepository: AppServices.of(context)
            .storeProductsRepository,
        product: widget.product,
      );
      _syncRuleFields();
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

  /// Copies the view model's rules into the fields (after a unit change).
  void _syncRuleFields() {
    final viewModel = _viewModel!;
    _min.text = viewModel.min;
    _step.text = viewModel.step;
    _max.text = viewModel.max;
    _stock.text = viewModel.stock;
  }

  Future<void> _submit() async {
    final viewModel = _viewModel!;
    final outcome = await viewModel.submit();
    if (!mounted) {
      return;
    }
    if (outcome != null) {
      Navigator.of(context).pop(outcome);
    } else if (viewModel.advancedHasError) {
      // Make sure an error inside the collapsed section can be seen.
      _rules.expand();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = widget.product;

    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        final unit = viewModel.saleUnit;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.xl,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── The catalog product: read-only ────────────────────────
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
                        if (product.brand != null)
                          Text(
                            product.brand!.name,
                            style: textTheme.labelMedium,
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${product.category.name} · '
                          '${ProductFormat.unitLabel(product.defaultSaleUnit)}',
                          style: textTheme.bodySmall,
                        ),
                        if (viewModel.catalogRulesPreview.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Catalogue : ${viewModel.catalogRulesPreview}',
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (product.description != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(product.description!, style: textTheme.bodySmall),
              ],
              const SizedBox(height: AppSpacing.xl),

              // ── The store's own configuration ─────────────────────────
              TextField(
                controller: _price,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onChanged: viewModel.setPrice,
                onSubmitted: (_) => _submit(),
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
                  onSelectionChanged: (selection) {
                    viewModel.selectUnit(selection.first);
                    _syncRuleFields();
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _RulesSection(
                viewModel: viewModel,
                controller: _rules,
                min: _min,
                step: _step,
                max: _max,
                stock: _stock,
              ),
              if (viewModel.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppErrorBanner(message: viewModel.errorMessage!),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: 'Ajouter à mon magasin',
                isLoading: viewModel.isBusy,
                onPressed: _submit,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: viewModel.isBusy
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Quantities, stock and availability — prefilled, collapsed by default.
class _RulesSection extends StatelessWidget {
  const _RulesSection({
    required this.viewModel,
    required this.controller,
    required this.min,
    required this.step,
    required this.max,
    required this.stock,
  });

  final QuickAddViewModel viewModel;
  final ExpansibleController controller;
  final TextEditingController min;
  final TextEditingController step;
  final TextEditingController max;
  final TextEditingController stock;

  @override
  Widget build(BuildContext context) {
    final base = viewModel.baseUnitName;
    final note = viewModel.stockNote;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        controller: controller,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text('Quantités, stock et disponibilité'),
        subtitle: Text(
          viewModel.rulesSummary,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: min,
            keyboardType: TextInputType.number,
            onChanged: viewModel.setMin,
            decoration: InputDecoration(
              labelText: 'Quantité minimale ($base)',
              errorText: viewModel.errorFor(StoreProductField.min),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: step,
            keyboardType: TextInputType.number,
            onChanged: viewModel.setStep,
            decoration: InputDecoration(
              labelText: 'Par tranche de ($base)',
              errorText: viewModel.errorFor(StoreProductField.step),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: max,
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
              'Le produit devient indisponible dès que le stock est épuisé.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: viewModel.trackStock,
            onChanged: viewModel.setTrackStock,
          ),
          if (viewModel.trackStock) ...[
            TextField(
              controller: stock,
              keyboardType: TextInputType.number,
              onChanged: viewModel.setStock,
              decoration: InputDecoration(
                labelText: 'Stock actuel ($base)',
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
            value: viewModel.isAvailable,
            onChanged: viewModel.setAvailable,
          ),
        ],
      ),
    );
  }
}
