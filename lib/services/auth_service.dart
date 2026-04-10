import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/app_user.dart';
 
/// Encapsulates all Supabase auth operations for ClinicQ.
class AuthService {
  final SupabaseClient _client;
 
  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
 
  // ───────────────────────────────────────────
  // Current session helpers
  // ───────────────────────────────────────────
 
  /// Returns the currently signed-in Supabase [User], or null.
  User? get currentAuthUser => _client.auth.currentUser;
 
  /// True when a session exists.
  bool get isLoggedIn => currentAuthUser != null;
 
  /// Stream of auth state changes.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
 
  // ───────────────────────────────────────────
  // Auth operations
  // ───────────────────────────────────────────
 
  /// Register a new user with email + password.
  /// Returns [AuthResult] with user or error message.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: fullName != null ? {'full_name': fullName.trim()} : null,
      );
 
      if (response.user == null) {
        return AuthResult.failure('Sign-up failed. Please try again.');
      }
 
      return AuthResult.success(response.user!);
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.message));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred.');
    }
  }
 
  /// Sign in with email + password.
  Future<AuthResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
 
      if (response.user == null) {
        return AuthResult.failure('Login failed. Check your credentials.');
      }
 
      return AuthResult.success(response.user!);
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.message));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred.');
    }
  }
 
  /// Sign in with Google OAuth (opens popup/redirect).
  Future<AuthResult> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      // The result is handled via authStateChanges stream after redirect.
      return AuthResult.pending();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e.message));
    } catch (e) {
      return AuthResult.failure('Google sign-in failed. Please try again.');
    }
  }
 
  /// Sign out the current user.
  Future<void> logout() async {
    await _client.auth.signOut();
  }
 
  /// Returns the full [AppUser] profile from the `users` table.
  Future<AppUser?> getCurrentUser() async {
    final authUser = currentAuthUser;
    if (authUser == null) return null;
 
    try {
      final data = await _client
          .from(AppConstants.tableUsers)
          .select()
          .eq('auth_id', authUser.id)
          .maybeSingle();
 
      if (data == null) return null;
      return AppUser.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// True when the current user has the global `super_admin` role.
  Future<bool> isSuperAdmin() async {
    final authUser = currentAuthUser;
    if (authUser == null) return false;

    try {
      final data = await _client
          .from(AppConstants.tableUsers)
          .select('role')
          .eq('auth_id', authUser.id)
          .maybeSingle();

      return (data?['role'] as String?) == 'super_admin';
    } catch (_) {
      return false;
    }
  }
 
  /// Checks whether the current user already has a hospital configured.
  /// Returns the hospital map or null.
  Future<Map<String, dynamic>?> getUserHospital() async {
    final authUser = currentAuthUser;
    if (authUser == null) return null;
 
    try {
      // Get the user's internal ID first
      final userData = await _client
          .from(AppConstants.tableUsers)
          .select('id')
          .eq('auth_id', authUser.id)
          .maybeSingle();
 
      if (userData == null) return null;
 
      final hospital = await _client
          .from(AppConstants.tableHospitals)
          .select()
          .eq('created_by', userData['id'] as String)
          .maybeSingle();
 
      return hospital;
    } catch (e) {
      return null;
    }
  }
 
  // ───────────────────────────────────────────
  // Private helpers
  // ───────────────────────────────────────────
 
  String get _redirectUrl {
    // In production replace with your actual domain
    return Uri.base.toString().contains('localhost')
        ? 'http://localhost:3000/auth/callback'
        : '${Uri.base.scheme}://${Uri.base.host}/auth/callback';
  }
 
  String _mapAuthError(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email already')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('weak password')) {
      return 'Password is too weak. Use at least 8 characters.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email before logging in.';
    }
    if (msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment.';
    }
    return raw;
  }
}
 
// ─────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────
 
enum AuthResultStatus { success, failure, pending }
 
class AuthResult {
  final AuthResultStatus status;
  final User? user;
  final String? errorMessage;
 
  const AuthResult._({
    required this.status,
    this.user,
    this.errorMessage,
  });
 
  factory AuthResult.success(User user) =>
      AuthResult._(status: AuthResultStatus.success, user: user);
 
  factory AuthResult.failure(String message) =>
      AuthResult._(status: AuthResultStatus.failure, errorMessage: message);
 
  factory AuthResult.pending() =>
      AuthResult._(status: AuthResultStatus.pending);
 
  bool get isSuccess => status == AuthResultStatus.success;
  bool get isFailure => status == AuthResultStatus.failure;
  bool get isPending => status == AuthResultStatus.pending;
}
 