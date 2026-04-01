// lib/models/queue_entry.dart

import 'package:flutter/foundation.dart';

class QueueEntry {
  final String id;
  final String hospitalId;
  final int tokenNumber;
  final DateTime queueDate;
  final String patientName;
  final String patientPhone;
  final int? patientAge;
  final String? reason;
  final QueueStatus status;
  final Map<String, dynamic> customData; // Step 4
  final DateTime? calledAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QueueEntry({
    required this.id,
    required this.hospitalId,
    required this.tokenNumber,
    required this.queueDate,
    required this.patientName,
    required this.patientPhone,
    this.patientAge,
    this.reason,
    required this.status,
    this.customData = const {},
    this.calledAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> json) {
    try {
      // Parse custom_data safely
      Map<String, dynamic> customData = {};
      final raw = json['custom_data'];
      if (raw is Map) customData = Map<String, dynamic>.from(raw);

      return QueueEntry(
        id:           json['id']           as String,
        hospitalId:   json['hospital_id']  as String,
        tokenNumber:  (json['token_number'] as num).toInt(),
        queueDate:    _parseDate(json['queue_date']),
        patientName:  json['patient_name']  as String? ?? '',
        patientPhone: json['patient_phone'] as String? ?? '',
        patientAge:   json['patient_age'] != null
            ? (json['patient_age'] as num).toInt()
            : null,
        reason:       json['reason']      as String?,
        status:       QueueStatus.fromString(json['status'] as String? ?? 'waiting'),
        customData:   customData,
        calledAt:     json['called_at'] != null
            ? DateTime.tryParse(json['called_at'] as String)
            : null,
        completedAt:  json['completed_at'] != null
            ? DateTime.tryParse(json['completed_at'] as String)
            : null,
        createdAt:    _parseDate(json['created_at']),
        updatedAt:    _parseDate(json['updated_at']),
      );
    } catch (e) {
      debugPrint('[QueueEntry.fromJson] parse error: $e  json=$json');
      rethrow;
    }
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  QueueEntry copyWith({QueueStatus? status}) => QueueEntry(
        id:           id,
        hospitalId:   hospitalId,
        tokenNumber:  tokenNumber,
        queueDate:    queueDate,
        patientName:  patientName,
        patientPhone: patientPhone,
        patientAge:   patientAge,
        reason:       reason,
        status:       status ?? this.status,
        customData:   customData,
        calledAt:     calledAt,
        completedAt:  completedAt,
        createdAt:    createdAt,
        updatedAt:    updatedAt,
      );

  int? get waitedMins {
    if (calledAt == null) return null;
    return calledAt!.difference(createdAt).inMinutes;
  }
}

// ─────────────────────────────────────────────────────────

enum QueueStatus {
  waiting,
  inProgress,
  done,
  skipped;

  static QueueStatus fromString(String s) => switch (s.toLowerCase().trim()) {
        'waiting'     => QueueStatus.waiting,
        'in_progress' => QueueStatus.inProgress,
        'serving'     => QueueStatus.inProgress,
        'done'        => QueueStatus.done,
        'skipped'     => QueueStatus.skipped,
        _             => QueueStatus.waiting,
      };

  String get label => switch (this) {
        QueueStatus.waiting    => 'Waiting',
        QueueStatus.inProgress => 'In Progress',
        QueueStatus.done       => 'Done',
        QueueStatus.skipped    => 'Skipped',
      };
}