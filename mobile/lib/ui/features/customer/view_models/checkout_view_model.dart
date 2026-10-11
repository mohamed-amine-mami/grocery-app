import 'package:flutter/foundation.dart';

import '../../../../data/models/customer_order.dart';
import '../../../../data/repositories/customer_orders_repository.dart';
import '../../../../data/repositories/customer_stores_repository.dart';
import '../../../core/utils/idempotency_key.dart';
import '../../../core/utils/pickup_slots.dart';
import 'cart_view_model.dart';
import 'checkout_failure.dart';

/// One submission attempt: the key, and the exact request it was made for.
class _Attempt {
  const _Attempt(this.key, this.fingerprint);

  final String key;
  final String fingerprint;
}

/// The checkout: the pickup time, and sending the order.
///
/// Idempotency. One attempt has one key, created when the customer first
/// presses send and kept for as long as the outcome may be unknown (a network
/// error, a server error): pressing send again re-sends the same request with
/// the same key, and the backend answers with the original order if the first
/// request did get through. The key is dropped once the backend has answered
/// definitively (success, or a refusal that changes what must be sent), and a
/// request that differs from the attempt's (another cart, another pickup time)
/// always gets a fresh key — reusing one for a different request is a 409.
///
/// The cart is cleared only once the backend returned the created order. The
/// request carries ids, quantities, pickup time and key — never prices,
/// totals, names or stock.
class CheckoutViewModel extends ChangeNotifier {
  CheckoutViewModel({
    required this._ordersRepository,
    required this._storesRepository,
    required this.cart,
    DateTime Function()? now,
    IdempotencyKeyGenerator? generateKey,
  }) : _now = now ?? DateTime.now,
       _generateKey = generateKey ?? generateIdempotencyKey {
    refreshSlots();
  }

  final CustomerOrdersRepository _ordersRepository;
  final CustomerStoresRepository _storesRepository;
  final CartViewModel cart;
  final DateTime Function() _now;
  final IdempotencyKeyGenerator _generateKey;

  List<DateTime> _slots = const [];

  /// The pickup times on offer, every 30 minutes, earliest first.
  List<DateTime> get slots => _slots;

  DateTime? _selectedSlot;
  DateTime? get selectedSlot => _selectedSlot;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  CheckoutFailure? _failure;
  CheckoutFailure? get failure => _failure;

  CustomerOrder? _created;

  /// The order the backend created, once it did.
  CustomerOrder? get created => _created;

  _Attempt? _attempt;

  /// The key of the attempt in progress (the outcome may be unknown), if any.
  String? get pendingKey => _attempt?.key;

  /// The store is known to be closed: sending is blocked here, though the
  /// backend has the final word.
  bool get storeClosed => cart.store != null && !cart.store!.isOpen;

  bool get canSubmit =>
      !_isSubmitting &&
      _created == null &&
      !cart.isEmpty &&
      !cart.hasProblems &&
      !storeClosed &&
      _selectedSlot != null;

  /// Asks the backend whether the store is still open, so a closure that
  /// happened since browsing is known before sending. Best effort: the order
  /// request itself is the final authority.
  Future<void> refreshStoreState() async {
    final store = cart.store;
    if (store == null) {
      return;
    }
    try {
      final stores = await _storesRepository.stores();
      for (final fresh in stores) {
        if (fresh.id == store.id) {
          cart.updateStore(fresh);
        }
      }
    } catch (_) {
      // Offline: nothing new is known.
    }
  }

  /// Recomputes the pickup times from now. The selection is kept while it is
  /// still on offer, otherwise it moves to the earliest slot.
  void refreshSlots() {
    _slots = PickupSlots.generate(_now());
    final selected = _selectedSlot;
    _selectedSlot = selected != null && _slots.contains(selected)
        ? selected
        : (_slots.isEmpty ? null : _slots.first);
    notifyListeners();
  }

  void selectSlot(DateTime slot) {
    if (_slots.contains(slot)) {
      _selectedSlot = slot;
      notifyListeners();
    }
  }

  /// Sends the order. Returns the created order, or `null` (see [failure]).
  Future<CustomerOrder?> submit() async {
    if (_isSubmitting) {
      return null;
    }
    final existing = _created;
    if (existing != null) {
      return existing; // never sent twice
    }
    final store = cart.store;
    final slot = _selectedSlot;
    if (store == null || cart.isEmpty || slot == null || cart.hasProblems) {
      return null;
    }
    if (!store.isOpen) {
      _failure = CheckoutFailure.storeClosed;
      notifyListeners();
      return null;
    }
    if (_attempt == null && !PickupSlots.isStillBookable(slot, _now())) {
      // Obviously stale and nothing in flight: choose again, without asking.
      refreshSlots();
      _failure = CheckoutFailure.invalidPickupTime;
      notifyListeners();
      return null;
    }

    final lines = [
      for (final line in cart.lines)
        NewOrderLine(storeProductId: line.product.id, quantity: line.quantity),
    ];
    final fingerprint = _fingerprint(store.id, lines, slot);
    final attempt = _attempt?.fingerprint == fingerprint
        ? _attempt!
        : _Attempt(_generateKey(), fingerprint);
    _attempt = attempt;

    _isSubmitting = true;
    _failure = null;
    notifyListeners();
    try {
      final order = await _ordersRepository.create(
        NewOrderRequest(
          storeId: store.id,
          lines: lines,
          requestedPickupAt: slot,
          idempotencyKey: attempt.key,
        ),
      );
      _created = order;
      _attempt = null;
      cart.clear();
      return order;
    } catch (error) {
      final failure = CheckoutFailure.from(error);
      _failure = failure;
      if (_isDefinitive(failure.kind)) {
        _attempt = null; // refused: nothing was created under this key
      }
      await _reviewAfter(failure, store.id);
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// A refusal that settles the attempt: the backend did not create an order.
  /// A network or server error does not (the request may have succeeded).
  static bool _isDefinitive(CheckoutFailureKind kind) => switch (kind) {
    CheckoutFailureKind.network ||
    CheckoutFailureKind.unknown ||
    CheckoutFailureKind.sessionExpired => false,
    _ => true,
  };

  /// Brings what the customer is looking at up to date with what the backend
  /// just said, so the cart can be reviewed.
  Future<void> _reviewAfter(CheckoutFailure failure, int storeId) async {
    switch (failure.kind) {
      case CheckoutFailureKind.storeClosed:
        final store = cart.store;
        if (store != null) {
          cart.updateStore(store.copyWith(isOpen: false));
        }
      case CheckoutFailureKind.invalidPickupTime:
        refreshSlots();
      case CheckoutFailureKind.productUnavailable ||
          CheckoutFailureKind.insufficientStock ||
          CheckoutFailureKind.invalidQuantity ||
          CheckoutFailureKind.notFound:
        try {
          cart.syncWithCatalog(
            storeId,
            await _storesRepository.products(storeId),
          );
        } catch (_) {
          // The message stands; the catalogue reloads when the cart is shown.
        }
      default:
    }
  }

  static String _fingerprint(
    int storeId,
    List<NewOrderLine> lines,
    DateTime slot,
  ) {
    final sorted = [
      for (final line in lines) '${line.storeProductId}x${line.quantity}',
    ]..sort();
    return '$storeId|${sorted.join(',')}|${slot.toUtc().toIso8601String()}';
  }
}
