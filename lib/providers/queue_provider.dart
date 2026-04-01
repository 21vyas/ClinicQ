// lib/providers/queue_provider.dart

import 'dart:async';
import 'package:clinic_q/models/queue_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/queue_service.dart';
import '../models/queue_today.dart';
import '../models/token_status.dart';
import '../models/hospital_full.dart';

// ── Service provider ──────────────────────────────────────

final queueServiceProvider =
    Provider<QueueService>((ref) => QueueService());

// ── Realtime connection status ────────────────────────────

enum RealtimeStatus { connecting, connected, disconnected }

// ── Hospital full (check-in page, public) ─────────────────

final hospitalFullProvider =
    FutureProvider.family<HospitalFull?, String>((ref, hospitalId) async {
  final result = await ref.read(queueServiceProvider).getHospitalFull(hospitalId);
  if (result.isFailure) throw Exception(result.error);
  return result.data;
});

// ─────────────────────────────────────────────────────────
// TOKEN STATUS NOTIFIER
// For the patient-facing /token/:queueId page.
// Subscribes to BOTH queue_entries and daily_state so
// it catches both status changes and position shifts.
// ─────────────────────────────────────────────────────────

class TokenStatusNotifier extends StateNotifier<AsyncValue<TokenStatus?>> {
  final QueueService _svc;
  final String _queueId;

  RealtimeChannel? _entriesChannel;
  RealtimeChannel? _dailyChannel;
  Timer? _pollTimer;            // fallback poll every 30 s
  String? _hospitalId;          // set after first load

  RealtimeStatus connectionStatus = RealtimeStatus.connecting;

  TokenStatusNotifier(this._svc, this._queueId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  // ── Load ─────────────────────────────────────────────────

  Future<void> _load() async {
    final result = await _svc.getTokenStatus(_queueId);
    if (!mounted) return;

    if (result.isFailure) {
      state = AsyncValue.error(result.error!, StackTrace.current);
      return;
    }

    state = AsyncValue.data(result.data);

    // Subscribe to realtime once we know the hospitalId
    final hospitalId = result.data!.hospitalId;
    if (_hospitalId == null) {
      _hospitalId = hospitalId;
      _subscribeRealtime(hospitalId);
      _startFallbackPoll();
    }
  }

  // ── Realtime ─────────────────────────────────────────────

  void _subscribeRealtime(String hospitalId) {
    // 1. Listen to queue_entries (status changes for this patient)
    _entriesChannel = _svc.subscribeToQueueEntries(
      hospitalId:  hospitalId,
      onAnyChange: _load,
    );

    // 2. Listen to daily_state (current token advances)
    _dailyChannel = _svc.subscribeToDailyState(
      hospitalId: hospitalId,
      onUpdate:   (_) => _load(),
    );

    connectionStatus = RealtimeStatus.connected;
  }

  // 30-second fallback poll for browsers that block WebSocket
  void _startFallbackPoll() {
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load();
    });
  }

  Future<void> refresh() => _load();

  @override
  void dispose() {
    _entriesChannel?.unsubscribe();
    _dailyChannel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }
}

final tokenStatusProvider = StateNotifierProvider.family<
    TokenStatusNotifier, AsyncValue<TokenStatus?>, String>(
  (ref, queueId) =>
      TokenStatusNotifier(ref.read(queueServiceProvider), queueId),
);

// ─────────────────────────────────────────────────────────
// QUEUE TODAY NOTIFIER
// For the authenticated dashboard.
// Drives the full queue list + real-time updates.
// ─────────────────────────────────────────────────────────

class QueueTodayNotifier extends StateNotifier<AsyncValue<QueueToday?>> {
  final QueueService _svc;
  final String _hospitalId;

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _isActionInProgress = false;

  QueueTodayNotifier(this._svc, this._hospitalId)
      : super(const AsyncValue.loading()) {
    _load();
    _subscribeRealtime();
    _startFallbackPoll();
  }

  // ── Load (silent refresh — keeps existing data while fetching) ──

