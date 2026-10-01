/// A store category, as returned by `/owner/categories`.
class StoreCategory {
  const StoreCategory({required this.id, required this.name});

  factory StoreCategory.fromJson(Map<String, dynamic> json) {
    return StoreCategory(id: json['id'] as int, name: json['name'] as String);
  }

  final int id;
  final String name;
}
