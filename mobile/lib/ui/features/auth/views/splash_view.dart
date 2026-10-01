import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';
import 'login_view.dart';

/// The branded splash. Shows only the GrocerGo logo and name, holds for a
/// short, fixed duration, then fades automatically into [LoginView] — no
/// button, no interaction required.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  static const _holdDuration = Duration(milliseconds: 1400);
  static const _transitionDuration = Duration(milliseconds: 400);

  Timer? _advanceTimer;
  bool _brandVisible = false;

  @override
  void initState() {
    super.initState();
    // Defer to the next frame so the entrance fade is visible rather than
    // starting already-opaque.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _brandVisible = true);
      }
    });
    _advanceTimer = Timer(_holdDuration, _goToLogin);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _goToLogin() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: _transitionDuration,
        pageBuilder: (_, _, _) => const LoginView(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedOpacity(
          opacity: _brandVisible ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: const BrandMark(),
        ),
      ),
    );
  }
}
