import 'package:flutter/foundation.dart';

import '../../../../data/models/customer_order.dart';
import '../../../../data/repositories/customer_orders_repository.dart';
import '../../../core/utils/poller.dart';
import '../../orders/order_errors.dart';
import '../../orders/view_models/owner_orders_view_model.dart'
    show ordersPollInterval;

/// One order, for its customer: the order as last seen, reloaded by pull and
/// by polling while it can still change, and the cancellation. Every value
/// shown is the backend's.
class CustomerOrderDetailViewModel extends ChangeNotifier {
  CustomerOrderDetailViewModel({
    required this._repository,
    required this._order,
    Duration pollInterval = ordersPollInterval,
  }) {
    _poller = Poller(interval: pollInterval, onTick: _poll);
  }

  final CustomerOrdersRepository _repository;
  late final Poller _poller;

  CustomerOrder _order;
  CustomerOrder get order => _order;

  bool _isBusy = false;

  /// A cancellation is running.
  bool get isBusy => _isBusy;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  /// The order is no longer available to this customer (404).
  bool _isGone = false;
  bool get isGone => _isGone;

  bool _disposed = false;
  Future<OrderFailure?>? _refreshing;

  bool get isPolling => _poller.isActive;

  /// Cancellation is offered for a pending or confirmed order only.
  bool get canCancel => _order.canCancel;

  /// Starts polling while the order can still change; a finished order needs
  /// no more requests.
  void startPolling() {
    if (!_order.isFinished) {
      _poller.start();
    }
  }

  void stopPolling() => _poller.stop();

  Future<void> _poll() async {
    if (_isBusy || _disposed) {
      return;
    }
    await refresh();
  }

  /// Reloads the order; joins a reload already running. Returns the failure,
  /// if any, and keeps the current order when it fails.
  Future<OrderFailure?> refresh() =>
      _refreshing ??= _reload().whenComplete(() => _refreshing = null);

  Future<OrderFailure?> _reload() async {
    _isRefreshing = true;
    notifyListeners();
    try {
      _adopt(await _repository.get(_order.id));
      return null;
    } catch (error) {
      return _failed(error);
    } finally {
      _isRefreshing = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Cancels the order. On `ORDER_STATE_CHANGED` the order is reloaded so the
  /// current state shows; the cancellation is never retried.
  Future<OrderFailure?> cancel() async {
    if (_isBusy) {
      return null;
    }
    _isBusy = true;
    notifyListeners();
    try {
      _adopt((await _repository.cancel(_order.id)).order);
      return null;
    } catch (error) {
      final failure = _failed(error);
      if (failure.kind == OrderFailureKind.stateChanged) {
        try {
          _adopt(await _repository.get(_order.id));
        } catch (reloadError) {
          _failed(reloadError);
        }
      }
      return failure;
    } finally {
      _isBusy = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  OrderFailure _failed(Object error) {
    final failure = OrderFailure.from(error);
    if (failure.kind == OrderFailureKind.notFound) {
      _isGone = true;
    }
    return failure;
  }

  void _adopt(CustomerOrder order) {
    if (_disposed) {
      return;
    }
    _order = order;
    if (order.isFinished) {
      _poller.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }
}
