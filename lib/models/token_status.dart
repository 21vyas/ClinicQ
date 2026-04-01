// lib/models/token_status.dart

import 'queue_entry.dart';

class TokenStatus {
  final String id;
  final int tokenNumber;
  final String patientName;
  final QueueStatus status;
  final String? reason;
  final String hospitalId;
  final int currentTokenNumber;
  final int positionAhead;
  final int estimatedWaitMins;

  const TokenStatus({
    required this.id,
    required this.tokenNumber,
    required this.patientName,
    required this.status,
    this.reason,
    required this.hospitalId,
    required this.currentTokenNumber,
    required this.positionAhead,
    required this.estimatedWaitMins,
  });

  factory TokenStatus.fromJson(Map<String, dynamic> json) {
    return TokenStatus(
      id:                   json['id'] as String,
      tokenNumber:          (json['token_number'] as num).toInt(),
      patientName:          json['patient_name'] as String,
      status:               QueueStatus.fromString(
          json['status'] as String? ?? 'waiting'),
      reason:               json['reason'] as String?,
      hospitalId:           json['hospital_id'] as String,
      currentTokenNumber:   (json['current_token_number'] as num?)?.toInt() ?? 0,
      positionAhead:        (json['position_ahead']        as num?)?.toInt() ?? 0,
      estimatedWaitMins:    (json['estimated_wait_mins']   as num?)?.toInt() ?? 0,
    );
  }

  /// True when this token is being served right now
  bool get isBeingServed => status == QueueStatus.inProgress;

  /// True when this patient is next (0 people ahead, still waiting)
  bool get isNext =>
      positionAhead == 0 && status == QueueStatus.waiting;
}