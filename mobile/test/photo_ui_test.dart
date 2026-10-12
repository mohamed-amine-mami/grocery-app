import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/data/models/store.dart';
import 'package:grocery_mobile/data/models/user.dart';
import 'package:grocery_mobile/data/services/api_client.dart';
import 'package:grocery_mobile/data/services/image_picker_service.dart';
import 'package:grocery_mobile/ui/core/photo/editable_photo.dart';

import 'fake_image_http.dart';
import 'fakes.dart';

const _photoA = 'https://res.example/users/2/profile-a.jpg';
const _storePhotoA = 'https://res.example/stores/10/photo-a.jpg';

/// The image provider under any resize wrapper (thumbnails are decoded at
/// their own size).
ImageProvider _unwrapped(ImageProvider provider) =>
    provider is ResizeImage ? _unwrapped(provider.imageProvider) : provider;

Finder _networkImage(String url) => find.byWidgetPredicate((widget) {
  if (widget is! Image) {
    return false;
  }
  final image = _unwrapped(widget.image);
  return image is NetworkImage && image.url == url;
});

/// The no-photo placeholder of the photo being edited (the tab bar uses the
/// same icons).
Finder get _avatarPlaceholder => find.descendant(
  of: find.byType(EditablePhoto),
  matching: find.byIcon(Icons.person_rounded),
);

Finder get _anyNetworkImage => find.byWidgetPredicate(
  (widget) => widget is Image && _unwrapped(widget.image) is NetworkImage,
);

/// Inside the open bottom sheet (the page behind may have the same words).
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

User _withPhoto(User user, String? photo) => User(
  id: user.id,
  name: user.name,
  email: user.email,
  phoneNumber: user.phoneNumber,
  role: user.role,
  photo: photo,
);

Store _storeWithPhoto(String? photo) => Store(
  id: closedStore.id,
  name: closedStore.name,
  address: closedStore.address,
  isOpen: false,
  ownerId: closedStore.ownerId,
  photo: photo,
);

class _Customer {
  _Customer(this.auth, this.picker);
  final FakeAuthRepository auth;
  final FakeImagePickerService picker;
}

Future<_Customer> _pumpCustomerProfile(
  WidgetTester tester, {
  String? photo,
}) async {
  late FakeAuthRepository auth;
  final picker = FakeImagePickerService();
  await pumpAppSignedInAs(
    tester,
    _withPhoto(testClient, photo),
    storeRepository: FakeStoreRepository.new,
    authRepository: (api) =>
        auth = FakeAuthRepository(api, _withPhoto(testClient, photo)),
    imagePickerService: picker,
  );
  await _openTab(tester, 'Profil');
  return _Customer(auth, picker);
}

class _Owner {
  _Owner(this.auth, this.store, this.picker);
  final FakeAuthRepository auth;
  final FakeStoreRepository store;
  final FakeImagePickerService picker;
}

Future<_Owner> _pumpOwner(
  WidgetTester tester, {
  String? userPhoto,
  String? storePhoto,
}) async {
  late FakeAuthRepository auth;
  late FakeStoreRepository store;
  final picker = FakeImagePickerService();
  await pumpAppSignedInAs(
    tester,
    _withPhoto(testOwner, userPhoto),
    storeRepository: (api) =>
        store = FakeStoreRepository(api, store: _storeWithPhoto(storePhoto)),
    authRepository: (api) =>
        auth = FakeAuthRepository(api, _withPhoto(testOwner, userPhoto)),
    imagePickerService: picker,
  );
  return _Owner(auth, store, picker);
}

Future<void> _tapPhoto(WidgetTester tester) async {
  await tester.tap(find.byType(EditablePhoto));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String option) async {
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(_inSheet(find.text('Enregistrer')));
  await tester.pumpAndSettle();
}

