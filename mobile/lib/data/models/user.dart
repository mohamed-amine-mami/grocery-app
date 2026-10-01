/// Mirrors the backend's `UserRole` enum (`backend/src/users/user-role.enum.ts`).
enum UserRole {
  owner,
  client;

  static UserRole fromJson(String value) => switch (value) {
    'OWNER' => UserRole.owner,
    'CLIENT' => UserRole.client,
    _ => throw FormatException('Unknown user role: $value'),
  };

  String toJson() => switch (this) {
    UserRole.owner => 'OWNER',
    UserRole.client => 'CLIENT',
  };
}

/// The public user shape returned by the backend (never includes a password).
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phoneNumber,
    this.whatsappNumber,
    this.photo,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      whatsappNumber: json['whatsappNumber'] as String?,
      photo: json['photo'] as String?,
      role: UserRole.fromJson(json['role'] as String),
    );
  }

  final int id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? whatsappNumber;
  final String? photo;
  final UserRole role;
}
