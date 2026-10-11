import 'brand.dart';
import 'catalog_category.dart';
import 'sale_unit.dart';
import 'store_product.dart';

/// One product of a store's catalogue as a customer sees it
/// (`GET /stores/:id/products`): this store's own price, unit and quantity
/// rules, and the backend's verdict on whether it can be ordered. There is no
/// stock figure anywhere in it, and none can be inferred from it.
class CustomerProduct {
  const CustomerProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.saleUnit,
    required this.priceMillimes,
    required this.minQuantity,
    required this.quantityStep,
    required this.isOrderable,
    this.description,
    this.photo,
    this.brand,
    this.maxQuantity,
    this.unavailabilityReason,
  });

  factory CustomerProduct.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>;
    final reason = json['unavailabilityReason'] as String?;
    final brand = json['brand'];
    return CustomerProduct(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      photo: json['photo'] as String?,
      // `null` (or absent) for a product without a brand.
      brand: brand == null
          ? null
          : Brand.fromJson(brand as Map<String, dynamic>),
      // The customer API sends only the category's id and name (no slug).
      category: CategoryRef(
        id: category['id'] as int,
        slug: '',
        name: category['name'] as String,
      ),
      saleUnit: SaleUnit.fromJson(json['saleUnit'] as String),
      priceMillimes: json['priceMillimes'] as int,
      minQuantity: json['minQuantity'] as int,
      quantityStep: json['quantityStep'] as int,
      maxQuantity: json['maxQuantity'] as int?,
      isOrderable: json['isOrderable'] as bool,
      unavailabilityReason: reason == null
          ? null
          : UnavailabilityReason.fromJson(reason),
    );
  }

  /// The store product id: what an order line refers to.
  final int id;
  final String name;
  final String? description;

  /// An image URL.
  final String? photo;

  /// `null` when the product has no brand.
  final Brand? brand;
  final CategoryRef category;
  final SaleUnit saleUnit;

  /// Price of one sale unit, in millimes.
  final int priceMillimes;

  /// In base units: pieces / grams / millilitres.
  final int minQuantity;
  final int quantityStep;
  final int? maxQuantity;

  /// The backend's derived verdict at the time of loading; checkout
  /// revalidates everything.
  final bool isOrderable;
  final UnavailabilityReason? unavailabilityReason;
}
