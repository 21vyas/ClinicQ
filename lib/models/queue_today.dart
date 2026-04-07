// lib/models/queue_today.dart

import 'queue_entry.dart';

class QueueToday {
  final List<QueueEntry> entries;
  final int currentTokenNumber;
  final int lastTokenNumber;
  final int totalServed;
  final int avgActualWait;    // minutes — measured from real data
  final int avgTimeSetting;   // minutes — from hospital_settings
  final QueueCounts counts;
  final DateTime queueDate;

  const QueueToday({
    required this.entries,
    required this.currentTokenNumber,
    required this.lastTokenNumber,
    required this.totalServed,
    required this.avgActualWait,
    required this.avgTimeSetting,
    required this.counts,
    required this.queueDate,
  });

  factory QueueToday.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    return QueueToday(
      entries: rawEntries
          .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentTokenNumber: (json['current_token_number'] as num?)?.toInt() ?? 0,
      lastTokenNumber:    (json['last_token_number']    as num?)?.toInt() ?? 0,
      totalServed:        (json['total_served']         as num?)?.toInt() ?? 0,
      avgActualWait:      (json['avg_actual_wait']      as num?)?.toInt() ?? 0,
      avgTimeSetting:     (json['avg_time_setting']     as num?)?.toInt() ?? 5,
      counts: QueueCounts.fromJson(
          json['counts'] as Map<String, dynamic>? ?? {}),
      queueDate: DateTime.parse(
          json['queue_date'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  List<QueueEntry> get waitingEntries =>
      entries.where((e) => e.status == QueueStatus.waiting).toList();

  QueueEntry? get inProgressEntry =>
      entries.cast<QueueEntry?>().firstWhere(
        (e) => e?.status == QueueStatus.inProgress,
        orElse: () => null,
      );

  List<QueueEntry> get doneEntries =>
      entries.where((e) => e.status == QueueStatus.done).toList();

  List<QueueEntry> get skippedEntries =>
      entries.where((e) => e.status == QueueStatus.skipped).toList();

  /// Displayed wait time: use actual if available, fall back to setting
  int get effectiveAvgWait =>
      avgActualWait > 0 ? avgActualWait : avgTimeSetting;
}

class QueueCounts {
  final int total;
  final int waiting;
  final int inProgress;
  final int done;
  final int skipped;

  const QueueCounts({
    required this.total,
    required this.waiting,
    required this.inProgress,
    required this.done,
    required this.skipped,
  });

  factory QueueCounts.fromJson(Map<String, dynamic> json) {
    return QueueCounts(
      total:      (json['total']       as num?)?.toInt() ?? 0,
      waiting:    (json['waiting']     as num?)?.toInt() ?? 0,
      inProgress: (json['in_progress'] as num?)?.toInt() ?? 0,
      done:       (json['done']        as num?)?.toInt() ?? 0,
      skipped:    (json['skipped']     as num?)?.toInt() ?? 0,
    );
  }

  factory QueueCounts.empty() =>
      const QueueCounts(total: 0, waiting: 0, inProgress: 0, done: 0, skipped: 0);
}