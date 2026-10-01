/// The store shape returned by the backend's owner-store API
/// (`/owner/store`).
class Store {
  const Store({
    required this.id,
    required this.name,
    required this.address,
    required this.isOpen,
    required this.ownerId,
    this.description,
    this.photo,
    this.latitude,
    this.longitude,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      photo: json['photo'] as String?,
      address: json['address'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isOpen: json['isOpen'] as bool,
      ownerId: json['ownerId'] as int,
    );
  }

  final int id;
  final String name;
  final String? description;
  final String? photo;
  final String address;
  final double? latitude;
  final double? longitude;

  /// Whether the store currently accepts orders. New stores start closed.
  final bool isOpen;
  final int ownerId;
}
