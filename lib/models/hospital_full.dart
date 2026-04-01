// lib/models/hospital_full.dart

import 'custom_field.dart';

class HospitalFull {
  final String id;
  final String name;
  final String slug;
  final String? address;
  final String? phone;
  final HospitalSettings settings;

  const HospitalFull({
    required this.id,
    required this.name,
    required this.slug,
    this.address,
    this.phone,
    required this.settings,
  });

  factory HospitalFull.fromJson(Map<String, dynamic> json) {
    return HospitalFull(
      id:       json['id']      as String,
      name:     json['name']    as String,
      slug:     json['slug']    as String,
      address:  json['address'] as String?,
      phone:    json['phone']   as String?,
      settings: HospitalSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────

class HospitalSettings {
  final int tokenLimit;
  final int avgTimePerPatient;
  final int alertBefore;
  final String workingHoursStart;
  final String workingHoursEnd;
  // Step 4 — dynamic fields
  final bool enableAge;
  final bool enableReason;
  final List<CustomField> customFields;

  const HospitalSettings({
    required this.tokenLimit,
    required this.avgTimePerPatient,
    required this.alertBefore,
    required this.workingHoursStart,
    required this.workingHoursEnd,
    this.enableAge    = true,
    this.enableReason = true,
    this.customFields = const [],
  });

  factory HospitalSettings.fromJson(Map<String, dynamic> json) {
    // Parse custom_fields — handles null, empty list, and proper array
    List<CustomField> customFields = [];
    final rawFields = json['custom_fields'];
    if (rawFields is List) {
      customFields = rawFields
          .whereType<Map>()
          .map((e) => CustomField.fromJson(Map<String, dynamic>.from(e)))
          .where((f) => f.id.isNotEmpty && f.label.isNotEmpty)
          .toList();
    }

    return HospitalSettings(
      tokenLimit:         (json['token_limit']          as num?)?.toInt() ?? 100,
      avgTimePerPatient:  (json['avg_time_per_patient'] as num?)?.toInt() ?? 5,
      alertBefore:        (json['alert_before']         as num?)?.toInt() ?? 3,
      workingHoursStart:  json['working_hours_start']   as String? ?? '09:00',
      workingHoursEnd:    json['working_hours_end']     as String? ?? '18:00',
      enableAge:          json['enable_age']            as bool?   ?? true,
      enableReason:       json['enable_reason']         as bool?   ?? true,
      customFields:       customFields,
    );
  }
}