// lib/screens/token_status_page.dart
//
// Public route: /token/:queueId
// Real-time: subscribes to queue_entries + queue_daily_state

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../core/theme/app_theme.dart';
import '../models/queue_entry.dart';
import '../models/token_status.dart';
import '../providers/queue_provider.dart';

class TokenStatusPage extends ConsumerWidget {
  final String queueId;
  const TokenStatusPage({super.key, required this.queueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(tokenStatusProvider(queueId));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: statusAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (status) => status == null
            ? const _ErrorView(message: 'Token not found.')
            : _TokenBody(key: ValueKey(status.id), status: status),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MAIN BODY — animates when status changes
// ─────────────────────────────────────────────────────────

class _TokenBody extends StatefulWidget {
  final TokenStatus status;
  const _TokenBody({super.key, required this.status});

  @override
  State<_TokenBody> createState() => _TokenBodyState();
}

class _TokenBodyState extends State<_TokenBody>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;

  TokenStatus? _previousStatus;
  bool _statusChanged = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _slideCtrl.forward();
  }

  @override
  void didUpdateWidget(_TokenBody old) {
    super.didUpdateWidget(old);
    if (_previousStatus != null &&
        _previousStatus!.status != widget.status.status) {
      _statusChanged = true;
      _slideCtrl.forward(from: 0);
    }
    _previousStatus = widget.status;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s          = widget.status;
    final isServing  = s.status == QueueStatus.inProgress;
    final isDone     = s.status == QueueStatus.done;
    final isSkipped  = s.status == QueueStatus.skipped;
    final isWaiting  = s.status == QueueStatus.waiting;
    final isNext     = s.isNext;

    final headerColors = _headerGradient(s.status, isNext);

    return SlideTransition(
      position: _slideAnim,
      child: CustomScrollView(
        slivers: [
          // ── SliverAppBar ───────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            backgroundColor: headerColors.first,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('ClinicQ',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                _LiveIndicator(isActive: !isDone && !isSkipped),
              ],
            ),
          ),

          // ── Hero header ────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: headerColors,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Column(
                children: [
                  // Status badge
                  _StatusBadge(status: s.status, isNext: isNext),
                  const SizedBox(height: 28),

                  // Token disc
                  isServing
                      ? ScaleTransition(scale: _pulseAnim,
                          child: _TokenDisc(token: s.formattedToken))
                      : _TokenDisc(token: s.formattedToken),

                  const SizedBox(height: 18),

                  // Patient name
                  Text(s.patientName,
                      style: GoogleFonts.dmSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),

                  if (s.reason != null) ...[
                    const SizedBox(height: 6),
                    Text(s.reason!,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.6))),
                  ],
                ],
              ),
            ),
          ),

          // ── Info cards ─────────────────────────────────
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [

                    // ── Waiting info ─────────────────────
                    if (isWaiting) ...[
                      _PositionRow(status: s),
                      const SizedBox(height: 12),
                      _WaitProgressCard(status: s),
                      const SizedBox(height: 12),
                    ],

                    // ── Now serving ──────────────────────
                    if (isServing) ...[
                      _ServingCard(),
                      const SizedBox(height: 12),
                    ],

                    // ── You're next! ─────────────────────
                    if (isNext && isWaiting) ...[
                      _YoureNextCard(),
                      const SizedBox(height: 12),
                    ],

                    // ── Done ─────────────────────────────
                    if (isDone) ...[
                      _DoneCard(),
                      const SizedBox(height: 12),
                    ],

                    // ── Skipped ──────────────────────────
                    if (isSkipped) ...[
                      _SkippedCard(),
                      const SizedBox(height: 12),
                    ],

                    // ── Currently serving indicator ───────
                    if (s.currentTokenNumber > 0 && !isServing)
                      _CurrentTokenCard(token: s.currentTokenNumber),

                    const SizedBox(height: 24),

                    // Status changed flash
                    if (_statusChanged)
                      _StatusChangedBanner(status: s.status),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }

  List<Color> _headerGradient(QueueStatus status, bool isNext) {
    if (status == QueueStatus.inProgress) {
      return [const Color(0xFF1A7F5A), const Color(0xFF0D5C3C)];
    }
    if (isNext) {
      return [const Color(0xFF6366F1), const Color(0xFF4338CA)];
    }
    if (status == QueueStatus.done) {
      return [const Color(0xFF374151), const Color(0xFF1F2937)];
    }
    if (status == QueueStatus.skipped) {
      return [const Color(0xFF92400E), const Color(0xFF78350F)];
    }
    return [const Color(0xFF0A5C5C), const Color(0xFF063D3D)];
  }
}

// ─────────────────────────────────────────────────────────
// TOKEN DISC
// ─────────────────────────────────────────────────────────

class _TokenDisc extends StatelessWidget {
  final String token;
  const _TokenDisc({required this.token});

