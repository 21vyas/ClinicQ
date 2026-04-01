// lib/screens/patients_page.dart
//
// Authenticated route: /patients
// Shows all patients grouped by phone number.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/analytics_data.dart';
import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';

// ─────────────────────────────────────────────────────────
// Date filter enum
// ─────────────────────────────────────────────────────────

enum PatientFilter { today, week, allTime }

extension PatientFilterExt on PatientFilter {
  String get label => switch (this) {
    PatientFilter.today   => 'Today',
    PatientFilter.week    => 'This Week',
    PatientFilter.allTime => 'All Time',
  };

  (DateTime?, DateTime?) get dates {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      PatientFilter.today   => (today, today),
      PatientFilter.week    => (today.subtract(const Duration(days: 6)), today),
      PatientFilter.allTime => (null, null),
    };
  }
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

class _PatientsQuery {
  final String hospitalId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? search;
  const _PatientsQuery({required this.hospitalId,
      this.dateFrom, this.dateTo, this.search});

  @override
  bool operator ==(Object other) =>
      other is _PatientsQuery &&
      hospitalId == other.hospitalId &&
      dateFrom   == other.dateFrom &&
      dateTo     == other.dateTo &&
      search     == other.search;

  @override
  int get hashCode => Object.hash(hospitalId, dateFrom, dateTo, search);
}

final _patientsProvider =
    FutureProvider.family<PatientsResult, _PatientsQuery>((ref, q) async {
  final svc = ref.read(queueServiceProvider);
  final result = await svc.getPatients(
    hospitalId: q.hospitalId,
    dateFrom:   q.dateFrom,
    dateTo:     q.dateTo,
    search:     q.search?.isEmpty == true ? null : q.search,
  );
  if (result.isFailure) throw Exception(result.error);
  return PatientsResult.fromJson(result.data!);
});

// ─────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────

class PatientsPage extends ConsumerStatefulWidget {
  final String hospitalId;
  const PatientsPage({super.key, required this.hospitalId});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> {
  PatientFilter _filter    = PatientFilter.allTime;
  String        _search    = '';
  Timer?        _debounce;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _search = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hospitalId.isNotEmpty) return _buildScaffold(widget.hospitalId);

    // Fallback: hospitalId not passed via navigation (e.g. deep link / refresh)
    final hospitalAsync = ref.watch(hospitalProvider);
    return hospitalAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (hospital) {
        if (hospital == null) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.go('/dashboard'));
          return const SizedBox.shrink();
        }
        return _buildScaffold(hospital.id);
      },
    );
  }

  Widget _buildScaffold(String hospitalId) {
    final (from, to) = _filter.dates;
    final query = _PatientsQuery(
      hospitalId: hospitalId,
      dateFrom:   from,
      dateTo:     to,
      search:     _search.isEmpty ? null : _search,
    );
    final patientsAsync = ref.watch(_patientsProvider(query));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Search bar
          _SearchBar(ctrl: _searchCtrl, onChanged: _onSearchChanged),
          // Filter chips
          _FilterBar(selected: _filter, onSelect: (f) => setState(() => _filter = f)),
          Container(height: 1, color: AppColors.border),

          // Patient list
          Expanded(
            child: patientsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 40),
                  const SizedBox(height: 12),
                  Text('$e', textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(_patientsProvider(query)),
                    child: const Text('Retry'),
                  ),
                ],
              )),
              data: (result) => _PatientList(
                result:     result,
                hospitalId: hospitalId,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppColors.surface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
      onPressed: () => context.go('/dashboard'),
      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary),
    ),
    title: Text('Patients', style: GoogleFonts.dmSans(
        fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    actions: [
      IconButton(
        onPressed: () => context.go('/analytics'),
        icon: const Icon(Icons.bar_chart_rounded, size: 20, color: AppColors.textSecondary),
        tooltip: 'Analytics',
      ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: AppColors.border),
    ),
  );
}

// ─────────────────────────────────────────────────────────
// SEARCH BAR
// ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final void Function(String) onChanged;
  const _SearchBar({required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: TextFormField(
      controller:  ctrl,
      onChanged:   onChanged,
      style: GoogleFonts.dmSans(fontSize: 14),
      decoration: InputDecoration(
        hintText:    'Search by name or phone...',
        hintStyle:   GoogleFonts.dmSans(fontSize: 14, color: AppColors.textHint),
        prefixIcon:  const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
        suffixIcon:  ctrl.text.isNotEmpty
            ? IconButton(
                onPressed: () { ctrl.clear(); onChanged(''); },
                icon: const Icon(Icons.clear_rounded, size: 18),
              )
            : null,
        filled:          true,
        fillColor:       AppColors.surfaceVariant,
        contentPadding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border:       OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final PatientFilter selected;
  final void Function(PatientFilter) onSelect;
  const _FilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(
      children: PatientFilter.values.map((f) {
        final isSelected = f == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onSelect(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(f.label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textSecondary)),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

// ─────────────────────────────────────────────────────────
// PATIENT LIST
// ─────────────────────────────────────────────────────────

class _PatientList extends ConsumerWidget {
  final PatientsResult result;
  final String hospitalId;
  const _PatientList({required this.result, required this.hospitalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (result.patients.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No patients found',
              style: GoogleFonts.dmSans(fontSize: 16, color: AppColors.textHint)),
        ]),
      );
    }

    return Column(
      children: [
        // Total count bar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('${result.total} patient${result.total == 1 ? '' : 's'}',
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ]),
        ),
        Container(height: 1, color: AppColors.border),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: result.patients.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _PatientCard(
              patient:    result.patients[i],
              hospitalId: hospitalId,
              onTap: () => _showHistory(context, ref,
                  hospitalId, result.patients[i]),
            ),
          ),
        ),
      ],
    );
  }

  void _showHistory(BuildContext context, WidgetRef ref,
      String hospitalId, PatientRecord patient) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PatientHistorySheet(
          patient: patient, hospitalId: hospitalId),
    );
  }
}

