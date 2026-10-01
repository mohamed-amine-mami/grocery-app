/// Client-side form validation. All messages are French — this is
/// user-facing content per the project's language rule.
/// Text bounds — the same ones the backend enforces.
abstract final class AppLimits {
  static const name = 100;
  static const address = 200;
  static const description = 1000;
  static const url = 2048;
}

abstract final class AppValidators {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^\+?[0-9]{8,15}$');

  static String? required(
    String? value, {
    String message = 'Ce champ est requis.',
  }) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  static String? name(String? value) =>
      required(value, message: 'Le nom est requis.');

  static String? email(String? value) {
    final requiredError = required(
      value,
      message: "L'adresse e-mail est requise.",
    );
    if (requiredError != null) {
      return requiredError;
    }
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Adresse e-mail invalide.';
    }
    return null;
  }

  static String? phoneNumber(String? value) {
    final requiredError = required(
      value,
      message: 'Le numéro de téléphone est requis.',
    );
    if (requiredError != null) {
      return requiredError;
    }
    final digits = value!.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (!_phonePattern.hasMatch(digits)) {
      return 'Numéro de téléphone invalide.';
    }
    return null;
  }

  /// WhatsApp number is optional, but must look like a phone number if given.
  static String? optionalPhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final digits = value.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (!_phonePattern.hasMatch(digits)) {
      return 'Numéro invalide.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = required(
      value,
      message: 'Le mot de passe est requis.',
    );
    if (requiredError != null) {
      return requiredError;
    }
    if (value!.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères.';
    }
    return null;
  }

  static String? storeName(String? value) =>
      required(value, message: 'Le nom du magasin est requis.');

  static const categoryNameMaxLength = 50;

  static String? categoryName(String? value) {
    final requiredError = required(
      value,
      message: 'Le nom de la catégorie est requis.',
    );
    if (requiredError != null) {
      return requiredError;
    }
    if (value!.trim().length > categoryNameMaxLength) {
      return 'Le nom ne doit pas dépasser $categoryNameMaxLength caractères.';
    }
    return null;
  }

  /// Optional photo link: empty is fine; otherwise an http(s) URL.
  static String? optionalPhotoUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(text);
    final isHttp =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return isHttp
        ? null
        : 'Lien invalide (il doit commencer par http:// ou https://).';
  }

  static String? storeAddress(String? value) =>
      required(value, message: "L'adresse du magasin est requise.");

  /// The backend stores latitude and longitude together or not at all, so
  /// filling one field makes the other mandatory.
  static String? coordinatePair(
    String? value,
    String? otherValue, {
    required String message,
  }) {
    final isEmpty = value == null || value.trim().isEmpty;
    final otherIsFilled = otherValue != null && otherValue.trim().isNotEmpty;
    return isEmpty && otherIsFilled ? message : null;
  }

  static String? optionalLatitude(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < -90 || parsed > 90) {
      return 'Latitude invalide (-90 à 90).';
    }
    return null;
  }

  static String? optionalLongitude(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < -180 || parsed > 180) {
      return 'Longitude invalide (-180 à 180).';
    }
    return null;
  }
}
