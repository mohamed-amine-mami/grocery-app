import 'package:flutter/foundation.dart';

import '../../../../data/models/catalog_product.dart';
import '../../../../data/models/sale_unit.dart';
import '../../../core/utils/product_formatters.dart';

enum StoreProductField { price, min, step, max, stock }

/// The form shared by quick-add and the store-product editor: the store's
/// price, unit, quantity rules, stock and availability for one catalog
/// product, with the validation that mirrors the backend's rules (the backend
/// still has the last word). The catalog [product] is read-only.
///
/// Customer availability is never decided here: with stock tracking on and a
/// stock of zero the backend makes the product unavailable by itself, and the
/// form only *explains* that.
abstract class StoreProductFormViewModel extends ChangeNotifier {
  StoreProductFormViewModel({required this.product, required this._saleUnit}) {
    _applyDefaultRules();
  }

  /// Sanity ceiling, same as the backend: 10 000 DT per sale unit.
  static const maxPriceMillimes = 10000000;

  /// The global product. Read-only.
  final CatalogProduct product;

  SaleUnit _saleUnit;
  SaleUnit get saleUnit => _saleUnit;

  /// The units the store may use: the product's default, or piece.
  List<SaleUnit> get allowedUnits => product.allowedSaleUnits;

  String _price = '';
  String _min = '';
  String _step = '';
  String _max = '';
  String _stock = '';
  bool _trackStock = false;
  bool _isAvailable = true;

  String get price => _price;
  String get min => _min;
  String get step => _step;
  String get max => _max;
  String get stock => _stock;
  bool get trackStock => _trackStock;
  bool get isAvailable => _isAvailable;

  final _touched = <StoreProductField>{};

  /// Shows every field's error (the owner tried to submit).
  @protected
  void touchAll() => _touched.addAll(StoreProductField.values);

  /// Replaces the whole form (the editor loads or reloads a store product).
  @protected
  void loadValues({
    required SaleUnit unit,
    required String price,
    required String min,
    required String step,
    required String max,
    required String stock,
    required bool trackStock,
    required bool isAvailable,
  }) {
    _saleUnit = unit;
    _price = price;
    _min = min;
    _step = step;
    _max = max;
    _stock = stock;
    _trackStock = trackStock;
    _isAvailable = isAvailable;
    _touched.clear();
    _errorMessage = null;
  }

  /// Empties the price without flagging it (a new unit means a new price).
  @protected
  void clearPrice() {
    _price = '';
    _touched.remove(StoreProductField.price);
  }

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  @protected
  void markBusy(bool value) => _isBusy = value;

  /// A French message for a failure the owner can retry (offline, server).
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  @protected
  void failWith(String? message) => _errorMessage = message;

  // ── Catalog defaults (read-only information) ──────────────────────────

  /// What the catalog suggests, e.g. `500 g, 600 g, 700 g… jusqu’à 10 kg`.
  String get catalogRulesPreview => ProductFormat.orderablePreview(
    unit: product.defaultSaleUnit,
    min: product.defaultMinQuantity,
    step: product.defaultQuantityStep,
    max: product.defaultMaxQuantity,
  );

  /// The base unit quantities are typed in: `g`, `mL` or `pièces`.
  String get baseUnitName => switch (_saleUnit) {
    SaleUnit.piece => 'pièces',
    SaleUnit.kg => 'g',
    SaleUnit.l => 'mL',
  };

  ({int min, int step, int? max}) _defaultRulesFor(SaleUnit unit) =>
      unit == product.defaultSaleUnit
      ? (
          min: product.defaultMinQuantity,
          step: product.defaultQuantityStep,
          max: product.defaultMaxQuantity,
        )
      // Another unit: the catalog's numbers would mean something else (100
      // would be pieces, not grams), so that unit's own defaults apply.
      : (min: unit.defaultStep, step: unit.defaultStep, max: null);

  void _applyDefaultRules() {
    final rules = _defaultRulesFor(_saleUnit);
    _min = '${rules.min}';
    _step = '${rules.step}';
    _max = rules.max == null ? '' : '${rules.max}';
  }

  // ── Editing ───────────────────────────────────────────────────────────

  void setPrice(String value) =>
      _set(StoreProductField.price, () => _price = value);
  void setMin(String value) => _set(StoreProductField.min, () => _min = value);
  void setStep(String value) =>
      _set(StoreProductField.step, () => _step = value);
  void setMax(String value) => _set(StoreProductField.max, () => _max = value);
  void setStock(String value) =>
      _set(StoreProductField.stock, () => _stock = value);

  void _set(StoreProductField field, VoidCallback change) {
    change();
    _touched.add(field);
    _errorMessage = null;
    notifyListeners();
  }

  void setTrackStock(bool value) {
    _trackStock = value;
    _errorMessage = null;
    notifyListeners();
  }

  void setAvailable(bool value) {
    _isAvailable = value;
    notifyListeners();
  }

  /// Switches the unit. The quantity rules go back to that unit's defaults and
  /// the stock must be typed again — a count in grams is not a count in pieces.
  /// A unit the product does not allow is ignored.
  void selectUnit(SaleUnit unit) {
    if (unit == _saleUnit || !allowedUnits.contains(unit)) {
      return;
    }
    _saleUnit = unit;
    _applyDefaultRules();
    _stock = '';
    _touched.removeAll([
      StoreProductField.min,
      StoreProductField.step,
      StoreProductField.max,
      StoreProductField.stock,
    ]);
    _errorMessage = null;
    notifyListeners();
  }

