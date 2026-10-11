import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/models/order.dart';
import '../../../../data/repositories/orders_repository.dart';
import '../order_errors.dart';

enum OrdersStatus { loading, ready, failed }

/// How often the open Orders tab asks the backend for fresh orders (V1 is
/// polling and pull-to-refresh only, see `docs/orders.md`).
const ordersPollInterval = Duration(seconds: 30);

/// The owner's order list: the selected status filter, the pages loaded so
/// far, the pending count, and the polling that keeps them fresh.
///
/// One request cycle at a time: a poll tick that finds a cycle running is
/// skipped, and a manual refresh joins the running one. The pending count is
/// the backend's own — the `total` of a `status=PENDING` request, which is
/// the list itself when the filter is "En attente" — never counted locally.
class OwnerOrdersViewModel extends ChangeNotifier {
  OwnerOrdersViewModel({
    required this._ordersRepository,
    this.pollInterval = ordersPollInterval,
    this.pageSize = defaultPageSize,
  }) : assert(
         pageSize >= 1 && pageSize <= OrdersRepository.maxPageSize,
         'pageSize must respect the backend maximum',
       );

  static const defaultPageSize = 20;

  final OrdersRepository _ordersRepository;
  final Duration pollInterval;
  final int pageSize;

  OrdersStatus _status = OrdersStatus.loading;
  OrdersStatus get status => _status;

  /// `null` = all statuses.
  OrderStatus? _filter;
  OrderStatus? get filter => _filter;

  List<Order> _orders = const [];
  List<Order> get orders => _orders;

  /// Orders matching the filter, across pages (backend value).
  int _total = 0;
  int get total => _total;

  /// Pages loaded so far; a refresh reloads exactly these.
  int _pages = 0;
  bool get hasMore => _orders.length < _total;

  /// The backend's count of `PENDING` orders; `null` until first known.
  int? _pendingCount;
  int? get pendingCount => _pendingCount;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// The last refresh failed; what is shown is the previous data.
  bool _refreshFailed = false;
  bool get refreshFailed => _refreshFailed;

  OrderFailure? _failure;
  OrderFailure? get failure => _failure;

  Timer? _timer;
  bool get isPolling => _timer != null;

  Future<void>? _cycle;

  /// Bumped when the filter changes, so a response for the old filter is
  /// dropped.
  int _generation = 0;
  bool _disposed = false;

  /// First load (and the retry of a failed one): shows the loading state.
  Future<void> load() {
    _status = OrdersStatus.loading;
    _failure = null;
    notifyListeners();
    return _run(isInitial: true);
  }

  /// Pull-to-refresh and polling: reloads what is shown without replacing it
  /// with a spinner, and keeps it if the request fails. Joins a cycle that is
  /// already running instead of starting a second one.
  Future<void> refresh() {
    final running = _cycle;
    if (running != null) {
      return running;
    }
    _isRefreshing = true;
    notifyListeners();
    return _run(isInitial: false);
  }

  /// A poll tick: like [refresh], but skipped while a cycle is running.
  Future<void> _poll() async {
    if (_cycle != null || _disposed) {
      return;
    }
    await refresh();
  }

  Future<void> selectFilter(OrderStatus? filter) {
    if (filter == _filter) {
      return _cycle ?? Future.value();
    }
    _filter = filter;
    _generation++;
    _cycle = null; // the running cycle (for the old filter) is obsolete
    _isRefreshing = false;
    _orders = const [];
    _total = 0;
    _pages = 0;
    return load();
  }

  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore || _cycle != null) {
      return;
    }
    _isLoadingMore = true;
    notifyListeners();
    final generation = _generation;
    try {
      final page = await _ordersRepository.list(
        status: _filter,
        page: _pages + 1,
        limit: pageSize,
      );
      if (generation != _generation || _disposed) {
        return;
      }
      _orders = [..._orders, ...page.orders];
      _total = page.total;
      _pages += 1;
    } catch (error) {
      if (generation == _generation && !_disposed) {
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

  /// Starts the polling timer. Safe to call repeatedly: there is never more
  /// than one timer.
  void startPolling() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run({required bool isInitial}) {
    final generation = _generation;
    late final Future<void> cycle;
    cycle = _fetch(isInitial: isInitial, generation: generation).whenComplete(
      () {
        if (identical(_cycle, cycle)) {
          _cycle = null;
        }
      },
    );
    _cycle = cycle;
    return cycle;
  }

  Future<void> _fetch({
    required bool isInitial,
    required int generation,
  }) async {
    try {
      // Reload exactly the pages already shown (at least the first), so
      // polling never collapses a list the owner has scrolled.
      final pages = _pages < 1 ? 1 : _pages;
      final loaded = <Order>[];
      var total = 0;
      for (var page = 1; page <= pages; page++) {
        final result = await _ordersRepository.list(
          status: _filter,
          page: page,
          limit: pageSize,
        );
        loaded.addAll(result.orders);
        total = result.total;
        if (result.orders.length < pageSize) {
          break;
        }
      }
      final pending = _filter == OrderStatus.pending
          ? total
          : (await _ordersRepository.list(
              status: OrderStatus.pending,
              limit: 1,
            )).total;
      if (generation != _generation || _disposed) {
        return;
      }
      _orders = loaded;
      _total = total;
      _pages = (loaded.length / pageSize).ceil().clamp(1, 1 << 30);
      _pendingCount = pending;
      _status = OrdersStatus.ready;
      _refreshFailed = false;
      _failure = null;
    } catch (error) {
      if (generation != _generation || _disposed) {
        return;
      }
      _failure = OrderFailure.from(error);
      if (isInitial || _status != OrdersStatus.ready) {
        _status = OrdersStatus.failed;
      } else {
        _refreshFailed = true; // keep showing the previous data
      }
    } finally {
      if (generation == _generation && !_disposed) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
