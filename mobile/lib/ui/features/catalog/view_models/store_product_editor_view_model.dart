import '../../../../data/models/sale_unit.dart';
import '../../../../data/models/store_product.dart';
import '../../../../data/repositories/store_products_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../core/utils/product_formatters.dart';
import 'store_product_form_view_model.dart';

/// Edits how the store sells one catalog product. The form and its validation
/// are shared with quick-add; this adds what only an existing offering has:
/// saving a diff, the stock-conflict flow, archive and restore, and the
/// backend-derived status.
///
/// The global product is read-only: nothing about it is ever sent. Customer
/// availability is whatever the backend derives ([status] reads the last
/// response); the owner's own switch is never changed because stock hit zero.
class StoreProductEditorViewModel extends StoreProductFormViewModel {
  StoreProductEditorViewModel({
    required this._storeProductsRepository,
    required StoreProduct storeProduct,
  }) : _current = storeProduct,
       _knownStock = storeProduct.stockQuantity,
       // ignore: use_super_parameters
       super(product: storeProduct.product, saleUnit: storeProduct.saleUnit) {
    _load(storeProduct);
  }

  final StoreProductsRepository _storeProductsRepository;

  /// The offering as the backend last returned it. Edits are diffed against it.
  StoreProduct _current;
  StoreProduct get current => _current;

  /// The stock the next stock edit is checked against (`expectedStockQuantity`):
  /// what the screen loaded, or what the backend reported in a stock conflict.
  int? _knownStock;
  int? get knownStock => _knownStock;

  /// Set when the last save was refused because the stock changed meanwhile:
  /// the stock the backend holds now (`null` = no longer tracked).
  bool _stockConflict = false;
  bool get hasStockConflict => _stockConflict;

  /// Whether anything was saved, archived or restored — the caller reloads.
  bool _didChange = false;
  bool get didChange => _didChange;

  bool get isArchived => _current.isArchived;

  void _load(StoreProduct source, {bool? availability}) {
    loadValues(
      unit: source.saleUnit,
      price: ProductFormat.millimesInput(source.priceMillimes),
      min: '${source.minQuantity}',
      step: '${source.quantityStep}',
      max: source.maxQuantity == null ? '' : '${source.maxQuantity}',
      stock: source.trackStock && source.stockQuantity != null
          ? '${source.stockQuantity}'
          : '',
      trackStock: source.trackStock,
      isAvailable: availability ?? source.isAvailable,
    );
  }

  /// The new unit's price and stock mean something else: the price must be
  /// typed again (the rules and stock are reset by the shared form).
  @override
  void selectUnit(SaleUnit unit) {
    final before = saleUnit;
    super.selectUnit(unit);
    if (saleUnit != before) {
      clearPrice();
      notifyListeners();
    }
  }

  // ── Backend-derived status (display only) ─────────────────────────────

  /// What customers can do right now, from the backend's `isOrderable` and
  /// `unavailabilityReason` — the app computes nothing.
  String get statusTitle => switch (_current.unavailabilityReason) {
    null => 'Disponible pour les clients',
    UnavailabilityReason.archived => 'Produit archivé',
    UnavailabilityReason.ownerDisabled => 'Désactivé par vous',
    UnavailabilityReason.outOfStock => 'Rupture de stock',
    UnavailabilityReason.stockBelowMinimum => 'Stock insuffisant',
    UnavailabilityReason.catalogArchived => 'Retiré du catalogue',
  };

  String? get statusDetail => switch (_current.unavailabilityReason) {
    null => null,
    UnavailabilityReason.archived =>
      'Il n’apparaît plus chez vos clients. Restaurez-le pour le modifier.',
    UnavailabilityReason.ownerDisabled =>
      'Les clients ne peuvent pas le commander tant que « Disponible à la '
          'vente » est désactivé.',
    UnavailabilityReason.outOfStock =>
      'Les clients ne peuvent pas le commander tant que le stock est à 0. '
          'Votre réglage « Disponible à la vente » n’est pas modifié : le '
          'produit redevient commandable dès que vous ajoutez du stock.',
    UnavailabilityReason.stockBelowMinimum =>
      'Le stock est inférieur à la quantité minimale : les clients ne peuvent '
          'pas le commander tant que vous n’ajoutez pas de stock.',
    UnavailabilityReason.catalogArchived =>
      'Le catalogue ne propose plus ce produit : les clients ne peuvent pas le '
          'commander.',
  };

  /// `Stock actuel : 20 kg`, as last saved — or `null` when stock is not
  /// tracked.
  String? get currentStockText {
    if (!_current.trackStock || _knownStock == null) {
      return null;
    }
    return ProductFormat.quantity(_current.saleUnit, _knownStock!);
  }

  // ── Changes ───────────────────────────────────────────────────────────

