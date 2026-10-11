import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How a photo is framed: a round avatar, or a 16:9 banner (a store).
enum PhotoShape { avatar, banner }

/// A remote photo in its frame, or the neutral no-photo state when there is no
/// URL (or it cannot be loaded). Display only.
class PhotoImage extends StatelessWidget {
  const PhotoImage({
    required this.shape,
    required this.url,
    this.size = 96,
    super.key,
  });

  final PhotoShape shape;
  final String? url;

  /// The avatar's diameter. A banner takes the width it is given.
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(shape: shape, size: size);
    final image = url == null
        ? placeholder
        : Image.network(
            url!,
            fit: BoxFit.cover,
            width: shape == PhotoShape.avatar ? size : double.infinity,
            height: shape == PhotoShape.avatar ? size : double.infinity,
            errorBuilder: (_, _, _) => placeholder,
          );
    return switch (shape) {
      PhotoShape.avatar => SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: image),
      ),
      PhotoShape.banner => AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: image,
        ),
      ),
    };
  }
}

/// The picked image itself, in the same frame as [PhotoImage], for the preview.
class PhotoPreviewImage extends StatelessWidget {
  const PhotoPreviewImage({
    required this.shape,
    required this.bytes,
    this.size = 160,
    super.key,
  });

  final PhotoShape shape;
  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: shape == PhotoShape.avatar ? size : double.infinity,
      height: shape == PhotoShape.avatar ? size : double.infinity,
      errorBuilder: (_, _, _) => _Placeholder(shape: shape, size: size),
    );
    return switch (shape) {
      PhotoShape.avatar => SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: image),
      ),
      PhotoShape.banner => AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: image,
        ),
      ),
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.shape, required this.size});

  final PhotoShape shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          shape == PhotoShape.avatar
              ? Icons.person_rounded
              : Icons.storefront_rounded,
          size: shape == PhotoShape.avatar ? size * 0.5 : 48,
          color: AppColors.primary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
