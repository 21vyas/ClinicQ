import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
 
class AuthCallbackPage extends ConsumerStatefulWidget {
  const AuthCallbackPage({super.key});
 
  @override
  ConsumerState<AuthCallbackPage> createState() => _AuthCallbackPageState();
}
 
class _AuthCallbackPageState extends ConsumerState<AuthCallbackPage> {
  String _status = 'Completing sign-in…';
 
  @override
  void initState() {
    super.initState();
    _handleCallback();
  }
 
  Future<void> _handleCallback() async {
    try {
      // Supabase automatically handles the URL fragment on Web
      final session = Supabase.instance.client.auth.currentSession;
 
      if (session == null) {
        // Wait briefly for session to propagate
        await Future.delayed(const Duration(milliseconds: 800));
      }
 
      if (!mounted) return;
 
      final hospital = await ref.read(hospitalServiceProvider).getUserHospital();
 
      if (!mounted) return;
 
      setState(() => _status = 'Redirecting…');
      await Future.delayed(const Duration(milliseconds: 300));
 
      if (!mounted) return;
      context.go(
        hospital == null
            ? AppConstants.routeSetup
            : AppConstants.routeDashboard,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Sign-in failed. Redirecting to login…');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppConstants.routeLogin);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoadingAnimationWidget.threeArchedCircle(
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}