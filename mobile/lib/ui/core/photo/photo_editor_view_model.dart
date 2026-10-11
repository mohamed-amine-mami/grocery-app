import 'package:flutter/foundation.dart';

import '../../../data/services/image_picker_service.dart';
import 'photo_failure.dart';

/// One photo being changed: picking, the preview (nothing is sent yet), saving
/// and removing. It knows nothing about users or stores — the two callbacks do
/// the actual request, and update whatever shows the photo, on success.
///
/// The persisted photo is untouched until a save succeeds: a failed save keeps
/// the picked image so the person can retry, and a failed removal keeps the
/// photo.
class PhotoEditorViewModel extends ChangeNotifier {
  PhotoEditorViewModel({
    required this._picker,
    required this._upload,
    required this._remove,
  });

  /// The backend refuses more than this.
  static const maxBytes = 5 * 1024 * 1024;

  final ImagePickerService _picker;
  final Future<void> Function(PickedImage image) _upload;
  final Future<void> Function() _remove;

  PickedImage? _pending;

  /// The image chosen and shown in the preview, not yet sent.
  PickedImage? get pending => _pending;

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  bool _isRemoving = false;
  bool get isRemoving => _isRemoving;

  bool get isBusy => _isUploading || _isRemoving || _isPicking;

  bool _isPicking = false;

  PhotoFailure? _failure;
  PhotoFailure? get failure => _failure;

  bool _disposed = false;

  /// Opens the camera or the library. `true` when an image is now waiting in
  /// the preview; `false` when the person cancelled or it failed (see
  /// [failure]).
  Future<bool> pick(PhotoSource source) async {
    if (isBusy) {
      return false;
    }
    _failure = null;
    _isPicking = true;
    notifyListeners();
    try {
      final image = await _picker.pick(source);
      if (image == null) {
        return false;
      }
      _pending = image;
      return true;
    } catch (error) {
      _failure = PhotoFailure.from(error);
      return false;
    } finally {
      _isPicking = false;
      notifyListeners();
    }
  }

  /// Sends the previewed image. A second call while one is running does
  /// nothing. `true` once the backend has it.
  Future<bool> save() async {
    final image = _pending;
    if (image == null || isBusy) {
      return false;
    }
    if (image.bytes.length > maxBytes) {
      _failure = PhotoFailure.tooLarge;
      notifyListeners();
      return false;
    }
    _failure = null;
    _isUploading = true;
    notifyListeners();
    try {
      await _upload(image);
      _pending = null;
      return true;
    } catch (error) {
      _failure = PhotoFailure.from(error);
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Drops the previewed image without sending it.
  void discard() {
    _pending = null;
    _failure = null;
    notifyListeners();
  }

  /// Removes the persisted photo. `true` once it is gone.
  Future<bool> remove() async {
    if (isBusy) {
      return false;
    }
    _failure = null;
    _isRemoving = true;
    notifyListeners();
    try {
      await _remove();
      return true;
    } catch (error) {
      _failure = PhotoFailure.from(error);
      return false;
    } finally {
      _isRemoving = false;
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    // A request can finish after its screen is gone.
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
