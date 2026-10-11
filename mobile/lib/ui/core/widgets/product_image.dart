import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A catalog product's image, or a neutral placeholder when there is none, while
/// it loads, or when it cannot be loaded. Display only: the image belongs to the
/// global catalog.
///
/// The picture is decoded at the size of its slot (in device pixels), not at
/// its source resolution: a 56 px thumbnail never holds a 1000 px bitmap.
class ProductImage extends StatelessWidget {
  const ProductImage({
    required this.photo,
    this.size = 64,
    this.fit = BoxFit.cover,
    this.tile = false,
    this.quiet = false,
    super.key,
  });

  final String? photo;
  final double size;

  /// `cover` fills the frame (cropping); `contain` shows the whole picture.
  final BoxFit fit;

  /// Paints the placeholder's tint behind the whole square, so a picture that
  /// does not fill it (`contain`) sits on the same tile as the placeholder.
  final bool tile;

  /// A smaller, lower-contrast placeholder icon, for a slot that holds no
  /// photo (a row without a picture is a quieter thing than one with it).
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.primary.withValues(alpha: 0.08);
    final placeholder = Container(
      width: size,
      height: size,
      // The same tint and icon tone as the store photo's placeholder
      // (`PhotoImage`): a missing photo looks intended, not like a hole.
      color: tile ? null : tint,
      child: Icon(
        Icons.shopping_basket_rounded,
        size: quiet ? 20 : null,
        color: AppColors.primary.withValues(alpha: quiet ? 0.4 : 0.6),
      ),
    );
    final decodeWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 4096);
    final picture = photo == null
        ? placeholder
        : Image.network(
            photo!,
            width: size,
            height: size,
            fit: fit,
            cacheWidth: decodeWidth,
            // Until the first frame is decoded the neutral placeholder
            // holds the space: no spinner, nothing animated.
            frameBuilder: (_, child, frame, loadedSynchronously) =>
                frame == null && !loadedSynchronously ? placeholder : child,
            errorBuilder: (_, _, _) => placeholder,
          );
    return Semantics(
      label: 'Image du produit',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.input),
        child: tile
            ? ColoredBox(
                color: tint,
                child: SizedBox.square(
                  dimension: size,
                  child: Center(child: picture),
                ),
              )
            : picture,
      ),
    );
  }
}
