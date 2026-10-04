import '../../../../data/models/catalog_product.dart';
import '../../../../data/models/store_product.dart';
import '../../../../data/repositories/store_products_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../core/utils/product_formatters.dart';
import 'store_product_form_view_model.dart';

/// What the quick-add sheet hands back when it closes.
class QuickAddOutcome {
  const QuickAddOutcome.created(StoreProduct this.created) : conflict = false;

  /// The store or the catalog changed under the owner (the product is already
  /// in the store, or was archived or removed from the catalog): nothing was
  /// created and the caller should reload what it shows.
  const QuickAddOutcome.conflict() : created = null, conflict = true;

  final StoreProduct? created;
  final bool conflict;
}

/// The quick-add form: it adds one catalog product to the store with as little
/// typing as possible. The catalog's unit and quantity rules prefill it, so the
/// owner usually only types a price. Validation mirrors the backend's rules
/// (the backend still has the last word).
///
/// The catalog product is read-only here; only the store's own configuration
/// is edited. Customer availability is never decided by the app: with stock
/// tracking on and a stock of zero the backend makes the product unavailable
/// by itself, and this form only *explains* that.
class QuickAddViewModel extends StoreProductFormViewModel {
  // ignore: use_super_parameters
  QuickAddViewModel({
    required this._storeProductsRepository,
    required CatalogProduct product,
  }) : super(product: product, saleUnit: product.defaultSaleUnit);

  final StoreProductsRepository _storeProductsRepository;

  // ── Submitting ────────────────────────────────────────────────────────

  NewStoreProduct _request() {
    final maxBlank = max.trim().isEmpty;
    return NewStoreProduct(
      productId: product.id,
      priceMillimes: ProductFormat.parseMillimes(price)!,
      saleUnit: saleUnit,
      minQuantity: int.parse(min.trim()),
      quantityStep: int.parse(step.trim()),
      maxQuantity: maxBlank ? null : int.parse(max.trim()),
      noMaximum: maxBlank,
      trackStock: trackStock,
      stockQuantity: trackStock ? int.parse(stock.trim()) : null,
      isAvailable: isAvailable,
    );
  }

  /// Adds the product to the store. Returns the outcome to close the sheet
  /// with, or `null` when the sheet should stay open (the form is invalid, or
  /// a retryable error is in [errorMessage]).
  Future<QuickAddOutcome?> submit() async {
    if (isBusy) {
      return null;
    }
    touchAll();
    if (hasErrors) {
      notifyListeners();
      return null;
    }
    markBusy(true);
    failWith(null);
    notifyListeners();
    try {
      return QuickAddOutcome.created(
        await _storeProductsRepository.create(_request()),
      );
    } on ApiException catch (error) {
      // 409: the store already has it (or the catalog archived it); 404: it is
      // gone from the catalog. Either way what the owner sees is out of date —
      // the caller reloads it and explains.
      if (error.statusCode == 409 || error.statusCode == 404) {
        return const QuickAddOutcome.conflict();
      }
      failWith(
        error.statusCode == 400
            ? 'Le serveur a refusé ces valeurs. Vérifiez le prix, les quantités '
                  'et le stock.'
            : 'Impossible d’ajouter le produit. Veuillez réessayer.',
      );
      return null;
    } on NetworkException catch (_) {
      failWith('Impossible de contacter le serveur. Vérifiez votre connexion.');
      return null;
    } finally {
      markBusy(false);
      notifyListeners();
    }
  }
}
