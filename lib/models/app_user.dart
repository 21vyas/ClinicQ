class AppUser {
  final String id;
  final String authId;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String? role;       // global role: super_admin | admin | staff
  final bool isActive;
  final DateTime createdAt;

  /// Hospital-level role from hospital_users table (admin | staff).
  /// Populated only after calling get_my_hospital().
  final String? hospitalRole;

  const AppUser({
    required this.id,
    required this.authId,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.role,
    this.isActive = true,
    required this.createdAt,
    this.hospitalRole,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id:        json['id']         as String,
      authId:    json['auth_id']    as String,
      email:     json['email']      as String,
      fullName:  json['full_name']  as String?,
      avatarUrl: json['avatar_url'] as String?,
      role:      json['role']       as String?,
      isActive:  (json['is_active'] as bool?) ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppUser copyWith({String? hospitalRole}) {
    return AppUser(
      id:           id,
      authId:       authId,
      email:        email,
      fullName:     fullName,
      avatarUrl:    avatarUrl,
      role:         role,
      isActive:     isActive,
      createdAt:    createdAt,
      hospitalRole: hospitalRole ?? this.hospitalRole,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'auth_id':    authId,
        'email':      email,
        'full_name':  fullName,
        'avatar_url': avatarUrl,
        'role':       role,
        'is_active':  isActive,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isSuperAdmin      => role == 'super_admin';
  bool get isHospitalAdmin   => hospitalRole == 'admin' || isSuperAdmin;
  bool get isStaff           => hospitalRole == 'staff' && !isSuperAdmin;
  String get displayName     => fullName ?? email.split('@').first;
}
