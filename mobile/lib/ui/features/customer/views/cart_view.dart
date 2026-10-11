import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/product_formatters.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/product_image.dart';
import '../view_models/cart_view_model.dart';
import '../view_models/customer_scope.dart';
import 'checkout_view.dart';
import 'quantity_stepper.dart';
import 'stores_view.dart' show StoreOpenBadge;

/// `Panier` tab — the local cart of one store, with an *estimated* total: the
/// backend computes the real one when the order is sent.
class CartView extends StatelessWidget {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = CustomerScope.of(context);
    final cart = scope.cart;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Panier')),
          body: SafeArea(
            child: cart.isEmpty
                ? _EmptyCart(
                    onBrowse: () => scope.navigation.select(CustomerTab.stores),
                  )
                : _CartContent(cart: cart),
          ),
        );
      },
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.shopping_cart_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Votre panier est vide',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Choisissez un magasin pour commencer vos achats.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppPrimaryButton(label: 'Voir les magasins', onPressed: onBrowse),
        ],
      ),
    );
  }
}

class _CartContent extends StatelessWidget {
  const _CartContent({required this.cart});

  final CartViewModel cart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final store = cart.store!;
    final blocked = cart.hasProblems || !store.isOpen;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              store.name,
                              style: textTheme.titleMedium,
                            ),
                          ),
                          StoreOpenBadge(isOpen: store.isOpen),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(store.address, style: textTheme.bodySmall),
                      if (!store.isOpen) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Ce magasin est fermé : vous ne pouvez pas commander pour le moment.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (index, line) in cart.lines.indexed) ...[
                      if (index > 0) const Divider(height: 1),
                      _CartLineTile(line: line, cart: cart),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              EstimatedTotal(totalMillimes: cart.estimatedTotalMillimes),
            ],
          ),
        ),
        Material(
          color: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cart.hasProblems) ...[
                  const Text(
                    'Corrigez votre panier avant de commander.',
                    style: TextStyle(fontSize: 14, color: AppColors.warning),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AppPrimaryButton(
                  label: 'Commander',
                  // The same estimate as the total card above: one number.
                  trailing: ProductFormat.price(cart.estimatedTotalMillimes),
                  onPressed: blocked
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const CheckoutView(),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.cart});

  final CartLine line;
  final CartViewModel cart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final product = line.product;
    final problem = line.problem;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LineThumbnail(
                photo: product.photo,
                // Same cue as the catalogue: a product that is gone is dimmed.
                dimmed: problem == CartProblem.unavailable,
              ),
              // The amount sits on the name's first baseline.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: textTheme.bodyMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            ProductFormat.pricePerUnit(
                              product.saleUnit,
                              product.priceMillimes,
                            ),
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      ProductFormat.price(line.subtotalMillimes),
                      style: textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (problem != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    problem == CartProblem.unavailable
                        ? 'Ce produit n’est plus disponible. Retirez-le du panier.'
                        : 'La quantité n’est plus valide pour ce produit.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: problem == CartProblem.unavailable
                ? TextButton.icon(
                    onPressed: () => cart.remove(product.id),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Retirer'),
                  )
                : problem == CartProblem.invalidQuantity
                ? TextButton(
                    onPressed: () => cart.fixQuantity(product.id),
                    child: const Text('Corriger la quantité'),
                  )
                : QuantityStepper(
                    productName: product.name,
                    unit: product.saleUnit,
                    quantity: line.quantity,
                    atMinimum:
                        line.quantity - product.quantityStep <
                        product.minQuantity,
                    canIncrement: line.canIncrement,
                    onIncrement: () => cart.increment(product.id),
                    onDecrement: () => cart.decrement(product.id),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A product's small picture at the start of a cart or order-summary line:
/// the catalogue's own [ProductImage] (placeholder when there is no photo, while
/// it loads or if it fails), whole picture, never cropped.
///
/// It is a recognition aid next to the product's name, so a screen reader skips
/// it (the name is read). At large text sizes the line needs its width for the
/// text and the picture steps aside: the line is then exactly what it was
/// without pictures.
class LineThumbnail extends StatelessWidget {
  const LineThumbnail({required this.photo, this.dimmed = false, super.key});

  final String? photo;

  /// For a product that can no longer be ordered.
  final bool dimmed;

  /// Same as the owner's catalogue rows.
  static const size = 56.0;

  /// Text scale above which the picture is left out.
  static const maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale > maxTextScale) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          // A tile of its own: the same 56 px square whether the picture
          // fills it, is narrower (whole picture) or is the placeholder.
          child: ProductImage(
            photo: photo,
            size: size,
            fit: BoxFit.contain,
            tile: true,
          ),
        ),
      ),
    );
  }
}

/// The cart's total *for review*: from the prices last loaded, never sent, and
/// not the final amount.
class EstimatedTotal extends StatelessWidget {
  const EstimatedTotal({required this.totalMillimes, super.key});

  final int totalMillimes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Total estimé', style: textTheme.bodyMedium),
                ),
                Text(
                  ProductFormat.price(totalMillimes),
                  style: textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Le total définitif est confirmé à l’envoi de la commande.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
