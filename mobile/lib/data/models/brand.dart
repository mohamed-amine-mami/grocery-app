/// A product's brand, as the catalog API shows it. Brands are global and
/// importer-managed; the app only displays them.
class Brand {
  const Brand({required this.id, required this.slug, required this.name});

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(
    id: json['id'] as int,
    slug: json['slug'] as String,
    name: json['name'] as String,
  );

  final int id;

  /// The catalog's stable identifier.
  final String slug;
  final String name;
}