  Future<void> _load({bool silent = true}) async {
    final existing = state.maybeWhen(data: (v) => v, orElse: () => null);
    if (silent && existing != null) {
      // Don't flash loading spinner on background refreshes
    } else {
      state = const AsyncValue.loading();
    }

    final result = await _svc.getQueueToday(_hospitalId);
    if (!mounted) return;

    if (result.isFailure) {
      // Keep old data visible on transient errors
      final previous = state.maybeWhen(data: (v) => v, orElse: () => null);
      if (previous == null) {
        state = AsyncValue.error(result.error!, StackTrace.current);
      }
      return;
    }
    state = AsyncValue.data(result.data);
  }

  // ── Realtime ─────────────────────────────────────────────

  void _subscribeRealtime() {
    _channel = _svc.subscribeToQueueEntries(
      hospitalId:  _hospitalId,
      onAnyChange: () {
        if (!_isActionInProgress) _load();
      },
    );
  }

  void _startFallbackPoll() {
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_isActionInProgress) _load();
    });
  }

  // ── Public actions ────────────────────────────────────────

  Future<void> refresh() => _load(silent: false);

  /// Call next patient: mark current as done + set next as in_progress
  Future<String?> callNext() async {
    _isActionInProgress = true;
    try {
      final result = await _svc.callNextToken(_hospitalId);
      if (result.isFailure) return result.error;
      await _load();
      return null;
    } finally {
      _isActionInProgress = false;
    }
  }

  /// Complete current in_progress entry WITHOUT calling next
  Future<String?> completeToken(String entryId) async {
    _isActionInProgress = true;
    try {
      // Optimistic update
      final current = state.maybeWhen(data: (v) => v, orElse: () => null);
      if (current != null) {
        final updated = current.entries.map((e) {
          if (e.id == entryId) return e.copyWith(status: QueueStatus.done);
          return e;
        }).toList();
        state = AsyncValue.data(QueueToday(
          entries:             updated,
          currentTokenNumber:  current.currentTokenNumber,
          lastTokenNumber:     current.lastTokenNumber,
          totalServed:         current.totalServed + 1,
          avgActualWait:       current.avgActualWait,
          avgTimeSetting:      current.avgTimeSetting,
          counts:              current.counts,
          queueDate:           current.queueDate,
        ));
      }

      final result = await _svc.completeToken(entryId);
      if (result.isFailure) {
        await _load(); // revert on error
        return result.error;
      }
      await _load();
      return null;
    } finally {
      _isActionInProgress = false;
    }
  }

  /// Skip an entry
  Future<String?> skipEntry(String entryId) async {
    _isActionInProgress = true;
    try {
      // Optimistic update
      _applyOptimisticStatus(entryId, QueueStatus.skipped);

      final result = await _svc.skipToken(entryId);
      if (result.isFailure) {
        await _load();
        return result.error;
      }
      await _load();
      return null;
    } finally {
      _isActionInProgress = false;
    }
  }

  /// Reset today's entire queue
  Future<String?> resetQueue() async {
    _isActionInProgress = true;
    try {
      final result = await _svc.resetQueueToday(_hospitalId);
      if (result.isFailure) return result.error;
      await _load(silent: false);
      return null;
    } finally {
      _isActionInProgress = false;
    }
  }

  void _applyOptimisticStatus(String entryId, QueueStatus newStatus) {
    final current = state.maybeWhen(data: (v) => v, orElse: () => null);
    if (current == null) return;
    final updated = current.entries.map((e) {
      if (e.id == entryId) return e.copyWith(status: newStatus);
      return e;
    }).toList();
    state = AsyncValue.data(QueueToday(
      entries:            updated,
      currentTokenNumber: current.currentTokenNumber,
      lastTokenNumber:    current.lastTokenNumber,
      totalServed:        current.totalServed,
      avgActualWait:      current.avgActualWait,
      avgTimeSetting:     current.avgTimeSetting,
      counts:             current.counts,
      queueDate:          current.queueDate,
    ));
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }
}

final queueTodayProvider = StateNotifierProvider.family<
    QueueTodayNotifier, AsyncValue<QueueToday?>, String>(
  (ref, hospitalId) =>
      QueueTodayNotifier(ref.read(queueServiceProvider), hospitalId),
);