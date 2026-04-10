import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/hospital.dart';
 
class HospitalService {
  final SupabaseClient _client;
 
  HospitalService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
 
  /// Creates a new hospital and its default settings.
  /// Returns [HospitalResult] with the created hospital or error.
  Future<HospitalResult> createHospital({
    required String name,
    required String address,
    String? phone,
  }) async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null) {
        return HospitalResult.failure('Not authenticated.');
      }
 
      // 1. Get user's internal id
      final userData = await _client
          .from(AppConstants.tableUsers)
          .select('id')
          .eq('auth_id', authUser.id)
          .single();
 
      final userId = userData['id'] as String;
 
      // 2. Generate a unique slug from hospital name
      final slug = _generateSlug(name);
 
      // 3. Insert hospital
      final hospitalData = await _client
          .from(AppConstants.tableHospitals)
          .insert({
            'name': name.trim(),
            'slug': slug,
            'address': address.trim(),
            'phone': phone?.trim(),
            'created_by': userId,
          })
          .select()
          .single();
 
      final hospital = Hospital.fromJson(hospitalData);
 
      // 4. Insert default hospital settings
      await _client.from(AppConstants.tableHospitalSettings).insert({
        'hospital_id': hospital.id,
        'token_limit': 100,
        'avg_time_per_patient': 5,
        'alert_before': 3,
      });
 
      return HospitalResult.success(hospital);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Unique violation — slug conflict
        return HospitalResult.failure(
            'A hospital with a similar name already exists. Try a different name.');
      }
      return HospitalResult.failure(e.message);
    } catch (e) {
      return HospitalResult.failure('Failed to create hospital. Please retry.');
    }
  }
 
  /// Fetches the hospital belonging to the current user.
  Future<Hospital?> getUserHospital() async {
    final scoped = await getUserHospitalWithRole();
    return scoped?.hospital;
  }

  /// Fetches the current user's first active hospital membership with role.
  Future<UserHospitalScope?> getUserHospitalWithRole() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;
 
    try {
      final userData = await _client
          .from(AppConstants.tableUsers)
          .select('id')
          .eq('auth_id', authUser.id)
          .maybeSingle();
 
      if (userData == null) return null;

      final userId = userData['id'] as String;

      final membershipData = await _client
          .from('hospital_users')
          .select('hospital_id, role')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

      if (membershipData != null) {
        final hospitalData = await _client
            .from(AppConstants.tableHospitals)
            .select()
            .eq('id', membershipData['hospital_id'] as String)
            .maybeSingle();

        if (hospitalData != null) {
          return UserHospitalScope(
            hospital: Hospital.fromJson(hospitalData),
            myRole: (membershipData['role'] as String?) ?? 'staff',
          );
        }
      }
 
      final data = await _client
          .from(AppConstants.tableHospitals)
          .select()
          .eq('created_by', userId)
          .maybeSingle();
 
      if (data == null) return null;
      return UserHospitalScope(
        hospital: Hospital.fromJson(data),
        myRole: 'admin',
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> getUserHospitalRole() async {
    final scoped = await getUserHospitalWithRole();
    return scoped?.myRole;
  }
 
  // ── helpers ──────────────────────────────────
  String _generateSlug(String name) {
    final base = name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
    return '$base-$suffix';
  }
}
 
// ─────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────
 
class HospitalResult {
  final bool isSuccess;
  final Hospital? hospital;
  final String? errorMessage;
 
  const HospitalResult._({
    required this.isSuccess,
    this.hospital,
    this.errorMessage,
  });
 
  factory HospitalResult.success(Hospital h) =>
      HospitalResult._(isSuccess: true, hospital: h);
 
  factory HospitalResult.failure(String msg) =>
      HospitalResult._(isSuccess: false, errorMessage: msg);
}

class UserHospitalScope {
  final Hospital hospital;
  final String myRole;

  const UserHospitalScope({
    required this.hospital,
    required this.myRole,
  });
}
 