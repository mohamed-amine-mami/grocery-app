import 'package:flutter/material.dart';

/// The app's primary call-to-action button — full-width, 48px minimum height
/// per `docs/design.md`, with a built-in loading state.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Text shown at the end of the button (an amount), beside [label]. The
  /// label gives way to it — the amount moves under the label — at large text.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : trailing == null
          ? Text(label)
          : MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3
          // Large text: the amount goes under the label, so that a word of the
          // label is never broken to make room for it.
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, textAlign: TextAlign.center),
                Text(trailing!),
              ],
            )
          : Row(
              children: [
                Expanded(child: Text(label, maxLines: 2)),
                const SizedBox(width: 12),
                Text(trailing!),
              ],
            ),
    );
  }
}
