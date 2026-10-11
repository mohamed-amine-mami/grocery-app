import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/ui/core/photo/photo_image.dart';
import 'package:grocery_mobile/ui/core/theme/app_theme.dart';
import 'package:grocery_mobile/ui/core/widgets/product_image.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Answers every image request with a PNG (or an error status), after a gate
/// if there is one — no real network.
/// `NetworkImage` keeps one shared HTTP client for the whole run, so the fake
/// goes through its test hook rather than `HttpOverrides`.
Future<void> _serving(
  Future<void> Function() body, {
  int status = 200,
  Completer<void>? gate,
}) async {
  debugNetworkImageHttpClientProvider = () => _Client(status, gate);
  try {
    await body();
  } finally {
    // Before the binding checks that no painting debug variable is left set.
    debugNetworkImageHttpClientProvider = null;
  }
}

class _Client implements HttpClient {
  _Client(this.status, this.gate);

  final int status;
  final Completer<void>? gate;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(status, gate);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.status, this.gate);

  final int status;
  final Completer<void>? gate;

  @override
  final headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    await gate?.future;
    return _Response(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode);

  @override
  final int statusCode;

  @override
  int get contentLength => statusCode == 200 ? _png.length : 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([if (statusCode == 200) _png])
          .listen(onData, onError: onError, onDone: onDone);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(Widget child, {double dpr = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(devicePixelRatio: dpr),
    child: Scaffold(body: Center(child: child)),
  ),
);

const _url = 'https://images.example.com/yaourt.webp';

final _placeholder = find.byIcon(Icons.shopping_basket_rounded);

Future<void> _settle(WidgetTester tester) async {
  // Image decoding finishes outside the fake-async zone.
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  // The image cache is global: without this, one test's picture is another's.
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('no photo: the neutral placeholder', (tester) async {
    await tester.pumpWidget(_app(const ProductImage(photo: null)));
    expect(_placeholder, findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the placeholder uses the same tint and icon tone as the store '
      'photo placeholder', (tester) async {
    await tester.pumpWidget(_app(const ProductImage(photo: null)));

    final icon = tester.widget<Icon>(_placeholder);
    expect(icon.color, AppColors.primary.withValues(alpha: 0.6));

    final box = tester.widget<Container>(
      find.ancestor(of: _placeholder, matching: find.byType(Container)).first,
    );
    expect(box.color, AppColors.primary.withValues(alpha: 0.08));

    // Same colours as `PhotoImage` draws for a store without a photo.
    await tester.pumpWidget(
      _app(const PhotoImage(shape: PhotoShape.banner, url: null)),
    );
    final storeIcon = tester.widget<Icon>(find.byIcon(Icons.storefront_rounded));
    expect(storeIcon.color, icon.color);
    final storeTint = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byIcon(Icons.storefront_rounded),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(storeTint.color, box.color);
  });

  testWidgets('the tint also shows while loading and after a failure', (
    tester,
  ) async {
    final tint = AppColors.primary.withValues(alpha: 0.08);
    await _serving(status: 404, () async {
      await tester.pumpWidget(_app(const ProductImage(photo: _url)));
      await tester.pump();
      expect(
        tester
            .widget<Container>(
              find
                  .ancestor(of: _placeholder, matching: find.byType(Container))
                  .first,
            )
            .color,
        tint,
      );
      await _settle(tester);
      expect(
        tester
            .widget<Container>(
              find
                  .ancestor(of: _placeholder, matching: find.byType(Container))
                  .first,
            )
            .color,
        tint,
      );
    });
  });

  testWidgets('a valid remote image replaces the placeholder', (tester) async {
    await _serving(() async {
      await tester.pumpWidget(_app(const ProductImage(photo: _url)));
      await _settle(tester);

      expect(find.byType(Image), findsOneWidget);
      expect(_placeholder, findsNothing);
    });
  });

  testWidgets('shows the placeholder while the image loads', (tester) async {
    final gate = Completer<void>();
    await _serving(gate: gate, () async {
      await tester.pumpWidget(_app(const ProductImage(photo: _url)));
      await tester.pump();
      expect(_placeholder, findsOneWidget);

      gate.complete();
      await _settle(tester);
      expect(_placeholder, findsNothing);
    });
  });

  testWidgets('a failing image falls back to the placeholder', (tester) async {
    await _serving(status: 404, () async {
      await tester.pumpWidget(_app(const ProductImage(photo: _url)));
      await _settle(tester);

      expect(_placeholder, findsOneWidget);
    });
  });

  testWidgets('decodes at the size of the slot, in device pixels', (
    tester,
  ) async {
    await _serving(() async {
      await tester.pumpWidget(
        _app(const ProductImage(photo: _url, size: 56), dpr: 3),
      );
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(provider.width, 168);
      expect(provider.height, isNull);
    });
  });

  testWidgets('a different slot size gives a different decode size', (
    tester,
  ) async {
    await _serving(() async {
      await tester.pumpWidget(_app(const ProductImage(photo: _url, size: 180)));
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(provider.width, 180);
    });
  });
}
