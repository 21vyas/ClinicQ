// lib/core/router/app_router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_page.dart';
import '../../screens/register_page.dart';
import '../../screens/setup_page.dart';
import '../../screens/dashboard_page.dart';
import '../../screens/settings_page.dart';
import '../../screens/analytics_page.dart';
import '../../screens/patients_page.dart';
import '../../screens/tv_display_page.dart';
import '../../screens/splash_screen.dart';
import '../../screens/auth_callback_page.dart';
import '../../screens/checkin_page.dart';
import '../../screens/token_status_page.dart';
import '../../screens/qr_checkin_page.dart';
import '../../screens/superadmin_page.dart';
import '../../screens/team_page.dart';
import '../../core/constants/app_constants.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthChangeNotifier();
  ref.listen(authStateProvider, (_, _) => authNotifier.notify());

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final authService = ref.read(authServiceProvider);
      final isLoggedIn  = authService.isLoggedIn;
      final loc         = state.matchedLocation;

      // Public routes — no auth required
      final isPublic = loc.startsWith('/checkin/') ||
          loc.startsWith('/token/')                ||
          loc.startsWith('/tv/')                   ||
          loc.startsWith('/qr/')                   ||
          loc == '/login'                          ||
          loc == '/register'                       ||
          loc == '/auth/callback';

      if (!isLoggedIn && !isPublic) return AppConstants.routeLogin;

      if (isLoggedIn && (loc == '/login' || loc == '/register')) {
        final hospital =
            await ref.read(hospitalServiceProvider).getUserHospital();
        return hospital == null
            ? AppConstants.routeSetup
            : AppConstants.routeDashboard;
      }

      // Superadmin-only route guard
      if (loc == '/superadmin') {
        if (!isLoggedIn) return AppConstants.routeLogin;
        final isSuper = await authService.isSuperAdmin();
        if (!isSuper) return AppConstants.routeDashboard;
      }

      // Team management is admin-only.
      if (loc.startsWith('/team/')) {
        if (!isLoggedIn) return AppConstants.routeLogin;
        final scoped =
            await ref.read(hospitalServiceProvider).getUserHospitalWithRole();
        if (scoped == null || scoped.myRole != 'admin') {
          return AppConstants.routeDashboard;
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),

      // ── Public (patient + TV) ────────────────────────────
      GoRoute(
        path: '/checkin/:hospitalId',
        builder: (_, s) =>
            CheckInPage(hospitalId: s.pathParameters['hospitalId']!),
      ),
      GoRoute(
        path: '/token/:queueId',
        builder: (_, s) =>
            TokenStatusPage(queueId: s.pathParameters['queueId']!),
      ),
      GoRoute(
        path: '/tv/:hospitalId',
        builder: (_, s) =>
            TvDisplayPage(hospitalId: s.pathParameters['hospitalId']!),
      ),
      GoRoute(
        path: '/qr/:hospitalId',
        builder: (_, s) =>
            QrCheckinPage(hospitalId: s.pathParameters['hospitalId']!),
      ),

      // ── Superadmin ───────────────────────────────────────
      GoRoute(
        path: '/superadmin',
        pageBuilder: (_, s) => _fadePage(s, const SuperadminPage()),
      ),

      // ── OAuth callback ───────────────────────────────────
      GoRoute(
        path: '/auth/callback',
        builder: (_, _) => const AuthCallbackPage(),
      ),

      // ── Auth ─────────────────────────────────────────────
      GoRoute(
        path: AppConstants.routeLogin,
        pageBuilder: (_, s) => _fadePage(s, const LoginPage()),
      ),
      GoRoute(
        path: AppConstants.routeRegister,
        pageBuilder: (_, s) => _fadePage(s, const RegisterPage()),
      ),
      GoRoute(
        path: AppConstants.routeSetup,
        pageBuilder: (_, s) => _fadePage(s, const SetupPage()),
      ),

      // ── Dashboard + sub-pages ────────────────────────────
      GoRoute(
        path: AppConstants.routeDashboard,
        pageBuilder: (_, s) => _fadePage(s, const DashboardPage()),
      ),
      GoRoute(
        path: '/settings/:hospitalId',
        pageBuilder: (_, s) => _fadePage(
          s, SettingsPage(hospitalId: s.pathParameters['hospitalId']!),
        ),
      ),
      GoRoute(
        path: '/analytics/:hospitalId',
        pageBuilder: (_, s) => _fadePage(
          s, AnalyticsPage(hospitalId: s.pathParameters['hospitalId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/patients/:hospitalId',
        pageBuilder: (_, s) => _fadePage(
          s, PatientsPage(hospitalId: s.pathParameters['hospitalId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/team/:hospitalId',
        builder: (_, s) => TeamPage(
          hospitalId: s.pathParameters['hospitalId']!,
        ),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (_, animation, _, c) =>
        FadeTransition(opacity: animation, child: c),
  );
}

class _AuthChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}