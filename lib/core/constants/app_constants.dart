// lib/core/constants/app_constants.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // ── Supabase (loaded from .env) ──────────────────────────
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ??
      (throw Exception('SUPABASE_URL missing in .env'));

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      (throw Exception('SUPABASE_ANON_KEY missing in .env'));

  static String get baseUrl =>
      dotenv.env['BASE_URL'] ??
      (throw Exception('BASE_URL missing in .env'));

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