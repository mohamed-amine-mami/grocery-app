import '../../../data/models/order.dart';

/// French wording for order statuses and history. Only the backend's real
/// statuses appear here.
abstract final class OrderLabels {
  /// Filter chip text (short).
  static String filter(OrderStatus? status) => switch (status) {
    null => 'Toutes',
    OrderStatus.pending => 'En attente',
    OrderStatus.confirmed => 'Confirmée',
    OrderStatus.readyForPickup => 'Prête',
    OrderStatus.completed => 'Terminée',
    OrderStatus.cancelled => 'Annulée',
    OrderStatus.noShow => 'Non récupérée',
  };

  /// Status badge text: "Prête à retirer" must read unambiguously.
  static String status(OrderStatus status) => switch (status) {
    OrderStatus.readyForPickup => 'Prête à retirer',
    OrderStatus.completed => 'Terminée',
    _ => filter(status),
  };

  /// One line of the history: what happened and who did it.
  static String event(OrderEvent event) {
    final by = switch (event.actorType) {
      OrderActorType.client => 'par le client',
      OrderActorType.owner => 'par le magasin',
      OrderActorType.system => 'automatiquement',
      OrderActorType.channel => 'par le client',
    };
    return switch (event.toStatus) {
      OrderStatus.pending => 'Commande reçue',
      OrderStatus.confirmed => 'Commande confirmée',
      OrderStatus.readyForPickup => 'Prête à retirer',
      OrderStatus.completed => 'Commande récupérée et payée',
      OrderStatus.cancelled => 'Commande annulée $by',
      OrderStatus.noShow => 'Commande non récupérée',
    };
  }
}
