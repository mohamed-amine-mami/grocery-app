import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// Where a photo comes from.
enum PhotoSource { camera, gallery }

/// A photo the user picked, held in memory and ready to be uploaded.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// Why a photo could not be picked (cancelling is not a failure: it is `null`).
enum ImagePickFailure {
  /// The user refused camera or photo-library access.
  permissionDenied,

  /// No camera, or the picker could not open.
  unavailable,
}

class ImagePickException implements Exception {
  const ImagePickException(this.failure);

  final ImagePickFailure failure;

  @override
  String toString() => 'ImagePickException($failure)';
}

/// Lets the user choose a photo. It only picks: no network, no upload, and no
/// knowledge of where the photo ends up.
abstract class ImagePickerService {
  /// The chosen photo, or `null` when the user cancelled.
  Future<PickedImage?> pick(PhotoSource source);
}

/// The device's camera and photo library, through `image_picker`. The photo is
/// scaled down and recompressed on the device, so uploads stay small.
class DeviceImagePickerService implements ImagePickerService {
  const DeviceImagePickerService({this._picker});

  static const maxDimension = 1600.0;
  static const quality = 85;

  final ImagePicker? _picker;

  @override
  Future<PickedImage?> pick(PhotoSource source) async {
    final XFile? file;
    try {
      file = await (_picker ?? ImagePicker()).pickImage(
        source: switch (source) {
          PhotoSource.camera => ImageSource.camera,
          PhotoSource.gallery => ImageSource.gallery,
        },
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: quality,
      );
    } on PlatformException catch (error) {
      throw ImagePickException(
        error.code.endsWith('access_denied')
            ? ImagePickFailure.permissionDenied
            : ImagePickFailure.unavailable,
      );
    }
    if (file == null) {
      return null;
    }
    return PickedImage(
      bytes: await file.readAsBytes(),
      filename: file.name.isEmpty ? 'photo.jpg' : file.name,
      contentType: file.mimeType ?? _contentTypeOf(file.name),
    );
  }

  static String _contentTypeOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return switch (dot < 0 ? '' : filename.substring(dot + 1).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}
