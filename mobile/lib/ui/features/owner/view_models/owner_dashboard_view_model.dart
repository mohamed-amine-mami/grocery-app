import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/models/order.dart';
import '../../../../data/models/store_product.dart';
import '../../../../data/repositories/orders_repository.dart';
import '../../../../data/repositories/store_products_repository.dart';
import '../../orders/view_models/owner_orders_view_model.dart'
    show ordersPollInterval;

enum DashboardStatus { loading, ready, failed }

/// What the owner's home knows beyond the store itself: enough to drive the
/// setup checklist, the order workload (how many orders wait for the store at
/// each step), the next pickups, and the stock alerts.
///
/// Everything is the backend's own: a count is the `total` of a status
/// filtered request, an alert is the backend's `isOrderable` /
/// `unavailabilityReason` verdict on a product. Nothing is recomputed from
/// stock or status rules here.
class OwnerDashboardViewModel extends ChangeNotifier {
  OwnerDashboardViewModel({
    required this._storeProductsRepository,
    required this._ordersRepository,
    this.pollInterval = ordersPollInterval,
  });

  final StoreProductsRepository _storeProductsRepository;
  final OrdersRepository _ordersRepository;

  /// How often the visible home asks for fresh numbers.
  final Duration pollInterval;

  /// How many pickups the home lists.
  static const upcomingLimit = 3;

  // ── Products (checklist, stock) ─────────────────────────────────────────

  DashboardStatus _status = DashboardStatus.loading;

  /// The products' state: it drives the checklist and the stock block.
  DashboardStatus get status => _status;

  /// Active (non-archived) store products only.
  int _productCount = 0;
  int get productCount => _productCount;

  bool get hasProduct => _productCount > 0;

  /// Active offerings customers can order right now: the backend's own
  /// `isOrderable` verdict on each one (owner switch, stock and catalogue
  /// combined), never recomputed here.
  int _orderableCount = 0;
  int get orderableCount => _orderableCount;

  bool get hasOrderable => _orderableCount > 0;

  /// Active products whose verdict is "tracked stock is zero".
  int _outOfStockCount = 0;
  int get outOfStockCount => _outOfStockCount;

  /// Active products whose verdict is "stock is positive but below the
  /// minimum order".
  int _belowMinimumCount = 0;
  int get belowMinimumCount => _belowMinimumCount;

  // ── Orders (workload, pickups) ──────────────────────────────────────────

  DashboardStatus _ordersStatus = DashboardStatus.loading;

  /// The orders' state, independent of the products': one failing does not
  /// hide the other.
  DashboardStatus get ordersStatus => _ordersStatus;

  /// The backend's count of `PENDING` orders: waiting for the store to
  /// confirm.
  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  /// The backend's count of `CONFIRMED` orders: to prepare.
  int _confirmedCount = 0;
  int get confirmedCount => _confirmedCount;

  /// The backend's count of `READY_FOR_PICKUP` orders: waiting at the store.
  int _readyCount = 0;
  int get readyCount => _readyCount;

  List<Order> _upcoming = const [];

  /// Up to [upcomingLimit] confirmed or ready orders, soonest requested
  /// pickup first. Cancelled, uncollected and completed orders are never
  /// here, and a pending order is not a pickup yet.
  List<Order> get upcomingPickups => _upcoming;

  /// There is work or something to pick up.
  bool get hasActivity =>
      _pendingCount > 0 ||
      _confirmedCount > 0 ||
      _readyCount > 0 ||
      _upcoming.isNotEmpty;

  /// The requested time has passed. It is the customer's desired time, not a
  /// reservation: the home says so in words and never calls it late.
  static bool isRequestedTimePast(Order order, DateTime now) =>
      order.requestedPickupAt.isBefore(now.toUtc());

  // ── Refresh ─────────────────────────────────────────────────────────────

  Future<bool>? _cycle;
  Timer? _timer;
  bool _disposed = false;

  bool get isPolling => _timer != null;

  /// Reloads the numbers. Keeps showing the previous ones while refreshing so
  /// the dashboard doesn't flicker when the owner comes back to the tab, and
  /// joins a cycle that is already running. Returns whether the product
  /// counts are now known to be up to date.
  Future<bool> refresh() => _cycle ??= _run();

  Future<bool> _run() async {
    final firstProducts = _status != DashboardStatus.ready;
    final firstOrders = _ordersStatus != DashboardStatus.ready;
    if (firstProducts || firstOrders) {
      if (firstProducts) {
        _status = DashboardStatus.loading;
      }
      if (firstOrders) {
        _ordersStatus = DashboardStatus.loading;
      }
      notifyListeners();
    }
    try {
      // Both at once; the orders' outcome never decides the products'.
      final products = _loadProducts(firstLoad: firstProducts);
      final orders = _loadOrders(firstLoad: firstOrders);
      final productsOk = await products;
      await orders;
      return productsOk;
    } finally {
      _cycle = null;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<bool> _loadProducts({required bool firstLoad}) async {
    try {
      final products = await _storeProductsRepository.listActive();
      _productCount = products.length;
      _orderableCount = products.where((p) => p.isOrderable).length;
      _outOfStockCount = products
          .where(
            (p) => p.unavailabilityReason == UnavailabilityReason.outOfStock,
          )
          .length;
      _belowMinimumCount = products
          .where(
            (p) =>
                p.unavailabilityReason ==
                UnavailabilityReason.stockBelowMinimum,
          )
          .length;
      _status = DashboardStatus.ready;
      return true;
    } catch (_) {
      // Keep stale-but-valid numbers if we already had some.
      if (firstLoad) {
        _status = DashboardStatus.failed;
      }
      return false;
    }
  }

  Future<void> _loadOrders({required bool firstLoad}) async {
    try {
      final pages = await Future.wait([
        _ordersRepository.list(status: OrderStatus.pending, limit: 1),
        _ordersRepository.list(
          status: OrderStatus.confirmed,
          limit: OrdersRepository.maxPageSize,
        ),
        _ordersRepository.list(
          status: OrderStatus.readyForPickup,
          limit: OrdersRepository.maxPageSize,
        ),
      ]);
      _pendingCount = pages[0].total;
      _confirmedCount = pages[1].total;
      _readyCount = pages[2].total;
      final pickups = [...pages[1].orders, ...pages[2].orders]
        ..sort((a, b) {
          final byTime = a.requestedPickupAt.compareTo(b.requestedPickupAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      _upcoming = pickups.take(upcomingLimit).toList();
      _ordersStatus = DashboardStatus.ready;
    } catch (_) {
      if (firstLoad) {
        _ordersStatus = DashboardStatus.failed;
      }
    }
  }

  /// Starts asking for fresh numbers every [pollInterval]. The home calls this
  /// only while it is the visible tab and the app is in the foreground.
  void startPolling() {
    if (_timer != null || _disposed) {
      return;
    }
    _timer = Timer.periodic(pollInterval, (_) {
      if (_cycle == null && !_disposed) {
        refresh();
      }
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
