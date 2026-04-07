// lib/screens/analytics_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/analytics_data.dart';
import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';

enum AnalyticsRange { today, week, month, custom }

extension AnalyticsRangeExt on AnalyticsRange {
  String get label => switch (this) {
        AnalyticsRange.today  => 'Today',
        AnalyticsRange.week   => '7 Days',
        AnalyticsRange.month  => '30 Days',
        AnalyticsRange.custom => 'Custom',
      };

  (DateTime, DateTime) get dates {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      AnalyticsRange.today  => (today, today),
      AnalyticsRange.week   => (today.subtract(const Duration(days: 6)), today),
      AnalyticsRange.month  => (today.subtract(const Duration(days: 29)), today),
      AnalyticsRange.custom => (today, today),
    };
  }
}

class _AnalyticsParams {
  final String hospitalId;
  final DateTime dateFrom;
  final DateTime dateTo;
  const _AnalyticsParams(this.hospitalId, this.dateFrom, this.dateTo);

  @override
  bool operator ==(Object other) =>
      other is _AnalyticsParams &&
      hospitalId == other.hospitalId &&
      dateFrom   == other.dateFrom &&
      dateTo     == other.dateTo;

  @override
  int get hashCode => Object.hash(hospitalId, dateFrom, dateTo);
}

final _analyticsProvider =
    FutureProvider.family<AnalyticsData, _AnalyticsParams>((ref, p) async {
  final svc = ref.read(queueServiceProvider);
  final result = await svc.getAnalytics(
    hospitalId: p.hospitalId,
    dateFrom:   p.dateFrom,
    dateTo:     p.dateTo,
  );
  if (result.isFailure) throw Exception(result.error);
  return AnalyticsData.fromJson(result.data!);
});

class AnalyticsPage extends ConsumerStatefulWidget {
  final String hospitalId;
  const AnalyticsPage({super.key, required this.hospitalId});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  AnalyticsRange _range = AnalyticsRange.today;
  DateTime? _customFrom;
  DateTime? _customTo;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fadeCtrl.forward();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  (DateTime, DateTime) get _activeDates {
    if (_range == AnalyticsRange.custom && _customFrom != null && _customTo != null) {
      return (_customFrom!, _customTo!);
    }
    return _range.dates;
  }

