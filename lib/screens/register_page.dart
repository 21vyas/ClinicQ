import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/cq_button.dart';
 
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
 
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}
 
class _RegisterPageState extends ConsumerState<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _successMessage;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
 
  late AnimationController _animCtrl;
  late List<Animation<double>> _fadeAnims;
 
  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnims = List.generate(
      6,
      (i) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _animCtrl,
          curve: Interval(i * 0.07, 0.55 + i * 0.07, curve: Curves.easeOut),
        ),
      ),
    );
    _animCtrl.forward();
  }
 
  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }
 
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
 
    final result = await ref.read(authServiceProvider).signUpWithEmail(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          fullName: _nameCtrl.text,
        );
 
    if (!mounted) return;
    setState(() => _isLoading = false);
 
    if (result.isSuccess) {
      // If email confirmation required, show success message
      if (result.user?.emailConfirmedAt == null) {
        setState(() {
          _successMessage =
              'Account created! Check your inbox to confirm your email.';
        });
      } else {
        context.go(AppConstants.routeSetup);
      }
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }
 
  Future<void> _googleRegister() async {
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
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 900) _buildAccentStrip(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildAccentStrip() {
    return Container(
      width: 480,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF063D3D), Color(0xFF0A5C5C), Color(0xFF0D7A7A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CirclePainter())),
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
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25), width: 1.5),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      size: 32, color: Colors.white),
                ),
                const SizedBox(height: 32),
                Text(
                  'Join ClinicQ',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Set up your clinic in under\n5 minutes.',
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    height: 1.5,
                    color: Colors.white.withOpacity(0.72),
                  ),
                ),
                const SizedBox(height: 40),
                _stepIndicator(1, 'Create account', done: false),
                _stepIndicator(2, 'Setup hospital', done: false),
                _stepIndicator(3, 'Start queuing', done: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _stepIndicator(int n, String label, {required bool done}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? const Color(0xFF1A7F5A)
                  : Colors.white.withOpacity(0.15),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1.5),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text('$n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
            ),
          ),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.dmSans(
                color: Colors.white.withOpacity(0.82),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
 
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          _fade(
            0,
            child: TextButton.icon(
              onPressed: () => context.go(AppConstants.routeLogin),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to login'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
 
          const SizedBox(height: 12),
 
          _fade(
            0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create your account',
                    style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text('Free to start. No credit card required.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 15)),
              ],
            ),
          ),
 
          const SizedBox(height: 32),
 
          if (_errorMessage != null) ...[
            _fade(1, child: CQErrorBanner(message: _errorMessage!)),
            const SizedBox(height: 16),
          ],
 
          if (_successMessage != null) ...[
            _fade(1, child: _SuccessBanner(message: _successMessage!)),
            const SizedBox(height: 16),
          ],
 
          // Full name
          _fade(
            1,
            child: TextFormField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                hintText: 'Dr. Arjun Sharma',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
          ),
 
          const SizedBox(height: 14),
 
          // Email
          _fade(
            2,
            child: TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'doctor@clinic.com',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
          ),
 
          const SizedBox(height: 14),
 
          // Password
          _fade(
            3,
            child: TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 characters',
                prefixIcon:
                    const Icon(Icons.lock_outline_rounded, size: 20),
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
                if (v.length < 8) return 'Use at least 8 characters';
                return null;
              },
            ),
          ),
 
          const SizedBox(height: 14),
 
          // Confirm password
          _fade(
            3,
            child: TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _register(),
              decoration: InputDecoration(
                labelText: 'Confirm password',
                hintText: 'Re-enter password',
                prefixIcon:
                    const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm password';
                if (v != _passwordCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
          ),
 
          const SizedBox(height: 24),
 
          _fade(
            4,
            child: CQButton(
              label: 'Create account',
              isLoading: _isLoading,
              onPressed: _register,
            ),
          ),
 
          const SizedBox(height: 16),
 
          _fade(4, child: const CQDivider()),
 
          const SizedBox(height: 16),
 
          _fade(
            4,
            child: CQGoogleButton(
              isLoading: _isGoogleLoading,
              onPressed: _googleRegister,
            ),
          ),
 
          const SizedBox(height: 28),
 
          _fade(
            5,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Already have an account? ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  GestureDetector(
                    onTap: () => context.go(AppConstants.routeLogin),
                    child: const Text(
                      'Sign in',
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
 
  Widget _fade(int i, {required Widget child}) {
    return FadeTransition(opacity: _fadeAnims[i], child: child);
  }
}
 
class _SuccessBanner extends StatelessWidget {
  final String message;
 
  const _SuccessBanner({required this.message});
 
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 
class _CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
 
    canvas.drawCircle(
        Offset(size.width * 0.8, size.height * 0.2), 160, paint);
    canvas.drawCircle(
        Offset(size.width * 0.2, size.height * 0.8), 120, paint);
  }
 
  @override
  bool shouldRepaint(_) => false;
}
 