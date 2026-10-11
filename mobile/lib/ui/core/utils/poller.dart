import 'dart:async';

/// One periodic refresh: a single timer, and a tick that finds the previous
/// one still running is skipped, so requests never overlap.
class Poller {
  Poller({required this.interval, required this.onTick});

  final Duration interval;
  final Future<void> Function() onTick;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  bool get isActive => _timer != null;

  /// Starts the timer. Safe to call repeatedly: there is never a second one.
  void start() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    try {
      await onTick();
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