  @override
  Widget build(BuildContext context) {
    final screenW  = MediaQuery.of(context).size.width;
    final discSize = (screenW * 0.38).clamp(128.0, 172.0);
    // Inner usable width inside the circle (chord at ~70% of diameter)
    final innerW   = discSize * 0.72;

    return Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('TOKEN',
              style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 2.5)),
          const SizedBox(height: 2),
          SizedBox(
            width: innerW,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                token,
                maxLines: 1,
                style: GoogleFonts.playfairDisplay(
                    fontSize: discSize * 0.40,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final QueueStatus status;
  final bool isNext;
  const _StatusBadge({required this.status, required this.isNext});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      QueueStatus.waiting    => isNext
          ? ('You\'re Next!', Icons.notifications_active_rounded)
          : ('Waiting in Queue', Icons.hourglass_empty_rounded),
      QueueStatus.inProgress => ('Now Serving', Icons.campaign_rounded),
      QueueStatus.done       => ('Consultation Done', Icons.check_circle_outline_rounded),
      QueueStatus.skipped    => ('Token Skipped', Icons.skip_next_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// POSITION ROW (2 info cards)
// ─────────────────────────────────────────────────────────

class _PositionRow extends StatelessWidget {
  final TokenStatus status;
  const _PositionRow({required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InfoCard(
            icon:  Icons.people_outline_rounded,
            color: AppColors.primary,
            value: '${status.positionAhead}',
            unit:  status.positionAhead == 1 ? 'person' : 'people',
            label: 'Ahead of You',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoCard(
            icon:  Icons.schedule_rounded,
            color: AppColors.accent,
            value: status.estimatedWaitMins < 60
                ? '${status.estimatedWaitMins}'
                : '${(status.estimatedWaitMins / 60).floor()}h ${status.estimatedWaitMins % 60}m',
            unit:  status.estimatedWaitMins < 60 ? 'mins' : '',
            label: 'Est. Wait',
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  final String label;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.0)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textHint,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// WAIT PROGRESS CARD
// ─────────────────────────────────────────────────────────

class _WaitProgressCard extends StatelessWidget {
  final TokenStatus status;
  const _WaitProgressCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final progressValue = status.estimatedWaitMins <= 0
        ? 1.0
        : math.max(0.03, 1 - status.estimatedWaitMins / 60.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Queue Position',
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (status.estimatedWaitMins > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('~${status.estimatedWaitMins} min wait',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progressValue),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: AppColors.surfaceVariant,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            status.estimatedWaitMins <= 0
                ? 'Your turn is very soon — please be ready!'
                : 'Approximately ${status.estimatedWaitMins} minute${status.estimatedWaitMins == 1 ? "" : "s"} remaining',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STATUS CARDS
// ─────────────────────────────────────────────────────────

class _ServingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _AlertCard(
    gradient: const [Color(0xFF1A7F5A), Color(0xFF0D5C3C)],
    icon:     Icons.campaign_rounded,
    title:    'It\'s Your Turn!',
    subtitle: 'Please proceed to the consultation room now.',
  );
}

class _YoureNextCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _AlertCard(
    gradient: const [Color(0xFF6366F1), Color(0xFF4338CA)],
    icon:     Icons.notifications_active_rounded,
    title:    'You\'re Next!',
    subtitle: 'Please make your way to the waiting area.',
  );
}

class _DoneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFECFDF3),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFA7F3D0)),
    ),
    child: Column(children: [
      const Icon(Icons.check_circle_rounded,
          color: AppColors.success, size: 36),
      const SizedBox(height: 10),
      Text('Consultation Complete',
          style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.success)),
      const SizedBox(height: 4),
      const Text(
          'Thank you for your visit. We hope you feel better soon!',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ]),
  );
}

class _SkippedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFE082)),
    ),
    child: Column(children: [
      const Icon(Icons.warning_amber_rounded,
          color: AppColors.warning, size: 36),
      const SizedBox(height: 10),
      Text('Token Skipped',
          style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.warning)),
      const SizedBox(height: 4),
      const Text('Your token was skipped. Please speak to the front desk.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ]),
  );
}

class _AlertCard extends StatelessWidget {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;

  const _AlertCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: gradient),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: [
      Icon(icon, color: Colors.white, size: 34),
      const SizedBox(height: 10),
      Text(title,
          style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
      const SizedBox(height: 6),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
    ]),
  );
}

class _CurrentTokenCard extends StatelessWidget {
  final int token;
  const _CurrentTokenCard({required this.token});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            const Icon(Icons.volume_up_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Text('Now Serving',
                style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('$token',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChangedBanner extends StatelessWidget {
  final QueueStatus status;
  const _StatusChangedBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final msg = switch (status) {
      QueueStatus.inProgress => '🎉 Your token is now being served!',
      QueueStatus.done       => '✅ Your consultation is complete.',
      QueueStatus.skipped    => '⚠️ Your token has been skipped.',
      _                      => '🔄 Queue position updated.',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary)),
    );
  }
}

// ─────────────────────────────────────────────────────────
// LIVE INDICATOR
// ─────────────────────────────────────────────────────────

class _LiveIndicator extends StatefulWidget {
  final bool isActive;
  const _LiveIndicator({required this.isActive});

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.4 + 0.6 * _ctrl.value),
            ),
          ),
          const SizedBox(width: 5),
          Text('Live',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// HELPER SCREENS
// ─────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.primary,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingAnimationWidget.threeArchedCircle(
              color: Colors.white, size: 48),
          const SizedBox(height: 20),
          Text('Loading your token...',
              style: GoogleFonts.dmSans(
                  fontSize: 15, color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 52),
          const SizedBox(height: 16),
          Text('Token not found',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    ),
  );
}