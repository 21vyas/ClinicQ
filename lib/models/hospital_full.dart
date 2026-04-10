// lib/models/hospital_full.dart

import 'custom_field.dart';

enum TokenFormat {
  numeric, // 1, 2, 3
  prefix,  // A01, A02
  custom,  // City-01, City-02
}

extension TokenFormatLabel on TokenFormat {
  String get label => switch (this) {
    TokenFormat.numeric => 'Numeric (1, 2, 3)',
    TokenFormat.prefix  => 'Prefix (A01, A02)',
    TokenFormat.custom  => 'Custom (City-01)',
  };

  String get value => switch (this) {
    TokenFormat.numeric => 'numeric',
    TokenFormat.prefix  => 'prefix',
    TokenFormat.custom  => 'custom',
  };
}

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
  final String tokenPrefix;
  final TokenFormat tokenFormat;
  final int tokenPadding;
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
    this.tokenPrefix = '',
    this.tokenFormat = TokenFormat.numeric,
    this.tokenPadding = 2,
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

    // Parse token format
    final formatStr = json['token_format'] as String? ?? 'numeric';
    final tokenFormat = TokenFormat.values.firstWhere(
      (f) => f.value == formatStr,
      orElse: () => TokenFormat.numeric,
    );

    return HospitalSettings(
      tokenLimit:         (json['token_limit']          as num?)?.toInt() ?? 100,
      avgTimePerPatient:  (json['avg_time_per_patient'] as num?)?.toInt() ?? 5,
      alertBefore:        (json['alert_before']         as num?)?.toInt() ?? 3,
      tokenPrefix:        json['token_prefix']          as String? ?? '',
      tokenFormat:        tokenFormat,
      tokenPadding:       (json['token_padding']        as num?)?.toInt() ?? 2,
      workingHoursStart:  json['working_hours_start']   as String? ?? '09:00',
      workingHoursEnd:    json['working_hours_end']     as String? ?? '18:00',
      enableAge:          json['enable_age']            as bool?   ?? true,
      enableReason:       json['enable_reason']         as bool?   ?? true,
      customFields:       customFields,
    );
  }

  /// Format a raw token number using this hospital's settings.
  String formatToken(int number) {
    switch (tokenFormat) {
      case TokenFormat.numeric:
        return '$number';
      case TokenFormat.prefix:
      case TokenFormat.custom:
        final padded = number.toString().padLeft(tokenPadding, '0');
        return '$tokenPrefix$padded';
    }
  }

  /// Preview string for the settings UI.
  String get tokenPreview {
    switch (tokenFormat) {
      case TokenFormat.numeric:
        return '1   2   3   …';
      case TokenFormat.prefix:
      case TokenFormat.custom:
        final p = tokenPrefix.isEmpty ? 'A' : tokenPrefix;
        final a = 1.toString().padLeft(tokenPadding, '0');
        final b = 2.toString().padLeft(tokenPadding, '0');
        final c = 3.toString().padLeft(tokenPadding, '0');
        return '$p$a   $p$b   $p$c   …';
    }
  }
}
