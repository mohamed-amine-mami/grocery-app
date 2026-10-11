import 'package:flutter/foundation.dart';

import '../../../../data/models/customer_product.dart';
import '../../../../data/models/customer_store.dart';

/// Why a cart line cannot be ordered as it stands.
enum CartProblem {
  /// The store no longer lists it, or the backend says it cannot be ordered.
  unavailable,

  /// The quantity no longer fits the product's current min / step / max.
  invalidQuantity,
}

/// One line of the cart: the product as last seen (for display) and how much
/// of it. Only the product id and the quantity are ever sent to the backend.
class CartLine {
  const CartLine({required this.product, required this.quantity, this.problem});

  final CustomerProduct product;

  /// In base units, always within the product's min / step / max when added.
  final int quantity;
  final CartProblem? problem;

  /// Estimated line subtotal in millimes, from the price last loaded.
  int get subtotalMillimes => product.saleUnit.lineTotalMillimes(
    priceMillimes: product.priceMillimes,
    quantity: quantity,
  );

  bool get canIncrement {
    final max = product.maxQuantity;
    return max == null || quantity + product.quantityStep <= max;
  }

  CartLine _with({
    CustomerProduct? product,
    int? quantity,
    CartProblem? problem,
    bool clearProblem = false,
  }) => CartLine(
    product: product ?? this.product,
    quantity: quantity ?? this.quantity,
    problem: clearProblem ? null : (problem ?? this.problem),
  );
}

/// What adding a product did.
enum CartAddResult {
  added,

  /// The cart holds another store's products: the customer must confirm the
  /// switch (which empties the cart) first. Nothing changed.
  needsStoreSwitch,

  /// The backend says the product cannot be ordered. Nothing changed.
  unavailable,

  /// The store is closed. Nothing changed.
  storeClosed,
}

/// The customer's local cart: one store, its lines, nothing else. There is no
/// server-side cart. The total here is an estimate for review; the backend
/// computes the real one when the order is placed.
class CartViewModel extends ChangeNotifier {
  CustomerStore? _store;

  /// The store the cart belongs to, or `null` while it is empty and unclaimed.
  CustomerStore? get store => _store;

  final _lines = <CartLine>[];
  List<CartLine> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  /// Number of different products.
  int get lineCount => _lines.length;

  bool get hasProblems => _lines.any((line) => line.problem != null);

  /// Estimated total for review, from the prices last loaded. Never sent.
  int get estimatedTotalMillimes =>
      _lines.fold(0, (sum, line) => sum + line.subtotalMillimes);

  int quantityOf(int productId) => _lineOf(productId)?.quantity ?? 0;

  CartLine? _lineOf(int productId) {
    for (final line in _lines) {
      if (line.product.id == productId) {
        return line;
      }
    }
    return null;
  }

  /// Adds [product] of [store] at its minimum quantity (or tells why not).
  /// Adding more of a product already in the cart is [increment].
  CartAddResult add(CustomerStore store, CustomerProduct product) {
    if (!store.isOpen) {
      return CartAddResult.storeClosed;
    }
    if (!product.isOrderable) {
      return CartAddResult.unavailable;
    }
    if (_lines.isNotEmpty && _store?.id != store.id) {
      return CartAddResult.needsStoreSwitch;
    }
    _store = store;
    if (_lineOf(product.id) == null) {
      _lines.add(CartLine(product: product, quantity: product.minQuantity));
    }
    notifyListeners();
    return CartAddResult.added;
  }

  /// Makes [store] the cart's store, emptying the cart. Call only after the
  /// customer confirmed.
  void switchStore(CustomerStore store) {
    _lines.clear();
    _store = store;
    notifyListeners();
  }

  /// One step more, within the maximum. Does nothing at the maximum.
  void increment(int productId) {
    final line = _lineOf(productId);
    if (line == null || !line.canIncrement) {
      return;
    }
    _replace(
      line,
      line._with(quantity: line.quantity + line.product.quantityStep),
    );
  }

  /// One step less. At the minimum the line is removed instead: the cart
  /// never holds a quantity below the product's minimum.
  void decrement(int productId) {
    final line = _lineOf(productId);
    if (line == null) {
      return;
    }
    final next = line.quantity - line.product.quantityStep;
    if (next < line.product.minQuantity) {
      remove(productId);
    } else {
      _replace(line, line._with(quantity: next));
    }
  }

  void remove(int productId) {
    _lines.removeWhere((line) => line.product.id == productId);
    if (_lines.isEmpty) {
      _store = null;
    }
    notifyListeners();
  }

  /// Empties the cart (after a successful order, or on sign-out).
  void clear() {
    _lines.clear();
    _store = null;
    notifyListeners();
  }

  /// Brings the cart's lines up to date with a freshly loaded catalogue of
  /// [storeId]: new prices and rules replace the old ones, and a line that is
  /// gone, no longer orderable or no longer a valid quantity is flagged so the
  /// customer reviews it. The backend still decides at checkout.
  void syncWithCatalog(int storeId, List<CustomerProduct> products) {
    if (_store?.id != storeId || _lines.isEmpty) {
      return;
    }
    final byId = {for (final product in products) product.id: product};
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final fresh = byId[line.product.id];
      if (fresh == null || !fresh.isOrderable) {
        _lines[i] = line._with(
          product: fresh,
          problem: CartProblem.unavailable,
        );
      } else if (!_isValidQuantity(line.quantity, fresh)) {
        _lines[i] = line._with(
          product: fresh,
          problem: CartProblem.invalidQuantity,
        );
      } else {
        _lines[i] = line._with(product: fresh, clearProblem: true);
      }
    }
    notifyListeners();
  }

  /// Records what the customer now knows about the store (open or closed).
  void updateStore(CustomerStore store) {
    if (_store?.id == store.id) {
      _store = store;
      notifyListeners();
    }
  }

  /// Puts a line whose quantity became invalid back on the product's minimum.
  void fixQuantity(int productId) {
    final line = _lineOf(productId);
    if (line != null && line.problem == CartProblem.invalidQuantity) {
      _replace(
        line,
        line._with(quantity: line.product.minQuantity, clearProblem: true),
      );
    }
  }

  void _replace(CartLine old, CartLine replacement) {
    _lines[_lines.indexOf(old)] = replacement;
    notifyListeners();
  }

  /// The display rule the product states: from the minimum, in whole steps,
  /// up to the maximum. (Stock is the backend's business.)
  static bool _isValidQuantity(int quantity, CustomerProduct product) {
    final max = product.maxQuantity;
    return quantity >= product.minQuantity &&
        (max == null || quantity <= max) &&
        (quantity - product.minQuantity) % product.quantityStep == 0;
  }
}
