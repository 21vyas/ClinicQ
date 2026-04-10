// lib/screens/tv_display_page.dart
//
// Public route: /tv/:hospitalId
// Full-screen live queue display for waiting room TV.
// No login required. Auto-refreshes every 4 seconds + realtime.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tv_display.dart';
import '../providers/queue_provider.dart';

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────

final tvDisplayProvider = StateNotifierProvider.family<
    _TvNotifier, AsyncValue<TvDisplay?>, String>(
  (ref, hospitalId) => _TvNotifier(ref.read(queueServiceProvider), hospitalId),
);

class _TvNotifier extends StateNotifier<AsyncValue<TvDisplay?>> {
  final dynamic _svc;
  final String _hospitalId;
  Timer? _timer;
  dynamic _channel;
  int? _lastToken;

  _TvNotifier(this._svc, this._hospitalId)
      : super(const AsyncValue.loading()) {
    _load();
    _startPoll();
    _subscribeRealtime();
  }

  Future<void> _load() async {
    final result = await _svc.getTvDisplay(_hospitalId);
    if (!mounted) return;
    if (result.isFailure) {
      if (state.asData?.value == null) {
        state = AsyncValue.error(result.error!, StackTrace.current);
      }
      return;
    }
    final display = TvDisplay.fromJson(result.data!);
    _lastToken = display.currentTokenNumber;
    state = AsyncValue.data(display);
  }

