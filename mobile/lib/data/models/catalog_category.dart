/// A global catalog category, as returned by `GET /owner/catalog/categories`.
/// Categories belong to the catalog, never to a store.
class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.slug,
    required this.name,
    required this.productCount,
    this.description,
    this.photo,
  });

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    return CatalogCategory(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      photo: json['photo'] as String?,
      productCount: json['productCount'] as int,
    );
  }

  final int id;

  /// The catalog's stable identifier for the category.
  final String slug;
  final String name;
  final String? description;

  /// An image URL.
  final String? photo;

  /// Active catalog products in this category.
  final int productCount;
}

/// The category a catalog product sits in, as embedded in a product.
class CategoryRef {
  const CategoryRef({
    required this.id,
    required this.slug,
    required this.name,
    this.isActive = true,
  });

  factory CategoryRef.fromJson(Map<String, dynamic> json) {
    return CategoryRef(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  final int id;
  final String slug;
  final String name;

  /// `false` once the catalog archived the category.
  final bool isActive;
}
