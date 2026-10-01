import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/models/product.dart';
import '../../../../data/models/sale_unit.dart';
import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_error_banner.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../view_models/product_editor_view_model.dart';

/// Create (when [product] is null) or edit a product — one screen for both.
/// Pops with a short French confirmation message when something changed.
class ProductEditorView extends StatefulWidget {
  const ProductEditorView({this.product, super.key});

  final Product? product;

  @override
  State<ProductEditorView> createState() => _ProductEditorViewState();
}

class _ProductEditorViewState extends State<ProductEditorView> {
  /// Quick picks for the "par tranche de" step, per unit (base units).
  static const _stepPresets = {
    SaleUnit.piece: [1, 2, 5, 10],
    SaleUnit.kg: [100, 250, 500, 1000],
    SaleUnit.l: [100, 250, 500, 1000],
  };

  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.product?.name,
  );
  late final _priceController = TextEditingController(
    text: widget.product == null
        ? null
        : ProductFormat.millimesInput(widget.product!.priceMillimes),
  );
  late final _descriptionController = TextEditingController(
    text: widget.product?.description,
  );
  late final _photoController = TextEditingController(
    text: widget.product?.photo,
  );

  late SaleUnit _unit = widget.product?.saleUnit ?? SaleUnit.piece;
  late int _step = widget.product?.quantityStep ?? _unit.defaultStep;
  late int _min = widget.product?.minQuantity ?? _step;
  late int? _max = widget.product?.maxQuantity;
  late int? _categoryId = widget.product?.categoryId;

  ProductEditorViewModel? _viewModel;
  String? _errorMessage;

  bool get _isEditing => widget.product != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      final services = AppServices.of(context);
      _viewModel = ProductEditorViewModel(
        productRepository: services.productRepository,
        categoryRepository: services.categoryRepository,
      )..addListener(_onViewModelChanged);
      _viewModel!.loadCategories();
    }
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel?.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  /// Largest value that is still a multiple of the step and within the cap.
  int get _upperBound => (_unit.cap ~/ _step) * _step;

  // ── unit and quantity rules: every control keeps the values aligned ──

  void _selectUnit(SaleUnit unit) {
    if (unit == _unit) {
      return;
    }
    setState(() {
      _unit = unit;
      _step = unit.defaultStep;
      _min = _step;
      _max = null;
    });
  }

  void _selectStep(int step) {
    setState(() {
      _step = step;
      _min = _min % step == 0 && _min <= _upperBound ? _min : step;
      final max = _max;
      if (max != null) {
        _max = (max ~/ step * step).clamp(_min, _upperBound);
      }
    });
  }

  void _setMin(int value) {
    setState(() {
      _min = value;
      if (_max != null && _max! < _min) {
        _max = _min;
      }
    });
  }

  void _toggleMax(bool enabled) {
    setState(() {
      _max = enabled ? (_min * 10).clamp(_min, _upperBound) : null;
    });
  }

  String? _validatePrice(String? value) {
    final requiredError = AppValidators.required(
      value,
      message: 'Le prix est requis.',
    );
    if (requiredError != null) {
      return requiredError;
    }
    final millimes = ProductFormat.parseMillimes(value!);
    if (millimes == null) {
      return 'Prix invalide (ex. 1,800).';
    }
    if (millimes <= 0) {
      return 'Le prix doit être supérieur à 0.';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();

    final error = await _viewModel!.save(
      ProductInput(
        name: _nameController.text.trim(),
        saleUnit: _unit,
        priceMillimes: ProductFormat.parseMillimes(_priceController.text)!,
        minQuantity: _min,
        quantityStep: _step,
        maxQuantity: _max,
        categoryId: _categoryId,
        description: _descriptionController.text,
        photo: _photoController.text,
      ),
      productId: widget.product?.id,
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    Navigator.of(context)
        .pop(_isEditing ? 'Modifications enregistrées.' : 'Produit ajouté.');
  }

  Future<void> _archive() async {
    final product = widget.product!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce produit du catalogue ?'),
        content: Text(
          '« ${product.name} » ne sera plus visible dans votre catalogue. '
          'Il reste conservé pour l’historique des commandes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final error = await _viewModel!.archive(product.id);
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    Navigator.of(context).pop('Produit supprimé du catalogue.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewModel = _viewModel!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier le produit' : 'Nouveau produit'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  AppErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                // The unit comes first: it changes the price label and the
                // quantity controls below.
                Text('Vendu…', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<SaleUnit>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: SaleUnit.piece,
                      label: Text('À la pièce'),
                    ),
                    ButtonSegment(value: SaleUnit.kg, label: Text('Au kilo')),
                    ButtonSegment(value: SaleUnit.l, label: Text('Au litre')),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (selection) =>
                      _selectUnit(selection.first),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nom du produit',
                  ),
                  validator: (value) => AppValidators.required(
                    value,
                    message: 'Le nom du produit est requis.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _priceController,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: ProductFormat.priceFieldLabel(_unit),
                    hintText: '0,000',
                  ),
                  validator: _validatePrice,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int?>(
                  initialValue:
                      viewModel.categories.any((c) => c.id == _categoryId)
                      ? _categoryId
                      : null,
                  style: textTheme.bodyLarge,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Aucune catégorie'),
                    ),
                    for (final category in viewModel.categories)
                      DropdownMenuItem<int?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                if (viewModel.categories.isEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Aucune catégorie pour l’instant. Vous pouvez en créer depuis le Catalogue.',
                    style: textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                Text('Quantités commandables', style: textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                Text('Par tranche de', style: textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                _StepChips(
                  unit: _unit,
                  current: _step,
                  presets: _stepPresets[_unit]!,
                  onSelected: _selectStep,
                ),
                const SizedBox(height: AppSpacing.lg),
                _QuantityStepper(
                  label: 'Quantité minimale',
                  value: ProductFormat.quantity(_unit, _min),
                  canDecrease: _min - _step >= _step,
                  canIncrease: _min + _step <= _upperBound,
                  onDecrease: () => _setMin(_min - _step),
                  onIncrease: () => _setMin(_min + _step),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Limiter la quantité par commande',
                        style: textTheme.bodyLarge,
                      ),
                    ),
                    Switch(value: _max != null, onChanged: _toggleMax),
                  ],
                ),
                if (_max != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _QuantityStepper(
                    label: 'Quantité maximale',
                    value: ProductFormat.quantity(_unit, _max!),
                    canDecrease: _max! - _step >= _min,
                    canIncrease: _max! + _step <= _upperBound,
                    onDecrease: () => setState(() => _max = _max! - _step),
                    onIncrease: () => setState(() => _max = _max! + _step),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _Preview(
                  unit: _unit,
                  min: _min,
                  step: _step,
                  max: _max,
                  priceMillimes: ProductFormat.parseMillimes(
                    _priceController.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TextFormField(
                  controller: _descriptionController,
                  textInputAction: TextInputAction.next,
                  maxLines: 3,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(AppLimits.description),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Optionnel',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _photoController,
                  keyboardType: TextInputType.url,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(AppLimits.url),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Photo du produit',
                    hintText: 'Lien de la photo (optionnel)',
                  ),
                  validator: AppValidators.optionalPhotoUrl,
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppPrimaryButton(
                  label: _isEditing ? 'Enregistrer' : 'Ajouter le produit',
                  isLoading: viewModel.isBusy,
                  onPressed: _save,
                ),
                if (_isEditing) ...[
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    onPressed: viewModel.isBusy ? null : _archive,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Supprimer du catalogue'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChips extends StatelessWidget {
  const _StepChips({
    required this.unit,
    required this.current,
    required this.presets,
    required this.onSelected,
  });

  final SaleUnit unit;
  final int current;
  final List<int> presets;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // An existing product may have a step that isn't one of the presets.
    final values = [...presets, if (!presets.contains(current)) current]
      ..sort();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(ProductFormat.quantity(unit, value)),
            selected: value == current,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.label,
    required this.value,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.bodyLarge)),
        IconButton(
          tooltip: '$label : diminuer',
          icon: const Icon(Icons.remove_rounded),
          onPressed: canDecrease ? onDecrease : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: '$label : augmenter',
          icon: const Icon(Icons.add_rounded),
          onPressed: canIncrease ? onIncrease : null,
        ),
      ],
    );
  }
}

/// Live explanation of what the customer will be able to order, generated from
/// the current settings.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.unit,
    required this.min,
    required this.step,
    required this.max,
    required this.priceMillimes,
  });

  final SaleUnit unit;
  final int min;
  final int step;
  final int? max;
  final int? priceMillimes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final price = priceMillimes;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Le client pourra commander :', style: textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ProductFormat.orderablePreview(
              unit: unit,
              min: min,
              step: step,
              max: max,
            ),
            style: textTheme.bodyMedium,
          ),
          if (price != null && price > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${ProductFormat.quantity(unit, min)} = '
              '${ProductFormat.price(unit.lineTotalMillimes(priceMillimes: price, quantity: min))}'
              ' · ${ProductFormat.pricePerUnit(unit, price)}',
              style: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
