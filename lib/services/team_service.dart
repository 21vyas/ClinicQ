import 'package:supabase_flutter/supabase_flutter.dart';

const int kMaxStaff = 5;

// ─────────────────────────────────────────────
// Data model for a hospital team member
// ─────────────────────────────────────────────

class HospitalMember {
  final String id;        // hospital_users.id
  final String userId;    // users.id
  final String email;
  final String? fullName;
  final String role;      // 'admin' | 'staff'
  final bool isActive;
  final DateTime createdAt;

  const HospitalMember({
    required this.id,
    required this.userId,
    required this.email,
    this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory HospitalMember.fromJson(Map<String, dynamic> j) {
    return HospitalMember(
      id:        j['id']        as String,
      userId:    j['user_id']   as String,
      email:     j['email']     as String,
      fullName:  j['full_name'] as String?,
      role:      j['role']      as String,
      isActive:  (j['is_active'] as bool?) ?? true,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  String get displayName => fullName ?? email.split('@').first;
}

// ─────────────────────────────────────────────
// Staff count info
// ─────────────────────────────────────────────

class StaffCount {
  final int staffCount;
  final int totalCount;
  final int staffLimit;
  final bool canAdd;

  const StaffCount({
    required this.staffCount,
    required this.totalCount,
    required this.staffLimit,
    required this.canAdd,
  });

  factory StaffCount.fromJson(Map<String, dynamic> j) => StaffCount(
    staffCount: (j['staff_count'] as num).toInt(),
    totalCount: (j['total_count'] as num).toInt(),
    staffLimit: (j['staff_limit'] as num).toInt(),
    canAdd:     j['can_add'] as bool,
  );
}

// ─────────────────────────────────────────────
// TeamService
// ─────────────────────────────────────────────

class TeamService {
  final SupabaseClient _client;

  TeamService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Lists all members of [hospitalId]. Caller must be a member.
  Future<TeamResult<List<HospitalMember>>> listMembers(String hospitalId) async {
    try {
      final data = await _client.rpc('list_hospital_users',
          params: {'p_hospital_id': hospitalId});
      final members = (data as Map)['members'] as List? ?? [];
      return TeamResult.success(
        members
            .map((m) => HospitalMember.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('UNAUTHORIZED')) {
        return TeamResult.failure('You do not have permission to view the team.');
      }
      return TeamResult.failure(e.message);
    } catch (_) {
      return TeamResult.failure('Failed to load team.');
    }
  }

  /// Returns current staff count info for [hospitalId].
  Future<TeamResult<StaffCount>> getStaffCount(String hospitalId) async {
    try {
      final data = await _client.rpc('get_staff_count',
          params: {'p_hospital_id': hospitalId});
      return TeamResult.success(
          StaffCount.fromJson(Map<String, dynamic>.from(data as Map)));
    } catch (_) {
      return TeamResult.failure('Failed to get staff count.');
    }
  }

  /// Creates a brand-new ClinicQ account for a staff member via Edge Function.
  /// Admin only. Enforces max [kMaxStaff] active staff per hospital.
  Future<TeamResult<void>> createStaffAccount({
    required String hospitalId,
    required String email,
    required String password,
    required String fullName,
    String role = 'staff',
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-staff-user',
        body: {
          'hospital_id': hospitalId,
          'email':       email.trim().toLowerCase(),
          'password':    password,
          'full_name':   fullName.trim(),
          'role':        role,
        },
      );

      final data = response.data as Map? ?? {};

      if (response.status != 200) {
        final err = data['error'] as String? ?? 'Unknown error';
        if (err.contains('LIMIT_REACHED')) {
          return TeamResult.failure(
              'Staff limit reached. Maximum $kMaxStaff active staff accounts allowed.');
        }
        if (err.contains('EMAIL_EXISTS')) {
          return TeamResult.failure(
              'An account with this email already exists. Use "Invite Existing User" instead.');
        }
        if (err.contains('UNAUTHORIZED')) {
          return TeamResult.failure('Only admins can create staff accounts.');
        }
        return TeamResult.failure(err);
      }

      return TeamResult.success(null);
    } catch (e) {
      final message = e.toString();
      if (message.contains('Failed to fetch')) {
        return TeamResult.failure(
          'Could not reach the staff creation service. Deploy or update the Supabase Edge Function CORS settings, then try again.',
        );
      }
      return TeamResult.failure('Failed to create account: $e');
    }
  }

  /// Invites an existing ClinicQ user by email to the hospital.
  Future<TeamResult<void>> inviteExistingUser({
    required String hospitalId,
    required String email,
    String role = 'staff',
  }) async {
    try {
      await _client.rpc('invite_staff', params: {
        'p_hospital_id': hospitalId,
        'p_email':       email.trim().toLowerCase(),
        'p_role':        role,
      });
      return TeamResult.success(null);
    } on PostgrestException catch (e) {
      if (e.message.contains('UNAUTHORIZED')) {
        return TeamResult.failure('Only admins can invite staff.');
      }
      if (e.message.contains('USER_NOT_FOUND')) {
        return TeamResult.failure(
            'No ClinicQ account found for that email. Use "Create New Account" instead.');
      }
      if (e.message.contains('ALREADY_MEMBER')) {
        return TeamResult.failure('This user is already a member of your hospital.');
      }
      return TeamResult.failure(e.message);
    } catch (_) {
      return TeamResult.failure('Failed to invite user.');
    }
  }

  /// Toggles [isActive] for the hospital_users row [membershipId].
  Future<TeamResult<void>> toggleActive({
    required String membershipId,
    required bool isActive,
  }) async {
    try {
      await _client.rpc('toggle_staff_active', params: {
        'p_hospital_user_id': membershipId,
        'p_is_active':       isActive,
      });
      return TeamResult.success(null);
    } on PostgrestException catch (e) {
      if (e.message.contains('UNAUTHORIZED')) {
        return TeamResult.failure('Only admins can change member status.');
      }
      return TeamResult.failure(e.message);
    } catch (_) {
      return TeamResult.failure('Failed to update member status.');
    }
  }

  /// Updates the role for the hospital_users row [membershipId].
  Future<TeamResult<void>> updateRole({
    required String membershipId,
    required String role,
  }) async {
    try {
      await _client.rpc('update_staff_role', params: {
        'p_hospital_user_id': membershipId,
        'p_role':             role,
      });
      return TeamResult.success(null);
    } on PostgrestException catch (e) {
      if (e.message.contains('UNAUTHORIZED')) {
        return TeamResult.failure('Only admins can change roles.');
      }
      return TeamResult.failure(e.message);
    } catch (_) {
      return TeamResult.failure('Failed to update role.');
    }
  }
}

// ─────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────

class TeamResult<T> {
  final bool isSuccess;
  final T? value;
  final String? errorMessage;

  const TeamResult._({required this.isSuccess, this.value, this.errorMessage});

  factory TeamResult.success(T value) =>
      TeamResult._(isSuccess: true, value: value);

  factory TeamResult.failure(String msg) =>
      TeamResult._(isSuccess: false, errorMessage: msg);
}