  void _startPoll() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load();
    });
  }

  void _subscribeRealtime() {
    _channel = _svc.subscribeToQueueEntries(
      hospitalId:  _hospitalId,
      onAnyChange: () { if (mounted) _load(); },
    );
  }

  bool get tokenChanged {
    final cur = state.asData?.value?.currentTokenNumber ?? 0;
    final changed = _lastToken != null && cur != _lastToken && cur > 0;
    return changed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────

class TvDisplayPage extends ConsumerStatefulWidget {
  final String hospitalId;
  const TvDisplayPage({super.key, required this.hospitalId});

  @override
  ConsumerState<TvDisplayPage> createState() => _TvDisplayPageState();
}

class _TvDisplayPageState extends ConsumerState<TvDisplayPage>
    with TickerProviderStateMixin {
  late AnimationController _flashCtrl;
  late Animation<double>   _flashAnim;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _tickCtrl;

  int? _prevToken;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();

    // Token flash on change
    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));

    // Continuous pulse on current token
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Tick animation for "live" dot
    _tickCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    // Clock ticker
    _clockTimer = Timer.periodic(const Duration(seconds: 30),
        (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    _pulseCtrl.dispose();
    _tickCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _onTokenChanged(int newToken) {
    if (newToken != _prevToken && newToken > 0) {
      _prevToken = newToken;
      _flashCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tvAsync = ref.watch(tvDisplayProvider(widget.hospitalId));

    return Scaffold(
      backgroundColor: const Color(0xFF080F0F),
      body: tvAsync.when(
        loading: () => _LoadingView(),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (tv) {
          if (tv == null) return _ErrorView(message: 'No data');
          _onTokenChanged(tv.currentTokenNumber);
          return _TvBody(
            tv:        tv,
            pulseAnim: _pulseAnim,
            flashAnim: _flashAnim,
            tickCtrl:  _tickCtrl,
            now:       _now,
            onBack:    () => context.go('/dashboard'),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MAIN TV BODY
// ─────────────────────────────────────────────────────────

class _TvBody extends StatelessWidget {
  final TvDisplay tv;
  final Animation<double> pulseAnim;
  final Animation<double> flashAnim;
  final AnimationController tickCtrl;
  final DateTime now;
  final VoidCallback onBack;

  const _TvBody({
    required this.tv,
    required this.pulseAnim,
    required this.flashAnim,
    required this.tickCtrl,
    required this.now,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(isWide ? 40 : 20),
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────
            _TopBar(tv: tv, tickCtrl: tickCtrl, now: now, onBack: onBack),
            const SizedBox(height: 24),

            // ── Main area ─────────────────────────────────
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left: current token hero
                        Expanded(
                          flex: 5,
                          child: _CurrentTokenPanel(
                            tv:        tv,
                            pulseAnim: pulseAnim,
                            flashAnim: flashAnim,
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Right: next up + stats
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              Expanded(child: _NextUpPanel(tv: tv)),
                              const SizedBox(height: 20),
                              _StatsBar(tv: tv),
                            ],
                          ),
                        ),
                      ],
                    )
                  // Narrow layout
                  : Column(
                      children: [
                        Expanded(
                          flex: 5,
                          child: _CurrentTokenPanel(
                            tv:        tv,
                            pulseAnim: pulseAnim,
                            flashAnim: flashAnim,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          flex: 4,
                          child: _NextUpPanel(tv: tv),
                        ),
                        const SizedBox(height: 12),
                        _StatsBar(tv: tv),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final TvDisplay tv;
  final AnimationController tickCtrl;
  final DateTime now;
  final VoidCallback onBack;

  const _TopBar({
    required this.tv,
    required this.tickCtrl,
    required this.now,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';

    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),

        // Hospital icon
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF0A5C5C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.local_hospital_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),

        // Hospital name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tv.hospitalName,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tv.hospitalAddress != null)
                Text(
                  tv.hospitalAddress!,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.45)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        // Live dot + time
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Live indicator
            AnimatedBuilder(
              animation: tickCtrl,
              builder: (_, _) => Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF4ADE80)
                          .withOpacity(0.4 + 0.6 * tickCtrl.value),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('LIVE',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4ADE80),
                          letterSpacing: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$h:$m $ampm',
              style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// CURRENT TOKEN PANEL — the hero element
// ─────────────────────────────────────────────────────────

class _CurrentTokenPanel extends StatelessWidget {
  final TvDisplay tv;
  final Animation<double> pulseAnim;
  final Animation<double> flashAnim;

  const _CurrentTokenPanel({
    required this.tv, required this.pulseAnim, required this.flashAnim,
  });

  @override
  Widget build(BuildContext context) {
    final hasPatient = tv.currentToken != null && tv.currentTokenNumber > 0;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.7, end: 1.0).animate(flashAnim),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasPatient
                ? [const Color(0xFF063D3D), const Color(0xFF0A5C5C)]
                : [const Color(0xFF111818), const Color(0xFF0D1F1F)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hasPatient
                ? const Color(0xFF0A5C5C)
                : Colors.white.withOpacity(0.06),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // "NOW SERVING" label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
              decoration: BoxDecoration(
                color: hasPatient
                    ? const Color(0xFF4ADE80).withOpacity(0.15)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPatient)
                    const Icon(Icons.campaign_rounded,
                        color: Color(0xFF4ADE80), size: 16)
                  else
                    Icon(Icons.hourglass_empty_rounded,
                        color: Colors.white.withOpacity(0.3), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    hasPatient ? 'NOW SERVING' : 'WAITING TO START',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: hasPatient
                          ? const Color(0xFF4ADE80)
                          : Colors.white.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Big token number
            ScaleTransition(
              scale: hasPatient ? pulseAnim : const AlwaysStoppedAnimation(1.0),
              child: Text(
                hasPatient ? tv.formatToken(tv.currentTokenNumber) : '—',
                style: GoogleFonts.playfairDisplay(
                  fontSize: _tokenFontSize(context),
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 0.9,
                ),
              ),
            ),

            if (hasPatient) ...[
              const SizedBox(height: 16),
              Text(
                tv.currentToken!.patientName,
                style: GoogleFonts.dmSans(
                  fontSize: _nameFontSize(context),
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tv.currentToken!.reason != null) ...[
                const SizedBox(height: 6),
                Text(
                  tv.currentToken!.reason!,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  double _tokenFontSize(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 1200) return 200;
    if (w >= 900)  return 160;
    return 120;
  }

  double _nameFontSize(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 26;
    return 20;
  }
}

// ─────────────────────────────────────────────────────────
// NEXT UP PANEL
// ─────────────────────────────────────────────────────────

class _NextUpPanel extends StatelessWidget {
  final TvDisplay tv;
  const _NextUpPanel({required this.tv});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1818),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.queue_rounded, color: Color(0xFF6EE7B7), size: 18),
              const SizedBox(width: 8),
              Text(
                'UP NEXT',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: const Color(0xFF6EE7B7)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Token list
          if (tv.nextTokens.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 40,
                        color: Colors.white.withOpacity(0.15)),
                    const SizedBox(height: 12),
                    Text(
                      'No patients waiting',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.3)),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  ...tv.nextTokens.asMap().entries.map((e) {
                    final i = e.key;
                    final t = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NextTokenRow(token: t, position: i + 1, display: tv),
                    );
                  }),

                  // More waiting indicator
                  if (tv.moreWaiting > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '+${tv.moreWaiting} more waiting',
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.45)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NextTokenRow extends StatelessWidget {
  final TvNextToken token;
  final int position;
  final TvDisplay display;
  const _NextTokenRow({required this.token, required this.position, required this.display});

  @override
  Widget build(BuildContext context) {
    final opacity = math.max(0.25, 1.0 - (position - 1) * 0.15);

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04 + (1 - opacity) * 0.01),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Token number badge
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0A5C5C).withOpacity(opacity),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  display.formatToken(token.tokenNumber),
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(opacity)),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + reason
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _maskName(token.patientName),
                    style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(opacity * 0.9)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (token.reason != null)
                    Text(
                      token.reason!,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: Colors.white.withOpacity(opacity * 0.4)),
                    ),
                ],
              ),
            ),

            // Position indicator
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withOpacity(0.15), width: 1),
              ),
              child: Center(
                child: Text(
                  '$position',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Partially mask patient name for privacy on public TV
  String _maskName(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return name;
    final first = parts[0];
    if (first.length <= 2) return first;
    return '${first[0]}${'*' * (first.length - 2)}${first[first.length - 1]}'
        '${parts.length > 1 ? ' ${parts.last[0]}.' : ''}';
  }
}

// ─────────────────────────────────────────────────────────
// STATS BAR
// ─────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final TvDisplay tv;
  const _StatsBar({required this.tv});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(
          label: 'Waiting',
          value: '${tv.totalWaiting}',
          icon:  Icons.hourglass_empty_rounded,
          color: const Color(0xFFFBBF24),
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(
          label: 'Served Today',
          value: '${tv.totalDone}',
          icon:  Icons.check_circle_outline_rounded,
          color: const Color(0xFF4ADE80),
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(
          label: 'Avg Wait',
          value: '${tv.avgWaitMins} min',
          icon:  Icons.schedule_rounded,
          color: const Color(0xFF60A5FA),
        )),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label, required this.value,
    required this.icon, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: color)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withOpacity(0.7),
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080F0F),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF0A5C5C),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 24),
          Text('ClinicQ',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 32, fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 16),
          const SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(
                color: Color(0xFF0A5C5C), strokeWidth: 3),
          ),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080F0F),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.white.withOpacity(0.3), size: 48),
          const SizedBox(height: 16),
          Text('Display unavailable',
              style: GoogleFonts.dmSans(
                  fontSize: 20, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.3))),
        ],
      ),
    ),
  );
}