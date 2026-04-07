// lib/models/analytics_data.dart

class AnalyticsData {
  final int totalPatients;
  final int totalDone;
  final int avgWaitMins;
  final List<VisitTypeStat> visitTypeDist;
  final List<PeakHourStat> peakHours;
  final List<DailyTotalStat> dailyTotals;
  final List<ReasonStat> topReasons;
  final DateTime dateFrom;
  final DateTime dateTo;

  const AnalyticsData({
    required this.totalPatients,
    required this.totalDone,
    required this.avgWaitMins,
    required this.visitTypeDist,
    required this.peakHours,
    required this.dailyTotals,
    required this.topReasons,
    required this.dateFrom,
    required this.dateTo,
  });

  factory AnalyticsData.fromJson(Map<String, dynamic> json) {
    return AnalyticsData(
      totalPatients: _i(json['total_patients']),
      totalDone:     _i(json['total_done']),
      avgWaitMins:   _i(json['avg_wait_mins']),
      visitTypeDist: _parseList(json['visit_type_dist'], VisitTypeStat.fromJson),
      peakHours:     _parseList(json['peak_hours'],      PeakHourStat.fromJson),
      dailyTotals:   _parseList(json['daily_totals'],    DailyTotalStat.fromJson),
      topReasons:    _parseList(json['top_reasons'],     ReasonStat.fromJson),
      dateFrom:      _parseDate(json['date_from']),
      dateTo:        _parseDate(json['date_to']),
    );
  }

  factory AnalyticsData.empty() => AnalyticsData(
    totalPatients: 0, totalDone: 0, avgWaitMins: 0,
    visitTypeDist: [], peakHours: [], dailyTotals: [], topReasons: [],
    dateFrom: DateTime.now(), dateTo: DateTime.now(),
  );

  static int _i(dynamic v) => (v is num) ? v.toInt() : 0;

  static List<T> _parseList<T>(dynamic raw, T Function(Map<String, dynamic>) fn) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => fn(Map<String, dynamic>.from(e))).toList();
  }

  static DateTime _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) ?? DateTime.now() : DateTime.now();

  double get completionRate =>
      totalPatients == 0 ? 0 : totalDone / totalPatients;

  /// Peak hour — hour with most patients
  PeakHourStat? get busiesHour =>
      peakHours.isEmpty ? null :
      peakHours.reduce((a, b) => a.count > b.count ? a : b);

  int get maxHourCount =>
      peakHours.isEmpty ? 1 : peakHours.map((h) => h.count).reduce((a, b) => a > b ? a : b);
}

class VisitTypeStat {
  final String visitType;
  final int count;

  const VisitTypeStat({required this.visitType, required this.count});

  factory VisitTypeStat.fromJson(Map<String, dynamic> json) => VisitTypeStat(
    visitType: json['visit_type'] as String? ?? 'general',
    count:     (json['count'] as num?)?.toInt() ?? 0,
  );

  String get label => switch (visitType) {
    'first_visit' => 'First Visit',
    'follow_up'   => 'Follow-up',
    'emergency'   => 'Emergency',
    _             => 'General',
  };
}

class PeakHourStat {
  final int hour;
  final int count;

  const PeakHourStat({required this.hour, required this.count});

  factory PeakHourStat.fromJson(Map<String, dynamic> json) => PeakHourStat(
    hour:  (json['hour']  as num?)?.toInt() ?? 0,
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  String get label {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h${hour < 12 ? 'am' : 'pm'}';
  }
}

class DailyTotalStat {
  final DateTime date;
  final int total;
  final int done;

  const DailyTotalStat({required this.date, required this.total, required this.done});

  factory DailyTotalStat.fromJson(Map<String, dynamic> json) => DailyTotalStat(
    date:  DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    total: (json['total'] as num?)?.toInt() ?? 0,
    done:  (json['done']  as num?)?.toInt() ?? 0,
  );
}

class ReasonStat {
  final String reason;
  final int count;
  const ReasonStat({required this.reason, required this.count});
  factory ReasonStat.fromJson(Map<String, dynamic> json) => ReasonStat(
    reason: json['reason'] as String? ?? '',
    count:  (json['count'] as num?)?.toInt() ?? 0,
  );
}

// ─────────────────────────────────────────────────────────
// Patient models
// ─────────────────────────────────────────────────────────

class PatientRecord {
  final String phone;
  final String name;
  final int visitCount;
  final DateTime lastVisit;
  final DateTime firstVisit;
  final String? lastReason;
  final int? lastToken;
  final bool isReturning;

  const PatientRecord({
    required this.phone,
    required this.name,
    required this.visitCount,
    required this.lastVisit,
    required this.firstVisit,
    this.lastReason,
    this.lastToken,
    required this.isReturning,
  });

  factory PatientRecord.fromJson(Map<String, dynamic> json) => PatientRecord(
    phone:       json['patient_phone']  as String? ?? '',
    name:        json['patient_name']   as String? ?? '',
    visitCount:  (json['visit_count']   as num?)?.toInt() ?? 1,
    lastVisit:   DateTime.tryParse(json['last_visit']  as String? ?? '') ?? DateTime.now(),
    firstVisit:  DateTime.tryParse(json['first_visit'] as String? ?? '') ?? DateTime.now(),
    lastReason:  json['last_reason']    as String?,
    lastToken:   (json['last_token']    as num?)?.toInt(),
    isReturning: json['is_returning']   as bool? ?? false,
  );
}

class PatientsResult {
  final List<PatientRecord> patients;
  final int total;

  const PatientsResult({required this.patients, required this.total});

  factory PatientsResult.fromJson(Map<String, dynamic> json) {
    final raw = json['patients'] as List<dynamic>? ?? [];
    return PatientsResult(
      patients: raw.whereType<Map>()
          .map((e) => PatientRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}