import 'package:flutter/widgets.dart';

/// Decides when a screen's polling may run: only while the screen is the
/// visible one, the app is in the foreground, and nothing covers it. Owned by
/// a `State`; it calls [onRun] / [onPause] as that changes, and [onResume]
/// (a refresh) whenever the screen becomes live again after being away.
class PollingGuard with WidgetsBindingObserver {
  PollingGuard({
    required this.onRun,
    required this.onPause,
    required this.onResume,
    this._visible = true,
  });

  final VoidCallback onRun;
  final VoidCallback onPause;
  final VoidCallback onResume;

  bool _visible;
  bool _foreground = true;
  bool _covered = false;
  bool _live = false;

  bool get isLive => _live;

  void attach() {
    WidgetsBinding.instance.addObserver(this);
    _sync(refresh: false);
  }

  set visible(bool value) {
    if (value != _visible) {
      _visible = value;
      _sync(refresh: true);
    }
  }

  /// A screen is pushed over this one (or removed again).
  set covered(bool value) {
    if (value != _covered) {
      _covered = value;
      _sync(refresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground) {
      _foreground = foreground;
      _sync(refresh: true);
    }
  }

  void _sync({required bool refresh}) {
    final shouldBeLive = _visible && _foreground && !_covered;
    if (shouldBeLive == _live) {
      return;
    }
    _live = shouldBeLive;
    if (shouldBeLive) {
      if (refresh) {
        onResume();
      }
      onRun();
    } else {
      onPause();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_live) {
      _live = false;
      onPause();
    }
  }
}
