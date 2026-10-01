import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The GrocerGo icon + wordmark, reused on the splash and the
/// authentication page.
///
/// The icon is the brand asset exactly as supplied (`assets/brand/
/// grocergo_icon.png`) — it is never redrawn or recolored. The "GrocerGo"
/// wordmark is rendered as text rather than image: the supplied wordmark
/// artwork was only available at a resolution too low to scale without
/// blurring, so it's set here in the app's own Inter typeface instead.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.iconSize = 132,
    this.nameStyle,
    this.spacing = AppSpacing.lg,
  });

  final double iconSize;
  final TextStyle? nameStyle;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/grocergo_icon.png',
          width: iconSize,
          height: iconSize,
        ),
        SizedBox(height: spacing),
        Text(
          'GrocerGo',
          style:
              nameStyle ??
              Theme.of(context).textTheme.displaySmall
                  ?.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}
