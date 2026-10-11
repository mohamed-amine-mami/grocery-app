import '../../../../data/services/api_client.dart';
import '../../orders/order_errors.dart';

enum CheckoutFailureKind {
  storeClosed,
  productUnavailable,
  insufficientStock,
  invalidQuantity,
  invalidPickupTime,

  /// 409 `IDEMPOTENCY_KEY_REUSED`: not a retry, a conflict.
  keyReused,

  /// The backend could not be reached: the attempt (and its key) is kept so
  /// the same request can be retried.
  network,
  sessionExpired,

  /// 404: the store or a product is gone.
  notFound,
  invalid,
  unknown,
}

/// A failed order submission, ready to show. Backend text is English and is
/// never shown: the status and the stable `code` pick the French message.
class CheckoutFailure {
  const CheckoutFailure(this.kind, this.message, {this.productIds = const []});

  /// The store is closed (known here, or said by the backend).
  static const storeClosed = CheckoutFailure(
    CheckoutFailureKind.storeClosed,
    'Ce magasin est fermé pour le moment : la commande ne peut pas être envoyée.',
  );

  /// The chosen pickup time is no longer possible.
  static const invalidPickupTime = CheckoutFailure(
    CheckoutFailureKind.invalidPickupTime,
    'L’heure de retrait choisie n’est plus possible. Choisissez un autre horaire.',
  );

  factory CheckoutFailure.from(Object error) {
    if (error is NetworkException) {
      return CheckoutFailure(
        CheckoutFailureKind.network,
        OrderFailure.from(error).message,
      );
    }
    if (error is ApiException) {
      final body = error.body ?? const {};
      final lines = body['lines'];
      final ids = <int>[
        if (body['storeProductId'] is int) body['storeProductId'] as int,
        if (lines is List)
          for (final line in lines)
            if (line is Map && line['storeProductId'] is int)
              line['storeProductId'] as int,
      ];
      switch ((error.statusCode, error.code)) {
        case (409, 'STORE_CLOSED'):
          return storeClosed;
        case (409, 'PRODUCT_UNAVAILABLE'):
          return CheckoutFailure(
            CheckoutFailureKind.productUnavailable,
            'Un ou plusieurs produits ne sont plus disponibles. Vérifiez votre panier.',
            productIds: ids,
          );
        case (409, 'INSUFFICIENT_STOCK'):
          return CheckoutFailure(
            CheckoutFailureKind.insufficientStock,
            'Un produit n’est plus disponible en quantité suffisante. Réduisez la quantité ou retirez-le.',
            productIds: ids,
          );
        case (400, 'INVALID_QUANTITY'):
          return CheckoutFailure(
            CheckoutFailureKind.invalidQuantity,
            'Une quantité n’est plus valide. Corrigez votre panier.',
            productIds: ids,
          );
        case (400, 'INVALID_PICKUP_TIME'):
          return invalidPickupTime;
        case (409, 'IDEMPOTENCY_KEY_REUSED'):
          return const CheckoutFailure(
            CheckoutFailureKind.keyReused,
            'Un conflit est survenu lors de l’envoi. Vérifiez vos commandes avant de réessayer.',
          );
        case (401, _):
          return CheckoutFailure(
            CheckoutFailureKind.sessionExpired,
            OrderFailure.from(error).message,
          );
        case (404, _):
          return const CheckoutFailure(
            CheckoutFailureKind.notFound,
            'Ce magasin ou l’un de ses produits n’existe plus. Revenez à la liste des magasins.',
          );
        case (400, _):
          return const CheckoutFailure(
            CheckoutFailureKind.invalid,
            'Votre commande n’est pas valide. Vérifiez votre panier et réessayez.',
          );
      }
    }
    return const CheckoutFailure(
      CheckoutFailureKind.unknown,
      'Une erreur est survenue. Veuillez réessayer.',
    );
  }

  final CheckoutFailureKind kind;
  final String message;

  /// The store products the backend named, if any.
  final List<int> productIds;
}
