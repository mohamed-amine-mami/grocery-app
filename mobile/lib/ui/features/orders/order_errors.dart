import '../../../data/services/api_client.dart';

enum OrderFailureKind {
  /// 409 `ORDER_STATE_CHANGED`: someone (the customer, another device) moved
  /// the order first. The order must be reloaded, not retried blindly.
  stateChanged,

  /// 409 `STOCK_CHANGED`: stock information changed under the screen.
  stockChanged,

  /// 400: the backend refused the request as invalid.
  invalid,

  /// The backend could not be reached.
  network,

  /// 401: the session is no longer valid.
  sessionExpired,

  /// 403.
  forbidden,

  /// 404: the order is no longer available to this store.
  notFound,

  /// Anything else.
  unknown,
}

/// A failed request, ready to show: [kind] drives what the screen does and
/// [message] is the French text. Backend messages are English by convention,
/// so they are never shown; the stable `code` and the status decide.
class OrderFailure {
  const OrderFailure(this.kind, this.message);

  factory OrderFailure.from(Object error) {
    if (error is NetworkException) {
      return const OrderFailure(
        OrderFailureKind.network,
        'Impossible de contacter le serveur. Vérifiez votre connexion et réessayez.',
      );
    }
    if (error is ApiException) {
      if (error.statusCode == 409 && error.code == 'ORDER_STATE_CHANGED') {
        return const OrderFailure(
          OrderFailureKind.stateChanged,
          'La commande a changé d’état. Actualisez les informations.',
        );
      }
      if (error.statusCode == 409 && error.code == 'STOCK_CHANGED') {
        return const OrderFailure(
          OrderFailureKind.stockChanged,
          'Le stock a changé. Vérifiez à nouveau la commande avant de continuer.',
        );
      }
      return switch (error.statusCode) {
        400 => const OrderFailure(
          OrderFailureKind.invalid,
          'Cette demande n’est pas valide. Vérifiez la commande et réessayez.',
        ),
        401 => const OrderFailure(
          OrderFailureKind.sessionExpired,
          'Votre session a expiré. Reconnectez-vous.',
        ),
        403 => const OrderFailure(
          OrderFailureKind.forbidden,
          'Vous n’avez pas accès à cette commande.',
        ),
        404 => const OrderFailure(
          OrderFailureKind.notFound,
          'Cette commande n’est plus disponible.',
        ),
        _ => _unknown,
      };
    }
    return _unknown;
  }

  static const _unknown = OrderFailure(
    OrderFailureKind.unknown,
    'Une erreur est survenue. Veuillez réessayer.',
  );

  final OrderFailureKind kind;
  final String message;
}
