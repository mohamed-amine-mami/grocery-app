import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:grocery_mobile/data/services/image_picker_service.dart';

/// Stands in for the plugin: records how it was called, answers as told.
class _FakePicker extends ImagePicker {
  _FakePicker({this.result, this.error});

  XFile? result;
  Object? error;

  ImageSource? source;
  double? maxWidth;
  double? maxHeight;
  int? imageQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

/// A real file under a temp directory: `XFile.fromData` forgets its name.
XFile _file(String name, {String? mimeType}) {
  final directory = Directory.systemTemp.createTempSync('picker_test');
  addTearDown(() => directory.deleteSync(recursive: true));
  final file = File('${directory.path}/$name')..writeAsBytesSync([1, 2, 3]);
  return XFile(file.path, mimeType: mimeType);
}

void main() {
  group('DeviceImagePickerService', () {
    test('picks from the camera, scaled to 1600 px at quality 85', () async {
      final picker = _FakePicker(
        result: _file('shot.jpg', mimeType: 'image/jpeg'),
      );
      final image = await DeviceImagePickerService(picker: picker)
          .pick(PhotoSource.camera);

      expect(picker.source, ImageSource.camera);
      expect(picker.maxWidth, 1600);
      expect(picker.maxHeight, 1600);
      expect(picker.imageQuality, 85);
      expect(image!.bytes, [1, 2, 3]);
      expect(image.filename, 'shot.jpg');
      expect(image.contentType, 'image/jpeg');
    });

    test('picks from the gallery with the same settings', () async {
      final picker = _FakePicker(
        result: _file('library.png', mimeType: 'image/png'),
      );
      final image = await DeviceImagePickerService(picker: picker)
          .pick(PhotoSource.gallery);

      expect(picker.source, ImageSource.gallery);
      expect(picker.maxWidth, 1600);
      expect(picker.maxHeight, 1600);
      expect(picker.imageQuality, 85);
      expect(image!.contentType, 'image/png');
    });

    test('answers null when the user cancels', () async {
      for (final source in PhotoSource.values) {
        final picker = _FakePicker();
        expect(
          await DeviceImagePickerService(picker: picker).pick(source),
          isNull,
        );
      }
    });

    test(
      'finds the content type from the extension when the plugin gives none',
      () async {
        Future<String> typeOf(String name) async {
          final picker = _FakePicker(result: _file(name));
          return (await DeviceImagePickerService(picker: picker)
                  .pick(PhotoSource.gallery))!
              .contentType;
        }

        expect(await typeOf('a.JPG'), 'image/jpeg');
        expect(await typeOf('a.jpeg'), 'image/jpeg');
        expect(await typeOf('a.png'), 'image/png');
        expect(await typeOf('a.webp'), 'image/webp');
        expect(await typeOf('a.heic'), 'application/octet-stream');
        expect(await typeOf('noextension'), 'application/octet-stream');
      },
    );

    test('names a photo that has no name', () async {
      final picker = _FakePicker(
        result: XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/jpeg',
        ),
      );
      final image = await DeviceImagePickerService(picker: picker)
          .pick(PhotoSource.gallery);
      expect(image!.filename, 'photo.jpg');
    });

    test('reports a refused permission', () async {
      for (final code in ['camera_access_denied', 'photo_access_denied']) {
        final picker = _FakePicker(error: PlatformException(code: code));
        await expectLater(
          DeviceImagePickerService(picker: picker).pick(PhotoSource.camera),
          throwsA(
            isA<ImagePickException>().having(
              (e) => e.failure,
              'failure',
              ImagePickFailure.permissionDenied,
            ),
          ),
        );
      }
    });

    test('reports any other platform failure as unavailable', () async {
      final picker = _FakePicker(
        error: PlatformException(code: 'no_available_camera'),
      );
      await expectLater(
        DeviceImagePickerService(picker: picker).pick(PhotoSource.camera),
        throwsA(
          isA<ImagePickException>().having(
            (e) => e.failure,
            'failure',
            ImagePickFailure.unavailable,
          ),
        ),
      );
    });
  });
}
