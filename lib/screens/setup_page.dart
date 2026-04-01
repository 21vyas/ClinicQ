import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/cq_button.dart';
 
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});
 
  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}
 
class _SetupPageState extends ConsumerState<SetupPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
 
  bool _isLoading = false;
  String? _errorMessage;
 
  late AnimationController _animCtrl;
  late AnimationController _successCtrl;
  late List<Animation<Offset>> _slideAnims;
  late List<Animation<double>> _fadeAnims;
  late Animation<double> _successScale;
  bool _showSuccess = false;
 
  @override
  void initState() {
    super.initState();
 
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _slideAnims = List.generate(
      6,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _animCtrl,
          curve:
              Interval(i * 0.07, 0.55 + i * 0.07, curve: Curves.easeOutCubic),
        ),
      ),
    );
    _fadeAnims = List.generate(
      6,
      (i) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _animCtrl,
          curve:
              Interval(i * 0.07, 0.55 + i * 0.07, curve: Curves.easeOut),
        ),
      ),
    );
 
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
 
    _animCtrl.forward();
  }
 
  @override
  void dispose() {
    _animCtrl.dispose();
    _successCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }
 
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
 
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
 
    final result = await ref.read(hospitalServiceProvider).createHospital(
          name: _nameCtrl.text,
          address: _addressCtrl.text,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text,
        );
 
    if (!mounted) return;
    setState(() => _isLoading = false);
 
    if (result.isSuccess) {
      // Refresh hospital provider
      ref.invalidate(hospitalProvider);
      setState(() => _showSuccess = true);
      await _successCtrl.forward();
 
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppConstants.routeDashboard);
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }
 
  Future<void> _logout() async {
    await ref.read(authServiceProvider).logout();
    if (!mounted) return;
    context.go(AppConstants.routeLogin);
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _showSuccess ? _buildSuccessView() : _buildSetupForm(),
    );
  }
 
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leadingWidth: 200,
      leading: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(
              'ClinicQ',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('Sign out'),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 20)),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }
 
  Widget _buildSetupForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left info panel (desktop)
            if (MediaQuery.of(context).size.width >= 900)
              _buildInfoPanel(),
 
            if (MediaQuery.of(context).size.width >= 900)
              const SizedBox(width: 48),
 
            // Form
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _buildForm(),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildInfoPanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          // Progress indicator
          _ProgressStepper(currentStep: 0),
          const SizedBox(height: 32),
          Text(
            'Tell us about your clinic',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This information will appear on your patient-facing queue screen and WhatsApp notifications.',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          _TipCard(
            icon: Icons.schedule_rounded,
            title: 'Default settings applied',
            body: 'Token limit: 100 • Avg time: 5 min\nYou can change these later in Settings.',
          ),
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
          // Mobile header
          if (MediaQuery.of(context).size.width < 900) ...[
            _a(
              0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProgressStepper(currentStep: 0),
                  const SizedBox(height: 24),
                  Text('Setup your clinic',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'You can update these details later from Settings.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
 
          // Error banner
          if (_errorMessage != null) ...[
            _a(0, child: CQErrorBanner(message: _errorMessage!)),
            const SizedBox(height: 16),
          ],
 
          // Hospital name
          _a(
            1,
            child: _FormSection(
              label: 'Hospital / Clinic Name',
              required: true,
              child: TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'City Heart Hospital',
                  prefixIcon: Icon(Icons.local_hospital_outlined, size: 20),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Hospital name is required';
                  }
                  if (v.trim().length < 3) {
                    return 'Name must be at least 3 characters';
                  }
                  return null;
                },
              ),
            ),
          ),
 
          const SizedBox(height: 20),
 
          // Address
          _a(
            2,
            child: _FormSection(
              label: 'Address',
              required: true,
              child: TextFormField(
                controller: _addressCtrl,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: '12, Sardar Patel Road, Jaipur, Rajasthan 302001',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 22),
                    child: Icon(Icons.location_on_outlined, size: 20),
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Address is required';
                  }
                  return null;
                },
              ),
            ),
          ),
 
          const SizedBox(height: 20),
 
          // Phone (optional)
          _a(
            3,
            child: _FormSection(
              label: 'Contact Number',
              subtitle: 'Optional',
              child: TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
              ),
            ),
          ),
 
          const SizedBox(height: 12),
 
          // Default settings notice
          _a(
            4,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.primaryLight, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Default queue settings will be applied. You can customise token limits, wait times, and alerts in Settings.',
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppColors.primaryLight,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
 
          const SizedBox(height: 28),
 
          _a(
            5,
            child: CQButton(
              label: 'Create clinic & continue',
              isLoading: _isLoading,
              onPressed: _submit,
              icon: Icons.arrow_forward_rounded,
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildSuccessView() {
    return Center(
      child: ScaleTransition(
        scale: _successScale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.success.withOpacity(0.3), width: 2),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 44, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            Text(
              'Clinic created!',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Taking you to your dashboard...',
              style: GoogleFonts.dmSans(
                  fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _a(int i, {required Widget child}) {
    return SlideTransition(
      position: _slideAnims[i],
      child: FadeTransition(opacity: _fadeAnims[i], child: child),
    );
  }
}
 
// ─────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────
 
class _ProgressStepper extends StatelessWidget {
  final int currentStep;
 
  const _ProgressStepper({required this.currentStep});
 
  @override
  Widget build(BuildContext context) {
    final steps = ['Account', 'Clinic Setup', 'Dashboard'];
 
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          return Expanded(
            child: Container(
              height: 2,
              color: i ~/ 2 < currentStep
                  ? AppColors.primary
                  : AppColors.border,
            ),
          );
        }
 
        final stepIdx = i ~/ 2;
        final isDone = stepIdx < currentStep;
        final isCurrent = stepIdx == currentStep;
 
        return Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? AppColors.primary
                    : isCurrent
                        ? AppColors.primarySurface
                        : AppColors.surfaceVariant,
                border: Border.all(
                  color: isCurrent || isDone
                      ? AppColors.primary
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : Text(
                        '${stepIdx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.textHint,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              steps[stepIdx],
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCurrent ? AppColors.primary : AppColors.textHint,
              ),
            ),
          ],
        );
      }),
    );
  }
}
 
class _FormSection extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool required;
  final Widget child;
 
  const _FormSection({
    required this.label,
    required this.child,
    this.subtitle,
    this.required = false,
  });
 
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
              const Text(' *',
                  style: TextStyle(color: AppColors.error, fontSize: 14)),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
 
class _TipCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
 
  const _TipCard(
      {required this.icon, required this.title, required this.body});
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(body,
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 