// lib/screens/checkin_page.dart
//
// Public route: /checkin/:hospitalId
// Fully dynamic — fields shown/hidden based on hospital settings.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/custom_field.dart';
import '../models/hospital_full.dart';
import '../providers/queue_provider.dart';
import '../widgets/cq_button.dart';

const _kDefaultReasons = [
  'General Consultation',
  'Follow-up Visit',
  'Prescription Renewal',
  'Lab Results / Reports',
  'Vaccination',
  'Emergency',
  'Other',
];

class CheckInPage extends ConsumerStatefulWidget {
  final String hospitalId;
  const CheckInPage({super.key, required this.hospitalId});

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage>
    with SingleTickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl   = TextEditingController();

  String? _selectedReason;
  bool    _isSubmitting = false;
  String? _errorMessage;

  // Custom field controllers keyed by field id
  final Map<String, TextEditingController> _customCtrls = {};
  final Map<String, String?> _customDropdownValues = {};

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Ensure controllers exist for all custom fields
  void _ensureControllers(List<CustomField> fields) {
    for (final f in fields) {
      if (f.type != CustomFieldType.dropdown) {
        _customCtrls.putIfAbsent(f.id, () => TextEditingController());
      } else {
        _customDropdownValues.putIfAbsent(f.id, () => null);
      }
    }
  }

  // Build custom_data map from controllers
  Map<String, dynamic> _buildCustomData(List<CustomField> fields) {
    final data = <String, dynamic>{};
    for (final f in fields) {
      if (f.type == CustomFieldType.dropdown) {
        final v = _customDropdownValues[f.id];
        if (v != null && v.isNotEmpty) data[f.id] = v;
      } else {
        final v = _customCtrls[f.id]?.text.trim() ?? '';
        if (v.isNotEmpty) data[f.id] = v;
      }
    }
    return data;
  }

