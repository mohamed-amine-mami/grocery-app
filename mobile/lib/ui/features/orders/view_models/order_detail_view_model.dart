import 'package:flutter/foundation.dart';

import '../../../../data/models/order.dart';
import '../../../../data/repositories/orders_repository.dart';
import '../order_errors.dart';

/// What the owner can ask for on an order. Which of these are offered for a
/// status is a display choice; the backend decides what is actually allowed
/// and answers `ORDER_STATE_CHANGED` otherwise.
enum OrderAction { confirm, cancel, ready, complete, noShow }

/// One order's detail screen: the order as last seen, the lines the owner has
/// staged for removal before confirming, and the actions. No total, stock or
/// transition rule is computed here — every result is the backend's order.
class OrderDetailViewModel extends ChangeNotifier {
  OrderDetailViewModel({required this._ordersRepository, required this._order});

  final OrdersRepository _ordersRepository;

  Order _order;
  Order get order => _order;

  final _staged = <int>{};

  /// Ids of the lines staged for removal (only while the order is pending).
  Set<int> get stagedRemovals => Set.unmodifiable(_staged);

  bool _isBusy = false;

  /// An action or a reload is running.
  bool get isBusy => _isBusy;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  /// The order is gone from this store (404).
  bool _isGone = false;
  bool get isGone => _isGone;

  /// The action buttons shown for the current status; completed, cancelled
  /// and no-show orders offer none.
  List<OrderAction> get actions => switch (_order.status) {
    OrderStatus.pending => const [OrderAction.confirm, OrderAction.cancel],
    OrderStatus.confirmed => const [OrderAction.ready, OrderAction.cancel],
    OrderStatus.readyForPickup => const [
      OrderAction.complete,
      OrderAction.noShow,
    ],
    OrderStatus.completed ||
    OrderStatus.cancelled ||
    OrderStatus.noShow => const [],
  };

  bool get canStageRemovals => _order.status == OrderStatus.pending;

  /// The lines that would be kept / removed by confirming now.
  List<OrderItem> get keptItems => [
    for (final item in _order.activeItems)
      if (!_staged.contains(item.id)) item,
  ];

  List<OrderItem> get stagedItems => [
    for (final item in _order.activeItems)
      if (_staged.contains(item.id)) item,
  ];

  /// Confirming would remove every line: the owner must cancel instead, and
  /// no request is made.
  bool get wouldRemoveAll =>
      canStageRemovals && _order.activeItems.isNotEmpty && keptItems.isEmpty;

  void toggleRemoval(int itemId) {
    if (!canStageRemovals ||
        _isBusy ||
        !_order.activeItems.any((item) => item.id == itemId)) {
      return;
    }
    if (!_staged.remove(itemId)) {
      _staged.add(itemId);
    }
    notifyListeners();
  }

  /// Confirms the order, removing the staged lines. Does nothing (returns
  /// `null`) when every line is staged.
  Future<OrderFailure?> confirm() {
    if (wouldRemoveAll) {
      return Future.value();
    }
    final ids = [..._staged]..sort();
    return _act(() => _ordersRepository.confirm(_order.id, removeItemIds: ids));
  }

  Future<OrderFailure?> markReady() =>
      _act(() => _ordersRepository.markReady(_order.id));

  Future<OrderFailure?> complete() =>
      _act(() => _ordersRepository.complete(_order.id));

  Future<OrderFailure?> markNoShow() =>
      _act(() => _ordersRepository.markNoShow(_order.id));

  Future<OrderFailure?> cancel(String reason) =>
      _act(() => _ordersRepository.cancel(_order.id, reason: reason.trim()));

  /// Reloads the order. Returns the failure, if any; keeps the current order
  /// when the reload fails.
  Future<OrderFailure?> refresh() async {
    if (_isBusy) {
      return null;
    }
    _isRefreshing = true;
    notifyListeners();
    try {
      _adopt(await _ordersRepository.get(_order.id));
      return null;
    } catch (error) {
      return _failed(error);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<OrderFailure?> _act(Future<OrderTransition> Function() request) async {
    if (_isBusy) {
      return null;
    }
    _isBusy = true;
    notifyListeners();
    try {
      _adopt((await request()).order);
      return null;
    } catch (error) {
      final failure = _failed(error);
      if (failure.kind == OrderFailureKind.stateChanged ||
          failure.kind == OrderFailureKind.stockChanged) {
        // Show what is true now; the owner decides again. Never retried.
        try {
          _adopt(await _ordersRepository.get(_order.id));
        } catch (reloadError) {
          _failed(reloadError);
        }
      }
      return failure;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  OrderFailure _failed(Object error) {
    final failure = OrderFailure.from(error);
    if (failure.kind == OrderFailureKind.notFound) {
      _isGone = true;
    }
    return failure;
  }

  void _adopt(Order order) {
    _order = order;
    if (!canStageRemovals) {
      _staged.clear();
    } else {
      _staged.removeWhere(
        (id) => !_order.activeItems.any((item) => item.id == id),
      );
    }
  }
}
