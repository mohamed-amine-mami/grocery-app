import 'package:flutter/material.dart';

import '../../../../data/models/sale_unit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';

/// `− quantité +` for a cart line. The caller only ever moves by the product's
/// own step; at the minimum the minus becomes a trash icon, because one step
/// less would be below the minimum: the line is removed instead.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.atMinimum,
    required this.canIncrement,
    required this.onIncrement,
    required this.onDecrement,
    this.compact = false,
    super.key,
  });

  final String productName;
  final SaleUnit unit;
  final int quantity;
  final bool atMinimum;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Fills the width it is given (a product card) instead of hugging its
  /// content: the quantity shrinks to fit between two 44 px buttons.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // 44 px buttons, in the catalogue and in the cart alike.
    const buttonSize = BoxConstraints.tightFor(width: 44, height: 44);
    final quantityText = Text(
      ProductFormat.quantity(unit, quantity),
      textAlign: TextAlign.center,
      style: textTheme.bodyMedium,
    );
    return Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: [
        IconButton(
          tooltip: atMinimum
              ? 'Retirer $productName du panier'
              : 'Diminuer la quantité de $productName',
          constraints: buttonSize,
          onPressed: onDecrement,
          icon: Icon(
            atMinimum ? Icons.delete_outline_rounded : Icons.remove_rounded,
            color: atMinimum ? AppColors.error : AppColors.primary,
          ),
        ),
        if (compact)
          Expanded(
            child: FittedBox(fit: BoxFit.scaleDown, child: quantityText),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: quantityText,
          ),
        IconButton(
          tooltip: canIncrement
              ? 'Augmenter la quantité de $productName'
              : 'Quantité maximale atteinte pour $productName',
          constraints: buttonSize,
          onPressed: canIncrement ? onIncrement : null,
          icon: const Icon(Icons.add_rounded),
          color: AppColors.primary,
        ),
      ],
    );
  }
}
