// lib/core/constants/app_constants.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
    // ── Compile-time defines (preferred in CI/Vercel) ─────────
    static const String _supabaseUrlDefine =
            String.fromEnvironment('SUPABASE_URL');
    static const String _supabaseAnonKeyDefine =
            String.fromEnvironment('SUPABASE_ANON_KEY');
    static const String _baseUrlDefine =
            String.fromEnvironment('BASE_URL');

  // ── Supabase (loaded from .env) ──────────────────────────
  static String get supabaseUrl =>
            _firstNonEmpty(_supabaseUrlDefine, dotenv.env['SUPABASE_URL']) ??
            (throw Exception(
                'SUPABASE_URL missing. Provide via --dart-define or .env',
            ));

  static String get supabaseAnonKey =>
            _firstNonEmpty(
                _supabaseAnonKeyDefine,
                dotenv.env['SUPABASE_ANON_KEY'],
            ) ??
            (throw Exception(
                'SUPABASE_ANON_KEY missing. Provide via --dart-define or .env',
            ));

  static String get baseUrl =>
            _firstNonEmpty(_baseUrlDefine, dotenv.env['BASE_URL']) ??
            (throw Exception(
                'BASE_URL missing. Provide via --dart-define or .env',
            ));

    static String? _firstNonEmpty(String? first, String? second) {
        if (first != null && first.trim().isNotEmpty) return first.trim();
        if (second != null && second.trim().isNotEmpty) return second.trim();
        return null;
    }

  // ── App ──────────────────────────────────────────────────
  static const String appName    = 'ClinicQ';
  static const String appVersion = '1.0.0';

  // ── Routes ───────────────────────────────────────────────
  static const String routeLogin     = '/login';
  static const String routeRegister  = '/register';
  static const String routeSetup     = '/setup';
  static const String routeDashboard = '/dashboard';

  // Step 2 — public patient routes
  static const String routeCheckin = '/checkin'; // + /:hospitalId
  static const String routeToken   = '/token';   // + /:queueId

  // ── Table names ──────────────────────────────────────────
  static const String tableUsers            = 'users';
  static const String tableHospitals        = 'hospitals';
  static const String tableHospitalSettings = 'hospital_settings';
  static const String tableQueueEntries     = 'queue_entries';
  static const String tableQueueDailyState  = 'queue_daily_state';
}