import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A short explanation next to a form field (what the backend will do with
/// what was typed). Icon and text, never color alone.
class AppInfoNote extends StatelessWidget {
  const AppInfoNote({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.warning,
            ),
          ),
        ),
      ],
    );
  }
}