// ─────────────────────────────────────────────────────────
// PATIENT CARD
// ─────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final PatientRecord patient;
  final String hospitalId;
  final VoidCallback onTap;
  const _PatientCard({
    required this.patient, required this.hospitalId, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: _avatarColor(patient.name).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(patient.name),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _avatarColor(patient.name),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(patient.name,
                          style: GoogleFonts.dmSans(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (patient.isReturning)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Returning',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.phone_outlined, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(patient.phone,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ]),
                  if (patient.lastReason != null) ...[
                    const SizedBox(height: 2),
                    Text('Last: ${patient.lastReason}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),

            // Visit count + date
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  const Icon(Icons.history_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('${patient.visitCount} visit${patient.visitCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
                const SizedBox(height: 4),
                Text(_fmtDate(patient.lastVisit),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
                const SizedBox(height: 2),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  Color _avatarColor(String name) {
    final colors = [
      AppColors.primary, const Color(0xFF6366F1), AppColors.accent,
      AppColors.success, const Color(0xFFEC4899),
    ];
    final index = name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  String _fmtDate(DateTime d) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date  = DateTime(d.year, d.month, d.day);
    final diff  = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7)  return '$diff days ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ─────────────────────────────────────────────────────────
// PATIENT HISTORY SHEET
// ─────────────────────────────────────────────────────────

class _PatientHistorySheet extends ConsumerWidget {
  final PatientRecord patient;
  final String hospitalId;
  const _PatientHistorySheet({required this.patient, required this.hospitalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface, shape: BoxShape.circle),
                    child: Center(child: Text(
                      patient.name.isEmpty ? '?' : patient.name[0].toUpperCase(),
                      style: GoogleFonts.dmSans(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.name, style: GoogleFonts.dmSans(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(patient.phone,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${patient.visitCount} visits',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(height: 1, color: AppColors.border),
              ],
            ),
          ),

          // Visit history loaded via FutureProvider
          Expanded(
            child: _VisitHistoryList(
                hospitalId: hospitalId, phone: patient.phone),
          ),
        ],
      ),
    );
  }
}

class _VisitHistoryList extends ConsumerWidget {
  final String hospitalId;
  final String phone;
  const _VisitHistoryList({required this.hospitalId, required this.phone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(_historyProvider(
        _HistoryKey(hospitalId, phone)));

    return histAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
          child: Text('Failed to load history', style: const TextStyle(
              color: AppColors.textSecondary))),
      data: (visits) => visits.isEmpty
          ? const Center(child: Text('No visit history'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: visits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _VisitTile(visit: visits[i]),
            ),
    );
  }
}

class _HistoryKey {
  final String hospitalId;
  final String phone;
  const _HistoryKey(this.hospitalId, this.phone);
}

final _historyProvider = FutureProvider.family<List<Map<String, dynamic>>, _HistoryKey>(
    (ref, key) async {
  final svc = ref.read(queueServiceProvider);
  final result = await svc.getPatientHistory(
      hospitalId: key.hospitalId, phone: key.phone);
  if (result.isFailure) throw Exception(result.error);
  final raw = result.data!['visits'] as List<dynamic>? ?? [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
});

class _VisitTile extends StatelessWidget {
  final Map<String, dynamic> visit;
  const _VisitTile({required this.visit});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(visit['queue_date'] as String? ?? '');
    final status = visit['status'] as String? ?? '';
    final token  = visit['token_number'];
    final reason = visit['reason'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text('#$token',
              style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.primary))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date != null ? '${date.day}/${date.month}/${date.year}' : '',
                style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            if (reason != null)
              Text(reason, style: const TextStyle(
                  fontSize: 11, color: AppColors.textHint),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _statusColor(status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_statusLabel(status),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  color: _statusColor(status))),
        ),
      ]),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'done'        => AppColors.success,
    'in_progress' => AppColors.primary,
    'skipped'     => AppColors.warning,
    _             => AppColors.textHint,
  };

  String _statusLabel(String s) => switch (s) {
    'done'        => 'Done',
    'in_progress' => 'In Progress',
    'skipped'     => 'Skipped',
    'waiting'     => 'Waiting',
    _             => s,
  };
}