import 'catalog_category.dart';
import 'catalog_product.dart';
import 'sale_unit.dart';

/// Why customers cannot order a store product right now. Mirrors the
/// backend's `unavailabilityReason`, which is derived and never stored.
enum UnavailabilityReason {
  /// The store archived this offering.
  archived,

  /// The owner switched it off.
  ownerDisabled,

  /// The catalog archived the product or its category.
  catalogArchived,

  /// Tracked stock is zero — automatic, no manual switch involved.
  outOfStock,

  /// Tracked stock is positive but below the minimum order.
  stockBelowMinimum;

  static UnavailabilityReason fromJson(String value) => switch (value) {
    'ARCHIVED' => UnavailabilityReason.archived,
    'OWNER_DISABLED' => UnavailabilityReason.ownerDisabled,
    'CATALOG_ARCHIVED' => UnavailabilityReason.catalogArchived,
    'OUT_OF_STOCK' => UnavailabilityReason.outOfStock,
    'STOCK_BELOW_MINIMUM' => UnavailabilityReason.stockBelowMinimum,
    _ => throw FormatException('Unknown unavailability reason: $value'),
  };
}

/// How the owner's store sells one catalog product, as returned by
/// `/owner/store-products`: the store's own price, unit, quantity rules, stock
/// and availability, plus the global [product] it is an offering of.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.product,
    required this.saleUnit,
    required this.priceMillimes,
    required this.minQuantity,
    required this.quantityStep,
    required this.trackStock,
    required this.isAvailable,
    required this.isOrderable,
    this.maxQuantity,
    this.stockQuantity,
    this.unavailabilityReason,
    this.isArchived = false,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) {
    final reason = json['unavailabilityReason'] as String?;
    return StoreProduct(
      id: json['id'] as int,
      // The response nests `product` and `category` side by side; the model
      // keeps the category inside the product, where it belongs.
      product: CatalogProduct.fromJson({
        ...(json['product'] as Map<String, dynamic>),
        'category': json['category'],
      }),
      saleUnit: SaleUnit.fromJson(json['saleUnit'] as String),
      priceMillimes: json['priceMillimes'] as int,
      minQuantity: json['minQuantity'] as int,
      quantityStep: json['quantityStep'] as int,
      maxQuantity: json['maxQuantity'] as int?,
      trackStock: json['trackStock'] as bool,
      stockQuantity: json['stockQuantity'] as int?,
      isAvailable: json['isAvailable'] as bool,
      isOrderable: json['isOrderable'] as bool,
      unavailabilityReason: reason == null
          ? null
          : UnavailabilityReason.fromJson(reason),
      isArchived: json['archivedAt'] != null,
    );
  }

  final int id;

  /// The global catalog product this is an offering of.
  final CatalogProduct product;

  int get productId => product.id;
  CategoryRef get category => product.category;

  /// The unit this store sells it in: the product's default, or piece.
  final SaleUnit saleUnit;

  /// Price of ONE sale unit in millimes (4500 = 4,500 DT).
  final int priceMillimes;

  /// In base units (pieces / grams / mL).
  final int minQuantity;
  final int quantityStep;
  final int? maxQuantity;

  /// Whether this store tracks stock for the product.
  final bool trackStock;

  /// Current stock in base units; `null` when stock is not tracked.
  final int? stockQuantity;

  /// The owner's manual on/off switch.
  final bool isAvailable;

  /// Derived by the backend: can customers order it right now?
  final bool isOrderable;
  final UnavailabilityReason? unavailabilityReason;
  final bool isArchived;
}

/// What the owner sends to add a catalog product to the store. Only the
/// product and the price are required; the backend fills the unit and the
/// quantity rules from the catalog when they are left out.
class NewStoreProduct {
  const NewStoreProduct({
    required this.productId,
    required this.priceMillimes,
    this.saleUnit,
    this.minQuantity,
    this.quantityStep,
    this.maxQuantity,
    this.noMaximum = false,
    this.trackStock,
    this.stockQuantity,
    this.isAvailable,
  }) : assert(
         !noMaximum || maxQuantity == null,
         'noMaximum and maxQuantity are mutually exclusive',
       );

  final int productId;
  final int priceMillimes;
  final SaleUnit? saleUnit;
  final int? minQuantity;
  final int? quantityStep;
  final int? maxQuantity;

  /// Sends `maxQuantity: null` — explicitly no maximum, instead of the
  /// catalog's default.
  final bool noMaximum;
  final bool? trackStock;
  final int? stockQuantity;
  final bool? isAvailable;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'priceMillimes': priceMillimes,
    'saleUnit': ?saleUnit?.toJson(),
    'minQuantity': ?minQuantity,
    'quantityStep': ?quantityStep,
    if (noMaximum) 'maxQuantity': null else 'maxQuantity': ?maxQuantity,
    'trackStock': ?trackStock,
    'stockQuantity': ?stockQuantity,
    'isAvailable': ?isAvailable,
  };
}

/// A change to a store product's stock. The owner enters an absolute count,
/// and [expectedStockQuantity] — the stock the screen loaded, `null` if it was
/// not tracked — lets the backend refuse it if an order changed the stock in
/// the meantime, so a count never silently overwrites an order.
class StockChange {
  const StockChange({
    required this.expectedStockQuantity,
    this.trackStock,
    this.stockQuantity,
  }) : assert(
         trackStock != null || stockQuantity != null,
         'a stock change must change trackStock or stockQuantity',
       );

  final int? expectedStockQuantity;
  final bool? trackStock;
  final int? stockQuantity;

  Map<String, dynamic> toJson() => {
    'trackStock': ?trackStock,
    'stockQuantity': ?stockQuantity,
    // Always sent, null included: it is required whenever stock is touched.
    'expectedStockQuantity': expectedStockQuantity,
  };
}

/// What the owner sends to edit a store product: only the fields that change.
/// Changing [saleUnit] requires restating the price and quantity rules (and
/// the stock while it is tracked) — the backend enforces that.
class StoreProductUpdate {
  const StoreProductUpdate({
    this.priceMillimes,
    this.saleUnit,
    this.minQuantity,
    this.quantityStep,
    this.maxQuantity,
    this.clearMaxQuantity = false,
    this.stock,
  }) : assert(
         !clearMaxQuantity || maxQuantity == null,
         'clearMaxQuantity and maxQuantity are mutually exclusive',
       );

  final int? priceMillimes;
  final SaleUnit? saleUnit;
  final int? minQuantity;
  final int? quantityStep;
  final int? maxQuantity;

  /// Sends `maxQuantity: null`, removing the maximum.
  final bool clearMaxQuantity;
  final StockChange? stock;

  Map<String, dynamic> toJson() => {
    'priceMillimes': ?priceMillimes,
    'saleUnit': ?saleUnit?.toJson(),
    'minQuantity': ?minQuantity,
    'quantityStep': ?quantityStep,
    if (clearMaxQuantity) 'maxQuantity': null else 'maxQuantity': ?maxQuantity,
    ...?stock?.toJson(),
  };
}