  /// The request for everything except the availability switch (which has its
  /// own endpoint), or `null` when nothing else changed. Only valid when the
  /// form has no errors.
  StoreProductUpdate? _buildUpdate() {
    final unit = saleUnit;
    final unitChanged = unit != _current.saleUnit;
    final priceMillimes = ProductFormat.parseMillimes(price)!;
    final minQuantity = int.parse(min.trim());
    final quantityStep = int.parse(step.trim());
    final maxQuantity = max.trim().isEmpty ? null : int.parse(max.trim());

    final priceChanged = unitChanged || priceMillimes != _current.priceMillimes;
    final rulesChanged =
        unitChanged ||
        minQuantity != _current.minQuantity ||
        quantityStep != _current.quantityStep ||
        maxQuantity != _current.maxQuantity;
    final trackChanged = trackStock != _current.trackStock;
    final stockQuantity = trackStock ? int.parse(stock.trim()) : null;
    final stockChanged =
        trackStock && (unitChanged || stockQuantity != _knownStock);

    if (!priceChanged && !rulesChanged && !trackChanged && !stockChanged) {
      return null;
    }
    return StoreProductUpdate(
      priceMillimes: priceChanged ? priceMillimes : null,
      saleUnit: unitChanged ? unit : null,
      minQuantity: rulesChanged ? minQuantity : null,
      quantityStep: rulesChanged ? quantityStep : null,
      maxQuantity: rulesChanged ? maxQuantity : null,
      clearMaxQuantity: rulesChanged && maxQuantity == null,
      stock: trackChanged || stockChanged
          ? StockChange(
              expectedStockQuantity: _knownStock,
              trackStock: trackChanged ? trackStock : null,
              stockQuantity: stockQuantity,
            )
          : null,
    );
  }

  bool get _availabilityChanged => isAvailable != _current.isAvailable;

  /// Whether there is anything to save. An invalid form counts as changed: it
  /// started out valid.
  bool get hasChanges =>
      !isArchived &&
      (_availabilityChanged || hasErrors || _buildUpdate() != null);

  // ── Actions ───────────────────────────────────────────────────────────

  /// Saves the changes. Returns `true` when everything was applied; `false`
  /// when the form is invalid or something failed — then [errorMessage] or
  /// [hasStockConflict] says why, and everything the owner typed is kept.
  Future<bool> save() async {
    if (isBusy || isArchived) {
      return false;
    }
    touchAll();
    if (hasErrors) {
      notifyListeners();
      return false;
    }
    markBusy(true);
    failWith(null);
    _stockConflict = false;
    notifyListeners();
    try {
      final update = _buildUpdate();
      if (update != null) {
        final saved = await _storeProductsRepository.update(
          _current.id,
          update,
        );
        _didChange = true;
        _adopt(saved, availability: isAvailable);
      }
      if (_availabilityChanged) {
        final saved = await _storeProductsRepository.setAvailability(
          _current.id,
          isAvailable: isAvailable,
        );
        _didChange = true;
        _adopt(saved);
      }
      return true;
    } on StockChangedException catch (error) {
      // Nothing was applied. Keep what the owner typed; the next save is
      // checked against the stock the backend holds now.
      _stockConflict = true;
      _knownStock = error.currentStockQuantity;
      return false;
    } catch (error) {
      failWith(_saveMessage(error));
      return false;
    } finally {
      markBusy(false);
      notifyListeners();
    }
  }

  /// After a stock conflict: puts the stock the backend holds now into the
  /// stock field, for the owner to adjust.
  void useServerStock() {
    if (_knownStock != null) {
      setStock('$_knownStock');
    }
  }

  /// Archives the offering (hidden from customers, kept for history). Returns
  /// `true` when it worked — the caller leaves the editor.
  Future<bool> archive() async {
    if (isBusy || isArchived) {
      return false;
    }
    markBusy(true);
    failWith(null);
    notifyListeners();
    try {
      await _storeProductsRepository.archive(_current.id);
      _didChange = true;
      return true;
    } catch (error) {
      failWith(
        _actionMessage(
          error,
          'Impossible d’archiver ce produit. Veuillez réessayer.',
        ),
      );
      return false;
    } finally {
      markBusy(false);
      notifyListeners();
    }
  }

  /// Restores this same offering exactly as it was left — it never creates a
  /// new one. The editor stays open, now editable.
  Future<bool> restore() async {
    if (isBusy || !isArchived) {
      return false;
    }
    markBusy(true);
    failWith(null);
    notifyListeners();
    try {
      _adopt(await _storeProductsRepository.restore(_current.id));
      _didChange = true;
      return true;
    } catch (error) {
      failWith(
        _actionMessage(
          error,
          'Impossible de restaurer ce produit. Veuillez réessayer.',
        ),
      );
      return false;
    } finally {
      markBusy(false);
      notifyListeners();
    }
  }

  /// Takes the backend's version as the new baseline and shows it in the form,
  /// except for the availability the owner is still waiting to save.
  void _adopt(StoreProduct saved, {bool? availability}) {
    _current = saved;
    _knownStock = saved.stockQuantity;
    _stockConflict = false;
    _load(saved, availability: availability);
  }

  String _saveMessage(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        400 =>
          'Le serveur a refusé ces valeurs. Vérifiez le prix, les quantités '
              'et le stock.',
        404 || 409 =>
          'Ce produit a été modifié ou archivé depuis un autre appareil. '
              'Revenez au catalogue et rouvrez-le.',
        _ => 'Impossible d’enregistrer les modifications. Veuillez réessayer.',
      };
    }
    return _connectionOr(
      error,
      'Impossible d’enregistrer les modifications. Veuillez réessayer.',
    );
  }

  String _actionMessage(Object error, String otherwise) {
    if (error is ApiException && error.statusCode == 404) {
      return 'Ce produit n’existe plus. Revenez au catalogue.';
    }
    return _connectionOr(error, otherwise);
  }

  String _connectionOr(Object error, String otherwise) =>
      error is NetworkException
      ? 'Impossible de contacter le serveur. Vérifiez votre connexion.'
      : otherwise;
}
