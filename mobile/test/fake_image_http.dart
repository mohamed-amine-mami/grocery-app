import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';

/// Runs [body] with every network image request answered by [status] (an
/// error), or — with [hang] — never answered: no real network, and an image
/// that stays loading. `NetworkImage` keeps one shared HTTP client for the
/// whole run, so this goes through its test hook rather than `HttpOverrides`.
Future<void> servingImageErrors(
  Future<void> Function() body, {
  int status = 404,
  bool hang = false,
}) async {
  // An earlier test's load of the same URL must not be answered from here.
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  debugNetworkImageHttpClientProvider = () => _Client(status, hang);
  try {
    await body();
  } finally {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // Before the binding checks that no painting debug variable is left set.
    debugNetworkImageHttpClientProvider = null;
  }
}

class _Client implements HttpClient {
  _Client(this.status, this.hang);

  final int status;
  final bool hang;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(status, hang);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.status, this.hang);

  final int status;
  final bool hang;

  @override
  final headers = _Headers();

  @override
  Future<HttpClientResponse> close() {
    if (hang) {
      return Completer<HttpClientResponse>().future;
    }
    return Future.value(_Response(status));
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
  int get contentLength => 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
