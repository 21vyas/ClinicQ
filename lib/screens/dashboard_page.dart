// lib/screens/dashboard_page.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/queue_entry.dart';
import '../models/queue_today.dart';
import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/cq_button.dart';

// ═════════════════════════════════════════════════════════
// ROOT — resolves hospital from auth state
// ═════════════════════════════════════════════════════════

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hospitalAsync = ref.watch(hospitalProvider);
    return hospitalAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (hospital) {
        if (hospital == null) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.go(AppConstants.routeSetup));
          return const SizedBox.shrink();
        }
        return _DashboardShell(
            hospitalId: hospital.id, hospitalName: hospital.name);
      },
    );
  }
}

// ═════════════════════════════════════════════════════════
// SHELL — app bar + body layout
// ═════════════════════════════════════════════════════════

class _DashboardShell extends ConsumerStatefulWidget {
  final String hospitalId;
  final String hospitalName;
  const _DashboardShell(
      {required this.hospitalId, required this.hospitalName});

  @override
  ConsumerState<_DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<_DashboardShell>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;
  DateTime _lastUpdated = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    // Tick every minute so "last updated" display stays fresh
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _checkInUrl {
    final origin = kIsWeb ? Uri.base.origin : AppConstants.baseUrl;
    return '$origin/#/checkin/${widget.hospitalId}';
  }