  Future<void> _submit(HospitalSettings settings) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSubmitting = true; _errorMessage = null; });

    final ageVal = _ageCtrl.text.trim().isEmpty ? null : int.tryParse(_ageCtrl.text.trim());
    final customData = _buildCustomData(settings.customFields);

    final result = await ref.read(queueServiceProvider).createQueueEntry(
      hospitalId: widget.hospitalId,
      name:       _nameCtrl.text.trim(),
      phone:      _phoneCtrl.text.trim(),
      age:        settings.enableAge ? ageVal : null,
      reason:     settings.enableReason ? _selectedReason : null,
      customData: customData,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isFailure) {
      setState(() => _errorMessage = result.error);
      return;
    }
    context.go('/token/${result.data!.id}');
  }

  @override
  Widget build(BuildContext context) {
    final hospitalAsync = ref.watch(hospitalFullProvider(widget.hospitalId));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F7),
      body: hospitalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (hospital) {
          if (hospital == null) return const _ErrorView(message: 'Clinic not found.');
          _ensureControllers(hospital.settings.customFields);
          return _buildBody(hospital);
        },
      ),
    );
  }

  Widget _buildBody(HospitalFull hospital) {
    final settings = hospital.settings;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF042E2E), Color(0xFF0A5C5C)],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.of(context).padding.top + 28,
                  24,
                  36,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Clinic identity row ─────────────────────
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.local_hospital_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hospital.name,
                            style: GoogleFonts.playfairDisplay(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2)),
                        const SizedBox(height: 6),
                        if (hospital.address != null)
                          _HospitalInfoChip(
                            icon: Icons.location_on_outlined,
                            text: hospital.address!,
                          ),
                        if (hospital.phone != null) ...[
                          const SizedBox(height: 4),
                          _HospitalInfoChip(
                            icon: Icons.phone_outlined,
                            text: hospital.phone!,
                          ),
                        ],
                      ],
                    )),
                  ]),

                  const SizedBox(height: 28),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 28),

                  // ── Call to action ──────────────────────────
                  Text('Register for\nyour token',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.15)),
                  const SizedBox(height: 10),
                  Text('Fill in your details below to receive a\nqueue number.',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.65),
                          height: 1.55)),

                  const SizedBox(height: 20),

                  // ── Working hours badge ─────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        'Open ${hospital.settings.workingHoursStart} – ${hospital.settings.workingHoursEnd}',
                        style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),

            // Form card
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // ── Card header ─────────────────────────────
                      Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.assignment_ind_outlined,
                              size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Your Details',
                              style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          Text('Required to issue your token',
                              style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: AppColors.textHint)),
                        ]),
                      ]),
                      const SizedBox(height: 20),
                      const Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 20),

                      if (_errorMessage != null) ...[
                        CQErrorBanner(message: _errorMessage!),
                        const SizedBox(height: 20),
                      ],

                      // ── Core fields (always shown) ──────────────
                      _FieldLabel('Full Name', required: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _dec(hint: 'Ramesh Kumar', icon: Icons.person_outline_rounded),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your name';
                          if (v.trim().length < 2) return 'Name is too short';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      _FieldLabel('Mobile Number', required: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: _dec(hint: '9876543210', icon: Icons.phone_outlined),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your mobile number';
                          final d = v.replaceAll(RegExp(r'\D'), '');
                          if (d.length != 10) return 'Enter a valid 10-digit mobile number';
                          return null;
                        },
                      ),

                      // ── Age (toggleable) ──────────────────────
                      if (settings.enableAge) ...[
                        const SizedBox(height: 18),
                        _FieldLabel('Age', required: false),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _ageCtrl,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                          decoration: _dec(hint: '35', icon: Icons.cake_outlined),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 1 || n > 120) return 'Enter a valid age (1-120)';
                            return null;
                          },
                        ),
                      ],

                      // ── Reason (toggleable) ────────────────────
                      if (settings.enableReason) ...[
                        const SizedBox(height: 18),
                        _FieldLabel('Reason for Visit', required: false),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedReason,
                          decoration: _dec(hint: 'Select reason', icon: Icons.medical_services_outlined),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                          borderRadius: BorderRadius.circular(12),
                          items: _kDefaultReasons.map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r, style: const TextStyle(fontSize: 14)),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedReason = v),
                        ),
                      ],

                      // ── Custom fields (dynamic) ────────────────
                      ...settings.customFields.map((field) => _buildCustomField(field)),

                      const SizedBox(height: 28),
                      CQButton(
                        label: 'Get My Token',
                        isLoading: _isSubmitting,
                        onPressed: () => _submit(settings),
                        icon: Icons.confirmation_number_outlined,
                      ),
                      const SizedBox(height: 12),
                      Center(child: Text(
                        'Your token number will appear on the next screen.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textHint, height: 1.5),
                      )),

                      const SizedBox(height: 28),
                      const Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 20),

                      // ── Share link section ──────────────────────
                      Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.share_outlined,
                              size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Share this clinic\'s check-in link',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              Text('Let others register without waiting in line',
                                  style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      color: AppColors.textHint)),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _ShareLinkBar(hospitalId: widget.hospitalId),
                    ]),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ── Dynamic custom field renderer ──────────────────────

  Widget _buildCustomField(CustomField field) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      _FieldLabel(field.label, required: field.required),
      const SizedBox(height: 6),
      switch (field.type) {
        CustomFieldType.text     => _buildTextField(field),
        CustomFieldType.number   => _buildNumberField(field),
        CustomFieldType.dropdown => _buildDropdownField(field),
      },
    ]);
  }

  Widget _buildTextField(CustomField field) {
    final ctrl = _customCtrls.putIfAbsent(field.id, () => TextEditingController());
    return TextFormField(
      controller: ctrl,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      decoration: _dec(hint: 'Enter ${field.label.toLowerCase()}', icon: Icons.short_text_rounded),
      validator: field.required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Please enter ${field.label}' : null
          : null,
    );
  }

  Widget _buildNumberField(CustomField field) {
    final ctrl = _customCtrls.putIfAbsent(field.id, () => TextEditingController());
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: _dec(hint: 'Enter ${field.label.toLowerCase()}', icon: Icons.numbers_rounded),
      validator: field.required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Please enter ${field.label}' : null
          : null,
    );
  }

  Widget _buildDropdownField(CustomField field) {
    if (field.options.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: _customDropdownValues[field.id],
      decoration: _dec(hint: 'Select ${field.label.toLowerCase()}', icon: Icons.list_rounded),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
      borderRadius: BorderRadius.circular(12),
      items: field.options.map((o) => DropdownMenuItem(
        value: o, child: Text(o, style: const TextStyle(fontSize: 14)),
      )).toList(),
      onChanged: (v) => setState(() => _customDropdownValues[field.id] = v),
      validator: field.required
          ? (v) => (v == null || v.isEmpty) ? 'Please select ${field.label}' : null
          : null,
    );
  }

  // ── Shared decoration ─────────────────────────────────

  InputDecoration _dec({required String hint, required IconData icon}) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
    hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textHint),
    filled: true,
    fillColor: AppColors.surfaceVariant,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 2)),
  );
}

// ─────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────
// SHARE LINK BAR
// ─────────────────────────────────────────────────────────

class _ShareLinkBar extends StatefulWidget {
  final String hospitalId;
  const _ShareLinkBar({required this.hospitalId});

  @override
  State<_ShareLinkBar> createState() => _ShareLinkBarState();
}

class _ShareLinkBarState extends State<_ShareLinkBar> {
  bool _copied = false;

  String get _url => 'https://clinicq.app/checkin/${widget.hospitalId}';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const Icon(Icons.link_rounded, size: 16, color: AppColors.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _copy,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _copied
                ? const Icon(Icons.check_rounded,
                    key: ValueKey('check'), size: 18, color: AppColors.success)
                : const Icon(Icons.copy_rounded,
                    key: ValueKey('copy'), size: 18, color: AppColors.primary),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────

class _HospitalInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HospitalInfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 13, color: Colors.white60),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
              fontSize: 12,
              color: Colors.white60,
              height: 1.4),
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {required this.required});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(text, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    if (required) const Text(' *', style: TextStyle(color: AppColors.error, fontSize: 14)),
  ]);
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 52),
        const SizedBox(height: 16),
        Text('Clinic not found', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      ]),
    ),
  );
}