class AppUser {
  final String id;
  final String authId;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String? role;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.authId,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.role,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id:        json['id']         as String,
      authId:    json['auth_id']    as String,
      email:     json['email']      as String,
      fullName:  json['full_name']  as String?,
      avatarUrl: json['avatar_url'] as String?,
      role:      json['role']       as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'auth_id':    authId,
        'email':      email,
        'full_name':  fullName,
        'avatar_url': avatarUrl,
        'role':       role,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isSuperAdmin => role == 'superadmin';
  String get displayName => fullName ?? email.split('@').first;
}
