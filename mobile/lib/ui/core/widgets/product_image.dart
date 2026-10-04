import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A catalog product's image, or a neutral placeholder when there is none (or
/// it cannot be loaded). Display only: the image belongs to the global catalog.
class ProductImage extends StatelessWidget {
  const ProductImage({required this.photo, this.size = 64, super.key});

  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.background,
      child: const Icon(
        Icons.shopping_basket_rounded,
        color: AppColors.textSecondary,
      ),
    );
    return Semantics(
      label: 'Image du produit',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.input),
        child: photo == null
            ? placeholder
            : Image.network(
                photo!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
