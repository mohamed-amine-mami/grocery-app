import '../../../../data/models/order.dart';

/// What a customer reads for an order's status and history. (The owner sees
/// "Non récupérée"; the customer, "Non retirée".)
abstract final class CustomerOrderLabels {
  static String status(OrderStatus status) => switch (status) {
    OrderStatus.pending => 'En attente',
    OrderStatus.confirmed => 'Confirmée',
    OrderStatus.readyForPickup => 'Prête à retirer',
    OrderStatus.completed => 'Terminée',
    OrderStatus.cancelled => 'Annulée',
    OrderStatus.noShow => 'Non retirée',
  };

  /// One line of the history, as the customer would say it.
  static String event(OrderEvent event) => switch (event.toStatus) {
    OrderStatus.pending => 'Commande passée',
    OrderStatus.confirmed => 'Commande confirmée par le magasin',
    OrderStatus.readyForPickup => 'Commande prête à retirer',
    OrderStatus.completed => 'Commande récupérée',
    OrderStatus.cancelled =>
      event.actorType == OrderActorType.owner
          ? 'Commande annulée par le magasin'
          : 'Commande annulée',
    OrderStatus.noShow => 'Commande non retirée',
  };

  /// A sentence under the status, for what happens next.
  static String? hint(OrderStatus status) => switch (status) {
    OrderStatus.pending => 'Le magasin va confirmer votre commande.',
    OrderStatus.confirmed => 'Le magasin a confirmé votre commande.',
    OrderStatus.readyForPickup =>
      'Votre commande est prête. Présentez votre code au magasin.',
    OrderStatus.completed => null,
    OrderStatus.cancelled => null,
    OrderStatus.noShow => 'La commande n’a pas été retirée.',
  };
}