  // ── Validation ────────────────────────────────────────────────────────

  String? get priceError {
    final text = _price.trim();
    if (text.isEmpty) {
      return 'Le prix est requis.';
    }
    final millimes = ProductFormat.parseMillimes(text);
    if (millimes == null) {
      return 'Prix invalide (ex. 1,800).';
    }
    if (millimes <= 0) {
      return 'Le prix doit être supérieur à 0.';
    }
    if (millimes > maxPriceMillimes) {
      return 'Prix trop élevé (maximum 10 000 DT).';
    }
    return null;
  }

  /// Checks shared by min, step and max: a whole number, within the unit's
  /// ceiling, on its granularity (kg/L quantities are multiples of 10).
  String? _quantityBasics(String text, int? value) {
    if (value == null || value <= 0) {
      return 'Entrez un nombre entier supérieur à 0.';
    }
    if (value > _saleUnit.cap) {
      return 'Maximum ${ProductFormat.quantity(_saleUnit, _saleUnit.cap)}.';
    }
    if (value % _saleUnit.granularity != 0) {
      return 'Utilisez un multiple de ${_saleUnit.granularity} $baseUnitName.';
    }
    return null;
  }

  int? get _stepValue => int.tryParse(_step.trim());
  int? get _minValue => int.tryParse(_min.trim());

  String? get stepError {
    if (_step.trim().isEmpty) {
      return 'La tranche est requise.';
    }
    return _quantityBasics(_step, _stepValue);
  }

  String? get minError {
    if (_min.trim().isEmpty) {
      return 'Le minimum est requis.';
    }
    final basics = _quantityBasics(_min, _minValue);
    if (basics != null) {
      return basics;
    }
    final step = stepError == null ? _stepValue : null;
    if (step != null && _minValue! % step != 0) {
      return 'Doit être un multiple de la tranche '
          '(${ProductFormat.quantity(_saleUnit, step)}).';
    }
    return null;
  }

  /// The maximum is optional: blank means no maximum.
  String? get maxError {
    if (_max.trim().isEmpty) {
      return null;
    }
    final value = int.tryParse(_max.trim());
    final basics = _quantityBasics(_max, value);
    if (basics != null) {
      return basics;
    }
    final min = minError == null ? _minValue : null;
    if (min != null && value! < min) {
      return 'Doit être au moins égal au minimum.';
    }
    final step = stepError == null ? _stepValue : null;
    if (step != null && value! % step != 0) {
      return 'Doit être un multiple de la tranche '
          '(${ProductFormat.quantity(_saleUnit, step)}).';
    }
    return null;
  }

  /// Only checked while stock is tracked. Zero is valid: it means "none left".
  String? get stockError {
    if (!_trackStock) {
      return null;
    }
    final text = _stock.trim();
    if (text.isEmpty) {
      return 'Indiquez le stock actuel (0 si épuisé).';
    }
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      return 'Entrez un nombre entier (0 ou plus).';
    }
    if (value > _saleUnit.stockCap) {
      return 'Maximum ${ProductFormat.quantity(_saleUnit, _saleUnit.stockCap)}.';
    }
    if (value % _saleUnit.granularity != 0) {
      return 'Utilisez un multiple de ${_saleUnit.granularity} $baseUnitName.';
    }
    return null;
  }

  String? _errorOf(StoreProductField field) => switch (field) {
    StoreProductField.price => priceError,
    StoreProductField.min => minError,
    StoreProductField.step => stepError,
    StoreProductField.max => maxError,
    StoreProductField.stock => stockError,
  };

  /// The error to show on [field]: only once the owner has touched it (or
  /// tried to submit), so an untouched form is not covered in red.
  String? errorFor(StoreProductField field) =>
      _touched.contains(field) ? _errorOf(field) : null;

  bool get hasErrors =>
      StoreProductField.values.any((f) => _errorOf(f) != null);

  /// Whether a field in the collapsible "quantities and stock" section is
  /// invalid — the sheet opens that section so the error is visible.
  bool get advancedHasError => [
    StoreProductField.min,
    StoreProductField.step,
    StoreProductField.max,
    StoreProductField.stock,
  ].any((f) => _errorOf(f) != null);

  /// An explanation, never a decision: what the backend will do with this
  /// stock. The product's availability for customers is derived by the backend.
  String? get stockNote {
    if (!_trackStock || stockError != null) {
      return null;
    }
    final stock = int.parse(_stock.trim());
    if (stock == 0) {
      return 'Stock à 0 : le produit sera indisponible pour les clients tant '
          'que vous n’aurez pas ajouté de stock.';
    }
    final min = minError == null ? _minValue : null;
    if (min != null && stock < min) {
      return 'Stock inférieur à la quantité minimale : le produit restera '
          'indisponible pour les clients.';
    }
    return null;
  }

  /// A one-line summary of the rules, for the collapsed section.
  String get rulesSummary {
    final step = stepError == null ? _stepValue : null;
    final min = minError == null ? _minValue : null;
    return [
      if (step != null)
        'Par tranche de ${ProductFormat.quantity(_saleUnit, step)}',
      if (min != null) 'minimum ${ProductFormat.quantity(_saleUnit, min)}',
      if (_trackStock) 'stock suivi',
      if (!_isAvailable) 'indisponible',
    ].join(' · ');
  }
}
