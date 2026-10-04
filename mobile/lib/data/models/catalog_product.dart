import 'catalog_category.dart';
import 'sale_unit.dart';

/// A global catalog product: the canonical identity of something a store can
/// sell. It carries only what the catalog knows — name, description, image,
/// category and the *default* unit and quantity rules. Price, stock and
/// availability belong to a store's offering ([StoreProduct]), never here.
class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.defaultSaleUnit,
    required this.allowedSaleUnits,
    required this.defaultMinQuantity,
    required this.defaultQuantityStep,
    this.description,
    this.photo,
    this.defaultMaxQuantity,
    this.isActive = true,
  });

  /// Parses a product with its category nested under `category` — the shape of
  /// `/owner/catalog/products`, and (rebuilt by [StoreProduct]) of a store
  /// product's `product` + `category`.
  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    return CatalogProduct(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      photo: json['photo'] as String?,
      category: CategoryRef.fromJson(json['category'] as Map<String, dynamic>),
      defaultSaleUnit: SaleUnit.fromJson(json['defaultSaleUnit'] as String),
      allowedSaleUnits: [
        for (final unit in json['allowedSaleUnits'] as List<dynamic>)
          SaleUnit.fromJson(unit as String),
      ],
      defaultMinQuantity: json['defaultMinQuantity'] as int,
      defaultQuantityStep: json['defaultQuantityStep'] as int,
      defaultMaxQuantity: json['defaultMaxQuantity'] as int?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  final int id;

  /// The catalog's stable identifier for the product.
  final String slug;
  final String name;
  final String? description;

  /// An image URL.
  final String? photo;
  final CategoryRef category;

  /// The unit the catalog suggests (a store may also sell it by the piece).
  final SaleUnit defaultSaleUnit;

  /// The units a store may use for this product: [defaultSaleUnit] or piece.
  final List<SaleUnit> allowedSaleUnits;

  /// Suggested quantity rules, in base units (pieces / grams / mL).
  final int defaultMinQuantity;
  final int defaultQuantityStep;
  final int? defaultMaxQuantity;

  /// `false` once the catalog archived the product.
  final bool isActive;
}

/// One row of the owner's catalog picker: a global product and whether the
/// owner's store already sells it.
class CatalogItem {
  const CatalogItem({
    required this.product,
    required this.inMyStore,
    required this.storeProductArchived,
    this.storeProductId,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      product: CatalogProduct.fromJson(json),
      inMyStore: json['inMyStore'] as bool,
      storeProductId: json['storeProductId'] as int?,
      storeProductArchived: json['storeProductArchived'] as bool,
    );
  }

  final CatalogProduct product;

  /// The store currently sells it (an active store product).
  final bool inMyStore;

  /// The store's own row for it — active or archived — if there is one.
  final int? storeProductId;

  /// The store has an archived row for it: restore it instead of adding.
  final bool storeProductArchived;
}