  // ── Helpers ───────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
        ]),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ));
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _callNext() async {
    final n = ref.read(queueTodayProvider(widget.hospitalId).notifier);
    final err = await n.callNext();
    if (!mounted) return;
    setState(() => _lastUpdated = DateTime.now());
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      _showSnack('Next patient called!', isError: false);
    }
  }

  Future<void> _completeToken(String entryId) async {
    final n = ref.read(queueTodayProvider(widget.hospitalId).notifier);
    final err = await n.completeToken(entryId);
    if (!mounted) return;
    setState(() => _lastUpdated = DateTime.now());
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      _showSnack('Patient marked as done.', isError: false);
    }
  }

  Future<void> _skipEntry(String entryId, int token) async {
    final confirmed = await _confirmDialog(
      title:   'Skip Token #$token?',
      body:    'This patient will be moved to skipped. They won\'t lose their place if re-queued.',
      confirm: 'Skip',
      danger:  true,
    );
    if (confirmed != true) return;
    final n = ref.read(queueTodayProvider(widget.hospitalId).notifier);
    final err = await n.skipEntry(entryId);
    if (!mounted) return;
    if (err != null) _showSnack(err, isError: true);
  }

  Future<void> _resetQueue() async {
    final confirmed = await _confirmDialog(
      title:   'Reset Today\'s Queue?',
      body:    'All today\'s tokens will be permanently deleted. This cannot be undone.',
      confirm: 'Reset',
      danger:  true,
    );
    if (confirmed != true) return;
    final n = ref.read(queueTodayProvider(widget.hospitalId).notifier);
    final err = await n.resetQueue();
    if (!mounted) return;
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      _showSnack('Queue has been reset.', isError: false);
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String confirm,
    bool danger = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title,
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
          content: Text(body,
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: danger ? AppColors.error : AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(confirm),
            ),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(queueTodayProvider(widget.hospitalId));
    final isWide     = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, ref),
      body: queueAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _ErrorView(
          message:   e.toString(),
          onRetry: () => ref
              .read(queueTodayProvider(widget.hospitalId).notifier)
              .refresh(),
        ),
        data: (queue) {
          if (queue == null) return const Center(child: Text('No data'));
          return isWide
              ? _WideLayout(
                  queue:         queue,
                  hospitalId:    widget.hospitalId,
                  hospitalName:  widget.hospitalName,
                  checkInUrl:    _checkInUrl,
                  lastUpdated:   _lastUpdated,
                  onCallNext:    _callNext,
                  onComplete:    _completeToken,
                  onSkip:        _skipEntry,
                  onReset:       _resetQueue,
                  tabCtrl:       _tabCtrl,
                )
              : _NarrowLayout(
                  queue:         queue,
                  hospitalId:    widget.hospitalId,
                  checkInUrl:    _checkInUrl,
                  lastUpdated:   _lastUpdated,
                  onCallNext:    _callNext,
                  onComplete:    _completeToken,
                  onSkip:        _skipEntry,
                  onReset:       _resetQueue,
                  tabCtrl:       _tabCtrl,
                );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leadingWidth: isMobile ? 160 : 240,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.local_hospital_rounded,
                  size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.hospitalName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // TV Display
        _AppBarAction(
          onPressed: () => context.go('/tv/${widget.hospitalId}'),
          icon: Icons.tv_rounded,
          label: 'TV',
          color: Colors.indigo,
          showLabel: isWide,
        ),
        // Analytics
        _AppBarAction(
          onPressed: () => context.go('/analytics/${widget.hospitalId}'),
          icon: Icons.bar_chart_rounded,
          label: 'Analytics',
          color: Colors.blue,
          showLabel: isWide,
        ),
        // Patients
        _AppBarAction(
          onPressed: () => context.go('/patients/${widget.hospitalId}'),
          icon: Icons.people_outline_rounded,
          label: 'Patients',
          color: Colors.teal,
          showLabel: isWide,
        ),
        // QR
        _AppBarAction(
          onPressed: () => _showQrSheet(context),
          icon: Icons.qr_code_2_rounded,
          label: 'QR',
          color: Colors.amber[800]!,
          showLabel: isWide,
        ),
        // Settings
        _AppBarAction(
          onPressed: () => context.go('/settings/${widget.hospitalId}'),
          icon: Icons.settings_outlined,
          label: 'Settings',
          color: AppColors.primary,
          showLabel: isWide,
        ),
        
        const SizedBox(width: 4),
        // Sign out
        TextButton(
          onPressed: () async {
            await ref.read(authServiceProvider).logout();
            if (context.mounted) context.go(AppConstants.routeLogin);
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('Out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  void _showQrSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrBottomSheet(
        url:          _checkInUrl,
        hospitalName: widget.hospitalName,
      ),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool showLabel;

  const _AppBarAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: color,
        tooltip: label,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// WIDE LAYOUT (desktop ≥ 900 px)
// Left sidebar: controls + stats + QR
// Right panel:  tabbed queue list
// ═════════════════════════════════════════════════════════

class _WideLayout extends StatelessWidget {
  final QueueToday queue;
  final String hospitalId;
  final String hospitalName;
  final String checkInUrl;
  final DateTime lastUpdated;
  final VoidCallback onCallNext;
  final Future<void> Function(String) onComplete;
  final Future<void> Function(String, int) onSkip;
  final VoidCallback onReset;
  final TabController tabCtrl;

  const _WideLayout({
    required this.queue,
    required this.hospitalId,
    required this.hospitalName,
    required this.checkInUrl,
    required this.lastUpdated,
    required this.onCallNext,
    required this.onComplete,
    required this.onSkip,
    required this.onReset,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left sidebar ──────────────────────────────────
        SizedBox(
          width: 300,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _ServingPanel(
                    queue:      queue,
                    onCallNext: onCallNext,
                    onComplete: onComplete,
                  ),
                  const SizedBox(height: 16),
                  _StatsGrid(queue: queue),
                  const SizedBox(height: 16),
                  _LastUpdatedRow(lastUpdated: lastUpdated),
                  const SizedBox(height: 16),
                  _MiniQrCard(url: checkInUrl),
                  const SizedBox(height: 16),
                  _ResetButton(onReset: onReset),
                ],
              ),
            ),
          ),
        ),

        // ── Right queue panel ─────────────────────────────
        Expanded(
          child: Column(
            children: [
              _QueueTabBar(ctrl: tabCtrl, counts: queue.counts),
              Expanded(
                child: TabBarView(
                  controller: tabCtrl,
                  children: [
                    _QueueList(
                      entries:    queue.waitingEntries,
                      emptyMsg:   'No patients waiting',
                      onSkip:     onSkip,
                      showSkip:   true,
                    ),
                    _QueueList(
                      entries:    queue.doneEntries,
                      emptyMsg:   'No completed patients yet',
                      showSkip:   false,
                    ),
                    _QueueList(
                      entries:    queue.skippedEntries,
                      emptyMsg:   'No skipped patients',
                      showSkip:   false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════
// NARROW LAYOUT (mobile < 900 px)
// ═════════════════════════════════════════════════════════

class _NarrowLayout extends StatelessWidget {
  final QueueToday queue;
  final String hospitalId;
  final String checkInUrl;
  final DateTime lastUpdated;
  final VoidCallback onCallNext;
  final Future<void> Function(String) onComplete;
  final Future<void> Function(String, int) onSkip;
  final VoidCallback onReset;
  final TabController tabCtrl;

  const _NarrowLayout({
    required this.queue,
    required this.hospitalId,
    required this.checkInUrl,
    required this.lastUpdated,
    required this.onCallNext,
    required this.onComplete,
    required this.onSkip,
    required this.onReset,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sticky top area
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              _ServingPanel(
                queue:      queue,
                onCallNext: onCallNext,
                onComplete: onComplete,
              ),
              const SizedBox(height: 10),
              _StatsRow(counts: queue.counts),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.border),
        _QueueTabBar(ctrl: tabCtrl, counts: queue.counts),
        Expanded(
          child: TabBarView(
            controller: tabCtrl,
            children: [
              _QueueList(
                entries:  queue.waitingEntries,
                emptyMsg: 'No patients waiting',
                onSkip:   onSkip,
                showSkip: true,
              ),
              _QueueList(
                entries:  queue.doneEntries,
                emptyMsg: 'No completed patients yet',
                showSkip: false,
              ),
              _QueueList(
                entries:  queue.skippedEntries,
                emptyMsg: 'No skipped patients',
                showSkip: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════
// SERVING PANEL
// Shows currently in_progress patient + action buttons
// ═════════════════════════════════════════════════════════

class _ServingPanel extends StatefulWidget {
  final QueueToday queue;
  final VoidCallback onCallNext;
  final Future<void> Function(String) onComplete;

  const _ServingPanel({
    required this.queue,
    required this.onCallNext,
    required this.onComplete,
  });

  @override
  State<_ServingPanel> createState() => _ServingPanelState();
}

class _ServingPanelState extends State<_ServingPanel> {
  bool _callingNext    = false;
  bool _completing     = false;

  Future<void> _handleCallNext() async {
    setState(() => _callingNext = true);
    widget.onCallNext();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _callingNext = false);
  }

  Future<void> _handleComplete(String entryId) async {
    setState(() => _completing = true);
    await widget.onComplete(entryId);
    if (mounted) setState(() => _completing = false);
  }

  @override
  Widget build(BuildContext context) {
    final serving  = widget.queue.inProgressEntry;
    final waiting  = widget.queue.counts.waiting;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A5C5C), Color(0xFF063D3D)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── Token display ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // Token circle
                _AnimatedTokenCircle(
                  token:    widget.queue.currentTokenNumber,
                  isActive: serving != null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serving != null ? 'Now Serving' : 'Queue Ready',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.6),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        serving?.patientName ?? 'No patient yet',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (serving != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (serving.patientPhone.isNotEmpty) ...[
                              Icon(Icons.phone_outlined,
                                  size: 11,
                                  color: Colors.white.withOpacity(0.55)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(serving.patientPhone,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.55),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (serving.reason != null) ...[
                              Icon(Icons.medical_services_outlined,
                                  size: 11,
                                  color: Colors.white.withOpacity(0.55)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  serving.reason!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.55),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Waiting badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$waiting',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // ── Action buttons ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useStack = constraints.maxWidth < 220;
                if (serving != null) {
                  return useStack 
                    ? Column(
                        children: [
                          _ActionButton(
                            label:    'Mark Done',
                            icon:     Icons.check_rounded,
                            color:    AppColors.success,
                            loading:  _completing,
                            onTap:    () => _handleComplete(serving.id),
                            fullWidth: true,
                          ),
                          const SizedBox(height: 8),
                          _ActionButton(
                            label:   'Call Next →',
                            icon:    Icons.campaign_rounded,
                            color:   const Color(0xFFE8820C),
                            loading: _callingNext,
                            onTap:   _handleCallNext,
                            fullWidth: true,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _ActionButton(
                              label:    'Mark Done',
                              icon:     Icons.check_rounded,
                              color:    AppColors.success,
                              loading:  _completing,
                              onTap:    () => _handleComplete(serving.id),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: _ActionButton(
                              label:   'Call Next →',
                              icon:    Icons.campaign_rounded,
                              color:   const Color(0xFFE8820C),
                              loading: _callingNext,
                              onTap:   _handleCallNext,
                            ),
                          ),
                        ],
                      );
                }
                return _ActionButton(
                  label:   waiting > 0 ? 'Call First Patient' : 'No Patients Yet',
                  icon:    Icons.campaign_rounded,
                  color:   waiting > 0
                      ? const Color(0xFFE8820C)
                      : Colors.white.withOpacity(0.3),
                  loading: _callingNext,
                  onTap:   waiting > 0 ? _handleCallNext : null,
                  fullWidth: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated token circle ─────────────────────────────────

class _AnimatedTokenCircle extends StatefulWidget {
  final int token;
  final bool isActive;
  const _AnimatedTokenCircle({required this.token, required this.isActive});

  @override
  State<_AnimatedTokenCircle> createState() => _AnimatedTokenCircleState();
}

class _AnimatedTokenCircleState extends State<_AnimatedTokenCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  int? _prevToken;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _prevToken = widget.token;
  }

  @override
  void didUpdateWidget(_AnimatedTokenCircle old) {
    super.didUpdateWidget(old);
    if (widget.token != _prevToken) _prevToken = widget.token;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isActive
        ? ScaleTransition(
            scale: _pulse,
            child: _circle(),
          )
        : _circle();
  }

  Widget _circle() => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(
              widget.isActive ? 0.18 : 0.1),
          border: Border.all(
              color: Colors.white.withOpacity(
                  widget.isActive ? 0.35 : 0.2),
              width: 1.5),
        ),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                widget.token > 0 ? '${widget.token}' : '—',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
}

// ── Action button ─────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 44,
      child: ElevatedButton(
        onPressed: onTap == null || loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
        ),
        child: loading
            ? LoadingAnimationWidget.threeArchedCircle(
                color: Colors.white, size: 18)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// STATS GRID (desktop sidebar)
// ═════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final QueueToday queue;
  const _StatsGrid({required this.queue});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(
              label:  'Total',
              value:  '${queue.counts.total}',
              icon:   Icons.list_alt_rounded,
              color:  AppColors.primary,
            )),
            const SizedBox(width: 8),
            Expanded(child: _StatCard(
              label:  'Waiting',
              value:  '${queue.counts.waiting}',
              icon:   Icons.hourglass_empty_rounded,
              color:  AppColors.accent,
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatCard(
              label:  'Done',
              value:  '${queue.counts.done}',
              icon:   Icons.check_circle_outline_rounded,
              color:  AppColors.success,
            )),
            const SizedBox(width: 8),
            Expanded(child: _StatCard(
              label:  'Avg Wait',
              value:  '${queue.effectiveAvgWait}m',
              icon:   Icons.schedule_rounded,
              color:  const Color(0xFF6366F1),
            )),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// Stats row (mobile)
class _StatsRow extends StatelessWidget {
  final QueueCounts counts;
  const _StatsRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(label: 'Total',   value: counts.total,   color: AppColors.primary),
        const SizedBox(width: 6),
        _StatChip(label: 'Waiting', value: counts.waiting, color: AppColors.accent),
        const SizedBox(width: 6),
        _StatChip(label: 'Done',    value: counts.done,    color: AppColors.success),
        const SizedBox(width: 6),
        _StatChip(label: 'Skipped', value: counts.skipped, color: AppColors.textHint),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$value',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 9, color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// QUEUE TAB BAR
// ═════════════════════════════════════════════════════════

class _QueueTabBar extends StatelessWidget {
  final TabController ctrl;
  final QueueCounts counts;
  const _QueueTabBar({required this.ctrl, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: ctrl,
        labelColor:   AppColors.primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelStyle: GoogleFonts.dmSans(
            fontSize: 13, fontWeight: FontWeight.w600),
        tabs: [
          Tab(text: 'Waiting  ${counts.waiting > 0 ? "(${counts.waiting})" : ""}'),
          Tab(text: 'Done  ${counts.done > 0 ? "(${counts.done})" : ""}'),
          Tab(text: 'Skipped  ${counts.skipped > 0 ? "(${counts.skipped})" : ""}'),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// QUEUE LIST + TILE
// ═════════════════════════════════════════════════════════

class _QueueList extends StatelessWidget {
  final List<QueueEntry> entries;
  final String emptyMsg;
  final Future<void> Function(String, int)? onSkip;
  final bool showSkip;

  const _QueueList({
    required this.entries,
    required this.emptyMsg,
    this.onSkip,
    required this.showSkip,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 44, color: AppColors.textHint.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(emptyMsg,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        return _QueueTile(
          entry:  e,
          onSkip: showSkip && onSkip != null
              ? () => onSkip!(e.id, e.tokenNumber)
              : null,
          onTap:  () => _showPatientSheet(context, e),
        );
      },
    );
  }

  void _showPatientSheet(BuildContext context, QueueEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PatientDetailSheet(entry: e),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final QueueEntry entry;
  final VoidCallback? onSkip;
  final VoidCallback? onTap;

  const _QueueTile({required this.entry, this.onSkip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(entry.status);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: entry.status == QueueStatus.inProgress
              ? const Color(0xFFECFDF3)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: entry.status == QueueStatus.inProgress
                ? AppColors.success.withOpacity(0.35)
                : AppColors.border,
            width: entry.status == QueueStatus.inProgress ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Token badge
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text('${entry.tokenNumber}',
                          style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: color)),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.patientName,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: entry.status == QueueStatus.done ||
                                      entry.status == QueueStatus.skipped
                                  ? AppColors.textHint
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusPill(status: entry.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 11, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(entry.patientPhone,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textHint)),
                        if (entry.reason != null) ...[
                          const SizedBox(width: 8),
                          const Text('·',
                              style: TextStyle(color: AppColors.textHint)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(entry.reason!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textHint)),
                          ),
                        ],
                      ],
                    ),
                    if (entry.waitedMins != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Waited ${entry.waitedMins} min',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textHint),
                        ),
                      ),
                  ],
                ),
              ),

              // Skip button
              if (onSkip != null)
                IconButton(
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next_rounded,
                      color: AppColors.textHint, size: 20),
                  tooltip: 'Skip',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(QueueStatus s) => switch (s) {
        QueueStatus.waiting    => AppColors.primary,
        QueueStatus.inProgress => AppColors.success,
        QueueStatus.done       => AppColors.textHint,
        QueueStatus.skipped    => AppColors.warning,
      };
}

class _StatusPill extends StatelessWidget {
  final QueueStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      QueueStatus.waiting    => (AppColors.primarySurface, AppColors.primary),
      QueueStatus.inProgress => (const Color(0xFFECFDF3), AppColors.success),
      QueueStatus.done       => (AppColors.surfaceVariant, AppColors.textHint),
      QueueStatus.skipped    => (AppColors.accentLight, AppColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ═════════════════════════════════════════════════════════
// PATIENT DETAIL SHEET
// ═════════════════════════════════════════════════════════

class _PatientDetailSheet extends StatelessWidget {
  final QueueEntry entry;
  const _PatientDetailSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text('${entry.tokenNumber}',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.patientName,
                        style: GoogleFonts.dmSans(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    _StatusPill(status: entry.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailRow(icon: Icons.phone_outlined,      label: 'Phone', value: entry.patientPhone),
          if (entry.patientAge != null)
            _DetailRow(icon: Icons.cake_outlined,     label: 'Age', value: '${entry.patientAge} yrs'),
          if (entry.reason != null)
            _DetailRow(icon: Icons.medical_services_outlined, label: 'Reason', value: entry.reason!),
          if (entry.waitedMins != null)
            _DetailRow(icon: Icons.timer_outlined,    label: 'Waited', value: '${entry.waitedMins} min'),
          _DetailRow(
            icon: Icons.access_time_rounded,
            label: 'Registered',
            value: _fmtTime(entry.createdAt),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Close'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// QR CARD + BOTTOM SHEET
// ═════════════════════════════════════════════════════════

class _MiniQrCard extends StatelessWidget {
  final String url;
  const _MiniQrCard({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: 64,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: AppColors.primary),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patient Check-in',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Share QR for patients to self-register',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: AppColors.textHint)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Check-in link copied!'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text('Copy link',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrBottomSheet extends StatelessWidget {
  final String url;
  final String hospitalName;
  const _QrBottomSheet({required this.url, required this.hospitalName});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Patient Check-in',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Patients scan this to register in the queue',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: AppColors.primary),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10)),
            child: Text(url,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 16),
          CQButton(
            label: 'Copy Check-in Link',
            icon:  Icons.copy_rounded,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied!')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// MISC WIDGETS
// ═════════════════════════════════════════════════════════

class _LastUpdatedRow extends StatelessWidget {
  final DateTime lastUpdated;
  const _LastUpdatedRow({required this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(lastUpdated).inMinutes;
    final label = diff == 0 ? 'Just now' : '${diff}m ago';
    return Row(
      children: [
        const _LiveDot(),
        const SizedBox(width: 6),
        Text('Live · Updated $label',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success.withOpacity(0.4 + 0.6 * _ctrl.value),
        ),
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetButton({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onReset,
        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
        label: const Text('Reset Today\'s Queue'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
