import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/order.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/ui/features/orders/order_errors.dart';
import 'package:grocery_mobile/ui/features/orders/view_models/owner_orders_view_model.dart';

import 'fakes.dart';

FakeOrdersRepository _repo(List<Order> orders) =>
    FakeOrdersRepository(ApiClient(), orders: orders);

OwnerOrdersViewModel _vm(
  FakeOrdersRepository repo, {
  int pageSize = 20,
  Duration poll = ordersPollInterval,
}) => OwnerOrdersViewModel(
  ordersRepository: repo,
  pageSize: pageSize,
  pollInterval: poll,
);

/// Orders 1..n with the given statuses.
List<Order> _orders(List<OrderStatus> statuses) => [
  for (final (i, status) in statuses.indexed)
    fakeOrder(id: i + 1, code: 'ORD${i + 1}', status: status),
];

void main() {
  group('loading', () {
    test('starts loading, then shows the orders newest first', () async {
      final repo = _repo(_orders([OrderStatus.pending, OrderStatus.confirmed]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      expect(vm.status, OrdersStatus.loading);

      await vm.load();

      expect(vm.status, OrdersStatus.ready);
      expect(vm.orders.map((o) => o.code), ['ORD2', 'ORD1']);
      expect(vm.total, 2);
    });

    test('the first request is page 1 with the configured size', () async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo, pageSize: 20);
      addTearDown(vm.dispose);
      await vm.load();
      expect(repo.listCalls.first, (status: null, page: 1, limit: 20));
    });

    test(
      'a failed first load is a failed state that a retry can fix',
      () async {
        final repo = _repo([])..fails = true;
        final vm = _vm(repo);
        addTearDown(vm.dispose);

        await vm.load();
        expect(vm.status, OrdersStatus.failed);
        expect(vm.failure?.kind, OrderFailureKind.network);

        repo.fails = false;
        await vm.load();
        expect(vm.status, OrdersStatus.ready);
        expect(vm.failure, isNull);
      },
    );

    test('an empty store is ready, with nothing to show', () async {
      final vm = _vm(_repo([]));
      addTearDown(vm.dispose);
      await vm.load();
      expect(vm.status, OrdersStatus.ready);
      expect(vm.orders, isEmpty);
      expect(vm.pendingCount, 0);
    });
  });

  group('pagination', () {
    test('never asks for more than the backend’s maximum page', () {
      expect(
        () => OwnerOrdersViewModel(ordersRepository: _repo([]), pageSize: 51),
        throwsA(isA<AssertionError>()),
      );
    });

    test('loads further pages on demand and stops at the total', () async {
      final repo = _repo(_orders(List.filled(5, OrderStatus.confirmed)));
      final vm = _vm(repo, pageSize: 2);
      addTearDown(vm.dispose);
      await vm.load();
      expect(vm.orders, hasLength(2));
      expect(vm.hasMore, isTrue);

      await vm.loadMore();
      expect(vm.orders.map((o) => o.code), ['ORD5', 'ORD4', 'ORD3', 'ORD2']);
      await vm.loadMore();
      expect(vm.orders, hasLength(5));
      expect(vm.hasMore, isFalse);

      final before = repo.listCallCount;
      await vm.loadMore();
      expect(repo.listCallCount, before);
    });

    test('a refresh reloads the pages already shown, in order', () async {
      final repo = _repo(_orders(List.filled(5, OrderStatus.confirmed)));
      final vm = _vm(repo, pageSize: 2);
      addTearDown(vm.dispose);
      await vm.load();
      await vm.loadMore();
      repo.add(fakeOrder(id: 6, code: 'ORD6', status: OrderStatus.confirmed));
      repo.listCalls.clear();

      await vm.refresh();

      expect(vm.orders.map((o) => o.code), ['ORD6', 'ORD5', 'ORD4', 'ORD3']);
      final pages = repo.listCalls
          .where((c) => c.status == null)
          .map((c) => c.page);
      expect(pages, [1, 2]);
      expect(repo.listCalls.every((c) => c.limit <= 50), isTrue);
    });
  });

  group('status filter', () {
    test('every status filter requests that status from the backend', () async {
      final repo = _repo(
        _orders([
          OrderStatus.pending,
          OrderStatus.confirmed,
          OrderStatus.readyForPickup,
          OrderStatus.completed,
          OrderStatus.cancelled,
          OrderStatus.noShow,
        ]),
      );
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();

      for (final status in OrderStatus.values) {
        repo.listCalls.clear();
        await vm.selectFilter(status);
        expect(vm.filter, status);
        expect(repo.listCalls.first.status, status);
        expect(vm.orders.map((o) => o.status).toSet(), {status});
      }

      repo.listCalls.clear();
      await vm.selectFilter(null);
      expect(repo.listCalls.first.status, isNull);
      expect(vm.orders, hasLength(6));
    });

    test('selecting the filter already selected does not reload', () async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();
      await vm.selectFilter(OrderStatus.pending);
      repo.listCalls.clear();
      await vm.selectFilter(OrderStatus.pending);
      expect(repo.listCalls, isEmpty);
    });

    test('the filter is kept by refresh and by polling', () async {
      final repo = _repo(_orders([OrderStatus.pending, OrderStatus.confirmed]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();
      await vm.selectFilter(OrderStatus.confirmed);
      repo.listCalls.clear();

      await vm.refresh();

      expect(vm.filter, OrderStatus.confirmed);
      expect(repo.listCalls.where((c) => c.limit != 1).map((c) => c.status), [
        OrderStatus.confirmed,
      ]);
      expect(vm.orders.map((o) => o.status).toSet(), {OrderStatus.confirmed});
    });

    test('an answer for the previous filter is dropped', () async {
      final repo = _repo(_orders([OrderStatus.pending, OrderStatus.confirmed]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();

      final gate = Completer<void>();
      repo.gate = gate;
      final slow = vm.selectFilter(OrderStatus.pending);
      repo.gate = null;
      await vm.selectFilter(OrderStatus.confirmed);
      gate.complete();
      await slow;

      expect(vm.filter, OrderStatus.confirmed);
      expect(vm.orders.map((o) => o.status).toSet(), {OrderStatus.confirmed});
    });
  });

  group('pending count', () {
    test('is the backend’s count, whatever the filter', () async {
      final repo = _repo(
        _orders([
          OrderStatus.pending,
          OrderStatus.pending,
          OrderStatus.confirmed,
          OrderStatus.completed,
        ]),
      );
      final vm = _vm(repo);
      addTearDown(vm.dispose);

      await vm.load();
      expect(vm.pendingCount, 2);

      await vm.selectFilter(OrderStatus.completed);
      expect(vm.pendingCount, 2);
      expect(vm.orders, hasLength(1));
    });

    test(
      'with the pending filter the list total is the count: one request',
      () async {
        final repo = _repo(_orders([OrderStatus.pending, OrderStatus.pending]));
        final vm = _vm(repo);
        addTearDown(vm.dispose);
        await vm.selectFilter(OrderStatus.pending);
        repo.listCalls.clear();

        await vm.refresh();

        expect(repo.listCalls, hasLength(1));
        expect(vm.pendingCount, 2);
      },
    );

    test(
      'is read with a one-order request when the list is another status',
      () async {
        final repo = _repo(
          _orders([OrderStatus.pending, OrderStatus.confirmed]),
        );
        final vm = _vm(repo);
        addTearDown(vm.dispose);
        await vm.load();
        expect(
          repo.listCalls.where((c) => c.status == OrderStatus.pending).single,
          (status: OrderStatus.pending, page: 1, limit: 1),
        );
      },
    );

    test('follows the backend after a refresh', () async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();
      expect(vm.pendingCount, 1);

      repo.add(fakeOrder(id: 2, code: 'ORD2'));
      repo.add(fakeOrder(id: 3, code: 'ORD3'));
      await vm.refresh();
      expect(vm.pendingCount, 3);

      repo.replace(
        fakeOrder(id: 1, code: 'ORD1', status: OrderStatus.confirmed),
      );
      await vm.refresh();
      expect(vm.pendingCount, 2);
    });

    test('keeps the last known count when a refresh fails', () async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();

      repo.fails = true;
      await vm.refresh();

      expect(vm.pendingCount, 1);
      expect(vm.orders, hasLength(1));
      expect(vm.status, OrdersStatus.ready);
      expect(vm.refreshFailed, isTrue);
    });
  });

  group('refresh', () {
    test(
      'keeps the list on screen while refreshing and clears the error',
      () async {
        final repo = _repo(_orders([OrderStatus.pending]));
        final vm = _vm(repo);
        addTearDown(vm.dispose);
        await vm.load();

        repo.fails = true;
        await vm.refresh();
        expect(vm.refreshFailed, isTrue);
        expect(vm.failure?.kind, OrderFailureKind.network);

        repo.fails = false;
        await vm.refresh();
        expect(vm.refreshFailed, isFalse);
        expect(vm.failure, isNull);
      },
    );

    test('a refresh while one is running joins it', () async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo);
      addTearDown(vm.dispose);
      await vm.load();
      repo.listCalls.clear();

      final gate = Completer<void>();
      repo.gate = gate;
      final first = vm.refresh();
      final second = vm.refresh();
      expect(identical(first, second), isTrue);
      gate.complete();
      await first;
      repo.gate = null;

      // One cycle: the list, then the pending count.
      expect(repo.listCalls, hasLength(2));
    });
  });

  group('polling', () {
    testWidgets(
      'refreshes on every tick, with one timer however often it is started',
      (tester) async {
        final repo = _repo(_orders([OrderStatus.pending]));
        final vm = _vm(repo, poll: const Duration(seconds: 30));
        await vm.load();
        repo.listCalls.clear();

        vm
          ..startPolling()
          ..startPolling()
          ..startPolling();
        expect(vm.isPolling, isTrue);

        await tester.pump(const Duration(seconds: 29));
        expect(repo.listCalls, isEmpty);

        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        final afterFirst = repo.listCallCount;
        expect(afterFirst, greaterThan(0));

        repo.add(fakeOrder(id: 2, code: 'ORD2'));
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();
        // Exactly one more cycle (the same number of requests), not three.
        expect(repo.listCallCount, afterFirst * 2);
        expect(vm.pendingCount, 2);
        expect(vm.orders, hasLength(2));
        vm.dispose();
      },
    );

    testWidgets('uses the V1 interval', (tester) async {
      expect(ordersPollInterval, const Duration(seconds: 30));
    });

    testWidgets('does not start a second request while one is running', (
      tester,
    ) async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo, poll: const Duration(seconds: 30));
      await vm.load();
      repo.listCalls.clear();

      final gate = Completer<void>();
      repo.gate = gate;
      vm.startPolling();
      await tester.pump(const Duration(seconds: 30));
      final duringFirst = repo.listCallCount;
      expect(duringFirst, 1);

      // Two more ticks while the first request is still waiting.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(repo.listCallCount, duringFirst);

      gate.complete();
      repo.gate = null;
      await tester.pump();
      await tester.pump();
      vm.dispose();
    });

    testWidgets('stops when told to, and can start again', (tester) async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo, poll: const Duration(seconds: 30));
      await vm.load();
      vm.startPolling();
      vm.stopPolling();
      expect(vm.isPolling, isFalse);
      repo.listCalls.clear();

      await tester.pump(const Duration(seconds: 90));
      expect(repo.listCalls, isEmpty);

      vm.startPolling();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(repo.listCalls, isNotEmpty);
      vm.dispose();
    });

    testWidgets('stops when the view model is disposed', (tester) async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo, poll: const Duration(seconds: 30));
      await vm.load();
      vm.startPolling();
      vm.dispose();
      repo.listCalls.clear();

      await tester.pump(const Duration(seconds: 120));
      expect(repo.listCalls, isEmpty);
      // Starting after dispose does nothing either.
      vm.startPolling();
      expect(vm.isPolling, isFalse);
    });

    testWidgets('keeps the selected filter on every tick', (tester) async {
      final repo = _repo(_orders([OrderStatus.pending, OrderStatus.confirmed]));
      final vm = _vm(repo, poll: const Duration(seconds: 30));
      await vm.load();
      await vm.selectFilter(OrderStatus.confirmed);
      repo.listCalls.clear();
      vm.startPolling();

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(repo.listCalls.where((c) => c.limit != 1).map((c) => c.status), [
        OrderStatus.confirmed,
      ]);
      expect(vm.filter, OrderStatus.confirmed);
      vm.dispose();
    });

    testWidgets('a failing tick keeps the data and the next one recovers', (
      tester,
    ) async {
      final repo = _repo(_orders([OrderStatus.pending]));
      final vm = _vm(repo, poll: const Duration(seconds: 30));
      await vm.load();
      vm.startPolling();

      repo.fails = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(vm.refreshFailed, isTrue);
      expect(vm.orders, hasLength(1));

      repo.fails = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(vm.refreshFailed, isFalse);
      vm.dispose();
    });
  });
}
