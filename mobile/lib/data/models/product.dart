import 'sale_unit.dart';

/// A catalog product, as returned by `/owner/products`.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.saleUnit,
    required this.priceMillimes,
    required this.minQuantity,
    required this.quantityStep,
    required this.isAvailable,
    this.categoryId,
    this.description,
    this.photo,
    this.maxQuantity,
    this.isArchived = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      categoryId: json['categoryId'] as int?,
      name: json['name'] as String,
      description: json['description'] as String?,
      photo: json['photo'] as String?,
      saleUnit: SaleUnit.fromJson(json['saleUnit'] as String),
      priceMillimes: json['priceMillimes'] as int,
      minQuantity: json['minQuantity'] as int,
      quantityStep: json['quantityStep'] as int,
      maxQuantity: json['maxQuantity'] as int?,
      isAvailable: json['isAvailable'] as bool,
      isArchived: json['archivedAt'] != null,
    );
  }

  final int id;
  final int? categoryId;
  final String name;
  final String? description;
  final String? photo;
  final SaleUnit saleUnit;

  /// Price of ONE sale unit in millimes (1800 = 1,800 DT).
  final int priceMillimes;

  /// In base units (pieces / grams / mL).
  final int minQuantity;
  final int quantityStep;
  final int? maxQuantity;

  /// `false` = temporarily unavailable (not deleted).
  final bool isAvailable;
  final bool isArchived;

  Product copyWith({bool? isAvailable}) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    description: description,
    photo: photo,
    saleUnit: saleUnit,
    priceMillimes: priceMillimes,
    minQuantity: minQuantity,
    quantityStep: quantityStep,
    maxQuantity: maxQuantity,
    isAvailable: isAvailable ?? this.isAvailable,
    isArchived: isArchived,
  );
}

/// What the editor sends. Every field is always included: for an update a
/// `null` clears the optional ones, and a unit change must restate price and
/// quantity rules anyway (the backend enforces that).
class ProductInput {
  const ProductInput({
    required this.name,
    required this.saleUnit,
    required this.priceMillimes,
    required this.minQuantity,
    required this.quantityStep,
    this.categoryId,
    this.description,
    this.photo,
    this.maxQuantity,
  });

  final String name;
  final SaleUnit saleUnit;
  final int priceMillimes;
  final int minQuantity;
  final int quantityStep;
  final int? maxQuantity;
  final int? categoryId;
  final String? description;
  final String? photo;

  Map<String, dynamic> toJson() => {
    'name': name,
    'saleUnit': saleUnit.toJson(),
    'priceMillimes': priceMillimes,
    'minQuantity': minQuantity,
    'quantityStep': quantityStep,
    'maxQuantity': maxQuantity,
    'categoryId': categoryId,
    'description': _nullIfBlank(description),
    'photo': _nullIfBlank(photo),
  };

  static String? _nullIfBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
