/// A store as a customer sees it (`GET /stores`): customer-safe fields only,
/// no owner information. A closed store can still be browsed; it just does not
/// accept new orders.
class CustomerStore {
  const CustomerStore({
    required this.id,
    required this.name,
    required this.address,
    required this.isOpen,
    this.description,
    this.photo,
  });

  factory CustomerStore.fromJson(Map<String, dynamic> json) => CustomerStore(
    id: json['id'] as int,
    name: json['name'] as String,
    address: json['address'] as String,
    isOpen: json['isOpen'] as bool,
    description: json['description'] as String?,
    photo: json['photo'] as String?,
  );

  final int id;
  final String name;
  final String address;

  /// Whether the store accepts new orders right now. Browsing is always
  /// allowed; `POST /orders` stays the final authority.
  final bool isOpen;
  final String? description;

  /// An image URL.
  final String? photo;

  CustomerStore copyWith({bool? isOpen}) => CustomerStore(
    id: id,
    name: name,
    address: address,
    isOpen: isOpen ?? this.isOpen,
    description: description,
    photo: photo,
  );
}
