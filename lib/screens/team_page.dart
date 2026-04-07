// lib/screens/team_page.dart
// Team management page — direct Supabase calls, plain StatefulWidget.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../services/team_service.dart';

class TeamPage extends StatefulWidget {
  final String hospitalId;
  const TeamPage({super.key, required this.hospitalId});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _svc = TeamService();

  // ── list state ─────────────────────────────────
  List<HospitalMember> _members  = [];
  bool   _loadingMembers = true;
  String _membersError   = '';

  // ── staff count ────────────────────────────────
  int  _staffCount = 0;
  int  _staffLimit = 5;
  bool _canAdd     = true;

  // ── tab: 0 = create, 1 = invite ───────────────
  int _tab = 0;

  // ── create form ───────────────────────────────
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  String _createRole = 'staff';
  bool   _obscure    = true;
  bool   _creating   = false;

  // ── invite form ───────────────────────────────
  final _inviteEmailCtrl = TextEditingController();
  String _inviteRole = 'staff';
  bool   _inviting   = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback so the first build completes before
    // setState is called from async load — prevents blank page on web.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _inviteEmailCtrl.dispose();
    super.dispose();
  }

  // ── Data load ──────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loadingMembers = true; _membersError = ''; });
    try {
      await _loadMembers();
      await _loadCount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMembers = false;
        _membersError = 'Failed to load team data: $error';
      });
    }
  }

  Future<void> _loadMembers() async {
    final result = await _svc.listMembers(widget.hospitalId);
    if (!mounted) return;
    setState(() {
      _loadingMembers = false;
      if (result.isSuccess) {
        _members = result.value!;
        _membersError = '';
      } else {
        _membersError = result.errorMessage ?? 'Failed to load members.';
      }
    });
  }

  Future<void> _loadCount() async {
    final result = await _svc.getStaffCount(widget.hospitalId);
    if (!mounted || !result.isSuccess) return;
    final c = result.value!;
    setState(() {
      _staffCount = c.staffCount;
      _staffLimit = c.staffLimit;
      _canAdd     = c.canAdd;
    });
  }

  // ── Snack ──────────────────────────────────────

  void _snack(String msg, {required bool error}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: error ? 5 : 2),
      ));
  }

  // ── Create account ─────────────────────────────

  Future<void> _createAccount() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      _snack('Please fill in all fields.', error: true); return;
    }
    if (pass.length < 6) {
      _snack('Password must be at least 6 characters.', error: true); return;
    }
    if (_createRole == 'staff' && !_canAdd) {
      _snack('Staff limit reached ($_staffLimit max). Deactivate a member first.', error: true);
      return;
    }
    setState(() => _creating = true);
    final result = await _svc.createStaffAccount(
      hospitalId: widget.hospitalId,
      email: email, password: pass, fullName: name, role: _createRole,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (result.isSuccess) {
      _nameCtrl.clear(); _emailCtrl.clear(); _passCtrl.clear();
      _snack('Account created for $name.', error: false);
      _load();
    } else {
      _snack(result.errorMessage!, error: true);
    }
  }

  // ── Invite existing ────────────────────────────

  Future<void> _inviteUser() async {
    final email = _inviteEmailCtrl.text.trim();
    if (email.isEmpty) { _snack('Enter an email address.', error: true); return; }
    if (_inviteRole == 'staff' && !_canAdd) {
      _snack('Staff limit reached ($_staffLimit max). Deactivate a member first.', error: true);
      return;
    }
    setState(() => _inviting = true);
    final result = await _svc.inviteExistingUser(
      hospitalId: widget.hospitalId, email: email, role: _inviteRole,
    );
    if (!mounted) return;
    setState(() => _inviting = false);
    if (result.isSuccess) {
      _inviteEmailCtrl.clear();
      _snack('$email added as $_inviteRole.', error: false);
      _load();
    } else {
      _snack(result.errorMessage!, error: true);
    }
  }

  // ── Toggle / Role ──────────────────────────────

  Future<void> _toggle(HospitalMember m) async {
    final result = await _svc.toggleActive(membershipId: m.id, isActive: !m.isActive);
    if (!mounted) return;
    if (result.isSuccess) { _load(); } else { _snack(result.errorMessage!, error: true); }
  }

  Future<void> _changeRole(HospitalMember m, String role) async {
    final result = await _svc.updateRole(membershipId: m.id, role: role);
    if (!mounted) return;
    if (result.isSuccess) { _load(); } else { _snack(result.errorMessage!, error: true); }
  }

  // ── Build ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    try {
      return _buildPage(context);
    } catch (e, st) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            Text('Team page error:\n$e\n\n$st',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        )),
      );
    }
  }

  Widget _buildPage(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.go('/dashboard'),
        ),
        title: Text('Team Management',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _badge(
                '$_staffCount/$_staffLimit staff',
                _staffCount >= _staffLimit ? AppColors.error : AppColors.primary,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Tab row ──────────────────────────
                  Row(children: [
                    Expanded(child: _tabBtn('Create Account', Icons.person_add_rounded, 0)),
                    const SizedBox(width: 8),
                    Expanded(child: _tabBtn('Invite Existing', Icons.mail_outline_rounded, 1)),
                  ]),
                  const SizedBox(height: 14),

                  // ── Form card ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _tab == 0 ? _buildCreateForm() : _buildInviteForm(),
                  ),

                  const SizedBox(height: 24),

                  // ── Members header ───────────────────
                  Row(children: [
                    const Icon(Icons.people_outline_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Current Team (${_members.length})',
                        style: GoogleFonts.dmSans(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    if (_loadingMembers)
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary),
                        onPressed: _load,
                        tooltip: 'Refresh',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ]),
                  const SizedBox(height: 8),

                  // ── Members list ─────────────────────
                  if (_membersError.isNotEmpty)
                    _errorBox(_membersError)
                  else if (_loadingMembers)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (_members.isEmpty)
                    _emptyState()
                  else
                    ..._members.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _memberCard(m),
                    )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────

  Widget _tabBtn(String label, IconData icon, int idx) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? AppColors.primary : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: sel ? Colors.white : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: sel ? Colors.white : AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withAlpha(60)),
    ),
    child: Text(text,
        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
    prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    isDense: true,
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 2)),
  );

  Widget _rolePicker(String value, ValueChanged<String> onChanged) => Container(
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
      color: AppColors.background,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary,
            fontWeight: FontWeight.w500),
        items: const [
          DropdownMenuItem(value: 'staff', child: Text('Staff')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
        ],
        onChanged: (v) => onChanged(v!),
      ),
    ),
  );

  Widget _submitBtn(String label, bool loading, VoidCallback? onTap, Color color) =>
      SizedBox(
        height: 46,
        child: ElevatedButton(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      );

  String _normalizeRole(String? role) {
    final normalized = (role ?? '').trim().toLowerCase();
    if (normalized == 'admin' || normalized == 'staff') return normalized;
    return 'staff';
  }

  // ── Create form ───────────────────────────────

  Widget _buildCreateForm() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final passwordField = TextField(
        controller: _passCtrl,
        obscureText: _obscure,
        decoration: _dec('Password (min 6 chars)', Icons.lock_outline_rounded).copyWith(
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Creates a new ClinicQ login. The user can log in immediately.',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (!_canAdd && _createRole == 'staff') _limitWarning(),
          if (compact) ...[
            TextField(controller: _nameCtrl, decoration: _dec('Full Name', Icons.person_outline_rounded)),
            const SizedBox(height: 8),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _dec('Email', Icons.email_outlined),
            ),
            const SizedBox(height: 8),
            passwordField,
            const SizedBox(height: 8),
            _rolePicker(_createRole, (v) => setState(() => _createRole = v)),
            const SizedBox(height: 8),
            _submitBtn(
              'Create',
              _creating,
              (!_canAdd && _createRole == 'staff') ? null : _createAccount,
              AppColors.primary,
            ),
          ] else ...[
            Row(children: [
              Expanded(child: TextField(controller: _nameCtrl, decoration: _dec('Full Name', Icons.person_outline_rounded))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('Email', Icons.email_outlined),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: passwordField),
              const SizedBox(width: 8),
              SizedBox(width: 130, child: _rolePicker(_createRole, (v) => setState(() => _createRole = v))),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _submitBtn(
                  'Create',
                  _creating,
                  (!_canAdd && _createRole == 'staff') ? null : _createAccount,
                  AppColors.primary,
                ),
              ),
            ]),
          ],
        ],
      );
    },
  );

  // ── Invite form ───────────────────────────────

  Widget _buildInviteForm() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('User must already have a ClinicQ account.',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (!_canAdd && _inviteRole == 'staff') _limitWarning(),
          if (compact) ...[
            TextField(
              controller: _inviteEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _dec('Email address', Icons.email_outlined),
            ),
            const SizedBox(height: 8),
            _rolePicker(_inviteRole, (v) => setState(() => _inviteRole = v)),
            const SizedBox(height: 8),
            _submitBtn(
              'Invite',
              _inviting,
              (!_canAdd && _inviteRole == 'staff') ? null : _inviteUser,
              Colors.indigo,
            ),
          ] else ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _inviteEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('Email address', Icons.email_outlined),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 130, child: _rolePicker(_inviteRole, (v) => setState(() => _inviteRole = v))),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _submitBtn(
                  'Invite',
                  _inviting,
                  (!_canAdd && _inviteRole == 'staff') ? null : _inviteUser,
                  Colors.indigo,
                ),
              ),
            ]),
          ],
        ],
      );
    },
  );

  Widget _limitWarning() => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.error.withAlpha(15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.error.withAlpha(50)),
    ),
    child: Row(children: [
      const Icon(Icons.block_rounded, size: 14, color: AppColors.error),
      const SizedBox(width: 6),
      Expanded(child: Text(
          'Staff limit reached ($_staffLimit max). Deactivate a member to add more.',
          style: const TextStyle(fontSize: 11, color: AppColors.error))),
    ]),
  );

  // ── Member card ───────────────────────────────

  Widget _memberCard(HospitalMember m) {
    final displayName = m.displayName.trim().isEmpty ? 'User' : m.displayName.trim();
    final avatarInitial = displayName.substring(0, 1).toUpperCase();
    final memberRole = _normalizeRole(m.role);
    final roleColor = memberRole == 'admin' ? AppColors.primary : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: m.isActive ? AppColors.surface : AppColors.surface.withAlpha(140),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: m.isActive ? AppColors.border : AppColors.border.withAlpha(80)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: roleColor.withAlpha(m.isActive ? 30 : 15),
          child: Text(avatarInitial,
              style: TextStyle(
                  color: m.isActive ? roleColor : AppColors.textSecondary,
                  fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(child: Text(displayName,
                  style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600,
                      color: m.isActive ? AppColors.textPrimary : AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis)),
              if (!m.isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(15),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('INACTIVE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: AppColors.error)),
                ),
              ],
            ]),
            Text(m.email,
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ],
        )),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: memberRole,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: roleColor, fontWeight: FontWeight.w600),
            items: const [
              DropdownMenuItem(value: 'staff', child: Text('Staff')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
            onChanged: (v) {
              if (v == null || v == memberRole) return;
              _changeRole(m, v);
            },
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: m.isActive ? 'Deactivate' : 'Activate',
          child: Switch(
            value: m.isActive,
            onChanged: (_) => _toggle(m),
            activeThumbColor: AppColors.success,
            activeTrackColor: AppColors.success.withAlpha(60),
            inactiveThumbColor: AppColors.textSecondary,
          ),
        ),
      ]),
    );
  }

  Widget _emptyState() => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.people_outline_rounded, size: 40, color: AppColors.textSecondary),
      SizedBox(height: 10),
      Text('No team members yet.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    ])),
  );

  Widget _errorBox(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.error.withAlpha(15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.error.withAlpha(50)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
      const SizedBox(width: 8),
      Expanded(child: Text(msg,
          style: const TextStyle(color: AppColors.error, fontSize: 12))),
      TextButton(onPressed: _load, child: const Text('Retry')),
    ]),
  );
}
