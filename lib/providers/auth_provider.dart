import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/hospital_service.dart';
import '../models/app_user.dart';
import '../models/hospital.dart';

// ─────────────────────────────────────────────
// Service providers (singleton)
// ─────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final hospitalServiceProvider =
    Provider<HospitalService>((ref) => HospitalService());

// ─────────────────────────────────────────────
// Auth state stream
// ─────────────────────────────────────────────

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.read(authServiceProvider).authStateChanges;
});

// ─────────────────────────────────────────────
// Current user notifier
// ─────────────────────────────────────────────

class AppUserNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    ref.listen(authStateProvider, (_, _) => refresh());
    return _fetch();
  }

  Future<AppUser?> _fetch() {
    return ref.read(authServiceProvider).getCurrentUser();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final appUserProvider = AsyncNotifierProvider<AppUserNotifier, AppUser?>(
  AppUserNotifier.new,
);

// ─────────────────────────────────────────────
// Hospital state — includes my_role from RPC
// ─────────────────────────────────────────────

class HospitalNotifier extends AsyncNotifier<Hospital?> {
  @override
  Future<Hospital?> build() async {
    ref.listen(appUserProvider, (_, _) => refresh());
    return _fetch();
  }

  Future<Hospital?> _fetch() {
    return ref.read(hospitalServiceProvider).getUserHospital();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final hospitalProvider = AsyncNotifierProvider<HospitalNotifier, Hospital?>(
  HospitalNotifier.new,
);

// ─────────────────────────────────────────────
// Hospital role provider — 'admin' | 'staff' | null
// Fetched alongside the hospital via get_my_hospital()
// ─────────────────────────────────────────────

final hospitalRoleProvider = FutureProvider<String?>((ref) async {
  // Re-run whenever the hospital refreshes
  final hospitalAsync = ref.watch(hospitalProvider);
  if (!hospitalAsync.hasValue || hospitalAsync.value == null) return null;

  final result = await ref
      .read(hospitalServiceProvider)
      .getUserHospitalWithRole();
  return result?.myRole;
});

// ─────────────────────────────────────────────
// Auth loading state (for button spinners)
// ─────────────────────────────────────────────

final authLoadingProvider = StateProvider<bool>((ref) => false);