void main() {
  group('the photo bottom sheet', () {
    testWidgets('offers camera and gallery, and no removal without a photo', (
      tester,
    ) async {
      await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);

      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      expect(find.text('Supprimer la photo'), findsNothing);
    });

    testWidgets('also offers removal when there is a photo', (tester) async {
      await _pumpCustomerProfile(tester, photo: _photoA);
      await _tapPhoto(tester);

      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      expect(find.text('Supprimer la photo'), findsOneWidget);
    });

    testWidgets('closing it changes nothing and asks nothing', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();

      expect(find.text('Prendre une photo'), findsNothing);
      expect(customer.picker.calls, isEmpty);
    });
  });

  group('picking', () {
    testWidgets('camera opens the camera and shows the preview', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Prendre une photo');

      expect(customer.picker.calls, [PhotoSource.camera]);
      expect(find.text('Enregistrer'), findsOneWidget);
      expect(find.text('Choisir une autre'), findsOneWidget);
    });

    testWidgets('gallery opens the library and shows the preview', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');

      expect(customer.picker.calls, [PhotoSource.gallery]);
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('the preview sends nothing until Enregistrer', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');

      expect(customer.auth.setPhotoCalls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('closing the preview discards the picked image', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrer'), findsNothing);
      expect(customer.auth.setPhotoCalls, 0);
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      customer.picker.results.add(null);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');

      expect(find.text('Enregistrer'), findsNothing);
      expect(customer.auth.setPhotoCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Choisir une autre goes back to the choice, sending nothing', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await _choose(tester, 'Choisir une autre');

      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(customer.auth.setPhotoCalls, 0);

      await _choose(tester, 'Prendre une photo');
      expect(customer.picker.calls, [PhotoSource.gallery, PhotoSource.camera]);
      await _save(tester);
      expect(customer.auth.setPhotoCalls, 1);
    });

    testWidgets('a refused permission is explained', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      customer.picker.error = const ImagePickException(
        ImagePickFailure.permissionDenied,
      );
      await _tapPhoto(tester);
      await _choose(tester, 'Prendre une photo');

      expect(
        find.textContaining(
          'L’accès à l’appareil photo ou aux photos est refusé',
        ),
        findsOneWidget,
      );
      expect(find.text('Enregistrer'), findsNothing);
    });

    testWidgets('a photo over 5 MB is refused before sending', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      customer.picker.results.add(
        PickedImage(
          bytes: Uint8List(5 * 1024 * 1024 + 1),
          filename: 'big.jpg',
          contentType: 'image/jpeg',
        ),
      );
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await _save(tester);

      expect(
        find.text('Cette photo est trop volumineuse (5 Mo maximum).'),
        findsOneWidget,
      );
      expect(customer.auth.setPhotoCalls, 0);
    });
  });

  group('customer profile photo', () {
    testWidgets('shows the no-photo state, then the saved photo', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester);
      expect(_avatarPlaceholder, findsOneWidget);
      expect(_anyNetworkImage, findsNothing);

      await _tapPhoto(tester);
      await _choose(tester, 'Prendre une photo');
      await _save(tester);

      expect(customer.auth.lastUploaded!.filename, 'photo.png');
      expect(find.text('Photo enregistrée.'), findsOneWidget);
      expect(find.text('Enregistrer'), findsNothing); // the sheet closed
      expect(
        _networkImage('https://res.example/users/2/profile-1.jpg'),
        findsOneWidget,
      );
      // (The test network answers 400, so the image itself falls back to the
      // placeholder; what counts is that the photo is the new URL.)
    });

    testWidgets('shows the current photo, and a replacement takes its place', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      expect(_networkImage(_photoA), findsOneWidget);

      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await _save(tester);

      expect(customer.auth.setPhotoCalls, 1);
      expect(_networkImage(_photoA), findsNothing);
      expect(
        _networkImage('https://res.example/users/2/profile-1.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('while saving: a spinner over the preview, nothing else can be '
        'pressed, no second upload, and the old photo stays', (tester) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      final gate = Completer<void>();
      customer.auth.photoGate = gate;

      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await tester.tap(_inSheet(find.text('Enregistrer')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_inSheet(find.byType(CircularProgressIndicator)), findsWidgets);
      expect(customer.auth.setPhotoCalls, 1);
      // The button is replaced by its spinner and cannot start a second upload.
      expect(_inSheet(find.text('Enregistrer')), findsNothing);
      final another = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Choisir une autre'),
      );
      expect(another.onPressed, isNull);
      // The persisted photo is still the old one.
      expect(_networkImage(_photoA), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(customer.auth.setPhotoCalls, 1);
      expect(_networkImage(_photoA), findsNothing);
    });

    testWidgets('the sheet cannot be dismissed while saving', (tester) async {
      final customer = await _pumpCustomerProfile(tester);
      final gate = Completer<void>();
      customer.auth.photoGate = gate;
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await tester.tap(_inSheet(find.text('Enregistrer')));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    group('errors keep the preview and the old photo, so it can be retried', () {
      final cases = <String, (Object, String)>{
        'network': (
          const NetworkException('offline'),
          'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
        ),
        '400': (
          const ApiException(statusCode: 400, message: 'invalid'),
          'Cette image n’est pas valide. Utilisez une photo JPEG, PNG ou WebP.',
        ),
        '413': (
          const ApiException(statusCode: 413, message: 'too big'),
          'Cette photo est trop volumineuse (5 Mo maximum).',
        ),
        '503': (
          const ApiException(
            statusCode: 503,
            message: 'Image storage is not configured',
          ),
          'Le service photo est momentanément indisponible. Réessayez plus tard.',
        ),
      };
      for (final entry in cases.entries) {
        testWidgets('upload ${entry.key}', (tester) async {
          final customer = await _pumpCustomerProfile(tester, photo: _photoA);
          customer.auth.photoError = entry.value.$1;

          await _tapPhoto(tester);
          await _choose(tester, 'Choisir dans la galerie');
          await _save(tester);

          expect(find.text(entry.value.$2), findsOneWidget);
          expect(
            find.textContaining('Image storage'),
            findsNothing,
          ); // no technical detail
          expect(find.text('Enregistrer'), findsOneWidget); // still previewing
          expect(_networkImage(_photoA), findsOneWidget);

          // …and a retry works once the problem is gone.
          customer.auth.photoError = null;
          await _save(tester);
          expect(find.text('Photo enregistrée.'), findsOneWidget);
          expect(customer.auth.setPhotoCalls, 2);
        });
      }

      testWidgets('upload 401 signs the user out', (tester) async {
        final customer = await _pumpCustomerProfile(tester);
        customer.auth.photoError = const ApiException(statusCode: 401);
        await _tapPhoto(tester);
        await _choose(tester, 'Choisir dans la galerie');
        await _save(tester);

        expect(find.text('Connexion'), findsOneWidget);
      });
    });

    testWidgets('delete asks first, and Annuler keeps the photo', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');

      expect(find.text('Supprimer la photo ?'), findsOneWidget);
      expect(
        find.text('Votre photo de profil sera supprimée.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(customer.auth.removePhotoCalls, 0);
      expect(_networkImage(_photoA), findsOneWidget);
    });

    testWidgets('confirming deletes, and the no-photo state shows at once', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(customer.auth.removePhotoCalls, 1);
      expect(find.text('Photo supprimée.'), findsOneWidget);
      expect(_anyNetworkImage, findsNothing);
      expect(_avatarPlaceholder, findsOneWidget);

      // Nothing left to remove.
      await _tapPhoto(tester);
      expect(find.text('Supprimer la photo'), findsNothing);
    });

    testWidgets('a failed delete keeps the photo and says why', (tester) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      customer.auth.photoError = const NetworkException('offline');
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      expect(_networkImage(_photoA), findsOneWidget);
    });

    testWidgets('a 503 on delete that did clear the photo counts as deleted', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      customer.auth
        ..photoError = const ApiException(statusCode: 503)
        ..removeClearsDespiteError = true;
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(find.text('Photo supprimée.'), findsOneWidget);
      expect(_anyNetworkImage, findsNothing);
    });

    testWidgets('while deleting: a spinner over the photo and no second tap', (
      tester,
    ) async {
      final customer = await _pumpCustomerProfile(tester, photo: _photoA);
      final gate = Completer<void>();
      customer.auth.photoGate = gate;
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      await tester.tap(find.text('Supprimer'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byType(EditablePhoto),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(EditablePhoto), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Prendre une photo'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('owner avatar (Accueil)', () {
    testWidgets('has the same editor, and the new photo shows next to the '
        'greeting', (tester) async {
      final owner = await _pumpOwner(tester);
      expect(find.text('Bonjour, Karim'), findsOneWidget);
      expect(_avatarPlaceholder, findsOneWidget);

      await _tapPhoto(tester);
      expect(find.text('Prendre une photo'), findsOneWidget);
      await _choose(tester, 'Prendre une photo');
      expect(owner.picker.calls, [PhotoSource.camera]);
      await _save(tester);

      expect(owner.auth.setPhotoCalls, 1);
      expect(
        _networkImage('https://res.example/users/1/profile-1.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('removal asks for confirmation', (tester) async {
      final owner = await _pumpOwner(
        tester,
        userPhoto: 'https://res.example/users/1/profile-a.jpg',
      );
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      expect(find.text('Supprimer la photo ?'), findsOneWidget);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(owner.auth.removePhotoCalls, 1);
      expect(_avatarPlaceholder, findsOneWidget);
    });
  });

  group('store photo (Magasin)', () {
    Future<_Owner> pump(WidgetTester tester, {String? photo}) async {
      final owner = await _pumpOwner(tester, storePhoto: photo);
      await _openTab(tester, 'Magasin');
      return owner;
    }

    testWidgets('shows the no-photo state, then offers camera and gallery', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.descendant(
          of: find.byType(EditablePhoto),
          matching: find.byIcon(Icons.storefront_rounded),
        ),
        findsOneWidget,
      );
      await _tapPhoto(tester);

      expect(find.text('Photo du magasin'), findsOneWidget);
      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      expect(find.text('Supprimer la photo'), findsNothing);
    });

    testWidgets('the preview is 16:9 and sends nothing until Enregistrer', (
      tester,
    ) async {
      final owner = await pump(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');

      expect(owner.picker.calls, [PhotoSource.gallery]);
      expect(
        tester
            .widget<AspectRatio>(_inSheet(find.byType(AspectRatio)))
            .aspectRatio,
        16 / 9,
      );
      expect(owner.store.setPhotoCalls, 0);
      expect(_inSheet(find.text('Choisir une autre')), findsOneWidget);
    });

    testWidgets('Choisir une autre returns to the choice', (tester) async {
      final owner = await pump(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Prendre une photo');
      await _choose(tester, 'Choisir une autre');

      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      expect(owner.store.setPhotoCalls, 0);
    });

    testWidgets('saving shows the new store photo', (tester) async {
      final owner = await pump(tester);
      await _tapPhoto(tester);
      await _choose(tester, 'Prendre une photo');
      await _save(tester);

      expect(owner.store.setPhotoCalls, 1);
      expect(find.text('Photo enregistrée.'), findsOneWidget);
      expect(
        _networkImage('https://res.example/stores/10/photo-1.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('a replacement takes the place of the old photo', (
      tester,
    ) async {
      final owner = await pump(tester, photo: _storePhotoA);
      expect(_networkImage(_storePhotoA), findsOneWidget);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await _save(tester);

      expect(owner.store.setPhotoCalls, 1);
      expect(_networkImage(_storePhotoA), findsNothing);
      expect(
        _networkImage('https://res.example/stores/10/photo-1.jpg'),
        findsOneWidget,
      );
    });

    testWidgets('delete asks first and then shows the no-photo state', (
      tester,
    ) async {
      final owner = await pump(tester, photo: _storePhotoA);
      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      expect(find.text('La photo du magasin sera supprimée.'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(owner.store.removePhotoCalls, 0);

      await _tapPhoto(tester);
      await _choose(tester, 'Supprimer la photo');
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(owner.store.removePhotoCalls, 1);
      expect(_anyNetworkImage, findsNothing);
      expect(
        find.descendant(
          of: find.byType(EditablePhoto),
          matching: find.byIcon(Icons.storefront_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable photo service is explained, in French', (
      tester,
    ) async {
      final owner = await pump(tester, photo: _storePhotoA);
      owner.store.photoError = const ApiException(statusCode: 503);
      await _tapPhoto(tester);
      await _choose(tester, 'Choisir dans la galerie');
      await _save(tester);

      expect(
        find.text(
          'Le service photo est momentanément indisponible. Réessayez plus tard.',
        ),
        findsOneWidget,
      );
      expect(_networkImage(_storePhotoA), findsOneWidget);
    });

    testWidgets('the details form no longer has a photo link', (tester) async {
      await pump(tester);
      expect(
        find.widgetWithText(TextFormField, 'Photo du magasin'),
        findsNothing,
      );
      expect(find.textContaining('Lien de la photo'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'Nom du magasin'),
        findsOneWidget,
      );
    });
  });

  group('store creation', () {
    testWidgets('has no photo link, and says the photo comes later', (
      tester,
    ) async {
      await pumpAppSignedInAs(
        tester,
        testOwner,
        storeRepository: (api) => FakeStoreRepository(api),
      );
      expect(find.text('Créer mon magasin'), findsWidgets);
      expect(find.textContaining('Lien de la photo'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'Photo du magasin'),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Vous pourrez ajouter une photo'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Vous pourrez ajouter une photo'),
        findsOneWidget,
      );
    });
  });

  group('customer store card', () {
    Future<void> pumpStores(WidgetTester tester, List<dynamic> stores) async {
      // Tall enough for every card: the list builds only what is near.
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = ApiClient();
      final repository = FakeCustomerStoresRepository(
        api,
        stores: [for (final s in stores) s],
      );
      await pumpAppSignedInAs(
        tester,
        testClient,
        storeRepository: FakeStoreRepository.new,
        customerStoresRepository: (_) => repository,
      );
    }

    testWidgets('shows the remote photo when the store has one', (
      tester,
    ) async {
      // Left loading: the strip is there as soon as there is a photo.
      await servingImageErrors(hang: true, () async {
        await pumpStores(tester, [
          fakeCustomerStore(
            id: 10,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/10/photo-a.jpg',
          ),
        ]);

        expect(find.text('Chez Sami'), findsOneWidget);
        expect(
          _networkImage('https://res.example/stores/10/photo-a.jpg'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a store with no photo is not fetched, and has a face', (
      tester,
    ) async {
      await pumpStores(tester, [fakeCustomerStore(id: 10, name: 'Chez Sami')]);

      expect(find.text('Chez Sami'), findsOneWidget);
      expect(_anyNetworkImage, findsNothing);
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.byIcon(Icons.storefront_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('only the stores with a photo fetch one', (tester) async {
      await servingImageErrors(hang: true, () async {
        await pumpStores(tester, [
          fakeCustomerStore(
            id: 10,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/10/photo-a.jpg',
          ),
          fakeCustomerStore(id: 20, name: 'Chez Leïla'),
        ]);

        expect(_anyNetworkImage, findsOneWidget);
      });
    });

    testWidgets('a photo that fails to load leaves the face, not a blank', (
      tester,
    ) async {
      await servingImageErrors(() async {
        await pumpStores(tester, [
          fakeCustomerStore(
            id: 10,
            name: 'Chez Sami',
            photo: 'https://res.example/stores/10/photo-a.jpg',
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('Chez Sami'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Card),
            matching: find.byIcon(Icons.storefront_rounded),
          ),
          findsOneWidget,
        );
      });
    });
  });
}
