import '../../../data/services/api_client.dart';
import '../../../data/services/image_picker_service.dart';

enum PhotoFailureKind {
  network,
  invalidImage,
  tooLarge,
  sessionExpired,
  unavailable,
  notFound,
  permissionDenied,
  pickerUnavailable,
  unknown,
}

/// Why a photo operation failed, with the French message to show. The
/// backend's own text is English and technical and is never displayed: the
/// status picks the message.
class PhotoFailure {
  const PhotoFailure(this.kind, this.message);

  /// The photo is bigger than the backend accepts (checked before sending).
  static const tooLarge = PhotoFailure(
    PhotoFailureKind.tooLarge,
    'Cette photo est trop volumineuse (5 Mo maximum).',
  );

  factory PhotoFailure.from(Object error) {
    if (error is NetworkException) {
      return const PhotoFailure(
        PhotoFailureKind.network,
        'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
      );
    }
    if (error is ApiException) {
      return switch (error.statusCode) {
        400 => const PhotoFailure(
          PhotoFailureKind.invalidImage,
          'Cette image n’est pas valide. Utilisez une photo JPEG, PNG ou WebP.',
        ),
        401 => const PhotoFailure(
          PhotoFailureKind.sessionExpired,
          'Votre session a expiré. Veuillez vous reconnecter.',
        ),
        404 => const PhotoFailure(
          PhotoFailureKind.notFound,
          'Impossible de trouver votre compte ou votre magasin.',
        ),
        413 => tooLarge,
        503 => const PhotoFailure(
          PhotoFailureKind.unavailable,
          'Le service photo est momentanément indisponible. Réessayez plus tard.',
        ),
        _ => _unknown,
      };
    }
    if (error is ImagePickException) {
      return switch (error.failure) {
        ImagePickFailure.permissionDenied => const PhotoFailure(
          PhotoFailureKind.permissionDenied,
          'L’accès à l’appareil photo ou aux photos est refusé. Autorisez-le dans les réglages de votre téléphone.',
        ),
        ImagePickFailure.unavailable => const PhotoFailure(
          PhotoFailureKind.pickerUnavailable,
          'Impossible d’ouvrir l’appareil photo ou la galerie.',
        ),
      };
    }
    return _unknown;
  }

  static const _unknown = PhotoFailure(
    PhotoFailureKind.unknown,
    'Une erreur est survenue. Veuillez réessayer.',
  );

  final PhotoFailureKind kind;
  final String message;
}
