// lib/screens/qr_checkin_page.dart
//
// Dedicated QR check-in page — print/share friendly.
// Route: /qr/:hospitalId
// No auth required (hospital data is public via hospitalFullProvider).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/queue_provider.dart';

// ─────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────

class QrCheckinPage extends ConsumerWidget {
  final String hospitalId;

  const QrCheckinPage({
    super.key,
    required this.hospitalId,
  });

  String get _checkInUrl {
    final origin = kIsWeb ? Uri.base.origin : AppConstants.baseUrl;
    return '$origin/#/checkin/$hospitalId';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hospitalAsync = ref.watch(hospitalFullProvider(hospitalId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textSecondary,
        ),
        title: Text(
          'Patient Check-in QR',
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: hospitalAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, e) => _QrContent(
          hospitalName: 'Clinic',
          address:      null,
          phone:        null,
          checkInUrl:   _checkInUrl,
        ),
        data: (hospital) => _QrContent(
          hospitalName: hospital?.name ?? 'Clinic',
          address:      hospital?.address,
          phone:        hospital?.phone,
          checkInUrl:   _checkInUrl,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// QR Content — responsive A4 + mobile layout
// ─────────────────────────────────────────────────────────

class _QrContent extends StatelessWidget {
  final String  hospitalName;
  final String? address;
  final String? phone;
  final String  checkInUrl;

  const _QrContent({
    required this.hospitalName,
    required this.address,
    required this.phone,
    required this.checkInUrl,
  });

  @override
  Widget build(BuildContext context) {
    final width    = MediaQuery.of(context).size.width;
    final isNarrow = width < 600;
    final qrSize   = isNarrow ? (width * 0.55).clamp(160.0, 260.0) : 260.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 20 : 40,
        vertical:   isNarrow ? 24 : 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              _PrintCard(
                hospitalName: hospitalName,
                address:      address,
                phone:        phone,
                checkInUrl:   checkInUrl,
                qrSize:       qrSize,
              ),
              const SizedBox(height: 28),
              _UrlRow(url: checkInUrl),
              const SizedBox(height: 20),
              _ActionButtons(checkInUrl: checkInUrl),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Print-friendly card
// ─────────────────────────────────────────────────────────

class _PrintCard extends StatelessWidget {
  final String  hospitalName;
  final String? address;
  final String? phone;
  final String  checkInUrl;
  final double  qrSize;

  const _PrintCard({
    required this.hospitalName,
    required this.address,
    required this.phone,
    required this.checkInUrl,
    required this.qrSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Teal header band ─────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
                colors: [Color(0xFF0A5C5C), Color(0xFF063D3D)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_hospital_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        hospitalName,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                if (phone != null || address != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (phone != null)
                        _InfoChip(
                            icon: Icons.phone_outlined, label: phone!),
                      if (address != null)
                        _InfoChip(
                            icon: Icons.location_on_outlined,
                            label: address!),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── QR body ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Text(
                  'Patient Self Check-in',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan this QR code to join the queue',
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // QR code with accent frame
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data:            checkInUrl,
                    version:         QrVersions.auto,
                    size:            qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color:    AppColors.primary,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color:           AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Instruction note
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Open your phone camera and point it at the QR '
                          'code to register without staff assistance',
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Footer ───────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 24),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFA),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(19)),
              border:
                  Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_outlined,
                    size: 14,
                    color: AppColors.textHint.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  'Powered by ClinicQ',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────
// URL row
// ─────────────────────────────────────────────────────────

class _UrlRow extends StatelessWidget {
  final String url;
  const _UrlRow({required this.url});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.link_rounded,
            size: 16, color: AppColors.textHint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            url,
            style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────
// Action buttons
// ─────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final String checkInUrl;
  const _ActionButtons({required this.checkInUrl});

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: checkInUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Text('Check-in link copied!',
              style: TextStyle(color: Colors.white)),
        ]),
        backgroundColor: AppColors.success,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin:   const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary: copy link
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _copyLink(context),
            icon:  const Icon(Icons.copy_rounded, size: 18),
            label: Text(
              'Copy Check-in Link',
              style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Secondary row
        Row(
          children: [
            if (kIsWeb) ...[
              Expanded(
                child: _SecondaryBtn(
                  icon:  Icons.print_rounded,
                  label: 'Print',
                  onTap: () {
                    // Browser print is triggered via JS on web builds
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Use your browser\'s Print (Ctrl+P) to print this page'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _SecondaryBtn(
                icon:  Icons.share_rounded,
                label: 'Share Link',
                onTap: () => _copyLink(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  const _SecondaryBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon:  Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.dmSans(
            fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
