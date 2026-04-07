import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/cq_button.dart';
 
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
 
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}
 
class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
 
  late AnimationController _animCtrl;
  late List<Animation<Offset>> _slideAnims;
  late List<Animation<double>> _fadeAnims;
 
  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
 
    _slideAnims = List.generate(
      5,
      (i) => Tween<Offset>(
              begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(CurvedAnimation(
        parent: _animCtrl,
        curve: Interval(i * 0.08, 0.6 + i * 0.08, curve: Curves.easeOut),
      )),
    );
 
    _fadeAnims = List.generate(
      5,
      (i) => Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _animCtrl,
        curve: Interval(i * 0.08, 0.6 + i * 0.08, curve: Curves.easeOut),
      )),
    );
 
    _animCtrl.forward();
  }
 
  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
 
  // ── Actions ───────────────────────────────────
 
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
 
    final result = await ref.read(authServiceProvider).loginWithEmail(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
 
    if (!mounted) return;
    setState(() => _isLoading = false);
 
    if (result.isSuccess) {
      _onLoginSuccess();
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }
 
  Future<void> _googleLogin() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });
 
    final result = await ref.read(authServiceProvider).signInWithGoogle();
    if (!mounted) return;
 
    setState(() => _isGoogleLoading = false);
 
    if (result.isFailure) {
      setState(() => _errorMessage = result.errorMessage);
    }
    // On success, GoRouter redirect handles navigation
  }
 
  Future<void> _onLoginSuccess() async {
    final hospital = await ref.read(hospitalServiceProvider).getUserHospital();
    if (!mounted) return;
    context.go(
        hospital == null ? AppConstants.routeSetup : AppConstants.routeDashboard);
  }
 
  // ── Build ─────────────────────────────────────
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left panel — branding (desktop only)
          if (MediaQuery.of(context).size.width >= 900) _buildBrandPanel(),
 
          // Right panel — form
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildBrandPanel() {
    return Container(
      width: 480,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A5C5C), Color(0xFF063D3D)],
        ),
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned.fill(
            child: CustomPaint(painter: _GridPatternPainter()),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      size: 32, color: Colors.white),
                ),
                const SizedBox(height: 32),
                Text(
                  'ClinicQ',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Smart queue management\nfor modern clinics.',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 48),
                ..._buildFeatureList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
 
  List<Widget> _buildFeatureList() {
    final features = [
      ('Token-based queuing', Icons.confirmation_number_outlined),
      ('WhatsApp notifications', Icons.chat_bubble_outline_rounded),
      ('Real-time dashboard', Icons.bar_chart_rounded),
      ('Multi-doctor support', Icons.people_outline_rounded),
    ];
 
    return features
        .map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(f.$2,
                      size: 18, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(width: 14),
                Text(
                  f.$1,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
 
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _animated(
            0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back',
                    style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text(
                  'Sign in to your ClinicQ account',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
 
          const SizedBox(height: 36),
 
          // Error banner
          if (_errorMessage != null) ...[
            _animated(1, child: CQErrorBanner(message: _errorMessage!)),
            const SizedBox(height: 16),
          ],
 
          // Email field
          _animated(
            1,
            child: TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@clinic.com',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
          ),
 
          const SizedBox(height: 16),
 
          // Password field
          _animated(
            2,
            child: TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
          ),
 
          const SizedBox(height: 24),
 
          // Login button
          _animated(
            3,
            child: CQButton(
              label: 'Sign in',
              isLoading: _isLoading,
              onPressed: _login,
            ),
          ),
 
          const SizedBox(height: 16),
 
          _animated(3, child: const CQDivider()),
 
          const SizedBox(height: 16),
 
          // Google button
          _animated(
            3,
            child: CQGoogleButton(
              isLoading: _isGoogleLoading,
              onPressed: _googleLogin,
            ),
          ),
 
          const SizedBox(height: 28),
 
          // Register link
          _animated(
            4,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  GestureDetector(
                    onTap: () => context.go(AppConstants.routeRegister),
                    child: Text(
                      'Create one',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _animated(int index, {required Widget child}) {
    return SlideTransition(
      position: _slideAnims[index],
      child: FadeTransition(opacity: _fadeAnims[index], child: child),
    );
  }
}
 
// ─────────────────────────────────────────────
// Background grid pattern painter
// ─────────────────────────────────────────────
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
 
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
 
  @override
  bool shouldRepaint(_) => false;
}
 