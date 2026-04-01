import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
 
class DashboardPlaceholder extends ConsumerWidget {
  const DashboardPlaceholder({super.key});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hospital = ref.watch(hospitalProvider);
    final user = ref.watch(appUserProvider);
 
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leadingWidth: 200,
        leading: Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.local_hospital_rounded,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'ClinicQ',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              if (context.mounted) context.go(AppConstants.routeLogin);
            },
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Sign out'),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 20)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2), width: 1.5),
                ),
                child: const Icon(Icons.dashboard_rounded,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              hospital.when(
                data: (h) => Text(
                  h?.name ?? 'Your Clinic',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                loading: () =>
                    const CircularProgressIndicator(color: AppColors.primary),
                error: (_, __) => const Text('Dashboard'),
              ),
              const SizedBox(height: 8),
              user.when(
                data: (u) => Text(
                  'Welcome back, ${u?.displayName ?? 'Doctor'} 👋',
                  style: GoogleFonts.dmSans(
                      fontSize: 16, color: AppColors.textSecondary),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.construction_rounded,
                        color: AppColors.accent, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      '✅ Step 1 Complete',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Auth + Database + Hospital Setup are all working.\nStep 2 (QR & Queue) coming next.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 