  void _setRange(AnalyticsRange r) {
    setState(() => _range = r);
    _fadeCtrl.forward(from: 0);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context, firstDate: DateTime(now.year - 1), lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customFrom ?? now.subtract(const Duration(days: 7)),
        end:   _customTo   ?? now,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customFrom = picked.start;
        _customTo   = picked.end;
        _range      = AnalyticsRange.custom;
      });
      _fadeCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    String hId = widget.hospitalId;
    if (hId.isEmpty) {
      final hospitalAsync = ref.watch(hospitalProvider);
      return hospitalAsync.when(
        data: (hospital) {
          if (hospital == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/dashboard'));
            return const SizedBox.shrink();
          }
          return _buildScaffold(hospital.id);
        },
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      );
    }
    return _buildScaffold(hId);
  }

  Widget _buildScaffold(String hospitalId) {
    final (dateFrom, dateTo) = _activeDates;
    final analyticsAsync = ref.watch(_analyticsProvider(_AnalyticsParams(hospitalId, dateFrom, dateTo)));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => context.go('/dashboard'),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary)),
        title: Text('Analytics', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            onPressed: () => context.go('/patients/$hospitalId'),
            icon: const Icon(Icons.people_outline_rounded, size: 20, color: AppColors.textSecondary),
            tooltip: 'Patients',
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: SafeArea(
        child: Column(children: [
          _RangeSelector(selected: _range, onSelect: _setRange, onCustom: _pickCustomRange, customFrom: _customFrom, customTo: _customTo),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: analyticsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (data) => data.totalPatients == 0
                  ? const Center(child: Text('No data found for this range'))
                  : FadeTransition(opacity: _fadeCtrl, child: _AnalyticsContent(data: data)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final AnalyticsRange selected;
  final void Function(AnalyticsRange) onSelect;
  final VoidCallback onCustom;
  final DateTime? customFrom, customTo;
  const _RangeSelector({required this.selected, required this.onSelect, required this.onCustom, this.customFrom, this.customTo});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      ...AnalyticsRange.values.where((r) => r != AnalyticsRange.custom).map((r) {
        final isSel = selected == r;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(r.label), selected: isSel,
            onSelected: (_) => onSelect(r),
            selectedColor: AppColors.primary, labelStyle: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary),
          ),
        );
      }),
      ActionChip(
        label: Text(selected == AnalyticsRange.custom && customFrom != null ? '${customFrom!.day}/${customFrom!.month} - ${customTo!.day}/${customTo!.month}' : 'Custom'),
        onPressed: onCustom, backgroundColor: selected == AnalyticsRange.custom ? AppColors.primary : null,
        labelStyle: TextStyle(color: selected == AnalyticsRange.custom ? Colors.white : null),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────
// ANALYTICS CONTENT
// ─────────────────────────────────────────────────────────

class _AnalyticsContent extends StatelessWidget {
  final AnalyticsData data;
  const _AnalyticsContent({required this.data});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── KPI grid ──────────────────────────────
                _KpiGrid(data: data),
                const SizedBox(height: 16),

                // ── Visit type ────────────────────────────
                if (data.visitTypeDist.isNotEmpty) ...[
                  _SectionCard(
                    title: 'Visit Type Distribution',
                    child: _VisitTypeChart(data: data),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Peak hours ────────────────────────────
                if (data.peakHours.isNotEmpty) ...[
                  _SectionCard(
                    title: 'Peak Hours',
                    child: _PeakHoursChart(data: data),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Top reasons ───────────────────────────
                if (data.topReasons.isNotEmpty) ...[
                  _SectionCard(
                    title: 'Top Visit Reasons',
                    child: _TopReasonsChart(data: data),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Daily trend ───────────────────────────
                if (data.dailyTotals.length > 1) ...[
                  _SectionCard(
                    title: 'Daily Trend',
                    child: _DailyTrendChart(data: data),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Responsive KPI grid ───────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final AnalyticsData data;
  const _KpiGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w    = constraints.maxWidth;
      final cols = w >= 600 ? 4 : 2;

      final cards = [
        _KpiCard(
          label: 'Total Patients',
          value: '${data.totalPatients}',
          icon: Icons.people_outline_rounded,
          color: AppColors.primary,
        ),
        _KpiCard(
          label: 'Completed',
          value: '${data.totalDone}',
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.success,
          subtitle: data.totalPatients > 0
              ? '${(data.completionRate * 100).round()}% rate'
              : null,
        ),
        _KpiCard(
          label: 'Avg Wait',
          value: data.avgWaitMins > 0 ? '${data.avgWaitMins}m' : '—',
          icon: Icons.schedule_rounded,
          color: const Color(0xFF6366F1),
        ),
        _KpiCard(
          label: 'Peak Hour',
          value: data.busiesHour?.label ?? '—',
          icon: Icons.trending_up_rounded,
          color: AppColors.accent,
          subtitle: data.busiesHour != null
              ? '${data.busiesHour!.count} patients'
              : null,
        ),
      ];

      // Build rows of `cols` cards — IntrinsicHeight lets cards size naturally
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        final rowCards = cards.sublist(i, (i + cols).clamp(0, cards.length));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < rowCards.length; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(child: rowCards[j]),
              ],
              // Fill empty slots in last row
              for (var k = rowCards.length; k < cols; k++) ...[
                const SizedBox(width: 12),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ));
        if (i + cols < cards.length) rows.add(const SizedBox(height: 12));
      }
      return Column(children: rows);
    });
  }
}

// ── KPI card ──────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.07),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.1)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textHint)),
      ],
    ),
  );
}

// ── Section card wrapper ──────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

// ── Visit type distribution ───────────────────────────────

class _VisitTypeChart extends StatelessWidget {
  final AnalyticsData data;
  const _VisitTypeChart({required this.data});

  static const _colors = [
    AppColors.primary,
    AppColors.accent,
    AppColors.success,
    Color(0xFF6366F1),
    AppColors.error,
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.visitTypeDist.fold(0, (s, v) => s + v.count);
    return Column(
      children: data.visitTypeDist.asMap().entries.map((e) {
        final stat  = e.value;
        final color = _colors[e.key % _colors.length];
        final pct   = total == 0 ? 0.0 : stat.count / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(stat.label,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                  ]),
                  Text('${stat.count} (${(pct * 100).round()}%)',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 7,
                    backgroundColor: AppColors.surfaceVariant,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Peak hours bar chart ──────────────────────────────────

class _PeakHoursChart extends StatelessWidget {
  final AnalyticsData data;
  const _PeakHoursChart({required this.data});

  static const _chartH = 90.0;
  static const _barMax  = 74.0; // leaves 16px headroom for label + gap

  @override
  Widget build(BuildContext context) {
    final maxCount    = data.maxHourCount;
    final clinicHours = List.generate(13, (i) => i + 8); // 8am–8pm

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: clinicHours.map((hour) {
              final match  = data.peakHours.where((h) => h.hour == hour).toList();
              final count  = match.isEmpty ? 0 : match.first.count;
              final frac   = maxCount == 0 ? 0.0 : count / maxCount;
              final isPeak = data.busiesHour?.hour == hour;
              final barColor = isPeak
                  ? AppColors.accent
                  : AppColors.primary.withValues(alpha: 0.45 + 0.45 * frac);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  // Stack: bar grows from bottom, label floats above it.
                  // No Column stacking → no overflow possible.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (_, v, _) {
                      final barH = _barMax * v + 2;
                      return Stack(
                        alignment: Alignment.bottomCenter,
                        clipBehavior: Clip.none,
                        children: [
                          // Bar
                          Container(
                            height: barH,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                          // Count label positioned above the bar
                          if (count > 0)
                            Positioned(
                              bottom: barH + 2,
                              left: 0,
                              right: 0,
                              child: Text(
                                '$count',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: isPeak
                                      ? AppColors.accent
                                      : AppColors.textHint,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['8am', '10am', '12pm', '2pm', '4pm', '6pm', '8pm']
              .map((t) => Text(t,
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textHint)))
              .toList(),
        ),
      ],
    );
  }
}

// ── Top reasons list ──────────────────────────────────────

class _TopReasonsChart extends StatelessWidget {
  final AnalyticsData data;
  const _TopReasonsChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxCount = data.topReasons.isEmpty
        ? 1
        : data.topReasons.map((r) => r.count).reduce((a, b) => a > b ? a : b);

    return Column(
      children: data.topReasons.asMap().entries.map((e) {
        final r    = e.value;
        final frac = r.count / maxCount;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(
              width: 20,
              child: Text('${e.key + 1}.',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(r.reason,
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${r.count}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (_, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceVariant,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ── Daily trend bar chart ─────────────────────────────────

class _DailyTrendChart extends StatelessWidget {
  final AnalyticsData data;
  const _DailyTrendChart({required this.data});

  static const _colorBusiest  = AppColors.accent;           // orange
  static const _colorAboveAvg = AppColors.primary;          // teal
  static const _colorBelowAvg = Color(0xFF6366F1);          // indigo

  Color _barColor(int total, int maxTotal, double avg) {
    if (total == maxTotal) return _colorBusiest;
    if (total >= avg)      return _colorAboveAvg;
    return _colorBelowAvg;
  }

  // Show d/m for ≤14 bars, day-only for more (avoids crowding)
  String _dateLabel(DateTime d, int count) =>
      count <= 14 ? '${d.day}/${d.month}' : '${d.day}';

  @override
  Widget build(BuildContext context) {
    final maxTotal = data.dailyTotals.isEmpty
        ? 1
        : data.dailyTotals.map((d) => d.total).reduce((a, b) => a > b ? a : b);
    final avg = data.dailyTotals.isEmpty
        ? 0.0
        : data.dailyTotals.fold(0, (s, d) => s + d.total) /
          data.dailyTotals.length;
    final n = data.dailyTotals.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(color: _colorBusiest,  label: 'Busiest day'),
            _LegendDot(color: _colorAboveAvg, label: 'Above avg'),
            _LegendDot(color: _colorBelowAvg, label: 'Below avg'),
          ],
        ),
        const SizedBox(height: 12),

        // Bars — each column has bar + count label + date label
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.dailyTotals.map((d) {
            final frac  = maxTotal == 0 ? 0.0 : d.total / maxTotal;
            final color = _barColor(d.total, maxTotal, avg);
            final label = _dateLabel(d.date, n);

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Count above bar (only for busiest + above-avg to avoid clutter)
                    if (d.total == maxTotal || d.total >= avg)
                      Text(
                        '${d.total}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      )
                    else
                      const SizedBox(height: 10),
                    const SizedBox(height: 2),

                    // Bar
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: frac),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (_, v, _) => Container(
                        height: 60 * v + 2,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.65 + 0.35 * v),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Date label below bar — same colour as bar
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: n <= 10 ? 9 : 7,
                        fontWeight: d.total == maxTotal
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: d.total == maxTotal
                            ? color
                            : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9, height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textHint)),
    ],
  );
}
