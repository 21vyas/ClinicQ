class Hospital {
  final String id;
  final String name;
  final String slug;
  final String? address;
  final String? phone;
  final String createdBy;
  final DateTime createdAt;
 
  const Hospital({
    required this.id,
    required this.name,
    required this.slug,
    this.address,
    this.phone,
    required this.createdBy,
    required this.createdAt,
  });
 
  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
 
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'address': address,
        'phone': phone,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };
}
 