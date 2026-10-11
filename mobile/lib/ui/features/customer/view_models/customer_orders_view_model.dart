import 'package:flutter/foundation.dart';

import '../../../../data/models/customer_order.dart';
import '../../../../data/repositories/customer_orders_repository.dart';
import '../../../../data/repositories/orders_repository.dart';
import '../../../core/utils/poller.dart';
import '../../orders/order_errors.dart';
import '../../orders/view_models/owner_orders_view_model.dart'
    show ordersPollInterval;

enum CustomerOrdersStatus { loading, ready, failed }

/// The customer's order history: pages loaded so far, kept fresh by pull and
/// by polling (the same 30-second interval as the owner's). One request cycle
/// at a time; a poll tick that finds one running is skipped.
class CustomerOrdersViewModel extends ChangeNotifier {
  CustomerOrdersViewModel({
    required this._repository,
    this.pageSize = defaultPageSize,
    Duration pollInterval = ordersPollInterval,
  }) : assert(
         pageSize >= 1 && pageSize <= OrdersRepository.maxPageSize,
         'pageSize must respect the backend maximum',
       ) {
    _poller = Poller(interval: pollInterval, onTick: _poll);
  }

  static const defaultPageSize = 20;

  final CustomerOrdersRepository _repository;
  final int pageSize;
  late final Poller _poller;

  CustomerOrdersStatus _status = CustomerOrdersStatus.loading;
  CustomerOrdersStatus get status => _status;

  List<CustomerOrder> _orders = const [];
  List<CustomerOrder> get orders => _orders;

  int _total = 0;
  bool get hasMore => _orders.length < _total;
  int _pages = 0;

  bool _refreshFailed = false;
  bool get refreshFailed => _refreshFailed;

  OrderFailure? _failure;
  OrderFailure? get failure => _failure;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool get isPolling => _poller.isActive;

  Future<void>? _cycle;
  bool _disposed = false;

  Future<void> load() {
    _status = CustomerOrdersStatus.loading;
    _failure = null;
    notifyListeners();
    return _run(isInitial: true);
  }

  /// Pull-to-refresh and polling: reloads what is shown without a spinner and
  /// keeps it if the request fails. Joins a cycle already running.
  Future<void> refresh() => _cycle ?? _run(isInitial: false);

  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore || _cycle != null) {
      return;
    }
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repository.list(page: _pages + 1, limit: pageSize);
      if (_disposed) {
        return;
      }
      _orders = [..._orders, ...page.orders];
      _total = page.total;
      _pages += 1;
    } catch (error) {
      if (!_disposed) {
        _failure = OrderFailure.from(error);
        _refreshFailed = true;
      }
    } finally {
      if (!_disposed) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void startPolling() => _poller.start();
  void stopPolling() => _poller.stop();

  Future<void> _poll() async {
    if (_cycle == null && !_disposed) {
      await refresh();
    }
  }

  Future<void> _run({required bool isInitial}) {
    late final Future<void> cycle;
    cycle = _fetch(isInitial: isInitial).whenComplete(() {
      if (identical(_cycle, cycle)) {
        _cycle = null;
      }
    });
    _cycle = cycle;
    return cycle;
  }

  Future<void> _fetch({required bool isInitial}) async {
    try {
      // Reload exactly the pages already shown, so a poll never collapses a
      // list the customer has scrolled.
      final pages = _pages < 1 ? 1 : _pages;
      final loaded = <CustomerOrder>[];
      var total = 0;
      for (var page = 1; page <= pages; page++) {
        final result = await _repository.list(page: page, limit: pageSize);
        loaded.addAll(result.orders);
        total = result.total;
        if (result.orders.length < pageSize) {
          break;
        }
      }
      if (_disposed) {
        return;
      }
      _orders = loaded;
      _total = total;
      _pages = (loaded.length / pageSize).ceil().clamp(1, 1 << 30);
      _status = CustomerOrdersStatus.ready;
      _refreshFailed = false;
      _failure = null;
    } catch (error) {
      if (_disposed) {
        return;
      }
      _failure = OrderFailure.from(error);
      if (isInitial || _status != CustomerOrdersStatus.ready) {
        _status = CustomerOrdersStatus.failed;
      } else {
        _refreshFailed = true;
      }
    } finally {
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }
}
