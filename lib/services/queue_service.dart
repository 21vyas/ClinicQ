// lib/services/queue_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hospital_full.dart';
import '../models/queue_entry.dart';
import '../models/queue_today.dart';
import '../models/token_status.dart';

class QueueService {
  final SupabaseClient _client;

  QueueService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ── Public RPCs (anon) ────────────────────────────────────

  Future<QueueServiceResult<HospitalFull>> getHospitalFull(
      String hospitalId) async {
    try {
      final data = await _client
          .rpc('get_hospital_full', params: {'p_hospital_id': hospitalId});
      return QueueServiceResult.success(
          HospitalFull.fromJson(_asMap(data)));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] getHospitalFull error: $e');
      return QueueServiceResult.failure('Failed to load clinic info.');
    }
  }

  Future<QueueServiceResult<QueueEntry>> createQueueEntry({
    required String hospitalId,
    required String name,
    required String phone,
    int? age,
    String? reason,
    Map<String, dynamic>? customData, // Step 4
  }) async {
    try {
      final data = await _client.rpc('create_queue_entry', params: {
        'p_hospital_id': hospitalId,
        'p_name':        name,
        'p_phone':       phone,
        'p_age':         age,
        'p_reason':      reason,
        'p_custom_data': customData ?? {},
      });
      return QueueServiceResult.success(QueueEntry.fromJson(_asMap(data)));
    } on PostgrestException catch (e) {
      if (e.message.contains('TOKEN_LIMIT_REACHED')) {
        return QueueServiceResult.failure(
            "Today's token limit has been reached. Please visit tomorrow.");
      }
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] createQueueEntry error: $e');
      return QueueServiceResult.failure(
          'Failed to get a token. Please try again.');
    }
  }

  Future<QueueServiceResult<TokenStatus>> getTokenStatus(
      String queueId) async {
    try {
      final data = await _client
          .rpc('get_token_status', params: {'p_queue_id': queueId});
      return QueueServiceResult.success(TokenStatus.fromJson(_asMap(data)));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] getTokenStatus error: $e');
      return QueueServiceResult.failure('Failed to load token status.');
    }
  }

  // ── Authenticated RPCs (dashboard) ───────────────────────

  Future<QueueServiceResult<QueueToday>> getQueueToday(
      String hospitalId) async {
    try {
      final data = await _client
          .rpc('get_queue_today', params: {'p_hospital_id': hospitalId});

      final map = _asMap(data);
      debugPrint('[QueueService] get_queue_today raw keys: ${map.keys}');

      return QueueServiceResult.success(QueueToday.fromJson(map));
    } on PostgrestException catch (e) {
      debugPrint('[QueueService] getQueueToday PostgrestException: '
          'code=${e.code} msg=${e.message} details=${e.details}');
      return QueueServiceResult.failure(_pgError(e));
    } catch (e, st) {
      debugPrint('[QueueService] getQueueToday error: $e\n$st');
      // Surface the real error message so it's visible in the UI
      return QueueServiceResult.failure('Queue load failed: $e');
    }
  }

  Future<QueueServiceResult<Map<String, dynamic>>> callNextToken(
      String hospitalId) async {
    try {
      final data = await _client
          .rpc('call_next_token', params: {'p_hospital_id': hospitalId});
      final map = _asMap(data);
      if (map['success'] == false) {
        return QueueServiceResult.failure(
            map['message'] as String? ?? 'No more patients.');
      }
      return QueueServiceResult.success(map);
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] callNextToken error: $e');
      return QueueServiceResult.failure('Failed to call next token.');
    }
  }

  Future<QueueServiceResult<void>> completeToken(String entryId) async {
    try {
      await _client.rpc('complete_token', params: {'p_entry_id': entryId});
      return QueueServiceResult.success(null);
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] completeToken error: $e');
      return QueueServiceResult.failure('Failed to complete token.');
    }
  }

  Future<QueueServiceResult<void>> skipToken(String entryId) async {
    try {
      await _client.rpc('skip_token', params: {'p_entry_id': entryId});
      return QueueServiceResult.success(null);
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] skipToken error: $e');
      return QueueServiceResult.failure('Failed to skip token.');
    }
  }

  Future<QueueServiceResult<void>> updateSettings({
    required String hospitalId,
    int? tokenLimit,
    int? avgTimePerPatient,
    int? alertBefore,
    String? workingHoursStart,
    String? workingHoursEnd,
    bool? enableAge,
    bool? enableReason,
    List<Map<String, dynamic>>? customFields,
    // Token format
    String? tokenPrefix,
    String? tokenFormat,
    int? tokenPadding,
  }) async {
    try {
      await _client.rpc('update_hospital_settings', params: {
        'p_hospital_id':          hospitalId,
        'p_token_limit':          tokenLimit,
        'p_avg_time_per_patient': avgTimePerPatient,
        'p_alert_before':         alertBefore,
        'p_working_hours_start':  workingHoursStart,
        'p_working_hours_end':    workingHoursEnd,
        'p_enable_age':           enableAge,
        'p_enable_reason':        enableReason,
        'p_custom_fields':        customFields,
        'p_token_prefix':         tokenPrefix,
        'p_token_format':         tokenFormat,
        'p_token_padding':        tokenPadding,
      });
      return QueueServiceResult.success(null);
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      return QueueServiceResult.failure('Failed to update settings.');
    }
  }

  Future<QueueServiceResult<void>> resetQueueToday(
      String hospitalId) async {
    try {
      await _client
          .rpc('reset_queue_today', params: {'p_hospital_id': hospitalId});
      return QueueServiceResult.success(null);
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      return QueueServiceResult.failure('Failed to reset queue.');
    }
  }

  // ── Realtime subscriptions ────────────────────────────────

  RealtimeChannel subscribeToQueueEntries({
    required String hospitalId,
    required void Function() onAnyChange,
  }) {
    return _client
        .channel('qe_$hospitalId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'queue_entries',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'hospital_id',
            value:  hospitalId,
          ),
          callback: (_) => onAnyChange(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToDailyState({
    required String hospitalId,
    required void Function(Map<String, dynamic> row) onUpdate,
  }) {
    return _client
        .channel('ds_$hospitalId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  'queue_daily_state',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'hospital_id',
            value:  hospitalId,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }

  // ── Step 5: TV Display, Analytics, Patients ──────────────

  /// TV display data — public / anon access
  Future<QueueServiceResult<Map<String, dynamic>>> getTvDisplay(
      String hospitalId) async {
    try {
      final data = await _client
          .rpc('get_tv_display', params: {'p_hospital_id': hospitalId});
      return QueueServiceResult.success(_asMap(data));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] getTvDisplay error: $e');
      return QueueServiceResult.failure('Failed to load display data.');
    }
  }

  /// Analytics for date range — authenticated
  Future<QueueServiceResult<Map<String, dynamic>>> getAnalytics({
    required String hospitalId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    try {
      final data = await _client.rpc('get_analytics', params: {
        'p_hospital_id': hospitalId,
        'p_date_from':   dateFrom.toIso8601String().substring(0, 10),
        'p_date_to':     dateTo.toIso8601String().substring(0, 10),
      });
      return QueueServiceResult.success(_asMap(data));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] getAnalytics error: $e');
      return QueueServiceResult.failure('Failed to load analytics.');
    }
  }

  /// Grouped patient list — authenticated
  Future<QueueServiceResult<Map<String, dynamic>>> getPatients({
    required String hospitalId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final data = await _client.rpc('get_patients', params: {
        'p_hospital_id': hospitalId,
        'p_date_from':   dateFrom?.toIso8601String().substring(0, 10),
        'p_date_to':     dateTo?.toIso8601String().substring(0, 10),
        'p_search':      search?.isEmpty == true ? null : search,
        'p_limit':       limit,
        'p_offset':      offset,
      });
      return QueueServiceResult.success(_asMap(data));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      debugPrint('[QueueService] getPatients error: $e');
      return QueueServiceResult.failure('Failed to load patients.');
    }
  }

  /// Single patient visit history — authenticated
  Future<QueueServiceResult<Map<String, dynamic>>> getPatientHistory({
    required String hospitalId,
    required String phone,
  }) async {
    try {
      final data = await _client.rpc('get_patient_history', params: {
        'p_hospital_id':   hospitalId,
        'p_patient_phone': phone,
      });
      return QueueServiceResult.success(_asMap(data));
    } on PostgrestException catch (e) {
      return QueueServiceResult.failure(_pgError(e));
    } catch (e) {
      return QueueServiceResult.failure('Failed to load patient history.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  Map<String, dynamic> _asMap(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  String _pgError(PostgrestException e) {
    final msg = e.message;
    if (msg.contains('UNAUTHORIZED'))      return 'Permission denied. Make sure you own this hospital.';
    if (msg.contains('not found'))         return 'Record not found.';
    if (msg.contains('Cannot complete'))   return 'Cannot complete this entry.';
    if (msg.contains('does not exist'))    return 'Database function missing. Please run step3_schema.sql in Supabase.';
    return 'Database error: $msg';
  }
}

// ── Typed result ──────────────────────────────────────────

class QueueServiceResult<T> {
  final T? data;
  final String? error;

  const QueueServiceResult._({this.data, this.error});

  factory QueueServiceResult.success(T data) =>
      QueueServiceResult._(data: data);

  factory QueueServiceResult.failure(String msg) =>
      QueueServiceResult._(error: msg);

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}