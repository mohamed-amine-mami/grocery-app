import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../core/theme/app_theme.dart';
import '../order_labels.dart';

/// An order's status as icon + text (never color alone). "Non récupérée" and
/// "Annulée" are calm, neutral states, not alarms.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({required this.status, this.label, super.key});

  final OrderStatus status;

  /// The text to show; the owner's wording by default.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      OrderStatus.pending => (Icons.hourglass_top_rounded, AppColors.warning),
      OrderStatus.confirmed => (
        Icons.check_circle_outline_rounded,
        AppColors.primary,
      ),
      OrderStatus.readyForPickup => (
        Icons.shopping_bag_rounded,
        AppColors.success,
      ),
      OrderStatus.completed => (
        Icons.task_alt_rounded,
        AppColors.textSecondary,
      ),
      OrderStatus.cancelled => (Icons.cancel_rounded, AppColors.textSecondary),
      OrderStatus.noShow => (Icons.person_off_rounded, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label ?? OrderLabels.status(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
